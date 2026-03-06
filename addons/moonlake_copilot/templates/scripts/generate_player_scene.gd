extends SceneTree

# Deterministic Player.tscn generator for third-person avatar prefabs.
#
# Two-step usage (run from the Godot project root):
#
#   Step 1 – setup (downloads mesh, copies templates, writes .import sidecar):
#     godot --headless --script _generators/generate_player_scene.gd \
#       -- mesh_url=https://example.com/mesh.glb mesh_path=res://player/knight.glb player_dir=res://player --setup
#
#   Step 2 – import + generate (reimports mesh with bone map, builds Player.tscn):
#     godot --headless --import && \
#     godot --headless --script _generators/generate_player_scene.gd \
#       -- mesh_path=res://player/knight.glb player_dir=res://player

const ANIM_TEMPLATE_DIR := "res://addons/moonlake_copilot/templates/player/"
const CONTROLLER_DIR := "res://addons/moonlake_copilot/templates/third_person_controller/player/"

# State name → animation clip in the "default" library.
# These are the EXACT clip names from Character_AnimationLibrary.tres.
const CLIP_NAMES := {
	"Idle": "default/Idle",
	"Walk": "default/Walk",
	"Run":  "default/Sprint",
	"Jump": "default/Jump_Start",
	"Fall": "default/Jump",
	"Land": "default/Jump_Land",
}

# [from, to, xfade_time, advance_mode]
# advance_mode: 1 = ENABLED (travel() triggers), 2 = AUTO (fires when clip ends)
const TRANSITIONS := [
	["Idle", "Walk", 0.1, 1],
	["Walk", "Idle", 0.1, 1],
	["Walk", "Run",  0.1, 1],
	["Run",  "Walk", 0.1, 1],
	["Idle", "Jump", 0.1, 1],
	["Walk", "Jump", 0.1, 1],
	["Run",  "Jump", 0.1, 1],
	["Idle", "Fall", 0.1, 1],
	["Walk", "Fall", 0.1, 1],
	["Run",  "Fall", 0.1, 1],
	["Run",  "Idle", 0.1, 1],
	["Jump", "Fall", 0.1, 1],
	["Fall", "Land", 0.1, 1],
	["Land", "Fall", 0.1, 1],
	["Land", "Idle", 0.15, 2],
	["Start", "Idle", 0.0, 2],
]


func _init() -> void:
	var mesh_url := ""
	var mesh_path := ""
	var player_dir := ""
	var setup_mode := false

	for arg in OS.get_cmdline_user_args():
		if arg == "--setup":
			setup_mode = true
		elif arg.begins_with("mesh_url="):
			mesh_url = arg.substr("mesh_url=".length())
		elif arg.begins_with("mesh_path="):
			mesh_path = arg.substr("mesh_path=".length())
		elif arg.begins_with("player_dir="):
			player_dir = arg.substr("player_dir=".length())

	if mesh_path.is_empty() or player_dir.is_empty():
		printerr("Usage: -- mesh_url=<URL> mesh_path=res://player/mesh.glb player_dir=res://player --setup")
		printerr("       -- mesh_path=res://player/mesh.glb player_dir=res://player")
		quit(1)
		return

	if not player_dir.ends_with("/"):
		player_dir += "/"

	if setup_mode:
		if mesh_url.is_empty():
			printerr("--setup requires mesh_url=<URL>")
			quit(1)
			return
		var err := _run_setup(mesh_url, mesh_path, player_dir)
		quit(0 if err == OK else 1)
	else:
		var err := _build_player_scene(mesh_path, player_dir)
		quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------
# Setup pass: download mesh, copy template assets, write .import sidecar
# ---------------------------------------------------------------------------

func _run_setup(mesh_url: String, mesh_path: String, player_dir: String) -> Error:
	if not DirAccess.dir_exists_absolute(player_dir):
		var err := DirAccess.make_dir_recursive_absolute(player_dir)
		if err != OK:
			printerr("Failed to create directory: %s" % player_dir)
			return err

	var dl_err := _download_file(mesh_url, mesh_path)
	if dl_err != OK:
		return dl_err

	var err_lib := _copy_file(ANIM_TEMPLATE_DIR + "Character_AnimationLibrary.tres",
		player_dir + "Character_AnimationLibrary.tres")
	if err_lib != OK:
		return err_lib
	var err_map := _copy_file(ANIM_TEMPLATE_DIR + "unirig_bone_map.tres",
		player_dir + "unirig_bone_map.tres")
	if err_map != OK:
		return err_map

	var bone_map_path := player_dir + "unirig_bone_map.tres"
	var err := _write_import_sidecar(mesh_path, bone_map_path)
	if err != OK:
		return err

	print("Setup complete: templates copied, .import sidecar written.")
	return OK


func _write_import_sidecar(mesh_path: String, bone_map_path: String) -> Error:
	var bone_map: Resource = load(bone_map_path)
	if bone_map == null:
		printerr("Failed to load bone map: %s" % bone_map_path)
		return ERR_FILE_NOT_FOUND

	# Multiple PATH entries cover different .glb skeleton hierarchies.
	var skeleton_paths := [
		"PATH:Skeleton3D",
		"PATH:Armature/Skeleton3D",
		"PATH:Rig/Skeleton3D",
		"PATH:RootNode/Skeleton3D",
		"PATH:RootNode/Armature/Skeleton3D",
	]
	var nodes := {}
	for path in skeleton_paths:
		nodes[path] = {"retarget/bone_map": bone_map}

	var config := ConfigFile.new()
	config.set_value("remap", "importer", "scene")
	config.set_value("remap", "importer_version", 1)
	config.set_value("remap", "type", "PackedScene")
	config.set_value("deps", "source_file", mesh_path)
	config.set_value("params", "nodes/import_as_skeleton_bones", true)
	config.set_value("params", "_subresources", {"nodes": nodes})

	var sidecar_path := mesh_path + ".import"
	var err := config.save(sidecar_path)
	if err != OK:
		printerr("Failed to write sidecar: %s (error: %s)" % [
			sidecar_path, error_string(err)])
		return err
	print("Wrote .import sidecar: %s" % sidecar_path)
	return OK


# ---------------------------------------------------------------------------
# Generation pass: load imported mesh + build Player.tscn
# ---------------------------------------------------------------------------

func _build_player_scene(mesh_path: String, player_dir: String) -> Error:
	var err_mc := _copy_file(CONTROLLER_DIR + "movement_controller.gd",
		player_dir + "movement_controller.gd")
	if err_mc != OK:
		return err_mc
	var err_ac := _copy_file(CONTROLLER_DIR + "animation_controller.gd",
		player_dir + "animation_controller.gd")
	if err_ac != OK:
		return err_ac

	# Copy orbit camera script so the agent only needs to create the Camera3D node
	var camera_dir := "res://camera/"
	if not DirAccess.dir_exists_absolute(camera_dir):
		DirAccess.make_dir_recursive_absolute(camera_dir)
	var err_cam := _copy_file("res://addons/moonlake_copilot/templates/third_person_controller/camera/orbit_camera.gd",
		camera_dir + "orbit_camera.gd")
	if err_cam != OK:
		return err_cam

	var mesh_scene: PackedScene = load(mesh_path)
	if mesh_scene == null:
		printerr("Failed to load mesh: %s — was the --setup pass run first?" % mesh_path)
		return ERR_FILE_NOT_FOUND

	var anim_lib: AnimationLibrary = load(player_dir + "Character_AnimationLibrary.tres")
	if anim_lib == null:
		printerr("Failed to load AnimationLibrary: %s" % (player_dir + "Character_AnimationLibrary.tres"))
		return ERR_FILE_NOT_FOUND

	var move_script: Script = load(player_dir + "movement_controller.gd")
	var anim_ctrl_script: Script = load(player_dir + "animation_controller.gd")
	if move_script == null or anim_ctrl_script == null:
		printerr("Failed to load controller scripts from %s" % player_dir)
		return ERR_FILE_NOT_FOUND

	# --- Build scene tree ---
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(move_script)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	player.add_child(collision)
	collision.owner = player

	# 180-deg Y rotation: mesh faces +Z from generation, Godot forward is -Z
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	visuals.transform = Transform3D(Basis(Vector3(0, 1, 0), PI), Vector3.ZERO)
	player.add_child(visuals)
	visuals.owner = player

	var char_mesh := mesh_scene.instantiate()
	char_mesh.name = "CharacterMesh"
	visuals.add_child(char_mesh)
	char_mesh.unique_name_in_owner = true
	char_mesh.owner = player
	# Children belong to the instanced scene — do NOT set their owner

	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	anim_player.root_node = NodePath("../CharacterMesh")
	visuals.add_child(anim_player)
	anim_player.owner = player
	anim_player.add_animation_library("default", anim_lib)

	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.root_node = NodePath("%CharacterMesh")
	anim_tree.anim_player = NodePath("../AnimationPlayer")
	anim_tree.tree_root = _build_state_machine()
	visuals.add_child(anim_tree)
	anim_tree.owner = player

	var anim_ctrl := Node.new()
	anim_ctrl.name = "AnimationController"
	anim_ctrl.set_script(anim_ctrl_script)
	player.add_child(anim_ctrl)
	anim_ctrl.owner = player

	# --- Pack & save ---
	var scene := PackedScene.new()
	var pack_err := scene.pack(player)
	if pack_err != OK:
		printerr("Failed to pack scene: %s" % error_string(pack_err))
		player.free()
		return pack_err

	var save_path := player_dir + "Player.tscn"
	var save_err := ResourceSaver.save(scene, save_path)
	if save_err != OK:
		printerr("Failed to save scene: %s" % error_string(save_err))
		player.free()
		return save_err

	print("Player.tscn saved to: %s" % save_path)
	player.free()
	return OK


# ---------------------------------------------------------------------------
# State machine builder
# ---------------------------------------------------------------------------

func _build_state_machine() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()

	var positions := {
		"Idle": Vector2(300, 100),
		"Walk": Vector2(550, 0),
		"Run":  Vector2(800, 0),
		"Jump": Vector2(550, 200),
		"Fall": Vector2(800, 200),
		"Land": Vector2(1050, 200),
	}

	for state_name in CLIP_NAMES:
		var anim_node := AnimationNodeAnimation.new()
		anim_node.animation = CLIP_NAMES[state_name]
		sm.add_node(state_name, anim_node, positions[state_name])

	for t in TRANSITIONS:
		var transition := AnimationNodeStateMachineTransition.new()
		transition.xfade_time = t[2]
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		transition.advance_mode = t[3]
		sm.add_transition(t[0], t[1], transition)

	return sm


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

func _download_file(url: String, res_path: String) -> Error:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var output := []
	var exit_code := OS.execute("curl", ["-sfL", "--connect-timeout", "30", "--max-time", "120", "-o", abs_path, url], output, true)
	if exit_code != 0:
		printerr("Download failed (exit %d): %s" % [exit_code, url])
		for line in output:
			printerr("  curl: %s" % line)
		return ERR_FILE_CANT_OPEN
	if not FileAccess.file_exists(res_path):
		printerr("Download produced no file at: %s" % res_path)
		return ERR_FILE_NOT_FOUND
	print("Downloaded: %s -> %s" % [url, res_path])
	return OK


func _copy_file(src: String, dst: String) -> Error:
	if FileAccess.file_exists(dst):
		return OK
	if not FileAccess.file_exists(src):
		printerr("Template not found: %s" % src)
		return ERR_FILE_NOT_FOUND
	var f_in := FileAccess.open(src, FileAccess.READ)
	if f_in == null:
		printerr("Could not open: %s" % src)
		return FileAccess.get_open_error()
	var data := f_in.get_buffer(f_in.get_length())
	f_in.close()

	# Strip the top-level uid from the [gd_resource] header so Godot assigns
	# a fresh one, preventing UID collisions when multiple characters share a
	# template. Only the first line is touched to avoid stripping UIDs from
	# sub-resource references deeper in the file.
	if dst.ends_with(".tres"):
		var text := data.get_string_from_utf8()
		var newline_pos := text.find("\n")
		if newline_pos > 0:
			var first_line := text.substr(0, newline_pos)
			var regex := RegEx.new()
			regex.compile(' uid="uid://[^"]*"')
			first_line = regex.sub(first_line, "")
			text = first_line + text.substr(newline_pos)
		data = text.to_utf8_buffer()

	var f_out := FileAccess.open(dst, FileAccess.WRITE)
	if f_out == null:
		printerr("Could not write: %s" % dst)
		return FileAccess.get_open_error()
	f_out.store_buffer(data)
	f_out.close()
	print("Copied: %s -> %s" % [src, dst])
	return OK
