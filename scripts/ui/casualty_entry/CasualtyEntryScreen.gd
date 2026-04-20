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
		for child in entry.get("children", []):
			if typeof(child) != TYPE_DICTIONARY:
				continue
			var child_item := own_tree.create_item(parent)
			child_item.set_text(0, "%s losses: %d" % [String(child.get("unit_id", "Child")), int(child.get("losses", 0))])
			child_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			child_item.set_editable(0, true)
			child_item.set_checked(0, false)

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
	GameState.pending_casualties = {}
	GameState.set_phase(GameState.Phase.GAMEPLAY)
