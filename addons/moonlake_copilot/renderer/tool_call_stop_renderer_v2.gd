@tool
extends RefCounted

## ToolCallStopRendererV2
##
## Handles message type: "tool_call_stop" - Shows when a tool call completes with final parameters
##
## Visual design:
## - Blue outline (terminal_streaming_panel)
## - Tool icon + name in header
## - Collapsible JSON parameters display
## - Monospace font

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const CollapseAnimation = preload("res://addons/moonlake_copilot/renderer/collapse_animation.gd")
const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")

static func render(message: Dictionary) -> Control:
	"""
	Render tool_call_stop message to Control node.

	Args:
		message: Message dictionary with structure:
			{
				"type": "tool_call_stop",
				"content": {
					"tool_call_id": "...",
					"content_block": {
						"tool_name": "...",
						"tool_input": {...}
					}
				}
			}

	Returns:
		ToolCallStopWidget control
	"""
	var widget = ToolCallStopWidget.new()
	widget.initialize(message)
	return widget


## ToolCallStopWidget - Collapsible control for tool_call_stop messages
class ToolCallStopWidget extends PanelContainer:
	var icon_label: TextureRect
	var header_label: RichTextLabel
	var result_code_edit: CodeEdit
	var is_expanded: bool = false
	var tool_name: String = ""
	var message_type: String = ""
	var display_name: String = ""
	var has_input: bool = false
	var filename: String = ""  # For syntax detection

	func _init() -> void:
		var min_height = int(ThemeConstants.spacing(40))
		custom_minimum_size = Vector2(0, min_height)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		set_meta("message_type", "tool_call_stop")

		add_theme_stylebox_override("panel", Styles.terminal_streaming_panel())

		# Main HBox: icon on left, content on right
		var main_hbox = HBoxContainer.new()
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var main_separation = int(ThemeConstants.spacing(10))
		main_hbox.add_theme_constant_override("separation", main_separation)
		add_child(main_hbox)

		# Icon using TextureRect
		var icon_rect = TextureRect.new()
		var icon_size = int(ThemeConstants.spacing(20))
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
		icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = EditorInterface.get_editor_theme().get_icon("Tools", "EditorIcons")
		icon_rect.modulate = ThemeConstants.COLORS.ICON_TOOL
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon_margin = MarginContainer.new()
		icon_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon_margin.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(12)))
		icon_margin.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(8)))
		icon_margin.add_child(icon_rect)

		icon_label = icon_rect  # Keep reference for compatibility
		main_hbox.add_child(icon_margin)

		# Right side VBox: header + content
		var content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vbox_separation = int(ThemeConstants.spacing(8))
		content_vbox.add_theme_constant_override("separation", vbox_separation)
		main_hbox.add_child(content_vbox)

		# Header label - RichTextLabel for monospace
		header_label = RichTextLabel.new()
		header_label.bbcode_enabled = true
		header_label.text = "Tool: ..."
		header_label.fit_content = true
		header_label.scroll_active = false
		header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER
		header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_label.mouse_default_cursor_shape = Control.CURSOR_ARROW

		ThemeConstants.apply_inter_font(header_label, ThemeConstants.Typography.FONT_SIZE_SMALL)

		var header_style = StyleBoxFlat.new()
		header_style.bg_color = Color(0, 0, 0, 0)
		ThemeConstants.apply_dpi_padding_custom(header_style, 0, 8, 4, 0)
		header_label.add_theme_stylebox_override("normal", header_style)

		content_vbox.add_child(header_label)

		# CodeEdit for result display (starts hidden)
		result_code_edit = CodeEdit.new()
		result_code_edit.visible = false
		result_code_edit.editable = false
		result_code_edit.gutters_draw_line_numbers = true
		result_code_edit.indent_automatic = false
		result_code_edit.auto_brace_completion_highlight_matching = false
		result_code_edit.selecting_enabled = true
		result_code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		result_code_edit.scroll_fit_content_height = true
		result_code_edit.scroll_horizontal = false
		result_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		ThemeConstants.apply_monospace_font(result_code_edit)

		result_code_edit.add_theme_color_override("font_color", ThemeConstants.COLORS.TEXT_TERMINAL)
		result_code_edit.add_theme_color_override("font_readonly_color", ThemeConstants.COLORS.TEXT_TERMINAL)
		result_code_edit.add_theme_color_override("font_placeholder_color", ThemeConstants.COLORS.TEXT_TERMINAL)

		# Transparent background with DPI-adjusted bottom margin
		var transparent_style = Styles.terminal_content()
		transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
		result_code_edit.add_theme_stylebox_override("normal", transparent_style)
		result_code_edit.add_theme_stylebox_override("focus", transparent_style)

		# Disable gutter interactions
		result_code_edit.gutters_draw_breakpoints_gutter = false
		result_code_edit.gutters_draw_bookmarks = false
		result_code_edit.gutters_draw_executing_lines = false

		content_vbox.add_child(result_code_edit)

		# Enable triple-click selection
		TripleClickSelector.enable_triple_click_selection(result_code_edit)

		# Make header clickable
		header_label.gui_input.connect(_on_header_clicked)

	func _get_tool_icon() -> Texture2D:
		"""Get Godot icon for tool"""
		match tool_name:
			"Read":
				return EditorInterface.get_editor_theme().get_icon("File", "EditorIcons")
			"Write":
				return EditorInterface.get_editor_theme().get_icon("Save", "EditorIcons")
			"Edit", "MultiEdit":
				return EditorInterface.get_editor_theme().get_icon("Edit", "EditorIcons")
			"Bash", "BashOutput", "KillBash":
				return EditorInterface.get_editor_theme().get_icon("Terminal", "EditorIcons")
			"Glob", "Grep":
				return EditorInterface.get_editor_theme().get_icon("Search", "EditorIcons")
			"WebFetch", "WebSearch":
				return EditorInterface.get_editor_theme().get_icon("Search", "EditorIcons")
			"Task":
				return EditorInterface.get_editor_theme().get_icon("Play", "EditorIcons")
			"TodoWrite":
				return EditorInterface.get_editor_theme().get_icon("FileList", "EditorIcons")
			"EditorOutput":
				return EditorInterface.get_editor_theme().get_icon("TextFile", "EditorIcons")
			"GenerateImage", "UpscaleImage", "GenerateAvatar":
				return EditorInterface.get_editor_theme().get_icon("ImageTexture", "EditorIcons")
			"Skill", "GenerateScene", "GenerateAssets", "GenerateSkybox", "SearchAssets", "RemoveBackground", "ReimportFile":
				return EditorInterface.get_editor_theme().get_icon("Tools", "EditorIcons")
			_:
				return EditorInterface.get_editor_theme().get_icon("Tools", "EditorIcons")

	func initialize(message: Dictionary) -> void:
		"""Initialize widget with message data"""
		var content = message.get("content", {})
		var content_block = content.get("content_block", {})
		tool_name = content_block.get("tool_name", "Unknown")
		message_type = message.get("type", "tool_call_stop")

		display_name = tool_name
		var tool_input_raw = content_block.get("tool_input", "")

		# Parse tool_input
		var tool_input = null
		if typeof(tool_input_raw) == TYPE_STRING and tool_input_raw != "":
			tool_input = JSON.parse_string(tool_input_raw)
		elif typeof(tool_input_raw) == TYPE_DICTIONARY:
			tool_input = tool_input_raw

		if tool_input and typeof(tool_input) == TYPE_DICTIONARY:
			# Check for description field first
			var description = tool_input.get("description", "")
			if description != "":
				display_name = tool_name + " (" + description + ")"
			elif tool_name in ["Read", "Write", "Edit", "MultiEdit"]:
				var file_path = tool_input.get("file_path", "")
				if file_path != "":
					self.filename = file_path  # Store for syntax detection
					display_name = tool_name + " (" + file_path.get_file() + ")"
			elif tool_name == "Bash":
				var command = tool_input.get("command", "")
				if command != "":
					display_name = tool_name + " (" + command + ")"
			elif tool_name == "Glob":
				var pattern = tool_input.get("pattern", "")
				if pattern != "":
					display_name = "Glob (pattern=" + pattern + ")"
			elif tool_name == "Grep":
				var pattern = tool_input.get("pattern", "")
				if pattern != "":
					display_name = "Grep (pattern=" + pattern + ")"
			elif tool_name == "WebSearch":
				var query = tool_input.get("query", "")
				if query != "":
					display_name = "WebSearch (" + query + ")"

			# Display tool input
			_display_input(tool_input)

		_update_header()
		result_code_edit.visible = is_expanded

	func _display_input(tool_input: Variant) -> void:
		"""Display tool input parameters, extracting content for Write/Edit tools"""
		has_input = true

		# Make header clickable
		header_label.mouse_filter = Control.MOUSE_FILTER_STOP
		header_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var display_text = ""
		var content_extracted = false

		# For Write/Edit tools, extract and display the content field
		if typeof(tool_input) == TYPE_DICTIONARY and tool_name in ["Write", "Edit"]:
			if tool_input.has("content"):
				display_text = tool_input["content"]
				display_text = display_text.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"")
				content_extracted = true

		# If content not extracted, pretty-print JSON
		if not content_extracted:
			if typeof(tool_input) == TYPE_DICTIONARY:
				display_text = JSON.stringify(tool_input, "  ", false, true)
			else:
				display_text = str(tool_input)

		# Display with appropriate syntax highlighting
		result_code_edit.text = display_text

		# Detect syntax type
		var syntax_type = SyntaxFactory.ContentType.JSON
		if content_extracted:
			# For Write/Edit with extracted content, detect by filename
			syntax_type = _detect_syntax_by_filename()

		result_code_edit.syntax_highlighter = SyntaxFactory.create_highlighter(syntax_type)

	func _detect_syntax_by_filename() -> int:
		"""Detect syntax highlighting type based on file extension for Write/Edit operations"""
		if filename.is_empty():
			return SyntaxFactory.ContentType.PLAIN

		var ext = filename.get_extension().to_lower()
		match ext:
			"md", "markdown":
				return SyntaxFactory.ContentType.MARKDOWN
			"json":
				return SyntaxFactory.ContentType.JSON
			"gd":
				return SyntaxFactory.ContentType.GDSCRIPT
			"sh", "bash":
				return SyntaxFactory.ContentType.BASH
			_:
				return SyntaxFactory.ContentType.PLAIN

	func _update_header() -> void:
		"""Update icon and header text"""
		var header_text = "Tool: " + display_name
		header_label.text = header_text

	func _on_header_clicked(event: InputEvent) -> void:
		"""Handle header click to expand/collapse"""
		if not event is InputEventMouseButton:
			return

		# Only allow clicking if we have input to show
		if not has_input:
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_expanded:
				_animate_collapse()
			else:
				_animate_expand()

	func _animate_collapse() -> void:
		"""Smoothly collapse content"""
		is_expanded = false
		_update_header()
		await CollapseAnimation.collapse_widget(self, AnimationConstants.COLLAPSED_HEIGHT, AnimationConstants.MIN_EXPANDED_HEIGHT, result_code_edit)

	func _animate_expand() -> void:
		"""Expand content"""
		is_expanded = true
		_update_header()
		CollapseAnimation.expand_widget(self, AnimationConstants.MIN_EXPANDED_HEIGHT, result_code_edit)
