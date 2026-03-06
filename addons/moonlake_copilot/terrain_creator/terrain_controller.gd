@tool
extends RefCounted

## Terrain Controller - Handles terrain creation dialog and Terrain3D node setup
##
## Responsibilities:
## - Connect to Terrain3D toolbar signal
## - Handle Create Terrain button press
## - Create and configure Terrain3D nodes
## - Show terrain creation dialog

# Signals
signal terrain_created(terrain_node: Node)

# External references (set externally)
var python_bridge: Node = null
var plugin_ref = null  # Reference to plugin for get_tree() and add_child()

# State
var active_terrain_dialog: Window = null
var _is_creating_terrain_dialog: bool = false
var _terrain_toolbar_connection_attempts: int = 0
var _terrain_toolbar_callback: Callable

# Constants
const MAX_TOOLBAR_CONNECTION_ATTEMPTS = 10


func initialize(py_bridge, plugin) -> void:
	"""Initialize with external references"""
	python_bridge = py_bridge
	plugin_ref = plugin


func connect_to_terrain_toolbar() -> void:
	"""Find and connect to Terrain3D toolbar's generate_terrain_requested signal"""
	_terrain_toolbar_connection_attempts += 1

	# Stop retrying after max attempts
	if _terrain_toolbar_connection_attempts > MAX_TOOLBAR_CONNECTION_ATTEMPTS:
		# Terrain3D toolbar not available - this is OK, user might not have plugin
		return

	# Search for TerrainDock in the editor
	var base_control = EditorInterface.get_base_control()
	var terrain_dock = _find_node_by_name(base_control, "TerrainDock")

	if not terrain_dock:
		# Toolbar not loaded yet, retry
		if plugin_ref:
			await plugin_ref.get_tree().create_timer(1.0).timeout
			plugin_ref.call_deferred("_terrain_controller_retry_connection")
		return

	# Find the toolbar inside the terrain dock
	for child in terrain_dock.get_children():
		if child.has_signal("generate_terrain_requested"):
			# Create callable once and store as member variable
			if not _terrain_toolbar_callback.is_valid():
				_terrain_toolbar_callback = func(): on_create_terrain_pressed(true)

			# Connect with force_show_dialog=true so dialog always shows from toolbar button
			if not child.is_connected("generate_terrain_requested", _terrain_toolbar_callback):
				child.connect("generate_terrain_requested", _terrain_toolbar_callback)
				# Reset retry counter since we successfully connected
				_terrain_toolbar_connection_attempts = 0
			return


func on_create_terrain_pressed(force_show_dialog: bool = false) -> void:
	"""Handle Create Terrain button press from SceneTreeDock or toolbar.

	Args:
		force_show_dialog: If true, always show dialog even if terrain exists (for toolbar button)
	"""
	# Prevent race condition from rapid clicks
	if _is_creating_terrain_dialog:
		return

	# Check if dialog already open
	if active_terrain_dialog and is_instance_valid(active_terrain_dialog):
		active_terrain_dialog.grab_focus()
		return

	# Set semaphore
	_is_creating_terrain_dialog = true

	var current_scene = EditorInterface.get_edited_scene_root()

	# Create new scene if none is open
	if not current_scene:
		# Create a new Node3D root (same as clicking "Other Node" and choosing Node3D)
		var new_scene_root = Node3D.new()
		new_scene_root.name = "Node3D"

		# Use SceneTreeDock to add root node (creates undo/redo action and sets edited scene)
		var scene_tree_dock = _get_scene_tree_dock()
		if scene_tree_dock and scene_tree_dock.has_method("add_root_node"):
			scene_tree_dock.add_root_node(new_scene_root)
		else:
			# Fallback: access EditorNode directly via get_tree().root
			var editor_node = plugin_ref.get_tree().root.get_child(0)  # EditorNode is first child of root
			if editor_node and editor_node.has_method("set_edited_scene"):
				editor_node.set_edited_scene(new_scene_root)
			else:
				Log.error("[MOONLAKE] Could not set edited scene")
				new_scene_root.free()
				_is_creating_terrain_dialog = false
				return

		# Wait a frame for the editor to process the new scene
		await plugin_ref.get_tree().process_frame

		current_scene = EditorInterface.get_edited_scene_root()
		if not current_scene:
			Log.error("[MOONLAKE] Failed to create new scene")
			_is_creating_terrain_dialog = false  # Reset semaphore
			return

	# Check if scene already has Terrain3D node
	var existing_terrain = current_scene.find_children("*", "Terrain3D", true, false)
	var terrain_node = null

	if existing_terrain.size() > 0:
		# Use existing terrain node
		terrain_node = existing_terrain[0]

		# Don't show dialog if terrain already exists (unless forced from toolbar)
		if not force_show_dialog:
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(terrain_node)
			_is_creating_terrain_dialog = false
			return
	else:
		# Create the Terrain3D node first
		terrain_node = create_terrain_node(current_scene)
		if not terrain_node:
			_is_creating_terrain_dialog = false  # Reset semaphore
			return

		# IMPORTANT: Ensure terrain_node is valid before continuing
		if not is_instance_valid(terrain_node):
			Log.error("[MOONLAKE] Created terrain node is invalid")
			_is_creating_terrain_dialog = false  # Reset semaphore
			return

	# Switch to terrain tab (only if not already there)
	var editor_node = plugin_ref.get_tree().root.get_child(0)
	if editor_node:
		var main_screen = editor_node.get("editor_main_screen")
		if main_screen and main_screen.has_method("select") and main_screen.has_method("get_selected_index"):
			var current_tab = main_screen.get_selected_index()
			# EDITOR_TERRAIN = 6 (from EditorMainScreen enum)
			if current_tab != 6:
				main_screen.select(6)

	# Now show the dialog to configure the terrain
	# Check if dialog already open
	if active_terrain_dialog and is_instance_valid(active_terrain_dialog):
		active_terrain_dialog.grab_focus()
		_is_creating_terrain_dialog = false
		return

	# Load terrain scene directly
	var terrain_scene = load("res://addons/moonlake_copilot/terrain_creator/terrain_root.tscn")
	if terrain_scene:
		var terrain_root = terrain_scene.instantiate()

		# Pass plugin and python_bridge references to terrain_root
		terrain_root.plugin_ref = plugin_ref
		if python_bridge:
			terrain_root.python_bridge = python_bridge

		# Create a simple Window wrapper
		var terrain_window = Window.new()
		terrain_window.title = "Moonlake: Create Terrain"
		terrain_window.size = Vector2i(900, 1250)
		terrain_window.unresizable = true
		terrain_window.transient = true
		terrain_window.exclusive = true

		# Ensure window can receive input events properly
		terrain_window.gui_embed_subwindows = false

		# Add terrain_root to window and ensure it's visible/processing
		terrain_window.add_child(terrain_root)
		terrain_root.set_process_input(true)
		terrain_root.set_process(true)

		# Validate terrain node before using in closure
		if not terrain_node or not is_instance_valid(terrain_node):
			Log.error("[MOONLAKE] Terrain node is invalid")
			_is_creating_terrain_dialog = false  # Reset semaphore
			terrain_window.queue_free()
			return

		# Connect the GenerateButton to configure terrain and generate from sketch
		var terrain_ref = terrain_node  # Capture in closure
		var generate_button = terrain_root.get_node_or_null("PromptSection/GenerateButton")
		var tools_panel = terrain_root.get_node_or_null("BottomToolbar")

		if generate_button and tools_panel:
			# Connect with our custom handler that configures terrain first
			generate_button.pressed.connect(func():
				# Step 1: Get terrain size settings
				var size_option = terrain_root.get_node_or_null("PromptSection/SizeContainer/SizeOption")
				if size_option:
					var terrain_size_index = size_option.selected
					var terrain_size = 0

					match terrain_size_index:
						0: terrain_size = 512
						1: terrain_size = 1024
						2: terrain_size = 2048

					# Step 2: Configure terrain with size settings
					configure_terrain_node(terrain_ref, terrain_size)

				# Step 3: Call tools_panel's generate method to handle AI generation
				# This will validate canvas, export image, upload to S3, send to AI, and close dialog
				if tools_panel.has_method("_on_generate_pressed"):
					tools_panel._on_generate_pressed("generate terrain from this image: ")
			)

		# Add window to editor
		EditorInterface.get_base_control().add_child(terrain_window)
		terrain_window.popup_centered()

		# Track instance and cleanup on close
		active_terrain_dialog = terrain_window
		_is_creating_terrain_dialog = false  # Reset semaphore after successful creation
		terrain_window.close_requested.connect(func():
			terrain_window.queue_free()
			active_terrain_dialog = null
		)
		terrain_window.tree_exited.connect(func(): active_terrain_dialog = null)
	else:
		Log.error("[MOONLAKE] Failed to load terrain scene")
		_is_creating_terrain_dialog = false  # Reset semaphore on failure


func create_terrain_node(parent_scene: Node) -> Node:
	"""Create a Terrain3D node and return it."""
	if not parent_scene:
		Log.error("[MOONLAKE] No parent scene to add terrain to")
		return null

	# Create new Terrain3D node
	var terrain_node = ClassDB.instantiate("Terrain3D")
	if not terrain_node:
		Log.error("[MOONLAKE] Failed to instantiate Terrain3D node. Make sure the Terrain3D plugin is enabled.")

		# Show user-friendly error dialog (delegate to plugin)
		if plugin_ref and plugin_ref.has_method("_show_alert"):
			plugin_ref._show_alert("Terrain3D Not Found",
				"Please install and enable the Terrain3D plugin before creating terrain.\n\n" +
				"You can download it from: https://github.com/TokisanGames/Terrain3D")

		return null

	terrain_node.name = "Terrain3D"

	# Add to scene root
	parent_scene.add_child(terrain_node)
	terrain_node.owner = parent_scene

	# Mark scene as modified
	EditorInterface.mark_scene_as_unsaved()

	# Select the newly created terrain node
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(terrain_node)

	# Emit signal
	terrain_created.emit(terrain_node)

	return terrain_node


func configure_terrain_node(terrain_node: Node, terrain_size: int) -> void:
	"""Configure the terrain node with specified settings."""
	if not terrain_node or not is_instance_valid(terrain_node):
		Log.error("[MOONLAKE] Invalid terrain node")
		return

	# Terrain3D uses the actual size value as the enum (not sequential integers)
	var region_size_enum = 1024  # Default to SIZE_1024
	match terrain_size:
		512: region_size_enum = 512   # Terrain3D.RegionSizeEnum.Size512
		1024: region_size_enum = 1024 # Terrain3D.RegionSizeEnum.Size1024
		2048: region_size_enum = 2048 # Terrain3D.RegionSizeEnum.Size2048

	# Configure terrain properties
	if terrain_node.has_method("change_region_size"):
		terrain_node.change_region_size(region_size_enum)

	# Add initial region at origin so there's terrain to work with
	if terrain_node.has_method("get_data"):
		var terrain_data = terrain_node.get_data()
		if not terrain_data:
			Log.error("[MOONLAKE] Failed to get terrain data from Terrain3D node")
			return

		if not terrain_data.has_method("add_region_blankp"):
			Log.error("[MOONLAKE] Terrain data does not have add_region_blankp() method")
			return

		# Add blank region at (0, 0, 0) with default heightmap
		var region = terrain_data.add_region_blankp(Vector3.ZERO)
		if not region:
			Log.warn("[MOONLAKE] Failed to add terrain region at origin")

	Log.info("[MOONLAKE] Terrain configured: size=%s (enum=%s)" % [terrain_size, region_size_enum])


## ============================================================================
## Helper Functions
## ============================================================================

func _find_node_by_name(node: Node, node_name: String) -> Node:
	"""Recursively find a node by name"""
	if node.name == node_name:
		return node

	for child in node.get_children():
		var result = _find_node_by_name(child, node_name)
		if result:
			return result

	return null


func _get_scene_tree_dock():
	"""Get the SceneTreeDock instance from the editor."""
	var base_control = EditorInterface.get_base_control()

	# SceneTreeDock is typically in the editor's dock system
	# Try to find it by checking children
	for child in base_control.get_parent().get_children():
		if child.get_class() == "SceneTreeDock" or child.name == "SceneTreeDock":
			return child

	# Try searching deeper
	var queue = [base_control.get_parent()]
	while queue.size() > 0:
		var node_item = queue.pop_front()
		if node_item.get_class() == "SceneTreeDock" or node_item.name == "SceneTreeDock":
			return node_item
		for child in node_item.get_children():
			queue.push_back(child)

	return null


func cleanup() -> void:
	"""Cleanup on plugin exit"""
	if active_terrain_dialog and is_instance_valid(active_terrain_dialog):
		active_terrain_dialog.queue_free()
		active_terrain_dialog = null
