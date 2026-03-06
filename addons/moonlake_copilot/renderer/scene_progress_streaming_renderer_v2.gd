@tool
extends PanelContainer

## SceneProgressStreamingRendererV2
##
## Renders real-time scene plan streaming with typewriter animation.
## V2: Uses CodeEdit with modular styling system and markdown syntax highlighting.
##
## Visual design:
## - Blue-bordered terminal (distinguishes from static scene progress)
## - CodeEdit with line numbers
## - Markdown syntax highlighting (plan text)
## - Fixed height (300px) with scrollbar
## - Auto-scroll to bottom as content streams
## - Typewriter animation (100 chars/sec)
## - Auto-collapses on completion

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const CollapseAnimation = preload("res://addons/moonlake_copilot/renderer/collapse_animation.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")

# UI Nodes
var title_label: RichTextLabel
var scroll_container: ScrollContainer
var code_edit: CodeEdit
var timer: Timer
var timeout_timer: Timer

# State
var scene_id: String = ""
var message_type: String = ""  # For debug display
var full_content: String = ""
var revealed_chars: float = 0.0
var pending_buffer: String = ""
var is_complete: bool = false
var large_content_warned: bool = false
var is_collapsed: bool = false  # Track collapse state
var is_animating: bool = false  # Prevent concurrent animations
var is_user_scrolled_up: bool = false  # Track if user scrolled up in inner scroll

# Constants - Override animation speed for scene progress streaming (faster for content)
const CHARS_PER_SEC = AnimationConstants.FAST_CHARS_PER_SEC
const TIMER_INTERVAL = AnimationConstants.TIMER_INTERVAL
const CHARS_PER_FRAME = AnimationConstants.FAST_CHARS_PER_FRAME
const MAX_BUFFER_SIZE = AnimationConstants.MAX_BUFFER_SIZE
const TIMEOUT_SECONDS = 180.0  # 3 minutes for large plans
const FIXED_HEIGHT = 300.0
const COLLAPSED_HEIGHT = AnimationConstants.COLLAPSED_HEIGHT

signal streaming_complete(scene_id: String)

func _init() -> void:
	custom_minimum_size = Vector2(0, COLLAPSED_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP  # Enable click detection
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND  # Show pointer on hover
	set_meta("message_type", "scene_progress_streaming")
	_apply_terminal_style()

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Title (RichTextLabel for BBCode emoji offset)
	title_label = RichTextLabel.new()
	title_label.bbcode_enabled = true
	title_label.fit_content = true
	title_label.scroll_active = false
	title_label.selection_enabled = false
	title_label.text = "[color=#B3B3B3]Scene Plan (streaming...)[/color]"
	title_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER

	ThemeConstants.apply_inter_font(title_label)

	# Remove default background, add top padding
	var title_transparent_style = StyleBoxFlat.new()
	title_transparent_style.bg_color = Color(0, 0, 0, 0)
	title_transparent_style.content_margin_top = ThemeConstants.spacing(8.0)  # Add top padding
	title_label.add_theme_stylebox_override("normal", title_transparent_style)
	title_label.add_theme_stylebox_override("focus", title_transparent_style)
	vbox.add_child(title_label)

	# Scrollable content
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll_container)

	# CodeEdit for streaming content
	code_edit = CodeEdit.new()
	code_edit.editable = false  # Read-only
	code_edit.gutters_draw_line_numbers = true
	code_edit.indent_automatic = false
	code_edit.auto_brace_completion_highlight_matching = false
	code_edit.selecting_enabled = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY  # Wrap at word boundaries
	code_edit.scroll_fit_content_height = true
	code_edit.scroll_horizontal = false
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL

	code_edit.syntax_highlighter = SyntaxFactory.create_highlighter(SyntaxFactory.ContentType.MARKDOWN)

	ThemeConstants.apply_monospace_font(code_edit)

	code_edit.add_theme_color_override("font_color", ThemeConstants.COLORS.TEXT_TERMINAL)

	# Transparent background for CodeEdit (terminal panel provides background)
	var transparent_style = Styles.terminal_content()
	code_edit.add_theme_stylebox_override("normal", transparent_style)
	code_edit.add_theme_stylebox_override("focus", transparent_style)

	# Disable gutter interactions (read-only widget)
	code_edit.gutters_draw_breakpoints_gutter = false
	code_edit.gutters_draw_bookmarks = false
	code_edit.gutters_draw_executing_lines = false

	scroll_container.add_child(code_edit)

	# Enable triple-click to select all text
	TripleClickSelector.enable_triple_click_selection(code_edit)

	# Detect user scroll in inner scroll container
	scroll_container.gui_input.connect(_on_inner_scroll_input)

	# Typewriter timer
	timer = Timer.new()
	timer.wait_time = TIMER_INTERVAL
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

	# Timeout timer
	timeout_timer = Timer.new()
	timeout_timer.wait_time = TIMEOUT_SECONDS
	timeout_timer.one_shot = true
	timeout_timer.timeout.connect(_on_timeout)
	add_child(timeout_timer)

	gui_input.connect(_gui_input)

func _apply_terminal_style() -> void:
	"""Apply terminal-style appearance with blue accent from theme"""
	add_theme_stylebox_override("panel", Styles.terminal_streaming_panel())

func initialize(scene_id_param: String, message_type_param: String = "") -> void:
	"""Initialize renderer with scene ID - starts expanded"""
	scene_id = scene_id_param
	message_type = message_type_param

	title_label.text = "[color=#B3B3B3]Scene Plan (streaming...)[/color]"

	# Start expanded
	is_collapsed = false
	custom_minimum_size = Vector2(0, FIXED_HEIGHT)
	scroll_container.visible = true

	# Start timers after widget is in scene tree
	call_deferred("_start_timers")

func _start_timers() -> void:
	"""Start timers after widget is added to scene tree"""
	if not is_inside_tree():
		Log.warn("[SceneProgressStreamingRendererV2] Not in scene tree yet, deferring timer start")
		call_deferred("_start_timers")
		return

	if timer.is_stopped():
		timer.start()
	if timeout_timer.is_stopped():
		timeout_timer.start()

func append_delta(delta: String) -> void:
	"""Append streaming content delta"""
	# Replace escaped characters with actual characters
	var processed_delta = delta.replace("\\n", "\n").replace("\\\"", "\"")

	# Append to pending buffer for typewriter animation
	pending_buffer += processed_delta

	# Check buffer overflow
	if pending_buffer.length() > MAX_BUFFER_SIZE:
		_flush_buffer()
		if not large_content_warned:
			code_edit.text += "\n\n[INFO] Large content, skipping animation..."
			large_content_warned = true

func _on_timer_timeout() -> void:
	"""Typewriter animation frame"""
	if pending_buffer.is_empty():
		return

	# Accumulate fractional characters
	revealed_chars += CHARS_PER_FRAME
	var chars_to_show = int(revealed_chars)

	# Calculate how many new characters to reveal
	var chars_to_reveal = chars_to_show - full_content.length()

	if chars_to_reveal > 0:
		# Take at most what's available in buffer
		chars_to_reveal = min(chars_to_reveal, pending_buffer.length())
		var chunk = pending_buffer.substr(0, chars_to_reveal)
		pending_buffer = pending_buffer.substr(chars_to_reveal)
		full_content += chunk
		code_edit.text = full_content
		_scroll_to_bottom()

func _flush_buffer() -> void:
	"""Flush pending buffer immediately"""
	full_content += pending_buffer
	code_edit.text = full_content
	pending_buffer = ""
	_scroll_to_bottom()

func _on_inner_scroll_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		is_user_scrolled_up = true
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var vscroll = scroll_container.get_v_scroll_bar() if scroll_container else null
		if vscroll and scroll_container.scroll_vertical >= vscroll.max_value - 10:
			is_user_scrolled_up = false


func _scroll_to_bottom() -> void:
	if not is_user_scrolled_up:
		call_deferred("_do_scroll_to_bottom")


func _do_scroll_to_bottom() -> void:
	if not is_inside_tree() or is_user_scrolled_up:
		return
	await get_tree().process_frame
	if is_user_scrolled_up:
		return
	var vscroll = scroll_container.get_v_scroll_bar() if scroll_container else null
	if vscroll:
		scroll_container.scroll_vertical = int(vscroll.max_value)

func complete(error: String = "") -> void:
	"""Complete streaming - stay expanded by default"""
	timeout_timer.stop()
	is_complete = true

	if error != "":
		_apply_error_style()
		code_edit.text += "\n\n[ERROR] " + error

	_flush_buffer()
	timer.stop()

	title_label.text = "[color=#B3B3B3]Scene Plan[/color]"

	# Change border from blue (streaming) to normal
	add_theme_stylebox_override("panel", Styles.terminal_panel())

	# Emit completion signal but stay expanded
	streaming_complete.emit(scene_id)

func finish_animation() -> void:
	"""Immediately finish animation (called by animation manager on stop)"""
	if is_complete:
		return  # Already complete
	complete()

func _apply_error_style() -> void:
	"""Apply error styling (red tint)"""
	var style = get_theme_stylebox("panel").duplicate()
	if style is StyleBoxFlat:
		style.bg_color = Color(0.2, 0.05, 0.05, 1.0)  # Red tint
		style.border_color = Color(0.8, 0.2, 0.2, 0.5)  # Red border
		add_theme_stylebox_override("panel", style)

func _animate_collapse() -> void:
	"""Collapse to header - shrink height and hide content"""
	if is_animating:
		return

	is_animating = true
	is_collapsed = true

	var title_text = "[color=#B3B3B3]Scene Plan"

	title_text += "[/color]"
	title_label.text = title_text

	# Ensure clickable after collapse
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	await CollapseAnimation.animate_collapse(self, COLLAPSED_HEIGHT, scroll_container)
	is_animating = false
	# Don't emit streaming_complete here - it's already emitted in complete()

func _animate_expand() -> void:
	"""Expand to show content"""
	if is_animating:
		return

	is_animating = true
	is_collapsed = false

	var title_text = "[color=#B3B3B3]Scene Plan[/color]"
	title_label.text = title_text
	await CollapseAnimation.animate_expand(self, FIXED_HEIGHT, scroll_container)
	is_animating = false
	_scroll_to_bottom()

func _gui_input(event: InputEvent) -> void:
	"""Handle clicks to toggle expand/collapse"""
	if not is_complete:
		return  # Only allow toggle after completion

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_collapsed:
				_animate_expand()
			else:
				_animate_collapse()

func _on_timeout() -> void:
	"""Handle timeout"""
	if is_complete:
		return
	complete("Timeout after %d seconds" % TIMEOUT_SECONDS)

func _exit_tree() -> void:
	if gui_input.is_connected(_gui_input):
		gui_input.disconnect(_gui_input)
	if timer:
		timer.stop()
	if timeout_timer:
		timeout_timer.stop()
