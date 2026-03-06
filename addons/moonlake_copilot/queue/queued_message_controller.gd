@tool
extends RefCounted

## Queued Message Controller - Manages queued messages when agent is streaming
##
## Responsibilities:
## - Queue messages when agent is busy
## - Display queued messages UI below todo list
## - Pop and send messages when streaming completes

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")

signal queue_emptied()

# UI References (set externally)
var queue_container: PanelContainer = null
var queue_content: Control = null
var queue_header: Label = null
var queue_close_button: Button = null

# State
var queued_messages: Array = []  # Array of {text: String, file_ids: Array}


func initialize(container: PanelContainer, content: Control, header: Label, close_btn: Button) -> void:
	queue_container = container
	queue_content = content
	queue_header = header
	queue_close_button = close_btn

	if queue_close_button:
		queue_close_button.pressed.connect(_on_close_pressed)


func add_message(text: String, file_ids: Array = []) -> void:
	queued_messages.append({"text": text, "file_ids": file_ids})
	_update_ui()


func pop_message() -> Dictionary:
	if queued_messages.is_empty():
		return {}
	var message = queued_messages.pop_front()
	_update_ui()
	return message


func has_messages() -> bool:
	return not queued_messages.is_empty()


func clear() -> void:
	queued_messages.clear()
	_update_ui()


func _update_ui() -> void:
	if not queue_container or not queue_content:
		return

	for child in queue_content.get_children():
		child.queue_free()

	if queued_messages.is_empty():
		queue_container.visible = false
		queue_emptied.emit()
		return

	queue_container.visible = true

	if queue_header:
		queue_header.text = "Queued messages (%d)" % queued_messages.size()

	for i in range(queued_messages.size()):
		var item = _create_message_item(i, queued_messages[i])
		queue_content.add_child(item)


func _create_message_item(index: int, message: Dictionary) -> Control:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var index_label = Label.new()
	index_label.text = "%d." % (index + 1)
	index_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	index_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ThemeConstants.apply_inter_font(index_label)
	hbox.add_child(index_label)

	var line_edit = LineEdit.new()
	line_edit.text = message.get("text", "")
	line_edit.editable = false
	line_edit.context_menu_enabled = true
	line_edit.selecting_enabled = true
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line_edit.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	line_edit.add_theme_color_override("font_uneditable_color", Color(0.9, 0.9, 0.9))
	var transparent_style = StyleBoxEmpty.new()
	line_edit.add_theme_stylebox_override("normal", transparent_style)
	line_edit.add_theme_stylebox_override("focus", transparent_style)
	line_edit.add_theme_stylebox_override("read_only", transparent_style)
	ThemeConstants.apply_inter_font(line_edit)
	TripleClickSelector.enable_triple_click_selection(line_edit)
	hbox.add_child(line_edit)

	var file_ids = message.get("file_ids", [])
	if not file_ids.is_empty():
		var file_label = Label.new()
		file_label.text = "[%d files]" % file_ids.size()
		file_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		file_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ThemeConstants.apply_inter_font(file_label)
		hbox.add_child(file_label)

	var remove_btn = Button.new()
	remove_btn.text = "x"
	remove_btn.flat = true
	remove_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	remove_btn.tooltip_text = "Remove from queue"
	remove_btn.pressed.connect(func(): _remove_message(index))
	remove_btn.mouse_entered.connect(func():
		remove_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	)
	remove_btn.mouse_exited.connect(func():
		remove_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	)
	hbox.add_child(remove_btn)

	return hbox


func _remove_message(index: int) -> void:
	if index >= 0 and index < queued_messages.size():
		queued_messages.remove_at(index)
		_update_ui()


func _on_close_pressed() -> void:
	clear()


static func create_ui(parent: VBoxContainer) -> Dictionary:
	var container = PanelContainer.new()
	container.visible = false
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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
	container.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(vbox)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(12)))
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_hbox)

	var header = Label.new()
	header.text = "Queued messages (0)"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	ThemeConstants.apply_inter_font(header, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
	var header_font = SystemFont.new()
	header_font.font_weight = 600
	header.add_theme_font_override("font", header_font)
	header_hbox.add_child(header)

	var close_btn = Button.new()
	close_btn.text = "x"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	close_btn.tooltip_text = "Clear queue"
	close_btn.mouse_entered.connect(func():
		close_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	)
	close_btn.mouse_exited.connect(func():
		close_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	)
	header_hbox.add_child(close_btn)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", int(ThemeConstants.spacing(4)))
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	parent.add_child(container)

	return {
		"container": container,
		"content": content,
		"header": header,
		"close_button": close_btn
	}
