@tool
extends Button

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const PopupMenuFactory = preload("res://addons/moonlake_copilot/ui/popup_menu_factory.gd")

signal slash_command_selected(command: String)

var popup_menu: PopupMenu

# Slash commands with descriptions (synced with godot_worker/slash_commands.py)
const SLASH_COMMANDS = [
	{"command": "/clear", "description": "Clear local chat history"},
	{"command": "/credits", "description": "Show credit usage"},
	{"command": "/jobs", "description": "List active jobs"},
	{"command": "/publish", "display": "/publish cancel|view", "description": "Publish project"},
	{"command": "/unpublish", "description": "Unpublish project"},
	{"command": "/yolo", "display": "/yolo on|off", "description": "Auto-accept bash commands"},
	{"command": "/test diagnostics", "description": "Run diagnostics"},
]

func _ready() -> void:
	# Platform-specific sizing: macOS Retina needs 2x size (match send button)
	var is_macos = OS.get_name() == "macOS"
	var button_size = 60 if is_macos else 32
	var button_margin = button_size + 12

	# Setup button appearance - match send button exactly
	custom_minimum_size = Vector2(button_size, button_size)
	size = Vector2(button_size, button_size)
	flat = false
	toggle_mode = false
	action_mode = Button.ACTION_MODE_BUTTON_PRESS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Position to the left of send button
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(button_margin * 2) - 8  # Two buttons + gap
	offset_top = -button_margin
	offset_right = -(button_margin + 8)
	offset_bottom = -12
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Normal style - transparent background
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	normal_style.content_margin_left = 4
	normal_style.content_margin_right = 4
	normal_style.content_margin_top = 0
	normal_style.content_margin_bottom = 0
	normal_style.anti_aliasing = true
	normal_style.anti_aliasing_size = 2.0
	add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("pressed", normal_style)

	# Hover style - white 20% background
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.2)
	add_theme_stylebox_override("hover", hover_style)

	# Add slash icon (white)
	var slash_label = Label.new()
	slash_label.text = "/"
	slash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slash_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # White icon

	# Font size for "/" symbol - platform-specific
	var font_size = 48 if is_macos else 24
	slash_label.add_theme_font_size_override("font_size", font_size)

	slash_label.add_theme_font_override("font", ThemeDB.fallback_font)
	slash_label.add_theme_constant_override("outline_size", 0)  # No outline for white text

	slash_label.anchor_left = 0.0
	slash_label.anchor_top = 0.0
	slash_label.anchor_right = 1.0
	slash_label.anchor_bottom = 1.0
	# Platform-specific vertical offset: shift to center properly
	slash_label.offset_top = -12 if is_macos else -7
	slash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(slash_label)

	pressed.connect(_on_button_pressed)
	tooltip_text = "Slash commands"


func _on_button_pressed() -> void:
	if popup_menu:
		popup_menu.queue_free()

	popup_menu = PopupMenu.new()
	get_tree().root.add_child(popup_menu)
	PopupMenuFactory.style_popup_menu(popup_menu)

	for i in range(SLASH_COMMANDS.size()):
		var cmd = SLASH_COMMANDS[i]
		var display_cmd = cmd.get("display", cmd["command"])
		var label = display_cmd + " - " + cmd["description"]
		popup_menu.add_item(label, i)

	popup_menu.id_pressed.connect(_on_menu_item_selected)

	# Show popup first so it calculates its size
	popup_menu.popup()

	# Get the screen the window is on (handles multi-monitor)
	var window = get_window()
	var screen_idx = window.current_screen
	var screen_pos = DisplayServer.screen_get_position(screen_idx)
	var screen_size = DisplayServer.screen_get_size(screen_idx)

	# Position above the button, right-aligned with button's right edge
	var button_pos = get_screen_position()
	var popup_size = popup_menu.size

	var x = int(button_pos.x + size.x - popup_size.x)  # Right-align with button
	var y = int(button_pos.y - popup_size.y - 8)

	# Clamp y to screen bounds
	y = clampi(y, screen_pos.y, screen_pos.y + screen_size.y - popup_size.y)

	popup_menu.position = Vector2i(x, y)


func _on_menu_item_selected(id: int) -> void:
	if id >= 0 and id < SLASH_COMMANDS.size():
		var command = SLASH_COMMANDS[id]["command"]
		slash_command_selected.emit(command)
