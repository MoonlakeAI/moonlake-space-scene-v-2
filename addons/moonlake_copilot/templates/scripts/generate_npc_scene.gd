extends SceneTree

# Deterministic NPC.tscn generator for AI-controlled characters.
#
# Two-step usage (run from the Godot project root):
#
#   Step 1 – setup (downloads mesh, copies templates, writes .import sidecar):
#     godot --headless --script _generators/generate_npc_scene.gd \
#       -- mesh_url=https://example.com/mesh.glb mesh_path=res://npc/mesh.glb npc_dir=res://npc --setup
#
#   Step 2 – import + generate (reimports mesh with bone map, builds NPC.tscn):
#     godot --headless --import && \
#     godot --headless --script _generators/generate_npc_scene.gd \
#       -- mesh_path=res://npc/mesh.glb npc_dir=res://npc npc_type=enemy

const ANIM_TEMPLATE_DIR := "res://addons/moonlake_copilot/templates/player/"
const NPC_TEMPLATE_DIR := "res://addons/moonlake_copilot/templates/npc/"


func _init() -> void:
	var mesh_url := ""
	var mesh_path := ""
	var npc_dir := ""
	var npc_type := "friendly"
	var setup_mode := false

	for arg in OS.get_cmdline_user_args():
		if arg == "--setup":
			setup_mode = true
		elif arg.begins_with("mesh_url="):
			mesh_url = arg.substr("mesh_url=".length())
		elif arg.begins_with("mesh_path="):
			mesh_path = arg.substr("mesh_path=".length())
		elif arg.begins_with("npc_dir="):
			npc_dir = arg.substr("npc_dir=".length())
		elif arg.begins_with("npc_type="):
			npc_type = arg.substr("npc_type=".length())

	if mesh_path.is_empty() or npc_dir.is_empty():
		printerr("Usage: -- mesh_url=<URL> mesh_path=res://npc/mesh.glb npc_dir=res://npc --setup")
		printerr("       -- mesh_path=res://npc/mesh.glb npc_dir=res://npc npc_type=friendly")
		quit(1)
		return

	if not npc_dir.ends_with("/"):
		npc_dir += "/"

	if setup_mode:
		if mesh_url.is_empty():
			printerr("--setup requires mesh_url=<URL>")
			quit(1)
			return
		var err := _run_setup(mesh_url, mesh_path, npc_dir)
		quit(0 if err == OK else 1)
	else:
		var err := _build_npc_scene(mesh_path, npc_dir, npc_type)
		quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------
# Setup pass: download mesh, copy template assets, write .import sidecar
# ---------------------------------------------------------------------------

func _run_setup(mesh_url: String, mesh_path: String, npc_dir: String) -> Error:
	if not DirAccess.dir_exists_absolute(npc_dir):
		var err := DirAccess.make_dir_recursive_absolute(npc_dir)
		if err != OK:
			printerr("Failed to create directory: %s" % npc_dir)
			return err

	var dl_err := _download_file(mesh_url, mesh_path)
	if dl_err != OK:
		return dl_err

	var err_lib := _copy_file(ANIM_TEMPLATE_DIR + "Character_AnimationLibrary.tres",
		npc_dir + "Character_AnimationLibrary.tres")
	if err_lib != OK:
		return err_lib
	var err_map := _copy_file(ANIM_TEMPLATE_DIR + "unirig_bone_map.tres",
		npc_dir + "unirig_bone_map.tres")
	if err_map != OK:
		return err_map
	var err_bt := _copy_file(NPC_TEMPLATE_DIR + "npc_idle.tres",
		npc_dir + "npc_idle.tres")
	if err_bt != OK:
		return err_bt

	var bone_map_path := npc_dir + "unirig_bone_map.tres"
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
# Generation pass: load imported mesh + build NPC.tscn
# ---------------------------------------------------------------------------

func _build_npc_scene(mesh_path: String, npc_dir: String, npc_type: String) -> Error:
	var mesh_scene: PackedScene = load(mesh_path)
	if mesh_scene == null:
		printerr("Failed to load mesh: %s — was the --setup pass run first?" % mesh_path)
		return ERR_FILE_NOT_FOUND

	var anim_lib: AnimationLibrary = load(npc_dir + "Character_AnimationLibrary.tres")
	if anim_lib == null:
		printerr("Failed to load AnimationLibrary: %s" % (npc_dir + "Character_AnimationLibrary.tres"))
		return ERR_FILE_NOT_FOUND

	# BT requires LimboAI GDExtension — load gracefully so scene generation
	# succeeds even without the extension (BTPlayer is created either way).
	var bt_resource: Resource = load(npc_dir + "npc_idle.tres")
	if bt_resource == null:
		print("Warning: could not load behavior tree (LimboAI not available?) — BTPlayer will have no behavior_tree set.")

	# --- Build scene tree ---
	var npc := CharacterBody3D.new()
	npc.name = "NPC"
	npc.set_meta("npc_type", npc_type)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	npc.add_child(collision)
	collision.owner = npc

	var visuals := Node3D.new()
	visuals.name = "Visuals"
	npc.add_child(visuals)
	visuals.owner = npc

	var char_mesh := mesh_scene.instantiate()
	char_mesh.name = "CharacterMesh"
	visuals.add_child(char_mesh)
	char_mesh.unique_name_in_owner = true
	char_mesh.owner = npc

	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	anim_player.root_node = NodePath("../CharacterMesh")
	visuals.add_child(anim_player)
	anim_player.owner = npc
	anim_player.add_animation_library("default", anim_lib)

	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.root_node = NodePath("%CharacterMesh")
	anim_tree.anim_player = NodePath("../AnimationPlayer")
	anim_tree.tree_root = _build_state_machine()
	visuals.add_child(anim_tree)
	anim_tree.owner = npc

	# BTPlayer (LimboAI behavior tree player — ClassDB gives us the real
	# GDExtension node so behavior_tree is a native property, not metadata).
	var bt_player: Node = ClassDB.instantiate(&"BTPlayer")
	bt_player.name = "BTPlayer"
	if bt_resource != null:
		bt_player.set("behavior_tree", bt_resource)
	npc.add_child(bt_player)
	bt_player.owner = npc

	# NavigationAgent3D for pathfinding
	var nav_agent := NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	npc.add_child(nav_agent)
	nav_agent.owner = npc

	# DetectionArea (Area3D with sphere collider for player detection)
	var detection_area := Area3D.new()
	detection_area.name = "DetectionArea"
	npc.add_child(detection_area)
	detection_area.owner = npc

	var detection_shape := CollisionShape3D.new()
	detection_shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 10.0
	detection_shape.shape = sphere
	detection_area.add_child(detection_shape)
	detection_shape.owner = npc

	# --- Pack & save ---
	var scene := PackedScene.new()
	var pack_err := scene.pack(npc)
	if pack_err != OK:
		printerr("Failed to pack scene: %s" % error_string(pack_err))
		npc.free()
		return pack_err

	var save_path := npc_dir + "NPC.tscn"
	var save_err := ResourceSaver.save(scene, save_path)
	if save_err != OK:
		printerr("Failed to save scene: %s" % error_string(save_err))
		npc.free()
		return save_err

	print("NPC.tscn saved to: %s (npc_type=%s)" % [save_path, npc_type])
	npc.free()
	return OK


# ---------------------------------------------------------------------------
# State machine builder — simple Idle-only state for NPC
# ---------------------------------------------------------------------------

func _build_state_machine() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "default/Idle"
	sm.add_node("Idle", idle_node, Vector2(300, 100))

	# Start → Idle (auto-advance)
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = 0.0
	transition.advance_mode = 2  # AUTO
	sm.add_transition("Start", "Idle", transition)

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
