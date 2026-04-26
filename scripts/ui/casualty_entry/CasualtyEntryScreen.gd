extends Control

@onready var own_tree: Tree = %OwnCasualtyTree
@onready var enemy_list: VBoxContainer = %EnemyCasualtyList
@onready var submit_button: Button = %SubmitButton

func _ready() -> void:
	_build_own_tree()
	_build_enemy_list()
	submit_button.pressed.connect(_on_submit_pressed)

func _build_own_tree() -> void:
	own_tree.clear()
	own_tree.columns = 1
	own_tree.select_mode = Tree.SELECT_MULTI
	own_tree.hide_root = true
	var root := own_tree.create_item()
	var own_entries := GameState.pending_casualties.get("own", []) as Array
	for entry in own_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var parent := own_tree.create_item(root)
		parent.set_text(0, "%s (confirm casualty)" % String(entry.get("unit_id", "Unknown")))
		parent.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		parent.set_editable(0, true)
		parent.set_checked(0, false)
		parent.set_metadata(0, String(entry.get("unit_id", "")))
		for child in entry.get("children", []):
			if typeof(child) != TYPE_DICTIONARY:
				continue
			var child_item := own_tree.create_item(parent)
			var segment := String(child.get("segment", "")).strip_edges()
			var segment_label := " %s" % segment if not segment.is_empty() else ""
			child_item.set_text(0, "%s%s losses: %d" % [String(child.get("unit_id", "Child")), segment_label, int(child.get("losses", 0))])
			child_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			child_item.set_editable(0, true)
			child_item.set_checked(0, false)
			child_item.set_metadata(0, String(child.get("unit_id", "")))

	own_tree.check_propagated_to_item.connect(_on_tree_check_propagated)

func _on_tree_check_propagated(item: TreeItem, column: int) -> void:
	if column != 0 or item == null:
		return
	if item.get_parent() == null:
		return
	var checked := item.is_checked(0)
	for i in range(item.get_child_count()):
		item.get_child(i).set_checked(0, checked)

func _build_enemy_list() -> void:
	for child in enemy_list.get_children():
		child.queue_free()
	var known := GameState.pending_casualties.get("known_enemy_units", []) as Array
	var enemy_entries := GameState.pending_casualties.get("enemy", []) as Array
	for unit_id in known:
		var losses := 0
		for entry in enemy_entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if String(entry.get("unit_id", "")) == String(unit_id):
				losses = int(entry.get("losses", 0))
		var checkbox := CheckBox.new()
		checkbox.text = "%s estimated losses: %d" % [String(unit_id), losses]
		enemy_list.add_child(checkbox)

func _on_submit_pressed() -> void:
	var confirmed_unit_ids := _confirmed_own_casualty_unit_ids()
	for unit_id in confirmed_unit_ids:
		GameState.mark_unit_status(unit_id, "dead")
	GameState.pending_casualties = {}
	GameState.set_phase(GameState.Phase.GAMEPLAY)

func _confirmed_own_casualty_unit_ids() -> Array[String]:
	var confirmed_ids: Array[String] = []
	var root := own_tree.get_root()
	if root == null:
		return confirmed_ids
	var unique_ids := {}
	_collect_checked_unit_ids(root, unique_ids)
	for key in unique_ids.keys():
		confirmed_ids.append(String(key))
	return confirmed_ids

func _collect_checked_unit_ids(item: TreeItem, output: Dictionary) -> void:
	if item == null:
		return
	if item.get_parent() != null and item.is_checked(0):
		var unit_id := String(item.get_metadata(0))
		if not unit_id.is_empty():
			output[unit_id] = true
	for i in range(item.get_child_count()):
		_collect_checked_unit_ids(item.get_child(i), output)
