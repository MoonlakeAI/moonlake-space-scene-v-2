@tool
extends RefCounted

## Message Dispatcher - Routes render commands to appropriate handlers
##
## Responsibilities:
## - Parse incoming render commands from Python
## - Route to appropriate handler based on command type
## - Delegate to specialized controllers (streaming, auth, etc.)

# Signals for different command types
signal add_message_requested(data: Dictionary)
signal update_message_requested(data: Dictionary)
signal append_to_message_requested(data: Dictionary)
signal replace_ephemeral_requested(data: Dictionary)
signal remove_ephemeral_requested(data: Dictionary)
signal replace_message_id_requested(data: Dictionary)
signal remove_message_requested(data: Dictionary)
signal clear_messages_requested(data: Dictionary)
signal session_restore_start()
signal session_restore_complete()
signal stop_animations_requested()
signal set_animating_interactive_requested(message_id: String)
signal cancel_pending_confirmations_requested()
signal connection_status_update(state: String, message: String)
signal credits_update(balance: float, total: float)
signal auth_error_detected(error_type: String, status_code: int)
signal is_streaming_changed(is_streaming: bool)
signal stream_complete_received()
signal prompt_suggestions_ready(suggestions: Array)
signal health_check_requested()
signal publish_start_requested()
signal publish_progress_received(message: String)
signal publish_cancel_requested()
signal publish_view_requested()
signal unpublish_start_requested()
signal unpublish_complete_received(success: bool, error: String)

# Reference to streaming coordinator (for tool streaming commands)
var streaming_coordinator = null
var config = null

var was_agent_recently_streaming: bool = false


func _init(streaming_coord = null, cfg = null):
	streaming_coordinator = streaming_coord
	config = cfg


func dispatch_render_command(command: Dictionary) -> void:
	"""
	Main entry point for Python render commands.

	Routes to appropriate handler based on command type.
	"""
	var cmd_type: String = command.get("command", "")
	var data: Dictionary = command.get("data", {})

	match cmd_type:
		"add_message":
			add_message_requested.emit(data)
		"update_message":
			update_message_requested.emit(data)
		"append_to_message":
			append_to_message_requested.emit(data)
		"replace_ephemeral":
			replace_ephemeral_requested.emit(data)
		"remove_ephemeral":
			remove_ephemeral_requested.emit(data)
		"replace_message_id":
			replace_message_id_requested.emit(data)
		"remove_message":
			remove_message_requested.emit(data)
		"clear_messages":
			clear_messages_requested.emit(data)
		"tool_call_start":
			if streaming_coordinator:
				streaming_coordinator.handle_tool_call_start(data)
		"tool_call_delta":
			if streaming_coordinator:
				streaming_coordinator.handle_tool_call_delta(data)
		"tool_call_stop":
			if streaming_coordinator:
				streaming_coordinator.handle_tool_call_stop(data)
		"scene_progress_start":
			if streaming_coordinator:
				streaming_coordinator.handle_scene_progress_start(data)
		"scene_progress_delta":
			if streaming_coordinator:
				streaming_coordinator.handle_scene_progress_delta(data)
		"scene_progress_stop":
			if streaming_coordinator:
				streaming_coordinator.handle_scene_progress_stop(data)
		"stream_complete":
			was_agent_recently_streaming = false
			stream_complete_received.emit()
			if streaming_coordinator:
				streaming_coordinator.stop_all_streaming()
		"session_restore_start":
			# Session restore starting - set flag to skip animations
			session_restore_start.emit()
		"session_restore_complete":
			# Session restore finished
			session_restore_complete.emit()
		"stop_animations":
			# Stop all typewriter animations (sent when user clicks Stop)
			stop_animations_requested.emit()
		"set_animating_interactive":
			var message_id = data.get("message_id", "")
			set_animating_interactive_requested.emit(message_id)
		"cancel_pending_confirmations":
			cancel_pending_confirmations_requested.emit()
		"streaming_timeout":
			# Streaming timeout detected - message_controller already handled cleanup
			# Just acknowledge so we don't show "Unknown command" warning
			pass
		"connection_status":
			# Proactive health check status update (project service warning, etc.)
			var state = data.get("state", "")
			var message = data.get("message", "")
			connection_status_update.emit(state, message)
		"credits_update":
			var balance = data.get("balance", 0.0)
			var total = data.get("total", 0.0)
			credits_update.emit(balance, total)
		"auth_error":
			# Auth error detected by health check or API call
			var error_type = data.get("error_type", "unauthorized")
			var status_code = data.get("status_code", 401)
			auth_error_detected.emit(error_type, status_code)
		"test_sentry":
			# Test Sentry error tracking from Python
			push_error("Test: Engine error tracking")
			push_warning("Test: Engine warning tracking")
		"yolo_mode":
			# Enable/disable YOLO mode (auto-confirm all Bash tools)
			var enabled = data.get("enabled", false)
			if config:
				if enabled:
					config.enable_yolo_mode()
				else:
					config.disable_yolo_mode()
		"is_streaming":
			was_agent_recently_streaming = data.get("is_streaming", false)
			is_streaming_changed.emit(was_agent_recently_streaming)
		"prompt_suggestions_ready":
			var suggestions = data.get("suggestions", [])
			if suggestions.size() > 0:
				prompt_suggestions_ready.emit(suggestions)
		"request_health_check":
			# Python worker requesting health check via C++ MoonlakeAuth
			health_check_requested.emit()
		"crash_moonlake":
			OS.crash("Test crash for crash recovery")
		"publish_start":
			publish_start_requested.emit()
		"publish_progress":
			var message = data.get("message", "")
			publish_progress_received.emit(message)
		"publish_cancel":
			publish_cancel_requested.emit()
		"publish_view":
			publish_view_requested.emit()
		"unpublish_start":
			unpublish_start_requested.emit()
		"unpublish_complete":
			var success = data.get("success", false)
			var error = data.get("error", "")
			unpublish_complete_received.emit(success, error)
		_:
			Log.warn("[MOONLAKE] Unknown command: %s" % cmd_type)
