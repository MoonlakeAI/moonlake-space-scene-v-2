@tool
extends RefCounted

## Empty State Controller - Manages typewriter effect for empty state prompts
##
## Responsibilities:
## - Typewriter animation (character-by-character typing)
## - Prompt cycling with fade transitions
## - Empty state visibility management

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")

# UI References (set externally)
var typewriter_label: Label = null
var typewriter_timer: Timer = null
var empty_state_center: Control = null
var parent_node: Node = null  # For create_tween

# Typewriter state
var typewriter_text: String = ""
var typewriter_index: int = 0
var current_prompt_index: int = 0

# Prompt texts (70% 3D, 30% 2D)
var typewriter_prompts: Array = [
	"Create a 3D open world RPG with fantasy characters, magic spells, and epic quests...",
	"Build a 3D first-person dungeon crawler with procedural levels and loot systems...",
	"Design a 3D space exploration game with planets, aliens, and spaceship combat...",
	"Make a 3D character with unique animations, special abilities, and customizable outfits...",
	"Create a 3D racing game with futuristic tracks, boost mechanics, and destructible environments...",
	"Build a 2D platformer with pixel art sprites, wall jumps, and retro music...",
	"Design 2D character sprites with walk cycles, attack animations, and idle poses...",
	"Create a 2D side-scrolling adventure with hand-drawn environments and puzzle mechanics..."
]


func initialize(label: Label, timer: Timer, empty_state: Control, parent: Node) -> void:
	"""Initialize with UI references"""
	typewriter_label = label
	typewriter_timer = timer
	empty_state_center = empty_state
	parent_node = parent

	# Connect timer signal
	if typewriter_timer:
		typewriter_timer.timeout.connect(_on_typewriter_tick)


func start_typewriter_effect() -> void:
	"""Start the typewriter effect animation"""
	start_next_prompt()


func stop_typewriter_effect() -> void:
	"""Stop the typewriter effect animation"""
	if typewriter_timer:
		typewriter_timer.stop()


func show_empty_state() -> void:
	"""Show empty state and start typewriter"""
	if empty_state_center:
		empty_state_center.visible = true
	start_typewriter_effect()


func hide_empty_state() -> void:
	"""Hide empty state and stop typewriter"""
	if empty_state_center:
		empty_state_center.visible = false
	stop_typewriter_effect()


## ============================================================================
## Typewriter Effect
## ============================================================================

func start_next_prompt() -> void:
	"""Start typing the next prompt"""
	if typewriter_prompts.is_empty():
		return

	typewriter_text = typewriter_prompts[current_prompt_index]
	typewriter_index = 0
	if typewriter_label:
		typewriter_label.text = ""
	if typewriter_timer:
		typewriter_timer.start()


func _on_typewriter_tick() -> void:
	"""Type one character at a time"""
	if typewriter_index < typewriter_text.length():
		if typewriter_label:
			typewriter_label.text += typewriter_text[typewriter_index]
		typewriter_index += 1
	else:
		# Finished typing, pause then move to next prompt
		if typewriter_timer:
			typewriter_timer.stop()

		# Wait for pause duration
		if parent_node:
			await parent_node.get_tree().create_timer(AnimationConstants.EMPTY_STATE_PAUSE_DURATION).timeout
			# Fade out effect
			_fade_out_prompt()


func _fade_out_prompt() -> void:
	"""Fade out the current prompt and start the next one"""
	if not parent_node or not typewriter_label:
		return

	var tween = parent_node.create_tween()
	tween.tween_property(typewriter_label, "modulate:a", 0.0, AnimationConstants.EMPTY_STATE_FADE_DURATION)
	await tween.finished

	# Move to next prompt
	current_prompt_index = (current_prompt_index + 1) % typewriter_prompts.size()

	# Reset opacity and start next prompt
	typewriter_label.modulate.a = 1.0
	start_next_prompt()
