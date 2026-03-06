# Copyright © 2025 Cory Petkovsek, Roope Palmroos, and Contributors.
# Importer for Terrain3D
@tool
extends Terrain3D

const SHADER_PATH: String = "res://addons/moonlake_copilot/templates/shaders/terrain.gdshader"
const CANVAS_SIZE: int = 256

@export_group("Utilities")
@export var runtime_foliage_scenes: Array[PackedScene] = []
@export var runtime_foliage_names: Array[String] = []
@export var runtime_foliage_ids: Array[int] = []
@export_tool_button("Clear All") var clear_all = reset_settings
@export_tool_button("Clear Terrain") var clear_terrain = reset_terrain
@export_tool_button("Update Height Range") var update_height_range = update_heights


func reset_settings() -> void:
	height_file_name = ""
	control_file_name = ""
	color_file_name = ""
	destination_directory = ""
	material = null
	assets = null
	reset_terrain()


func reset_terrain() -> void:
	data_directory = ""
	for region:Terrain3DRegion in data.get_regions_active():
		data.remove_region(region, false)
	data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)


## Recalculates min and max heights for all regions.
func update_heights() -> void:
	if data:
		data.calc_height_range(true)


@export_group("Import File")
## EXR or R16 are recommended for heightmaps. 16-bit PNGs are down sampled to 8-bit and not recommended.
@export_global_file var height_file_name: String = ""
## Only use EXR files in our proprietary format.
@export_global_file var control_file_name: String = ""
## Any RGB or RGBA format is fine; PNG or Webp are recommended. Can be different dimensions than height map.
@export_global_file var color_file_name: String = ""
@export_tool_button("Run Import") var run_import = start_import

@export_dir var destination_directory: String = ""
@export_tool_button("Save to Disk") var save_to_disk = save_data


func start_import() -> void:
	print("Terrain3DImporter: Importing files:\n\t%s\n\t%s\n\t%s" % [ height_file_name, control_file_name, color_file_name])
	var imported_images: Array[Image]
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	var min_max := Vector2(0, 1)
	var target_size := Vector2i.ZERO
	var img: Image
	var high_res_color_img: Image = null
	material.world_background = 0
	material.shader_override_enabled = true
	if ResourceLoader.exists(SHADER_PATH):
		material.shader_override = load(SHADER_PATH)
	else:
		push_error("Shader not found at: ", SHADER_PATH)
	region_size = CANVAS_SIZE / 2
	
	# Load height map first to establish target size
	if height_file_name:
		img = Terrain3DUtil.load_image(height_file_name, ResourceLoader.CACHE_MODE_IGNORE, Vector2(0, 1), Vector2i(1024, 1024))
		min_max = Terrain3DUtil.get_min_max(img)
		target_size = img.get_size()
		imported_images[Terrain3DRegion.TYPE_HEIGHT] = img
		print("Height map size: ", target_size)
		
	if control_file_name:
		img = Terrain3DUtil.load_image(control_file_name, ResourceLoader.CACHE_MODE_IGNORE)
		# Resize if needed to match height map
		if target_size != Vector2i.ZERO and img.get_size() != target_size:
			print("Resizing control map from ", img.get_size(), " to ", target_size)
			img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		imported_images[Terrain3DRegion.TYPE_CONTROL] = img
			
	# Handle regular color map (if no high-res or in addition to high-res)
	if color_file_name:
		img = Terrain3DUtil.load_image(color_file_name, ResourceLoader.CACHE_MODE_IGNORE)
		# var high_res_texture = ImageTexture.create_from_image(img)
		var high_res_texture = load(color_file_name)
		print("high_res_texture_size", high_res_texture.to_string())
		# Resize if needed to match height map
		if target_size != Vector2i.ZERO and img.get_size() != target_size:
			print("Resizing color map from ", img.get_size(), " to ", target_size)
			img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		imported_images[Terrain3DRegion.TYPE_COLOR] = img
		material.set_shader_param("high_res_color_map", high_res_texture)
		material.set_shader_param("canvas_size", CANVAS_SIZE)

	var import_position = Vector2i(-CANVAS_SIZE / 2, -CANVAS_SIZE / 2)
	var pos := Vector3(import_position.x * vertex_spacing, 0, import_position.y * vertex_spacing)
	data.import_images(imported_images, pos, 0.0, 1.0)
	print("Terrain3DImporter: Import finished")


func save_data() -> void:
	if destination_directory.is_empty():
		push_error("Set destination directory first")
		return
	data.save_directory(destination_directory)


@export_group("Export File")
enum { TYPE_HEIGHT, TYPE_CONTROL, TYPE_COLOR }
@export_enum("Height:0", "Control:1", "Color:2") var map_type: int = TYPE_HEIGHT
@export var file_name_out: String = ""
@export_tool_button("Run Export") var run_export = start_export

func start_export() -> void:
	var err: int = data.export_image(file_name_out, map_type)
	print("Terrain3DImporter: Export error status: ", err, " ", error_string(err))

# Load assets at runtime
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_assets_runtime()

func _ensure_assets_runtime() -> void:
	if assets != null and assets.mesh_list.size() > 0:
		if runtime_foliage_scenes.is_empty():
			return
		if assets.mesh_list.size() >= runtime_foliage_scenes.size():
			return

	# No data to fill (to avoid filling randomly)
	if runtime_foliage_scenes.is_empty():
		return

	var a := Terrain3DAssets.new()
	var list: Array[Terrain3DMeshAsset] = []

	for i in range(runtime_foliage_scenes.size()):
		var m := Terrain3DMeshAsset.new()
		m.id = (runtime_foliage_ids[i] if i < runtime_foliage_ids.size() else i)
		m.name = (runtime_foliage_names[i] if i < runtime_foliage_names.size() else "mesh_%d" % m.id)
		m.scene_file = runtime_foliage_scenes[i]
		list.append(m)

	a.mesh_list = list
	assets = a
