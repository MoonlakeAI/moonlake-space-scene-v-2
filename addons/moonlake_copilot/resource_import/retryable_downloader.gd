@tool
extends RefCounted
class_name RetryableDownloader

## Handles download retry logic with exponential backoff

const FileOperations = preload("res://addons/moonlake_copilot/operations/file_operations.gd")

static func download_with_retry(url: String, local_path: String, timeout_per_attempt: float = DownloadConfig.DOWNLOAD_TIMEOUT_PER_ATTEMPT) -> Dictionary:
	# DEBUG: Force mesh downloads to fail for testing
	if DownloadConfig.DEBUG_FORCE_MESH_DOWNLOAD_FAILURE:
		var ext = local_path.get_extension().to_lower()
		if ext in ["glb", "gltf", "obj", "mesh"]:
			Log.info("[DEBUG] Forcing mesh download failure for testing: %s" % url.get_file())
			return {
				"success": false,
				"http_code": 404,
				"message": "DEBUG: Forced failure for testing error cylinders",
				"attempts": 1
			}

	var start_time = Time.get_ticks_msec() / 1000.0

	for attempt in range(DownloadConfig.RETRY_MAX_ATTEMPTS):
		# Check if we have time remaining
		var elapsed = Time.get_ticks_msec() / 1000.0 - start_time
		if elapsed >= DownloadConfig.DOWNLOAD_MAX_TOTAL_TIMEOUT:
			return {
				"success": false,
				"http_code": 0,
				"message": "Error: Max retry timeout (%ds) exceeded" % DownloadConfig.DOWNLOAD_MAX_TOTAL_TIMEOUT,
				"attempts": attempt
			}

		# Attempt download
		var result = await FileOperations._download_file(url, local_path, timeout_per_attempt)

		# Success - return immediately
		if result.success:
			result["attempts"] = attempt + 1
			return result

		# For 404 (pending generation), retry with backoff
		# For 5xx (server error), retry with backoff
		# For network errors (timeout, connection failure), retry with backoff
		# For 4xx (except 404), fail immediately
		var should_retry = false
		if result.http_code == 404 or (result.http_code >= 500 and result.http_code < 600):
			should_retry = true
		elif result.get("result_code", 0) in [
			HTTPRequest.RESULT_TIMEOUT,
			HTTPRequest.RESULT_CANT_CONNECT,
			HTTPRequest.RESULT_NO_RESPONSE
		]:
			should_retry = true

		# Last attempt or no retry needed - return failure
		if attempt == DownloadConfig.RETRY_MAX_ATTEMPTS - 1 or not should_retry:
			result["attempts"] = attempt + 1
			return result

		# Wait before next attempt (exponential backoff)
		var delay = DownloadConfig.RETRY_BACKOFF_DELAYS[attempt]
		var failure_reason = "HTTP %d" % result.http_code if result.http_code > 0 else "Result code %d" % result.get("result_code", 0)
		Log.warn("[RETRY] Attempt %d failed (%s), waiting %ds..." % [attempt + 1, failure_reason, delay])

		var scene_tree = Engine.get_main_loop()
		if scene_tree and scene_tree is SceneTree:
			await scene_tree.create_timer(delay).timeout

	# Should never reach here
	return {
		"success": false,
		"http_code": 0,
		"message": "Error: Retry logic error",
		"attempts": DownloadConfig.RETRY_MAX_ATTEMPTS
	}
