@tool
extends RefCounted

const TRIPLE_CLICK_TIME_MS = 500

static func enable_triple_click_selection(label: Control) -> void:
	if not label.has_method("select_all"):
		return

	label.set_meta("_triple_click_count", 0)
	label.set_meta("_triple_click_last_time", 0)

	if not label.gui_input.is_connected(_on_label_gui_input):
		label.gui_input.connect(_on_label_gui_input.bind(label))

	label.mouse_filter = Control.MOUSE_FILTER_STOP


static func _on_label_gui_input(event: InputEvent, label: Control) -> void:
	if not (event is InputEventMouseButton):
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	var current_time = Time.get_ticks_msec()
	var last_time = label.get_meta("_triple_click_last_time", 0)
	var click_count = label.get_meta("_triple_click_count", 0)

	if current_time - last_time > TRIPLE_CLICK_TIME_MS:
		click_count = 1
	else:
		click_count += 1

	label.set_meta("_triple_click_count", click_count)
	label.set_meta("_triple_click_last_time", current_time)

	if click_count >= 3:
		label.set_meta("_triple_click_count", 0)
		# Consume event to prevent default click handling from deselecting
		label.accept_event()
		# Defer selection to ensure it happens after all input processing
		_select_all_text_deferred.call_deferred(label)


static func _select_all_text_deferred(label: Control) -> void:
	_select_all_text(label)


static func _select_all_text(label: Control) -> void:
	if label.has_method("select_all"):
		label.select_all()
	elif label.has_method("select") and label.has_method("get_line_count"):
		var line_count = label.get_line_count()
		if line_count > 0:
			var last_line = line_count - 1
			var last_column = label.get_line(last_line).length()
			label.select(0, 0, last_line, last_column)
