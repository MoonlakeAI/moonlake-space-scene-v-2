@tool
extends Control

signal fix_all_pressed

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

var error_count: int = 0
var warning_count: int = 0
var is_tracking: bool = false
var _debuggers: Array[Node] = []

var _play_mode_label: Label
var _status_label: Label
var _fix_all_button: Button


func _ready() -> void:
	var is_macos = OS.get_name() == "macOS"
	var button_height = 60 if is_macos else 32
	var button_margin = button_height + 12

	custom_minimum_size = Vector2(340, button_height)
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = button_margin + 8
	offset_top = -button_margin
	offset_right = button_margin + 348
	offset_bottom = -12
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = ThemeConstants.COLORS.BG_USER_MESSAGE
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	panel_style.anti_aliasing = true
	panel_style.anti_aliasing_size = 2.0
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(hbox)

	_play_mode_label = Label.new()
	_play_mode_label.text = "PLAY MODE:"
	_play_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_play_mode_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
	_play_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ThemeConstants.apply_inter_font(_play_mode_label, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
	hbox.add_child(_play_mode_label)

	_status_label = Label.new()
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ThemeConstants.apply_inter_font(_status_label, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
	hbox.add_child(_status_label)

	_fix_all_button = Button.new()
	_fix_all_button.text = "Fix All"
	_fix_all_button.visible = false
	ThemeConstants.apply_inter_font(_fix_all_button, ThemeConstants.Typography.FONT_SIZE_SMALL)
	var fix_style = StyleBoxFlat.new()
	fix_style.bg_color = Color(0.3, 0.5, 0.8, 0.6)
	fix_style.corner_radius_top_left = 6
	fix_style.corner_radius_top_right = 6
	fix_style.corner_radius_bottom_left = 6
	fix_style.corner_radius_bottom_right = 6
	fix_style.content_margin_left = 8
	fix_style.content_margin_right = 8
	fix_style.content_margin_top = 2
	fix_style.content_margin_bottom = 2
	fix_style.anti_aliasing = true
	fix_style.anti_aliasing_size = 2.0
	var fix_hover = fix_style.duplicate()
	fix_hover.bg_color = Color(0.4, 0.6, 0.9, 0.8)
	_fix_all_button.add_theme_stylebox_override("normal", fix_style)
	_fix_all_button.add_theme_stylebox_override("hover", fix_hover)
	_fix_all_button.add_theme_stylebox_override("pressed", fix_hover)
	_fix_all_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_fix_all_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	_fix_all_button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	_fix_all_button.pressed.connect(func():
		fix_all_pressed.emit()
		visible = false
	)
	hbox.add_child(_fix_all_button)

	var close_button = Button.new()
	close_button.text = "✕"
	close_button.flat = true
	close_button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	close_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	close_button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	ThemeConstants.apply_inter_font(close_button, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
	close_button.pressed.connect(func(): visible = false)
	hbox.add_child(close_button)

	visible = false


func set_debuggers(debuggers: Array[Node]) -> void:
	_debuggers = debuggers


func start_tracking() -> void:
	is_tracking = true
	error_count = 0
	warning_count = 0
	visible = true
	_update_display()


func stop_tracking() -> void:
	is_tracking = false
	visible = (error_count > 0 or warning_count > 0)
	_update_display()


func _process(_delta: float) -> void:
	if not is_tracking:
		return

	var total_errors = 0
	var total_warnings = 0
	for debugger in _debuggers:
		if is_instance_valid(debugger):
			total_errors += debugger.get_error_count()
			total_warnings += debugger.get_warning_count()

	if total_errors != error_count or total_warnings != warning_count:
		error_count = total_errors
		warning_count = total_warnings
		_update_display()


func _update_display() -> void:
	if is_tracking:
		_play_mode_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
	else:
		_play_mode_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

	if error_count == 0 and warning_count == 0:
		_status_label.text = "Detecting issues"
		_fix_all_button.visible = false
	else:
		_status_label.text = "🔴 %d  ⚠️ %d" % [error_count, warning_count]
		_fix_all_button.visible = true
