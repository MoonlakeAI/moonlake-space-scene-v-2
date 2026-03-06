class_name ChatPanelUIBuilder
extends RefCounted

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const AttachmentMenu = preload("res://addons/moonlake_copilot/attachments/attachment_menu.gd")
const SlashCommandsMenu = preload("res://addons/moonlake_copilot/slash_commands/slash_commands_menu.gd")
const TodoController = preload("res://addons/moonlake_copilot/todo/todo_controller.gd")
const QueuedMessageController = preload("res://addons/moonlake_copilot/queue/queued_message_controller.gd")
const PublishController = preload("res://addons/moonlake_copilot/publish/publish_controller.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const ErrorCounterButton = preload("res://addons/moonlake_copilot/error_counter/error_counter_button.gd")
const PopupMenuFactory = preload("res://addons/moonlake_copilot/ui/popup_menu_factory.gd")

const PLACEHOLDER_GREETING = "Describe your game. Be as specific as possible!\n\n"

const PROMPT_TIPS = [
	{"text": "Tip: Be specific about what you want to build or fix", "weight": 1},
	{"text": "Tip: Ask Moonlake to explain code before modifying it", "weight": 1},
	{"text": "Tip: Moonlake supports long-running generation from a single prompt", "weight": 1},
]

static func _get_weighted_random_tip() -> String:
	var total_weight = 0
	for tip in PROMPT_TIPS:
		total_weight += tip["weight"]

	var random_value = randf() * total_weight
	var cumulative_weight = 0.0

	for tip in PROMPT_TIPS:
		cumulative_weight += tip["weight"]
		if random_value <= cumulative_weight:
			return tip["text"]

	return PROMPT_TIPS[0]["text"]


static func build_ui(parent_control: Control, config = null) -> Dictionary:
	var ui = {}

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_right = 0
	vbox.offset_bottom = 0
	
	parent_control.add_child(vbox)

	# Shared content area for messages + todo (flex together within available space)
	var content_area = VBoxContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_theme_constant_override("separation", 0)
	vbox.add_child(content_area)

	ui["messages_wrapper"] = Control.new()
	ui["messages_wrapper"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["messages_wrapper"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui["messages_wrapper"].custom_minimum_size = Vector2(0, int(ThemeConstants.spacing(50)))
	ui["messages_wrapper"].clip_contents = true  # Prevent children from overflowing
	content_area.add_child(ui["messages_wrapper"])

	ui["scroll_container"] = ScrollContainer.new()
	ui["scroll_container"].set_anchors_preset(Control.PRESET_FULL_RECT)
	ui["scroll_container"].horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui["scroll_container"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ui["messages_wrapper"].add_child(ui["scroll_container"])

	var message_margin = MarginContainer.new()
	message_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_margin.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(16)))
	message_margin.add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(16)))
	ui["scroll_container"].add_child(message_margin)

	ui["message_container"] = VBoxContainer.new()
	ui["message_container"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["message_container"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui["message_container"].add_theme_constant_override("separation", int(ThemeConstants.spacing(16)))
	message_margin.add_child(ui["message_container"])

	var empty_state_nodes = _create_empty_state(ui["message_container"], parent_control)
	ui["empty_state_container"] = empty_state_nodes["empty_state_container"]
	ui["empty_state_center"] = empty_state_nodes["empty_state_center"]
	ui["typewriter_label"] = empty_state_nodes["typewriter_label"]
	ui["typewriter_timer"] = empty_state_nodes["typewriter_timer"]

	ui["new_message_toast"] = Button.new()
	ui["new_message_toast"].text = "↓ New Messages"
	var toast_width = int(ThemeConstants.spacing(120))
	var toast_height = int(ThemeConstants.spacing(40))
	ui["new_message_toast"].custom_minimum_size = Vector2(toast_width, toast_height)
	ui["new_message_toast"].visible = false
	ui["new_message_toast"].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ui["new_message_toast"].anchor_left = 0.5
	ui["new_message_toast"].anchor_top = 1.0
	ui["new_message_toast"].anchor_right = 0.5
	ui["new_message_toast"].anchor_bottom = 1.0
	ui["new_message_toast"].offset_left = -toast_width / 2
	ui["new_message_toast"].offset_top = -95
	ui["new_message_toast"].offset_right = toast_width / 2
	ui["new_message_toast"].offset_bottom = -55

	var toast_style = StyleBoxFlat.new()
	toast_style.bg_color = Color("#3B82F6")  # Blue background
	toast_style.set_corner_radius_all(int(ThemeConstants.spacing(28)))
	toast_style.content_margin_left = int(ThemeConstants.spacing(24))
	toast_style.content_margin_right = int(ThemeConstants.spacing(24))
	toast_style.content_margin_top = int(ThemeConstants.spacing(12))
	toast_style.content_margin_bottom = int(ThemeConstants.spacing(12))
	toast_style.shadow_color = Color(0, 0, 0, 0.3)
	toast_style.shadow_size = 6
	ui["new_message_toast"].add_theme_stylebox_override("normal", toast_style)

	var toast_hover = toast_style.duplicate()
	toast_hover.bg_color = Color("#2563EB")  # Darker blue on hover
	ui["new_message_toast"].add_theme_stylebox_override("hover", toast_hover)

	ui["new_message_toast"].add_theme_color_override("font_color", Color.WHITE)
	ThemeConstants.apply_inter_font(ui["new_message_toast"], ThemeConstants.Typography.FONT_SIZE_DEFAULT)

	ui["messages_wrapper"].add_child(ui["new_message_toast"])

	var todo_ui = TodoController.create_pinned_todo_ui(content_area)
	ui["todo_container"] = todo_ui["container"]
	ui["todo_content"] = todo_ui["content"]
	ui["todo_scroll_container"] = todo_ui["scroll_container"]
	ui["todo_header"] = todo_ui["header"]
	ui["todo_header_hbox"] = todo_ui["header_hbox"]
	ui["todo_spinner"] = todo_ui["spinner"]
	ui["todo_expand_icon"] = todo_ui["expand_icon"]

	var queue_ui = QueuedMessageController.create_ui(vbox)
	ui["queue_container"] = queue_ui["container"]
	ui["queue_content"] = queue_ui["content"]
	ui["queue_header"] = queue_ui["header"]
	ui["queue_close_button"] = queue_ui["close_button"]

	var publish_ui = PublishController.create_ui(vbox)
	ui["publish_container"] = publish_ui["container"]
	ui["publish_header"] = publish_ui["header"]
	ui["publish_header_hbox"] = publish_ui["header_hbox"]
	ui["publish_spinner"] = publish_ui["spinner"]
	ui["publish_progress_log"] = publish_ui["progress_log"]
	ui["publish_scroll_container"] = publish_ui["scroll_container"]
	ui["publish_cancel_button"] = publish_ui["cancel_button"]
	ui["publish_view_button"] = publish_ui["view_button"]
	ui["publish_close_button"] = publish_ui["close_button"]

	var is_macos = OS.get_name() == "macOS"
	var button_size = 60 if is_macos else 32  # Smaller buttons

	# Suggestions panel (above attachments)
	ui["suggestions_wrapper"] = MarginContainer.new()
	ui["suggestions_wrapper"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["suggestions_wrapper"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui["suggestions_wrapper"].visible = false
	ui["suggestions_wrapper"].add_theme_constant_override("margin_left", 0)
	ui["suggestions_wrapper"].add_theme_constant_override("margin_right", 0)
	ui["suggestions_wrapper"].add_theme_constant_override("margin_top", 0)
	ui["suggestions_wrapper"].add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(6)))
	vbox.add_child(ui["suggestions_wrapper"])

	ui["suggestions_container"] = HFlowContainer.new()
	ui["suggestions_container"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["suggestions_container"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui["suggestions_container"].add_theme_constant_override("h_separation", int(ThemeConstants.spacing(8)))
	ui["suggestions_container"].add_theme_constant_override("v_separation", int(ThemeConstants.spacing(8)))
	ui["suggestions_wrapper"].add_child(ui["suggestions_container"])

	ui["attachment_chips_wrapper"] = MarginContainer.new()
	ui["attachment_chips_wrapper"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["attachment_chips_wrapper"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui["attachment_chips_wrapper"].visible = false
	ui["attachment_chips_wrapper"].add_theme_constant_override("margin_left", int(ThemeConstants.spacing(12)))
	ui["attachment_chips_wrapper"].add_theme_constant_override("margin_right", int(ThemeConstants.spacing(12)))
	ui["attachment_chips_wrapper"].add_theme_constant_override("margin_top", 0)
	ui["attachment_chips_wrapper"].add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(6)))

	vbox.add_child(ui["attachment_chips_wrapper"])

	ui["attachment_chips_container"] = GridContainer.new()
	ui["attachment_chips_container"].columns = 3
	ui["attachment_chips_container"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["attachment_chips_container"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui["attachment_chips_container"].add_theme_constant_override("h_separation", int(ThemeConstants.spacing(8)))
	ui["attachment_chips_container"].add_theme_constant_override("v_separation", int(ThemeConstants.spacing(8)))
	ui["attachment_chips_wrapper"].add_child(ui["attachment_chips_container"])

	# Add divider above input controls
	var divider = HSeparator.new()
	divider.add_theme_constant_override("separation", 1)
	var divider_style = StyleBoxFlat.new()
	divider_style.bg_color = Color(1.0, 1.0, 1.0, 0.1)  # Subtle white divider
	divider_style.content_margin_top = 0
	divider_style.content_margin_bottom = 0
	divider.add_theme_stylebox_override("separator", divider_style)
	vbox.add_child(divider)

	var yolo_wrapper = MarginContainer.new()
	yolo_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yolo_wrapper.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(16)))
	yolo_wrapper.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(16)))
	yolo_wrapper.add_theme_constant_override("margin_top", 0)
	yolo_wrapper.add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(4)))
	yolo_wrapper.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	vbox.add_child(yolo_wrapper)
	ui["yolo_wrapper"] = yolo_wrapper

	var yolo_hbox = HBoxContainer.new()
	yolo_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
	yolo_wrapper.add_child(yolo_hbox)

	ui["yolo_toggle"] = CheckButton.new()
	ui["yolo_toggle"].button_pressed = false
	yolo_hbox.add_child(ui["yolo_toggle"])

	var yolo_label = Label.new()
	yolo_label.text = "Auto-Accept Bash Commands"
	yolo_label.clip_text = true
	yolo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeConstants.apply_inter_font(yolo_label, ThemeConstants.Typography.FONT_SIZE_SMALL)
	yolo_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	yolo_hbox.add_child(yolo_label)

	var input_wrapper = MarginContainer.new()
	input_wrapper.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(8)))
	input_wrapper.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(8)))
	input_wrapper.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(8)))
	input_wrapper.add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(8)))
	input_wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(input_wrapper)

	ui["input_container"] = Control.new()
	ui["input_container"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui["input_container"].custom_minimum_size = Vector2(0, 200)
	ui["input_container"].clip_contents = false
	input_wrapper.add_child(ui["input_container"])

	var button_margin = button_size + 12

	ui["resize_handle"] = Control.new()
	ui["resize_handle"].anchor_left = 0.0
	ui["resize_handle"].anchor_top = 1.0
	ui["resize_handle"].anchor_right = 1.0
	ui["resize_handle"].anchor_bottom = 1.0
	ui["resize_handle"].offset_left = 0
	ui["resize_handle"].offset_top = -306  # Just above input box (-300 - 6)
	ui["resize_handle"].offset_right = 0
	ui["resize_handle"].offset_bottom = -300
	ui["resize_handle"].grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui["resize_handle"].mouse_filter = Control.MOUSE_FILTER_STOP
	ui["resize_handle"].mouse_default_cursor_shape = Control.CURSOR_VSPLIT
	ui["input_container"].add_child(ui["resize_handle"])

	ui["input_box"] = CodeEdit.new()
	ui["input_box"].anchor_left = 0.0
	ui["input_box"].anchor_top = 1.0
	ui["input_box"].anchor_right = 1.0
	ui["input_box"].anchor_bottom = 1.0
	ui["input_box"].offset_left = 0
	ui["input_box"].offset_top = -300
	ui["input_box"].offset_right = 0
	ui["input_box"].offset_bottom = 0
	ui["input_box"].grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui["input_box"].placeholder_text = PLACEHOLDER_GREETING + _get_weighted_random_tip()
	ui["input_box"].wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ui["input_box"].scroll_fit_content_height = false
	ui["input_box"].scroll_smooth = true
	ui["input_box"].gutters_draw_line_numbers = false
	ui["input_box"].syntax_highlighter = null
	ui["input_box"].auto_brace_completion_enabled = false

	var input_style = StyleBoxFlat.new()
	input_style.bg_color = ThemeConstants.COLORS.BG_USER_MESSAGE  # Match user message bubble
	input_style.border_color = ThemeConstants.COLORS.BORDER_USER_MESSAGE  # Match user message border
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(24)  # Increased border radius
	input_style.anti_aliasing = true
	input_style.anti_aliasing_size = 2.0
	input_style.content_margin_left = int(ThemeConstants.spacing(24))  # Less horizontal padding
	input_style.content_margin_right = int(ThemeConstants.spacing(24))
	input_style.content_margin_top = int(ThemeConstants.spacing(20))  # More top padding
	input_style.content_margin_bottom = int(ThemeConstants.spacing(40))
	ui["input_box"].add_theme_stylebox_override("normal", input_style)
	ui["input_box"].add_theme_stylebox_override("focus", input_style)

	ui["input_box"].add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	ui["input_box"].add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.5, 1.0))
	ui["input_box"].add_theme_constant_override("line_separation", 0)
	ThemeConstants.apply_inter_font(ui["input_box"])
	ui["input_container"].add_child(ui["input_box"])

	ui["send_button"] = Button.new()
	ui["send_button"].icon = parent_control.get_theme_icon("ArrowUp", "EditorIcons")
	ui["send_button"].custom_minimum_size = Vector2(button_size, button_size)
	ui["send_button"].size = Vector2(button_size, button_size)
	ui["send_button"].expand_icon = true
	ui["send_button"].icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui["send_button"].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ui["send_button"].anchor_left = 1.0
	ui["send_button"].anchor_top = 1.0
	ui["send_button"].anchor_right = 1.0
	ui["send_button"].anchor_bottom = 1.0
	ui["send_button"].offset_left = -button_margin
	ui["send_button"].offset_top = -button_margin
	ui["send_button"].offset_right = -12
	ui["send_button"].offset_bottom = -12
	ui["send_button"].grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui["send_button"].grow_vertical = Control.GROW_DIRECTION_BEGIN

	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	button_style.corner_radius_top_left = 12
	button_style.corner_radius_top_right = 12
	button_style.corner_radius_bottom_left = 12
	button_style.corner_radius_bottom_right = 12
	button_style.content_margin_left = 4
	button_style.content_margin_right = 4
	button_style.content_margin_top = 4
	button_style.content_margin_bottom = 4
	button_style.anti_aliasing = true
	button_style.anti_aliasing_size = 1.0
	ui["send_button"].add_theme_stylebox_override("normal", button_style)
	ui["send_button"].add_theme_stylebox_override("hover", button_style)
	ui["send_button"].add_theme_stylebox_override("pressed", button_style)
	ui["send_button"].add_theme_color_override("icon_normal_color", Color(0.0, 0.0, 0.0, 1.0))
	ui["send_button"].add_theme_color_override("icon_hover_color", Color(0.0, 0.0, 0.0, 1.0))
	ui["send_button"].add_theme_color_override("icon_pressed_color", Color(0.0, 0.0, 0.0, 1.0))
	var icon_size = 48 if is_macos else 24  # Smaller icon to match smaller button
	ui["send_button"].add_theme_constant_override("icon_max_width", icon_size)

	ui["input_container"].add_child(ui["send_button"])

	ui["slash_commands_menu"] = SlashCommandsMenu.new()
	ui["input_container"].add_child(ui["slash_commands_menu"])

	# Connection status dot - positioned to the left of slash commands button
	var editor_scale = EditorInterface.get_editor_scale()
	var dot_size = int(7 * editor_scale)
	var dot_container_size = int(32 * editor_scale)

	var dot_container = CenterContainer.new()
	dot_container.custom_minimum_size = Vector2(dot_container_size, dot_container_size)
	dot_container.anchor_left = 1.0
	dot_container.anchor_top = 1.0
	dot_container.anchor_right = 1.0
	dot_container.anchor_bottom = 1.0
	dot_container.offset_left = -(button_margin * 2) - dot_container_size
	dot_container.offset_top = -button_margin
	dot_container.offset_right = -(button_margin * 2)
	dot_container.offset_bottom = -12
	dot_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dot_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dot_container.tooltip_text = "Connection status"
	dot_container.mouse_filter = Control.MOUSE_FILTER_STOP
	ui["input_container"].add_child(dot_container)

	ui["connection_status_dot"] = Panel.new()
	ui["connection_status_dot"].custom_minimum_size = Vector2(dot_size, dot_size)
	ui["connection_status_dot"].mouse_filter = Control.MOUSE_FILTER_PASS
	var dot_style = StyleBoxFlat.new()
	dot_style.bg_color = Color(0.5, 0.5, 0.5, 1.0)
	dot_style.set_corner_radius_all(int(dot_size / 2.0))
	ui["connection_status_dot"].add_theme_stylebox_override("panel", dot_style)
	dot_container.add_child(ui["connection_status_dot"])

	ui["attachment_menu"] = AttachmentMenu.new()
	ui["input_container"].add_child(ui["attachment_menu"])

	ui["mode_dropdown"] = _create_mode_dropdown_button()
	ui["input_container"].add_child(ui["mode_dropdown"])

	ui["error_counter_button"] = ErrorCounterButton.new()
	ui["input_container"].add_child(ui["error_counter_button"])

	return ui


static func _create_empty_state(message_container: VBoxContainer, parent_control: Control) -> Dictionary:
	var nodes = {}

	nodes["empty_state_center"] = MarginContainer.new()
	nodes["empty_state_center"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nodes["empty_state_center"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	nodes["empty_state_center"].add_theme_constant_override("margin_left", int(ThemeConstants.spacing(48)))
	nodes["empty_state_center"].add_theme_constant_override("margin_right", int(ThemeConstants.spacing(48)))

	nodes["empty_state_container"] = VBoxContainer.new()
	nodes["empty_state_container"].add_theme_constant_override("separation", int(ThemeConstants.spacing(16)))
	nodes["empty_state_container"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nodes["empty_state_container"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	nodes["empty_state_container"].alignment = BoxContainer.ALIGNMENT_CENTER

	nodes["typewriter_label"] = Label.new()
	nodes["typewriter_label"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nodes["typewriter_label"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nodes["typewriter_label"].add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	nodes["typewriter_label"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ThemeConstants.apply_inter_font(nodes["typewriter_label"], ThemeConstants.Typography.FONT_SIZE_HEADER)

	nodes["empty_state_container"].add_child(nodes["typewriter_label"])

	nodes["typewriter_timer"] = Timer.new()
	nodes["typewriter_timer"].one_shot = false
	nodes["typewriter_timer"].wait_time = AnimationConstants.CHAR_DELAY
	parent_control.add_child(nodes["typewriter_timer"])

	nodes["empty_state_center"].add_child(nodes["empty_state_container"])
	message_container.add_child(nodes["empty_state_center"])

	return nodes


static func _create_mode_dropdown_button() -> Button:
	var is_macos = OS.get_name() == "macOS"
	var button_height = 60 if is_macos else 32
	var button_width = 200 if is_macos else 100
	var button_margin = 84 if is_macos else 44

	var button = Button.new()
	button.text = "General mode"
	button.tooltip_text = "Select agent mode"
	button.custom_minimum_size = Vector2(button_width, button_height)
	button.size = Vector2(button_width, button_height)
	button.flat = false
	button.toggle_mode = false
	button.action_mode = Button.ACTION_MODE_BUTTON_PRESS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	button.icon = EditorInterface.get_editor_theme().get_icon("GuiOptionArrow", "EditorIcons")
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.expand_icon = false

	button.anchor_left = 0.0
	button.anchor_top = 1.0
	button.anchor_right = 0.0
	button.anchor_bottom = 1.0
	button.offset_left = button_margin
	button.offset_top = -button_margin + 12
	button.offset_right = button_margin + button_width
	button.offset_bottom = -12
	button.grow_horizontal = Control.GROW_DIRECTION_END
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	normal_style.content_margin_left = 12
	normal_style.content_margin_right = 12
	normal_style.content_margin_top = 0
	normal_style.content_margin_bottom = 0
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("pressed", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.2)
	button.add_theme_stylebox_override("hover", hover_style)

	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("icon_normal_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("icon_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("icon_pressed_color", Color(1.0, 1.0, 1.0, 1.0))

	var font_size = 28 if is_macos else 14
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_font_override("font", ThemeDB.fallback_font)

	button.set_meta("popup_menu", null)

	return button


static func show_mode_dropdown_popup(dropdown_button: Button) -> void:
	if dropdown_button.has_meta("popup_menu"):
		var old_popup = dropdown_button.get_meta("popup_menu")
		if old_popup:
			old_popup.queue_free()

	var popup = PopupMenuFactory.create_popup(dropdown_button)
	var container = PopupMenuFactory.get_content_container(popup)

	var general_icon = EditorInterface.get_editor_theme().get_icon("AnimationPlayer", "EditorIcons")
	var collision_icon = EditorInterface.get_editor_theme().get_icon("CollisionShape3D", "EditorIcons")
	var character_icon = EditorInterface.get_editor_theme().get_icon("CharacterBody3D", "EditorIcons")

	var items = [
		{"id": 0, "icon": general_icon, "title": "General mode", "subtitle": "Default agent behaviour"},
		{"id": 1, "icon": collision_icon, "title": "Prototype mode", "subtitle": "Mechanics over assets"},
		{"id": 2, "icon": character_icon, "title": "Generate World & Assets", "subtitle": "Generate immersive 3D worlds and assets"}
	]

	for item_data in items:
		var item = PopupMenuFactory.add_rich_item(container, item_data.title, item_data.subtitle, item_data.id, item_data.icon)
		PopupMenuFactory.connect_item_click(item, popup, func(id: int):
			dropdown_button.set_meta("last_selected_id", id)
		)

	dropdown_button.set_meta("popup_menu", popup)
	PopupMenuFactory.show_above_button(popup, dropdown_button)


static func _create_mode_button(text: String, mode_id: String, tooltip: String) -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, int(ThemeConstants.spacing(40)))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.set_meta("mode_id", mode_id)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Center align text and icon
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Add icon based on mode
	if mode_id == "prototype-games":
		button.icon = EditorInterface.get_editor_theme().get_icon("CollisionShape3D", "EditorIcons")
	elif mode_id == "generate-3d-world":
		button.icon = EditorInterface.get_editor_theme().get_icon("CharacterBody3D", "EditorIcons")

	button.expand_icon = false

	# Set icon color to blue accent
	var icon_color = Color(0.24, 0.72, 1.0, 1.0)  # Blue accent color
	button.add_theme_color_override("icon_normal_color", icon_color)
	button.add_theme_color_override("icon_hover_color", icon_color)
	button.add_theme_color_override("icon_pressed_color", icon_color)
	button.add_theme_color_override("icon_focus_color", icon_color)

	ThemeConstants.apply_inter_font(button, ThemeConstants.Typography.FONT_SIZE_SMALL)
	_apply_mode_button_style(button, false)

	return button


static func _apply_mode_button_style(button: Button, is_selected: bool) -> void:
	var style = StyleBoxFlat.new()

	if is_selected:
		style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		style.border_color = Color(0.24, 0.72, 1.0, 1.0)
		style.shadow_color = Color(0.24, 0.72, 1.0, 0.6)
		style.shadow_size = 16
		style.shadow_offset = Vector2(0, 0)
	else:
		style.bg_color = Color(0.2, 0.2, 0.2, 0.4)
		style.border_color = Color(0.5, 0.5, 0.5, 0.5)
		style.shadow_color = Color(0, 0, 0, 0.2)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 1)

	style.set_border_width_all(int(ThemeConstants.spacing(2)))
	style.set_corner_radius_all(int(ThemeConstants.spacing(16)))
	style.content_margin_left = int(ThemeConstants.spacing(6))
	style.content_margin_right = int(ThemeConstants.spacing(24))
	style.content_margin_top = int(ThemeConstants.spacing(8))
	style.content_margin_bottom = int(ThemeConstants.spacing(8))

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("focus", style.duplicate())

	if is_selected:
		button.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
		button.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.0, 0.0, 0.0, 1.0))
		button.add_theme_color_override("font_focus_color", Color(0.0, 0.0, 0.0, 1.0))
	else:
		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
		button.add_theme_color_override("font_focus_color", Color(0.9, 0.9, 0.9, 1.0))
