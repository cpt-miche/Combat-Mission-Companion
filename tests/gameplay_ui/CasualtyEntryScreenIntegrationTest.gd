extends Node

const CASUALTY_SCREEN_SCENE := preload("res://scenes/screens/CasualtyEntryScreen.tscn")
const MAIN_SCENE := preload("res://scenes/Main.tscn")
const BattleOutcomeResolver = preload("res://scripts/systems/BattleOutcomeResolver.gd")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	await _test_engagements_show_recursive_casualty_hierarchy_and_health()
	await _test_stacked_defenders_all_appear_and_accept_casualties()
	await _test_battle_prep_uses_concise_unit_hierarchy()
	await _test_battle_labels_include_readable_unit_types()
	await _test_dead_units_are_hidden_and_living_descendants_are_promoted()
	await _test_all_subordinate_losses_kill_and_remove_parent()
	_test_living_hq_does_not_keep_destroyed_parent_alive()
	await _test_owner_one_resolution_uses_owner_one_as_own_tree()
	await _test_multiple_battles_advance_one_at_a_time_and_build_summary()
	await _test_new_battle_announcement_prep_and_destroyed_formation_summary()
	await _test_vehicle_casualties_are_tracked_individually()
	await _test_full_vehicle_loss_reports_destroyed_platoon()
	_test_battle_outcomes_move_scatter_destroy_and_advance()
	await _test_partial_combined_formation_hides_absent_casualty_branches()
	await _test_turn_summary_reports_destroyed_formation_once_across_battles()
	await _test_no_combat_turn_still_shows_summary()
	await _test_battle_resolution_is_a_blocking_gameplay_overlay()
	await _test_loaded_resolution_restores_saved_battle_and_summary()

	if _failures.is_empty():
		print("CasualtyEntryScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_engagements_show_recursive_casualty_hierarchy_and_health() -> void:
	_reset_state()
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var own_root: TreeItem = screen.own_tree.get_root()
	var own_unit: TreeItem = own_root.get_first_child()
	_assert_equal("Battle 1 of 1", String(screen.progress_label.text), "Battle screen should show sequence progress")
	_assert_true(String(screen.hex_label.text).contains("3,4"), "Battle screen should show the defending hex")
	_assert_true(own_unit != null, "Player casualty tree should include engaged player unit")
	_assert_equal(2, own_unit.get_child_count(), "Player engaged platoon should include each immediate sub-unit")
	_assert_true(not own_unit.collapsed, "Engaged casualty root should start expanded")
	_assert_true(String(own_unit.get_text(0)).contains("Strength: 2/2 sub-units"), "Casualty parent should show aggregate strength")
	var own_section: TreeItem = own_unit.get_child(0)
	_assert_equal(2, own_section.get_child_count(), "Nested section should preserve both subordinate squads")
	_assert_true(own_section.collapsed, "Deeper casualty parent should start collapsed")
	var casualty_sub_unit_text := String(own_section.get_child(0).get_text(0))
	_assert_true(casualty_sub_unit_text.contains("Health: Alive"), "Casualty sub-unit should show health: %s" % casualty_sub_unit_text)
	var enemy_root: TreeItem = screen.enemy_tree.get_root()
	var enemy_unit: TreeItem = enemy_root.get_first_child()
	_assert_true(enemy_unit != null, "Enemy casualty tree should include engaged enemy unit")
	_assert_equal(1, enemy_unit.get_child_count(), "Enemy engaged platoon should expand to squad/section casualty choices")
	own_section.get_child(0).set_checked(0, true)
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()
	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	var casualty := _find_unit(p1_tree, "p1_squad_a")
	_assert_equal("dead", String(casualty.get("status", "")), "Confirmed squad casualty should mark the squad dead in the formation tree")
	var surviving_parent := _find_unit(p1_tree, "p1_platoon")
	_assert_equal("alive", String(surviving_parent.get("status", "")), "A partial casualty should leave the parent formation alive")
	_assert_true(screen._showing_summary, "Confirming the final battle should show the combat summary")
	_assert_true(String(screen.summary_label.text).contains("Battle 1 — Hex 3,4"), "Combat summary should identify the resolved battle hex")
	_assert_true(String(screen.summary_label.text).contains("1st Squad"), "Combat summary should name reported casualties")
	screen.queue_free()

func _test_stacked_defenders_all_appear_and_accept_casualties() -> void:
	_reset_state()
	var targeted_defender := _unit_tree("targeted_defender", "Targeted Platoon", "platoon", [
		_unit_tree("targeted_squad", "Targeted Squad", "squad", [])
	])
	var stacked_defender := _unit_tree("stacked_defender", "Stacked Platoon", "platoon", [
		_unit_tree("stacked_squad", "Stacked Squad", "squad", [])
	])
	(GameState.players[0] as Dictionary)["division_tree"] = _unit_tree("p1_root", "P1 Army", "army", [targeted_defender, stacked_defender])
	GameState.gameplay_units = {
		"ai_attacker": _gameplay_formation("ai_attacker", 1, Vector2i(2, 3), "company"),
		"targeted_defender": _gameplay_formation("targeted_defender", 0, Vector2i(3, 3), "platoon"),
		"stacked_defender": _gameplay_formation("stacked_defender", 0, Vector2i(3, 3), "platoon")
	}
	(GameState.gameplay_units["stacked_defender"] as Dictionary)["dug_in"] = true
	var engagement := {
		"attacker_unit_id": "ai_attacker",
		"defender_unit_id": "targeted_defender",
		"attacker_owner": 1,
		"defender_owner": 0,
		"attacker_hex": {"q": 2, "r": 3},
		"defender_hex": {"q": 3, "r": 3}
	}
	GameState.pending_casualties = {
		"resolving_player": 1,
		"resolving_turn": 2,
		"workflow_stage": "prep",
		"battles": [{
			"hex": {"q": 3, "r": 3},
			"engagements": [engagement],
			"attacker_unit_ids": ["ai_attacker"],
			"defender_unit_ids": ["targeted_defender", "stacked_defender"]
		}],
		"current_battle_index": 0,
		"results": []
	}

	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var prep_text := String(screen.prep_label.text)
	_assert_true(prep_text.contains("Targeted Platoon"), "Battle prep should list the explicitly targeted defender")
	_assert_true(prep_text.contains("Stacked Platoon"), "Battle prep should list an untargeted defender stacked on the battle hex")
	_assert_true(prep_text.contains("Dug In"), "Battle prep should retain the stacked defender's defensive posture")

	screen._on_submit_pressed()
	var defender_root: TreeItem = screen.enemy_tree.get_root()
	_assert_true(_find_tree_item_by_unit_id(defender_root, "targeted_defender") != null, "Casualty entry should contain the targeted defender")
	_assert_true(_find_tree_item_by_unit_id(defender_root, "stacked_defender") != null, "Casualty entry should contain every listed stacked defender")
	var stacked_squad_item := _find_tree_item_by_unit_id(defender_root, "stacked_squad")
	_assert_true(stacked_squad_item != null, "The stacked defender's casualty-level descendants should be selectable")
	if stacked_squad_item != null:
		stacked_squad_item.set_checked(0, true)
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()
	var updated_stacked_squad := _find_unit((GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary, "stacked_squad")
	_assert_equal("dead", String(updated_stacked_squad.get("status", "")), "A casualty selected from an untargeted stacked defender should be recorded")
	screen.queue_free()

func _test_battle_prep_uses_concise_unit_hierarchy() -> void:
	_reset_state()
	var designation := {
		"division_number": 1,
		"regiment_number": 2,
		"battalion_number": 1,
		"company_letter": "A",
		"platoon_number": 3
	}
	var platoon := _unit_tree("concise_platoon", "3rd Platoon", "platoon", [])
	platoon["role"] = "rifle"
	platoon["designation"] = designation.duplicate(true)
	var company := _unit_tree("concise_company", "A Company", "company", [platoon])
	company["designation"] = designation.duplicate(true)
	var battalion := _unit_tree("concise_battalion", "1st Battalion", "battalion", [company])
	battalion["designation"] = designation.duplicate(true)
	var army := _unit_tree("concise_army", "Army HQ", "army", [battalion])
	(GameState.players[0] as Dictionary)["division_tree"] = army
	GameState.gameplay_units["concise_platoon"] = {
		"id": "concise_platoon",
		"display_name": "3rd Platoon",
		"designation": designation.duplicate(true),
		"owner": 0,
		"hex": Vector2i.ZERO,
		"size": "platoon",
		"type": "infantry",
		"role": "rifle",
		"status": "alive"
	}

	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	_assert_equal("3rd rifle platoon, 1st battalion, A company", screen._prep_unit_line(0, "concise_platoon", false), "Battle prep should combine unit role and echelon without repeating the selected unit")
	_assert_equal("3rd rifle platoon, 1st battalion, A company — Not Dug In", screen._prep_unit_line(0, "concise_platoon", true), "Concise defender labels should retain defensive posture")

	var regiment := _unit_tree("concise_regiment", "2nd Regiment", "regiment", [battalion])
	regiment["designation"] = designation.duplicate(true)
	var division := _unit_tree("concise_division", "1st Division", "division", [regiment])
	division["designation"] = designation.duplicate(true)
	army["children"] = [division]
	_assert_equal("3rd rifle platoon, 1st division, 2nd regiment, 1st battalion, A company", screen._prep_unit_line(0, "concise_platoon", false), "Concise labels should retain relevant division and regiment ancestors")

	platoon["designation"] = {}
	(GameState.gameplay_units["concise_platoon"] as Dictionary)["designation"] = {}
	_assert_true(screen._prep_unit_line(0, "concise_platoon", false).begins_with("3rd Platoon"), "Units without designation data should retain their readable display name")
	screen.queue_free()

func _test_battle_labels_include_readable_unit_types() -> void:
	_reset_state()
	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	var machine_gun_section := _find_unit(p1_tree, "p1_section_group")
	machine_gun_section["type"] = "infantry"
	machine_gun_section["role"] = "machine_gun"
	var heavy_machine_gun := _find_unit(p1_tree, "p1_squad_a")
	heavy_machine_gun["type"] = "INFANTRY"
	heavy_machine_gun["role"] = "heavy_machine_gun"
	var mortar := _find_unit(p1_tree, "p1_squad_b")
	mortar["type"] = "ARTILLERY"
	mortar["role"] = "81mm_mortar"
	var panzer := _find_unit(p1_tree, "p1_section_b")
	panzer["type"] = "tank"
	panzer["role"] = "panzer"
	var p2_tree := (GameState.players[1] as Dictionary).get("division_tree", {}) as Dictionary
	_find_unit(p2_tree, "p2_squad_a")["type"] = "recon"
	_find_unit(p2_tree, "p2_squad_a")["role"] = "recon"

	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame

	var own_root: TreeItem = screen.own_tree.get_root()
	_assert_tree_item_contains(own_root, "p1_section_group", "— Machine Gun —", "Canonical roles should produce readable labels")
	_assert_tree_item_contains(own_root, "p1_squad_a", "— Heavy Machine Gun —", "Specific role should distinguish a weapon unit from its broad infantry class")
	_assert_tree_item_contains(own_root, "p1_squad_b", "— 81mm Mortar —", "Specific role should distinguish a mortar unit from its broad artillery class")
	_assert_tree_item_contains(own_root, "p1_section_b", "— Panzer —", "Specific role should distinguish a catalog tank family from its broad tank class")
	_assert_tree_item_contains(own_root, "p1_platoon", "— Infantry —", "Canonical infantry records should use their explicit role")
	var enemy_root: TreeItem = screen.enemy_tree.get_root()
	_assert_tree_item_contains(enemy_root, "p2_squad_a", "— Recon —", "Enemy casualty rows should use canonical type data")
	screen.queue_free()

func _test_new_battle_announcement_prep_and_destroyed_formation_summary() -> void:
	_reset_state()
	GameState.pending_casualties["workflow_stage"] = "announcement"
	GameState.pending_casualties["battles"] = [{
		"hex": {"q": 3, "r": 4},
		"engagements": GameState.pending_casualties["engagements"],
		"attacker_unit_ids": ["p1_platoon"],
		"defender_unit_ids": ["p2_platoon"]
	}]
	GameState.gameplay_units["p2_platoon"] = {"id": "p2_platoon", "owner": 1, "dug_in": true, "size": "platoon", "type": "infantry", "role": "infantry", "status": "alive"}
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	_assert_equal("Begin", String(screen.submit_button.text), "A new battle should begin on the announcement popup")
	_assert_true(String(screen.hex_label.text).contains("3,4"), "Announcement should list the current battle tile")
	_assert_true(is_zero_approx(screen.dimmer.color.a), "Battle announcement should leave the highlighted map unobscured")
	_assert_true(screen.screen_margin.offset_right - screen.screen_margin.offset_left <= 420.0, "Battle announcement should use a compact popup")
	var viewport_center_x: float = screen.get_viewport_rect().size.x * 0.5
	_assert_true(is_equal_approx(screen.screen_margin.get_global_rect().get_center().x, viewport_center_x), "Battle announcement should initially appear at the top center of the screen")
	var starting_popup_position: Vector2 = screen.screen_margin.position
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_LEFT
	drag_press.pressed = true
	drag_press.position = screen.modal_panel.get_global_rect().position + Vector2(12.0, 12.0)
	screen._input(drag_press)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag_motion.position = drag_press.position + Vector2(48.0, 36.0)
	drag_motion.relative = Vector2(48.0, 36.0)
	screen._input(drag_motion)
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_LEFT
	drag_release.pressed = false
	drag_release.position = drag_motion.position
	screen._input(drag_release)
	_assert_equal(starting_popup_position + Vector2(48.0, 36.0), screen.screen_margin.position, "Battle announcement should be draggable by its panel")
	screen._on_submit_pressed()
	_assert_equal("Go to Battle Resolution Screen", String(screen.submit_button.text), "Begin should advance to battle prep")
	_assert_true(String(screen.prep_label.text).contains("Dug In"), "Battle prep should list defender posture")
	screen._on_submit_pressed()
	_assert_equal("Battle 1 of 1", String(screen.progress_label.text), "Battle prep should advance to casualty resolution")

	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	for casualty_id in ["p1_squad_a", "p1_squad_b", "p1_section_b"]:
		_mark_unit_dead(p1_tree, casualty_id)
	var summarized: Array[String] = screen._largest_destroyed_formation_ids(0, ["p1_squad_a", "p1_squad_b", "p1_section_b"])
	_assert_equal(["p1_platoon"], summarized, "A fully destroyed platoon should replace its individual subordinate casualty entries")
	screen.queue_free()

func _test_vehicle_casualties_are_tracked_individually() -> void:
	_configure_tank_casualty_battle()
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var tank_item := _find_tree_item_by_unit_id(screen.own_tree.get_root(), "sherman_platoon")
	_assert_true(tank_item != null, "An engaged tank platoon should appear in casualty entry")
	_assert_equal(5, tank_item.get_child_count() if tank_item != null else -1, "A five-tank platoon should expose five named vehicle checkboxes")
	if tank_item != null:
		var commander_item: TreeItem = null
		var vehicle_labels: Array[String] = []
		for child_index in range(tank_item.get_child_count()):
			var candidate := tank_item.get_child(child_index)
			vehicle_labels.append(String(candidate.get_text(0)))
			if String(candidate.get_text(0)).contains("Commander M4 Sherman"):
				commander_item = candidate
				break
		_assert_true(commander_item != null, "The command tank should be named in casualty entry; labels=%s" % str(vehicle_labels))
		if commander_item != null:
			commander_item.set_checked(0, true)
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()
	var updated_tank := _find_unit((GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary, "sherman_platoon")
	_assert_equal("dead", String(((updated_tank.get("vehicles", []) as Array)[0] as Dictionary).get("status", "")), "Checking a tank should mark only that vehicle dead")
	_assert_equal(4, int(updated_tank.get("live_sub_units", -1)), "A partial vehicle loss should update platoon strength")
	_assert_equal("alive", String(updated_tank.get("status", "")), "A platoon with surviving tanks should remain alive")
	_assert_true(String(screen.summary_label.text).contains("Commander M4 Sherman"), "The turn summary should name partial vehicle losses")
	for index in range(1, 5):
		GameState.mark_vehicle_status("sherman_platoon", "sherman_vehicle_%d" % index, "dead", 0)
	GameState.reconcile_formation_statuses(0)
	updated_tank = _find_unit((GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary, "sherman_platoon")
	_assert_equal("dead", String(updated_tank.get("status", "")), "A tank platoon should be destroyed when all tracked vehicles are dead")
	screen.queue_free()

func _test_full_vehicle_loss_reports_destroyed_platoon() -> void:
	_configure_tank_casualty_battle()
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var tank_item := _find_tree_item_by_unit_id(screen.own_tree.get_root(), "sherman_platoon")
	_assert_true(tank_item != null, "The tank platoon should be available for a full vehicle-loss report")
	if tank_item != null:
		for child_index in range(tank_item.get_child_count()):
			tank_item.get_child(child_index).set_checked(0, true)
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()
	var updated_tank := _find_unit((GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary, "sherman_platoon")
	_assert_equal("dead", String(updated_tank.get("status", "")), "Checking every tank should destroy the platoon")
	var summary := String(screen.summary_label.text)
	_assert_true(summary.contains("M4 Sherman Platoon"), "A fully destroyed tank platoon should be listed as the casualty formation")
	_assert_true(not summary.contains("P1 vehicle losses:"), "A fully destroyed platoon should not also be reported as partial vehicle losses")
	screen.queue_free()

func _configure_tank_casualty_battle() -> void:
	_reset_state()
	var vehicles: Array = []
	for index in range(5):
		vehicles.append({
			"id": "sherman_vehicle_%d" % index,
			"model": "M4 Sherman",
			"slot": "platoon_commander" if index == 0 else "line_vehicle",
			"display_name": "Commander M4 Sherman" if index == 0 else "M4 Sherman %d" % index,
			"status": "alive"
		})
	var tank_platoon := _unit_tree("sherman_platoon", "M4 Sherman Platoon", "platoon", [])
	tank_platoon["role"] = "medium_tank"
	tank_platoon["type"] = "tank"
	tank_platoon["vehicles"] = vehicles.duplicate(true)
	(GameState.players[0] as Dictionary)["division_tree"] = tank_platoon
	GameState.gameplay_units = {
		"sherman_platoon": {
			"id": "sherman_platoon", "display_name": "M4 Sherman Platoon", "designation": {}, "owner": 0, "hex": Vector2i(2, 2),
			"size": "platoon", "type": "tank", "role": "medium_tank", "status": "alive",
			"vehicles": vehicles.duplicate(true), "live_sub_units": 5, "max_sub_units": 5
		},
		"p2_platoon": {"id": "p2_platoon", "display_name": "P2 Platoon", "designation": {}, "owner": 1, "hex": Vector2i(3, 2), "size": "platoon", "type": "infantry", "role": "infantry", "status": "alive"}
	}
	GameState.pending_casualties = {
		"resolving_player": 0,
		"resolving_turn": 1,
		"workflow_stage": "resolution",
		"battles": [{
			"hex": {"q": 3, "r": 2},
			"attacker_unit_ids": ["sherman_platoon"],
			"defender_unit_ids": ["p2_platoon"],
			"engagements": [{
				"attacker_unit_id": "sherman_platoon", "defender_unit_id": "p2_platoon",
				"attacker_owner": 0, "defender_owner": 1, "defender_hex": {"q": 3, "r": 2}
			}]
		}]
	}

func _test_battle_outcomes_move_scatter_destroy_and_advance() -> void:
	var dimensions := Vector2i(8, 6)
	var territory := {}
	for q in range(dimensions.x):
		for r in range(dimensions.y):
			territory["%d,%d" % [q, r]] = GameState.TerritoryOwnership.NEUTRAL
	var battle := {
		"hex": {"q": 3, "r": 2},
		"engagements": [{
			"attacker_unit_id": "attacker", "defender_unit_id": "defender",
			"attacker_owner": 0, "defender_owner": 1,
			"attacker_hex": {"q": 2, "r": 2}, "defender_hex": {"q": 3, "r": 2}
		}]
	}
	var units := {
		"attacker": _gameplay_formation("attacker", 0, Vector2i(2, 2), "company"),
		"defender": _gameplay_formation("defender", 1, Vector2i(3, 2), "company")
	}
	var defeat := BattleOutcomeResolver.resolve(units, battle, BattleOutcomeResolver.OUTCOME_ATTACKER_DEFEAT, {"territory_map": territory, "map_dimensions": dimensions})
	_assert_equal(Vector2i(2, 2), ((defeat.get("units", {}) as Dictionary)["attacker"] as Dictionary).get("hex"), "Attacker defeat should leave attackers in place")
	_assert_equal(Vector2i(3, 2), ((defeat.get("units", {}) as Dictionary)["defender"] as Dictionary).get("hex"), "Attacker defeat should leave defenders in place")

	var victory := BattleOutcomeResolver.resolve(units, battle, BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY, {"territory_map": territory, "map_dimensions": dimensions, "rng_seed": 3})
	var victory_units := victory.get("units", {}) as Dictionary
	_assert_equal(Vector2i(3, 2), (victory_units["attacker"] as Dictionary).get("hex"), "Attacker victory should advance the attacker into the battle tile")
	_assert_equal(1, Pathfinding.hex_distance(Vector2i(3, 2), (victory_units["defender"] as Dictionary).get("hex")), "Attacker victory should push the defender back one tile")
	_assert_equal(GameState.TerritoryOwnership.PLAYER_1, int((victory.get("territory_updates", {}) as Dictionary).get("3,2", -1)), "An advancing attacker should capture the battle tile")

	var stacked_defender_battle := battle.duplicate(true)
	stacked_defender_battle["attacker_unit_ids"] = ["attacker"]
	stacked_defender_battle["defender_unit_ids"] = ["defender", "defender_reserve"]
	var stacked_defender_units := units.duplicate(true)
	stacked_defender_units["defender_reserve"] = _gameplay_formation("defender_reserve", 1, Vector2i(3, 2), "platoon")
	var stacked_defender_result := BattleOutcomeResolver.resolve(stacked_defender_units, stacked_defender_battle, BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY, {"territory_map": territory, "map_dimensions": dimensions, "rng_seed": 4})
	var stacked_result_units := stacked_defender_result.get("units", {}) as Dictionary
	_assert_true((stacked_result_units["defender"] as Dictionary).get("hex") != Vector2i(3, 2), "The explicitly targeted defender should retreat")
	_assert_true((stacked_result_units["defender_reserve"] as Dictionary).get("hex") != Vector2i(3, 2), "Every untargeted defender stacked on the battle hex should also retreat")
	_assert_equal(Vector2i(3, 2), (stacked_result_units["attacker"] as Dictionary).get("hex"), "The attacker should advance only after every defender leaves the hex")

	var major := BattleOutcomeResolver.resolve(units, battle, BattleOutcomeResolver.OUTCOME_MAJOR_ATTACKER_VICTORY, {"territory_map": territory, "map_dimensions": dimensions, "rng_seed": 7})
	var major_units := major.get("units", {}) as Dictionary
	_assert_equal(2, Pathfinding.hex_distance(Vector2i(3, 2), (major_units["defender"] as Dictionary).get("hex")), "Major attacker victory should scatter the defender exactly two tiles")
	_assert_equal(Vector2i(3, 2), (major_units["attacker"] as Dictionary).get("hex"), "Major attacker victory should advance the attacker")

	var trapped_battle := {
		"hex": {"q": 1, "r": 0},
		"engagements": [{
			"attacker_unit_id": "trap_attacker", "defender_unit_id": "trap_defender",
			"attacker_owner": 0, "defender_owner": 1,
			"attacker_hex": {"q": 0, "r": 0}, "defender_hex": {"q": 1, "r": 0}
		}]
	}
	var trapped_units := {
		"trap_attacker": _gameplay_formation("trap_attacker", 0, Vector2i(0, 0), "company"),
		"trap_defender": _gameplay_formation("trap_defender", 1, Vector2i(1, 0), "company")
	}
	var trapped := BattleOutcomeResolver.resolve(trapped_units, trapped_battle, BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY, {"territory_map": {"0,0": GameState.TerritoryOwnership.PLAYER_1, "1,0": GameState.TerritoryOwnership.PLAYER_2}, "map_dimensions": Vector2i(2, 1)})
	_assert_equal(["trap_defender"], trapped.get("forced_destroyed_unit_ids", []), "A defender with no legal retreat should be destroyed")

	var stacked_units := {"stack_defender": _gameplay_formation("stack_defender", 1, Vector2i(3, 2), "company")}
	var stack_engagements: Array = []
	for index in range(5):
		var attacker_id := "stack_attacker_%d" % index
		stacked_units[attacker_id] = _gameplay_formation(attacker_id, 0, Vector2i(2, 2), "company")
		stack_engagements.append({"attacker_unit_id": attacker_id, "defender_unit_id": "stack_defender", "attacker_owner": 0, "defender_owner": 1, "attacker_hex": {"q": 2, "r": 2}, "defender_hex": {"q": 3, "r": 2}})
	var stacked := BattleOutcomeResolver.resolve(stacked_units, {"hex": {"q": 3, "r": 2}, "engagements": stack_engagements}, BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY, {"territory_map": territory, "map_dimensions": dimensions})
	var advanced_count := 0
	for index in range(5):
		if ((stacked.get("units", {}) as Dictionary)["stack_attacker_%d" % index] as Dictionary).get("hex") == Vector2i(3, 2):
			advanced_count += 1
	_assert_equal(4, advanced_count, "All legal attackers should advance, while the fifth company remains behind at the stack cap")

func _test_partial_combined_formation_hides_absent_casualty_branches() -> void:
	_reset_state()
	var platoon_one := _unit_tree("partial_p1", "1st Platoon", "platoon", [_unit_tree("partial_s1", "1st Squad", "squad", [])])
	var platoon_two := _unit_tree("partial_p2", "2nd Platoon", "platoon", [_unit_tree("partial_s2", "2nd Squad", "squad", [])])
	var platoon_three := _unit_tree("partial_p3", "3rd Platoon", "platoon", [_unit_tree("partial_s3", "3rd Squad", "squad", [])])
	var company := _unit_tree("partial_company", "A Company", "company", [platoon_one, platoon_two, platoon_three])
	(GameState.players[0] as Dictionary)["division_tree"] = company
	GameState.gameplay_units = {
		"partial_company": {
			"id": "partial_company",
			"owner": 0,
			"hex": Vector2i(0, 0),
			"size": "company",
			"status": "alive",
			"is_combined_formation": true,
			"combined_components": [{"id": "partial_p1"}, {"id": "partial_p2"}]
		}
	}
	GameState.pending_casualties = {
		"resolving_player": 0,
		"resolving_turn": 2,
		"workflow_stage": "resolution",
		"battles": [{
			"hex": {"q": 1, "r": 1},
			"engagements": [{"attacker_unit_id": "partial_company", "defender_unit_id": "p2_platoon", "attacker_owner": 0, "defender_owner": 1, "defender_hex": {"q": 1, "r": 1}}],
			"attacker_unit_ids": ["partial_company"],
			"defender_unit_ids": ["p2_platoon"]
		}],
		"current_battle_index": 0,
		"results": []
	}
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var own_tree := screen.get_node("%OwnCasualtyTree") as Tree
	var own_root: TreeItem = own_tree.get_root()
	_assert_true(_find_tree_item_by_unit_id(own_root, "partial_p1") != null, "An included platoon should appear under a partial combined company")
	_assert_true(_find_tree_item_by_unit_id(own_root, "partial_p2") != null, "Every included branch should remain available for casualty entry")
	_assert_true(_find_tree_item_by_unit_id(own_root, "partial_p3") == null, "An absent platoon must not appear as a casualty choice")
	_assert_true(_find_tree_item_by_unit_id(own_root, "partial_s3") == null, "Absent platoon descendants must also be excluded")
	screen.queue_free()

func _test_turn_summary_reports_destroyed_formation_once_across_battles() -> void:
	_reset_state()
	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	for casualty_id in ["p1_squad_a", "p1_squad_b", "p1_section_b"]:
		_mark_unit_dead(p1_tree, casualty_id)
	GameState.reconcile_formation_statuses(0)
	GameState.pending_casualties = _two_battle_resolution_payload()
	GameState.pending_casualties["current_battle_index"] = 2
	GameState.pending_casualties["workflow_stage"] = "summary"
	GameState.pending_casualties["results"] = [
		{"casualties_by_owner": {"0": ["p1_squad_a"], "1": []}},
		{"casualties_by_owner": {"0": ["p1_squad_b", "p1_section_b"], "1": []}}
	]
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var summary := String(screen.summary_label.text)
	var casualty_section: String = summary.split("Turn Casualties")[1] if summary.contains("Turn Casualties") else summary
	_assert_equal(1, casualty_section.count("P1 Platoon"), "A formation destroyed across multiple battles should appear once in the turn casualty summary")
	_assert_true(not casualty_section.contains("1st Squad") and not casualty_section.contains("2nd Squad"), "A destroyed platoon should replace its subordinate casualty entries turn-wide")
	screen.queue_free()

func _test_dead_units_are_hidden_and_living_descendants_are_promoted() -> void:
	_reset_state()
	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	_mark_unit_dead(p1_tree, "p1_platoon")
	_mark_unit_dead(p1_tree, "p1_squad_a")
	var p2_tree := (GameState.players[1] as Dictionary).get("division_tree", {}) as Dictionary
	_mark_unit_dead(p2_tree, "p2_platoon")
	_mark_unit_dead(p2_tree, "p2_squad_a")

	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame

	var own_root: TreeItem = screen.own_tree.get_root()
	_assert_true(_find_tree_item_by_unit_id(own_root, "p1_platoon") == null, "Dead engaged roots should not appear in casualty choices")
	_assert_true(_find_tree_item_by_unit_id(own_root, "p1_squad_a") == null, "Dead descendants should not appear in casualty choices")
	var living_section := _find_tree_item_by_unit_id(own_root, "p1_section_group")
	_assert_true(living_section != null, "Living descendants of a dead engaged root should be promoted into the casualty tree")
	_assert_true(_find_tree_item_by_unit_id(own_root, "p1_squad_b") != null, "Promoting a living branch should preserve its living casualty choices")

	var enemy_empty_item: TreeItem = screen.enemy_tree.get_root().get_first_child()
	_assert_true(enemy_empty_item != null, "A fully dead engaged side should show an empty-state row")
	if enemy_empty_item != null:
		var empty_metadata: Variant = enemy_empty_item.get_metadata(0)
		_assert_true(empty_metadata == null or str(empty_metadata).is_empty(), "The empty-state row should not identify a dead unit")
		_assert_true(not enemy_empty_item.is_selectable(0), "The empty-state row should not be selectable")

	if living_section != null:
		living_section.set_checked(0, true)
		_mark_unit_dead(p1_tree, "p1_section_group")
		_assert_true(screen._confirmed_own_casualty_unit_ids().is_empty(), "A unit that dies while casualty entry is open must not be confirmed again")
	screen.queue_free()

func _test_all_subordinate_losses_kill_and_remove_parent() -> void:
	_reset_state()
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var own_unit: TreeItem = screen.own_tree.get_root().get_first_child()
	var nested_section: TreeItem = own_unit.get_child(0)
	nested_section.set_checked(0, true)
	screen._on_tree_check_propagated(nested_section, 0)
	own_unit.get_child(1).set_checked(0, true)
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()

	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	_assert_equal("dead", String(_find_unit(p1_tree, "p1_section_group").get("status", "")), "A section should die when it and all nested squads are confirmed lost")
	_assert_equal("dead", String(_find_unit(p1_tree, "p1_platoon").get("status", "")), "A parent formation should die when all direct sub-units are dead")
	var gameplay_parent := GameState.gameplay_units.get("p1_platoon", {}) as Dictionary
	_assert_true(not GameState.is_unit_alive(gameplay_parent), "Dead parent should be synchronized out of live gameplay")
	var deployments := (GameState.players[0] as Dictionary).get("deployments", {}) as Dictionary
	var deployed_stack := deployments.get("0,0", []) as Array
	var deployed_parent := deployed_stack[0] as Dictionary
	_assert_true(not GameState.is_unit_alive(deployed_parent), "Dead parent should be synchronized to its map deployment")
	_assert_true(GameState.is_unit_alive(deployed_stack[1] as Dictionary), "Synchronizing a dead parent should preserve other units stacked on the hex")
	screen.queue_free()

func _test_living_hq_does_not_keep_destroyed_parent_alive() -> void:
	_reset_state()
	var player_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	var living_hq := _unit_tree("p1_platoon_hq", "Platoon HQ", "section", [])
	living_hq["type"] = "headquarters"
	living_hq["role"] = "headquarters"
	(player_tree.get("children", []) as Array).append(living_hq)
	for casualty_id in ["p1_squad_a", "p1_squad_b", "p1_section_b"]:
		_mark_unit_dead(player_tree, casualty_id)

	var reconciled_ids := GameState.reconcile_formation_statuses(0)
	_assert_equal("dead", String(_find_unit(player_tree, "p1_platoon").get("status", "")), "A living HQ should not keep a parent alive after every combat subordinate is destroyed")
	_assert_equal("alive", String(_find_unit(player_tree, "p1_platoon_hq").get("status", "")), "Destroying the effective parent should not kill its surviving HQ element")
	_assert_true(reconciled_ids.has("p1_platoon"), "Parent destruction caused by combat-subordinate losses should be reported for casualty summaries")

	var headquarters_only_parent := _unit_tree("hq_only_parent", "HQ-only Parent", "platoon", [])
	var headquarters_only_child := _unit_tree("hq_only_child", "Platoon HQ", "section", [])
	headquarters_only_child["type"] = UnitType.Value.HEADQUARTERS
	headquarters_only_child["role"] = "headquarters"
	(headquarters_only_parent.get("children", []) as Array).append(headquarters_only_child)
	(GameState.players[1] as Dictionary)["division_tree"] = headquarters_only_parent
	GameState.reconcile_formation_statuses(1)
	_assert_equal("alive", String(headquarters_only_parent.get("status", "")), "A formation with no combat components should not be auto-destroyed merely because it contains only HQ elements")

func _test_owner_one_resolution_uses_owner_one_as_own_tree() -> void:
	_reset_state()
	GameState.pending_casualties["resolving_player"] = 1
	var engagement := {
		"attacker_unit_id": "p2_platoon",
		"defender_unit_id": "p1_platoon",
		"attacker_owner": 1,
		"defender_owner": 0,
		"defender_hex": {"q": 0, "r": 0}
	}
	GameState.pending_casualties["engagements"] = [engagement]
	GameState.pending_casualties["battles"] = [{"hex": {"q": 0, "r": 0}, "engagements": [engagement], "attacker_unit_ids": ["p2_platoon"], "defender_unit_ids": ["p1_platoon"]}]
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var own_unit: TreeItem = screen.own_tree.get_root().get_first_child()
	var enemy_unit: TreeItem = screen.enemy_tree.get_root().get_first_child()
	_assert_true(own_unit != null, "Owner 1 casualty tree should include its engaged unit as own")
	_assert_true(enemy_unit != null, "Owner 1 casualty tree should include owner 0 unit as enemy")
	_assert_equal("p2_platoon", String(own_unit.get_metadata(0)), "Resolving owner 1 should build the own tree from owner 1 units")
	_assert_equal("p1_platoon", String(enemy_unit.get_metadata(0)), "Resolving owner 1 should build the enemy tree from owner 0 units")
	screen.queue_free()

func _test_multiple_battles_advance_one_at_a_time_and_build_summary() -> void:
	_reset_state()
	GameState.pending_casualties = _two_battle_resolution_payload()
	GameState.pending_casualties["workflow_stage"] = "resolution"
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var first_own_unit: TreeItem = screen.own_tree.get_root().get_first_child()
	first_own_unit.get_child(0).get_child(0).set_checked(0, true)
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()
	_assert_equal("Begin", String(screen.submit_button.text), "The next defending hex should restart at its announcement")
	_assert_true(String(screen.hex_label.text).contains("8,1"), "Second battle should display its own defending hex")
	screen._on_submit_pressed()
	_assert_equal("Go to Battle Resolution Screen", String(screen.submit_button.text), "The second battle announcement should advance to prep")
	screen._on_submit_pressed()
	_assert_equal("Battle 2 of 2", String(screen.progress_label.text), "The second battle prep should advance to its own resolution")
	var second_own_root: TreeItem = screen.own_tree.get_root()
	_assert_true(_find_tree_item_by_unit_id(second_own_root, "p1_squad_a") == null, "Later battles should hide casualties already applied")
	_assert_true(_find_tree_item_by_unit_id(second_own_root, "p1_squad_b") != null, "Later battles should retain living units beside a prior casualty")
	_select_attacker_defeat(screen)
	screen._on_submit_pressed()
	_assert_true(screen._showing_summary, "Confirming every battle should replace casualty entry with the summary")
	var summary_text := String(screen.summary_label.text)
	_assert_true(summary_text.contains("Battle 1 — Hex 3,4"), "Summary should include the first battle")
	_assert_true(summary_text.contains("Battle 2 — Hex 8,1"), "Summary should include the second battle")
	_assert_true(summary_text.contains("P2 casualties: None"), "Summary should explicitly report a side with no losses")
	screen.queue_free()

func _test_no_combat_turn_still_shows_summary() -> void:
	_reset_state()
	GameState.pending_casualties = {
		"resolving_player": 0,
		"resolving_turn": 5,
		"engagements": [],
		"battles": [],
		"results": [],
		"current_battle_index": 0
	}
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	_assert_true(screen._showing_summary, "A turn without combat should open directly on the summary")
	_assert_equal("No combat occurred.", String(screen.summary_label.text), "Empty combat summary should clearly state that nothing occurred")
	screen._on_submit_pressed()
	_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Continuing from the summary should return to gameplay")
	_assert_true(GameState.pending_casualties.is_empty(), "Continuing should clear completed battle-resolution state")
	screen.queue_free()

func _test_battle_resolution_is_a_blocking_gameplay_overlay() -> void:
	_reset_state()
	GameState.pending_casualties = _two_battle_resolution_payload()
	GameState.current_phase = GameState.Phase.CASUALTY_ENTRY
	var main := MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame

	var gameplay: Control = main.current_screen
	var overlay: Control = main.battle_resolution_overlay
	_assert_true(is_instance_valid(gameplay), "Pending resolution should reconstruct and retain the gameplay screen")
	_assert_true(is_instance_valid(overlay), "Pending resolution should open a modal above gameplay")
	_assert_true(overlay.get_index() > gameplay.get_index(), "Battle resolution should render above gameplay")
	_assert_true(gameplay.is_battle_resolution_overlay_active(), "Gameplay input should be locked while battle resolution is open")
	_assert_true(gameplay.end_turn_button.disabled, "End Turn should be disabled behind battle resolution")
	_assert_true(gameplay.move_button.disabled and gameplay.attack_button.disabled and gameplay.dig_in_button.disabled, "Order controls should be disabled behind battle resolution")

	var dimmer := overlay.get_node("Dimmer") as ColorRect
	_assert_true(dimmer.color.a > 0.0 and dimmer.color.a < 1.0, "Overlay should dim the recognizable gameplay map with transparency")
	var modal_panel := overlay.get_node("%ModalPanel") as PanelContainer
	var modal_style := modal_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_assert_true(modal_style != null and is_equal_approx(modal_style.bg_color.a, 1.0), "Battle controls should sit on a fully opaque panel")
	_assert_true(overlay.submit_button.has_focus(), "The primary resolution control should receive keyboard focus")

	var starting_zoom: float = gameplay._camera_zoom
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_event.pressed = true
	wheel_event.position = Vector2(400, 300)
	gameplay._gui_input(wheel_event)
	_assert_true(is_equal_approx(starting_zoom, gameplay._camera_zoom), "Map zoom should be blocked behind the modal")
	var starting_turn := GameState.current_turn
	var starting_mode: int = gameplay._active_order_mode
	gameplay._on_attack_mode_pressed()
	gameplay._on_end_turn_pressed()
	_assert_equal(starting_mode, gameplay._active_order_mode, "Order-mode input should be blocked behind the modal")
	_assert_equal(starting_turn, GameState.current_turn, "End Turn should not run behind the modal")

	_select_attacker_defeat(overlay)
	overlay._on_submit_pressed()
	_assert_equal("Begin", String(overlay.submit_button.text), "The next in-map battle should restart at its announcement")
	_assert_true(String(overlay.progress_label.text).begins_with("Battle 2 of 2"), "The in-map overlay should identify the next battle")
	var saved_after_first_battle := SaveManager.load_current_game()
	var saved_casualties := saved_after_first_battle.get("casualties", {}) as Dictionary
	_assert_equal(1, int(saved_casualties.get("current_battle_index", -1)), "Battle progress should autosave after each confirmation")
	_assert_equal(2, (saved_after_first_battle.get("players", []) as Array).size(), "Autosave should retain force trees needed to resume casualty entry")
	overlay._on_submit_pressed()
	_assert_equal("Go to Battle Resolution Screen", String(overlay.submit_button.text), "The next battle should include its own prep screen")
	overlay._on_submit_pressed()
	_assert_equal("Battle 2 of 2", String(overlay.progress_label.text), "The next battle prep should advance to its resolution")
	_select_attacker_defeat(overlay)
	overlay._on_submit_pressed()
	_assert_true(overlay._showing_summary, "The final battle should transition to the combat summary in the overlay")
	var retained_gameplay := gameplay
	overlay._on_submit_pressed()
	overlay._on_submit_pressed()
	await get_tree().process_frame
	_assert_equal(GameState.Phase.GAMEPLAY, GameState.current_phase, "Completing the summary should return to gameplay")
	_assert_true(GameState.pending_casualties.is_empty(), "Completing the overlay should clear pending casualty state")
	_assert_true(not is_instance_valid(main.battle_resolution_overlay), "Completing the summary should close the overlay")
	_assert_true(main.current_screen == retained_gameplay, "Closing resolution should reuse the same gameplay screen")
	_assert_true(not retained_gameplay.is_battle_resolution_overlay_active(), "Gameplay input should be restored after resolution")
	_assert_true(not retained_gameplay.end_turn_button.disabled, "End Turn should be restored after resolution")
	_assert_equal(starting_turn, GameState.current_turn, "Closing the overlay twice must not advance the turn again")
	var completed_save := SaveManager.load_current_game()
	_assert_true((completed_save.get("casualties", {}) as Dictionary).is_empty(), "Completing resolution should autosave the cleared pending state")
	main.queue_free()
	await get_tree().process_frame

func _test_loaded_resolution_restores_saved_battle_and_summary() -> void:
	_reset_state()
	GameState.current_phase = GameState.Phase.MAIN_MENU
	var main := MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var main_menu: Control = main.current_screen
	var battle_payload := _two_battle_resolution_payload()
	battle_payload["current_battle_index"] = 1
	battle_payload["results"] = [_empty_battle_result((battle_payload["battles"] as Array)[0] as Dictionary)]
	var save_payload := {
		"save_version": SaveManager.CURRENT_GAME_SAVE_VERSION,
		"turn_number": 4,
		"active_player": 1,
		"players": GameState.players.duplicate(true),
		"map": {"version": GameState.MAP_PAYLOAD_VERSION_CURRENT, "name": "loaded-resolution", "grid": {"columns": 16, "rows": 16}, "terrain": {"0,0": "woods"}, "territory": {}, "objectives": {}, "ai_doctrine": "balanced", "difficulty": "medium"},
		"units": {"p1_platoon": {"id": "p1_platoon", "display_name": "P1 Platoon", "designation": {}, "owner": 0, "hex": {"x": 0, "y": 0}, "size": "platoon", "type": "infantry", "role": "infantry", "status": "alive"}},
		"orders": {},
		"casualties": battle_payload,
		"combat_log_entries": [],
		"ai_debug": {"enabled": false, "level": 0},
		"ai_formation_state": {},
		"scout_intel_by_observer": {}
	}
	main_menu._apply_loaded_payload(save_payload)
	_assert_equal(GameState.Phase.CASUALTY_ENTRY, main_menu._loaded_game_phase(), "A save with pending casualties should resume resolution instead of bare gameplay")
	GameState.set_phase(main_menu._loaded_game_phase())
	await get_tree().process_frame
	var restored_overlay: Control = main.battle_resolution_overlay
	_assert_true(is_instance_valid(restored_overlay), "Loading pending resolution should reopen the overlay")
	_assert_equal("Battle 2 of 2", String(restored_overlay.progress_label.text), "Loading should restore the saved battle index")
	_assert_equal(Vector2i(16, 16), GameState.selected_map_dimensions, "Loading pending resolution should restore map dimensions")
	_assert_equal("woods", String(GameState.terrain_map.get("0,0", "")), "Loading pending resolution should restore map terrain")
	main.queue_free()
	await get_tree().process_frame

	_reset_state()
	GameState.pending_casualties = _two_battle_resolution_payload()
	GameState.pending_casualties["current_battle_index"] = 2
	GameState.pending_casualties["results"] = [
		_empty_battle_result((GameState.pending_casualties["battles"] as Array)[0] as Dictionary),
		_empty_battle_result((GameState.pending_casualties["battles"] as Array)[1] as Dictionary)
	]
	GameState.current_phase = GameState.Phase.CASUALTY_ENTRY
	main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	restored_overlay = main.battle_resolution_overlay
	_assert_true(restored_overlay._showing_summary, "A save after all battles should reopen at the combat summary")
	main.queue_free()
	await get_tree().process_frame

func _two_battle_resolution_payload() -> Dictionary:
	var engagements := [
		{"attacker_unit_id": "p1_platoon", "defender_unit_id": "p2_platoon", "attacker_owner": 0, "defender_owner": 1, "defender_hex": {"q": 3, "r": 4}},
		{"attacker_unit_id": "p1_platoon", "defender_unit_id": "p2_platoon", "attacker_owner": 0, "defender_owner": 1, "defender_hex": {"q": 8, "r": 1}}
	]
	return {
		"resolving_player": 0,
		"resolving_turn": 1,
		"workflow_stage": "resolution",
		"engagements": engagements,
		"battles": [
			{"hex": {"q": 3, "r": 4}, "engagements": [engagements[0]], "attacker_unit_ids": ["p1_platoon"], "defender_unit_ids": ["p2_platoon"]},
			{"hex": {"q": 8, "r": 1}, "engagements": [engagements[1]], "attacker_unit_ids": ["p1_platoon"], "defender_unit_ids": ["p2_platoon"]}
		],
		"current_battle_index": 0,
		"results": []
	}

func _empty_battle_result(battle: Dictionary) -> Dictionary:
	return {
		"hex": (battle.get("hex", {}) as Dictionary).duplicate(true),
		"attacker_unit_ids": (battle.get("attacker_unit_ids", []) as Array).duplicate(),
		"defender_unit_ids": (battle.get("defender_unit_ids", []) as Array).duplicate(),
		"casualties_by_owner": {"0": [], "1": []}
	}

func _select_attacker_defeat(screen: Control) -> void:
	screen._on_outcome_selected("attacker_defeat")

func _reset_state() -> void:
	GameState.reset()
	GameState.players = [
		{"name":"P1", "controller":"human", "division_tree": _unit_tree("p1_platoon", "P1 Platoon", "platoon", [
			_unit_tree("p1_section_group", "Rifle Section", "section", [
				_unit_tree("p1_squad_a", "1st Squad", "squad", []),
				_unit_tree("p1_squad_b", "2nd Squad", "squad", [])
			]),
			_unit_tree("p1_section_b", "Weapons Section", "section", [])
		]), "deployments": {"0,0": [
			_unit_tree("p1_platoon", "P1 Platoon", "platoon", []),
			_unit_tree("p1_support", "P1 Support", "section", [])
		]}},
		{"name":"P2", "controller":"human", "division_tree": _unit_tree("p2_platoon", "P2 Platoon", "platoon", [
			_unit_tree("p2_squad_a", "Enemy Squad", "squad", [])
		]), "deployments": {}}
	]
	GameState.gameplay_units = {
		"p1_platoon": {
			"id": "p1_platoon",
			"display_name": "P1 Platoon",
			"designation": {},
			"owner": 0,
			"hex": Vector2i(0, 0),
			"size": "platoon",
			"type": "infantry",
			"role": "infantry",
			"status": "alive"
		}
	}
	GameState.pending_casualties = {
		"resolving_player": 0,
		"resolving_turn": 1,
		"engagements": [{
			"attacker_unit_id": "p1_platoon",
			"defender_unit_id": "p2_platoon",
			"attacker_owner": 0,
			"defender_owner": 1,
			"defender_hex": {"q": 3, "r": 4}
		}],
		"workflow_stage": "resolution",
		"battles": [{"hex": {"q": 3, "r": 4}, "engagements": [{"attacker_unit_id": "p1_platoon", "defender_unit_id": "p2_platoon", "attacker_owner": 0, "defender_owner": 1, "defender_hex": {"q": 3, "r": 4}}], "attacker_unit_ids": ["p1_platoon"], "defender_unit_ids": ["p2_platoon"]}]
	}

func _unit_tree(id: String, name: String, size: String, children: Array) -> Dictionary:
	return {"id": id, "display_name": name, "type": "infantry", "role": "infantry", "size": size, "status": "alive", "designation": {}, "vehicles": [], "children": children}

func _gameplay_formation(id: String, owner: int, hex: Vector2i, size: String) -> Dictionary:
	return {"id": id, "display_name": id, "designation": {}, "owner": owner, "hex": hex, "size": size, "type": "infantry", "role": "infantry", "status": "alive"}

func _find_unit(node: Dictionary, unit_id: String) -> Dictionary:
	if String(node.get("id", "")) == unit_id:
		return node
	var children := node.get("children", []) as Array
	for child in children:
		if typeof(child) != TYPE_DICTIONARY:
			continue
		var found := _find_unit(child as Dictionary, unit_id)
		if not found.is_empty():
			return found
	return {}

func _mark_unit_dead(root: Dictionary, unit_id: String) -> void:
	var unit := _find_unit(root, unit_id)
	if unit.is_empty():
		return
	unit["status"] = "dead"

func _find_tree_item_by_unit_id(item: TreeItem, unit_id: String) -> TreeItem:
	if item == null:
		return null
	var metadata: Variant = item.get_metadata(0)
	if metadata != null and str(metadata) == unit_id:
		return item
	for child_index in range(item.get_child_count()):
		var found := _find_tree_item_by_unit_id(item.get_child(child_index), unit_id)
		if found != null:
			return found
	return null

func _assert_tree_item_contains(root: TreeItem, unit_id: String, expected_text: String, message: String) -> void:
	var item := _find_tree_item_by_unit_id(root, unit_id)
	_assert_true(item != null, "%s: missing unit %s" % [message, unit_id])
	if item != null:
		var actual_text := String(item.get_text(0))
		_assert_true(actual_text.contains(expected_text), "%s: %s" % [message, actual_text])

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
