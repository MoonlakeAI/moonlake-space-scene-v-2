extends PanelContainer

## Debug Panel - Reads/writes settings from debug_settings.json
## Displays configurable values on top right of screen
## Supports grouped settings (nested dictionaries)

const SETTINGS_PATH := "res://debug_settings.json"

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/Title
@onready var save_button: Button = $MarginContainer/VBoxContainer/TitleRow/SaveButton
@onready var settings_container: VBoxContainer = $MarginContainer/VBoxContainer/SettingsContainer

# References to other nodes (set after scene is ready)
var _spaceship_traffic: Node = null
var _preview_spaceship: Node = null

var _settings: Dictionary = {}
var _controls: Dictionary = {}  # Maps "group.key" to their input controls
var _original_types: Dictionary = {}  # Tracks original types for proper save (int vs float)


func _ready() -> void:
	save_button.pressed.connect(_on_save_pressed)
	
	# Get reference to spaceship traffic (deferred to ensure scene is ready)
	call_deferred("_setup_references")
	
	_load_settings()
	_build_ui()
	_apply_all_settings()


func _setup_references() -> void:
	"""Setup references to other nodes in the scene."""
	# Find spaceship traffic node
	var root = get_tree().current_scene
	if root:
		_spaceship_traffic = root.get_node_or_null("SpaceshipTraffic")
		if _spaceship_traffic:
			print("[DebugPanel] Found SpaceshipTraffic")
		
		# Find preview spaceship node
		var preview_layer = root.get_node_or_null("PreviewLayer")
		if preview_layer:
			_preview_spaceship = preview_layer.get_node_or_null("PreviewSpaceship")
			if _preview_spaceship:
				print("[DebugPanel] Found PreviewSpaceship")


func _load_settings() -> void:
	"""Load settings from JSON file."""
	if not FileAccess.file_exists(SETTINGS_PATH):
		print("[DebugPanel] Settings file not found, using defaults")
		_settings = {}
		return
	
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		push_warning("[DebugPanel] Failed to open settings file")
		_settings = {}
		return
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_warning("[DebugPanel] Failed to parse JSON: %s" % json.get_error_message())
		_settings = {}
		return
	
	_settings = json.data if json.data is Dictionary else {}
	print("[DebugPanel] Loaded settings: %s" % str(_settings))


func _save_settings() -> void:
	"""Save current settings to JSON file."""
	# Update settings from UI controls
	for control_key in _controls:
		var control = _controls[control_key]
		var parts = control_key.split(".")
		
		var value: Variant
		if control is SpinBox:
			# Preserve original type (int vs float)
			if _original_types.get(control_key) == "int":
				value = int(control.value)
			else:
				value = control.value
		elif control is CheckBox:
			value = control.button_pressed
		elif control is LineEdit:
			value = control.text
		elif control is ColorPickerButton:
			var c: Color = control.color
			value = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
		else:
			continue
		
		# Handle nested keys (group.setting)
		if parts.size() == 2:
			var group = parts[0]
			var key = parts[1]
			if not _settings.has(group):
				_settings[group] = {}
			_settings[group][key] = value
		else:
			_settings[control_key] = value
	
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if not file:
		push_warning("[DebugPanel] Failed to save settings")
		return
	
	file.store_string(JSON.stringify(_settings, "\t"))
	file.close()
	print("[DebugPanel] Saved settings")
	
	# Visual feedback
	_flash_save_button()


func _build_ui() -> void:
	"""Build UI controls for each setting."""
	# Clear existing controls
	for child in settings_container.get_children():
		child.queue_free()
	_controls.clear()
	
	# Create controls for each setting/group
	for key in _settings:
		var value = _settings[key]
		
		if value is Dictionary and not value.has("r"):
			# This is a group (not a color)
			_create_group(key, value)
		else:
			# Top-level setting
			var row := _create_setting_row(key, key, value)
			if row:
				settings_container.add_child(row)


func _create_group(group_name: String, group_settings: Dictionary) -> void:
	"""Create a collapsible group with header and settings."""
	# Group header button (acts as collapse/expand toggle)
	var header_btn := Button.new()
	header_btn.text = "v " + group_name.capitalize().replace("_", " ")
	header_btn.flat = true
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.add_theme_font_size_override("font_size", 12)
	header_btn.add_theme_color_override("font_color", Color(0.4, 0.85, 0.95, 1.0))
	header_btn.add_theme_color_override("font_hover_color", Color(0.6, 0.95, 1.0, 1.0))
	header_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	settings_container.add_child(header_btn)
	
	# Container for group settings (collapsible)
	var group_container := VBoxContainer.new()
	group_container.add_theme_constant_override("separation", 4)
	settings_container.add_child(group_container)
	
	# Connect header button to toggle visibility
	header_btn.pressed.connect(_on_group_toggle.bind(header_btn, group_container, group_name))
	
	# Group settings
	for key in group_settings:
		var value = group_settings[key]
		var control_key = "%s.%s" % [group_name, key]
		var row := _create_setting_row(control_key, key, value)
		if row:
			group_container.add_child(row)


func _on_group_toggle(header_btn: Button, container: VBoxContainer, group_name: String) -> void:
	"""Toggle group visibility and update header icon."""
	container.visible = not container.visible
	var display_name = group_name.capitalize().replace("_", " ")
	if container.visible:
		header_btn.text = "v " + display_name
	else:
		header_btn.text = "> " + display_name


func _create_setting_row(control_key: String, display_key: String, value: Variant) -> HBoxContainer:
	"""Create a row with label and appropriate input control."""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	# Label
	var label := Label.new()
	label.text = display_key.capitalize().replace("_", " ")
	label.custom_minimum_size.x = 140
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.9))
	row.add_child(label)
	
	# Input control based on type
	var control: Control = null
	
	if value is bool:
		var checkbox := CheckBox.new()
		checkbox.button_pressed = value
		checkbox.toggled.connect(_on_setting_changed.bind(control_key))
		control = checkbox
	elif value is float or value is int:
		var spinbox := SpinBox.new()
		# Set min/max BEFORE value to avoid clamping
		spinbox.min_value = -10000
		spinbox.max_value = 10000
		# Use appropriate step based on value range
		# Small floats (0-1 range like ratios) use 0.01, larger values use 1.0
		if value is float and absf(value) < 2.0:
			spinbox.step = 0.01
		else:
			spinbox.step = 1.0
		spinbox.custom_minimum_size.x = 80
		# Defer value setting and signal connection until after node is in tree
		spinbox.set_meta("pending_value", value)
		spinbox.tree_entered.connect(_on_spinbox_ready.bind(spinbox, control_key))
		control = spinbox
		# Track if original value was int for proper save
		_original_types[control_key] = "int" if value is int else "float"
		print("[DebugPanel] Created SpinBox for %s with value: %s" % [control_key, value])
	elif value is String:
		var lineedit := LineEdit.new()
		lineedit.text = value
		lineedit.custom_minimum_size.x = 100
		lineedit.text_changed.connect(_on_setting_changed.bind(control_key))
		control = lineedit
	elif value is Dictionary and value.has("r"):
		# Color value
		var colorpicker := ColorPickerButton.new()
		colorpicker.color = Color(value.get("r", 1), value.get("g", 1), value.get("b", 1), value.get("a", 1))
		colorpicker.custom_minimum_size.x = 60
		colorpicker.color_changed.connect(_on_color_changed.bind(control_key))
		control = colorpicker
	else:
		# Unsupported type - show as label
		var val_label := Label.new()
		val_label.text = str(value)
		val_label.add_theme_font_size_override("font_size", 11)
		control = val_label
	
	if control:
		row.add_child(control)
		_controls[control_key] = control
	
	return row


func _on_setting_changed(_value: Variant, control_key: String) -> void:
	"""Called when a setting value changes - apply immediately."""
	_apply_setting(control_key)


func _on_spinbox_ready(spinbox: SpinBox, control_key: String) -> void:
	"""Called when SpinBox enters tree - set value and connect signal."""
	var pending_value = spinbox.get_meta("pending_value", 0.0)
	spinbox.value = pending_value
	spinbox.value_changed.connect(_on_setting_changed.bind(control_key))
	spinbox.remove_meta("pending_value")


func _on_color_changed(_color: Color, control_key: String) -> void:
	"""Called when a color value changes - apply immediately."""
	_apply_setting(control_key)


func _apply_setting(control_key: String) -> void:
	"""Apply a single setting to the game."""
	var control = _controls.get(control_key)
	if not control:
		return
	
	var value: Variant
	if control is CheckBox:
		value = control.button_pressed
	elif control is SpinBox:
		value = control.value
	elif control is LineEdit:
		value = control.text
	elif control is ColorPickerButton:
		value = control.color
	else:
		return
	
	# Apply based on control key
	match control_key:
		"space_traffic.show_lane_background":
			if _spaceship_traffic:
				_spaceship_traffic.set_debug_layers(value)
		"spaceship.spawn_offset":
			if _spaceship_traffic:
				_spaceship_traffic.set_spawn_offset(value)
		"spaceship.despawn_offset":
			if _spaceship_traffic:
				_spaceship_traffic.set_despawn_offset(value)
		"preview.position_y":
			if _preview_spaceship and _preview_spaceship.has_method("set_position_y_ratio"):
				_preview_spaceship.set_position_y_ratio(value)
		_:
			# Handle lane row settings dynamically
			if _spaceship_traffic and control_key.begins_with("lane_"):
				_apply_lane_row_setting(control_key, value)
	
	print("[DebugPanel] Applied: %s = %s" % [control_key, str(value)])


func _apply_all_settings() -> void:
	"""Apply all settings on startup using stored values (not control values)."""
	# Wait a frame for references to be set up
	await get_tree().process_frame
	
	# Apply directly from _settings to avoid SpinBox value issues
	for group_key in _settings:
		var group_value = _settings[group_key]
		if group_value is Dictionary and not group_value.has("r"):
			# It's a group
			for setting_key in group_value:
				var control_key = "%s.%s" % [group_key, setting_key]
				var value = group_value[setting_key]
				_apply_setting_value(control_key, value)
		else:
			# Top-level setting
			_apply_setting_value(group_key, group_value)


func _apply_setting_value(control_key: String, value: Variant) -> void:
	"""Apply a setting value directly (used for initial load)."""
	match control_key:
		"space_traffic.show_lane_background":
			if _spaceship_traffic:
				_spaceship_traffic.set_debug_layers(value)
		"spaceship.spawn_offset":
			if _spaceship_traffic:
				_spaceship_traffic.set_spawn_offset(value)
		"spaceship.despawn_offset":
			if _spaceship_traffic:
				_spaceship_traffic.set_despawn_offset(value)
		"preview.position_y":
			if _preview_spaceship and _preview_spaceship.has_method("set_position_y_ratio"):
				_preview_spaceship.set_position_y_ratio(value)
		_:
			# Handle lane row settings dynamically
			if _spaceship_traffic and control_key.begins_with("lane_"):
				_apply_lane_row_setting(control_key, value)
	
	print("[DebugPanel] Applied: %s = %s" % [control_key, str(value)])


func _on_save_pressed() -> void:
	_save_settings()


func _apply_lane_row_setting(control_key: String, value: float) -> void:
	"""Apply lane row position settings. Format: lane_N_color.row_M"""
	# Parse control_key like "lane_1_blue.row_1" or "lane_2_yellow.row_2"
	var parts = control_key.split(".")
	if parts.size() != 2:
		return
	
	var lane_part = parts[0]  # e.g., "lane_1_blue"
	var row_part = parts[1]   # e.g., "row_1"
	
	# Extract lane index (1-based in settings, 0-based internally)
	var lane_index = -1
	if lane_part.begins_with("lane_1"):
		lane_index = 0
	elif lane_part.begins_with("lane_2"):
		lane_index = 1
	elif lane_part.begins_with("lane_3"):
		lane_index = 2
	
	if lane_index < 0:
		return
	
	# Extract row index (1-based in settings, 0-based internally)
	var row_index = int(row_part.replace("row_", "")) - 1
	if row_index < 0:
		return
	
	_spaceship_traffic.set_lane_row_position(lane_index, row_index, value)


func _flash_save_button() -> void:
	var tween := create_tween()
	save_button.modulate = Color(0.5, 1.0, 0.8, 1.0)
	tween.tween_property(save_button, "modulate", Color.WHITE, 0.3)


## Public API for other scripts to get/set values

func get_value(group: String, key: String, default: Variant = null) -> Variant:
	"""Get a setting value by group and key."""
	if _settings.has(group) and _settings[group] is Dictionary:
		return _settings[group].get(key, default)
	return default


func set_value(group: String, key: String, value: Variant) -> void:
	"""Set a setting value (does not auto-save)."""
	if not _settings.has(group):
		_settings[group] = {}
	_settings[group][key] = value


func refresh_ui() -> void:
	"""Rebuild the UI from current settings."""
	_build_ui()
