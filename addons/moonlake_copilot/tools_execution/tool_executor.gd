@tool
extends Node
class_name ToolExecutor

## ToolExecutor - Executes tool requests from the backend
##
## NOTE: Most tools (Edit, Glob, Grep, Bash, MultiEdit, TodoWrite) are now handled
## in Python for better performance. Only scene-specific tools remain in Godot.

# Extensions that have Godot importers (verified from Godot 4.5 source)
const IMPORTABLE_EXTENSIONS = [
	# Images
	"png", "jpg", "jpeg", "bmp", "webp", "tga", "hdr", "exr", "svg",
	# Audio
	"wav", "ogg", "mp3", "mp1", "mp2",
	# 3D
	"gltf", "glb", "fbx", "blend", "obj", "escn",
	# Fonts
	"ttf", "ttc", "otf", "otc", "woff", "woff2", "pfb", "pfm", "font", "fnt",
	# Shaders
	"glsl",
]

var python_bridge: Node  # Injected by plugin.gd

func handle_request(message: Dictionary) -> void:
	"""
	Handle tool_request message from plugin.gd's message pump.

	Args:
		message: Tool request with request_id, tool_name, tool_params
	"""
	var request_id = message.get("request_id", "")
	var tool_name = message.get("tool_name", "")
	var tool_params = message.get("tool_params", {})

	var result = await execute_tool(tool_name, tool_params)

	if python_bridge:
		python_bridge.call_python("tool_result", {
			"request_id": request_id,
			"tool_name": tool_name,
			"result": result,
			"error": null
		})
	else:
		Log.error("[ToolExecutor] python_bridge not set, cannot send tool result")

func execute_tool(tool_name: String, params: Dictionary) -> String:
	var result: String
	match tool_name:
		"ResolvePath":
			var file_path = params.get("file_path", "")
			if file_path.begins_with("res://"):
				result = ProjectSettings.globalize_path(file_path)
			else:
				result = file_path

		"AddMesh":
			result = await FileOperations.add_mesh(
				params.get("url", ""),
				params.get("name", ""),
				params.get("position", {}),
				params.get("scale", {"x": 1, "y": 1, "z": 1}),
				params.get("rotation", {"x": 0, "y": 0, "z": 0})
			)

		"ReimportFile":
			result = await _execute_reimport_file(params)

		"EditorOutput":
			result = _execute_editor_output(params)

		_:
			var supported_tools = ["ResolvePath", "AddMesh", "ReimportFile", "EditorOutput"]
			result = "Error: Unknown tool '%s'. Supported tools: %s (other tools are handled in Python)" % [tool_name, ", ".join(supported_tools)]
			Log.error(result)

	return result


func _execute_reimport_file(params: Dictionary) -> String:
	"""
	Scan and optionally reimport files.

	For script/scene files: Only scans filesystem (no reimport needed)
	For asset files: Scans and reimports

	params: {
		"files": Array[String] - File paths to scan/reimport (res:// or absolute)
	}
	"""
	var files = params.get("files", [])

	if files.is_empty():
		var fs = EditorInterface.get_resource_filesystem()
		if fs:
			Log.info("[Reimport] Empty file list - triggering filesystem scan")
			fs.scan_sources()
			return "Triggered filesystem scan"
		return "Error: Could not get EditorFileSystem"

	Log.info("[Reimport] Processing %d file(s):" % files.size())
	for f in files:
		Log.info("  - %s" % f)

	var res_paths = PackedStringArray()
	var files_needing_import = PackedStringArray()
	var resource_files = PackedStringArray()
	var scene_files = PackedStringArray()
	var config_files = PackedStringArray()
	var other_text_files = PackedStringArray()
	var unrecognized_files = PackedStringArray()

	for file_path in files:
		var resolved_path = file_path
		if not file_path.begins_with("res://"):
			resolved_path = ProjectSettings.localize_path(file_path)
		res_paths.append(resolved_path)

		var ext = resolved_path.get_extension().to_lower()

		if ext in ["tscn", "scn"]:
			scene_files.append(resolved_path)
		elif ext == "godot":
			config_files.append(resolved_path)
		elif ext in ["gd", "tres", "res", "gdshader"]:
			resource_files.append(resolved_path)
		elif ext in ["txt", "md", "json", "import", "log", "cfg", "uid", "remap", "gitignore", "gitattributes", "gdignore"]:
			other_text_files.append(resolved_path)
		elif ext in IMPORTABLE_EXTENSIONS:
			files_needing_import.append(resolved_path)
		else:
			unrecognized_files.append(resolved_path)

	var fs = EditorInterface.get_resource_filesystem()
	if not fs:
		return "Error: Could not get EditorFileSystem"

	var needs_scan = false
	for res_path in res_paths:
		var file_item = fs.get_filesystem_path(res_path)
		if not file_item:
			needs_scan = true
			break

	if needs_scan:
		Log.info("[Reimport] Scanning filesystem for new files...")
		fs.scan_sources()

		var success = await EditorUtils.await_filesystem_ready(fs, 15.0)
		if not success:
			return "Error: Filesystem scan timed out"

		Log.info("[Reimport] Filesystem scan complete")

	if resource_files.size() > 0:
		Log.info("[Reimport] Reloading %d resource file(s):" % resource_files.size())
		for file_path in resource_files:
			Log.info("  - %s" % file_path)
			var resource = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if resource:
				resource.reload_from_file()
				Log.info("  Reloaded")
			else:
				Log.warn("Failed to load resource: %s" % file_path)

	if config_files.size() > 0:
		Log.info("[Reimport] Reloading project settings:")
		for file_path in config_files:
			Log.info("  - %s" % file_path)
		EditorInterface.reload_project_settings()
		Log.info("  Project settings reloaded")

	if other_text_files.size() > 0:
		Log.info("[Reimport] Detected %d text file change(s) (no action needed)" % other_text_files.size())

	if files_needing_import.size() > 0:
		Log.info("[Reimport] Importing %d asset file(s):" % files_needing_import.size())

		var valid_files: PackedStringArray = []

		for file_path in files_needing_import:
			var abs_path = file_path if file_path.begins_with("/") else ProjectSettings.globalize_path(file_path)

			if not FileAccess.file_exists(file_path):
				Log.error("  Skipped (not found): %s" % file_path)
				continue

			var file = FileAccess.open(file_path, FileAccess.READ)
			if file == null:
				Log.error("  Skipped (cannot open): %s" % file_path)
				continue

			var file_size = file.get_length()
			file.close()  # Close file handle after reading size

			if file_size == 0:
				Log.error("  Skipped (empty file): %s" % file_path)
				continue

			# File is valid, add to import list
			valid_files.append(file_path)
			Log.info("  - %s (%d bytes)" % [file_path, file_size])

		if valid_files.size() == 0:
			Log.warn("[Reimport] No valid files to import (all skipped)")
		else:
			# Import one file at a time - batch import crashes with mixed file types
			for file_path in valid_files:
				fs.reimport_files(PackedStringArray([file_path]))
				Log.info("  Imported: %s" % file_path)
			Log.info("[Reimport] All %d file(s) imported successfully" % valid_files.size())

	if unrecognized_files.size() > 0:
		Log.warn("[Reimport] Skipped %d file(s) with unrecognized extensions:" % unrecognized_files.size())
		for file_path in unrecognized_files:
			Log.warn("  - %s" % file_path)

	var counts = []
	if resource_files.size() > 0:
		counts.append("%d resource(s)" % resource_files.size())
	if scene_files.size() > 0:
		counts.append("%d scene(s)" % scene_files.size())
	if config_files.size() > 0:
		counts.append("project settings")
	if files_needing_import.size() > 0:
		counts.append("%d asset(s)" % files_needing_import.size())
	if unrecognized_files.size() > 0:
		counts.append("%d skipped (unrecognized)" % unrecognized_files.size())

	if counts.size() > 0:
		return "Reloaded: " + ", ".join(counts)
	else:
		return "No files to reload"


func _execute_editor_output(params: Dictionary) -> String:
	"""
	Get output from the Godot editor log.

	params: {
		"filter_type": int (optional) - Filter by type: -1=all (default), 0=standard, 1=errors, 3=warnings, 4=editor
		"limit": int (optional) - Max number of recent messages to return (default: 50, max: 50)
	}
	"""
	var filter_type = params.get("filter_type", -1)
	var limit = mini(params.get("limit", 50), 50)

	var editor_log = _find_editor_log(EditorInterface.get_base_control())
	if not editor_log:
		return JSON.stringify({"success": false, "error": "EditorLog not found"})

	var messages: Array = editor_log.get_messages_text(filter_type)

	if messages.size() > limit:
		messages = messages.slice(messages.size() - limit, messages.size())

	messages.append("--- Output generated at %s ---" % Time.get_time_string_from_system())

	return JSON.stringify({
		"success": true,
		"messages": messages,
		"total_count": messages.size()
	})


func _find_editor_log(node: Node) -> Node:
	"""Recursively search for EditorLog node in the editor tree"""
	if node.get_class() == "EditorLog":
		return node

	for child in node.get_children():
		var result = _find_editor_log(child)
		if result:
			return result

	return null

