extends Node

const SCENARIO_SCREEN := preload("res://scenes/scenario_editor/ScenarioEditorScreen.tscn")
const MAP_SCREEN := preload("res://scenes/map_setup/MapSetupScreen.tscn")
const DEPLOYMENT_SCREEN := preload("res://scenes/deployment/DeploymentScreen.tscn")
const GAMEPLAY_SCREEN := preload("res://scenes/screens/GameplayScreen.tscn")

const SCENARIO_NAME := "CI Scenario Editor Roundtrip"
const SCENARIO_ID := "CI_Scenario_Editor_Roundtrip"
const EXPORT_PATH := "/tmp/cmc_scenario_editor_roundtrip.json"
const STARTER_SCENARIO_ID := "Ardennes_Crossroads"

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_cleanup_storage()
	_test_version_three_storage_preserves_both_sides()
	_test_completed_scenario_validation_rejects_illegal_authoring()
	_test_validation_reports_each_illegal_stack()
	_test_draft_round_trip()
	_test_unified_library_restores_draft_with_validation_state()
	_test_completed_save_returns_to_library_and_survives_reload()
	_test_guided_map_step_and_manual_deployments()
	_test_launch_as_either_side_keeps_positions()
	_test_export_import_round_trip()
	_test_starter_scenario_data_and_export()
	_test_starter_scenario_launches_as_either_side()
	_cleanup_storage()
	ScenarioEditorState.clear()
	if _failures.is_empty():
		print("ScenarioEditor integration tests passed.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_version_three_storage_preserves_both_sides() -> void:
	var payload := _complete_payload()
	_assert_true(SaveManager.validate_scenario_payload(payload), "A complete two-sided version-3 scenario should validate")
	_assert_true(SaveManager.save_scenario(SCENARIO_NAME, payload), "A complete scenario should save")
	var loaded := SaveManager.load_scenario(SCENARIO_ID)
	var players := loaded.get("players", []) as Array
	_assert_equal(2, players.size(), "Saved scenario should retain both player records")
	if players.size() == 2:
		_assert_true(not ((players[0] as Dictionary).get("deployments", {}) as Dictionary).is_empty(), "Player 1 authored positions should persist")
		_assert_true(not ((players[1] as Dictionary).get("deployments", {}) as Dictionary).is_empty(), "Player 2 authored positions should persist")
	payload["briefing"] = "Updated directly in the project scenario catalog."
	_assert_true(SaveManager.save_scenario(SCENARIO_NAME, payload), "Editing a scenario should update its project JSON")
	_assert_equal("Updated directly in the project scenario catalog.", String(SaveManager.load_scenario(SCENARIO_ID).get("briefing", "")), "Resaving should update the same scenario file")
	var matching_records := 0
	for record in SaveManager.list_scenario_records():
		if String(record.get("id", "")) == SCENARIO_ID:
			matching_records += 1
			_assert_true(not record.has("source"), "Scenario records should not distinguish built-in and local sources")
	_assert_equal(1, matching_records, "The project catalog should list each scenario exactly once")
	_assert_true(FileAccess.file_exists("res://data/scenarios/%s.json" % SCENARIO_ID), "Completed scenarios should be written directly to data/scenarios")

func _test_completed_scenario_validation_rejects_illegal_authoring() -> void:
	var incomplete := _complete_payload()
	((incomplete.get("players", []) as Array)[1] as Dictionary)["deployments"] = {}
	_assert_true(not SaveManager.validate_scenario_payload(incomplete), "Completed scenarios should reject an undeployed side")

	var wrong_territory := _complete_payload()
	var wrong_players := wrong_territory.get("players", []) as Array
	(wrong_players[1] as Dictionary)["deployments"] = {"0,0": _snapshot((((wrong_players[1] as Dictionary).get("division_tree", {}) as Dictionary).get("children", []) as Array)[0])}
	_assert_true(not SaveManager.validate_scenario_payload(wrong_territory), "Completed scenarios should reject units outside their side's territory")

	var duplicate_ids := _complete_payload()
	var duplicate_players := duplicate_ids.get("players", []) as Array
	var p2_root := (duplicate_players[1] as Dictionary).get("division_tree", {}) as Dictionary
	var p2_children := p2_root.get("children", []) as Array
	(p2_children[0] as Dictionary)["id"] = "p1_platoon"
	p2_root["children"] = p2_children
	(duplicate_players[1] as Dictionary)["division_tree"] = p2_root
	_assert_true(not SaveManager.validate_scenario_payload(duplicate_ids), "Completed scenarios should reject duplicate unit IDs across sides")

func _test_validation_reports_each_illegal_stack() -> void:
	var payload := _overstacked_payload()
	var errors := SaveManager.scenario_validation_errors(payload)
	_assert_true(_packed_lines_contain(errors, "Player 1 hex 0,0"), "Validation should identify the player and coordinate of an illegal stack")
	_assert_true(_packed_lines_contain(errors, "Stack exceeds 4 company-equivalents"), "Validation should expose the actionable stacking rule")
	_assert_true(not SaveManager.save_scenario(SCENARIO_NAME, payload), "A scenario with an illegal stack should not be saved as completed")
	_assert_true(SaveManager.get_last_save_error().contains("Player 1 hex 0,0"), "A rejected completed save should retain its actionable validation error")

func _test_draft_round_trip() -> void:
	ScenarioEditorState.begin_edit(_complete_payload(), {"id": SCENARIO_ID})
	ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_2_DEPLOYMENT, 1)
	_assert_true(ScenarioEditorState.save_draft(), "Explicit Save Draft should persist the working scenario")
	var draft := SaveManager.load_scenario_draft(SCENARIO_ID)
	_assert_equal(ScenarioEditorState.Step.PLAYER_2_DEPLOYMENT, int(draft.get("current_step", -1)), "Draft should preserve the current editor step")
	ScenarioEditorState.clear()
	_assert_true(ScenarioEditorState.resume_draft(draft, SCENARIO_ID), "A saved draft should resume")
	_assert_equal(1, ScenarioEditorState.editor_side, "Draft should preserve the side currently being edited")
	_assert_equal(SCENARIO_NAME, String(ScenarioEditorState.document.get("name", "")), "Draft should preserve scenario metadata")

func _test_unified_library_restores_draft_with_validation_state() -> void:
	ScenarioEditorState.begin_edit(_overstacked_payload(), {"id": SCENARIO_ID})
	ScenarioEditorState.set_step(ScenarioEditorState.Step.REVIEW, 1)
	_assert_true(ScenarioEditorState.save_draft(), "An incomplete scenario should remain saveable as a draft")
	ScenarioEditorState.clear()
	var screen := SCENARIO_SCREEN.instantiate()
	get_tree().root.add_child(screen)
	var draft_index := _library_item_index(screen, SCENARIO_ID, "draft")
	_assert_true(draft_index >= 0, "A saved draft should appear in the unified Scenario Library after reopening it")
	if draft_index >= 0:
		screen.scenario_list.select(draft_index)
		screen._on_library_selection_changed(draft_index)
		_assert_true(screen.scenario_list.get_item_text(draft_index).contains("[DRAFT]"), "Unified library entries should visibly distinguish drafts")
		_assert_true(screen.scenario_description_label.text.contains("Player 1 hex 0,0"), "Selecting an invalid draft should display its exact validation failure")
		_assert_true(not screen.get_node("%ResumeDraftButton").disabled, "A selected draft should enable Resume")
		_assert_true(screen.play_button.disabled, "Drafts should not be playable before completion")
	screen.queue_free()

func _test_completed_save_returns_to_library_and_survives_reload() -> void:
	SaveManager.delete_scenario(SCENARIO_ID)
	SaveManager.delete_scenario_draft(SCENARIO_ID)
	ScenarioEditorState.begin_edit(_complete_payload(), {"id": SCENARIO_ID})
	ScenarioEditorState.set_step(ScenarioEditorState.Step.REVIEW, 1)
	_assert_true(ScenarioEditorState.save_draft(), "The review-ready scenario should have a recoverable draft before completion")
	var screen := SCENARIO_SCREEN.instantiate()
	get_tree().root.add_child(screen)
	_assert_true(not screen.save_scenario_button.disabled, "A valid review-ready scenario should enable completed saving")
	screen.save_scenario_button.pressed.emit()
	_assert_true(not ScenarioEditorState.active, "A verified completed save should return to the Scenario Library")
	_assert_true(screen.library_panel.visible and not screen.editor_panel.visible, "A verified completed save should visibly return to the library instead of leaving the review panel open")
	_assert_true(SaveManager.scenario_exists(SCENARIO_ID), "Completed saving should create the project-catalog JSON")
	_assert_true(SaveManager.load_scenario(SCENARIO_ID).get("name", "") == SCENARIO_NAME, "The completed file should round-trip before the draft is removed")
	_assert_true(not SaveManager.list_scenario_drafts().has(SCENARIO_ID), "A verified completed save should remove its matching draft")
	_assert_true(_library_item_index(screen, SCENARIO_ID, "completed") >= 0, "The completed record should be selected from the refreshed unified library")
	screen.queue_free()
	var reloaded_screen := SCENARIO_SCREEN.instantiate()
	get_tree().root.add_child(reloaded_screen)
	_assert_true(_library_item_index(reloaded_screen, SCENARIO_ID, "completed") >= 0, "A completed scenario should remain listed after recreating the editor screen")
	reloaded_screen.queue_free()

func _test_guided_map_step_and_manual_deployments() -> void:
	ScenarioEditorState.start_new({
		"name": "Guided CI",
		"briefing": "Guided workflow",
		"columns": 16,
		"rows": 16,
		"player_1_name": "Allies",
		"player_2_name": "Axis",
		"player_1_nation": "usa",
		"player_2_nation": "germany"
	})
	GameState.territory_map = {"0,0": GameState.TerritoryOwnership.PLAYER_1, "1,0": GameState.TerritoryOwnership.PLAYER_2}
	GameState.set_phase(GameState.Phase.MAP_SETUP)
	var map_screen := MAP_SCREEN.instantiate()
	get_tree().root.add_child(map_screen)
	_assert_true(map_screen.scenario_editor_chrome.visible, "Scenario map step should show persistent editor navigation")
	map_screen._on_confirm_pressed()
	_assert_equal(GameState.Phase.DIVISION_BUILDER, GameState.current_phase, "Completing the scenario map should advance to force authoring")
	_assert_equal(ScenarioEditorState.Step.PLAYER_1_FORCES, ScenarioEditorState.current_step, "Map completion should target Player 1 forces")
	map_screen.queue_free()

	ScenarioEditorState.begin_edit(_complete_payload(), {"id": SCENARIO_ID})
	ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_DEPLOYMENT, 0)
	GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)
	var p1_screen := DEPLOYMENT_SCREEN.instantiate()
	get_tree().root.add_child(p1_screen)
	_assert_true(p1_screen.scenario_editor_chrome.visible, "Scenario deployment should show persistent editor navigation")
	p1_screen._on_finish_deployment_pressed()
	_assert_equal(GameState.Phase.DEPLOYMENT_P2, GameState.current_phase, "Player 1 scenario deployment should always advance to manual Player 2 deployment")
	_assert_equal("1,0", _deployment_hex_for(GameState.players[1].get("deployments", {}) as Dictionary, "p2_platoon"), "Player 1 completion must not replace the authored Player 2 deployment with AI placement")
	p1_screen.queue_free()

	var p2_screen := DEPLOYMENT_SCREEN.instantiate()
	get_tree().root.add_child(p2_screen)
	p2_screen._on_finish_deployment_pressed()
	_assert_equal(GameState.Phase.SCENARIO_REVIEW, GameState.current_phase, "Player 2 scenario deployment should advance to review instead of gameplay")
	_assert_equal(ScenarioEditorState.Step.REVIEW, ScenarioEditorState.current_step, "Both deployments should complete the guided workflow")
	p2_screen.queue_free()

func _test_launch_as_either_side_keeps_positions() -> void:
	if not SaveManager.scenario_exists(SCENARIO_ID):
		SaveManager.save_scenario(SCENARIO_NAME, _complete_payload())
	for human_side in [0, 1]:
		ScenarioEditorState.clear()
		GameState.reset(false)
		GameState.current_phase = GameState.Phase.SCENARIO_EDITOR
		var screen := SCENARIO_SCREEN.instantiate()
		get_tree().root.add_child(screen)
		_assert_true(_open_play_dialog_for_scenario(screen, SCENARIO_ID), "The completed scenario should be selectable from the library")
		_assert_true(not screen._pending_play_payload.is_empty(), "Opening Choose Side should cache one validated launch payload")
		if human_side == 0:
			screen.play_side_1_button.pressed.emit()
		else:
			screen.play_side_2_button.pressed.emit()
		_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Either side button should skip deployment and enter gameplay")
		_assert_equal("human", String(GameState.players[human_side].get("controller", "")), "The chosen side should be human controlled")
		_assert_equal("ai", String(GameState.players[1 - human_side].get("controller", "")), "The opposing side should be AI controlled")
		_assert_equal(0, GameState.active_player, "Player 1 should retain the first turn regardless of chosen side")
		_assert_equal("0,0", _deployment_hex_for(GameState.players[0].get("deployments", {}) as Dictionary, "p1_platoon"), "Player 1 authored position should remain locked")
		_assert_equal("1,0", _deployment_hex_for(GameState.players[1].get("deployments", {}) as Dictionary, "p2_platoon"), "Player 2 authored position should remain locked")
		_assert_true(not screen.play_dialog.visible, "A successful side selection should close the Choose Side dialog")
		screen.queue_free()

	ScenarioEditorState.clear()
	GameState.reset(false)
	GameState.current_phase = GameState.Phase.SCENARIO_EDITOR
	GameState.selected_scenario_name = "launch-state-sentinel"
	GameState.players = [{"sentinel": true}]
	var invalid_screen := SCENARIO_SCREEN.instantiate()
	get_tree().root.add_child(invalid_screen)
	invalid_screen._pending_play_payload = {}
	invalid_screen.play_side_1_button.pressed.emit()
	_assert_equal(GameState.Phase.SCENARIO_EDITOR, GameState.current_phase, "A missing launch payload should leave the editor phase unchanged")
	_assert_equal("launch-state-sentinel", GameState.selected_scenario_name, "A failed launch should not reset current game state")
	_assert_true(invalid_screen.play_status_label.visible and not invalid_screen.play_status_label.text.is_empty(), "A failed side selection should explain the problem inside the dialog")
	invalid_screen.queue_free()

func _test_export_import_round_trip() -> void:
	if not SaveManager.scenario_exists(SCENARIO_ID):
		SaveManager.save_scenario(SCENARIO_NAME, _complete_payload())
	_assert_true(SaveManager.export_scenario({"id": SCENARIO_ID}, EXPORT_PATH), "Completed scenario should export as JSON")
	SaveManager.delete_scenario(SCENARIO_ID)
	var imported := SaveManager.import_scenario(EXPORT_PATH)
	_assert_true(not imported.is_empty(), "Exported scenario should import on another installation")
	_assert_true(SaveManager.validate_scenario_payload(SaveManager.load_scenario_ref(imported)), "Imported JSON should pass the same completed-scenario validator")
	DirAccess.remove_absolute(EXPORT_PATH)

func _test_starter_scenario_data_and_export() -> void:
	var payload := SaveManager.load_scenario(STARTER_SCENARIO_ID)
	_assert_true(not payload.is_empty(), "The checked-in starter scenario should load on a fresh checkout")
	if payload.is_empty():
		return
	var errors := SaveManager.scenario_validation_errors(payload)
	_assert_true(errors.is_empty(), "Starter scenario should pass the completed-scenario validator: %s" % "; ".join(errors))
	var grid := payload.get("grid", {}) as Dictionary
	_assert_equal(8, int(grid.get("columns", 0)), "Starter scenario should use a small supported map width")
	_assert_equal(8, int(grid.get("rows", 0)), "Starter scenario should use a small supported map height")
	_assert_equal({"4,3": {"priority": "primary"}}, payload.get("objectives", {}), "Starter scenario should have one clear crossroads objective")
	var players := payload.get("players", []) as Array
	for player_index in range(players.size()):
		var player := players[player_index] as Dictionary
		var nation := String(player.get("nation_id", ""))
		_assert_equal("usa" if player_index == 0 else "germany", nation, "Starter forces should use the American and German nations")
		_assert_true(SaveManager.validate_scenario_player_deployment(payload, player_index), "All starter units should be legally deployed and covered by their force tree")
		var deployments := player.get("deployments", {}) as Dictionary
		_assert_equal(9, deployments.size(), "Each starter side should deploy nine separate platoons")
		for row in range(int(grid.get("rows", 0))):
			var front_column := 1 if player_index == 0 else 5
			if player_index == 1 and row == 3:
				front_column = 4
			_assert_true(deployments.has("%d,%d" % [front_column, row]), "Each starter side should cover every row of its eight-hex front")
		_assert_true(deployments.has("0,3" if player_index == 0 else "6,3"), "Each starter side should retain one separate platoon behind its front as a reserve")
		for snapshot_variant in deployments.values():
			var snapshot := snapshot_variant as Dictionary
			var template := UnitCatalog.get_nation_template(nation, String(snapshot.get("template_id", "")))
			_assert_true(not template.is_empty(), "Starter platoons should reference existing catalog templates")
			_assert_equal("platoon", String(snapshot.get("size", "")), "Starter combat counters should be platoons")
	var exported := SaveManager.export_scenario({"id": STARTER_SCENARIO_ID}, EXPORT_PATH)
	_assert_true(exported, "The checked-in starter should export through the existing scenario workflow")
	if exported:
		_assert_equal(payload, SaveManager.load_external_scenario(EXPORT_PATH), "Starter export should round-trip all map, force, briefing, and deployment data")
	DirAccess.remove_absolute(EXPORT_PATH)

func _test_starter_scenario_launches_as_either_side() -> void:
	var payload := SaveManager.load_scenario(STARTER_SCENARIO_ID)
	if payload.is_empty():
		return
	var authored_players := payload.get("players", []) as Array
	for human_side in [0, 1]:
		ScenarioEditorState.clear()
		GameState.reset(false)
		GameState.current_phase = GameState.Phase.SCENARIO_EDITOR
		var screen := SCENARIO_SCREEN.instantiate()
		get_tree().root.add_child(screen)
		var dialog_opened := _open_play_dialog_for_scenario(screen, STARTER_SCENARIO_ID)
		_assert_true(dialog_opened, "The starter should be selectable and playable from the real Scenario Library")
		if not dialog_opened:
			screen.free()
			continue
		_assert_true(screen.scenario_description_label.text.contains("AMERICANS:") and screen.scenario_description_label.text.contains("GERMANS:"), "The library should show both sides' mission briefing")
		if human_side == 0:
			screen.play_side_1_button.pressed.emit()
		else:
			screen.play_side_2_button.pressed.emit()
		_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Both starter side buttons should enter gameplay directly")
		_assert_equal(0, GameState.active_player, "Americans should act first even when the human chooses Germany")
		_assert_equal(1, GameState.current_turn, "Each starter launch should begin a fresh first turn")
		_assert_equal(String((authored_players[human_side] as Dictionary).get("nation_id", "")), GameState.selected_nation_id, "The selected nation should match the chosen starter side")
		_assert_equal(payload.get("terrain", {}), GameState.terrain_map, "Starter terrain should survive launch")
		_assert_equal(payload.get("territory", {}), GameState.territory_map, "Starter territory should survive launch")
		_assert_equal(payload.get("objectives", {}), GameState.key_objectives, "The primary objective should survive launch")
		for player_index in range(2):
			var runtime_player := GameState.players[player_index] as Dictionary
			var authored_player := authored_players[player_index] as Dictionary
			_assert_equal("human" if player_index == human_side else "ai", String(runtime_player.get("controller", "")), "Starter launch should assign the chosen controller to each side")
			_assert_equal(authored_player.get("division_tree", {}), runtime_player.get("division_tree", {}), "Starter launch should preserve each authored force")
			_assert_equal(authored_player.get("deployments", {}), runtime_player.get("deployments", {}), "Starter launch should preserve every authored position")
		screen.free()

		var gameplay := GAMEPLAY_SCREEN.instantiate()
		get_tree().root.add_child(gameplay)
		_assert_equal(18, GameState.gameplay_units.size(), "The gameplay screen should initialize all eighteen starter counters")
		for player_index in range(2):
			var deployments := (authored_players[player_index] as Dictionary).get("deployments", {}) as Dictionary
			for coordinate_variant in deployments.keys():
				var parts := String(coordinate_variant).split(",")
				var start := Vector2i(int(parts[0]), int(parts[1]))
				var snapshot := deployments[coordinate_variant] as Dictionary
				var unit_id := String(snapshot.get("id", ""))
				var runtime_unit := GameState.gameplay_units.get(unit_id, {}) as Dictionary
				_assert_equal(start, runtime_unit.get("hex", null), "Gameplay should use the starter counter's authored hex")
				_assert_equal(player_index, int(runtime_unit.get("owner", -1)), "Gameplay should retain each starter counter's owner")
				_assert_true(not Pathfinding.find_path(start, Vector2i(4, 3), GameState.terrain_map).is_empty(), "Each starter platoon should have a terrain route to the objective")

		# Exercise the same AI planning and turn resolver used during play, for the
		# opposing side in each launch. Free the screen before its deferred AI turn.
		GameState.active_player = 1 - human_side
		gameplay._active_player = GameState.active_player
		gameplay._generate_ai_orders_for_active_player()
		_assert_true(not gameplay._orders.is_empty(), "Either AI opponent should produce orders for the starter mission")
		var result := TurnResolver.resolve_turn(gameplay._units.duplicate(true), gameplay._orders, CombatLog.new(), {"rng_seed": 1944, "active_owner": GameState.active_player})
		var anomalies := result.get("trace_anomalies", []) as Array
		_assert_true(anomalies.is_empty(), "Starter AI side %d should resolve without anomalies: %s" % [1 - human_side, str(anomalies)])
		gameplay.free()
	GameState.reset(false)

func _complete_payload() -> Dictionary:
	var p1_tree := _tree("p1_root", "US Force", "army", "headquarters", "headquarters", [
		_tree("p1_platoon", "US Platoon", "platoon", "infantry", "infantry", [])
	], "usa")
	var p2_tree := _tree("p2_root", "German Force", "army", "headquarters", "headquarters", [
		_tree("p2_platoon", "German Platoon", "platoon", "infantry", "infantry", [])
	], "germany")
	return {
		"scenario_version": SaveManager.SCENARIO_VERSION_CURRENT,
		"version": GameState.MAP_PAYLOAD_VERSION_CURRENT,
		"name": SCENARIO_NAME,
		"briefing": "A complete two-sided integration scenario.",
		"grid": {"columns": 16, "rows": 16},
		"terrain": {"0,0": "woods"},
		"territory": {"0,0": GameState.TerritoryOwnership.PLAYER_1, "1,0": GameState.TerritoryOwnership.PLAYER_2},
		"objectives": {},
		"ai_doctrine": "balanced",
		"difficulty": "medium",
		"players": [
			{"name": "Allied Force", "nation_id": "usa", "division_tree": p1_tree, "deployments": {"0,0": _snapshot(p1_tree["children"][0])}},
			{"name": "Axis Force", "nation_id": "germany", "division_tree": p2_tree, "deployments": {"1,0": _snapshot(p2_tree["children"][0])}}
		]
	}

func _overstacked_payload() -> Dictionary:
	var payload := _complete_payload()
	var players := payload.get("players", []) as Array
	var player_one := players[0] as Dictionary
	var player_one_tree := player_one.get("division_tree", {}) as Dictionary
	var children := player_one_tree.get("children", []) as Array
	for unit_index in range(2, 6):
		children.append(_tree("p1_platoon_%d" % unit_index, "US Platoon %d" % unit_index, "platoon", "infantry", "infantry", []))
	player_one_tree["children"] = children
	player_one["division_tree"] = player_one_tree
	var stack: Array[Dictionary] = []
	for child_variant in children:
		stack.append(_snapshot(child_variant as Dictionary))
	player_one["deployments"] = {"0,0": stack}
	players[0] = player_one
	payload["players"] = players
	return payload

func _packed_lines_contain(lines: PackedStringArray, fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false

func _library_item_index(screen: Control, scenario_id: String, kind: String) -> int:
	for item_index in range(screen.scenario_list.item_count):
		var metadata: Variant = screen.scenario_list.get_item_metadata(item_index)
		if metadata is Dictionary and String((metadata as Dictionary).get("id", "")) == scenario_id and String((metadata as Dictionary).get("kind", "")) == kind:
			return item_index
	return -1

func _tree(id: String, display_name: String, size: String, type: String, role: String, children: Array, nation: String = "") -> Dictionary:
	return {
		"id": id,
		"template_id": id,
		"display_name": display_name,
		"short_name": display_name,
		"designation": {},
		"nation": nation,
		"type": type,
		"role": role,
		"size": size,
		"status": "alive",
		"vehicles": [],
		"children": children
	}

func _snapshot(unit: Dictionary) -> Dictionary:
	var result := unit.duplicate(true)
	result.erase("children")
	result.erase("nation")
	return result

func _deployment_hex_for(deployments: Dictionary, unit_id: String) -> String:
	for key_variant in deployments.keys():
		var value: Variant = deployments[key_variant]
		var units: Array = [value] if value is Dictionary else value as Array
		for unit_variant in units:
			if unit_variant is Dictionary and String((unit_variant as Dictionary).get("id", "")) == unit_id:
				return String(key_variant)
	return ""

func _open_play_dialog_for_scenario(screen: Control, scenario_id: String) -> bool:
	for index in range(screen.scenario_list.item_count):
		var metadata: Variant = screen.scenario_list.get_item_metadata(index)
		if metadata is Dictionary and String((metadata as Dictionary).get("id", "")) == scenario_id:
			screen.scenario_list.select(index)
			screen._on_library_selection_changed(index)
			screen.play_button.pressed.emit()
			return screen.play_dialog.visible
	return false

func _cleanup_storage() -> void:
	SaveManager.delete_scenario(SCENARIO_ID)
	SaveManager.delete_scenario_draft(SCENARIO_ID)
	DirAccess.remove_absolute(EXPORT_PATH)

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_failures.append("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
