extends Control

const DETAIL_SIZES := {"squad": true, "section": true}

@onready var own_tree: Tree = %OwnCasualtyTree
@onready var enemy_tree: Tree = %EnemyCasualtyTree
@onready var submit_button: Button = %SubmitButton

func _ready() -> void:
	_build_own_tree()
	_build_enemy_tree()
	submit_button.pressed.connect(_on_submit_pressed)

func _build_own_tree() -> void:
	_build_casualty_tree(own_tree, _resolving_player(), "No player units were listed for this battle.")

func _build_enemy_tree() -> void:
	_build_casualty_tree(enemy_tree, _opposing_player(), "No enemy units were listed for this battle.")

func _resolving_player() -> int:
	return clampi(int(GameState.pending_casualties.get("resolving_player", 0)), 0, 1)

func _opposing_player() -> int:
	return 1 - _resolving_player()

func _build_casualty_tree(tree: Tree, owner: int, empty_message: String) -> void:
	tree.clear()
	tree.columns = 1
	tree.select_mode = Tree.SELECT_MULTI
	tree.hide_root = true
	var root := tree.create_item()
	var engaged_ids := _engaged_unit_ids_for_owner(owner)
	if engaged_ids.is_empty():
		var empty_item := tree.create_item(root)
		empty_item.set_text(0, empty_message)
		empty_item.set_selectable(0, false)
		return
	for unit_id in engaged_ids:
		var unit_node := _find_player_unit_node(owner, unit_id)
		var display_name := unit_id
		if not unit_node.is_empty():
			display_name = String(unit_node.get("name", unit_node.get("display_name", unit_id)))
		var parent := tree.create_item(root)
		parent.set_text(0, "%s (%s)" % [display_name, unit_id])
		parent.set_metadata(0, unit_id)
		var detail_count := _add_detail_casualty_items(parent, unit_node)
		if detail_count == 0:
			_make_checkable(parent, unit_id)
		else:
			parent.collapsed = false
	if not tree.check_propagated_to_item.is_connected(_on_tree_check_propagated):
		tree.check_propagated_to_item.connect(_on_tree_check_propagated)

func _on_tree_check_propagated(item: TreeItem, column: int) -> void:
	if column != 0 or item == null:
		return
	if item.get_parent() == null:
		return
	var checked := item.is_checked(0)
	for i in range(item.get_child_count()):
		item.get_child(i).set_checked(0, checked)

func _add_detail_casualty_items(parent: TreeItem, unit_node: Dictionary) -> int:
	if unit_node.is_empty():
		return 0
	var details: Array[Dictionary] = []
	_collect_squad_section_nodes(unit_node, details)
	for detail in details:
		var detail_id := String(detail.get("id", ""))
		if detail_id.is_empty():
			continue
		var item := parent.create_child()
		var detail_name := String(detail.get("name", detail.get("display_name", detail_id)))
		var detail_size := String(detail.get("size", "unit")).capitalize()
		item.set_text(0, "%s - %s" % [detail_name, detail_size])
		_make_checkable(item, detail_id)
	return details.size()

func _make_checkable(item: TreeItem, unit_id: String) -> void:
	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	item.set_editable(0, true)
	item.set_checked(0, false)
	item.set_metadata(0, unit_id)

func _collect_squad_section_nodes(node: Dictionary, output: Array[Dictionary]) -> void:
	var size_name := String(node.get("size", node.get("formation_size", ""))).strip_edges().to_lower()
	if DETAIL_SIZES.has(size_name):
		output.append(node)
		return
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	var children := children_variant as Array
	for child_variant in children:
		if typeof(child_variant) == TYPE_DICTIONARY:
			_collect_squad_section_nodes(child_variant as Dictionary, output)

func _engaged_unit_ids_for_owner(owner: int) -> Array[String]:
	var unique := {}
	var engagements := GameState.pending_casualties.get("engagements", []) as Array
	for engagement_variant in engagements:
		if typeof(engagement_variant) != TYPE_DICTIONARY:
			continue
		var engagement := engagement_variant as Dictionary
		if int(engagement.get("attacker_owner", -1)) == owner:
			unique[String(engagement.get("attacker_unit_id", ""))] = true
		if int(engagement.get("defender_owner", -1)) == owner:
			unique[String(engagement.get("defender_unit_id", ""))] = true
	var ids: Array[String] = []
	for unit_id in unique.keys():
		var typed_id := String(unit_id)
		if not typed_id.is_empty():
			ids.append(typed_id)
	ids.sort()
	return ids

func _find_player_unit_node(owner: int, unit_id: String) -> Dictionary:
	if owner < 0 or owner >= GameState.players.size():
		return {}
	var player := GameState.players[owner] as Dictionary
	var root := player.get("division_tree", {}) as Dictionary
	return _find_unit_node_recursive(root, unit_id)

func _find_unit_node_recursive(node: Dictionary, unit_id: String) -> Dictionary:
	if node.is_empty():
		return {}
	if String(node.get("id", "")) == unit_id:
		return node
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return {}
	var children := children_variant as Array
	for child_variant in children:
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var found := _find_unit_node_recursive(child_variant as Dictionary, unit_id)
		if not found.is_empty():
			return found
	return {}

func _on_submit_pressed() -> void:
	var confirmed_unit_ids := _confirmed_casualty_unit_ids()
	for unit_id in confirmed_unit_ids:
		GameState.mark_unit_status(unit_id, "dead")
	GameState.pending_casualties = {}
	GameState.set_phase(GameState.Phase.GAMEPLAY)

func _confirmed_casualty_unit_ids() -> Array[String]:
	var unique_ids := {}
	_collect_checked_unit_ids(own_tree.get_root(), unique_ids)
	_collect_checked_unit_ids(enemy_tree.get_root(), unique_ids)
	var confirmed_ids: Array[String] = []
	for key in unique_ids.keys():
		confirmed_ids.append(String(key))
	confirmed_ids.sort()
	return confirmed_ids

func _confirmed_own_casualty_unit_ids() -> Array[String]:
	var unique_ids := {}
	_collect_checked_unit_ids(own_tree.get_root(), unique_ids)
	var confirmed_ids: Array[String] = []
	for key in unique_ids.keys():
		confirmed_ids.append(String(key))
	confirmed_ids.sort()
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
