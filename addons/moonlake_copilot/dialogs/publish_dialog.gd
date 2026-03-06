@tool
extends AcceptDialog

signal publish_completed(url: String)
signal unpublish_completed()

var _name_edit: LineEdit
var _description_edit: TextEdit
var _thumbnail_button: Button
var _thumbnail_preview: TextureRect
var _thumbnail_dialog: EditorFileDialog

var _action_dropdown: OptionButton
var _execute_button: Button
var _copy_url_button: Button

var _status_label: Label
var _progress_bar: ProgressBar
var _output_log: RichTextLabel

var _url_label: Label
var _url_display: LineEdit

var _project_id: String
var _published_url: String
var _thumbnail_path: String
var _thumbnail_changed: bool = false
var _is_busy: bool = false
var _is_cancelled: bool = false

var _http_request: HTTPRequest
var _metadata_request: HTTPRequest
var _thumbnail_request: HTTPRequest


var python_bridge: Node

enum Action {
	PUBLISH,
	UNPUBLISH,
}


func _init() -> void:
	title = "Publish to Web"
	var scale := EditorInterface.get_editor_scale()
	min_size = Vector2(700, 600) * scale
	get_ok_button().visible = false

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# Top section: Thumbnail on left, Name/Description on right
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(top_hbox)

	# Left side: Thumbnail
	var thumb_vbox := VBoxContainer.new()
	thumb_vbox.add_theme_constant_override("separation", 8)
	top_hbox.add_child(thumb_vbox)

	var thumb_label := Label.new()
	thumb_label.text = "Thumbnail:"
	thumb_vbox.add_child(thumb_label)

	_thumbnail_preview = TextureRect.new()
	_thumbnail_preview.custom_minimum_size = Vector2(200, 200)
	_thumbnail_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumbnail_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var thumb_panel := PanelContainer.new()
	thumb_panel.custom_minimum_size = Vector2(200, 200)
	thumb_panel.add_child(_thumbnail_preview)
	thumb_vbox.add_child(thumb_panel)

	_thumbnail_button = Button.new()
	_thumbnail_button.text = "Select Image..."
	_thumbnail_button.pressed.connect(_on_thumbnail_button_pressed)
	thumb_vbox.add_child(_thumbnail_button)

	# Right side: Name and Description
	var details_vbox := VBoxContainer.new()
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_vbox.add_theme_constant_override("separation", 8)
	top_hbox.add_child(details_vbox)

	var name_label := Label.new()
	name_label.text = "Name:"
	details_vbox.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "Project name"
	details_vbox.add_child(_name_edit)

	var desc_label := Label.new()
	desc_label.text = "Description:"
	details_vbox.add_child(desc_label)

	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size.y = 120
	_description_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_description_edit.placeholder_text = "Project description"
	details_vbox.add_child(_description_edit)

	# Action section
	var action_hbox := HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(action_hbox)

	var action_label := Label.new()
	action_label.text = "Action:"
	action_hbox.add_child(action_label)

	_action_dropdown = OptionButton.new()
	_action_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_dropdown.add_item("Publish", Action.PUBLISH)
	_action_dropdown.add_item("Unpublish", Action.UNPUBLISH)
	_action_dropdown.item_selected.connect(_on_action_selected)
	action_hbox.add_child(_action_dropdown)

	_execute_button = Button.new()
	_execute_button.text = "Publish"
	_execute_button.pressed.connect(_on_execute_pressed)
	action_hbox.add_child(_execute_button)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Ready"
	main_vbox.add_child(_status_label)

	# Progress bar (hidden by default)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size.y = 20
	_progress_bar.value = 0
	_progress_bar.visible = false
	main_vbox.add_child(_progress_bar)

	# Output log
	_output_log = RichTextLabel.new()
	_output_log.custom_minimum_size.y = 200
	_output_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output_log.scroll_following = true
	_output_log.selection_enabled = true
	_output_log.context_menu_enabled = true
	_output_log.bbcode_enabled = true
	main_vbox.add_child(_output_log)

	# URL section (always visible)
	var url_hbox := HBoxContainer.new()
	url_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(url_hbox)

	_url_label = Label.new()
	_url_label.text = "Published URL:"
	url_hbox.add_child(_url_label)

	_url_display = LineEdit.new()
	_url_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_display.editable = false
	_url_display.placeholder_text = "Not published"
	url_hbox.add_child(_url_display)

	_copy_url_button = Button.new()
	_copy_url_button.text = "Copy"
	_copy_url_button.pressed.connect(_on_copy_url_pressed)
	url_hbox.add_child(_copy_url_button)

	# HTTP requests
	_http_request = HTTPRequest.new()
	add_child(_http_request)

	_metadata_request = HTTPRequest.new()
	_metadata_request.request_completed.connect(_on_metadata_completed)
	add_child(_metadata_request)

	_thumbnail_request = HTTPRequest.new()
	_thumbnail_request.request_completed.connect(_on_thumbnail_completed)
	add_child(_thumbnail_request)

	# Thumbnail file dialog
	_thumbnail_dialog = EditorFileDialog.new()
	_thumbnail_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_thumbnail_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_thumbnail_dialog.filters = PackedStringArray(["*.png", "*.jpg", "*.jpeg", "*.webp"])
	_thumbnail_dialog.file_selected.connect(_on_thumbnail_selected)
	add_child(_thumbnail_dialog)


func _ready() -> void:
	# Cancel on close
	close_requested.connect(_on_close_requested)

	# Connect to MoonlakeAuth signals
	var auth = MoonlakeAuth.get_singleton()
	if auth:
		if not auth.is_connected("publish_requested", _on_publish_requested):
			auth.connect("publish_requested", _on_publish_requested)
		if not auth.is_connected("unpublish_requested", _on_unpublish_requested):
			auth.connect("unpublish_requested", _on_unpublish_requested)


func _on_close_requested() -> void:
	_cancel_operation()
	hide()


func _on_publish_requested() -> void:
	if not popup_dialog():
		push_warning("Cannot publish: No Moonlake project found. Create or open a project first.")


func _on_unpublish_requested() -> void:
	if not popup_dialog():
		return
	_action_dropdown.select(Action.UNPUBLISH)
	_on_action_selected(Action.UNPUBLISH)
	_on_execute_pressed()


func popup_dialog() -> bool:
	_project_id = MoonlakeProjectConfig.get_singleton().get_project_id()

	if _project_id.is_empty():
		_log_message("Error: No project ID found")
		return false

	# Load project name from project.godot
	var project_name := ProjectSettings.get_setting("application/config/name", "")
	if not project_name.is_empty() and _name_edit.text.is_empty():
		_name_edit.text = project_name

	# Load project description from MoonlakeProjectConfig
	var config = MoonlakeProjectConfig.get_singleton()
	if config and _description_edit.text.is_empty():
		var saved_description: String = config.get_project_description()
		if not saved_description.is_empty():
			_description_edit.text = saved_description

	# Load project icon as default thumbnail
	if _thumbnail_path.is_empty():
		var icon_path: String = ProjectSettings.get_setting("application/config/icon", "")
		if not icon_path.is_empty() and FileAccess.file_exists(icon_path):
			_thumbnail_path = ProjectSettings.globalize_path(icon_path)
			var image := Image.load_from_file(_thumbnail_path)
			if image:
				var texture := ImageTexture.create_from_image(image)
				_thumbnail_preview.texture = texture

	_load_published_url()
	_update_ui_state()

	# Reset to Publish action
	_action_dropdown.select(Action.PUBLISH)
	_on_action_selected(Action.PUBLISH)

	_output_log.clear()
	_update_ready_status()
	popup_centered()
	return true


func _load_published_url() -> void:
	var config = MoonlakeProjectConfig.get_singleton()
	if config and not _project_id.is_empty():
		_published_url = config.get_published_url()
		_url_display.text = _published_url


func _save_published_url(url: String) -> void:
	var config = MoonlakeProjectConfig.get_singleton()
	if config:
		config.set_published_url(url)
		_published_url = url
		_url_display.text = url


func _update_ui_state() -> void:
	var has_url := not _published_url.is_empty()
	_action_dropdown.set_item_disabled(Action.UNPUBLISH, not has_url)
	_copy_url_button.disabled = not has_url


func _on_action_selected(index: int) -> void:
	match index:
		Action.PUBLISH:
			_execute_button.text = "Publish"
		Action.UNPUBLISH:
			_execute_button.text = "Unpublish"


func _on_execute_pressed() -> void:
	if _is_busy:
		_cancel_operation()
		return

	match _action_dropdown.selected:
		Action.PUBLISH:
			_start_publish()
		Action.UNPUBLISH:
			_start_unpublish()


func _on_copy_url_pressed() -> void:
	if not _published_url.is_empty():
		DisplayServer.clipboard_set(_published_url)
		_log_message("URL copied to clipboard")


func _on_thumbnail_button_pressed() -> void:
	_thumbnail_dialog.popup_centered_ratio(0.6)


func _on_thumbnail_selected(path: String) -> void:
	_thumbnail_path = path
	_thumbnail_changed = true
	var image := Image.load_from_file(path)
	if image:
		var texture := ImageTexture.create_from_image(image)
		_thumbnail_preview.texture = texture
		_log_message("Thumbnail selected: " + path.get_file())


func _start_publish() -> void:
	var auth = MoonlakeAuth.get_singleton()
	if not auth or not auth.get_is_authenticated():
		_log_message("Error: Not authenticated. Please log in first.")
		return

	_output_log.clear()
	_log_message("Starting publish...")
	_set_busy(true)
	_is_cancelled = false
	_progress_bar.value = 0

	# Step 1: Copy export_presets.cfg if needed
	_copy_export_presets()

	# Step 2: Sync to git
	_log_message("Syncing project to git...")
	_progress_bar.value = 10

	if not python_bridge:
		_log_message("Error: Python bridge not available")
		_set_busy(false)
		return

	var workdir := ProjectSettings.globalize_path("res://")
	var result = await python_bridge.call_python_async("sync_to_gitea", {
		"workdir": workdir,
		"project_id": _project_id,
		"session_token": auth.get_session_token()
	}, 120.0)  # 2 min timeout for sync

	if _is_cancelled:
		return

	if not result.get("ok", false) or not result.get("result", {}).get("success", false):
		var error = result.get("error", result.get("result", {}).get("error", "Unknown error"))
		_log_message("Sync failed: " + str(error))
		_set_busy(false)
		return

	var commit_hash = result.get("result", {}).get("commit_hash", "")
	var message = result.get("result", {}).get("message", "")
	if commit_hash:
		_log_message("Sync complete: " + str(commit_hash))
	else:
		_log_message("Sync complete: " + str(message))
	_progress_bar.value = 30

	if _is_cancelled:
		return

	# Step 3: Update metadata if changed
	if _thumbnail_changed:
		_upload_thumbnail()
	_update_metadata()

	if _is_cancelled:
		return

	# Step 4: Call publish via Python worker (streams progress back)
	_progress_bar.value = 40

	var publish_result = await python_bridge.call_python_async("publish_project", {
		"project_id": _project_id,
		"session_token": auth.get_session_token()
	}, 600.0)  # 10 min timeout for publish

	if _is_cancelled:
		return

	if publish_result.get("ok", false) and publish_result.get("result", {}).get("success", false):
		_progress_bar.value = 100
		_status_label.text = "Published!"
		var internal_url = publish_result.get("result", {}).get("url", "")
		if internal_url:
			_save_published_url(internal_url)
			_load_published_url()  # Get the formatted public URL
			_update_ui_state()
			_log_message("Published to: " + _published_url)
			DisplayServer.clipboard_set(_published_url)
			_log_message("URL copied to clipboard")
			publish_completed.emit(_published_url)
			_log_message("Opening URL in 5 seconds...")
			await get_tree().create_timer(5.0).timeout
			if _is_cancelled:
				return
			OS.shell_open(_published_url)
	else:
		var error = publish_result.get("error", publish_result.get("result", {}).get("error", "Unknown error"))
		_log_message("Publish failed: " + str(error))

	_set_busy(false)


func _copy_export_presets() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	var presets_path := project_path + "export_presets.cfg"

	if FileAccess.file_exists(presets_path):
		_log_message("export_presets.cfg already exists")
		return

	# Find the template in copilot assets
	var addon_path := "res://addons/moonlake_copilot/assets/export_presets.cfg"
	if not FileAccess.file_exists(addon_path):
		_log_message("Warning: export_presets.cfg template not found in addon assets")
		return

	var source := FileAccess.open(addon_path, FileAccess.READ)
	if not source:
		_log_message("Warning: Could not open export_presets.cfg template")
		return

	var content := source.get_as_text()
	source.close()

	var dest := FileAccess.open(presets_path, FileAccess.WRITE)
	if not dest:
		_log_message("Warning: Could not create export_presets.cfg")
		return

	dest.store_string(content)
	dest.close()
	_log_message("Copied export_presets.cfg to project")


func _start_unpublish() -> void:
	var auth = MoonlakeAuth.get_singleton()
	if not auth or not auth.get_is_authenticated():
		_log_message("Error: Not authenticated")
		return

	_log_message("Unpublishing...")
	_set_busy(true)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Cookie: wos_session=" + auth.get_session_token()
	])

	var backend_url: String = MoonlakeResources.get_worker_config()["backend_url"]
	var url := backend_url + "/api/projects/" + _project_id + "/unpublish"

	_http_request.request_completed.connect(_on_unpublish_completed, CONNECT_ONE_SHOT)
	_http_request.request(url, headers, HTTPClient.METHOD_POST, "")


func _on_unpublish_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_set_busy(false)

	if result != HTTPRequest.RESULT_SUCCESS:
		_log_message("Unpublish failed: Network error")
		return

	if code == 200:
		_save_published_url("")
		_update_ui_state()
		_log_message("Project unpublished successfully")
		unpublish_completed.emit()
	else:
		var error := body.get_string_from_utf8()
		_log_message("Unpublish failed: " + error)


func _update_metadata() -> void:
	var auth = MoonlakeAuth.get_singleton()
	if not auth or not auth.get_is_authenticated():
		return

	var name_text := _name_edit.text.strip_edges()
	var desc_text := _description_edit.text.strip_edges()

	if name_text.is_empty() and desc_text.is_empty():
		return

	# Save description locally
	if not desc_text.is_empty():
		var config = MoonlakeProjectConfig.get_singleton()
		if config:
			config.set_project_description(desc_text)

	var payload := {}
	if not name_text.is_empty():
		payload["name"] = name_text
	if not desc_text.is_empty():
		payload["description"] = desc_text

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Cookie: wos_session=" + auth.get_session_token()
	])

	var backend_url: String = MoonlakeResources.get_worker_config()["backend_url"]
	var url := backend_url + "/api/projects/" + _project_id

	_metadata_request.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify(payload))


func _upload_thumbnail() -> void:
	if _thumbnail_path.is_empty():
		return

	var auth = MoonlakeAuth.get_singleton()
	if not auth or not auth.get_is_authenticated():
		return

	# Read thumbnail file
	var file := FileAccess.open(_thumbnail_path, FileAccess.READ)
	if not file:
		_log_message("Could not open thumbnail file")
		return

	var file_data := file.get_buffer(file.get_length())
	file.close()

	var filename := _thumbnail_path.get_file()
	var boundary := "----GodotFormBoundary" + str(randi())

	# Determine Content-Type from file extension
	var ext := _thumbnail_path.get_extension().to_lower()
	var content_type := "image/png"
	match ext:
		"jpg", "jpeg":
			content_type = "image/jpeg"
		"webp":
			content_type = "image/webp"
		"svg":
			content_type = "image/svg+xml"

	var body := PackedByteArray()
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"" + filename + "\"\r\n").to_utf8_buffer())
	body.append_array(("Content-Type: " + content_type + "\r\n\r\n").to_utf8_buffer())
	body.append_array(file_data)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"Cookie: wos_session=" + auth.get_session_token()
	])

	var backend_url: String = MoonlakeResources.get_worker_config()["backend_url"]
	var url := backend_url + "/api/projects/" + _project_id + "/thumbnail_file"

	_thumbnail_request.request_raw(url, headers, HTTPClient.METHOD_POST, body)


func _on_metadata_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_log_message("Failed to update metadata: network error (result=%d)" % result)
		return
	if code == 200:
		_log_message("Metadata updated")
	else:
		_log_message("Failed to update metadata: HTTP %d" % code)


func _on_thumbnail_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_log_message("Failed to upload thumbnail: network error (result=%d)" % result)
		return
	if code == 200:
		_thumbnail_changed = false
		_log_message("Thumbnail uploaded")
	else:
		_log_message("Failed to upload thumbnail: HTTP %d" % code)


func on_publish_progress(message: String) -> void:
	_log_message(message)

	# Parse progress from message
	if message.contains("Uploading.") and message.contains("%"):
		var regex = RegEx.new()
		regex.compile("(\\d+)%")
		var result = regex.search(message)
		if result:
			var percent = int(result.get_string(1))
			# Download is 40-80% of total progress
			_progress_bar.value = 40 + (percent * 0.4)
	elif message.contains("Creating build environment"):
		_progress_bar.value = 5
	elif message.contains("Exporting project"):
		_progress_bar.value = 10
	elif message.contains("Packaging build output"):
		_progress_bar.value = 30
	elif message.contains("Build output packaged"):
		_progress_bar.value = 35
	elif message.contains("Extracting build output"):
		_progress_bar.value = 82
	elif message.contains("Processing files"):
		_progress_bar.value = 85
	elif message.contains("Creating deployment"):
		_progress_bar.value = 88
	elif message.contains("Generating building config"):
		_progress_bar.value = 90
	elif message.contains("Building images and deploying"):
		_progress_bar.value = 92
	elif message.contains("Deployed successfully"):
		_progress_bar.value = 98
	elif message.contains("Published successfully"):
		_progress_bar.value = 100


func _log_message(message: String) -> void:
	_output_log.append_text(message + "\n")


func _set_busy(busy: bool) -> void:
	_is_busy = busy
	_action_dropdown.disabled = busy
	_name_edit.editable = not busy
	_description_edit.editable = not busy
	_thumbnail_button.disabled = busy
	_progress_bar.visible = busy

	if busy:
		_execute_button.text = "Cancel"
		_status_label.text = "Working..."
	else:
		_on_action_selected(_action_dropdown.selected)
		_status_label.text = "Ready"


func _cancel_operation() -> void:
	if not _is_busy:
		return

	_log_message("Cancelling...")
	_is_cancelled = true

	# Disconnect one-shot signal to prevent duplicate callbacks
	if _http_request.is_connected("request_completed", _on_unpublish_completed):
		_http_request.disconnect("request_completed", _on_unpublish_completed)

	_http_request.cancel_request()
	_metadata_request.cancel_request()
	_thumbnail_request.cancel_request()

	# Set cancellation flag in Python worker
	if python_bridge:
		python_bridge.call_python("cancel_publish", {})

	_set_busy(false)
	_log_message("Cancelled")


func _update_ready_status() -> void:
	_log_message("Ready to publish.")

	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	if renderer == "forward_plus":
		_log_message("")
		_log_message("[color=yellow]Note: This project uses the Forward+ renderer. Some visual effects may look different on web.[/color]")
		_log_message("")

	if not _thumbnail_path.is_empty():
		_log_message("Thumbnail selected: " + _thumbnail_path.get_file())
