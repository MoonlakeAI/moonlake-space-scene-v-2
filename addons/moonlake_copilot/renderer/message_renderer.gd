@tool
extends RefCounted

## MessageRenderer Factory
##
## Routes message rendering to specific renderers based on message type.
## Phase 1: Text renderer implemented.
## Phase 2: Ephemeral renderer implemented.
## Phase 3: Error renderer implemented.
## Phase 4: TodoList renderer implemented.
## Phase 5: Progress renderer implemented.
## Phase 6: MultiStageProgress renderer implemented.
## Phase 7: MultipleChoice renderer implemented.
## Phase 8: ToolResult, ToolCall, Thinking renderers implemented.
## Phase 9: Info renderer implemented.

const TextRendererV2 = preload("res://addons/moonlake_copilot/renderer/text_renderer_v2.gd")
const EphemeralRendererV2 = preload("res://addons/moonlake_copilot/renderer/ephemeral_renderer_v2.gd")
const ErrorRendererV2 = preload("res://addons/moonlake_copilot/renderer/error_renderer_v2.gd")
const TodoListRenderer = preload("res://addons/moonlake_copilot/renderer/todo_list_renderer.gd")
const ProgressRenderer = preload("res://addons/moonlake_copilot/renderer/progress_renderer.gd")
const MultiStageProgressRenderer = preload("res://addons/moonlake_copilot/renderer/multi_stage_progress_renderer.gd")
const MultipleChoiceRenderer = preload("res://addons/moonlake_copilot/renderer/multiple_choice_renderer.gd")
const AskUserQuestionRenderer = preload("res://addons/moonlake_copilot/renderer/ask_user_question_renderer.gd")
const ToolResultRendererV2 = preload("res://addons/moonlake_copilot/renderer/tool_result_renderer_v2.gd")
const ToolCallRendererV2 = preload("res://addons/moonlake_copilot/renderer/tool_call_renderer_v2.gd")
const ToolCallStopRendererV2 = preload("res://addons/moonlake_copilot/renderer/tool_call_stop_renderer_v2.gd")
const ToolStreamingRendererV2 = preload("res://addons/moonlake_copilot/renderer/tool_streaming_renderer_v2.gd")
const ThinkingRendererV2 = preload("res://addons/moonlake_copilot/renderer/thinking_renderer_v2.gd")
const InfoRendererV2 = preload("res://addons/moonlake_copilot/renderer/info_renderer_v2.gd")
const SystemMessageRendererV2 = preload("res://addons/moonlake_copilot/renderer/system_message_renderer_v2.gd")
const SceneProgressRendererV2 = preload("res://addons/moonlake_copilot/renderer/scene_progress_renderer_v2.gd")

static func create_renderer(message_type: String) -> RefCounted:
	"""
	Create appropriate renderer for message type.

	Args:
		message_type: Message type (todo_list, progress, etc.)

	Returns:
		Renderer instance or null if unsupported
	"""
	match message_type:
		"todo_list":
			return TodoListRenderer.new()
		"progress":
			return ProgressRenderer.new()
		"multi_stage_progress":
			return MultiStageProgressRenderer.new()
		"multiple_choice":
			return MultipleChoiceRenderer.new()
		"clear_messages", "prompt_suggestion":
			return null
		_:
			Log.warn("[MessageRenderer] Unsupported message type: %s" % message_type)
			return null


static func render_message(message: Dictionary, config = null) -> Control:
	"""
	Render message to Control node.

	Args:
		message: Message dictionary from Python
		config: CopilotConfig instance (passed from plugin)

	Returns:
		Rendered Control node, or null for system commands
	"""
	var message_type: String = message.get("type", "text")

	# System commands that should not be rendered
	if message_type == "clear_messages":
		return null

	# Handle V2 renderers with static render() methods
	match message_type:
		"text":
			return TextRendererV2.render(message, config)
		"ephemeral":
			return EphemeralRendererV2.render(message)
		"error":
			return ErrorRendererV2.render(message)
		"info":
			return InfoRendererV2.render(message)
		"system_message":
			return SystemMessageRendererV2.render(message)
		"tool_result":
			return ToolResultRendererV2.render(message)
		"tool_call":
			return ToolCallRendererV2.render(message, config)
		"tool_call_stop":
			return ToolCallStopRendererV2.render(message)
		"tool_use":
			# Convert tool_use format to tool_call format for rendering
			var original_content = message.get("content", {})
			var content_block = original_content.get("content_block", {})
			if content_block.get("name", "") == "AskUserQuestion":
				return AskUserQuestionRenderer.render(message)
			# tool_call_id may be at top level (live) or in content (restored)
			var tool_call_id = message.get("tool_call_id", original_content.get("tool_call_id", ""))
			var tool_call_message = {
				"id": message.get("id", ""),
				"type": "tool_use",
				"sender": "copilot",
				"content": {
					"tool_name": content_block.get("name", "Unknown"),
					"tool_input": JSON.stringify(content_block.get("input", {})),
					"tool_call_id": tool_call_id,
					"confirmed": original_content.get("confirmed")
				},
				"is_last_message": message.get("is_last_message", false),
				"ask_confirmation": message.get("metadata", {}).get("ask_confirmation", false)
			}
			var widget = ToolCallRendererV2.render(tool_call_message, config)
			widget.override_icon = EditorInterface.get_editor_theme().get_icon("Search", "EditorIcons")
			widget._update_header()
			return widget
		"thinking":
			return ThinkingRendererV2.render(message)
		"scene_progress":
			return SceneProgressRendererV2.render(message)

	# Handle other renderers with instance methods
	var renderer = create_renderer(message_type)

	if renderer and renderer.has_method("render"):
		return renderer.render(message)

	var worker_config: Dictionary = MoonlakeResources.get_worker_config()
	var is_dev = worker_config["moonlake_mode"] == "development"
	# Fallback: show unhandled message type in dev mode only
	if is_dev:
		const UnhandledEventRenderer = preload("res://addons/moonlake_copilot/renderer/unhandled_event_renderer.gd")
		return UnhandledEventRenderer.render(message_type, message.get("content", {}))

	return null
