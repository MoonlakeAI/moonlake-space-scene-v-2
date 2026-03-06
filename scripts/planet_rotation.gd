extends MeshInstance3D

## Slowly rotates the planet about the X axis towards the camera
## Rotation is very slow for a realistic planetary rotation feel

@export var rotation_speed: float = 0.005  # Radians per second (extremely slow, realistic)

func _process(delta: float) -> void:
	# Rotate around the X axis (tilted towards camera)
	rotate_x(rotation_speed * delta)
