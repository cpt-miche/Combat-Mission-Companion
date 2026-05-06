extends Node

const GAMEPLAY_SCREEN_SCENE := preload("res://scenes/screens/GameplayScreen.tscn")
const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_test_selection_exposes_order_actions()
	_test_mode_based_order_issuing()
	_test_left_click_move_tile_issues_move_order()
	_test_stack_cap_feedback()
	_test_empty_execution_queue_advances_turn()

	if _failures.is_empty():
		print("GameplayScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_selection_exposes_order_actions() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._update_order_action_panel()
	_assert_true(screen.order_action_panel.visible, "Selecting a friendly unit should show Move/Attack/Dig In panel")
	_assert_equal("Move", screen.move_button.text, "Move button text should be visible")
	_assert_equal("Attack", screen.attack_button.text, "Attack button text should be visible")
	_assert_equal("Dig In", screen.dig_in_button.text, "Dig In button text should be visible")
	_cleanup_screen(screen)

func _test_mode_based_order_issuing() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._on_dig_in_mode_pressed()
	_assert_true(screen._orders.has("u1"), "Dig In mode should issue order for selected unit")
	_assert_equal(OrderSystem.OrderType.DIG_IN, int((screen._orders["u1"] as Dictionary).get("type", -1)), "Dig In mode should create DIG_IN order")
	_assert_true(String(screen.info_label.text).contains("Dig In order created"), "Dig In mode should show order feedback")
	_cleanup_screen(screen)

func _test_stack_cap_feedback() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	var succeeded: bool = screen._issue_move_order("u1", Vector2i(1, 0))
	_assert_true(not succeeded, "Move order should be blocked when destination stack cap exceeded")
	_assert_true(String(screen.info_label.text).contains("Stack exceeds"), "Blocked stack move should explain stack-cap feedback")
	_cleanup_screen(screen)


func _test_empty_execution_queue_advances_turn() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._on_dig_in_mode_pressed()
	screen._on_end_turn_pressed()
	_assert_true(screen._execution_queue.is_empty(), "Dig-in-only resolution should have no animation steps")
	_assert_equal(1, GameState.active_player, "Dig-in-only resolution should advance to the next player")
	_assert_equal(2, GameState.current_turn, "Dig-in-only resolution should increment the turn counter")
	_assert_equal(GameState.Phase.CASUALTY_ENTRY, GameState.current_phase, "Dig-in-only resolution should still show casualty entry")
	_cleanup_screen(screen)

func _test_left_click_move_tile_issues_move_order() -> void:
	_reset_state()
	var screen := _spawn_screen()
	screen._selected_unit_id = "u1"
	screen._set_order_mode(screen.OrderMode.MOVE)
	var target_hex := Vector2i(0, 1)
	var click_position: Vector2 = screen._world_to_screen(screen._hex_center(target_hex.x, target_hex.y))
	screen._handle_left_press(click_position)
	screen._handle_left_release(click_position)
	_assert_true(screen._orders.has("u1"), "Left-clicking a destination in Move mode should issue a move order for selected unit")
	var order := screen._orders["u1"] as Dictionary
	_assert_equal(OrderSystem.OrderType.MOVE, int(order.get("type", -1)), "Left-click move should create MOVE order")
	var path := order.get("path", []) as Array
	_assert_true(path.size() >= 2, "Left-click move order should include a traversable path")
	_cleanup_screen(screen)

func _reset_state() -> void:
	GameState.reset()
	GameState.set_phase(GameState.Phase.GAMEPLAY)
	GameState.active_player = 0 # GameplayScreen reads GameState.active_player in _ready(); keep deterministic active side for tests.
	GameState.players = [
		{"name":"P1","division_tree":{},"deployments":{},"controller":"human"},
		{"name":"P2","division_tree":{},"deployments":{},"controller":"human"}
	]
	GameState.gameplay_units = {
		"u1": {"id":"u1","owner":0,"hex":Vector2i(0,0),"size":"company","status":"alive"},
		"a": {"id":"a","owner":0,"hex":Vector2i(1,0),"size":"company","status":"alive"},
		"b": {"id":"b","owner":0,"hex":Vector2i(1,0),"size":"company","status":"alive"},
		"c": {"id":"c","owner":0,"hex":Vector2i(1,0),"size":"company","status":"alive"},
		"d": {"id":"d","owner":0,"hex":Vector2i(1,0),"size":"company","status":"alive"}
	}
	GameState.terrain_map = {}

func _spawn_screen() -> Control:
	var screen: Control = GAMEPLAY_SCREEN_SCENE.instantiate()
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

func _fail(message: String) -> void:
	_failures.append(message)
