@tool
class_name SpaceshipExhaust
extends Node2D

## Spaceship Exhaust Effect
## A customizable animated engine exhaust trail

# Preset color schemes
enum ColorPreset {
	BLUE_PLASMA,      ## Classic blue sci-fi engine
	ORANGE_FLAME,     ## Hot orange/red exhaust
	GREEN_ION,        ## Green ion drive
	PURPLE_WARP,      ## Purple/pink warp drive
	WHITE_HOT,        ## Extremely hot white exhaust
	CUSTOM            ## Use custom colors
}

@export_group("Preset")
@export var color_preset: ColorPreset = ColorPreset.BLUE_PLASMA:
	set(value):
		color_preset = value
		_apply_preset()

@export_group("Colors")
@export var core_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		core_color = value
		_update_shader_param("core_color", value)

@export var mid_color: Color = Color(0.4, 0.7, 1.0, 1.0):
	set(value):
		mid_color = value
		_update_shader_param("mid_color", value)

@export var outer_color: Color = Color(0.1, 0.3, 0.9, 1.0):
	set(value):
		outer_color = value
		_update_shader_param("outer_color", value)

@export_range(0.5, 5.0) var color_falloff: float = 1.5:
	set(value):
		color_falloff = value
		_update_shader_param("color_falloff", value)

@export_group("Shape")
@export_range(0.1, 2.0) var exhaust_length: float = 1.0:
	set(value):
		exhaust_length = value
		_update_shader_param("exhaust_length", value)

@export_range(0.05, 1.0) var spread_start: float = 0.3:
	set(value):
		spread_start = value
		_update_shader_param("spread_start", value)

@export_range(0.0, 1.0) var spread_end: float = 0.6:
	set(value):
		spread_end = value
		_update_shader_param("spread_end", value)

@export_range(0.2, 3.0) var taper_curve: float = 1.2:
	set(value):
		taper_curve = value
		_update_shader_param("taper_curve", value)

@export_range(0.01, 0.5) var core_thickness: float = 0.15:
	set(value):
		core_thickness = value
		_update_shader_param("core_thickness", value)

@export_range(0.01, 1.0) var edge_softness: float = 0.3:
	set(value):
		edge_softness = value
		_update_shader_param("edge_softness", value)

@export_group("Animation")
@export_range(0.0, 10.0) var anim_speed: float = 2.0:
	set(value):
		anim_speed = value
		_update_shader_param("anim_speed", value)

@export_range(0.0, 1.0) var flicker_intensity: float = 0.15:
	set(value):
		flicker_intensity = value
		_update_shader_param("flicker_intensity", value)

@export_range(0.0, 20.0) var flicker_speed: float = 8.0:
	set(value):
		flicker_speed = value
		_update_shader_param("flicker_speed", value)

@export_range(0.0, 5.0) var flow_speed: float = 1.5:
	set(value):
		flow_speed = value
		_update_shader_param("flow_speed", value)

@export_group("Turbulence")
@export var enable_turbulence: bool = true:
	set(value):
		enable_turbulence = value
		_update_shader_param("enable_turbulence", value)

@export_range(0.0, 0.5) var turbulence_intensity: float = 0.08:
	set(value):
		turbulence_intensity = value
		_update_shader_param("turbulence_intensity", value)

@export_range(1.0, 20.0) var turbulence_scale: float = 6.0:
	set(value):
		turbulence_scale = value
		_update_shader_param("turbulence_scale", value)

@export_range(0.0, 5.0) var turbulence_speed: float = 1.0:
	set(value):
		turbulence_speed = value
		_update_shader_param("turbulence_speed", value)

@export_group("Advanced")
@export var flip_horizontal: bool = true:
	set(value):
		flip_horizontal = value
		_update_shader_param("flip_horizontal", value)

@export_range(0.0, 3.0) var intensity: float = 1.0:
	set(value):
		intensity = value
		_update_shader_param("intensity", value)

@export_range(0.0, 1.0) var tail_fade: float = 0.8:
	set(value):
		tail_fade = value
		_update_shader_param("tail_fade", value)

@export_range(0.0, 2.0) var hotspot_intensity: float = 0.5:
	set(value):
		hotspot_intensity = value
		_update_shader_param("hotspot_intensity", value)

@export_range(0.0, 0.5) var hotspot_size: float = 0.15:
	set(value):
		hotspot_size = value
		_update_shader_param("hotspot_size", value)

@export_group("Size")
@export var exhaust_size: Vector2 = Vector2(150, 40):
	set(value):
		exhaust_size = value
		_update_size()

@export var exhaust_offset: Vector2 = Vector2(-75, 0):
	set(value):
		exhaust_offset = value
		_update_position()

var _exhaust_sprite: Sprite2D
var _shader_material: ShaderMaterial
var _white_texture: GradientTexture2D


func _ready() -> void:
	_setup_exhaust()
	_apply_preset()


func _setup_exhaust() -> void:
	# Check if sprite already exists
	_exhaust_sprite = get_node_or_null("ExhaustSprite") as Sprite2D
	
	if not _exhaust_sprite:
		_exhaust_sprite = Sprite2D.new()
		_exhaust_sprite.name = "ExhaustSprite"
		add_child(_exhaust_sprite)
	
	# Create a simple white texture for the shader
	_white_texture = GradientTexture2D.new()
	_white_texture.width = 128
	_white_texture.height = 64
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)
	_white_texture.gradient = gradient
	_white_texture.fill = GradientTexture2D.FILL_LINEAR
	
	_exhaust_sprite.texture = _white_texture
	
	# Load and apply the shader
	var shader = load("res://shaders/spaceship_exhaust.gdshader") as Shader
	if shader:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
		_exhaust_sprite.material = _shader_material
	
	_update_size()
	_update_position()
	_sync_all_params()


func _update_size() -> void:
	if _exhaust_sprite:
		# Scale based on desired size vs texture size
		var tex_size := Vector2(128, 64)
		_exhaust_sprite.scale = exhaust_size / tex_size


func _update_position() -> void:
	if _exhaust_sprite:
		_exhaust_sprite.position = exhaust_offset


func _update_shader_param(param_name: String, value: Variant) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter(param_name, value)


func _sync_all_params() -> void:
	if not _shader_material:
		return
	
	_update_shader_param("core_color", core_color)
	_update_shader_param("mid_color", mid_color)
	_update_shader_param("outer_color", outer_color)
	_update_shader_param("color_falloff", color_falloff)
	_update_shader_param("exhaust_length", exhaust_length)
	_update_shader_param("spread_start", spread_start)
	_update_shader_param("spread_end", spread_end)
	_update_shader_param("taper_curve", taper_curve)
	_update_shader_param("core_thickness", core_thickness)
	_update_shader_param("edge_softness", edge_softness)
	_update_shader_param("anim_speed", anim_speed)
	_update_shader_param("flicker_intensity", flicker_intensity)
	_update_shader_param("flicker_speed", flicker_speed)
	_update_shader_param("flow_speed", flow_speed)
	_update_shader_param("enable_turbulence", enable_turbulence)
	_update_shader_param("turbulence_intensity", turbulence_intensity)
	_update_shader_param("turbulence_scale", turbulence_scale)
	_update_shader_param("turbulence_speed", turbulence_speed)
	_update_shader_param("intensity", intensity)
	_update_shader_param("tail_fade", tail_fade)
	_update_shader_param("hotspot_intensity", hotspot_intensity)
	_update_shader_param("hotspot_size", hotspot_size)
	_update_shader_param("flip_horizontal", flip_horizontal)


func _apply_preset() -> void:
	match color_preset:
		ColorPreset.BLUE_PLASMA:
			core_color = Color(1.0, 1.0, 1.0, 1.0)
			mid_color = Color(0.4, 0.7, 1.0, 1.0)
			outer_color = Color(0.1, 0.3, 0.9, 1.0)
		ColorPreset.ORANGE_FLAME:
			core_color = Color(1.0, 1.0, 0.9, 1.0)
			mid_color = Color(1.0, 0.6, 0.2, 1.0)
			outer_color = Color(0.8, 0.2, 0.05, 1.0)
		ColorPreset.GREEN_ION:
			core_color = Color(0.9, 1.0, 0.95, 1.0)
			mid_color = Color(0.3, 0.9, 0.5, 1.0)
			outer_color = Color(0.1, 0.6, 0.3, 1.0)
		ColorPreset.PURPLE_WARP:
			core_color = Color(1.0, 0.9, 1.0, 1.0)
			mid_color = Color(0.7, 0.3, 0.9, 1.0)
			outer_color = Color(0.4, 0.1, 0.6, 1.0)
		ColorPreset.WHITE_HOT:
			core_color = Color(1.0, 1.0, 1.0, 1.0)
			mid_color = Color(0.95, 0.95, 0.9, 1.0)
			outer_color = Color(0.8, 0.85, 0.9, 1.0)
		ColorPreset.CUSTOM:
			pass  # Keep current colors
	
	_sync_all_params()


## Set exhaust power (0 = off, 1 = normal, 2 = boost)
func set_power(power: float) -> void:
	intensity = clamp(power, 0.0, 3.0)
	
	# Scale other effects with power
	var power_factor: float = clamp(power, 0.5, 2.0)
	flicker_intensity = 0.15 * power_factor
	turbulence_intensity = 0.08 * power_factor


## Boost the exhaust temporarily (for acceleration effects)
func boost(duration: float = 0.5, boost_amount: float = 2.0) -> void:
	var original_intensity: float = intensity
	var original_length: float = exhaust_length
	
	intensity = boost_amount
	exhaust_length = exhaust_length * 1.3
	
	var tween: Tween = create_tween()
	tween.tween_property(self, "intensity", original_intensity, duration).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "exhaust_length", original_length, duration).set_ease(Tween.EASE_OUT)


## Turn off the exhaust with fade
func fade_out(duration: float = 0.3) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "intensity", 0.0, duration).set_ease(Tween.EASE_OUT)


## Turn on the exhaust with fade
func fade_in(duration: float = 0.3, target_intensity: float = 1.0) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "intensity", target_intensity, duration).set_ease(Tween.EASE_IN)
