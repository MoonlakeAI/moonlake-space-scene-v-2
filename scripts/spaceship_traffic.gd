class_name SpaceshipTraffic
extends CanvasLayer

## Manages spaceship traffic with layered parallax effect
## Each layer has rows - farther layers have more rows, closer layers have fewer

@export var spaceship_scene: PackedScene
@export var spaceship_texture: Texture2D
@export var min_ships: int = 8
@export var max_ships: int = 14
@export var debug_show_layers: bool = false  ## Enable to show colored layer regions

# Debug colors for each layer (RGBA with low alpha for transparency)
var debug_colors: Array[Color] = [
	Color(1.0, 0.0, 0.0, 0),  # Layer 0 - Red (far)
	Color(1.0, 1.0, 0.0, 0),  # Layer 1 - Yellow (mid)
	Color(0.0, 0.5, 1.0, 0),  # Layer 2 - Blue (close)
]
var debug_rects: Array[ColorRect] = []

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

# Speed behavior data: [speed_multiplier, drift_amplitude, drift_frequency, acceleration_factor]
# speed_multiplier: multiplies the base layer speed (0.5 = half speed, 2.0 = double speed)
# drift_amplitude: vertical sine wave drift amount in pixels (0 = no drift)
# drift_frequency: how fast the drift oscillates (higher = faster wobble)
# acceleration_factor: 0 = constant speed, >0 = accelerates, <0 = decelerates over time
var speeds_data: Array = [
	[0.6, 0.0, 0.0, 0.0],      # Slow steady - cargo ships
	[0.8, 0.0, 0.0, 0.0],      # Slow steady
	[1.0, 0.0, 0.0, 0.0],      # Normal steady
	[1.0, 0.0, 0.0, 0.0],      # Normal steady
	[1.2, 0.0, 0.0, 0.05],     # Slightly fast, accelerating
	[1.3, 0.0, 0.0, 0.0],      # Fast steady
	[1.5, 0.0, 0.0, 0.0],      # Fast steady - fighters
	[0.7, 0.0, 0.0, 0.0],      # Slow steady - freighters
	[1.1, 0.0, 0.0, -0.02],    # Medium, decelerating
	[1.4, 0.0, 0.0, 0.08],     # Fast accelerating - scouts
]

# Layer configuration with rows
# rows: array of y_position_ratios for each row in this layer
var layers: Array = [
	{
		"depth": 0.3, 
		"speed": 20.0,
		"rows": [0.12, 0.18, 0.24, 0.30]  # Far layer - more rows for higher density
	},
	{
		"depth": 0.6, 
		"speed": 45.0,
		"rows": [0.40, 0.45]  # Mid layer - moved up
	},
	{
		"depth": 1.0, 
		"speed": 80.0,
		"rows": [0.40,0.65]  # Close layer - moved down
	},
]

var viewport_size: Vector2

func _ready() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	spawn_initial_ships()
	if debug_show_layers:
		_create_debug_layer_visuals()

func _create_debug_layer_visuals() -> void:
	"""Create transparent colored rectangles to visualize each layer's row positions"""
	# Clear existing debug rects
	for rect in debug_rects:
		if is_instance_valid(rect):
			rect.queue_free()
	debug_rects.clear()
	
	var row_height: float = 60.0  # Height of each row band
	
	for layer_index in range(layers.size()):
		var layer_config = layers[layer_index]
		var rows: Array = layer_config["rows"]
		var color = debug_colors[layer_index] if layer_index < debug_colors.size() else Color(1, 1, 1, 0.1)
		
		for row_y_ratio in rows:
			var rect = ColorRect.new()
			var y_pos = viewport_size.y * row_y_ratio - row_height / 2.0
			
			rect.position = Vector2(0, y_pos)
			rect.size = Vector2(viewport_size.x, row_height)
			rect.color = color
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			# Add label to show layer info
			var label = Label.new()
			label.text = "L%d (d:%.2f, s:%.0f)" % [layer_index, layer_config["depth"], layer_config["speed"]]
			label.position = Vector2(10, 5)
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
			rect.add_child(label)
			
			add_child(rect)
			# Move to back so ships render on top
			move_child(rect, 0)
			debug_rects.append(rect)

func toggle_debug_layers() -> void:
	"""Toggle debug layer visualization on/off"""
	debug_show_layers = !debug_show_layers
	if debug_show_layers:
		_create_debug_layer_visuals()
	else:
		for rect in debug_rects:
			if is_instance_valid(rect):
				rect.queue_free()
		debug_rects.clear()

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
	
	# Pick layer with weighted probability - far layer gets more ships
	# Weights: Far=50%, Mid=35%, Close=15%
	var rand_val = randf()
	var layer_index: int
	if rand_val < 0.50:
		layer_index = 0  # Far
	elif rand_val < 0.85:
		layer_index = 1  # Mid
	else:
		layer_index = 2  # Close
	
	var layer_config = layers[layer_index]
	
	# Pick random row within the layer
	var rows: Array = layer_config["rows"]
	var row_y_ratio: float = rows[randi() % rows.size()]
	
	# Pick random ship data
	var data = ship_data[randi() % ship_data.size()]
	
	# Pick random speed behavior
	var speed_behavior = speeds_data[randi() % speeds_data.size()]
	
	# Random direction
	var direction = 1 if randf() > 0.5 else -1
	
	# Calculate Y position from row with small variance
	var y_pos = viewport_size.y * row_y_ratio
	y_pos += randf_range(-10, 10) * layer_config["depth"]
	
	# Random X starting position
	var x_pos = randf_range(0, viewport_size.x)
	
	# Calculate final speed with multiplier
	var base_speed = layer_config["speed"] * speed_behavior[0]
	
	# Setup ship with movement parameters
	ship.setup(data[0], data[1], direction, layer_config["depth"], base_speed)
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
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
	
	# Pick random speed behavior
	var speed_behavior = speeds_data[randi() % speeds_data.size()]
	var base_speed = layer_config["speed"] * speed_behavior[0]
	
	var direction = 1 if randf() > 0.5 else -1
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float = -200.0 if direction > 0 else viewport_size.x + 200.0
	
	ship.setup(ship_name, ship_role, direction, layer_config["depth"], base_speed)
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
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
	ship.set_movement_behavior(0.0, 0.0, 0.0)  # Steady movement for player ships
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(spaceship_texture)
	ship.modulate.a = 1.0  # Full opacity for player ships
	
	add_child(ship)
	return ship
