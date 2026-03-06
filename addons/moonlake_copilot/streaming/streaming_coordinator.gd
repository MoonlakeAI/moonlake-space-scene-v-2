@tool
extends RefCounted
class_name StreamingCoordinator

## Streaming coordination for agent tool calls
## Manages active streaming renderers and their lifecycle

signal streaming_started
signal streaming_stopped
signal scroll_requested

const ToolStreamingRendererV2 = preload("res://addons/moonlake_copilot/renderer/tool_streaming_renderer_v2.gd")
const SceneProgressStreamingRendererV2 = preload("res://addons/moonlake_copilot/renderer/scene_progress_streaming_renderer_v2.gd")

# Active streaming tools: tool_call_id -> ToolStreamingRendererV2
var active_streaming_tools: Dictionary = {}

# Active scene progress: scene_id -> SceneProgressStreamingRendererV2
var active_scene_progress: Dictionary = {}

# State tracking
var is_agent_streaming: bool = false
var streaming_start_time: float = 0.0
var last_streaming_activity: float = 0.0
# UI streaming timeout: How long before stop button reverts to send button
# See godot_worker/godot_worker/config.py for full timeout documentation
# This timeout is LONGER than the streaming delta timeout (30s) to allow
# the backend timeout to trigger first. This is a UI safety mechanism.
const STREAMING_TIMEOUT_SEC: float = 60.0

# UI reference
var message_container: VBoxContainer
var config = null


func _init(container: VBoxContainer, cfg = null):
	message_container = container
	config = cfg


func handle_tool_call_start(data: Dictionary) -> void:
	if not config or not config.enable_tool_streaming:
		return

	var tool_call_id = data.get("tool_call_id", "")
	if tool_call_id.is_empty():
		return

	var content_block = data.get("content_block", {})
	var tool_name = content_block.get("tool_name", "")

	if tool_name in config.tool_streaming_exclude:
		return

	var file_path = "Unknown"
	var description = ""
	var tool_input = content_block.get("input", "")
	if tool_input != "":
		var parsed = JSON.parse_string(tool_input)
		if parsed and typeof(parsed) == TYPE_DICTIONARY:
			file_path = parsed.get("file_path", "Unknown")

	var renderer = ToolStreamingRendererV2.new()
	var message_type = data.get("type", "")
	renderer.initialize(tool_name, file_path, description, message_type)
	renderer.streaming_complete.connect(func(): _on_streaming_complete(tool_call_id))

	message_container.add_child(renderer)
	active_streaming_tools[tool_call_id] = renderer

	if not is_agent_streaming:
		is_agent_streaming = true
		streaming_start_time = Time.get_ticks_msec() / 1000.0
		streaming_started.emit()

	last_streaming_activity = Time.get_ticks_msec() / 1000.0
	scroll_requested.emit()


func handle_tool_call_delta(data: Dictionary) -> void:
	"""Handle tool_call_delta - forward to renderer"""
	var tool_call_id = data.get("tool_call_id", "")
	if not active_streaming_tools.has(tool_call_id):
		return

	var delta_data = data.get("delta", {})

	if typeof(delta_data) != TYPE_DICTIONARY:
		Log.error("[StreamingCoordinator] Invalid delta format - expected Dictionary, got %s" % type_string(typeof(delta_data)))
		return

	var partial_json = delta_data.get("partial_json", "")
	if partial_json.is_empty():
		return

	var renderer = active_streaming_tools[tool_call_id]
	renderer.append_delta(partial_json)

	last_streaming_activity = Time.get_ticks_msec() / 1000.0
	scroll_requested.emit()


func handle_tool_call_stop(data: Dictionary) -> void:
	"""Handle tool_call_stop - complete streaming"""
	var tool_call_id = data.get("tool_call_id", "")
	if not active_streaming_tools.has(tool_call_id):
		return

	var renderer = active_streaming_tools[tool_call_id]

	var content_block = data.get("content_block", {})
	var tool_input_raw = content_block.get("tool_input", "")

	var tool_input = null
	if typeof(tool_input_raw) == TYPE_STRING and tool_input_raw != "":
		tool_input = JSON.parse_string(tool_input_raw)
	elif typeof(tool_input_raw) == TYPE_DICTIONARY:
		tool_input = tool_input_raw

	if tool_input and typeof(tool_input) == TYPE_DICTIONARY:
		var description = tool_input.get("description", "")

		if description == "":
			if renderer.tool_name in ["Write", "Read", "Edit", "MultiEdit"]:
				var file_path = tool_input.get("file_path", "")
				if file_path != "":
					description = file_path.get_file()
			elif renderer.tool_name == "web_search":
				var query = tool_input.get("query", "")
				if query != "":
					description = query

		if description != "":
			renderer.set_description(description)

		var tool_input_str = ""
		if typeof(tool_input_raw) == TYPE_DICTIONARY:
			tool_input_str = JSON.stringify(tool_input_raw, "  ", false)
		elif typeof(tool_input_raw) == TYPE_STRING:
			tool_input_str = tool_input_raw

		if tool_input_str != "":
			renderer.set_tool_input(tool_input_str)

	renderer.complete()
	last_streaming_activity = Time.get_ticks_msec() / 1000.0


func handle_scene_progress_start(data: Dictionary) -> void:
	"""Handle scene_progress_start - create streaming renderer"""
	var content_block = data.get("content_block", {})
	var scene_id = content_block.get("id", "")
	if scene_id.is_empty():
		return

	var renderer = SceneProgressStreamingRendererV2.new()
	var message_type = data.get("type", "")
	renderer.initialize(scene_id, message_type)
	renderer.streaming_complete.connect(func(sid): _on_scene_progress_complete(sid))

	message_container.add_child(renderer)
	active_scene_progress[scene_id] = renderer

	if not is_agent_streaming:
		is_agent_streaming = true
		streaming_start_time = Time.get_ticks_msec() / 1000.0
		streaming_started.emit()

	last_streaming_activity = Time.get_ticks_msec() / 1000.0
	scroll_requested.emit()


func handle_scene_progress_delta(data: Dictionary) -> void:
	"""Handle scene_progress_delta - forward to all active renderers"""
	var delta_data = data.get("delta", {})

	if typeof(delta_data) != TYPE_DICTIONARY:
		Log.error("[StreamingCoordinator] Invalid delta format - expected Dictionary, got %s" % type_string(typeof(delta_data)))
		return

	var text = delta_data.get("text", "")
	if text.is_empty():
		return

	# Broadcast to all active scene progress renderers (backend doesn't send scene_id)
	for renderer in active_scene_progress.values():
		if not renderer.is_complete:
			renderer.append_delta(text)

	last_streaming_activity = Time.get_ticks_msec() / 1000.0
	scroll_requested.emit()


func handle_scene_progress_stop(data: Dictionary) -> void:
	"""Handle scene_progress_stop - complete streaming"""
	var content_block = data.get("content_block", {})
	var scene_id = content_block.get("id", "")
	if scene_id.is_empty():
		return

	if not active_scene_progress.has(scene_id):
		return

	var renderer = active_scene_progress[scene_id]
	renderer.complete()
	last_streaming_activity = Time.get_ticks_msec() / 1000.0


func _on_scene_progress_complete(scene_id: String) -> void:
	"""Handle scene progress streaming completion signal"""
	if not active_scene_progress.has(scene_id):
		return

	var renderer = active_scene_progress[scene_id]
	active_scene_progress.erase(scene_id)

	if renderer and is_instance_valid(renderer):
		_deferred_free(renderer)

	if active_scene_progress.is_empty() and active_streaming_tools.is_empty():
		is_agent_streaming = false
		streaming_stopped.emit()


func _on_streaming_complete(_tool_call_id: String) -> void:
	pass


func stop_all_streaming() -> void:
	is_agent_streaming = false

	for tool_call_id in active_streaming_tools.keys():
		var renderer = active_streaming_tools[tool_call_id]
		if renderer and is_instance_valid(renderer):
			renderer.complete()
			renderer.queue_free()

	for scene_id in active_scene_progress.keys():
		var renderer = active_scene_progress[scene_id]
		if renderer and is_instance_valid(renderer):
			renderer.complete()
			renderer.queue_free()

	active_streaming_tools.clear()
	active_scene_progress.clear()
	streaming_stopped.emit()


func remove_streaming_widget(tool_call_id: String) -> void:
	if not active_streaming_tools.has(tool_call_id):
		return

	var renderer = active_streaming_tools[tool_call_id]
	active_streaming_tools.erase(tool_call_id)

	if renderer and is_instance_valid(renderer):
		renderer.queue_free()

	if active_streaming_tools.is_empty() and active_scene_progress.is_empty():
		is_agent_streaming = false
		streaming_stopped.emit()


func check_timeout() -> bool:
	"""Check if streaming has timed out. Returns true if timed out."""
	if is_agent_streaming:
		var time_since_activity = Time.get_ticks_msec() / 1000.0 - last_streaming_activity

		if time_since_activity > STREAMING_TIMEOUT_SEC:
			Log.warn("[StreamingCoordinator] Streaming timeout after %d seconds of inactivity" % STREAMING_TIMEOUT_SEC)
			is_agent_streaming = false
			streaming_stopped.emit()
			return true

	return false


func get_streaming_state() -> bool:
	"""Get current streaming state"""
	return is_agent_streaming


func has_active_streams() -> bool:
	"""Check if there are any active streaming tools or scene progress"""
	return not active_streaming_tools.is_empty() or not active_scene_progress.is_empty()


func _deferred_free(renderer: Node) -> void:
	"""Free renderer after collapse animation completes"""
	if renderer and is_instance_valid(renderer) and renderer.is_inside_tree():
		renderer.queue_free()
