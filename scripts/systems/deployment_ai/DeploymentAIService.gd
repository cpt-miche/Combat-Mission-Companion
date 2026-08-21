extends RefCounted
class_name DeploymentAIService

const DeploymentDataConverter = preload("res://scripts/domain/deployment_ai/DeploymentDataConverter.gd")
const DeploymentPlanner = preload("res://scripts/systems/deployment_ai/DeploymentPlanner.gd")
const FormationDecomposer = preload("res://scripts/systems/deployment_ai/FormationDecomposer.gd")
const DeploymentValidator = preload("res://scripts/domain/units/DeploymentValidator.gd")
const AIDebugTracer = preload("res://scripts/systems/ai_debug/AIDebugTracer.gd")
const AIDebugFormatter = preload("res://scripts/systems/ai_debug/AIDebugFormatter.gd")
const HexGrid = preload("res://scripts/domain/map/HexGrid.gd")
const UnitEquipmentWeight = preload("res://scripts/domain/units/UnitEquipmentWeight.gd")

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

	var hexes := DeploymentDataConverter.map_payload_to_hexes(GameState.terrain_map, GameState.territory_map)
	var legal_hexes := _legal_hexes_for_player(ai_player_index)
	if legal_hexes.is_empty():
		GameState.players[ai_player_index]["deployments"] = {}
		var outputs_no_hexes := {
			"planner": "DeploymentPlanner",
			"playerIndex": ai_player_index,
			"objectiveMode": _objective_mode_for_player(player),
			"plan": {},
			"resultDeployments": {},
			"notes": ["No legal deployment hexes available for this player."]
		}
		var no_hexes_trace := tracer.finish_trace(trace, outputs_no_hexes, {"planner_ms": 0})
		GameState.deployment_ai_debug["player_%d" % ai_player_index] = no_hexes_trace.duplicate(true)
		_persist_trace(no_hexes_trace)
		return {"ok": false, "reason": "no_legal_hexes", "deployments": {}}

	var ai_owner := _territory_owner_for_player(ai_player_index)
	var opposing_owner := _territory_owner_for_player(1 - ai_player_index)
	var context := _context_for_mode(_objective_mode_for_player(player))
	var objectives := _deployment_objectives(ai_player_index)
	var sector_model := MapAnalyzer.build_sector_model(
		GameState.territory_map,
		GameState.terrain_map,
		ai_owner,
		opposing_owner,
		context,
		objectives
	)
	var frontline_count := (sector_model.get("frontlineHexes", []) as Array).size()
	var decomposition := _decomposition_for_player(ai_player_index, frontline_count)
	var elements: Array[Dictionary] = []
	for element_variant in (decomposition.get("deployableElements", []) as Array):
		if typeof(element_variant) == TYPE_DICTIONARY:
			elements.append(element_variant as Dictionary)
	if elements.is_empty():
		GameState.players[ai_player_index]["deployments"] = {}
		var outputs := {
			"planner": "DeploymentPlanner",
			"playerIndex": ai_player_index,
			"objectiveMode": _objective_mode_for_player(player),
			"decomposition": decomposition,
			"plan": {},
			"resultDeployments": {},
			"notes": ["No deployable elements available for this player."]
		}
		var finished_trace := tracer.finish_trace(trace, outputs, {"planner_ms": 0})
		GameState.deployment_ai_debug["player_%d" % ai_player_index] = finished_trace.duplicate(true)
		_persist_trace(finished_trace)
		return {"ok": true, "reason": "no_elements", "deployments": {}}

	var plan := DeploymentPlanner.create_plan(elements, hexes, sector_model, {
		"objectiveMode": _objective_mode_for_player(player),
		"objectives": objectives,
		"decomposition": decomposition.get("metadata", {}),
		"traceEventCallback": func(event_type: String, payload: Dictionary) -> void:
			tracer.add_event(trace, event_type, payload)
	})
	var deployments := _deployments_from_plan(ai_player_index, elements, plan, sector_model)
	var unplaced_elements := plan.get("unplacedElements", []) as Array

	var outputs := {
		"planner": "DeploymentPlanner",
		"playerIndex": ai_player_index,
		"objectiveMode": _objective_mode_for_player(player),
		"sectorModel": sector_model,
		"decomposition": decomposition,
		"plan": plan,
		"resultDeployments": deployments,
		"resultSummary": {
			"unitCount": elements.size(),
			"deployedHexCount": deployments.size(),
			"deployedUnitCount": _deployment_unit_count(deployments),
			"ordersCount": (plan.get("orders", []) as Array).size(),
			"unplacedUnitCount": unplaced_elements.size()
		}
	}
	var finished_trace := tracer.finish_trace(trace, outputs, {"planner_ms": 0})
	GameState.deployment_ai_debug["player_%d" % ai_player_index] = finished_trace.duplicate(true)
	_persist_trace(finished_trace)
	if deployments.is_empty():
		return {"ok": false, "reason": "planned_empty", "deployments": {}, "plan": plan}
	if not unplaced_elements.is_empty():
		return {
			"ok": false,
			"reason": "partial_plan",
			"deployments": {},
			"candidate_deployments": deployments,
			"unplaced_elements": unplaced_elements.duplicate(true),
			"plan": plan
		}
	GameState.players[ai_player_index]["deployments"] = deployments
	return {"ok": true, "reason": "planned", "deployments": deployments, "plan": plan}

static func _decomposition_for_player(player_index: int, frontline_count: int) -> Dictionary:
	if player_index < 0 or player_index >= GameState.players.size():
		return {"deployableElements": [], "splitAudit": [], "metadata": {}}
	var player := GameState.players[player_index] as Dictionary
	var root := player.get("division_tree", {}) as Dictionary
	if root.is_empty():
		return {"deployableElements": [], "splitAudit": [], "metadata": {}}
	return FormationDecomposer.decompose_formation_tree(root, {
		"playerIndex": player_index,
		"minDeploySize": "platoon",
		"preferredBaseSize": "company",
		"targetCombatElements": frontline_count,
		"context": {
			"frontageCoverageNeed": 1.0,
			"screenNeed": 1.0,
			"strongpointNeed": 0.7,
			"reservePreservationNeed": 0.0
		}
	})

static func _deployments_from_plan(ai_player_index: int, elements: Array[Dictionary], plan: Dictionary, sector_model: Dictionary) -> Dictionary:
	var units_by_id := _units_by_id_for_player(ai_player_index)
	var deployments := {}
	var ranked_ai_hexes := _ranked_ai_hexes(ai_player_index, sector_model)
	var root: Variant = (GameState.players[ai_player_index] as Dictionary).get("division_tree", {})
	var fallback_placements: Array[Dictionary] = []
	var unplaced_elements: Array[Dictionary] = []

	for order_variant in (plan.get("orders", []) as Array):
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order := order_variant as Dictionary
		var unit_id := String(order.get("unitId", ""))
		var preferred_hex := String(order.get("toHexId", ""))
		_try_place_ai_unit(ai_player_index, unit_id, preferred_hex, units_by_id, deployments, ranked_ai_hexes, root, sector_model)

	for element in elements:
		var unit_id := String(element.get("id", ""))
		if _deployments_has_unit_id(deployments, unit_id) or _deployments_has_related_unit_id(deployments, unit_id, root):
			continue
		if not units_by_id.has(unit_id):
			unplaced_elements.append({"unitId": unit_id, "reason": "missing_unit"})
			continue
		var snapshot := _unit_snapshot_for(units_by_id[unit_id] as Dictionary)
		var fallback_hex := _select_fallback_hex_for_snapshot(
			snapshot,
			deployments,
			ranked_ai_hexes,
			ai_player_index,
			sector_model
		)
		if fallback_hex.is_empty():
			unplaced_elements.append({"unitId": unit_id, "reason": "no_legal_hex"})
			continue
		if _try_place_ai_unit(ai_player_index, unit_id, fallback_hex, units_by_id, deployments, ranked_ai_hexes, root, sector_model):
			fallback_placements.append({
				"unitId": unit_id,
				"hexId": fallback_hex,
				"role": String(snapshot.get("role", "unknown")),
				"reason": "role_aware_unplanned_placement"
			})
		else:
			unplaced_elements.append({"unitId": unit_id, "reason": "placement_rejected"})

	plan["fallbackPlacements"] = fallback_placements
	plan["unplacedElements"] = unplaced_elements

	return deployments

static func _try_place_ai_unit(
	ai_player_index: int,
	unit_id: String,
	preferred_hex: String,
	units_by_id: Dictionary,
	deployments: Dictionary,
	ranked_ai_hexes: Array[String],
	root: Variant,
	sector_model: Dictionary = {}
) -> bool:
	if unit_id.is_empty() or not units_by_id.has(unit_id):
		return false
	if _deployments_has_unit_id(deployments, unit_id):
		return false
	if _deployments_has_related_unit_id(deployments, unit_id, root):
		return false

	var unit := units_by_id[unit_id] as Dictionary
	var snapshot := _unit_snapshot_for(unit)
	var selected_hex := preferred_hex if _can_place_snapshot_at_hex(snapshot, preferred_hex, deployments, ai_player_index) else ""
	if selected_hex.is_empty() and not sector_model.is_empty():
		selected_hex = _select_fallback_hex_for_snapshot(snapshot, deployments, ranked_ai_hexes, ai_player_index, sector_model)
	if selected_hex.is_empty():
		selected_hex = _select_legal_hex_for_snapshot(snapshot, "", deployments, ranked_ai_hexes, ai_player_index)
	if selected_hex.is_empty():
		return false

	_add_deployment_unit_at_key(deployments, selected_hex, snapshot)
	return true

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

static func _select_legal_hex_for_snapshot(snapshot: Dictionary, preferred_hex: String, deployments: Dictionary, ranked_ai_hexes: Array[String], player_index: int) -> String:
	if _can_place_snapshot_at_hex(snapshot, preferred_hex, deployments, player_index):
		return preferred_hex
	for candidate in ranked_ai_hexes:
		if _can_place_snapshot_at_hex(snapshot, candidate, deployments, player_index):
			return candidate
	return ""

static func _select_fallback_hex_for_snapshot(
	snapshot: Dictionary,
	deployments: Dictionary,
	ranked_ai_hexes: Array[String],
	player_index: int,
	sector_model: Dictionary
) -> String:
	var role := String(snapshot.get("role", "unknown"))
	var placement_kind := _fallback_placement_kind(role, String(snapshot.get("type", "")))
	var frontline := _legal_candidates_from_sector(
		sector_model.get("frontlineHexes", []) as Array,
		snapshot,
		deployments,
		player_index
	)
	var rear := _legal_candidates_from_sector(
		sector_model.get("rearArea", []) as Array,
		snapshot,
		deployments,
		player_index
	)
	var all_legal := _legal_candidates_from_sector(ranked_ai_hexes, snapshot, deployments, player_index)
	var candidates: Array[String] = []
	match placement_kind:
		"combat":
			candidates = frontline if not frontline.is_empty() else all_legal
		"support":
			for candidate in all_legal:
				if _hex_has_combat_partner(deployments, candidate):
					candidates.append(candidate)
			if candidates.is_empty():
				candidates = rear if not rear.is_empty() else all_legal
		"rear":
			candidates = rear if not rear.is_empty() else all_legal
		_:
			candidates = all_legal

	if candidates.is_empty():
		return ""
	var scores := sector_model.get("hexScores", {}) as Dictionary
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var a_load := _deployment_units_at_key(deployments, a).size()
		var b_load := _deployment_units_at_key(deployments, b).size()
		if a_load != b_load:
			return a_load < b_load
		var a_neighbors := _occupied_neighbor_count(deployments, a)
		var b_neighbors := _occupied_neighbor_count(deployments, b)
		if a_neighbors != b_neighbors:
			return a_neighbors < b_neighbors
		var a_priority := float((scores.get(a, {}) as Dictionary).get("priority", 0.0))
		var b_priority := float((scores.get(b, {}) as Dictionary).get("priority", 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return candidates[0]

static func _legal_candidates_from_sector(
	raw_candidates: Array,
	snapshot: Dictionary,
	deployments: Dictionary,
	player_index: int
) -> Array[String]:
	var candidates: Array[String] = []
	for candidate_variant in raw_candidates:
		var candidate := String(candidate_variant)
		if candidates.has(candidate):
			continue
		if _can_place_snapshot_at_hex(snapshot, candidate, deployments, player_index):
			candidates.append(candidate)
	return candidates

static func _fallback_placement_kind(role: String, broad_type: String) -> String:
	if role in [
		"weapons", "heavy_weapons", "machine_gun", "heavy_machine_gun",
		"medium_machine_gun", "light_machine_gun", "mortar", "light_mortar",
		"60mm_mortar", "81mm_mortar", "8cm_mortar", "12cm_mortar",
		"anti_tank", "anti_tank_gun", "medium_anti_tank_gun", "tank_destroyer"
	]:
		return "support"
	if role in ["artillery", "howitzer", "105mm_howitzer", "155mm_howitzer", "headquarters"]:
		return "rear"
	if role in [
		"infantry", "rifle", "grenadier", "mechanized", "motorized", "engineer",
		"pionier", "recon", "tank", "panzer", "light_tank", "medium_tank",
		"heavy_tank", "assault_gun"
	]:
		return "combat"
	if broad_type in ["infantry", "tank", "engineer", "recon", "airborne", "mechanized", "motorized"]:
		return "combat"
	if broad_type in ["artillery", "headquarters"]:
		return "rear"
	return "general"

static func _hex_has_combat_partner(deployments: Dictionary, hex_id: String) -> bool:
	for unit in _deployment_units_at_key(deployments, hex_id):
		if _fallback_placement_kind(String(unit.get("role", "unknown")), String(unit.get("type", ""))) == "combat":
			return true
	return false

static func _occupied_neighbor_count(deployments: Dictionary, hex_id: String) -> int:
	var coordinates := hex_id.split(",")
	if coordinates.size() != 2:
		return 0
	var q := int(coordinates[0])
	var r := int(coordinates[1])
	var count := 0
	for offset in HexGrid.neighbor_offsets(r):
		var neighbor := "%d,%d" % [q + offset.x, r + offset.y]
		if not _deployment_units_at_key(deployments, neighbor).is_empty():
			count += 1
	return count

static func _can_place_snapshot_at_hex(snapshot: Dictionary, hex_id: String, deployments: Dictionary, player_index: int) -> bool:
	if not _is_legal_hex_for_player(hex_id, player_index):
		return false
	var existing_units := _deployment_units_at_key(deployments, hex_id)
	return DeploymentValidator.placement_block_reason(snapshot, existing_units).is_empty()

static func _is_legal_hex_for_player(hex_id: String, player_index: int) -> bool:
	if hex_id.is_empty():
		return false
	var owner := int(GameState.territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL))
	return DeploymentValidator.can_deploy_in_territory(owner, player_index)

static func _legal_hexes_for_player(player_index: int) -> Array[String]:
	var legal_hexes: Array[String] = []
	for key_variant in GameState.territory_map.keys():
		var key := String(key_variant)
		if _is_legal_hex_for_player(key, player_index):
			legal_hexes.append(key)
	legal_hexes.sort()
	return legal_hexes

static func _deployments_has_unit_id(deployments: Dictionary, unit_id: String) -> bool:
	for deployment in deployments.values():
		for deployed_unit in _deployment_units_from_variant(deployment):
			if String(deployed_unit.get("id", "")) == unit_id:
				return true
	return false

static func _deployments_has_related_unit_id(deployments: Dictionary, unit_id: String, root: Variant) -> bool:
	var related_unit_ids := _related_unit_ids_for_unit_id(root, unit_id)
	if related_unit_ids.is_empty():
		return false
	for deployment in deployments.values():
		for deployed_unit in _deployment_units_from_variant(deployment):
			var deployed_unit_id := String(deployed_unit.get("id", ""))
			if related_unit_ids.has(deployed_unit_id):
				return true
	return false

static func _related_unit_ids_for_unit_id(root: Variant, unit_id: String) -> Dictionary:
	var related_unit_ids := {}
	if unit_id.is_empty():
		return related_unit_ids
	_collect_related_unit_ids(root, unit_id, [], related_unit_ids)
	related_unit_ids.erase(unit_id)
	return related_unit_ids

static func _collect_related_unit_ids(node: Variant, target_unit_id: String, ancestor_path: Array, related_unit_ids: Dictionary) -> bool:
	if typeof(node) != TYPE_DICTIONARY:
		return false

	var unit := node as Dictionary
	var unit_id := String(unit.get("id", ""))
	if unit_id == target_unit_id:
		for ancestor_id in ancestor_path:
			var ancestor_id_text := String(ancestor_id)
			if not ancestor_id_text.is_empty():
				related_unit_ids[ancestor_id_text] = true
		_collect_descendant_unit_ids(unit, related_unit_ids)
		return true

	var next_ancestor_path := ancestor_path.duplicate()
	if not unit_id.is_empty():
		next_ancestor_path.append(unit_id)
	for child in (unit.get("children", []) as Array):
		if _collect_related_unit_ids(child, target_unit_id, next_ancestor_path, related_unit_ids):
			return true
	return false

static func _collect_descendant_unit_ids(node: Dictionary, related_unit_ids: Dictionary) -> void:
	for child_variant in (node.get("children", []) as Array):
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var child := child_variant as Dictionary
		var child_id := String(child.get("id", ""))
		if not child_id.is_empty():
			related_unit_ids[child_id] = true
		_collect_descendant_unit_ids(child, related_unit_ids)

static func _deployment_units_at_key(deployments: Dictionary, key: String) -> Array[Dictionary]:
	if not deployments.has(key):
		return []
	return _deployment_units_from_variant(deployments[key])

static func _deployment_units_from_variant(deployment_variant: Variant) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	if typeof(deployment_variant) == TYPE_DICTIONARY:
		units.append(deployment_variant as Dictionary)
	elif typeof(deployment_variant) == TYPE_ARRAY:
		for unit_variant in (deployment_variant as Array):
			if typeof(unit_variant) == TYPE_DICTIONARY:
				units.append(unit_variant as Dictionary)
	return units

static func _add_deployment_unit_at_key(deployments: Dictionary, key: String, snapshot: Dictionary) -> void:
	var units := _deployment_units_at_key(deployments, key)
	units.append(snapshot)
	if units.size() == 1:
		deployments[key] = units[0]
	else:
		deployments[key] = units.duplicate(true)

static func _deployment_unit_count(deployments: Dictionary) -> int:
	var count := 0
	for deployment in deployments.values():
		count += _deployment_units_from_variant(deployment).size()
	return count

static func _unit_snapshot_for(unit: Dictionary) -> Dictionary:
	var unit_type := _string_for_type(unit.get("type", ""))
	var unit_size := _string_for_size(unit.get("size", ""))
	var unit_name := String(unit.get("display_name", unit.get("id", "Unit")))
	var short_name := String(unit.get("short_name", unit_name))
	var snapshot := {
		"id": String(unit.get("id", "")),
		"template_id": String(unit.get("template_id", "")),
		"display_name": unit_name,
		"short_name": short_name,
		"designation": _designation_payload(unit),
		"type": unit_type,
		"role": UnitRole.normalize(unit.get("role", ""), unit_type),
		"equipment_weight": UnitEquipmentWeight.for_unit(unit),
		"size": unit_size,
		"is_attached": bool(unit.get("is_attached", false)),
		"status": String(unit.get("status", "")).to_lower(),
		"label": unit_name.substr(0, 2).to_upper()
	}
	var vehicles := unit.get("vehicles", []) as Array
	if not vehicles.is_empty():
		snapshot["vehicles"] = vehicles.duplicate(true)
		snapshot["live_sub_units"] = _living_vehicle_count(vehicles)
		snapshot["max_sub_units"] = vehicles.size()
	return snapshot

static func _living_vehicle_count(vehicles: Array) -> int:
	var living := 0
	for vehicle_variant in vehicles:
		if vehicle_variant is Dictionary and GameState.is_unit_alive(vehicle_variant as Dictionary):
			living += 1
	return living

static func _designation_payload(unit: Dictionary) -> Dictionary:
	var designation_variant: Variant = unit.get("designation", {})
	if typeof(designation_variant) == TYPE_DICTIONARY:
		return (designation_variant as Dictionary).duplicate(true)
	return {}

static func _string_for_type(raw_type: Variant) -> String:
	return String(raw_type).to_lower()

static func _string_for_size(raw_size: Variant) -> String:
	return String(raw_size).to_lower()

static func _objective_mode_for_player(player: Dictionary) -> String:
	var configured := String(player.get("ai_objective_mode", "mixed_split")).strip_edges().to_lower()
	if configured in ["attack-only", "defense-only", "mixed_split"]:
		return configured
	return "mixed_split"

static func _deployment_objectives(ai_player_index: int) -> Array[Dictionary]:
	var objectives: Array[Dictionary] = []
	var ai_owner := _territory_owner_for_player(ai_player_index)
	var objective_hex_ids: Array[String] = []
	for key_variant in GameState.key_objectives.keys():
		objective_hex_ids.append(String(key_variant))
	objective_hex_ids.sort()
	for hex_id in objective_hex_ids:
		var authored := GameState.key_objectives.get(hex_id, {}) as Dictionary
		var priority_label := String(authored.get("priority", "secondary")).strip_edges().to_lower()
		var priority := 2 if priority_label == "primary" else 1
		var territory_owner := int(GameState.territory_map.get(hex_id, GameState.TerritoryOwnership.NEUTRAL))
		var mission := "defend" if territory_owner == ai_owner else "attack"
		objectives.append(DeploymentTypes.make_ai_objective(
			"objective_%s" % hex_id.replace(",", "_"),
			mission,
			priority,
			hex_id,
			{
				"priorityLabel": priority_label,
				"territoryOwner": territory_owner,
				"classification": "ownership_inferred"
			}
		))
	return objectives

static func _context_for_mode(mode: String) -> String:
	if mode == "attack-only":
		return "attack"
	return "defense"

static func _territory_owner_for_player(player_index: int) -> int:
	return GameState.TerritoryOwnership.PLAYER_1 if player_index == 0 else GameState.TerritoryOwnership.PLAYER_2

static func _persist_trace(final_trace: Dictionary) -> void:
	var trace_payload := final_trace.duplicate(true)
	trace_payload["line_entries"] = AIDebugFormatter.format_trace_lines(final_trace)
	trace_payload["line_log_path"] = SaveManager.AI_TRACE_LINE_LOG_PATH
	if not SaveManager.save_ai_trace(trace_payload):
		push_warning("Deployment AI trace was not fully persisted for player %d." % int(final_trace.get("player_id", -1)))
