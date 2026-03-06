@tool
extends RefCounted
class_name PlayerInputConfig

enum GameType {
	THIRD_PERSON_ACTION,
	PLATFORMER_2D,
}

const BASE_MOVEMENT = {
	"move_forward": {
		"keys": [KEY_W, KEY_UP],
		"joy_axis": [JOY_AXIS_LEFT_Y, -1.0],
	},
	"move_back": {
		"keys": [KEY_S, KEY_DOWN],
		"joy_axis": [JOY_AXIS_LEFT_Y, 1.0],
	},
	"move_left": {
		"keys": [KEY_A, KEY_LEFT],
		"joy_axis": [JOY_AXIS_LEFT_X, -1.0],
	},
	"move_right": {
		"keys": [KEY_D, KEY_RIGHT],
		"joy_axis": [JOY_AXIS_LEFT_X, 1.0],
	},
}

const ACTION_JUMP = {
	"jump": {
		"keys": [KEY_SPACE],
		"joy_buttons": [JOY_BUTTON_A],
	},
}

const ACTION_SPRINT = {
	"sprint": {
		"keys": [KEY_SHIFT],
		"joy_buttons": [JOY_BUTTON_B],
	},
}

const CAMERA_LOOK = {
	"look_right": {
		"joy_axis": [JOY_AXIS_RIGHT_X, 1.0],
	},
	"look_left": {
		"joy_axis": [JOY_AXIS_RIGHT_X, -1.0],
	},
	"look_down": {
		"joy_axis": [JOY_AXIS_RIGHT_Y, 1.0],
	},
	"look_up": {
		"joy_axis": [JOY_AXIS_RIGHT_Y, -1.0],
	},
}

const PRESETS = {
	GameType.THIRD_PERSON_ACTION: [BASE_MOVEMENT, ACTION_JUMP, ACTION_SPRINT, CAMERA_LOOK],
	GameType.PLATFORMER_2D: [BASE_MOVEMENT, ACTION_JUMP, ACTION_SPRINT],
}


static func setup_for_game_type(game_type: GameType) -> int:
	var action_sets: Array = PRESETS.get(game_type, [])
	var merged_actions := {}
	
	for action_set in action_sets:
		merged_actions.merge(action_set)
	
	return _apply_input_actions(merged_actions)


static func _apply_input_actions(actions: Dictionary) -> int:
	var added_count := 0
	
	for action_name in actions:
		var setting_path = "input/%s" % action_name
		if ProjectSettings.has_setting(setting_path):
			continue
		
		var events: Array = []
		var config = actions[action_name]
		
		if config.has("keys"):
			for keycode in config["keys"]:
				events.append(_create_key_event(keycode))
		
		if config.has("joy_axis"):
			var axis_data = config["joy_axis"]
			events.append(_create_joypad_motion_event(axis_data[0], axis_data[1]))
		
		if config.has("joy_buttons"):
			for button in config["joy_buttons"]:
				events.append(_create_joypad_button_event(button))
		
		ProjectSettings.set_setting(setting_path, {
			"deadzone": 0.5,
			"events": events
		})
		added_count += 1
		Log.info("[PlayerInputConfig] Added: %s" % action_name)
	
	if added_count > 0:
		ProjectSettings.save()
		Log.info("[PlayerInputConfig] Saved %d new input actions" % added_count)
	
	return added_count


static func _create_key_event(keycode: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = keycode
	return event


static func _create_joypad_motion_event(axis: int, axis_value: float) -> InputEventJoypadMotion:
	var event = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	return event


static func _create_joypad_button_event(button: int) -> InputEventJoypadButton:
	var event = InputEventJoypadButton.new()
	event.button_index = button
	return event
