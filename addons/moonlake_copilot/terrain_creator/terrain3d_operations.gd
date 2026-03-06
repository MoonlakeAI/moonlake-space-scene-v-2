@tool
extends RefCounted
class_name Terrain3DOperations

static func import_terrain_data(
	terrain_node,
	height_path: String = "",
	control_path: String = "",
	color_path: String = "",
	data_directory: String = "res://assets/terrain_data"
) -> void:
	"""Import Terrain3D data from downloaded files.

	Call this AFTER files have been imported by EditorFileSystem.
	"""
	# Set file paths
	if not height_path.is_empty():
		terrain_node.height_file_name = height_path
	if not control_path.is_empty():
		terrain_node.control_file_name = control_path
	if not color_path.is_empty():
		terrain_node.color_file_name = color_path

	# Run import
	terrain_node.start_import()

	# Save to disk
	if not DirAccess.dir_exists_absolute(data_directory):
		DirAccess.make_dir_recursive_absolute(data_directory)
	terrain_node.destination_directory = data_directory
	terrain_node.save_data()

	# Set data directory to load the terrain
	terrain_node.data_directory = data_directory

	Log.info("[TERRAIN3D] Import complete: %s" % data_directory)
