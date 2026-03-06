@tool
extends RefCounted

static var _signal_bus: Object = null


static func _get_signal_bus() -> Object:
	if _signal_bus == null or not is_instance_valid(_signal_bus):
		_signal_bus = Object.new()
		_signal_bus.add_user_signal("user_stopped")
	return _signal_bus


static func notify_user_stopped() -> void:
	_get_signal_bus().emit_signal("user_stopped")


static func connect_cleanup(callback: Callable) -> void:
	_get_signal_bus().connect("user_stopped", callback)
