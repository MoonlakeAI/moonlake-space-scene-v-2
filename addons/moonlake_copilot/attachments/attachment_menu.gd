@tool
extends Button

const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const PopupMenuFactory = preload("res://addons/moonlake_copilot/ui/popup_menu_factory.gd")

signal image_attach_requested
signal editor_output_attach_requested
signal editor_screenshot_attach_requested

var popup_menu: PopupMenu

enum MenuItem {
	IMAGE = 0,
	EDITOR_OUTPUT = 1,
	EDITOR_SCREENSHOT = 2
}

func _ready() -> void:
	# Platform-specific sizing: macOS Retina needs 2x size (double all dimensions)
	var is_macos = OS.get_name() == "macOS"
	var button_size = 60 if is_macos else 32  # Smaller to match send button
	var button_margin = button_size + 12

	# Setup button appearance - match send button exactly (NO TEXT)
	custom_minimum_size = Vector2(button_size, button_size)
	size = Vector2(button_size, button_size)
	flat = false
	toggle_mode = false
	action_mode = Button.ACTION_MODE_BUTTON_PRESS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 12
	offset_top = -button_margin
	offset_right = button_margin
	offset_bottom = -12
	grow_horizontal = Control.GROW_DIRECTION_END
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

	var plus_label = Label.new()
	plus_label.text = "+"
	plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # White text

	# Font size for "+" symbol - platform-specific (larger for macOS Retina visibility)
	var font_size = 48 if is_macos else 24  # Smaller to match smaller button
	plus_label.add_theme_font_size_override("font_size", font_size)

	plus_label.add_theme_font_override("font", ThemeDB.fallback_font)
	plus_label.add_theme_constant_override("line_spacing", -10)

	plus_label.anchor_left = 0.0
	plus_label.anchor_top = 0.0
	plus_label.anchor_right = 1.0
	plus_label.anchor_bottom = 1.0
	# Platform-specific vertical offset: shift up to center properly
	plus_label.offset_top = -12 if is_macos else -7
	plus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(plus_label)

	pressed.connect(_on_button_pressed)
	tooltip_text = "Attach image or editor content"


func _on_button_pressed() -> void:
	if popup_menu:
		popup_menu.queue_free()

	popup_menu = PopupMenu.new()
	get_tree().root.add_child(popup_menu)
	PopupMenuFactory.style_popup_menu(popup_menu)

	popup_menu.add_item("Image", MenuItem.IMAGE)
	popup_menu.add_item("Editor Output", MenuItem.EDITOR_OUTPUT)
	popup_menu.add_item("Editor Screenshot", MenuItem.EDITOR_SCREENSHOT)

	popup_menu.id_pressed.connect(_on_menu_item_selected)

	var button_rect = get_screen_position()
	popup_menu.position = Vector2i(int(button_rect.x), int(button_rect.y - popup_menu.get_contents_minimum_size().y - 8))
	popup_menu.popup()


func _on_menu_item_selected(id: int) -> void:
	match id:
		MenuItem.IMAGE:
			image_attach_requested.emit()
		MenuItem.EDITOR_OUTPUT:
			editor_output_attach_requested.emit()
		MenuItem.EDITOR_SCREENSHOT:
			editor_screenshot_attach_requested.emit()
