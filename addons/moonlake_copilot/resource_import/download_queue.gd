@tool
extends RefCounted
class_name DownloadQueue

## Priority queue that manages download tasks

const DownloadTask = preload("res://addons/moonlake_copilot/resource_import/download_task.gd")

var tasks: Array[DownloadTask] = []
var task_lookup: Dictionary = {}  # "(url, local_path)" -> DownloadTask

func add_task(task: DownloadTask) -> void:
	var key = _make_key(task.url, task.local_path)
	if key in task_lookup:
		return  # Already exists
	tasks.append(task)
	task_lookup[key] = task
	_sort_by_priority()

func get_next_batch(count: int) -> Array[DownloadTask]:
	var batch: Array[DownloadTask] = []
	for task in tasks:
		if task.state == "pending" and batch.size() < count:
			batch.append(task)
	return batch

func mark_in_progress(task: DownloadTask) -> void:
	task.state = "in_progress"

func mark_completed(task: DownloadTask) -> void:
	task.state = "completed"

func mark_failed(task: DownloadTask, error_msg: String) -> void:
	task.state = "failed"
	task.error_message = error_msg

func has_pending_tasks() -> bool:
	for task in tasks:
		if task.state == "pending":
			return true
	return false

func get_summary() -> Dictionary:
	var completed = 0
	var failed = 0
	var pending = 0
	var cached = 0
	for task in tasks:
		match task.state:
			"completed": completed += 1
			"failed": failed += 1
			"pending": pending += 1
			"cached": cached += 1
	return {
		"completed": completed,
		"failed": failed,
		"pending": pending,
		"cached": cached
	}

func _sort_by_priority() -> void:
	tasks.sort_custom(func(a, b): return a.priority < b.priority)

func _make_key(p_url: String, p_local_path: String) -> String:
	return p_url + "|" + p_local_path
