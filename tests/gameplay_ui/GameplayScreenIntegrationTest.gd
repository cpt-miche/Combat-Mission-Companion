extends SceneTree

const GAMEPLAY_SCREEN_SCENE := preload("res://scenes/gameplay/GameplayScreen.tscn")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_issue_move_order_succeeds_for_adjacent_hex()

	if _failures.is_empty():
		print("GameplayScreen integration tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)

func _test_issue_move_order_succeeds_for_adjacent_hex() -> void:
	_reset_state()
	var screen := _spawn_screen()

	var succeeded: bool = screen._issue_move_order("u1", Vector2i(1, 0))
	_assert_true(succeeded, "Expected _issue_move_order to succeed for adjacent target hex.")

	_cleanup_screen(screen)

func _reset_state() -> void:
	GameState.reset()
	GameState.set_phase(GameState.Phase.GAMEPLAY)
	GameState.players = [
		{"name": "Player 1", "division_tree": {}, "deployments": {}, "controller": "human"},
		{"name": "Player 2", "division_tree": {}, "deployments": {}, "controller": "human"}
	]
	GameState.gameplay_units = {
		"u1": {
			"id": "u1",
			"name": "1st Platoon",
			"size": "platoon",
			"status": "alive",
			"hex": Vector2i(0, 0),
			"faction": "player",
			"can_act": true,
			"children": []
		}
	}
	GameState.current_player_idx = 0

func _spawn_screen() -> Control:
	var screen: Control = GAMEPLAY_SCREEN_SCENE.instantiate()
	get_root().add_child(screen)
	return screen

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
