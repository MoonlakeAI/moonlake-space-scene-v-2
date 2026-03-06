@tool
extends RefCounted
class_name SceneOperations

const PlayerInputConfig = preload("res://addons/moonlake_copilot/config/player_input_config.gd")

static func _download_and_import_mesh(url: String, local_path: String) -> String:
	"""
	Download mesh from URL and wait for import to complete.
	Reusable helper extracted from add_mesh logic.

	Returns: "Success" or error message starting with "Error:"
	"""
	if FileAccess.file_exists(local_path):
		return "Success"

	var assets_dir = local_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(assets_dir):
		var err = DirAccess.make_dir_recursive_absolute(assets_dir)
		if err != OK:
			return "Error: Unable to create directory: " + assets_dir

	var download_result = await FileOperations._download_file(url, local_path)
	if not download_result.success:
		return download_result.message

	return "Success"

static func _configure_avatar_import_settings(glb_path: String, editor_interface) -> void:
	var import_path = glb_path + ".import"
	var config = ConfigFile.new()
	config.load(import_path)
	config.set_value("params", "nodes/import_as_skeleton_bones", true)
	config.set_value("params", "skins/use_named_skins", true)
	config.set_value("params", "animation/import", true)

	var bone_map_path = "res://addons/moonlake_copilot/templates/player/unirig_bone_map.tres"
	var bone_map = load(bone_map_path) as BoneMap
	if bone_map:
		var subresources = {
			"nodes": {
				"PATH:Skeleton3D": {
					"retarget/bone_map": bone_map
				}
			}
		}
		config.set_value("params", "_subresources", subresources)
		Log.info("[CREATE_AVATAR] Configured import with bone map: %s" % glb_path.get_file())
	else:
		Log.warn("[CREATE_AVATAR] Could not load bone map, skipping retarget config")

	config.save(import_path)

	var fs = EditorInterface.get_resource_filesystem()
	fs.reimport_files(PackedStringArray([glb_path]))

static func reload_all_modified_scenes() -> String:
	# Wait for filesystem scan/import to finish before reloading,
	# otherwise we may reference scenes that no longer exist.
	var fs = EditorInterface.get_resource_filesystem()
	await EditorUtils.await_filesystem_ready(fs, 15.0)

	EditorInterface.reload_modified_scenes()

	return "Reloaded modified scenes"

static func open_main_scene_or_fallback(scene_path: String) -> String:
	"""
	- Main scene open AND active → reload and open it
	- Main scene open but NOT active → open scene_path (don't switch tabs)
	- Main scene NOT open AND scene_path is active → stay on it
	- Main scene NOT open → open main_scene
	"""
	# First reload all modified scenes
	await reload_all_modified_scenes()

	var main_scene = ResourceUID.ensure_path(ProjectSettings.get_setting("application/run/main_scene", ""))

	# If no main scene defined, fall back to scene_path
	if main_scene.is_empty() or not FileAccess.file_exists(main_scene):
		if not scene_path:
			return "No scene to open"
		var path = scene_path
		if not scene_path.begins_with("res://"):
			path = ProjectSettings.localize_path(scene_path)
		EditorInterface.open_scene_from_path(path)
		return "Opened scene: %s (main scene not found)" % path

	var open_scenes = Array(EditorInterface.get_open_scenes()).map(func(p): return ResourceUID.ensure_path(p))
	Log.info("[OpenScene] main_scene=%s, open_scenes=%s" % [main_scene, open_scenes])

	var edited_scene = EditorInterface.get_edited_scene_root()
	var active_scene_path = ResourceUID.ensure_path(edited_scene.scene_file_path) if edited_scene else ""

	if main_scene in open_scenes:
		if active_scene_path == main_scene:
			# https://github.com/godotengine/godot-proposals/issues/13816
			await Engine.get_main_loop().process_frame
			EditorInterface.reload_scene_from_path(main_scene)
			await Engine.get_main_loop().process_frame
			EditorInterface.open_scene_from_path(main_scene)
			return "Reloaded main scene: %s" % main_scene
		else:
			if scene_path:
				var path = scene_path
				if not scene_path.begins_with("res://"):
					path = ProjectSettings.localize_path(scene_path)
				EditorInterface.open_scene_from_path(path)
				return "Opened scene: %s (main scene not active)" % path
			return "Main scene open but not active, no fallback scene"

	# Main scene not open
	if scene_path:
		var path = scene_path
		if not scene_path.begins_with("res://"):
			path = ProjectSettings.localize_path(scene_path)
		if path == active_scene_path:
			return "Scene already active: %s" % path

	await Engine.get_main_loop().process_frame
	EditorInterface.open_scene_from_path(main_scene)
	return "Opened main scene: %s" % main_scene

const STOCK_PLAYER_DIR = "res://addons/moonlake_copilot/templates/player"
const USER_PLAYER_DIR = "res://player"
const USER_PLAYER_TSCN = "res://player/Player.tscn"

static func _copy_player_to_project(editor_interface) -> String:
	var source_dir = STOCK_PLAYER_DIR
	var dest_dir = USER_PLAYER_DIR
	
	if not DirAccess.dir_exists_absolute(dest_dir):
		var err = DirAccess.make_dir_recursive_absolute(dest_dir)
		if err != OK:
			return "Error: Failed to create directory: %s" % dest_dir
	
	var files_to_copy = [
		"Player.tscn",
		"player.gd",
		"Character_AnimationLibrary.tres",
		"CharacterMesh.glb",
	]
	
	var dirs_to_copy = [
		"ability_sets",
		"systems",
	]
	
	for filename in files_to_copy:
		var src_path = source_dir.path_join(filename)
		var dst_path = dest_dir.path_join(filename)
		var result = _copy_and_process_file(src_path, dst_path)
		if result.begins_with("Error:"):
			return result
	
	for dirname in dirs_to_copy:
		var src_subdir = source_dir.path_join(dirname)
		var dst_subdir = dest_dir.path_join(dirname)
		var result = _copy_directory_recursive(src_subdir, dst_subdir)
		if result.begins_with("Error:"):
			return result
	
	var fs = EditorInterface.get_resource_filesystem()
	await Engine.get_main_loop().create_timer(0.5).timeout
	fs.scan()
	await Engine.get_main_loop().process_frame

	await EditorUtils.await_filesystem_ready(fs, 15.0)

	await Engine.get_main_loop().create_timer(0.5).timeout
	Log.info("[CREATE_AVATAR] Player system copied to %s" % dest_dir)
	
	PlayerInputConfig.setup_for_game_type(PlayerInputConfig.GameType.THIRD_PERSON_ACTION)
	
	return "Success"

static func _copy_directory_recursive(src_dir: String, dst_dir: String) -> String:
	if not DirAccess.dir_exists_absolute(src_dir):
		return "Error: Source directory does not exist: %s" % src_dir
	
	if not DirAccess.dir_exists_absolute(dst_dir):
		var err = DirAccess.make_dir_recursive_absolute(dst_dir)
		if err != OK:
			return "Error: Failed to create directory: %s" % dst_dir
	
	var dir = DirAccess.open(src_dir)
	if dir == null:
		return "Error: Failed to open directory: %s" % src_dir
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		
		var src_path = src_dir.path_join(file_name)
		var dst_path = dst_dir.path_join(file_name)
		
		if file_name.ends_with(".uid") or file_name.ends_with(".import"):
			file_name = dir.get_next()
			continue
		
		if dir.current_is_dir():
			var result = _copy_directory_recursive(src_path, dst_path)
			if result.begins_with("Error:"):
				return result
		else:
			var result = _copy_and_process_file(src_path, dst_path)
			if result.begins_with("Error:"):
				return result
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return "Success"

static func _copy_and_process_file(src_path: String, dst_path: String) -> String:
	if not FileAccess.file_exists(src_path):
		return "Error: Source file does not exist: %s" % src_path
	
	var content: String
	if src_path.ends_with(".tscn") or src_path.ends_with(".tres") or src_path.ends_with(".gd"):
		var file = FileAccess.open(src_path, FileAccess.READ)
		if file == null:
			return "Error: Failed to read file: %s" % src_path
		content = file.get_as_text()
		file.close()
		
		content = _strip_uids_from_content(content)
		content = _update_paths_in_content(content)
		
		var out_file = FileAccess.open(dst_path, FileAccess.WRITE)
		if out_file == null:
			return "Error: Failed to write file: %s" % dst_path
		out_file.store_string(content)
		out_file.close()
	else:
		var bytes = FileAccess.get_file_as_bytes(src_path)
		if bytes.is_empty() and FileAccess.get_open_error() != OK:
			return "Error: Failed to read binary file: %s" % src_path
		
		var out_file = FileAccess.open(dst_path, FileAccess.WRITE)
		if out_file == null:
			return "Error: Failed to write binary file: %s" % dst_path
		out_file.store_buffer(bytes)
		out_file.close()
	
	return "Success"

static func _strip_uids_from_content(content: String) -> String:
	var uid_pattern = RegEx.new()
	uid_pattern.compile('\\s*uid="uid://[^"]*"')
	return uid_pattern.sub(content, "", true)

static func _update_paths_in_content(content: String) -> String:
	var old_path = "res://addons/moonlake_copilot/templates/player/"
	var new_path = "res://player/"
	return content.replace(old_path, new_path)

static func _replace_character_mesh_via_api(player_tscn_path: String, avatar_glb_path: String) -> String:
	if not ResourceLoader.exists(avatar_glb_path):
		return "Error: Avatar file not found: %s" % avatar_glb_path
	
	var avatar_scene = ResourceLoader.load(avatar_glb_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not avatar_scene:
		return "Error: Failed to load avatar: %s" % avatar_glb_path
	
	if not ResourceLoader.exists(player_tscn_path):
		return "Error: Player.tscn not found: %s" % player_tscn_path
	
	var player_scene = ResourceLoader.load(player_tscn_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not player_scene:
		return "Error: Failed to load Player.tscn"
	
	var player_instance = player_scene.instantiate()
	if not player_instance:
		return "Error: Failed to instantiate Player.tscn"
	
	var char_mesh = player_instance.get_node_or_null("%CharacterMesh")
	if not char_mesh:
		player_instance.free()
		return "Error: CharacterMesh node not found in Player.tscn"
	
	var visuals = char_mesh.get_parent()
	if not visuals:
		player_instance.free()
		return "Error: CharacterMesh has no parent"
	
	var mesh_index = char_mesh.get_index()
	
	var avatar_instance = avatar_scene.instantiate()
	if not avatar_instance:
		player_instance.free()
		return "Error: Failed to instantiate avatar"
	
	visuals.remove_child(char_mesh)
	char_mesh.free()
	
	avatar_instance.name = "CharacterMesh"
	visuals.add_child(avatar_instance)
	visuals.move_child(avatar_instance, mesh_index)
	avatar_instance.owner = player_instance
	avatar_instance.unique_name_in_owner = true
	
	var anim_player = visuals.get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.root_node = NodePath("../CharacterMesh")
	
	var anim_tree = visuals.get_node_or_null("AnimationTree")
	if anim_tree:
		anim_tree.root_node = NodePath("../CharacterMesh")
	
	var new_packed = PackedScene.new()
	var pack_result = new_packed.pack(player_instance)
	player_instance.free()
	
	if pack_result != OK:
		return "Error: Failed to pack scene (code: %d)" % pack_result
	
	var save_result = ResourceSaver.save(new_packed, player_tscn_path)
	if save_result != OK:
		return "Error: Failed to save scene (code: %d)" % save_result
	
	Log.info("[CREATE_AVATAR] Replaced CharacterMesh with avatar: %s" % avatar_glb_path.get_file())
	return "Success"

static func _show_player_exists_dialog(editor_interface) -> String:
	var dialog = AcceptDialog.new()
	dialog.title = "Player Already Exists"
	dialog.dialog_text = "A Player.tscn already exists in your project.\n\nWhat would you like to do?"
	dialog.ok_button_text = "Update Avatar Only"
	dialog.add_button("Overwrite All", true, "overwrite")
	dialog.add_cancel_button("Cancel")
	
	var result = "keep"
	
	dialog.confirmed.connect(func():
		result = "keep"
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(action):
		if action == "overwrite":
			result = "overwrite"
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		result = "cancel"
		dialog.queue_free()
	)
	
	var base_control = EditorInterface.get_base_control()
	base_control.add_child(dialog)
	dialog.popup_centered()
	
	await dialog.tree_exited
	return result