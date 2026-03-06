@tool
extends RefCounted

const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")

static func render(message: Dictionary) -> Control:
	var widget = ErrorWidget.new()
	widget.initialize(message)
	return widget


class ErrorWidget extends PanelContainer:
	var message_id: String
	var code_edit: CodeEdit
	var retry_button: Button
	var python_bridge
	var vbox: VBoxContainer

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		set_meta("message_type", "error")

		add_theme_stylebox_override("panel", Styles.error_panel())

		vbox = VBoxContainer.new()
		var vbox_separation = int(ThemeConstants.spacing(12))
		vbox.add_theme_constant_override("separation", vbox_separation)
		add_child(vbox)

		var hbox = HBoxContainer.new()
		var hbox_separation = int(ThemeConstants.spacing(10))
		hbox.add_theme_constant_override("separation", hbox_separation)
		vbox.add_child(hbox)

		var icon_rect = TextureRect.new()
		var icon_size = int(ThemeConstants.spacing(20))
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
		icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = EditorInterface.get_editor_theme().get_icon("StatusError", "EditorIcons")

		var icon_margin = MarginContainer.new()
		icon_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon_margin.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_bottom", 0)
		icon_margin.add_child(icon_rect)

		hbox.add_child(icon_margin)

		code_edit = CodeEdit.new()
		code_edit.editable = false
		code_edit.gutters_draw_line_numbers = false
		code_edit.indent_automatic = false
		code_edit.auto_brace_completion_highlight_matching = false
		code_edit.selecting_enabled = true
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		code_edit.scroll_fit_content_height = true
		code_edit.scroll_past_end_of_file = false
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		code_edit.custom_minimum_size = Vector2(int(ThemeConstants.spacing(100)), 0)

		code_edit.syntax_highlighter = null

		ThemeConstants.apply_monospace_font(code_edit)

		code_edit.add_theme_color_override("font_color", ThemeConstants.COLORS.TEXT_ERROR)

		var transparent_style = StyleBoxFlat.new()
		transparent_style.bg_color = Color(0, 0, 0, 0)
		transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
		#ThemeConstants.apply_dpi_padding_custom(transparent_style, 8, 8, 6, 12)
		code_edit.add_theme_stylebox_override("normal", transparent_style)
		code_edit.add_theme_stylebox_override("focus", transparent_style)

		code_edit.gutters_draw_breakpoints_gutter = false
		code_edit.gutters_draw_bookmarks = false
		code_edit.gutters_draw_executing_lines = false

		hbox.add_child(code_edit)

		TripleClickSelector.enable_triple_click_selection(code_edit)

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		var error_text = content.get("message", "")

		var metadata = message.get("metadata", {})
		message_id = metadata.get("retry_local_id", message.get("id", ""))

		var error_detail = message.get("error", "")
		if error_detail and not error_text:
			error_text = error_detail

		code_edit.text = error_text

		code_edit.call_deferred("update_minimum_size")
		call_deferred("update_minimum_size")

		var buttons = content.get("buttons", [])
		for button_data in buttons:
			var btn = Button.new()
			btn.text = button_data.get("text", "Button")
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			ThemeConstants.apply_inter_font(btn, ThemeConstants.Typography.FONT_SIZE_HEADER)

			var normal_style = StyleBoxFlat.new()
			var hover_style = StyleBoxFlat.new()

			normal_style.bg_color = Color(0.2, 0.3, 0.2, 1.0)
			hover_style.bg_color = Color(0.3, 0.6, 0.3, 1.0)

			var corner_radius = int(ThemeConstants.spacing(6))
			normal_style.corner_radius_top_left = corner_radius
			normal_style.corner_radius_top_right = corner_radius
			normal_style.corner_radius_bottom_left = corner_radius
			normal_style.corner_radius_bottom_right = corner_radius
			normal_style.anti_aliasing = true
			normal_style.anti_aliasing_size = 2.0
			ThemeConstants.apply_dpi_padding_custom(normal_style, 12, 12, 8, 8)

			hover_style.corner_radius_top_left = corner_radius
			hover_style.corner_radius_top_right = corner_radius
			hover_style.corner_radius_bottom_left = corner_radius
			hover_style.corner_radius_bottom_right = corner_radius
			hover_style.anti_aliasing = true
			hover_style.anti_aliasing_size = 2.0
			ThemeConstants.apply_dpi_padding_custom(hover_style, 12, 12, 8, 8)

			var pressed_style = StyleBoxFlat.new()
			pressed_style.bg_color = Color(0.4, 0.4, 0.4, 0.8)
			pressed_style.corner_radius_top_left = corner_radius
			pressed_style.corner_radius_top_right = corner_radius
			pressed_style.corner_radius_bottom_left = corner_radius
			pressed_style.corner_radius_bottom_right = corner_radius
			pressed_style.anti_aliasing = true
			pressed_style.anti_aliasing_size = 2.0
			ThemeConstants.apply_dpi_padding_custom(pressed_style, 12, 12, 8, 8)

			btn.add_theme_stylebox_override("normal", normal_style)
			btn.add_theme_stylebox_override("hover", hover_style)
			btn.add_theme_stylebox_override("pressed", pressed_style)
			btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
			btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

			var url = button_data.get("url", "")
			if url:
				btn.pressed.connect(func(): OS.shell_open(url))

			vbox.add_child(btn)

		var is_user_message = metadata.get("retry_is_user_message", false)
		if is_user_message:
			retry_button = Button.new()
			retry_button.text = "Retry"
			var button_width = int(ThemeConstants.spacing(80))
			var button_height = int(ThemeConstants.spacing(30))
			retry_button.custom_minimum_size = Vector2(button_width, button_height)
			retry_button.pressed.connect(_on_retry_pressed)
			vbox.add_child(retry_button)

			retry_button.add_theme_stylebox_override("normal", Styles.error_button())
			retry_button.add_theme_stylebox_override("hover", Styles.error_button_hover())

			_find_python_bridge()

	func _find_python_bridge() -> void:
		var current = get_parent()
		while current != null:
			if current.name == "MoonlakeCopilot" and current.has_node("PythonBridge"):
				python_bridge = current.get_node("PythonBridge")
				return
			current = current.get_parent()

	func _on_retry_pressed() -> void:
		if retry_button:
			retry_button.visible = false

		var params = {
			"local_message_id": message_id,
			"workdir": ProjectSettings.globalize_path("res://")
		}
		python_bridge.call_python("retry_message", params)
