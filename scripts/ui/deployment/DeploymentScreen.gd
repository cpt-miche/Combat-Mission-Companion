extends Control

const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")
const DeploymentAIService = preload("res://scripts/systems/deployment_ai/DeploymentAIService.gd")

@onready var phase_label: Label = %PhaseLabel
# Maintainer note: this is intentionally a Tree (not an ItemList) because deployment units are hierarchical,
# and operators need expand/collapse by command chain while still selecting leaf/parent nodes.
# Godot stable docs: Tree/TreeItem API used here →
# https://docs.godotengine.org/en/stable/classes/class_tree.html and
# https://docs.godotengine.org/en/stable/classes/class_treeitem.html
@onready var unit_list: Tree = %UnitList
@onready var status_label: Label = %StatusLabel
@onready var hex_map_view: DeploymentHexMapView = %HexMapView
@onready var p2_structure_label: Label = %P2StructureLabel
@onready var p2_structure_picker: OptionButton = %P2StructurePicker
@onready var finish_button: Button = %FinishDeploymentButton

var _player_index := 0
var _deployable_units: Array[Dictionary] = []
var _unplaced_deployable_unit_ids: Dictionary = {}
# Maintainer note: selected unit UI state lives in these two fields and is refreshed from TreeItem metadata.
var _selected_unit_id := ""
var _selected_unit_metadata: Dictionary = {}

func _ready() -> void:
	_player_index = 0 if GameState.current_phase == GameState.Phase.DEPLOYMENT_P1 else 1
	_ensure_players_initialized()
	_populate_p2_structure_picker()
	unit_list.columns = 1
	unit_list.hide_root = true
	_build_deployable_unit_list(false)
	_refresh_phase_ui("Select a unit, then click a hex in your territory.")

	hex_map_view.hex_selected.connect(_on_hex_selected)
	unit_list.item_selected.connect(_on_unit_item_selected)
	unit_list.item_activated.connect(_on_unit_item_activated)
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
		var option_tree := _namespace_division_tree_ids((option.get("tree", {}) as Dictionary), 1)
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
		return _namespace_division_tree_ids(tree, player_index)
	return _default_division_tree(player_index)

func _namespace_division_tree_ids(tree: Dictionary, player_index: int) -> Dictionary:
	var prefixed_tree := tree.duplicate(true)
	var player_prefix := "P%d" % (player_index + 1)
	_namespace_division_tree_ids_in_place(prefixed_tree, player_prefix)
	return prefixed_tree

func _namespace_division_tree_ids_in_place(node: Dictionary, player_prefix: String) -> void:
	var existing_id := String(node.get("id", ""))
	var id_prefix := "%s__" % player_prefix
	if not existing_id.is_empty() and not existing_id.begins_with(id_prefix):
		node["id"] = "%s%s" % [id_prefix, existing_id]

	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	var children := children_variant as Array
	for i in range(children.size()):
		if typeof(children[i]) != TYPE_DICTIONARY:
			continue
		var child_node := (children[i] as Dictionary).duplicate(true)
		_namespace_division_tree_ids_in_place(child_node, player_prefix)
		children[i] = child_node
	node["children"] = children

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
		"status": String(template_data.get("status", "alive")).to_lower(),
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
		_build_deployable_unit_list(false)
		if show_status:
			_refresh_phase_ui("Opponent structure updated.")

func _default_division_tree(player_index: int) -> Dictionary:
	var side_label := "P%d" % (player_index + 1)
	return {
		"id": "%s_hq" % side_label,
		"name": "%s HQ" % side_label,
		"type": "headquarters",
		"size": "army",
		"status": "alive",
		"children": [
			{
				"id": "%s_infantry_bn" % side_label,
				"name": "%s Infantry Battalion" % side_label,
				"type": "infantry",
				"size": "battalion",
				"status": "alive",
				"children": [
					{
						"id": "%s_bn_hq" % side_label,
						"name": "%s Battalion Headquarters" % side_label,
						"type": "headquarters",
						"size": "section",
						"status": "alive",
						"children": []
					},
					{
						"id": "%s_hq_company" % side_label,
						"name": "%s Headquarters Company" % side_label,
						"type": "headquarters",
						"size": "company",
						"status": "alive",
						"children": [
							{
								"id": "%s_hq_company_hq" % side_label,
								"name": "%s Company HQ" % side_label,
								"type": "headquarters",
								"size": "section",
								"status": "alive",
								"children": []
							},
							{
								"id": "%s_bn_hq_section" % side_label,
								"name": "%s Battalion HQ Section" % side_label,
								"type": "headquarters",
								"size": "section",
								"status": "alive",
								"children": []
							},
							{
								"id": "%s_antitank_platoon" % side_label,
								"name": "%s Antitank Platoon" % side_label,
								"type": "anti_tank",
								"size": "platoon",
								"status": "alive",
								"children": [
									{
										"id": "%s_antitank_platoon_hq" % side_label,
										"name": "%s Antitank Platoon HQ" % side_label,
										"type": "headquarters",
										"size": "section",
										"status": "alive",
										"children": []
									},
									{
										"id": "%s_antitank_squad_1" % side_label,
										"name": "%s Antitank Squad 1" % side_label,
										"type": "anti_tank",
										"size": "squad",
										"status": "alive",
										"children": []
									},
									{
										"id": "%s_antitank_squad_2" % side_label,
										"name": "%s Antitank Squad 2" % side_label,
										"type": "anti_tank",
										"size": "squad",
										"status": "alive",
										"children": []
									},
									{
										"id": "%s_antitank_squad_3" % side_label,
										"name": "%s Antitank Squad 3" % side_label,
										"type": "anti_tank",
										"size": "squad",
										"status": "alive",
										"children": []
									}
								]
							}
						]
					},
					{
						"id": "%s_rifle_company_a" % side_label,
						"name": "%s Rifle Company A" % side_label,
						"type": "infantry",
						"size": "company",
						"status": "alive",
						"children": _default_rifle_company_children(side_label, "a")
					},
					{
						"id": "%s_rifle_company_b" % side_label,
						"name": "%s Rifle Company B" % side_label,
						"type": "infantry",
						"size": "company",
						"status": "alive",
						"children": _default_rifle_company_children(side_label, "b")
					},
					{
						"id": "%s_rifle_company_c" % side_label,
						"name": "%s Rifle Company C" % side_label,
						"type": "infantry",
						"size": "company",
						"status": "alive",
						"children": _default_rifle_company_children(side_label, "c")
					},
					{
						"id": "%s_heavy_weapons_company" % side_label,
						"name": "%s Heavy Weapons Company" % side_label,
						"type": "infantry",
						"size": "company",
						"status": "alive",
						"children": [
							{
								"id": "%s_heavy_weapons_company_hq" % side_label,
								"name": "%s Heavy Weapons Company HQ" % side_label,
								"type": "headquarters",
								"size": "section",
								"status": "alive",
								"children": []
							},
							{
								"id": "%s_heavy_machine_gun_platoon_1" % side_label,
								"name": "%s Heavy Machine-Gun Platoon 1" % side_label,
								"type": "infantry",
								"size": "platoon",
								"status": "alive",
								"children": []
							},
							{
								"id": "%s_heavy_machine_gun_platoon_2" % side_label,
								"name": "%s Heavy Machine-Gun Platoon 2" % side_label,
								"type": "infantry",
								"size": "platoon",
								"status": "alive",
								"children": []
							}
						]
					}
				]
			}
		]
	}

func _default_rifle_company_children(side_label: String, company_suffix: String) -> Array:
	var company_tag := "%s_rifle_company_%s" % [side_label, company_suffix]
	var company_upper := company_suffix.to_upper()
	return [
		{
			"id": "%s_hq" % company_tag,
			"name": "%s Rifle Company %s HQ" % [side_label, company_upper],
			"type": "headquarters",
			"size": "section",
			"status": "alive",
			"children": []
		},
		_default_rifle_platoon(side_label, company_suffix, 1),
		_default_rifle_platoon(side_label, company_suffix, 2),
		_default_rifle_platoon(side_label, company_suffix, 3),
		{
			"id": "%s_weapons_platoon" % company_tag,
			"name": "%s Rifle Company %s Weapons Platoon" % [side_label, company_upper],
			"type": "infantry",
			"size": "platoon",
			"status": "alive",
			"children": []
		}
	]

func _default_rifle_platoon(side_label: String, company_suffix: String, platoon_number: int) -> Dictionary:
	var platoon_tag := "%s_rifle_company_%s_platoon_%d" % [side_label, company_suffix, platoon_number]
	return {
		"id": platoon_tag,
		"name": "%s Rifle Company %s Platoon %d" % [side_label, company_suffix.to_upper(), platoon_number],
		"type": "infantry",
		"size": "platoon",
		"status": "alive",
		"children": [
			{
				"id": "%s_hq" % platoon_tag,
				"name": "%s Platoon %d HQ" % [side_label, platoon_number],
				"type": "headquarters",
				"size": "section",
				"status": "alive",
				"children": []
			},
			{
				"id": "%s_squad_1" % platoon_tag,
				"name": "%s Platoon %d Rifle Squad 1" % [side_label, platoon_number],
				"type": "infantry",
				"size": "squad",
				"status": "alive",
				"children": []
			},
			{
				"id": "%s_squad_2" % platoon_tag,
				"name": "%s Platoon %d Rifle Squad 2" % [side_label, platoon_number],
				"type": "infantry",
				"size": "squad",
				"status": "alive",
				"children": []
			},
			{
				"id": "%s_squad_3" % platoon_tag,
				"name": "%s Platoon %d Rifle Squad 3" % [side_label, platoon_number],
				"type": "infantry",
				"size": "squad",
				"status": "alive",
				"children": []
			}
		]
	}

func _build_deployable_unit_list(preserve_ui_state: bool = true) -> void:
	var collapsed_by_unit_id := {}
	var previously_selected_unit_id := ""
	if preserve_ui_state:
		collapsed_by_unit_id = _collapsed_state_by_unit_id(unit_list.get_root())
		previously_selected_unit_id = _selected_unit_id

	unit_list.clear()
	unit_list.hide_root = true
	_deployable_units.clear()
	if not preserve_ui_state:
		_selected_unit_id = ""
		_selected_unit_metadata = {}
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var coordinates_by_unit_id := _deployment_coordinates_by_unit_id(deployments)

	var division_tree = GameState.players[_player_index].get("division_tree", {})
	var root_item := unit_list.create_item()
	_build_deployable_unit_tree_items(root_item, division_tree, coordinates_by_unit_id, collapsed_by_unit_id)
	_unplaced_deployable_unit_ids = _unplaced_deployable_unit_ids_from_coordinates(coordinates_by_unit_id)
	if preserve_ui_state and not previously_selected_unit_id.is_empty():
		_restore_selected_unit(previously_selected_unit_id)

func _build_deployable_unit_tree_items(parent_item: TreeItem, node: Variant, coordinates_by_unit_id: Dictionary = {}, collapsed_by_unit_id: Dictionary = {}) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return

	var unit_data := node as Dictionary
	if unit_data.is_empty():
		return

	var item := unit_list.create_item(parent_item)
	var block_reason := _deployability_block_reason(unit_data)
	var display_label := _unit_label(unit_data)
	var unit_id := String(unit_data.get("id", ""))
	# Maintainer note: "Placed: x,y" annotation is derived from deployments keyed by unit id.
	# `_deployment_coordinates_by_unit_id` builds that lookup from `GameState.players[*]["deployments"]`.
	var deployed_coordinate := String(coordinates_by_unit_id.get(unit_id, ""))
	var is_placed := not deployed_coordinate.is_empty()
	if is_placed:
		display_label += " (Placed: %s)" % deployed_coordinate
	if not block_reason.is_empty():
		display_label += "  [Not deployable: %s]" % block_reason
	item.set_text(0, display_label)
	item.set_selectable(0, block_reason.is_empty() or is_placed)
	if block_reason.is_empty() and not is_placed:
		item.set_custom_color(0, Color(1.0, 0.35, 0.35))
	item.set_metadata(0, {
		"unit": unit_data,
		"base_block_reason": block_reason,
		"unit_id": unit_id
	})
	_deployable_units.append(unit_data)

	var children_variant: Variant = unit_data.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return

	for child in children_variant:
		_build_deployable_unit_tree_items(item, child, coordinates_by_unit_id, collapsed_by_unit_id)

	if item.get_child_count() > 0:
		var was_collapsed := bool(collapsed_by_unit_id.get(unit_id, true))
		item.set_collapsed(was_collapsed)

func _on_unit_item_selected() -> void:
	var selected_item := unit_list.get_selected()
	if selected_item == null:
		_selected_unit_id = ""
		_selected_unit_metadata = {}
		return

	var selected_metadata_variant: Variant = selected_item.get_metadata(0)
	if typeof(selected_metadata_variant) != TYPE_DICTIONARY:
		_selected_unit_id = ""
		_selected_unit_metadata = {}
		return

	_selected_unit_metadata = (selected_metadata_variant as Dictionary).duplicate(true)
	_selected_unit_id = String(_selected_unit_metadata.get("unit_id", ""))

func _on_unit_item_activated() -> void:
	_on_unit_item_selected()


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
	if not GameState.is_unit_alive(unit):
		return "%s is dead and cannot be deployed." % _preferred_unit_name(unit)
	var snapshot := _unit_snapshot(unit)
	snapshot["name"] = _preferred_unit_name(unit)
	return DeploymentValidator.placement_block_reason(snapshot, [])

func _unit_label(unit: Dictionary) -> String:
	var size := _string_for_size(unit.get("size", "Unknown"))
	var type := _string_for_type(unit.get("type", "Unit"))
	var name := _preferred_unit_name(unit)
	return "%s - %s %s" % [name, size.capitalize(), type.capitalize()]

func _on_hex_selected(column: int, row: int) -> void:
	if _selected_unit_id.is_empty() or _selected_unit_metadata.is_empty():
		_refresh_phase_ui("Select a unit first.")
		return

	var unit_data_variant: Variant = _selected_unit_metadata.get("unit", {})
	if typeof(unit_data_variant) != TYPE_DICTIONARY or (unit_data_variant as Dictionary).is_empty():
		_refresh_phase_ui("Select a unit first.")
		return
	var unit_data := unit_data_variant as Dictionary

	var base_block_reason := String(_selected_unit_metadata.get("base_block_reason", ""))
	if not base_block_reason.is_empty():
		_refresh_phase_ui(base_block_reason)
		return

	var unit_snapshot := _unit_snapshot(unit_data)
	var unit_id := _selected_unit_id
	if unit_id.is_empty():
		unit_id = String(unit_snapshot.get("id", ""))
	var territory_owner := int(GameState.territory_map.get("%d,%d" % [column, row], GameState.TerritoryOwnership.NEUTRAL))
	if not DeploymentValidator.can_deploy_in_territory(territory_owner, _player_index):
		_refresh_phase_ui("Deployment must be inside your territory.")
		return

	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var target_key := "%d,%d" % [column, row]
	var existing_key := _deployment_key_for_unit_id(deployments, unit_id)
	var units_on_target_hex := _deployed_unit_snapshots_at_key(deployments, target_key)
	var filtered_units_on_target_hex: Array[Dictionary] = []
	for deployed_unit in units_on_target_hex:
		if String(deployed_unit.get("id", "")) == unit_id:
			continue
		filtered_units_on_target_hex.append(deployed_unit)

	var next_deployments := deployments.duplicate(true)
	if existing_key != "":
		next_deployments.erase(existing_key)

	var placement_block_reason := DeploymentValidator.placement_block_reason(unit_snapshot, filtered_units_on_target_hex)
	if not placement_block_reason.is_empty():
		_refresh_phase_ui(placement_block_reason)
		return

	next_deployments[target_key] = unit_snapshot
	GameState.players[_player_index]["deployments"] = next_deployments
	_build_deployable_unit_list()
	if existing_key.is_empty():
		_refresh_phase_ui("Placed %s at %d,%d." % [_unit_label(unit_data), column, row])
	else:
		_refresh_phase_ui("Moved %s from %s to %d,%d." % [_unit_label(unit_data), existing_key, column, row])

func _deployed_unit_snapshots(deployments: Dictionary) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for key in deployments.keys():
		var unit_data = deployments[key]
		if typeof(unit_data) == TYPE_DICTIONARY:
			units.append(unit_data)
	return units

func _deployed_unit_snapshots_at_key(deployments: Dictionary, key: String) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	if not deployments.has(key):
		return units
	var deployment_variant: Variant = deployments[key]
	if typeof(deployment_variant) == TYPE_DICTIONARY:
		units.append(deployment_variant as Dictionary)
	elif typeof(deployment_variant) == TYPE_ARRAY:
		for unit_variant in (deployment_variant as Array):
			if typeof(unit_variant) == TYPE_DICTIONARY:
				units.append(unit_variant as Dictionary)
	return units

func _collapsed_state_by_unit_id(root_item: TreeItem) -> Dictionary:
	var collapsed_by_unit_id := {}
	_collect_collapsed_state(root_item, collapsed_by_unit_id)
	return collapsed_by_unit_id

func _collect_collapsed_state(item: TreeItem, collapsed_by_unit_id: Dictionary) -> void:
	if item == null:
		return
	var metadata_variant: Variant = item.get_metadata(0)
	if typeof(metadata_variant) == TYPE_DICTIONARY:
		var metadata := metadata_variant as Dictionary
		var unit_id := String(metadata.get("unit_id", ""))
		if not unit_id.is_empty() and item.get_child_count() > 0:
			collapsed_by_unit_id[unit_id] = item.is_collapsed()

	var child := item.get_first_child()
	while child != null:
		_collect_collapsed_state(child, collapsed_by_unit_id)
		child = child.get_next()

func _restore_selected_unit(unit_id: String) -> void:
	var item := _find_tree_item_by_unit_id(unit_list.get_root(), unit_id)
	if item == null:
		_selected_unit_id = ""
		_selected_unit_metadata = {}
		return
	item.select(0)
	var selected_metadata_variant: Variant = item.get_metadata(0)
	if typeof(selected_metadata_variant) == TYPE_DICTIONARY:
		_selected_unit_metadata = (selected_metadata_variant as Dictionary).duplicate(true)
		_selected_unit_id = unit_id
	else:
		_selected_unit_id = ""
		_selected_unit_metadata = {}

func _find_tree_item_by_unit_id(item: TreeItem, unit_id: String) -> TreeItem:
	if item == null:
		return null
	var metadata_variant: Variant = item.get_metadata(0)
	if typeof(metadata_variant) == TYPE_DICTIONARY:
		var metadata := metadata_variant as Dictionary
		if String(metadata.get("unit_id", "")) == unit_id:
			return item

	var child := item.get_first_child()
	while child != null:
		var found := _find_tree_item_by_unit_id(child, unit_id)
		if found != null:
			return found
		child = child.get_next()
	return null

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

func _deployment_coordinates_by_unit_id(deployments: Dictionary) -> Dictionary:
	var coordinates_by_unit_id := {}
	for key in deployments.keys():
		var unit_data = deployments[key]
		if typeof(unit_data) != TYPE_DICTIONARY:
			continue
		var unit_id := String((unit_data as Dictionary).get("id", ""))
		if unit_id.is_empty():
			continue
		coordinates_by_unit_id[unit_id] = String(key)
	return coordinates_by_unit_id

func _unplaced_deployable_unit_ids_from_coordinates(coordinates_by_unit_id: Dictionary) -> Dictionary:
	var unplaced_by_id := {}
	for deployable_unit in _deployable_units:
		if not _is_deployable(deployable_unit):
			continue
		var unit_id := String(deployable_unit.get("id", ""))
		if unit_id.is_empty():
			continue
		if coordinates_by_unit_id.has(unit_id):
			continue
		unplaced_by_id[unit_id] = true
	return unplaced_by_id

func _unit_snapshot(unit: Dictionary) -> Dictionary:
	# Maintainer note: keep `_unit_snapshot`, `_string_for_type`, `_string_for_size`, `_size_rank`,
	# `_preferred_unit_name`, and `_preferred_short_name` aligned with DeploymentValidator contracts
	# (`can_deploy_in_territory` / `placement_block_reason`) so UI checks and validator checks stay identical.
	var unit_type := _string_for_type(unit.get("type", ""))
	var unit_size := _string_for_size(unit.get("size", ""))
	var preferred_name := _preferred_unit_name(unit)
	var preferred_short_name := _preferred_short_name(unit, preferred_name)
	return {
		"id": unit.get("id", ""),
		"name": preferred_name,
		"type": unit_type,
		"size": unit_size,
		"status": String(unit.get("status", "alive")).to_lower(),
		"is_alive": bool(unit.get("is_alive", String(unit.get("status", "alive")).to_lower() != "dead")),
		"size_rank": _size_rank(unit_size),
		"label": preferred_short_name.substr(0, 2).to_upper(),
		"is_tank": unit_type == "tank",
		"is_headquarters": unit_type == "headquarters",
		"is_battalion": unit_size == "battalion",
		"is_company": unit_size == "company",
		"is_platoon": unit_size == "platoon"
	}

func _preferred_unit_name(unit: Dictionary) -> String:
	var name := String(unit.get("name", "")).strip_edges()
	if not name.is_empty():
		return name

	var display_name := String(unit.get("display_name", "")).strip_edges()
	if not display_name.is_empty():
		return display_name

	var short_name := String(unit.get("short_name", "")).strip_edges()
	if not short_name.is_empty():
		return short_name

	var fallback_id := String(unit.get("id", "")).strip_edges()
	if fallback_id.is_empty() or fallback_id.begins_with("unit_"):
		return "Unnamed Unit"
	return fallback_id

func _preferred_short_name(unit: Dictionary, fallback_name: String) -> String:
	var short_name := String(unit.get("short_name", "")).strip_edges()
	if not short_name.is_empty():
		return short_name
	return fallback_name

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
	var unplaced_count := _unplaced_deployable_unit_ids.size()
	if unplaced_count > 0:
		_build_deployable_unit_list()
		_refresh_phase_ui("Place all deployable units before submitting (%d remaining)." % unplaced_count)
		return

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
