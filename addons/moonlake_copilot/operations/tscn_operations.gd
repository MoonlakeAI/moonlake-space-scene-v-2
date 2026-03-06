@tool
extends RefCounted
class_name TSCNOperations

# Reference to FileOperations for file I/O and downloads
const FileOperations = preload("res://addons/moonlake_copilot/operations/file_operations.gd")

# Resource import v2 classes
const Terrain3DOperations = preload("res://addons/moonlake_copilot/terrain_creator/terrain3d_operations.gd")
const DownloadTask = preload("res://addons/moonlake_copilot/resource_import/download_task.gd")
const DownloadQueue = preload("res://addons/moonlake_copilot/resource_import/download_queue.gd")
const RetryableDownloader = preload("res://addons/moonlake_copilot/resource_import/retryable_downloader.gd")
const DownloadWorkerPool = preload("res://addons/moonlake_copilot/resource_import/download_worker_pool.gd")
const PlaceholderManager = preload("res://addons/moonlake_copilot/resource_import/placeholder_manager.gd")
const ImportProgressDialog = preload("res://addons/moonlake_copilot/resource_import/import_progress_dialog.gd")

# Global import lock (class-level static variable) - uses Semaphore for atomicity
static var _import_semaphore: Semaphore = null

# Template resource constants
const TEMPLATE_PATH_PATTERN = "templates/"
const TEMPLATE_SOURCE_BASE = "res://addons/moonlake_copilot/"

static func _get_import_semaphore() -> Semaphore:
	"""Lazy initialization of semaphore to avoid preload issues."""
	if _import_semaphore == null:
		_import_semaphore = Semaphore.new()
		_import_semaphore.post()  # Initialize to 1 (lock available)
	return _import_semaphore


static func _get_local_path_for_type(resource_type: String, filename: String) -> String:
	"""Determine local res:// path based on resource type."""
	var base_dir = ""

	if "Texture" in resource_type or "Image" in resource_type:
		base_dir = "res://assets/textures"
	elif resource_type == "PackedScene" or resource_type == "Mesh":
		base_dir = "res://assets/meshes"
	else:
		base_dir = "res://assets/resources"

	return base_dir.path_join(filename)

static func _get_s3_bucket() -> String:
	var config = MoonlakeResources.get_worker_config()
	match config["moonlake_mode"]:
		"development":
			return "moonlake-generation-development"
		"staging":
			return "moonlake-generation-staging"
		"production":
			return "moonlake-generation-production"
	return "moonlake-generation-production"

static func infer_url_from_path(local_path: String) -> String:
	"""Infer S3 URL from res:// path using project_id from MoonlakeProjectConfig.

	Pattern: res://{path} -> {base_url}{path}
	Example: res://scenes/0/assets/boat_0.glb ->
	         https://moonlake-generation-production.s3.us-east-1.amazonaws.com/godot_projects/{project_id}/scenes/0/assets/boat_0.glb

	Returns: Full S3 URL or empty string on error
	"""
	# Strip sub-resource notation (::SubResource) if present
	var clean_path = local_path
	if "::" in clean_path:
		clean_path = clean_path.split("::")[0]
		if OS.is_debug_build():
			Log.info("[URL_INFERENCE] Stripped sub-resource notation: %s -> %s" % [local_path, clean_path])

	if not clean_path.begins_with("res://"):
		Log.error("[URL_INFERENCE] Path must start with res://: %s" % clean_path)
		return ""

	var project_id = MoonlakeProjectConfig.get_singleton().get_project_id()

	# Strip res:// prefix
	var path_without_prefix = clean_path.substr(6)  # "res://" is 6 characters

	# URL-encode the path for S3 compatibility (handles spaces, special characters)
	# Split by '/', encode each component, then rejoin to preserve forward slashes
	var path_parts = path_without_prefix.split("/")
	var encoded_parts: Array[String] = []
	for part in path_parts:
		if part.is_empty():
			continue  # Skip empty parts (from double slashes)
		encoded_parts.append(part.uri_encode())
	var encoded_path = "/".join(encoded_parts)

	var base_url = "https://%s.s3.us-east-1.amazonaws.com/godot_projects/%s/" % [_get_s3_bucket(), project_id]
	return base_url + encoded_path

static func resolve_template_resource(local_path: String) -> Dictionary:
	"""Resolve template resources by copying from moonlake_copilot templates folder.

	Args:
		local_path: Target res:// path (e.g., res://scenes/2/assets/templates/shaders/water.gdshader)

	Returns:
		Dictionary with {success: bool, copied: bool, error: String, source_path: String}
	"""
	var result = {
		"success": false,
		"copied": false,
		"error": "",
		"source_path": ""
	}

	# Check if path contains templates/ pattern
	if not TEMPLATE_PATH_PATTERN in local_path:
		return result

	# Extract everything from "templates/" onwards
	var template_index = local_path.find(TEMPLATE_PATH_PATTERN)
	if template_index == -1:
		return result

	var relative_path = local_path.substr(template_index)

	# Construct source path
	var source_path = TEMPLATE_SOURCE_BASE + relative_path
	result["source_path"] = source_path

	# Check if source exists
	if not FileAccess.file_exists(source_path):
		result["error"] = "Template resource not found: %s" % source_path
		return result

	# Check if target already exists
	if FileAccess.file_exists(local_path):
		result["success"] = true
		result["copied"] = false
		Log.info("[TEMPLATE] Already exists: %s" % local_path)
		return result

	# Create target directory if needed
	var target_dir = local_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		var err = DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			result["error"] = "Failed to create directory: %s (error code: %d)" % [target_dir, err]
			return result

	# Copy file from source to target
	var err = DirAccess.copy_absolute(source_path, local_path)
	if err != OK:
		result["error"] = "Failed to copy: %s -> %s (error code: %d)" % [source_path, local_path, err]
		return result

	# Success
	result["success"] = true
	result["copied"] = true
	Log.info("[TEMPLATE] Copied: %s -> %s" % [source_path, local_path])
	return result

## ============================================================================
## resolve_resources v2 - Parallel downloads with retry and progress dialog
## ============================================================================

static func _classify_priority(filename: String) -> int:
	"""Determine priority based on filename keywords. Returns 0=skybox, 1=terrain, 2=player, 3=other."""
	var lower = filename.to_lower()

	# Priority 0: Skybox HDR (highest - needed for environment lighting)
	if lower.ends_with(".hdr") or "skybox" in lower or "environment" in lower:
		return 0

	# Priority 1: Terrain
	if "terrain" in lower or "heightmap" in lower or "splat" in lower or "color" in lower:
		return 1

	# Priority 2: Player-related
	if "player" in lower or "character" in lower or "avatar" in lower:
		return 2

	# Priority 3: Other (default - meshes, textures, etc.)
	return 3

static func resolve_resources_v2(
	tscn_path: String,
	dialog: ImportProgressDialog,
	priority_min: int = 0,
	priority_max: int = 999,
	timeout_per_download: float = DownloadConfig.DOWNLOAD_TIMEOUT_PER_ATTEMPT,
	max_total_timeout: float = DownloadConfig.DOWNLOAD_MAX_TOTAL_TIMEOUT,
	worker_count: int = DownloadConfig.WORKER_POOL_SIZE,
	batch_size: int = 10,
	pre_captured_tasks: Array = [],  # Optional: pre-captured tasks (for Phase 4)
	plugin: EditorPlugin = null  # Optional: EditorPlugin instance for scene_changed signal
):
	"""Public wrapper that manages import lock. Dialog is owned by caller.

	Args:
		priority_min: Minimum priority to download (0=terrain, 1=player, 2=other)
		priority_max: Maximum priority to download (inclusive)
		pre_captured_tasks: Optional pre-captured Array[DownloadTask] (skips TSCN parsing)

	Returns:
		Dictionary with keys: {summary: String, url_mapping: Dictionary, success: bool}
		Or String error message if import fails early
	"""

	# Atomic lock check using Semaphore
	var sem = _get_import_semaphore()
	if not sem.try_wait():
		return "Import already in progress"

	# Quick check: does this scene have any restorable resources?
	# Skip check if using pre-captured tasks
	if pre_captured_tasks.is_empty() and not has_restorable_resources_from_file(tscn_path):
		sem.post()  # Release lock
		Log.info("[RESOLVE] No restorable resources found in TSCN - skipping import")
		return "No external resources to download (all resources already local)"

	# Dialog is owned by caller - just use it
	# Call implementation
	var result = await _resolve_resources_v2_impl(
		dialog,
		tscn_path,
		priority_min,
		priority_max,
		timeout_per_download,
		max_total_timeout,
		worker_count,
		batch_size,
		pre_captured_tasks,
		plugin
	)

	# Dialog cleanup is now handled by caller (plugin.gd)
	sem.post()  # Release lock

	return result

static func _print_dep_tree(tree: Array, indent: String = "", is_last: bool = true) -> void:
	"""Recursively print dependency tree with box drawing characters."""
	for i in range(tree.size()):
		var node: Dictionary = tree[i]
		var is_last_item = (i == tree.size() - 1)
		var prefix = indent + ("└─ " if is_last_item else "├─ ")

		var status_str = ""
		if node.status == "s":
			status_str = " (s)"
		elif node.status == "f":
			status_str = " (f: %s)" % node.reason
		elif node.status == "skip":
			status_str = " (skip: %s)" % node.reason

		Log.info(prefix + node.name + status_str)

		# Print children with appropriate indentation
		if not node.children.is_empty():
			var child_indent = indent + ("   " if is_last_item else "│  ")
			_print_dep_tree(node.children, child_indent, is_last_item)

static func has_restorable_resources_from_file(tscn_path: String) -> bool:
	"""Check if TSCN has missing resources that can be restored via URL inference.

	Reads the TSCN file as text and parses ext_resource lines.
	"""
	var file = FileAccess.open(tscn_path, FileAccess.READ)
	if file == null:
		return false

	var content = file.get_as_text()
	file.close()

	# Parse ext_resource lines
	var lines = content.split("\n")
	var regex = RegEx.new()
	regex.compile('path="([^"]*)"')

	for line in lines:
		if not line.begins_with("[ext_resource"):
			continue

		# Extract path using regex
		var result = regex.search(line)
		if not result:
			continue

		var path = result.get_string(1)
		if path.is_empty():
			continue

		# Check if local file is missing and can be inferred
		if path.begins_with("res://"):
			var exists = FileAccess.file_exists(path)
			if not exists:
				var inferred_url = infer_url_from_path(path)
				if not inferred_url.is_empty():
					return true

	return false


static func _resolve_resources_v2_impl(
	dialog: ImportProgressDialog,
	tscn_path: String,
	priority_min: int,
	priority_max: int,
	timeout_per_download: float,
	max_total_timeout: float,
	worker_count: int,
	batch_size: int,
	pre_captured_tasks: Array = [],  # Optional: pre-captured tasks from Phase 0
	plugin: EditorPlugin = null  # Optional: EditorPlugin for scene_changed signal
):
	"""Core implementation with defensive programming throughout.

	Args:
		tscn_path: Path to TSCN file to parse
		priority_min: Minimum priority to download (inclusive)
		priority_max: Maximum priority to download (inclusive)
		pre_captured_tasks: Optional pre-captured Array[DownloadTask] (skips TSCN parsing)

	Returns:
		Dictionary with keys: {summary: String, url_mapping: Dictionary, success: bool}
		Or String error message on failure
	"""

	# Step 1: Use pre-captured tasks or parse TSCN
	var task_map: Dictionary = {}  # "(url|local_path)" -> DownloadTask
	var skipped_count = 0

	if not pre_captured_tasks.is_empty():
		# Use pre-captured tasks from Phase 0
		Log.info("[RESOLVE] Using %d pre-captured tasks" % pre_captured_tasks.size())
		for task in pre_captured_tasks:
			var task_key = task.url + "|" + task.local_path
			task_map[task_key] = task
	else:
		# Read and parse TSCN file as text
		var file = FileAccess.open(tscn_path, FileAccess.READ)
		if file == null:
			return {"success": false, "summary": "Error: Could not read TSCN file", "url_mapping": {}}

		var content = file.get_as_text()
		file.close()

		var lines = content.split("\n")

		# Single regex with named groups - attributes can be in any order
		var regex = RegEx.new()
		regex.compile('type="(?<type>[^"]*)".*?path="(?<path>[^"]*)".*?id="(?<id>[^"]*)"')

		for line in lines:
			if not line.begins_with("[ext_resource"):
				continue

			# Extract all attributes in one match
			var match = regex.search(line)
			if not match:
				continue

			var resource_type = match.get_string("type")
			var path = match.get_string("path")
			var resource_id = match.get_string("id")

			# Validate required attributes
			if resource_type.is_empty() or path.is_empty() or resource_id.is_empty():
				continue

			# Check if this is an HTTP URL
			var is_http = path.begins_with("http://") or path.begins_with("https://")

			# Check if this is a restorable resource (res:// path with missing file)
			var is_restorable = false
			var inferred_url = ""
			if path.begins_with("res://") and not FileAccess.file_exists(path):
				inferred_url = infer_url_from_path(path)
				if not inferred_url.is_empty():
					is_restorable = true

			# Don't skip .tscn files even if they exist - they need recursive scanning
			var is_tscn = path.ends_with(".tscn")
			if not is_http and not is_restorable and not is_tscn:
				if OS.is_debug_build():
					Log.info("[RESOLVE] Skipped (local exists): %s" % path)
				skipped_count += 1
				continue

			# Use inferred URL if restoring missing file, otherwise use path
			var url = inferred_url if is_restorable else path
			var filename = url.split("/")[-1] if "/" in url else url
			var local_path: String

			if is_restorable:
				# Use existing path from TSCN (already res://)
				local_path = path
			elif is_tscn and FileAccess.file_exists(path):
				# Existing .tscn file - use as-is for recursive scanning
				local_path = path
			else:
				# Compute local path from URL
				local_path = _get_local_path_for_type(resource_type, filename)

			# Determine priority
			var priority = _classify_priority(filename)

			# Deduplication key
			var task_key = url + "|" + local_path

			if task_key in task_map:
				# Task already exists, add this resource_id
				var task = task_map[task_key]
				task.resource_ids.append(resource_id)
			else:
				# Create new task
				var task = DownloadTask.new(url, local_path, priority)
				task.resource_ids.append(resource_id)
				task_map[task_key] = task

		# Scan for terrain custom properties (not tracked by ResourceLoader.get_dependencies)
		var terrain_property_names = ["height_file_name", "control_file_name", "color_file_name"]
		var property_regex = RegEx.new()
		var pattern = "(%s)\\s*=\\s*\"(res://[^\"]+)\"" % "|".join(terrain_property_names)
		property_regex.compile(pattern)

		for line in lines:
			var match_result = property_regex.search(line)
			if match_result:
				var property_name = match_result.get_string(1)
				var res_path = match_result.get_string(2)

				# Skip if file exists locally
				if FileAccess.file_exists(res_path):
					if OS.is_debug_build():
						Log.info("[RESOLVE] Skipped terrain property (local exists): %s = %s" % [property_name, res_path])
					skipped_count += 1
					continue

				# Infer S3 URL from res:// path
				var inferred_url = infer_url_from_path(res_path)
				if inferred_url.is_empty():
					if OS.is_debug_build():
						Log.info("[RESOLVE] Skipped terrain property (no URL inference): %s = %s" % [property_name, res_path])
					skipped_count += 1
					continue

				var url = inferred_url
				var local_path = res_path
				var filename = url.split("/")[-1] if "/" in url else url
				var priority = _classify_priority(filename)
				var task_key = url + "|" + local_path

				if not task_key in task_map:
					var task = DownloadTask.new(url, local_path, priority)
					task_map[task_key] = task
					Log.info("[RESOLVE] Added terrain property: %s = %s" % [property_name, res_path])

	# Filter tasks by priority range
	var original_task_count = task_map.size()
	var filtered_task_keys: Array = []
	for task_key in task_map:
		var task: DownloadTask = task_map[task_key]
		if task.priority >= priority_min and task.priority <= priority_max:
			filtered_task_keys.append(task_key)

	# Create new filtered task map
	var filtered_task_map: Dictionary = {}
	for task_key in filtered_task_keys:
		filtered_task_map[task_key] = task_map[task_key]

	# Replace task_map with filtered version
	task_map = filtered_task_map

	Log.info("[RESOLVE] Filtered %d tasks to %d tasks (priority %d-%d)" % [original_task_count, task_map.size(), priority_min, priority_max])

	if task_map.size() == 0:
		return "No tasks match priority filter (priority %d-%d)" % [priority_min, priority_max]

	# Step 3.5: Resolve template resources (copy from moonlake_copilot templates folder)
	Log.info("[RESOLVE] Resolving template resources...")
	var template_copied_count = 0
	var template_cached_count = 0
	var template_failed_count = 0

	for task_key in task_map:
		var task: DownloadTask = task_map[task_key]

		# Check if this is a template resource
		if TEMPLATE_PATH_PATTERN in task.local_path:
			var resolve_result = resolve_template_resource(task.local_path)

			if resolve_result["success"]:
				if resolve_result["copied"]:
					template_copied_count += 1
				else:
					template_cached_count += 1
				# Mark task as cached so it skips S3 download
				task.state = "cached"
			else:
				# Template resolution failed - mark as failed (no S3 fallback)
				template_failed_count += 1
				task.state = "failed"
				Log.error("[TEMPLATE] Copy failed: %s" % resolve_result["error"])

	if template_copied_count > 0 or template_cached_count > 0 or template_failed_count > 0:
		Log.info("[RESOLVE] Template resources: %d copied, %d cached, %d failed" % [template_copied_count, template_cached_count, template_failed_count])

	# Step 3.6: Parse nodes to populate node_instances for placeholders
	# Skip if using pre-captured tasks (node_instances already populated)
	if pre_captured_tasks.is_empty():
		Log.info("[RESOLVE] Parsing node instances for placeholder mapping...")

		# Parse node sections from TSCN text
		var file_for_nodes = FileAccess.open(tscn_path, FileAccess.READ)
		if file_for_nodes:
			var node_content = file_for_nodes.get_as_text()
			file_for_nodes.close()

			var node_lines = node_content.split("\n")
			var name_regex = RegEx.new()
			name_regex.compile('name="(?<name>[^"]*)"')
			var parent_regex = RegEx.new()
			parent_regex.compile('parent="(?<parent>[^"]*)"')
			var instance_regex = RegEx.new()
			instance_regex.compile('instance=ExtResource\\("(?<id>[^"]*)"\\)')
			var transform_regex = RegEx.new()
			transform_regex.compile('transform\\s*=\\s*Transform3D\\(([^)]+)\\)')

			var current_section = ""
			var current_node_name = ""
			var current_parent = "."
			var current_transform = ""
			var current_pending_task = null  # Track task to add node_info to later

			for node_line in node_lines:
				# Check if this is a node section header
				if node_line.begins_with("[node"):
					# Finalize previous node if it had a pending task
					if current_pending_task and not current_node_name.is_empty():
						var node_info = {
							"node_name": current_node_name,
							"parent": current_parent,
							"transform": current_transform
						}
						current_pending_task.node_instances.append(node_info)

					# Extract node attributes from current line
					current_node_name = ""
					current_parent = "."
					current_transform = ""
					current_pending_task = null
					current_section = node_line

					var name_match = name_regex.search(node_line)
					if name_match:
						current_node_name = name_match.get_string("name")

					var parent_match = parent_regex.search(node_line)
					if parent_match:
						current_parent = parent_match.get_string("parent")
						if current_parent.is_empty():
							current_parent = "."

					# Check for instance in section header
					var instance_match = instance_regex.search(node_line)
					if instance_match and not current_node_name.is_empty():
						var ext_id = instance_match.get_string("id")
						# Find which task uses this ExtResource ID
						for task_key in task_map:
							var task: DownloadTask = task_map[task_key]
							if ext_id in task.resource_ids:
								current_pending_task = task
								break

				# Check for transform property in body
				elif not current_node_name.is_empty() and node_line.begins_with("transform"):
					var transform_match = transform_regex.search(node_line)
					if transform_match:
						current_transform = transform_match.get_string(1)

				# Check for mesh/scene properties
				elif not current_node_name.is_empty() and (node_line.begins_with("mesh") or node_line.begins_with("scene")):
					var resource_match = instance_regex.search(node_line)
					if resource_match:
						var ext_id = resource_match.get_string("id")
						# Find which task uses this ExtResource ID
						for task_key in task_map:
							var task: DownloadTask = task_map[task_key]
							if ext_id in task.resource_ids:
								current_pending_task = task
								break

			# Finalize last node if it had a pending task
			if current_pending_task and not current_node_name.is_empty():
				var node_info = {
					"node_name": current_node_name,
					"parent": current_parent,
					"transform": current_transform
				}
				current_pending_task.node_instances.append(node_info)

	# Step 4: Separate TSCN tasks from other resources
	var tscn_tasks: Array = []
	var other_tasks: Array = []

	for task_key in task_map:
		var task: DownloadTask = task_map[task_key]

		# Create directory if needed
		var dir_path = task.local_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			var err = DirAccess.make_dir_recursive_absolute(dir_path)
			if err != OK:
				Log.warn("[WARN] Could not create directory: %s" % dir_path)

		# Check if file already exists
		if FileAccess.file_exists(task.local_path):
			task.state = "cached"
		else:
			task.state = "pending"

		# Separate TSCNs from other resources
		if task.local_path.ends_with(".tscn"):
			tscn_tasks.append(task)
		else:
			other_tasks.append(task)

	Log.info("[RECURSIVE] Found %d TSCN dependencies, %d other dependencies" % [tscn_tasks.size(), other_tasks.size()])

	# Create download queue for non-TSCN resources
	var download_queue = DownloadQueue.new()
	for task in other_tasks:
		download_queue.add_task(task)

	# Step 5: Check for unsaved changes and create placeholders
	var editor_interface = Engine.get_singleton("EditorInterface")
	var placeholder_manager = null
	if editor_interface:
		var edited_root = editor_interface.get_edited_scene_root()
		if edited_root and edited_root.scene_file_path == tscn_path:
			# Scene is open - check for unsaved changes
			if editor_interface.is_plugin_enabled("moonlake_copilot"):  # Placeholder for has_unsaved_changes check
				# TODO: Implement proper unsaved changes check
				# For now, we'll skip this check and just warn
				Log.warn("[WARN] Scene may have unsaved changes")

			# Create placeholders for pending downloads (only for Phase 4: priority >= 3)
			# Phase 3 (avatar) uses modal dialog and doesn't need placeholders
			if priority_min >= 3:
				placeholder_manager = PlaceholderManager.new()
				var pending_tasks: Array[DownloadTask] = []
				for task in download_queue.tasks:
					if task.state == "pending":
						pending_tasks.append(task)

				if not pending_tasks.is_empty():
					placeholder_manager.create_placeholders_for_tasks(pending_tasks, tscn_path)
					var placeholder_count = 0
					for task in pending_tasks:
						placeholder_count += task.node_instances.size()
					Log.info("[RESOLVE] Created %d placeholder(s) for pending meshes" % placeholder_count)
			else:
				# Count how many downloads are pending (without creating placeholders)
				var placeholder_count = 0
				for task in download_queue.tasks:
					if task.state == "pending":
						placeholder_count += task.node_instances.size()
				Log.info("[RESOLVE] Scene is open, %d pending downloads (no placeholders for priority < 3)" % placeholder_count)

	# Step 6: Initialize worker pool and connect dialog
	var worker_pool = DownloadWorkerPool.new(worker_count, timeout_per_download, batch_size)
	dialog.connect_to_worker_pool(worker_pool)

	# Set total tasks for progress tracking (only count pending tasks)
	var pending_count = 0
	for task in download_queue.tasks:
		if task.state == "pending":
			pending_count += 1
	dialog.set_total_tasks(pending_count)

	# Step 7: Define batch callback
	var batch_callback = func(completed_count: int) -> bool:
		dialog.update_status("Importing batch %d..." % (completed_count / batch_size))
		dialog.set_cancel_enabled(false)

		# Collect downloaded files for this batch
		var downloaded_files: Array = []
		for task in download_queue.tasks:
			if task.state == "completed" and FileAccess.file_exists(task.local_path):
				downloaded_files.append(task.local_path)

		# Trigger batch import
		var import_success = await FileOperations._batch_import_resources(editor_interface, downloaded_files)
		if not import_success:
			Log.warn("[WARN] Batch import failed or timed out, continuing anyway")

		# Replace placeholders for imported resources
		if placeholder_manager:
			for task in download_queue.tasks:
				if task.state == "completed" and FileAccess.file_exists(task.local_path):
					placeholder_manager.replace_placeholders(task)
					Log.info("[RESOLVE] Replaced placeholders for: %s" % task.url.get_file())

		dialog.set_cancel_enabled(true)

		# Check cancellation flag
		if worker_pool.cancelled:
			return false
		return true

	# Step 8: Process all downloads
	Log.info("[RESOLVE] Starting parallel downloads...")
	var summary = await worker_pool.process_all(download_queue, batch_callback)

	# Step 9: Final import batch - collect any remaining files
	dialog.update_status("Importing final batch...")
	dialog.set_cancel_enabled(false)
	var final_files: Array = []
	for task in download_queue.tasks:
		if task.state == "completed" and FileAccess.file_exists(task.local_path):
			final_files.append(task.local_path)
	var final_import = await FileOperations._batch_import_resources(editor_interface, final_files)
	if not final_import:
		Log.warn("[WARN] Final import failed or timed out")

	# Replace any remaining placeholders after final import
	if placeholder_manager:
		for task in download_queue.tasks:
			if task.state == "completed" and FileAccess.file_exists(task.local_path):
				placeholder_manager.replace_placeholders(task)
		Log.info("[RESOLVE] Replaced all remaining placeholders")

	# Step 9.5: Import Terrain3D data if terrain files were downloaded
	if priority_min <= 1 and priority_max >= 1 and editor_interface:
		# Collect terrain file paths from completed tasks
		var height_path = ""
		var control_path = ""
		var color_path = ""

		for task in download_queue.tasks:
			if task.state == "completed" or task.state == "cached":
				var filename = task.local_path.get_file().to_lower()
				if "height" in filename or "heightmap" in filename:
					height_path = task.local_path
				elif "control" in filename or "splatmap" in filename:
					control_path = task.local_path
				elif "color" in filename or "colormap" in filename:
					color_path = task.local_path
			
		# Run import if we have at least one terrain file
		if not height_path.is_empty() or not control_path.is_empty() or not color_path.is_empty():
			Log.info("[TERRAIN3D] Found terrain files: height=%s, control=%s, color=%s" % [height_path, control_path, color_path])
			dialog.update_status("Importing terrain image files...")

			# CRITICAL: Force filesystem scan and wait for imports BEFORE opening scene
			var fs = editor_interface.get_resource_filesystem()
			if fs:
				Log.info("[TERRAIN3D] Forcing filesystem scan for terrain images...")
				fs.scan()

				# Wait for scan to complete
				if fs.is_scanning():
					await fs.filesystem_changed

				# Wait for actual imports to complete
				Log.info("[TERRAIN3D] Waiting for terrain image imports to complete...")
				await fs.resources_reimported


			# Open the terrain scene in the editor (force open even with dependency issues)
			Log.info("[TERRAIN3D] Opening terrain scene: %s" % tscn_path)
			dialog.update_status("Importing Terrain3D data...")


			# Open the terrain scene
			editor_interface.open_scene_from_path(tscn_path, false, true)  # set_inherited=false, ignore_broken_deps=true

			# Check if scene loaded immediately (synchronously)
			var terrain_scene = editor_interface.get_edited_scene_root()
			if not terrain_scene or terrain_scene.scene_file_path != tscn_path:
				# Scene not loaded yet, wait for signal
				if plugin:
					await plugin.scene_changed
				else:
					Log.warn("[TERRAIN3D] WARNING: No plugin instance, using frame wait fallback")
					await editor_interface.get_base_control().get_tree().process_frame
				# Get scene after waiting
				terrain_scene = editor_interface.get_edited_scene_root()
			if not terrain_scene:
				Log.error("[TERRAIN3D] ERROR: Failed to open terrain scene")
			else:
				# Find Terrain3D node in the live scene
				var terrain_nodes = terrain_scene.find_children("", "Terrain3D", true, false)
				if not terrain_nodes.is_empty():
					var terrain_node = terrain_nodes[0]
					Log.info("[TERRAIN3D] Found Terrain3D node: %s" % terrain_node.name)

					# Run the import
					Terrain3DOperations.import_terrain_data(terrain_node, height_path, control_path, color_path)
					Log.info("[TERRAIN3D] Import complete")

					# Save the terrain scene
					editor_interface.save_scene()
					Log.info("[TERRAIN3D] Saved terrain scene")
				else:
					Log.warn("[TERRAIN3D] WARNING: No Terrain3D node found in scene")

			# Don't close the terrain scene - just leave it open
			# Closing it properly would require more complex EditorNode interaction
			# The scene will be properly cleaned up when the user opens another scene
			Log.info("[TERRAIN3D] Terrain import complete (scene left open)")

	# Step 10: Error cylinders will be created AFTER scene opens (see plugin.gd)
	# We can't create them here because the scene isn't open yet

	# Step 11: [RECURSIVE] Download TSCN files sequentially and recursively process each
	var tscn_completed = 0
	var tscn_failed = 0
	var dep_tree: Array = []

	# Add non-TSCN resources to dep tree
	for task in download_queue.tasks:
		var status = "s" if task.state == "completed" or task.state == "cached" else "f"
		var reason = "" if status == "s" else "download failed"
		dep_tree.append({
			"name": task.local_path.get_file(),
			"status": status,
			"reason": reason,
			"children": []
		})

	if not tscn_tasks.is_empty():
		Log.info("[RECURSIVE] Processing %d TSCN dependencies sequentially..." % tscn_tasks.size())

		for task in tscn_tasks:
			if task.state == "cached":
				Log.info("[RECURSIVE] TSCN already exists: %s" % task.local_path)
				tscn_completed += 1

				# Still recursively process cached TSCN if it has missing deps
				if has_restorable_resources_from_file(task.local_path):
					Log.info("[RECURSIVE]   Recursively resolving: %s" % task.local_path.get_file())
					var child_result = await _resolve_resources_v2_impl(dialog, task.local_path, priority_min, priority_max, timeout_per_download, max_total_timeout, worker_count, batch_size, pre_captured_tasks, plugin)
					if child_result is Dictionary:
						Log.info("[RECURSIVE]   Child completed: %s" % child_result.get("summary", ""))
						# Add to tree with children
						dep_tree.append({
							"name": task.local_path.get_file(),
							"status": "s",
							"reason": "",
							"children": child_result.get("dep_tree", [])
						})
					else:
						# Add failed node
						dep_tree.append({
							"name": task.local_path.get_file(),
							"status": "f",
							"reason": str(child_result),
							"children": []
						})
				else:
					# TSCN exists with no nested deps
					dep_tree.append({
						"name": task.local_path.get_file(),
						"status": "s",
						"reason": "",
						"children": []
					})
			else:
				# Download the TSCN file
				Log.info("[RECURSIVE] Downloading TSCN: %s" % task.url)
				dialog.update_status("Downloading TSCN: %s" % task.local_path.get_file())

				var download_result = await FileOperations._download_file(task.url, task.local_path, timeout_per_download)

				if download_result.success:
					Log.info("[RECURSIVE] Downloaded: %s" % task.local_path.get_file())
					task.state = "completed"
					tscn_completed += 1

					# Recursively resolve this TSCN's dependencies immediately
					Log.info("[RECURSIVE]   Recursively resolving: %s" % task.local_path.get_file())
					var child_result = await _resolve_resources_v2_impl(dialog, task.local_path, priority_min, priority_max, timeout_per_download, max_total_timeout, worker_count, batch_size, pre_captured_tasks, plugin)
					if child_result is Dictionary:
						Log.info("[RECURSIVE]   Child completed: %s" % child_result.get("summary", ""))
						# Add to tree with children
						dep_tree.append({
							"name": task.local_path.get_file(),
							"status": "s",
							"reason": "",
							"children": child_result.get("dep_tree", [])
						})
					else:
						Log.error("[RECURSIVE]   Child failed: %s" % str(child_result))
						# Add failed node
						dep_tree.append({
							"name": task.local_path.get_file(),
							"status": "f",
							"reason": str(child_result),
							"children": []
						})
				else:
					Log.error("[RECURSIVE] Failed to download: %s (%s)" % [task.url, download_result.message])
					task.state = "failed"
					tscn_failed += 1
					# Add failed node
					dep_tree.append({
						"name": task.local_path.get_file(),
						"status": "f",
						"reason": str(download_result.get("http_code", 0)),
						"children": []
					})

		Log.info("[RECURSIVE] TSCN processing complete: %d completed, %d failed" % [tscn_completed, tscn_failed])

	# Step 11: Return summary (dialog owned by caller, they handle final summary)
	# Note: TSCN files are already correct (paths are res://, types are correct, nodes use instance syntax)
	# No TSCN modifications needed
	# Don't call show_final_summary here - dialog will be reused for terrain import

	var result_msg = "Resolved %d resources (Completed: %d, Failed: %d, Cached: %d, Cancelled: %d, Skipped: %d) + %d TSCNs (Completed: %d, Failed: %d)" % [
		summary.get("completed", 0) + summary.get("cached", 0),
		summary.get("completed", 0),
		summary.get("failed", 0),
		summary.get("cached", 0),
		summary.get("cancelled", 0),
		skipped_count,
		tscn_completed + tscn_failed,
		tscn_completed,
		tscn_failed
	]

	Log.info("[RESOLVE] %s" % result_msg)

	# Build URL mapping for post-import injection (include both non-TSCN and TSCN tasks)
	var url_mapping: Dictionary = {}
	var completed_tasks: Array = []
	var all_tasks: Array[DownloadTask] = []

	# Add non-TSCN tasks from download queue
	for task in download_queue.tasks:
		all_tasks.append(task)  # Keep ALL tasks (including failed)
		if task.state == "completed" or task.state == "cached":
			url_mapping[task.local_path] = task.url
			completed_tasks.append(task)

	# Add TSCN tasks
	for task in tscn_tasks:
		all_tasks.append(task)  # Keep ALL tasks (including failed)
		if task.state == "completed" or task.state == "cached":
			url_mapping[task.local_path] = task.url
			completed_tasks.append(task)

	# Return summary, mapping, tasks, and dep_tree
	return {
		"summary": result_msg,
		"url_mapping": url_mapping,
		"tasks": completed_tasks,  # Completed tasks for in-memory node replacement
		"all_tasks": all_tasks,  # ALL tasks including failed (for error cylinder creation)
		"dep_tree": dep_tree,
		"success": true
	}

