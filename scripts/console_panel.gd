extends PanelContainer

## Console Panel for crew deployment
## Handles input and triggers preview ship launch animation

@onready var name_input: LineEdit = $"../InputsPanel/MarginContainer/InputsContainer/NameColumn/NameInput"
@onready var role_input: OptionButton = $"../InputsPanel/MarginContainer/InputsContainer/RoleColumn/RoleInput"

# Predefined roles for crew members
const ROLES: Array[String] = ["Design", "Engineering", "Art", "Production"]
@onready var launch_button: Button = $ButtonContainer/LaunchButton
@onready var preview_button: Button = $ButtonContainer/PreviewButton

# Reference to spaceship generator panel (sibling node)
@onready var generator_panel = $"../GeneratorPanel"

# Reference to preview spaceship (found at runtime)
var _preview_spaceship: Node2D = null

func _ready() -> void:
	launch_button.pressed.connect(_on_launch_pressed)
	
	# Connect preview button hover signals
	preview_button.mouse_entered.connect(_on_preview_hover_start)
	preview_button.mouse_exited.connect(_on_preview_hover_end)
	
	# Allow Enter key to launch from name input
	name_input.text_submitted.connect(_on_text_submitted)
	
	# Populate role dropdown with predefined roles
	_populate_roles()
	
	# Find the preview spaceship after scene is ready
	await get_tree().process_frame
	_find_preview_spaceship()


func _populate_roles() -> void:
	role_input.clear()
	for role in ROLES:
		role_input.add_item(role)
	role_input.selected = 0  # Select first role by default
	
	# Style the popup menu to match console theme
	_style_popup_menu()


func _style_popup_menu() -> void:
	var popup := role_input.get_popup()
	if not popup:
		return
	
	# Create panel style for popup background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0.03, 0.06, 0.95)
	panel_style.border_color = Color(0, 0.55, 0.7, 0.85)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel_style.shadow_color = Color(0, 0.45, 0.55, 0.4)
	panel_style.shadow_size = 6
	popup.add_theme_stylebox_override("panel", panel_style)
	
	# Create hover style for menu items
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0, 0.08, 0.12, 0.9)
	hover_style.border_color = Color(0, 0.6, 0.75, 0.8)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(2)
	popup.add_theme_stylebox_override("hover", hover_style)
	
	# Font colors
	popup.add_theme_color_override("font_color", Color(0.5, 0.75, 0.8, 1))
	popup.add_theme_color_override("font_hover_color", Color(0.7, 0.95, 1, 1))
	popup.add_theme_color_override("font_separator_color", Color(0.3, 0.5, 0.55, 0.7))
	
	# Connect to reposition popup to open upward
	if not popup.about_to_popup.is_connected(_on_popup_about_to_show):
		popup.about_to_popup.connect(_on_popup_about_to_show)


func _on_popup_about_to_show() -> void:
	var popup := role_input.get_popup()
	if not popup:
		return
	
	# Wait for popup to calculate its size
	await get_tree().process_frame
	
	# Get the button's global position and size
	var button_rect := role_input.get_global_rect()
	var popup_size := popup.size
	
	# Position popup above the button, aligned to left edge
	var new_pos := Vector2(
		button_rect.position.x,
		button_rect.position.y - popup_size.y
	)
	popup.position = new_pos


func _find_preview_spaceship() -> void:
	# Find PreviewSpaceship in the scene tree
	var preview_layer := get_tree().root.find_child("PreviewLayer", true, false)
	if preview_layer:
		_preview_spaceship = preview_layer.get_node_or_null("PreviewSpaceship")
		if _preview_spaceship:
			print("[ConsolePanel] Found PreviewSpaceship")
		else:
			push_warning("[ConsolePanel] PreviewSpaceship not found in PreviewLayer")
	else:
		push_warning("[ConsolePanel] PreviewLayer not found")


func _on_launch_pressed() -> void:
	launch_ship()


func _on_text_submitted(_text: String) -> void:
	launch_ship()


func launch_ship() -> void:
	# Check if preview spaceship is ready
	if _preview_spaceship and _preview_spaceship.has_method("is_ready"):
		if not _preview_spaceship.is_ready():
			print("[ConsolePanel] Ship not ready - animation in progress")
			return
	
	var ship_name = name_input.text.strip_edges()
	var ship_role = role_input.get_item_text(role_input.selected)
	
	# Default values if empty
	if ship_name.is_empty():
		ship_name = "Unknown Vessel"
	if ship_role.is_empty():
		ship_role = ROLES[0]  # Default to first role
	
	# Get the generated texture from spaceship generator
	var texture: Texture2D = null
	if generator_panel and generator_panel.has_method("get_generated_texture"):
		texture = generator_panel.get_generated_texture()
	
	# Trigger the preview ship's launch animation
	if _preview_spaceship and _preview_spaceship.has_method("launch"):
		var launched: bool = _preview_spaceship.launch(ship_name, ship_role, texture)
		if launched:
			# Clear inputs - reset name, keep role selection
			name_input.clear()
			role_input.selected = 0
			
			# Flash effect on button
			_play_launch_effect()
		else:
			print("[ConsolePanel] Launch failed - ship may be busy")
	else:
		push_warning("[ConsolePanel] PreviewSpaceship not available for launch")


func _play_launch_effect() -> void:
	var tween = create_tween()
	launch_button.modulate = Color(0.5, 1.0, 1.0, 1.0)
	tween.tween_property(launch_button, "modulate", Color.WHITE, 0.3)


func _on_preview_hover_start() -> void:
	# Reduce holographic effect to reveal the original ship
	if _preview_spaceship and _preview_spaceship.has_method("set_preview_mode"):
		_preview_spaceship.set_preview_mode(true)


func _on_preview_hover_end() -> void:
	# Restore holographic effect
	if _preview_spaceship and _preview_spaceship.has_method("set_preview_mode"):
		_preview_spaceship.set_preview_mode(false)
