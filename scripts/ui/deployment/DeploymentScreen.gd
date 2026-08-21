extends Control

const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")
const DeploymentAIService = preload("res://scripts/systems/deployment_ai/DeploymentAIService.gd")
const TerrainCatalog = preload("res://scripts/core/TerrainCatalog.gd")
const UnitNotationFormatter = preload("res://scripts/domain/units/UnitNotationFormatter.gd")
const NatoUnitSymbolRenderer = preload("res://scripts/ui/shared/NatoUnitSymbolRenderer.gd")
const FormationHierarchyModel = preload("res://scripts/domain/units/FormationHierarchy.gd")
const UNDEPLOYED_WARNING_COLOR := Color(1.0, 0.35, 0.35)

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
@onready var save_scenario_button: Button = %SaveScenarioButton
@onready var finish_button: Button = %FinishDeploymentButton
@onready var scenario_save_dialog: ConfirmationDialog = %ScenarioSaveDialog
@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var overwrite_scenario_dialog: ConfirmationDialog = %OverwriteScenarioDialog
@onready var selected_hex_title_label: Label = %SelectedHexTitleLabel
@onready var selected_hex_ownership_label: Label = %SelectedHexOwnershipLabel
@onready var selected_hex_terrain_label: Label = %SelectedHexTerrainLabel
@onready var selected_hex_count_label: Label = %SelectedHexCountLabel
@onready var selected_hex_unit_cards: VBoxContainer = %SelectedHexUnitCards
@onready var root_margin: MarginContainer = $RootMargin
@onready var scenario_editor_chrome: Control = %ScenarioEditorChrome

var _player_index := 0
var _deployable_units: Array[Dictionary] = []
var _unplaced_deployable_unit_ids: Dictionary = {}
# Maintainer note: selected unit UI state lives in these two fields and is refreshed from TreeItem metadata.
var _selected_unit_id := ""
var _selected_unit_metadata: Dictionary = {}
var _selected_unit_ids: Array[String] = []
var _selected_unit_metadata_by_id: Dictionary = {}
var _inspected_deployment_unit_id := ""
var _setting_group_tree_selection := false
var _selected_hex := Vector2i(-1, -1)
var _pending_scenario_name := ""

func _ready() -> void:
	_player_index = 0 if GameState.current_phase == GameState.Phase.DEPLOYMENT_P1 else 1
	_ensure_players_initialized()
	_populate_p2_structure_picker()
	unit_list.columns = 1
	unit_list.hide_root = true
	_build_deployable_unit_list(false)
	_refresh_phase_ui("Select a unit, then click a hex in your territory.")

	hex_map_view.hex_selected.connect(_on_hex_selected)
	hex_map_view.hex_stack_selected.connect(_on_hex_stack_selected)
	hex_map_view.hex_undeploy_requested.connect(_on_hex_undeploy_requested)
	hex_map_view.deployment_cancel_requested.connect(_on_deployment_cancel_requested)
	unit_list.item_selected.connect(_on_unit_item_selected)
	unit_list.item_activated.connect(_on_unit_item_activated)
	p2_structure_picker.item_selected.connect(_on_p2_structure_selected)
	save_scenario_button.pressed.connect(_on_save_scenario_pressed)
	finish_button.pressed.connect(_on_finish_deployment_pressed)
	scenario_save_dialog.confirmed.connect(_on_scenario_save_confirmed)
	overwrite_scenario_dialog.confirmed.connect(_on_overwrite_scenario_confirmed)
	save_scenario_button.visible = false
	_refresh_selected_hex_panel()
	_configure_scenario_editor_mode()

func _configure_scenario_editor_mode() -> void:
	if not ScenarioEditorState.active:
		return
	root_margin.offset_top = 56.0
	ScenarioEditorState.set_step(
		ScenarioEditorState.Step.PLAYER_1_DEPLOYMENT if _player_index == 0 else ScenarioEditorState.Step.PLAYER_2_DEPLOYMENT,
		_player_index
	)
	scenario_editor_chrome.configure()
	scenario_editor_chrome.back_requested.connect(_on_scenario_editor_back)
	scenario_editor_chrome.before_draft_save.connect(_on_scenario_editor_before_draft_save)
	p2_structure_label.visible = false
	p2_structure_picker.visible = false
	save_scenario_button.visible = false
	finish_button.text = "Continue to Player 2 Deployment" if _player_index == 0 else "Review Scenario"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not _selected_deployment_unit_ids().is_empty():
		_on_deployment_cancel_requested()
		get_viewport().set_input_as_handled()

func _ensure_players_initialized() -> void:
	while GameState.players.size() < 2:
		var player_index := GameState.players.size()
		GameState.players.append({
			"name": "Player %d" % (player_index + 1),
			"division_tree": {},
			"deployments": {},
			"controller": "ai" if player_index == 1 else "human"
		})

	for i in range(2):
		var player := GameState.players[i]
		if not player.has("division_tree"):
			player["division_tree"] = {}
		if (player.get("division_tree", {}) as Dictionary).is_empty():
			player["division_tree"] = _best_default_structure_for_player(i)
		if not GameState.players[i].has("deployments"):
			GameState.players[i]["deployments"] = {}
		if not player.has("controller"):
			player["controller"] = "ai" if i == 1 else "human"
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
		"template_id": local_tree_id,
		"name": tree_name,
		"type": String(template_data.get("type", "INFANTRY")).to_lower(),
		"role": UnitRole.normalize(template_data.get("role", ""), template_data.get("type", "INFANTRY")),
		"equipment_weight": NatoUnitSymbolRenderer.equipment_weight_for_unit(template_data),
		"size": String(template_data.get("size", "COMPANY")).to_lower(),
		"is_attached": false,
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
						"id": "%s_hq_company" % side_label,
						"name": "%s Headquarters Company" % side_label,
						"type": "headquarters",
						"size": "company",
						"status": "alive",
						"children": [
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
		_default_rifle_company_weapons_platoon(side_label, company_suffix)
	]

func _default_rifle_company_weapons_platoon(side_label: String, company_suffix: String) -> Dictionary:
	var company_tag := "%s_rifle_company_%s" % [side_label, company_suffix]
	var weapons_platoon_tag := "%s_weapons_platoon" % company_tag
	return {
		"id": weapons_platoon_tag,
		"name": "%s Rifle Company %s Weapons Platoon" % [side_label, company_suffix.to_upper()],
		"type": "infantry",
		"size": "platoon",
		"status": "alive",
		"children": [
			{
				"id": "%s_hq" % weapons_platoon_tag,
				"name": "%s Weapons Platoon HQ" % side_label,
				"type": "headquarters",
				"size": "section",
				"status": "alive",
				"children": []
			},
			{
				"id": "%s_mmg_section" % weapons_platoon_tag,
				"name": "%s Weapons Platoon MMG Section" % side_label,
				"type": "infantry",
				"size": "section",
				"status": "alive",
				"children": []
			},
			{
				"id": "%s_mortar_section" % weapons_platoon_tag,
				"name": "%s Weapons Platoon Mortar Section" % side_label,
				"type": "infantry",
				"size": "section",
				"status": "alive",
				"children": []
			}
		]
	}

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
		_selected_unit_ids.clear()
		_selected_unit_metadata_by_id.clear()
		_inspected_deployment_unit_id = ""
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var coordinates_by_unit_id := _deployment_coordinates_by_unit_id(deployments)

	var division_tree = GameState.players[_player_index].get("division_tree", {})
	var covered_unit_ids := _unit_ids_covered_by_higher_echelon_deployments()
	var subordinate_covered_unit_ids := _unit_ids_covered_by_lower_echelon_deployments()
	var root_item := unit_list.create_item()
	_build_deployable_unit_tree_items(root_item, division_tree, coordinates_by_unit_id, collapsed_by_unit_id, covered_unit_ids, subordinate_covered_unit_ids)
	_unplaced_deployable_unit_ids = _unplaced_deployable_unit_ids_from_coordinates(coordinates_by_unit_id)
	_apply_incomplete_deployment_colors()
	if preserve_ui_state and not previously_selected_unit_id.is_empty():
		_restore_selected_unit(previously_selected_unit_id)

func _build_deployable_unit_tree_items(parent_item: TreeItem, node: Variant, coordinates_by_unit_id: Dictionary = {}, collapsed_by_unit_id: Dictionary = {}, _covered_unit_ids: Dictionary = {}, subordinate_covered_unit_ids: Dictionary = {}) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return

	var unit_data := node as Dictionary
	if unit_data.is_empty():
		return
	if _string_for_size(unit_data.get("size", "")) == "squad":
		return

	var item := unit_list.create_item(parent_item)
	var display_label := _unit_label(unit_data)
	var unit_id := String(unit_data.get("id", ""))
	# Maintainer note: "Placed: x,y" annotation is derived from deployments keyed by unit id.
	# `_deployment_coordinates_by_unit_id` builds that lookup from `GameState.players[*]["deployments"]`.
	var deployed_coordinate := String(coordinates_by_unit_id.get(unit_id, ""))
	var is_placed := not deployed_coordinate.is_empty()
	var is_covered_by_lower_echelon := subordinate_covered_unit_ids.has(unit_id)
	var block_reason := _deployability_block_reason(unit_data)
	if is_covered_by_lower_echelon and not is_placed:
		block_reason = "All deployable subordinate branches are already deployed."
	if is_placed:
		display_label += " (Placed: %s)" % deployed_coordinate
	if not block_reason.is_empty():
		display_label += "  [Not deployable: %s]" % block_reason
	item.set_text(0, display_label)
	item.set_selectable(0, block_reason.is_empty() or is_placed)
	if is_covered_by_lower_echelon and not is_placed:
		display_label += " (Covered by subordinates)"
		item.set_text(0, display_label)
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
		_build_deployable_unit_tree_items(item, child, coordinates_by_unit_id, collapsed_by_unit_id, _covered_unit_ids, subordinate_covered_unit_ids)

	if item.get_child_count() > 0:
		var was_collapsed := bool(collapsed_by_unit_id.get(unit_id, true))
		item.set_collapsed(was_collapsed)

func _on_unit_item_selected() -> void:
	if _setting_group_tree_selection:
		return
	var selected_item := unit_list.get_selected()
	if selected_item == null:
		_clear_deployment_selection_state()
		return

	var selected_metadata_variant: Variant = selected_item.get_metadata(0)
	if typeof(selected_metadata_variant) != TYPE_DICTIONARY:
		_clear_deployment_selection_state()
		return

	_selected_unit_metadata = (selected_metadata_variant as Dictionary).duplicate(true)
	_selected_unit_id = String(_selected_unit_metadata.get("unit_id", ""))
	_selected_unit_ids.clear()
	_selected_unit_metadata_by_id.clear()
	if not _selected_unit_id.is_empty():
		_selected_unit_ids.append(_selected_unit_id)
		_selected_unit_metadata_by_id[_selected_unit_id] = _selected_unit_metadata.duplicate(true)
	if not _inspected_deployment_unit_id.is_empty() and _inspected_deployment_unit_id != _selected_unit_id:
		_inspected_deployment_unit_id = ""
	_sync_map_selection()
	_refresh_selected_hex_panel()

func _on_unit_item_activated() -> void:
	_on_unit_item_selected()

func _string_for_type(raw_type: Variant) -> String:
	return String(raw_type).to_lower()

func _string_for_size(raw_size: Variant) -> String:
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
	var role := _role_display_name(unit)
	var name := _preferred_unit_name(unit)
	return "%s — %s — %s" % [name, size.capitalize(), role]

func _role_display_name(unit: Dictionary) -> String:
	var role := UnitRole.normalize(unit.get("role", ""), unit.get("type", ""))
	return UnitRole.display_name(role, unit.get("type", ""))

func _on_hex_selected(column: int, row: int) -> void:
	var selected_unit_ids := _selected_deployment_unit_ids()
	if selected_unit_ids.is_empty():
		_inspected_deployment_unit_id = ""
	_selected_hex = Vector2i(column, row)
	_sync_map_selection()
	_refresh_selected_hex_panel()
	if selected_unit_ids.is_empty():
		_refresh_phase_ui("Selected hex %d,%d." % [column, row])
		return
	if selected_unit_ids.size() > 1:
		_move_selected_deployment_group(column, row, selected_unit_ids)
		return
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
	if existing_key == target_key:
		_refresh_phase_ui("%s is already at %s." % [_unit_label(unit_data), target_key])
		return
	var same_hex_related_unit_id := _deployed_related_formation_id_at_key_for_unit_id(deployments, unit_id, target_key)
	if not same_hex_related_unit_id.is_empty():
		_refresh_phase_ui("%s is already covered by a related formation at %s." % [_unit_label(unit_data), target_key])
		return

	if existing_key.is_empty():
		var hierarchy_block_reason := _hierarchy_placement_block_reason(unit_id, deployments)
		if not hierarchy_block_reason.is_empty():
			_refresh_phase_ui(hierarchy_block_reason)
			return
		var deployed_company_block_reason := _battalion_with_deployed_companies_block_reason(unit_snapshot, deployments, unit_id)
		if not deployed_company_block_reason.is_empty():
			_refresh_phase_ui(deployed_company_block_reason)
			return

	var units_on_target_hex := _deployed_unit_snapshots_at_key(deployments, target_key)
	var filtered_units_on_target_hex: Array[Dictionary] = []
	for deployed_unit in units_on_target_hex:
		if String(deployed_unit.get("id", "")) == unit_id:
			continue
		filtered_units_on_target_hex.append(deployed_unit)

	var next_deployments := deployments.duplicate(true)
	if existing_key != "":
		_remove_deployment_unit_at_key(next_deployments, existing_key, unit_id)

	var placement_block_reason := DeploymentValidator.placement_block_reason(unit_snapshot, filtered_units_on_target_hex)
	if not placement_block_reason.is_empty():
		_refresh_phase_ui(placement_block_reason)
		return

	_add_deployment_unit_at_key(next_deployments, target_key, unit_snapshot)
	var removed_parent_names := _remove_redundant_deployed_ancestors(next_deployments, [unit_id])
	GameState.players[_player_index]["deployments"] = next_deployments
	var action_message := "Placed %s at %d,%d." % [_unit_label(unit_data), column, row] if existing_key.is_empty() else "Moved %s from %s to %d,%d." % [_unit_label(unit_data), existing_key, column, row]
	if not removed_parent_names.is_empty():
		action_message += " Removed redundant %s." % ", ".join(removed_parent_names)
	_clear_armed_unit()
	_build_deployable_unit_list()
	_refresh_selected_hex_panel()
	_refresh_phase_ui(action_message)

func _on_hex_stack_selected(column: int, row: int) -> void:
	_selected_hex = Vector2i(column, row)
	var key := "%d,%d" % [column, row]
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var units := _deployed_unit_snapshots_at_key(deployments, key)
	_clear_deployment_selection_state()
	unit_list.deselect_all()
	if units.is_empty():
		_sync_map_selection()
		_refresh_selected_hex_panel()
		_refresh_phase_ui("Selected hex %s; no deployed units to select." % key)
		return

	for unit in units:
		var unit_id := String(unit.get("id", ""))
		if unit_id.is_empty() or _selected_unit_ids.has(unit_id):
			continue
		var metadata := _selection_metadata_for_unit_id(unit_id)
		if metadata.is_empty():
			continue
		_selected_unit_ids.append(unit_id)
		_selected_unit_metadata_by_id[unit_id] = metadata
	if _selected_unit_ids.is_empty():
		_sync_map_selection()
		_refresh_selected_hex_panel()
		_refresh_phase_ui("Selected hex %s; no movable deployed units found." % key)
		return

	_selected_unit_id = _selected_unit_ids[_selected_unit_ids.size() - 1]
	_selected_unit_metadata = (_selected_unit_metadata_by_id[_selected_unit_id] as Dictionary).duplicate(true)
	_inspected_deployment_unit_id = _selected_unit_id
	var primary_item := _find_tree_item_by_unit_id(unit_list.get_root(), _selected_unit_id)
	if primary_item != null:
		_setting_group_tree_selection = true
		primary_item.select(0)
		_setting_group_tree_selection = false
	_sync_map_selection()
	_refresh_selected_hex_panel()
	_refresh_phase_ui("Selected %d deployed units at %s. Click a destination hex to move the complete stack." % [_selected_unit_ids.size(), key])

func _move_selected_deployment_group(column: int, row: int, unit_ids: Array[String]) -> void:
	var target_key := "%d,%d" % [column, row]
	var territory_owner := int(GameState.territory_map.get(target_key, GameState.TerritoryOwnership.NEUTRAL))
	if not DeploymentValidator.can_deploy_in_territory(territory_owner, _player_index):
		_refresh_phase_ui("Deployment must be inside your territory. No selected units moved.")
		return

	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var source_key := ""
	for unit_id in unit_ids:
		var unit_key := _deployment_key_for_unit_id(deployments, unit_id)
		if unit_key.is_empty():
			_refresh_phase_ui("The selected stack changed; %s is no longer independently deployed. No units moved." % _preferred_unit_name(_division_unit_by_id(unit_id)))
			return
		if source_key.is_empty():
			source_key = unit_key
		elif unit_key != source_key:
			_refresh_phase_ui("Selected units are no longer on the same source hex. No units moved.")
			return
	if source_key == target_key:
		_refresh_phase_ui("The selected stack is already at %s." % target_key)
		return

	var next_deployments := deployments.duplicate(true)
	for unit_id in unit_ids:
		_remove_deployment_unit_at_key(next_deployments, source_key, unit_id)

	var projected_units := _deployed_unit_snapshots_at_key(next_deployments, target_key)
	for unit_id in unit_ids:
		var unit_data := _division_unit_by_id(unit_id)
		if unit_data.is_empty():
			_refresh_phase_ui("A selected unit is missing from the formation hierarchy. No units moved.")
			return
		var related_unit_id := _deployed_related_formation_id_at_key_for_unit_id(next_deployments, unit_id, target_key)
		if not related_unit_id.is_empty():
			_refresh_phase_ui("%s is already covered by a related formation at %s. No selected units moved." % [_preferred_unit_name(unit_data), target_key])
			return
		var unit_snapshot := _unit_snapshot(unit_data)
		var placement_block_reason := DeploymentValidator.placement_block_reason(unit_snapshot, projected_units)
		if not placement_block_reason.is_empty():
			_refresh_phase_ui("%s No selected units moved." % placement_block_reason)
			return
		_add_deployment_unit_at_key(next_deployments, target_key, unit_snapshot)
		projected_units.append(unit_snapshot)

	var removed_parent_names := _remove_redundant_deployed_ancestors(next_deployments, unit_ids)
	GameState.players[_player_index]["deployments"] = next_deployments
	var action_message := "Moved %d units from %s to %s." % [unit_ids.size(), source_key, target_key]
	if not removed_parent_names.is_empty():
		action_message += " Removed redundant %s." % ", ".join(removed_parent_names)
	_clear_armed_unit()
	_build_deployable_unit_list()
	_refresh_selected_hex_panel()
	_refresh_phase_ui(action_message)

func _on_hex_undeploy_requested(column: int, row: int) -> void:
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var target_key := "%d,%d" % [column, row]
	var deployed_units := _deployed_unit_snapshots_at_key(deployments, target_key)
	if deployed_units.is_empty():
		_refresh_phase_ui("No deployed units at %s." % target_key)
		return

	var next_deployments := deployments.duplicate(true)
	next_deployments.erase(target_key)
	GameState.players[_player_index]["deployments"] = next_deployments
	for selected_unit_id in _selected_deployment_unit_ids():
		if _deployed_units_include_id(deployed_units, selected_unit_id):
			_clear_deployment_selection_state()
			break
	_build_deployable_unit_list()
	_refresh_selected_hex_panel()
	_refresh_phase_ui("Undeployed %s from %s." % [_unit_summary(deployed_units), target_key])

func _on_deployment_cancel_requested() -> void:
	if _selected_deployment_unit_ids().is_empty():
		return
	_clear_armed_unit()
	_refresh_phase_ui("Unit selection cancelled.")

func _refresh_selected_hex_panel() -> void:
	_clear_selected_hex_unit_cards()
	if _selected_hex.x < 0 or _selected_hex.y < 0:
		selected_hex_title_label.text = "Selected Hex: -, -"
		selected_hex_ownership_label.text = "Owner: None"
		selected_hex_terrain_label.text = "Terrain: %s" % TerrainCatalog.display_name(TerrainCatalog.default_terrain_id())
		selected_hex_count_label.text = "Unit Count: 0"
		_add_selected_hex_empty_state("No hex selected.")
		return

	var key := "%d,%d" % [_selected_hex.x, _selected_hex.y]
	selected_hex_title_label.text = "Selected Hex: %s" % key
	selected_hex_ownership_label.text = "Owner: %s" % _territory_owner_name(int(GameState.territory_map.get(key, GameState.TerritoryOwnership.NEUTRAL)))
	var terrain_id := TerrainCatalog.normalize_terrain_id(String(GameState.terrain_map.get(key, TerrainCatalog.default_terrain_id())))
	selected_hex_terrain_label.text = "Terrain: %s" % TerrainCatalog.display_name(terrain_id)
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var units := _deployed_unit_snapshots_at_key(deployments, key)
	selected_hex_count_label.text = "Unit Count: %d" % units.size()
	for unit in units:
		_add_selected_hex_unit_card(unit)
	if units.is_empty():
		_add_selected_hex_empty_state("No friendly units deployed here.")
	if not _inspected_deployment_unit_id.is_empty():
		_add_deployment_subunit_inspector(_inspected_deployment_unit_id)

func _clear_selected_hex_unit_cards() -> void:
	for child in selected_hex_unit_cards.get_children():
		selected_hex_unit_cards.remove_child(child)
		child.queue_free()

func _add_selected_hex_empty_state(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_hex_unit_cards.add_child(label)

func _add_selected_hex_unit_card(unit: Dictionary) -> void:
	var unit_id := String(unit.get("id", ""))
	var card := Button.new()
	card.text = _selected_hex_unit_card_text(unit)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.custom_minimum_size = Vector2(0.0, 76.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("unit_id", unit_id)
	_apply_selected_hex_card_theme(card, _is_deployment_unit_selected(unit_id))
	card.pressed.connect(_on_selected_hex_unit_card_pressed.bind(unit_id))
	selected_hex_unit_cards.add_child(card)

func _selected_hex_unit_card_text(unit: Dictionary) -> String:
	var identity := UnitNotationFormatter.format_counter_unit(unit)
	var display_name := String(unit.get("display_name", unit.get("short_name", "Unit")))
	var capped_display_name := UnitNotationFormatter.format_counter_unit({"short_name": display_name})
	var name_line := identity
	if display_name == capped_display_name and display_name != identity:
		name_line += " — %s" % display_name
	var summary := "%s\n%s — %s" % [name_line, String(unit.get("size", "unit")).capitalize(), _role_display_name(unit)]
	if unit.has("max_sub_units"):
		summary += "\nVehicles: %d/%d" % [int(unit.get("live_sub_units", 0)), int(unit.get("max_sub_units", 0))]
	if _is_deployment_unit_selected(String(unit.get("id", ""))):
		var armed_label := "ARMED AS GROUP" if _selected_deployment_unit_ids().size() > 1 else "ARMED TO MOVE"
		summary = "%s\n%s" % [armed_label, summary]
	return summary

func _apply_selected_hex_card_theme(card: Button, selected: bool) -> void:
	var background := Color(0.10, 0.13, 0.17, 0.98) if not selected else Color(0.24, 0.20, 0.07, 0.98)
	var border := Color(0.34, 0.40, 0.48, 0.9) if not selected else Color(1.0, 0.86, 0.28, 1.0)
	for state in ["normal", "disabled"]:
		card.add_theme_stylebox_override(state, _selected_hex_card_style(background, border, 2 if selected else 1))
	card.add_theme_stylebox_override("hover", _selected_hex_card_style(background.lightened(0.08), border, 2 if selected else 1))
	card.add_theme_stylebox_override("pressed", _selected_hex_card_style(background.darkened(0.05), border, 2 if selected else 1))
	card.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	card.add_theme_color_override("font_hover_color", Color.WHITE)
	card.add_theme_color_override("font_pressed_color", Color.WHITE)

func _selected_hex_card_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	return style

func _on_selected_hex_unit_card_pressed(unit_id: String) -> void:
	if unit_id.is_empty():
		return
	_focus_deployment_unit(unit_id, true)

func _on_deployment_subunit_pressed(unit_id: String) -> void:
	if unit_id.is_empty():
		return
	_focus_deployment_unit(unit_id, true)

func _focus_deployment_unit(unit_id: String, jump_to_independent_marker: bool) -> void:
	var item := _find_tree_item_by_unit_id(unit_list.get_root(), unit_id)
	if item != null:
		var parent := item.get_parent()
		while parent != null:
			parent.set_collapsed(false)
			parent = parent.get_parent()
	_restore_selected_unit(unit_id)
	if _selected_unit_id != unit_id:
		var canonical_unit := _division_unit_by_id(unit_id)
		var block_reason := _deployability_block_reason(canonical_unit) if not canonical_unit.is_empty() else "Unit not found."
		if canonical_unit.is_empty() or not block_reason.is_empty():
			return
		_selected_unit_id = unit_id
		_selected_unit_metadata = {
			"unit": canonical_unit.duplicate(true),
			"base_block_reason": "",
			"unit_id": unit_id
		}
	_selected_unit_ids.clear()
	_selected_unit_ids.append(unit_id)
	_selected_unit_metadata_by_id.clear()
	_selected_unit_metadata_by_id[unit_id] = _selected_unit_metadata.duplicate(true)
	_inspected_deployment_unit_id = unit_id
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var deployment_key := _deployment_key_for_unit_id(deployments, unit_id)
	if jump_to_independent_marker and not deployment_key.is_empty():
		var marker_coordinate := _coordinate_from_key(deployment_key)
		if marker_coordinate.x >= 0 and marker_coordinate.y >= 0:
			_selected_hex = marker_coordinate
	_sync_map_selection()
	_refresh_selected_hex_panel()
	_refresh_phase_ui("%s armed. Click a destination hex to move it." % _preferred_unit_name((_selected_unit_metadata.get("unit", {}) as Dictionary)))

func _clear_armed_unit() -> void:
	_clear_deployment_selection_state()
	unit_list.deselect_all()
	_sync_map_selection()
	_refresh_selected_hex_panel()

func _sync_map_selection() -> void:
	hex_map_view.set_selected_hex(_selected_hex)
	var visible_marker_ids: Array[String] = []
	for unit_id in _selected_deployment_unit_ids():
		var marker_id := _visible_deployment_marker_id_for_unit(unit_id)
		if not marker_id.is_empty() and not visible_marker_ids.has(marker_id):
			visible_marker_ids.append(marker_id)
	hex_map_view.set_armed_units(visible_marker_ids, _visible_deployment_marker_id_for_unit(_selected_unit_id))

func _selected_deployment_unit_ids() -> Array[String]:
	var selected: Array[String] = []
	for unit_id in _selected_unit_ids:
		if not unit_id.is_empty() and not selected.has(unit_id):
			selected.append(unit_id)
	if selected.is_empty() and not _selected_unit_id.is_empty():
		selected.append(_selected_unit_id)
	return selected

func _is_deployment_unit_selected(unit_id: String) -> bool:
	return not unit_id.is_empty() and _selected_deployment_unit_ids().has(unit_id)

func _clear_deployment_selection_state() -> void:
	_selected_unit_id = ""
	_selected_unit_metadata = {}
	_selected_unit_ids.clear()
	_selected_unit_metadata_by_id.clear()
	_inspected_deployment_unit_id = ""

func _selection_metadata_for_unit_id(unit_id: String) -> Dictionary:
	var item := _find_tree_item_by_unit_id(unit_list.get_root(), unit_id)
	if item != null:
		var metadata_variant: Variant = item.get_metadata(0)
		if typeof(metadata_variant) == TYPE_DICTIONARY:
			return (metadata_variant as Dictionary).duplicate(true)
	var unit := _division_unit_by_id(unit_id)
	if unit.is_empty():
		return {}
	return {
		"unit": unit.duplicate(true),
		"base_block_reason": _deployability_block_reason(unit),
		"unit_id": unit_id
	}

func _add_deployment_subunit_inspector(unit_id: String) -> void:
	var inspected_unit := _division_unit_by_id(unit_id)
	if inspected_unit.is_empty():
		_inspected_deployment_unit_id = ""
		return

	selected_hex_unit_cards.add_child(HSeparator.new())
	var header := Label.new()
	header.text = "Subunits of %s" % _preferred_unit_name(inspected_unit)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.28))
	header.add_theme_font_size_override("font_size", 16)
	selected_hex_unit_cards.add_child(header)

	var children_variant: Variant = inspected_unit.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY or (children_variant as Array).is_empty():
		_add_selected_hex_empty_state("No subunits.")
		return

	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var coordinates_by_unit_id := _deployment_coordinates_by_unit_id(deployments)
	for child_variant in (children_variant as Array):
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		_add_deployment_subunit_card(child_variant as Dictionary, coordinates_by_unit_id)

func _add_deployment_subunit_card(unit: Dictionary, coordinates_by_unit_id: Dictionary) -> void:
	var unit_id := String(unit.get("id", ""))
	var block_reason := _deployability_block_reason(unit)
	var relationship := _deployment_relationship_for_branch(unit, coordinates_by_unit_id)
	var card := Button.new()
	card.text = _deployment_subunit_card_text(unit, relationship, block_reason)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.custom_minimum_size = Vector2(0.0, 68.0 if block_reason.is_empty() else 86.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = not block_reason.is_empty()
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if card.disabled else Control.CURSOR_POINTING_HAND
	card.set_meta("subunit_id", unit_id)
	card.set_meta("attachment_status", String(relationship.get("status", "Attached")))
	_apply_selected_hex_card_theme(card, _is_deployment_unit_selected(unit_id))
	if not card.disabled:
		card.pressed.connect(_on_deployment_subunit_pressed.bind(unit_id))
	selected_hex_unit_cards.add_child(card)

func _deployment_subunit_card_text(unit: Dictionary, relationship: Dictionary, block_reason: String) -> String:
	var name := _preferred_unit_name(unit)
	var size := _string_for_size(unit.get("size", "unit")).capitalize()
	var type_name := _role_display_name(unit)
	var text := "%s — %s — %s\n%s | Health: —" % [name, size, type_name, String(relationship.get("summary", "Attached"))]
	if not block_reason.is_empty():
		text += "\nInternal element — not independently deployable"
	return text

func _deployment_relationship_for_branch(unit: Dictionary, coordinates_by_unit_id: Dictionary) -> Dictionary:
	var unit_id := String(unit.get("id", ""))
	if coordinates_by_unit_id.has(unit_id):
		var coordinate := String(coordinates_by_unit_id[unit_id])
		return {"status": "Detached", "summary": "Detached — Hex %s" % coordinate, "coordinates": [coordinate]}

	var descendant_coordinates: Array[String] = []
	_collect_independent_descendant_coordinates(unit, coordinates_by_unit_id, descendant_coordinates, true)
	descendant_coordinates.sort()
	if not descendant_coordinates.is_empty():
		var marker_word := "marker" if descendant_coordinates.size() == 1 else "markers"
		return {
			"status": "Partially detached",
			"summary": "Partially detached — %d %s at %s" % [descendant_coordinates.size(), marker_word, "; ".join(descendant_coordinates)],
			"coordinates": descendant_coordinates
		}
	return {"status": "Attached", "summary": "Attached", "coordinates": []}

func _collect_independent_descendant_coordinates(node: Dictionary, coordinates_by_unit_id: Dictionary, output: Array[String], skip_current: bool = false) -> void:
	var unit_id := String(node.get("id", ""))
	if not skip_current and coordinates_by_unit_id.has(unit_id):
		var coordinate := String(coordinates_by_unit_id[unit_id])
		if not output.has(coordinate):
			output.append(coordinate)
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	for child_variant in (children_variant as Array):
		if typeof(child_variant) == TYPE_DICTIONARY:
			_collect_independent_descendant_coordinates(child_variant as Dictionary, coordinates_by_unit_id, output)

func _division_unit_by_id(unit_id: String) -> Dictionary:
	if unit_id.is_empty():
		return {}
	var division_tree: Dictionary = GameState.players[_player_index].get("division_tree", {})
	return FormationHierarchyModel.find_node(division_tree, unit_id)

func _visible_deployment_marker_id_for_unit(unit_id: String) -> String:
	if unit_id.is_empty():
		return ""
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	var coordinates_by_unit_id := _deployment_coordinates_by_unit_id(deployments)
	if coordinates_by_unit_id.has(unit_id):
		return unit_id
	var division_tree: Dictionary = GameState.players[_player_index].get("division_tree", {})
	var path: Array[Dictionary] = FormationHierarchyModel.path_to(division_tree, unit_id)
	for index in range(path.size() - 2, -1, -1):
		var ancestor_id := String(path[index].get("id", ""))
		if coordinates_by_unit_id.has(ancestor_id):
			return ancestor_id
	return unit_id

func _coordinate_from_key(coordinate_key: String) -> Vector2i:
	var parts := coordinate_key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

func _territory_owner_name(owner: int) -> String:
	match owner:
		GameState.TerritoryOwnership.PLAYER_1:
			return "Player 1%s" % (" (Friendly)" if _player_index == 0 else " (Enemy)")
		GameState.TerritoryOwnership.PLAYER_2:
			return "Player 2%s" % (" (Friendly)" if _player_index == 1 else " (Enemy)")
		_:
			return "Neutral"

func _unit_summary(units: Array[Dictionary]) -> String:
	if units.is_empty():
		return "units"
	if units.size() == 1:
		return String(units[0].get("display_name", "unit"))
	return "%d units" % units.size()

func _deployed_unit_snapshots(deployments: Dictionary) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for key in deployments.keys():
		units.append_array(_deployment_units_from_variant(deployments[key]))
	return units

func _deployed_units_include_id(units: Array[Dictionary], unit_id: String) -> bool:
	if unit_id.is_empty():
		return false
	for unit in units:
		if String(unit.get("id", "")) == unit_id:
			return true
	return false

func _deployed_unit_snapshots_at_key(deployments: Dictionary, key: String) -> Array[Dictionary]:
	if not deployments.has(key):
		return []
	return _deployment_units_from_variant(deployments[key])

func _deployment_units_from_variant(deployment_variant: Variant) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	if typeof(deployment_variant) == TYPE_DICTIONARY:
		units.append(deployment_variant as Dictionary)
	elif typeof(deployment_variant) == TYPE_ARRAY:
		for unit_variant in (deployment_variant as Array):
			if typeof(unit_variant) == TYPE_DICTIONARY:
				units.append(unit_variant as Dictionary)
	return units

func _battalion_with_deployed_companies_block_reason(unit_snapshot: Dictionary, deployments: Dictionary, unit_id: String) -> String:
	if String(unit_snapshot.get("size", "")).to_lower() != "battalion":
		return ""
	for deployed_unit in _deployed_unit_snapshots(deployments):
		if String(deployed_unit.get("id", "")) == unit_id:
			continue
		if String(deployed_unit.get("size", "")).to_lower() == "company":
			return "Cannot place a battalion after companies are deployed."
	return ""

func _add_deployment_unit_at_key(deployments: Dictionary, key: String, unit_snapshot: Dictionary) -> void:
	var units := _deployed_unit_snapshots_at_key(deployments, key)
	units.append(unit_snapshot)
	_deployments_set_units_at_key(deployments, key, units)

func _remove_deployment_unit_at_key(deployments: Dictionary, key: String, unit_id: String) -> void:
	var remaining_units: Array[Dictionary] = []
	for deployed_unit in _deployed_unit_snapshots_at_key(deployments, key):
		if String(deployed_unit.get("id", "")) == unit_id:
			continue
		remaining_units.append(deployed_unit)
	_deployments_set_units_at_key(deployments, key, remaining_units)

func _deployments_set_units_at_key(deployments: Dictionary, key: String, units: Array[Dictionary]) -> void:
	if units.is_empty():
		deployments.erase(key)
	elif units.size() == 1:
		deployments[key] = units[0]
	else:
		deployments[key] = units.duplicate(true)

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

func _deployed_related_formation_id_at_key_for_unit_id(deployments: Dictionary, unit_id: String, key: String) -> String:
	if unit_id.is_empty() or key.is_empty():
		return ""
	var related_unit_ids := _ancestor_unit_ids_for_unit_id(unit_id)
	for descendant_unit_id in _descendant_unit_ids_for_unit_id(unit_id).keys():
		related_unit_ids[descendant_unit_id] = true
	if related_unit_ids.is_empty():
		return ""
	for deployed_unit in _deployed_unit_snapshots_at_key(deployments, key):
		var deployed_unit_id := String(deployed_unit.get("id", ""))
		if related_unit_ids.has(deployed_unit_id):
			return deployed_unit_id
	return ""

func _descendant_unit_ids_for_unit_id(unit_id: String) -> Dictionary:
	var descendant_unit_ids := {}
	if unit_id.is_empty():
		return descendant_unit_ids
	var division_tree: Dictionary = GameState.players[_player_index].get("division_tree", {})
	_collect_descendant_unit_ids_for_unit_id(division_tree, unit_id, false, descendant_unit_ids)
	return descendant_unit_ids

func _collect_descendant_unit_ids_for_unit_id(node: Variant, target_unit_id: String, collecting_descendants: bool, descendant_unit_ids: Dictionary) -> bool:
	if typeof(node) != TYPE_DICTIONARY:
		return false

	var unit_data := node as Dictionary
	if unit_data.is_empty():
		return false

	var unit_id := String(unit_data.get("id", ""))
	var should_collect_children := collecting_descendants or unit_id == target_unit_id
	if collecting_descendants and not unit_id.is_empty():
		descendant_unit_ids[unit_id] = true

	var found_target := unit_id == target_unit_id
	var children_variant: Variant = unit_data.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return found_target

	for child in (children_variant as Array):
		if _collect_descendant_unit_ids_for_unit_id(child, target_unit_id, should_collect_children, descendant_unit_ids):
			found_target = true
	return found_target

func _ancestor_unit_ids_for_unit_id(unit_id: String) -> Dictionary:
	var ancestor_unit_ids := {}
	if unit_id.is_empty():
		return ancestor_unit_ids
	var division_tree: Dictionary = GameState.players[_player_index].get("division_tree", {})
	_collect_ancestor_unit_ids_for_unit_id(division_tree, unit_id, [], ancestor_unit_ids)
	return ancestor_unit_ids

func _collect_ancestor_unit_ids_for_unit_id(node: Variant, target_unit_id: String, ancestor_path: Array, ancestor_unit_ids: Dictionary) -> bool:
	if typeof(node) != TYPE_DICTIONARY:
		return false

	var unit_data := node as Dictionary
	if unit_data.is_empty():
		return false

	var unit_id := String(unit_data.get("id", ""))
	if unit_id == target_unit_id:
		for ancestor_id in ancestor_path:
			var ancestor_id_string := String(ancestor_id)
			if not ancestor_id_string.is_empty():
				ancestor_unit_ids[ancestor_id_string] = true
		return true

	var next_ancestor_path := ancestor_path.duplicate()
	if not unit_id.is_empty():
		next_ancestor_path.append(unit_id)

	var children_variant: Variant = unit_data.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return false

	for child in (children_variant as Array):
		if _collect_ancestor_unit_ids_for_unit_id(child, target_unit_id, next_ancestor_path, ancestor_unit_ids):
			return true
	return false

func _deployment_key_for_unit_id(deployments: Dictionary, unit_id: String) -> String:
	if unit_id.is_empty():
		return ""
	for key in deployments.keys():
		for unit_data in _deployment_units_from_variant(deployments[key]):
			if String(unit_data.get("id", "")) == unit_id:
				return String(key)
	return ""

func _deployment_coordinates_by_unit_id(deployments: Dictionary) -> Dictionary:
	var coordinates_by_unit_id := {}
	for key in deployments.keys():
		for unit_data in _deployment_units_from_variant(deployments[key]):
			var unit_id := String(unit_data.get("id", ""))
			if unit_id.is_empty():
				continue
			coordinates_by_unit_id[unit_id] = String(key)
	return coordinates_by_unit_id

func _unplaced_deployable_unit_ids_from_coordinates(coordinates_by_unit_id: Dictionary) -> Dictionary:
	var unplaced_by_id := {}
	var covered_unit_ids := _unit_ids_covered_by_higher_echelon_deployments()
	var subordinate_covered_unit_ids := _unit_ids_covered_by_lower_echelon_deployments()
	for deployable_unit in _deployable_units:
		if not _is_deployable(deployable_unit):
			continue
		var unit_id := String(deployable_unit.get("id", ""))
		if unit_id.is_empty():
			continue
		if covered_unit_ids.has(unit_id):
			continue
		if subordinate_covered_unit_ids.has(unit_id):
			continue
		if coordinates_by_unit_id.has(unit_id):
			continue
		unplaced_by_id[unit_id] = true
	return unplaced_by_id

func _apply_incomplete_deployment_colors() -> void:
	var warning_unit_ids := _unplaced_deployable_unit_ids.duplicate()
	for unit_id_variant in _unplaced_deployable_unit_ids.keys():
		var unit_id := String(unit_id_variant)
		for ancestor_id_variant in _ancestor_unit_ids_for_unit_id(unit_id).keys():
			warning_unit_ids[String(ancestor_id_variant)] = true

	for warning_unit_id_variant in warning_unit_ids.keys():
		var warning_item := _find_tree_item_by_unit_id(unit_list.get_root(), String(warning_unit_id_variant))
		if warning_item != null:
			warning_item.set_custom_color(0, UNDEPLOYED_WARNING_COLOR)

func _unit_ids_covered_by_higher_echelon_deployments() -> Dictionary:
	var covered_unit_ids := {}
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {})
	if deployments.is_empty():
		return covered_unit_ids

	var deployed_unit_ids := {}
	for deployment in deployments.values():
		for deployed_unit in _deployment_units_from_variant(deployment):
			var deployed_unit_id := String(deployed_unit.get("id", ""))
			if deployed_unit_id.is_empty():
				continue
			deployed_unit_ids[deployed_unit_id] = true

	if deployed_unit_ids.is_empty():
		return covered_unit_ids

	var division_tree: Dictionary = GameState.players[_player_index].get("division_tree", {})
	_collect_covered_descendant_ids(division_tree, false, deployed_unit_ids, covered_unit_ids)
	return covered_unit_ids

func _collect_covered_descendant_ids(node: Variant, ancestor_deployed: bool, deployed_unit_ids: Dictionary, covered_unit_ids: Dictionary) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return

	var unit_data := node as Dictionary
	if unit_data.is_empty():
		return

	var unit_id := String(unit_data.get("id", ""))
	var current_is_deployed := not unit_id.is_empty() and deployed_unit_ids.has(unit_id)
	var descendant_is_covered := ancestor_deployed or current_is_deployed

	if ancestor_deployed and not unit_id.is_empty():
		covered_unit_ids[unit_id] = true

	var children_variant: Variant = unit_data.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return

	for child in (children_variant as Array):
		_collect_covered_descendant_ids(child, descendant_is_covered, deployed_unit_ids, covered_unit_ids)

func _unit_ids_covered_by_lower_echelon_deployments(deployments_override: Variant = null) -> Dictionary:
	var covered_unit_ids := {}
	var deployments: Dictionary = GameState.players[_player_index].get("deployments", {}) if deployments_override == null else deployments_override as Dictionary
	if deployments.is_empty():
		return covered_unit_ids

	var deployed_unit_ids := {}
	for deployment in deployments.values():
		for deployed_unit in _deployment_units_from_variant(deployment):
			var deployed_unit_id := String(deployed_unit.get("id", ""))
			if deployed_unit_id.is_empty():
				continue
			deployed_unit_ids[deployed_unit_id] = true

	if deployed_unit_ids.is_empty():
		return covered_unit_ids

	var division_tree: Dictionary = GameState.players[_player_index].get("division_tree", {})
	_collect_lower_echelon_covered_ids(division_tree, deployed_unit_ids, covered_unit_ids)
	return covered_unit_ids

func _collect_lower_echelon_covered_ids(node: Variant, deployed_unit_ids: Dictionary, covered_unit_ids: Dictionary) -> Dictionary:
	if typeof(node) != TYPE_DICTIONARY:
		return {"has_deployable": false, "satisfied": true}

	var unit_data := node as Dictionary
	if unit_data.is_empty():
		return {"has_deployable": false, "satisfied": true}

	var unit_id := String(unit_data.get("id", ""))
	var is_deployable := _is_deployable(unit_data)
	var is_deployed := not unit_id.is_empty() and deployed_unit_ids.has(unit_id)
	var has_deployable_descendant := false
	var descendants_satisfied := true

	var children_variant: Variant = unit_data.get("children", [])
	if typeof(children_variant) == TYPE_ARRAY:
		for child in (children_variant as Array):
			var child_state := _collect_lower_echelon_covered_ids(child, deployed_unit_ids, covered_unit_ids)
			if bool(child_state.get("has_deployable", false)):
				has_deployable_descendant = true
				if not bool(child_state.get("satisfied", false)):
					descendants_satisfied = false

	var satisfied := false
	if is_deployable:
		satisfied = is_deployed or (has_deployable_descendant and descendants_satisfied)
		if has_deployable_descendant and descendants_satisfied and not unit_id.is_empty():
			covered_unit_ids[unit_id] = true
	else:
		satisfied = descendants_satisfied

	return {
		"has_deployable": is_deployable or has_deployable_descendant,
		"satisfied": satisfied
	}

func _hierarchy_placement_block_reason(unit_id: String, deployments: Dictionary) -> String:
	if unit_id.is_empty():
		return ""
	if _unit_ids_covered_by_lower_echelon_deployments(deployments).has(unit_id):
		return "%s is already represented by all of its deployed subordinate branches." % _preferred_unit_name(_division_unit_by_id(unit_id))
	return ""

func _remove_redundant_deployed_ancestors(deployments: Dictionary, affected_unit_ids: Array[String]) -> Array[String]:
	var represented_by_subordinates := _unit_ids_covered_by_lower_echelon_deployments(deployments)
	var candidate_ancestor_ids := {}
	for unit_id in affected_unit_ids:
		for ancestor_id_variant in _ancestor_unit_ids_for_unit_id(unit_id).keys():
			candidate_ancestor_ids[String(ancestor_id_variant)] = true
	var removed_names: Array[String] = []
	for ancestor_id_variant in candidate_ancestor_ids.keys():
		var ancestor_id := String(ancestor_id_variant)
		if not represented_by_subordinates.has(ancestor_id):
			continue
		var deployment_key := _deployment_key_for_unit_id(deployments, ancestor_id)
		if deployment_key.is_empty():
			continue
		_remove_deployment_unit_at_key(deployments, deployment_key, ancestor_id)
		var ancestor_unit := _division_unit_by_id(ancestor_id)
		removed_names.append(_preferred_unit_name(ancestor_unit) if not ancestor_unit.is_empty() else ancestor_id)
	removed_names.sort()
	return removed_names

func _unit_snapshot(unit: Dictionary) -> Dictionary:
	# Maintainer note: keep `_unit_snapshot`, `_string_for_type`, and `_string_for_size`
	# `_preferred_unit_name`, and `_preferred_short_name` aligned with DeploymentValidator contracts
	# (`can_deploy_in_territory` / `placement_block_reason`) so UI checks and validator checks stay identical.
	var unit_type := _string_for_type(unit.get("type", ""))
	var unit_size := _string_for_size(unit.get("size", ""))
	var preferred_name := _preferred_unit_name(unit)
	var preferred_short_name := _preferred_short_name(unit, preferred_name)
	var designation := _designation_payload(unit)
	var snapshot := {
		"id": unit.get("id", ""),
		"template_id": String(unit.get("template_id", "")),
		"display_name": preferred_name,
		"short_name": preferred_short_name,
		"designation": designation,
		"type": unit_type,
		"role": UnitRole.normalize(unit.get("role", ""), unit_type),
		"equipment_weight": NatoUnitSymbolRenderer.equipment_weight_for_unit(unit),
		"size": unit_size,
		"is_attached": bool(unit.get("is_attached", false)),
		"status": String(unit.get("status", "")).to_lower(),
		"label": preferred_short_name.substr(0, 2).to_upper()
	}
	var vehicles := unit.get("vehicles", []) as Array
	if not vehicles.is_empty():
		snapshot["vehicles"] = vehicles.duplicate(true)
		snapshot["live_sub_units"] = _living_vehicle_count(vehicles)
		snapshot["max_sub_units"] = vehicles.size()
	return snapshot

func _living_vehicle_count(vehicles: Array) -> int:
	var living := 0
	for vehicle_variant in vehicles:
		if vehicle_variant is Dictionary and GameState.is_unit_alive(vehicle_variant as Dictionary):
			living += 1
	return living

func _designation_payload(unit: Dictionary) -> Dictionary:
	var designation_variant: Variant = unit.get("designation", {})
	if typeof(designation_variant) == TYPE_DICTIONARY:
		return (designation_variant as Dictionary).duplicate(true)
	return {}

func _preferred_unit_name(unit: Dictionary) -> String:
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

func _on_save_scenario_pressed() -> void:
	if _player_index != 0:
		return
	if not GameState.selected_scenario_name.is_empty():
		scenario_name_input.text = GameState.selected_scenario_name
	scenario_save_dialog.popup_centered()
	scenario_name_input.grab_focus()
	scenario_name_input.select_all()

func _on_scenario_save_confirmed() -> void:
	if _player_index != 0:
		return
	var scenario_name := scenario_name_input.text.strip_edges()
	if scenario_name.is_empty():
		_refresh_phase_ui("Enter a scenario name before saving.")
		return
	_pending_scenario_name = scenario_name
	if SaveManager.scenario_exists(scenario_name):
		overwrite_scenario_dialog.dialog_text = "A scenario named '%s' already exists. Replace it?" % scenario_name
		overwrite_scenario_dialog.popup_centered()
		return
	_save_starting_scenario(scenario_name)

func _on_overwrite_scenario_confirmed() -> void:
	if _pending_scenario_name.is_empty():
		return
	_save_starting_scenario(_pending_scenario_name)

func _save_starting_scenario(scenario_name: String) -> bool:
	var payload := _build_starting_scenario_payload(scenario_name)
	if payload.is_empty() or not SaveManager.save_scenario(scenario_name, payload):
		var error_message := SaveManager.get_last_load_error()
		_refresh_phase_ui(error_message if not error_message.is_empty() else "Failed to save starting scenario '%s'." % scenario_name)
		_pending_scenario_name = ""
		return false
	GameState.selected_scenario_name = scenario_name.strip_edges()
	_pending_scenario_name = ""
	_refresh_phase_ui("Saved starting scenario '%s'." % scenario_name)
	return true

func _build_starting_scenario_payload(scenario_name: String) -> Dictionary:
	if GameState.players.size() < 2:
		return {}
	var scenario_players: Array[Dictionary] = []
	for player_index in range(2):
		var player := (GameState.players[player_index] as Dictionary).duplicate(true)
		var division_tree := player.get("division_tree", {}) as Dictionary
		if division_tree.is_empty():
			return {}
		player["division_tree"] = division_tree.duplicate(true)
		player["deployments"] = (player.get("deployments", {}) as Dictionary).duplicate(true) if player_index == 0 else {}
		player["controller"] = "human" if player_index == 0 else "ai"
		scenario_players.append(player)
	return {
		"scenario_version": SaveManager.SCENARIO_VERSION_CURRENT,
		"version": GameState.MAP_PAYLOAD_VERSION_CURRENT,
		"name": scenario_name,
		"selected_nation_id": String(GameState.selected_nation_id),
		"grid": {
			"columns": GameState.map_columns,
			"rows": GameState.map_rows
		},
		"terrain": GameState.terrain_map.duplicate(true),
		"territory": GameState.territory_map.duplicate(true),
		"objectives": GameState.key_objectives.duplicate(true),
		"ai_doctrine": String(GameState.selected_ai_doctrine),
		"difficulty": String(GameState.selected_difficulty),
		"players": scenario_players
	}

func _on_finish_deployment_pressed() -> void:
	var unplaced_count := _unplaced_deployable_unit_ids.size()
	if unplaced_count > 0:
		_build_deployable_unit_list()
		_refresh_phase_ui("Place all deployable units before submitting (%d remaining)." % unplaced_count)
		return
	if ScenarioEditorState.active:
		ScenarioEditorState.capture_from_game_state()
		if _player_index == 0:
			ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_2_DEPLOYMENT, 1)
			GameState.set_phase(GameState.Phase.DEPLOYMENT_P2)
			return
		ScenarioEditorState.set_step(ScenarioEditorState.Step.REVIEW)
		ScenarioEditorState.capture_from_game_state()
		GameState.set_phase(GameState.Phase.SCENARIO_REVIEW)
		return

	if _player_index == 0:
		var p2_is_ai := _is_ai_controlled(1)
		if p2_is_ai:
			var ai_result := _run_ai_deployment_if_needed(1)
			if not _ai_deployment_allows_gameplay(ai_result):
				_refresh_phase_ui(_ai_deployment_failure_message(ai_result))
				return
			GameState.set_phase(GameState.Phase.GAMEPLAY)
		else:
			GameState.set_phase(GameState.Phase.DEPLOYMENT_P2)
		return

	_run_ai_deployment_if_needed(0)
	GameState.set_phase(GameState.Phase.GAMEPLAY)

func _run_ai_deployment_if_needed(player_index: int) -> Dictionary:
	if not _is_ai_controlled(player_index):
		return {"ok": true, "reason": "skipped", "deployments": {}}
	var result := DeploymentAIService.run_for_player(player_index)
	if not bool(result.get("ok", false)):
		push_warning("AI deployment planning failed for player %d (%s)." % [player_index + 1, String(result.get("reason", "unknown"))])
	return result

func _ai_deployment_allows_gameplay(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var deployments := result.get("deployments", {}) as Dictionary
	return not deployments.is_empty()

func _ai_deployment_failure_message(result: Dictionary) -> String:
	var reason := String(result.get("reason", "unknown"))
	match reason:
		"no_legal_hexes":
			return "Player 2 needs at least one owned deployment hex before the AI can deploy."
		"no_elements":
			return "Player 2 has no deployable units for the AI to place."
		"planned_empty":
			return "AI deployment did not place any units. Check Player 2 structure and deployment territory."
		"partial_plan":
			return "AI deployment could not legally place every formation. Add deployment territory or reduce the force."
		_:
			return "AI deployment failed (%s)." % reason

func _is_ai_controlled(player_index: int) -> bool:
	if player_index < 0 or player_index >= GameState.players.size():
		return false
	var player := GameState.players[player_index] as Dictionary
	if player.is_empty():
		return false
	var controller := String(player.get("controller", "human")).strip_edges().to_lower()
	return controller == "ai"

func _refresh_phase_ui(message: String) -> void:
	phase_label.text = "%sPlayer %d" % ["Scenario Deployment: " if ScenarioEditorState.active else "Deployment: ", _player_index + 1]
	status_label.text = message
	var visible := {
		0: GameState.players[0].get("deployments", {}),
		1: GameState.players[1].get("deployments", {})
	}
	hex_map_view.configure(GameState.terrain_map, GameState.territory_map, visible, _player_index, true, GameState.key_objectives)
	_sync_map_selection()

func _on_scenario_editor_before_draft_save() -> void:
	ScenarioEditorState.capture_from_game_state()

func _on_scenario_editor_back() -> void:
	ScenarioEditorState.capture_from_game_state()
	if _player_index == 1:
		ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_DEPLOYMENT, 0)
		GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)
		return
	ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_2_FORCES, 1)
	GameState.set_phase(GameState.Phase.DIVISION_BUILDER)
