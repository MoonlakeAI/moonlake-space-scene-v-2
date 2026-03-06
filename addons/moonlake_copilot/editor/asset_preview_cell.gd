@tool
extends VBoxContainer
class_name AssetPreviewCell

signal clicked

var glb_path: String = ""
var preview_container: Control
var preview_panel: Panel
var preview_image: TextureRect
var filename_label: Label
var loading_label: Label
var show_button: Button
var zoom_button: Button
var normal_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var single_click_mode: bool = false
var show_overlay_buttons: bool = true

func _get_scale() -> float:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_scale()
	return 1.0

func _init() -> void:
	var scale = _get_scale()
	custom_minimum_size = Vector2(200, 240) * scale
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_cell_size(size: Vector2) -> void:
	custom_minimum_size = size
	var scale = _get_scale()
	var panel_size = size.x
	var image_size = panel_size - int(8 * scale)
	if preview_container:
		preview_container.custom_minimum_size = Vector2(panel_size, panel_size)
	if preview_panel:
		preview_panel.size = Vector2(panel_size, panel_size)
	if preview_image:
		preview_image.custom_minimum_size = Vector2(image_size, image_size)

func _ready() -> void:
	_build_ui()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# Apply deferred initialization if path was set before _ready
	if not glb_path.is_empty() and filename_label:
		filename_label.text = glb_path.get_file()

func _build_ui() -> void:
	var scale = _get_scale()
	var panel_size = custom_minimum_size.x

	# Container for preview area (allows overlay positioning)
	preview_container = Control.new()
	preview_container.custom_minimum_size = Vector2(panel_size, panel_size)
	preview_container.mouse_filter = Control.MOUSE_FILTER_PASS
	preview_container.clip_contents = true
	add_child(preview_container)

	# Background panel
	preview_panel = Panel.new()
	preview_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Normal style
	normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.1, 0.1, 0.1)
	normal_style.border_width_left = int(2 * scale)
	normal_style.border_width_right = int(2 * scale)
	normal_style.border_width_top = int(2 * scale)
	normal_style.border_width_bottom = int(2 * scale)
	normal_style.border_color = Color(0.3, 0.3, 0.3)
	var corner_radius = int(8 * scale)
	normal_style.corner_radius_top_left = corner_radius
	normal_style.corner_radius_top_right = corner_radius
	normal_style.corner_radius_bottom_left = corner_radius
	normal_style.corner_radius_bottom_right = corner_radius
	normal_style.set_corner_detail(8)
	normal_style.anti_aliasing = true
	normal_style.anti_aliasing_size = 2.0

	# Hover style
	hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.15, 0.15, 0.15)
	hover_style.border_width_left = int(2 * scale)
	hover_style.border_width_right = int(2 * scale)
	hover_style.border_width_top = int(2 * scale)
	hover_style.border_width_bottom = int(2 * scale)
	hover_style.border_color = Color(0.5, 0.7, 1.0)
	hover_style.corner_radius_top_left = corner_radius
	hover_style.corner_radius_top_right = corner_radius
	hover_style.corner_radius_bottom_left = corner_radius
	hover_style.corner_radius_bottom_right = corner_radius
	hover_style.set_corner_detail(8)
	hover_style.anti_aliasing = true
	hover_style.anti_aliasing_size = 2.0

	preview_panel.add_theme_stylebox_override("panel", normal_style)
	preview_container.add_child(preview_panel)

	# Center container for image
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_container.add_child(center)

	# Loading indicator
	loading_label = Label.new()
	loading_label.text = "Loading..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(loading_label)

	# Preview image (slightly smaller to fit within border)
	preview_image = TextureRect.new()
	preview_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var image_size = panel_size - int(8 * scale)
	preview_image.custom_minimum_size = Vector2(image_size, image_size)
	preview_image.visible = false
	center.add_child(preview_image)

	# Show in FileSystem button (overlaid in bottom-right)
	show_button = Button.new()
	show_button.tooltip_text = "Show in FileSystem"
	var btn_size = int(26 * scale)
	var btn_margin = int(8 * scale)
	show_button.custom_minimum_size = Vector2(btn_size, btn_size)
	show_button.size = Vector2(btn_size, btn_size)
	show_button.position = Vector2(panel_size - btn_size - btn_margin, panel_size - btn_size - btn_margin)
	show_button.pressed.connect(_on_show_in_files_pressed)
	show_button.mouse_filter = Control.MOUSE_FILTER_STOP

	# Style the button with semi-transparent background
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	btn_style.corner_radius_top_left = int(4 * scale)
	btn_style.corner_radius_top_right = int(4 * scale)
	btn_style.corner_radius_bottom_left = int(4 * scale)
	btn_style.corner_radius_bottom_right = int(4 * scale)
	show_button.add_theme_stylebox_override("normal", btn_style)
	show_button.add_theme_stylebox_override("hover", btn_style)
	show_button.add_theme_stylebox_override("pressed", btn_style)

	preview_container.add_child(show_button)

	# Zoom button (next to show button)
	zoom_button = Button.new()
	zoom_button.tooltip_text = "Open Preview"
	zoom_button.custom_minimum_size = Vector2(btn_size, btn_size)
	zoom_button.size = Vector2(btn_size, btn_size)
	zoom_button.position = Vector2(panel_size - (btn_size * 2) - btn_margin - int(4 * scale), panel_size - btn_size - btn_margin)
	zoom_button.pressed.connect(_on_zoom_pressed)
	zoom_button.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_button.add_theme_stylebox_override("normal", btn_style)
	zoom_button.add_theme_stylebox_override("hover", btn_style)
	zoom_button.add_theme_stylebox_override("pressed", btn_style)
	preview_container.add_child(zoom_button)

	# Set icons after fully in tree
	call_deferred("_setup_buttons")

	# Filename label
	filename_label = Label.new()
	filename_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	filename_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	filename_label.add_theme_font_size_override("font_size", int(13 * scale))
	add_child(filename_label)

func _setup_buttons() -> void:
	if not Engine.is_editor_hint():
		return
	var theme = EditorInterface.get_editor_theme()
	if not theme:
		return
	# Setup show button
	if show_button:
		if not show_overlay_buttons:
			show_button.visible = false
		else:
			var fs_icon = theme.get_icon("Filesystem", "EditorIcons")
			if fs_icon:
				show_button.icon = fs_icon
	# Setup zoom button
	if zoom_button:
		if not show_overlay_buttons:
			zoom_button.visible = false
		else:
			var zoom_icon = theme.get_icon("Search", "EditorIcons")
			if zoom_icon:
				zoom_button.icon = zoom_icon

func _on_mouse_entered() -> void:
	if preview_panel:
		preview_panel.add_theme_stylebox_override("panel", hover_style)

func _on_mouse_exited() -> void:
	if preview_panel:
		preview_panel.add_theme_stylebox_override("panel", normal_style)

func _on_show_in_files_pressed() -> void:
	if Engine.is_editor_hint() and not glb_path.is_empty():
		# Disable distraction free mode if enabled so FileSystem dock is visible
		if EditorInterface.is_distraction_free_mode_enabled():
			EditorInterface.set_distraction_free_mode(false)
		EditorInterface.get_file_system_dock().navigate_to_path(glb_path)

func _on_zoom_pressed() -> void:
	clicked.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if single_click_mode and mb.pressed:
				clicked.emit()
				accept_event()
			elif not single_click_mode and mb.double_click:
				clicked.emit()
				accept_event()

func initialize(path: String) -> void:
	glb_path = path
	if filename_label:
		filename_label.text = path.get_file()
	call_deferred("_render_preview")

func _render_preview() -> void:
	var glb_scene = ResourceLoader.load(glb_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not glb_scene:
		loading_label.text = "Failed to load"
		return

	var scene_instance = glb_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if not scene_instance:
		loading_label.text = "Invalid GLB"
		return

	var sub_viewport = SubViewport.new()
	sub_viewport.name = "Preview_" + str(get_instance_id())
	sub_viewport.size = Vector2i(512, 512)
	sub_viewport.transparent_bg = false
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub_viewport.own_world_3d = true

	var aabb = _get_scene_aabb(scene_instance)
	var camera_pos = _calculate_camera_position(aabb)
	var look_at_pos = aabb.get_center()

	var camera = Camera3D.new()
	camera.position = camera_pos
	camera.fov = 65.0
	camera.near = 0.1
	camera.far = 1000.0
	sub_viewport.add_child(camera)

	var world_env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.1, 0.1, 0.1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 1, 1)
	environment.ambient_light_energy = 0.5
	world_env.environment = environment
	sub_viewport.add_child(world_env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	sub_viewport.add_child(sun)

	sub_viewport.add_child(scene_instance)

	var root = get_tree().root
	root.add_child(sub_viewport)
	camera.look_at(look_at_pos, Vector3.UP)

	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img = sub_viewport.get_texture().get_image()

	root.remove_child(sub_viewport)
	sub_viewport.queue_free()

	if img:
		var texture = ImageTexture.create_from_image(img)
		preview_image.texture = texture
		preview_image.visible = true
		loading_label.visible = false
	else:
		loading_label.text = "Render failed"

func _get_scene_aabb(node: Node) -> AABB:
	var combined = AABB()
	var first = true

	for child in _get_all_children(node):
		if child is MeshInstance3D:
			var mesh_instance = child as MeshInstance3D
			var mesh_aabb = mesh_instance.get_aabb()
			var global_aabb = mesh_aabb.abs()
			global_aabb.position = mesh_instance.position + mesh_aabb.position

			if first:
				combined = global_aabb
				first = false
			else:
				combined = combined.merge(global_aabb)

	if first:
		combined = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

	return combined

func _get_all_children(node: Node) -> Array:
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(_get_all_children(child))
	return children

func _calculate_camera_position(aabb: AABB) -> Vector3:
	var center = aabb.get_center()
	var size = aabb.size
	var max_dimension = max(size.x, max(size.y, size.z))

	var distance = max_dimension * 1.2
	var height_offset = size.y * 0.1

	return center + Vector3(0, height_offset, distance)
