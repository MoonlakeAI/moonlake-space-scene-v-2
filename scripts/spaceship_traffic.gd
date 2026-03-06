class_name SpaceshipTraffic
extends CanvasLayer

## Manages spaceship traffic with layered parallax effect
## Each layer has rows - farther layers have more rows, closer layers have fewer

@export var spaceship_scene: PackedScene
@export var spaceship_texture: Texture2D
@export var min_ships: int = 8
@export var max_ships: int = 14

# Ship data: [name, role]
var ship_data: Array = [
	["Vanguard", "Battleship"],
	["Prometheus", "Carrier"],
	["Omega Freighter", "Cargo"],
	["Terra Resources", "Mining"],
	["Celestial Voyager", "Explorer"],
	["Nova Strike", "Fighter"],
	["Stellar Wind", "Transport"],
	["Horizon", "Scout"],
	["Nebula Runner", "Smuggler"],
	["Titan's Fury", "Dreadnought"],
]

# Layer configuration with rows
# rows: array of y_position_ratios for each row in this layer
var layers: Array = [
	{
		"depth": 0.25, 
		"speed": 15.0,
		"rows": [0.12, 0.22, 0.32]  # 3 rows - farthest layer
	},
	{
		"depth": 0.45, 
		"speed": 30.0,
		"rows": [0.18, 0.30, 0.42]  # 3 rows
	},
	{
		"depth": 0.65, 
		"speed": 50.0,
		"rows": [0.35, 0.50]  # 2 rows - middle layer
	},
	{
		"depth": 0.85, 
		"speed": 70.0,
		"rows": [0.45, 0.60]  # 2 rows
	},
	{
		"depth": 1.0, 
		"speed": 90.0,
		"rows": [0.55]  # 1 row - closest layer
	},
]

var viewport_size: Vector2

func _ready() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	spawn_initial_ships()

func spawn_initial_ships() -> void:
	var ship_count = randi_range(min_ships, max_ships)
	
	for i in range(ship_count):
		spawn_random_ship()

func spawn_random_ship() -> void:
	if not spaceship_scene or not spaceship_texture:
		push_warning("SpaceshipTraffic: Missing spaceship_scene or spaceship_texture")
		return
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return
	
	# Pick random layer
	var layer_index = randi() % layers.size()
	var layer_config = layers[layer_index]
	
	# Pick random row within the layer
	var rows: Array = layer_config["rows"]
	var row_y_ratio: float = rows[randi() % rows.size()]
	
	# Pick random ship data
	var data = ship_data[randi() % ship_data.size()]
	
	# Random direction
	var direction = 1 if randf() > 0.5 else -1
	
	# Calculate Y position from row with small variance
	var y_pos = viewport_size.y * row_y_ratio
	y_pos += randf_range(-10, 10) * layer_config["depth"]
	
	# Random X starting position
	var x_pos = randf_range(0, viewport_size.x)
	
	# Setup ship
	ship.setup(data[0], data[1], direction, layer_config["depth"], layer_config["speed"])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(spaceship_texture)
	
	# Farther ships more transparent
	ship.modulate.a = 0.5 + (layer_config["depth"] * 0.5)
	
	add_child(ship)

func spawn_ship_at_layer(layer_index: int, row_index: int, ship_name: String, ship_role: String) -> Spaceship:
	if not spaceship_scene or not spaceship_texture:
		return null
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	layer_index = clampi(layer_index, 0, layers.size() - 1)
	var layer_config = layers[layer_index]
	
	var rows: Array = layer_config["rows"]
	row_index = clampi(row_index, 0, rows.size() - 1)
	var row_y_ratio: float = rows[row_index]
	
	var direction = 1 if randf() > 0.5 else -1
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float = -200.0 if direction > 0 else viewport_size.x + 200.0
	
	ship.setup(ship_name, ship_role, direction, layer_config["depth"], layer_config["speed"])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(spaceship_texture)
	ship.modulate.a = 0.5 + (layer_config["depth"] * 0.5)
	
	add_child(ship)
	return ship

func spawn_player_ship(ship_name: String, ship_role: String) -> Spaceship:
	"""Spawn a ship from player input - spawns in the closest layer for visibility"""
	if not spaceship_scene or not spaceship_texture:
		return null
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	# Use the closest layer (last one) for player ships
	var layer_config = layers[layers.size() - 1]
	var rows: Array = layer_config["rows"]
	var row_y_ratio: float = rows[0]
	
	# Always enter from the left, moving right
	var direction = 1
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float = -300.0
	
	ship.setup(ship_name, ship_role, direction, layer_config["depth"], layer_config["speed"])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(spaceship_texture)
	ship.modulate.a = 1.0  # Full opacity for player ships
	
	add_child(ship)
	return ship
