extends VBoxContainer

## ImageGalleryRenderer - Reusable image gallery component
## Displays images in a 2-column grid with automatic loading

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")

var gallery: GridContainer
var sender: String = "copilot"  # Default to copilot
var selection_mode: bool = false  # If true, clicking selects instead of opening URL
var selection_callback: Callable  # Called with (index: int) when image selected
var selected_index: int = -1  # Currently selected image index
var is_disabled: bool = false  # If true, clicks are ignored

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func load_images(image_urls: Array, message_sender: String = "copilot", enable_selection: bool = false, on_selected: Callable = Callable(), disabled: bool = false) -> void:
	"""Load and display images in gallery

	Args:
		image_urls: Array of image URLs to load
		message_sender: "user" or "copilot" for alignment
		enable_selection: If true, clicking selects image instead of opening URL
		on_selected: Callback function(index: int) called when image selected
		disabled: If true, images are not clickable
	"""
	sender = message_sender
	selection_mode = enable_selection
	selection_callback = on_selected
	is_disabled = disabled
	call_deferred("_load_images_deferred", image_urls)

func _load_images_deferred(images: Array) -> void:
	"""Load images after widget is in scene tree"""
	# Known image services that don't use file extensions
	const IMAGE_SERVICES = ["picsum.photos", "imgur.com", "i.imgur.com"]

	# Filter valid image URLs
	var valid_images = []
	for image_url in images:
		if typeof(image_url) != TYPE_STRING or image_url.is_empty():
			continue

		var lower_url = image_url.to_lower()
		var url_path = lower_url
		var query_index = url_path.find("?")
		if query_index != -1:
			url_path = url_path.substr(0, query_index)

		# Check if URL ends with image extension
		var has_extension = url_path.ends_with(".png") or url_path.ends_with(".jpg") or \
		                    url_path.ends_with(".jpeg") or url_path.ends_with(".webp")

		# Check if URL is from known image service
		var is_image_service = false
		for service in IMAGE_SERVICES:
			if service in url_path:
				is_image_service = true
				break

		if has_extension or is_image_service:
			valid_images.append(image_url)

	if valid_images.is_empty():
		return

	gallery = GridContainer.new()
	gallery.columns = 5  # 5 images per row
	gallery.add_theme_constant_override("h_separation", int(ThemeConstants.spacing(8)))
	gallery.add_theme_constant_override("v_separation", int(ThemeConstants.spacing(8)))

	# Align based on sender: user messages on right, copilot on left
	if sender == "user":
		gallery.size_flags_horizontal = Control.SIZE_SHRINK_END  # Right-aligned for user
	else:
		gallery.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # Left-aligned for copilot

	add_child(gallery)

	var http_pool = _ensure_http_pool()

	# Load each image
	for i in range(valid_images.size()):
		var image_url = valid_images[i]

		var panel = PanelContainer.new()
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.9, 0.9, 0.9, 1.0)  # Dull white background
		panel_style.set_corner_radius_all(int(ThemeConstants.spacing(12)))
		panel_style.anti_aliasing = true
		panel_style.content_margin_left = int(ThemeConstants.spacing(8))
		panel_style.content_margin_right = int(ThemeConstants.spacing(8))
		panel_style.content_margin_top = int(ThemeConstants.spacing(8))
		panel_style.content_margin_bottom = int(ThemeConstants.spacing(8))
		panel.add_theme_stylebox_override("panel", panel_style)
		panel.custom_minimum_size = Vector2(int(ThemeConstants.spacing(180)), int(ThemeConstants.spacing(180)))
		panel.set_meta("image_index", i)  # Store index for selection
		panel.set_meta("normal_style", panel_style)  # Store for hover restoration
		gallery.add_child(panel)

		var texture_rect = TextureRect.new()
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# Only allow mouse events if not disabled
		if not is_disabled:
			texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # Allow mouse events
			texture_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND  # Show hand cursor
			panel.set_meta("texture_rect", texture_rect)  # Store for hover effects

			texture_rect.mouse_entered.connect(func() -> void:
				_on_image_hover(panel, true)
			)
			texture_rect.mouse_exited.connect(func() -> void:
				_on_image_hover(panel, false)
			)

			if selection_mode:
				# Selection mode: call callback with index
				texture_rect.gui_input.connect(func(event: InputEvent) -> void:
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
						_on_image_selected(i, panel)
				)
			else:
				# Default mode: open URL in browser
				texture_rect.gui_input.connect(func(event: InputEvent) -> void:
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
						OS.shell_open(image_url)
				)
		else:
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		panel.add_child(texture_rect)

		var spinner = Label.new()
		spinner.text = "Loading..."
		spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spinner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var editor_scale = EditorInterface.get_editor_scale()
		var spinner_size = int(ThemeConstants.Typography.FONT_SIZE_LARGE * 2 * editor_scale)
		spinner.add_theme_font_size_override("font_size", spinner_size)
		spinner.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		spinner.anchor_left = 0.0
		spinner.anchor_top = 0.0
		spinner.anchor_right = 1.0
		spinner.anchor_bottom = 1.0
		spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(spinner)
		panel.set_meta("loading_spinner", spinner)

		# Fetch image using pool
		if http_pool and image_url.begins_with("http"):
			http_pool.fetch(image_url, func(result: int, response_code: int, headers: Array, body: PackedByteArray) -> void:
				_on_image_loaded_rect(texture_rect, panel, image_url, result, response_code, headers, body)
			)

func _ensure_http_pool() -> Node:
	"""Get or create HTTPRequestPool singleton"""
	var root = get_tree().root if get_tree() else null
	if root:
		for child in root.get_children():
			if child.name == "HTTPRequestPool":
				return child

	var http_pool = load("res://addons/moonlake_copilot/http/http_request_pool.gd").new()
	http_pool.name = "HTTPRequestPool"
	if root:
		root.add_child(http_pool)
	return http_pool

func _on_image_hover(panel: PanelContainer, is_hovering: bool) -> void:
	"""Handle image hover effects"""
	var image_index = panel.get_meta("image_index", -1)
	var normal_style = panel.get_meta("normal_style", null)
	if not normal_style:
		return

	if is_hovering:
		var hover_style = normal_style.duplicate()
		if selection_mode:
			# Selection mode: light blue border
			hover_style.border_width_left = 3
			hover_style.border_width_right = 3
			hover_style.border_width_top = 3
			hover_style.border_width_bottom = 3
			hover_style.border_color = Color(0.5, 0.7, 1.0, 1.0)
		else:
			# Normal mode: slight brightness increase
			hover_style.bg_color = Color(0.95, 0.95, 0.95, 1.0)
		panel.add_theme_stylebox_override("panel", hover_style)
	else:
		# Restore normal or selected style
		if image_index == selected_index:
			_apply_selected_style(panel)
		else:
			panel.add_theme_stylebox_override("panel", normal_style)

func _on_image_selected(index: int, panel: PanelContainer) -> void:
	"""Handle image selection"""
	if not selection_mode:
		return

	# Clear previous selection
	if selected_index >= 0 and gallery:
		var prev_panel = gallery.get_child(selected_index) if selected_index < gallery.get_child_count() else null
		if prev_panel:
			var normal_style = prev_panel.get_meta("normal_style", null)
			if normal_style:
				prev_panel.add_theme_stylebox_override("panel", normal_style)

	selected_index = index
	_apply_selected_style(panel)

	# Call callback
	if selection_callback.is_valid():
		selection_callback.call(index)

func _apply_selected_style(panel: PanelContainer) -> void:
	"""Apply selected style to panel"""
	var normal_style = panel.get_meta("normal_style", null)
	if not normal_style:
		return

	var selected_style = normal_style.duplicate()
	selected_style.border_width_left = 4
	selected_style.border_width_right = 4
	selected_style.border_width_top = 4
	selected_style.border_width_bottom = 4
	selected_style.border_color = Color(0.3, 0.5, 0.8, 1.0)  # Blue highlight
	selected_style.bg_color = Color(0.85, 0.9, 1.0, 1.0)  # Light blue background
	panel.add_theme_stylebox_override("panel", selected_style)

func set_selected_index(index: int) -> void:
	"""Set the selected image index (for restore)"""
	selected_index = index
	if gallery and index >= 0 and index < gallery.get_child_count():
		var panel = gallery.get_child(index)
		_apply_selected_style(panel)

func disable_interaction() -> void:
	"""Disable all mouse interaction with images"""
	is_disabled = true
	if not gallery:
		return

	# Disable mouse interaction on all texture rects
	for i in range(gallery.get_child_count()):
		var panel = gallery.get_child(i)
		var texture_rect = panel.get_meta("texture_rect", null)
		if texture_rect:
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			texture_rect.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_image_loaded_button(
	button: TextureButton,
	url: String,
	result: int,
	response_code: int,
	headers: Array,
	body: PackedByteArray
) -> void:
	"""Handle image load completion for TextureButton"""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		# Button will just show the background style
		return

	var image = Image.new()
	var error = ERR_FILE_UNRECOGNIZED

	var url_lower = url.to_lower()
	var url_path = url_lower
	var query_index = url_path.find("?")
	if query_index != -1:
		url_path = url_path.substr(0, query_index)

	if url_path.ends_with(".jpg") or url_path.ends_with(".jpeg"):
		error = image.load_jpg_from_buffer(body)
	elif url_path.ends_with(".png"):
		error = image.load_png_from_buffer(body)
	elif url_path.ends_with(".webp"):
		error = image.load_webp_from_buffer(body)
	else:
		# Fallback: try Content-Type header then all formats
		var content_type = ""
		for header in headers:
			var header_str = header as String
			if header_str.to_lower().begins_with("content-type:"):
				content_type = header_str.substr(13).strip_edges().to_lower()
				break

		if "jpeg" in content_type or "jpg" in content_type:
			error = image.load_jpg_from_buffer(body)
		elif "png" in content_type:
			error = image.load_png_from_buffer(body)
		elif "webp" in content_type:
			error = image.load_webp_from_buffer(body)
		else:
			# Last resort - try all formats
			error = image.load_jpg_from_buffer(body)
			if error != OK:
				error = image.load_png_from_buffer(body)
			if error != OK:
				error = image.load_webp_from_buffer(body)

	if error != OK:
		return

	var texture = ImageTexture.create_from_image(image)
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture

func _on_image_loaded_rect(
	texture_rect: TextureRect,
	panel: PanelContainer,
	url: String,
	result: int,
	response_code: int,
	headers: Array,
	body: PackedByteArray
) -> void:
	"""Handle image load completion for TextureRect with rounded corners"""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		Log.warn("[ImageGallery] Failed to load image: %s (result=%d, code=%d)" % [url, result, response_code])
		# Panel will just show the background style
		return

	var image = Image.new()
	var error = ERR_FILE_UNRECOGNIZED

	var url_lower = url.to_lower()
	var url_path = url_lower
	var query_index = url_path.find("?")
	if query_index != -1:
		url_path = url_path.substr(0, query_index)

	if url_path.ends_with(".jpg") or url_path.ends_with(".jpeg"):
		error = image.load_jpg_from_buffer(body)
	elif url_path.ends_with(".png"):
		error = image.load_png_from_buffer(body)
	elif url_path.ends_with(".webp"):
		error = image.load_webp_from_buffer(body)
	else:
		# Fallback: try Content-Type header then all formats
		var content_type = ""
		for header in headers:
			var header_str = header as String
			if header_str.to_lower().begins_with("content-type:"):
				content_type = header_str.substr(13).strip_edges().to_lower()
				break

		if "jpeg" in content_type or "jpg" in content_type:
			error = image.load_jpg_from_buffer(body)
		elif "png" in content_type:
			error = image.load_png_from_buffer(body)
		elif "webp" in content_type:
			error = image.load_webp_from_buffer(body)
		else:
			# Last resort - try all formats
			error = image.load_jpg_from_buffer(body)
			if error != OK:
				error = image.load_png_from_buffer(body)
			if error != OK:
				error = image.load_webp_from_buffer(body)

	if error != OK:
		Log.warn("[ImageGallery] Failed to parse image data: %s (error=%d, size=%d bytes)" % [url, error, body.size()])
		return

	var texture = ImageTexture.create_from_image(image)
	texture_rect.texture = texture

	# Remove loading spinner
	var spinner = panel.get_meta("loading_spinner", null)
	if spinner and is_instance_valid(spinner):
		spinner.queue_free()
		panel.remove_meta("loading_spinner")

	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float corner_radius = 12.0;

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 uv = UV * size;

	// Calculate distance from corners
	vec2 corner_dist = min(uv, size - uv);
	float dist = min(corner_dist.x, corner_dist.y);

	// Smooth edge for anti-aliasing
	float alpha = smoothstep(corner_radius - 1.0, corner_radius, dist);

	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a * alpha);
}
"""
	shader_material.shader = shader
	shader_material.set_shader_parameter("corner_radius", 12.0)
	texture_rect.material = shader_material

func _on_image_loaded(
	content_container: CenterContainer,
	loading_label: Label,
	url: String,
	result: int,
	response_code: int,
	headers: Array,
	body: PackedByteArray
) -> void:
	"""Handle image load completion"""
	loading_label.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		Log.warn("[ImageGallery] Failed to load image: %s (result=%d, code=%d)" % [url, result, response_code])
		var error_label = Label.new()
		error_label.text = "Failed"
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_container.add_child(error_label)
		return

	var image = Image.new()
	var error = ERR_FILE_UNRECOGNIZED

	var url_lower = url.to_lower()
	var url_path = url_lower
	var query_index = url_path.find("?")
	if query_index != -1:
		url_path = url_path.substr(0, query_index)

	if url_path.ends_with(".jpg") or url_path.ends_with(".jpeg"):
		error = image.load_jpg_from_buffer(body)
	elif url_path.ends_with(".png"):
		error = image.load_png_from_buffer(body)
	elif url_path.ends_with(".webp"):
		error = image.load_webp_from_buffer(body)
	else:
		# Fallback: try Content-Type header then all formats
		var content_type = ""
		for header in headers:
			var header_str = header as String
			if header_str.to_lower().begins_with("content-type:"):
				content_type = header_str.substr(13).strip_edges().to_lower()
				break

		if "jpeg" in content_type or "jpg" in content_type:
			error = image.load_jpg_from_buffer(body)
		elif "png" in content_type:
			error = image.load_png_from_buffer(body)
		elif "webp" in content_type:
			error = image.load_webp_from_buffer(body)
		else:
			# Last resort - try all formats
			error = image.load_jpg_from_buffer(body)
			if error != OK:
				error = image.load_png_from_buffer(body)
			if error != OK:
				error = image.load_webp_from_buffer(body)

	if error != OK:
		Log.warn("[ImageGallery] Failed to parse image data: %s (error=%d, size=%d bytes)" % [url, error, body.size()])
		var error_label = Label.new()
		error_label.text = "Invalid"
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content_container.add_child(error_label)
		return

	var texture = ImageTexture.create_from_image(image)
	var texture_rect = TextureRect.new()
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.custom_minimum_size = Vector2(int(ThemeConstants.spacing(190)), int(ThemeConstants.spacing(190)))  # Force minimum size
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float corner_radius = 12.0;

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 uv = UV * size;

	// Calculate distance from corners
	vec2 corner_dist = min(uv, size - uv);
	float dist = min(corner_dist.x, corner_dist.y);

	// Smooth edge for anti-aliasing
	float alpha = smoothstep(corner_radius - 1.0, corner_radius, dist);

	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a * alpha);
}
"""
	shader_material.shader = shader
	shader_material.set_shader_parameter("corner_radius", 12.0)
	texture_rect.material = shader_material

	content_container.add_child(texture_rect)
