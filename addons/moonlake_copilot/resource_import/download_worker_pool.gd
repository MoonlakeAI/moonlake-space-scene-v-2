@tool
extends RefCounted
class_name DownloadWorkerPool

## Manages concurrent download workers with signal-based parallelism

const DownloadTask = preload("res://addons/moonlake_copilot/resource_import/download_task.gd")
const DownloadQueue = preload("res://addons/moonlake_copilot/resource_import/download_queue.gd")
const RetryableDownloader = preload("res://addons/moonlake_copilot/resource_import/retryable_downloader.gd")

signal download_started(url: String, priority: int)
signal download_completed(url: String, success: bool, http_code: int, error_msg: String)

var worker_count: int
var timeout_per_download: float
var batch_size: int
var cancelled: bool = false
var completion_count: int = 0
var active_downloads: int = 0

func _init(p_worker_count: int = DownloadConfig.WORKER_POOL_SIZE, p_timeout_per_download: float = DownloadConfig.DOWNLOAD_TIMEOUT_PER_ATTEMPT, p_batch_size: int = 10):
	worker_count = p_worker_count
	timeout_per_download = p_timeout_per_download
	batch_size = p_batch_size

func cancel() -> void:
	cancelled = true

func process_all(queue: DownloadQueue, batch_callback: Callable) -> Dictionary:
	cancelled = false
	completion_count = 0
	active_downloads = 0

	# Main coordinator loop - processes queue with max N concurrent downloads
	while not cancelled and (queue.has_pending_tasks() or active_downloads > 0):
		# Launch new downloads up to worker_count limit
		while active_downloads < worker_count and queue.has_pending_tasks() and not cancelled:
			var batch = queue.get_next_batch(1)
			if batch.is_empty():
				break

			var task = batch[0]
			queue.mark_in_progress(task)
			active_downloads += 1

			# Emit signal
			download_started.emit(task.url, task.priority)

			# Launch download (don't await - true parallelism)
			_download_task(task, queue, batch_callback)

		# Wait one frame before checking for more work
		var scene_tree = Engine.get_main_loop()
		if scene_tree and scene_tree is SceneTree:
			await scene_tree.process_frame

	# Transform summary: pending -> cancelled if cancelled flag is true
	var summary = queue.get_summary()
	if cancelled:
		summary["cancelled"] = summary["pending"]
		summary["pending"] = 0
	else:
		summary["cancelled"] = 0

	return summary

func _download_task(task: DownloadTask, queue: DownloadQueue, batch_callback: Callable) -> void:
	# Download with retry (this runs async)
	var result = await RetryableDownloader.download_with_retry(
		task.url,
		task.local_path,
		timeout_per_download
	)

	# DEBUG: Add artificial delay if configured
	if DownloadConfig.WORKER_DEBUG_DELAY > 0.0:
		var scene_tree = Engine.get_main_loop()
		if scene_tree and scene_tree is SceneTree:
			await scene_tree.create_timer(DownloadConfig.WORKER_DEBUG_DELAY).timeout

	# Update task state (runs when download completes)
	if result.success:
		queue.mark_completed(task)
		completion_count += 1

		# Check if batch callback should be triggered (only one coordinator path)
		if completion_count % batch_size == 0:
			var should_continue = await batch_callback.call(completion_count)
			if not should_continue:
				cancelled = true
	else:
		queue.mark_failed(task, result.message)

	# Emit completion signal
	download_completed.emit(task.url, result.success, result.get("http_code", 0), result.message)

	# Decrement active counter
	active_downloads -= 1
