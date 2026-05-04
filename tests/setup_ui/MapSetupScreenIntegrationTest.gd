extends SceneTree

const MAP_SETUP_SCENE := preload("res://scenes/map_setup/MapSetupScreen.tscn")
const OperationalAIService = preload("res://scripts/systems/operational_ai/OperationalAIService.gd")
const MatchSetupTypes = preload("res://scripts/core/MatchSetupTypes.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_setup_screen_stores_selected_doctrine_and_difficulty()
	_test_selected_profile_persists_into_match_state_and_operational_config()

	if _failures.is_empty():
		print("MapSetupScreen integration tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)

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
	var setup := GameState.match_setup.duplicate(true)
	_assert_equal("defensive", String(setup.get("ai_doctrine", "")), "Match setup payload should persist doctrine")
	_assert_equal("easy", String(setup.get("difficulty", "")), "Match setup payload should persist difficulty")
	GameState.players = [
		{"id": "p1", "name": "Player", "controller": "human"},
		{"id": "p2", "name": "AI", "controller": "ai", "doctrine": "defensive"}
	]
	var ai_cfg := OperationalAIService._resolve_ai_config(GameState.players[1], {})
	_assert_equal("security", String(ai_cfg.get("doctrine", "")), "Operational AI profile should use selected doctrine mapping")
	_assert_equal("easy", String(ai_cfg.get("difficulty", "")), "Operational AI profile should use selected difficulty")
	_cleanup_screen(screen)

func _reset_state() -> void:
	GameState.reset()
	GameState.set_phase(GameState.Phase.MAP_SETUP)
	GameState.selected_ai_doctrine = "balanced"
	GameState.selected_difficulty = "medium"
	GameState.map_columns = 2
	GameState.map_rows = 2
	GameState.terrain_map = {}
	GameState.players = []

func _spawn_screen() -> Control:
	var screen: Control = MAP_SETUP_SCENE.instantiate()
	get_root().add_child(screen)
	return screen

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
