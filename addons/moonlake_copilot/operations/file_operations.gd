@tool
extends RefCounted
class_name FileOperations

static func read_file(file_path: String, offset: int = 0, limit: int = 0) -> String:
	if not FileAccess.file_exists(file_path):
		return "Error: File not found: " + file_path

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return "Error: Unable to open file: " + file_path

	var content = file.get_as_text()
	file.close()

	if offset > 0 or limit > 0:
		var lines = content.split("\n")
		var start = offset if offset > 0 else 0
		var end = start + limit if limit > 0 else lines.size()
		lines = lines.slice(start, end)
		return "\n".join(lines)

	return content

static func edit_file(file_path: String, old_string: String, new_string: String, replace_all: bool = false) -> String:
	var content = read_file(file_path)
	if content.begins_with("Error:"):
		return content

	if not old_string in content:
		return "Error: old_string not found in file"

	var new_content: String
	if replace_all:
		new_content = content.replace(old_string, new_string)
	else:
		var pos = content.find(old_string)
		new_content = content.substr(0, pos) + new_string + content.substr(pos + old_string.length())

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return "Error: Unable to write file"

	file.store_string(new_content)
	file.close()

	return "Modified " + file_path

static func write_file(file_path: String, content: String) -> String:
	var dir_path = file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return "Error: Unable to create directory"

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return "Error: Unable to create file"

	file.store_string(content)
	file.close()

	return "Created " + file_path

static var IGNORED_PATHS: Array[String] = [
	"res://addons/moonlake_copilot",  # Don't find our own plugin code
	"res://.godot",                    # Godot's cache folder
	"res://.git",                      # Git folder
]

# TODO: Consider C++ implementation (https://github.com/p-ranav/glob)
static func glob_match(path: String, pattern: String) -> bool:
	"""Match path against glob pattern. Supports *, ?, and **."""
	path = path.replace("\\", "/")
	pattern = pattern.replace("\\", "/")

	if path.begins_with("res://"):
		path = path.substr(6)
	if pattern.begins_with("res://"):
		pattern = pattern.substr(6)

	var path_segments = path.split("/", false)
	var pattern_segments = pattern.split("/", false)

	return _match_segments(path_segments, pattern_segments, 0, 0)

static func _match_segments(path_segs: Array[String], pattern_segs: Array[String], path_idx: int, pattern_idx: int) -> bool:
	if pattern_idx >= pattern_segs.size():
		return path_idx >= path_segs.size()

	var pattern_seg = pattern_segs[pattern_idx]

	if pattern_seg == "**":
		if _match_segments(path_segs, pattern_segs, path_idx, pattern_idx + 1):
			return true
		if path_idx < path_segs.size():
			return _match_segments(path_segs, pattern_segs, path_idx + 1, pattern_idx)
		return false

	if path_idx >= path_segs.size():
		return false

	if path_segs[path_idx].match(pattern_seg):
		return _match_segments(path_segs, pattern_segs, path_idx + 1, pattern_idx + 1)

	return false

static func glob_files(pattern: String, path: String = "res://") -> Array[String]:
	var results: Array[String] = []
	_scan_directory(path, pattern, results)
	return results

static func _scan_directory(path: String, pattern: String, results: Array[String]):
	for ignored_path in IGNORED_PATHS:
		if path.begins_with(ignored_path):
			return

	var dir = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		var full_path = path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory(full_path, pattern, results)
		else:
			if glob_match(full_path, pattern):
				results.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()

static func grep_files(pattern: String, path: String = "res://", glob: String = "*.gd") -> String:
	var files = glob_files(glob, path)
	var results: Array[String] = []

	for file_path in files:
		var content = read_file(file_path)
		if content.begins_with("Error:"):
			continue

		var lines = content.split("\n")
		for i in range(lines.size()):
			if pattern in lines[i]:  # Simple substring match for MVP
				results.append("%s:%d: %s" % [file_path, i + 1, lines[i].strip_edges()])

	if results.is_empty():
		return "No matches found."

	# Limit to 100 results
	if results.size() > 100:
		results = results.slice(0, 100)
		return "\n".join(results) + "\n\n(Results truncated to 100 matches)"

	return "\n".join(results)

# TODO: Can improve speed by batching downloads and inserting into scene after downloads are done, and downloading in parallel
static func add_mesh(url: String, name: String, position_dict: Dictionary, scale_dict: Dictionary, rotation_dict: Dictionary) -> String:
	if not url.begins_with("http://") and not url.begins_with("https://"):
		return "Error: URL must start with http:// or https://"

	var valid_extensions = [".glb", ".gltf"]
	var is_valid_format = false
	for ext in valid_extensions:
		if url.to_lower().ends_with(ext):
			is_valid_format = true
			break

	if not is_valid_format:
		return "Error: URL must point to a .glb or .gltf file"

	var url_parts = url.split("/")
	var filename = url_parts[-1] if url_parts.size() > 0 else "mesh.glb"

	var node_name = name if name != "" else filename.get_basename()

	var assets_dir = "res://assets/meshes"
	if not DirAccess.dir_exists_absolute(assets_dir):
		var err = DirAccess.make_dir_recursive_absolute(assets_dir)
		if err != OK:
			return "Error: Unable to create assets/meshes directory: " + error_string(err)

	var local_path = assets_dir.path_join(filename)

	var file_already_exists = FileAccess.file_exists(local_path)

	if not file_already_exists:
		var download_result = await _download_file(url, local_path)
		if not download_result.success:
			return download_result.message

	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface == null:
		return "Error: EditorInterface not available"

	var edited_scene_root = editor_interface.get_edited_scene_root()
	if edited_scene_root == null:
		return "Error: No scene is currently open in the editor"

	var mesh_scene = load(local_path)
	if mesh_scene == null:
		return "Error: Failed to load mesh from " + local_path

	var mesh_instance = mesh_scene.instantiate()
	if mesh_instance == null:
		return "Error: Failed to instantiate mesh"

	mesh_instance.name = node_name

	if mesh_instance is Node3D:
		mesh_instance.position = Vector3(
			position_dict.get("x", 0.0),
			position_dict.get("y", 0.0),
			position_dict.get("z", 0.0)
		)

		mesh_instance.scale = Vector3(
			scale_dict.get("x", 1.0),
			scale_dict.get("y", 1.0),
			scale_dict.get("z", 1.0)
		)

		mesh_instance.rotation_degrees = Vector3(
			rotation_dict.get("x", 0.0),
			rotation_dict.get("y", 0.0),
			rotation_dict.get("z", 0.0)
		)
	else:
		return "Error: Loaded mesh is not a Node3D"

	edited_scene_root.add_child(mesh_instance)
	mesh_instance.owner = edited_scene_root

	var pos = mesh_instance.position
	return "Added mesh '%s' at position (%.1f, %.1f, %.1f)\nDownloaded from: %s\nLocal path: %s" % [
		node_name, pos.x, pos.y, pos.z, url, local_path
	]

static func _download_file(url: String, save_path: String, timeout: float = DownloadConfig.DOWNLOAD_TIMEOUT_PER_ATTEMPT) -> Dictionary:
	Log.info("[DOWNLOAD] %s" % url)

	var scene_tree = Engine.get_main_loop()
	if scene_tree == null or not scene_tree is SceneTree:
		Log.error("[ERROR] Cannot access SceneTree")
		return {
			"success": false,
			"http_code": 0,
			"message": "Error: Cannot access SceneTree"
		}

	# Ensure directory exists
	var dir_path = save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mkdir_err = DirAccess.make_dir_recursive_absolute(dir_path)
		if mkdir_err != OK:
			Log.error("[ERROR] Cannot create directory: %s" % dir_path)
			return {
				"success": false,
				"http_code": 0,
				"message": "Error: Cannot create directory: " + dir_path
			}

	# Create HTTPRequest node (direct approach - works correctly)
	var http = HTTPRequest.new()
	scene_tree.root.add_child(http)
	http.timeout = timeout
	http.use_threads = true

	var err = http.request(url)
	if err != OK:
		http.queue_free()
		Log.error("[ERROR] HTTP request failed: %s - %s" % [error_string(err), url])
		return {
			"success": false,
			"http_code": 0,
			"message": "Error: HTTP request failed: " + error_string(err)
		}

	# Directly await signal (this works - signals fire correctly)
	var result = await http.request_completed
	http.queue_free()

	var result_code = result[0]
	var response_code = result[1]
	var body = result[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		Log.error("[ERROR] Result code %d - %s" % [result_code, url])
		return {
			"success": false,
			"http_code": 0,
			"result_code": result_code,
			"message": "Error: Download failed with result code: " + str(result_code)
		}

	if response_code != 200:
		Log.error("[ERROR] HTTP %d - %s" % [response_code, url])
		return {
			"success": false,
			"http_code": response_code,
			"message": "Error: HTTP response code: " + str(response_code)
		}

	# Save to file
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		Log.error("[ERROR] Cannot write file: %s" % save_path)
		return {
			"success": false,
			"http_code": response_code,
			"message": "Error: Cannot write file: " + save_path
		}

	file.store_buffer(body)
	file.close()

	Log.info("[DOWNLOAD] Complete: %s" % save_path)
	return {
		"success": true,
		"http_code": 200,
		"message": "Downloaded successfully"
	}

static func _wait_for_signal_with_timeout(object: Object, signal_name: String, timeout_seconds: float) -> bool:
	"""Wait for a signal with timeout. Returns true if timed out, false if signal fired."""
	var scene_tree = Engine.get_main_loop()
	if scene_tree == null or not scene_tree is SceneTree:
		return true

	var timer = scene_tree.create_timer(timeout_seconds)
	var signal_fired = false

	# Connect to signal to track if it fires (accepts any number of arguments)
	var on_signal = func(_arg1 = null, _arg2 = null, _arg3 = null): signal_fired = true
	object.connect(signal_name, on_signal, CONNECT_ONE_SHOT)

	# Wait for timer to expire
	await timer.timeout

	# Disconnect if signal hasn't fired yet
	if not signal_fired and object.is_connected(signal_name, on_signal):
		object.disconnect(signal_name, on_signal)

	return not signal_fired  # Returns true if timed out

static func _batch_import_resources(editor_interface, file_paths: Array = []) -> bool:
	"""No-op function - imports are now handled after dialog closes to avoid progress dialog crashes."""
	if file_paths.is_empty():
		Log.info("[IMPORT] No files to import")
		return true

	Log.info("[IMPORT] Skipping scan during resolve (will scan after dialog closes)")
	return true


