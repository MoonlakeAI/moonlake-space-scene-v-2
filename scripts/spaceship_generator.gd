extends PanelContainer

## Spaceship Generator Panel
## Calls backend API to generate spaceship images and saves them locally

signal image_generated(path: String, texture: Texture2D)
signal ship_selected(index: int)

## Structure for tracking generated ships: {timestamp: String, path: String, texture: Texture2D, prompt: String}
var _generated_ships: Array[Dictionary] = []

const SAVE_DIR := "user://generated_spaceships/"
const DEFAULT_PROMPT := "Side view of a sci-fi mining spaceship, dark gray metallic hull with yellow warning stripes, industrial mechanical design with drilling equipment and ore containers, bulky angular hull, elongated horizontal shape pointing right, single object on clean white background, heavy mining vessel, facing towards right, maintain the aspect ratio of the reference images"

const REFERENCE_IMAGES := [
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/military_frigate.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/mining_vessel.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/nimble_transport.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/speeder_3.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/speeder_1.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/speeder_2.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/spaceship_luxury_1.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/spaceship_luxury_2.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/spaceship_luxury_3.png"
]

const SHIP_TEXTURES: Array[String] = [
	"res://assets/images/spaceships/military_frigate.png",
	"res://assets/images/spaceships/mining_vessel.png",
	"res://assets/images/spaceships/nimble_transport.png"
]

@onready var generate_button: Button = $MarginContainer/VBoxContainer/GenerateButton
@onready var prompt_input: TextEdit = $MarginContainer/VBoxContainer/PromptInput
@onready var progress_bar: HBoxContainer = $MarginContainer/VBoxContainer/ProgressBar
@onready var reference_container: HBoxContainer = $MarginContainer/VBoxContainer/ReferenceScroll/ReferenceContainer

# Progress bar colors
const COLOR_FILLED := Color(0.3, 0.7, 0.8, 1.0)
const COLOR_EMPTY := Color(0.15, 0.3, 0.35, 0.5)

var _http_request: HTTPRequest
var _download_request: HTTPRequest
var _poll_timer: Timer
var _current_job_id: String = ""
var _current_prompt: String = ""
var _is_generating := false
var _progress_blocks: Array[ColorRect] = []
var _loaded_textures: Array[Texture2D] = []
var _current_ship_index: int = 0
var _generated_texture: Texture2D = null

# Reference selector state
var _reference_buttons: Array[TextureButton] = []
var _selected_reference_index: int = 0
var _reference_download_queue: Array = []
var _reference_textures: Array[Texture2D] = []

const THUMB_SIZE := Vector2(60, 40)
const SELECTED_COLOR := Color(0, 0.8, 1, 1)
const UNSELECTED_COLOR := Color(0.5, 0.6, 0.7, 0.6)


func _ready() -> void:
	# Setup HTTP request nodes
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_generate_request_completed)
	
	_download_request = HTTPRequest.new()
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_completed)
	
	# Setup poll timer
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 2.0
	_poll_timer.timeout.connect(_poll_job_status)
	add_child(_poll_timer)
	
	# Connect UI
	generate_button.pressed.connect(_on_generate_pressed)
	
	# Cache progress bar blocks
	for child in progress_bar.get_children():
		if child is ColorRect:
			_progress_blocks.append(child)
	
	# Set default prompt
	prompt_input.text = DEFAULT_PROMPT
	
	# Hide progress bar initially
	progress_bar.visible = false
	
	# Load ship textures and select initial ship
	_load_ship_textures()
	_select_random_ship()
	
	# Ensure save directory exists
	_ensure_save_dir()
	
	# Create reference selector buttons
	_create_reference_buttons()
	
	# Start loading reference images
	_start_loading_references()


func _load_ship_textures() -> void:
	for path in SHIP_TEXTURES:
		var texture = load(path) as Texture2D
		if texture:
			_loaded_textures.append(texture)


func _select_random_ship() -> void:
	if _loaded_textures.is_empty():
		return
	_current_ship_index = randi() % _loaded_textures.size()
	ship_selected.emit(_current_ship_index)


func get_current_ship_texture() -> Texture2D:
	if _current_ship_index < _loaded_textures.size():
		return _loaded_textures[_current_ship_index]
	return null


func _update_progress(percent: int) -> void:
	var filled_count := int(float(percent) / 100.0 * _progress_blocks.size())
	for i in range(_progress_blocks.size()):
		if i < filled_count:
			_progress_blocks[i].color = COLOR_FILLED
		else:
			_progress_blocks[i].color = COLOR_EMPTY


func _show_progress() -> void:
	progress_bar.visible = true
	_update_progress(0)


func _hide_progress() -> void:
	progress_bar.visible = false


func _ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _create_reference_buttons() -> void:
	# Clear existing buttons
	for child in reference_container.get_children():
		child.queue_free()
	_reference_buttons.clear()
	_reference_textures.clear()
	
	# Create a button for each reference image
	for i in range(REFERENCE_IMAGES.size()):
		var btn := TextureButton.new()
		btn.custom_minimum_size = THUMB_SIZE
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.ignore_texture_size = true
		
		# Add border panel behind button
		var panel := PanelContainer.new()
		panel.custom_minimum_size = THUMB_SIZE + Vector2(4, 4)
		
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0.05, 0.1, 0.8)
		style.border_color = UNSELECTED_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		panel.add_theme_stylebox_override("panel", style)
		
		# Center the button in the panel
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(center)
		center.add_child(btn)
		
		reference_container.add_child(panel)
		_reference_buttons.append(btn)
		_reference_textures.append(null)
		
		# Connect click handler
		var index := i
		btn.pressed.connect(func(): _on_reference_selected(index))
	
	# Select first by default
	_update_reference_selection(0)


func _start_loading_references() -> void:
	_reference_download_queue = REFERENCE_IMAGES.duplicate()
	_load_next_reference()


func _load_next_reference() -> void:
	if _reference_download_queue.is_empty():
		return
	
	var url: String = _reference_download_queue.pop_front()
	var index := REFERENCE_IMAGES.find(url)
	
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
			_on_reference_image_loaded(result, code, body, index)
			http.queue_free()
			# Load next image
			_load_next_reference()
	)
	http.request(url)


func _on_reference_image_loaded(result: int, code: int, body: PackedByteArray, index: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[SpaceshipGenerator] Failed to load reference %d" % index)
		return
	
	if index < 0 or index >= _reference_buttons.size():
		return
	
	# Load image from bytes
	var image := Image.new()
	var error := image.load_png_from_buffer(body)
	if error != OK:
		print("[SpaceshipGenerator] Failed to decode reference image %d" % index)
		return
	
	# Create texture and assign to button
	var texture := ImageTexture.create_from_image(image)
	_reference_textures[index] = texture
	_reference_buttons[index].texture_normal = texture


func _on_reference_selected(index: int) -> void:
	_update_reference_selection(index)


func _update_reference_selection(index: int) -> void:
	_selected_reference_index = index
	
	# Update visual state of all buttons
	for i in range(_reference_buttons.size()):
		var btn := _reference_buttons[i]
		var panel := btn.get_parent().get_parent() as PanelContainer
		if panel:
			var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				var new_style := style.duplicate() as StyleBoxFlat
				if i == index:
					new_style.border_color = SELECTED_COLOR
					new_style.shadow_color = Color(0, 0.6, 0.8, 0.5)
					new_style.shadow_size = 4
				else:
					new_style.border_color = UNSELECTED_COLOR
					new_style.shadow_size = 0
				panel.add_theme_stylebox_override("panel", new_style)


func _on_generate_pressed() -> void:
	if _is_generating:
		return
	
	var prompt := prompt_input.text.strip_edges()
	if prompt.is_empty():
		prompt = DEFAULT_PROMPT
	
	_start_generation(prompt)


func _start_generation(prompt: String) -> void:
	_is_generating = true
	_current_prompt = prompt
	generate_button.disabled = true
	generate_button.text = "BUILDING..."
	_show_progress()
	
	var url := Config.api_url("generate-image")
	
	# Use only the selected reference image
	var selected_refs: Array[String] = []
	if _selected_reference_index >= 0 and _selected_reference_index < REFERENCE_IMAGES.size():
		selected_refs.append(REFERENCE_IMAGES[_selected_reference_index])
	
	var body := JSON.stringify({
		"prompt": prompt,
		"aspect_ratio": "16:9",
		"reference_images": selected_refs,
		"remove_background": true
	})
	
	var headers := ["Content-Type: application/json"]
	var error := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		_on_error("Failed to send request (error: %d)" % error)


func _on_generate_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg := "Connection failed. "
		if result == HTTPRequest.RESULT_CANT_CONNECT:
			error_msg += "Is backend running at %s?" % Config.get_backend_url()
		_on_error(error_msg)
		return
	
	if response_code != 200:
		_on_error("Server error: HTTP %d" % response_code)
		return
	
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		_on_error("Invalid response")
		return
	
	var data: Dictionary = json as Dictionary
	var status: String = str(data.get("status", ""))
	
	print("[SpaceshipGenerator] Response: ", data)
	
	if status == "error":
		_on_error(str(data.get("error", "Unknown error")))
	elif status == "processing":
		_current_job_id = str(data.get("job_id", ""))
		generate_button.text = "BUILDING..."
		_poll_timer.start()
	elif status == "completed":
		_on_generation_complete(data)
	else:
		_on_error("Unknown status: " + status)


func _poll_job_status() -> void:
	if _current_job_id.is_empty():
		_poll_timer.stop()
		return
	
	var url := Config.api_url("job-status/" + _current_job_id)
	
	# Create a one-off request for polling
	var poll_request := HTTPRequest.new()
	add_child(poll_request)
	poll_request.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
			_on_poll_completed(result, code, headers, body)
			poll_request.queue_free()
	)
	poll_request.request(url)


func _on_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[SpaceshipGenerator] Poll error, retrying...")
		return
	
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		return
	
	var data: Dictionary = json as Dictionary
	var status: String = str(data.get("status", ""))
	var progress: int = int(data.get("progress", 0))
	
	print("[SpaceshipGenerator] Poll: status=%s, progress=%d" % [status, progress])
	
	if status == "completed":
		_poll_timer.stop()
		_on_generation_complete(data)
	elif status == "failed" or status == "error":
		_poll_timer.stop()
		_on_error(str(data.get("error", "Generation failed")))
	else:
		# Update progress bar
		_update_progress(progress)


func _on_generation_complete(data: Dictionary) -> void:
	# Check for base64 image data (with background removed)
	var image_data: String = str(data.get("image_data", ""))
	var image_url: String = str(data.get("image_url", ""))
	
	if not image_data.is_empty():
		# Decode base64 and save directly
		_save_base64_image(image_data)
	elif not image_url.is_empty():
		# Download from URL
		print("[SpaceshipGenerator] Downloading: ", image_url)
		var error := _download_request.request(image_url)
		if error != OK:
			_on_error("Failed to download image")
	else:
		_on_error("No image data returned")


func _save_base64_image(base64_data: String) -> void:
	# Decode base64 to bytes
	var image_bytes := Marshalls.base64_to_raw(base64_data)
	
	print("[SpaceshipGenerator] Decoded %d bytes from base64" % image_bytes.size())
	
	if image_bytes.is_empty():
		_on_error("Failed to decode image data")
		return
	
	# Generate unique filename
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename := "spaceship_%s.png" % timestamp
	var save_path := SAVE_DIR + filename
	var global_path := ProjectSettings.globalize_path(save_path)
	
	print("[SpaceshipGenerator] Saving to: ", global_path)
	
	# Save the image
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_buffer(image_bytes)
		file.close()
		print("[SpaceshipGenerator] Saved successfully!")
		
		# Store generated texture and track the ship
		_store_generated_texture(image_bytes, save_path)
		
		image_generated.emit(save_path, _generated_texture)
		_play_success_effect()
	else:
		var err := FileAccess.get_open_error()
		_on_error("Failed to save: error %d" % err)
	
	_reset_state()


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_on_error("Download failed")
		return
	
	# Generate unique filename
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename := "spaceship_%s.png" % timestamp
	var save_path := SAVE_DIR + filename
	
	# Save the image
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()
		print("[SpaceshipGenerator] Saved: ", save_path)
		
		# Store generated texture and track the ship
		_store_generated_texture(body, save_path)
		
		image_generated.emit(save_path, _generated_texture)
		_play_success_effect()
	else:
		_on_error("Failed to save image")
	
	_reset_state()


func _store_generated_texture(image_bytes: PackedByteArray, save_path: String) -> void:
	# Load image from bytes
	var image := Image.new()
	var error := image.load_png_from_buffer(image_bytes)
	
	if error != OK:
		print("[SpaceshipGenerator] Failed to load image, error: ", error)
		return
	
	print("[SpaceshipGenerator] Image loaded: %dx%d" % [image.get_width(), image.get_height()])
	
	# Create texture from image
	_generated_texture = ImageTexture.create_from_image(image)
	
	# Track this generated ship
	var timestamp := Time.get_datetime_string_from_system()
	_generated_ships.append({
		"timestamp": timestamp,
		"path": save_path,
		"texture": _generated_texture,
		"prompt": _current_prompt.substr(0, 50) + "..." if _current_prompt.length() > 50 else _current_prompt
	})
	print("[SpaceshipGenerator] Tracked generated ship #%d" % _generated_ships.size())


func _on_error(message: String) -> void:
	print("[SpaceshipGenerator] Error: ", message)
	_reset_state()


func _reset_state() -> void:
	_is_generating = false
	_current_job_id = ""
	generate_button.disabled = false
	generate_button.text = ">> BUILD <<"
	_poll_timer.stop()
	_hide_progress()


func _play_success_effect() -> void:
	var tween := create_tween()
	generate_button.modulate = Color(0.5, 1.0, 0.8, 1.0)
	tween.tween_property(generate_button, "modulate", Color.WHITE, 0.4)


## Returns the currently generated texture (or current ship texture if none generated)
func get_generated_texture() -> Texture2D:
	if _generated_texture != null:
		return _generated_texture
	return get_current_ship_texture()


## Returns the list of all generated ships for tracking
func get_generated_ships() -> Array[Dictionary]:
	return _generated_ships


## Returns the count of generated ships
func get_generated_ships_count() -> int:
	return _generated_ships.size()
