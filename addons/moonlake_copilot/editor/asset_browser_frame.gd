@tool
extends VBoxContainer
class_name AssetBrowserFrame

const AssetPreviewCell = preload("res://addons/moonlake_copilot/editor/asset_preview_cell.gd")

signal asset_selected(glb_path: String)

var search_input: LineEdit
var refresh_button: Button
var scroll_container: ScrollContainer
var grid_container: GridContainer
var empty_label: Label

var all_glb_files: Array[String] = []
var current_filter: String = ""
var base_cell_size: Vector2 = Vector2(200, 240)
var single_click_mode: bool = false
var show_overlay_buttons: bool = true

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	_build_ui()
	refresh_assets()

func _get_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0

func _build_ui() -> void:
	var scale = _get_scale()

	# Toolbar
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_theme_constant_override("separation", int(8 * scale))
	add_child(toolbar)

	# Search input
	search_input = LineEdit.new()
	search_input.placeholder_text = "Search assets..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size.y = int(28 * scale)
	search_input.text_changed.connect(_on_search_changed)
	toolbar.add_child(search_input)

	# Refresh button
	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.custom_minimum_size = Vector2(int(80 * scale), int(28 * scale))
	refresh_button.pressed.connect(_on_refresh_pressed)
	toolbar.add_child(refresh_button)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size.y = int(8 * scale)
	add_child(spacer)

	# Scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_container)

	# Margin container for grid padding
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var padding = int(16 * scale)
	margin.add_theme_constant_override("margin_left", padding)
	margin.add_theme_constant_override("margin_right", padding)
	margin.add_theme_constant_override("margin_top", int(8 * scale))
	margin.add_theme_constant_override("margin_bottom", int(8 * scale))
	scroll_container.add_child(margin)

	# Grid container
	grid_container = GridContainer.new()
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.columns = 4
	grid_container.add_theme_constant_override("h_separation", int(12 * scale))
	grid_container.add_theme_constant_override("v_separation", int(12 * scale))
	margin.add_child(grid_container)

	# Empty state label (hidden initially)
	empty_label = Label.new()
	empty_label.text = "No assets found"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label.visible = false
	add_child(empty_label)

func set_base_cell_size(size: Vector2) -> void:
	base_cell_size = size
	_rebuild_grid()

func _on_search_changed(text: String) -> void:
	current_filter = text.to_lower()
	_rebuild_grid()

func _on_refresh_pressed() -> void:
	refresh_assets()

func refresh_assets() -> void:
	all_glb_files.clear()
	_scan_directory_recursive("res://", all_glb_files)
	_rebuild_grid()

func _scan_directory_recursive(path: String, results: Array[String]) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var full_path = path.path_join(file_name)

		if dir.current_is_dir():
			if file_name != "addons":
				_scan_directory_recursive(full_path, results)
		elif file_name.ends_with(".glb"):
			results.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()

func _rebuild_grid() -> void:
	if not grid_container:
		return

	var scale = _get_scale()

	# Clear existing children
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()

	# Filter assets
	var filtered: Array[String] = []
	for glb_path in all_glb_files:
		if current_filter.is_empty() or glb_path.get_file().to_lower().contains(current_filter):
			filtered.append(glb_path)

	# Show empty state if no results
	if filtered.is_empty():
		empty_label.visible = true
		empty_label.text = "No assets found" if current_filter.is_empty() else "No matching assets"
		scroll_container.visible = false
		return

	empty_label.visible = false
	scroll_container.visible = true

	# Create cells with scaled size
	var scaled_cell_size = base_cell_size * scale
	for glb_path in filtered:
		var cell = AssetPreviewCell.new()
		cell.set_cell_size(scaled_cell_size)
		cell.single_click_mode = single_click_mode
		cell.show_overlay_buttons = show_overlay_buttons
		cell.initialize(glb_path)
		cell.clicked.connect(_on_cell_clicked.bind(glb_path))
		grid_container.add_child(cell)

func _on_cell_clicked(glb_path: String) -> void:
	asset_selected.emit(glb_path)
