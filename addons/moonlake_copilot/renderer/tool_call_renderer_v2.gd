@tool
extends RefCounted

## ToolCallRendererV2
##
## Handles message types:
## - "tool_call" - Local tool execution (Godot-side)
## - "tool_use" - API/backend tool execution with confirmation buttons

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const CollapseAnimation = preload("res://addons/moonlake_copilot/renderer/collapse_animation.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")

static func render(message: Dictionary, config = null) -> Control:
	var widget = ToolCallWidget.new()
	widget.config = config
	widget.initialize(message)
	return widget


class ToolCallWidget extends PanelContainer:
	var icon_label: TextureRect
	var fold_button: Button
	var header_label: RichTextLabel
	var result_code_edit: CodeEdit
	var is_expanded: bool = false
	var is_complete: bool = false
	var tool_name: String = ""
	var message_type: String = ""
	var display_name: String = ""
	var has_input: bool = false
	var expand_time: float = 0.0
	var user_manually_expanded: bool = false
	var filename: String = ""
	var override_icon: Texture2D = null
	var python_bridge: Node
	var awaiting_confirmation: bool = false
	var confirmation_buttons_container: Control
	var message_id: String = ""
	var tool_call_id: String = ""
	var is_last_message: bool = false
	var should_auto_confirm_yolo: bool = false
	var config = null

	func _init() -> void:
		var min_height = int(ThemeConstants.spacing(40))
		custom_minimum_size = Vector2(0, min_height)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		set_meta("message_type", "tool_call")

		add_theme_stylebox_override("panel", Styles.terminal_streaming_panel())

		var main_hbox = HBoxContainer.new()
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
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

		var content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vbox_separation = int(ThemeConstants.spacing(8))
		content_vbox.add_theme_constant_override("separation", vbox_separation)
		main_hbox.add_child(content_vbox)

		# Create header row with fold button
		var header_hbox = HBoxContainer.new()
		header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
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
		header_label.text = "Calling tool..."
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

		header_hbox.add_child(header_label)

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

		var transparent_style = Styles.terminal_content()
		transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
		result_code_edit.add_theme_stylebox_override("normal", transparent_style)
		result_code_edit.add_theme_stylebox_override("focus", transparent_style)

		result_code_edit.gutters_draw_breakpoints_gutter = false
		result_code_edit.gutters_draw_bookmarks = false
		result_code_edit.gutters_draw_executing_lines = false

		content_vbox.add_child(result_code_edit)

		TripleClickSelector.enable_triple_click_selection(result_code_edit)

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

	func set_python_bridge(bridge: Node) -> void:
		python_bridge = bridge

		if should_auto_confirm_yolo:
			should_auto_confirm_yolo = false
			_auto_confirm_tool()

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		tool_name = content.get("tool_name", "Unknown")
		message_type = message.get("type", "tool_call")
		message_id = message.get("id", "")
		tool_call_id = content.get("tool_call_id", message_id)
		is_last_message = message.get("is_last_message", false)

		var ask_confirmation = message.get("ask_confirmation", false)
		var skip_animation = message.get("skip_typewriter", false)
		var already_confirmed = content.get("confirmed", null) != null

		if is_last_message:
			is_expanded = true
			expand_time = Time.get_ticks_msec() / 1000.0

		display_name = tool_name
		var tool_input = content.get("tool_input", "")
		var parsed: Variant = null
		if typeof(tool_input) == TYPE_DICTIONARY:
			parsed = tool_input
		elif typeof(tool_input) == TYPE_STRING and tool_input != "":
			parsed = JSON.parse_string(tool_input)
		if parsed and typeof(parsed) == TYPE_DICTIONARY:
			# Check for description field first (highest priority)
			var description = parsed.get("description", "")
			if description != "":
				display_name = tool_name + " (" + description + ")"
			elif tool_name in ["Read", "Write", "Edit", "MultiEdit"]:
				var file_path = parsed.get("file_path", "")
				if file_path != "":
					self.filename = file_path  # Store for syntax detection
					display_name = tool_name + " (" + file_path.get_file() + ")"
			elif tool_name == "Bash":
				var command = parsed.get("command", "")
				if command != "":
					display_name = tool_name + " (" + command + ")"
			elif tool_name == "Glob":
				var pattern = parsed.get("pattern", "")
				if pattern != "":
					display_name = "Glob (pattern=" + pattern + ")"
			elif tool_name == "Grep":
				var pattern = parsed.get("pattern", "")
				if pattern != "":
					display_name = "Grep (pattern=" + pattern + ")"
			elif tool_name == "WebSearch":
				var query = parsed.get("query", "")
				if query != "":
					display_name = "WebSearch (" + query + ")"

		# Display tool input (parameters) if available
		if tool_input and (typeof(tool_input) == TYPE_DICTIONARY or (typeof(tool_input) == TYPE_STRING and tool_input != "")):
			is_complete = true
			_display_input(tool_input)

		if ask_confirmation and not skip_animation and not already_confirmed and config and config.yolo_mode_enabled:
			# Defer auto-confirm until python_bridge is set (happens in set_python_bridge)
			should_auto_confirm_yolo = true
			awaiting_confirmation = false
			is_expanded = true  # Force expanded so tool result will be visible
			result_code_edit.visible = true

			var content_vbox = result_code_edit.get_parent()
			var yolo_label = Label.new()
			yolo_label.text = "Auto-Accept mode enabled"
			yolo_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))  # Cyan
			yolo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			yolo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeConstants.apply_inter_font(yolo_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
			content_vbox.add_child(yolo_label)
		elif ask_confirmation and not skip_animation and not already_confirmed:
			awaiting_confirmation = true
			is_expanded = true  # Force expanded
			result_code_edit.visible = true
			_create_confirmation_buttons()
			# Disable header click while awaiting confirmation
			header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			awaiting_confirmation = false

		_update_header()
		if not awaiting_confirmation:
			result_code_edit.visible = is_expanded

		if config and not config.yolo_mode_activated.is_connected(_on_yolo_mode_activated):
			config.yolo_mode_activated.connect(_on_yolo_mode_activated)

	func _on_yolo_mode_activated() -> void:
		if awaiting_confirmation:
			if confirmation_buttons_container:
				confirmation_buttons_container.queue_free()
				confirmation_buttons_container = null

			header_label.mouse_filter = Control.MOUSE_FILTER_STOP
			awaiting_confirmation = false

			_auto_confirm_tool()

			var content_vbox = result_code_edit.get_parent()
			var yolo_label = Label.new()
			yolo_label.text = "Auto-Accept mode enabled"
			yolo_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))  # Cyan
			yolo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			yolo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeConstants.apply_inter_font(yolo_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
			content_vbox.add_child(yolo_label)

	func _display_input(input_data: Variant) -> void:
		"""Display tool input parameters, extracting content for Write/Edit tools"""
		has_input = true

		header_label.mouse_filter = Control.MOUSE_FILTER_STOP
		header_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var parsed: Variant = null
		var display_text: String = ""
		if typeof(input_data) == TYPE_DICTIONARY:
			parsed = input_data
			display_text = JSON.stringify(input_data, "  ", false, true)
		elif typeof(input_data) == TYPE_STRING:
			parsed = JSON.parse_string(input_data)
			display_text = input_data
		var content_extracted = false

		if parsed and typeof(parsed) == TYPE_DICTIONARY and tool_name in ["Write", "Edit"]:
			if parsed.has("content"):
				display_text = parsed["content"]
				display_text = display_text.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"")
				content_extracted = true

		if not content_extracted and parsed:
			display_text = JSON.stringify(parsed, "  ", false, true)

		result_code_edit.text = display_text

		var syntax_type = SyntaxFactory.ContentType.JSON
		if content_extracted:
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

	func _create_confirmation_buttons() -> void:
		"""Create Yes/No confirmation buttons for Bash tool"""
		var content_vbox = result_code_edit.get_parent()

		confirmation_buttons_container = VBoxContainer.new()
		confirmation_buttons_container.add_theme_constant_override("separation", int(ThemeConstants.spacing(12)))
		confirmation_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.add_child(confirmation_buttons_container)

		var warning_label = Label.new()
		warning_label.text = "This command will be executed. Do you want to proceed?"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))  # Yellow warning
		warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeConstants.apply_inter_font(warning_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
		confirmation_buttons_container.add_child(warning_label)

		# Top row: Yes / No
		var top_row = HBoxContainer.new()
		top_row.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
		top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirmation_buttons_container.add_child(top_row)

		var yes_button = _create_confirmation_button("Yes", "yes")
		yes_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(yes_button)

		var no_button = _create_confirmation_button("No", "no")
		no_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(no_button)

		# Bottom row: Yes for session (full width)
		var yolo_button = _create_confirmation_button("Yes for session", "yolo")
		yolo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirmation_buttons_container.add_child(yolo_button)

	func _create_confirmation_button(label: String, button_type: String) -> Button:
		"""Create a styled confirmation button (button_type: 'yes', 'yolo', 'no')"""
		var button = Button.new()
		button.text = label
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		ThemeConstants.apply_inter_font(button, ThemeConstants.Typography.FONT_SIZE_HEADER)

		var normal_style = StyleBoxFlat.new()
		var hover_style = StyleBoxFlat.new()

		match button_type:
			"yes":
				normal_style.bg_color = Color(0.2, 0.3, 0.2, 0.5)  # Dim green
				hover_style.bg_color = Color(0.3, 0.6, 0.3, 0.9)   # Bright green
			"yolo":
				normal_style.bg_color = Color(0.2, 0.3, 0.4, 0.5)  # Dim cyan/blue
				hover_style.bg_color = Color(0.3, 0.5, 0.7, 0.9)   # Bright cyan/blue
			"no":
				normal_style.bg_color = Color(0.3, 0.2, 0.2, 0.5)  # Dim red
				hover_style.bg_color = Color(0.6, 0.3, 0.3, 0.9)   # Bright red

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

		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", pressed_style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

		button.pressed.connect(func() -> void: _on_confirmation(button_type))

		return button

	func _auto_confirm_tool() -> void:
		if not python_bridge:
			Log.error("[tool_call_renderer_v2] Cannot auto-confirm - python_bridge not set!")
			return

		python_bridge.call_python("update_message_content", {
			"message_id": message_id,
			"content_updates": {
				"confirmed": true
			}
		})

		python_bridge.call_python("send_tool_confirmation", {
			"tool_call_id": tool_call_id,
			"confirmed": true
		})

	func _on_confirmation(button_type: String) -> void:
		"""Handle user confirmation (yes/yolo/no)"""
		if confirmation_buttons_container:
			confirmation_buttons_container.queue_free()
			confirmation_buttons_container = null

		var content_vbox = result_code_edit.get_parent()
		var confirmed = (button_type == "yes" or button_type == "yolo")

		awaiting_confirmation = false
		header_label.mouse_filter = Control.MOUSE_FILTER_STOP

		if button_type == "yolo":
			if config:
				config.enable_yolo_mode()
			var yolo_label = Label.new()
			yolo_label.text = "Auto-Accept mode enabled - auto-confirming all tools this session"
			yolo_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))  # Cyan
			yolo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			yolo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeConstants.apply_inter_font(yolo_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
			content_vbox.add_child(yolo_label)

		if button_type == "no":
			var rejection_label = Label.new()
			rejection_label.text = "Tool execution rejected by user"
			rejection_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))  # Red
			rejection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rejection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeConstants.apply_inter_font(rejection_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
			content_vbox.add_child(rejection_label)

		if python_bridge:
			python_bridge.call_python("update_message_content", {
				"message_id": message_id,
				"content_updates": {
					"confirmed": confirmed
				}
			})

		if python_bridge:
			python_bridge.call_python("send_tool_confirmation", {
				"tool_call_id": tool_call_id,
				"confirmed": confirmed
			})

		if not is_last_message and is_expanded:
			_animate_collapse()

	func cancel_confirmation() -> void:
		if not awaiting_confirmation:
			return

		if confirmation_buttons_container:
			confirmation_buttons_container.queue_free()
			confirmation_buttons_container = null

		awaiting_confirmation = false
		header_label.mouse_filter = Control.MOUSE_FILTER_STOP

		var content_vbox = result_code_edit.get_parent()
		var cancelled_label = Label.new()
		cancelled_label.text = "Confirmation cancelled"
		cancelled_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		cancelled_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cancelled_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeConstants.apply_inter_font(cancelled_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
		content_vbox.add_child(cancelled_label)

		if python_bridge:
			python_bridge.call_python("send_tool_confirmation", {
				"tool_call_id": tool_call_id,
				"confirmed": false
			})
			python_bridge.call_python("update_message_content", {
				"message_id": message_id,
				"content_updates": {
					"confirmed": "cancelled"
				}
			})

	func _update_header() -> void:
		"""Update icon and header text"""
		# Update fold button icon
		if fold_button:
			if is_expanded:
				fold_button.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowDown", "EditorIcons")
			else:
				fold_button.icon = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowRight", "EditorIcons")

		# Update tool icon (icon_label is now a TextureRect)
		if override_icon:
			icon_label.texture = override_icon
		else:
			icon_label.texture = _get_tool_icon()

		# Update header text (no fold indicator needed)
		var label_text = "Tool: " if is_complete else "Calling tool: "
		var header_text = label_text + display_name
		header_label.text = header_text

	func _toggle_fold() -> void:
		"""Handle fold button press"""
		if awaiting_confirmation or not has_input:
			return

		user_manually_expanded = true
		if is_expanded:
			_animate_collapse()
		else:
			_animate_expand()

	func _on_header_clicked(event: InputEvent) -> void:
		"""Handle header click to expand/collapse"""
		if not event is InputEventMouseButton:
			return

		if awaiting_confirmation:
			return

		if not has_input:
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			user_manually_expanded = true

			if is_expanded:
				_animate_collapse()
			else:
				_animate_expand()

	func _is_currently_last_message() -> bool:
		"""Check if this widget is the last message"""
		var parent = get_parent()
		if not parent:
			return false

		var grandparent = parent.get_parent()
		if not grandparent:
			return false

		var parent_index = parent.get_index()
		var last_index = grandparent.get_child_count() - 1
		return parent_index == last_index

	func collapse_if_expanded(force: bool = false) -> void:
		"""Collapse if expanded"""
		if awaiting_confirmation:
			return

		if user_manually_expanded and not force:
			return

		if is_expanded:
			if not force:
				var current_time = Time.get_ticks_msec() / 1000.0
				var elapsed = current_time - expand_time
				if elapsed < AnimationConstants.MIN_EXPAND_DURATION:
					return

			_animate_collapse()
		else:
			return

	func _animate_collapse() -> void:
		"""Smoothly collapse content with height animation"""
		is_expanded = false
		_update_header()

		result_code_edit.visible = false

		await CollapseAnimation.collapse_widget(self, AnimationConstants.COLLAPSED_HEIGHT, AnimationConstants.MIN_EXPANDED_HEIGHT, result_code_edit)

		result_code_edit.visible = false
		custom_minimum_size.y = AnimationConstants.COLLAPSED_HEIGHT

	func _animate_expand() -> void:
		"""Expand content instantly (no animation)"""
		is_expanded = true
		expand_time = Time.get_ticks_msec() / 1000.0  # Record expand time
		_update_header()

		CollapseAnimation.expand_widget(self, AnimationConstants.MIN_EXPANDED_HEIGHT, result_code_edit)

	func update_message(message: Dictionary) -> void:
		"""Handle message updates (called when tool_input arrives or is_last_message changes)"""
		is_last_message = message.get("is_last_message", false)

		if not awaiting_confirmation and not is_last_message and is_expanded:
			collapse_if_expanded()
