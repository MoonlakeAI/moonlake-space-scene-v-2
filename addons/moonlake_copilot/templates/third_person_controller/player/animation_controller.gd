extends Node
class_name AnimationController

signal action_started(anim_name: StringName)
signal action_finished(anim_name: StringName)
signal hit_frame_triggered(anim_name: StringName, index: int)
signal cancel_window_opened(anim_name: StringName)
signal cancel_window_closed(anim_name: StringName)

@export var idle_state: StringName = &"Idle"
@export var walk_state: StringName = &"Walk"
@export var run_state: StringName = &"Run"
@export var jump_state: StringName = &"Jump"
@export var fall_state: StringName = &"Fall"
@export var land_state: StringName = &"Land"

var _animation_tree: AnimationTree
var _animation_player: AnimationPlayer
var _state_machine: AnimationNodeStateMachinePlayback
var _current_state: StringName = StringName()
var _current_action: StringName = StringName()
var _is_playing_action: bool = false
var _can_cancel: bool = false
var _was_airborne: bool = false
var _land_grace_timer: float = 0.0

const LAND_GRACE_DURATION: float = 0.15


func initialize(animation_tree: AnimationTree) -> void:
	_animation_tree = animation_tree
	if _animation_tree:
		_animation_tree.active = true
		_state_machine = _animation_tree.get("parameters/playback")
		
		var anim_player_path := _animation_tree.anim_player
		if anim_player_path:
			_animation_player = _animation_tree.get_node(anim_player_path) as AnimationPlayer
		
		if _animation_player:
			_animation_player.animation_finished.connect(_on_animation_finished)
		
		if _state_machine:
			_state_machine.start(idle_state)
			_current_state = idle_state


func update_locomotion(is_on_floor: bool, velocity: Vector3, is_sprinting: bool, delta: float = 0.0) -> void:
	if _is_playing_action:
		return
	
	_sync_current_state()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	
	if _land_grace_timer > 0.0:
		_land_grace_timer -= delta
	
	if _was_airborne and is_on_floor:
		_was_airborne = false
		_land_grace_timer = LAND_GRACE_DURATION
		_travel_to(land_state)
		return
	
	if _current_state == land_state:
		if is_on_floor:
			_was_airborne = false
			return
		_was_airborne = true
		_travel_to(fall_state)
		return
	
	var in_grace_period := _land_grace_timer > 0.0 and is_on_floor
	if in_grace_period:
		_was_airborne = false
	else:
		_was_airborne = not is_on_floor
	
	if not is_on_floor:
		var airborne := jump_state if velocity.y > 0.0 else fall_state
		_travel_to(airborne)
		return
	
	if horizontal_speed < 0.1:
		_travel_to(idle_state)
		return
	
	var move_state := run_state if is_sprinting else walk_state
	_travel_to(move_state)


func play_action(anim_name: StringName, _lock_movement: bool = true) -> bool:
	if not _state_machine:
		return false
	
	if not _has_state(anim_name):
		push_warning("AnimationController: State '%s' not found in state machine" % anim_name)
		return false
	
	_is_playing_action = true
	_current_action = anim_name
	_can_cancel = false
	_travel_to(anim_name)
	action_started.emit(anim_name)
	return true


func stop_action() -> void:
	if _is_playing_action:
		_is_playing_action = false
		_can_cancel = false
		var finished := _current_action
		_current_action = StringName()
		action_finished.emit(finished)


func cancel_action() -> void:
	if _is_playing_action and _can_cancel:
		stop_action()


func force_stop_action() -> void:
	if _is_playing_action:
		stop_action()


func is_playing_action() -> bool:
	return _is_playing_action


func get_current_action() -> StringName:
	return _current_action


func can_cancel_current_action() -> bool:
	return _is_playing_action and _can_cancel


func on_hit_frame(index: int = 0) -> void:
	if _is_playing_action:
		hit_frame_triggered.emit(_current_action, index)


func on_cancel_window_open() -> void:
	if _is_playing_action:
		_can_cancel = true
		cancel_window_opened.emit(_current_action)


func on_cancel_window_close() -> void:
	if _is_playing_action:
		_can_cancel = false
		cancel_window_closed.emit(_current_action)


func _travel_to(state_name: StringName) -> void:
	if _current_state == state_name:
		return
	if _state_machine:
		_state_machine.travel(state_name)
		_current_state = state_name


func _sync_current_state() -> void:
	if _state_machine:
		_current_state = _state_machine.get_current_node()


func _has_state(state_name: StringName) -> bool:
	if not _state_machine:
		return false
	var tree_root := _animation_tree.tree_root as AnimationNodeStateMachine
	if not tree_root:
		return false
	return tree_root.has_node(state_name)


func _on_animation_finished(anim_name: StringName) -> void:
	var clean_name := _strip_library_prefix(anim_name)
	if _is_playing_action and clean_name == _current_action:
		stop_action()


func _strip_library_prefix(anim_name: StringName) -> StringName:
	var name_str := String(anim_name)
	var slash_idx := name_str.find("/")
	if slash_idx >= 0:
		return StringName(name_str.substr(slash_idx + 1))
	return anim_name
