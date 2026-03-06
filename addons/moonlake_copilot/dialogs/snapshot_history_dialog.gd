@tool
extends AcceptDialog
class_name SnapshotHistoryDialog

var python_bridge: Node
var input_controller
var scroll_container: ScrollContainer
var list_container: VBoxContainer
var empty_label: Label
var loading_label: Label


func _init(bridge: Node, input_ctrl = null):
	python_bridge = bridge
	input_controller = input_ctrl
	title = "Snapshot History"
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog_close_on_escape = true
	keep_title_visible = true

	_build_ui()
	about_to_popup.connect(_on_about_to_popup)


func _ready() -> void:
	var scale = 2 if DisplayServer.screen_get_scale() > 1.0 else 1
	size = Vector2i(500 * scale, 600 * scale)
	min_size = size


func _build_ui() -> void:
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll_container)

	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 8)
	scroll_container.add_child(list_container)

	loading_label = Label.new()
	loading_label.text = "Loading snapshots..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loading_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loading_label.visible = false
	loading_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	list_container.add_child(loading_label)

	empty_label = Label.new()
	empty_label.text = "No snapshots available"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label.visible = false
	empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	list_container.add_child(empty_label)

	get_ok_button().visible = false


func _on_about_to_popup() -> void:
	_load_snapshots()


func _load_snapshots() -> void:
	if not python_bridge:
		Log.error("[SnapshotHistoryDialog] Cannot load snapshots: python_bridge not found")
		_show_error("Cannot load snapshots: python_bridge not found")
		return

	_show_loading()

	var workdir = ProjectSettings.globalize_path("res://")
	var params = {"workdir": workdir}
	var response = await python_bridge.call_python_async("list_snapshots", params, 10.0)

	if not response or not response.get("ok", false):
		var error_msg = response.get("error", "No response from Python") if response else "No response from Python"
		Log.error("[SnapshotHistoryDialog] Python call failed: " + error_msg)
		_show_error("Failed to call Python:\n" + error_msg)
		return

	var result = response.get("result", {})
	if not result.get("success", false):
		var error_msg = result.get("error", "Unknown error")
		Log.error("[SnapshotHistoryDialog] Failed to load snapshots: " + error_msg)
		_show_error("Failed to load snapshots:\n" + error_msg)
		return

	var snapshots = result.get("snapshots", [])
	if snapshots.is_empty():
		_show_empty_state()
		return

	_populate_list(snapshots)


func _clear_snapshot_entries() -> void:
	for child in list_container.get_children():
		if child != empty_label and child != loading_label:
			child.queue_free()


func _show_loading() -> void:
	_clear_snapshot_entries()
	empty_label.visible = false
	loading_label.visible = true


func _show_empty_state() -> void:
	_clear_snapshot_entries()
	loading_label.visible = false
	empty_label.visible = true


func _show_error(error_message: String) -> void:
	var error_dialog = AcceptDialog.new()
	error_dialog.title = "Error"
	error_dialog.dialog_text = error_message
	error_dialog.min_size = Vector2(400, 150)
	error_dialog.exclusive = false

	if python_bridge:
		python_bridge.add_child(error_dialog)
		error_dialog.popup_centered()
	else:
		Log.error("[SnapshotHistoryDialog] Cannot show error dialog: python_bridge not found")

	_show_empty_state()


func _populate_list(snapshots: Array) -> void:
	_clear_snapshot_entries()
	loading_label.visible = false
	empty_label.visible = false

	for i in range(snapshots.size()):
		var snapshot = snapshots[i]
		var entry = _create_snapshot_entry(snapshot)
		list_container.add_child(entry)

		if i < snapshots.size() - 1:
			var separator = HSeparator.new()
			list_container.add_child(separator)


func _create_snapshot_entry(snapshot: Dictionary) -> Control:
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(content_vbox)

	var message_text = snapshot.get("message_text", "")
	message_text = message_text.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if message_text.is_empty():
		message_text = "[No message]"

	var title_label = Label.new()
	title_label.text = message_text
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_text = true
	title_label.tooltip_text = message_text
	content_vbox.add_child(title_label)

	var file_count = int(snapshot.get("file_count", 0))
	var size_kb = int(snapshot.get("size_kb", 0))
	var timestamp = snapshot.get("timestamp", "Unknown")

	var subtitle_text = timestamp
	if file_count > 0:
		subtitle_text += "  •  " + str(file_count) + " files  •  " + str(size_kb) + " KB"

	var subtitle_label = Label.new()
	subtitle_label.text = subtitle_text
	subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_vbox.add_child(subtitle_label)

	var revert_button = Button.new()
	revert_button.text = "Revert"
	revert_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	revert_button.custom_minimum_size = Vector2(80, 0)
	var message_id = snapshot.get("message_id", "")
	revert_button.pressed.connect(_on_revert_pressed.bind(message_id, timestamp))
	hbox.add_child(revert_button)

	return margin


func _on_revert_pressed(message_id: String, timestamp: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Revert Files?"
	dialog.dialog_text = "This will restore your project files to before this message.\n\n"
	dialog.dialog_text += "Snapshot from: " + timestamp + "\n\n"
	dialog.dialog_text += "Conversation history will be preserved.\nThis action cannot be undone."
	dialog.ok_button_text = "Revert Files"
	dialog.min_size = Vector2(400, 200)
	dialog.exclusive = false
	dialog.confirmed.connect(func(): _call_revert(message_id))

	if python_bridge:
		python_bridge.add_child(dialog)
		dialog.popup_centered()
	else:
		Log.error("[SnapshotHistoryDialog] Cannot show dialog: python_bridge not found")


func _call_revert(message_id: String) -> void:
	if not python_bridge:
		Log.error("[SnapshotHistoryDialog] Cannot revert: python_bridge not found")
		_show_error("Cannot revert: python_bridge not found")
		return

	if input_controller and input_controller.has_method("stop_agent"):
		input_controller.stop_agent()

	var params = {
		"message_id": message_id,
		"workdir": ProjectSettings.globalize_path("res://")
	}

	var response = await python_bridge.call_python_async("revert_to_message", params, 30.0)

	if not response or not response.get("ok", false):
		var error_msg = response.get("error", "No response from Python") if response else "No response from Python"
		Log.error("[SnapshotHistoryDialog] Python call failed: " + error_msg)
		_show_error("Revert failed:\n" + error_msg)
		return

	var result = response.get("result", {})
	if result.get("success", false):
		hide()
	else:
		var error_msg = result.get("error", "Unknown error")
		Log.error("[SnapshotHistoryDialog] Revert failed: " + error_msg)
		_show_error("Revert failed:\n" + error_msg)
