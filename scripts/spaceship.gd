class_name Spaceship
extends Node2D

## Spaceship component with name, role, and model
## Moves horizontally across the screen with optional non-linear movement

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
var spawn_margin: float = 200.0  # Extra distance beyond screen edges for smooth entry/exit
var lane_index: int = -1  # Which lane this ship belongs to (0=closest/blue, 1=mid/yellow, 2=far/red)

@onready var name_label: Label = $LabelContainer/VBoxContainer/NameLabel
@onready var role_label: Label = $LabelContainer/VBoxContainer/RoleLabel
@onready var label_container: Control = $LabelContainer

# Store original label width for positioning
var _label_width: float = 240.0

func _ready() -> void:
	viewport_width = get_viewport_rect().size.x
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
	
	# Wrap around when off screen
	if direction > 0 and position.x > viewport_width + spawn_margin:
		position.x = -spawn_margin
		_on_wrap()
	elif direction < 0 and position.x < -spawn_margin:
		position.x = viewport_width + spawn_margin
		_on_wrap()

func _on_wrap() -> void:
	# Reset time and speed when wrapping for varied behavior
	time_alive = randf() * 10.0  # Random phase offset
	current_speed = speed  # Reset to base speed

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
