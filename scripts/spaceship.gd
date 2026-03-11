class_name Spaceship
extends Node2D

## Spaceship component with name, role, and model
## Moves horizontally across the screen with optional non-linear movement

signal journey_completed(ship: Spaceship)  # Emitted when ship exits screen

@export var ship_name: String = "Unknown"
@export var role: String = "Freighter"
@export var speed: float = 50.0
@export var direction: int = 1  # 1 = right, -1 = left
@export var layer_depth: float = 1.0  # Affects scale and speed (bigger = closer/faster)
@export var show_labels: bool = true

@export_group("Label Offsets")
@export var label_offset_x_looking_right: float = -110.0  ## X offset when ship faces right
@export var label_offset_x_looking_left: float = 110.0   ## X offset when ship faces left

# Non-linear movement parameters
var drift_amplitude: float = 0.0    # Vertical sine wave drift in pixels
var drift_frequency: float = 0.0    # How fast the drift oscillates
var acceleration: float = 0.0       # Speed change per second
var base_y: float = 0.0             # Original Y position for drift calculation
var time_alive: float = 0.0         # Time since spawn for drift calculation
var current_speed: float = 0.0      # Actual speed (changes with acceleration)

var viewport_width: float = 1920.0
var viewport_height: float = 1080.0
var spawn_margin: float = 200.0  # Extra distance beyond screen edges for smooth entry/exit
var lane_index: int = -1  # Which lane this ship belongs to (0=closest/blue, 1=mid/yellow, 2=far/red)
var row_index: int = 0    # Which row within the lane

@onready var name_label: Label = $LabelContainer/VBoxContainer/NameLabel
@onready var role_label: Label = $LabelContainer/VBoxContainer/RoleLabel
@onready var label_container: Control = $LabelContainer

# Store original label width for positioning
var _label_width: float = 240.0

func _ready() -> void:
	var viewport_size = get_viewport_rect().size
	viewport_width = viewport_size.x
	viewport_height = viewport_size.y
	base_y = position.y
	current_speed = speed
	
	# Calculate label width from original offsets
	if label_container:
		_label_width = label_container.offset_right - label_container.offset_left
	
	update_labels()

func _process(delta: float) -> void:
	time_alive += delta
	
	# Apply acceleration (speed changes over time)
	if acceleration != 0.0:
		current_speed += acceleration * delta
		# Clamp speed to reasonable bounds
		current_speed = clampf(current_speed, speed * 0.3, speed * 2.5)
	
	# Horizontal movement
	position.x += current_speed * direction * delta
	
	# Vertical drift (sine wave)
	if drift_amplitude > 0.0:
		position.y = base_y + sin(time_alive * drift_frequency * TAU) * drift_amplitude
	
	# Check if ship has exited screen (journey completed)
	if direction > 0 and position.x > viewport_width + spawn_margin:
		journey_completed.emit(self)
	elif direction < 0 and position.x < -spawn_margin:
		journey_completed.emit(self)


func transition_to_lane(new_lane_index: int, new_row_index: int, row_y_ratio: float, new_depth: float, new_speed: float) -> void:
	"""Transition ship to a new lane with flipped direction."""
	lane_index = new_lane_index
	row_index = new_row_index
	
	# Flip direction
	direction *= -1
	
	# Update depth and speed for new lane
	layer_depth = new_depth
	speed = new_speed
	current_speed = new_speed
	
	# Update scale for new depth
	scale = Vector2(layer_depth, layer_depth)
	if direction < 0:
		scale.x *= -1
	
	# Set new Y position
	var new_y = viewport_height * row_y_ratio
	position.y = new_y
	base_y = new_y
	
	# Set spawn position based on new direction
	if direction > 0:
		position.x = -spawn_margin  # Enter from left
	else:
		position.x = viewport_width + spawn_margin  # Enter from right
	
	# Reset movement state
	time_alive = randf() * 10.0
	drift_amplitude = 0.0
	acceleration = 0.0
	
	update_labels()

func setup(p_name: String, p_role: String, p_direction: int, p_depth: float, p_speed: float) -> void:
	ship_name = p_name
	role = p_role
	direction = p_direction
	layer_depth = p_depth
	
	# Closer ships (higher depth) are bigger and move faster
	speed = p_speed
	current_speed = p_speed
	scale = Vector2(layer_depth, layer_depth)
	
	# Flip sprite if moving left (but keep labels readable)
	if direction < 0:
		scale.x *= -1
	
	# Update labels after setup
	if is_inside_tree():
		update_labels()

func set_movement_behavior(p_drift_amplitude: float, p_drift_frequency: float, p_acceleration: float) -> void:
	drift_amplitude = p_drift_amplitude
	drift_frequency = p_drift_frequency
	acceleration = p_acceleration
	# Random starting phase for variety
	time_alive = randf() * 10.0

func update_labels() -> void:
	if name_label:
		name_label.text = ship_name.to_upper()
	if role_label:
		role_label.text = role
	
	# Keep labels upright and properly positioned when ship is flipped
	if label_container:
		if direction < 0:
			# Flip scale to keep text readable
			label_container.scale.x = -1
			# Use custom offset for left-facing ships
			label_container.offset_left = label_offset_x_looking_left
			label_container.offset_right = label_offset_x_looking_left + _label_width
		else:
			# Use custom offset for right-facing ships
			label_container.scale.x = 1
			label_container.offset_left = label_offset_x_looking_right
			label_container.offset_right = label_offset_x_looking_right + _label_width

func set_labels_visible(labels_visible: bool) -> void:
	show_labels = labels_visible
	if label_container:
		label_container.visible = labels_visible

func set_texture(texture: Texture2D) -> void:
	var sprite = $Sprite2D
	if sprite:
		sprite.texture = texture

func apply_texture_scale(scale_factor: float) -> void:
	## Apply a scale factor to the sprite for sizing adjustments
	var sprite = $Sprite2D
	if sprite:
		sprite.scale = Vector2(scale_factor, scale_factor)
