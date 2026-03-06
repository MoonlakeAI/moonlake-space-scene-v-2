@tool
extends Control

## Chat Panel v2 - Main orchestrator for chat UI
##
## Initializes all controllers and wires them together via signals

const AttachmentManager = preload("res://addons/moonlake_copilot/attachments/attachment_manager.gd")
const StreamingCoordinator = preload("res://addons/moonlake_copilot/streaming/streaming_coordinator.gd")
const AnimationManager = preload("res://addons/moonlake_copilot/streaming/animation_manager.gd")
const SocketIOManager = preload("res://addons/moonlake_copilot/communication/socketio_manager.gd")
const MessageDispatcher = preload("res://addons/moonlake_copilot/communication/message_dispatcher.gd")
const MessageContainerController = preload("res://addons/moonlake_copilot/chat/message_container_controller.gd")
const InputController = preload("res://addons/moonlake_copilot/chat/input_controller.gd")
const EmptyStateController = preload("res://addons/moonlake_copilot/chat/empty_state_controller.gd")
const TodoController = preload("res://addons/moonlake_copilot/todo/todo_controller.gd")
const QueuedMessageController = preload("res://addons/moonlake_copilot/queue/queued_message_controller.gd")
const PublishController = preload("res://addons/moonlake_copilot/publish/publish_controller.gd")
const ChatPanelUIBuilder = preload("res://addons/moonlake_copilot/chat/chat_panel_ui_builder.gd")
const PromptSuggestionsController = preload("res://addons/moonlake_copilot/chat/prompt_suggestions_controller.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

# UI Nodes
var scroll_container: ScrollContainer
var message_container: VBoxContainer
var input_box: CodeEdit
var send_button: Button
var slash_commands_menu: Control
var yolo_toggle: CheckButton
var yolo_wrapper: Control
var resize_handle: Control
var input_container: Control
var attachment_menu: Control
var error_counter_button: Control
var connection_status_dot: Panel

# Mode selection UI
var mode_dropdown: Button
var empty_state_center: Control
var empty_state_container: Control
var messages_wrapper: Control
var typewriter_label: Label
var typewriter_timer: Timer

# Authentication state
var is_authenticated: bool = false
var session_token: String = ""
var auth_error_state: String = ""

# Connection state
var is_socketio_connected: bool = false
var current_project_id: String = ""

# Resize handle state
var is_dragging_resize: bool = false
var drag_start_y: float = 0.0
var drag_start_height: float = 0.0

# Python bridge reference
var python_bridge: Node = null

# Streaming coordination
var streaming_coordinator: StreamingCoordinator = null
var animation_manager: AnimationManager = null

# Communication modules
var socketio_manager: SocketIOManager = null
var message_dispatcher: MessageDispatcher = null

# Message container controller
var message_container_controller: MessageContainerController = null

# Input controller
var input_controller: InputController = null

# Empty state controller
var empty_state_controller: EmptyStateController = null

# Todo controller
var todo_controller: TodoController = null
var _todo_ui: Dictionary = {}

var queued_message_controller: QueuedMessageController = null

var publish_controller: PublishController = null
var _publish_ui: Dictionary = {}

var prompt_suggestions_controller: PromptSuggestionsController = null
var suggestions_wrapper: MarginContainer = null
var suggestions_container: HFlowContainer = null

# New message notification
var new_message_toast: Button = null

# Session restore state
var is_restoring_session: bool = false

# Streaming state tracking
var streaming_start_time: float = 0.0
var last_streaming_activity: float = 0.0
var is_agent_streaming: bool = false

# Attachment management
var attachment_manager: AttachmentManager = null
var attachment_chips_container: Container  # HFlowContainer for auto-wrapping

var config: Node = null


func _init():
	name = "Moonlake Copilot"


func _ready() -> void:
	_setup_ui()

	# python_bridge is passed from plugin.gd
	# Wait a frame for everything to be ready
	await get_tree().process_frame

	if python_bridge:
		_initialize_modules()
		_load_auth_from_cpp()
		await _setup_client()
	else:
		Log.error("[MOONLAKE] Python bridge not set by plugin")

	# Auto-focus input box on startup
	if input_box:
		input_box.grab_focus()


func _initialize_modules() -> void:
	"""Initialize all subsystems and wire their signals"""
	_apply_input_height()
	_initialize_communication()
	_initialize_streaming()
	_initialize_messages()
	_initialize_attachments()  # MUST initialize before input_controller
	_initialize_input()
	_initialize_prompt_suggestions()
	_initialize_empty_state()
	_initialize_auth()
	_initialize_publish()
	_connect_python_bridge()


func _apply_input_height() -> void:
	"""Apply initial input height from ProjectSettings"""
	var input_height = ProjectSettings.get_setting("moonlake/ui/chat_input_height", 300.0)
	if input_container:
		input_container.custom_minimum_size.y = input_height
	if input_box:
		input_box.offset_top = -input_height
	if resize_handle:
		resize_handle.offset_top = -input_height - 6
		resize_handle.offset_bottom = -input_height


func _initialize_communication() -> void:
	"""Initialize SocketIO manager and connect its signals"""
	socketio_manager = SocketIOManager.new(python_bridge)

	socketio_manager.connection_established.connect(_on_socketio_connected)
	socketio_manager.connection_lost.connect(_on_socketio_disconnected)
	socketio_manager.connection_error.connect(_on_socketio_error)
	socketio_manager.reconnecting.connect(_on_socketio_reconnecting)
	socketio_manager.system_message.connect(_on_socketio_system_message)


func _initialize_streaming() -> void:
	"""Initialize streaming coordinator and animation manager"""
	streaming_coordinator = StreamingCoordinator.new(message_container, config)

	streaming_coordinator.streaming_started.connect(_on_streaming_started)
	streaming_coordinator.streaming_stopped.connect(_on_streaming_stopped)
	streaming_coordinator.scroll_requested.connect(func():
		if message_container_controller: message_container_controller.scroll_to_bottom()
	)


func _initialize_messages() -> void:
	"""Initialize message container controller, animation manager, and message dispatcher"""
	# Initialize message container controller
	message_container_controller = MessageContainerController.new()
	message_container_controller.initialize(message_container, scroll_container, empty_state_center, new_message_toast, python_bridge, config)

	# Create animation manager with message_container_controller's cache/order
	animation_manager = AnimationManager.new(
		message_container,
		message_container_controller.get_message_cache(),
		message_container_controller.get_message_order()
	)
	message_container_controller.animation_manager = animation_manager

	# Connect message container controller signals
	message_container_controller.todo_list_updated.connect(func(message):
		if todo_controller: todo_controller.update_todo_list(message)
	)
	message_container_controller.empty_state_visibility_changed.connect(_on_empty_state_visibility_changed)
	message_container_controller.input_history_reset.connect(func():
		if input_controller: input_controller.reset_history_navigation()
	)
	message_container_controller.tool_use_received.connect(streaming_coordinator.remove_streaming_widget)

	# Initialize message dispatcher
	message_dispatcher = MessageDispatcher.new(streaming_coordinator, config)

	# Connect message dispatcher signals to message container controller
	message_dispatcher.add_message_requested.connect(message_container_controller.handle_add_message)
	message_dispatcher.update_message_requested.connect(message_container_controller.handle_update_message)
	message_dispatcher.append_to_message_requested.connect(func(data): message_container_controller.handle_append_to_message(data, streaming_coordinator))
	message_dispatcher.replace_ephemeral_requested.connect(message_container_controller.handle_replace_ephemeral)
	message_dispatcher.remove_ephemeral_requested.connect(message_container_controller.handle_remove_ephemeral)
	message_dispatcher.replace_message_id_requested.connect(message_container_controller.handle_replace_message_id)
	message_dispatcher.remove_message_requested.connect(message_container_controller.handle_remove_message)
	message_dispatcher.clear_messages_requested.connect(message_container_controller.handle_clear_messages)
	message_dispatcher.session_restore_start.connect(_on_session_restore_start)
	message_dispatcher.session_restore_complete.connect(_on_session_restore_complete)
	message_dispatcher.stop_animations_requested.connect(message_container_controller.stop_all_animations)
	message_dispatcher.set_animating_interactive_requested.connect(message_container_controller.set_animating_interactive)
	message_dispatcher.cancel_pending_confirmations_requested.connect(message_container_controller.cancel_pending_confirmations)
	message_dispatcher.connection_status_update.connect(_on_connection_status_update)
	message_dispatcher.credits_update.connect(_on_credits_update)
	message_dispatcher.auth_error_detected.connect(_on_auth_error_detected)
	message_dispatcher.is_streaming_changed.connect(_on_is_streaming_changed)
	message_dispatcher.stream_complete_received.connect(_on_stream_complete)
	message_dispatcher.health_check_requested.connect(_on_health_check_requested)
	message_dispatcher.publish_start_requested.connect(_on_publish_start)
	message_dispatcher.publish_progress_received.connect(_on_publish_progress)
	message_dispatcher.publish_cancel_requested.connect(_on_publish_cancel)
	message_dispatcher.publish_view_requested.connect(_on_publish_view)
	message_dispatcher.unpublish_start_requested.connect(_on_unpublish_start)
	message_dispatcher.unpublish_complete_received.connect(_on_unpublish_complete)


func _initialize_input() -> void:
	"""Initialize input controller and connect its signals"""
	input_controller = InputController.new()
	input_controller.initialize(input_box, send_button, python_bridge)
	input_controller.attachment_manager = attachment_manager
	input_controller.message_container_controller = message_container_controller
	input_controller.queued_message_controller = queued_message_controller
	input_controller.message_dispatcher = message_dispatcher
	input_controller.session_token = session_token

	# Give message_container_controller reference to input_controller (for stopping agent on revert)
	message_container_controller.input_controller = input_controller

	# Verify attachment_manager was initialized first
	if not attachment_manager:
		Log.error("[ChatPanel] CRITICAL: attachment_manager is null in _initialize_input! Check initialization order.")

	# Initialize mode selection UI
	input_controller.initialize_mode_ui(mode_dropdown)

	input_controller.message_sent.connect(_on_message_sent)
	input_controller.stop_requested.connect(_on_stop_requested)
	input_controller.stop_completed.connect(_on_stop_completed)

	todo_controller = TodoController.new()
	todo_controller.initialize(
		_todo_ui["container"],
		_todo_ui["content"],
		_todo_ui["header"],
		_todo_ui["header_hbox"],
		_todo_ui["spinner"],
		_todo_ui["expand_icon"],
		_todo_ui["scroll_container"],
		input_controller
	)

	input_controller.user_stop_completed.connect(_on_user_stop_completed)


func _initialize_prompt_suggestions() -> void:
	"""Initialize prompt suggestions controller"""
	prompt_suggestions_controller = PromptSuggestionsController.new()
	prompt_suggestions_controller.initialize(suggestions_wrapper, suggestions_container, attachment_chips_container.get_parent())
	prompt_suggestions_controller.set_message_dispatcher(message_dispatcher)
	prompt_suggestions_controller.set_queued_message_controller(queued_message_controller)
	prompt_suggestions_controller.suggestion_selected.connect(_on_suggestion_selected)
	prompt_suggestions_controller.suggestions_shown.connect(_on_suggestions_shown)


func _initialize_empty_state() -> void:
	"""Initialize empty state controller"""
	empty_state_controller = EmptyStateController.new()
	empty_state_controller.initialize(typewriter_label, typewriter_timer, empty_state_center, self)


func _initialize_auth() -> void:
	var auth = MoonlakeAuth.get_singleton()
	if auth:
		auth.auth_changed.connect(_on_auth_changed)


func _initialize_publish() -> void:
	"""Initialize publish controller"""
	publish_controller = PublishController.new()
	publish_controller.initialize(
		_publish_ui["container"],
		_publish_ui["header"],
		_publish_ui["header_hbox"],
		_publish_ui["spinner"],
		_publish_ui["progress_log"],
		_publish_ui["scroll_container"],
		_publish_ui["cancel_button"],
		_publish_ui["view_button"],
		_publish_ui["close_button"]
	)
	publish_controller.python_bridge = python_bridge


func _load_auth_from_cpp() -> void:
	var auth = MoonlakeAuth.get_singleton()
	if auth and auth.get_is_authenticated():
		session_token = auth.get_session_token()
		is_authenticated = true
		if input_controller:
			input_controller.session_token = session_token


func _initialize_attachments() -> void:
	"""Initialize attachment manager and connect its signals"""
	attachment_manager = AttachmentManager.new(attachment_chips_container, python_bridge)

	attachment_manager.upload_failed.connect(_on_upload_failed)
	attachment_manager.max_attachments_reached.connect(_on_max_attachments_reached)
	attachment_manager.input_position_update_needed.connect(_update_input_position)
	attachment_manager.paste_text_requested.connect(_on_paste_text_requested)

	# Connect attachment menu signals to attachment manager
	attachment_menu.image_attach_requested.connect(func(): attachment_manager.request_image_attach(self))
	attachment_menu.editor_output_attach_requested.connect(_on_editor_output_attach_requested)
	attachment_menu.editor_screenshot_attach_requested.connect(_on_editor_screenshot_attach_requested)

	slash_commands_menu.slash_command_selected.connect(_on_slash_command_selected)


func _connect_python_bridge() -> void:
	"""Connect python bridge signals"""
	python_bridge.worker_restarted.connect(_on_worker_restarted)
	python_bridge.response_received.connect(_on_python_response)


func _process(_delta: float) -> void:
	"""Check for streaming timeout (safety mechanism)"""
	if streaming_coordinator and streaming_coordinator.check_timeout():
		if input_controller:
			input_controller.update_send_button_state()


func _input(event: InputEvent) -> void:
	"""Handle keyboard input for message sending and history navigation"""
	if input_controller and input_controller.handle_input_event(event):
		accept_event()


func _on_streaming_started() -> void:
	if input_controller:
		input_controller.set_streaming_state(true)

	if message_container_controller:
		message_container_controller.update_all_revert_buttons()


func _on_streaming_stopped() -> void:
	if message_container_controller:
		message_container_controller.update_all_revert_buttons()


func _on_is_streaming_changed(is_streaming: bool) -> void:
	if input_controller:
		input_controller.set_streaming_state(is_streaming)
	if not is_streaming:
		_try_send_queued_messages()


func _on_stream_complete() -> void:
	if input_controller:
		input_controller.set_streaming_state(false)
	_try_send_queued_messages()


func _try_send_queued_messages() -> void:
	if not queued_message_controller or not queued_message_controller.has_messages():
		return
	if input_controller and input_controller.skip_next_queue_process:
		input_controller.skip_next_queue_process = false
		return
	_send_all_queued_messages()


func _send_all_queued_messages() -> void:
	"""Pop all queued messages and send as one combined message"""
	var combined_texts: Array = []
	var combined_file_ids: Array = []

	while queued_message_controller.has_messages():
		var queued = queued_message_controller.pop_message()
		if not queued.is_empty():
			var text = queued.get("text", "")
			if not text.is_empty():
				combined_texts.append(text)
			var file_ids = queued.get("file_ids", [])
			for fid in file_ids:
				if fid not in combined_file_ids:
					combined_file_ids.append(fid)

	if combined_texts.size() > 0 and input_controller:
		var combined_text = "\n".join(combined_texts)
		if message_container_controller:
			message_container_controller.force_scroll_to_bottom()
		input_controller.send_message_with_attachments(combined_text, combined_file_ids)


func _on_message_sent(text: String) -> void:
	"""Handle message_sent signal from InputController"""
	# Set streaming state tracking
	streaming_start_time = Time.get_ticks_msec() / 1000.0
	last_streaming_activity = streaming_start_time
	is_agent_streaming = true

	if prompt_suggestions_controller:
		prompt_suggestions_controller.clear_suggestions()

	if message_container_controller:
		message_container_controller.force_scroll_to_bottom()


func _on_stop_requested() -> void:
	if message_container_controller:
		message_container_controller.stop_all_animations()
	is_agent_streaming = false


func _on_stop_completed() -> void:
	if message_container_controller:
		message_container_controller.update_all_revert_buttons()


func _on_user_stop_completed() -> void:
	if not queued_message_controller or not queued_message_controller.has_messages():
		return
	if not message_container_controller.stop_message_was_received:
		await message_container_controller.stop_message_received
	message_container_controller.stop_message_was_received = false
	if message_dispatcher and message_dispatcher.was_agent_recently_streaming:
		await message_dispatcher.stream_complete_received
	_send_all_queued_messages()


func _on_session_restore_start() -> void:
	"""Handle session restore start signal from dispatcher"""
	is_restoring_session = true
	if message_container_controller:
		message_container_controller.is_restoring_session = true
	# Hide empty state during restore
	if empty_state_center:
		empty_state_center.visible = false


func _on_session_restore_complete() -> void:
	"""Handle session restore complete signal from dispatcher"""
	is_restoring_session = false
	if message_container_controller:
		message_container_controller.is_restoring_session = false

	# Don't try to connect if not authenticated
	if not is_authenticated:
		Log.info("[MOONLAKE] Session restore complete, skipping connect (not authenticated)")
		return

	var msg_cache = message_container_controller.get_message_cache() if message_container_controller else {}
	if msg_cache.size() == 0 and empty_state_center:
		empty_state_center.visible = true
		if empty_state_controller:
			empty_state_controller.start_typewriter_effect()
	else:
		if message_container_controller:
			call_deferred("_deferred_scroll_after_restore")

	if socketio_manager.is_socketio_connected:
		var status = await python_bridge.call_python_async("get_connection_status", {}, 5.0)
		if status.get("ok") and status.get("result", {}).get("socketio_connected", false):
			Log.info("[MOONLAKE] Session restore complete, already connected")
			return
		else:
			Log.info("[MOONLAKE] Session restore complete, cached state stale - reconnecting")
			socketio_manager.is_socketio_connected = false
	Log.info("[MOONLAKE] Session restore complete, connecting to agent service...")
	if current_project_id != "" and session_token != "":
		socketio_manager.connect_socketio(current_project_id, session_token)
	else:
		if current_project_id == "":
			Log.warn("[MOONLAKE] Cannot connect - missing project_id")
			_add_error_message("Cannot connect - missing project_id")
			return
		if session_token == "":
			Log.warn("[MOONLAKE] Cannot connect - missing session_token")
			_add_error_message("Cannot connect - missing auth. Please login.")
			return


func _deferred_scroll_after_restore() -> void:
	if message_container_controller:
		message_container_controller.force_scroll_to_bottom()


func _on_empty_state_visibility_changed(visible: bool) -> void:
	"""Handle empty state visibility change from message container"""
	if empty_state_controller:
		if visible:
			empty_state_controller.show_empty_state()
		else:
			empty_state_controller.hide_empty_state()


func _setup_ui() -> void:
	"""Create basic UI structure using ChatPanelUIBuilder"""
	var ui = ChatPanelUIBuilder.build_ui(self, config)

	connection_status_dot = ui["connection_status_dot"]
	messages_wrapper = ui["messages_wrapper"]
	scroll_container = ui["scroll_container"]
	message_container = ui["message_container"]
	empty_state_container = ui["empty_state_container"]
	empty_state_center = ui["empty_state_center"]
	typewriter_label = ui["typewriter_label"]
	typewriter_timer = ui["typewriter_timer"]
	new_message_toast = ui["new_message_toast"]
	attachment_chips_container = ui["attachment_chips_container"]
	mode_dropdown = ui["mode_dropdown"]
	input_container = ui["input_container"]
	input_box = ui["input_box"]
	send_button = ui["send_button"]
	slash_commands_menu = ui["slash_commands_menu"]
	yolo_toggle = ui["yolo_toggle"]
	yolo_wrapper = ui["yolo_wrapper"]
	resize_handle = ui["resize_handle"]
	attachment_menu = ui["attachment_menu"]
	error_counter_button = ui["error_counter_button"]
	suggestions_wrapper = ui["suggestions_wrapper"]
	suggestions_container = ui["suggestions_container"]

	# Connect resize handle signals
	resize_handle.gui_input.connect(_on_resize_handle_input)

	_todo_ui = {
		"container": ui["todo_container"],
		"content": ui["todo_content"],
		"header": ui["todo_header"],
		"header_hbox": ui["todo_header_hbox"],
		"spinner": ui["todo_spinner"],
		"expand_icon": ui["todo_expand_icon"],
		"scroll_container": ui["todo_scroll_container"]
	}

	_publish_ui = {
		"container": ui["publish_container"],
		"header": ui["publish_header"],
		"header_hbox": ui["publish_header_hbox"],
		"spinner": ui["publish_spinner"],
		"progress_log": ui["publish_progress_log"],
		"scroll_container": ui["publish_scroll_container"],
		"cancel_button": ui["publish_cancel_button"],
		"view_button": ui["publish_view_button"],
		"close_button": ui["publish_close_button"]
	}

	queued_message_controller = QueuedMessageController.new()
	queued_message_controller.initialize(
		ui["queue_container"],
		ui["queue_content"],
		ui["queue_header"],
		ui["queue_close_button"]
	)

	yolo_wrapper.gui_input.connect(_on_yolo_wrapper_input)
	yolo_toggle.toggled.connect(_on_yolo_toggle_changed)
	config.yolo_mode_activated.connect(_on_yolo_mode_activated)
	config.yolo_mode_deactivated.connect(_on_yolo_mode_deactivated)
	yolo_toggle.button_pressed = config.yolo_mode_enabled


func handle_render_command(command: Dictionary) -> void:
	"""
	Main entry point for Python render commands.

	Delegates to MessageDispatcher for routing.
	"""
	if message_dispatcher:
		message_dispatcher.dispatch_render_command(command)




## ============================================================================
## Python Response Handling (for auth and connection status)
## ============================================================================

func handle_python_response(id: int, ok: bool, result, error_msg: String) -> void:
	"""
	Handle Python responses (auth, connection status).

	Note: Render commands are routed via plugin.gd single message pump.
	This is only for non-render responses.
	"""
	# Log.info("[MOONLAKE] Python response [ID ", id, "]: ok=", ok)

	if not ok:
		_add_error_message("WORKER error: " + error_msg)
		return

	if result is Dictionary:
		if result.has("connected"):
			is_socketio_connected = result.connected
			if result.get("success", false):
				if result.connected:
					Log.info("[MOONLAKE] Successfully connected to agent service")
				else:
					Log.info("[MOONLAKE] Disconnected from agent service")
			else:
				var error = result.get("error", "Unknown error")
				Log.error("[MOONLAKE] SocketIO operation failed: " + error)
				_add_system_message("Agent service offline. Retrying automatically...")
				is_socketio_connected = false
			return


## ============================================================================
## Setup and Connection
## ============================================================================

func _setup_client():
	"""Setup client - create or load project_id"""
	var existing_project_id = MoonlakeProjectConfig.get_singleton().get_project_id()
	if existing_project_id == "":
		Log.warn("[MOONLAKE] No project_id found, creating new project...")
		var project_name = ProjectSettings.get_setting("application/config/name", "Untitled Project")
		var project_description = "Created with Godot Moonlake Agent"

		if python_bridge and python_bridge.pid != -1:
			var create_params = {
				"name": project_name,
				"description": project_description,
				"session_token": session_token if session_token != "" else null
			}

			var response = await python_bridge.call_python_async("create_project", create_params, 30.0)

			if response["ok"]:
				var result = response["result"]
				if result is Dictionary and result.get("success", false):
					current_project_id = result.get("project_id", "")
					Log.info("[MOONLAKE] Project created with ID: " + current_project_id)

					MoonlakeProjectConfig.get_singleton().set_project_id(current_project_id)
					MoonlakeProjectConfig.get_singleton().set_project_description(project_description)

					# Load session first, then connect (ensures correct message order)
					_load_previous_session_messages()
				else:
					var error = result.get("error", "Unknown error") if result is Dictionary else "Unknown error"
					Log.error("[MOONLAKE] Failed to create project: " + error)

					# Provide helpful message for auth-related errors
					if "session_token" in error.to_lower():
						_add_system_message("Please sign in to use Moonlake. Click the Login button above.")
					else:
						_add_error_message("Failed to create project.")
			else:
				Log.error("[MOONLAKE] Python call failed: " + response["error"])
				_add_error_message("WORKER error: " + response["error"])
	else:
		Log.info("[MOONLAKE] Using existing project_id: " + existing_project_id)
		current_project_id = existing_project_id

		# Load session first, then connect (ensures correct message order)
		_load_previous_session_messages()




func _load_previous_session_messages():
	"""Load previous session messages from disk via Python worker"""
	if not python_bridge or python_bridge.pid == -1 or current_project_id == "":
		return

	# Guard against concurrent restore attempts
	if is_restoring_session:
		Log.info("[MOONLAKE] Session restore already in progress, skipping")
		return

	# Ensure workdir is initialized before loading
	var workdir_result = await python_bridge.call_python_async("initialize_workdir", {
		"workdir": ProjectSettings.globalize_path("res://")
	}, 5.0)

	if not workdir_result["ok"]:
		Log.error("[MOONLAKE] Failed to initialize workdir: " + workdir_result.get("error", ""))
		return

	# Set flag to skip animations during restore
	is_restoring_session = true
	if message_container_controller:
		message_container_controller.is_restoring_session = true

	# Hide empty state and stop typewriter immediately
	if empty_state_center:
		empty_state_center.visible = false
		if typewriter_timer:
			typewriter_timer.stop()

	python_bridge.call_python("load_previous_session", {
		"project_id": current_project_id
	})

	# Safety timeout in case session_restore_complete never arrives
	await get_tree().create_timer(10.0).timeout
	if is_restoring_session:
		Log.warn("[MOONLAKE] Session restore timeout, resetting state")
		is_restoring_session = false
		if message_container_controller:
			message_container_controller.is_restoring_session = false
		var msg_cache = message_container_controller.get_message_cache() if message_container_controller else {}
		if empty_state_center and msg_cache.size() == 0:
			empty_state_center.visible = true
			if empty_state_controller:
				empty_state_controller.start_typewriter_effect()


func _on_worker_restarted():
	"""Handle Python worker restart - reconnect to agent service"""
	Log.warn("[MOONLAKE] Python worker restarted, reconnecting...")

	# Stop all pending typewriter animations
	if message_container_controller:
		message_container_controller.stop_all_animations()

	await get_tree().create_timer(0.5).timeout

	_load_auth_from_cpp()

	var saved_project_id = MoonlakeProjectConfig.get_singleton().get_project_id()
	if saved_project_id != "":
		current_project_id = saved_project_id
		Log.info("[MOONLAKE] Reloaded project_id: " + current_project_id)

	# Reconnect to SocketIO if we have both project_id and session_token
	if current_project_id != "" and session_token != "":
		socketio_manager.connect_socketio(current_project_id, session_token)
		_add_system_message("Reconnected to agent")
	else:
		Log.warn("[MOONLAKE] Worker restarted but missing credentials (project_id=%s, has_token=%s)" % [current_project_id != "", session_token != ""])


func _on_python_response(id: int, ok: bool, result, error_msg: String):
	"""Handle responses from Python worker, including system notifications"""
	# Only handle system notifications (id = -1)
	if id != -1:
		return

	# Check if result is a dictionary with type field
	if typeof(result) == TYPE_DICTIONARY:
		# Check for HTTP error codes and delegate to socketio_manager
		if socketio_manager and socketio_manager.check_http_error(result):
			return

		var msg_type = result.get("type", "")

		# Delegate SocketIO events to socketio_manager
		if msg_type in ["socketio_disconnected", "socketio_connected", "socketio_reconnecting",
						"socketio_connect_error", "socketio_reconnect_failed", "socketio_auth_failed",
						"socketio_reconnect_attempt_failed"]:
			if socketio_manager:
				socketio_manager.handle_socketio_event(msg_type, result)
			return


func _finish_all_animations() -> void:
	"""Finish all ongoing typewriter animations in message widgets"""
	for child in message_container.get_children():
		# Unwrap MarginContainer wrapper
		var widget = child
		if child is MarginContainer and child.get_child_count() > 0:
			widget = child.get_child(0)

		# Unwrap HBoxContainer (for user messages)
		if widget is HBoxContainer and widget.get_child_count() > 1:
			widget = widget.get_child(1)

		# Call finish_animation if available
		if widget.has_method("finish_animation"):
			widget.finish_animation()

func _add_system_message(text: String, category: String = "info") -> void:
	"""Add system message to UI using message store"""
	if message_dispatcher and message_dispatcher.was_agent_recently_streaming:
		python_bridge.call_python("move_interactive_to_latest", {})

	var system_message = {
		"id": str(Time.get_ticks_msec()),  # Simple unique ID
		"type": "system_message",
		"sender": "system",
		"content": {
			"message": text,
			"category": category  # "info", "success", or "fail"
		},
		"created_at": Time.get_unix_time_from_system(),
		"is_streaming": false,
		"success": true
	}
	# Wrap in data structure expected by handle_add_message
	message_container_controller.handle_add_message({"message": system_message})
	if message_container_controller:
		message_container_controller.force_scroll_to_bottom()


func _add_error_message(text: String) -> void:
	"""Add error message to UI - uses system message with fail category"""
	_add_system_message(text, "fail")




## ============================================================================
## Authentication - MoonlakeAuth Signal Handler
## ============================================================================

func _on_auth_changed(authenticated: bool) -> void:
	var auth = MoonlakeAuth.get_singleton()
	if authenticated and auth:
		session_token = auth.get_session_token()
		if input_controller:
			input_controller.session_token = session_token
		is_authenticated = true

		if current_project_id != "":
			await socketio_manager.reconnect_after_login(current_project_id, session_token)
		else:
			await _setup_client()
	else:
		is_socketio_connected = false
		auth_error_state = ""
		if socketio_manager:
			socketio_manager.is_intentional_disconnect = true
			socketio_manager.disconnect_socketio()
		session_token = ""
		if input_controller:
			input_controller.session_token = ""
		is_authenticated = false


## ============================================================================
## SocketIO Manager Signal Handlers
## ============================================================================

func _on_socketio_connected() -> void:
	is_socketio_connected = true
	is_agent_streaming = false

	if connection_status_dot:
		_set_dot_color(Color(0.2, 0.8, 0.2, 1.0))
		connection_status_dot.get_parent().tooltip_text = "Connected"

	if input_controller:
		input_controller.set_streaming_state(false)

	if queued_message_controller:
		queued_message_controller.clear()


func _on_socketio_disconnected() -> void:
	is_socketio_connected = false

	if connection_status_dot:
		_set_dot_color(Color(0.8, 0.2, 0.2, 1.0))
		connection_status_dot.get_parent().tooltip_text = "Disconnected"

	if message_container_controller:
		message_container_controller.handle_remove_ephemeral({})
		message_container_controller.cancel_pending_confirmations()

	if streaming_coordinator:
		streaming_coordinator.stop_all_streaming()
	if animation_manager:
		animation_manager.finish_all_animations()


func _on_socketio_error(error_type: String) -> void:
	is_socketio_connected = false

	if connection_status_dot:
		_set_dot_color(Color(0.8, 0.2, 0.2, 1.0))
		connection_status_dot.get_parent().tooltip_text = "Connection error"

	if error_type in ["token_expired", "unauthorized"]:
		session_token = ""
		if input_controller:
			input_controller.session_token = ""
		is_authenticated = false
		var auth = MoonlakeAuth.get_singleton()
		if auth:
			auth.logout()


func _on_socketio_reconnecting(attempt: int, next_delay: int) -> void:
	is_socketio_connected = false

	if connection_status_dot:
		_set_dot_color(Color(0.9, 0.7, 0.1, 1.0))
		connection_status_dot.get_parent().tooltip_text = "Reconnecting... (attempt #%d)" % attempt

	if message_container_controller:
		message_container_controller.stop_all_animations()


func _on_socketio_system_message(message: String, category: String) -> void:
	_add_system_message(message, category)


func _set_dot_color(color: Color) -> void:
	if not connection_status_dot:
		return
	var style = connection_status_dot.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.bg_color = color


func _on_connection_status_update(state: String, message: String) -> void:
	match state:
		"service_warning":
			if connection_status_dot:
				_set_dot_color(Color(0.9, 0.5, 0.1, 1.0))
				connection_status_dot.get_parent().tooltip_text = message if message else "Service issue"
		"clear_override":
			auth_error_state = ""
			if connection_status_dot and is_socketio_connected:
				_set_dot_color(Color(0.2, 0.8, 0.2, 1.0))
				connection_status_dot.get_parent().tooltip_text = "Connected"
		_:
			Log.warn("[ChatPanel] Unknown connection_status state: %s" % state)


func _on_health_check_requested() -> void:
	"""Handle health check request from Python - call C++ and return result"""
	var auth = MoonlakeAuth.get_singleton()
	if not auth:
		if python_bridge:
			python_bridge.call_python("do_health_check", {"project_ok": true})
		return

	auth.check_project_service_health()

	var result = await auth.project_service_health_checked
	var is_healthy: bool = result[0]

	if python_bridge:
		python_bridge.call_python("do_health_check", {"project_ok": is_healthy})


func _on_credits_update(balance: float, total: float) -> void:
	pass


func _on_auth_error_detected(error_type: String, status_code: int) -> void:
	Log.warn("[ChatPanel] Auth error detected: %s (status %d)" % [error_type, status_code])

	session_token = ""
	is_authenticated = false
	auth_error_state = error_type

	if input_controller:
		input_controller.session_token = ""

	var auth = MoonlakeAuth.get_singleton()
	if auth:
		auth.logout()


func _on_yolo_wrapper_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		yolo_toggle.button_pressed = !yolo_toggle.button_pressed


func _on_yolo_toggle_changed(is_pressed: bool) -> void:
	if is_pressed:
		config.enable_yolo_mode()
	else:
		config.disable_yolo_mode()


func _on_yolo_mode_activated() -> void:
	if yolo_toggle and not yolo_toggle.button_pressed:
		yolo_toggle.button_pressed = true


func _on_yolo_mode_deactivated() -> void:
	if yolo_toggle and yolo_toggle.button_pressed:
		yolo_toggle.button_pressed = false


# ============================================================================
# Attachment Management Signal Handlers
# ============================================================================

func _on_upload_failed(error: String) -> void:
	_add_system_message(error, "fail")


func _on_max_attachments_reached() -> void:
	"""Handle max attachments reached signal from AttachmentManager"""
	_add_system_message("Maximum %d attachments reached. Remove some attachments to add more." % attachment_manager.MAX_ATTACHMENTS)


func _on_paste_text_requested(text: String) -> void:
	if input_controller and input_controller.input_box:
		input_controller.input_box.insert_text_at_caret(text)


func _update_input_position() -> void:
	"""Adjust chips wrapper minimum size to match HFlowContainer's wrapped height"""
	var wrapper = attachment_chips_container.get_parent() as MarginContainer
	if not wrapper:
		return

	if prompt_suggestions_controller:
		prompt_suggestions_controller.on_attachments_changed()

	if wrapper.visible:
		# Wait TWO frames to ensure HFlowContainer has calculated wrapped height
		await get_tree().process_frame
		await get_tree().process_frame

		var chips_height = attachment_chips_container.size.y

		# Set wrapper's minimum size to match container's calculated height
		# Add padding from MarginContainer's bottom margin (6px)
		wrapper.custom_minimum_size.y = chips_height + 6

		# Force layout update
		wrapper.size.y = 0  # Reset to trigger recalculation

		# Scroll to bottom to show latest message after layout settles
		await get_tree().process_frame
		if message_container_controller:
			message_container_controller.force_scroll_to_bottom()
	else:
		# Reset wrapper size when hidden
		wrapper.custom_minimum_size.y = 0


# ============================================================================

func _on_slash_command_selected(command: String) -> void:
	"""Handle slash command selection from menu"""
	if input_box:
		# Insert command at cursor position (or replace selection if any)
		input_box.insert_text_at_caret(command + " ")
		input_box.grab_focus()


func _on_suggestion_selected(text: String) -> void:
	"""Handle prompt suggestion selection - send message immediately"""
	if input_controller:
		input_controller.send_message_with_attachments(text, [])


func _on_suggestions_shown() -> void:
	"""Scroll to bottom when suggestions panel appears"""
	if message_container_controller:
		message_container_controller.force_scroll_to_bottom()


# ============================================================================
# Publish Operations
# ============================================================================

func _on_publish_start() -> void:
	"""Handle publish start from slash command"""
	if publish_controller:
		publish_controller.start_publish()

	var auth = MoonlakeAuth.get_singleton()
	if not auth or not auth.get_is_authenticated():
		if publish_controller:
			publish_controller.on_progress("[color=red]Error: Not authenticated. Please log in first.[/color]")
			publish_controller.current_state = publish_controller.State.ERROR
		return

	var project_id = MoonlakeProjectConfig.get_singleton().get_project_id()
	if project_id.is_empty():
		if publish_controller:
			publish_controller.on_progress("[color=red]Error: No project ID found[/color]")
			publish_controller.current_state = publish_controller.State.ERROR
		return

	# Start full publish flow in background (sync + publish handled by Python)
	var workdir = ProjectSettings.globalize_path("res://")
	python_bridge.call_python("full_publish", {
		"workdir": workdir,
		"project_id": project_id,
		"session_token": auth.get_session_token()
	})


func _on_publish_progress(message: String) -> void:
	"""Handle publish progress from Python"""
	if publish_controller:
		publish_controller.on_progress(message)


func _on_publish_cancel() -> void:
	"""Handle publish cancel from slash command"""
	if publish_controller:
		publish_controller.cancel_publish()


func _on_publish_view() -> void:
	"""Handle publish view from slash command"""
	if publish_controller:
		publish_controller.open_published_url()


func _on_unpublish_start() -> void:
	"""Handle unpublish start from slash command"""
	if publish_controller:
		publish_controller.start_unpublish()
		_start_unpublish_operation()


func _start_unpublish_operation() -> void:
	"""Start the actual unpublish operation"""
	var auth = MoonlakeAuth.get_singleton()
	if not auth or not auth.get_is_authenticated():
		if publish_controller:
			publish_controller.on_unpublish_complete(false, "Not authenticated")
		return

	var project_id = MoonlakeProjectConfig.get_singleton().get_project_id()
	if project_id.is_empty():
		if publish_controller:
			publish_controller.on_unpublish_complete(false, "No project ID")
		return

	# Call unpublish via Python
	if python_bridge:
		python_bridge.call_python("unpublish_project", {
			"project_id": project_id,
			"session_token": auth.get_session_token()
		})


func _on_unpublish_complete(success: bool, error: String) -> void:
	"""Handle unpublish complete from Python"""
	if publish_controller:
		publish_controller.on_unpublish_complete(success, error)


func _on_editor_output_attach_requested() -> void:
	attachment_manager.request_editor_output_attach(session_token)


func _on_editor_screenshot_attach_requested() -> void:
	attachment_manager.request_editor_screenshot_attach()


# ============================================================================
# Resize Handle
# ============================================================================

func _on_resize_handle_input(event: InputEvent) -> void:
	"""Handle resize handle dragging"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				is_dragging_resize = true
				drag_start_y = event.global_position.y
				drag_start_height = -input_box.offset_top  # Current height (positive)
			else:
				# End dragging
				if is_dragging_resize:
					is_dragging_resize = false
					# Save new height to settings
					var new_height = -input_box.offset_top
					ProjectSettings.set_setting("moonlake/ui/chat_input_height", new_height)
					ProjectSettings.save()

	elif event is InputEventMouseMotion:
		if is_dragging_resize:
			# Calculate new height
			var delta_y = drag_start_y - event.global_position.y  # Inverted because dragging up increases height
			var new_height = drag_start_height + delta_y

			# Clamp to min/max
			new_height = clampf(new_height, 100.0, 500.0)

			# Apply new height to container (VBox will handle layout automatically)
			input_container.custom_minimum_size.y = new_height
			input_box.offset_top = -new_height
			resize_handle.offset_top = -new_height - 6  # Keep handle 6px above input
			resize_handle.offset_bottom = -new_height


