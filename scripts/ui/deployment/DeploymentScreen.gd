extends Control

const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")
const DeploymentAIService = preload("res://scripts/systems/deployment_ai/DeploymentAIService.gd")

@onready var phase_label: Label = %PhaseLabel
@onready var unit_list: ItemList = %UnitList
@onready var status_label: Label = %StatusLabel
@onready var hex_map_view: DeploymentHexMapView = %HexMapView
@onready var p2_structure_label: Label = %P2StructureLabel
@onready var p2_structure_picker: OptionButton = %P2StructurePicker
@onready var finish_button: Button = %FinishDeploymentButton

var _player_index := 0
var _deployable_units: Array[Dictionary] = []

func _ready() -> void:
	_player_index = 0 if GameState.current_phase == GameState.Phase.DEPLOYMENT_P1 else 1
	_ensure_players_initialized()
	_populate_p2_structure_picker()
	_build_deployable_unit_list()
	_refresh_phase_ui("Select a unit, then click a hex in your territory.")

	hex_map_view.hex_selected.connect(_on_hex_selected)
	p2_structure_picker.item_selected.connect(_on_p2_structure_selected)
	finish_button.pressed.connect(_on_finish_deployment_pressed)

func _ensure_players_initialized() -> void:
	while GameState.players.size() < 2:
		GameState.players.append({
			"name": "Player %d" % (GameState.players.size() + 1),
			"division_tree": {},
			"deployments": {},
			"controller": "human"
		})

	for i in range(2):
		var player := GameState.players[i]
		if not player.has("division_tree"):
			player["division_tree"] = {}
		if (player.get("division_tree", {}) as Dictionary).is_empty():
			player["division_tree"] = _best_default_structure_for_player(i)
		if not GameState.players[i].has("deployments"):
			GameState.players[i]["deployments"] = {}
		GameState.players[i] = player

func _populate_p2_structure_picker() -> void:
	p2_structure_picker.clear()

	var options: Array[Dictionary] = []
	options.append_array(_catalog_structure_options())
	options.append_array(_saved_structure_options())

	if options.is_empty():
		var fallback_tree := _default_division_tree(1)
		options.append({
			"label": "Default Opponent Structure",
			"tree": fallback_tree
		})

	var selected_index := 0
	var current_tree := GameState.players[1].get("division_tree", {}) as Dictionary
	var matched_current := false

	for i in range(options.size()):
		var option := options[i]
		var option_label := String(option.get("label", "Option %d" % i))
		var option_tree := (option.get("tree", {}) as Dictionary).duplicate(true)
		p2_structure_picker.add_item(option_label)
		p2_structure_picker.set_item_metadata(i, option_tree)
		if not current_tree.is_empty() and option_tree.hash() == current_tree.hash():
			selected_index = i
			matched_current = true

	if not current_tree.is_empty() and not matched_current:
		p2_structure_picker.add_item("Current Opponent Structure")
		selected_index = p2_structure_picker.item_count - 1
		p2_structure_picker.set_item_metadata(selected_index, current_tree.duplicate(true))

	p2_structure_picker.select(selected_index)
	_apply_selected_p2_structure(selected_index, false)
	var picker_enabled := _player_index == 0
	p2_structure_label.visible = true
	p2_structure_picker.visible = true
	p2_structure_picker.disabled = not picker_enabled

func _catalog_structure_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var nation_id := String(GameState.selected_nation_id)
	var templates: Array = UnitCatalog.get_nation_templates(nation_id)
	for template_variant in templates:
		if typeof(template_variant) != TYPE_DICTIONARY:
			continue
		var template := template_variant as Dictionary
		var label := "Catalog: %s" % String(template.get("display_name", template.get("id", "Template")))
		options.append({
			"label": label,
			"tree": _division_tree_from_catalog_template(template)
		})
	return options

func _best_default_structure_for_player(player_index: int) -> Dictionary:
	var catalog_options := _catalog_structure_options()
	for option in catalog_options:
		if typeof(option) != TYPE_DICTIONARY:
			continue
		var option_dict := option as Dictionary
		var tree_variant: Variant = option_dict.get("tree", {})
		if typeof(tree_variant) != TYPE_DICTIONARY:
			continue
		var tree := tree_variant as Dictionary
		if tree.is_empty():
			continue
		return tree.duplicate(true)
	return _default_division_tree(player_index)

func _saved_structure_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var template_names: PackedStringArray = SaveManager.list_division_templates()
	for template_name in template_names:
		var payload: Dictionary = SaveManager.load_division_template(template_name)
		var root_unit: Variant = payload.get("root_unit", {})
		if typeof(root_unit) != TYPE_DICTIONARY:
			continue
		var root_dict := root_unit as Dictionary
		if root_dict.is_empty():
			continue
		options.append({
			"label": "Saved: %s" % template_name,
			"tree": root_dict.duplicate(true)
		})
	return options

func _division_tree_from_catalog_template(template_data: Dictionary, variant_index: int = 1, parent_tree_id: String = "") -> Dictionary:
	var local_tree_id := String(template_data.get("id", "template"))
	if variant_index > 1:
		local_tree_id = "%s_%d" % [local_tree_id, variant_index]
	var tree_id := local_tree_id if parent_tree_id.is_empty() else "%s__%s" % [parent_tree_id, local_tree_id]
	var tree_name := String(template_data.get("display_name", tree_id))
	if variant_index > 1:
		tree_name = "%s %d" % [tree_name, variant_index]

	var tree := {
		"id": tree_id,
		"name": tree_name,
		"type": String(template_data.get("type", "INFANTRY")).to_lower(),
		"size": String(template_data.get("size", "COMPANY")).to_lower(),
		"children": []
	}

	var expanded_children: Array[Dictionary] = []
	var children_variant: Variant = template_data.get("children", [])
	if typeof(children_variant) == TYPE_ARRAY:
		var child_templates := children_variant as Array
		for child_variant in child_templates:
			if typeof(child_variant) != TYPE_DICTIONARY:
				continue
			var child_template := child_variant as Dictionary
			var child_count := maxi(int(child_template.get("count", 1)), 1)
			for i in range(child_count):
				expanded_children.append(_division_tree_from_catalog_template(child_template, i + 1, tree_id))
	tree["children"] = expanded_children
	return tree

func _on_p2_structure_selected(index: int) -> void:
	_apply_selected_p2_structure(index, true)

func _apply_selected_p2_structure(index: int, show_status: bool) -> void:
	var selected_tree: Variant = p2_structure_picker.get_item_metadata(index)
	if typeof(selected_tree) != TYPE_DICTIONARY:
		return

	var selected_tree_copy := (selected_tree as Dictionary).duplicate(true)
	var current_tree := GameState.players[1].get("division_tree", {}) as Dictionary
	var tree_changed := current_tree.is_empty() or current_tree.hash() != selected_tree_copy.hash()

	GameState.players[1]["division_tree"] = selected_tree_copy
	if tree_changed:
		GameState.players[1]["deployments"] = {}
	if _player_index == 1:
		_build_deployable_unit_list()
		if show_status:
			_refresh_phase_ui("Opponent structure updated.")

func _default_division_tree(player_index: int) -> Dictionary:
	var side_label := "P%d" % (player_index + 1)
	return {
		"id": "%s_hq" % side_label,
		"name": "%s HQ" % side_label,
		"type": "headquarters",
		"size": "army",
		"children": [
			{
				"id": "%s_infantry_bn" % side_label,
				"name": "%s Infantry Battalion" % side_label,
				"type": "infantry",
				"size": "battalion",
				"children": [
					{
						"id": "%s_infantry_co_1" % side_label,
						"name": "%s Infantry Company A" % side_label,
						"type": "infantry",
						"size": "company",
						"children": [
							{
								"id": "%s_infantry_co_1_plt_1" % side_label,
								"name": "%s 1st Platoon" % side_label,
								"type": "infantry",
								"size": "platoon",
								"children": []
							},
							{
								"id": "%s_infantry_co_1_plt_2" % side_label,
								"name": "%s 2nd Platoon" % side_label,
								"type": "infantry",
								"size": "platoon",
								"children": []
							}
						]
					},
					{
						"id": "%s_infantry_co_2" % side_label,
						"name": "%s Infantry Company B" % side_label,
						"type": "infantry",
						"size": "company",
						"children": [
							{
								"id": "%s_infantry_co_2_plt_1" % side_label,
								"name": "%s 3rd Platoon" % side_label,
								"type": "infantry",
								"size": "platoon",
								"children": []
							}
						]
					}
				]
			},
			{
				"id": "%s_tank_bn" % side_label,
				"name": "%s Tank Battalion" % side_label,
				"type": "tank",
				"size": "battalion",
				"children": [
					{
						"id": "%s_tank_co_1" % side_label,
						"name": "%s Tank Company" % side_label,
						"type": "tank",
						"size": "company",
						"children": [
							{
								"id": "%s_tank_co_1_plt_1" % side_label,
								"name": "%s Tank Platoon" % side_label,
								"type": "tank",
								"size": "platoon",
								"children": []
							}
						]
					}
				]
			},
			{
				"id": "%s_support_bn" % side_label,
				"name": "%s Support Battalion" % side_label,
				"type": "engineer",
				"size": "battalion",
				"children": [
					{
						"id": "%s_support_co" % side_label,
						"name": "%s Support Company" % side_label,
						"type": "engineer",
						"size": "company",
						"children": [
							{
								"id": "%s_support_co_plt_1" % side_label,
								"name": "%s Engineer Platoon" % side_label,
								"type": "engineer",
								"size": "platoon",
								"children": []
							},
							{
								"id": "%s_support_co_plt_2" % side_label,
								"name": "%s Weapons Platoon" % side_label,
								"type": "artillery",
								"size": "platoon",
								"children": []
							}
						]
					}
				]
			}
		]
	}

func _build_deployable_unit_list() -> void:
	unit_list.clear()
	_deployable_units.clear()

	var division_tree = GameState.players[_player_index].get("division_tree", {})
	var flattened: Array[Dictionary] = []
	_flatten_units(division_tree, flattened, 0)

	for entry in flattened:
		var unit_data := entry.get("unit", {}) as Dictionary
		var depth := int(entry.get("depth", 0))
		var block_reason := _deployability_block_reason(unit_data)
		var display_label := _unit_label(unit_data, depth)
		if not block_reason.is_empty():
			display_label += "  [Not deployable: %s]" % block_reason

		unit_list.add_item(display_label)
		var item_index := unit_list.item_count - 1
		unit_list.set_item_metadata(item_index, {
			"unit": unit_data,
			"base_block_reason": block_reason
		})
		unit_list.set_item_disabled(item_index, not block_reason.is_empty())
		_deployable_units.append(unit_data)

func _flatten_units(node: Variant, output: Array[Dictionary], depth: int) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return
	var unit := node as Dictionary
	if not unit.is_empty():
		output.append({
			"unit": unit,
			"depth": depth
		})
	for child in unit.get("children", []):
		_flatten_units(child, output, depth + 1)


func _string_for_type(raw_type: Variant) -> String:
	if typeof(raw_type) == TYPE_INT:
		return UnitType.display_name(int(raw_type)).to_lower()
	return String(raw_type).to_lower()

func _string_for_size(raw_size: Variant) -> String:
	if typeof(raw_size) == TYPE_INT:
		return UnitSize.display_name(int(raw_size)).to_lower()
	return String(raw_size).to_lower()

func _is_deployable(unit: Dictionary) -> bool:
	return _deployability_block_reason(unit).is_empty()

func _deployability_block_reason(unit: Dictionary) -> String:
	var snapshot := _unit_snapshot(unit)
	snapshot["name"] = String(unit.get("name", unit.get("id", "Unit")))
	return DeploymentValidator.placement_block_reason(snapshot, [])

func _unit_label(unit: Dictionary, depth: int = 0) -> String:
	var size := _string_for_size(unit.get("size", "Unknown"))
	var type := _string_for_type(unit.get("type", "Unit"))
	var name := String(unit.get("name", unit.get("id", "unnamed")))
	return "%s%s - %s %s" % ["  ".repeat(max(depth, 0)), name, size.capitalize(), type.capitalize()]

func _on_hex_selected(column: int, row: int) -> void:
	var selected := unit_list.get_selected_items()
	if selected.is_empty():
		_refresh_phase_ui("Select a unit first.")
		return

	var selected_metadata := unit_list.get_item_metadata(selected[0]) as Dictionary
	var unit_data := selected_metadata.get("unit", {}) as Dictionary
	var base_block_reason := String(selected_metadata.get("base_block_reason", ""))
	if not base_block_reason.is_empty():
		_refresh_phase_ui(base_block_reason)
		return

	var unit_snapshot := _unit_snapshot(unit_data)
	var unit_id := String(unit_snapshot.get("id", ""))
	var territory_owner := int(GameState.territory_map.get("%d,%d" % [column, row], GameState.TerritoryOwnership.NEUTRAL))
	if not DeploymentValidator.can_deploy_in_territory(territory_owner, _player_index):
		_refresh_phase_ui("Deployment must be inside your territory.")
		return

	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var target_key := "%d,%d" % [column, row]
	var existing_key := _deployment_key_for_unit_id(deployments, unit_id)

	var next_deployments := deployments.duplicate(true)
	if existing_key != "":
		next_deployments.erase(existing_key)
	next_deployments.erase(target_key)

	var snapshot := _deployed_unit_snapshots(next_deployments)
	var placement_block_reason := DeploymentValidator.placement_block_reason(unit_snapshot, snapshot)
	if not placement_block_reason.is_empty():
		_refresh_phase_ui(placement_block_reason)
		return

	next_deployments[target_key] = unit_snapshot
	GameState.players[_player_index]["deployments"] = next_deployments
	_refresh_phase_ui("Placed %s at %d,%d." % [_unit_label(unit_data), column, row])

func _deployed_unit_snapshots(deployments: Dictionary) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for key in deployments.keys():
		var unit_data = deployments[key]
		if typeof(unit_data) == TYPE_DICTIONARY:
			units.append(unit_data)
	return units

func _deployment_key_for_unit_id(deployments: Dictionary, unit_id: String) -> String:
	if unit_id.is_empty():
		return ""
	for key in deployments.keys():
		var unit_data = deployments[key]
		if typeof(unit_data) != TYPE_DICTIONARY:
			continue
		if String(unit_data.get("id", "")) == unit_id:
			return String(key)
	return ""

func _unit_snapshot(unit: Dictionary) -> Dictionary:
	var unit_type := _string_for_type(unit.get("type", ""))
	var unit_size := _string_for_size(unit.get("size", ""))
	return {
		"id": unit.get("id", ""),
		"name": String(unit.get("name", unit.get("id", "Unit"))),
		"type": unit_type,
		"size": unit_size,
		"size_rank": _size_rank(unit_size),
		"label": String(unit.get("name", unit.get("id", "U"))).substr(0, 2).to_upper(),
		"is_tank": unit_type == "tank",
		"is_headquarters": unit_type == "headquarters",
		"is_battalion": unit_size == "battalion",
		"is_company": unit_size == "company",
		"is_platoon": unit_size == "platoon"
	}

func _size_rank(size_name: String) -> int:
	match size_name:
		"squad":
			return UnitSize.Value.SQUAD
		"section":
			return UnitSize.Value.SECTION
		"platoon":
			return UnitSize.Value.PLATOON
		"company":
			return UnitSize.Value.COMPANY
		"battalion":
			return UnitSize.Value.BATTALION
		"regiment":
			return UnitSize.Value.REGIMENT
		"division":
			return UnitSize.Value.DIVISION
		"army":
			return UnitSize.Value.ARMY
		_:
			return -1

func _on_finish_deployment_pressed() -> void:
	if _player_index == 0:
		_run_ai_deployment_if_needed(1)
		GameState.set_phase(GameState.Phase.DEPLOYMENT_P2)
		return

	_run_ai_deployment_if_needed(0)
	GameState.set_phase(GameState.Phase.GAMEPLAY)

func _run_ai_deployment_if_needed(player_index: int) -> void:
	if not _is_ai_controlled(player_index):
		return
	var result := DeploymentAIService.run_for_player(player_index)
	if not bool(result.get("ok", false)):
		push_warning("AI deployment planning failed for player %d (%s)." % [player_index + 1, String(result.get("reason", "unknown"))])

func _is_ai_controlled(player_index: int) -> bool:
	if player_index < 0 or player_index >= GameState.players.size():
		return false
	var player := GameState.players[player_index] as Dictionary
	if player.is_empty():
		return false
	if bool(player.get("is_ai", false)):
		return true
	var controller := String(player.get("controller", "human")).strip_edges().to_lower()
	return controller == "ai"

func _refresh_phase_ui(message: String) -> void:
	phase_label.text = "Deployment: Player %d" % (_player_index + 1)
	status_label.text = message
	var visible := {
		0: GameState.players[0].get("deployments", {}),
		1: GameState.players[1].get("deployments", {})
	}
	hex_map_view.configure(GameState.territory_map, visible, _player_index, true)
