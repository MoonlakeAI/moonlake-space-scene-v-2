@tool
extends RefCounted

## SocketIO Manager - Handles connection lifecycle, reconnection, and error handling
##
## Responsibilities:
## - Connect/disconnect SocketIO
## - Reconnection with exponential backoff
## - Connection error handling
## - Authentication error detection

signal connection_established()
signal connection_lost()
signal connection_error(error_type: String)
signal reconnecting(attempt: int, next_delay: int)
signal system_message(message: String, category: String)

# Connection state
var is_socketio_connected: bool = false
var is_intentional_disconnect: bool = false
var auth_error_state: String = ""

# Python bridge reference
var python_bridge: Node = null

# Project and session
var current_project_id: String = ""
var session_token: String = ""


func _init(bridge: Node):
	python_bridge = bridge


func connect_socketio(project_id: String, token: String) -> void:
	"""Connect to agent service via Socket.IO"""
	if not python_bridge or python_bridge.pid == -1:
		Log.error("[MOONLAKE] Python bridge not available")
		return

	if project_id == "":
		Log.info("[MOONLAKE] No project_id yet, skipping SocketIO connection")
		return

	if token == "":
		Log.info("[MOONLAKE] No session token, skipping SocketIO connection")
		return

	current_project_id = project_id
	session_token = token

	is_socketio_connected = false
	system_message.emit("Connecting to agent...", "info")

	var params = {
		"project_id": current_project_id,
		"session_token": session_token if session_token != "" else null,
	}

	var result = await python_bridge.call_python_async("connect_socketio", params)

	# Check if connection failed (result is wrapped in {"result": {...}})
	var connect_result = result.get("result", {})
	if connect_result and not connect_result.get("success", false):
		var error = connect_result.get("error", "Unknown error")
		Log.error("[MOONLAKE] Failed to connect to agent service: " + error)

		# Check if this is an authentication error
		var error_lower = error.to_lower()
		if "token" in error_lower and ("expired" in error_lower or "invalid" in error_lower):
			# Token is expired or invalid - treat as auth error
			handle_authentication_error("token_expired")
		elif "unauthorized" in error_lower or "401" in error_lower:
			# Unauthorized - treat as auth error
			handle_authentication_error("unauthorized")
		else:
			# Generic connection error - don't clear session
			system_message.emit("Failed to connect to agent service: " + error, "fail")
			handle_connection_error()


func disconnect_socketio() -> void:
	"""Explicitly disconnect SocketIO"""
	if not python_bridge or python_bridge.pid == -1:
		return

	Log.info("[MOONLAKE] Disconnecting from agent service...")
	var disconnect_response = await python_bridge.call_python_async("disconnect_socketio", {})
	var disconnect_result = disconnect_response.get("result", {})

	if not disconnect_result.get("success", false):
		Log.warn("[MOONLAKE] Failed to disconnect old socket: " + str(disconnect_result))


func reconnect_after_login(project_id: String, token: String) -> void:
	"""Properly disconnect and reconnect after login with new token."""
	Log.info("[MOONLAKE] Reconnecting with new session token...")

	current_project_id = project_id
	session_token = token

	# Step 0: Clear any error state from previous auth failures
	auth_error_state = ""

	# Step 1: Explicitly disconnect old socket
	system_message.emit("Disconnecting old session...", "info")
	await disconnect_socketio()

	# Step 2: Small delay to ensure clean disconnect
	await python_bridge.get_tree().create_timer(0.5).timeout

	# Step 3: Connect with new token
	system_message.emit("Connecting with new credentials...", "info")
	connect_socketio(current_project_id, session_token)


func handle_connection_error(error: String = "Connection error") -> void:
	auth_error_state = "connection_failed"
	is_socketio_connected = false
	connection_error.emit("connection_failed")


func handle_authentication_error(error_type: String = "unauthorized") -> void:
	"""Handle authentication errors by clearing session and updating UI."""
	Log.error("[MOONLAKE] Authentication error: %s" % error_type)

	# Set error state
	auth_error_state = error_type

	# Clear session
	session_token = ""
	is_socketio_connected = false

	# Disconnect socket
	if python_bridge and python_bridge.pid != -1:
		python_bridge.call_python("disconnect_socketio", {})

	# Emit authentication error signal
	connection_error.emit(error_type)

	# Show appropriate message
	match error_type:
		"token_expired":
			system_message.emit("Authentication expired. Please login again.", "fail")
		"unauthorized":
			system_message.emit("Unauthorized. Please login again.", "fail")
		"server_error":
			system_message.emit("Server error. Please try again later.", "fail")
		_:
			system_message.emit("Authentication error. Please login again.", "fail")


func handle_socketio_event(event_type: String, result: Dictionary) -> void:
	"""
	Handle SocketIO system events from Python worker.

	Called from chat_panel when response_received with id=-1 (system notification).
	"""
	match event_type:
		"socketio_disconnected":
			Log.info("[MOONLAKE] SocketIO disconnected")
			is_socketio_connected = false
			connection_lost.emit()
			if is_intentional_disconnect:
				system_message.emit("Disconnected.", "info")
			else:
				system_message.emit("Connection lost. Reconnecting...", "info")
			is_intentional_disconnect = false

		"socketio_connected":
			is_socketio_connected = true
			# Clear any connection error state from previous failures
			auth_error_state = ""
			connection_established.emit()
			system_message.emit("Welcome to Moonlake. Let's build something fun together!", "success")

		"socketio_reconnecting":
			var attempt = result.get("attempt", 0)
			var next_delay = result.get("next_delay", 0)
			Log.info("[MOONLAKE] SocketIO reconnecting, attempt #%d (retry in ~%ds)" % [attempt, next_delay])
			is_socketio_connected = false
			reconnecting.emit(attempt, next_delay)

			# Show all reconnection attempts to visualize backoff
			if attempt <= 10:
				# Show first 10 attempts individually
				system_message.emit("Reconnecting... (attempt #%d, next retry in ~%ds)" % [attempt, next_delay], "info")
			elif attempt % 5 == 0:  # Show every 5th attempt after that
				system_message.emit("Still reconnecting... (attempt #%d, next retry in ~%ds)" % [attempt, next_delay], "info")

		"socketio_reconnect_attempt_failed":
			# Message already added by Python worker via _add_system_message
			pass

		"socketio_connect_error":
			var error = result.get("error", "Connection error")
			Log.warn("[MOONLAKE] SocketIO connection error: %s" % error)
			is_socketio_connected = false
			# Only treat as auth error if it's actually unauthorized
			# Generic connection errors shouldn't clear the session token
			if error == "unauthorized":
				handle_authentication_error("unauthorized")
			else:
				# Network error - don't clear session, show error message
				handle_connection_error(error)

		"socketio_reconnect_failed":
			Log.info("[MOONLAKE] SocketIO reconnection failed after max attempts")
			is_socketio_connected = false
			connection_error.emit("reconnect_failed")
			system_message.emit("Connection failed. Please check your internet connection and try reloading.", "fail")

		"socketio_auth_failed":
			var error = result.get("error", "Authentication failed")
			Log.info("[MOONLAKE] SocketIO authentication failed: %s" % error)
			is_socketio_connected = false
			system_message.emit(error, "fail")
			handle_authentication_error("unauthorized")


func check_http_error(result: Dictionary) -> bool:
	"""
	Check for HTTP error codes in response and handle auth errors.

	Returns true if an error was detected and handled.
	"""
	# Check for 401 Unauthorized response
	if result.get("http_code") == 401 or result.get("status_code") == 401:
		Log.info("[MOONLAKE] 401 Unauthorized - token expired/invalid")
		handle_authentication_error("token_expired")
		return true

	# Check for other error codes
	var http_code = result.get("http_code", 0)
	if http_code >= 500 and http_code < 600:
		Log.info("[MOONLAKE] Server error: %d" % http_code)
		handle_authentication_error("server_error")
		return true

	return false


func get_connection_state() -> Dictionary:
	"""Get current connection and auth error state"""
	return {
		"is_connected": is_socketio_connected,
		"error_state": auth_error_state
	}
