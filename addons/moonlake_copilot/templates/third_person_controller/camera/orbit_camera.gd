extends Camera3D
class_name OrbitCamera

@export_group("Mouse")
@export var capture_mouse_on_start: bool = true
@export var toggle_mouse_on_ui_cancel: bool = true

@export var target_path: NodePath
@export var distance: float = 3.0
@export var height_offset: float = 2.0
@export var target_offset: Vector3 = Vector3(0, 1.0, 0)

@export_group("Sensitivity")
@export var mouse_sensitivity: float = 0.003
@export var stick_sensitivity: float = 3.0
@export_range(-89.0, 0.0) var pitch_min_degrees: float = -60.0
@export_range(0.0, 89.0) var pitch_max_degrees: float = 30.0

@export_group("Smoothing")
@export var follow_smoothing: float = 12.0
@export var rotation_smoothing: float = 15.0

var _target: Node3D
var _yaw: float = 0.0
var _pitch: float = -0.2


func _ready() -> void:
	if target_path:
		_target = get_node(target_path) as Node3D
	if capture_mouse_on_start:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if not toggle_mouse_on_ui_cancel:
		return
	if event.is_action_pressed(&"ui_cancel"):
		var next := Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(next)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch -= motion.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_degrees), deg_to_rad(pitch_max_degrees))


func _physics_process(delta: float) -> void:
	if not _target:
		return
	
	_apply_stick_look(delta)
	
	var pivot_point: Vector3 = _target.global_position + Vector3(0, height_offset, 0)
	var look_target: Vector3 = _target.global_position + target_offset
	
	var offset: Vector3 = Vector3.BACK * distance
	offset = offset.rotated(Vector3.RIGHT, _pitch)
	offset = offset.rotated(Vector3.UP, _yaw)
	
	var desired_position: Vector3 = pivot_point + offset
	global_position = global_position.lerp(desired_position, follow_smoothing * delta)
	
	var desired_basis: Basis = Basis.looking_at(look_target - global_position, Vector3.UP)
	basis = basis.slerp(desired_basis, rotation_smoothing * delta)


func _apply_stick_look(delta: float) -> void:
	var stick_x := 0.0
	var stick_y := 0.0
	if InputMap.has_action(&"look_right"):
		stick_x = Input.get_action_strength(&"look_right") - Input.get_action_strength(&"look_left")
	if InputMap.has_action(&"look_down"):
		stick_y = Input.get_action_strength(&"look_down") - Input.get_action_strength(&"look_up")
	if abs(stick_x) > 0.1 or abs(stick_y) > 0.1:
		_yaw -= stick_x * stick_sensitivity * delta
		_pitch -= stick_y * stick_sensitivity * delta
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_degrees), deg_to_rad(pitch_max_degrees))
