extends Camera3D

## Orbit camera controller for scene viewing
## Auto-rotates around center with mouse controls for manual orbit and zoom

@export var target_position: Vector3 = Vector3.ZERO
@export var orbit_distance: float = 180.0
@export var min_distance: float = 50.0
@export var max_distance: float = 350.0
@export var auto_rotate_speed: float = 0.2
@export var mouse_sensitivity: float = 0.005
@export var zoom_speed: float = 10.0
@export var min_pitch: float = -80.0
@export var max_pitch: float = 80.0

var yaw: float = 0.0
var pitch: float = -30.0
var is_dragging: bool = false
var auto_rotate: bool = true

func _ready() -> void:
	# Start positioned to view the scene nicely
	yaw = 45.0
	pitch = -35.0
	_update_camera_position()

func _process(delta: float) -> void:
	if auto_rotate and not is_dragging:
		yaw += auto_rotate_speed * delta * 60.0
	_update_camera_position()

func _input(event: InputEvent) -> void:
	# Mouse button handling
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = mouse_event.pressed
			if mouse_event.pressed:
				auto_rotate = false
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed:
				auto_rotate = true
		# Zoom with scroll wheel
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = max(min_distance, orbit_distance - zoom_speed)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = min(max_distance, orbit_distance + zoom_speed)
	
	# Mouse motion for orbiting
	if event is InputEventMouseMotion and is_dragging:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity * 60.0
		pitch -= motion.relative.y * mouse_sensitivity * 60.0
		pitch = clamp(pitch, min_pitch, max_pitch)

func _update_camera_position() -> void:
	var pitch_rad := deg_to_rad(pitch)
	var yaw_rad := deg_to_rad(yaw)
	
	var offset := Vector3(
		orbit_distance * cos(pitch_rad) * sin(yaw_rad),
		orbit_distance * sin(-pitch_rad),
		orbit_distance * cos(pitch_rad) * cos(yaw_rad)
	)
	
	global_position = target_position + offset
	look_at(target_position)
