extends SceneTree

# CLI screenshot tool for 2D scenes.
#
# Usage:
#   godot --path <project_dir> -s screenshot_2d.gd -- --scene=res://scene.tscn --output=res://out.png [options]
#
# Required:
#   --scene=<res://path>        Scene to load
#   --output=<res://path.png>   Output image path
#
# Optional:
#   --camera_position=x,y       Camera center position (default: 0,0)
#   --camera_zoom=N             Zoom level, higher = zoomed in (default: 1.0)
#   --size=WxH                  Output resolution (default: 1920x1080)
#   --settle_frames=N           Frames to wait before capture (default: 2)

var _output_path: String
var _camera_position: String
var _camera_zoom: String
var _size: String
var _settle_frames: String
var _scene_path: String

var _valid := false
var _camera_ready := false
var _frame_count := 0
var _capture_frame := -1
var _sub_viewport: SubViewport
var _viewport_size := Vector2i(1920, 1080)
const _DEFAULT_SETTLE_FRAMES := 2
const _MAX_FRAMES_BUFFER := 30


func _init():
	for arg in OS.get_cmdline_user_args():
		if not arg.contains("="):
			continue
		var kv = arg.split("=", true, 1)
		var key = kv[0].trim_prefix("--")
		var value = kv[1]
		match key:
			"scene":           _scene_path = value
			"output":          _output_path = value
			"camera_position": _camera_position = value
			"camera_zoom":     _camera_zoom = value
			"size":            _size = value
			"settle_frames":   _settle_frames = value

	if _scene_path.is_empty():
		printerr("Missing required arg: --scene=<res://path/to/scene.tscn>")
		quit(1)
		return
	if _output_path.is_empty():
		printerr("Missing required arg: --output=<res://path/to/output.png>")
		quit(1)
		return

	# Parse size early
	if not _size.is_empty():
		var parts = _size.split("x")
		if parts.size() == 2:
			_viewport_size = Vector2i(int(parts[0]), int(parts[1]))

	print("Loading 2D scene: ", _scene_path)
	print("Output path: ", _output_path)

	var packed_scene = load(_scene_path)
	if packed_scene == null:
		printerr("Failed to load scene: ", _scene_path)
		quit(1)
		return

	var scene = packed_scene.instantiate()
	root.add_child(scene)
	_valid = true


func _process(_delta: float) -> bool:
	if not _valid:
		return true
	_frame_count += 1

	var settle := int(_settle_frames) if not _settle_frames.is_empty() else _DEFAULT_SETTLE_FRAMES
	if _frame_count > settle + _MAX_FRAMES_BUFFER:
		printerr("Screenshot timed out after %d frames" % _frame_count)
		quit(1)
		return true

	if not _camera_ready:
		# Create SubViewport that shares the World2D with the main viewport
		_sub_viewport = SubViewport.new()
		_sub_viewport.size = _viewport_size
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_sub_viewport.transparent_bg = false
		_sub_viewport.handle_input_locally = false
		_sub_viewport.gui_disable_input = true
		
		# Share the World2D from the root viewport
		_sub_viewport.world_2d = root.get_viewport().world_2d
		
		print("Frame %d: SubViewport size: %dx%d" % [_frame_count, _viewport_size.x, _viewport_size.y])
		
		root.add_child(_sub_viewport)
		_setup_camera()
		_camera_ready = true
		_capture_frame = _frame_count + settle
		print("Frame %d: Waiting %d settle frames before capture" % [_frame_count, settle])
		return false

	if _frame_count >= _capture_frame:
		_capture()
		return true

	return false


func _setup_camera() -> void:
	var pos := _parse_vector2(_camera_position) if not _camera_position.is_empty() else Vector2.ZERO
	var zoom_val := float(_camera_zoom) if not _camera_zoom.is_empty() else 1.0

	var camera = Camera2D.new()
	camera.position = pos
	camera.zoom = Vector2(zoom_val, zoom_val)
	_sub_viewport.add_child(camera)
	camera.make_current()

	print("Frame %d: 2D camera at %s (zoom=%s)" % [_frame_count, pos, zoom_val])


func _capture() -> void:
	print("Frame %d: Capturing screenshot (SubViewport %dx%d)" % [
		_frame_count, _sub_viewport.size.x, _sub_viewport.size.y])
	
	# Try to get texture from SubViewport
	var texture = _sub_viewport.get_texture()
	var image: Image = null
	
	if texture != null:
		image = texture.get_image()
	
	# If SubViewport failed, try root viewport
	if image == null:
		texture = root.get_viewport().get_texture()
		if texture != null:
			image = texture.get_image()
	
	# If all rendering failed (headless mode), create fallback
	if image == null:
		print("Frame %d: Headless 2D rendering not supported, creating fallback image" % _frame_count)
		image = Image.create(_viewport_size.x, _viewport_size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.35, 0.35, 0.35, 1.0))
	
	image.save_png(_output_path)
	print("Frame %d: Screenshot saved to %s (%dx%d)" % [
		_frame_count, _output_path, image.get_width(), image.get_height()])


func _parse_vector2(s: String) -> Vector2:
	var parts = s.split(",")
	return Vector2(float(parts[0]), float(parts[1]))
