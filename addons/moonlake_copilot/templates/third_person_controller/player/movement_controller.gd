extends CharacterBody3D
class_name MovementController

@export_group("Nodes")
@export var visuals_path: NodePath = NodePath("Visuals")
@export var animation_tree_path: NodePath = NodePath("Visuals/AnimationTree")
@export var animation_controller_path: NodePath = NodePath("AnimationController")

@export_group("Camera")
@export var enable_camera_relative: bool = true

@export_group("Movement")
@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var acceleration: float = 12.0
@export var air_acceleration: float = 4.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 28.0
@export var max_fall_speed: float = 54.0
@export var rotation_speed: float = 12.0

var _visuals: Node3D
var _animation_tree: AnimationTree
var _animation_controller: Node  # AnimationController


func _ready() -> void:
	_visuals = get_node_or_null(visuals_path) as Node3D
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_animation_controller = get_node_or_null(animation_controller_path)
	if _animation_controller and _animation_tree:
		_animation_controller.initialize(_animation_tree)


func _physics_process(delta: float) -> void:
	var move_axis := _read_move_axis()
	var input_direction := _get_input_direction(move_axis)
	var is_sprinting := _is_sprinting()
	_handle_jump_request()

	velocity = _compute_velocity(velocity, input_direction, is_sprinting, delta)
	move_and_slide()

	if _animation_controller:
		_animation_controller.update_locomotion(is_on_floor(), velocity, is_sprinting, delta)


func _get_input_direction(move_axis: Vector2) -> Vector3:
	var raw := Vector3(move_axis.x, 0.0, move_axis.y)
	if enable_camera_relative:
		return _get_camera_relative_direction(raw).normalized()
	return raw.normalized()


func _read_move_axis() -> Vector2:
	var axis := Vector2.ZERO
	if Input.is_action_pressed(&"move_left"):
		axis.x -= 1.0
	if Input.is_action_pressed(&"move_right"):
		axis.x += 1.0
	if Input.is_action_pressed(&"move_forward"):
		axis.y -= 1.0
	if Input.is_action_pressed(&"move_back"):
		axis.y += 1.0
	return axis.limit_length(1.0)


func _is_sprinting() -> bool:
	return InputMap.has_action(&"sprint") and Input.is_action_pressed(&"sprint")


func _handle_jump_request() -> void:
	if not InputMap.has_action(&"jump"):
		return
	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = jump_velocity


func _compute_velocity(
	current_velocity: Vector3,
	input_direction: Vector3,
	is_sprinting: bool,
	delta: float
) -> Vector3:
	var v := current_velocity
	v = _apply_horizontal_movement(v, input_direction, is_sprinting, delta)
	v = _apply_gravity(v, delta)
	_apply_rotation(input_direction, delta)
	return v


func _apply_horizontal_movement(
	v: Vector3,
	input_direction: Vector3,
	is_sprinting: bool,
	delta: float
) -> Vector3:
	var base_speed := sprint_speed if is_sprinting else move_speed
	var desired_velocity := input_direction * base_speed

	var base_accel := acceleration if is_on_floor() else air_acceleration
	v.x = move_toward(v.x, desired_velocity.x, base_accel * delta)
	v.z = move_toward(v.z, desired_velocity.z, base_accel * delta)
	return v


func _apply_gravity(v: Vector3, delta: float) -> Vector3:
	if is_on_floor():
		return v
	v.y = clamp(v.y - gravity * delta, -max_fall_speed, max_fall_speed)
	return v


func _apply_rotation(input_direction: Vector3, delta: float) -> void:
	if not _visuals:
		return
	if input_direction.length_squared() <= 0.01:
		return

	var target_rotation := atan2(input_direction.x, input_direction.z)
	var current_rotation := _visuals.rotation.y
	_visuals.rotation.y = lerp_angle(current_rotation, target_rotation, rotation_speed * delta)


func _get_camera_relative_direction(raw_input: Vector3) -> Vector3:
	var viewport := get_viewport()
	if not viewport:
		return raw_input

	var camera := viewport.get_camera_3d()
	if not camera:
		return raw_input

	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x

	forward.y = 0.0
	right.y = 0.0

	forward = forward.normalized()
	right = right.normalized()

	return (forward * -raw_input.z) + (right * raw_input.x)
