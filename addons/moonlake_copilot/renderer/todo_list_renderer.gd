@tool
extends RefCounted

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const RendererCleanup = preload("res://addons/moonlake_copilot/renderer/renderer_cleanup.gd")

static var _current_widget: TodoListWidget = null


static func render(message: Dictionary) -> Control:
	if _current_widget and is_instance_valid(_current_widget):
		_current_widget._on_destroy()
	_current_widget = TodoListWidget.new()
	_current_widget.initialize(message)
	return _current_widget


class TodoListWidget extends PanelContainer:
	var code_edit: CodeEdit
	var animation_timer: Timer
	var hide_timer: Timer
	var animation_frame: int = 0
	var current_todo_list: Array = []

	const ANIMATION_FRAMES := ["◐", "◓", "◑", "◒"]
	const HIDE_DELAY := 5.0

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		RendererCleanup.connect_cleanup(_on_destroy)

		code_edit = CodeEdit.new()
		code_edit.editable = false
		code_edit.gutters_draw_line_numbers = false
		code_edit.indent_automatic = false
		code_edit.auto_brace_completion_highlight_matching = false
		code_edit.selecting_enabled = true
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		code_edit.scroll_fit_content_height = true
		code_edit.scroll_past_end_of_file = false
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		var transparent_style = Styles.transparent_label()
		code_edit.add_theme_stylebox_override("normal", transparent_style)
		code_edit.add_theme_stylebox_override("focus", transparent_style)

		ThemeConstants.apply_monospace_font(code_edit)

		add_child(code_edit)

		animation_timer = Timer.new()
		animation_timer.wait_time = 0.15
		animation_timer.timeout.connect(_on_animation_timeout)
		add_child(animation_timer)

		hide_timer = Timer.new()
		hide_timer.wait_time = HIDE_DELAY
		hide_timer.one_shot = true
		hide_timer.timeout.connect(_on_hide_timeout)
		add_child(hide_timer)

		_apply_style()

	func _apply_style() -> void:
		add_theme_stylebox_override("panel", Styles.todo_list_panel())

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		current_todo_list = content.get("todo_list", [])

		_rebuild_text()

		var skip_auto_start = message.get("skip_interactive_animation", false)
		if not skip_auto_start:
			call_deferred("start_animation")
		call_deferred("_check_auto_hide")

	func start_animation() -> void:
		var has_running = false
		for todo in current_todo_list:
			if todo.get("status", "pending") == "running":
				has_running = true
				break

		if has_running and is_inside_tree():
			animation_timer.start()

	func finish_animation() -> void:
		if is_inside_tree():
			animation_timer.stop()

	func _rebuild_text() -> void:
		var lines = []
		lines.append("TODO LIST")
		lines.append("")

		for todo in current_todo_list:
			var status = todo.get("status", "pending")
			var description = todo.get("description", "")

			var icon = ""
			match status:
				"done":
					icon = "[✓]"
				"running":
					icon = "[" + ANIMATION_FRAMES[animation_frame % ANIMATION_FRAMES.size()] + "]"
				_:
					icon = "[ ]"

			lines.append(icon + " " + description)

		lines.append("")

		code_edit.text = "\n".join(lines)

	func _on_animation_timeout() -> void:
		animation_frame += 1
		_rebuild_text()

	func update_message(message: Dictionary) -> void:
		initialize(message)

	func _check_auto_hide() -> void:
		if current_todo_list.is_empty():
			return
		for todo in current_todo_list:
			if todo.get("status", "pending") != "done":
				hide_timer.stop()
				return
		if not hide_timer.is_stopped():
			return
		hide_timer.start()

	func _on_hide_timeout() -> void:
		_on_destroy()

	func _on_destroy() -> void:
		if is_inside_tree():
			finish_animation()
			queue_free()
