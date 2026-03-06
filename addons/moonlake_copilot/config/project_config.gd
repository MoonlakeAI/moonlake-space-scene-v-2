extends Node

## Manages Moonlake project configuration stored in .godot/moonlake_config.ini
## Handles UUID generation and persistence for linking Godot projects to backend

const CONFIG_DIR = ".godot"
const CONFIG_FILE = "moonlake_config.ini"

## Get or create a unique project ID for this Godot project
## Returns a UUID string that persists across sessions
func get_or_create_project_id(project_root: String) -> String:
	var config_dir_path = project_root.path_join(CONFIG_DIR)
	var config_file_path = config_dir_path.path_join(CONFIG_FILE)

	if FileAccess.file_exists(config_file_path):
		var project_id = _read_project_id(config_file_path)
		if project_id != "":
			Log.info("[ProjectConfig] Loaded existing project_id: " + project_id)
			return project_id

	var project_id = _generate_uuid()
	Log.info("[ProjectConfig] Generated new project_id: " + project_id)
	_write_config(config_file_path, project_id)

	return project_id

## Read project_id from existing config file
func _read_project_id(config_path: String) -> String:
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		Log.error("[ProjectConfig] Failed to read config: " + str(FileAccess.get_open_error()))
		return ""

	var content = file.get_as_text()
	file.close()

	# Parse INI format - look for project_id = <uuid>
	var lines = content.split("\n")
	for line in lines:
		line = line.strip_edges()
		if line.begins_with("project_id"):
			var parts = line.split("=")
			if parts.size() >= 2:
				return parts[1].strip_edges()

	return ""

## Write new config file with project_id
func _write_config(config_path: String, project_id: String):
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(CONFIG_DIR):
		var err = dir.make_dir(CONFIG_DIR)
		if err != OK:
			Log.error("[ProjectConfig] Failed to create .godot directory: " + str(err))
			return

	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		Log.error("[ProjectConfig] Failed to write config: " + str(FileAccess.get_open_error()))
		return

	var timestamp = Time.get_datetime_string_from_system(true)

	file.store_string("[moonlake]\n")
	file.store_string("project_id = " + project_id + "\n")
	file.store_string("created_at = " + timestamp + "\n")
	file.close()

	Log.info("[ProjectConfig] Wrote config to: " + config_path)

## Generate a UUID v4 string
## Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
func _generate_uuid() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var uuid = ""

	for i in range(36):
		if i == 8 or i == 13 or i == 18 or i == 23:
			uuid += "-"
		elif i == 14:
			uuid += "4"  # Version 4
		elif i == 19:
			# Variant bits: 8, 9, a, or b
			var variant = ["8", "9", "a", "b"][rng.randi() % 4]
			uuid += variant
		else:
			var hex_chars = "0123456789abcdef"
			uuid += hex_chars[rng.randi() % 16]

	return uuid

## Get auth cookie from config, returns empty string if not found
func get_auth_cookie(project_root: String) -> String:
	return _read_config_value(project_root, "auth_cookie")

## Get account ID from config, returns empty string if not found
func get_account_id(project_root: String) -> String:
	return _read_config_value(project_root, "account_id")

## Helper function to read a config value
func _read_config_value(project_root: String, key: String) -> String:
	var config_dir_path = project_root.path_join(CONFIG_DIR)
	var config_file_path = config_dir_path.path_join(CONFIG_FILE)

	if not FileAccess.file_exists(config_file_path):
		return ""

	var file = FileAccess.open(config_file_path, FileAccess.READ)
	if file == null:
		return ""

	var content = file.get_as_text()
	file.close()

	var lines = content.split("\n")
	for line in lines:
		line = line.strip_edges()
		if line.begins_with(key):
			var parts = line.split("=", true, 1)  # Only split on first =
			if parts.size() >= 2:
				return parts[1].strip_edges()

	return ""
