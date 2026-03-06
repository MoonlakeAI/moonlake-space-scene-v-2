@tool
extends RefCounted
class_name AttachmentManager

## Attachment lifecycle manager
## Handles file uploads, chips display, and attachment operations

signal attachment_added(attachment: Dictionary)
signal attachment_removed(attachment: Dictionary)
signal attachments_cleared
signal upload_failed(error: String)
signal max_attachments_reached
signal input_position_update_needed
signal paste_text_requested(text: String)

const AttachmentChip = preload("res://addons/moonlake_copilot/attachments/attachment_chip.gd")
const InputController = preload("res://addons/moonlake_copilot/chat/input_controller.gd")

# State
var active_attachments: Array[Dictionary] = []
const MAX_ATTACHMENTS: int = 5

# UI references
var attachment_chips_container: Container  # GridContainer with 3 columns
var attachment_chips_wrapper: Control  # The wrapper that should be shown/hidden
var python_bridge: Node


func _init(chips_container: Container, bridge: Node):
	attachment_chips_container = chips_container
	python_bridge = bridge
	# Get wrapper reference (parent of container)
	# Defer until first use to ensure container is in scene tree
	attachment_chips_wrapper = null


func _get_wrapper() -> Control:
	if attachment_chips_wrapper == null and attachment_chips_container != null:
		attachment_chips_wrapper = attachment_chips_container.get_parent() as Control
	return attachment_chips_wrapper


func _can_attach() -> bool:
	if active_attachments.size() >= MAX_ATTACHMENTS:
		max_attachments_reached.emit()
		return false
	if not python_bridge:
		upload_failed.emit("Python bridge not available")
		return false
	return true


func _save_to_temp_file(content: String, filename_pattern: String) -> String:
	var temp_path = OS.get_user_data_dir().path_join(filename_pattern % int(Time.get_unix_time_from_system()))
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		return ""
	file.store_string(content)
	file.close()
	return temp_path


func _handle_upload_result(attachment: Dictionary, result: Dictionary, error_prefix: String) -> void:
	if attachment.get("cancelled", false):
		return

	if result and result.get("ok"):
		var data = result.get("result", {})
		if data.get("success"):
			attachment["url"] = data.get("file_url", "")
			attachment["file_id"] = data.get("file_id", "")
			attachment["name"] = attachment["file_id"]
			attachment["uploading"] = false
			var chip = attachment.get("chip_node")
			if chip and chip.has_method("_update_upload_status"):
				chip._update_upload_status()
			return

	var error = result.get("result", {}).get("error", "Unknown error") if result and result.get("ok") else (result.get("error", "No response") if result else "No response")
	remove_attachment(attachment)
	upload_failed.emit("%s: %s" % [error_prefix, error])


func add_attachment(attachment: Dictionary) -> bool:
	attachment["index"] = active_attachments.size() + 1

	var chip = AttachmentChip.new()
	chip.clicked.connect(func(att: Dictionary): _on_chip_clicked(att))
	chip.remove_requested.connect(func(att: Dictionary): _on_chip_remove_requested(att))

	# Add to scene tree first so _ready() gets called
	attachment_chips_container.add_child(chip)

	# Now initialize with data (label exists now)
	chip.initialize(attachment)

	# Store attachment with chip reference
	attachment["chip_node"] = chip
	active_attachments.append(attachment)

	# Show wrapper (not the container itself)
	var wrapper = _get_wrapper()
	if wrapper:
		wrapper.visible = true
		wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	attachment_added.emit(attachment)
	input_position_update_needed.emit()

	return true


func remove_attachment(attachment: Dictionary) -> void:
	if attachment.get("uploading", false):
		attachment["cancelled"] = true

	var chip = attachment.get("chip_node")
	if chip:
		chip.queue_free()

	active_attachments.erase(attachment)

	# Hide wrapper if no attachments - use deferred to ensure chip is actually removed
	if active_attachments.is_empty():
		# Use call_deferred to wait until queue_free completes
		_hide_wrapper_deferred.call_deferred()

	attachment_removed.emit(attachment)
	input_position_update_needed.emit()


func _hide_wrapper_deferred() -> void:
	if active_attachments.is_empty():
		var wrapper = _get_wrapper()
		if wrapper:
			wrapper.visible = false
			# Remove from layout by setting size flags to NONE
			wrapper.size_flags_vertical = 0


func clear_attachments() -> void:
	for attachment in active_attachments:
		var chip = attachment.get("chip_node")
		if chip:
			chip.queue_free()

	active_attachments.clear()

	# Hide wrapper when cleared - deferred to ensure chips are removed
	_hide_wrapper_deferred.call_deferred()

	attachments_cleared.emit()
	input_position_update_needed.emit()


func get_attachments() -> Array[Dictionary]:
	return active_attachments


func request_image_attach(parent_node: Node) -> void:
	if not _can_attach():
		return

	# Create file dialog
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.jpg,*.jpeg ; JPEG Images", "*.gif ; GIF Images"])
	file_dialog.title = "Select Image"

	file_dialog.file_selected.connect(func(path: String):
		handle_image_selected(path)
		file_dialog.queue_free()
	)

	file_dialog.canceled.connect(func():
		file_dialog.queue_free()
	)

	parent_node.add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(800, 600))


func request_clipboard_attach(session_token: String) -> void:
	if not _can_attach():
		return

	var attachment = {"type": "clipboard_text", "name": "Uploading...", "url": "", "uploading": true}
	add_attachment(attachment)

	var result = await python_bridge.call_python_async("attach_clipboard", {"session_token": session_token})
	_handle_upload_result(attachment, result, "Clipboard upload failed")


func request_editor_output_attach(session_token: String) -> void:
	var messages = _get_editor_log_messages()
	if messages.is_empty():
		upload_failed.emit("Editor output is empty")
		return

	var content = "\n".join(messages)

	if content.length() <= InputController.PASTE_TEXT_THRESHOLD:
		paste_text_requested.emit(content)
		return

	if not _can_attach():
		return

	var temp_path = _save_to_temp_file(content, "editor_output_%d.md")
	if temp_path.is_empty():
		upload_failed.emit("Failed to create temp file")
		return

	var attachment = {"type": "editor_output", "name": "Uploading...", "url": "", "uploading": true}
	add_attachment(attachment)

	var result = await python_bridge.call_python_async("upload_attachment", {"file_path": temp_path, "type": "text"})
	_handle_upload_result(attachment, result, "Editor output upload failed")


func _get_editor_log_messages() -> PackedStringArray:
	var editor_log = _find_editor_log(EditorInterface.get_base_control())
	if not editor_log or not editor_log.has_method("get_messages_text"):
		return PackedStringArray()
	return editor_log.get_messages_text(-1)


func _find_editor_log(node: Node) -> Node:
	if node.get_class() == "EditorLog":
		return node

	for child in node.get_children():
		var result = _find_editor_log(child)
		if result:
			return result

	return null


func _capture_editor_screenshot() -> Image:
	var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if not image or image.is_empty():
		Log.warn("[AttachmentManager] Failed to capture editor screenshot")
		return null
	return image


func request_editor_screenshot_attach() -> void:
	if not _can_attach():
		return

	var image = _capture_editor_screenshot()
	if not image:
		upload_failed.emit("Failed to capture editor screenshot")
		return

	var temp_path = OS.get_user_data_dir().path_join("editor_screenshot_%d.png" % int(Time.get_unix_time_from_system()))
	if image.save_png(temp_path) != OK:
		upload_failed.emit("Failed to save screenshot")
		return

	var attachment = {"type": "image", "name": "Uploading...", "url": "", "uploading": true}
	add_attachment(attachment)

	var result = await python_bridge.call_python_async("upload_attachment", {"file_path": temp_path, "type": "image"})
	_handle_upload_result(attachment, result, "Editor screenshot upload failed")


func handle_image_selected(file_path: String) -> void:
	if not _can_attach():
		return

	if not FileAccess.file_exists(file_path):
		upload_failed.emit("File not found: %s" % file_path)
		return

	var attachment = {"type": "image", "name": "Uploading...", "url": "", "uploading": true}
	add_attachment(attachment)

	var result = await python_bridge.call_python_async("upload_attachment", {"file_path": file_path, "type": "image"})
	_handle_upload_result(attachment, result, "Image upload failed")


func add_file_attachment(file_path: String, _display_name: String = "") -> void:
	"""Add a file as an attachment (for JSON, text, etc.)."""
	if not _can_attach():
		return

	if not FileAccess.file_exists(file_path):
		upload_failed.emit("File not found: %s" % file_path)
		return

	var attachment = {"type": "text", "name": "Uploading...", "url": "", "uploading": true}
	add_attachment(attachment)

	var result = await python_bridge.call_python_async("upload_attachment", {"file_path": file_path, "type": "text"})
	_handle_upload_result(attachment, result, "File upload failed")


func _on_chip_clicked(attachment: Dictionary) -> void:
	var url = attachment.get("url", "")
	if not url.is_empty():
		OS.shell_open(url)


func _on_chip_remove_requested(attachment: Dictionary) -> void:
	remove_attachment(attachment)
