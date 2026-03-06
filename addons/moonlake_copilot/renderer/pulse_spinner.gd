@tool
extends Control

## PulseSpinner
##
## Animated spinner for "running" status in todo lists and progress indicators.
## Rotates continuously while visible.

@export var spinner_size: float = 16.0
@export var rotation_speed: float = 3.0  # Radians per second

var current_rotation: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(spinner_size, spinner_size)
	size = Vector2(spinner_size, spinner_size)

func _process(delta: float) -> void:
	"""Rotate the spinner continuously"""
	if visible:
		current_rotation += rotation_speed * delta
		queue_redraw()  # Request redraw each frame

func _draw() -> void:
	"""Draw rotating spinner arc"""
	var center = Vector2(spinner_size / 2.0, spinner_size / 2.0)
	var radius = spinner_size / 2.0 - 2.0  # Slight padding
	var color = Color(0.5, 0.7, 1.0, 1.0)  # Light blue

	# Draw a circular arc (270 degrees)
	var arc_angle = PI * 1.5  # 270 degrees
	var start_angle = current_rotation
	var end_angle = start_angle + arc_angle

	# Draw arc as multiple line segments
	var segments = 16
	for i in range(segments):
		var t1 = float(i) / segments
		var t2 = float(i + 1) / segments
		var angle1 = start_angle + arc_angle * t1
		var angle2 = start_angle + arc_angle * t2

		var point1 = center + Vector2(cos(angle1), sin(angle1)) * radius
		var point2 = center + Vector2(cos(angle2), sin(angle2)) * radius

		draw_line(point1, point2, color, 2.0)
