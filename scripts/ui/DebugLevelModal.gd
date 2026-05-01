extends Control
class_name DebugLevelModal

signal level_selected(level: int)
signal canceled

@onready var level_1_button: Button = %Level1Button
@onready var level_2_button: Button = %Level2Button
@onready var level_3_button: Button = %Level3Button
@onready var cancel_button: Button = %CancelButton

func _ready() -> void:
	level_1_button.pressed.connect(func() -> void: _emit_level(1))
	level_2_button.pressed.connect(func() -> void: _emit_level(2))
	level_3_button.pressed.connect(func() -> void: _emit_level(3))
	cancel_button.pressed.connect(_on_cancel_pressed)

func open_modal() -> void:
	visible = true

func close_modal() -> void:
	visible = false

func _emit_level(level: int) -> void:
	level_selected.emit(level)
	close_modal()

func _on_cancel_pressed() -> void:
	canceled.emit()
	close_modal()
