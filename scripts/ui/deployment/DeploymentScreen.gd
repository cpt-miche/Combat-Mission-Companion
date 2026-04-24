extends Control

const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")

@onready var phase_label: Label = %PhaseLabel
@onready var unit_list: ItemList = %UnitList
@onready var status_label: Label = %StatusLabel
@onready var hex_map_view: DeploymentHexMapView = %HexMapView
@onready var finish_button: Button = %FinishDeploymentButton

var _player_index := 0
var _deployable_units: Array[Dictionary] = []

func _ready() -> void:
	_player_index = 0 if GameState.current_phase == GameState.Phase.DEPLOYMENT_P1 else 1
	_ensure_players_initialized()
	_build_deployable_unit_list()
	_refresh_phase_ui("Select a unit, then click a hex in your territory.")

	hex_map_view.hex_selected.connect(_on_hex_selected)
	finish_button.pressed.connect(_on_finish_deployment_pressed)

func _ensure_players_initialized() -> void:
	while GameState.players.size() < 2:
		GameState.players.append({
			"name": "Player %d" % (GameState.players.size() + 1),
			"division_tree": {},
			"deployments": {}
		})

	for i in range(2):
		var player := GameState.players[i]
		if not player.has("division_tree") or (player.get("division_tree", {}) as Dictionary).is_empty():
			player["division_tree"] = _default_division_tree(i)
		if not GameState.players[i].has("deployments"):
			GameState.players[i]["deployments"] = {}
		GameState.players[i] = player

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
				"children": []
			},
			{
				"id": "%s_tank_bn" % side_label,
				"name": "%s Tank Battalion" % side_label,
				"type": "tank",
				"size": "battalion",
				"children": []
			},
			{
				"id": "%s_support_co" % side_label,
				"name": "%s Support Company" % side_label,
				"type": "engineer",
				"size": "company",
				"children": []
			},
			{
				"id": "%s_infantry_co_1" % side_label,
				"name": "%s Infantry Company A" % side_label,
				"type": "infantry",
				"size": "company",
				"children": []
			},
			{
				"id": "%s_infantry_co_2" % side_label,
				"name": "%s Infantry Company B" % side_label,
				"type": "infantry",
				"size": "company",
				"children": []
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
		"label": String(unit.get("name", unit.get("id", "U"))).substr(0, 2).to_upper(),
		"is_tank": unit_type == "tank",
		"is_battalion": unit_size == "battalion",
		"is_company": unit_size == "company"
	}

func _on_finish_deployment_pressed() -> void:
	if _player_index == 0:
		GameState.set_phase(GameState.Phase.DEPLOYMENT_P2)
		return
	GameState.set_phase(GameState.Phase.GAMEPLAY)

func _refresh_phase_ui(message: String) -> void:
	phase_label.text = "Deployment: Player %d" % (_player_index + 1)
	status_label.text = message
	var visible := {
		0: GameState.players[0].get("deployments", {}),
		1: GameState.players[1].get("deployments", {})
	}
	hex_map_view.configure(GameState.territory_map, visible, _player_index, true)
