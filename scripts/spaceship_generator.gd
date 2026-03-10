extends PanelContainer

## Spaceship Generator Panel
## Calls backend API to generate spaceship images and saves them locally

signal image_generated(path: String)

const SAVE_DIR := "user://generated_spaceships/"
const DEFAULT_PROMPT := "Side view of a sci-fi mining spaceship, dark gray metallic hull with yellow warning stripes, industrial mechanical design with drilling equipment and ore containers, bulky angular hull, elongated horizontal shape pointing right, single object on clean white background, heavy mining vessel, facing towards right, maintain the aspect ratio of the reference images"

const REFERENCE_IMAGES := [
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/military_frigate.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/mining_vessel.png",
	"https://spatio-social-media.s3.us-east-1.amazonaws.com/gdc-demo-assets/nimble_transport.png"
]

const SHIP_TEXTURES: Array[String] = [
	"res://assets/images/spaceships/military_frigate.png",
	"res://assets/images/spaceships/mining_vessel.png",
	"res://assets/images/spaceships/nimble_transport.png"
]

@onready var generate_button: Button = $MarginContainer/VBoxContainer/GenerateButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusRow/StatusLabel
@onready var ship_preview: TextureRect = $MarginContainer/VBoxContainer/StatusRow/ShipPreview
@onready var preview_section: VBoxContainer = $MarginContainer/VBoxContainer/PreviewSection
@onready var preview_header: Button = $MarginContainer/VBoxContainer/PreviewSection/PreviewHeader
@onready var preview_container: PanelContainer = $MarginContainer/VBoxContainer/PreviewSection/PreviewContainer
@onready var preview_image: TextureRect = $MarginContainer/VBoxContainer/PreviewSection/PreviewContainer/PreviewImage
@onready var code_button: Button = $MarginContainer/VBoxContainer/TitleRow/CodeButton
@onready var progress_bar: HBoxContainer = $MarginContainer/VBoxContainer/ProgressBar

# Prompt overlay references (sibling node under ConsoleUI)
@onready var prompt_overlay: PanelContainer = $"../PromptOverlay"
@onready var prompt_input: TextEdit = $"../PromptOverlay/MarginContainer/VBoxContainer/PromptInput"
@onready var close_button: Button = $"../PromptOverlay/MarginContainer/VBoxContainer/HeaderRow/CloseButton"
@onready var apply_button: Button = $"../PromptOverlay/MarginContainer/VBoxContainer/ApplyButton"

# Progress bar colors
const COLOR_FILLED := Color(0.3, 0.7, 0.8, 1.0)
const COLOR_EMPTY := Color(0.15, 0.3, 0.35, 0.5)
const GEAR_SPIN_SPEED := 2.0

var _http_request: HTTPRequest
var _download_request: HTTPRequest
var _poll_timer: Timer
var _current_job_id: String = ""
var _is_generating := false
var _current_prompt: String = DEFAULT_PROMPT
var _progress_blocks: Array[ColorRect] = []
var _gear_rotation: float = 0.0
var _loaded_textures: Array[Texture2D] = []
var _current_ship_index: int = 0
var _preview_collapsed: bool = false
var _generated_texture: Texture2D = null


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
	code_button.pressed.connect(_on_code_button_pressed)
	close_button.pressed.connect(_on_close_overlay)
	apply_button.pressed.connect(_on_apply_prompt)
	preview_header.pressed.connect(_toggle_preview)
	
	# Cache progress bar blocks
	for child in progress_bar.get_children():
		if child is ColorRect:
			_progress_blocks.append(child)
	
	# Set gear button pivot for rotation
	code_button.pivot_offset = code_button.size / 2
	
	# Set default prompt
	prompt_input.text = _current_prompt
	
	# Hide preview section, overlay, and progress bar initially
	preview_section.visible = false
	prompt_overlay.visible = false
	progress_bar.visible = false
	
	# Load ship textures and show initial preview
	_load_ship_textures()
	_select_random_ship()
	
	# Ensure save directory exists
	_ensure_save_dir()


func _load_ship_textures() -> void:
	for path in SHIP_TEXTURES:
		var texture = load(path) as Texture2D
		if texture:
			_loaded_textures.append(texture)


func _select_random_ship() -> void:
	if _loaded_textures.is_empty():
		return
	_current_ship_index = randi() % _loaded_textures.size()
	ship_preview.texture = _loaded_textures[_current_ship_index]


func get_current_ship_texture() -> Texture2D:
	if _current_ship_index < _loaded_textures.size():
		return _loaded_textures[_current_ship_index]
	return null


func _process(delta: float) -> void:
	# Spin gear icon when generating
	if _is_generating:
		_gear_rotation += delta * GEAR_SPIN_SPEED
		code_button.rotation = _gear_rotation
	else:
		code_button.rotation = 0.0


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


func _on_code_button_pressed() -> void:
	prompt_input.text = _current_prompt
	prompt_overlay.visible = true


func _on_close_overlay() -> void:
	prompt_overlay.visible = false


func _on_apply_prompt() -> void:
	_current_prompt = prompt_input.text
	prompt_overlay.visible = false
	status_label.text = "Prompt updated"


func _ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _on_generate_pressed() -> void:
	if _is_generating:
		status_label.text = "Already generating..."
		return
	
	var prompt := _current_prompt.strip_edges()
	if prompt.is_empty():
		status_label.text = "Please enter a prompt"
		return
	
	_start_generation(prompt)


func _start_generation(prompt: String) -> void:
	_is_generating = true
	generate_button.disabled = true
	status_label.text = "Connecting..."
	preview_container.visible = false
	_show_progress()
	
	var url := Config.api_url("generate-image")
	var body := JSON.stringify({
		"prompt": prompt,
		"aspect_ratio": "16:9",
		"reference_images": REFERENCE_IMAGES,
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
		status_label.text = "Generating spaceship..."
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
		# Update progress bar and status message
		_update_progress(progress)
		if progress < 30:
			status_label.text = "Generating image..."
		elif progress < 80:
			status_label.text = "Processing..."
		else:
			status_label.text = "Removing background..."


func _on_generation_complete(data: Dictionary) -> void:
	# Check for base64 image data (with background removed)
	var image_data: String = str(data.get("image_data", ""))
	var image_url: String = str(data.get("image_url", ""))
	
	if not image_data.is_empty():
		# Decode base64 and save directly
		status_label.text = "Saving image..."
		_save_base64_image(image_data)
	elif not image_url.is_empty():
		# Download from URL
		status_label.text = "Downloading image..."
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
		status_label.text = "Saved: " + filename
		
		# Show preview
		_show_preview(image_bytes)
		
		image_generated.emit(save_path)
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
		status_label.text = "Saved!"
		
		# Show preview
		_show_preview(body)
		
		image_generated.emit(save_path)
		_play_success_effect()
	else:
		_on_error("Failed to save image")
	
	_reset_state()


func _show_preview(image_bytes: PackedByteArray) -> void:
	# Load image from bytes
	var image := Image.new()
	var error := image.load_png_from_buffer(image_bytes)
	
	if error != OK:
		print("[SpaceshipGenerator] Failed to load preview image, error: ", error)
		return
	
	print("[SpaceshipGenerator] Image loaded: %dx%d, format: %d" % [image.get_width(), image.get_height(), image.get_format()])
	
	# Create texture from image
	var texture := ImageTexture.create_from_image(image)
	_generated_texture = texture  # Store for Crew Deployment to use
	
	preview_image.texture = texture
	preview_container.visible = true
	
	# Show the preview section (collapsible)
	preview_section.visible = true
	_preview_collapsed = false
	preview_header.text = "▼ Generated Preview"
	
	# Update the ship preview next to "Ready For Deployment"
	ship_preview.texture = texture
	status_label.text = "Ready For Deployment"
	
	print("[SpaceshipGenerator] Preview texture set, size: ", preview_image.size)


func _on_error(message: String) -> void:
	print("[SpaceshipGenerator] Error: ", message)
	status_label.text = "Error: " + message
	_reset_state()


func _reset_state() -> void:
	_is_generating = false
	_current_job_id = ""
	generate_button.disabled = false
	_poll_timer.stop()
	_hide_progress()


func _play_success_effect() -> void:
	var tween := create_tween()
	generate_button.modulate = Color(0.5, 1.0, 0.8, 1.0)
	tween.tween_property(generate_button, "modulate", Color.WHITE, 0.4)


func _toggle_preview() -> void:
	_preview_collapsed = !_preview_collapsed
	preview_container.visible = !_preview_collapsed
	
	# Update header text with arrow indicator
	if _preview_collapsed:
		preview_header.text = "▶ Generated Preview"
	else:
		preview_header.text = "▼ Generated Preview"


## Returns the currently generated texture (or current ship texture if none generated)
func get_generated_texture() -> Texture2D:
	if _generated_texture != null:
		return _generated_texture
	return get_current_ship_texture()
