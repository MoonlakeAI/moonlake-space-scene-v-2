@tool
extends RefCounted

## SystemMessageRendererV2
##
## Renders system messages (connection status, notifications, etc.)
## V2: Uses CodeEdit with modular styling system
##
## Visual design:
## - Cyan/teal background (from theme)
## - System prefix
## - CodeEdit with plain text highlighting
## - Rounded corners (8px)

const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")

static func render(message: Dictionary) -> Control:
	"""
	Render system message to Control node.

	Args:
		message: Message dictionary with structure:
			{
				"type": "system_message",
				"content": {
					"message": "System message text here",
					"category": "info" | "success" | "fail"  # Optional, defaults to "info"
				}
			}

	Returns:
		PanelContainer with minimal system message display (transparent, tool-call style)
	"""
	var container = PanelContainer.new()
	container.set_meta("message_type", "system_message")
	container.set_meta("content", message.get("content", {}))

	var min_height = int(ThemeConstants.spacing(40))
	container.custom_minimum_size = Vector2(0, min_height)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Transparent panel style (like tool_call_renderer)
	container.add_theme_stylebox_override("panel", Styles.terminal_streaming_panel())

	var content = message.get("content", {})
	var category = content.get("category", "info")
	var text = content.get("message", "")

	var main_hbox = HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var main_separation = int(ThemeConstants.spacing(10))
	main_hbox.add_theme_constant_override("separation", main_separation)
	container.add_child(main_hbox)

	# Icon using TextureRect (like tool_call_renderer)
	var icon_rect = TextureRect.new()
	var icon_size = int(ThemeConstants.spacing(20))
	icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Set icon and color based on category
	var text_color: Color
	match category:
		"success":
			icon_rect.texture = EditorInterface.get_editor_theme().get_icon("StatusSuccess", "EditorIcons")
			text_color = Color(0.4, 1.0, 0.4, 1.0)  # Bright green
		"fail":
			icon_rect.texture = EditorInterface.get_editor_theme().get_icon("StatusError", "EditorIcons")
			text_color = Color(1.0, 0.4, 0.4, 1.0)  # Bright red
		_:  # "info" or default
			icon_rect.texture = EditorInterface.get_editor_theme().get_icon("Notification", "EditorIcons")
			text_color = Color(0.4, 1.0, 1.0, 1.0)  # Bright cyan

	icon_rect.modulate = text_color

	var icon_margin = MarginContainer.new()
	icon_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_margin.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(8)))
	icon_margin.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(12)))
	icon_margin.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(8)))
	icon_margin.add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(8)))
	icon_margin.add_child(icon_rect)
	main_hbox.add_child(icon_margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vbox_separation = int(ThemeConstants.spacing(8))
	content_vbox.add_theme_constant_override("separation", vbox_separation)
	main_hbox.add_child(content_vbox)

	var code_edit = CodeEdit.new()
	code_edit.editable = false
	code_edit.gutters_draw_line_numbers = false
	code_edit.indent_automatic = false
	code_edit.auto_brace_completion_highlight_matching = false
	code_edit.selecting_enabled = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_edit.scroll_fit_content_height = true
	code_edit.scroll_horizontal = false
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	code_edit.text = text

	# No syntax highlighting for system messages - just plain text with uniform color
	code_edit.syntax_highlighter = null

	ThemeConstants.apply_monospace_font(code_edit)

	code_edit.add_theme_color_override("font_color", text_color)
	code_edit.add_theme_color_override("font_selected_color", text_color)
	code_edit.add_theme_color_override("font_readonly_color", text_color)
	code_edit.add_theme_color_override("font_placeholder_color", text_color)

	# Transparent background (like tool_call_renderer)
	var transparent_style = Styles.terminal_content()
	transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
	code_edit.add_theme_stylebox_override("normal", transparent_style)
	code_edit.add_theme_stylebox_override("focus", transparent_style)

	# Disable gutter interactions (read-only widget)
	code_edit.gutters_draw_breakpoints_gutter = false
	code_edit.gutters_draw_bookmarks = false
	code_edit.gutters_draw_executing_lines = false

	content_vbox.add_child(code_edit)

	# Enable triple-click to select all text
	TripleClickSelector.enable_triple_click_selection(code_edit)

	code_edit.tree_entered.connect(func():
		(func():
			if is_instance_valid(code_edit):
				for child in code_edit.get_children():
					if child is HScrollBar:
						child.visible = false
						break
		).call_deferred()
	, CONNECT_ONE_SHOT)

	return container
