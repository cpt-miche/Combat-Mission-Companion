class_name ScenarioEditorChrome
extends PanelContainer

signal back_requested
signal before_draft_save

@onready var step_label: Label = %StepLabel
@onready var status_label: Label = %StatusLabel
@onready var back_button: Button = %BackButton
@onready var save_draft_button: Button = %SaveDraftButton
@onready var exit_button: Button = %ExitButton
@onready var exit_dialog: ConfirmationDialog = %ExitDialog

func _ready() -> void:
	back_button.pressed.connect(func() -> void: back_requested.emit())
	save_draft_button.pressed.connect(_on_save_draft_pressed)
	exit_button.pressed.connect(func() -> void: exit_dialog.popup_centered())
	exit_dialog.confirmed.connect(_on_save_and_exit_confirmed)
	exit_dialog.custom_action.connect(_on_exit_custom_action)
	exit_dialog.add_button("Exit Without Saving", false, "discard")

func configure(can_go_back: bool = true) -> void:
	visible = ScenarioEditorState.active
	if not visible:
		return
	step_label.text = ScenarioEditorState.step_label()
	back_button.disabled = not can_go_back
	status_label.text = ""

func _on_save_draft_pressed() -> void:
	before_draft_save.emit()
	status_label.text = "Draft saved." if ScenarioEditorState.save_draft() else "Draft could not be saved."

func _on_save_and_exit_confirmed() -> void:
	before_draft_save.emit()
	if not ScenarioEditorState.save_draft():
		status_label.text = "Draft could not be saved."
		return
	_return_to_library()

func _on_exit_custom_action(action: StringName) -> void:
	if action != &"discard":
		return
	exit_dialog.hide()
	_return_to_library()

func _return_to_library() -> void:
	ScenarioEditorState.clear()
	GameState.set_phase(GameState.Phase.SCENARIO_EDITOR)
