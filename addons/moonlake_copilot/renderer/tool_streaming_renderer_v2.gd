@tool
extends PanelContainer

## ToolStreamingRendererV2
##
## Handles message type: "tool_call_start" (streaming tool execution)
##
## Renders real-time tool parameter streaming with typewriter animation.
##
## Visual design:
## - Blue-bordered terminal (distinguishes from regular tool results)
## - CodeEdit with line numbers
## - JSON syntax highlighting (tool parameters)
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
var icon_label: TextureRect
var title_label: RichTextLabel
var scroll_container: ScrollContainer
var code_edit: CodeEdit
var timer: Timer
var timeout_timer: Timer

# State
var tool_name: String = ""
var file_path: String = ""
var description: String = ""
var message_type: String = ""  # For debug display
var tool_input: String = ""  # Full JSON tool input for display
var full_content: String = ""
var revealed_chars: float = 0.0
var pending_buffer: String = ""
var is_complete: bool = false
var large_content_warned: bool = false
var is_collapsed: bool = false  # Track collapse state
var is_animating: bool = false  # Prevent concurrent animations
var is_user_scrolled_up: bool = false
var is_programmatic_scroll: bool = false

# Constants - Override animation speed for tool streaming (faster than thinking renderer)
const CHARS_PER_SEC = AnimationConstants.FAST_CHARS_PER_SEC
const TIMER_INTERVAL = AnimationConstants.TIMER_INTERVAL
const CHARS_PER_FRAME = AnimationConstants.FAST_CHARS_PER_FRAME
const MAX_BUFFER_SIZE = AnimationConstants.MAX_BUFFER_SIZE
const TIMEOUT_SECONDS = 180.0  # 3 minutes for large files
const COLLAPSED_HEIGHT = AnimationConstants.COLLAPSED_HEIGHT

signal streaming_complete

func _init() -> void:
	# DPI-adjusted fixed height
	var fixed_height = ThemeConstants.spacing(300.0)
	custom_minimum_size = Vector2(0, fixed_height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP  # Enable click detection
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND  # Show pointer on hover
	set_meta("message_type", "tool_streaming")
	_apply_terminal_style()

	var main_hbox = HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var main_separation = int(ThemeConstants.spacing(10))
	main_hbox.add_theme_constant_override("separation", main_separation)
	add_child(main_hbox)

	# Icon using TextureRect
	var icon_rect = TextureRect.new()
	var icon_size = int(ThemeConstants.spacing(20))
	icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = EditorInterface.get_editor_theme().get_icon("Play", "EditorIcons")
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

	# Content column
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox_separation = int(ThemeConstants.spacing(8))
	content_vbox.add_theme_constant_override("separation", vbox_separation)
	main_hbox.add_child(content_vbox)

	# Title (RichTextLabel for BBCode)
	title_label = RichTextLabel.new()
	title_label.bbcode_enabled = true
	title_label.fit_content = true
	title_label.scroll_active = false
	title_label.selection_enabled = false
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS  # Let clicks pass through to panel

	ThemeConstants.apply_inter_font(title_label, ThemeConstants.Typography.FONT_SIZE_SMALL)

	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color(0, 0, 0, 0)
	ThemeConstants.apply_dpi_padding_custom(header_style, 0, 8, 4, 0)
	title_label.add_theme_stylebox_override("normal", header_style)
	title_label.add_theme_stylebox_override("focus", header_style)
	content_vbox.add_child(title_label)

	# Scrollable content
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_vbox.add_child(scroll_container)

	# CodeEdit for streaming content
	code_edit = CodeEdit.new()
	code_edit.editable = false  # Read-only
	code_edit.gutters_draw_line_numbers = true  # YES - line numbers for tool parameters
	code_edit.indent_automatic = false
	code_edit.auto_brace_completion_highlight_matching = false
	code_edit.selecting_enabled = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY  # Wrap at word boundaries
	code_edit.scroll_fit_content_height = true
	code_edit.scroll_horizontal = false
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Disable syntax highlighting - use plain text for visibility
	# EditorJSONSyntaxHighlighter uses dark colors that are unreadable on dark background
	code_edit.syntax_highlighter = null

	ThemeConstants.apply_monospace_font(code_edit)

	code_edit.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))  # Light gray

	# Transparent background for CodeEdit (terminal panel provides background)
	var transparent_style = Styles.terminal_content()
	transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
	code_edit.add_theme_stylebox_override("normal", transparent_style)
	code_edit.add_theme_stylebox_override("focus", transparent_style)

	# Disable gutter interactions (read-only widget)
	code_edit.gutters_draw_breakpoints_gutter = false
	code_edit.gutters_draw_bookmarks = false
	code_edit.gutters_draw_executing_lines = false

	scroll_container.add_child(code_edit)

	var vscroll = scroll_container.get_v_scroll_bar()
	if vscroll:
		vscroll.scrolling.connect(_on_user_scrolling)

	# Enable triple-click to select all text
	TripleClickSelector.enable_triple_click_selection(code_edit)

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

func initialize(tool_name_param: String, file_path_param: String, description_param: String = "", message_type_param: String = "") -> void:
	"""Initialize renderer with tool info"""
	tool_name = tool_name_param
	file_path = file_path_param
	description = description_param
	message_type = message_type_param

	title_label.text = "Tool: Streaming..."
	# Start timers after widget is in scene tree
	call_deferred("_start_timers")

func _start_timers() -> void:
	"""Start timers after widget is added to scene tree"""
	if not is_inside_tree():
		Log.warn("[ToolStreamingRendererV2] Not in scene tree yet, deferring timer start")
		call_deferred("_start_timers")
		return

	if timer.is_stopped():
		timer.start()
	if timeout_timer.is_stopped():
		timeout_timer.start()

func set_description(desc: String) -> void:
	"""Set the description (called when tool_call_stop provides full input)"""
	description = desc

func set_tool_input(input: String) -> void:
	"""Set the full tool input JSON (for display if no output content)"""
	tool_input = input

func append_delta(delta: String) -> void:
	"""Append streaming content delta"""
	# Python backend now extracts content field for Write/Edit tools
	# So we just display the delta directly (already processed)

	# Note: For Write/Edit tools, Python sends extracted content (unescaped)
	# For other tools, Python sends raw JSON (needs unescaping)
	var processed_delta = delta
	if tool_name not in ["Write", "Edit"]:
		# Unescape for non-Write/Edit tools (raw JSON)
		processed_delta = delta.replace("\\n", "\n").replace("\\\"", "\"")

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

func _on_user_scrolling() -> void:
	if is_programmatic_scroll:
		return
	var vscroll = scroll_container.get_v_scroll_bar() if scroll_container else null
	if vscroll:
		var at_bottom = scroll_container.scroll_vertical >= vscroll.max_value - vscroll.page - 20
		if not at_bottom:
			is_user_scrolled_up = true
		else:
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
		is_programmatic_scroll = true
		scroll_container.scroll_vertical = int(vscroll.max_value)
		is_programmatic_scroll = false

func complete(error: String = "") -> void:
	"""Complete streaming and collapse"""
	timeout_timer.stop()
	is_complete = true

	if error != "":
		_apply_error_style()
		code_edit.text += "\n\n[ERROR] " + error
		await get_tree().create_timer(2.0).timeout

	_flush_buffer()
	timer.stop()

	# Extract query for WebSearch after streaming complete
	if tool_name == "WebSearch" and description == "":
		var parsed = JSON.parse_string(full_content)
		if parsed is Dictionary and parsed.has("query"):
			description = parsed["query"]

	if code_edit.text.strip_edges().is_empty():
		if tool_input != "":
			# Display the tool input JSON (prettified if possible)
			var parsed = JSON.parse_string(tool_input)
			if parsed != null:
				code_edit.text = JSON.stringify(parsed, "  ", false)
			else:
				code_edit.text = tool_input
		else:
			code_edit.text = "(No output - tool completed successfully)"
			code_edit.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))  # Gray/dim

	_animate_collapse()

	# Emit completion signal for coordinator tracking (widget stays visible)
	streaming_complete.emit()

func finish_animation() -> void:
	"""Immediately finish animation (called by _finish_all_animations on stop)"""
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

	var title_text = "Tool: " + tool_name
	if description != "":
		var short_desc = description
		if "/" in description or "\\" in description:
			short_desc = description.get_file()
		title_text += " (" + short_desc + ")"
	title_label.text = title_text

	# Ensure clickable after collapse
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	await CollapseAnimation.animate_collapse(self, COLLAPSED_HEIGHT, scroll_container)
	is_animating = false
	# Don't emit streaming_complete - widget should stay visible

func _animate_expand() -> void:
	"""Expand to show content"""
	if is_animating:
		return

	is_animating = true
	is_collapsed = false

	var title_text = "Tool: " + tool_name
	if description != "":
		var short_desc = description
		if "/" in description or "\\" in description:
			short_desc = description.get_file()
		title_text += " (" + short_desc + ")"
	title_label.text = title_text
	await CollapseAnimation.animate_expand(self, ThemeConstants.spacing(300.0), scroll_container)
	is_animating = false
	_scroll_to_bottom()

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

func _gui_input(event: InputEvent) -> void:
	"""Handle clicks to toggle expand/collapse"""
	# Allow expand/collapse at any time (even during streaming)
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
