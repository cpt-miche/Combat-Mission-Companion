extends Control

const DIVISION_BUILDER_SCENE := preload("res://scenes/division_builder/DivisionBuilderScreen.tscn")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_test_ai_catalog_allows_german_infantry_division()
	_test_ai_catalog_allows_german_infantry_regiment()

	if _failures.is_empty():
		print("DivisionBuilderScreen integration tests passed.")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_ai_catalog_allows_german_infantry_division() -> void:
	var screen := _spawn_ai_builder_screen()
	var division_item := _find_template_item(screen.unit_tree.get_root(), "Infantry Division", UnitType.Value.INFANTRY, UnitSize.Value.DIVISION)
	_assert_true(division_item != null, "AI Germany catalog should include an infantry division template.")
	_assert_true(division_item != null and division_item.is_selectable(0), "AI Germany infantry division should be selectable from the army root.")

	_select_catalog_item(screen, division_item)
	screen._on_add_unit_pressed()

	_assert_equal(1, screen._root_unit.children.size(), "Adding AI Germany infantry division should create one division under the army root.")
	_assert_equal(UnitSize.Value.DIVISION, screen._root_unit.children[0].size, "Added AI Germany template should be a division.")
	_assert_false(String(screen.pending_unit_label.text).begins_with("Cannot add"), "Adding AI Germany infantry division should not show a validation failure.")
	_cleanup_screen(screen)

func _test_ai_catalog_allows_german_infantry_regiment() -> void:
	var screen := _spawn_ai_builder_screen()
	var regiment_item := _find_template_item(screen.unit_tree.get_root(), "Infantry Regiment", UnitType.Value.INFANTRY, UnitSize.Value.REGIMENT)
	_assert_true(regiment_item != null, "AI Germany catalog should include an infantry regiment template.")
	_assert_true(regiment_item != null and regiment_item.is_selectable(0), "AI Germany infantry regiment should be selectable from the army root.")

	_select_catalog_item(screen, regiment_item)
	screen._on_add_unit_pressed()

	_assert_equal(1, screen._root_unit.children.size(), "Adding AI Germany infantry regiment should create one regiment under the army root.")
	_assert_equal(UnitSize.Value.REGIMENT, screen._root_unit.children[0].size, "Added AI Germany template should be a regiment.")
	_assert_false(String(screen.pending_unit_label.text).begins_with("Cannot add"), "Adding AI Germany infantry regiment should not show a validation failure.")
	_cleanup_screen(screen)

func _spawn_ai_builder_screen() -> Control:
	GameState.reset()
	GameState.selected_nation_id = "usa"
	UnitCatalog.reload()
	var screen: Control = DIVISION_BUILDER_SCENE.instantiate()
	add_child(screen)
	screen._builder_player_index = 1
	screen._initialize_organization(screen._default_nation_for_builder_player(1))
	screen._pending_unit_data.clear()
	screen._refresh_all()
	return screen

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _select_catalog_item(screen: Control, item: TreeItem) -> void:
	screen.unit_tree.set_selected(item, 0)
	screen._on_unit_tree_selected()

func _find_template_item(item: TreeItem, display_name: String, unit_type: UnitType.Value, unit_size: UnitSize.Value) -> TreeItem:
	if item == null:
		return null
	var child := item.get_first_child()
	while child != null:
		var metadata: Variant = child.get_metadata(0)
		if typeof(metadata) == TYPE_DICTIONARY:
			var template_data := metadata as Dictionary
			if String(template_data.get("name", "")) == display_name and int(template_data.get("type", -1)) == int(unit_type) and int(template_data.get("size", -1)) == int(unit_size):
				return child
		var nested := _find_template_item(child, display_name, unit_type, unit_size)
		if nested != null:
			return nested
		child = child.get_next()
	return null

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
