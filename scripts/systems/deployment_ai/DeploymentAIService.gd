extends RefCounted
class_name DeploymentAIService

const DeploymentDataConverter = preload("res://scripts/domain/deployment_ai/DeploymentDataConverter.gd")
const DeploymentPlanner = preload("res://scripts/systems/deployment_ai/DeploymentPlanner.gd")
const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")
const AIDebugTracer = preload("res://scripts/systems/ai_debug/AIDebugTracer.gd")

static func run_for_player(ai_player_index: int) -> Dictionary:
	if ai_player_index < 0 or ai_player_index >= GameState.players.size():
		return {"ok": false, "reason": "invalid_player_index"}

	var player := GameState.players[ai_player_index] as Dictionary
	if player.is_empty():
		return {"ok": false, "reason": "missing_player"}

	var tracer := AIDebugTracer.new()
	var trace := tracer.start_trace({
		"phase": "deployment_ai",
		"turn": int(GameState.current_turn),
		"player_id": ai_player_index,
		"ai_version": "DeploymentPlanner",
		"debug_level": int(GameState.ai_debug_level),
		"inputs_hash": AIDebugTracer.make_deterministic_id({
			"playerIndex": ai_player_index,
			"objectiveMode": _objective_mode_for_player(player)
		})
	})

	var elements := _elements_for_player(ai_player_index)
	if elements.is_empty():
		GameState.players[ai_player_index]["deployments"] = {}
		var outputs := {
			"planner": "DeploymentPlanner",
			"playerIndex": ai_player_index,
			"objectiveMode": _objective_mode_for_player(player),
			"plan": {},
			"resultDeployments": {},
			"notes": ["No deployable elements available for this player."]
		}
		var finished_trace := tracer.finish_trace(trace, outputs, {"planner_ms": 0})
		GameState.deployment_ai_debug["player_%d" % ai_player_index] = _legacy_debug_from_trace(finished_trace)
		return {"ok": true, "reason": "no_elements", "deployments": {}}

	var hexes := DeploymentDataConverter.map_payload_to_hexes(GameState.terrain_map, GameState.territory_map)
	var ai_owner := _territory_owner_for_player(ai_player_index)
	var opposing_owner := _territory_owner_for_player(1 - ai_player_index)
	var context := _context_for_mode(_objective_mode_for_player(player))
	var sector_model := MapAnalyzer.build_sector_model(
		GameState.territory_map,
		GameState.terrain_map,
		ai_owner,
		opposing_owner,
		"",
		"",
		context
	)

	var plan := DeploymentPlanner.create_plan(elements, hexes, sector_model, {
		"objectiveMode": _objective_mode_for_player(player),
		"traceEventCallback": func(event_type: String, payload: Dictionary) -> void:
			tracer.add_event(trace, event_type, payload)
	})
	var deployments := _deployments_from_plan(ai_player_index, elements, plan, sector_model)
	GameState.players[ai_player_index]["deployments"] = deployments

	var outputs := {
		"planner": "DeploymentPlanner",
		"playerIndex": ai_player_index,
		"objectiveMode": _objective_mode_for_player(player),
		"sectorModel": sector_model,
		"plan": plan,
		"resultDeployments": deployments,
		"resultSummary": {
			"unitCount": elements.size(),
			"deployedCount": deployments.size(),
			"ordersCount": (plan.get("orders", []) as Array).size()
		}
	}
	var finished_trace := tracer.finish_trace(trace, outputs, {"planner_ms": 0})
	GameState.deployment_ai_debug["player_%d" % ai_player_index] = _legacy_debug_from_trace(finished_trace)
	return {"ok": true, "reason": "planned", "deployments": deployments, "plan": plan}

static func _legacy_debug_from_trace(final_trace: Dictionary) -> Dictionary:
	var outputs := final_trace.get("outputs", {}) as Dictionary
	var legacy := outputs.duplicate(true)
	legacy["traceId"] = String(final_trace.get("trace_id", ""))
	legacy["trace"] = final_trace.duplicate(true)
	legacy["events"] = (final_trace.get("events", []) as Array).duplicate(true)
	legacy["eventCount"] = int(final_trace.get("event_count", (final_trace.get("events", []) as Array).size()))
	return legacy

static func _elements_for_player(player_index: int) -> Array[Dictionary]:
	var all_elements := DeploymentDataConverter.players_to_deployable_elements(GameState.players)
	var filtered: Array[Dictionary] = []
	for element_variant in all_elements:
		if typeof(element_variant) != TYPE_DICTIONARY:
			continue
		var element := element_variant as Dictionary
		if int(element.get("playerId", -1)) != player_index:
			continue
		filtered.append(element)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return filtered

static func _deployments_from_plan(ai_player_index: int, elements: Array[Dictionary], plan: Dictionary, sector_model: Dictionary) -> Dictionary:
	var units_by_id := _units_by_id_for_player(ai_player_index)
	var occupied := {}
	var deployments := {}
	var unit_snapshots: Array[Dictionary] = []
	var ranked_ai_hexes := _ranked_ai_hexes(ai_player_index, sector_model)

	for order_variant in (plan.get("orders", []) as Array):
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order := order_variant as Dictionary
		var unit_id := String(order.get("unitId", order.get("elementId", "")))
		if unit_id.is_empty() or not units_by_id.has(unit_id):
			continue

		var preferred_hex := String(order.get("toHexId", order.get("hexId", "")))
		var selected_hex := _select_unoccupied_hex(preferred_hex, occupied, ranked_ai_hexes, ai_player_index)
		if selected_hex.is_empty():
			continue

		var unit := units_by_id[unit_id] as Dictionary
		var snapshot := _unit_snapshot_for(unit)
		var reason := DeploymentValidator.placement_block_reason(snapshot, unit_snapshots)
		if not reason.is_empty():
			continue

		occupied[selected_hex] = true
		deployments[selected_hex] = snapshot
		unit_snapshots.append(snapshot)

	for element in elements:
		var unit_id := String(element.get("id", ""))
		if unit_id.is_empty() or not units_by_id.has(unit_id):
			continue
		if _deployments_has_unit_id(deployments, unit_id):
			continue
		var fallback_hex := _first_legal_fallback_hex(ai_player_index, occupied, ranked_ai_hexes)
		if fallback_hex.is_empty():
			break
		var unit := units_by_id[unit_id] as Dictionary
		var snapshot := _unit_snapshot_for(unit)
		var reason := DeploymentValidator.placement_block_reason(snapshot, unit_snapshots)
		if not reason.is_empty():
			continue
		occupied[fallback_hex] = true
		deployments[fallback_hex] = snapshot
		unit_snapshots.append(snapshot)

	return deployments

static func _units_by_id_for_player(player_index: int) -> Dictionary:
	var player := GameState.players[player_index] as Dictionary
	var root: Variant = player.get("division_tree", {})
	var units := {}
	_flatten_units(root, units)
	return units

static func _flatten_units(node: Variant, out_units: Dictionary) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return
	var unit := node as Dictionary
	if unit.is_empty():
		return
	var unit_id := String(unit.get("id", ""))
	if not unit_id.is_empty():
		out_units[unit_id] = unit
	for child in (unit.get("children", []) as Array):
		_flatten_units(child, out_units)

static func _ranked_ai_hexes(player_index: int, sector_model: Dictionary) -> Array[String]:
	var owner := _territory_owner_for_player(player_index)
	var ranked: Array[String] = []
	for key_variant in GameState.territory_map.keys():
		var key := String(key_variant)
		if int(GameState.territory_map.get(key, GameState.TerritoryOwnership.NEUTRAL)) != owner:
			continue
		ranked.append(key)

	var scores := sector_model.get("hexScores", {}) as Dictionary
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var a_priority := float((scores.get(a, {}) as Dictionary).get("priority", 0.0))
		var b_priority := float((scores.get(b, {}) as Dictionary).get("priority", 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return ranked

static func _select_unoccupied_hex(preferred_hex: String, occupied: Dictionary, ranked_ai_hexes: Array[String], player_index: int) -> String:
	if _is_legal_hex_for_player(preferred_hex, player_index) and not occupied.has(preferred_hex):
		return preferred_hex
	for candidate in ranked_ai_hexes:
		if occupied.has(candidate):
			continue
		if _is_legal_hex_for_player(candidate, player_index):
			return candidate
	return ""

static func _first_legal_fallback_hex(player_index: int, occupied: Dictionary, ranked_ai_hexes: Array[String]) -> String:
	for candidate in ranked_ai_hexes:
		if occupied.has(candidate):
			continue
		if _is_legal_hex_for_player(candidate, player_index):
			return candidate
	return ""

static func _is_legal_hex_for_player(hex_id: String, player_index: int) -> bool:
	if hex_id.is_empty():
		return false
	var owner := int(GameState.territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL))
	return DeploymentValidator.can_deploy_in_territory(owner, player_index)

static func _deployments_has_unit_id(deployments: Dictionary, unit_id: String) -> bool:
	for key_variant in deployments.keys():
		var unit_variant: Variant = deployments[key_variant]
		if typeof(unit_variant) != TYPE_DICTIONARY:
			continue
		if String((unit_variant as Dictionary).get("id", "")) == unit_id:
			return true
	return false

static func _unit_snapshot_for(unit: Dictionary) -> Dictionary:
	var unit_type := _string_for_type(unit.get("type", ""))
	var unit_size := _string_for_size(unit.get("size", ""))
	return {
		"id": String(unit.get("id", "")),
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

static func _string_for_type(raw_type: Variant) -> String:
	if typeof(raw_type) == TYPE_INT:
		return UnitType.display_name(int(raw_type)).to_lower()
	return String(raw_type).to_lower()

static func _string_for_size(raw_size: Variant) -> String:
	if typeof(raw_size) == TYPE_INT:
		return UnitSize.display_name(int(raw_size)).to_lower()
	return String(raw_size).to_lower()

static func _size_rank(size_name: String) -> int:
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

static func _objective_mode_for_player(player: Dictionary) -> String:
	var configured := String(player.get("ai_objective_mode", "mixed_split")).strip_edges().to_lower()
	if configured in ["attack-only", "defense-only", "mixed_split"]:
		return configured
	return "mixed_split"

static func _context_for_mode(mode: String) -> String:
	if mode == "attack-only":
		return "attack"
	return "defense"

static func _territory_owner_for_player(player_index: int) -> int:
	return GameState.TerritoryOwnership.PLAYER_1 if player_index == 0 else GameState.TerritoryOwnership.PLAYER_2
