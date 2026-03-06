extends PanelContainer

## Console Panel for crew deployment
## Handles input and launches new ships

signal ship_launched(ship_name: String, ship_role: String)

@onready var name_input: LineEdit = $MarginContainer/VBoxContainer/InputsRow/NameColumn/NameInput
@onready var role_input: LineEdit = $MarginContainer/VBoxContainer/InputsRow/RoleColumn/RoleInput
@onready var launch_button: Button = $MarginContainer/VBoxContainer/LaunchButton

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
	
	# Emit signal for traffic manager to handle
	ship_launched.emit(ship_name, ship_role)
	
	# Clear inputs
	name_input.clear()
	role_input.clear()
	
	# Flash effect on button
	_play_launch_effect()

func _play_launch_effect() -> void:
	var tween = create_tween()
	launch_button.modulate = Color(0.5, 1.0, 1.0, 1.0)
	tween.tween_property(launch_button, "modulate", Color.WHITE, 0.3)
