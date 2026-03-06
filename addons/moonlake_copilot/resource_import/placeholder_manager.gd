@tool
extends RefCounted
class_name PlaceholderManager

## Manages visual placeholders for pending meshes

const DownloadTask = preload("res://addons/moonlake_copilot/resource_import/download_task.gd")
const FileOperations = preload("res://addons/moonlake_copilot/operations/file_operations.gd")

var placeholder_nodes: Dictionary = {}  # "(url, node_name)" -> Node3D
var error_material: StandardMaterial3D = null  # Shared material for all error cylinders

func _init():
	# Create shared error material (reused by all cylinders)
	error_material = StandardMaterial3D.new()
	error_material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta (classic missing texture color)
	error_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func create_placeholders_for_tasks(tasks: Array[DownloadTask], tscn_path: String) -> void:
	"""Parse TSCN and create placeholders for mesh nodes with pending downloads."""

	var edited_root = EditorInterface.get_edited_scene_root()
	if not edited_root or edited_root.scene_file_path != tscn_path:
		return  # Scene not open

	# Parse TSCN to find mesh nodes
	var content = FileOperations.read_file(tscn_path)
	if content.begins_with("Error:"):
		return

	# For each task that's pending (not cached)
	for task in tasks:
		if task.state != "pending":
			continue

		# Create placeholders for each node instance
		for node_info in task.node_instances:
			var node_name = node_info.get("node_name", "")
			var parent_path = node_info.get("parent", ".")
			var transform_str = node_info.get("transform", "")

			if node_name == "":
				continue

			_create_placeholder(task.url, node_name, parent_path, transform_str)

func _create_placeholder(url: String, node_name: String, parent_path: String, transform_str: String = "") -> void:
	"""Create a pink box placeholder at the node location."""
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		Log.error("[PLACEHOLDER] Cannot create placeholder - no scene root")
		return

	# Find parent and remove broken node
	var parent = root if parent_path == "." else root.get_node_or_null(parent_path)
	if not parent:
		Log.error("[PLACEHOLDER] Cannot create placeholder - parent not found: %s" % parent_path)
		return

	var old_node = parent.get_node_or_null(node_name)
	if old_node:
		Log.info("[PLACEHOLDER] Removing old broken node: %s" % node_name)
		old_node.queue_free()

	# Create placeholder node with prefix to avoid name collision
	var placeholder = MeshInstance3D.new()
	placeholder.name = "placeholder_" + node_name
	placeholder.mesh = BoxMesh.new()

	# Pink semi-transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 1.0, 0.5)  # Pink
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placeholder.mesh.surface_set_material(0, material)

	parent.add_child(placeholder)
	placeholder.owner = root

	# Apply transform if provided
	if transform_str != "":
		var transform = _parse_transform(transform_str)
		if transform:
			placeholder.transform = transform
			Log.info("[PLACEHOLDER] Applied transform: %s" % transform_str)

	# Track for replacement
	var key = _make_key(url, node_name)
	placeholder_nodes[key] = placeholder
	Log.info("[PLACEHOLDER] Created pink box for '%s' at position %s (will be replaced by %s)" % [node_name, placeholder.global_position, url.get_file()])

func replace_placeholders(task: DownloadTask) -> void:
	"""Replace placeholders with real imported meshes."""

	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return

	for node_info in task.node_instances:
		var node_name = node_info.get("node_name", "")
		if node_name == "":
			continue

		var key = _make_key(task.url, node_name)

		if key not in placeholder_nodes:
			continue

		var placeholder = placeholder_nodes[key]
		if not is_instance_valid(placeholder):
			Log.info("[PLACEHOLDER] Placeholder no longer valid for '%s'" % node_name)
			continue

		# Load the imported scene
		var packed_scene = load(task.local_path)
		if not packed_scene:
			Log.error("[PLACEHOLDER] Failed to load imported mesh: %s" % task.local_path)
			continue

		var instance = packed_scene.instantiate()
		if not instance:
			Log.error("[PLACEHOLDER] Failed to instantiate mesh for '%s'" % node_name)
			continue

		# Copy transform and name from original node info
		instance.transform = placeholder.transform
		instance.name = node_name  # Use original node name, not auto-generated placeholder name

		# Replace in scene tree
		var parent = placeholder.get_parent()
		if parent:
			parent.add_child(instance)
			instance.owner = root
			placeholder.queue_free()

			placeholder_nodes.erase(key)
			Log.info("[PLACEHOLDER] Replaced '%s' with real mesh from %s" % [node_name, task.url.get_file()])

func create_error_placeholders_for_failed_tasks(tasks: Array[DownloadTask], tscn_path: String) -> void:
	"""Create pink cylinders for failed mesh downloads."""

	var root = EditorInterface.get_edited_scene_root()
	# Validate scene still open AND matches the TSCN we're processing
	if not root or root.scene_file_path != tscn_path:
		Log.warn("[PLACEHOLDER] Scene closed or changed, skipping error cylinders")
		return

	for task in tasks:
		if task.state != "failed":
			continue

		# Case-insensitive extension check
		if not _is_mesh_file(task.local_path):
			continue

		# Skip if node_instances is empty (priority < 3 scenario)
		if task.node_instances.is_empty():
			Log.warn("[PLACEHOLDER] No node_instances data for failed task: %s" % task.url.get_file())
			continue

		for node_info in task.node_instances:
			var node_name = node_info.get("node_name", "")
			if node_name == "":
				continue

			var key = _make_key(task.url, node_name)

			# Check if pending placeholder exists
			if key in placeholder_nodes:
				var placeholder = placeholder_nodes[key]
				if is_instance_valid(placeholder) and placeholder.get_parent() != null:
					_convert_placeholder_to_error_cylinder(placeholder, task)
				else:
					placeholder_nodes.erase(key)
					_create_error_cylinder(task, node_info, tscn_path)
			else:
				_create_error_cylinder(task, node_info, tscn_path)

func _convert_placeholder_to_error_cylinder(placeholder: MeshInstance3D, task: DownloadTask) -> void:
	"""Convert existing pink box placeholder to pink cylinder."""
	var cylinder = CylinderMesh.new()
	cylinder.height = 2.0
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5

	# Use shared material instead of creating new one
	cylinder.surface_set_material(0, error_material)

	placeholder.mesh = cylinder

	var original_name = placeholder.name.replace("placeholder_", "")
	placeholder.name = "failed_" + original_name

	# Do NOT set owner - keeps cylinder temporary (not saved to .tscn)
	# placeholder.owner is already set from pending placeholder, we'll clear it
	placeholder.owner = null

	placeholder.set_meta("error_message", task.error_message)
	placeholder.set_meta("original_url", task.url)
	placeholder.set_meta("failed_download", true)

	Log.info("[PLACEHOLDER] Converted box to error cylinder for '%s': %s" % [original_name, task.error_message])

func _create_error_cylinder(task: DownloadTask, node_info: Dictionary, tscn_path: String) -> void:
	"""Create error cylinder from scratch when no pending placeholder exists."""
	# Re-validate scene state (user might have closed during iteration)
	var root = EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path != tscn_path:
		return

	var node_name = node_info.get("node_name", "")
	var parent_path = node_info.get("parent", ".")
	var transform_str = node_info.get("transform", "")

	var parent = root if parent_path == "." else root.get_node_or_null(parent_path)
	if not parent:
		Log.warn("[PLACEHOLDER] Cannot create error cylinder - parent not found: %s" % parent_path)
		return

	var old_node = parent.get_node_or_null(node_name)
	if old_node:
		old_node.queue_free()

	var placeholder = MeshInstance3D.new()
	placeholder.name = "failed_" + node_name

	var cylinder = CylinderMesh.new()
	cylinder.height = 2.0
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5

	# Use shared material
	cylinder.surface_set_material(0, error_material)
	placeholder.mesh = cylinder

	placeholder.set_meta("error_message", task.error_message)
	placeholder.set_meta("original_url", task.url)
	placeholder.set_meta("failed_download", true)

	parent.add_child(placeholder)
	# Do NOT set owner - keeps cylinder temporary
	# placeholder.owner = root  <- REMOVED

	# Apply transform with validation
	if transform_str != "":
		var transform = _parse_transform(transform_str)
		if transform:
			placeholder.transform = transform
		else:
			Log.warn("[PLACEHOLDER] Failed to parse transform for '%s', using identity" % node_name)

	var key = _make_key(task.url, node_name)
	placeholder_nodes[key] = placeholder

	Log.info("[PLACEHOLDER] Created error cylinder for '%s': %s" % [node_name, task.error_message])

func _parse_transform(transform_str: String) -> Transform3D:
	# Parse Transform3D from TSCN format (e.g., "Transform3D(1,0,0,...)")
	# Remove 'Transform3D(' prefix and ')' suffix
	var clean_str = transform_str.replace("Transform3D(", "").replace(")", "").strip_edges()

	# Split by comma and parse floats
	var parts = clean_str.split(",")
	if parts.size() != 12:
		Log.error("[PLACEHOLDER] Invalid transform string (expected 12 values): %s" % transform_str)
		return Transform3D()

	# Parse the 12 float values
	var values: Array[float] = []
	for part in parts:
		values.append(float(part.strip_edges()))

	# Construct Transform3D from basis (9 values) and origin (3 values)
	var basis = Basis(
		Vector3(values[0], values[1], values[2]),  # x axis
		Vector3(values[3], values[4], values[5]),  # y axis
		Vector3(values[6], values[7], values[8])   # z axis
	)
	var origin = Vector3(values[9], values[10], values[11])

	return Transform3D(basis, origin)

func _is_mesh_file(path: String) -> bool:
	"""Check if file is a mesh type (case-insensitive)."""
	var ext = path.get_extension().to_lower()
	return ext in ["glb", "gltf", "obj", "mesh"]

func _make_key(url: String, node_name: String) -> String:
	return url + "|" + node_name

func clear_all_error_cylinders() -> int:
	"""Clear all error cylinders from current scene (used before new import or manual cleanup)."""
	var count = 0
	for key in placeholder_nodes.keys():
		var node = placeholder_nodes[key]
		if is_instance_valid(node) and node.has_meta("failed_download"):
			var parent = node.get_parent()
			if parent:
				parent.remove_child(node)
			node.queue_free()  # OK to use queue_free() during normal operation (not shutdown)
			count += 1
	placeholder_nodes.clear()
	return count
