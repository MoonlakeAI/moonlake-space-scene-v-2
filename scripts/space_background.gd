extends CanvasLayer

## Space Background Controller
## Dark background with flickering stars and spinning galaxy

@onready var background_rect: ColorRect = $BackgroundRect
@onready var galaxy_sprite: Sprite2D = $GalaxySprite

var material: ShaderMaterial

@export var galaxy_rotation_speed: float = 0.02  # Radians per second

func _ready() -> void:
	material = background_rect.material as ShaderMaterial
	
	# Center galaxy in viewport
	var viewport_size = get_viewport().get_visible_rect().size
	if galaxy_sprite:
		galaxy_sprite.position = viewport_size * 0.5
		galaxy_sprite.position.y *= 0.6  # Slightly above center

func _process(delta: float) -> void:
	# Slowly spin the galaxy
	if galaxy_sprite:
		galaxy_sprite.rotation += galaxy_rotation_speed * delta

# ========== STAR CONTROLS ==========

func set_star_density(density: float) -> void:
	if material:
		material.set_shader_parameter("star_density", density)

func set_star_brightness(brightness: float) -> void:
	if material:
		material.set_shader_parameter("star_brightness", brightness)

func set_star_flicker_speed(speed: float) -> void:
	if material:
		material.set_shader_parameter("star_flicker_speed", speed)

# ========== GALAXY CONTROLS ==========

func set_galaxy_rotation_speed(speed: float) -> void:
	galaxy_rotation_speed = speed

func set_galaxy_scale(scale_value: float) -> void:
	if galaxy_sprite:
		galaxy_sprite.scale = Vector2(scale_value, scale_value)

func set_galaxy_opacity(opacity: float) -> void:
	if galaxy_sprite:
		galaxy_sprite.modulate.a = opacity

func set_galaxy_position(pos: Vector2) -> void:
	if galaxy_sprite:
		galaxy_sprite.position = pos

# ========== BACKGROUND COLOR ==========

func set_background_color(color: Color) -> void:
	if material:
		material.set_shader_parameter("background_color", color)
