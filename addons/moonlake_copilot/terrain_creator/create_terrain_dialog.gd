extends VBoxContainer

signal terrain_created(terrain_size: int, height_scale: float)
signal dialog_cancelled

var plugin_ref = null

@onready var size_option: OptionButton = $MarginContainer/VBoxContainer/SettingsGrid/SizeOption
@onready var height_scale_spinbox: SpinBox = $MarginContainer/VBoxContainer/SettingsGrid/HeightScaleSpinBox


func _ready() -> void:
	pass


func _on_create_pressed() -> void:
	var terrain_size_index = size_option.selected
	var terrain_size = 0

	match terrain_size_index:
		0: terrain_size = 512
		1: terrain_size = 1024
		2: terrain_size = 2048

	var height_scale = height_scale_spinbox.value

	terrain_created.emit(terrain_size, height_scale)


func _on_cancel_pressed() -> void:
	dialog_cancelled.emit()
