@tool
extends ConfirmationDialog
class_name ImportProgressDialog

## Modal dialog showing import progress

const DownloadWorkerPool = preload("res://addons/moonlake_copilot/resource_import/download_worker_pool.gd")

var worker_pool: DownloadWorkerPool
var progress_bar: ProgressBar
var status_label: Label
var current_label: Label
var priority_label: Label
var total_tasks: int = 0
var completed_tasks: int = 0

func _init():
	title = "Moonlake: Importing Scene Resources"
	dialog_hide_on_ok = true  # Close when OK is pressed
	size = Vector2(500, 200)

	# Hide OK button during import, show Cancel
	get_ok_button().visible = false
	get_cancel_button().text = "Cancel"

	# Connect cancel button to handler
	canceled.connect(_on_cancel_pressed)

	# Build UI
	var vbox = VBoxContainer.new()
	add_child(vbox)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = true
	progress_bar.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(progress_bar)

	# Status label
	status_label = Label.new()
	status_label.text = "Starting import..."
	vbox.add_child(status_label)

	# Current download label
	current_label = Label.new()
	current_label.text = ""
	vbox.add_child(current_label)

	# Priority breakdown label
	priority_label = Label.new()
	priority_label.text = ""
	vbox.add_child(priority_label)

	# Recenter dialog whenever size changes
	size_changed.connect(func():
		if visible:
			popup_centered()
	)

func connect_to_worker_pool(pool: DownloadWorkerPool) -> void:
	worker_pool = pool
	if pool.download_started.is_connected(_on_download_started):
		pool.download_started.disconnect(_on_download_started)
	if pool.download_completed.is_connected(_on_download_completed):
		pool.download_completed.disconnect(_on_download_completed)
	pool.download_started.connect(_on_download_started)
	pool.download_completed.connect(_on_download_completed)

func _exit_tree():
	# Disconnect signals when dialog is freed
	if worker_pool:
		if worker_pool.download_started.is_connected(_on_download_started):
			worker_pool.download_started.disconnect(_on_download_started)
		if worker_pool.download_completed.is_connected(_on_download_completed):
			worker_pool.download_completed.disconnect(_on_download_completed)

func _on_download_started(url: String, priority: int) -> void:
	var filename = url.get_file()
	current_label.text = "Downloading: %s" % filename

func _on_download_completed(url: String, success: bool, http_code: int, error_msg: String) -> void:
	completed_tasks += 1
	if total_tasks > 0:
		progress_bar.value = (float(completed_tasks) / float(total_tasks)) * 100.0
	status_label.text = "Downloaded %d / %d resources" % [completed_tasks, total_tasks]

func set_total_tasks(count: int) -> void:
	total_tasks = count
	completed_tasks = 0
	progress_bar.value = 0
	progress_bar.max_value = 100

func update_status(message: String) -> void:
	status_label.text = message

func set_cancel_enabled(enabled: bool) -> void:
	get_cancel_button().disabled = not enabled

func show_final_summary(summary: Dictionary) -> void:
	var completed = summary.get("completed", 0)
	var failed = summary.get("failed", 0)
	var cached = summary.get("cached", 0)
	var cancelled = summary.get("cancelled", 0)

	var message = "Import Complete!\n"
	message += "Completed: %d\n" % completed
	message += "Failed: %d\n" % failed
	message += "Cached: %d\n" % cached
	if cancelled > 0:
		message += "Cancelled: %d\n" % cancelled

	status_label.text = message

	# Hide cancel button and show OK button
	get_cancel_button().visible = false
	get_ok_button().visible = true
	get_ok_button().text = "Close"

	# Auto-close after 2s if successful (no failures or cancellations)
	if failed == 0 and cancelled == 0:
		var scene_tree = Engine.get_main_loop()
		if scene_tree and scene_tree is SceneTree:
			await scene_tree.create_timer(2.0).timeout
			hide()

func _on_cancel_pressed() -> void:
	if worker_pool:
		worker_pool.cancel()
	get_cancel_button().disabled = true
	status_label.text = "Cancelling..."
