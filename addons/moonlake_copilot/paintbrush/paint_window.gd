@tool
extends Window

## Paint Window - Modal popup wrapper for the paintbrush tool
##
## Wraps paint_root.tscn in a modal Window for character creation

var paint_root: Control

func _init():
	# Window configuration
	title = "Moonlake: Create Character"
	size = Vector2i(900, 1100)  # Match PaintRoot design size
	unresizable = true
	transient = true  # Modal behavior
	exclusive = true  # Blocks editor interaction

func _ready() -> void:
	Log.info("[PaintWindow] _ready() called")

	# Load scene using PackedScene API (avoids placeholder issues)
	var scene_path = "res://addons/moonlake_copilot/paintbrush/paint_root.tscn"
	var packed_scene = ResourceLoader.load(scene_path, "PackedScene")

	if packed_scene:
		Log.info("[PaintWindow] PackedScene loaded successfully")
		paint_root = packed_scene.instantiate()
		Log.info("[PaintWindow] paint_root instantiated: %s" % paint_root)

		# Add to window BEFORE accessing children (ensures proper initialization)
		add_child(paint_root)
		Log.info("[PaintWindow] paint_root added as child")

		# Force show the window
		show()
		Log.info("[PaintWindow] Window shown")

		# Wait multiple frames for everything to initialize
		await get_tree().process_frame
		await get_tree().process_frame

		Log.info("[PaintWindow] Children initialized, count: %s" % paint_root.get_child_count())

		# Check PaintControl
		var paint_control = paint_root.get_node_or_null("PaintControl")
		if paint_control:
			var script = paint_control.get_script()
			Log.info("[PaintWindow] PaintControl script: %s" % script)
			if script:
				Log.info("[PaintWindow] Script class: %s" % script.get_class())
				Log.info("[PaintWindow] Script resource path: %s" % script.resource_path)

			# Check if it has the expected methods
			Log.info("[PaintWindow] Has _ready: %s" % paint_control.has_method("_ready"))
			Log.info("[PaintWindow] Has _process: %s" % paint_control.has_method("_process"))

			# Try to check TL_node
			var tl_node = paint_control.get_node_or_null("TLPos")
			Log.info("[PaintWindow] TLPos found: %s" % (tl_node != null))

			# Check if the TL_node variable in the script was set (would prove _ready ran)
			Log.info("[PaintWindow] Checking TL_node variable in paint_control...")
			var tl_var = paint_control.TL_node
			Log.info("[PaintWindow] TL_node variable value: %s" % tl_var)
			if tl_var == null:
				Log.error("[PaintWindow] CRITICAL: TL_node is null - _ready() NEVER RAN!")
				Log.error("[PaintWindow] This is the root problem - scripts attached but not executing")
			else:
				Log.info("[PaintWindow] Good: TL_node is set, _ready() executed")
		else:
			Log.error("[PaintWindow] ERROR: PaintControl not found")
	else:
		Log.error("[PaintWindow] ERROR: Failed to load PackedScene")

	# Connect window close signal for cleanup
	close_requested.connect(_on_close_requested)

func _on_close_requested() -> void:
	# Clean up and close
	queue_free()
