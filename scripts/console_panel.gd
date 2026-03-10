extends PanelContainer

## Console Panel for crew deployment
## Handles input and triggers preview ship launch animation

@onready var name_input: LineEdit = $"../InputsPanel/MarginContainer/InputsContainer/NameColumn/NameInput"
@onready var role_input: LineEdit = $"../InputsPanel/MarginContainer/InputsContainer/RoleColumn/RoleInput"
@onready var launch_button: Button = $LaunchButton

# Reference to spaceship generator panel (sibling node)
@onready var generator_panel = $"../GeneratorPanel"

# Reference to preview spaceship (found at runtime)
var _preview_spaceship: Node2D = null

func _ready() -> void:
	launch_button.pressed.connect(_on_launch_pressed)
	
	# Allow Enter key to launch
	name_input.text_submitted.connect(_on_text_submitted)
	role_input.text_submitted.connect(_on_text_submitted)
	
	# Find the preview spaceship after scene is ready
	await get_tree().process_frame
	_find_preview_spaceship()


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
	
	# Trigger the preview ship's launch animation
	if _preview_spaceship and _preview_spaceship.has_method("launch"):
		var launched: bool = _preview_spaceship.launch(ship_name, ship_role, texture)
		if launched:
			# Clear inputs immediately
			name_input.clear()
			role_input.clear()
			
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
