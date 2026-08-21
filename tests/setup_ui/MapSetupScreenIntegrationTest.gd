extends Node

const MAP_SETUP_SCENE := preload("res://scenes/map_setup/MapSetupScreen.tscn")
const OperationalAIService = preload("res://scripts/systems/operational_ai/OperationalAIService.gd")
const MatchSetupTypes = preload("res://scripts/core/MatchSetupTypes.gd")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_test_setup_screen_stores_selected_doctrine_and_difficulty()
	_test_selected_profile_persists_into_match_state_and_operational_config()
	_test_confirm_territories_requires_player_two_hex()
	_test_confirm_territories_advances_when_player_two_has_hex()
	_test_key_objectives_persist_and_old_maps_are_rejected()

	if _failures.is_empty():
		print("MapSetupScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_setup_screen_stores_selected_doctrine_and_difficulty() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._on_doctrine_selected(MatchSetupTypes.AI_DOCTRINES.find("aggressive"))
	screen._on_difficulty_selected(MatchSetupTypes.DIFFICULTIES.find("hard"))
	_assert_equal("aggressive", GameState.selected_ai_doctrine, "Selecting doctrine should store selected_ai_doctrine")
	_assert_equal("hard", GameState.selected_difficulty, "Selecting difficulty should store selected_difficulty")
	_assert_true(String(screen.setup_summary_label.text).contains("Doctrine Aggressive"), "Setup summary should include selected doctrine")
	_assert_true(String(screen.setup_summary_label.text).contains("Difficulty Hard"), "Setup summary should include selected difficulty")
	_cleanup_screen(screen)

func _test_selected_profile_persists_into_match_state_and_operational_config() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._on_doctrine_selected(MatchSetupTypes.AI_DOCTRINES.find("defensive"))
	screen._on_difficulty_selected(MatchSetupTypes.DIFFICULTIES.find("easy"))
	screen._sync_game_state_map_data()
	var setup: Dictionary = screen._build_map_payload("integration-test-map")
	_assert_equal("defensive", String(setup.get("ai_doctrine", "")), "Map payload should persist doctrine")
	_assert_equal("easy", String(setup.get("difficulty", "")), "Map payload should persist difficulty")
	GameState.players = [
		{"id": "p1", "name": "Player", "controller": "human"},
		{"id": "p2", "name": "AI", "controller": "ai", "doctrine": "defensive"}
	]
	var ai_cfg := OperationalAIService._resolve_ai_config(GameState.players[1], {})
	_assert_equal("security", String(ai_cfg.get("doctrine", "")), "Operational AI profile should use selected doctrine mapping")
	_assert_equal("easy", String(ai_cfg.get("difficulty", "")), "Operational AI profile should use selected difficulty")
	_cleanup_screen(screen)

func _test_confirm_territories_requires_player_two_hex() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1
	}
	screen._on_confirm_territories_pressed()
	_assert_equal(GameState.Phase.MAP_SETUP, GameState.current_phase, "Submitting map territory should stay in map setup when Player 2 owns no hexes.")
	_assert_true(String(screen.map_status_label.text).contains("Player 2"), "Missing Player 2 territory should be reported on the map setup screen.")
	_cleanup_screen(screen)

func _test_confirm_territories_advances_when_player_two_has_hex() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._territory_map = {
		"0,0": GameState.TerritoryOwnership.PLAYER_1,
		"1,0": GameState.TerritoryOwnership.PLAYER_2
	}
	screen._on_confirm_territories_pressed()
	_assert_equal(GameState.Phase.DEPLOYMENT_P1, GameState.current_phase, "Submitting map territory should start deployment when Player 2 owns at least one hex.")
	_cleanup_screen(screen)

func _test_key_objectives_persist_and_old_maps_are_rejected() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._on_hex_objective_painted(Vector2i(0, 0), "primary")
	screen._on_hex_objective_painted(Vector2i(1, 1), "secondary")
	var payload: Dictionary = screen._build_map_payload("objective-map")
	_assert_equal({"priority": "primary"}, (payload.get("objectives", {}) as Dictionary).get("0,0", {}), "Primary objectives should be included in saved map payloads")
	_assert_equal({"priority": "secondary"}, (payload.get("objectives", {}) as Dictionary).get("1,1", {}), "Secondary objectives should be included in saved map payloads")
	_assert_true(GameState.apply_map_payload(payload), "Current map payloads should load")
	_assert_equal(2, GameState.key_objectives.size(), "Loading a current map should restore authored objectives")
	var objectives_before := GameState.key_objectives.duplicate(true)
	_assert_false(GameState.apply_map_payload({"version": 1, "name": "old", "grid": {"columns": 8, "rows": 8}, "terrain": {}, "territory": {}, "objectives": {}, "ai_doctrine": "balanced", "difficulty": "medium"}), "Version-one maps should be rejected")
	_assert_equal(objectives_before, GameState.key_objectives, "Rejected maps should not mutate current map state")
	_cleanup_screen(screen)

func _reset_state() -> void:
	GameState.reset()
	GameState.set_phase(GameState.Phase.MAP_SETUP)
	GameState.selected_ai_doctrine = "balanced"
	GameState.selected_difficulty = "medium"
	GameState.map_columns = 8
	GameState.map_rows = 8
	GameState.terrain_map = {}
	GameState.players = []

func _spawn_screen() -> Control:
	var screen: Control = MAP_SETUP_SCENE.instantiate()
	get_tree().root.add_child(screen)
	return screen

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _assert_false(value: bool, message: String) -> void:
	if value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
