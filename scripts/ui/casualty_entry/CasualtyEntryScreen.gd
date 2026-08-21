extends Control

signal resolution_state_changed

const DETAIL_SIZES := {"squad": true, "section": true}
const UnitHealthFormatter = preload("res://scripts/domain/units/UnitHealthFormatter.gd")
const FormationHierarchy = preload("res://scripts/domain/units/FormationHierarchy.gd")
const BattleOutcomeResolver = preload("res://scripts/systems/BattleOutcomeResolver.gd")
@onready var dimmer: ColorRect = %Dimmer
@onready var screen_margin: MarginContainer = $ScreenMargin
@onready var modal_panel: PanelContainer = %ModalPanel
@onready var title_label: Label = %Title
@onready var progress_label: Label = %ProgressLabel
@onready var hex_label: Label = %HexLabel
@onready var instructions_label: Label = %InstructionsLabel
@onready var outcome_container: VBoxContainer = %OutcomeContainer
@onready var major_victory_button: CheckButton = %MajorAttackerVictoryButton
@onready var victory_button: CheckButton = %AttackerVictoryButton
@onready var defeat_button: CheckButton = %AttackerDefeatButton
@onready var prep_content: ScrollContainer = %PrepContent
@onready var prep_label: RichTextLabel = %PrepLabel
@onready var battle_content: HBoxContainer = %BattleContent
@onready var own_label: Label = %OwnLabel
@onready var enemy_label: Label = %EnemyLabel
@onready var own_tree: Tree = %OwnCasualtyTree
@onready var enemy_tree: Tree = %EnemyCasualtyTree
@onready var summary_scroll: ScrollContainer = %SummaryScroll
@onready var summary_label: RichTextLabel = %SummaryLabel
@onready var submit_button: Button = %SubmitButton

var _showing_summary := false
var _completion_requested := false
var _announcement_layout_active := false
var _dragging_announcement := false

func _ready() -> void:
	_prepare_resolution_payload()
	_configure_outcome_buttons()
	submit_button.pressed.connect(_on_submit_pressed)
	_show_current_battle_or_summary()
	submit_button.grab_focus()

func _prepare_resolution_payload() -> void:
	var battles := GameState.pending_casualties.get("battles", []) as Array
	GameState.pending_casualties["battles"] = battles
	if not GameState.pending_casualties.has("current_battle_index"):
		GameState.pending_casualties["current_battle_index"] = 0
	if not GameState.pending_casualties.has("results"):
		GameState.pending_casualties["results"] = []
	if not GameState.pending_casualties.has("resolving_turn"):
		GameState.pending_casualties["resolving_turn"] = maxi(GameState.current_turn - 1, 1)
	if not GameState.pending_casualties.has("workflow_stage"):
		GameState.pending_casualties["workflow_stage"] = "announcement" if not battles.is_empty() else "summary"
	if not GameState.pending_casualties.has("selected_outcomes"):
		GameState.pending_casualties["selected_outcomes"] = {}
	if not GameState.pending_casualties.has("outcome_rng_seed"):
		GameState.pending_casualties["outcome_rng_seed"] = int(GameState.pending_casualties.get("resolving_turn", 1)) * 104729 + 17

func _configure_outcome_buttons() -> void:
	var group := ButtonGroup.new()
	for button in [major_victory_button, victory_button, defeat_button]:
		button.button_group = group
	major_victory_button.pressed.connect(_on_outcome_selected.bind(BattleOutcomeResolver.OUTCOME_MAJOR_ATTACKER_VICTORY))
	victory_button.pressed.connect(_on_outcome_selected.bind(BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY))
	defeat_button.pressed.connect(_on_outcome_selected.bind(BattleOutcomeResolver.OUTCOME_ATTACKER_DEFEAT))

func _show_current_battle_or_summary() -> void:
	var battles := GameState.pending_casualties.get("battles", []) as Array
	var workflow_stage := String(GameState.pending_casualties.get("workflow_stage", "resolution"))
	if battles.is_empty() or workflow_stage == "summary":
		_show_summary()
		return
	var battle_index := int(GameState.pending_casualties.get("current_battle_index", 0))
	if battle_index >= battles.size():
		_show_summary()
		return
	var battle := battles[battle_index] as Dictionary
	if workflow_stage == "announcement":
		_show_announcement(battle, battle_index, battles.size())
		return
	if workflow_stage == "prep":
		_show_battle_prep(battle, battle_index, battles.size())
		return
	_show_battle(battle, battle_index, battles.size())

func _show_announcement(battle: Dictionary, battle_index: int, battle_count: int) -> void:
	_apply_announcement_layout()
	_showing_summary = false
	title_label.text = "Battle Commences"
	progress_label.text = "Battle %d of %d — Turn %d" % [battle_index + 1, battle_count, int(GameState.pending_casualties.get("resolving_turn", 1))]
	hex_label.visible = true
	hex_label.text = "Battle commences on tile %s" % _battle_hex_text(battle)
	instructions_label.visible = true
	instructions_label.text = "The map has focused on and highlighted the battle location."
	prep_content.visible = false
	battle_content.visible = false
	outcome_container.visible = false
	summary_scroll.visible = false
	submit_button.text = "Begin"

func _show_battle_prep(battle: Dictionary, battle_index: int, battle_count: int) -> void:
	_apply_full_layout()
	_showing_summary = false
	title_label.text = "Battle Prep"
	progress_label.text = "Battle %d of %d — Turn %d" % [battle_index + 1, battle_count, int(GameState.pending_casualties.get("resolving_turn", 1))]
	hex_label.visible = true
	hex_label.text = "Battle Tile: %s" % _battle_hex_text(battle)
	instructions_label.visible = true
	instructions_label.text = "Review the formations and defensive posture before resolving the battle."
	prep_content.visible = true
	prep_label.text = _battle_prep_text(battle)
	battle_content.visible = false
	outcome_container.visible = false
	summary_scroll.visible = false
	submit_button.text = "Go to Battle Resolution Screen"

func _show_battle(battle: Dictionary, battle_index: int, battle_count: int) -> void:
	_apply_full_layout()
	_showing_summary = false
	title_label.text = "Battle Resolution"
	progress_label.text = "Battle %d of %d" % [battle_index + 1, battle_count]
	hex_label.visible = true
	hex_label.text = "Battle Hex: %s" % _battle_hex_text(battle)
	instructions_label.visible = true
	instructions_label.text = "Resolve this battle outside the game, then check every squad or section lost on both sides."
	prep_content.visible = false
	outcome_container.visible = true
	battle_content.visible = true
	summary_scroll.visible = false
	own_label.text = "%s casualties (check squads/sections lost)" % _player_display_name(_resolving_player())
	enemy_label.text = "%s casualties (check squads/sections lost)" % _player_display_name(_opposing_player())
	_build_casualty_tree(own_tree, _resolving_player(), battle, "No player units were listed for this battle.")
	_build_casualty_tree(enemy_tree, _opposing_player(), battle, "No enemy units were listed for this battle.")
	submit_button.text = "Confirm Casualties & Review Summary" if battle_index == battle_count - 1 else "Confirm Casualties & Next Battle"
	_restore_outcome_selection(battle_index)

func _show_summary() -> void:
	_apply_full_layout()
	_showing_summary = true
	GameState.pending_casualties["workflow_stage"] = "summary"
	title_label.text = "Combat Summary"
	progress_label.text = "Turn %d — %s" % [int(GameState.pending_casualties.get("resolving_turn", 1)), _player_display_name(_resolving_player())]
	hex_label.visible = false
	instructions_label.visible = false
	battle_content.visible = false
	prep_content.visible = false
	outcome_container.visible = false
	summary_scroll.visible = true
	summary_label.text = _combat_summary_text()
	submit_button.text = "Continue to Next Turn"
	submit_button.disabled = false

func _apply_announcement_layout() -> void:
	_announcement_layout_active = true
	_dragging_announcement = false
	dimmer.color.a = 0.0
	screen_margin.set_anchors_preset(Control.PRESET_CENTER_TOP)
	screen_margin.offset_left = -210.0
	screen_margin.offset_top = 24.0
	screen_margin.offset_right = 210.0
	screen_margin.offset_bottom = 244.0

func _apply_full_layout() -> void:
	_announcement_layout_active = false
	_dragging_announcement = false
	dimmer.color.a = 0.55
	screen_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_margin.offset_left = 64.0
	screen_margin.offset_top = 40.0
	screen_margin.offset_right = -64.0
	screen_margin.offset_bottom = -40.0

func _input(event: InputEvent) -> void:
	if not _announcement_layout_active:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mouse_button.pressed:
			_dragging_announcement = false
			return
		var inside_popup := screen_margin.get_global_rect().has_point(mouse_button.position)
		var over_submit_button := submit_button.get_global_rect().has_point(mouse_button.position)
		_dragging_announcement = inside_popup and not over_submit_button
		if _dragging_announcement:
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseMotion) or not _dragging_announcement:
		return
	var mouse_motion := event as InputEventMouseMotion
	if not (mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_dragging_announcement = false
		return
	_move_announcement_popup(mouse_motion.relative)
	get_viewport().set_input_as_handled()

func _move_announcement_popup(relative_motion: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var popup_size := screen_margin.size
	var maximum_position := Vector2(
		maxf(viewport_size.x - popup_size.x, 0.0),
		maxf(viewport_size.y - popup_size.y, 0.0)
	)
	var next_position := screen_margin.position + relative_motion
	next_position.x = clampf(next_position.x, 0.0, maximum_position.x)
	next_position.y = clampf(next_position.y, 0.0, maximum_position.y)
	screen_margin.position = next_position

func _on_outcome_selected(outcome: String) -> void:
	var battle_index := int(GameState.pending_casualties.get("current_battle_index", 0))
	var selected := GameState.pending_casualties.get("selected_outcomes", {}) as Dictionary
	selected[str(battle_index)] = outcome
	GameState.pending_casualties["selected_outcomes"] = selected
	submit_button.disabled = false
	resolution_state_changed.emit()

func _restore_outcome_selection(battle_index: int) -> void:
	var selected := GameState.pending_casualties.get("selected_outcomes", {}) as Dictionary
	var outcome := String(selected.get(str(battle_index), ""))
	major_victory_button.button_pressed = outcome == BattleOutcomeResolver.OUTCOME_MAJOR_ATTACKER_VICTORY
	victory_button.button_pressed = outcome == BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY
	defeat_button.button_pressed = outcome == BattleOutcomeResolver.OUTCOME_ATTACKER_DEFEAT
	submit_button.disabled = outcome.is_empty()

func _resolving_player() -> int:
	return clampi(int(GameState.pending_casualties.get("resolving_player", 0)), 0, 1)

func _opposing_player() -> int:
	return 1 - _resolving_player()

func _current_battle() -> Dictionary:
	var battles := GameState.pending_casualties.get("battles", []) as Array
	var battle_index := int(GameState.pending_casualties.get("current_battle_index", 0))
	if battle_index < 0 or battle_index >= battles.size():
		return {}
	return battles[battle_index] as Dictionary

func _build_casualty_tree(tree: Tree, owner: int, battle: Dictionary, empty_message: String) -> void:
	tree.clear()
	tree.columns = 1
	tree.select_mode = Tree.SELECT_MULTI
	tree.hide_root = true
	var root := tree.create_item()
	var engaged_ids := _engaged_unit_ids_for_owner(battle, owner)
	for unit_id in engaged_ids:
		var unit_node := _find_player_unit_node(owner, unit_id)
		if unit_node.is_empty():
			unit_node = {"id": unit_id, "name": unit_id, "status": "alive", "children": []}
		var gameplay_unit_variant: Variant = GameState.gameplay_units.get(unit_id, null)
		if gameplay_unit_variant is Dictionary and bool((gameplay_unit_variant as Dictionary).get("is_combined_formation", false)):
			unit_node = _combined_engaged_hierarchy(unit_node, gameplay_unit_variant as Dictionary)
		_add_casualty_unit_item(root, unit_node, true)
	if root.get_child_count() == 0:
		var empty_item := tree.create_item(root)
		empty_item.set_text(0, empty_message)
		empty_item.set_selectable(0, false)
	if not tree.check_propagated_to_item.is_connected(_on_tree_check_propagated):
		tree.check_propagated_to_item.connect(_on_tree_check_propagated)
	var edited_handler := _on_tree_item_edited.bind(tree)
	if not tree.item_edited.is_connected(edited_handler):
		tree.item_edited.connect(edited_handler)

func _combined_engaged_hierarchy(tree_node: Dictionary, gameplay_unit: Dictionary) -> Dictionary:
	var pruned := tree_node.duplicate(true)
	var included_children: Array[Dictionary] = []
	for component_variant in gameplay_unit.get("combined_components", []) as Array:
		if not (component_variant is Dictionary):
			continue
		var component := component_variant as Dictionary
		var component_id := String(component.get("id", ""))
		if component_id.is_empty():
			continue
		var tree_component := _find_unit_node_recursive(tree_node, component_id)
		if tree_component.is_empty():
			continue
		if bool(component.get("is_combined_formation", false)):
			included_children.append(_combined_engaged_hierarchy(tree_component, component))
		else:
			included_children.append(tree_component.duplicate(true))
	pruned["children"] = included_children
	return pruned

func _on_tree_item_edited(tree: Tree) -> void:
	_on_tree_check_propagated(tree.get_edited(), tree.get_edited_column())

func _on_tree_check_propagated(item: TreeItem, column: int) -> void:
	if column != 0 or item == null or item.get_parent() == null:
		return
	var checked := item.is_checked(0)
	for i in range(item.get_child_count()):
		_set_checked_recursive(item.get_child(i), checked)

func _set_checked_recursive(item: TreeItem, checked: bool) -> void:
	if item.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK:
		item.set_checked(0, checked)
	for i in range(item.get_child_count()):
		_set_checked_recursive(item.get_child(i), checked)

func _add_casualty_unit_item(parent: TreeItem, unit_node: Dictionary, engaged_root: bool = false) -> TreeItem:
	if not GameState.is_unit_alive(unit_node):
		_add_living_casualty_children(parent, unit_node, engaged_root)
		return null

	var unit_id := String(unit_node.get("id", ""))
	var item := parent.create_child()
	item.set_text(0, _casualty_unit_label(unit_node, unit_id))
	item.set_metadata(0, unit_id)

	var size_name := String(unit_node.get("size", "")).strip_edges().to_lower()
	if DETAIL_SIZES.has(size_name):
		_make_checkable(item, unit_id)
	else:
		item.set_selectable(0, false)

	var children_variant: Variant = unit_node.get("children", [])
	_add_vehicle_casualty_items(item, unit_node)
	if typeof(children_variant) == TYPE_ARRAY:
		for child_variant in children_variant as Array:
			if typeof(child_variant) == TYPE_DICTIONARY:
				_add_casualty_unit_item(item, child_variant as Dictionary)

	if engaged_root and not _has_casualty_level_descendant(unit_node) and (unit_node.get("vehicles", []) as Array).is_empty():
		_make_checkable(item, unit_id)
	if item.get_child_count() > 0:
		item.collapsed = not engaged_root
	return item

func _add_vehicle_casualty_items(parent: TreeItem, unit_node: Dictionary) -> void:
	var unit_id := String(unit_node.get("id", ""))
	for vehicle_variant in unit_node.get("vehicles", []) as Array:
		if not (vehicle_variant is Dictionary):
			continue
		var vehicle := vehicle_variant as Dictionary
		if not GameState.is_unit_alive(vehicle):
			continue
		var vehicle_id := String(vehicle.get("id", ""))
		var item := parent.create_child()
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, "%s — Health: Alive" % String(vehicle.get("display_name", vehicle.get("model", vehicle_id))))
		item.set_editable(0, true)
		item.set_checked(0, false)
		item.set_metadata(0, {"kind": "vehicle", "unit_id": unit_id, "vehicle_id": vehicle_id, "display_name": String(vehicle.get("display_name", vehicle_id))})

func _add_living_casualty_children(parent: TreeItem, unit_node: Dictionary, engaged_root: bool) -> void:
	var children_variant: Variant = unit_node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	for child_variant in children_variant as Array:
		if typeof(child_variant) == TYPE_DICTIONARY:
			_add_casualty_unit_item(parent, child_variant as Dictionary, engaged_root)

func _casualty_unit_label(unit_node: Dictionary, unit_id: String) -> String:
	var display_name := String(unit_node.get("display_name", unit_id))
	var size_name := String(unit_node.get("size", "unit")).capitalize()
	var broad_type: Variant = _unit_type_value(unit_node)
	var role := UnitRole.normalize(unit_node.get("role", ""), broad_type)
	return "%s (%s) — %s — %s — %s" % [display_name, unit_id, size_name, UnitRole.display_name(role, broad_type), UnitHealthFormatter.summary(unit_node)]

func _unit_type_value(unit_node: Dictionary) -> Variant:
	return unit_node.get("type", "")

func _has_casualty_level_descendant(node: Dictionary) -> bool:
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return false
	for child_variant in children_variant as Array:
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var child := child_variant as Dictionary
		var size_name := String(child.get("size", "")).strip_edges().to_lower()
		if (GameState.is_unit_alive(child) and DETAIL_SIZES.has(size_name)) or _has_casualty_level_descendant(child):
			return true
	return false

func _make_checkable(item: TreeItem, unit_id: String) -> void:
	var label := item.get_text(0)
	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	item.set_text(0, label)
	item.set_editable(0, true)
	item.set_checked(0, false)
	item.set_metadata(0, unit_id)

func _engaged_unit_ids_for_owner(battle: Dictionary, owner: int) -> Array[String]:
	var ids: Array[String] = []
	for participant in [
		{"ids_key": "attacker_unit_ids", "owner_key": "attacker_owner"},
		{"ids_key": "defender_unit_ids", "owner_key": "defender_owner"}
	]:
		var ids_key := String(participant.get("ids_key", ""))
		var owner_key := String(participant.get("owner_key", ""))
		for unit_id_variant in battle.get(ids_key, []) as Array:
			var unit_id := String(unit_id_variant)
			if _battle_unit_owner(battle, unit_id, owner_key) == owner:
				_append_unique_string(ids, unit_id)
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
	for child_variant in children_variant as Array:
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var found := _find_unit_node_recursive(child_variant as Dictionary, unit_id)
		if not found.is_empty():
			return found
	return {}

func _on_submit_pressed() -> void:
	var workflow_stage := String(GameState.pending_casualties.get("workflow_stage", "resolution"))
	if workflow_stage == "announcement":
		GameState.pending_casualties["workflow_stage"] = "prep"
		resolution_state_changed.emit()
		_show_current_battle_or_summary()
		return
	if workflow_stage == "prep":
		GameState.pending_casualties["workflow_stage"] = "resolution"
		resolution_state_changed.emit()
		_show_current_battle_or_summary()
		return
	if _showing_summary:
		if _completion_requested:
			return
		_completion_requested = true
		submit_button.disabled = true
		GameState.pending_casualties = {}
		resolution_state_changed.emit()
		GameState.set_phase(GameState.Phase.GAMEPLAY)
		return

	var battle := _current_battle()
	if battle.is_empty():
		_show_summary()
		return
	var battle_index := int(GameState.pending_casualties.get("current_battle_index", 0))
	var selected_outcomes := GameState.pending_casualties.get("selected_outcomes", {}) as Dictionary
	var outcome := String(selected_outcomes.get(str(battle_index), ""))
	if outcome.is_empty():
		submit_button.disabled = true
		return
	var own_casualties := _confirmed_unit_ids(own_tree, _resolving_player())
	var enemy_casualties := _confirmed_unit_ids(enemy_tree, _opposing_player())
	var own_vehicle_casualties := _confirmed_vehicle_losses(own_tree, _resolving_player())
	var enemy_vehicle_casualties := _confirmed_vehicle_losses(enemy_tree, _opposing_player())
	var all_casualties: Array[String] = []
	for unit_id in own_casualties + enemy_casualties:
		_append_unique_string(all_casualties, unit_id)
	for unit_id in all_casualties:
		GameState.mark_unit_status(unit_id, "dead")
	for vehicle_loss in own_vehicle_casualties + enemy_vehicle_casualties:
		GameState.mark_vehicle_status(String(vehicle_loss.get("unit_id", "")), String(vehicle_loss.get("vehicle_id", "")), "dead")
	var reconciled_ids := GameState.reconcile_formation_statuses()
	_append_reconciled_casualties(reconciled_ids, own_casualties, enemy_casualties)

	var outcome_result := BattleOutcomeResolver.resolve(GameState.gameplay_units, battle, outcome, {
		"rng_seed": int(GameState.pending_casualties.get("outcome_rng_seed", 1)) + battle_index,
		"territory_map": GameState.territory_map,
		"terrain_map": GameState.terrain_map,
		"map_dimensions": GameState.selected_map_dimensions
	})
	GameState.gameplay_units = (outcome_result.get("units", {}) as Dictionary).duplicate(true)
	for forced_id_variant in outcome_result.get("forced_destroyed_unit_ids", []) as Array:
		var forced_id := String(forced_id_variant)
		GameState.mark_unit_subtree_status(forced_id, "dead")
		var forced_owner := _owner_for_gameplay_unit(forced_id)
		if forced_owner == _resolving_player():
			_append_unique_string(own_casualties, forced_id)
		else:
			_append_unique_string(enemy_casualties, forced_id)
	for territory_key in (outcome_result.get("territory_updates", {}) as Dictionary).keys():
		GameState.territory_map[String(territory_key)] = int((outcome_result.get("territory_updates", {}) as Dictionary)[territory_key])
	reconciled_ids = GameState.reconcile_formation_statuses()
	_append_reconciled_casualties(reconciled_ids, own_casualties, enemy_casualties)

	var casualties_by_owner := {
		str(_resolving_player()): own_casualties,
		str(_opposing_player()): enemy_casualties
	}
	var results := GameState.pending_casualties.get("results", []) as Array
	results.append({
		"hex": (battle.get("hex", {}) as Dictionary).duplicate(true),
		"attacker_unit_ids": (battle.get("attacker_unit_ids", []) as Array).duplicate(),
		"defender_unit_ids": (battle.get("defender_unit_ids", []) as Array).duplicate(),
		"casualties_by_owner": casualties_by_owner,
		"vehicle_casualties_by_owner": {str(_resolving_player()): own_vehicle_casualties, str(_opposing_player()): enemy_vehicle_casualties},
		"outcome": outcome,
		"movement_events": (outcome_result.get("movement_events", []) as Array).duplicate(true),
		"forced_destroyed_unit_ids": (outcome_result.get("forced_destroyed_unit_ids", []) as Array).duplicate()
	})
	GameState.pending_casualties["results"] = results
	GameState.pending_casualties["current_battle_index"] = int(GameState.pending_casualties.get("current_battle_index", 0)) + 1
	if int(GameState.pending_casualties["current_battle_index"]) >= (GameState.pending_casualties.get("battles", []) as Array).size():
		GameState.pending_casualties["workflow_stage"] = "summary"
	else:
		GameState.pending_casualties["workflow_stage"] = "announcement"
	resolution_state_changed.emit()
	_show_current_battle_or_summary()

func _owner_for_gameplay_unit(unit_id: String) -> int:
	if GameState.gameplay_units.has(unit_id):
		return int((GameState.gameplay_units[unit_id] as Dictionary).get("owner", _opposing_player()))
	for owner in range(GameState.players.size()):
		if not _find_player_unit_node(owner, unit_id).is_empty():
			return owner
	return _opposing_player()

func _append_reconciled_casualties(unit_ids: Array[String], own_casualties: Array[String], enemy_casualties: Array[String]) -> void:
	for unit_id in unit_ids:
		if _owner_for_gameplay_unit(unit_id) == _resolving_player():
			_append_unique_string(own_casualties, unit_id)
		else:
			_append_unique_string(enemy_casualties, unit_id)

func _confirmed_vehicle_losses(tree: Tree, owner: int) -> Array[Dictionary]:
	var losses: Array[Dictionary] = []
	_collect_checked_vehicle_losses(tree.get_root(), losses, owner)
	return losses

func _collect_checked_vehicle_losses(item: TreeItem, output: Array[Dictionary], owner: int) -> void:
	if item == null:
		return
	if item.get_parent() != null and item.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK and item.is_checked(0):
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary and String((metadata as Dictionary).get("kind", "")) == "vehicle":
			var loss := (metadata as Dictionary).duplicate(true)
			if _is_vehicle_alive_for_owner(owner, String(loss.get("unit_id", "")), String(loss.get("vehicle_id", ""))):
				output.append(loss)
	for child_index in range(item.get_child_count()):
		_collect_checked_vehicle_losses(item.get_child(child_index), output, owner)

func _is_vehicle_alive_for_owner(owner: int, unit_id: String, vehicle_id: String) -> bool:
	var unit := _find_player_unit_node(owner, unit_id)
	for vehicle_variant in unit.get("vehicles", []) as Array:
		if vehicle_variant is Dictionary and String((vehicle_variant as Dictionary).get("id", "")) == vehicle_id:
			return GameState.is_unit_alive(vehicle_variant as Dictionary)
	return false

func _confirmed_unit_ids(tree: Tree, owner: int = -1) -> Array[String]:
	var unique_ids := {}
	_collect_checked_unit_ids(tree.get_root(), unique_ids, owner)
	var confirmed_ids: Array[String] = []
	for key in unique_ids.keys():
		confirmed_ids.append(String(key))
	confirmed_ids.sort()
	return confirmed_ids

func _confirmed_casualty_unit_ids() -> Array[String]:
	var confirmed_ids := _confirmed_unit_ids(own_tree, _resolving_player())
	for unit_id in _confirmed_unit_ids(enemy_tree, _opposing_player()):
		_append_unique_string(confirmed_ids, unit_id)
	confirmed_ids.sort()
	return confirmed_ids

func _confirmed_own_casualty_unit_ids() -> Array[String]:
	return _confirmed_unit_ids(own_tree, _resolving_player())

func _collect_checked_unit_ids(item: TreeItem, output: Dictionary, owner: int = -1) -> void:
	if item == null:
		return
	if item.get_parent() != null and item.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK and item.is_checked(0):
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary:
			for child_index in range(item.get_child_count()):
				_collect_checked_unit_ids(item.get_child(child_index), output, owner)
			return
		var unit_id := String(metadata)
		if not unit_id.is_empty() and _is_unit_id_alive_for_owner(unit_id, owner):
			output[unit_id] = true
	for i in range(item.get_child_count()):
		_collect_checked_unit_ids(item.get_child(i), output, owner)

func _is_unit_id_alive_for_owner(unit_id: String, owner: int) -> bool:
	if owner < 0:
		return true
	var unit_node := _find_player_unit_node(owner, unit_id)
	return unit_node.is_empty() or GameState.is_unit_alive(unit_node)

func _combat_summary_text() -> String:
	var battles := GameState.pending_casualties.get("battles", []) as Array
	var results := GameState.pending_casualties.get("results", []) as Array
	if battles.is_empty():
		return "No combat occurred."

	var lines: Array[String] = []
	for battle_index in range(battles.size()):
		var battle := battles[battle_index] as Dictionary
		lines.append("Battle %d — Hex %s" % [battle_index + 1, _battle_hex_text(battle)])
		lines.append("Attackers: %s" % _participant_names(battle, "attacker_unit_ids", "attacker_owner"))
		lines.append("Defenders: %s" % _participant_names(battle, "defender_unit_ids", "defender_owner"))
		if battle_index < results.size():
			lines.append("Outcome: %s" % _outcome_display_name(String((results[battle_index] as Dictionary).get("outcome", ""))))
		if battle_index < battles.size() - 1:
			lines.append("")
	lines.append("")
	lines.append("Turn Casualties")
	var turn_casualties_by_owner := _turn_casualty_ids_by_owner(results)
	for owner in range(mini(GameState.players.size(), 2)):
		var casualty_ids := turn_casualties_by_owner.get(str(owner), []) as Array
		var summarized_ids := _largest_destroyed_formation_ids(owner, casualty_ids)
		lines.append("%s casualties: %s" % [_player_display_name(owner), _unit_name_list(owner, summarized_ids)])
		var vehicle_names := _partial_vehicle_loss_names(owner, results)
		if not vehicle_names.is_empty():
			lines.append("%s vehicle losses: %s" % [_player_display_name(owner), ", ".join(vehicle_names)])
	return "\n".join(lines)

func _outcome_display_name(outcome: String) -> String:
	match outcome:
		BattleOutcomeResolver.OUTCOME_MAJOR_ATTACKER_VICTORY:
			return "Major Attacker Victory"
		BattleOutcomeResolver.OUTCOME_ATTACKER_VICTORY:
			return "Attacker Victory"
		BattleOutcomeResolver.OUTCOME_ATTACKER_DEFEAT:
			return "Attacker Defeat"
		_:
			return "Not Recorded"

func _partial_vehicle_loss_names(owner: int, results: Array) -> Array[String]:
	var names: Array[String] = []
	for result_variant in results:
		if not (result_variant is Dictionary):
			continue
		var by_owner := (result_variant as Dictionary).get("vehicle_casualties_by_owner", {}) as Dictionary
		for loss_variant in by_owner.get(str(owner), []) as Array:
			if not (loss_variant is Dictionary):
				continue
			var loss := loss_variant as Dictionary
			var parent := _find_player_unit_node(owner, String(loss.get("unit_id", "")))
			if not parent.is_empty() and not GameState.is_unit_alive(parent):
				continue
			var display_name := String(loss.get("display_name", loss.get("vehicle_id", "Vehicle")))
			if not names.has(display_name):
				names.append(display_name)
	names.sort()
	return names

func _turn_casualty_ids_by_owner(results: Array) -> Dictionary:
	var aggregated := {}
	for owner in range(mini(GameState.players.size(), 2)):
		aggregated[str(owner)] = []
	for result_variant in results:
		if not (result_variant is Dictionary):
			continue
		var casualties_by_owner := (result_variant as Dictionary).get("casualties_by_owner", {}) as Dictionary
		for owner_key_variant in casualties_by_owner.keys():
			var owner_key := String(owner_key_variant)
			if not aggregated.has(owner_key):
				aggregated[owner_key] = []
			for unit_id_variant in casualties_by_owner[owner_key_variant] as Array:
				_append_unique_string(aggregated[owner_key] as Array, String(unit_id_variant))
	return aggregated

func _participant_names(battle: Dictionary, ids_key: String, owner_key: String) -> String:
	var ids := battle.get(ids_key, []) as Array
	var names: Array[String] = []
	for unit_id_variant in ids:
		var unit_id := String(unit_id_variant)
		var owner := _battle_unit_owner(battle, unit_id, owner_key)
		names.append(_unit_display_name(owner, unit_id))
	return "None" if names.is_empty() else ", ".join(names)

func _battle_unit_owner(battle: Dictionary, unit_id: String, owner_key: String) -> int:
	for engagement_variant in battle.get("engagements", []) as Array:
		if typeof(engagement_variant) != TYPE_DICTIONARY:
			continue
		var engagement := engagement_variant as Dictionary
		var id_key := "attacker_unit_id" if owner_key == "attacker_owner" else "defender_unit_id"
		if String(engagement.get(id_key, "")) == unit_id:
			return int(engagement.get(owner_key, -1))
	return _owner_for_gameplay_unit(unit_id)

func _unit_name_list(owner: int, unit_ids: Array) -> String:
	var names: Array[String] = []
	var root := (GameState.players[owner] as Dictionary).get("division_tree", {}) as Dictionary if owner >= 0 and owner < GameState.players.size() else {}
	for unit_id_variant in unit_ids:
		var unit_id := String(unit_id_variant)
		names.append(FormationHierarchy.casualty_name(root, unit_id) if not root.is_empty() else _unit_display_name(owner, unit_id))
	return "None" if names.is_empty() else ", ".join(names)

func _largest_destroyed_formation_ids(owner: int, casualty_ids: Array) -> Array[String]:
	var output: Array[String] = []
	if owner < 0 or owner >= GameState.players.size():
		for unit_id_variant in casualty_ids:
			_append_unique_string(output, String(unit_id_variant))
		return output
	var raw_ids := {}
	for unit_id_variant in casualty_ids:
		raw_ids[String(unit_id_variant)] = true
	var root := (GameState.players[owner] as Dictionary).get("division_tree", {}) as Dictionary
	var state := _destruction_summary_state(root, raw_ids)
	for unit_id_variant in state.get("report_ids", []) as Array:
		_append_unique_string(output, String(unit_id_variant))
	for unit_id_variant in casualty_ids:
		var unit_id := String(unit_id_variant)
		if not bool((state.get("covered_raw_ids", {}) as Dictionary).get(unit_id, false)):
			_append_unique_string(output, unit_id)
	return output

func _destruction_summary_state(node: Dictionary, raw_ids: Dictionary) -> Dictionary:
	if node.is_empty() or _is_headquarters_node(node):
		return {"has_components": false, "all_dead": true, "touched": false, "report_ids": [], "covered_raw_ids": {}}
	var child_states: Array[Dictionary] = []
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) == TYPE_ARRAY:
		for child_variant in children_variant as Array:
			if child_variant is Dictionary:
				child_states.append(_destruction_summary_state(child_variant as Dictionary, raw_ids))
	var has_components := false
	var all_dead := true
	var touched := raw_ids.has(String(node.get("id", "")))
	var report_ids: Array[String] = []
	var covered_raw_ids := {}
	for child_state in child_states:
		if bool(child_state.get("has_components", false)):
			has_components = true
			all_dead = all_dead and bool(child_state.get("all_dead", false))
		touched = touched or bool(child_state.get("touched", false))
		for report_id_variant in child_state.get("report_ids", []) as Array:
			_append_unique_string(report_ids, String(report_id_variant))
		covered_raw_ids.merge(child_state.get("covered_raw_ids", {}) as Dictionary, true)
	var size_name := String(node.get("size", "")).strip_edges().to_lower()
	if not has_components and size_name in ["squad", "section"]:
		has_components = true
		all_dead = not GameState.is_unit_alive(node)
	if not has_components and touched:
		has_components = true
		all_dead = true
	var size_rank := _formation_size_rank(size_name)
	if has_components and all_dead and touched and size_rank >= UnitSize.Value.PLATOON:
		report_ids = [String(node.get("id", ""))]
		covered_raw_ids.clear()
		_collect_raw_ids_in_subtree(node, raw_ids, covered_raw_ids)
	elif raw_ids.has(String(node.get("id", ""))):
		covered_raw_ids[String(node.get("id", ""))] = true
		if size_rank < UnitSize.Value.PLATOON:
			_append_unique_string(report_ids, String(node.get("id", "")))
	return {
		"has_components": has_components,
		"all_dead": all_dead,
		"touched": touched,
		"report_ids": report_ids,
		"covered_raw_ids": covered_raw_ids
	}

func _collect_raw_ids_in_subtree(node: Dictionary, raw_ids: Dictionary, output: Dictionary) -> void:
	var unit_id := String(node.get("id", ""))
	if raw_ids.has(unit_id):
		output[unit_id] = true
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			_collect_raw_ids_in_subtree(child_variant as Dictionary, raw_ids, output)

func _is_headquarters_node(node: Dictionary) -> bool:
	var role := String(node.get("role", "")).strip_edges().to_lower()
	if role == "headquarters":
		return true
	var raw_type: Variant = node.get("type", "")
	return (typeof(raw_type) == TYPE_INT and int(raw_type) == UnitType.Value.HEADQUARTERS) or String(raw_type).strip_edges().to_lower() == "headquarters"

func _formation_size_rank(size_name: String) -> int:
	match size_name:
		"squad": return UnitSize.Value.SQUAD
		"section": return UnitSize.Value.SECTION
		"platoon": return UnitSize.Value.PLATOON
		"company": return UnitSize.Value.COMPANY
		"battalion": return UnitSize.Value.BATTALION
		"regiment": return UnitSize.Value.REGIMENT
		"division": return UnitSize.Value.DIVISION
		"army": return UnitSize.Value.ARMY
	return -1

func _unit_display_name(owner: int, unit_id: String) -> String:
	var unit := _find_player_unit_node(owner, unit_id)
	if unit.is_empty():
		return unit_id
	return String(unit.get("display_name", unit_id))

func _player_display_name(owner: int) -> String:
	if owner >= 0 and owner < GameState.players.size():
		var player := GameState.players[owner] as Dictionary
		var player_name := String(player.get("name", "")).strip_edges()
		if not player_name.is_empty():
			return player_name
	return "Player %d" % [owner + 1]

func _battle_hex_text(battle: Dictionary) -> String:
	var raw_hex: Variant = battle.get("hex", {})
	if typeof(raw_hex) != TYPE_DICTIONARY:
		return "?,?"
	var hex_dict := raw_hex as Dictionary
	return "%d,%d" % [int(hex_dict.get("q", 0)), int(hex_dict.get("r", 0))]

func _battle_prep_text(battle: Dictionary) -> String:
	var attacker_ids := battle.get("attacker_unit_ids", []) as Array
	var defender_ids := battle.get("defender_unit_ids", []) as Array
	var lines: Array[String] = ["Attackers:"]
	for unit_id_variant in attacker_ids:
		var unit_id := String(unit_id_variant)
		lines.append("• %s" % _prep_unit_line(_battle_unit_owner(battle, unit_id, "attacker_owner"), unit_id, false))
	if attacker_ids.is_empty():
		lines.append("• None")
	lines.append("")
	lines.append("Defenders:")
	for unit_id_variant in defender_ids:
		var unit_id := String(unit_id_variant)
		lines.append("• %s" % _prep_unit_line(_battle_unit_owner(battle, unit_id, "defender_owner"), unit_id, true))
	if defender_ids.is_empty():
		lines.append("• None")
	return "\n".join(lines)

func _prep_unit_line(owner: int, unit_id: String, include_defense: bool) -> String:
	var unit := _find_player_unit_node(owner, unit_id)
	var gameplay_unit := GameState.gameplay_units.get(unit_id, {}) as Dictionary
	var source := gameplay_unit if not gameplay_unit.is_empty() else unit
	var root := (GameState.players[owner] as Dictionary).get("division_tree", {}) as Dictionary if owner >= 0 and owner < GameState.players.size() else {}
	var fallback_name := String(unit.get("display_name", "")).strip_edges()
	if fallback_name.is_empty():
		fallback_name = String(source.get("display_name", "")).strip_edges()
	if fallback_name.is_empty():
		fallback_name = unit_id
	var line := _prep_unit_identity(source, unit, fallback_name)
	var ancestor_labels := _prep_ancestor_labels(root, unit_id)
	if not ancestor_labels.is_empty():
		line += ", %s" % ", ".join(ancestor_labels)
	if include_defense:
		var defensive_states: Array[String] = []
		if bool(source.get("dug_in", false)):
			defensive_states.append("Dug In")
		if defensive_states.is_empty():
			defensive_states.append("Not Dug In")
		line += " — %s" % ", ".join(defensive_states)
	return line

func _prep_unit_identity(source: Dictionary, tree_unit: Dictionary, fallback_name: String) -> String:
	var designation := source.get("designation", {}) as Dictionary
	if designation.is_empty():
		designation = tree_unit.get("designation", {}) as Dictionary
	var size := String(source.get("size", tree_unit.get("size", ""))).strip_edges().to_lower()
	var role := UnitRole.display_name(source.get("role", tree_unit.get("role", "")), source.get("type", tree_unit.get("type", ""))).strip_edges().to_lower()
	if role == "unknown":
		return fallback_name
	match size:
		"division":
			var division_number := int(designation.get("division_number", 0))
			if division_number > 0:
				return "%s %s division" % [_prep_ordinal(division_number), role]
		"regiment":
			var regiment_number := int(designation.get("regiment_number", 0))
			if regiment_number > 0:
				return "%s %s regiment" % [_prep_ordinal(regiment_number), role]
		"battalion":
			var battalion_number := int(designation.get("battalion_number", 0))
			if battalion_number > 0:
				return "%s %s battalion" % [_prep_ordinal(battalion_number), role]
		"company":
			var company_letter := String(designation.get("company_letter", "")).strip_edges().to_upper()
			if not company_letter.is_empty():
				return "%s %s company" % [company_letter, role]
		"platoon":
			var platoon_number := int(designation.get("platoon_number", 0))
			if platoon_number > 0:
				return "%s %s platoon" % [_prep_ordinal(platoon_number), role]
	return fallback_name

func _prep_ancestor_labels(root: Dictionary, unit_id: String) -> Array[String]:
	var labels: Array[String] = []
	var path := FormationHierarchy.path_to(root, unit_id)
	for index in range(maxi(path.size() - 1, 0)):
		var ancestor := path[index] as Dictionary
		var size := String(ancestor.get("size", "")).strip_edges().to_lower()
		if size == "army" or _prep_node_is_headquarters(ancestor):
			continue
		var label := _prep_ancestor_label(ancestor, size)
		if not label.is_empty():
			labels.append(label)
	return labels

func _prep_ancestor_label(unit: Dictionary, size: String) -> String:
	var designation := unit.get("designation", {}) as Dictionary
	match size:
		"division":
			var division_number := int(designation.get("division_number", 0))
			if division_number > 0:
				return "%s division" % _prep_ordinal(division_number)
		"regiment":
			var regiment_number := int(designation.get("regiment_number", 0))
			if regiment_number > 0:
				return "%s regiment" % _prep_ordinal(regiment_number)
		"battalion":
			var battalion_number := int(designation.get("battalion_number", 0))
			if battalion_number > 0:
				return "%s battalion" % _prep_ordinal(battalion_number)
		"company":
			var company_letter := String(designation.get("company_letter", "")).strip_edges().to_upper()
			if not company_letter.is_empty():
				return "%s company" % company_letter
		"platoon":
			var platoon_number := int(designation.get("platoon_number", 0))
			if platoon_number > 0:
				return "%s platoon" % _prep_ordinal(platoon_number)
	return String(unit.get("display_name", unit.get("short_name", unit.get("id", "")))).strip_edges()

func _prep_node_is_headquarters(unit: Dictionary) -> bool:
	if String(unit.get("role", "")).strip_edges().to_lower() == "headquarters":
		return true
	return String(unit.get("type", "")).strip_edges().to_lower().replace("_", "").replace(" ", "") == "headquarters"

func _prep_ordinal(number: int) -> String:
	var remainder_100 := number % 100
	if remainder_100 >= 11 and remainder_100 <= 13:
		return "%dth" % number
	match number % 10:
		1:
			return "%dst" % number
		2:
			return "%dnd" % number
		3:
			return "%drd" % number
		_:
			return "%dth" % number

func _append_unique_string(values: Array, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)
