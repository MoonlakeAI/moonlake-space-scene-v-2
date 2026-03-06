@tool
extends RefCounted

const ChatPanelUIBuilder = preload("res://addons/moonlake_copilot/chat/chat_panel_ui_builder.gd")
const RendererCleanup = preload("res://addons/moonlake_copilot/renderer/renderer_cleanup.gd")
const PythonBridge = preload("res://addons/moonlake_copilot/core/python_bridge.gd")

# Signals
signal message_sent(text: String)
signal stop_requested()  # Emitted when stop is initiated (before ack)
signal stop_completed()  # Emitted when streaming ends (natural or user-initiated)
signal user_stop_completed()  # Emitted only when user clicks stop AND stop_generation is acked

# UI References (set externally)
var input_box: CodeEdit = null
var send_button: Button = null
var python_bridge: Node = null

# Mode selection UI references
var mode_dropdown: Button = null

# External references
var attachment_manager = null
var message_container_controller = null
var queued_message_controller = null
var message_dispatcher = null

# State
var session_token: String = ""
var is_agent_streaming: bool = false
var skip_next_queue_process: bool = false
var selected_mode: String = ""  # "" | "prototype-games" | "generate-3d-world"
var first_message_sent: bool = false

# Paste thresholds
const PASTE_TEXT_THRESHOLD: int = 20000  # Characters - paste text as attachment if larger

# History navigation
var input_history_index: int = -1
var unsent_text_buffer: String = ""


func initialize(input: CodeEdit, send_btn: Button, bridge: Node) -> void:
	input_box = input
	send_button = send_btn
	python_bridge = bridge

	if input_box:
		input_box.text_changed.connect(_on_input_box_text_changed)

	if send_button:
		send_button.pressed.connect(func(): _on_send_pressed(false))

	update_send_button_state()


func handle_input_event(event: InputEvent) -> bool:
	"""
	Handle keyboard input for message sending and history navigation.

	Returns true if event was handled, false otherwise.
	"""
	if not input_box or not input_box.has_focus():
		return false

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			if event.shift_pressed:
				# Shift+Enter: manually insert newline (CodeEdit doesn't handle this by default)
				input_box.insert_text_at_caret("\n")
				return true
			else:
				# Plain Enter: always send message (bypass stop)
				_on_send_pressed(true)
				return true

		elif event.keycode == KEY_ESCAPE:
			DisplayServer.beep()
			var escape_enabled = ProjectSettings.get_setting("moonlake/agent_behavior/escape_key_stops_agent", false)
			if escape_enabled and is_agent_streaming:
				_send_stop_command()
			return true

		elif event.keycode == KEY_UP:
			# Up arrow: navigate to older message only if cursor is on first line
			if _is_cursor_on_first_line():
				_navigate_history_up()
				return true
			# Otherwise, let CodeEdit handle cursor movement
			return false

		elif event.keycode == KEY_DOWN:
			# Down arrow: navigate to newer message only if cursor is on last line
			if _is_cursor_on_last_line():
				_navigate_history_down()
				return true
			# Otherwise, let CodeEdit handle cursor movement
			return false

		elif event.keycode == KEY_V and event.is_command_or_control_pressed():
			# Ctrl+V / Cmd+V: handle paste with attachment logic
			if _handle_paste_with_attachments():
				return true
			# Otherwise, let normal paste happen
			return false

	return false


func _is_cursor_on_first_line() -> bool:
	"""Check if cursor is on the first line of input box"""
	return input_box.get_caret_line() == 0


func _is_cursor_on_last_line() -> bool:
	"""Check if cursor is on the last line of input box"""
	var last_line = input_box.get_line_count() - 1
	return input_box.get_caret_line() == last_line


## ============================================================================
## Send Button and Message Sending
## ============================================================================

func update_send_button_state() -> void:
	if not send_button:
		return

	if is_agent_streaming:
		var stop_icon = send_button.get_theme_icon("Stop", "EditorIcons")
		if stop_icon:
			send_button.icon = stop_icon
		send_button.tooltip_text = "Stop agent (Interrupt generation)"
		send_button.disabled = false
	else:
		var arrow_icon = send_button.get_theme_icon("ArrowUp", "EditorIcons")
		if arrow_icon:
			send_button.icon = arrow_icon
		send_button.tooltip_text = "Send message (Enter)"
		var has_text = input_box and not input_box.text.strip_edges().is_empty()
		send_button.disabled = not has_text

	_apply_button_icon_color()
	call_deferred("_apply_button_icon_color")


func _apply_button_icon_color() -> void:
	"""Apply black icon color - called multiple times to ensure it sticks"""
	if send_button:
		send_button.add_theme_color_override("icon_normal_color", Color(0.0, 0.0, 0.0, 1.0))
		send_button.add_theme_color_override("icon_hover_color", Color(0.0, 0.0, 0.0, 1.0))
		send_button.add_theme_color_override("icon_pressed_color", Color(0.0, 0.0, 0.0, 1.0))
		send_button.add_theme_color_override("icon_focus_color", Color(0.0, 0.0, 0.0, 1.0))
		send_button.add_theme_color_override("icon_disabled_color", Color(0.5, 0.5, 0.5, 1.0))
		# Force visual update
		send_button.queue_redraw()
		send_button.update_minimum_size()


func _on_send_pressed(bypass_stop: bool = false) -> void:
	"""Handle send button - dynamically send or stop based on streaming state"""
	if is_agent_streaming and not bypass_stop:
		# Stop mode: send /stop command
		_send_stop_command()
		return

	# Send mode: send user message
	var text = input_box.text.strip_edges()
	if text.is_empty():
		return

	var backend_streaming = message_dispatcher and message_dispatcher.was_agent_recently_streaming
	# Slash commands that should execute immediately (bypass queue)
	var immediate_commands = ["/publish", "/unpublish", "/clear", "/stop", "/yolo"]
	var is_immediate_slash = false
	for cmd in immediate_commands:
		if text.begins_with(cmd):
			is_immediate_slash = true
			break

	if (is_agent_streaming or backend_streaming) and queued_message_controller and not is_immediate_slash:
		var file_ids = _collect_file_ids()
		queued_message_controller.add_message(text, file_ids)
		input_box.text = ""
		if attachment_manager:
			attachment_manager.clear_attachments()
		return

	# Reset history navigation state
	reset_history_navigation()

	# Clear input
	input_box.text = ""

	# Update placeholder with new random tip
	_update_placeholder_text()

	# Send via message system
	send_user_message(text)


func _update_placeholder_text() -> void:
	"""Update input box placeholder with new random tip"""
	if not input_box:
		return

	input_box.placeholder_text = ChatPanelUIBuilder.PLACEHOLDER_GREETING + ChatPanelUIBuilder._get_weighted_random_tip()


func _send_stop_command() -> void:
	_play_stop_feedback()
	stop_requested.emit()
	is_agent_streaming = false
	skip_next_queue_process = true
	if message_dispatcher:
		message_dispatcher.was_agent_recently_streaming = true
	update_send_button_state()
	stop_completed.emit()
	var _result = await python_bridge.call_python_async("stop_generation", {})
	user_stop_completed.emit()
	RendererCleanup.notify_user_stopped()


func _play_stop_feedback() -> void:
	if send_button:
		_flash_button(send_button)


func _flash_button(button: Button) -> void:
	var original_modulate = button.modulate
	var flash_color = Color(1.0, 0.3, 0.3, 1.0)  # Red flash
	button.modulate = flash_color

	var tween = button.create_tween()
	tween.tween_property(button, "modulate", original_modulate, 0.15)


func send_user_message(text: String, display_text: String = "", uuid: String = "") -> void:
	"""
	Send user message via python_bridge.

	Generates local_message_id for optimistic UI.
	"""
	var local_message_id = uuid if not uuid.is_empty() else _generate_uuid()
	var dtext = display_text if not display_text.is_empty() else text

	if not python_bridge:
		Log.error("[MOONLAKE] PythonBridge not found")
		return

	# Set streaming state when user sends message (agent will start working)
	# Skip for slash commands - they complete immediately and send stream_complete
	var is_slash_command = text.begins_with("/")
	if not is_slash_command:
		is_agent_streaming = true
		if message_dispatcher:
			message_dispatcher.was_agent_recently_streaming = true
		update_send_button_state()

	skip_next_queue_process = false

	# Emit signal that message was sent (for scroll handling)
	message_sent.emit(text)

	# Collect attachments from attachment manager
	# Only include completed uploads, cancel any still uploading
	var file_ids = []
	var files = []
	if not attachment_manager:
		Log.warn("[InputController] attachment_manager is null! Attachments will not be sent. Check initialization order in chat_panel_v2.gd")
	else:
		var uploading_attachments = []
		for attachment in attachment_manager.get_attachments():
			if attachment.get("uploading", false):
				# Still uploading - mark for cancellation
				uploading_attachments.append(attachment)
			else:
				# Upload complete - include in message
				var file_id = attachment.get("file_id", "")
				if not file_id.is_empty():
					file_ids.append(file_id)
					files.append({
						"id": file_id,
						"file_url": attachment.get("url", ""),
						"filename": attachment.get("name", file_id)
					})

		# Cancel uploading attachments
		for attachment in uploading_attachments:
			attachment_manager.remove_attachment(attachment)

	# Build message payload
	var payload = PythonBridge.make_message_payload(local_message_id, text, dtext)
	payload["file_ids"] = file_ids
	payload["files"] = files
	payload["session_token"] = session_token

	# Include mode in first message only (if selected)
	if not first_message_sent and not selected_mode.is_empty():
		payload["mode"] = selected_mode
		Log.info("[MOONLAKE] Including mode in message: %s" % selected_mode)

	# Hide mode selection UI after first message (regardless of whether mode was selected)
	if not first_message_sent:
		_hide_mode_selection()
		first_message_sent = true

	python_bridge.call_python("send_user_message", payload)

	# Clear attachments after sending
	if attachment_manager:
		attachment_manager.clear_attachments()


func _generate_uuid() -> String:
	"""Generate simple UUID for local messages"""
	return "%08x-%04x-%04x-%04x-%012x" % [
		randi(),
		randi() & 0xffff,
		(randi() & 0x0fff) | 0x4000,
		(randi() & 0x3fff) | 0x8000,
		(randi() << 32) | randi()
	]


## ============================================================================
## Input Box Text Changed
## ============================================================================

func _on_input_box_text_changed() -> void:
	if input_history_index != -1:
		reset_history_navigation()
	update_send_button_state()


func reset_history_navigation() -> void:
	"""Reset history navigation state"""
	input_history_index = -1
	unsent_text_buffer = ""


## ============================================================================
## History Navigation
## ============================================================================

func _get_user_message_history() -> PackedStringArray:
	"""Extract user messages from conversation history in chronological order"""
	var history: PackedStringArray = []

	if not message_container_controller:
		return history

	var msg_cache = message_container_controller.get_message_cache()
	var msg_order = message_container_controller.get_message_order()

	for message_id in msg_order:
		var widget = msg_cache.get(message_id)
		if widget == null:
			Log.warn("[MOONLAKE] Message ID in message_order but not in cache: %s" % message_id)
			continue

		# Check if this is a user message (has "is_user" metadata)
		if widget.has_meta("is_user") and widget.get_meta("is_user", false):
			var content = widget.get_meta("content", {})
			if content.has("message"):
				var text = content.get("message", "").strip_edges()
				if text.length() > 0:
					history.append(text)

	return history


func _navigate_history_up() -> void:
	"""Navigate to older message in history (Up arrow)"""
	var history = _get_user_message_history()

	if history.size() == 0:
		return  # No history available

	# First time navigating? Save current unsent text
	if input_history_index == -1:
		unsent_text_buffer = input_box.text
		input_history_index = history.size()  # Start at end (most recent)

	# Move up (older message)
	if input_history_index > 0:
		input_history_index -= 1
		input_box.text = history[input_history_index]
		# Move cursor to end
		input_box.set_caret_column(input_box.text.length())
		input_box.set_caret_line(input_box.get_line_count() - 1)


func _navigate_history_down() -> void:
	"""Navigate to newer message in history (Down arrow)"""
	var history = _get_user_message_history()

	if input_history_index == -1:
		return  # Not currently navigating

	# Move down (newer message)
	if input_history_index < history.size() - 1:
		input_history_index += 1
		input_box.text = history[input_history_index]
		# Move cursor to end
		input_box.set_caret_column(input_box.text.length())
		input_box.set_caret_line(input_box.get_line_count() - 1)
	else:
		# Reached end of history - restore unsent text
		input_history_index = -1
		input_box.text = unsent_text_buffer
		unsent_text_buffer = ""
		# Move cursor to end
		input_box.set_caret_column(input_box.text.length())
		input_box.set_caret_line(input_box.get_line_count() - 1)


## ============================================================================
## Paste Handling with Attachments
## ============================================================================

func _handle_paste_with_attachments() -> bool:
	"""
	Handle paste with attachment logic.
	Returns true if paste was handled as attachment, false to let normal paste happen.
	"""
	if not attachment_manager:
		return false

	# Check if clipboard has image first (more specific check)
	if DisplayServer.clipboard_has_image():
		_handle_paste_image()
		return true

	# Check if clipboard has text above threshold
	var clipboard_text = DisplayServer.clipboard_get()
	if clipboard_text.length() > PASTE_TEXT_THRESHOLD:
		_handle_paste_large_text()
		return true

	# Let normal paste happen for small text
	return false


func _handle_paste_image() -> void:
	"""Handle pasting an image from clipboard - save to temp file and upload"""
	var image = DisplayServer.clipboard_get_image()
	if image == null or image.is_empty():
		Log.warn("[InputController] Clipboard image is null or empty")
		return

	# Save image to temp file
	var temp_dir = OS.get_user_data_dir()
	var timestamp = Time.get_unix_time_from_system()
	var temp_path = temp_dir.path_join("clipboard_image_%d.png" % int(timestamp))

	var error = image.save_png(temp_path)
	if error != OK:
		Log.error("[InputController] Failed to save clipboard image: %s" % error_string(error))
		return

	Log.info("[InputController] Saved clipboard image to: %s" % temp_path)

	# Upload via attachment manager (same flow as file dialog)
	attachment_manager.handle_image_selected(temp_path)


func _handle_paste_large_text() -> void:
	"""Handle pasting large text - upload as clipboard attachment"""
	Log.info("[InputController] Pasting large text as attachment (> %d chars)" % PASTE_TEXT_THRESHOLD)

	# Use existing clipboard attach flow (Python reads clipboard via pyperclip)
	attachment_manager.request_clipboard_attach(session_token)


## ============================================================================
## State Setters
## ============================================================================

func set_streaming_state(streaming: bool) -> void:
	var was_streaming = is_agent_streaming
	is_agent_streaming = streaming
	update_send_button_state()
	if was_streaming and not streaming:
		stop_completed.emit()


func _collect_file_ids() -> Array:
	"""Collect file IDs from completed attachment uploads"""
	var file_ids = []
	if not attachment_manager:
		return file_ids

	for attachment in attachment_manager.get_attachments():
		if not attachment.get("uploading", false):
			var file_id = attachment.get("file_id", "")
			if not file_id.is_empty():
				file_ids.append(file_id)
	return file_ids


func send_message_with_attachments(text: String, file_ids: Array) -> void:
	"""Send a message with pre-collected file IDs (used for queued messages)"""
	if text.is_empty():
		return

	var local_message_id = _generate_uuid()

	if not python_bridge:
		Log.error("[MOONLAKE] PythonBridge not found")
		return

	var is_slash_command = text.begins_with("/")
	if not is_slash_command:
		is_agent_streaming = true
		if message_dispatcher:
			message_dispatcher.was_agent_recently_streaming = true
		update_send_button_state()
	message_sent.emit(text)

	var files = []
	for file_id in file_ids:
		files.append({"id": file_id, "file_url": "", "filename": file_id})

	var payload = PythonBridge.make_message_payload(local_message_id, text)
	payload["file_ids"] = file_ids
	payload["files"] = files
	payload["session_token"] = session_token

	if not first_message_sent and not selected_mode.is_empty():
		payload["mode"] = selected_mode

	if not first_message_sent:
		_hide_mode_selection()
		first_message_sent = true

	python_bridge.call_python("send_user_message", payload)


## ============================================================================
## Mode Selection
## ============================================================================

func initialize_mode_ui(dropdown: Button) -> void:
	"""Initialize mode selection UI references and connect signals"""
	mode_dropdown = dropdown

	if mode_dropdown:
		mode_dropdown.pressed.connect(_on_mode_dropdown_pressed)


func _on_mode_dropdown_pressed() -> void:
	if not mode_dropdown:
		return

	ChatPanelUIBuilder.show_mode_dropdown_popup(mode_dropdown)

	var popup = mode_dropdown.get_meta("popup_menu")
	if popup:
		popup.popup_hide.connect(_check_mode_selection, CONNECT_ONE_SHOT)


func _check_mode_selection() -> void:
	"""Check if a mode was selected from the custom popup"""
	if not mode_dropdown:
		return

	if mode_dropdown.has_meta("last_selected_id"):
		var id = mode_dropdown.get_meta("last_selected_id")
		mode_dropdown.remove_meta("last_selected_id")
		_on_mode_selected(id)


func _on_mode_selected(id: int) -> void:
	"""Handle mode selection from dropdown menu"""
	# Map dropdown indices to mode IDs
	match id:
		0:  # General mode
			selected_mode = ""
			mode_dropdown.text = "General mode"
		1:  # Prototype mode
			selected_mode = "prototype-games"
			mode_dropdown.text = "Prototype mode"
		2:  # High-fidelity mode
			selected_mode = "generate-3d-world"
			mode_dropdown.text = "Generate World & Assets"


func _hide_mode_selection() -> void:
	"""Hide mode selection UI after first message sent"""
	if mode_dropdown:
		mode_dropdown.visible = false


func reset_mode_state() -> void:
	"""Reset mode state when clearing conversation"""
	first_message_sent = false
	selected_mode = ""

	# Show mode dropdown again
	if mode_dropdown:
		mode_dropdown.visible = true
		mode_dropdown.text = "General mode"
