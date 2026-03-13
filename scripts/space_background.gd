extends CanvasLayer

## Space Background Controller
## Dark background with flickering stars and spinning galaxy

@onready var background_rect: ColorRect = $BackgroundRect
@onready var galaxy_sprite: Sprite2D = $GalaxySprite

var material: ShaderMaterial

@export var galaxy_rotation_speed: float = 0.02  # Radians per second

func _ready() -> void:
	material = background_rect.material as ShaderMaterial
	
	# Set screen size for aspect ratio correction
	var viewport_size = get_viewport().get_visible_rect().size
	if material:
		material.set_shader_parameter("screen_size", viewport_size)
	
	# Center galaxy in viewport
	if galaxy_sprite:
		galaxy_sprite.position = viewport_size * 0.95
		galaxy_sprite.position.y *= 0.3  # Slightly above center
		galaxy_sprite.scale.x = 0.3
		galaxy_sprite.scale.y = 0.3
	
	# Update screen size when viewport resizes
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	if material:
		material.set_shader_parameter("screen_size", viewport_size)
		
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
		material.set_shader_parameter("flicker_speed", speed)

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

# ========== BACKGROUND COLOR & OPACITY ==========

func set_background_color(color: Color) -> void:
	if material:
		material.set_shader_parameter("background_color", color)

func set_opacity(value: float) -> void:
	"""Set overall opacity of the space background (0.0 to 1.0)"""
	if material:
		material.set_shader_parameter("opacity", clampf(value, 0.0, 1.0))

func get_opacity() -> float:
	"""Get current opacity value"""
	if material:
		return material.get_shader_parameter("opacity")
	return 1.0

func fade_opacity(target: float, duration: float) -> void:
	"""Smoothly fade opacity to target value over duration seconds"""
	var tween = create_tween()
	var current = get_opacity()
	tween.tween_method(set_opacity, current, clampf(target, 0.0, 1.0), duration)
