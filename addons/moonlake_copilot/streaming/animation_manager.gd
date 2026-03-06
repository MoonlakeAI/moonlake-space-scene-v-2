@tool
extends RefCounted
class_name AnimationManager

## Animation control for message widgets
## Manages typewriter animations and message collapsing

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")

# UI references
var message_container: VBoxContainer
var message_cache: Dictionary  # message_id -> Control node
var message_order: Array  # Array of message_ids in order


func _init(container: VBoxContainer, cache: Dictionary, order: Array):
	message_container = container
	message_cache = cache
	message_order = order


func finish_all_animations() -> void:
	"""Finish all ongoing typewriter animations in message widgets"""
	for child in message_container.get_children():
		# Unwrap MarginContainer wrapper
		var widget = child
		if child is MarginContainer and child.get_child_count() > 0:
			widget = child.get_child(0)

		# Unwrap HBoxContainer (for user messages)
		if widget is HBoxContainer and widget.get_child_count() > 1:
			widget = widget.get_child(1)

		# Call finish_animation if available
		if widget.has_method("finish_animation"):
			widget.finish_animation()


func collapse_previous_last_message() -> void:
	"""Collapse the previous last collapsible message when a new one is added."""
	if message_order.size() == 0:
		return

	# Get the last message widget
	var last_message_id = message_order[-1]
	if not message_cache.has(last_message_id):
		return

	var last_widget = message_cache[last_message_id]

	# Unwrap the widget to find the actual collapsible widget
	# All widgets are wrapped in MarginContainer by _wrap_message_with_max_width
	var target_widget = last_widget

	# Unwrap MarginContainer (from _wrap_message_with_max_width)
	if last_widget is MarginContainer and last_widget.get_child_count() > 0:
		target_widget = last_widget.get_child(0)

	# Unwrap HBoxContainer (for user messages)
	if target_widget is HBoxContainer and target_widget.get_child_count() > 1:
		# User message wrapper - get the actual widget (second child after spacer)
		target_widget = target_widget.get_child(1)

	# Finish any ongoing typewriter animation
	if target_widget.has_method("finish_animation"):
		target_widget.finish_animation()

	# Call collapse_if_expanded if the method exists
	# This will respect MIN_EXPAND_DURATION, so the widget stays open for at least 2 seconds
	if target_widget.has_method("collapse_if_expanded"):
		# Try to collapse immediately (respects minimum duration)
		target_widget.collapse_if_expanded()

		# If it didn't collapse yet (too soon), schedule a delayed collapse
		# Check if widget is still expanded after trying to collapse
		var is_expanded = target_widget.get("is_expanded")
		if is_expanded != null and is_expanded:
			# Calculate remaining time until MIN_EXPAND_DURATION is reached
			var expand_time = target_widget.get("expand_time")
			if expand_time != null:
				var current_time = Time.get_ticks_msec() / 1000.0
				var elapsed = current_time - expand_time
				var remaining = AnimationConstants.MIN_EXPAND_DURATION - elapsed

				# Schedule collapse after remaining time
				if remaining > 0:
					await _get_tree_from_container().create_timer(remaining + 0.1).timeout
					if is_instance_valid(target_widget) and target_widget.has_method("collapse_if_expanded"):
						# Force collapse after waiting - we already waited for MIN_EXPAND_DURATION
						target_widget.collapse_if_expanded(true)


func _get_tree_from_container() -> SceneTree:
	"""Helper to get SceneTree from message_container"""
	if message_container and is_instance_valid(message_container):
		return message_container.get_tree()
	return Engine.get_main_loop()
