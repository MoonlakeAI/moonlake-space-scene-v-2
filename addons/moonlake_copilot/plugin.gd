@tool
extends EditorPlugin

var chat_panel: Control
var python_bridge: Node
var active_paint_window: Window = null
var tool_executor: ToolExecutor
var dependency_resolver = null
var terrain_controller = null
var viewport_context_controller = null
var placeholder_manager = null  # Keeps error cylinders alive during plugin lifecycle
var copilot_config = null
var publish_dialog = null
var _was_playing: bool = false  # Track game running state for error counter

const MAX_TOOLBAR_CONNECTION_ATTEMPTS = 10

const TSCNOperations = preload("res://addons/moonlake_copilot/operations/tscn_operations.gd")
const DownloadWorkerPool = preload("res://addons/moonlake_copilot/resource_import/download_worker_pool.gd")
const UISimplifier = preload("res://addons/moonlake_copilot/ui/ui_simplifier.gd")


## ============================================================================
## Settings Registration
## ============================================================================

func _register_setting(path: String, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "", skip_initial_value: bool = false) -> void:
	if not ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, default_value)
	if not skip_initial_value:
		ProjectSettings.set_initial_value(path, default_value)
	ProjectSettings.add_property_info({
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string
	})
	ProjectSettings.set_as_basic(path, true)


func _register_settings() -> void:
	# Migrate legacy settings to new paths before clearing
	var did_migrate = false
	var migrations = {
		"moonlake/project_type": "moonlake/general/project_type",
		"moonlake/dont_ask_import_scenes": "moonlake/ui/skip_import_dialog_scenes",
	}
	for old_path in migrations:
		if ProjectSettings.has_setting(old_path):
			var value = ProjectSettings.get_setting(old_path)
			var new_path = migrations[old_path]
			if not ProjectSettings.has_setting(new_path):
				ProjectSettings.set_setting(new_path, value)
			ProjectSettings.clear(old_path)
			did_migrate = true

	# Clean up legacy settings
	for legacy_path in [
		"moonlake/project_id",
		"moonlake/general/project_id",
		"moonlake/copilot_settings",
		"moonlake/ui/input_height",
		"moonlake/behavior/show_waiting_messages",
		"moonlake/behavior/escape_to_stop",
		"moonlake/behavior/auto_scroll",
		"moonlake_copilot/enable_tool_streaming",
	]:
		if ProjectSettings.has_setting(legacy_path):
			ProjectSettings.clear(legacy_path)
			did_migrate = true

	if did_migrate:
		ProjectSettings.save()

	# General settings (shown in Project Settings)
	_register_setting("moonlake/general/project_type", "3d", TYPE_STRING, PROPERTY_HINT_ENUM, "2d,3d", true)

	# UI settings (shown in Project Settings)
	_register_setting("moonlake/ui/chat_input_height", 300.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "100,500,1")
	_register_setting("moonlake/ui/simplified_ui", false, TYPE_BOOL)
	_register_setting("moonlake/ui/skip_import_dialog_scenes", PackedStringArray(), TYPE_PACKED_STRING_ARRAY)

	# Behavior settings (shown in Project Settings)
	_register_setting("moonlake/agent_behavior/show_wait_messages_when_slow", true, TYPE_BOOL)
	_register_setting("moonlake/agent_behavior/escape_key_stops_agent", false, TYPE_BOOL)
	_register_setting("moonlake/agent_behavior/show_internal_logs", false, TYPE_BOOL)


func _enter_tree() -> void:
	# Skip plugin entirely in headless mode - it's an editor UI plugin with no headless functionality
	if DisplayServer.get_name() == "headless":
		return

	Log._static_init()

	# Register all Moonlake settings
	_register_settings()

	# Create config as a child node (not autoload) to avoid undo history pollution
	var CopilotConfigScript = load("res://addons/moonlake_copilot/core/copilot_config.gd")
	copilot_config = CopilotConfigScript.new()
	copilot_config.name = "CopilotConfig"
	add_child(copilot_config)

	var PythonBridgeScript = load("res://addons/moonlake_copilot/core/python_bridge.gd")
	python_bridge = PythonBridgeScript.new()
	python_bridge.name = "PythonBridge"  # Set name for easy lookup
	add_child(python_bridge)
	python_bridge.start()

	var ChatPanelScript = load("res://addons/moonlake_copilot/chat_panel_v2.gd")
	chat_panel = ChatPanelScript.new()
	chat_panel.python_bridge = python_bridge  # Pass python_bridge directly
	chat_panel.config = copilot_config

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, chat_panel)
	chat_panel.visible = true  # Force visible after restart

	var PublishDialogScript = load("res://addons/moonlake_copilot/dialogs/publish_dialog.gd")
	if PublishDialogScript:
		publish_dialog = PublishDialogScript.new()
		publish_dialog.name = "PublishDialog"
		publish_dialog.python_bridge = python_bridge
		EditorInterface.get_base_control().add_child(publish_dialog)

	tool_executor = ToolExecutor.new()
	tool_executor.python_bridge = python_bridge  # Inject python_bridge
	add_child(tool_executor)

	var PlaceholderManager = load("res://addons/moonlake_copilot/resource_import/placeholder_manager.gd")
	placeholder_manager = PlaceholderManager.new()

	var DependencyResolver = load("res://addons/moonlake_copilot/editor/dependency_resolver.gd")
	dependency_resolver = DependencyResolver.new()
	dependency_resolver.initialize(placeholder_manager, self)

	var TerrainController = load("res://addons/moonlake_copilot/terrain_creator/terrain_controller.gd")
	terrain_controller = TerrainController.new()
	terrain_controller.initialize(python_bridge, self)

	var ViewportContextController = load("res://addons/moonlake_copilot/viewport/viewport_context_controller.gd")
	viewport_context_controller = ViewportContextController.new()
	viewport_context_controller.initialize(chat_panel, self)

	python_bridge.response_received.connect(_on_python_message)

	var fs = EditorInterface.get_resource_filesystem()
	if fs:
		fs.resources_reimported.connect(_on_resources_reimported)

	if terrain_controller:
		call_deferred("_terrain_controller_retry_connection")

	var setting_name = "editor/suppress_dependency_error_dialog"
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, true)
		ProjectSettings.set_initial_value(setting_name, true)
		# Add property info so it shows in Project Settings UI
		ProjectSettings.add_property_info({
			"name": setting_name,
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": ""
		})
		ProjectSettings.set_as_basic(setting_name, true)  # Show in basic view
		ProjectSettings.save()

	var editor_node = get_tree().root.get_child(0)
	if dependency_resolver:
		dependency_resolver.connect_to_editor_node(editor_node)

	_setup_moonlake_menu()

	EditorInterface.distraction_free_mode_changed.connect(_on_distraction_free_mode_changed)
	call_deferred("_apply_ui_mode")

	await get_tree().process_frame
	_connect_scene_dock_signals()

	# Delay debugger connection to ensure it's fully initialized
	get_tree().create_timer(1.0).timeout.connect(_connect_debugger_signals)

	set_input_event_forwarding_always_enabled()


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var is_playing = EditorInterface.is_playing_scene()
	if is_playing and not _was_playing:
		_on_game_started()
	elif not is_playing and _was_playing:
		_on_game_stopped()
	_was_playing = is_playing


func _on_game_started() -> void:
	if not chat_panel:
		return
	if chat_panel.prompt_suggestions_controller:
		chat_panel.prompt_suggestions_controller.on_play_mode_changed(true)
	if not chat_panel.error_counter_button:
		return
	var debuggers = _find_all_script_debuggers(EditorInterface.get_debugger())
	chat_panel.error_counter_button.set_debuggers(debuggers)
	chat_panel.error_counter_button.start_tracking()
	if not chat_panel.error_counter_button.fix_all_pressed.is_connected(_on_error_counter_fix_all):
		chat_panel.error_counter_button.fix_all_pressed.connect(_on_error_counter_fix_all)


func _on_error_counter_fix_all() -> void:
	var debugger_node = EditorInterface.get_debugger()
	if not debugger_node:
		return
	for debugger in _find_all_script_debuggers(debugger_node):
		debugger.fix_all_errors()
		return


func _on_game_stopped() -> void:
	if chat_panel:
		if chat_panel.prompt_suggestions_controller:
			chat_panel.prompt_suggestions_controller.on_play_mode_changed(false)
		if chat_panel.error_counter_button:
			chat_panel.error_counter_button.stop_tracking()


func _on_python_message(id: int, ok: bool, result, error_msg: String) -> void:
	"""
	Single message pump - routes all Python messages.

	Messages are routed to:
	- chat_panel_v2.handle_render_command() for render commands
	- chat_panel_v2.handle_python_response() for auth/connection responses
	- tool_executor.handle_request() for tool requests (Phase 8)
	"""
	if ok and typeof(result) == TYPE_DICTIONARY:
		var msg_type: String = result.get("type", "")

		if msg_type == "render_command":
			var command: String = result.get("command", "")
			if command == "publish_progress":
				# Route to both publish_dialog (legacy) and chat_panel (new controller)
				if publish_dialog:
					publish_dialog.on_publish_progress(result.get("data", {}).get("message", ""))
				if chat_panel:
					chat_panel.handle_render_command(result)
			elif chat_panel:
				chat_panel.handle_render_command(result)

		elif msg_type == "tool_request":
			if tool_executor and tool_executor.has_method("handle_request"):
				tool_executor.handle_request(result)
			else:
				Log.warn("[Plugin] tool_executor not ready or missing handle_request()")

		elif msg_type == "internal_api_call":
			var api_call = result.get("api_call", "")
			var params = result.get("params", {})

			if api_call == "open_main_scene_or_fallback":
				var scene_path = params.get("scene_path", "")
				var open_task = func():
					var open_result = await SceneOperations.open_main_scene_or_fallback(scene_path)
					Log.info("[OpenScene] %s" % open_result)
				open_task.call()

		elif msg_type == "mark_for_auto_import":
			var scene_paths = result.get("scene_paths", [])
			if dependency_resolver:
				for scene_path in scene_paths:
					dependency_resolver.mark_for_auto_import(scene_path)

		else:
			if chat_panel and chat_panel.has_method("handle_python_response"):
				chat_panel.handle_python_response(id, ok, result, error_msg)
			else:
				Log.error("[Plugin] Unhandled message type: %s" % msg_type)
	else:
		if chat_panel and chat_panel.has_method("handle_python_response"):
			chat_panel.handle_python_response(id, ok, result, error_msg)
		elif not ok:
			Log.error("[Plugin] Python error: %s" % error_msg)


func _exit_tree() -> void:
	# Skip cleanup in headless mode - nothing was initialized
	if DisplayServer.get_name() == "headless":
		return

	Log.info("[MOONLAKE] Shutting down...")

	# Clean up error cylinders FIRST to avoid shutdown crash
	# Must happen before scene tree finalization
	if placeholder_manager:
		var count = _cleanup_error_cylinders()
		placeholder_manager = null

	if dependency_resolver:
		dependency_resolver.disconnect_from_editor_node()
		dependency_resolver = null

	if terrain_controller:
		terrain_controller.cleanup()
		terrain_controller = null

	if viewport_context_controller:
		viewport_context_controller.cleanup()
		viewport_context_controller = null

	if python_bridge:
		if python_bridge.response_received.is_connected(_on_python_message):
			python_bridge.response_received.disconnect(_on_python_message)

	if _app_menu_rid.is_valid():
		if _separator_after_idx >= 0:
			NativeMenu.remove_item(_app_menu_rid, _separator_after_idx)
		if _import_scene_idx >= 0:
			NativeMenu.remove_item(_app_menu_rid, _import_scene_idx)
		if _simplified_ui_idx >= 0:
			NativeMenu.remove_item(_app_menu_rid, _simplified_ui_idx)
		if _separator_before_idx >= 0:
			NativeMenu.remove_item(_app_menu_rid, _separator_before_idx)
		_app_menu_rid = RID()
		_separator_before_idx = -1
		_simplified_ui_idx = -1
		_import_scene_idx = -1
		_separator_after_idx = -1

	if _moonlake_popup_menu:
		if _moonlake_popup_menu.get_parent():
			_moonlake_popup_menu.get_parent().remove_child(_moonlake_popup_menu)
		_moonlake_popup_menu.queue_free()
		_moonlake_popup_menu = null

	if chat_panel:
		remove_control_from_docks(chat_panel)
		chat_panel.queue_free()
		chat_panel = null

	if publish_dialog:
		publish_dialog.queue_free()
		publish_dialog = null

	# Close any open paint windows
	if active_paint_window and is_instance_valid(active_paint_window):
		active_paint_window.queue_free()
		active_paint_window = null

	if tool_executor:
		tool_executor.queue_free()
		tool_executor = null

	if python_bridge:
		var bridge = python_bridge
		python_bridge = null

		if bridge.pid != -1:
			bridge.call_python("cancel_all_operations", {})

		bridge.stop()
		bridge.queue_free()

func _cleanup_error_cylinders() -> int:
	"""Free all error cylinder nodes before shutdown to prevent crash."""
	if not placeholder_manager:
		return 0

	var count = placeholder_manager.placeholder_nodes.size()
	if count == 0:
		return 0

	# Free all tracked placeholder nodes (including error cylinders)
	# Use free() instead of queue_free() during shutdown to avoid queueing
	for key in placeholder_manager.placeholder_nodes.keys():
		var node = placeholder_manager.placeholder_nodes[key]
		if is_instance_valid(node):
			var parent = node.get_parent()
			if parent:
				parent.remove_child(node)
			# Use free() for immediate deletion during shutdown
			node.free()

	placeholder_manager.placeholder_nodes.clear()
	return count

func _terrain_controller_retry_connection() -> void:
	"""Helper to delegate terrain toolbar connection to controller"""
	if terrain_controller:
		terrain_controller.connect_to_terrain_toolbar()


func _apply_ui_mode() -> void:
	# Restore simplified_ui on startup if it was previously enabled
	var simplified = ProjectSettings.get_setting("moonlake/ui/simplified_ui", false)
	if simplified:
		EditorInterface.set_distraction_free_mode(true)
	elif EditorInterface.is_distraction_free_mode_enabled():
		UISimplifier.apply()


func _on_distraction_free_mode_changed(enabled: bool) -> void:
	# Save simplified_ui preference
	ProjectSettings.set_setting("moonlake/ui/simplified_ui", enabled)
	ProjectSettings.save()

	if enabled:
		UISimplifier.apply()
	else:
		UISimplifier.restore()

## ============================================================================
## Moonlake App Menu (macOS application menu)
## ============================================================================

var _app_menu_rid: RID
var _separator_before_idx: int = -1
var _simplified_ui_idx: int = -1
var _import_scene_idx: int = -1
var _separator_after_idx: int = -1
var _moonlake_popup_menu: PopupMenu

func _setup_moonlake_menu() -> void:
	# macOS: add to native application menu
	if NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		_app_menu_rid = NativeMenu.get_system_menu(NativeMenu.APPLICATION_MENU_ID)
		if _app_menu_rid.is_valid():
			NativeMenu.set_popup_open_callback(_app_menu_rid, _on_app_menu_opened)
			_separator_before_idx = NativeMenu.add_separator(_app_menu_rid)
			_simplified_ui_idx = NativeMenu.add_check_item(
				_app_menu_rid,
				"Simplified UI",
				_on_simplified_ui_toggled
			)

			_import_scene_idx = NativeMenu.add_item(
				_app_menu_rid,
				"Import Scene Resources",
				_on_import_scene_pressed
			)
			_separator_after_idx = NativeMenu.add_separator(_app_menu_rid)
			return

	# Windows/Linux: add Moonlake menu to main menu bar
	_moonlake_popup_menu = PopupMenu.new()
	_moonlake_popup_menu.name = "Moonlake"
	_moonlake_popup_menu.add_check_item("Simplified UI", 0)
	_moonlake_popup_menu.add_separator()
	_moonlake_popup_menu.add_item("Import Scene Resources", 1)
	_moonlake_popup_menu.about_to_popup.connect(_on_popup_menu_about_to_show)
	_moonlake_popup_menu.id_pressed.connect(_on_popup_menu_item)

	var menu_bar = _find_menu_bar(EditorInterface.get_base_control())
	if menu_bar:
		menu_bar.add_child(_moonlake_popup_menu)


func _find_menu_bar(node: Node) -> MenuBar:
	if node is MenuBar:
		return node
	for child in node.get_children():
		var result = _find_menu_bar(child)
		if result:
			return result
	return null

func _on_app_menu_opened() -> void:
	if _app_menu_rid.is_valid() and _simplified_ui_idx >= 0:
		NativeMenu.set_item_checked(_app_menu_rid, _simplified_ui_idx, EditorInterface.is_distraction_free_mode_enabled())


func _on_popup_menu_about_to_show() -> void:
	if _moonlake_popup_menu:
		_moonlake_popup_menu.set_item_checked(0, EditorInterface.is_distraction_free_mode_enabled())


func _on_simplified_ui_toggled(_tag: Variant) -> void:
	var enabled = not EditorInterface.is_distraction_free_mode_enabled()
	EditorInterface.set_distraction_free_mode(enabled)


func _on_import_scene_pressed(_tag: Variant) -> void:
	_trigger_manual_import_for_current_scene()


func _on_popup_menu_item(id: int) -> void:
	match id:
		0:
			var enabled = not EditorInterface.is_distraction_free_mode_enabled()
			EditorInterface.set_distraction_free_mode(enabled)
		1:
			_trigger_manual_import_for_current_scene()

func _show_alert(title: String, message: String) -> void:
	"""Show a simple alert dialog using Godot's AcceptDialog."""
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)

func _trigger_manual_import_for_current_scene() -> void:
	"""Manually trigger import for current scene."""
	var edited_root = EditorInterface.get_edited_scene_root()
	if not edited_root:
		_show_alert("Moonlake Import", "No scene currently open. Please open a .tscn scene first.")
		return

	var tscn_path = edited_root.scene_file_path
	if not tscn_path or tscn_path == "":
		_show_alert("Moonlake Import", "Current scene has no file path. Please save the scene first.")
		return

	Log.info("[MOONLAKE] Manual import triggered for: %s" % tscn_path)

	# Create dialog for manual import
	var ImportProgressDialog = load("res://addons/moonlake_copilot/resource_import/import_progress_dialog.gd")
	var dialog = ImportProgressDialog.new()
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2(500, 200))

	var result = await TSCNOperations.resolve_resources_v2(tscn_path, dialog, 0, 999, DownloadConfig.DOWNLOAD_TIMEOUT_PER_ATTEMPT, DownloadConfig.DOWNLOAD_MAX_TOTAL_TIMEOUT, DownloadConfig.WORKER_POOL_SIZE, 10, [], self)
	Log.info("[MOONLAKE] Import result: %s" % result)

	# Show completion message
	dialog.status_label.text = "Import Complete!"
	dialog.current_label.text = ""

	# Wait a moment before cleanup
	await get_tree().create_timer(1.5).timeout

	# Cleanup dialog
	dialog.hide()
	if dialog.get_parent():
		dialog.get_parent().remove_child(dialog)
	dialog.queue_free()

	# Show user-friendly notification
	if "No external resources" in result or "already local" in result:
		_show_alert("Moonlake Import", "Scene already imported - all resources are local")
	elif "Import already in progress" in result:
		_show_alert("Moonlake Import", "An import is already running. Please wait for it to complete.")
	elif result.begins_with("Error:"):
		Log.error("[MOONLAKE] Import failed: " + result)
		_show_alert("Moonlake Import Error", "Import failed: " + result)
	else:
		_show_alert("Moonlake Import", "Import complete: " + result)


func _clear_error_markers() -> void:
	"""Manually clear all error cylinder placeholders."""
	if not placeholder_manager:
		_show_alert("Moonlake", "No error markers to clear")
		return

	var count = placeholder_manager.clear_all_error_cylinders()
	if count > 0:
		_show_alert("Moonlake", "Cleared %d error marker(s)" % count)
	else:
		_show_alert("Moonlake", "No error markers found")


## ============================================================================
## SceneTreeDock and AssetsEditorPlugin Signal Connections
## ============================================================================

func _connect_scene_dock_signals() -> void:
	"""Find SceneTreeDock and AssetsEditorPlugin and connect to create button signals."""
	var editor_node = get_tree().root.get_child(0)
	if not editor_node or editor_node.get_class() != "EditorNode":
		Log.error("[MOONLAKE] EditorNode not found!")
		return

	# Connect to SceneTreeDock signals
	var scene_dock = _find_scene_tree_dock(editor_node)
	if not scene_dock:
		Log.error("[MOONLAKE] SceneTreeDock not found in editor tree!")
	else:
		# Connect signals
		if scene_dock.has_signal("create_character_pressed"):
			scene_dock.connect("create_character_pressed", _on_create_character_pressed)
		else:
			Log.error("[MOONLAKE] create_character_pressed signal not found! Rebuild Godot with engine changes.")

		if scene_dock.has_signal("create_terrain_pressed"):
			if terrain_controller:
				scene_dock.connect("create_terrain_pressed", terrain_controller.on_create_terrain_pressed)
		else:
			Log.error("[MOONLAKE] create_terrain_pressed signal not found! Rebuild Godot with engine changes.")

	# Connect to AssetsEditorPlugin signals and set chat panel
	var assets_plugin = _find_assets_editor_plugin(editor_node)
	if not assets_plugin:
		Log.warn("[MOONLAKE] AssetsEditorPlugin not found in editor tree")

func _find_scene_tree_dock(node: Node) -> Node:
	"""Recursively find SceneTreeDock in editor scene tree."""
	if node.get_class() == "SceneTreeDock":
		return node

	for child in node.get_children():
		var result = _find_scene_tree_dock(child)
		if result:
			return result

	return null

func _find_assets_editor_plugin(node: Node) -> Node:
	"""Recursively find AssetsEditorPlugin in editor scene tree."""
	if node.get_class() == "AssetsEditorPlugin":
		return node

	for child in node.get_children():
		var result = _find_assets_editor_plugin(child)
		if result:
			return result

	return null


## ============================================================================
## Debugger Fix Button Signal Connections
## ============================================================================

func _connect_debugger_signals() -> void:
	"""Connect to debugger fix error signals via EditorInterface."""
	var debugger_node = EditorInterface.get_debugger()
	if not debugger_node:
		Log.warn("[MOONLAKE] EditorDebuggerNode not available - fix buttons won't work")
		return

	var debuggers = _find_all_script_debuggers(debugger_node)
	for debugger in debuggers:
		_connect_single_debugger(debugger)


func _find_all_script_debuggers(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if node.get_class() == "ScriptEditorDebugger":
		result.append(node)

	for child in node.get_children():
		result.append_array(_find_all_script_debuggers(child))

	return result


func _connect_single_debugger(debugger: Node) -> void:
	"""Connect fix signals from a single ScriptEditorDebugger."""
	if debugger.has_signal("fix_error_requested"):
		if not debugger.is_connected("fix_error_requested", _on_fix_error_requested):
			debugger.connect("fix_error_requested", _on_fix_error_requested)

	if debugger.has_signal("fix_all_errors_requested"):
		if not debugger.is_connected("fix_all_errors_requested", _on_fix_all_errors_requested):
			debugger.connect("fix_all_errors_requested", _on_fix_all_errors_requested)


func _on_fix_error_requested(source_file: String, source_line: int, error_message: String, is_warning: bool) -> void:
	if not chat_panel or not chat_panel.input_controller or not chat_panel.input_box:
		return

	var error_type = "warning" if is_warning else "error"
	var message = "%s\n\nPlease fix this runtime %s reported by Godot at %s:%d" % [error_message, error_type, source_file, source_line]

	var existing = chat_panel.input_box.text
	if existing.strip_edges().is_empty():
		chat_panel.input_box.text = message
	else:
		chat_panel.input_box.text = existing + "\n\n" + message

	chat_panel.input_box.grab_focus()
	chat_panel.input_box.set_caret_line(chat_panel.input_box.get_line_count() - 1)
	chat_panel.input_box.set_caret_column(chat_panel.input_box.get_line(chat_panel.input_box.get_line_count() - 1).length())


func _on_fix_all_errors_requested(file_path: String) -> void:
	if not chat_panel or not chat_panel.input_controller or not chat_panel.input_box:
		return

	if chat_panel.attachment_manager:
		chat_panel.attachment_manager.add_file_attachment(file_path, "fix_all_errors.json")

	var message = "Please fix all the errors/warnings in the attached file. Prioritise errors first."

	chat_panel.input_box.text = message
	chat_panel.input_box.grab_focus()
	chat_panel.input_box.set_caret_line(chat_panel.input_box.get_line_count() - 1)
	chat_panel.input_box.set_caret_column(chat_panel.input_box.get_line(chat_panel.input_box.get_line_count() - 1).length())


func _on_create_character_pressed() -> void:
	"""Handle Create Character button press from SceneTreeDock or AssetsEditorPlugin."""
	# Check if window already open
	if active_paint_window and is_instance_valid(active_paint_window):
		active_paint_window.grab_focus()
		return

	# Load paint scene directly
	var paint_scene = load("res://addons/moonlake_copilot/paintbrush/paint_root.tscn")
	if paint_scene:
		var paint_root = paint_scene.instantiate()

		# Pass plugin and python_bridge references to paint_root
		paint_root.plugin_ref = self
		if python_bridge:
			paint_root.python_bridge = python_bridge

		# Create a simple Window wrapper
		var paint_window = Window.new()
		paint_window.title = "Moonlake: Create Character"
		paint_window.size = Vector2i(900, 1150)
		paint_window.unresizable = true
		paint_window.transient = true
		paint_window.exclusive = true

		# Ensure window can receive input events properly
		paint_window.gui_embed_subwindows = false

		# Add paint_root to window and ensure it's visible/processing
		paint_window.add_child(paint_root)
		paint_root.set_process_input(true)
		paint_root.set_process(true)

		# Add window to editor
		EditorInterface.get_base_control().add_child(paint_window)
		paint_window.popup_centered()

		# Track instance and cleanup on close
		active_paint_window = paint_window
		paint_window.close_requested.connect(func():
			# Cancel any ongoing operations in tools_panel
			var tools_panel = paint_root.get_node_or_null("BottomToolbar")
			if tools_panel and tools_panel.has_method("cancel_operations"):
				tools_panel.cancel_operations()

			paint_window.queue_free()
			active_paint_window = null
		)
		paint_window.tree_exited.connect(func(): active_paint_window = null)
	else:
		Log.error("[MOONLAKE] Failed to load paint scene")

func _on_resources_reimported(resources: PackedStringArray) -> void:
	"""Watch for new GLB files being added (indicates avatar generation)."""
	var avatar_dirs = ["res://assets/meshes/", "res://npcs/", "res://player/"]

	for res_path in resources:
		# Check if it's a GLB file in one of our avatar directories
		if res_path.ends_with(".glb"):
			var is_avatar_dir = false
			for dir in avatar_dirs:
				if res_path.begins_with(dir):
					is_avatar_dir = true
					break

			if is_avatar_dir:
				# Extract filename from path
				var filename = res_path.get_file()

				# Update Assets tab
				var editor_node = get_tree().root.get_child(0)
				var assets_plugin = _find_assets_editor_plugin(editor_node)

				if assets_plugin:
					if assets_plugin.has_method("show_avatar_result"):
						var display_message = "Avatar Generated Successfully\n\nFile: %s\nPath: %s\n\nClick Refresh to see all assets." % [filename, res_path]
						assets_plugin.call("show_avatar_result", display_message)

					# Also refresh the asset list
					if assets_plugin.has_method("refresh_asset_list"):
						assets_plugin.call("refresh_asset_list")

				# Only show for the first GLB found in this batch
				return

## 3D Viewport Context Menu (Delegated to viewport_context_controller)
## ============================================================================

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	"""Delegate viewport input to viewport_context_controller."""
	if viewport_context_controller:
		return viewport_context_controller.forward_3d_gui_input(viewport_camera, event)
	return EditorPlugin.AFTER_GUI_INPUT_PASS

