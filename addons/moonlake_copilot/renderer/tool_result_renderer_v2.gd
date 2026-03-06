@tool
extends RefCounted

## ToolResultRendererV2
##
## Handles message type: "tool_result" - Shows tool execution output/results

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const CollapseAnimation = preload("res://addons/moonlake_copilot/renderer/collapse_animation.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")

static func render(message: Dictionary) -> Control:
	var widget = ToolResultWidget.new()
	widget.initialize(message)
	return widget


class ToolResultWidget extends PanelContainer:
	var icon_label: TextureRect
	var fold_button: Button
	var header_label: RichTextLabel
	var content_vbox: VBoxContainer
	var code_edit: CodeEdit
	var is_expanded: bool = false
	var tool_name: String = ""
	var message_type: String = ""
	var filename: String = ""
	var call_count: int = 1
	var expand_time: float = 0.0
	var user_manually_expanded: bool = false
	var has_error: bool = false

	func _init() -> void:
		var min_height = int(ThemeConstants.spacing(40))
		custom_minimum_size = Vector2(0, min_height)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		set_meta("message_type", "tool_result")

		add_theme_stylebox_override("panel", Styles.terminal_streaming_panel())

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
		icon_rect.texture = EditorInterface.get_editor_theme().get_icon("StatusSuccess", "EditorIcons")
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

		content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vbox_separation = int(ThemeConstants.spacing(8))
		content_vbox.add_theme_constant_override("separation", vbox_separation)
		main_hbox.add_child(content_vbox)

		# Create header row with fold button
		var header_hbox = HBoxContainer.new()
		header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(4)))
		content_vbox.add_child(header_hbox)

		# Fold button
		fold_button = Button.new()
		fold_button.flat = true
		fold_button.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowRight", "EditorIcons")
		fold_button.custom_minimum_size = Vector2(16, 16)
		fold_button.mouse_filter = Control.MOUSE_FILTER_PASS
		fold_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		fold_button.pressed.connect(_toggle_fold)
		header_hbox.add_child(fold_button)

		header_label = RichTextLabel.new()
		header_label.bbcode_enabled = true
		header_label.text = "Tool result..."
		header_label.fit_content = true
		header_label.scroll_active = false
		header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER
		header_label.mouse_filter = Control.MOUSE_FILTER_STOP
		header_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		ThemeConstants.apply_inter_font(header_label, ThemeConstants.Typography.FONT_SIZE_SMALL)

		var header_style = StyleBoxFlat.new()
		header_style.bg_color = Color(0, 0, 0, 0)
		ThemeConstants.apply_dpi_padding_custom(header_style, 0, 8, 4, 0)
		header_label.add_theme_stylebox_override("normal", header_style)

		header_hbox.add_child(header_label)

		code_edit = CodeEdit.new()
		code_edit.visible = false
		code_edit.editable = false
		code_edit.gutters_draw_line_numbers = true
		code_edit.indent_automatic = false
		code_edit.auto_brace_completion_highlight_matching = false
		code_edit.selecting_enabled = true
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		code_edit.scroll_fit_content_height = true
		code_edit.scroll_horizontal = false
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		ThemeConstants.apply_monospace_font(code_edit)

		var transparent_style = Styles.terminal_content()
		transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
		code_edit.add_theme_stylebox_override("normal", transparent_style)
		code_edit.add_theme_stylebox_override("focus", transparent_style)

		code_edit.gutters_draw_breakpoints_gutter = false
		code_edit.gutters_draw_bookmarks = false
		code_edit.gutters_draw_executing_lines = false

		content_vbox.add_child(code_edit)

		TripleClickSelector.enable_triple_click_selection(code_edit)

		call_deferred("_hide_horizontal_scrollbar")

		header_label.gui_input.connect(_on_header_clicked)

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		tool_name = content.get("tool_name", "Unknown")
		message_type = message.get("type", "tool_result")
		var result = content.get("result", "")
		var error = content.get("error")
		call_count = content.get("call_count", 1)

		match tool_name:
			"EditorOutput":
				if content.has("tool_input"):
					var tool_input = content.get("tool_input", "")
					if tool_input.begins_with("{"):
						var json = JSON.new()
						if json.parse(tool_input) == OK:
							var input_dict = json.get_data()
							var filter_type = input_dict.get("filter_type", -1)
							var filter_name = "all"
							match filter_type:
								0: filter_name = "stdout"
								1: filter_name = "errors"
								3: filter_name = "warnings"
								4: filter_name = "editor"
							self.filename = "filter: " + filter_name

			"Read", "Edit", "Write":
				# Check for filename in content
				if content.has("file_path"):
					self.filename = content.get("file_path", "")
				elif content.has("path"):
					self.filename = content.get("path", "")

				# If not in content, try tool_input
				if self.filename.is_empty() and content.has("tool_input"):
					var tool_input = content.get("tool_input", "")
					if tool_input.begins_with("{"):
						var json = JSON.new()
						if json.parse(tool_input) == OK:
							var input_dict = json.get_data()
							if input_dict.has("file_path"):
								self.filename = input_dict.get("file_path", "")
							elif input_dict.has("path"):
								self.filename = input_dict.get("path", "")

			"Bash":
				if content.has("tool_input"):
					var tool_input = content.get("tool_input", "")
					if tool_input.begins_with("{"):
						var json = JSON.new()
						if json.parse(tool_input) == OK:
							var input_dict = json.get_data()
							if input_dict.has("command"):
								var cmd = input_dict.get("command", "")
								self.filename = cmd.substr(0, 50) if cmd.length() > 50 else cmd

			"Glob":
				if content.has("tool_input"):
					var tool_input = content.get("tool_input", "")
					if tool_input.begins_with("{"):
						var json = JSON.new()
						if json.parse(tool_input) == OK:
							var input_dict = json.get_data()
							if input_dict.has("pattern"):
								self.filename = input_dict.get("pattern", "")

			"Grep":
				if content.has("tool_input"):
					var tool_input = content.get("tool_input", "")
					if tool_input.begins_with("{"):
						var json = JSON.new()
						if json.parse(tool_input) == OK:
							var input_dict = json.get_data()
							if input_dict.has("pattern"):
								self.filename = input_dict.get("pattern", "")

		# Start expanded if this is the most recent message
		# During session restore, is_last_message is not set, so widgets start collapsed
		if message.get("is_last_message", false):
			is_expanded = true
			expand_time = Time.get_ticks_msec() / 1000.0  # Record expand time
			custom_minimum_size.y = AnimationConstants.MIN_EXPANDED_HEIGHT  # Set minimum expanded height

		# Parse result and show execution metadata
		var display_text = result
		self.has_error = error != null

		# Try to parse result JSON and extract metadata
		if not self.has_error and result.begins_with("{"):
			var json = JSON.new()
			var parse_result = json.parse(result)
			if parse_result == OK:
				var result_dict = json.get_data()

				# Check for error status
				if result_dict.get("status") == "error":
					self.has_error = true
					error = result_dict.get("error", "Unknown error")
					display_text = ""
				else:
					if result_dict.has("data"):
						var data = result_dict["data"]
						if typeof(data) == TYPE_STRING:
							display_text = data.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"")
						elif typeof(data) == TYPE_DICTIONARY and data.has("output"):
							display_text = data["output"].replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"")
						else:
							display_text = JSON.stringify(data, "\t")
					else:
						display_text = "Success"

		var display_content = display_text if not self.has_error else ("Error: " + str(error))

		# Auto-detect syntax highlighting based on content
		var content_type = SyntaxFactory.detect_content_type(display_content, "tool_result")
		code_edit.syntax_highlighter = SyntaxFactory.create_highlighter(content_type)

		var text_color = ThemeConstants.COLORS.TEXT_TERMINAL if content_type == SyntaxFactory.ContentType.FILEPATH else Color(0.85, 0.85, 0.85, 1.0)
		code_edit.add_theme_color_override("font_color", text_color)
		code_edit.add_theme_color_override("font_readonly_color", text_color)

		code_edit.text = display_content

		_update_header()
		code_edit.visible = is_expanded

	func _update_header() -> void:
		"""Update icon and header text separately"""
		# Update fold button icon
		if fold_button:
			if is_expanded:
				fold_button.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowDown", "EditorIcons")
			else:
				fold_button.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowRight", "EditorIcons")

		# Success/failure icon (icon_label is now a TextureRect)
		if not self.has_error:
			icon_label.texture = EditorInterface.get_editor_theme().get_icon("StatusSuccess", "EditorIcons")
		else:
			icon_label.texture = EditorInterface.get_editor_theme().get_icon("StatusError", "EditorIcons")

		var header_text = "Tool: " + tool_name

		var args_text = ""
		if not filename.is_empty():
			# For Bash commands, use full command (already truncated). For file tools, extract filename only.
			if tool_name == "Bash":
				args_text = filename
			else:
				args_text = filename.get_file()

		if not args_text.is_empty():
			header_text += " (" + args_text + ")"

		if call_count > 1:
			header_text += " [%d calls]" % call_count
		header_label.text = header_text

	func _toggle_fold() -> void:
		"""Handle fold button press"""
		user_manually_expanded = true
		if is_expanded:
			_animate_collapse()
		else:
			_animate_expand()

	func _on_header_clicked(event: InputEvent) -> void:
		"""Handle header click to expand/collapse"""
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Mark as manually expanded/collapsed
			user_manually_expanded = true

			if is_expanded:
				# Collapse with animation
				_animate_collapse()
			else:
				# Expand instantly (no animation)
				_animate_expand()

	func collapse_if_expanded(force: bool = false) -> void:
		"""Collapse this widget if it's currently expanded"""
		# Don't auto-collapse if user manually expanded
		if user_manually_expanded and not force:
			return

		if is_expanded:
			# Check if minimum duration has passed (unless forced)
			if not force:
				var current_time = Time.get_ticks_msec() / 1000.0
				var elapsed = current_time - expand_time
				if elapsed < AnimationConstants.MIN_EXPAND_DURATION:
					# Too soon to collapse - skip
					return

			# Animate collapse
			_animate_collapse()

	func _animate_collapse() -> void:
		"""Smoothly collapse content with height animation"""
		is_expanded = false
		_update_header()

		# Immediately hide content as fallback (in case animation doesn't run when window is not focused)
		code_edit.visible = false

		# Try to animate (might not work if window is alt-tabbed)
		await CollapseAnimation.collapse_widget(self, AnimationConstants.COLLAPSED_HEIGHT, AnimationConstants.MIN_EXPANDED_HEIGHT, code_edit)

		# Force final state (in case animation didn't complete)
		code_edit.visible = false
		custom_minimum_size.y = AnimationConstants.COLLAPSED_HEIGHT

	func _animate_expand() -> void:
		"""Expand content instantly (no animation)"""
		is_expanded = true
		expand_time = Time.get_ticks_msec() / 1000.0  # Record expand time
		_update_header()

		CollapseAnimation.expand_widget(self, AnimationConstants.MIN_EXPANDED_HEIGHT, code_edit)

	func _hide_horizontal_scrollbar() -> void:
		"""Hide horizontal scrollbar by making it invisible"""
		if not code_edit:
			return
		for child in code_edit.get_children():
			if child is HScrollBar:
				child.visible = false
