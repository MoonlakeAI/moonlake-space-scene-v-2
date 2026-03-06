@tool
extends RefCounted

## ThinkingRendererV2
##
## Renders thinking messages with shimmer effect and typewriter animation.
## V2: Uses CodeEdit with modular styling system and markdown syntax highlighting.
## Collapsible after completion, persists in message cache.

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const CollapseAnimation = preload("res://addons/moonlake_copilot/renderer/collapse_animation.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")

const CHARS_PER_SEC = AnimationConstants.FAST_CHARS_PER_SEC
const TIMER_INTERVAL = AnimationConstants.TIMER_INTERVAL
const CHARS_PER_FRAME = AnimationConstants.FAST_CHARS_PER_FRAME
const MAX_BUFFER_SIZE = AnimationConstants.MAX_BUFFER_SIZE

static func render(message: Dictionary) -> Control:
	"""
	Create thinking widget with shimmer effect and typewriter animation.

	Args:
		message: Message dictionary with thinking content

	Returns:
		ThinkingWidget control
	"""
	var widget = ThinkingWidget.new()
	widget.initialize(message)
	return widget


## ThinkingWidget - Collapsible control for streaming thinking with animated gradient text
class ThinkingWidget extends PanelContainer:
	var icon_label: TextureRect
	var header_label: RichTextLabel
	var content_margin: MarginContainer
	var code_edit: CodeEdit
	var shader_material: ShaderMaterial
	var timer: Timer
	var tween: Tween
	var use_shader: bool = false
	var message_type: String = ""  # For debug display
	var full_text: String = ""
	var revealed_chars: float = 0.0
	var pending_delta_buffer: String = ""
	var is_expanded: bool = false
	var is_complete: bool = false
	var expand_time: float = 0.0
	var user_manually_expanded: bool = false
	var is_user_scrolled_up: bool = false

	func _init() -> void:
		var min_height = int(ThemeConstants.spacing(40))
		custom_minimum_size = Vector2(0, min_height)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		set_meta("message_type", "thinking")

		add_theme_stylebox_override("panel", Styles.collapsible_transparent_panel())

		# Main HBox: icon on left, content on right (like tool_call_renderer)
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
		icon_rect.texture = EditorInterface.get_editor_theme().get_icon("NodeInfo", "EditorIcons")
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

		# Content VBox: header + code_edit
		var content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vbox_separation = int(ThemeConstants.spacing(8))
		content_vbox.add_theme_constant_override("separation", vbox_separation)
		main_hbox.add_child(content_vbox)

		# Header text (clickable)
		header_label = RichTextLabel.new()
		header_label.bbcode_enabled = true
		header_label.text = "Thinking..."
		header_label.fit_content = true
		header_label.scroll_active = false
		header_label.selection_enabled = false
		header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER
		header_label.mouse_filter = Control.MOUSE_FILTER_STOP
		header_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		ThemeConstants.apply_inter_font(header_label, ThemeConstants.Typography.FONT_SIZE_SMALL)

		# Transparent background for header
		var header_style = StyleBoxFlat.new()
		header_style.bg_color = Color(0, 0, 0, 0)
		ThemeConstants.apply_dpi_padding_custom(header_style, 0, 8, 4, 0)
		header_label.add_theme_stylebox_override("normal", header_style)
		header_label.add_theme_stylebox_override("focus", header_style)

		content_vbox.add_child(header_label)

		# Margin container for content with DPI-adjusted margins
		content_margin = MarginContainer.new()
		content_margin.visible = false
		content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var bottom_margin = int(ThemeConstants.spacing(2))
		content_margin.add_theme_constant_override("margin_bottom", bottom_margin)
		content_vbox.add_child(content_margin)

		# CodeEdit for thinking content
		code_edit = CodeEdit.new()
		code_edit.editable = false
		code_edit.gutters_draw_line_numbers = false  # No line numbers for thinking
		code_edit.indent_automatic = false
		code_edit.auto_brace_completion_highlight_matching = false
		code_edit.selecting_enabled = true
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY  # Enable word wrap
		code_edit.scroll_fit_content_height = true
		code_edit.scroll_past_end_of_file = false
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		code_edit.syntax_highlighter = SyntaxFactory.create_highlighter(SyntaxFactory.ContentType.MARKDOWN)

		ThemeConstants.apply_monospace_font(code_edit)

		# Transparent background
		var transparent_style = Styles.transparent_label()
		code_edit.add_theme_stylebox_override("normal", transparent_style)
		code_edit.add_theme_stylebox_override("focus", transparent_style)

		var empty_style = StyleBoxEmpty.new()
		code_edit.add_theme_stylebox_override("scroll", empty_style)
		code_edit.add_theme_stylebox_override("scroll_focus", empty_style)

		# Disable gutter interactions
		code_edit.gutters_draw_breakpoints_gutter = false
		code_edit.gutters_draw_bookmarks = false
		code_edit.gutters_draw_executing_lines = false

		content_margin.add_child(code_edit)

		call_deferred("_hide_scrollbars")

		# Enable triple-click selection
		TripleClickSelector.enable_triple_click_selection(code_edit)

		# Detect user scroll in code edit
		code_edit.gui_input.connect(_on_code_edit_input)

		# Make header clickable
		header_label.gui_input.connect(_on_header_clicked)

		timer = Timer.new()
		timer.wait_time = TIMER_INTERVAL
		timer.timeout.connect(_on_timer_tick)
		add_child(timer)

	func initialize(message: Dictionary) -> void:
		"""Initialize widget with message data"""

		var content = message.get("content", {})
		var text = content.get("thinking", "")  # Use "thinking" field, not "text"
		var metadata = message.get("metadata", {})
		message_type = message.get("type", "thinking")

		# ALWAYS start expanded - collapse only when not last message anymore
		is_expanded = true
		expand_time = Time.get_ticks_msec() / 1000.0
		content_margin.visible = true

		# Check if streaming or complete
		var is_streaming = metadata.get("is_streaming_message", true)
		if is_streaming == false:
			# Complete message
			is_complete = true
			full_text = text
			code_edit.text = text + "\n"
			_stop_shimmer()
		else:
			# Streaming message - start typewriter
			full_text = text
			revealed_chars = 0.0
			code_edit.text = ""
			if text.length() > 0:
				_setup_shimmer()
				call_deferred("_start_typewriter")

		_update_header()

		custom_minimum_size.y = AnimationConstants.MIN_EXPANDED_HEIGHT
		content_margin.modulate.a = 1.0
		code_edit.modulate.a = 1.0

	func _hide_scrollbars() -> void:
		"""Forcibly hide scrollbar children"""
		for child in code_edit.get_children():
			if child is HScrollBar or child is VScrollBar:
				child.visible = false

	func _start_typewriter() -> void:
		"""Start typewriter timer (called after widget is in scene tree)"""
		if not timer.is_stopped():
			return
		timer.start()

	func append_delta(delta: String) -> void:
		"""Append streaming delta"""
		pending_delta_buffer += delta
		full_text += delta

		# Restart timer if it's stopped (ensure typewriter continues)
		if timer.is_stopped() and full_text.length() > 0:
			timer.start()

		if pending_delta_buffer.length() > MAX_BUFFER_SIZE:
			revealed_chars = full_text.length()
			code_edit.text = full_text + "\n"
			pending_delta_buffer = ""

	func update_message(message: Dictionary) -> void:
		"""Update when streaming completes"""
		is_complete = true

		var content = message.get("content", {})
		var text = content.get("thinking", "")  # Use "thinking" field, not "text"
		full_text = text

		# Reveal remaining text
		revealed_chars = full_text.length()
		code_edit.text = full_text + "\n"
		pending_delta_buffer = ""
		if timer:
			timer.stop()

		_stop_shimmer()
		_update_header()

		# Auto-collapse after delay (always, even if last message)
		if is_expanded and is_inside_tree():
			await get_tree().create_timer(0.5).timeout
			if is_expanded:
				collapse_if_expanded(true)

	func _on_timer_tick() -> void:
		"""Typewriter animation tick"""
		if revealed_chars >= full_text.length():
			code_edit.text = full_text + "\n"
			timer.stop()
			_scroll_to_bottom()
			return

		revealed_chars = min(revealed_chars + CHARS_PER_FRAME, full_text.length())
		var display_text = full_text.substr(0, int(revealed_chars))
		code_edit.text = display_text + "\n"

		# Auto-scroll to bottom during streaming (for long thinking)
		_scroll_to_bottom()

	func finish_animation() -> void:
		"""Immediately complete typewriter animation"""
		if timer and not timer.is_stopped():
			timer.stop()
		code_edit.text = full_text + "\n"
		revealed_chars = full_text.length()
		pending_delta_buffer = ""

	func _on_code_edit_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			is_user_scrolled_up = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var vscroll = code_edit.get_v_scroll_bar()
			if vscroll and code_edit.get_v_scroll() >= vscroll.max_value - 10:
				is_user_scrolled_up = false

	func _scroll_to_bottom() -> void:
		if not is_user_scrolled_up:
			call_deferred("_do_scroll_to_bottom")

	func _do_scroll_to_bottom() -> void:
		if not is_inside_tree() or is_user_scrolled_up or not is_expanded:
			return
		await get_tree().process_frame
		await get_tree().process_frame
		if is_user_scrolled_up:
			return
		var vscroll = code_edit.get_v_scroll_bar()
		if vscroll and vscroll.max_value > 0:
			code_edit.set_v_scroll(vscroll.max_value)
			var last_line = code_edit.get_line_count() - 1
			if last_line >= 0:
				code_edit.set_caret_line(last_line)

	func _setup_shimmer() -> void:
		"""Setup animated gradient shader or fallback to Tween animation"""
		var shader_path = "res://addons/moonlake_copilot/renderer/ephemeral_gradient_text.gdshader"
		var shader = load(shader_path)

		if shader == null:
			Log.warn("[ThinkingRendererV2] Failed to load shader, using Tween fallback")
			_use_tween_fallback()
			return


		shader_material = ShaderMaterial.new()
		shader_material.shader = shader

		shader_material.set_shader_parameter("gradient_color_1", ThemeConstants.COLORS.GRADIENT_1)
		shader_material.set_shader_parameter("gradient_color_2", ThemeConstants.COLORS.GRADIENT_2)
		shader_material.set_shader_parameter("gradient_color_3", ThemeConstants.COLORS.GRADIENT_3)
		shader_material.set_shader_parameter("animation_speed", 1.0)  # 1.0 second cycle (faster)
		shader_material.set_shader_parameter("gradient_width", 3.0)

		code_edit.material = shader_material
		use_shader = true

	func _use_tween_fallback() -> void:
		"""Fallback animation using Tween (pulse alpha on header)"""
		use_shader = false

		tween = create_tween()
		tween.set_loops()
		tween.tween_property(header_label, "modulate:a", 0.5, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(header_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func _stop_shimmer() -> void:
		"""Stop gradient effect"""
		if use_shader and shader_material:
			code_edit.material = null
			shader_material = null
		elif tween:
			tween.kill()
			header_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER

	func _update_header() -> void:
		"""Update header text based on state"""
		var status_text = "Thinking..." if not is_complete else "Thinking (complete)"

		# No fold icon in text - just the status
		header_label.text = status_text

	func _on_header_clicked(event: InputEvent) -> void:
		"""Handle header click to expand/collapse"""
		if not event is InputEventMouseButton:
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Mark as manually expanded/collapsed
			user_manually_expanded = true

			if is_expanded:
				# Collapse with animation
				_animate_collapse()
			else:
				# Expand instantly
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
		# Don't auto-collapse if user manually expanded
		if user_manually_expanded and not force:
			return

		if is_expanded:
			# Check if minimum duration has passed
			if not force:
				var current_time = Time.get_ticks_msec() / 1000.0
				var elapsed = current_time - expand_time
				if elapsed < AnimationConstants.MIN_EXPAND_DURATION:
					return

			# Animate collapse
			_animate_collapse()

	func _animate_collapse() -> void:
		"""Smoothly collapse content with height animation"""
		is_expanded = false
		_update_header()

		# Immediately hide content as fallback (in case animation doesn't run when window is not focused)
		content_margin.visible = false

		# Try to animate (might not work if window is alt-tabbed)
		await CollapseAnimation.collapse_widget(self, AnimationConstants.COLLAPSED_HEIGHT, AnimationConstants.MIN_EXPANDED_HEIGHT, content_margin)

		# Force final state (in case animation didn't complete)
		content_margin.visible = false
		custom_minimum_size.y = AnimationConstants.COLLAPSED_HEIGHT

	func _animate_expand() -> void:
		"""Expand content instantly"""
		is_expanded = true
		expand_time = Time.get_ticks_msec() / 1000.0
		_update_header()

		CollapseAnimation.expand_widget(self, AnimationConstants.MIN_EXPANDED_HEIGHT, content_margin)
		# Override the reduced opacity set at initialization
		code_edit.modulate.a = 1.0

	func _exit_tree() -> void:
		if header_label and header_label.gui_input.is_connected(_on_header_clicked):
			header_label.gui_input.disconnect(_on_header_clicked)
		if timer:
			timer.stop()
