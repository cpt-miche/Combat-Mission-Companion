extends SceneTree

const CASUALTY_SCREEN_SCENE := preload("res://scenes/screens/CasualtyEntryScreen.tscn")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_engagements_expand_to_squad_section_casualty_items()

	if _failures.is_empty():
		print("CasualtyEntryScreen integration tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)

func _test_engagements_expand_to_squad_section_casualty_items() -> void:
	_reset_state()
	var screen: Control = CASUALTY_SCREEN_SCENE.instantiate()
	get_root().add_child(screen)
	await process_frame
	var own_root: TreeItem = screen.own_tree.get_root()
	var own_unit: TreeItem = own_root.get_first_child()
	_assert_true(own_unit != null, "Player casualty tree should include engaged player unit")
	_assert_equal(2, own_unit.get_child_count(), "Player engaged platoon should expand to squad/section casualty choices")
	var enemy_root: TreeItem = screen.enemy_tree.get_root()
	var enemy_unit: TreeItem = enemy_root.get_first_child()
	_assert_true(enemy_unit != null, "Enemy casualty tree should include engaged enemy unit")
	_assert_equal(1, enemy_unit.get_child_count(), "Enemy engaged platoon should expand to squad/section casualty choices")
	own_unit.get_child(0).set_checked(0, true)
	screen._on_submit_pressed()
	var p1_tree := (GameState.players[0] as Dictionary).get("division_tree", {}) as Dictionary
	var casualty := _find_unit(p1_tree, "p1_squad_a")
	_assert_equal("dead", String(casualty.get("status", "")), "Confirmed squad casualty should mark the squad dead in the formation tree")
	screen.queue_free()

func _reset_state() -> void:
	GameState.reset()
	GameState.players = [
		{"name":"P1", "controller":"human", "division_tree": _unit_tree("p1_platoon", "P1 Platoon", "platoon", [
			_unit_tree("p1_squad_a", "1st Squad", "squad", []),
			_unit_tree("p1_section_b", "Weapons Section", "section", [])
		]), "deployments": {}},
		{"name":"P2", "controller":"human", "division_tree": _unit_tree("p2_platoon", "P2 Platoon", "platoon", [
			_unit_tree("p2_squad_a", "Enemy Squad", "squad", [])
		]), "deployments": {}}
	]
	GameState.pending_casualties = {
		"engagements": [{
			"attacker_unit_id": "p1_platoon",
			"defender_unit_id": "p2_platoon",
			"attacker_owner": 0,
			"defender_owner": 1
		}]
	}

func _unit_tree(id: String, name: String, size: String, children: Array) -> Dictionary:
	return {"id": id, "name": name, "size": size, "status": "alive", "children": children}

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

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
