@tool
class_name PopupMenuFactory
extends RefCounted

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

const PANEL_BG_COLOR = Color(0.15, 0.15, 0.15, 0.98)
const HOVER_BG_COLOR = Color(1.0, 1.0, 1.0, 0.1)
const CORNER_RADIUS = 0
const ITEM_CORNER_RADIUS = 6
const CONTENT_MARGIN = 8


static func create_popup(parent: Node) -> Popup:
	var popup = Popup.new()
	popup.transparent_bg = true
	popup.borderless = true
	parent.get_tree().root.add_child(popup)

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.set_corner_radius_all(CORNER_RADIUS)
	style.content_margin_left = CONTENT_MARGIN
	style.content_margin_right = CONTENT_MARGIN
	style.content_margin_top = CONTENT_MARGIN
	style.content_margin_bottom = CONTENT_MARGIN
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	panel.add_theme_stylebox_override("panel", style)
	popup.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	popup.set_meta("content_container", vbox)
	popup.set_meta("panel", panel)
	return popup


static func get_content_container(popup: Popup) -> VBoxContainer:
	return popup.get_meta("content_container") as VBoxContainer


static func style_popup_menu(popup_menu: PopupMenu) -> void:
	popup_menu.transparent_bg = true
	popup_menu.borderless = true

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG_COLOR
	panel_style.set_corner_radius_all(CORNER_RADIUS)
	panel_style.content_margin_left = CONTENT_MARGIN
	panel_style.content_margin_right = CONTENT_MARGIN
	panel_style.content_margin_top = CONTENT_MARGIN
	panel_style.content_margin_bottom = CONTENT_MARGIN
	panel_style.anti_aliasing = true
	panel_style.anti_aliasing_size = 1.0
	popup_menu.add_theme_stylebox_override("panel", panel_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = HOVER_BG_COLOR
	hover_style.set_corner_radius_all(4)
	popup_menu.add_theme_stylebox_override("hover", hover_style)

	var editor_scale = EditorInterface.get_editor_scale()
	var scaled_size = int(ThemeConstants.Typography.FONT_SIZE_SMALL * editor_scale)
	var inter_font = load(ThemeConstants.INTER_FONT_PATH)
	if inter_font:
		popup_menu.add_theme_font_override("font", inter_font)
	popup_menu.add_theme_font_size_override("font_size", scaled_size)


static func add_simple_item(container: VBoxContainer, text: String, id: int, icon: Texture2D = null) -> PanelContainer:
	var item = _create_item_container(id)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(hbox)

	if icon:
		var icon_rect = _create_icon(icon)
		hbox.add_child(icon_rect)

	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var editor_scale = EditorInterface.get_editor_scale()
	var font_size = int(ThemeConstants.Typography.FONT_SIZE_SMALL * editor_scale)
	label.add_theme_font_size_override("font_size", font_size)
	hbox.add_child(label)

	container.add_child(item)
	return item


static func add_rich_item(container: VBoxContainer, title: String, subtitle: String, id: int, icon: Texture2D = null) -> PanelContainer:
	var is_macos = OS.get_name() == "macOS"
	var item = _create_item_container(id)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(hbox)

	if icon:
		var icon_size = Vector2(32, 32) if is_macos else Vector2(16, 16)
		var icon_rect = _create_icon(icon, icon_size)
		hbox.add_child(icon_rect)

	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", -16)
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var title_label = Label.new()
	title_label.text = title
	var title_size = (ThemeConstants.Typography.FONT_SIZE_SMALL * 2) if is_macos else ThemeConstants.Typography.FONT_SIZE_SMALL
	title_label.add_theme_font_size_override("font_size", title_size)
	title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	title_label.add_theme_constant_override("line_spacing", -4)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title_label)

	var subtitle_label = Label.new()
	subtitle_label.text = subtitle
	var subtitle_size = 24 if is_macos else 12
	subtitle_label.add_theme_font_size_override("font_size", subtitle_size)
	subtitle_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	subtitle_label.add_theme_constant_override("line_spacing", -16)
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(subtitle_label)

	container.add_child(item)
	return item


static func add_separator(container: VBoxContainer) -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	container.add_child(sep)


static func show_above_button(popup: Popup, button: Control) -> void:
	var panel = popup.get_meta("panel") as PanelContainer
	var min_size = panel.get_combined_minimum_size()
	popup.size = Vector2i(int(min_size.x), int(min_size.y))
	var button_pos = button.get_screen_position()
	popup.position = Vector2i(int(button_pos.x), int(button_pos.y - min_size.y - 8))
	popup.popup()


static func show_below_button(popup: Popup, button: Control) -> void:
	var panel = popup.get_meta("panel") as PanelContainer
	var min_size = panel.get_combined_minimum_size()
	popup.size = Vector2i(int(min_size.x), int(min_size.y))
	var button_pos = button.get_screen_position()
	var button_size = button.size
	popup.position = Vector2i(int(button_pos.x), int(button_pos.y + button_size.y))
	popup.popup()


static func _create_item_container(id: int) -> PanelContainer:
	var is_macos = OS.get_name() == "macOS"
	var item = PanelContainer.new()
	item.set_meta("item_id", id)
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	normal_style.set_corner_radius_all(ITEM_CORNER_RADIUS)
	var h_padding = 16 if is_macos else 8
	var v_padding = 8 if is_macos else 4
	normal_style.content_margin_top = v_padding
	normal_style.content_margin_bottom = v_padding
	normal_style.content_margin_left = h_padding
	normal_style.content_margin_right = h_padding
	item.add_theme_stylebox_override("panel", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = HOVER_BG_COLOR

	item.set_meta("normal_style", normal_style)
	item.set_meta("hover_style", hover_style)

	item.mouse_entered.connect(func():
		item.add_theme_stylebox_override("panel", item.get_meta("hover_style"))
	)
	item.mouse_exited.connect(func():
		item.add_theme_stylebox_override("panel", item.get_meta("normal_style"))
	)

	return item


static func _create_icon(texture: Texture2D, size: Vector2 = Vector2(16, 16)) -> TextureRect:
	var icon_rect = TextureRect.new()
	icon_rect.texture = texture
	icon_rect.custom_minimum_size = size
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon_rect


static func connect_item_click(item: PanelContainer, popup: Popup, callback: Callable) -> void:
	item.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id = item.get_meta("item_id")
			callback.call(id)
			popup.hide()
	)
