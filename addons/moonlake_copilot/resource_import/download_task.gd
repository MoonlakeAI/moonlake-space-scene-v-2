@tool
extends RefCounted
class_name DownloadTask

## Data structure for tracking individual resource downloads
## Deduplication key: Tasks are unique by (url, local_path) tuple

var url: String
var local_path: String
var resource_ids: Array[String]  # All resource IDs that reference this (url, local_path)
var priority: int  # 0=terrain, 1=player, 2=other
var state: String  # "cached", "pending", "in_progress", "completed", "failed"
var retry_count: int = 0
var error_message: String = ""
var tscn_line_indices: Array[int]  # Line numbers in TSCN for updates
var node_instances: Array[Dictionary]  # For placeholder tracking: [{node_name: String, parent: String}]
var start_time: float = 0.0  # For timeout enforcement

func _init(p_url: String, p_local_path: String, p_priority: int):
	url = p_url
	local_path = p_local_path
	priority = p_priority
	resource_ids = []
	tscn_line_indices = []
	node_instances = []
	state = "pending"
