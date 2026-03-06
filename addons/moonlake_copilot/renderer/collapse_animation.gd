@tool
extends RefCounted

## CollapseAnimation
##
## Reusable collapse/expand animation utilities for renderers.
## Provides smooth height-based collapse animations.

const ANIMATION_DURATION: float = 0.2  # Seconds for collapse/expand animations

## Animate a control collapsing to a target height
## Args:
##   control: The Control node to animate
##   collapsed_height: Target height when collapsed (e.g., 40px)
##   content_to_hide: Optional Control to hide immediately (e.g., content container)
static func animate_collapse(control: Control, collapsed_height: float, content_to_hide: Control = null) -> void:
	"""Collapse control by shrinking height"""
	if content_to_hide:
		content_to_hide.visible = false

	var tween = control.create_tween()
	tween.tween_property(control, "custom_minimum_size:y", collapsed_height, ANIMATION_DURATION)
	await tween.finished

## Animate a control expanding to a target height
## Args:
##   control: The Control node to animate
##   expanded_height: Target height when expanded (e.g., 300px)
##   content_to_show: Optional Control to show after animation (e.g., content container)
static func animate_expand(control: Control, expanded_height: float, content_to_show: Control = null) -> void:
	"""Expand control by growing height"""
	var tween = control.create_tween()
	tween.tween_property(control, "custom_minimum_size:y", expanded_height, ANIMATION_DURATION)
	await tween.finished

	if content_to_show:
		content_to_show.visible = true

## Helper for collapsible widgets - captures current height and animates collapse
## Args:
##   control: The Control node to animate
##   collapsed_height: Target height when collapsed (e.g., 40px)
##   min_expanded_height: Minimum height to use for animation (e.g., 100px)
##   content_to_hide: Control to hide during collapse
static func collapse_widget(control: Control, collapsed_height: float, min_expanded_height: float, content_to_hide: Control) -> void:
	"""Capture current height, lock it, then animate collapse"""
	var current_height = max(control.size.y, min_expanded_height)
	control.custom_minimum_size.y = current_height
	await animate_collapse(control, collapsed_height, content_to_hide)

## Helper for expandable widgets - shows content and sets minimum height instantly
## Args:
##   control: The Control node
##   min_expanded_height: Minimum height when expanded (e.g., 100px)
##   content_to_show: Control to show during expand
static func expand_widget(control: Control, min_expanded_height: float, content_to_show: Control) -> void:
	"""Show content and set minimum height (instant, no animation)"""
	content_to_show.visible = true
	content_to_show.modulate.a = 1.0
	control.custom_minimum_size.y = min_expanded_height
