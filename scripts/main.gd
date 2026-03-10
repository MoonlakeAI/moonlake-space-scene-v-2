extends Node2D

## Main scene controller
## Wires up the preview spaceship launch animation to the spaceship traffic

@onready var spaceship_traffic: SpaceshipTraffic = $SpaceshipTraffic
@onready var preview_spaceship: Node2D = $PreviewLayer/PreviewSpaceship

func _ready() -> void:
	# Connect preview spaceship launch_completed to traffic manager
	# The preview ship animates out, then this signal fires to spawn in traffic
	if preview_spaceship and preview_spaceship.has_signal("launch_completed"):
		preview_spaceship.launch_completed.connect(_on_ship_launched)
		print("[Main] Connected to PreviewSpaceship.launch_completed")
	else:
		push_warning("[Main] PreviewSpaceship not found or missing launch_completed signal")


func _on_ship_launched(ship_name: String, ship_role: String, texture: Texture2D) -> void:
	if spaceship_traffic:
		spaceship_traffic.spawn_player_ship(ship_name, ship_role, texture)
