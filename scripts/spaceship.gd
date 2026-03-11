class_name Spaceship
extends Node2D

## Spaceship component with name, role, and model
## Moves horizontally across the screen with optional non-linear movement

signal journey_completed(ship: Spaceship)  # Emitted when ship exits screen

# Activity types
enum Activity { NONE, STOP_AND_GO, LIGHT_SPEED_JUMP }

# Activity map - defines available activities and their weights
const ACTIVITY_MAP: Dictionary = {
	Activity.STOP_AND_GO: {
		"name": "StopAndGo",
		"weight": 1.0,           # Relative chance of being selected
		"min_progress": 0.2,     # Don't trigger before 20% of journey
		"max_progress": 0.8,     # Don't trigger after 80% of journey
	},
	Activity.LIGHT_SPEED_JUMP: {
		"name": "LightSpeedJump",
		"weight": 1.0,           # Equal chance with StopAndGo
		"min_progress": 0.15,    # Can trigger earlier
		"max_progress": 0.6,     # Must trigger before 60% (needs room to jump)
	},
}

# Chance that an activity will occur during a lane (0.0 - 1.0)
const ACTIVITY_CHANCE: float = 0.4

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

# Activity state
var activity: Activity = Activity.NONE      # Current activity
var _activity_done_this_lane: bool = false  # Only one activity per lane
var _activity_triggered: bool = false       # Has activity trigger been checked
var _activity_tween: Tween = null           # Tween for activity animations

# Lightspeed jump shader
var _lightspeed_shader: ShaderMaterial = null
var _original_material: Material = null
var _lightspeed_trail: ColorRect = null
var _original_sprite_scale: Vector2 = Vector2.ONE
const LIGHTSPEED_SHADER_PATH = "res://shaders/lightspeed_jump.gdshader"
const TRAIL_GRADIENT_SHADER = preload("res://shaders/lightspeed_trail.gdshader")

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
	
	# Calculate label width from original offsets
	if label_container:
		_label_width = label_container.offset_right - label_container.offset_left
	
	update_labels()

func _process(delta: float) -> void:
	time_alive += delta
	
	# Skip movement if activity is controlling speed
	if activity == Activity.NONE:
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
	
	# Check for random activity trigger (only once per lane, when no activity running)
	if not _activity_done_this_lane and activity == Activity.NONE:
		_check_activity_trigger()
	
	# Check if ship has exited screen (journey completed)
	if direction > 0 and position.x > viewport_width + spawn_margin:
		journey_completed.emit(self)
	elif direction < 0 and position.x < -spawn_margin:
		journey_completed.emit(self)


func _check_activity_trigger() -> void:
	"""Check if we should trigger a random activity based on journey progress."""
	var progress = _get_journey_progress()
	
	# Only check once we're past minimum progress
	if progress < 0.2:
		return
	
	# Random check (only do this once per valid range)
	if not _activity_triggered and progress >= 0.2 and progress <= 0.8:
		_activity_triggered = true
		if randf() < ACTIVITY_CHANCE:
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
				Activity.STOP_AND_GO:
					_start_activity_stop_and_go()
				Activity.LIGHT_SPEED_JUMP:
					_start_activity_light_speed_jump()
			return
	
	# Fallback
	_start_activity_stop_and_go()


func _start_activity_stop_and_go() -> void:
	"""StopAndGo activity: bring ship to halt, pause, then resume speed."""
	activity = Activity.STOP_AND_GO
	_activity_done_this_lane = true
	
	var original_speed = current_speed
	
	# Kill any existing tween
	if _activity_tween and _activity_tween.is_valid():
		_activity_tween.kill()
	
	_activity_tween = create_tween()
	
	# Phase 1: Decelerate to stop (0.8 seconds)
	_activity_tween.tween_property(self, "current_speed", 0.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	# Phase 2: Hold at stop (1.0-2.0 seconds random)
	var hold_time = randf_range(1.0, 2.0)
	_activity_tween.tween_interval(hold_time)
	
	# Phase 3: Accelerate back to original speed (1.0 seconds)
	_activity_tween.tween_property(self, "current_speed", original_speed, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	
	# Phase 4: Activity complete
	_activity_tween.tween_callback(_on_activity_complete)


func _start_activity_light_speed_jump() -> void:
	"""LightSpeedJump activity: ship glows, scales down, then rapidly jumps off-screen with a gradient trail."""
	activity = Activity.LIGHT_SPEED_JUMP
	_activity_done_this_lane = true
	
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
	
	# Create gradient trail ColorRect at jump start position
	_activity_tween.tween_callback(_create_gradient_trail.bind(jump_start_x, jump_target_x))
	
	# Phase 3: JUMP! Rapidly move to end of lane (0.25 seconds)
	_activity_tween.tween_property(self, "position:x", jump_target_x, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
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


func _create_gradient_trail(start_x: float, end_x: float) -> void:
	"""Create a ColorRect gradient trail from start to end position."""
	# Remove any existing trail
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail):
		_lightspeed_trail.queue_free()
	
	# Create ColorRect for trail
	_lightspeed_trail = ColorRect.new()
	
	# Calculate trail dimensions
	var trail_width = absf(end_x - start_x)
	var trail_height = 40.0 * layer_depth  # Height based on ship depth
	
	# Position trail at ship's Y, spanning from start to end
	var trail_x: float
	if direction > 0:
		trail_x = start_x
	else:
		trail_x = end_x
	
	_lightspeed_trail.position = Vector2(trail_x, position.y - trail_height / 2.0)
	_lightspeed_trail.size = Vector2(trail_width, trail_height)
	
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


func _fade_out_gradient_trail() -> void:
	"""Fade out and remove the gradient trail."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail):
		var trail_tween = create_tween()
		trail_tween.tween_method(_set_trail_opacity, 1.0, 0.0, 0.5)
		trail_tween.tween_callback(_remove_gradient_trail)


func _set_trail_opacity(value: float) -> void:
	"""Helper to set trail opacity via tween."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail) and _lightspeed_trail.material:
		_lightspeed_trail.material.set_shader_parameter("opacity", value)


func _remove_gradient_trail() -> void:
	"""Remove the gradient trail from the scene."""
	if _lightspeed_trail and is_instance_valid(_lightspeed_trail):
		_lightspeed_trail.queue_free()
		_lightspeed_trail = null


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


func _reset_activity_state() -> void:
	"""Reset activity state for a new lane."""
	activity = Activity.NONE
	_activity_done_this_lane = false
	_activity_triggered = false
	
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
	
	# Clean up any leftover trail
	_remove_gradient_trail()

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
