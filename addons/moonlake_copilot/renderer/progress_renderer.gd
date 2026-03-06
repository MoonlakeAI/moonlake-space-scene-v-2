@tool
extends RefCounted

const PulseSpinner = preload("res://addons/moonlake_copilot/renderer/pulse_spinner.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const RendererCleanup = preload("res://addons/moonlake_copilot/renderer/renderer_cleanup.gd")

static var _current_widget: ProgressWidget = null


static func render(message: Dictionary) -> Control:
	if _current_widget and is_instance_valid(_current_widget):
		_current_widget._on_destroy()
	_current_widget = ProgressWidget.new()
	_current_widget.initialize(message)
	return _current_widget


class ProgressWidget extends PanelContainer:
	var message_label: RichTextLabel
	var progress_bar: ProgressBar
	var percentage_label: Label
	var spinner: Control
	var hide_timer: Timer

	const HIDE_DELAY := 5.0

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		RendererCleanup.connect_cleanup(_on_destroy)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(vbox)

		message_label = RichTextLabel.new()
		message_label.bbcode_enabled = true
		message_label.fit_content = true
		message_label.scroll_active = false
		message_label.selection_enabled = true
		message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		var transparent_style = Styles.transparent_label()
		message_label.add_theme_stylebox_override("normal", transparent_style)
		message_label.add_theme_stylebox_override("focus", transparent_style)

		ThemeConstants.apply_inter_font(message_label)
		message_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))

		vbox.add_child(message_label)

		var progress_row = HBoxContainer.new()
		progress_row.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
		progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(progress_row)

		var spinner_container = CenterContainer.new()
		spinner_container.custom_minimum_size = Vector2(int(ThemeConstants.spacing(32)), int(ThemeConstants.spacing(32)))
		spinner_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spinner = PulseSpinner.new()
		spinner.spinner_size = 28.0
		spinner.visible = false
		spinner_container.add_child(spinner)
		progress_row.add_child(spinner_container)

		progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(0, int(ThemeConstants.spacing(12)))
		progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress_bar.show_percentage = false

		progress_bar.add_theme_stylebox_override("fill", Styles.progress_bar_fill())
		progress_bar.add_theme_stylebox_override("background", Styles.progress_bar_background())

		progress_row.add_child(progress_bar)

		percentage_label = Label.new()
		ThemeConstants.apply_inter_font(percentage_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
		percentage_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		percentage_label.custom_minimum_size = Vector2(int(ThemeConstants.spacing(50)), 0)
		percentage_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress_row.add_child(percentage_label)

		hide_timer = Timer.new()
		hide_timer.wait_time = HIDE_DELAY
		hide_timer.one_shot = true
		hide_timer.timeout.connect(_on_hide_timeout)
		add_child(hide_timer)

		_apply_style()

	func _apply_style() -> void:
		add_theme_stylebox_override("panel", Styles.progress_panel())

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		var message_text = content.get("message", "")
		var percentage_done = content.get("percentage_done", 0.0)

		message_label.text = message_text.replace("[", "[lb]").replace("]", "[rb]")

		progress_bar.value = percentage_done
		percentage_label.text = "%d%%" % int(percentage_done)

		var skip_auto_start = message.get("skip_interactive_animation", false)
		if skip_auto_start:
			spinner.visible = false
		else:
			spinner.visible = percentage_done < 100.0

		call_deferred("_check_auto_hide")

	func start_animation() -> void:
		var percentage_done = progress_bar.value
		if percentage_done < 100.0:
			spinner.visible = true

	func finish_animation() -> void:
		spinner.visible = false

	func update_message(message: Dictionary) -> void:
		initialize(message)

	func _check_auto_hide() -> void:
		if progress_bar.value >= 100.0:
			if hide_timer.is_stopped():
				hide_timer.start()
		else:
			hide_timer.stop()

	func _on_hide_timeout() -> void:
		_on_destroy()

	func _on_destroy() -> void:
		if is_inside_tree():
			finish_animation()
			queue_free()
