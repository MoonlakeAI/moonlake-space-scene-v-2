# TreeInstancerRuntime.gd
@tool
extends Node3D

@export var mesh_id: int = 0
@export var transforms: Array[Transform3D] = [
	Transform3D(
		Basis().scaled(Vector3(20.0, 2.0, 2.0)),
		Vector3(0.0, 5.0, 0.0)
	),
	Transform3D(
		Basis().rotated(Vector3.UP, deg_to_rad(45.0)).scaled(Vector3(1.1, 1.1, 1.1)),
		Vector3(5.0, 5.0, 8.0)
	),
	Transform3D(
		Basis().rotated(Vector3.UP, deg_to_rad(120.0)).scaled(Vector3(0.9, 0.9, 0.9)),
		Vector3(-6.0, 5.0, 10.0)
	)
]
@export var clear_before_add := false
@export var visibility_distance := 0.0 # 0=disable cull, else max visible distance

var _terrain_id: int = 0


func _ready() -> void:
	var terrain := get_terrain()
	if not terrain:
		push_error("Terrain3D not found")
		return

	if mesh_id < 0:
		push_error("mesh_id invalid (<0)")
		return

	if transforms.is_empty():
		return

	var inst := terrain.get_instancer()

	if clear_before_add:
		inst.clear_by_mesh(mesh_id)

	apply_visibility(terrain, mesh_id)
	inst.add_transforms(mesh_id, transforms, PackedColorArray(), true)
	inst.update_mmis(mesh_id)


func apply_visibility(terrain: Terrain3D, mid: int) -> void:
	var ma := terrain.assets.get_mesh_asset(mid)
	if ma == null:
		return

	var last_lod := ma.get_last_lod()

	var end := visibility_distance
	var fade := 0.0
	if end > 0.0:
		fade = end * 0.1   # hardcoded 10% fade-out

	if ma.has_method("set_fade_margin"):
		ma.set_fade_margin(fade)

	for lod in range(last_lod + 1):
		ma.set_lod_range(lod, end)

func get_terrain() -> Terrain3D:
	var terrain := instance_from_id(_terrain_id) as Terrain3D
	if terrain and terrain.is_inside_tree() and not terrain.is_queued_for_deletion():
		return terrain

	# runtime-safe lookup
	var terrains := get_tree().get_root().find_children("", "Terrain3D", true, false)
	if terrains.size() > 0:
		terrain = terrains[0] as Terrain3D
		_terrain_id = terrain.get_instance_id()
		return terrain

	return null


func print_mesh_id_table(terrain: Terrain3D) -> void:
	var assets := terrain.assets
	print("---- Terrain3D Asset Dock: Mesh ID Table ----")

	var count := assets.get_mesh_count()
	print("mesh_count =", count)

	for i in range(count):
		var asset := assets.get_mesh_asset(i)
		if asset == null:
			print("mesh_id =", i, " -> NULL")
		else:
			print("mesh_id =", i, " ->", asset.resource_name)
