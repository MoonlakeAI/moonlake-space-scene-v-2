@tool
extends RefCounted

## Todo Controller - Manages pinned todo list above input box
##
## Responsibilities:
## - Pinned todo list rendering
## - Todo item creation with status indicators
## - Expand/collapse state management
## - Progress tracking and header updates

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

# UI References (set externally)
var pinned_todo_container: PanelContainer = null
var pinned_todo_content: Control = null
var pinned_todo_scroll_container: ScrollContainer = null
var pinned_todo_header: Label = null
var pinned_todo_header_hbox: HBoxContainer = null
var pinned_todo_spinner: Control = null
var pinned_todo_expand_icon: TextureRect = null

# State
var is_pinned_todo_expanded: bool = false  # Collapsed by default
var latest_todo_message: Dictionary = {}


func initialize(container: PanelContainer, content: Control, header: Label, header_hbox: HBoxContainer, spinner: Control, expand_icon: TextureRect, scroll_container: ScrollContainer, input_ctrl) -> void:
	pinned_todo_container = container
	pinned_todo_content = content
	pinned_todo_scroll_container = scroll_container
	pinned_todo_header = header
	pinned_todo_header_hbox = header_hbox
	pinned_todo_spinner = spinner
	pinned_todo_expand_icon = expand_icon

	if pinned_todo_header_hbox:
		pinned_todo_header_hbox.gui_input.connect(_on_header_input)

	input_ctrl.user_stop_completed.connect(clear)



## ============================================================================
## Todo List Rendering
## ============================================================================

func update_todo_list(message: Dictionary) -> void:
	"""Update the pinned todo list with new content"""
	if not pinned_todo_container or not pinned_todo_content:
		return

	# Store the latest todo message
	latest_todo_message = message

	# Clear existing content
	for child in pinned_todo_content.get_children():
		child.queue_free()

	# Extract todo list
	var content = message.get("content", {})
	var todo_list = content.get("todo_list", [])

	if todo_list.is_empty():
		# Hide pinned container if no todos
		pinned_todo_container.visible = false
		return

	# Show the pinned container
	pinned_todo_container.visible = true

	# Find current running task and count progress
	var current_task_description = ""
	var completed_count = 0
	var total_count = todo_list.size()
	var has_running_task = false

	for todo in todo_list:
		var status = todo.get("status", "pending")
		if status == "done":
			completed_count += 1
		elif status == "running" and not has_running_task:
			# Get the first running task as the header
			current_task_description = todo.get("description", "Working...")
			has_running_task = true

	# If no running task, show first pending task or "All complete"
	if not has_running_task:
		if completed_count < total_count:
			# Find first pending task
			for todo in todo_list:
				if todo.get("status", "") == "pending":
					current_task_description = todo.get("description", "Pending...")
					break
		else:
			current_task_description = "All tasks complete"

	# Update header with current task and progress
	pinned_todo_header.text = "%s (%d/%d)" % [current_task_description, completed_count, total_count]

	# Show/hide spinner based on whether there's an active running task
	if pinned_todo_spinner:
		pinned_todo_spinner.visible = has_running_task

	# Auto-hide if all tasks are completed
	if completed_count >= total_count:
		# All tasks complete - hide the todo container using a Timer
		if pinned_todo_container:
			var timer = Timer.new()
			timer.one_shot = true
			timer.wait_time = 2.0
			timer.timeout.connect(func():
				if pinned_todo_container and pinned_todo_container.visible:
					pinned_todo_container.visible = false
				timer.queue_free()
			)
			pinned_todo_container.add_child(timer)
			timer.start()
		return

	# Find first pending task (the "next" one to run)
	var first_pending_idx = -1
	for i in range(todo_list.size()):
		if todo_list[i].get("status", "pending") == "pending":
			first_pending_idx = i
			break

	# Create todo items
	for i in range(todo_list.size()):
		var todo = todo_list[i]
		var is_next_pending = (i == first_pending_idx)
		var item = _create_todo_item(todo, is_next_pending)
		pinned_todo_content.add_child(item)

	pinned_todo_scroll_container.visible = is_pinned_todo_expanded

	if is_pinned_todo_expanded:
		_scroll_to_running_item.call_deferred()


## ============================================================================
## Todo Item Creation
## ============================================================================

func _create_todo_item(todo: Dictionary, is_next_pending: bool = false) -> Control:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))

	var status = todo.get("status", "pending")
	var description = todo.get("description", "")

	var icon_size = int(ThemeConstants.spacing(20))
	var icon_container = CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(icon_size, icon_size)

	var PulseSpinner = load("res://addons/moonlake_copilot/renderer/pulse_spinner.gd")

	match status:
		"done":
			var icon_rect = TextureRect.new()
			icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
			icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture = EditorInterface.get_editor_theme().get_icon("StatusSuccess", "EditorIcons")
			icon_rect.modulate = Color(0.4, 0.9, 0.4)
			icon_container.add_child(icon_rect)
		"running":
			var spinner = PulseSpinner.new()
			spinner.spinner_size = icon_size
			spinner.custom_minimum_size = Vector2(icon_size, icon_size)
			icon_container.add_child(spinner)
		_:  # "pending"
			if is_next_pending:
				var spinner = PulseSpinner.new()
				spinner.spinner_size = icon_size
				spinner.custom_minimum_size = Vector2(icon_size, icon_size)
				spinner.modulate = Color(0.5, 0.5, 0.5)
				icon_container.add_child(spinner)
			else:
				var icon = Label.new()
				icon.text = "○"
				icon.custom_minimum_size = Vector2(icon_size, icon_size)
				icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				icon.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
				ThemeConstants.apply_inter_font(icon, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
				icon_container.add_child(icon)

	hbox.add_child(icon_container)

	# Todo description
	var label = Label.new()
	label.text = description.replace("[", "[lb]").replace("]", "[rb]")  # BBCode escape

	# Apply Inter font for UI
	ThemeConstants.apply_inter_font(label)

	# Style based on status
	if status == "done":
		# Reduced opacity for completed tasks
		label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.4))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)

	return hbox


## ============================================================================
## Expand/Collapse Control
## ============================================================================

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_header_pressed()


func _on_header_pressed() -> void:
	is_pinned_todo_expanded = !is_pinned_todo_expanded
	pinned_todo_scroll_container.visible = is_pinned_todo_expanded

	if pinned_todo_expand_icon:
		pinned_todo_expand_icon.texture = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowDown", "EditorIcons")
		pinned_todo_expand_icon.flip_v = not is_pinned_todo_expanded

	if is_pinned_todo_expanded:
		# Wait 2 frames for layout to complete (1 frame sometimes insufficient)
		await pinned_todo_scroll_container.get_tree().process_frame
		await pinned_todo_scroll_container.get_tree().process_frame
		_scroll_to_running_item()


func _scroll_to_running_item() -> void:
	var todo_list = latest_todo_message.get("content", {}).get("todo_list", [])
	for i in range(todo_list.size()):
		if todo_list[i].get("status") == "running":
			var child = pinned_todo_content.get_child(i)
			if child:
				pinned_todo_scroll_container.ensure_control_visible(child)
			return


func clear() -> void:
	"""Clear and hide the todo list (called on /clear command)"""
	# Clear the stored message
	latest_todo_message = {}

	# Clear content
	if pinned_todo_content:
		for child in pinned_todo_content.get_children():
			child.queue_free()

	# Hide container
	if pinned_todo_container:
		pinned_todo_container.visible = false

	# Hide spinner
	if pinned_todo_spinner:
		pinned_todo_spinner.visible = false


## ============================================================================
## UI Creation (called from chat_panel during _setup_ui)
## ============================================================================

static func create_pinned_todo_ui(parent: VBoxContainer) -> Dictionary:
	"""
	Create the pinned todo list UI structure.

	Returns a dictionary with references:
	{
		"container": PanelContainer,
		"content": VBoxContainer,
		"header": Button,
		"spinner": Control
	}
	"""
	var pinned_todo_container = PanelContainer.new()
	pinned_todo_container.visible = false  # Hidden by default until we get a todo list
	pinned_todo_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pinned_todo_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Style the pinned container
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.7, 0.9, 0.08)  # Light blue with transparency
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.8, 1.0, 0.25)  # Blue border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.border_blend = true
	style.anti_aliasing = true
	style.corner_detail = 8
	pinned_todo_container.add_theme_stylebox_override("panel", style)

	# VBox to hold header + content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pinned_todo_container.add_child(vbox)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(12)))
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	vbox.add_child(header_hbox)

	# Spinner container (left side)
	var spinner_container = CenterContainer.new()
	spinner_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_hbox.add_child(spinner_container)

	# Create spinner
	var PulseSpinner = load("res://addons/moonlake_copilot/renderer/pulse_spinner.gd")
	var pinned_todo_spinner = PulseSpinner.new()
	pinned_todo_spinner.spinner_size = ThemeConstants.spacing(28.0)
	pinned_todo_spinner.rotation_speed = 3.0
	pinned_todo_spinner.visible = true  # Will be toggled based on task status
	spinner_container.add_child(pinned_todo_spinner)

	var pinned_todo_header = Label.new()
	pinned_todo_header.text = "Current Task"
	pinned_todo_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pinned_todo_header.clip_text = true
	pinned_todo_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pinned_todo_header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	ThemeConstants.apply_inter_font(pinned_todo_header, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
	var header_font = SystemFont.new()
	header_font.font_weight = 600  # Semi-bold
	pinned_todo_header.add_theme_font_override("font", header_font)
	header_hbox.add_child(pinned_todo_header)

	var pinned_todo_expand_icon = TextureRect.new()
	pinned_todo_expand_icon.texture = EditorInterface.get_editor_theme().get_icon("GuiTreeArrowDown", "EditorIcons")
	pinned_todo_expand_icon.flip_v = true
	pinned_todo_expand_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pinned_todo_expand_icon.custom_minimum_size = Vector2(16, 16)
	header_hbox.add_child(pinned_todo_expand_icon)

	# Scroll container for content (prevents vertical overflow)
	var scroll_container = ScrollContainer.new()
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll_container.visible = false  # Start collapsed
	vbox.add_child(scroll_container)

	# Content container (inside scroll)
	var pinned_todo_content = VBoxContainer.new()
	pinned_todo_content.add_theme_constant_override("separation", int(ThemeConstants.spacing(2)))
	pinned_todo_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(pinned_todo_content)

	# Dynamically adjust scroll container height based on content (max 150px to fit in 600px min window)
	const MAX_TODO_HEIGHT = 150
	pinned_todo_content.resized.connect(func():
		var content_height = pinned_todo_content.get_combined_minimum_size().y
		scroll_container.custom_minimum_size.y = min(content_height, MAX_TODO_HEIGHT)
	)

	# Add to parent
	parent.add_child(pinned_todo_container)

	return {
		"container": pinned_todo_container,
		"content": pinned_todo_content,
		"scroll_container": scroll_container,
		"header": pinned_todo_header,
		"header_hbox": header_hbox,
		"spinner": pinned_todo_spinner,
		"expand_icon": pinned_todo_expand_icon
	}
