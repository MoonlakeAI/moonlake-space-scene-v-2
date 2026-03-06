@tool
extends PanelContainer

## AttachmentChip
##
## A visual chip component for displaying attachments with name and remove button.
## Clickable to open file with OS default app, removable via X button.

signal clicked(attachment_data: Dictionary)
signal remove_requested(attachment_data: Dictionary)

var attachment_data: Dictionary = {}
var label: Button
var close_button: Button
var upload_progress: float = 0.0
var upload_timer: Timer


func _ready() -> void:
	# Use single baseline values - Godot handles DPI automatically
	var close_button_size = 20
	var close_button_font = 16
	var label_font_size = 20

	# Create HBoxContainer for label + close button
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN  # Left align contents
	add_child(hbox)

	# Button for attachment name (using Button so we can have icon property)
	label = Button.new()
	label.flat = true
	var dark_color = Color(0.2, 0.2, 0.2)
	label.add_theme_color_override("font_color", dark_color)
	label.add_theme_color_override("font_hover_color", dark_color)
	label.add_theme_color_override("font_pressed_color", dark_color)
	label.add_theme_color_override("font_focus_color", dark_color)
	label.add_theme_color_override("font_disabled_color", dark_color)
	label.add_theme_color_override("icon_normal_color", dark_color)
	label.add_theme_color_override("icon_hover_color", dark_color)
	label.add_theme_color_override("icon_pressed_color", dark_color)
	label.add_theme_color_override("icon_focus_color", dark_color)
	label.add_theme_color_override("icon_disabled_color", dark_color)
	label.add_theme_font_size_override("font_size", label_font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT  # Left align text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # Trim with ellipsis
	label.clip_text = true
	label.custom_minimum_size = Vector2(0, 0)  # Auto width
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.pressed.connect(_on_label_pressed)

	# Apply Inter font
	var ThemeConstants = load("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
	if ThemeConstants:
		ThemeConstants.apply_inter_font(label, label_font_size)

	hbox.add_child(label)

	# X button
	close_button = Button.new()
	close_button.text = "×"
	close_button.flat = true
	close_button.custom_minimum_size = Vector2(0,0)
	close_button.add_theme_font_size_override("font_size", close_button_font)
	close_button.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	close_button.add_theme_color_override("font_hover_color", Color(0.8, 0.2, 0.2))
	close_button.pressed.connect(_on_close_pressed)
	ThemeConstants.apply_inter_font(close_button, close_button_font)

	hbox.add_child(close_button)

	# Chip styling - rounded, light background
	# Will be updated based on upload status in _update_upload_status()
	_create_chip_style()

	# Hover style - slightly darker gray
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.95, 0.95, 0.95)
	hover_style.corner_radius_top_left = 16
	hover_style.corner_radius_top_right = 16
	hover_style.corner_radius_bottom_left = 16
	hover_style.corner_radius_bottom_right = 16
	hover_style.content_margin_left = 12
	hover_style.content_margin_right = 8
	hover_style.content_margin_top = 6
	hover_style.content_margin_bottom = 6
	hover_style.anti_aliasing = true
	hover_style.corner_detail = 8

	custom_minimum_size = Vector2(0, 40)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Create timer for progress animation
	upload_timer = Timer.new()
	upload_timer.wait_time = 0.1  # Update every 100ms
	upload_timer.timeout.connect(_on_progress_tick)
	add_child(upload_timer)

	# Set label text if attachment_data was set before _ready()
	if not attachment_data.is_empty():
		label.text = _format_attachment_name(attachment_data)
		if attachment_data.get("uploading", false):
			upload_timer.start()


func _get_attachment_icon(data: Dictionary) -> Texture2D:
	"""Get Godot icon for attachment type"""
	# Check type field first (more reliable)
	var file_type = data.get("type", "")
	if file_type == "image":
		return EditorInterface.get_editor_theme().get_icon("ImageTexture", "EditorIcons")
	elif file_type == "clipboard_text":
		return EditorInterface.get_editor_theme().get_icon("TextFile", "EditorIcons")
	else:
		# Fall back to extension detection
		var name = data.get("name", "")
		var extension = name.get_extension().to_lower()

		var image_extensions = ["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico", "tiff", "tif"]
		if extension in image_extensions:
			return EditorInterface.get_editor_theme().get_icon("ImageTexture", "EditorIcons")
		else:
			var text_extensions = ["txt", "md", "json"]
			if extension in text_extensions:
				return EditorInterface.get_editor_theme().get_icon("TextFile", "EditorIcons")

	return EditorInterface.get_editor_theme().get_icon("File", "EditorIcons")


func _format_attachment_name(data: Dictionary) -> String:
	"""Format attachment name with upload progress"""
	var type_name = "File"

	# Check type field first (more reliable)
	var file_type = data.get("type", "")
	if file_type == "image":
		type_name = "Image"
	elif file_type == "clipboard_text":
		type_name = "Text"
	else:
		# Fall back to extension detection
		var name = data.get("name", "")
		var extension = name.get_extension().to_lower()

		var image_extensions = ["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico", "tiff", "tif"]
		if extension in image_extensions:
			type_name = "Image"
		else:
			var text_extensions = ["txt", "md", "json"]
			if extension in text_extensions:
				type_name = "Text"

	var index = data.get("index", 1)
	var is_uploading = data.get("uploading", false)
	if is_uploading:
		var percentage = int(upload_progress)
		return "%d%% | %s %d" % [percentage, type_name, index]
	else:
		return "%s %d" % [type_name, index]


func initialize(data: Dictionary) -> void:
	"""Initialize chip with attachment data"""
	attachment_data = data
	if label:
		label.icon = _get_attachment_icon(data)
		label.text = _format_attachment_name(data)
		# Force update
		label.queue_redraw()
	_update_upload_status()


func _create_chip_style() -> void:
	"""Create chip background style based on upload status"""
	var style = StyleBoxFlat.new()

	# White background, slightly dimmer during upload
	var is_uploading = attachment_data.get("uploading", false)
	if is_uploading:
		style.bg_color = Color(0.95, 0.95, 0.95, 1.0)  # Light gray during upload
	else:
		style.bg_color = Color(1.0, 1.0, 1.0, 1.0)  # White when done

	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 16
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.anti_aliasing = true
	style.corner_detail = 8
	add_theme_stylebox_override("panel", style)


func _on_progress_tick() -> void:
	"""Animate upload progress"""
	# Increment progress (simulate upload progress)
	upload_progress += 2.0  # 2% per 100ms = ~5 seconds to reach 100%
	if upload_progress >= 99.0:
		upload_progress = 99.0  # Cap at 99% until actually done

	# Update label
	if label:
		label.text = _format_attachment_name(attachment_data)


func _update_upload_status() -> void:
	"""Update label text and styling to reflect upload status"""
	if label:
		label.text = _format_attachment_name(attachment_data)

	# Update chip styling
	_create_chip_style()

	# Start/stop timer based on upload status
	var is_uploading = attachment_data.get("uploading", false)
	if is_uploading:
		if upload_timer:
			upload_progress = 0.0
			if upload_timer.is_stopped():
				upload_timer.start()
	else:
		if upload_timer:
			upload_timer.stop()
		upload_progress = 100.0


func _on_label_pressed() -> void:
	clicked.emit(attachment_data)


func _on_close_pressed() -> void:
	"""Handle close button press"""
	remove_requested.emit(attachment_data)
