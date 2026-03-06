@tool
extends Node

## HTTPRequestPool
##
## Pool of HTTPRequest nodes for efficient image loading.
## Phase 7: Multiple choice renderer dependency.

const MAX_CONCURRENT = 8

var _available_requests: Array[HTTPRequest] = []
var _active_requests: Dictionary = {}  # HTTPRequest -> timestamp
var _pending_requests: Array = []  # Queue of {url, callback} when pool exhausted

func _ready() -> void:
	# Create initial pool
	for i in range(MAX_CONCURRENT):
		var request = _create_request()
		_available_requests.append(request)

func _create_request() -> HTTPRequest:
	"""Create a new HTTPRequest node with proper configuration"""
	var request = HTTPRequest.new()
	request.timeout = DownloadConfig.UI_IMAGE_LOAD_TIMEOUT
	request.use_threads = true  # Non-blocking
	add_child(request)
	return request

func fetch(url: String, callback: Callable) -> void:
	"""
	Fetch URL using a pooled HTTPRequest.

	Args:
		url: URL to fetch
		callback: Called with (result: int, response_code: int, headers: Array, body: PackedByteArray)
	"""
	var request: HTTPRequest = null

	# Try to get request from pool
	if _available_requests.size() > 0:
		request = _available_requests.pop_back()
	else:
		# Pool exhausted, queue request
		_pending_requests.append({"url": url, "callback": callback})
		return

	# Track active request
	_active_requests[request] = Time.get_ticks_msec()

	# Connect completion handler (CONNECT_ONE_SHOT)
	request.request_completed.connect(
		func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			_on_request_completed(request, callback, result, response_code, headers, body),
		CONNECT_ONE_SHOT
	)

	# Start request
	var error = request.request(url)
	if error != OK:
		# Request failed to start, return to pool immediately
		_return_to_pool(request)
		callback.call(error, 0, [], PackedByteArray())

func _on_request_completed(
	request: HTTPRequest,
	callback: Callable,
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	"""Handle request completion"""
	# Call user callback
	callback.call(result, response_code, headers, body)

	# Return request to pool
	_return_to_pool(request)

	# Process pending requests
	if _pending_requests.size() > 0:
		var pending = _pending_requests.pop_front()
		fetch(pending["url"], pending["callback"])

func _return_to_pool(request: HTTPRequest) -> void:
	"""Return HTTPRequest to available pool"""
	_active_requests.erase(request)
	_available_requests.append(request)

func _process(_delta: float) -> void:
	"""Clean up idle requests after timeout"""
	var now = Time.get_ticks_msec()

	# Free idle requests older than HTTP_POOL_CLEANUP_DELAY
	var to_free: Array[HTTPRequest] = []
	for request in _available_requests:
		# Check when request was last used
		var last_used = _active_requests.get(request, 0)
		if last_used > 0 and (now - last_used) > DownloadConfig.HTTP_POOL_CLEANUP_DELAY * 1000:
			to_free.append(request)

	# Free old requests
	for request in to_free:
		_available_requests.erase(request)
		request.queue_free()

		# Ensure we maintain at least 1 request in pool
		if _available_requests.size() == 0:
			var new_request = _create_request()
			_available_requests.append(new_request)
