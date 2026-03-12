extends Node2D

## Preview Spaceship
## Displays a preview of the next spaceship to launch in front of the hangar docking
## Y position is controlled via debug_settings.json (preview.position_y)
## Shows name and role from Crew Deployment panel in real-time
## Handles launch animation sequence and docking of next ship

signal launch_completed(ship_name: String, ship_role: String, texture: Texture2D)
signal dock_completed
signal request_next_ship

enum State { IDLE, LAUNCHING, DOCKING }

const SHIP_TEXTURES: Array[String] = [
	"res://assets/images/spaceships/spaceship_military_1.png",
	"res://assets/images/spaceships/spaceship_mining_1.png",
	"res://assets/images/spaceships/spaceship_transport_1.png"
]

const DEFAULT_NAME := ""
const DEFAULT_ROLE := ""

# Role-to-emblem texture mapping
const ROLE_EMBLEMS: Dictionary = {
	"Design": "res://assets/images/emblems/design.png",
	"Engineering": "res://assets/images/emblems/engineering.png",
	"Creative": "res://assets/images/emblems/creative.png",
	"Production": "res://assets/images/emblems/production.png",
}

@export var preview_scale: float = 0.8  ## Scale of the preview ship
@export var label_offset_x: float = 0.0  ## Horizontal offset for labels (when facing left)
@export var label_offset_y: float = 0.0  ## Vertical offset for labels (0 = centered on ship)

# Idle bob animation parameters
const BOB_AMPLITUDE: float = 1.5  ## Pixels of vertical movement
const BOB_SPEED: float = 0.2  ## Cycles per second (slow and dreamy)

# Launch animation parameters
@export var lift_amount: float = 25.0  ## Pixels to lift before accelerating
@export var lift_duration: float = 2  ## Duration of lift phase (hold at top)
@export var launch_duration: float = 1.0  ## Duration of acceleration phase
@export var launch_exit_offset: float = 300.0  ## How far off-screen to exit

# Dock animation parameters
@export var dock_delay: float = 1.0  ## Delay before next ship arrives
@export var dock_enter_offset: float = 400.0  ## How far off-screen the next ship starts
@export var dock_duration: float = 4.0  ## Duration of dock-in animation (slow approach)
@export var settle_duration: float = 1.2  ## Duration of descent to dock

@onready var sprite: Sprite2D = $Sprite2D
@onready var label_container: Control = $LabelContainer
@onready var name_label: Label = $LabelContainer/HBoxContainer/NameLabel
@onready var role_emblem: TextureRect = $LabelContainer/HBoxContainer/RoleEmblem

var _generator_panel: PanelContainer
var _console_panel: PanelContainer
var _name_input: LineEdit
var _role_input: OptionButton
var _loaded_textures: Array[Texture2D] = []
var _hangar_frame_material: ShaderMaterial  ## Reference to hangar frame shader material
var _blueprint_material: ShaderMaterial  ## Blueprint hologram shader for docked ship
var _original_material: Material  ## Store original material to restore on launch
var _current_index: int = 0
var _position_y_ratio: float = 0.9  ## Y position as ratio of screen height (0.9 = 90% from top)
var _bob_time: float = 0.0
var _state: State = State.IDLE
var _base_position: Vector2  ## The dock position (center of screen)
var _launch_tween: Tween
var _dock_tween: Tween

# Store launch data for the signal
var _pending_ship_name: String = ""
var _pending_ship_role: String = ""
var _pending_texture: Texture2D = null


func _ready() -> void:
	# Load ship textures
	_load_ship_textures()
	
	# Setup blueprint hologram shader
	_setup_blueprint_shader()
	
	# Position at center horizontally, Y from settings
	_update_position()
	_base_position = position
	get_tree().root.size_changed.connect(_on_viewport_resized)
	
	# Set default label text
	if name_label:
		name_label.text = DEFAULT_NAME
	if role_emblem:
		role_emblem.texture = null
		role_emblem.visible = false
	
	# Apply initial label offset
	if label_container:
		label_container.position.x = label_offset_x
		label_container.position.y = label_offset_y
	
	# Find panels and connect to inputs
	await get_tree().process_frame
	_find_generator_panel()
	_find_console_panel()
	_find_hangar_frame()
	_sync_texture()


func _process(delta: float) -> void:
	# Only bob during IDLE state
	if _state != State.IDLE:
		return
	
	_bob_time += delta
	var bob_offset := sin(_bob_time * BOB_SPEED * TAU) * BOB_AMPLITUDE
	
	if sprite:
		sprite.position.y = bob_offset
	if label_container:
		label_container.position.x = label_offset_x
		label_container.position.y = label_offset_y + bob_offset


func _on_viewport_resized() -> void:
	_update_position()
	_base_position = position


func _load_ship_textures() -> void:
	for path in SHIP_TEXTURES:
		var texture = load(path) as Texture2D
		if texture:
			_loaded_textures.append(texture)


func _setup_blueprint_shader() -> void:
	var shader := load("res://shaders/blueprint_hologram.gdshader") as Shader
	if shader and sprite:
		_original_material = sprite.material
		_blueprint_material = ShaderMaterial.new()
		_blueprint_material.shader = shader
		# Apply blueprint shader by default (ship starts docked)
		sprite.material = _blueprint_material


## Blueprint shader parameter setters (called by DebugPanel)
func set_blueprint_holo_color(r: float, g: float, b: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("holo_color", Color(r, g, b, 1.0))

func set_blueprint_chunk_scale(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("chunk_scale", value)

func set_blueprint_chunk_speed(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("chunk_speed", value)

func set_blueprint_scanline_density(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("scanline_density", value)

func set_blueprint_scanline_opacity(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("scanline_opacity", value)

func set_blueprint_grid_density(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("grid_density", value)

func set_blueprint_grid_thickness(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("grid_thickness", value)

func set_blueprint_edge_glow(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("edge_glow", value)

func set_blueprint_alpha_base(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("alpha_base", value)


func _apply_blueprint_shader() -> void:
	if sprite and _blueprint_material:
		sprite.material = _blueprint_material


func _remove_blueprint_shader() -> void:
	if sprite:
		sprite.material = _original_material


func _update_position() -> void:
	var viewport_size := get_viewport_rect().size
	position.x = viewport_size.x / 2.0
	position.y = viewport_size.y * _position_y_ratio


func _find_generator_panel() -> void:
	var console_ui := get_tree().root.find_child("ConsoleUI", true, false)
	if console_ui:
		_generator_panel = console_ui.find_child("GeneratorPanel", true, false)
		if _generator_panel:
			if _generator_panel.has_signal("image_generated"):
				_generator_panel.image_generated.connect(_on_image_generated)
			if _generator_panel.has_signal("ship_selected"):
				_generator_panel.ship_selected.connect(_on_ship_selected)


func _find_console_panel() -> void:
	var console_ui := get_tree().root.find_child("ConsoleUI", true, false)
	if console_ui:
		_console_panel = console_ui.find_child("ConsolePanel", true, false)
		
		var inputs_panel := console_ui.find_child("InputsPanel", true, false)
		if inputs_panel:
			_name_input = inputs_panel.get_node_or_null("MarginContainer/InputsContainer/NameColumn/NameInput")
			_role_input = inputs_panel.get_node_or_null("MarginContainer/InputsContainer/RoleColumn/RoleInput")
			
			if _name_input:
				_name_input.text_changed.connect(_on_name_changed)
			if _role_input:
				_role_input.item_selected.connect(_on_role_changed)


func _find_hangar_frame() -> void:
	## Find the HangarFrame node and get its shader material for launch effects
	var hangar_overlay := get_tree().root.find_child("HangarOverlay", true, false)
	if hangar_overlay:
		var hangar_frame := hangar_overlay.find_child("HangarFrame", true, false)
		if hangar_frame and hangar_frame is CanvasItem:
			_hangar_frame_material = hangar_frame.material as ShaderMaterial


func _set_hangar_launch_progress(progress: float) -> void:
	## Set the launch_progress shader parameter on the hangar frame
	if _hangar_frame_material:
		_hangar_frame_material.set_shader_parameter("launch_progress", progress)


func _on_name_changed(new_text: String) -> void:
	# Only update labels during IDLE state
	if _state != State.IDLE:
		return
	if name_label:
		if new_text.strip_edges().is_empty():
			name_label.text = DEFAULT_NAME
		else:
			name_label.text = new_text.to_upper()


func _on_role_changed(index: int) -> void:
	if _state != State.IDLE:
		return
	if role_emblem and _role_input:
		var role_text := _role_input.get_item_text(index)
		var emblem_path = ROLE_EMBLEMS.get(role_text, "")
		if emblem_path != "":
			role_emblem.texture = load(emblem_path)
			role_emblem.visible = true
		else:
			role_emblem.texture = null
			role_emblem.visible = false


## Trigger the launch animation sequence
## Returns false if already launching/docking
func launch(ship_name: String, ship_role: String, texture: Texture2D = null) -> bool:
	if _state != State.IDLE:
		return false
	
	_state = State.LAUNCHING
	
	# Store data for the completion signal
	_pending_ship_name = ship_name
	_pending_ship_role = ship_role
	_pending_texture = texture if texture else sprite.texture
	
	# Kill any existing tweens
	if _launch_tween and _launch_tween.is_valid():
		_launch_tween.kill()
	
	# Reset sprite position (stop bobbing at current position)
	var current_bob := sin(_bob_time * BOB_SPEED * TAU) * BOB_AMPLITUDE
	if sprite:
		sprite.position.y = current_bob
	if label_container:
		label_container.position.x = label_offset_x
		label_container.position.y = label_offset_y + current_bob
	
	# Create launch animation sequence
	_launch_tween = create_tween()
	
	# Phase 0: Dematerialize (chunk_threshold 0 -> 1) before undocking
	_launch_tween.set_ease(Tween.EASE_IN)
	_launch_tween.set_trans(Tween.TRANS_CUBIC)
	_launch_tween.tween_method(_set_chunk_threshold, 0.0, 1.0, 1.5)
	
	# Remove blueprint shader after dematerialization completes
	_launch_tween.tween_callback(_remove_blueprint_shader)
	
	# Phase 1: Lift up (sprite moves up relative to base)
	# Also transition hangar frame from cyan to yellow
	_launch_tween.set_ease(Tween.EASE_OUT)
	_launch_tween.set_trans(Tween.TRANS_QUAD)
	var lift_target_y := -lift_amount + current_bob
	_launch_tween.tween_property(sprite, "position:y", lift_target_y, lift_duration)
	if label_container:
		_launch_tween.parallel().tween_property(label_container, "position:y", label_offset_y + lift_target_y, lift_duration)
	# Transition hangar frame to launch mode (cyan -> yellow)
	_launch_tween.parallel().tween_method(_set_hangar_launch_progress, 0.0, 1.0, lift_duration)
	
	# Phase 2: Accelerate to the left (exponential feel)
	var exit_x := -launch_exit_offset
	
	_launch_tween.set_ease(Tween.EASE_IN)
	_launch_tween.set_trans(Tween.TRANS_EXPO)
	_launch_tween.tween_property(self, "position:x", exit_x, launch_duration)
	
	# On completion, emit signal and start docking next ship
	_launch_tween.tween_callback(_on_launch_animation_finished)
	
	return true


func _on_launch_animation_finished() -> void:
	# Emit the launch signal so traffic manager can spawn the ship
	launch_completed.emit(_pending_ship_name, _pending_ship_role, _pending_texture)
	
	# Immediately start docking the next ship
	_dock_next_ship()


func _dock_next_ship() -> void:
	_state = State.DOCKING
	
	# Request generator to select next ship
	request_next_ship.emit()
	
	# Fallback: cycle local textures if generator doesn't respond
	_current_index = (_current_index + 1) % max(1, _loaded_textures.size())
	_sync_texture()
	
	# Reset labels for next ship
	if name_label:
		name_label.text = DEFAULT_NAME
	if role_emblem:
		role_emblem.texture = null
		role_emblem.visible = false
	
	# Calculate positions
	var viewport_size := get_viewport_rect().size
	_base_position.x = viewport_size.x / 2.0
	_base_position.y = viewport_size.y * _position_y_ratio
	
	# Start ship off-screen to the right, at lifted height
	var lifted_y := _base_position.y - lift_amount
	position.x = viewport_size.x + dock_enter_offset
	position.y = lifted_y
	
	# Reset sprite offset
	if sprite:
		sprite.position.y = 0
	if label_container:
		label_container.position.x = label_offset_x
		label_container.position.y = label_offset_y
	
	# Hide ship initially (will appear after delay)
	modulate.a = 0.0
	
	# Kill any existing dock tween
	if _dock_tween and _dock_tween.is_valid():
		_dock_tween.kill()
	
	# Create dock animation
	_dock_tween = create_tween()
	
	# Phase 0: Wait before next ship arrives
	_dock_tween.tween_interval(dock_delay)
	
	# Fade in as ship appears
	_dock_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	
	# Phase 1: Slide in horizontally - already decelerating (ease out, slow approach)
	# TRANS_CIRC with EASE_OUT gives a smooth deceleration feel
	_dock_tween.set_ease(Tween.EASE_OUT)
	_dock_tween.set_trans(Tween.TRANS_CIRC)
	_dock_tween.tween_property(self, "position:x", _base_position.x, dock_duration)
	
	# Phase 2: Descend to dock position (move down gently)
	# Also transition hangar frame back from yellow to cyan
	_dock_tween.set_ease(Tween.EASE_IN_OUT)
	_dock_tween.set_trans(Tween.TRANS_SINE)
	_dock_tween.tween_property(self, "position:y", _base_position.y, settle_duration)
	_dock_tween.parallel().tween_method(_set_hangar_launch_progress, 1.0, 0.0, 2.0)  # 2 second transition back to cyan
	
	# On completion, return to IDLE state
	_dock_tween.tween_callback(_on_dock_animation_finished)


func _on_dock_animation_finished() -> void:
	_state = State.IDLE
	_bob_time = 0.0  # Reset bob phase for smooth start
	# Apply blueprint shader - new ship is under construction
	_apply_blueprint_shader()
	# Start materializing animation (chunk_threshold 1 -> 0)
	_start_materialize_animation()
	dock_completed.emit()


func _start_materialize_animation() -> void:
	if not _blueprint_material:
		return
	# Start fully holographic (threshold = 1)
	_blueprint_material.set_shader_parameter("chunk_threshold", 1.0)
	# Animate to fully solid (threshold = 0) over time
	var materialize_tween := create_tween()
	materialize_tween.set_ease(Tween.EASE_OUT)
	materialize_tween.set_trans(Tween.TRANS_CUBIC)
	materialize_tween.tween_method(_set_chunk_threshold, 1.0, 0.0, 3.0)


func _set_chunk_threshold(value: float) -> void:
	if _blueprint_material:
		_blueprint_material.set_shader_parameter("chunk_threshold", value)


## Check if the ship is ready to launch (in IDLE state)
func is_ready() -> bool:
	return _state == State.IDLE


## Get current state
func get_state() -> State:
	return _state


func _sync_texture() -> void:
	if not sprite:
		return
	
	# Try to get texture from generator panel first
	if _generator_panel and _generator_panel.has_method("get_generated_texture"):
		var texture: Texture2D = _generator_panel.get_generated_texture()
		if texture:
			sprite.texture = texture
			sprite.scale = Vector2(-preview_scale, preview_scale)
			return
	
	# Fallback: use local textures for initial load or dock cycling
	if not _loaded_textures.is_empty():
		_current_index = _current_index % _loaded_textures.size()
		sprite.texture = _loaded_textures[_current_index]
		sprite.scale = Vector2(-preview_scale, preview_scale)


func _on_image_generated(_path: String, texture: Texture2D = null) -> void:
	if _state == State.IDLE and texture:
		sprite.texture = texture
		sprite.scale = Vector2(-preview_scale, preview_scale)


func _on_ship_selected(texture: Texture2D) -> void:
	if _state == State.IDLE and texture:
		sprite.texture = texture
		sprite.scale = Vector2(-preview_scale, preview_scale)


## Set Y position as a ratio of screen height (called by DebugPanel)
func set_position_y_ratio(ratio: float) -> void:
	_position_y_ratio = ratio
	_update_position()
	_base_position = position


## Call this to manually set the preview texture
func set_preview_texture(texture: Texture2D) -> void:
	if sprite and texture:
		sprite.texture = texture
		sprite.scale = Vector2(-preview_scale, preview_scale)  # Flipped to face left


## Update the preview to match the generator panel's current selection
func refresh_preview() -> void:
	if _state == State.IDLE:
		_sync_texture()


## Set the ship index directly (for standalone use)
func set_ship_index(index: int) -> void:
	_current_index = index
	if _state == State.IDLE:
		_sync_texture()


## Set label X offset (horizontal position)
func set_label_offset_x(offset: float) -> void:
	label_offset_x = offset
	if label_container:
		label_container.position.x = label_offset_x


## Set label Y offset (vertical position)
func set_label_offset_y(offset: float) -> void:
	label_offset_y = offset
	if label_container:
		label_container.position.y = label_offset_y
