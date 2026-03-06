extends SceneTree

# CLI screenshot tool with two camera modes:
#
# Mode selection:
#   If --camera_position is provided → Free camera (position + look_at target)
#   Otherwise                        → Orbit camera (target + distance + angles)
#   Both produce a Camera3D; the difference is how its position is determined.
#
# Usage:
#   godot --path <project_dir> -s screenshot.gd -- --scene=res://scene.tscn --output=res://out.png [camera args]
#
# Required:
#   --scene=<res://path>        Scene to load
#   --output=<res://path.png>   Output image path
#
# Orbit camera (inspect objects, overviews):
#   --camera_target=x,y,z      Point to look at (default: 0,0,0)
#   --camera_distance=N         Distance from target in meters (required)
#   --camera_yaw=N              Horizontal angle in degrees (required)
#   --camera_pitch=N            Vertical angle in degrees, negative=looking down (required)
#
# Free camera (ground-level, water surface, skybox):
#   --camera_position=x,y,z    Exact camera position (required)
#   --camera_target=x,y,z      Point to look at (default: 0,0,0)
#
# Shared (optional):
#   --camera_fov=N              Field of view in degrees (default: 75)
#   --camera_ortho_size=N       Switch to orthographic projection with this size in meters
#   --size=WxH                  Output resolution (e.g., 1024x1024)
#   --settle_frames=N           Frames to wait before capture (default: 2, use 120 for 2s lifetime VFX at 60 FPS)

var _output_path: String
var _camera_position: String
var _camera_target: String
var _camera_distance: String
var _camera_yaw: String
var _camera_pitch: String
var _camera_fov: String
var _camera_ortho_size: String
var _size: String
var _settle_frames: String
var _is_free_camera: bool

var _valid := false
var _camera_ready := false
var _frame_count := 0
var _capture_frame := -1
var _sub_viewport: SubViewport
const _DEFAULT_SETTLE_FRAMES := 2
const _MAX_FRAMES_BUFFER := 30

func _init():
	var scene_path := ""

	for arg in OS.get_cmdline_user_args():
		if not arg.contains("="):
			continue
		var kv = arg.split("=", true, 1)
		var key = kv[0].trim_prefix("--")
		var value = kv[1]
		match key:
			"scene":             scene_path = value
			"output":            _output_path = value
			"camera_position":   _camera_position = value
			"camera_target":     _camera_target = value
			"camera_distance":   _camera_distance = value
			"camera_yaw":        _camera_yaw = value
			"camera_pitch":      _camera_pitch = value
			"camera_fov":        _camera_fov = value
			"camera_ortho_size": _camera_ortho_size = value
			"size":              _size = value
			"settle_frames":     _settle_frames = value

	# Validate required args
	if scene_path.is_empty():
		printerr("Missing required arg: --scene=<res://path/to/scene.tscn>")
		quit(1)
		return
	if _output_path.is_empty():
		printerr("Missing required arg: --output=<res://path/to/output.png>")
		quit(1)
		return

	# Determine camera mode and validate
	_is_free_camera = not _camera_position.is_empty()
	if not _is_free_camera:
		var missing := []
		if _camera_distance.is_empty():
			missing.append("--camera_distance")
		if _camera_yaw.is_empty():
			missing.append("--camera_yaw")
		if _camera_pitch.is_empty():
			missing.append("--camera_pitch")
		if not missing.is_empty():
			printerr("Orbit camera requires: %s" % ", ".join(missing))
			quit(1)
			return

	print("Loading scene: ", scene_path)
	print("Output path: ", _output_path)

	var packed_scene = load(scene_path)
	if packed_scene == null:
		printerr("Failed to load scene: ", scene_path)
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
		_sub_viewport = SubViewport.new()
		_sub_viewport.own_world_3d = false
		_sub_viewport.world_3d = root.get_viewport().world_3d
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if not _size.is_empty():
			var parts = _size.split("x")
			if parts.size() == 2:
				var w = int(parts[0])
				var h = int(parts[1])
				_sub_viewport.size = Vector2i(w, h)
				print("Frame %d: SubViewport size: %dx%d" % [_frame_count, w, h])
		else:
			_sub_viewport.size = Vector2i(1920, 1080)
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
	var target := _parse_vector3(_camera_target) if not _camera_target.is_empty() else Vector3.ZERO
	var fov := float(_camera_fov) if not _camera_fov.is_empty() else 75.0

	var camera = Camera3D.new()
	camera.fov = fov

	# Orthographic projection
	if not _camera_ortho_size.is_empty():
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = float(_camera_ortho_size)

	if _is_free_camera:
		camera.position = _parse_vector3(_camera_position)
		_sub_viewport.add_child(camera)
		camera.look_at(target)
		print("Frame %d: Free camera at %s → target %s (fov=%s)" % [
			_frame_count, camera.position, target, fov])
	else:
		var distance := float(_camera_distance)
		var yaw := float(_camera_yaw)
		var pitch := float(_camera_pitch)
		var pitch_rad := deg_to_rad(pitch)
		var yaw_rad := deg_to_rad(yaw)

		var offset := Vector3(
			distance * cos(pitch_rad) * sin(yaw_rad),
			distance * sin(-pitch_rad),
			distance * cos(pitch_rad) * cos(yaw_rad)
		)
		camera.position = target + offset
		_sub_viewport.add_child(camera)
		if pitch < -89.0:
			camera.look_at(target, Vector3(0, 0, -1))
		elif pitch > 89.0:
			camera.look_at(target, Vector3(0, 0, 1))
		else:
			camera.look_at(target)
		if not _camera_ortho_size.is_empty():
			print("Frame %d: Orbit camera (ortho=%sm) → target %s (distance=%s, yaw=%s, pitch=%s)" % [
				_frame_count, _camera_ortho_size, target, distance, yaw, pitch])
		else:
			print("Frame %d: Orbit camera → target %s (distance=%s, yaw=%s, pitch=%s, fov=%s)" % [
				_frame_count, target, distance, yaw, pitch, fov])

	camera.make_current()


func _capture() -> void:
	print("Frame %d: Capturing screenshot (SubViewport %dx%d)" % [
		_frame_count, _sub_viewport.size.x, _sub_viewport.size.y])
	var image = _sub_viewport.get_texture().get_image()
	if image == null:
		printerr("Frame %d: Failed to get SubViewport image" % _frame_count)
		quit(1)
		return
	image.save_png(_output_path)
	print("Frame %d: Screenshot saved to %s (%dx%d)" % [
		_frame_count, _output_path, image.get_width(), image.get_height()])


func _parse_vector3(s: String) -> Vector3:
	var parts = s.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
