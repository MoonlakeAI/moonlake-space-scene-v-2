extends Node2D

## Preview Spaceship
## Displays a preview of the next spaceship to launch in front of the hangar docking
## Y position is controlled via debug_settings.json (preview.position_y)
## Shows name and role from Crew Deployment panel in real-time

const SHIP_TEXTURES: Array[String] = [
	"res://assets/images/spaceships/military_frigate.png",
	"res://assets/images/spaceships/mining_vessel.png",
	"res://assets/images/spaceships/nimble_transport.png"
]

const DEFAULT_NAME := "AWAITING DESIGNATION"
const DEFAULT_ROLE := "Unassigned"

@export var preview_scale: float = 0.8  ## Scale of the preview ship
@export var label_offset_y: float = 0.0  ## Vertical offset for labels (0 = centered on ship)

# Very subtle idle bob - slow and smooth for a satisfying hovering feel
const BOB_AMPLITUDE: float = 1.5  ## Pixels of vertical movement
const BOB_SPEED: float = 0.2  ## Cycles per second (slow and dreamy)

@onready var sprite: Sprite2D = $Sprite2D
@onready var label_container: Control = $LabelContainer
@onready var name_label: Label = $LabelContainer/VBoxContainer/NameLabel
@onready var role_label: Label = $LabelContainer/VBoxContainer/RoleLabel

var _generator_panel: PanelContainer
var _console_panel: PanelContainer
var _name_input: LineEdit
var _role_input: LineEdit
var _loaded_textures: Array[Texture2D] = []
var _current_index: int = 0
var _position_y_ratio: float = 0.9  ## Y position as ratio of screen height (0.9 = 90% from top)
var _bob_time: float = 0.0


func _ready() -> void:
	# Load ship textures
	_load_ship_textures()
	
	# Position at center horizontally, Y from settings
	_update_position()
	get_tree().root.size_changed.connect(_update_position)
	
	# Set default label text
	if name_label:
		name_label.text = DEFAULT_NAME
	if role_label:
		role_label.text = DEFAULT_ROLE
	
	# Find panels and connect to inputs
	await get_tree().process_frame
	_find_generator_panel()
	_find_console_panel()
	_sync_texture()


func _process(delta: float) -> void:
	# Very subtle idle bobbing - applied to sprite offset so base position stays accurate
	_bob_time += delta
	if sprite:
		sprite.position.y = sin(_bob_time * BOB_SPEED * TAU) * BOB_AMPLITUDE
	# Label container follows the bob
	if label_container:
		label_container.position.y = label_offset_y + sin(_bob_time * BOB_SPEED * TAU) * BOB_AMPLITUDE


func _load_ship_textures() -> void:
	for path in SHIP_TEXTURES:
		var texture = load(path) as Texture2D
		if texture:
			_loaded_textures.append(texture)


func _update_position() -> void:
	var viewport_size := get_viewport_rect().size
	# Center horizontally, Y position from ratio setting
	position.x = viewport_size.x / 2.0
	position.y = viewport_size.y * _position_y_ratio


func _find_generator_panel() -> void:
	# Find the GeneratorPanel in the scene tree
	var console_ui := get_tree().root.find_child("ConsoleUI", true, false)
	if console_ui:
		_generator_panel = console_ui.find_child("GeneratorPanel", true, false)
		if _generator_panel:
			if _generator_panel.has_signal("image_generated"):
				_generator_panel.image_generated.connect(_on_image_generated)
			if _generator_panel.has_signal("ship_selected"):
				_generator_panel.ship_selected.connect(_on_ship_selected)


func _find_console_panel() -> void:
	# Find the ConsolePanel (Crew Deployment) and connect to its inputs
	var console_ui := get_tree().root.find_child("ConsoleUI", true, false)
	if console_ui:
		_console_panel = console_ui.find_child("ConsolePanel", true, false)
		
		# Get the input fields from InputsPanel (sibling of ConsolePanel)
		var inputs_panel := console_ui.find_child("InputsPanel", true, false)
		if inputs_panel:
			_name_input = inputs_panel.get_node_or_null("MarginContainer/InputsContainer/NameColumn/NameInput")
			_role_input = inputs_panel.get_node_or_null("MarginContainer/InputsContainer/RoleColumn/RoleInput")
			
			# Connect to text_changed for real-time updates
			if _name_input:
				_name_input.text_changed.connect(_on_name_changed)
			if _role_input:
				_role_input.text_changed.connect(_on_role_changed)
		
		# Connect to ship_launched to reset labels after launch
		if _console_panel and _console_panel.has_signal("ship_launched"):
			_console_panel.ship_launched.connect(_on_ship_launched)


func _on_name_changed(new_text: String) -> void:
	if name_label:
		if new_text.strip_edges().is_empty():
			name_label.text = DEFAULT_NAME
		else:
			name_label.text = new_text.to_upper()


func _on_role_changed(new_text: String) -> void:
	if role_label:
		if new_text.strip_edges().is_empty():
			role_label.text = DEFAULT_ROLE
		else:
			role_label.text = new_text


func _on_ship_launched(_name: String, _role: String, _texture: Texture2D) -> void:
	# Reset labels after ship launches
	if name_label:
		name_label.text = DEFAULT_NAME
	if role_label:
		role_label.text = DEFAULT_ROLE


func _sync_texture() -> void:
	if not sprite:
		return
	
	# Try to get texture from generator panel first
	if _generator_panel and _generator_panel.has_method("get_current_ship_texture"):
		var texture: Texture2D = _generator_panel.get_current_ship_texture()
		if texture:
			sprite.texture = texture
			sprite.scale = Vector2(preview_scale, preview_scale)
			return
	
	# Fallback: use our own loaded textures
	if not _loaded_textures.is_empty():
		if _current_index >= _loaded_textures.size():
			_current_index = 0
		sprite.texture = _loaded_textures[_current_index]
		sprite.scale = Vector2(preview_scale, preview_scale)


func _on_image_generated(_path: String) -> void:
	_sync_texture()


func _on_ship_selected(_index: int) -> void:
	_sync_texture()


## Set Y position as a ratio of screen height (called by DebugPanel)
func set_position_y_ratio(ratio: float) -> void:
	_position_y_ratio = ratio
	_update_position()


## Call this to manually set the preview texture
func set_preview_texture(texture: Texture2D) -> void:
	if sprite and texture:
		sprite.texture = texture
		sprite.scale = Vector2(preview_scale, preview_scale)


## Update the preview to match the generator panel's current selection
func refresh_preview() -> void:
	_sync_texture()


## Set the ship index directly (for standalone use)
func set_ship_index(index: int) -> void:
	_current_index = index
	_sync_texture()
