extends Node2D

## Main scene controller
## Wires up the console panel to the spaceship traffic

@onready var spaceship_traffic: SpaceshipTraffic = $SpaceshipTraffic
@onready var console_panel: PanelContainer = $ConsoleUI/ConsolePanel

func _ready() -> void:
	# Connect console panel launch signal to traffic manager
	if console_panel.has_signal("ship_launched"):
		console_panel.ship_launched.connect(_on_ship_launched)

func _on_ship_launched(ship_name: String, ship_role: String, texture: Texture2D) -> void:
	if spaceship_traffic:
		spaceship_traffic.spawn_player_ship(ship_name, ship_role, texture)
