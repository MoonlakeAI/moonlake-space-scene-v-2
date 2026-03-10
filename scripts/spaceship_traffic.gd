class_name SpaceshipTraffic
extends CanvasLayer

## Manages spaceship traffic with layered parallax effect
## Lane 1 = closest (fastest, largest), Lane 3 = farthest (slowest, smallest)

@export var spaceship_scene: PackedScene
@export var spaceship_textures: Array[Texture2D] = []  ## Array of spaceship textures to randomly choose from
@export var spaceship_scale: float = 0.4  ## Scale factor for spaceship sprites (adjust to fit scene)
@export var min_ships: int = 12
@export var max_ships: int = 18
@export var debug_show_layers: bool = false  ## Enable to show colored lane regions

# Debug colors for each lane (Lane 1 = closest, Lane 3 = farthest)
var debug_colors: Array[Color] = [
	Color(0.0, 0.5, 1.0, 0.25),  # Lane 1 - Blue (closest)
	Color(1.0, 1.0, 0.0, 0.25),  # Lane 2 - Yellow (mid)
	Color(1.0, 0.0, 0.0, 0.25),  # Lane 3 - Red (farthest)
]
var debug_rects: Array[ColorRect] = []

# Spawn/despawn offset - how far off-screen ships spawn/despawn
var spawn_offset: float = 200.0
var despawn_offset: float = 200.0

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

# Lane configuration with rows (Lane 1 = closest, Lane 3 = farthest)
# rows: array of y_position_ratios for each row in this lane
# variance: random Y offset in pixels for ships in this lane
var lanes: Array = [
	{
		"depth": 1.0, 
		"speed": 80.0,
		"rows": [0.65],  # Lane 1 - Closest (blue) - bottom of screen
		"variance": 0.0
	},
	{
		"depth": 0.5, 
		"speed": 45.0,
		"rows": [0.38, 0.45],  # Lane 2 - Mid (yellow)
		"variance": 0.0
	},
	{
		"depth": 0.3, 
		"speed": 20.0,
		"rows": [0.12, 0.18, 0.24, 0.30],  # Lane 3 - Farthest (red) - more rows for density
		"variance": 0.0
	},
]

var viewport_size: Vector2

func _ready() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	spawn_initial_ships()
	if debug_show_layers:
		_create_debug_layer_visuals()

func _create_debug_layer_visuals() -> void:
	"""Create transparent colored rectangles to visualize each lane's row positions"""
	# Clear existing debug rects
	for rect in debug_rects:
		if is_instance_valid(rect):
			rect.queue_free()
	debug_rects.clear()
	
	# Use the same viewport_size that ships use to ensure alignment
	# (Don't fetch fresh - ships were spawned with this size)
	var current_viewport_size = viewport_size
	
	var row_height: float = 40.0  # Height of each row band
	
	for lane_index in range(lanes.size()):
		var lane_config = lanes[lane_index]
		var rows: Array = lane_config["rows"]
		var color = debug_colors[lane_index] if lane_index < debug_colors.size() else Color(1, 1, 1, 0.1)
		
		for row_y_ratio in rows:
			var rect = ColorRect.new()
			var y_pos = current_viewport_size.y * row_y_ratio - row_height / 2.0
			
			# Extend bars well beyond screen edges to ensure full coverage
			rect.position = Vector2(-500, y_pos)
			rect.size = Vector2(current_viewport_size.x + 2000, row_height)
			rect.color = color
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			# Add label to show lane info (Lane 1 = closest)
			var label = Label.new()
			label.text = "Lane %d (d:%.2f, s:%.0f)" % [lane_index + 1, lane_config["depth"], lane_config["speed"]]
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
	set_debug_layers(!debug_show_layers)


func set_debug_layers(enabled: bool) -> void:
	"""Set debug layer visualization on/off"""
	debug_show_layers = enabled
	if debug_show_layers:
		_create_debug_layer_visuals()
	else:
		for rect in debug_rects:
			if is_instance_valid(rect):
				rect.queue_free()
		debug_rects.clear()


func set_spawn_offset(value: float) -> void:
	"""Set how far off-screen ships spawn"""
	spawn_offset = value
	print("[SpaceshipTraffic] Spawn offset set to: %.0f" % spawn_offset)


func set_despawn_offset(value: float) -> void:
	"""Set how far off-screen ships despawn (wrap around)"""
	despawn_offset = value
	# Update all existing ships with the new despawn offset
	for child in get_children():
		if child is Spaceship:
			child.spawn_margin = despawn_offset
	print("[SpaceshipTraffic] Despawn offset set to: %.0f" % despawn_offset)


func set_lane_row_position(lane_index: int, row_index: int, y_ratio: float) -> void:
	"""Set the Y position ratio for a specific row in a lane"""
	if lane_index < 0 or lane_index >= lanes.size():
		push_warning("[SpaceshipTraffic] Invalid lane index: %d" % lane_index)
		return
	
	var rows: Array = lanes[lane_index]["rows"]
	if row_index < 0 or row_index >= rows.size():
		push_warning("[SpaceshipTraffic] Invalid row index: %d for lane %d" % [row_index, lane_index])
		return
	
	lanes[lane_index]["rows"][row_index] = y_ratio
	
	# Refresh debug layer visuals if enabled
	if debug_show_layers:
		_create_debug_layer_visuals()
	
	print("[SpaceshipTraffic] Lane %d Row %d set to: %.2f" % [lane_index + 1, row_index + 1, y_ratio])


func spawn_initial_ships() -> void:
	var ship_count = randi_range(min_ships, max_ships)
	var lane_counts = [0, 0, 0]  # Track ships per lane for debugging
	
	for i in range(ship_count):
		var spawned_lane = spawn_random_ship()
		if spawned_lane >= 0:
			lane_counts[spawned_lane] += 1
	
	print("[SpaceshipTraffic] Spawned %d ships - Lane 1 (Blue): %d, Lane 2 (Yellow): %d, Lane 3 (Red): %d" % [ship_count, lane_counts[0], lane_counts[1], lane_counts[2]])

func spawn_random_ship() -> int:
	"""Spawn a random ship. Returns the lane index (0-2) or -1 on failure."""
	if not spaceship_scene or spaceship_textures.is_empty():
		push_warning("SpaceshipTraffic: Missing spaceship_scene or spaceship_textures")
		return -1
	
	# Randomly select a texture from the array
	var selected_texture = spaceship_textures[randi() % spaceship_textures.size()]
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return -1
	
	# Pick lane with weighted probability (Lane 1 = closest, Lane 3 = farthest)
	# Weights: Lane 1 (closest)=25%, Lane 2 (mid)=35%, Lane 3 (far)=40%
	var rand_val = randf()
	var lane_index: int
	if rand_val < 0.25:
		lane_index = 0  # Lane 1 - Closest
	elif rand_val < 0.60:
		lane_index = 1  # Lane 2 - Mid
	else:
		lane_index = 2  # Lane 3 - Farthest
	
	var lane_config = lanes[lane_index]
	
	# Pick random row within the lane
	var rows: Array = lane_config["rows"]
	var row_y_ratio: float = rows[randi() % rows.size()]
	
	# Pick random ship data
	var data = ship_data[randi() % ship_data.size()]
	
	# Pick random speed behavior
	var speed_behavior = speeds_data[randi() % speeds_data.size()]
	
	# Random direction
	var direction = 1 if randf() > 0.5 else -1
	
	# Calculate Y position from row with lane-specific variance
	var y_pos = viewport_size.y * row_y_ratio
	var lane_variance: float = lane_config.get("variance", 0.0)
	if lane_variance > 0.0:
		y_pos += randf_range(-lane_variance, lane_variance)
	
	# Random X starting position
	var x_pos = randf_range(0, viewport_size.x)
	
	# Calculate final speed with multiplier
	var base_speed = lane_config["speed"] * speed_behavior[0]
	
	# Setup ship with movement parameters
	ship.setup(data[0], data[1], direction, lane_config["depth"], base_speed)
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	
	# Full opacity for all ships
	ship.modulate.a = 1.0
	
	# Track which lane this ship belongs to
	ship.lane_index = lane_index
	
	# Set despawn offset
	ship.spawn_margin = despawn_offset
	
	add_child(ship)
	return lane_index

func spawn_ship_at_lane(lane_index: int, row_index: int, ship_name: String, ship_role: String) -> Spaceship:
	if not spaceship_scene or spaceship_textures.is_empty():
		return null
	
	# Randomly select a texture from the array
	var selected_texture = spaceship_textures[randi() % spaceship_textures.size()]
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	lane_index = clampi(lane_index, 0, lanes.size() - 1)
	var lane_config = lanes[lane_index]
	
	var rows: Array = lane_config["rows"]
	row_index = clampi(row_index, 0, rows.size() - 1)
	var row_y_ratio: float = rows[row_index]
	
	# Pick random speed behavior
	var speed_behavior = speeds_data[randi() % speeds_data.size()]
	var base_speed = lane_config["speed"] * speed_behavior[0]
	
	var direction = 1 if randf() > 0.5 else -1
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float = -spawn_offset if direction > 0 else viewport_size.x + spawn_offset
	
	ship.setup(ship_name, ship_role, direction, lane_config["depth"], base_speed)
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	ship.modulate.a = 1.0
	ship.lane_index = lane_index
	ship.spawn_margin = despawn_offset
	
	add_child(ship)
	return ship

func spawn_player_ship(ship_name: String, ship_role: String, texture: Texture2D = null) -> Spaceship:
	"""Spawn a ship from player input - always spawns in Lane 1 (closest)"""
	if not spaceship_scene:
		return null
	
	# Use provided texture, or fall back to random from array
	var selected_texture: Texture2D = texture
	if selected_texture == null and not spaceship_textures.is_empty():
		selected_texture = spaceship_textures[randi() % spaceship_textures.size()]
	
	if selected_texture == null:
		push_warning("SpaceshipTraffic: No texture available for player ship")
		return null
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	# Use Lane 1 (index 0) - the closest lane for player ships
	var lane_config = lanes[0]
	var rows: Array = lane_config["rows"]
	var row_y_ratio: float = rows[rows.size() - 1]  # Use the bottom row of Lane 1
	
	# Always enter from the left, moving right
	var direction = 1
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float = -spawn_offset
	
	ship.setup(ship_name, ship_role, direction, lane_config["depth"], lane_config["speed"])
	ship.set_movement_behavior(0.0, 0.0, 0.0)  # Steady movement for player ships
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	ship.modulate.a = 1.0  # Full opacity for player ships
	ship.lane_index = 0  # Player ships always in Lane 1 (closest)
	ship.spawn_margin = despawn_offset
	
	add_child(ship)
	return ship
