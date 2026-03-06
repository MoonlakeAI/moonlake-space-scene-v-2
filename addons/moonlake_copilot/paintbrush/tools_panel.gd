@tool
extends Panel

## Tools Panel - Bottom toolbar with drawing tools

const PythonBridge = preload("res://addons/moonlake_copilot/core/python_bridge.gd")

@onready var paint_root = _find_paint_root()
@onready var paint_control = paint_root.get_node_or_null("CanvasContainer/PaintControl") if paint_root else null
@onready var preview_control = paint_root.get_node_or_null("CanvasContainer/PreviewControl") if paint_root else null
@onready var image_preview = paint_root.get_node_or_null("CanvasContainer/PreviewControl/ImagePreview") if paint_root else null
@onready var clear_button = paint_root.get_node_or_null("CanvasContainer/ClearButton") if paint_root else null

# Bottom toolbar controls
@onready var button_pencil = $HBoxContainer/ButtonToolPencil
@onready var button_eraser = $HBoxContainer/ButtonToolEraser
@onready var color_picker = $HBoxContainer/ColorPickerButton
@onready var brush_size_slider = $HBoxContainer/HSliderBrushSize
@onready var brush_size_label = $HBoxContainer/LabelBrushSize

# Prompt section
@onready var prompt_input = paint_root.get_node_or_null("PromptSection/PromptInput") if paint_root else null
@onready var generate_button = paint_root.get_node_or_null("PromptSection/GenerateButton") if paint_root else null
@onready var upload_button = paint_root.get_node_or_null("PromptSection/UploadButton") if paint_root else null
@onready var capture_button = paint_root.get_node_or_null("PromptSection/CaptureButton") if paint_root else null

# File dialog for image upload
var file_dialog: FileDialog = null

# Store uploaded file info
var uploaded_file_id: String = ""
var uploaded_file_url: String = ""

# Track if prompt API call is in progress
var api_in_progress: bool = false

func _find_paint_root() -> Control:
	var current = get_parent()
	while current:
		if current.name == "PaintRoot" or current.name == "TerrainRoot":
			return current
		current = current.get_parent()
	return null

func _ready():
	if not paint_control:
		Log.error("[ToolsPanel] paint_control not found!")
		return

	# Connect tool buttons
	button_pencil.pressed.connect(_on_pencil_pressed)
	button_eraser.pressed.connect(_on_eraser_pressed)

	# Connect color picker
	color_picker.color_changed.connect(_on_color_changed)

	# Connect brush size slider
	brush_size_slider.value_changed.connect(_on_brush_size_changed)

	# Connect clear button
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)

	# Connect generate button (but not for TerrainRoot - plugin.gd handles that)
	if generate_button and paint_root and paint_root.name == "PaintRoot":
		generate_button.pressed.connect(_on_generate_pressed)

	# Connect upload button
	if upload_button:
		upload_button.pressed.connect(_on_upload_pressed)

	# Connect capture button (terrain dialog only)
	if capture_button and paint_root and paint_root.name == "TerrainRoot":
		capture_button.pressed.connect(_on_capture_terrain_pressed)

	# Connect prompt input Ctrl+Enter key (TextEdit doesn't have text_submitted signal)
	if prompt_input:
		prompt_input.gui_input.connect(_on_prompt_input_gui_input)

	# Initialize brush size label
	_on_brush_size_changed(brush_size_slider.value)

	# Connect to window close event for cleanup
	call_deferred("_connect_window_close")

func _on_pencil_pressed() -> void:
	if paint_control:
		paint_control.brush_mode = paint_control.BrushModes.PENCIL

func _on_eraser_pressed() -> void:
	if paint_control:
		paint_control.brush_mode = paint_control.BrushModes.ERASER

func _on_color_changed(color: Color) -> void:
	if paint_control:
		paint_control.brush_color = color

func _on_brush_size_changed(value: float) -> void:
	if paint_control:
		paint_control.brush_size = int(value)

	# Update label with formatted value (e.g., " 3.2" or "10.0")
	var display_value = value / 10.0  # Scale down for display
	brush_size_label.text = "%4.1f" % display_value

func _on_clear_pressed() -> void:
	# Clear canvas drawing
	if paint_control:
		paint_control.brush_data_list = []
		paint_control.stroke_history = []
		paint_control.queue_redraw()

	# Clear uploaded image preview
	if image_preview:
		image_preview.texture = null

	uploaded_file_id = ""
	uploaded_file_url = ""

	# Hide preview, show paint control
	if preview_control:
		preview_control.visible = false
	if paint_control:
		paint_control.visible = true

	# Re-enable drawing tools
	_set_drawing_enabled(true)

func _on_generate_pressed(custom_message: String = "") -> void:
	"""Generate avatar/terrain from uploaded image or canvas sketch

	Args:
		custom_message: Optional custom message prefix. If empty, defaults to "generate an avatar from this image: "
	"""
	# Get references
	var refs = _get_plugin_and_bridge()
	if not refs:
		Log.error("[ToolsPanel] Failed to get plugin/bridge references")
		return

	var python_bridge = refs.python_bridge
	var image_url = ""

	# NEW: Check if user only typed text without any image work
	var prompt_text = prompt_input.text.strip_edges() if prompt_input else ""
	var has_canvas = paint_control and paint_control.brush_data_list.size() > 0
	var has_uploaded = not uploaded_file_url.is_empty()
	var has_preview = preview_control and preview_control.visible and image_preview and image_preview.texture
	var has_any_image = has_canvas or has_uploaded or has_preview

	if prompt_text.length() > 0 and not has_any_image:
		# User typed text but did no image work - send to main copilot
		_send_mini_prompt_to_copilot(prompt_text)
		return

	# Get file_id and file_url (either from uploaded file or fresh upload)
	var file_id = ""
	var file_url = ""

	# Check if user uploaded an image
	if not uploaded_file_url.is_empty():
		# Use uploaded file info directly
		file_id = uploaded_file_id
		file_url = uploaded_file_url
	else:
		# Validate: Check if canvas has any drawing OR preview image (captured terrain)
		# (has_canvas and has_preview already declared above for text-only check)
		if not has_canvas and not has_preview:
			_add_status_message("Error: Please draw something or upload an image first")
			return

		# Export canvas sketch/preview and upload
		_add_status_message("Uploading image to S3...")

		var image_data = await _export_canvas_to_buffer()
		if not image_data:
			_add_status_message("Error: Failed to export canvas")
			return

		var upload_result = await _upload_image_to_s3(python_bridge, image_data, "sketch.png")
		if upload_result.is_empty():
			_add_status_message("Error: Failed to upload image")
			return

		_add_status_message("Upload Complete")
		file_id = upload_result.get("file_id", "")
		file_url = upload_result.get("file_url", "")

	# Determine message based on context
	var message = ""
	var file_ids = [file_id] if not file_id.is_empty() else []
	var files = []
	if not file_id.is_empty():
		files.append({"id": file_id, "file_url": file_url, "filename": file_id})

	if custom_message.is_empty():
		# Default: avatar generation (agent knows to look at attached file)
		message = "generate an avatar from the attached image"
	else:
		# Custom message (e.g., for terrain)
		message = custom_message

	_send_copilot_message(python_bridge, message, file_ids, files)

	# Close the paint window
	_close_paint_window()

func _on_upload_pressed() -> void:
	"""Open file picker to select an image"""
	# Disable drawing immediately to prevent race condition with double-click
	_set_drawing_enabled(false)

	# Create file dialog if it doesn't exist
	if not file_dialog:
		file_dialog = FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp", "Image Files")
		file_dialog.file_selected.connect(_on_file_selected)
		file_dialog.canceled.connect(_on_file_dialog_canceled)
		# Set larger size
		file_dialog.size = Vector2i(1200, 800)
		file_dialog.min_size = Vector2i(800, 600)
		add_child(file_dialog)

	# Set initial directory to Desktop
	var desktop_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if not desktop_path.is_empty():
		file_dialog.current_dir = desktop_path

	# Show file picker
	file_dialog.popup_centered()

func _on_file_selected(file_path: String) -> void:
	"""Handle file selection - load preview and upload to S3"""
	Log.info("[ToolsPanel] File selected: %s" % file_path)

	# Load image for preview
	var image = Image.load_from_file(file_path)
	if not image:
		_add_status_message("Error: Failed to load image")
		# On early errors (before image is displayed), re-enable drawing
		if preview_control:
			preview_control.visible = false
		if paint_control:
			paint_control.visible = true
		_set_drawing_enabled(true)
		return

	# Display image in preview
	if image_preview:
		# Free old texture to prevent memory leak
		if image_preview.texture:
			image_preview.texture = null

		var texture = ImageTexture.create_from_image(image)
		image_preview.texture = texture
	else:
		Log.error("[ToolsPanel] image_preview node is NULL!")

	# Clear the paint canvas since we're using an uploaded image
	if paint_control:
		paint_control.brush_data_list.clear()
		paint_control.queue_redraw()
		paint_control.visible = false

	if preview_control:
		preview_control.visible = true

	# Drawing is already disabled from _on_upload_pressed()

	# Get references
	var refs = _get_plugin_and_bridge()
	if not refs:
		Log.error("[ToolsPanel] Failed to get plugin/bridge references")
		return

	var python_bridge = refs.python_bridge

	# Read file as bytes
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		_add_status_message("Error: Failed to read file")
		# On early errors (before image is displayed), re-enable drawing
		if preview_control:
			preview_control.visible = false
		if paint_control:
			paint_control.visible = true
		_set_drawing_enabled(true)
		return

	var file_bytes = file.get_buffer(file.get_length())
	file.close()

	if file_bytes.size() == 0:
		_add_status_message("Error: File is empty")
		# On early errors (before image is displayed), re-enable drawing
		if preview_control:
			preview_control.visible = false
		if paint_control:
			paint_control.visible = true
		_set_drawing_enabled(true)
		return

	# Get filename for upload
	var filename = file_path.get_file()

	# Upload via python_bridge
	var upload_result = await _upload_image_to_s3(python_bridge, file_bytes, filename)
	if upload_result.is_empty():
		_add_status_message("Error: Failed to upload image. Click 'Clear' to go back to drawing.")
		# Keep the image preview visible so user can see what they tried to upload
		# They can click Clear to dismiss it and go back to drawing
		return

	# Store the uploaded file info
	uploaded_file_id = upload_result.get("file_id", "")
	uploaded_file_url = upload_result.get("file_url", "")

	# Show ready status
	_add_status_message("Image ready! Click 'Generate 3D Avatar' to continue.")


func _on_file_dialog_canceled() -> void:
	"""Handle file dialog cancellation - re-enable drawing"""
	# Re-enable drawing since user didn't upload an image
	_set_drawing_enabled(true)


func _on_capture_terrain_pressed() -> void:
	"""Capture top-down screenshot of current terrain and display it"""
	# Get references
	var refs = _get_plugin_and_bridge()
	if refs.is_empty():
		Log.error("[ToolsPanel] Plugin/bridge not available")
		_add_status_message("Error: Plugin not available")
		return

	var plugin_ref = refs["plugin_ref"]

	# Get current scene and find terrain
	var current_scene = EditorInterface.get_edited_scene_root()
	if not current_scene:
		_add_status_message("Error: No scene open")
		return

	var terrain_nodes = current_scene.find_children("*", "Terrain3D", true, false)
	if terrain_nodes.size() == 0:
		_add_status_message("Error: No terrain found in scene.\nCreate a terrain first or open a scene with terrain.")
		return

	var terrain = terrain_nodes[0]

	# Show loading state
	if capture_button:
		capture_button.disabled = true
		capture_button.text = "⏳ Capturing..."

	# Capture terrain screenshot
	_add_status_message("Capturing terrain...")
	var captured_image = await _capture_terrain_screenshot(terrain, current_scene)

	# Restore button state
	if capture_button:
		capture_button.disabled = false
		capture_button.text = "📷 Capture Current Terrain"

	if not captured_image:
		_add_status_message("Error: Failed to capture terrain.\nCheck that terrain is visible and properly loaded.")
		return

	# Display captured image in preview
	var texture = ImageTexture.create_from_image(captured_image)
	if image_preview:
		# Free old texture to prevent memory leak
		if image_preview.texture:
			image_preview.texture = null
		image_preview.texture = texture
	else:
		Log.error("[ToolsPanel] image_preview node is NULL!")

	# Hide paint control, show preview control
	if paint_control:
		paint_control.brush_data_list.clear()
		paint_control.queue_redraw()
		paint_control.visible = false

	if preview_control:
		preview_control.visible = true

	# Disable drawing tools since we're showing captured image
	_set_drawing_enabled(false)

	_add_status_message("Terrain captured! Click 'Create Terrain' to generate")


func _capture_terrain_screenshot(terrain: Node, scene_root: Node) -> Image:
	"""Capture a top-down screenshot of the terrain using SubViewport

	Args:
		terrain: The Terrain3D node to capture
		scene_root: The current scene root node

	Returns:
		Image: Captured terrain image, or null if failed
	"""
	# Create SubViewport for isolated rendering
	var sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(1024, 1024)  # Capture at 1024x1024
	sub_viewport.transparent_bg = false
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Create Camera3D for top-down view
	var capture_camera = Camera3D.new()

	# Calculate terrain bounds from active regions
	var terrain_data = terrain.get_data()
	var active_regions = terrain_data.get_regions_active()

	if active_regions.size() == 0:
		Log.error("[ToolsPanel] No active terrain regions found")
		return null

	# Get region size and vertex spacing
	var region_size = terrain.get_region_size()
	var vertex_spacing = terrain.get_vertex_spacing()
	var region_world_size = region_size * vertex_spacing

	# Calculate bounds from all active regions
	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF

	for region in active_regions:
		var loc: Vector2i = region.location
		var region_min_x = loc.x * region_world_size
		var region_max_x = region_min_x + region_world_size
		var region_min_z = loc.y * region_world_size
		var region_max_z = region_min_z + region_world_size

		min_x = min(min_x, region_min_x)
		max_x = max(max_x, region_max_x)
		min_z = min(min_z, region_min_z)
		max_z = max(max_z, region_max_z)

	# Calculate center and size
	var terrain_center_x = (min_x + max_x) / 2.0
	var terrain_center_z = (min_z + max_z) / 2.0
	var terrain_width = max_x - min_x
	var terrain_depth = max_z - min_z
	var terrain_size = max(terrain_width, terrain_depth)

	# Position camera above terrain center
	var terrain_position = terrain.global_position
	var camera_height = 1000.0  # Fixed height for orthographic camera

	capture_camera.position = terrain_position + Vector3(terrain_center_x, camera_height, terrain_center_z)
	capture_camera.rotation_degrees = Vector3(-90, 0, 0)  # Look straight down
	capture_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	capture_camera.size = terrain_size * 0.55  # Orthographic size to fit all regions

	# Add camera to viewport
	sub_viewport.add_child(capture_camera)

	# Create WorldEnvironment with basic lighting
	var world_env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.background_color = Color(0.53, 0.81, 0.92)  # Sky blue
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 1, 1)
	environment.ambient_light_energy = 1.0
	world_env.environment = environment
	sub_viewport.add_child(world_env)

	# Add DirectionalLight3D for better terrain visibility
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sub_viewport.add_child(sun)

	# Add SubViewport to scene temporarily (required for rendering)
	scene_root.add_child(sub_viewport)

	# Force viewport to render
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw  # Wait 2 frames to ensure rendering

	# Capture image from viewport
	var img = sub_viewport.get_texture().get_image()

	# Cleanup
	scene_root.remove_child(sub_viewport)
	sub_viewport.queue_free()

	if not img:
		Log.error("[ToolsPanel] Failed to capture viewport image")
		return null

	# Flip Y-axis (viewport rendering is upside down)
	img.flip_y()

	return img


## ============================================================================
## Prompt API Integration
## ============================================================================

func _on_prompt_input_gui_input(event: InputEvent) -> void:
	"""Handle Ctrl+Enter in TextEdit prompt input"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
			# Ctrl+Enter or Cmd+Enter to submit
			if prompt_input:
				_on_prompt_submitted(prompt_input.text)
				# Accept the event to prevent it from adding a newline
				prompt_input.get_viewport().set_input_as_handled()

func _on_prompt_submitted(text: String) -> void:
	"""Handle prompt submission - call API to modify image"""
	# Guard: Block if API in progress
	if api_in_progress:
		_add_status_message("Please wait, processing previous request...")
		return

	# Guard: Empty prompt
	text = text.strip_edges()
	if text.is_empty():
		return

	# Check for text-only scenario (same logic as Generate button)
	var has_uploaded = not uploaded_file_url.is_empty()
	var has_drawn = paint_control and paint_control.brush_data_list.size() > 0
	var has_preview = preview_control and preview_control.visible and image_preview and image_preview.texture

	if not has_uploaded and not has_drawn and not has_preview:
		# Text-only scenario - redirect to main copilot
		_send_mini_prompt_to_copilot(text)
		return

	# Clear prompt input (user expects this in chat UIs)
	prompt_input.text = ""

	# Disable buttons during API call
	_set_prompt_buttons_enabled(false)
	api_in_progress = true

	# Show loading in prompt placeholder
	var original_placeholder = prompt_input.placeholder_text
	prompt_input.placeholder_text = "⏳ Preparing image..."

	# Get S3 URL for image
	var s3_url = ""

	if has_uploaded:
		# Already have S3 URL
		s3_url = uploaded_file_url
	else:
		# Upload canvas to S3 first
		s3_url = await _upload_canvas_to_s3()

	if s3_url.is_empty():
		_add_status_message("Error: Failed to prepare image")
		api_in_progress = false
		_set_prompt_buttons_enabled(true)
		prompt_input.placeholder_text = original_placeholder
		return

	# Wait 1.5 seconds to ensure S3 image is fully available
	await get_tree().create_timer(1.5).timeout

	prompt_input.placeholder_text = "⏳ Generating with AI (30-60s)..."
	var response = await _call_edit_image_api(text, s3_url)

	# Handle failure
	if not response.get("ok", false):
		var error_msg = response.get("error", "Unknown error")
		_add_status_message("Error: " + error_msg)
		api_in_progress = false
		_set_prompt_buttons_enabled(true)
		prompt_input.placeholder_text = original_placeholder
		return

	# Extract result
	var result = response.get("result", {})
	if not result.get("success", false):
		var error_msg = result.get("error", "API returned error")
		_add_status_message("Error: " + error_msg)
		api_in_progress = false
		_set_prompt_buttons_enabled(true)
		prompt_input.placeholder_text = original_placeholder
		return

	# Get modified image URL
	var modified_image_url = result.get("image_url", "")
	if modified_image_url.is_empty():
		_add_status_message("Error: No image returned from API")
		api_in_progress = false
		_set_prompt_buttons_enabled(true)
		prompt_input.placeholder_text = original_placeholder
		return

	# Download and display modified image
	var success = await _download_and_display_image(modified_image_url)
	if not success:
		_add_status_message("Error: Failed to download modified image")
		api_in_progress = false
		_set_prompt_buttons_enabled(true)
		prompt_input.placeholder_text = original_placeholder
		return

	# Update uploaded_file_url so "Generate" button uses the modified image
	uploaded_file_url = modified_image_url

	# Success!
	_add_status_message("Image updated!")
	api_in_progress = false
	_set_prompt_buttons_enabled(true)
	prompt_input.placeholder_text = original_placeholder


func _call_edit_image_api(prompt: String, image_url: String) -> Dictionary:
	"""Call the real edit_image API via python_bridge"""
	var refs = _get_plugin_and_bridge()
	if refs.is_empty():
		return {"ok": false, "error": "Plugin/bridge not available"}

	var python_bridge = refs.python_bridge
	var project_id = paint_root.plugin_ref.chat_panel.current_project_id

	# Pre-flight validation
	if project_id.is_empty():
		return {"ok": false, "error": "No project loaded"}

	# Get session_token from chat_panel
	var session_token = ""
	var chat_panel = paint_root.plugin_ref.chat_panel
	if chat_panel and "session_token" in chat_panel:
		session_token = chat_panel.session_token

	if session_token.is_empty():
		return {"ok": false, "error": "Not authenticated. Please login first."}

	if image_url.is_empty():
		return {"ok": false, "error": "Missing image URL"}

	# Call Python worker with 60s timeout (Gemini is slow)
	var response = await python_bridge.call_python_async("edit_image", {
		"image_url": image_url,
		"prompt": prompt,
		"session_token": session_token
	}, 60.0)

	# Check Python bridge response
	if not response.get("ok", false):
		var error_msg = response.get("error", "Unknown error")
		return {"ok": false, "error": error_msg}

	# Check API result
	var result = response.get("result", {})
	if not result.get("success", false):
		var error_msg = result.get("error", "API call failed")
		return {"ok": false, "error": error_msg}

	# Success
	return {
		"ok": true,
		"result": {
			"success": true,
			"image_url": result.get("edited_image_url", ""),
			"name": result.get("name", "")
		}
	}


func _download_and_display_image(image_url: String) -> bool:
	"""Download edited image from S3 and display in preview"""
	if image_url.is_empty():
		Log.error("[ToolsPanel] Empty image URL")
		return false

	# Use HTTPRequestPool for efficient downloading
	var http_pool = _ensure_http_pool()
	if not http_pool:
		Log.error("[ToolsPanel] Failed to get HTTPRequestPool")
		return false

	var download_complete = false
	var success = false

	http_pool.fetch(image_url, func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			Log.error("[ToolsPanel] Download failed: result=%d, status=%d" % [result, response_code])
			download_complete = true
			return

		var image = Image.new()
		var error = image.load_png_from_buffer(body)
		if error != OK:
			Log.error("[ToolsPanel] Failed to load PNG: %s" % error_string(error))
			download_complete = true
			return

		_display_image_in_preview(image)
		success = true
		download_complete = true
	)

	# Wait for download (max 10s)
	var max_wait = 10.0
	var elapsed = 0.0
	while not download_complete and elapsed < max_wait:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	return success


func _display_image_in_preview(image: Image) -> void:
	"""Display an image in the preview control, replacing any existing image"""
	if not image_preview:
		Log.error("[ToolsPanel] image_preview is null")
		return

	# Free old texture to prevent memory leak
	if image_preview.texture:
		image_preview.texture = null

	# Create new texture from image
	var texture = ImageTexture.create_from_image(image)
	image_preview.texture = texture

	# Show preview control, hide paint control
	if preview_control:
		preview_control.visible = true
	if paint_control:
		paint_control.visible = false

	# Disable drawing (image is now displayed)
	_set_drawing_enabled(false)

## ============================================================================
## Helper Functions
## ============================================================================

func _get_plugin_and_bridge() -> Dictionary:
	"""Get plugin and python_bridge references from paint_root"""
	if not paint_root:
		Log.error("[ToolsPanel] paint_root not found")
		return {}

	if not paint_root.plugin_ref:
		Log.error("[ToolsPanel] plugin_ref not set on paint_root")
		return {}

	if not paint_root.python_bridge:
		Log.error("[ToolsPanel] python_bridge not set on paint_root")
		return {}

	return {
		"plugin_ref": paint_root.plugin_ref,
		"python_bridge": paint_root.python_bridge
	}

func _export_canvas_to_buffer() -> PackedByteArray:
	"""Export canvas drawing OR preview image to PNG buffer"""
	# Check if showing preview image instead of canvas (e.g., captured terrain or uploaded image)
	if preview_control and preview_control.visible and image_preview and image_preview.texture:
		# Export the preview image directly
		var preview_texture = image_preview.texture

		# ImageTexture needs different handling than regular Texture2D
		var preview_image: Image = null
		if preview_texture is ImageTexture:
			preview_image = preview_texture.get_image()
		else:
			Log.error("[ToolsPanel] Preview texture is not ImageTexture: %s" % preview_texture.get_class())
			return PackedByteArray()

		if not preview_image:
			Log.error("[ToolsPanel] Failed to get image from preview texture")
			return PackedByteArray()

		# Convert to PNG buffer
		var png_buffer = preview_image.save_png_to_buffer()
		return png_buffer

	# Otherwise, export canvas drawing
	if not paint_control:
		Log.error("[ToolsPanel] paint_control not found")
		return PackedByteArray()

	# Hide UI widgets before capturing (Clear button, etc)
	var widgets_to_hide = []
	if clear_button:
		widgets_to_hide.append(clear_button)

	for widget in widgets_to_hide:
		if widget:
			widget.hide()

	# Wait for frame to complete
	await RenderingServer.frame_post_draw

	# Get viewport image
	var img = paint_control.get_viewport().get_texture().get_image()

	# Show UI widgets again
	for widget in widgets_to_hide:
		if widget:
			widget.show()

	# Crop to canvas area
	var tl_node = paint_control.get_node("TLPos")
	if not tl_node:
		Log.error("[ToolsPanel] TLPos node not found")
		return PackedByteArray()

	var image_size = Vector2(660, 660)
	var cropped_image = img.get_region(Rect2(tl_node.global_position, image_size))

	# Convert to PNG buffer
	var png_buffer = cropped_image.save_png_to_buffer()
	return png_buffer


func _export_canvas_to_data_url() -> String:
	"""Export canvas as base64 data URL for API submission"""
	var png_buffer = await _export_canvas_to_buffer()
	if png_buffer.size() == 0:
		Log.error("[ToolsPanel] Failed to export canvas to buffer")
		return ""

	var base64_data = Marshalls.raw_to_base64(png_buffer)
	return "data:image/png;base64," + base64_data


func _upload_canvas_to_s3() -> String:
	"""Upload canvas drawing to S3 and return URL"""
	var refs = _get_plugin_and_bridge()
	if refs.is_empty():
		Log.error("[ToolsPanel] Plugin/bridge not available")
		return ""

	var python_bridge = refs.python_bridge

	if not python_bridge:
		Log.error("[ToolsPanel] python_bridge is null!")
		return ""

	if not python_bridge.has_method("call_python_async"):
		Log.error("[ToolsPanel] python_bridge doesn't have call_python_async method!")
		return ""

	# Export canvas to PNG buffer
	var png_buffer = await _export_canvas_to_buffer()
	if png_buffer.size() == 0:
		Log.error("[ToolsPanel] Failed to export canvas")
		return ""

	# Upload to S3
	var upload_result = await _upload_image_to_s3(python_bridge, png_buffer, "canvas_sketch.png")
	if upload_result.is_empty():
		return ""

	# Return just the URL (edit_image API needs URL, not file_id)
	return upload_result.get("file_url", "")


func _download_s3_image_to_data_url(s3_url: String) -> String:
	"""Download S3 image and convert to base64 data URL"""
	# Use HTTPRequestPool for efficient downloading
	var http_pool = _ensure_http_pool()
	if not http_pool:
		Log.error("[ToolsPanel] Failed to get HTTPRequestPool")
		return ""

	var download_complete = false
	var result_data: String = ""

	http_pool.fetch(s3_url, func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			Log.error("[ToolsPanel] S3 download failed: result=%d, response_code=%d" % [result, response_code])
			download_complete = true
			return

		var base64_data = Marshalls.raw_to_base64(body)
		result_data = "data:image/png;base64," + base64_data
		download_complete = true
	)

	# Wait for download (max 30s for S3)
	var max_wait = 30.0
	var elapsed = 0.0
	while not download_complete and elapsed < max_wait:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	if not download_complete:
		Log.error("[ToolsPanel] S3 download timed out after 30s")
		return ""

	return result_data


func _upload_image_to_s3(python_bridge, image_bytes: PackedByteArray, filename: String) -> Dictionary:
	"""Upload image bytes via python_bridge, returns {file_id, file_url} or empty dict on failure"""

	# Validate file size
	const MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10MB
	if image_bytes.size() > MAX_UPLOAD_SIZE:
		Log.error("[ToolsPanel] File too large: %d bytes (max %d)" % [image_bytes.size(), MAX_UPLOAD_SIZE])
		return {}

	# Write image to temp file instead of sending via stdin (avoids pipe buffer limits)
	var temp_dir = OS.get_cache_dir()
	var temp_filename = "godot_upload_%d.png" % Time.get_ticks_msec()
	var temp_path = temp_dir.path_join(temp_filename)

	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		Log.error("[ToolsPanel] Failed to create temp file: %s" % temp_path)
		return {}

	file.store_buffer(image_bytes)
	file.close()

	# No need to pass session_token - Python uses state.session_token
	var response = await python_bridge.call_python_async("upload_user_image", {
		"temp_file_path": temp_path,
		"filename": filename
	}, 60.0)

	# Clean up temp file
	DirAccess.remove_absolute(temp_path)

	if not response.get("ok", false):
		return {}

	var result = response.get("result", {})
	if not result.get("success", false):
		return {}

	# Return both file_id and file_url (same as attachment manager)
	var file_id = result.get("file_id", "")
	var file_url = result.get("file_url", "")

	if file_id.is_empty() or file_url.is_empty():
		return {}

	return {
		"file_id": file_id,
		"file_url": file_url
	}

func _exit_tree() -> void:
	"""Cleanup when panel is destroyed"""
	if file_dialog:
		file_dialog.queue_free()
		file_dialog = null

func _send_copilot_message(python_bridge, message: String, file_ids: Array = [], files: Array = []) -> void:
	"""Send message to copilot via python_bridge with optional file attachments"""
	if not python_bridge:
		Log.error("[ToolsPanel] python_bridge is null")
		return

	# Get session_token from chat_panel_v2
	var session_token = ""
	if paint_root and paint_root.plugin_ref:
		var chat_panel = paint_root.plugin_ref.chat_panel
		if chat_panel and "session_token" in chat_panel:
			session_token = chat_panel.session_token
		else:
			Log.error("[ToolsPanel] Could not find chat_panel or session_token")
			return
	else:
		Log.error("[ToolsPanel] Could not access plugin_ref")
		return

	var local_id = _generate_uuid()
	var payload = PythonBridge.make_message_payload(local_id, message)
	payload["file_ids"] = file_ids
	payload["files"] = files
	payload["session_token"] = session_token
	python_bridge.call_python("send_user_message", payload)
	Log.info("[ToolsPanel] python_bridge.call_python completed, local_id=%s, file_ids=%s" % [local_id, file_ids])

func _generate_uuid() -> String:
	"""Generate a simple UUID for message IDs"""
	var uuid = ""
	for i in range(16):
		uuid += "%02x" % (randi() % 256)
		if i == 3 or i == 5 or i == 7 or i == 9:
			uuid += "-"
	return uuid

func _add_status_message(text: String) -> void:
	"""Add status message to chat panel (doesn't send to agent)"""
	if paint_root and paint_root.plugin_ref:
		var chat_panel = paint_root.plugin_ref.chat_panel
		if chat_panel and chat_panel.has_method("_add_system_message"):
			chat_panel._add_system_message(text)

func _send_mini_prompt_to_copilot(text: String) -> void:
	"""Send mini-prompt text to main copilot when no image work was done"""
	# Get python_bridge from paint_root
	if not paint_root or not paint_root.python_bridge:
		Log.error("[ToolsPanel] python_bridge is null")
		_add_status_message("Error: Plugin not available")
		_close_paint_window()
		return

	var python_bridge = paint_root.python_bridge

	# Get session_token from chat_panel_v2
	var session_token = ""
	if paint_root and paint_root.plugin_ref:
		var chat_panel = paint_root.plugin_ref.chat_panel
		if chat_panel and "session_token" in chat_panel:
			session_token = chat_panel.session_token
		else:
			Log.error("[ToolsPanel] Could not find chat_panel or session_token")
			_add_status_message("Error: Not authenticated")
			_close_paint_window()
			return
	else:
		Log.error("[ToolsPanel] Could not access plugin_ref")
		_add_status_message("Error: Plugin not available")
		_close_paint_window()
		return

	# Validate session token
	if session_token.is_empty():
		_add_status_message("Error: Not authenticated. Please login first.")
		_close_paint_window()
		return

	# Clear prompt input (consistent with edit behavior)
	if prompt_input:
		prompt_input.text = ""

	# Send via python_bridge (same pattern as _send_copilot_message)
	var local_id = _generate_uuid()
	var payload = PythonBridge.make_message_payload(local_id, text)
	payload["session_token"] = session_token
	python_bridge.call_python("send_user_message", payload)

	# Close dialog
	_close_paint_window()

func _connect_window_close() -> void:
	"""Connect to parent window's close signal for cleanup"""
	if paint_root:
		var window = paint_root.get_parent()
		if window and window is Window:
			if not window.close_requested.is_connected(_cleanup_on_close):
				window.close_requested.connect(_cleanup_on_close)


func _cleanup_on_close() -> void:
	"""Clean up any pending requests when window is closed"""
	# Reset API state
	if api_in_progress:
		api_in_progress = false
		_set_prompt_buttons_enabled(true)
		if prompt_input:
			prompt_input.placeholder_text = "Enter a prompt to modify the image..."


func _close_paint_window() -> void:
	"""Close the paint window after successful generation"""
	_cleanup_on_close()

	if paint_root:
		var window = paint_root.get_parent()
		if window and window is Window:
			window.queue_free()
			Log.info("[ToolsPanel] Closed paint window")
		else:
			Log.warn("[ToolsPanel] Warning: Could not find parent window to close")

func _set_drawing_enabled(enabled: bool) -> void:
	"""Enable or disable drawing tools and paint control"""
	# Disable/enable paint control input using the painting_enabled flag
	# NOTE: mouse_filter does NOT disable _process() or Input polling, so we use the internal flag
	if paint_control:
		if enabled:
			paint_control.enable_painting()
		else:
			paint_control.disable_painting()

	# Disable/enable drawing tool buttons
	if button_pencil:
		button_pencil.disabled = not enabled
	if button_eraser:
		button_eraser.disabled = not enabled
	if color_picker:
		color_picker.disabled = not enabled
	if brush_size_slider:
		brush_size_slider.editable = enabled

func _set_prompt_buttons_enabled(enabled: bool) -> void:
	"""Enable or disable upload, generate buttons, and prompt input during API operations"""
	if upload_button:
		upload_button.disabled = not enabled
	if generate_button:
		generate_button.disabled = not enabled
	if prompt_input:
		prompt_input.editable = enabled


func _ensure_http_pool() -> Node:
	"""Get or create HTTPRequestPool singleton"""
	var root = get_tree().root if get_tree() else null
	if root:
		for child in root.get_children():
			if child.name == "HTTPRequestPool":
				return child

	# Create new pool if not exists
	var http_pool = load("res://addons/moonlake_copilot/http/http_request_pool.gd").new()
	http_pool.name = "HTTPRequestPool"
	if root:
		root.add_child(http_pool)
	return http_pool
