@tool
extends RefCounted
class_name EditorUtils

## Shared editor utilities for the Moonlake Copilot plugin.

static func await_filesystem_ready(fs: EditorFileSystem, timeout_sec: float) -> bool:
	"""Wait for filesystem to finish scanning/importing using polling with timeout.
	Returns true if completed, false if timed out.

	Note: Uses polling instead of signals due to GDScript closure issues on Windows
	where signal callbacks don't reliably modify captured variables."""
	if not fs.is_scanning() and not fs.is_importing():
		return true

	var start_ms = Time.get_ticks_msec()
	var timeout_ms = timeout_sec * 1000.0

	while Time.get_ticks_msec() - start_ms < timeout_ms:
		await Engine.get_main_loop().create_timer(0.1).timeout
		if not fs.is_scanning() and not fs.is_importing():
			return true

	Log.warn("[EditorUtils] Timeout waiting for filesystem (%.1fs)" % timeout_sec)
	return false
