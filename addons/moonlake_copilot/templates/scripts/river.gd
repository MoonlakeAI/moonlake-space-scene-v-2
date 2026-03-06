@tool
extends MeshInstance3D

@export var river_polylines: Array = [
	{"center":[-18,   0], "left":[-38,   0], "right":[2,    0], "water_surface_height":1.2},
	{"center":[-10,  45], "left":[-30,  45], "right":[10,  45], "water_surface_height":1.2},
	{"center":[0,   90],  "left":[-20,  90], "right":[20,  90], "water_surface_height":1.2},
	{"center":[10, 135],  "left":[-10, 135], "right":[30, 135], "water_surface_height":1.2},
	{"center":[18, 180],  "left":[-2,  180], "right":[38, 180], "water_surface_height":1.2},
]
@export var double_sided: bool = true

# 讓你在 Inspector 改資料就自動更新
func _ready() -> void:
	_rebuild_if_possible()

func _notification(what: int) -> void:
	# 在 editor 中，屬性變動/重載時也會走到這裡
	if Engine.is_editor_hint():
		if what == NOTIFICATION_ENTER_TREE:
			_rebuild_if_possible()

func _set(property: StringName, value) -> bool:
	# 任何 export 欄位被改動，都觸發重建（@tool 下很實用）
	var handled := false
	if property == &"river_polylines":
		river_polylines = value
		handled = true
	elif property == &"double_sided":
		double_sided = value
		handled = true

	if handled and Engine.is_editor_hint():
		call_deferred("_rebuild_if_possible")
	return handled

func _rebuild_if_possible() -> void:
	if river_polylines.size() >= 2:
		rebuild(river_polylines)

func rebuild(data: Array) -> void:
	if data.size() < 2:
		push_error("river_array_mesh.gd: river_polylines must have at least 2 points")
		return

	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var n := data.size()

	for i in range(n):
		var p = data[i]
		if typeof(p) != TYPE_DICTIONARY:
			push_error("river_array_mesh.gd: each item must be a Dictionary")
			return

		var y: float = float(p.get("water_surface_height", 0.0))
		var left_arr: Array = p.get("left", [0.0, 0.0])
		var center_arr: Array = p.get("center", [0.0, 0.0])
		var right_arr: Array = p.get("right", [0.0, 0.0])

		var v := float(i) / float(max(1, n - 1))

		positions.append(Vector3(float(left_arr[0]), y, float(left_arr[1])))
		uvs.append(Vector2(0.0, v))

		positions.append(Vector3(float(center_arr[0]), y, float(center_arr[1])))
		uvs.append(Vector2(0.5, v))

		positions.append(Vector3(float(right_arr[0]), y, float(right_arr[1])))
		uvs.append(Vector2(1.0, v))

	for i in range(n - 1):
		var i0_left := i * 3
		var i0_center := i * 3 + 1
		var i0_right := i * 3 + 2
		var i1_left := (i + 1) * 3
		var i1_center := (i + 1) * 3 + 1
		var i1_right := (i + 1) * 3 + 2

		indices.append(i0_left);   indices.append(i0_center); indices.append(i1_left)
		indices.append(i0_center); indices.append(i1_center); indices.append(i1_left)
		indices.append(i0_center); indices.append(i0_right);  indices.append(i1_center)
		indices.append(i0_right);  indices.append(i1_right);  indices.append(i1_center)

	# --- Provide normals + tangents explicitly (most reliable) ---
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for vi in range(positions.size()):
		normals[vi] = Vector3.UP

	# Godot tangent format: 4 floats per vertex (x,y,z,w)
	# Use a constant tangent along +X with w=1.
	var tangents := PackedFloat32Array()
	tangents.resize(positions.size() * 4)
	for vi in range(positions.size()):
		var base := vi * 4
		tangents[base + 0] = 1.0
		tangents[base + 1] = 0.0
		tangents[base + 2] = 0.0
		tangents[base + 3] = 1.0

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = am

	# Verify: print whether tangents exist
	var s_arrays := am.surface_get_arrays(0)
	var has_tangent := s_arrays.size() > Mesh.ARRAY_TANGENT and s_arrays[Mesh.ARRAY_TANGENT] != null
