@tool
extends RefCounted

## EphemeralRendererV2
##
## Renders ephemeral messages (e.g., "Thinking...") with animated gradient text effect.
## V2: Uses centralized styling, monospace font, and modern gradient animation.
##
## Visual design:
## - Animated gradient text (blue → purple → pink)
## - Monospace font (matches all other renderers)
## - Transparent background
## - Left-aligned, 70% max width
## - 80% opacity for subtlety

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

static func render(message: Dictionary) -> Control:
	"""
	Create ephemeral message widget with animated gradient text effect.

	Args:
		message: Message dictionary with ephemeral content

	Returns:
		EphemeralWidget control
	"""
	var widget = EphemeralWidget.new()
	widget.initialize(message)
	return widget


## EphemeralWidget - Control for ephemeral messages with gradient text animation
class EphemeralWidget extends PanelContainer:
	var label: Label
	var shader_material: ShaderMaterial
	var use_shader: bool = false
	var tween: Tween

	func _init() -> void:
		var min_height = int(ThemeConstants.spacing(30))
		custom_minimum_size = Vector2(0, min_height)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		add_theme_stylebox_override("panel", Styles.transparent_label())

		label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		ThemeConstants.apply_inter_font(label, ThemeConstants.Typography.FONT_SIZE_HEADER)
		label.add_theme_color_override("font_color", ThemeConstants.COLORS.TEXT_EPHEMERAL)
		label.modulate.a = ThemeConstants.COLORS.OPACITY_EPHEMERAL  # 80% opacity
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER  # Center vertically
		add_child(label)

		# Try to load gradient text shader
		_setup_gradient_effect()

	func _setup_gradient_effect() -> void:
		"""Setup animated gradient shader or fallback to Tween animation"""
		# Try to load gradient text shader
		var shader_path = "res://addons/moonlake_copilot/renderer/ephemeral_gradient_text.gdshader"
		var shader = load(shader_path)

		if shader == null:
			Log.warn("[EphemeralRendererV2] Failed to load gradient shader at %s, using Tween fallback" % shader_path)
			_use_tween_fallback()
			return

		# Test shader on temporary node (shader validation)
		var test_label = Label.new()
		test_label.material = ShaderMaterial.new()
		test_label.material.shader = shader

		# Check if shader compiled successfully
		if test_label.material.shader == null:
			Log.warn("[EphemeralRendererV2] Gradient shader compile error, using Tween fallback")
			test_label.queue_free()
			_use_tween_fallback()
			return

		test_label.queue_free()

		# Shader loaded successfully - apply to label
		shader_material = ShaderMaterial.new()
		shader_material.shader = shader

		shader_material.set_shader_parameter("gradient_color_1", ThemeConstants.COLORS.GRADIENT_1)
		shader_material.set_shader_parameter("gradient_color_2", ThemeConstants.COLORS.GRADIENT_2)
		shader_material.set_shader_parameter("gradient_color_3", ThemeConstants.COLORS.GRADIENT_3)
		shader_material.set_shader_parameter("animation_speed", 1.0)  # 1.0 second cycle (faster)
		shader_material.set_shader_parameter("gradient_width", 3.0)  # 300% width

		label.material = shader_material
		use_shader = true

	func _use_tween_fallback() -> void:
		"""Fallback animation using Tween (pulse alpha 0.6 → 1.0)"""
		use_shader = false

		tween = create_tween()
		tween.set_loops()
		tween.tween_property(label, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func initialize(message: Dictionary) -> void:
		"""Initialize widget with message data"""

		var content = message.get("content", {})
		var message_text = content.get("message", "Thinking...")

		label.text = message_text

	func _process(_delta: float) -> void:
		pass

	func _exit_tree() -> void:
		if tween and tween.is_valid():
			tween.kill()
