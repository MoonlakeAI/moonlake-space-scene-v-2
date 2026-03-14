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

# Ship Registry Table UI
var _ship_table_panel: PanelContainer
var _ship_table_container: VBoxContainer
var _ship_table_header: Button
var _ship_table_grid: GridContainer
var _ship_table_visible: bool = true
var _update_timer: float = 0.0
const SHIP_TABLE_UPDATE_INTERVAL: float = 0.5  # Update every 0.5 seconds

# Activity controls
var _activity_dropdown: OptionButton
var _selected_activity: int = 2  # 2 = LIGHT_SPEED_JUMP, 3 = ACCELERATE, 4 = DECELERATE

# Generated Ships Panel UI
var _generated_ships_panel: PanelContainer
var _generated_ships_container: VBoxContainer
var _generated_ships_header: Button
var _generated_ships_scroll: ScrollContainer
var _generated_ships_grid: GridContainer
var _generated_ships_visible: bool = true
var _generator_panel: PanelContainer


func _ready() -> void:
	save_button.pressed.connect(_on_save_pressed)
	
	# Get reference to spaceship traffic (deferred to ensure scene is ready)
	# Ship registry table is created after references are set up
	call_deferred("_setup_references")
	
	_load_settings()
	_build_ui()
	_apply_all_settings()
	
	# Start hidden by default
	visible = false


func _process(delta: float) -> void:
	# Update ship table periodically when visible
	if _ship_table_panel and _ship_table_panel.visible and _ship_table_visible:
		_update_timer += delta
		if _update_timer >= SHIP_TABLE_UPDATE_INTERVAL:
			_update_timer = 0.0
			_update_ship_registry_table()


func _unhandled_key_input(event: InputEvent) -> void:
	# Toggle visibility with Ctrl+Shift+D
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_D and event.ctrl_pressed and event.shift_pressed:
			visible = !visible
			if _ship_table_panel:
				_ship_table_panel.visible = visible
			if _generated_ships_panel:
				_generated_ships_panel.visible = visible
			get_viewport().set_input_as_handled()


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
	
	# Find generator panel in ConsoleUI
	var console_ui = get_parent()
	if console_ui:
		_generator_panel = console_ui.find_child("GeneratorPanel", true, false)
		if _generator_panel:
			print("[DebugPanel] Found GeneratorPanel")
			# Connect to image_generated signal
			if _generator_panel.has_signal("image_generated"):
				_generator_panel.image_generated.connect(_on_ship_generated)
	
	# Create ship registry table after references are ready
	_create_ship_registry_table()
	
	# Create generated ships panel
	_create_generated_ships_panel()


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
		"spaceship.afterburner_trail_offset_x":
			if _spaceship_traffic and _spaceship_traffic.has_method("set_all_ships_afterburner_trail_offset_x"):
				_spaceship_traffic.set_all_ships_afterburner_trail_offset_x(value)
		"preview.position_y":
			if _preview_spaceship and _preview_spaceship.has_method("set_position_y_ratio"):
				_preview_spaceship.set_position_y_ratio(value)
		"preview.label_offset_x":
			if _preview_spaceship and _preview_spaceship.has_method("set_label_offset_x"):
				_preview_spaceship.set_label_offset_x(value)
		"preview.label_offset_y":
			if _preview_spaceship and _preview_spaceship.has_method("set_label_offset_y"):
				_preview_spaceship.set_label_offset_y(value)
		"preview.trail_offset_x":
			if _preview_spaceship and _preview_spaceship.has_method("set_trail_offset_x"):
				_preview_spaceship.set_trail_offset_x(value)
		"preview.perpetual_launch":
			if _preview_spaceship and _preview_spaceship.has_method("set_perpetual_launch"):
				_preview_spaceship.set_perpetual_launch(value)
		"space_traffic.label_offset_x_looking_left":
			if _spaceship_traffic and _spaceship_traffic.has_method("set_all_ships_label_offset_left"):
				_spaceship_traffic.set_all_ships_label_offset_left(value)
		"space_traffic.label_offset_x_looking_right":
			if _spaceship_traffic and _spaceship_traffic.has_method("set_all_ships_label_offset_right"):
				_spaceship_traffic.set_all_ships_label_offset_right(value)
		_:
			# Handle blueprint shader settings
			if control_key.begins_with("blueprint_shader."):
				_apply_blueprint_shader_setting(control_key, value)
			# Handle lane row settings dynamically
			elif _spaceship_traffic and control_key.begins_with("lane_"):
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
		"spaceship.afterburner_trail_offset_x":
			if _spaceship_traffic and _spaceship_traffic.has_method("set_all_ships_afterburner_trail_offset_x"):
				_spaceship_traffic.set_all_ships_afterburner_trail_offset_x(value)
		"preview.position_y":
			if _preview_spaceship and _preview_spaceship.has_method("set_position_y_ratio"):
				_preview_spaceship.set_position_y_ratio(value)
		"preview.label_offset_x":
			if _preview_spaceship and _preview_spaceship.has_method("set_label_offset_x"):
				_preview_spaceship.set_label_offset_x(value)
		"preview.label_offset_y":
			if _preview_spaceship and _preview_spaceship.has_method("set_label_offset_y"):
				_preview_spaceship.set_label_offset_y(value)
		"preview.trail_offset_x":
			if _preview_spaceship and _preview_spaceship.has_method("set_trail_offset_x"):
				_preview_spaceship.set_trail_offset_x(value)
		"preview.perpetual_launch":
			if _preview_spaceship and _preview_spaceship.has_method("set_perpetual_launch"):
				_preview_spaceship.set_perpetual_launch(value)
		"space_traffic.label_offset_x_looking_left":
			if _spaceship_traffic and _spaceship_traffic.has_method("set_all_ships_label_offset_left"):
				_spaceship_traffic.set_all_ships_label_offset_left(value)
		"space_traffic.label_offset_x_looking_right":
			if _spaceship_traffic and _spaceship_traffic.has_method("set_all_ships_label_offset_right"):
				_spaceship_traffic.set_all_ships_label_offset_right(value)
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


func _apply_blueprint_shader_setting(control_key: String, value: float) -> void:
	"""Apply blueprint shader settings to preview spaceship."""
	if not _preview_spaceship:
		return
	
	# Handle color components specially - collect all three and apply together
	if control_key.ends_with("_r") or control_key.ends_with("_g") or control_key.ends_with("_b"):
		# Get all color components from settings
		var shader_settings = _settings.get("blueprint_shader", {})
		var r = shader_settings.get("holo_color_r", 0.1)
		var g = shader_settings.get("holo_color_g", 0.6)
		var b = shader_settings.get("holo_color_b", 0.9)
		if _preview_spaceship.has_method("set_blueprint_holo_color"):
			_preview_spaceship.set_blueprint_holo_color(r, g, b)
		return
	
	# Map control_key to method name
	var setting_name = control_key.replace("blueprint_shader.", "")
	var method_name = "set_blueprint_" + setting_name
	
	if _preview_spaceship.has_method(method_name):
		_preview_spaceship.call(method_name, value)


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


# ============ SHIP REGISTRY TABLE ============

func _create_ship_registry_table() -> void:
	"""Create a collapsible ship registry table at top-left of screen."""
	# Get the parent CanvasLayer (ConsoleUI)
	var canvas_layer = get_parent()
	if not canvas_layer:
		return
	
	# Create the panel container
	_ship_table_panel = PanelContainer.new()
	_ship_table_panel.name = "ShipRegistryPanel"
	
	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.02, 0.05, 0.85)
	panel_style.border_color = Color(0.0, 0.5, 0.65, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_ship_table_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Position at top-left
	_ship_table_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_ship_table_panel.offset_left = 15
	_ship_table_panel.offset_top = 15
	_ship_table_panel.offset_right = 350
	_ship_table_panel.offset_bottom = 400
	
	# Main container
	_ship_table_container = VBoxContainer.new()
	_ship_table_container.add_theme_constant_override("separation", 6)
	_ship_table_panel.add_child(_ship_table_container)
	
	# Collapsible header button
	_ship_table_header = Button.new()
	_ship_table_header.text = "v SHIP REGISTRY"
	_ship_table_header.flat = true
	_ship_table_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ship_table_header.add_theme_font_size_override("font_size", 13)
	_ship_table_header.add_theme_color_override("font_color", Color(0.3, 0.85, 0.95, 1.0))
	_ship_table_header.add_theme_color_override("font_hover_color", Color(0.5, 0.95, 1.0, 1.0))
	_ship_table_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ship_table_header.pressed.connect(_on_ship_table_toggle)
	_ship_table_container.add_child(_ship_table_header)
	
	# Separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("separation", Color(0.0, 0.5, 0.65, 0.5))
	_ship_table_container.add_child(separator)
	
	# Lane summary row
	var summary_label = Label.new()
	summary_label.name = "SummaryLabel"
	summary_label.add_theme_font_size_override("font_size", 11)
	summary_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.8, 0.9))
	summary_label.text = "Lane 1: 0 | Lane 2: 0 | Lane 3: 0"
	_ship_table_container.add_child(summary_label)
	
	# Activity control row
	var activity_row = HBoxContainer.new()
	activity_row.add_theme_constant_override("separation", 8)
	_ship_table_container.add_child(activity_row)
	
	var activity_label = Label.new()
	activity_label.text = "Activity:"
	activity_label.add_theme_font_size_override("font_size", 10)
	activity_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.8, 0.9))
	activity_row.add_child(activity_label)
	
	_activity_dropdown = OptionButton.new()
	_activity_dropdown.add_theme_font_size_override("font_size", 10)
	_activity_dropdown.custom_minimum_size.x = 120
	_activity_dropdown.add_item("LightSpeedJump", 2)
	_activity_dropdown.add_item("Accelerate", 3)
	_activity_dropdown.add_item("Decelerate", 4)
	_activity_dropdown.selected = 0
	_activity_dropdown.item_selected.connect(_on_activity_selected)
	activity_row.add_child(_activity_dropdown)
	
	var trigger_all_btn = Button.new()
	trigger_all_btn.text = "Trigger All"
	trigger_all_btn.add_theme_font_size_override("font_size", 9)
	trigger_all_btn.custom_minimum_size = Vector2(70, 20)
	trigger_all_btn.pressed.connect(_on_trigger_all_activities)
	activity_row.add_child(trigger_all_btn)
	
	# Scroll container for the grid
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 250)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ship_table_container.add_child(scroll)
	
	# Grid container for ship data
	_ship_table_grid = GridContainer.new()
	_ship_table_grid.columns = 8  # ID, Name, Lane, Row, Dir, Pos X, Action, Delete
	_ship_table_grid.add_theme_constant_override("h_separation", 6)
	_ship_table_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_ship_table_grid)
	
	# Add header row
	_add_table_header()
	
	# Add to canvas layer
	canvas_layer.add_child(_ship_table_panel)
	
	# Start hidden (same as debug panel)
	_ship_table_panel.visible = false
	
	# Initial update
	_update_ship_registry_table()
	
	# Connect to registry signals if available
	if _spaceship_traffic and _spaceship_traffic.has_signal("registry_updated"):
		_spaceship_traffic.registry_updated.connect(_update_ship_registry_table)


func _add_table_header() -> void:
	"""Add header row to the ship table grid."""
	var headers = ["ID", "Name", "Lane", "Row", "Dir", "X", "Act", "Del"]
	var widths = [25, 80, 30, 28, 25, 45, 35, 30]
	
	for i in range(headers.size()):
		var label = Label.new()
		label.text = headers[i]
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.8, 0.8))
		label.custom_minimum_size.x = widths[i]
		_ship_table_grid.add_child(label)


func _on_ship_table_toggle() -> void:
	"""Toggle ship table content visibility."""
	_ship_table_visible = not _ship_table_visible
	
	# Update header arrow
	if _ship_table_visible:
		_ship_table_header.text = "v SHIP REGISTRY"
	else:
		_ship_table_header.text = "> SHIP REGISTRY"
	
	# Show/hide content (skip header at index 0)
	for i in range(1, _ship_table_container.get_child_count()):
		_ship_table_container.get_child(i).visible = _ship_table_visible


func _update_ship_registry_table() -> void:
	"""Update the ship registry table with current data."""
	if not _spaceship_traffic or not _ship_table_grid:
		return
	
	# Get registry data
	var registry: Array = []
	if _spaceship_traffic.has_method("get_ship_registry"):
		registry = _spaceship_traffic.get_ship_registry()
	
	# Sort by lane (highest to lowest), then by row
	registry.sort_custom(_sort_ships_by_lane_desc)
	
	# Update summary
	var summary_label = _ship_table_container.get_node_or_null("SummaryLabel")
	if summary_label and _spaceship_traffic.has_method("get_lane_counts"):
		var counts = _spaceship_traffic.get_lane_counts()
		summary_label.text = "Lane 1: %d | Lane 2: %d | Lane 3: %d | Total: %d" % [counts[0], counts[1], counts[2], registry.size()]
	
	# Clear existing rows (keep header - first 8 children)
	while _ship_table_grid.get_child_count() > 8:
		var child = _ship_table_grid.get_child(7)
		_ship_table_grid.remove_child(child)
		child.queue_free()
	
	# Add ship rows
	var lane_colors = [
		Color(0.3, 0.7, 1.0, 1.0),   # Lane 0 (1) - Blue
		Color(1.0, 0.9, 0.3, 1.0),   # Lane 1 (2) - Yellow
		Color(1.0, 0.4, 0.4, 1.0),   # Lane 2 (3) - Red
	]
	
	for ship_data in registry:
		var ship_id = ship_data.get("id", -1)
		var ship_name = ship_data.get("name", "???")
		var lane = ship_data.get("lane", -1)
		var row = ship_data.get("row", -1)
		var direction = ship_data.get("direction", 0)
		var pos: Vector2 = ship_data.get("position", Vector2.ZERO)
		
		# Truncate name if too long
		if ship_name.length() > 10:
			ship_name = ship_name.substr(0, 8) + ".."
		
		var lane_color = lane_colors[lane] if lane >= 0 and lane < 3 else Color.WHITE
		
		# ID
		var id_label = Label.new()
		id_label.text = str(ship_id)
		id_label.add_theme_font_size_override("font_size", 10)
		id_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9, 0.9))
		id_label.custom_minimum_size.x = 25
		_ship_table_grid.add_child(id_label)
		
		# Name
		var name_label = Label.new()
		name_label.text = ship_name
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.95))
		name_label.custom_minimum_size.x = 80
		_ship_table_grid.add_child(name_label)
		
		# Lane (color-coded)
		var lane_label = Label.new()
		lane_label.text = str(lane + 1)  # Display as 1-indexed
		lane_label.add_theme_font_size_override("font_size", 10)
		lane_label.add_theme_color_override("font_color", lane_color)
		lane_label.custom_minimum_size.x = 30
		_ship_table_grid.add_child(lane_label)
		
		# Row
		var row_label = Label.new()
		row_label.text = str(row + 1)  # Display as 1-indexed
		row_label.add_theme_font_size_override("font_size", 10)
		row_label.add_theme_color_override("font_color", lane_color)
		row_label.custom_minimum_size.x = 28
		_ship_table_grid.add_child(row_label)
		
		# Direction
		var dir_label = Label.new()
		dir_label.text = ">" if direction > 0 else "<"
		dir_label.add_theme_font_size_override("font_size", 10)
		dir_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9, 0.9))
		dir_label.custom_minimum_size.x = 25
		_ship_table_grid.add_child(dir_label)
		
		# Position X
		var pos_label = Label.new()
		pos_label.text = "%.0f" % pos.x
		pos_label.add_theme_font_size_override("font_size", 10)
		pos_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.8, 0.8))
		pos_label.custom_minimum_size.x = 45
		_ship_table_grid.add_child(pos_label)
		
		# Action button
		var action_btn = Button.new()
		action_btn.text = "Go"
		action_btn.add_theme_font_size_override("font_size", 9)
		action_btn.custom_minimum_size = Vector2(35, 18)
		action_btn.pressed.connect(_on_trigger_activity.bind(ship_id))
		_ship_table_grid.add_child(action_btn)
		
		# Delete button
		var delete_btn = Button.new()
		delete_btn.text = "X"
		delete_btn.add_theme_font_size_override("font_size", 9)
		delete_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
		delete_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.6, 0.6, 1.0))
		delete_btn.custom_minimum_size = Vector2(30, 18)
		delete_btn.pressed.connect(_on_delete_ship.bind(ship_id))
		_ship_table_grid.add_child(delete_btn)


func _sort_ships_by_lane_desc(a: Dictionary, b: Dictionary) -> bool:
	"""Sort ships by lane (highest first), then by row."""
	var lane_a = a.get("lane", 0)
	var lane_b = b.get("lane", 0)
	if lane_a != lane_b:
		return lane_a > lane_b  # Higher lane first
	# Same lane, sort by row
	var row_a = a.get("row", 0)
	var row_b = b.get("row", 0)
	return row_a < row_b  # Lower row first within same lane


func _on_activity_selected(index: int) -> void:
	"""Handle activity dropdown selection."""
	_selected_activity = _activity_dropdown.get_item_id(index)


func _on_trigger_activity(ship_id: int) -> void:
	"""Trigger the selected activity on a specific ship."""
	if not _spaceship_traffic:
		return
	
	# Find the ship in the registry
	var registry = _spaceship_traffic.get_ship_registry()
	for entry in registry:
		if entry.get("id") == ship_id:
			var ship = entry.get("ship_ref")
			if ship and is_instance_valid(ship):
				_trigger_activity_on_ship(ship)
			return


func _on_delete_ship(ship_id: int) -> void:
	"""Delete a specific ship from the registry."""
	if not _spaceship_traffic:
		return
	
	if _spaceship_traffic.has_method("remove_ship_by_id"):
		_spaceship_traffic.remove_ship_by_id(ship_id)


func _on_trigger_all_activities() -> void:
	"""Trigger the selected activity on all ships."""
	if not _spaceship_traffic:
		return
	
	var registry = _spaceship_traffic.get_ship_registry()
	for entry in registry:
		var ship = entry.get("ship_ref")
		if ship and is_instance_valid(ship):
			# Small delay between each to stagger the effect
			_trigger_activity_on_ship(ship)


func _trigger_activity_on_ship(ship: Node) -> void:
	"""Trigger the selected activity on a ship."""
	# Check if ship already has an activity running
	if ship.activity != 0:  # 0 = Activity.NONE
		return
	
	match _selected_activity:
		2:  # LIGHT_SPEED_JUMP
			if ship.has_method("_start_activity_light_speed_jump"):
				ship._start_activity_light_speed_jump()
		3:  # ACCELERATE
			if ship.has_method("_start_activity_accelerate"):
				ship._start_activity_accelerate()
		4:  # DECELERATE
			if ship.has_method("_start_activity_decelerate"):
				ship._start_activity_decelerate()


# ============ GENERATED SHIPS PANEL ============

func _create_generated_ships_panel() -> void:
	"""Create a panel to track all generated ships with thumbnails."""
	var canvas_layer = get_parent()
	if not canvas_layer:
		return
	
	# Create the panel container
	_generated_ships_panel = PanelContainer.new()
	_generated_ships_panel.name = "GeneratedShipsPanel"
	
	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.0, 0.05, 0.85)
	panel_style.border_color = Color(0.6, 0.3, 0.8, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_generated_ships_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Position at bottom-left (below ship registry)
	_generated_ships_panel.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_generated_ships_panel.offset_left = 15
	_generated_ships_panel.offset_bottom = -15
	_generated_ships_panel.offset_right = 280
	_generated_ships_panel.offset_top = -220
	
	# Main container
	_generated_ships_container = VBoxContainer.new()
	_generated_ships_container.add_theme_constant_override("separation", 6)
	_generated_ships_panel.add_child(_generated_ships_container)
	
	# Collapsible header button
	_generated_ships_header = Button.new()
	_generated_ships_header.text = "v GENERATED SHIPS (0)"
	_generated_ships_header.flat = true
	_generated_ships_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_generated_ships_header.add_theme_font_size_override("font_size", 13)
	_generated_ships_header.add_theme_color_override("font_color", Color(0.7, 0.4, 0.9, 1.0))
	_generated_ships_header.add_theme_color_override("font_hover_color", Color(0.85, 0.55, 1.0, 1.0))
	_generated_ships_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_generated_ships_header.pressed.connect(_on_generated_ships_toggle)
	_generated_ships_container.add_child(_generated_ships_header)
	
	# Separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("separation", Color(0.6, 0.3, 0.8, 0.5))
	_generated_ships_container.add_child(separator)
	
	# Scroll container for the grid
	_generated_ships_scroll = ScrollContainer.new()
	_generated_ships_scroll.custom_minimum_size = Vector2(260, 150)
	_generated_ships_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_generated_ships_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_generated_ships_container.add_child(_generated_ships_scroll)
	
	# Grid container for ship thumbnails
	_generated_ships_grid = GridContainer.new()
	_generated_ships_grid.columns = 3  # 3 thumbnails per row
	_generated_ships_grid.add_theme_constant_override("h_separation", 8)
	_generated_ships_grid.add_theme_constant_override("v_separation", 8)
	_generated_ships_scroll.add_child(_generated_ships_grid)
	
	# Add to canvas layer
	canvas_layer.add_child(_generated_ships_panel)
	
	# Start hidden (same as debug panel)
	_generated_ships_panel.visible = false
	
	# Load any previously generated ships
	_refresh_generated_ships_display()


func _on_generated_ships_toggle() -> void:
	"""Toggle generated ships panel content visibility."""
	_generated_ships_visible = not _generated_ships_visible
	
	# Update header arrow
	var count := 0
	if _generator_panel and _generator_panel.has_method("get_generated_ships_count"):
		count = _generator_panel.get_generated_ships_count()
	
	if _generated_ships_visible:
		_generated_ships_header.text = "v GENERATED SHIPS (%d)" % count
	else:
		_generated_ships_header.text = "> GENERATED SHIPS (%d)" % count
	
	# Show/hide content (skip header at index 0)
	for i in range(1, _generated_ships_container.get_child_count()):
		_generated_ships_container.get_child(i).visible = _generated_ships_visible


func _on_ship_generated(_path: String, _texture: Texture2D) -> void:
	"""Called when a new ship is generated."""
	print("[DebugPanel] Ship generated: %s" % _path)
	_refresh_generated_ships_display()


func _refresh_generated_ships_display() -> void:
	"""Refresh the generated ships panel with current data."""
	if not _generated_ships_grid or not _generator_panel:
		return
	
	# Clear existing thumbnails
	for child in _generated_ships_grid.get_children():
		child.queue_free()
	
	# Get generated ships from generator
	var ships: Array = []
	if _generator_panel.has_method("get_generated_ships"):
		ships = _generator_panel.get_generated_ships()
	
	# Update header count
	if _generated_ships_visible:
		_generated_ships_header.text = "v GENERATED SHIPS (%d)" % ships.size()
	else:
		_generated_ships_header.text = "> GENERATED SHIPS (%d)" % ships.size()
	
	# Add thumbnail for each ship (newest first)
	for i in range(ships.size() - 1, -1, -1):
		var ship_data: Dictionary = ships[i]
		var texture: Texture2D = ship_data.get("texture")
		var timestamp: String = ship_data.get("timestamp", "")
		var prompt: String = ship_data.get("prompt", "")
		
		if texture:
			_add_ship_thumbnail(texture, timestamp, prompt, ships.size() - i)


func _add_ship_thumbnail(texture: Texture2D, timestamp: String, prompt: String, index: int) -> void:
	"""Add a thumbnail entry for a generated ship."""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	
	# Thumbnail panel with border
	var thumb_panel = PanelContainer.new()
	var thumb_style = StyleBoxFlat.new()
	thumb_style.bg_color = Color(0.05, 0.02, 0.08, 0.9)
	thumb_style.border_color = Color(0.5, 0.3, 0.7, 0.7)
	thumb_style.set_border_width_all(1)
	thumb_style.set_corner_radius_all(3)
	thumb_panel.add_theme_stylebox_override("panel", thumb_style)
	thumb_panel.custom_minimum_size = Vector2(75, 50)
	container.add_child(thumb_panel)
	
	# Texture rect for the ship image
	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(75, 50)
	thumb_panel.add_child(tex_rect)
	
	# Index label
	var index_label = Label.new()
	index_label.text = "#%d" % index
	index_label.add_theme_font_size_override("font_size", 9)
	index_label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.8, 0.9))
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(index_label)
	
	# Set tooltip with full info
	var time_part := timestamp.split("T")[1] if "T" in timestamp else timestamp
	time_part = time_part.split(".")[0] if "." in time_part else time_part
	container.tooltip_text = "Generated at: %s\nPrompt: %s" % [time_part, prompt]
	
	_generated_ships_grid.add_child(container)
