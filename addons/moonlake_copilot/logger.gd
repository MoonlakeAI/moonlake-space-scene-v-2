@tool
class_name Log extends Logger

enum Event {
	INFO,
	WARN,
	ERROR,
	CRITICAL,
	FORCE_FLUSH,
}

const _MAX_BUFFER_SIZE: int = 10
const _FLUSH_EVENTS: PackedInt32Array = [
	Event.ERROR,
	Event.CRITICAL,
	Event.FORCE_FLUSH,
]
const EVENT_COLORS: Dictionary[Event, String] = {
	Event.INFO: "obsidian",
	Event.WARN: "gold",
	Event.ERROR: "tomato",
	Event.CRITICAL: "crimson",
}

static var _buffer_size: int
static var _event_strings: PackedStringArray = Event.keys()

static var _log_file: FileAccess
static var _is_valid: bool
static var _mutex := Mutex.new()

static func _static_init() -> void:
	_log_file = _create_log_file()
	_is_valid = _log_file and _log_file.is_open()
	if _is_valid:
		OS.add_logger(Log.new())


static func _create_log_file() -> FileAccess:
	var file_name := Time.get_datetime_string_from_system().replace(":", "-") + ".log"
	var file_path := "user://" + file_name
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	return file

static func _get_gdscript_backtrace(script_backtraces: Array[ScriptBacktrace]) -> String:
	var gdscript := script_backtraces.find_custom(func(backtrace: ScriptBacktrace) -> bool:
		return backtrace.get_language_name() == "GDScript")
	return "Backtrace N/A" if gdscript == -1 else str(script_backtraces[gdscript])

static func _format_log_message(message: String, event: Event) -> String:
	return "[{time}] {event}: {message}".format({
		"time": Time.get_time_string_from_system(),
		"event": _event_strings[event],
		"message": message,
	})

static func _add_message_to_file(message: String, event: Event) -> void:
	_mutex.lock()
	if _is_valid:
		if not message.is_empty():
			_is_valid = _log_file.store_line(message)
			_buffer_size += 1
		if _buffer_size >= _MAX_BUFFER_SIZE or event in _FLUSH_EVENTS:
			_log_file.flush()
			_buffer_size = 0
	_mutex.unlock()

static func _print_event(message: String, event: Event) -> void:
	if not ProjectSettings.get_setting("moonlake/agent_behavior/show_internal_logs", false):
		return
	var message_lines := message.split("\n")
	message_lines[0] = "[b][color=%s]%s[/color][/b]" % [EVENT_COLORS[event], message_lines[0]]
	print_rich.call_deferred("[lang=tlh]%s[/lang]" % "\n".join(message_lines))

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if not _is_valid:
		return
	var event := Event.WARN if error_type == ERROR_TYPE_WARNING else Event.ERROR
	var message := "[{time}] {event}: {rationale}\n{code}\n{file}:{line} @ {function}()".format({
		"time": Time.get_time_string_from_system(),
		"event": _event_strings[event],
		"rationale": rationale,
		"code": code,
		"file": file,
		"line": line,
		"function": function,
 	})
	if event == Event.ERROR:
		message += '\n' + _get_gdscript_backtrace(script_backtraces)
	_add_message_to_file(message, event)

func _log_message(message: String, log_message_error: bool) -> void:
	if not _is_valid or message.begins_with("[lang=tlh]"):
		return
	var event := Event.ERROR if log_message_error else Event.INFO
	message = _format_log_message(message.trim_suffix('\n'), event)
	_add_message_to_file(message, event)

static func info(message: String) -> void:
	if not _is_valid:
		return
	var event := Event.INFO
	message = _format_log_message(message, event)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func warn(message: String) -> void:
	if not _is_valid:
		return
	var event := Event.WARN
	message = _format_log_message(message, event)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func error(message: String) -> void:
	if not _is_valid:
		return
	var event := Event.ERROR
	message = _format_log_message(message, event)
	var script_backtraces := Engine.capture_script_backtraces()
	message += '\n' + _get_gdscript_backtrace(script_backtraces)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func critical(message: String) -> void:
	if not _is_valid:
		return
	var event := Event.CRITICAL
	message = _format_log_message(message, event)
	var script_backtraces := Engine.capture_script_backtraces()
	message += '\n' + _get_gdscript_backtrace(script_backtraces)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func force_flush() -> void:
	_add_message_to_file("", Event.FORCE_FLUSH)