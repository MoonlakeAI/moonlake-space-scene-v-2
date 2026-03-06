@tool
class_name SkeletonVisualizer
extends Skeleton3D

@export var sphere_radius: float = 0.03:
	set(value):
		sphere_radius = value
		_rebuild_visuals()

@export var sphere_color: Color = Color.CYAN:
	set(value):
		sphere_color = value
		_update_materials()

@export var label_color: Color = Color.WHITE:
	set(value):
		label_color = value
		_update_label_colors()

@export var label_font_size: int = 12:
	set(value):
		label_font_size = value
		_update_label_sizes()

@export var debug_draw_enabled: bool = true:
	set(value):
		debug_draw_enabled = value
		_update_visibility()

@export var show_labels: bool = true:
	set(value):
		show_labels = value
		_update_label_visibility()

@export_range(8, 32) var sphere_segments: int = 12:
	set(value):
		sphere_segments = value
		_rebuild_visuals()

var _bone_visuals: Array[MeshInstance3D] = []
var _bone_labels: Array[Label3D] = []
var _wireframe_mesh: ArrayMesh
var _bone_materials: Array[StandardMaterial3D] = []


func _enter_tree() -> void:
	set_process(true)
	call_deferred("_create_visuals")
	print("SkeletonVisualizer: _enter_tree called, bone count = ", get_bone_count())


func _create_visuals() -> void:
	_clear_visuals()

	var bone_count: int = get_bone_count()
	print("SkeletonVisualizer: Creating visuals for ", bone_count, " bones")

	if bone_count == 0:
		return

	_wireframe_mesh = _create_wireframe_sphere_mesh(sphere_radius, sphere_segments)
	_bone_materials.clear()

	for i in range(bone_count):
		var bone_name: String = get_bone_name(i)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		var color: Color = _color_for_bone(i, bone_count)
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.render_priority = 100
		_bone_materials.append(material)

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = _wireframe_mesh
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_instance, false, Node.INTERNAL_MODE_BACK)
		_bone_visuals.append(mesh_instance)

		var label: Label3D = Label3D.new()
		label.text = bone_name
		label.font_size = label_font_size
		label.modulate = label_color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 101
		label.visible = show_labels
		add_child(label, false, Node.INTERNAL_MODE_BACK)
		_bone_labels.append(label)

	_update_visibility()
	print("SkeletonVisualizer: Created ", _bone_visuals.size(), " visuals")


func _clear_visuals() -> void:
	for visual in _bone_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	_bone_visuals.clear()
	_bone_materials.clear()

	for label in _bone_labels:
		if is_instance_valid(label):
			label.queue_free()
	_bone_labels.clear()


func _create_wireframe_sphere_mesh(radius: float, segments: int) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array()

	for plane in range(3):
		for i in range(segments):
			var angle1: float = (float(i) / segments) * TAU
			var angle2: float = (float(i + 1) / segments) * TAU

			var p1: Vector3
			var p2: Vector3

			match plane:
				0:
					p1 = Vector3(cos(angle1) * radius, sin(angle1) * radius, 0)
					p2 = Vector3(cos(angle2) * radius, sin(angle2) * radius, 0)
				1:
					p1 = Vector3(cos(angle1) * radius, 0, sin(angle1) * radius)
					p2 = Vector3(cos(angle2) * radius, 0, sin(angle2) * radius)
				2:
					p1 = Vector3(0, cos(angle1) * radius, sin(angle1) * radius)
					p2 = Vector3(0, cos(angle2) * radius, sin(angle2) * radius)

			vertices.append(p1)
			vertices.append(p2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _process(_delta: float) -> void:
	if not debug_draw_enabled:
		return

	var bone_count: int = get_bone_count()
	for i in range(bone_count):
		if i >= _bone_visuals.size() or i >= _bone_labels.size():
			break

		var bone_global_pose: Transform3D = global_transform * get_bone_global_pose(i)
		var bone_origin: Vector3 = bone_global_pose.origin

		if is_instance_valid(_bone_visuals[i]):
			_bone_visuals[i].global_position = bone_origin

		if is_instance_valid(_bone_labels[i]):
			_bone_labels[i].global_position = bone_origin + Vector3(0, sphere_radius * 1.5, 0)


func _update_visibility() -> void:
	for visual in _bone_visuals:
		if is_instance_valid(visual):
			visual.visible = debug_draw_enabled
	_update_label_visibility()


func _update_label_visibility() -> void:
	for label in _bone_labels:
		if is_instance_valid(label):
			label.visible = debug_draw_enabled and show_labels


func _update_materials() -> void:
	var bone_count: int = get_bone_count()
	var count: int = min(_bone_materials.size(), bone_count)
	for i in range(count):
		var material: StandardMaterial3D = _bone_materials[i]
		if is_instance_valid(material):
			material.albedo_color = _color_for_bone(i, bone_count)


func _update_label_colors() -> void:
	for label in _bone_labels:
		if is_instance_valid(label):
			label.modulate = label_color


func _update_label_sizes() -> void:
	for label in _bone_labels:
		if is_instance_valid(label):
			label.font_size = label_font_size


func _rebuild_visuals() -> void:
	if is_inside_tree():
		_create_visuals()


func _color_for_bone(index: int, bone_count: int) -> Color:
	var count: int = max(1, bone_count)
	var base_hue: float = sphere_color.h
	var hue: float = fmod(base_hue + float(index) / float(count), 1.0)
	var saturation: float = max(0.2, sphere_color.s)
	var value: float = max(0.2, sphere_color.v)
	var color: Color = Color.from_hsv(hue, saturation, value)
	color.a = sphere_color.a
	return color
