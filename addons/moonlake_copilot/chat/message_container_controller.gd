@tool
extends RefCounted

## Message Container Controller - Manages message cache, ordering, and lifecycle
##
## Responsibilities:
## - Message cache management (add, update, remove)
## - Message ordering and cleanup
## - Scroll control
## - Message widget creation and updates

const MessageRenderer = preload("res://addons/moonlake_copilot/renderer/message_renderer.gd")

# Signals
signal todo_list_updated(message: Dictionary)
signal empty_state_visibility_changed(visible: bool)
signal input_history_reset()
signal scroll_requested()
signal force_scroll_requested()
signal stop_message_received()
signal tool_use_received(tool_call_id: String)

var message_container: VBoxContainer = null
var scroll_container: ScrollContainer = null
var empty_state_center: Control = null
var new_message_toast: Button = null
var python_bridge: Node = null
var input_controller = null
var config = null

var message_cache: Dictionary = {}

var message_order: Array = []

var ephemeral_node: Control = null
var ephemeral_tween: Tween = null
var ephemeral_replacement_in_progress: bool = false
var ephemeral_removal_requested: bool = false

var is_restoring_session: bool = false
var is_user_scrolled_up: bool = false
var stop_message_was_received: bool = false
var _last_scroll_value: float = 0.0
var _last_scroll_max: float = 0.0

var animation_manager = null


func initialize(msg_container: VBoxContainer, scroll_cont: ScrollContainer, empty_state: Control, toast: Button, bridge: Node, cfg = null) -> void:
	message_container = msg_container
	scroll_container = scroll_cont
	empty_state_center = empty_state
	new_message_toast = toast
	python_bridge = bridge
	config = cfg

	if message_container:
		message_container.sort_children.connect(_on_container_sorted)

	if new_message_toast:
		new_message_toast.pressed.connect(_on_new_message_toast_pressed)

	if scroll_container:
		var vscroll = scroll_container.get_v_scroll_bar()
		if vscroll:
			vscroll.value_changed.connect(_on_scroll_value_changed)


## ============================================================================
## Message Handling (called via signals from MessageDispatcher)
## ============================================================================

func handle_add_message(data: Dictionary) -> void:
	"""Add new message to end"""
	var message: Dictionary = data.get("message", {})
	var message_id: String = message.get("id", "")

	if message_id.is_empty():
		Log.error("[MOONLAKE] add_message: missing message ID")
		return

	if message.get("type") == "error":
		Log.error("[MOONLAKE] Error message received: %s" % JSON.stringify(message))

	var content = message.get("content", {})
	var text = content.get("message", "") if content is Dictionary else ""
	if "stopped by user" in text.to_lower():
		stop_message_was_received = true
		stop_message_received.emit()

	if message.get("type", "") == "tool_use":
		var metadata = message.get("metadata", {})
		var tool_call_start_id = metadata.get("tool_call_start_id", "")
		if not tool_call_start_id.is_empty():
			tool_use_received.emit(tool_call_start_id)

	if message_cache.has(message_id):
		var existing_type = message_cache[message_id].get_meta("message_type", "")
		if existing_type == message.get("type", ""):
			return

	if message.get("type") == "todo_list":
		if not is_restoring_session:
			todo_list_updated.emit(message)

	if is_restoring_session:
		message["skip_typewriter"] = true
		message["skip_interactive_animation"] = true

	if not is_restoring_session:
		_collapse_previous_last_message()

	# Mark as last message so collapsible renderers start expanded
	# Skip during session restore to keep all messages collapsed
	if not is_restoring_session:
		message["is_last_message"] = true

	var widget := _create_message_widget(message)

	if widget == null:
		return

	message_container.add_child(widget)
	message_cache[message_id] = widget
	if message_id not in message_order:
		message_order.append(message_id)

	var message_type = message.get("type", "text")
	var is_conversation_message = message_type not in ["system_message", "info"]

	var conversation_message_count = 0
	for msg_id in message_order:
		var cached_widget = message_cache.get(msg_id)
		if cached_widget:
			var cached_type = cached_widget.get_meta("message_type", "text")
			if cached_type not in ["system_message", "info"]:
				conversation_message_count += 1

	if empty_state_center and conversation_message_count >= 1 and is_conversation_message:
		empty_state_visibility_changed.emit(false)

	_scroll_to_max()
	_show_new_message_toast()


func handle_update_message(data: Dictionary) -> void:
	"""Update existing message by ID"""
	var message_id: String = data.get("message_id", "")
	var message: Dictionary = data.get("message", {})

	if not message_cache.has(message_id):
		Log.warn("[MOONLAKE] update_message: message not found: %s" % message_id)
		return

	# Update pinned todo list if this is a todo_list message
	if message.get("type") == "todo_list":
		todo_list_updated.emit(message)

	var widget: Control = message_cache[message_id]

	_update_message_widget(widget, message)

	_scroll_to_max()
	_show_new_message_toast()


func handle_append_to_message(data: Dictionary, streaming_coordinator) -> void:
	"""Append text delta to existing message (streaming)"""
	var message_id: String = data.get("message_id", "")
	var delta: String = data.get("delta", "")

	if streaming_coordinator:
		streaming_coordinator.last_streaming_activity = Time.get_ticks_msec() / 1000.0

	if not message_cache.has(message_id):
		Log.warn("[MOONLAKE] append_to_message: message not found: %s" % message_id)
		return

	var margin: Control = message_cache[message_id]
	var widget = _find_widget_with_method(margin, "append_delta")

	if widget:
		widget.append_delta(delta)


func handle_replace_ephemeral(data: Dictionary) -> void:
	"""Replace current ephemeral message with smooth transition"""
	if ephemeral_replacement_in_progress:
		return

	ephemeral_replacement_in_progress = true
	ephemeral_removal_requested = false

	var message: Dictionary = data.get("message", {})

	if ephemeral_node:
		var old_content = ephemeral_node.get_meta("content", {})
		var new_content = message.get("content", {})
		if old_content.get("message", "") == new_content.get("message", ""):
			ephemeral_replacement_in_progress = false
			return

	if ephemeral_tween and ephemeral_tween.is_valid():
		ephemeral_tween.kill()
	ephemeral_tween = null

	for child in message_container.get_children():
		if child.has_meta("is_ephemeral"):
			child.visible = false
			message_container.remove_child(child)
			child.queue_free()

	ephemeral_node = null

	await python_bridge.get_tree().process_frame
	await python_bridge.get_tree().process_frame

	if ephemeral_removal_requested:
		ephemeral_replacement_in_progress = false
		return

	ephemeral_node = _create_message_widget(message)

	if ephemeral_node == null:
		ephemeral_replacement_in_progress = false
		return

	ephemeral_node.set_meta("is_ephemeral", true)
	ephemeral_node.set_meta("content", message.get("content", {}))

	ephemeral_node.modulate.a = 0.0
	message_container.add_child(ephemeral_node)

	ephemeral_node.reset_size()

	await python_bridge.get_tree().process_frame

	if not ephemeral_node or not is_instance_valid(ephemeral_node):
		ephemeral_replacement_in_progress = false
		return

	ephemeral_tween = message_container.create_tween()
	ephemeral_tween.tween_property(ephemeral_node, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	_scroll_to_max()
	_show_new_message_toast()

	ephemeral_replacement_in_progress = false



func handle_remove_ephemeral(data: Dictionary) -> void:
	"""Remove current ephemeral message immediately"""
	ephemeral_removal_requested = true

	if ephemeral_node:
		if ephemeral_tween and ephemeral_tween.is_valid():
			ephemeral_tween.kill()
		ephemeral_tween = null

		ephemeral_node.visible = false
		message_container.remove_child(ephemeral_node)
		ephemeral_node.queue_free()
		ephemeral_node = null

	for child in message_container.get_children():
		if child.has_meta("is_ephemeral"):
			child.visible = false
			message_container.remove_child(child)
			child.queue_free()


func handle_replace_message_id(data: Dictionary) -> void:
	"""Replace local message ID with backend ID (optimistic UI)"""
	var old_id: String = data.get("old_id", "")
	var new_id: String = data.get("new_id", "")

	if not message_cache.has(old_id):
		Log.warn("[MOONLAKE] replace_message_id: old message not found: %s" % old_id)
		return

	var widget: Control = message_cache[old_id]
	message_cache.erase(old_id)
	message_cache[new_id] = widget
	widget.set_meta("message_id", new_id)

	var idx = message_order.find(old_id)
	if idx != -1:
		message_order[idx] = new_id
	else:
		Log.error("[MOONLAKE] Message ID %s found in cache but not in message_order - data inconsistency!" % old_id)

	input_history_reset.emit()


func handle_remove_message(data: Dictionary) -> void:
	"""Remove message (when hitting 1000 limit)"""
	var message_id: String = data.get("message_id", "")

	message_order.erase(message_id)

	if not message_cache.has(message_id):
		return

	var widget: Control = message_cache[message_id]
	message_cache.erase(message_id)
	widget.queue_free()


func handle_clear_messages(data: Dictionary) -> void:
	for child in message_container.get_children():
		if child != empty_state_center:
			child.queue_free()

	message_cache.clear()
	message_order.clear()
	ephemeral_node = null
	ephemeral_tween = null
	ephemeral_replacement_in_progress = false

	var should_clear_log = data.get("clear_editor_log", true)
	if should_clear_log:
		_clear_editor_log()

	empty_state_visibility_changed.emit(true)

	Log.info("[MOONLAKE] Cleared all messages")


func _clear_editor_log() -> void:
	"""Clear the Godot editor output log"""
	var editor_log = _find_editor_log(EditorInterface.get_base_control())
	if editor_log and editor_log.has_method("clear"):
		editor_log.clear()


func _find_editor_log(node: Node) -> Node:
	"""Recursively search for EditorLog node in the editor tree"""
	if node.get_class() == "EditorLog":
		return node

	for child in node.get_children():
		var result = _find_editor_log(child)
		if result:
			return result

	return null


## ============================================================================
## Message Widget Creation and Updates
## ============================================================================

func _create_message_widget(message: Dictionary) -> Control:
	"""Create message widget using MessageRenderer factory"""
	var widget = MessageRenderer.render_message(message, config)

	if widget == null:
		return null

	widget.set_meta("message_id", message.get("id", ""))
	widget.set_meta("message_type", message.get("type", "text"))
	widget.set_meta("content", message.get("content", {}))

	_inject_python_bridge_recursive(widget)

	_connect_resize_signal_recursive(widget)

	_connect_revert_buttons_recursive(widget)

	var wrapper = _wrap_message_with_max_width(widget, message.get("sender", "copilot"))
	return wrapper


func _inject_python_bridge_recursive(node: Node) -> void:
	if node.has_method("set_python_bridge"):
		node.set_python_bridge(python_bridge)
	elif "python_bridge" in node:
		node.python_bridge = python_bridge

	for child in node.get_children():
		_inject_python_bridge_recursive(child)


func _connect_resize_signal_recursive(node: Node) -> void:
	"""Recursively connect to resize signals from widgets that grow during streaming"""
	if node.has_signal("content_streaming"):
		if not node.is_connected("content_streaming", _on_message_widget_resized):
			node.connect("content_streaming", _on_message_widget_resized)

	elif node is Control:
		if not node.resized.is_connected(_on_message_widget_resized):
			node.resized.connect(_on_message_widget_resized)

	for child in node.get_children():
		_connect_resize_signal_recursive(child)


func _on_scroll_value_changed(value: float) -> void:
	if is_restoring_session:
		_last_scroll_value = value
		return

	var vscroll = scroll_container.get_v_scroll_bar()
	if not vscroll:
		return

	var max_val = vscroll.max_value

	if value < _last_scroll_value - 5 and max_val >= _last_scroll_max:
		_set_user_scrolled_up(true)
	elif value >= max_val - 20:
		_set_user_scrolled_up(false)

	_last_scroll_value = value
	_last_scroll_max = max_val


func _set_user_scrolled_up(scrolled_up: bool) -> void:
	is_user_scrolled_up = scrolled_up
	if not scrolled_up and new_message_toast:
		new_message_toast.visible = false


func _show_new_message_toast() -> void:
	if is_user_scrolled_up and new_message_toast:
		new_message_toast.visible = true


func _connect_revert_buttons_recursive(node: Node) -> void:
	"""Recursively find and connect revert buttons in user messages"""
	if node is Button and node.has_meta("snapshot_id"):
		var snapshot_id = node.get_meta("snapshot_id")
		if snapshot_id and not snapshot_id.is_empty():
			_update_revert_button_state(node)

			if not node.pressed.is_connected(_on_revert_button_pressed):
				node.pressed.connect(_on_revert_button_pressed.bind(snapshot_id))

	for child in node.get_children():
		_connect_revert_buttons_recursive(child)


func _update_revert_button_state(button: Button) -> void:
	if input_controller and input_controller.is_agent_streaming:
		button.disabled = true
		button.tooltip_text = "Cannot revert while agent is generating. Please wait or stop the agent."
		button.modulate = Color(1, 1, 1, 0.5)
	else:
		button.disabled = false
		button.tooltip_text = "Revert files to before this message"
		button.modulate = Color(1, 1, 1, 1)


func update_all_revert_buttons() -> void:
	if not message_container:
		return

	_update_revert_buttons_recursive(message_container)


func _update_revert_buttons_recursive(node: Node) -> void:
	if node is Button and node.has_meta("snapshot_id"):
		_update_revert_button_state(node)

	for child in node.get_children():
		_update_revert_buttons_recursive(child)


func _on_revert_button_pressed(snapshot_id: String) -> void:
	"""Handle revert button pressed - show confirmation dialog"""
	Log.info("[MessageContainer] Revert button pressed for snapshot: %s" % snapshot_id)

	var workdir = ProjectSettings.globalize_path("res://")
	var timestamp = _get_snapshot_timestamp(workdir, snapshot_id)

	var dialog = AcceptDialog.new()
	dialog.title = "Revert Files?"
	dialog.dialog_text = "This will restore your project files to before this message.\n\n"
	if timestamp:
		dialog.dialog_text += "Snapshot from: " + timestamp + "\n\n"
	dialog.dialog_text += "Conversation history will be preserved.\nThis action cannot be undone."
	dialog.ok_button_text = "Revert Files"
	dialog.min_size = Vector2(400, 200)
	dialog.confirmed.connect(func():
		_call_revert_to_message(snapshot_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	if python_bridge:
		python_bridge.add_child(dialog)
		dialog.popup_centered()
	else:
		Log.error("[MessageContainer] Cannot show dialog: python_bridge not found")


func _get_snapshot_timestamp(workdir: String, snapshot_id: String) -> String:
	var manifest_path = workdir + "/.moonlake/snapshots/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return ""

	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if not file:
		return ""

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		return ""

	var data = json.data
	if not data or not data.has("snapshots"):
		return ""

	var snapshots = data["snapshots"]
	if not snapshots.has(snapshot_id):
		return ""

	var snapshot_info = snapshots[snapshot_id]
	if snapshot_info.has("timestamp"):
		return snapshot_info["timestamp"]

	return ""


func _call_revert_to_message(snapshot_id: String) -> void:
	if not python_bridge:
		Log.error("[MessageContainer] Cannot revert: python_bridge not found")
		return

	if input_controller and input_controller.has_method("stop_agent"):
		input_controller.stop_agent()
		Log.info("[MessageContainer] Stopped agent before reverting")

	var params = {
		"message_id": snapshot_id,
		"workdir": ProjectSettings.globalize_path("res://")
	}

	Log.info("[MessageContainer] Calling revert_to_message with params: %s" % str(params))

	var result = await python_bridge.call_python_async("revert_to_message", params, 30.0)

	Log.info("[MessageContainer] Revert response: %s" % str(result))

	if not result.get("ok", false):
		var error_msg = result.get("error", "Unknown error")
		Log.error("[MessageContainer] Revert failed (Python error): " + error_msg)
	else:
		var response = result.get("result", {})
		if not response.get("success", false):
			var error_msg = response.get("error", "Unknown error")
			Log.error("[MessageContainer] Revert failed: " + error_msg)
		else:
			Log.info("[MessageContainer] Revert succeeded for snapshot: %s" % snapshot_id)


func _on_message_widget_resized() -> void:
	if is_restoring_session:
		_set_user_scrolled_up(false)
		return

	if is_user_scrolled_up:
		_show_new_message_toast()
		return

	_scroll_to_max()


func _wrap_message_with_max_width(widget: Control, sender: String) -> Control:
	"""Wrap message widget to enforce 70% max width with proper alignment"""
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	match sender:
		"user":
			margin.add_theme_constant_override("margin_left", 0)
			margin.add_child(widget)
			margin.set_meta("margin_percent", 0.3)
			margin.set_meta("is_user", true)
		_:
			margin.add_child(widget)

	margin.set_meta("message_id", widget.get_meta("message_id", ""))
	margin.set_meta("content", widget.get_meta("content", {}))

	return margin


func _update_message_widget(margin: Control, message: Dictionary) -> void:
	"""Update existing message widget"""
	var widget = _find_widget_with_method(margin, "update_message")

	if widget:
		widget.update_message(message)
	else:
		Log.warn("[MOONLAKE] No widget found with update_message method in message tree")


func _find_widget_with_method(node: Node, method_name: String) -> Node:
	"""Recursively find first child node that has the specified method"""
	if node.has_method(method_name):
		return node

	for child in node.get_children():
		var result = _find_widget_with_method(child, method_name)
		if result:
			return result

	return null




## ============================================================================
## Scroll Control
## ============================================================================

func _scroll_to_max(force: bool = false) -> void:
	if not scroll_container:
		return
	if not force and is_user_scrolled_up:
		return
	call_deferred("_do_scroll_to_max")


func _do_scroll_to_max() -> void:
	if not scroll_container:
		return
	await scroll_container.get_tree().process_frame
	var vscroll = scroll_container.get_v_scroll_bar()
	if vscroll:
		scroll_container.scroll_vertical = int(vscroll.max_value)


func force_scroll_to_bottom() -> void:
	_set_user_scrolled_up(false)
	_scroll_to_max(true)


func scroll_to_bottom() -> void:
	_scroll_to_max(false)


func _on_container_sorted() -> void:
	_scroll_to_max()


func _on_new_message_toast_pressed() -> void:
	_set_user_scrolled_up(false)
	_scroll_to_max(true)


## ============================================================================
## Animation Integration
## ============================================================================

func _collapse_previous_last_message() -> void:
	if animation_manager:
		animation_manager.collapse_previous_last_message()


func stop_all_animations() -> void:
	for message_id in message_cache:
		var widget = message_cache[message_id]
		_stop_animations_recursive(widget)


func set_animating_interactive(message_id: String) -> void:
	if message_id.is_empty():
		return

	if not message_cache.has(message_id):
		return

	var widget = message_cache[message_id]
	_start_animation_recursive(widget)


func _start_animation_recursive(node: Node) -> void:
	if node.has_method("start_animation"):
		node.start_animation()

	for child in node.get_children():
		_start_animation_recursive(child)


func cancel_pending_confirmations() -> void:
	for message_id in message_cache:
		var widget = message_cache[message_id]
		_cancel_confirmation_recursive(widget)


func _cancel_confirmation_recursive(node: Node) -> void:
	if node.has_method("cancel_confirmation"):
		node.cancel_confirmation()

	for child in node.get_children():
		_cancel_confirmation_recursive(child)


func _stop_animations_recursive(node: Node) -> void:
	if node.has_method("finish_animation"):
		node.finish_animation()

	for child in node.get_children():
		_stop_animations_recursive(child)


## ============================================================================
## Getters
## ============================================================================

func get_message_cache() -> Dictionary:
	"""Get message cache for input history navigation"""
	return message_cache


func get_message_order() -> Array:
	"""Get message order for input history navigation"""
	return message_order
