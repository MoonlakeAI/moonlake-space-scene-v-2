extends PanelContainer

## Console Panel for crew deployment
## Handles input and launches new ships

signal ship_launched(ship_name: String, ship_role: String, texture: Texture2D)

@onready var name_input: LineEdit = $"../InputsPanel/MarginContainer/InputsContainer/NameColumn/NameInput"
@onready var role_input: LineEdit = $"../InputsPanel/MarginContainer/InputsContainer/RoleColumn/RoleInput"
@onready var launch_button: Button = $LaunchButton

# Reference to spaceship generator panel (sibling node)
@onready var generator_panel = $"../GeneratorPanel"

func _ready() -> void:
	launch_button.pressed.connect(_on_launch_pressed)
	
	# Allow Enter key to launch
	name_input.text_submitted.connect(_on_text_submitted)
	role_input.text_submitted.connect(_on_text_submitted)

func _on_launch_pressed() -> void:
	launch_ship()

func _on_text_submitted(_text: String) -> void:
	launch_ship()

func launch_ship() -> void:
	var ship_name = name_input.text.strip_edges()
	var ship_role = role_input.text.strip_edges()
	
	# Default values if empty
	if ship_name.is_empty():
		ship_name = "Unknown Vessel"
	if ship_role.is_empty():
		ship_role = "Unassigned"
	
	# Get the generated texture from spaceship generator
	var texture: Texture2D = null
	if generator_panel and generator_panel.has_method("get_generated_texture"):
		texture = generator_panel.get_generated_texture()
	
	# Emit signal for traffic manager to handle
	ship_launched.emit(ship_name, ship_role, texture)
	
	# Clear inputs
	name_input.clear()
	role_input.clear()
	
	# Flash effect on button
	_play_launch_effect()

func _play_launch_effect() -> void:
	var tween = create_tween()
	launch_button.modulate = Color(0.5, 1.0, 1.0, 1.0)
	tween.tween_property(launch_button, "modulate", Color.WHITE, 0.3)
