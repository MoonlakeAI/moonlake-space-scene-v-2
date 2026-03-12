class_name SpaceshipTraffic
extends CanvasLayer

## Manages spaceship traffic with layered parallax effect
## Lane 1 = closest (fastest, largest), Lane 3 = farthest (slowest, smallest)
## Observable and deterministic - all ships tracked in ship_registry

signal ship_spawned(ship_id: int, ship_data: Dictionary)
signal ship_removed(ship_id: int)
signal registry_updated()

@export var spaceship_scene: PackedScene
@export var spaceship_textures: Array[Texture2D] = []  ## Array of spaceship textures to randomly choose from
@export var spaceship_scale: float = 0.4  ## Scale factor for spaceship sprites (adjust to fit scene)
@export var min_ships: int = 12
@export var max_ships: int = 18
@export var debug_show_layers: bool = false  ## Enable to show colored lane regions
@export var ship_min_speed: float = 20.0   ## Minimum speed ships can have
@export var ship_max_speed: float = 200.0  ## Maximum speed ships can have
@export var speed_randomization: float = 0.3  ## How much to randomize speed (0.3 = ±30%)

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
	["Vanguard", "Bot"],
	["Prometheus", "Bot"],
	["Omega", "Bot"],
	["Terra", "Bot"],
	["Voyager", "Bot"],
	["Nova", "Bot"],
	["Stellar", "Bot"],
	["Horizon", "Bot"],
	["Nebula", "Bot"],
	["Titan", "Bot"],
	["Aurora", "Bot"],
	["Zenith", "Bot"],
	["Orion", "Bot"],
	["Echo", "Bot"],
	["Pulse", "Bot"],
	["Apex", "Bot"],
	["Drift", "Bot"],
	["Comet", "Bot"],
	["Flux", "Bot"],
	["Spark", "Bot"],
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

# ============ SHIP REGISTRY (Observable State) ============
# Tracks all active ships with their configuration and state
# Each entry: { id, ship_ref, config_index, lane, row, direction, name, role, texture_index }
var ship_registry: Array[Dictionary] = []
var _next_ship_id: int = 0

# ============ SEQUENTIAL SPAWN SYSTEM ============
# Tracks next spawn position for launched ships
# Cycles: 1.1 -> 2.1 -> 2.2 -> 3.1 -> 3.2 -> 3.3 -> 3.4 -> 1.1...
var _current_spawn_lane: int = 0      # 0-indexed lane
var _current_spawn_row: int = 0       # 0-indexed row within lane
var _current_spawn_direction: int = 1 # 1 = left-to-right, -1 = right-to-left

# ============ DETERMINISTIC SHIP CONFIGURATIONS ============
# Pre-defined ship configurations for deterministic spawning
# Each config: { name, role, lane, row, direction, texture_index, speed_index }
# Set this array before calling spawn_from_config() for full determinism
var ship_configurations: Array[Dictionary] = []

func _ready() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	_load_spaceship_textures_from_folder()
	spawn_initial_ships()
	if debug_show_layers:
		_create_debug_layer_visuals()


func _load_spaceship_textures_from_folder() -> void:
	"""Load all spaceship textures from res://assets/images/spaceships/ folder"""
	var folder_path := "res://assets/images/spaceships/"
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_warning("SpaceshipTraffic: Could not open folder: %s" % folder_path)
		return
	
	spaceship_textures.clear()
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# Only load PNG files (skip .import files)
		if file_name.ends_with(".png"):
			var full_path := folder_path + file_name
			var texture := load(full_path) as Texture2D
			if texture:
				spaceship_textures.append(texture)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	print("[SpaceshipTraffic] Loaded %d spaceship textures from %s" % [spaceship_textures.size(), folder_path])

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


func _randomize_speed(base_speed: float) -> float:
	"""Randomize speed within the configured range, clamped to min/max limits."""
	var variation = base_speed * speed_randomization
	var randomized = base_speed + randf_range(-variation, variation)
	return clampf(randomized, ship_min_speed, ship_max_speed)


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
	var texture_index = randi() % spaceship_textures.size()
	var selected_texture = spaceship_textures[texture_index]
	
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
	var row_index = randi() % rows.size()
	var row_y_ratio: float = rows[row_index]
	
	# Pick random ship data
	var data_index = randi() % ship_data.size()
	var data = ship_data[data_index]
	
	# Pick random speed behavior
	var speed_index = randi() % speeds_data.size()
	var speed_behavior = speeds_data[speed_index]
	
	# Random direction
	var direction = 1 if randf() > 0.5 else -1
	
	# Calculate Y position from row with lane-specific variance
	var y_pos = viewport_size.y * row_y_ratio
	var lane_variance: float = lane_config.get("variance", 0.0)
	if lane_variance > 0.0:
		y_pos += randf_range(-lane_variance, lane_variance)
	
	# Random X starting position
	var x_pos = randf_range(0, viewport_size.x)
	
	# Calculate final speed with multiplier and randomization
	var base_speed = lane_config["speed"] * speed_behavior[0]
	var randomized_speed = _randomize_speed(base_speed)
	
	# Setup ship with movement parameters
	ship.setup(data[0], data[1], direction, lane_config["depth"], randomized_speed)
	ship.min_speed = ship_min_speed
	ship.max_speed = ship_max_speed
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	
	# Full opacity for all ships
	ship.modulate.a = 1.0
	
	# Track which lane this ship belongs to
	ship.lane_index = lane_index
	ship.row_index = row_index
	
	# Set despawn offset
	ship.spawn_margin = despawn_offset
	
	# Connect to journey completion signal
	ship.journey_completed.connect(_on_ship_journey_completed)
	
	add_child(ship)
	
	# Register ship in registry
	var ship_id = _register_ship(ship, lane_index, row_index, direction, 
		data[0], data[1], texture_index, speed_index)
	ship.set_meta("ship_id", ship_id)
	
	return lane_index

func spawn_ship_at_lane(lane_index: int, row_index: int, ship_name: String, ship_role: String) -> Spaceship:
	if not spaceship_scene or spaceship_textures.is_empty():
		return null
	
	# Randomly select a texture from the array
	var texture_index = randi() % spaceship_textures.size()
	var selected_texture = spaceship_textures[texture_index]
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	lane_index = clampi(lane_index, 0, lanes.size() - 1)
	var lane_config = lanes[lane_index]
	
	var rows: Array = lane_config["rows"]
	row_index = clampi(row_index, 0, rows.size() - 1)
	var row_y_ratio: float = rows[row_index]
	
	# Pick random speed behavior
	var speed_index = randi() % speeds_data.size()
	var speed_behavior = speeds_data[speed_index]
	var base_speed = lane_config["speed"] * speed_behavior[0]
	var randomized_speed = _randomize_speed(base_speed)
	
	var direction = 1 if randf() > 0.5 else -1
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float = -spawn_offset if direction > 0 else viewport_size.x + spawn_offset
	
	ship.setup(ship_name, ship_role, direction, lane_config["depth"], randomized_speed)
	ship.min_speed = ship_min_speed
	ship.max_speed = ship_max_speed
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	ship.modulate.a = 1.0
	ship.lane_index = lane_index
	ship.row_index = row_index
	ship.spawn_margin = despawn_offset
	
	# Connect to journey completion signal
	ship.journey_completed.connect(_on_ship_journey_completed)
	
	add_child(ship)
	
	# Register ship in registry
	var ship_id = _register_ship(ship, lane_index, row_index, direction, 
		ship_name, ship_role, texture_index, speed_index)
	ship.set_meta("ship_id", ship_id)
	
	return ship


# ============ JOURNEY COMPLETION HANDLING ============

func _on_ship_journey_completed(ship: Spaceship) -> void:
	"""Handle ship completing its journey - transition to next lane."""
	if not is_instance_valid(ship):
		return
	
	# Calculate next lane (cycle: 0 -> 1 -> 2 -> 0...)
	var current_lane = ship.lane_index
	var next_lane = (current_lane + 1) % lanes.size()
	
	# Pick random row in next lane
	var next_lane_config = lanes[next_lane]
	var rows: Array = next_lane_config["rows"]
	var next_row = randi() % rows.size()
	var row_y_ratio: float = rows[next_row]
	
	# Get lane properties
	var new_depth = next_lane_config["depth"]
	var new_speed = next_lane_config["speed"]
	
	# Transition ship to new lane (direction flips automatically)
	ship.transition_to_lane(next_lane, next_row, row_y_ratio, new_depth, new_speed)
	
	# Update registry entry
	_update_ship_registry_entry(ship, next_lane, next_row, ship.direction)
	
	print("[SpaceshipTraffic] Ship '%s' transitioned to Lane %d.%d, dir=%d" % [
		ship.ship_name, next_lane + 1, next_row + 1, ship.direction])


func _update_ship_registry_entry(ship: Spaceship, lane: int, row: int, direction: int) -> void:
	"""Update a ship's registry entry after lane transition."""
	var ship_id = ship.get_meta("ship_id", -1)
	if ship_id < 0:
		return
	
	for entry in ship_registry:
		if entry["id"] == ship_id:
			entry["lane"] = lane
			entry["row"] = row
			entry["direction"] = direction
			registry_updated.emit()
			return


# ============ REGISTRY MANAGEMENT ============

func _register_ship(ship: Spaceship, lane: int, row: int, direction: int, 
		ship_name: String, ship_role: String, texture_index: int, speed_index: int) -> int:
	"""Register a ship in the registry and return its unique ID"""
	var ship_id = _next_ship_id
	_next_ship_id += 1
	
	var entry := {
		"id": ship_id,
		"ship_ref": ship,
		"lane": lane,
		"row": row,
		"direction": direction,
		"name": ship_name,
		"role": ship_role,
		"texture_index": texture_index,
		"speed_index": speed_index,
	}
	
	ship_registry.append(entry)
	ship_spawned.emit(ship_id, entry.duplicate())
	registry_updated.emit()
	
	return ship_id


func _unregister_ship(ship_id: int) -> void:
	"""Remove a ship from the registry"""
	for i in range(ship_registry.size() - 1, -1, -1):
		if ship_registry[i]["id"] == ship_id:
			ship_registry.remove_at(i)
			ship_removed.emit(ship_id)
			registry_updated.emit()
			return


func get_ship_registry() -> Array[Dictionary]:
	"""Get a copy of the current ship registry for observation"""
	var result: Array[Dictionary] = []
	for entry in ship_registry:
		var copy = entry.duplicate()
		# Include current position from the ship reference
		var ship = entry["ship_ref"] as Spaceship
		if is_instance_valid(ship):
			copy["position"] = ship.position
			copy["current_speed"] = ship.current_speed
		else:
			copy["position"] = Vector2.ZERO
			copy["current_speed"] = 0.0
		result.append(copy)
	return result


func get_ships_in_lane(lane_index: int) -> Array[Dictionary]:
	"""Get all ships currently in a specific lane"""
	var result: Array[Dictionary] = []
	for entry in ship_registry:
		if entry["lane"] == lane_index:
			var copy = entry.duplicate()
			var ship = entry["ship_ref"] as Spaceship
			if is_instance_valid(ship):
				copy["position"] = ship.position
			result.append(copy)
	return result


func get_lane_counts() -> Array[int]:
	"""Get count of ships in each lane [lane1, lane2, lane3]"""
	var counts: Array[int] = [0, 0, 0]
	for entry in ship_registry:
		var lane = entry["lane"]
		if lane >= 0 and lane < 3:
			counts[lane] += 1
	return counts


func get_registry_as_json() -> String:
	"""Export the current registry state as JSON for debugging/saving"""
	var data := {
		"ship_count": ship_registry.size(),
		"lane_counts": get_lane_counts(),
		"ships": []
	}
	
	for entry in ship_registry:
		var ship = entry["ship_ref"] as Spaceship
		var entry_data := {
			"id": entry["id"],
			"name": entry["name"],
			"role": entry["role"],
			"lane": entry["lane"],
			"row": entry["row"],
			"direction": entry["direction"],
			"texture_index": entry["texture_index"],
			"speed_index": entry["speed_index"],
		}
		if is_instance_valid(ship):
			entry_data["position_x"] = ship.position.x
			entry_data["position_y"] = ship.position.y
			entry_data["current_speed"] = ship.current_speed
		data["ships"].append(entry_data)
	
	return JSON.stringify(data, "\t")


func clear_registry() -> void:
	"""Clear the registry and remove all ships"""
	for entry in ship_registry:
		var ship = entry["ship_ref"] as Spaceship
		if is_instance_valid(ship):
			ship.queue_free()
	ship_registry.clear()
	registry_updated.emit()


func set_ship_configurations(configs: Array[Dictionary]) -> void:
	"""Set the deterministic ship configurations array"""
	ship_configurations = configs


func spawn_from_configurations() -> void:
	"""Spawn all ships from the configurations array (deterministic)"""
	clear_registry()
	
	for i in range(ship_configurations.size()):
		var config = ship_configurations[i]
		_spawn_ship_from_config(config, i)
	
	var counts = get_lane_counts()
	print("[SpaceshipTraffic] Spawned %d ships from config - Lane 1: %d, Lane 2: %d, Lane 3: %d" % 
		[ship_registry.size(), counts[0], counts[1], counts[2]])


func _spawn_ship_from_config(config: Dictionary, config_index: int) -> Spaceship:
	"""Spawn a single ship from a configuration dictionary"""
	if not spaceship_scene:
		return null
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	# Extract config values with defaults
	var lane_index: int = config.get("lane", 0)
	var row_index: int = config.get("row", 0)
	var direction: int = config.get("direction", 1)
	var ship_name: String = config.get("name", "Unknown")
	var ship_role: String = config.get("role", "Freighter")
	var texture_index: int = config.get("texture_index", 0)
	var speed_index: int = config.get("speed_index", 2)
	var start_x_ratio: float = config.get("start_x_ratio", randf())  # 0-1 ratio of viewport
	
	# Validate indices
	lane_index = clampi(lane_index, 0, lanes.size() - 1)
	var lane_config = lanes[lane_index]
	var rows: Array = lane_config["rows"]
	row_index = clampi(row_index, 0, rows.size() - 1)
	
	if not spaceship_textures.is_empty():
		texture_index = clampi(texture_index, 0, spaceship_textures.size() - 1)
	speed_index = clampi(speed_index, 0, speeds_data.size() - 1)
	
	# Get texture
	var selected_texture: Texture2D = null
	if not spaceship_textures.is_empty():
		selected_texture = spaceship_textures[texture_index]
	
	# Calculate position
	var row_y_ratio: float = rows[row_index]
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos = viewport_size.x * start_x_ratio
	
	# Get speed behavior
	var speed_behavior = speeds_data[speed_index]
	var base_speed = lane_config["speed"] * speed_behavior[0]
	var randomized_speed = _randomize_speed(base_speed)
	
	# Setup ship
	ship.setup(ship_name, ship_role, direction, lane_config["depth"], randomized_speed)
	ship.min_speed = ship_min_speed
	ship.max_speed = ship_max_speed
	ship.set_movement_behavior(speed_behavior[1], speed_behavior[2], speed_behavior[3])
	ship.position = Vector2(x_pos, y_pos)
	if selected_texture:
		ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	ship.modulate.a = 1.0
	ship.lane_index = lane_index
	ship.spawn_margin = despawn_offset
	
	add_child(ship)
	
	# Register ship
	var ship_id = _register_ship(ship, lane_index, row_index, direction, 
		ship_name, ship_role, texture_index, speed_index)
	ship.set_meta("ship_id", ship_id)
	ship.set_meta("config_index", config_index)
	
	return ship


func generate_default_configurations(count: int = 15) -> Array[Dictionary]:
	"""Generate a set of default ship configurations for deterministic spawning"""
	var configs: Array[Dictionary] = []
	
	for i in range(count):
		# Distribute across lanes: 25% lane 0, 35% lane 1, 40% lane 2
		var lane: int
		var ratio = float(i) / float(count)
		if ratio < 0.25:
			lane = 0
		elif ratio < 0.60:
			lane = 1
		else:
			lane = 2
		
		var rows: Array = lanes[lane]["rows"]
		var row = i % rows.size()
		var direction = 1 if (i % 2 == 0) else -1
		var texture_index = i % max(1, spaceship_textures.size())
		var speed_index = i % speeds_data.size()
		var data_index = i % ship_data.size()
		
		configs.append({
			"name": ship_data[data_index][0],
			"role": ship_data[data_index][1],
			"lane": lane,
			"row": row,
			"direction": direction,
			"texture_index": texture_index,
			"speed_index": speed_index,
			"start_x_ratio": float(i) / float(count),  # Spread across screen
		})
	
	return configs

func spawn_player_ship(ship_name: String, ship_role: String, texture: Texture2D = null) -> Spaceship:
	"""Spawn a launched ship using sequential lane system.
	Cycles through: 1.1 -> 2.1 -> 2.2 -> 3.1 -> 3.2 -> 3.3 -> 3.4 -> 1.1...
	Direction flips each time the lane changes."""
	if not spaceship_scene:
		push_warning("SpaceshipTraffic: Missing spaceship_scene")
		return null
	
	var ship = spaceship_scene.instantiate() as Spaceship
	if not ship:
		return null
	
	# Use current spawn position
	var lane_index = _current_spawn_lane
	var row_index = _current_spawn_row
	var direction = _current_spawn_direction
	
	var lane_config = lanes[lane_index]
	var rows: Array = lane_config["rows"]
	var row_y_ratio: float = rows[row_index]
	
	# Use the preview texture if provided, otherwise fall back to random
	var selected_texture: Texture2D = texture
	var texture_index: int = -1
	if selected_texture == null and not spaceship_textures.is_empty():
		texture_index = randi() % spaceship_textures.size()
		selected_texture = spaceship_textures[texture_index]
	
	if selected_texture == null:
		push_warning("SpaceshipTraffic: No texture available")
		ship.queue_free()
		return null
	
	# Calculate spawn position based on direction
	var y_pos = viewport_size.y * row_y_ratio
	var x_pos: float
	if direction > 0:
		x_pos = -spawn_offset  # Enter from left
	else:
		x_pos = viewport_size.x + spawn_offset  # Enter from right
	
	# Setup ship with randomized speed
	var randomized_speed = _randomize_speed(lane_config["speed"])
	ship.setup(ship_name, ship_role, direction, lane_config["depth"], randomized_speed)
	ship.min_speed = ship_min_speed
	ship.max_speed = ship_max_speed
	ship.set_movement_behavior(0.0, 0.0, 0.0)  # Steady movement
	ship.position = Vector2(x_pos, y_pos)
	ship.set_texture(selected_texture)
	ship.apply_texture_scale(spaceship_scale)
	ship.modulate.a = 1.0
	ship.lane_index = lane_index
	ship.row_index = row_index
	ship.spawn_margin = despawn_offset
	
	# Connect to journey completion signal
	ship.journey_completed.connect(_on_ship_journey_completed)
	
	add_child(ship)
	
	# Register in registry
	var ship_id = _register_ship(ship, lane_index, row_index, direction, 
		ship_name, ship_role, texture_index, -1)
	ship.set_meta("ship_id", ship_id)
	
	print("[SpaceshipTraffic] Launched '%s' at Lane %d.%d, dir=%d" % [ship_name, lane_index + 1, row_index + 1, direction])
	
	# Advance to next spawn position
	_advance_spawn_position()
	
	return ship


func _advance_spawn_position() -> void:
	"""Advance to next spawn position in sequence.
	Order: 1.1 -> 2.1 -> 2.2 -> 3.1 -> 3.2 -> 3.3 -> 3.4 -> 1.1...
	Direction flips when lane changes."""
	var rows: Array = lanes[_current_spawn_lane]["rows"]
	
	# Move to next row
	_current_spawn_row += 1
	
	# If we've exhausted rows in current lane, move to next lane
	if _current_spawn_row >= rows.size():
		_current_spawn_row = 0
		_current_spawn_lane += 1
		
		# If we've exhausted all lanes, cycle back to lane 0
		if _current_spawn_lane >= lanes.size():
			_current_spawn_lane = 0
		
		# Flip direction when lane changes
		_current_spawn_direction *= -1
	
	print("[SpaceshipTraffic] Next spawn: Lane %d.%d, dir=%d" % [_current_spawn_lane + 1, _current_spawn_row + 1, _current_spawn_direction])


func reset_spawn_position() -> void:
	"""Reset spawn position back to Lane 1, Row 1, left-to-right."""
	_current_spawn_lane = 0
	_current_spawn_row = 0
	_current_spawn_direction = 1
	print("[SpaceshipTraffic] Spawn position reset to Lane 1.1, dir=1")


## Update label offset for left-facing ships on all active ships
func set_all_ships_label_offset_left(new_offset: float) -> void:
	for entry in ship_registry:
		var ship = entry.get("ship_ref")
		if ship and is_instance_valid(ship) and ship.has_method("set_label_offset_x_looking_left"):
			ship.set_label_offset_x_looking_left(new_offset)
	print("[SpaceshipTraffic] Updated label_offset_x_looking_left to %s on %d ships" % [new_offset, ship_registry.size()])


## Update label offset for right-facing ships on all active ships
func set_all_ships_label_offset_right(new_offset: float) -> void:
	for entry in ship_registry:
		var ship = entry.get("ship_ref")
		if ship and is_instance_valid(ship) and ship.has_method("set_label_offset_x_looking_right"):
			ship.set_label_offset_x_looking_right(new_offset)
	print("[SpaceshipTraffic] Updated label_offset_x_looking_right to %s on %d ships" % [new_offset, ship_registry.size()])


## Update afterburner trail X offset on all active ships
func set_all_ships_afterburner_trail_offset_x(new_offset: float) -> void:
	for entry in ship_registry:
		var ship = entry.get("ship_ref")
		if ship and is_instance_valid(ship) and ship.has_method("set_afterburner_trail_offset_x"):
			ship.set_afterburner_trail_offset_x(new_offset)
	print("[SpaceshipTraffic] Updated afterburner_trail_offset_x to %s on %d ships" % [new_offset, ship_registry.size()])
