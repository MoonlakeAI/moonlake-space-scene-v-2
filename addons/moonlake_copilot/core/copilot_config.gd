@tool
extends Node

## CopilotConfig
##
## Centralized configuration for Moonlake Copilot plugin.
## Created as a child node of the plugin and passed to components that need it.

# Tool streaming settings
var enable_tool_streaming: bool = true
var tool_streaming_exclude: Array = []  # Exclude list - empty by default to show all tools

# Version control settings
var enable_snapshot_reverts: bool = false  # snapshot/revert feature

# YOLO mode - auto-confirm all Bash tools for this session (not persisted)
var yolo_mode_enabled: bool = false

# Signals for YOLO mode state changes
signal yolo_mode_activated
signal yolo_mode_deactivated

func _ready() -> void:
	_load_settings()

func enable_yolo_mode() -> void:
	if not yolo_mode_enabled:
		yolo_mode_enabled = true
		yolo_mode_activated.emit()

func disable_yolo_mode() -> void:
	if yolo_mode_enabled:
		yolo_mode_enabled = false
		yolo_mode_deactivated.emit()
		Log.info("[CopilotConfig] YOLO mode disabled")

func _load_settings() -> void:
	"""Load settings from ProjectSettings with defaults"""
	tool_streaming_exclude = ProjectSettings.get_setting(
		"moonlake_copilot/tool_streaming_exclude",
		[]
	)
