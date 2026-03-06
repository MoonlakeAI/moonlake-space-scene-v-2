@tool
extends RefCounted

const DEFAULT_REQUIRED_NAME: String = "UniRigSkeleton"
const OUTPUT_SUFFIX: String = ".skeleton.json"

func dump_skeletons(paths: PackedStringArray) -> Dictionary:
	var results: Array = []
	var errors: Array = []
	for path in paths:
		if not _is_scene_file(path):
			continue
		var res = load(path)
		if res == null:
			errors.append({"path": path, "error": "Failed to load resource"})
			continue
		var root: Node = null
		if res is PackedScene:
			root = (res as PackedScene).instantiate()
		elif res is Node:
			root = res as Node
		else:
			errors.append({"path": path, "error": "Unsupported resource type"})
			continue
		var skeleton: Skeleton3D = _find_skeleton(root)
		if skeleton == null:
			errors.append({"path": path, "error": "No Skeleton3D found"})
			if root is Node:
				root.queue_free()
			continue
		var entry := _build_entry(path, root, skeleton)
		results.append(entry)
		_save_json(path.get_basename() + OUTPUT_SUFFIX, entry)
		if root is Node:
			root.queue_free()
	return {"results": results, "errors": errors}

func validate_target(paths: PackedStringArray, required_name: String = DEFAULT_REQUIRED_NAME) -> Dictionary:
	var results: Array = []
	var errors: Array = []
	for path in paths:
		if not _is_scene_file(path):
			continue
		var res = load(path)
		if res == null:
			errors.append({"path": path, "error": "Failed to load resource"})
			continue
		var root: Node = null
		if res is PackedScene:
			root = (res as PackedScene).instantiate()
		elif res is Node:
			root = res as Node
		else:
			errors.append({"path": path, "error": "Unsupported resource type"})
			continue
		var skeletons := _find_all_skeletons(root)
		if skeletons.is_empty():
			errors.append({"path": path, "error": "No Skeleton3D found"})
			if root is Node:
				root.queue_free()
			continue
		var matched: Skeleton3D = null
		for s in skeletons:
			if s.name == required_name:
				matched = s
				break
		var entry := {
			"path": path,
			"required_name": required_name,
			"found_count": skeletons.size(),
			"matched": matched != null,
			"matched_unique_name": matched != null and matched.is_unique_name_in_owner(),
			"skeleton_paths": skeletons.map(func(s: Skeleton3D): return String(s.get_path()))
		}
		results.append(entry)
		if root is Node:
			root.queue_free()
	return {"results": results, "errors": errors}

func _build_entry(path: String, root: Node, skeleton: Skeleton3D) -> Dictionary:
	var bones: Array = []
	for i in skeleton.get_bone_count():
		bones.append({
			"name": skeleton.get_bone_name(i),
			"parent": skeleton.get_bone_parent(i)
		})
	var rel_path := _get_relative_path(root, skeleton)
	return {
		"source_file": path,
		"skeleton_node_path": rel_path,
		"skeleton_name": skeleton.name,
		"unique_name_in_owner": skeleton.is_unique_name_in_owner(),
		"bone_count": skeleton.get_bone_count(),
		"bones": bones
	}

func _get_relative_path(root: Node, node: Node) -> String:
	if node == root:
		return node.name
	var parts: Array[String] = []
	var current: Node = node
	while current and current != root:
		parts.push_front(current.name)
		current = current.get_parent()
	if current == root:
		parts.push_front(root.name)
	return "/".join(parts)

func _save_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save skeleton dump: " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("Saved skeleton dump -> ", path)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		if child is Node:
			var found := _find_skeleton(child)
			if found:
				return found
	return null

func _find_all_skeletons(node: Node) -> Array:
	var found: Array = []
	if node is Skeleton3D:
		found.append(node)
	for child in node.get_children():
		if child is Node:
			found.append_array(_find_all_skeletons(child))
	return found

func _is_scene_file(path: String) -> bool:
	var lower := path.to_lower()
	return lower.ends_with(".glb") or lower.ends_with(".fbx") or lower.ends_with(".gltf") or lower.ends_with(".tscn")
