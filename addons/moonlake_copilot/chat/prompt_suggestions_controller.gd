@tool
extends RefCounted

## Prompt Suggestions Controller - Manages suggestion chips above attachments
##
## Responsibilities:
## - Store suggestions when received from Python
## - Display suggestion chips when conditions are met
## - Handle suggestion clicks (send message)
## - Hide during streaming, play mode, or when attachments visible

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

signal suggestion_selected(text: String)
signal suggestions_shown()

# UI References
var suggestions_wrapper: MarginContainer = null
var suggestions_container: HFlowContainer = null
var attachment_wrapper: Control = null

# External references
var message_dispatcher = null
var queued_message_controller = null

# State
var stored_suggestions: Array = []
var is_streaming: bool = false

const MAX_VISIBLE_SUGGESTIONS = 3


func initialize(wrapper: MarginContainer, container: HFlowContainer, attach_wrapper: Control) -> void:
	suggestions_wrapper = wrapper
	suggestions_container = container
	attachment_wrapper = attach_wrapper


func set_message_dispatcher(dispatcher) -> void:
	message_dispatcher = dispatcher
	if message_dispatcher:
		message_dispatcher.is_streaming_changed.connect(_on_streaming_changed)
		message_dispatcher.prompt_suggestions_ready.connect(_on_suggestions_ready)


func set_queued_message_controller(controller) -> void:
	queued_message_controller = controller
	if queued_message_controller:
		queued_message_controller.queue_emptied.connect(_try_show_suggestions)


func _on_streaming_changed(streaming: bool) -> void:
	is_streaming = streaming
	if is_streaming:
		_hide_suggestions()
	else:
		_try_show_suggestions()


func _on_suggestions_ready(suggestions: Array) -> void:
	stored_suggestions = suggestions
	_try_show_suggestions()


func _try_show_suggestions() -> void:
	if _should_show():
		_show_suggestions()
	elif suggestions_wrapper and suggestions_wrapper.visible:
		_hide_suggestions()


func _should_show() -> bool:
	if stored_suggestions.size() == 0:
		return false
	if is_streaming:
		return false
	if message_dispatcher and message_dispatcher.was_agent_recently_streaming:
		return false
	if queued_message_controller and queued_message_controller.has_messages():
		return false
	if EditorInterface.is_playing_scene():
		return false
	if attachment_wrapper and attachment_wrapper.visible:
		return false
	return true


func _show_suggestions() -> void:
	if not suggestions_container or not suggestions_wrapper:
		return
	if not _should_show():
		return

	_clear_chips()

	var suggestions_to_show = stored_suggestions.slice(-MAX_VISIBLE_SUGGESTIONS)

	for suggestion_text in suggestions_to_show:
		var chip = _create_suggestion_chip(suggestion_text)
		suggestions_container.add_child(chip)

	suggestions_wrapper.visible = true
	suggestions_shown.emit()


func _hide_suggestions() -> void:
	if suggestions_wrapper:
		suggestions_wrapper.visible = false


func _clear_chips() -> void:
	if not suggestions_container:
		return
	for child in suggestions_container.get_children():
		child.queue_free()


func clear_suggestions() -> void:
	stored_suggestions.clear()
	_hide_suggestions()
	_clear_chips()


func on_play_mode_changed(is_playing: bool) -> void:
	if is_playing:
		_hide_suggestions()
	else:
		_try_show_suggestions()


func on_attachments_changed() -> void:
	if attachment_wrapper and attachment_wrapper.visible:
		_hide_suggestions()
	else:
		_try_show_suggestions()


func _create_suggestion_chip(text: String) -> Button:
	var chip = Button.new()
	chip.text = "✨ " + text
	chip.tooltip_text = text
	chip.flat = false
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size.x = 150
	chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color(0.35, 0.35, 0.35)
	normal_style.set_corner_radius_all(8)
	normal_style.content_margin_left = 12
	normal_style.content_margin_right = 12
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	chip.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.32, 0.32, 0.32, 0.95)
	hover_style.border_color = Color(0.45, 0.45, 0.45)
	chip.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.2, 0.2, 0.2, 0.95)
	chip.add_theme_stylebox_override("pressed", pressed_style)

	chip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	chip.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	chip.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7))

	ThemeConstants.apply_inter_font(chip, ThemeConstants.Typography.FONT_SIZE_SMALL)

	chip.pressed.connect(func(): _on_suggestion_clicked(text))

	return chip


func _on_suggestion_clicked(text: String) -> void:
	clear_suggestions()
	suggestion_selected.emit(text)
