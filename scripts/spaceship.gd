class_name Spaceship
extends Node2D

## Spaceship component with name, role, and model
## Moves horizontally across the screen with optional non-linear movement

signal journey_completed(ship: Spaceship)  # Emitted when ship exits screen

# Activity types
enum Activity { NONE, LIGHT_SPEED_JUMP, ACCELERATE, DECELERATE }

# Activity map - defines available activities and their weights
const ACTIVITY_MAP: Dictionary = {
	Activity.LIGHT_SPEED_JUMP: {
		"name": "LightSpeedJump",
		"weight": 1.0,           # Equal chance with StopAndGo
		"min_progress": 0.15,    # Can trigger earlier
		"max_progress": 0.6,     # Must trigger before 60% (needs room to jump)
	},
	Activity.ACCELERATE: {
		"name": "Accelerate",
		"weight": 1.0,           # Equal chance with others
		"min_progress": 0.1,     # Can trigger early
		"max_progress": 0.7,     # Don't trigger too late
	},
	Activity.DECELERATE: {
		"name": "Decelerate",
		"weight": 1.0,           # Equal chance with others
		"min_progress": 0.1,     # Can trigger early
		"max_progress": 0.7,     # Don't trigger too late
	},
}

# Chance that an activity will occur during a lane (0.0 - 1.0)
# Base chance for lane 1, increases for lanes 2 and 3
const ACTIVITY_CHANCE_BASE: float = 0.2   # Lane 1 (closest): 20%
const ACTIVITY_CHANCE_PER_LANE: float = 0.2  # +20% per lane (Lane 2: 40%, Lane 3: 60%)

@export var ship_name: String = "Unknown"
@export var role: String = "Freighter"
@export var speed: float = 50.0
@export var direction: int = 1  # 1 = right, -1 = left
@export var layer_depth: float = 1.0  # Affects scale and speed (bigger = closer/faster)
@export var show_labels: bool = true
@export var min_speed: float = 20.0   # Minimum speed the ship can decelerate to
@export var max_speed: float = 200.0  # Maximum speed the ship can accelerate to

@export_group("Label Offsets")
@export var label_offset_x_looking_right: float = -110.0  ## X offset when ship faces right
@export var label_offset_x_looking_left: float = 110.0   ## X offset when ship faces left

# Role-to-theme color mapping (RGBA)
# Bots always use white, player ships use role-based colors
const ROLE_THEME_COLORS: Dictionary = {
	"Bot": Color(1.0, 1.0, 1.0, 1.0),           # White for bots
	"Design": Color(0.95, 0.3, 0.5, 1.0),       # Pink/Magenta
	"Engineering": Color(0.2, 0.8, 1.0, 1.0),   # Cyan
	"Creative": Color(1.0, 0.6, 0.1, 1.0),      # Orange
	"Production": Color(0.4, 1.0, 0.4, 1.0),    # Green
}
const DEFAULT_THEME_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)  # White fallback

# Theme color for this ship (set based on role)
var theme_color: Color = DEFAULT_THEME_COLOR

# Non-linear movement parameters
var drift_amplitude: float = 0.0    # Vertical sine wave drift in pixels
var drift_frequency: float = 0.0    # How fast the drift oscillates
var acceleration: float = 0.0       # Speed change per second
var base_y: float = 0.0             # Original Y position for drift calculation
var time_alive: float = 0.0         # Time since spawn for drift calculation
var current_speed: float = 0.0      # Actual speed (changes with acceleration)

# Organic speed variation - makes ships naturally accelerate/decelerate
var organic_speed_enabled: bool = true        # Enable organic speed changes
var organic_target_speed: float = 0.0         # Target speed we're transitioning to
var organic_speed_lerp_rate: float = 0.5      # How fast to transition (per second)
var organic_next_change_time: float = 0.0     # When to pick a new target speed
var organic_change_interval_min: float = 2.0  # Min seconds between speed changes
var organic_change_interval_max: float = 5.0  # Max seconds between speed changes
var organic_speed_variance: float = 0.25      # How much speed can vary from base (0.25 = ±25%)

var viewport_width: float = 1920.0
var viewport_height: float = 1080.0
var spawn_margin: float = 200.0  # Extra distance beyond screen edges for smooth entry/exit
var lane_index: int = -1  # Which lane this ship belongs to (0=closest/blue, 1=mid/yellow, 2=far/red)
var row_index: int = 0    # Which row within the lane

# Activity state
var activity: Activity = Activity.NONE      # Current activity
var _activity_tween: Tween = null           # Tween for activity animations

# Multi-segment activity system - allows activity checks at multiple points in journey
var _activity_check_points: Array[float] = [0.2, 0.4, 0.6, 0.8]  # Progress points to check for activities
var _next_check_index: int = 0              # Which checkpoint to check next

# Lightspeed jump shader
var _lightspeed_shader: ShaderMaterial = null
var _original_material: Material = null
var _lightspeed_trail: ColorRect = null
var _afterburner_trail: ColorRect = null
var _afterburner_pulse_time: float = 0.0
var _afterburner_trail_offset_x: float = 0.0  # X offset for afterburner trail position
var _original_sprite_scale: Vector2 = Vector2.ONE
const LIGHTSPEED_SHADER_PATH = "res://shaders/lightspeed_jump.gdshader"
const TRAIL_GRADIENT_SHADER = preload("res://shaders/lightspeed_trail.gdshader")
const AFTERBURNER_TRAIL_SHADER = preload("res://shaders/afterburner_trail.gdshader")

@onready var sprite: Sprite2D = $Sprite2D
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
	organic_target_speed = speed
	
	# Randomize initial organic speed change timing so ships don't all change at once
	organic_next_change_time = randf_range(0.5, organic_change_interval_max)
	
	# Calculate label width from original offsets
	if label_container:
		_label_width = label_container.offset_right - label_container.offset_left
	
	update_labels()

func _process(delta: float) -> void:
	time_alive += delta
	
	# Skip movement if activity is controlling speed
	if activity == Activity.NONE:
		# Organic speed variation - natural acceleration/deceleration
		if organic_speed_enabled:
			_update_organic_speed(delta)
		# Apply manual acceleration (speed changes over time)
		elif acceleration != 0.0:
			current_speed += acceleration * delta
			current_speed = clampf(current_speed, min_speed, max_speed)
	
	# Horizontal movement
	position.x += current_speed * direction * delta
	
	# Vertical drift (sine wave)
	if drift_amplitude > 0.0:
		position.y = base_y + sin(time_alive * drift_frequency * TAU) * drift_amplitude
	
	# Check for random activity trigger (only once per lane, when no activity running)
	if activity == Activity.NONE:
		_check_activity_trigger()
	
	# Check if ship has exited screen (journey completed)
	if direction > 0 and position.x > viewport_width + spawn_margin:
		journey_completed.emit(self)
	elif direction < 0 and position.x < -spawn_margin:
		journey_completed.emit(self)


func _update_organic_speed(delta: float) -> void:
	"""Update organic speed variation - makes ships naturally speed up and slow down."""
	# Check if it's time to pick a new target speed
	if time_alive >= organic_next_change_time:
		_pick_new_organic_target()
	
	# Smoothly interpolate current speed towards target
	if abs(current_speed - organic_target_speed) > 0.1:
		current_speed = lerpf(current_speed, organic_target_speed, organic_speed_lerp_rate * delta)
		current_speed = clampf(current_speed, min_speed, max_speed)


func _pick_new_organic_target() -> void:
	"""Pick a new random target speed for organic movement."""
	# Calculate speed range based on base speed and variance
	var speed_min = speed * (1.0 - organic_speed_variance)
	var speed_max = speed * (1.0 + organic_speed_variance)
	
	# Clamp to ship's min/max limits
	speed_min = maxf(speed_min, min_speed)
	speed_max = minf(speed_max, max_speed)
	
	# Pick new target (bias towards base speed slightly)
	var rand_val = randf()
	if rand_val < 0.3:
		# 30% chance: accelerate
		organic_target_speed = randf_range(speed, speed_max)
	elif rand_val < 0.6:
		# 30% chance: decelerate
		organic_target_speed = randf_range(speed_min, speed)
	else:
		# 40% chance: stay near current with small variation
		var small_variance = speed * 0.1
		organic_target_speed = randf_range(current_speed - small_variance, current_speed + small_variance)
	
	organic_target_speed = clampf(organic_target_speed, min_speed, max_speed)
	
	# Schedule next speed change
	organic_next_change_time = time_alive + randf_range(organic_change_interval_min, organic_change_interval_max)


func _check_activity_trigger() -> void:
	"""Check if we should trigger an activity at journey checkpoints."""
	# Skip if we've checked all points or an activity is running
	if _next_check_index >= _activity_check_points.size():
		return
	
	var progress = _get_journey_progress()
	var next_checkpoint = _activity_check_points[_next_check_index]
	
	# Check if we've reached the next checkpoint
	if progress >= next_checkpoint:
		_next_check_index += 1
		
		# Calculate activity chance based on lane (farther lanes = higher chance)
		# lane_index: 0=closest, 1=mid, 2=farthest
		var activity_chance = ACTIVITY_CHANCE_BASE + (lane_index * ACTIVITY_CHANCE_PER_LANE)
		
		# Roll for activity
		if randf() < activity_chance:
			_start_random_activity()


func _get_journey_progress() -> float:
	"""Get journey progress as 0.0 to 1.0 based on position."""
	if direction > 0:
		# Moving right: progress from -spawn_margin to viewport_width + spawn_margin
		return (position.x + spawn_margin) / (viewport_width + 2 * spawn_margin)
	else:
		# Moving left: progress from viewport_width + spawn_margin to -spawn_margin
		return (viewport_width + spawn_margin - position.x) / (viewport_width + 2 * spawn_margin)


func _start_random_activity() -> void:
	"""Pick and start a random activity from the activity map."""
	# Calculate total weight
	var total_weight = 0.0
	for activity_type in ACTIVITY_MAP:
		total_weight += ACTIVITY_MAP[activity_type]["weight"]
	
	# Pick random activity based on weights
	var roll = randf() * total_weight
	var cumulative = 0.0
	
	for activity_type in ACTIVITY_MAP:
		cumulative += ACTIVITY_MAP[activity_type]["weight"]
		if roll <= cumulative:
			match activity_type:
				Activity.LIGHT_SPEED_JUMP:
					_start_activity_light_speed_jump()
				Activity.ACCELERATE:
					_start_activity_accelerate()
				Activity.DECELERATE:
					_start_activity_decelerate()
			return
	
	# Fallback
	_start_activity_accelerate()



func _start_activity_accelerate() -> void:
	"""Accelerate activity: increase ship speed and maintain it with neon afterburner trail."""
	activity = Activity.ACCELERATE
	print("[Spaceship] Starting ACCELERATE activity for ", ship_name)
	
	# Calculate target speed (increase by 30-60% but clamp to max_speed)
	var speed_increase = current_speed * randf_range(0.3, 0.6)
	var target_speed = minf(current_speed + speed_increase, max_speed)
	
	# Kill any existing tween
	if _activity_tween and _activity_tween.is_valid():
		_activity_tween.kill()
	
	# Create afterburner trail at current position
	_create_afterburner_trail()
	
	_activity_tween = create_tween()
	
	# Accelerate to target speed (0.8-1.2 seconds)
	var accel_time = 6.0  # Fixed 6 second acceleration duration
	
	# Animate speed and trail simultaneously
	_activity_tween.tween_method(_animate_accelerate_with_trail.bind(current_speed, target_speed), 0.0, 1.0, accel_time).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	
	# Fade out the trail after acceleration completes
	_activity_tween.tween_callback(_fade_out_afterburner_trail)
	_activity_tween.tween_interval(0.4)  # Wait for trail fade
	
	# Activity complete - ship stays at new speed
	_activity_tween.tween_callback(_on_activity_complete)


func _start_activity_decelerate() -> void:
	"""Decelerate activity: decrease ship speed and maintain it."""
	activity = Activity.DECELERATE

	
	# Calculate target speed (decrease by 20-40% but clamp to min_speed)
	var speed_decrease = current_speed * randf_range(0.2, 0.4)
	var target_speed = maxf(current_speed - speed_decrease, min_speed)
	
	# Kill any existing tween
	if _activity_tween and _activity_tween.is_valid():
		_activity_tween.kill()
	
	_activity_tween = create_tween()
	
	# Decelerate to target speed (1.0-1.5 seconds, slower than accelerate)
	var decel_time = randf_range(1.0, 1.5)
	_activity_tween.tween_property(self, "current_speed", target_speed, decel_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	# Activity complete - ship stays at new speed
	_activity_tween.tween_callback(_on_activity_complete)


func _start_activity_light_speed_jump() -> void:
	"""LightSpeedJump activity: ship glows, scales down, then rapidly jumps off-screen with a gradient trail."""
	activity = Activity.LIGHT_SPEED_JUMP

	
	# Setup shader if not already done
	_setup_lightspeed_shader()
	
	# Store original sprite scale (accounting for direction flip)
	if sprite:
		_original_sprite_scale = sprite.scale
	
	# Calculate jump destination - move to end of lane (off-screen)
	var jump_target_x: float
	if direction > 0:
		jump_target_x = viewport_width + spawn_margin + 100.0  # Off right edge
	else:
		jump_target_x = -spawn_margin - 100.0  # Off left edge
	
	# Store jump start position for trail
	var jump_start_x: float = position.x
	
	# Kill any existing tween
	if _activity_tween and _activity_tween.is_valid():
		_activity_tween.kill()
	
	_activity_tween = create_tween()
	
	# Phase 1: Charge up - slow to stop, build glow (0.5 seconds)
	_activity_tween.tween_property(self, "current_speed", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	_activity_tween.parallel().tween_method(_set_shader_param.bind("glow_intensity"), 0.0, 2.5, 0.5)
	
	# Phase 2: Flash moment with scale down to 0.7 (0.1 seconds)
	_activity_tween.tween_method(_set_shader_param.bind("flash_intensity"), 0.0, 1.0, 0.1)
	if sprite:
		var scaled_down = _original_sprite_scale * 0.7
		_activity_tween.parallel().tween_property(sprite, "scale", scaled_down, 0.1)
	
	# Create gradient trail ColorRect at jump start position (starts with zero width)
	_activity_tween.tween_callback(_create_gradient_trail.bind(jump_start_x))
	
	# Phase 3: JUMP! Rapidly move to end of lane (0.25 seconds)
	# Use tween_method to animate position AND update trail simultaneously
	_activity_tween.tween_method(_animate_jump_with_trail.bind(jump_start_x, jump_target_x), 0.0, 1.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	_activity_tween.parallel().tween_method(_set_shader_param.bind("flash_intensity"), 1.0, 0.0, 0.25)
	_activity_tween.parallel().tween_method(_set_shader_param.bind("glow_intensity"), 2.5, 1.0, 0.25)
	
	# Restore sprite scale after jump
	if sprite:
		_activity_tween.parallel().tween_property(sprite, "scale", _original_sprite_scale, 0.2).set_delay(0.15)
	
	# Phase 4: Fade out gradient trail (0.5 seconds)
	_activity_tween.tween_callback(_fade_out_gradient_trail)
	_activity_tween.tween_interval(0.5)  # Wait for trail fade
	_activity_tween.parallel().tween_method(_set_shader_param.bind("glow_intensity"), 1.0, 0.0, 0.3)
	
	# Phase 5: Emit journey completed (ship has exited screen)
	_activity_tween.tween_callback(_on_lightspeed_complete)
	_activity_tween.tween_callback(func(): journey_completed.emit(self))


func _setup_lightspeed_shader() -> void:
	"""Setup the lightspeed shader on the sprite."""
	if not sprite:
		return
	
	if _lightspeed_shader == null:
		var shader = load(LIGHTSPEED_SHADER_PATH) as Shader
		if shader:
			_lightspeed_shader = ShaderMaterial.new()
			_lightspeed_shader.shader = shader
	
	if _lightspeed_shader:
		_original_material = sprite.material
		sprite.material = _lightspeed_shader
		# Set initial values
		_lightspeed_shader.set_shader_parameter("glow_intensity", 0.0)
		_lightspeed_shader.set_shader_parameter("trail_length", 0.0)
		_lightspeed_shader.set_shader_parameter("trail_opacity", 0.0)
		_lightspeed_shader.set_shader_parameter("flash_intensity", 0.0)
		_lightspeed_shader.set_shader_parameter("direction", direction)


func _set_shader_param(value: float, param_name: String) -> void:
	"""Helper to set shader parameters via tween."""
	if _lightspeed_shader:
		_lightspeed_shader.set_shader_parameter(param_name, value)


func _create_gradient_trail(start_x: float) -> void:
	"""Create a ColorRect gradient trail starting at zero width (grows with ship movement)."""
	# Remove any existing trail
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail):
		_lightspeed_trail.queue_free()
	
	# Create ColorRect for trail
	_lightspeed_trail = ColorRect.new()
	
	# Calculate trail dimensions - start with zero width
	var trail_height = 40.0 * layer_depth  # Height based on ship depth
	
	# Position trail at ship's Y, at the start position
	_lightspeed_trail.position = Vector2(start_x, position.y - trail_height / 2.0)
	_lightspeed_trail.size = Vector2(0.0, trail_height)  # Start at zero width
	
	# Store start position for growth updates
	_lightspeed_trail.set_meta("start_x", start_x)
	_lightspeed_trail.set_meta("direction", direction)
	
	# Apply gradient shader
	var trail_material = ShaderMaterial.new()
	trail_material.shader = TRAIL_GRADIENT_SHADER
	trail_material.set_shader_parameter("trail_color", Color(0.4, 0.8, 1.0, 0.8))
	trail_material.set_shader_parameter("opacity", 1.0)
	trail_material.set_shader_parameter("direction", direction)
	_lightspeed_trail.material = trail_material
	
	# Add to parent (same level as ship for proper layering)
	var parent = get_parent()
	if parent:
		parent.add_child(_lightspeed_trail)
		# Move trail behind the ship
		parent.move_child(_lightspeed_trail, get_index())


func _update_trail_to_ship_position() -> void:
	"""Update trail width and position to follow the ship's current position."""
	if not _lightspeed_trail or not is_instance_valid(_lightspeed_trail):
		return
	
	var start_x: float = _lightspeed_trail.get_meta("start_x", position.x)
	var trail_direction: int = _lightspeed_trail.get_meta("direction", 1)
	
	# Calculate current trail width based on ship position
	var trail_width = absf(position.x - start_x)
	
	# Update trail size
	_lightspeed_trail.size.x = trail_width
	
	# Update position based on direction
	if trail_direction > 0:
		# Moving right: trail extends from start_x to ship
		_lightspeed_trail.position.x = start_x
	else:
		# Moving left: trail extends from ship to start_x
		_lightspeed_trail.position.x = position.x


func _animate_jump_with_trail(progress: float, start_x: float, end_x: float) -> void:
	"""Animate ship position and trail growth together during jump."""
	# Update ship position based on progress
	position.x = lerpf(start_x, end_x, progress)
	
	# Update trail to follow ship position
	_update_trail_to_ship_position()


func _fade_out_gradient_trail() -> void:
	"""Fade out the gradient trail progressively from tail to head (like smoke dissipating)."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail):
		var trail_tween = create_tween()
		# Progressive fade from tail to head using fade_progress
		trail_tween.tween_method(_set_trail_fade_progress, 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN)
		trail_tween.tween_callback(_remove_gradient_trail)


func _set_trail_fade_progress(value: float) -> void:
	"""Helper to set trail fade progress via tween (0=full trail, 1=fully faded from tail)."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail) and _lightspeed_trail.material:
		_lightspeed_trail.material.set_shader_parameter("fade_progress", value)


func _set_trail_opacity(value: float) -> void:
	"""Helper to set trail opacity via tween."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail) and _lightspeed_trail.material:
		_lightspeed_trail.material.set_shader_parameter("opacity", value)


func _remove_gradient_trail() -> void:
	"""Remove the gradient trail from the scene."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail):
		_lightspeed_trail.queue_free()
		_lightspeed_trail = null


# ============================================================================
# AFTERBURNER TRAIL FUNCTIONS (for Accelerate activity)
# ============================================================================

func _create_afterburner_trail() -> void:
	"""Create a neon afterburner trail anchored at the ship's current position.
	Trail grows in world space as ship accelerates away from the start point."""
	# Remove any existing trail
	_remove_afterburner_trail()
	
	# Create ColorRect for trail
	_afterburner_trail = ColorRect.new()
	_afterburner_pulse_time = 0.0
	
	# Calculate trail height based on ship depth
	var trail_height = 30.0 * layer_depth
	
	# Store the starting position (where acceleration began)
	var start_x = position.x
	
	# Position trail at ship's current Y, starting with zero width
	_afterburner_trail.position = Vector2(start_x, position.y - trail_height / 2.0)
	_afterburner_trail.size = Vector2(0.0, trail_height)  # Start at zero width
	
	# Store metadata for trail updates
	_afterburner_trail.set_meta("start_x", start_x)
	_afterburner_trail.set_meta("start_y", position.y)
	_afterburner_trail.set_meta("trail_height", trail_height)
	_afterburner_trail.set_meta("direction", direction)
	_afterburner_trail.set_meta("start_time", Time.get_ticks_msec())
	
	# Apply neon afterburner shader with theme color
	var trail_material = ShaderMaterial.new()
	trail_material.shader = AFTERBURNER_TRAIL_SHADER
	
	# Calculate trail colors based on theme
	var core_col: Color
	var glow_col: Color
	
	if theme_color == DEFAULT_THEME_COLOR:
		# Bot ships: use default white core with subtle cyan glow
		core_col = Color(1.0, 0.98, 0.95, 1.0)  # Warm white core
		glow_col = Color(0.7, 0.85, 1.0, 1.0)   # Subtle cool white/cyan glow
	else:
		# Player ships: use theme color for the trail hue
		# Core is a brightened/lighter version of theme color
		core_col = Color(
			minf(theme_color.r + 0.4, 1.0),
			minf(theme_color.g + 0.4, 1.0),
			minf(theme_color.b + 0.4, 1.0),
			1.0
		)
		# Glow uses the theme color directly
		glow_col = theme_color
	
	trail_material.set_shader_parameter("core_color", core_col)
	trail_material.set_shader_parameter("glow_color", glow_col)
	trail_material.set_shader_parameter("opacity", 1.0)
	trail_material.set_shader_parameter("direction", direction)
	trail_material.set_shader_parameter("glow_intensity", 2.5)
	trail_material.set_shader_parameter("fade_progress", 0.0)
	trail_material.set_shader_parameter("pulse_time", 0.0)
	_afterburner_trail.material = trail_material
	
	# Add to parent (world space) so trail stays anchored while ship moves
	var parent = get_parent()
	if parent:
		parent.add_child(_afterburner_trail)
		# Move trail behind the ship in render order
		parent.move_child(_afterburner_trail, get_index())
	
	print("[Spaceship] Afterburner trail created for ", ship_name, " at start_x=", start_x)


func _animate_accelerate_with_trail(progress: float, start_speed: float, target_speed: float) -> void:
	"""Animate ship speed and update afterburner trail during acceleration."""
	# Update ship speed
	current_speed = lerpf(start_speed, target_speed, progress)
	
	# Update afterburner trail position and pulse
	_update_afterburner_trail()


func _update_afterburner_trail() -> void:
	"""Update afterburner trail to grow from start position to current ship position."""
	if not _afterburner_trail or not is_instance_valid(_afterburner_trail):
		return
	
	var start_x: float = _afterburner_trail.get_meta("start_x", position.x)
	var start_y: float = _afterburner_trail.get_meta("start_y", position.y)
	var trail_height: float = _afterburner_trail.get_meta("trail_height", 30.0)
	var trail_direction: int = _afterburner_trail.get_meta("direction", 1)
	var start_time: int = _afterburner_trail.get_meta("start_time", Time.get_ticks_msec())
	
	# Calculate trail width based on distance traveled from start
	var trail_width = absf(position.x - start_x)
	
	# Update trail size
	_afterburner_trail.size.x = trail_width
	_afterburner_trail.size.y = trail_height
	
	# Update trail position based on direction
	if trail_direction > 0:
		# Moving right: trail starts at start_x and extends right toward ship
		_afterburner_trail.position.x = start_x
	else:
		# Moving left: trail starts at current position and extends right toward start_x
		_afterburner_trail.position.x = position.x
	
	# Keep Y centered on the path
	_afterburner_trail.position.y = start_y - trail_height / 2.0
	
	# Update pulse animation
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	if _afterburner_trail.material:
		_afterburner_trail.material.set_shader_parameter("pulse_time", elapsed)


func _fade_out_afterburner_trail() -> void:
	"""Fade out the afterburner trail by reducing opacity to 0."""
	if _afterburner_trail and is_instance_valid(_afterburner_trail):
		var trail_tween = create_tween()
		# Fade opacity from 1.0 to 0.0 over 0.5 seconds
		trail_tween.tween_method(_set_afterburner_opacity, 1.0, 0.0, 0.5).set_ease(Tween.EASE_OUT)
		trail_tween.tween_callback(_remove_afterburner_trail)


func _set_afterburner_opacity(value: float) -> void:
	"""Helper to set afterburner trail opacity via tween."""
	if _afterburner_trail and is_instance_valid(_afterburner_trail) and _afterburner_trail.material:
		_afterburner_trail.material.set_shader_parameter("opacity", value)


func _set_afterburner_fade_progress(value: float) -> void:
	"""Helper to set afterburner trail fade progress via tween."""
	if _afterburner_trail and is_instance_valid(_afterburner_trail) and _afterburner_trail.material:
		_afterburner_trail.material.set_shader_parameter("fade_progress", value)


func _remove_afterburner_trail() -> void:
	"""Remove the afterburner trail from the scene."""
	if _afterburner_trail and is_instance_valid(_afterburner_trail):
		_afterburner_trail.queue_free()
		_afterburner_trail = null


func _on_lightspeed_complete() -> void:
	"""Called when lightspeed jump completes."""
	# Restore original material
	if sprite and _original_material != null:
		sprite.material = _original_material
	elif sprite:
		sprite.material = null
	
	# Restore sprite scale
	if sprite:
		sprite.scale = _original_sprite_scale
	
	# Clean up trail if still exists
	_remove_gradient_trail()
	
	activity = Activity.NONE


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
	
	# Reset activity state for new lane
	_reset_activity_state()
	
	update_labels()


func _on_activity_complete() -> void:
	"""Called when an activity finishes."""
	activity = Activity.NONE
	
	# Sync organic speed system with current speed after activity
	# This makes the new speed (from Accelerate/Decelerate) the baseline for organic variation
	organic_target_speed = current_speed
	speed = current_speed  # Update base speed so organic variation centers around new speed
	organic_next_change_time = time_alive + randf_range(1.0, organic_change_interval_max)


func _reset_activity_state() -> void:
	"""Reset activity state for a new lane."""
	activity = Activity.NONE
	_next_check_index = 0  # Reset checkpoint index for new lane
	
	# Kill any running activity tween
	if _activity_tween and _activity_tween.is_valid():
		_activity_tween.kill()
		_activity_tween = null
	
	# Restore original material if lightspeed shader was active
	if sprite and sprite.material == _lightspeed_shader:
		if _original_material != null:
			sprite.material = _original_material
		else:
			sprite.material = null
	
	# Restore sprite scale if it was modified
	if sprite and _original_sprite_scale != Vector2.ONE:
		sprite.scale = _original_sprite_scale
	
	# Clean up any leftover trails
	_remove_gradient_trail()
	_remove_afterburner_trail()

func setup(p_name: String, p_role: String, p_direction: int, p_depth: float, p_speed: float) -> void:
	ship_name = p_name
	role = p_role
	direction = p_direction
	layer_depth = p_depth
	
	# Set theme color based on role
	theme_color = ROLE_THEME_COLORS.get(p_role, DEFAULT_THEME_COLOR)
	
	# Closer ships (higher depth) are bigger and move faster
	speed = p_speed
	current_speed = p_speed
	organic_target_speed = p_speed  # Initialize organic speed target
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
	# Hide labels entirely for Bot ships
	if role == "Bot":
		if label_container:
			label_container.visible = false
		return
	
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
	var sprite_node = $Sprite2D
	if sprite_node:
		sprite_node.texture = texture

func apply_texture_scale(scale_factor: float) -> void:
	## Apply a scale factor to the sprite for sizing adjustments
	var sprite_node = $Sprite2D
	if sprite_node:
		sprite_node.scale = Vector2(scale_factor, scale_factor)


## Set label X offset for right-facing ships and refresh position
func set_label_offset_x_looking_right(offset: float) -> void:
	label_offset_x_looking_right = offset
	_refresh_label_position()


## Set label X offset for left-facing ships and refresh position
func set_label_offset_x_looking_left(offset: float) -> void:
	label_offset_x_looking_left = offset
	_refresh_label_position()


## Refresh label position based on current direction and offsets
func _refresh_label_position() -> void:
	if not label_container:
		return
	
	if direction < 0:
		label_container.scale.x = -1
		label_container.offset_left = label_offset_x_looking_left
		label_container.offset_right = label_offset_x_looking_left + _label_width
	else:
		label_container.scale.x = 1
		label_container.offset_left = label_offset_x_looking_right
		label_container.offset_right = label_offset_x_looking_right + _label_width


## Set afterburner trail X offset (positive = toward ship nose, negative = away from ship)
func set_afterburner_trail_offset_x(offset: float) -> void:
	_afterburner_trail_offset_x = offset
	# Update trail position if it exists
	if _afterburner_trail and is_instance_valid(_afterburner_trail):
		_update_afterburner_trail()
