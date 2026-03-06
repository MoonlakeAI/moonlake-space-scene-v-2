extends MeshInstance3D

## Cloud layer that rotates slightly faster than the planet
## Creates the effect of clouds drifting over the surface

@export var rotation_speed: float = 0.001  # Slightly faster than planet (0.005)

func _process(delta: float) -> void:
	rotate_x(rotation_speed * delta *0.5)
