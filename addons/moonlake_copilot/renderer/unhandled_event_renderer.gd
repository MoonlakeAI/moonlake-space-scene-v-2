@tool
extends RefCounted

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

static func render(event_type: String, data: Dictionary) -> Control:
	var container = PanelContainer.new()
	container.set_meta("message_type", "unhandled_event")
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	container.add_theme_stylebox_override("panel", Styles.terminal_streaming_panel())

	var main_hbox = HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(10)))
	container.add_child(main_hbox)

	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(int(ThemeConstants.spacing(20)), int(ThemeConstants.spacing(20)))
	icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture = EditorInterface.get_editor_theme().get_icon("Debug", "EditorIcons")
	icon_rect.modulate = Color(0.6, 0.6, 0.6)

	var icon_margin = MarginContainer.new()
	icon_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_margin.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(8)))
	icon_margin.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(8)))
	icon_margin.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(8)))
	icon_margin.add_child(icon_rect)
	main_hbox.add_child(icon_margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(4)))
	main_hbox.add_child(content_vbox)

	var label = Label.new()
	label.text = "[DEV] Unhandled: " + event_type
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	ThemeConstants.apply_inter_font(label, ThemeConstants.Typography.FONT_SIZE_SMALL)
	content_vbox.add_child(label)

	var code_edit = CodeEdit.new()
	code_edit.editable = false
	code_edit.gutters_draw_line_numbers = false
	code_edit.selecting_enabled = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_edit.scroll_fit_content_height = true
	code_edit.scroll_horizontal = false
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	code_edit.text = JSON.stringify(data, "  ")
	code_edit.syntax_highlighter = null

	ThemeConstants.apply_monospace_font(code_edit)
	code_edit.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	code_edit.add_theme_color_override("font_readonly_color", Color(0.5, 0.5, 0.5))

	var style = Styles.terminal_content()
	style.content_margin_bottom = ThemeConstants.spacing(8.0)
	code_edit.add_theme_stylebox_override("normal", style)
	code_edit.add_theme_stylebox_override("focus", style)

	code_edit.gutters_draw_breakpoints_gutter = false
	code_edit.gutters_draw_bookmarks = false
	code_edit.gutters_draw_executing_lines = false

	content_vbox.add_child(code_edit)

	return container
