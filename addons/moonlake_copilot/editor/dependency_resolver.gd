@tool
extends RefCounted

## Dependency Resolver - Auto-import dialog for missing scene dependencies
##
## Responsibilities:
## - Detect missing dependencies via EditorNode signals
## - Show confirmation dialog asking user to import
## - Trigger two-phase import (terrain first, then other resources)
## - Manage "don't ask again" list
## - Create error placeholders for failed downloads

# Signals
signal import_triggered(tscn_path: String)

# External references (set externally)
var placeholder_manager = null
var plugin_ref = null  # Reference to plugin for get_tree() access

# State
var dont_ask_again_list: Array[String] = []
var auto_import_scenes: Array[String] = []
var _editor_node: Node = null

# Constants
const TSCNOperations = preload("res://addons/moonlake_copilot/operations/tscn_operations.gd")
const DownloadConfig = preload("res://addons/moonlake_copilot/config/download_config.gd")


func initialize(placeholder_mgr, plugin) -> void:
	"""Initialize with external references"""
	placeholder_manager = placeholder_mgr
	plugin_ref = plugin

	# Load "don't ask again" list from project settings
	_load_dont_ask_list()


func mark_for_auto_import(scene_path: String) -> void:
	"""Mark a scene to auto-import without showing dialog (used by BatchDownload)"""
	if scene_path not in auto_import_scenes:
		auto_import_scenes.append(scene_path)
		Log.info("[MOONLAKE] Marked for auto-import: %s" % scene_path)


func connect_to_editor_node(editor_node: Node) -> void:
	"""Connect to EditorNode's dependency_error_detected signal"""
	_editor_node = editor_node

	if _editor_node and _editor_node.get_class() == "EditorNode":
		if _editor_node.has_signal("dependency_error_detected"):
			_editor_node.dependency_error_detected.connect(_on_dependency_error_detected)
		else:
			Log.error("[MOONLAKE] ERROR: dependency_error_detected signal not found! (Did you rebuild Godot with the engine changes?)")
	else:
		Log.error("[MOONLAKE] ERROR: EditorNode not valid!")


func disconnect_from_editor_node() -> void:
	"""Disconnect from EditorNode signal on cleanup"""
	if _editor_node and _editor_node.get_class() == "EditorNode":
		if _editor_node.has_signal("dependency_error_detected"):
			if _editor_node.dependency_error_detected.is_connected(_on_dependency_error_detected):
				_editor_node.dependency_error_detected.disconnect(_on_dependency_error_detected)
	_editor_node = null


## ============================================================================
## Dependency Detection and Auto-Import
## ============================================================================

func _on_dependency_error_detected(scene_path: String, missing_deps: PackedStringArray) -> void:
	"""Called when Godot detects missing dependencies in a scene."""
	Log.info("[MOONLAKE] Dependency error detected for %s: %s" % [scene_path, str(missing_deps)])

	# Check if in "don't ask again" list
	if scene_path in dont_ask_again_list:
		Log.info("[MOONLAKE] Scene in 'don't ask again' list, skipping")
		return

	# Check if marked for auto-import (from BatchDownload)
	if scene_path in auto_import_scenes:
		Log.info("[MOONLAKE] Scene marked for auto-import, skipping dialog")
		auto_import_scenes.erase(scene_path)
		_trigger_import(scene_path)
		return

	# Check if any missing dependencies are HTTP URLs or have original URLs in metadata
	var has_http_deps = false
	var has_restorable_deps = false

	for dep in missing_deps:
		if dep.begins_with("http://") or dep.begins_with("https://"):
			has_http_deps = true
			break

	# Check for restorable res:// paths with URL inference
	if not has_http_deps:
		has_restorable_deps = TSCNOperations.has_restorable_resources_from_file(scene_path)
		Log.info("[MOONLAKE] Checked restorable resources: %s" % ("found" if has_restorable_deps else "none found"))

	if not has_http_deps and not has_restorable_deps:
		Log.info("[MOONLAKE] No HTTP dependencies or restorable resources found, skipping auto-import")
		return

	# Show confirmation dialog (ask user first!)
	Log.info("[MOONLAKE] Showing auto-import dialog...")
	_show_auto_import_dialog(scene_path)


func _show_auto_import_dialog(tscn_path: String) -> void:
	"""Show confirmation dialog asking user if they want to import resources."""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Moonlake: Import Scene Resources"
	dialog.dialog_text = "The scene contains resources that need to be downloaded and imported.\n\nScene: %s\n\nImport now?" % tscn_path.get_file()
	dialog.ok_button_text = "Import"
	dialog.cancel_button_text = "Skip"

	# Connect signals
	dialog.confirmed.connect(func():
		Log.info("[MOONLAKE] User clicked Import button")
		_trigger_import(tscn_path)
	)

	dialog.canceled.connect(func():
		Log.info("[MOONLAKE] User clicked Skip button")
	)

	# Show dialog
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.tree_exited.connect(dialog.queue_free)


func _trigger_import(tscn_path: String) -> void:
	"""Two-phase import: terrain first → reload → other resources → reload."""
	Log.info("[MOONLAKE] Triggering two-phase import for: %s" % tscn_path)

	# Disconnect during import to prevent re-triggering
	if _editor_node and _editor_node.has_signal("dependency_error_detected"):
		if _editor_node.dependency_error_detected.is_connected(_on_dependency_error_detected):
			_editor_node.dependency_error_detected.disconnect(_on_dependency_error_detected)
			Log.info("[MOONLAKE] Disconnected from dependency_error_detected signal")

	# Create dialog
	var ImportProgressDialog = load("res://addons/moonlake_copilot/resource_import/import_progress_dialog.gd")
	var dialog = ImportProgressDialog.new()
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2(500, 200))

	# Resolve dependencies using v2 system
	Log.info("\n=== DEPENDENCY RESOLUTION ===")
	dialog.status_label.text = "Resolving dependencies..."

	var result = await TSCNOperations.resolve_resources_v2(tscn_path, dialog, 0, 999, DownloadConfig.DOWNLOAD_TIMEOUT_PER_ATTEMPT, DownloadConfig.DOWNLOAD_MAX_TOTAL_TIMEOUT, DownloadConfig.WORKER_POOL_SIZE, 10, [], plugin_ref)

	# Show summary result with dependency tree
	Log.info("\n=== RESOLUTION SUMMARY ===")
	Log.info("")
	Log.info("%s (root)" % tscn_path.get_file())

	if result is Dictionary:
		Log.info("Summary: %s" % result.get("summary", "Unknown"))

		# Print dependency tree
		var dep_tree = result.get("dep_tree", [])
		if not dep_tree.is_empty():
			TSCNOperations._print_dep_tree(dep_tree)
	else:
		Log.info("Result: %s" % result)

	Log.info("")
	Log.info("=========================\n")

	# Force-open scene even with missing dependencies (to show error cylinders)
	# Validate scene file before opening to prevent crashes
	if not FileAccess.file_exists(tscn_path):
		Log.error("[MOONLAKE] ERROR: Scene file not found: %s" % tscn_path)
		dialog.hide()
		return

	var file = FileAccess.open(tscn_path, FileAccess.READ)
	if file == null:
		Log.error("[MOONLAKE] ERROR: Cannot open scene file: %s" % tscn_path)
		dialog.hide()
		return

	var file_size = file.get_length()

	if file_size == 0:
		file.close()
		Log.error("[MOONLAKE] ERROR: Scene file is empty: %s" % tscn_path)
		dialog.hide()
		return

	# Validate TSCN format - check for required header
	var first_line = file.get_line()
	file.close()

	if not first_line.begins_with("[gd_scene"):
		Log.error("[MOONLAKE] ERROR: Invalid TSCN format (missing [gd_scene header): %s" % tscn_path)
		Log.info("[MOONLAKE] First line: %s" % first_line)
		dialog.hide()
		return

	if file_size < 50:  # TSCN files need at least header + some content
		Log.error("[MOONLAKE] ERROR: Scene file suspiciously small (%d bytes): %s" % [file_size, tscn_path])
		dialog.hide()
		return

	Log.info("[MOONLAKE] Force-opening scene (ignoring broken deps): %s (%d bytes)" % [tscn_path, file_size])
	EditorInterface.open_scene_from_path(tscn_path, false, true)  # ignore_broken_deps = true
	await plugin_ref.get_tree().create_timer(0.5).timeout

	# NOW create error cylinders (scene is open now)
	if result is Dictionary:
		var all_tasks = result.get("all_tasks", [])
		if not all_tasks.is_empty() and placeholder_manager:
			# Clear old error cylinders from previous imports (prevents memory leak)
			var cleared = placeholder_manager.clear_all_error_cylinders()
			if cleared > 0:
				Log.info("[MOONLAKE] Cleared %d old error cylinders" % cleared)

				# Reuse singleton instance (don't create new one)
				placeholder_manager.create_error_placeholders_for_failed_tasks(all_tasks, tscn_path)
				Log.info("[MOONLAKE] Created error cylinders for failed downloads")

	# Close dialog immediately to avoid conflict with Godot's filesystem rescan
	dialog.hide()
	if dialog.get_parent():
		dialog.get_parent().remove_child(dialog)
	dialog.queue_free()

	Log.info("[MOONLAKE] Import dialog closed")

	# Trigger filesystem scan AFTER dialog is fully closed
	# Check if any resources were downloaded
	var should_rescan = false
	if result is Dictionary and result.get("success", false):
		var url_mapping = result.get("url_mapping", {})
		should_rescan = not url_mapping.is_empty()

	if should_rescan:
		var fs = EditorInterface.get_resource_filesystem()
		if fs:
			# Wait for dialog cleanup to complete
			await plugin_ref.get_tree().process_frame
			await plugin_ref.get_tree().process_frame

			Log.info("[MOONLAKE] Triggering filesystem scan...")
			fs.scan()

			# Wait for scan to start
			await plugin_ref.get_tree().create_timer(0.5).timeout
			Log.info("[MOONLAKE] Scan triggered")

	# Reconnect to dependency_error_detected signal after import completes
	if _editor_node and _editor_node.has_signal("dependency_error_detected"):
		if not _editor_node.dependency_error_detected.is_connected(_on_dependency_error_detected):
			_editor_node.dependency_error_detected.connect(_on_dependency_error_detected)
			Log.info("[MOONLAKE] Reconnected to dependency_error_detected signal")

	# Emit signal for tracking
	import_triggered.emit(tscn_path)


## ============================================================================
## "Don't Ask Again" List Management
## ============================================================================

func _load_dont_ask_list() -> void:
	"""Load 'don't ask again' list from project metadata."""
	if ProjectSettings.has_setting("moonlake/ui/skip_import_dialog_scenes"):
		var saved = ProjectSettings.get_setting("moonlake/ui/skip_import_dialog_scenes")
		if saved is Array:
			dont_ask_again_list = saved


func _save_dont_ask_list() -> void:
	"""Save 'don't ask again' list to project metadata."""
	ProjectSettings.set_setting("moonlake/ui/skip_import_dialog_scenes", dont_ask_again_list)
	ProjectSettings.save()


func add_to_dont_ask_list(scene_path: String) -> void:
	"""Add a scene to the don't ask again list"""
	if scene_path not in dont_ask_again_list:
		dont_ask_again_list.append(scene_path)
		_save_dont_ask_list()
