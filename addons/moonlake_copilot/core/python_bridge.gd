@tool
extends Node

signal response_received(id: int, ok: bool, result, error_msg: String)
signal worker_restarted()
signal worker_ready_received()

var proc := {}
var io: FileAccess
var err: FileAccess
var pid: int = -1
var worker_ready: bool = false

var next_id: int = 1
var pending := {}
var awaiting := {}

# Auto-restart configuration
var auto_restart_enabled: bool = true
var restart_attempts: int = 0
var max_restart_attempts: int = 5  # Give up after 5 attempts
var restart_timer: Timer = null
var last_cmd: String = ""
var last_args: PackedStringArray = []

static func make_message_payload(local_message_id: String, message: String, display_text: String = "") -> Dictionary:
    """Create base payload for send_user_message with common fields."""
    return {
        "local_message_id": local_message_id,
        "message": message,
        "display_text": display_text if not display_text.is_empty() else message,
        "images": [],
        "selected_entities": [],
        "workdir": ProjectSettings.globalize_path("res://"),
        "show_wait_messages_when_slow": ProjectSettings.get_setting("moonlake/agent_behavior/show_wait_messages_when_slow", true),
    }


func _ready() -> void:
    # Create timer for delayed restarts
    restart_timer = Timer.new()
    restart_timer.one_shot = true
    restart_timer.timeout.connect(_on_restart_timer_timeout)
    add_child(restart_timer)

func _on_restart_timer_timeout() -> void:
    Log.warn("[MOONLAKE] Attempting to restart Python worker...")
    _do_start(last_cmd, last_args, true)

func start(_deprecated = null) -> void:
    if pid != -1:
        return

    if DisplayServer.get_name() == "headless":
        Log.info("[MOONLAKE] Headless mode - skipping Python worker")
        return

    var cmd: String
    var args := PackedStringArray([])

    var worker_config: Dictionary = MoonlakeResources.get_worker_config()
    var is_dev = worker_config["moonlake_mode"] == "development"
    worker_config["executable_path"] = OS.get_executable_path()
    worker_config["app_version"] = MoonlakeResources.get_version()
    if ProjectSettings.has_setting("moonlake/general/project_type"):
        worker_config["project_type"] = ProjectSettings.get_setting("moonlake/general/project_type")
    elif ProjectSettings.has_setting("moonlake/project_type"):
        worker_config["project_type"] = ProjectSettings.get_setting("moonlake/project_type")
    else:
        worker_config["project_type"] = "unknown"
    var config_json: String = JSON.stringify(worker_config)
    var config_b64: String = Marshalls.utf8_to_base64(config_json)

    if is_dev:
        var dev_worker = _get_dev_python_worker()
        if dev_worker.is_empty():
            Log.error("[MOONLAKE] Dev mode but Python worker not found")
            return
        cmd = dev_worker["cmd"]
        args = dev_worker["args"]
        args.append("--config_b64")
        args.append(config_b64)
        Log.info("[MOONLAKE] Dev mode - using Python script")
    else:
        cmd = MoonlakeResources.ensure_worker_extracted()
        if cmd.is_empty():
            Log.error("[MOONLAKE] Production mode but worker binary not found")
            return
        args.append("--config_b64")
        args.append(config_b64)
        Log.info("[MOONLAKE] Production mode - using embedded binary")

    # Save for potential restarts
    last_cmd = cmd
    last_args = args
    restart_attempts = 0

    _do_start(cmd, args, false)

func _do_start(cmd: String, args: PackedStringArray, is_restart: bool) -> void:
    """Internal function to start or restart the Python worker"""
    if pid != -1:
        return

    worker_ready = false

    if is_restart:
        restart_attempts += 1
        Log.warn("[MOONLAKE] Restart attempt #%d" % restart_attempts)

    proc = OS.execute_with_pipe(cmd, args, false)
    if proc.is_empty():
        Log.error("[MOONLAKE] Failed to start Python worker (OS.execute_with_pipe returned empty Dictionary).")
        _schedule_restart()
        return

    io = proc["stdio"]
    err = proc["stderr"]
    pid = proc["pid"]
    Log.info("[MOONLAKE] Waiting for Python worker ready signal...")

    if is_restart:
        restart_attempts = 0

func _schedule_restart() -> void:
    """Schedule a restart with exponential backoff"""
    if not auto_restart_enabled:
        Log.error("[MOONLAKE] Auto-restart is disabled, Python worker will not restart")
        return

    if max_restart_attempts >= 0 and restart_attempts >= max_restart_attempts:
        Log.error("[MOONLAKE] Max restart attempts (%d) reached, giving up" % max_restart_attempts)
        return

    # Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s (max)
    var delay = min(pow(2, restart_attempts), 60.0)
    Log.warn("[MOONLAKE] Scheduling Python worker restart in %.1fs..." % delay)

    if restart_timer:
        restart_timer.start(delay)

func _get_dev_python_worker() -> Dictionary:
    var repo_root := MoonlakeResources.get_dev_repo_root()
    if repo_root.is_empty():
        Log.error("[MOONLAKE] get_dev_repo_root() returned empty (not in dev mode?)")
        return {}

    var py := repo_root.path_join("godot_worker/.venv/bin/python")
    var worker_script := repo_root.path_join("godot_worker/godot_worker/worker.py")

    if OS.get_name() == "Windows":
        py = repo_root.path_join("godot_worker/.venv/Scripts/python.exe")

    if not FileAccess.file_exists(py):
        Log.error("[MOONLAKE] Dev mode but Python not found at: %s" % py)
        return {}

    if not FileAccess.file_exists(worker_script):
        Log.error("[MOONLAKE] Dev mode but worker script not found at: %s" % worker_script)
        return {}

    return {
        "cmd": py,
        "args": PackedStringArray(["-u", worker_script])  # -u for unbuffered output
    }

func stop() -> void:
    if pid == -1:
        return

    _send_raw({"op": "shutdown"})

    var start_time := Time.get_ticks_msec()
    var grace_msec := 2000
    while OS.is_process_running(pid) and Time.get_ticks_msec() - start_time < grace_msec:
        if io != null:
            _drain_stdout()
        if err != null:
            _drain_stderr()
        OS.delay_msec(10)

    if OS.is_process_running(pid):
        OS.kill(pid)

    pid = -1
    proc = {}
    worker_ready = false
    pending.clear()
    awaiting.clear()

func call_python(op: String, params: Dictionary) -> int:
    var id := next_id
    next_id += 1
    pending[id] = {
        "op": op,
        "params": params,
        "timestamp": Time.get_ticks_msec()
    }
    _send_raw({"id": id, "op": op, "params": params})
    return id

## Call Python operation asynchronously with timeout
## Default timeout: 30 seconds (see godot_worker/godot_worker/config.py for full timeout documentation)
func call_python_async(op: String, params: Dictionary, timeout_sec: float = 30.0) -> Dictionary:
    if not worker_ready:
        await worker_ready_received

    var id := call_python(op, params)
    return await await_response(id, timeout_sec)

func await_response(id: int, timeout_sec: float = 30.0) -> Dictionary:
    var start_time := Time.get_ticks_msec()
    var timeout_msec := timeout_sec * 1000.0
    
    awaiting[id] = {
        "completed": false,
        "ok": false,
        "result": null,
        "error": ""
    }
    
    while Time.get_ticks_msec() - start_time < timeout_msec:
        if awaiting[id]["completed"]:
            var result: Dictionary = awaiting[id]
            awaiting.erase(id)
            
            if not result["ok"]:
                Log.error("Python call failed: " + result["error"])
            
            return result
        
        await get_tree().process_frame
    
    var call_info = pending.get(id, {})
    var op_name = call_info.get("op", "unknown")

    # Build list of other pending operations
    var other_pending = []
    for pending_id in pending.keys():
        if pending_id != id:
            var info = pending[pending_id]
            other_pending.append("%s(id=%d)" % [info.get("op", "?"), pending_id])

    awaiting.erase(id)
    pending.erase(id)

    var pending_info = "none" if other_pending.is_empty() else str(other_pending)
    Log.warn("Python call timeout after %.1f seconds: op='%s' id=%d | Other pending: %s" % [
        timeout_sec, op_name, id, pending_info
    ])

    return {
        "completed": true,
        "ok": false,
        "result": null,
        "error": "Timeout after %.1f seconds" % timeout_sec
    }

func _process(_dt: float) -> void:
    if pid == -1:
        return

    _drain_stdout()
    _drain_stderr()
    _cleanup_stale_pending()

const PENDING_TIMEOUT_MS = 300000  # 5 minutes

func _cleanup_stale_pending() -> void:
    var now = Time.get_ticks_msec()
    var stale_ids = []
    for id in pending.keys():
        var entry = pending[id]
        if now - entry.get("timestamp", 0) > PENDING_TIMEOUT_MS:
            stale_ids.append(id)
    for id in stale_ids:
        pending.erase(id)

func _send_raw(msg: Dictionary) -> void:
    if io == null or pid == -1:
        return

    if not OS.is_process_running(pid):
        Log.error("[MOONLAKE] Cannot send to dead worker process (pid=%d)" % pid)
        pid = -1
        io = null
        err = null
        return

    if not io.is_open():
        Log.error("[MOONLAKE] Attempted to write to closed pipe")
        return

    var json_str = JSON.stringify(msg)
    io.store_string(json_str + "\n")
    io.flush()

func _drain_stdout() -> void:
    if io == null or pid == -1:
        return

    if not OS.is_process_running(pid):
        if not worker_ready:
            Log.error("[MOONLAKE] Python worker crashed on startup (pid=%d)" % pid)
            _drain_stderr()
        else:
            Log.error("[MOONLAKE] Python worker died (pid=%d)" % pid)
        pid = -1
        io = null
        err = null
        _schedule_restart()
        return

    var max_reads = 1000
    var reads = 0
    while reads < max_reads:
        reads += 1

        if pid == -1 or io == null:
            break

        var line: String
        if io != null and io.is_open():
            line = io.get_line()
        else:
            break

        if line.is_empty():
            break

        var parsed = JSON.parse_string(line)
        if typeof(parsed) != TYPE_DICTIONARY:
            if line.begins_with("{"):  # Looks like JSON but failed to parse
                Log.error("[MOONLAKE] Failed to parse JSON from worker: %s" % line)
            continue

        var id = int(parsed.get("id", -1))
        if id != -1 and pending.has(id):
            pending.erase(id)

        var result = parsed.get("result")
        if typeof(result) == TYPE_DICTIONARY and result.get("type") == "worker_ready":
            if not worker_ready:
                worker_ready = true
                Log.info("[MOONLAKE] Python worker ready")
                emit_signal("worker_ready_received")
            continue

        if id != -1 and awaiting.has(id):
            awaiting[id]["completed"] = true
            awaiting[id]["ok"] = bool(parsed.get("ok", false))
            awaiting[id]["result"] = parsed.get("result")
            awaiting[id]["error"] = str(parsed.get("error", ""))

        emit_signal(
            "response_received",
            id,
            bool(parsed.get("ok", false)),
            parsed.get("result"),
            str(parsed.get("error", ""))
        )

func _drain_stderr() -> bool:
    """Drain stderr and return true if any errors were found"""
    if err == null or pid == -1:
        return false

    var had_output := false
    var max_reads = 1000  # Prevent infinite loop

    var reads = 0
    while reads < max_reads:
        reads += 1

        if err == null:
            break

        var line: String
        if err != null and err.is_open():
            line = err.get_line()
        else:
            break

        if line.is_empty():
            break

        had_output = true
        Log.info(line)

    return had_output
