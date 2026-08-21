extends Control

@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var library_panel: VBoxContainer = %LibraryPanel
@onready var editor_panel: VBoxContainer = %EditorPanel
@onready var scenario_list: ItemList = %ScenarioList
@onready var scenario_description_label: Label = %ScenarioDescriptionLabel
@onready var edit_button: Button = %EditButton
@onready var delete_button: Button = %DeleteButton
@onready var play_button: Button = %PlayButton
@onready var export_button: Button = %ExportButton
@onready var draft_selector: OptionButton = %DraftSelector
@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var briefing_input: TextEdit = %BriefingInput
@onready var player_1_name_input: LineEdit = %Player1NameInput
@onready var player_2_name_input: LineEdit = %Player2NameInput
@onready var editor_step_label: Label = %EditorStepLabel
@onready var review_summary_label: Label = %ReviewSummaryLabel
@onready var save_scenario_button: Button = %SaveScenarioButton
@onready var new_scenario_dialog: ConfirmationDialog = %NewScenarioDialog
@onready var new_name_input: LineEdit = %NewNameInput
@onready var new_briefing_input: TextEdit = %NewBriefingInput
@onready var new_size_selector: OptionButton = %NewSizeSelector
@onready var new_p1_name_input: LineEdit = %NewP1NameInput
@onready var new_p2_name_input: LineEdit = %NewP2NameInput
@onready var new_p1_nation_selector: OptionButton = %NewP1NationSelector
@onready var new_p2_nation_selector: OptionButton = %NewP2NationSelector
@onready var play_dialog: Window = %PlayDialog
@onready var play_status_label: Label = %PlayStatusLabel
@onready var play_side_1_button: Button = %PlaySide1Button
@onready var play_side_2_button: Button = %PlaySide2Button
@onready var delete_dialog: ConfirmationDialog = %DeleteDialog
@onready var editor_exit_dialog: ConfirmationDialog = %EditorExitDialog
@onready var import_conflict_dialog: ConfirmationDialog = %ImportConflictDialog
@onready var import_dialog: FileDialog = %ImportDialog
@onready var export_dialog: FileDialog = %ExportDialog

var _records: Array[Dictionary] = []
var _pending_play_ref: Dictionary = {}
var _pending_play_payload: Dictionary = {}
var _pending_delete_ref: Dictionary = {}
var _pending_export_ref: Dictionary = {}
var _pending_import_path := ""

func _ready() -> void:
	_configure_new_dialog_options()
	%NewButton.pressed.connect(func() -> void: new_scenario_dialog.popup_centered())
	new_scenario_dialog.confirmed.connect(_on_new_scenario_confirmed)
	edit_button.pressed.connect(_on_edit_pressed)
	%DuplicateButton.pressed.connect(_on_duplicate_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	play_button.pressed.connect(_on_play_pressed)
	play_side_1_button.pressed.connect(_on_play_side_1_pressed)
	play_side_2_button.pressed.connect(_on_play_side_2_pressed)
	%ImportButton.pressed.connect(func() -> void: import_dialog.popup_centered_ratio(0.75))
	import_dialog.file_selected.connect(_on_import_file_selected)
	import_conflict_dialog.confirmed.connect(_on_import_replace_confirmed)
	import_conflict_dialog.custom_action.connect(_on_import_conflict_action)
	import_conflict_dialog.add_button("Save Copy", false, "save_copy")
	export_button.pressed.connect(_on_export_pressed)
	export_dialog.file_selected.connect(_on_export_file_selected)
	%MainMenuButton.pressed.connect(func() -> void: GameState.set_phase(GameState.Phase.MAIN_MENU))
	scenario_list.item_selected.connect(_on_library_selection_changed)
	%ResumeDraftButton.pressed.connect(_on_resume_draft_pressed)
	%DeleteDraftButton.pressed.connect(_on_delete_draft_pressed)
	%ContinueButton.pressed.connect(_on_apply_details_and_continue)
	%SaveDraftButton.pressed.connect(_on_save_draft_pressed)
	save_scenario_button.pressed.connect(_on_save_completed_scenario)
	%ExitLibraryButton.pressed.connect(func() -> void: editor_exit_dialog.popup_centered())
	editor_exit_dialog.confirmed.connect(_on_save_draft_and_exit)
	editor_exit_dialog.custom_action.connect(_on_editor_exit_custom_action)
	editor_exit_dialog.add_button("Exit Without Saving", false, "discard")
	%MapStepButton.pressed.connect(_go_to_map)
	%P1ForcesButton.pressed.connect(_go_to_forces.bind(0))
	%P2ForcesButton.pressed.connect(_go_to_forces.bind(1))
	%P1DeploymentButton.pressed.connect(_go_to_deployment.bind(0))
	%P2DeploymentButton.pressed.connect(_go_to_deployment.bind(1))
	_refresh_mode()

func _refresh_mode() -> void:
	library_panel.visible = not ScenarioEditorState.active
	editor_panel.visible = ScenarioEditorState.active
	if ScenarioEditorState.active:
		_show_editor_document()
	else:
		_refresh_library()

func _refresh_library() -> void:
	title_label.text = "Scenario Library"
	_records.clear()
	for completed_record in SaveManager.list_scenario_records():
		var record := completed_record.duplicate(true)
		record["kind"] = "completed"
		_records.append(record)
	for draft_id in SaveManager.list_scenario_drafts():
		var draft := SaveManager.load_scenario_draft(draft_id)
		var scenario := draft.get("scenario", {}) as Dictionary
		if scenario.is_empty():
			continue
		_records.append({
			"id": draft_id,
			"kind": "draft",
			"name": String(scenario.get("name", draft_id)),
			"briefing": String(scenario.get("briefing", "")),
			"validation_errors": SaveManager.scenario_validation_errors(scenario)
		})
	_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_comparison := String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", "")))
		if name_comparison != 0:
			return name_comparison < 0
		return String(a.get("kind", "")) < String(b.get("kind", ""))
	)
	scenario_list.clear()
	for record in _records:
		var kind := String(record.get("kind", "completed"))
		var label := "[COMPLETED] %s" % String(record.get("name", record.get("id", "Scenario")))
		if kind == "draft":
			var error_count := (record.get("validation_errors", PackedStringArray()) as PackedStringArray).size()
			var state := "Ready to complete" if error_count == 0 else "%d issue%s" % [error_count, "" if error_count == 1 else "s"]
			label = "[DRAFT] %s — %s" % [String(record.get("name", record.get("id", "Scenario"))), state]
		scenario_list.add_item(label)
		scenario_list.set_item_metadata(scenario_list.item_count - 1, {"id": record.get("id", ""), "kind": kind})
	if scenario_list.item_count > 0:
		scenario_list.select(0)
		_on_library_selection_changed(0)
	else:
		scenario_description_label.text = "No scenarios or drafts. Create one or import a scenario JSON file."
	_update_library_buttons()
	draft_selector.clear()
	draft_selector.visible = false

func _refresh_library_selecting(scenario_ref: Dictionary) -> void:
	_refresh_mode()
	for item_index in range(scenario_list.item_count):
		var metadata: Variant = scenario_list.get_item_metadata(item_index)
		if not (metadata is Dictionary):
			continue
		var candidate := metadata as Dictionary
		if String(candidate.get("id", "")) == String(scenario_ref.get("id", "")) and String(candidate.get("kind", "")) == String(scenario_ref.get("kind", "")):
			scenario_list.select(item_index)
			_on_library_selection_changed(item_index)
			return

func _on_library_selection_changed(_index: int) -> void:
	var scenario_ref := _selected_scenario_ref()
	var payload := _load_library_payload(scenario_ref)
	if payload.is_empty():
		scenario_description_label.text = "Scenario could not be loaded."
	else:
		var players := payload.get("players", []) as Array
		var side_text := ""
		if players.size() >= 2:
			side_text = "%s vs %s" % [String((players[0] as Dictionary).get("name", "Player 1")), String((players[1] as Dictionary).get("name", "Player 2"))]
		var lines: Array[String] = ["%s — %s" % [String(scenario_ref.get("kind", "completed")).capitalize(), side_text], String(payload.get("briefing", "No briefing."))]
		if String(scenario_ref.get("kind", "")) == "draft":
			var validation_errors := SaveManager.scenario_validation_errors(payload)
			if validation_errors.is_empty():
				lines.append("Ready to complete. Resume this draft and use Save Completed Scenario on Review.")
			else:
				lines.append("Cannot be completed yet:")
				for validation_error in validation_errors:
					lines.append("• %s" % validation_error)
		scenario_description_label.text = "\n".join(lines)
	_update_library_buttons()

func _update_library_buttons() -> void:
	var scenario_ref := _selected_scenario_ref()
	var has_selection := not scenario_ref.is_empty()
	var is_draft := has_selection and String(scenario_ref.get("kind", "")) == "draft"
	var is_completed := has_selection and not is_draft
	edit_button.disabled = not is_completed
	delete_button.disabled = not is_completed
	play_button.disabled = not is_completed
	export_button.disabled = not is_completed
	%DuplicateButton.disabled = not is_completed
	%ResumeDraftButton.disabled = not is_draft
	%DeleteDraftButton.disabled = not is_draft
	%ResumeDraftButton.get_parent().visible = is_draft

func _load_library_payload(scenario_ref: Dictionary) -> Dictionary:
	var scenario_id := String(scenario_ref.get("id", ""))
	if scenario_id.is_empty():
		return {}
	if String(scenario_ref.get("kind", "completed")) == "draft":
		return (SaveManager.load_scenario_draft(scenario_id).get("scenario", {}) as Dictionary).duplicate(true)
	return SaveManager.load_scenario_ref(scenario_ref)

func _selected_scenario_ref() -> Dictionary:
	var selected := scenario_list.get_selected_items()
	if selected.is_empty():
		return {}
	var metadata: Variant = scenario_list.get_item_metadata(selected[0])
	return (metadata as Dictionary).duplicate(true) if metadata is Dictionary else {}

func _on_new_scenario_confirmed() -> void:
	var name := new_name_input.text.strip_edges()
	if name.is_empty():
		status_label.text = "Enter a scenario name."
		return
	if SaveManager.scenario_exists(name):
		status_label.text = "A scenario with that name already exists. Edit or duplicate it from the library."
		return
	if SaveManager.scenario_draft_exists(name):
		status_label.text = "A draft with that name already exists. Resume it from the library."
		return
	var size := int(new_size_selector.get_item_metadata(maxi(new_size_selector.selected, 0)))
	ScenarioEditorState.start_new({
		"name": name,
		"briefing": new_briefing_input.text,
		"columns": size,
		"rows": size,
		"player_1_name": new_p1_name_input.text,
		"player_2_name": new_p2_name_input.text,
		"player_1_nation": _selected_nation(new_p1_nation_selector),
		"player_2_nation": _selected_nation(new_p2_nation_selector)
	})
	GameState.set_phase(GameState.Phase.MAP_SETUP)

func _on_edit_pressed() -> void:
	var scenario_ref := _selected_scenario_ref()
	var payload := SaveManager.load_scenario_ref(scenario_ref)
	if payload.is_empty():
		return
	ScenarioEditorState.begin_edit(payload, scenario_ref)
	_refresh_mode()

func _on_duplicate_pressed() -> void:
	var payload := SaveManager.load_scenario_ref(_selected_scenario_ref())
	if payload.is_empty():
		return
	var copy_name := "%s Copy" % String(payload.get("name", "Scenario"))
	var suffix := 2
	while SaveManager.scenario_exists(copy_name) or SaveManager.scenario_draft_exists(copy_name):
		copy_name = "%s Copy %d" % [String(payload.get("name", "Scenario")), suffix]
		suffix += 1
	payload["name"] = copy_name
	if not SaveManager.save_scenario(copy_name, payload):
		status_label.text = "Scenario could not be duplicated."
		return
	ScenarioEditorState.begin_edit(payload, {"id": SaveManager.sanitize_name(copy_name)})
	_refresh_mode()

func _on_delete_pressed() -> void:
	_pending_delete_ref = _selected_scenario_ref()
	delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if String(_pending_delete_ref.get("kind", "completed")) == "completed" and SaveManager.delete_scenario(String(_pending_delete_ref.get("id", ""))):
		status_label.text = "Scenario deleted."
	_pending_delete_ref.clear()
	_refresh_library()

func _on_play_pressed() -> void:
	_pending_play_ref = _selected_scenario_ref()
	_pending_play_payload.clear()
	_clear_play_launch_error()
	var payload := SaveManager.load_scenario_ref(_pending_play_ref)
	if payload.is_empty():
		status_label.text = SaveManager.get_last_load_error() if not SaveManager.get_last_load_error().is_empty() else "The selected scenario could not be loaded."
		return
	if not SaveManager.validate_scenario_payload(payload):
		status_label.text = "The selected scenario is incomplete or contains an illegal deployment."
		return
	var players := payload.get("players", []) as Array
	if players.size() < 2:
		status_label.text = "The selected scenario must contain two player forces."
		return
	_pending_play_payload = payload.duplicate(true)
	play_side_1_button.text = "Play as %s" % String((players[0] as Dictionary).get("name", "Player 1"))
	play_side_2_button.text = "Play as %s" % String((players[1] as Dictionary).get("name", "Player 2"))
	play_dialog.popup_centered()

func _on_play_side_1_pressed() -> void:
	_launch_selected_scenario(0)

func _on_play_side_2_pressed() -> void:
	_launch_selected_scenario(1)

func _launch_selected_scenario(human_side: int) -> bool:
	if human_side < 0 or human_side > 1:
		_show_play_launch_error("Choose Player 1 or Player 2 before launching the scenario.")
		return false
	var payload := _pending_play_payload.duplicate(true)
	if payload.is_empty():
		_show_play_launch_error("The selected scenario is no longer available. Close this dialog and select it again.")
		return false
	if not SaveManager.validate_scenario_payload(payload) or not GameState.validate_map_payload(payload):
		_show_play_launch_error("The selected scenario is incomplete or contains an illegal map or deployment.")
		return false
	var players := payload.get("players", []) as Array
	if players.size() != 2 or not (players[0] is Dictionary) or not (players[1] is Dictionary):
		_show_play_launch_error("The selected scenario must contain exactly two valid player forces.")
		return false

	var runtime_players: Array[Dictionary] = []
	for index in range(2):
		var player := (players[index] as Dictionary).duplicate(true)
		player["controller"] = "human" if index == human_side else "ai"
		runtime_players.append(player)

	GameState.reset(false)
	if not GameState.apply_map_payload(payload):
		_show_play_launch_error("The scenario map could not be initialized.")
		return false
	GameState.players = runtime_players
	GameState.selected_nation_id = String(runtime_players[human_side].get("nation_id", "usa"))
	GameState.selected_scenario_name = String(payload.get("name", ""))
	GameState.map_flow = GameState.MapFlow.STARTING_SCENARIO
	GameState.active_player = 0
	GameState.current_turn = 1
	ScenarioEditorState.clear()
	_pending_play_payload.clear()
	play_dialog.hide()
	GameState.set_phase(GameState.Phase.GAMEPLAY)
	return true

func _clear_play_launch_error() -> void:
	play_status_label.text = ""
	play_status_label.visible = false

func _show_play_launch_error(message: String) -> void:
	play_status_label.text = message
	play_status_label.visible = true
	status_label.text = message

func _on_import_file_selected(path: String) -> void:
	var payload := SaveManager.load_external_scenario(path)
	if payload.is_empty():
		status_label.text = SaveManager.get_last_load_error()
		return
	var imported_id := SaveManager.sanitize_name(String(payload.get("name", "")))
	if SaveManager.scenario_exists(imported_id):
		_pending_import_path = path
		import_conflict_dialog.popup_centered()
		return
	_finish_import(path, false)

func _on_import_replace_confirmed() -> void:
	_finish_import(_pending_import_path, true)

func _on_import_conflict_action(action: StringName) -> void:
	if action != &"save_copy":
		return
	import_conflict_dialog.hide()
	_finish_import(_pending_import_path, false)

func _finish_import(path: String, replace_existing: bool) -> void:
	var imported := SaveManager.import_scenario(path, replace_existing)
	status_label.text = "Scenario imported." if not imported.is_empty() else SaveManager.get_last_load_error()
	_pending_import_path = ""
	_refresh_library()

func _on_export_pressed() -> void:
	_pending_export_ref = _selected_scenario_ref()
	if _pending_export_ref.is_empty():
		return
	export_dialog.current_file = "%s.json" % String(_pending_export_ref.get("id", "scenario"))
	export_dialog.popup_centered_ratio(0.75)

func _on_export_file_selected(path: String) -> void:
	status_label.text = "Scenario exported." if SaveManager.export_scenario(_pending_export_ref, path) else "Scenario export failed."

func _on_resume_draft_pressed() -> void:
	var scenario_ref := _selected_scenario_ref()
	if String(scenario_ref.get("kind", "")) != "draft":
		return
	var draft_id := String(scenario_ref.get("id", ""))
	if not ScenarioEditorState.resume_draft(SaveManager.load_scenario_draft(draft_id), draft_id):
		status_label.text = "Draft could not be resumed."
		return
	_navigate_to_current_step()

func _on_delete_draft_pressed() -> void:
	var scenario_ref := _selected_scenario_ref()
	if String(scenario_ref.get("kind", "")) != "draft":
		return
	var draft_id := String(scenario_ref.get("id", ""))
	if SaveManager.delete_scenario_draft(draft_id):
		status_label.text = "Draft discarded."
	_refresh_library()

func _show_editor_document() -> void:
	title_label.text = "Scenario Editor"
	editor_step_label.text = ScenarioEditorState.step_label()
	var document := ScenarioEditorState.document
	scenario_name_input.text = String(document.get("name", ""))
	briefing_input.text = String(document.get("briefing", ""))
	var players := document.get("players", []) as Array
	player_1_name_input.text = String((players[0] as Dictionary).get("name", "Player 1")) if players.size() > 0 else "Player 1"
	player_2_name_input.text = String((players[1] as Dictionary).get("name", "Player 2")) if players.size() > 1 else "Player 2"
	var validation_errors := SaveManager.scenario_validation_errors(document)
	var summary := _scenario_summary(document)
	if ScenarioEditorState.current_step == ScenarioEditorState.Step.REVIEW:
		if validation_errors.is_empty():
			summary += "\n\nReady to save as a completed scenario."
		else:
			summary += "\n\nCannot save as completed until these issues are fixed:"
			for validation_error in validation_errors:
				summary += "\n• %s" % validation_error
	review_summary_label.text = summary
	save_scenario_button.visible = ScenarioEditorState.current_step == ScenarioEditorState.Step.REVIEW
	save_scenario_button.disabled = not validation_errors.is_empty()

func _apply_editor_details() -> bool:
	if scenario_name_input.text.strip_edges().is_empty():
		status_label.text = "Scenario name is required."
		return false
	ScenarioEditorState.update_details({
		"name": scenario_name_input.text,
		"briefing": briefing_input.text,
		"player_1_name": player_1_name_input.text,
		"player_2_name": player_2_name_input.text
	})
	return true

func _on_apply_details_and_continue() -> void:
	if not _apply_editor_details():
		return
	_go_to_map()

func _go_to_map() -> void:
	_apply_editor_details()
	ScenarioEditorState.capture_from_game_state()
	ScenarioEditorState.set_step(ScenarioEditorState.Step.MAP)
	GameState.set_phase(GameState.Phase.MAP_SETUP)

func _go_to_forces(side: int) -> void:
	_apply_editor_details()
	ScenarioEditorState.capture_from_game_state()
	ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_FORCES if side == 0 else ScenarioEditorState.Step.PLAYER_2_FORCES, side)
	GameState.set_phase(GameState.Phase.DIVISION_BUILDER)

func _go_to_deployment(side: int) -> void:
	_apply_editor_details()
	ScenarioEditorState.capture_from_game_state()
	ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_DEPLOYMENT if side == 0 else ScenarioEditorState.Step.PLAYER_2_DEPLOYMENT, side)
	GameState.set_phase(GameState.Phase.DEPLOYMENT_P1 if side == 0 else GameState.Phase.DEPLOYMENT_P2)

func _on_save_draft_pressed() -> void:
	if not _apply_editor_details():
		return
	status_label.text = "Draft saved. It will remain marked Draft in the Scenario Library until it passes Review and is saved as completed." if ScenarioEditorState.save_draft() else "Draft could not be saved: %s" % SaveManager.get_last_save_error()

func _on_save_completed_scenario() -> void:
	if not _apply_editor_details():
		return
	ScenarioEditorState.capture_from_game_state()
	var payload := ScenarioEditorState.document
	var validation_errors := SaveManager.scenario_validation_errors(payload)
	if not validation_errors.is_empty():
		status_label.text = "Scenario could not be completed:\n• %s" % "\n• ".join(validation_errors)
		save_scenario_button.disabled = true
		return
	var name := String(payload.get("name", ""))
	var next_id := SaveManager.sanitize_name(name)
	var previous_id := String(ScenarioEditorState.scenario_ref.get("id", ""))
	if SaveManager.scenario_exists(next_id) and next_id != previous_id:
		status_label.text = "A different scenario already uses that name. Choose another name."
		return
	var current_draft_id := ScenarioEditorState.draft_id()
	if SaveManager.scenario_draft_exists(next_id) and next_id != current_draft_id:
		status_label.text = "A different draft already uses that name. Choose another name or resume that draft."
		return
	if not SaveManager.save_scenario(name, payload):
		status_label.text = "Completed scenario could not be saved: %s" % SaveManager.get_last_save_error()
		return
	var verified_payload := SaveManager.load_scenario(next_id)
	if verified_payload.is_empty() or not SaveManager.validate_scenario_payload(verified_payload):
		status_label.text = "Scenario write could not be verified. The draft was retained."
		return
	var previous_draft_id := ScenarioEditorState.draft_id()
	SaveManager.delete_scenario_draft(previous_draft_id)
	if previous_draft_id != next_id:
		SaveManager.delete_scenario_draft(next_id)
	if not previous_id.is_empty() and previous_id != next_id:
		SaveManager.delete_scenario(previous_id)
	ScenarioEditorState.scenario_ref = {"id": next_id}
	ScenarioEditorState.dirty = false
	ScenarioEditorState.clear()
	_refresh_library_selecting({"id": next_id, "kind": "completed"})
	status_label.text = "Completed scenario saved to %s." % ProjectSettings.globalize_path("%s/%s.json" % [SaveManager.SCENARIOS_DIR, next_id])

func _return_to_library() -> void:
	ScenarioEditorState.clear()
	_refresh_mode()

func _on_save_draft_and_exit() -> void:
	if not _apply_editor_details() or not ScenarioEditorState.save_draft():
		status_label.text = "Draft could not be saved."
		return
	_return_to_library()

func _on_editor_exit_custom_action(action: StringName) -> void:
	if action != &"discard":
		return
	editor_exit_dialog.hide()
	_return_to_library()

func _navigate_to_current_step() -> void:
	match ScenarioEditorState.current_step:
		ScenarioEditorState.Step.MAP: GameState.set_phase(GameState.Phase.MAP_SETUP)
		ScenarioEditorState.Step.PLAYER_1_FORCES, ScenarioEditorState.Step.PLAYER_2_FORCES: GameState.set_phase(GameState.Phase.DIVISION_BUILDER)
		ScenarioEditorState.Step.PLAYER_1_DEPLOYMENT: GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)
		ScenarioEditorState.Step.PLAYER_2_DEPLOYMENT: GameState.set_phase(GameState.Phase.DEPLOYMENT_P2)
		ScenarioEditorState.Step.REVIEW: GameState.set_phase(GameState.Phase.SCENARIO_REVIEW)
		_: _refresh_mode()

func _scenario_summary(payload: Dictionary) -> String:
	var grid := payload.get("grid", {}) as Dictionary
	var players := payload.get("players", []) as Array
	var territory := payload.get("territory", {}) as Dictionary
	var lines: Array[String] = [
		"Map: %dx%d | Objectives: %d | P1 territory: %d hexes | P2 territory: %d hexes" % [
			int(grid.get("columns", 0)),
			int(grid.get("rows", 0)),
			(payload.get("objectives", {}) as Dictionary).size(),
			_count_territory_hexes(territory, GameState.TerritoryOwnership.PLAYER_1),
			_count_territory_hexes(territory, GameState.TerritoryOwnership.PLAYER_2)
		]
	]
	for index in range(mini(players.size(), 2)):
		var player := players[index] as Dictionary
		var deployments := player.get("deployments", {}) as Dictionary
		lines.append("%s (%s): %d force nodes | %d deployed markers | Deployment complete: %s" % [
			String(player.get("name", "Player %d" % (index + 1))),
			String(player.get("nation_id", "unknown")).to_upper(),
			_count_force_nodes(player.get("division_tree", {}) as Dictionary),
			_count_deployment_markers(deployments),
			"Yes" if SaveManager.validate_scenario_player_deployment(payload, index) else "No"
		])
	lines.append("Ready to save." if SaveManager.validate_scenario_payload(payload) else "Incomplete: finish both forces and legal deployments before saving.")
	return "\n".join(lines)

func _count_territory_hexes(territory: Dictionary, owner: int) -> int:
	var count := 0
	for value in territory.values():
		if int(value) == owner:
			count += 1
	return count

func _count_force_nodes(node: Dictionary) -> int:
	if node.is_empty():
		return 0
	var count := 1
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			count += _count_force_nodes(child_variant as Dictionary)
	return count

func _count_deployment_markers(deployments: Dictionary) -> int:
	var count := 0
	for value in deployments.values():
		count += (value as Array).size() if value is Array else (1 if value is Dictionary else 0)
	return count

func _configure_new_dialog_options() -> void:
	new_size_selector.clear()
	for size in MapGridConfig.allowed_sizes():
		new_size_selector.add_item("%dx%d" % [size, size])
		new_size_selector.set_item_metadata(new_size_selector.item_count - 1, size)
	for selector in [new_p1_nation_selector, new_p2_nation_selector]:
		selector.clear()
		var nation_ids: Array = UnitCatalog.nations.keys()
		nation_ids.sort()
		for nation_id in nation_ids:
			selector.add_item(String((UnitCatalog.nations[nation_id] as Dictionary).get("name", nation_id)))
			selector.set_item_metadata(selector.item_count - 1, nation_id)
	_select_nation(new_p1_nation_selector, "usa")
	_select_nation(new_p2_nation_selector, "germany")

func _selected_nation(selector: OptionButton) -> String:
	return String(selector.get_item_metadata(maxi(selector.selected, 0)))

func _select_nation(selector: OptionButton, nation_id: String) -> void:
	for index in range(selector.item_count):
		if String(selector.get_item_metadata(index)) == nation_id:
			selector.select(index)
			return
