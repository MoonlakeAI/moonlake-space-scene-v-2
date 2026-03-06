@tool
extends RefCounted

## Publish Controller - Manages publish progress panel above input box
##
## Responsibilities:
## - Display publish progress in a collapsible panel
## - Handle cancel/view URL actions
## - Track publish state (idle, publishing, success, error)

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

signal publish_started()
signal publish_completed(url: String)
signal publish_failed(error: String)
signal publish_cancelled()

enum State {
	IDLE,
	PUBLISHING,
	SUCCESS,
	ERROR,
}

# UI References
var container: PanelContainer = null
var header: Label = null
var header_hbox: HBoxContainer = null
var spinner: Control = null
var progress_log: RichTextLabel = null
var scroll_container: ScrollContainer = null
var cancel_button: Button = null
var view_button: Button = null
var close_button: Button = null

# State
var current_state: State = State.IDLE
var published_url: String = ""
var is_expanded: bool = true

var python_bridge: Node = null


func initialize(p_container: PanelContainer, p_header: Label, p_header_hbox: HBoxContainer, p_spinner: Control, p_progress_log: RichTextLabel, p_scroll_container: ScrollContainer, p_cancel_button: Button, p_view_button: Button, p_close_button: Button) -> void:
	container = p_container
	header = p_header
	header_hbox = p_header_hbox
	spinner = p_spinner
	progress_log = p_progress_log
	scroll_container = p_scroll_container
	cancel_button = p_cancel_button
	view_button = p_view_button
	close_button = p_close_button

	if header_hbox:
		header_hbox.gui_input.connect(_on_header_input)

	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)

	if view_button:
		view_button.pressed.connect(_on_view_pressed)

	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	_load_published_url()


func _load_published_url() -> void:
	var config = MoonlakeProjectConfig.get_singleton()
	if config:
		published_url = config.get_published_url()


func start_publish() -> void:
	current_state = State.PUBLISHING
	_clear_log()
	_log("Starting publish...")
	_update_ui()
	container.visible = true
	publish_started.emit()


func on_progress(message: String) -> void:
	# Handle cancelled messages - don't change state, just log
	if message.to_lower().contains("cancelled") or message.to_lower().contains("cancelling"):
		_log(message)
		return

	# Show container if hidden and ensure we're in publishing state
	if current_state == State.IDLE:
		current_state = State.PUBLISHING
		_update_ui()
	if container and not container.visible:
		container.visible = true

	_log(message)

	if message.contains("Deployed to "):
		published_url = message.replace("Deployed to ", "").strip_edges()

	if message.contains("Published successfully"):
		_on_publish_success()
	elif message.begins_with("[ERROR]") or message.contains("Failed"):
		_on_publish_error(message)


func _on_publish_success() -> void:
	current_state = State.SUCCESS
	_log("[color=green]Publish complete![/color]")

	# Save URL
	var config = MoonlakeProjectConfig.get_singleton()
	if config and not published_url.is_empty():
		config.set_published_url(published_url)
		_log("URL: " + published_url)
		DisplayServer.clipboard_set(published_url)
		_log("[color=gray]URL copied to clipboard[/color]")

	_update_ui()
	publish_completed.emit(published_url)

	# Auto-hide after 5 seconds
	if container:
		var timer = Timer.new()
		timer.one_shot = true
		timer.wait_time = 5.0
		timer.timeout.connect(func():
			if container and container.visible and current_state == State.SUCCESS:
				container.visible = false
				current_state = State.IDLE
			timer.queue_free()
		)
		container.add_child(timer)
		timer.start()


func _on_publish_error(error: String) -> void:
	current_state = State.ERROR
	_log("[color=red]" + error + "[/color]")
	_update_ui()
	publish_failed.emit(error)


func cancel_publish() -> void:
	if current_state != State.PUBLISHING:
		return

	_log("[color=yellow]Cancelling...[/color]")
	if python_bridge:
		python_bridge.call_python("cancel_publish", {})
	current_state = State.IDLE
	_log("[color=yellow]Cancelled[/color]")
	_update_ui()
	publish_cancelled.emit()

	# Hide panel after short delay
	if container:
		var timer = Timer.new()
		timer.one_shot = true
		timer.wait_time = 2.0
		timer.timeout.connect(func():
			if container and current_state == State.IDLE:
				container.visible = false
			timer.queue_free()
		)
		container.add_child(timer)
		timer.start()


func start_unpublish() -> void:
	current_state = State.PUBLISHING
	_clear_log()
	_log("Unpublishing project...")
	_update_ui()
	container.visible = true


func on_unpublish_complete(success: bool, error: String = "") -> void:
	if success:
		current_state = State.SUCCESS
		published_url = ""
		var config = MoonlakeProjectConfig.get_singleton()
		if config:
			config.set_published_url("")
		_log("[color=green]Project unpublished successfully[/color]")
	else:
		current_state = State.ERROR
		_log("[color=red]Unpublish failed: " + error + "[/color]")
	_update_ui()


func open_published_url() -> void:
	_load_published_url()
	if published_url.is_empty():
		_show_temporarily("No published URL found")
		return
	OS.shell_open(published_url)


func _show_temporarily(message: String) -> void:
	container.visible = true
	_clear_log()
	_log(message)
	_update_ui()

	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 3.0
	timer.timeout.connect(func():
		if current_state == State.IDLE:
			container.visible = false
		timer.queue_free()
	)
	container.add_child(timer)
	timer.start()


func _update_ui() -> void:
	if not container:
		return

	match current_state:
		State.IDLE:
			if header:
				header.text = "Publish"
			if spinner:
				spinner.visible = false
			if cancel_button:
				cancel_button.visible = false
			if view_button:
				view_button.visible = not published_url.is_empty()
			if close_button:
				close_button.visible = true

		State.PUBLISHING:
			if header:
				header.text = "Publishing..."
			if spinner:
				spinner.visible = true
			if cancel_button:
				cancel_button.visible = true
			if view_button:
				view_button.visible = false
			if close_button:
				close_button.visible = false

		State.SUCCESS:
			if header:
				header.text = "Published!"
			if spinner:
				spinner.visible = false
			if cancel_button:
				cancel_button.visible = false
			if view_button:
				view_button.visible = not published_url.is_empty()
			if close_button:
				close_button.visible = true

		State.ERROR:
			if header:
				header.text = "Publish Failed"
			if spinner:
				spinner.visible = false
			if cancel_button:
				cancel_button.visible = false
			if view_button:
				view_button.visible = not published_url.is_empty()
			if close_button:
				close_button.visible = true


func _log(message: String) -> void:
	if progress_log:
		progress_log.append_text(message + "\n")


func _clear_log() -> void:
	if progress_log:
		progress_log.clear()


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_expand()


func _toggle_expand() -> void:
	is_expanded = not is_expanded
	if scroll_container:
		scroll_container.visible = is_expanded


func _on_cancel_pressed() -> void:
	cancel_publish()


func _on_view_pressed() -> void:
	open_published_url()


func _on_close_pressed() -> void:
	container.visible = false
	current_state = State.IDLE


func hide_panel() -> void:
	if container:
		container.visible = false


static func create_ui(parent: VBoxContainer) -> Dictionary:
	var panel = PanelContainer.new()
	panel.visible = false
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.7, 0.9, 0.08)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.8, 1.0, 0.25)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.border_blend = true
	style.anti_aliasing = true
	style.corner_detail = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Header row
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	vbox.add_child(header_hbox)

	# Spinner
	var spinner_container = CenterContainer.new()
	spinner_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_hbox.add_child(spinner_container)

	var PulseSpinner = load("res://addons/moonlake_copilot/renderer/pulse_spinner.gd")
	var spinner = PulseSpinner.new()
	spinner.spinner_size = ThemeConstants.spacing(20.0)
	spinner.rotation_speed = 3.0
	spinner.visible = false
	spinner_container.add_child(spinner)

	# Header label
	var header = Label.new()
	header.text = "Publish"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	ThemeConstants.apply_inter_font(header, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
	var header_font = SystemFont.new()
	header_font.font_weight = 600
	header.add_theme_font_override("font", header_font)
	header_hbox.add_child(header)

	# View URL button
	var view_button = Button.new()
	view_button.text = "Open URL"
	view_button.flat = true
	view_button.visible = false
	view_button.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	view_button.add_theme_color_override("font_hover_color", Color(0.7, 0.9, 1.0))
	view_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_hbox.add_child(view_button)

	# Cancel button
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.flat = true
	cancel_button.visible = false
	cancel_button.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	cancel_button.add_theme_color_override("font_hover_color", Color(1.0, 0.4, 0.4))
	cancel_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_hbox.add_child(cancel_button)

	# Close button
	var close_button = Button.new()
	close_button.text = "×"
	close_button.flat = true
	close_button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.4, 0.4))
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_hbox.add_child(close_button)

	# Scroll container for progress log (capped at 120px height)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.custom_minimum_size.y = 120
	vbox.add_child(scroll)

	# Progress log
	var log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.selection_enabled = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8))
	ThemeConstants.apply_monospace_font(log_label, ThemeConstants.Typography.FONT_SIZE_SMALL)
	scroll.add_child(log_label)

	parent.add_child(panel)

	return {
		"container": panel,
		"header": header,
		"header_hbox": header_hbox,
		"spinner": spinner,
		"progress_log": log_label,
		"scroll_container": scroll,
		"cancel_button": cancel_button,
		"view_button": view_button,
		"close_button": close_button,
	}
