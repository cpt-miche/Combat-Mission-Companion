extends RefCounted
class_name DeploymentPlanner

const ReconAIConfig = preload("res://scripts/core/ReconAIConfig.gd")
const HexGrid = preload("res://scripts/domain/map/HexGrid.gd")

const MAX_COMBAT_CAPACITY := 9
const MAX_SUPPORT_CAPACITY := 3
const ARTILLERY_RANGE := 6

const SUPPORT_ATTACH_ROLES := {
	DeploymentTypes.ROLE_RECON: true,
	DeploymentTypes.ROLE_ANTI_TANK_SUPPORT: true,
	DeploymentTypes.ROLE_WEAPONS: true
}

const SIZE_COMBAT_COST := {
	"platoon": 1,
	"company": 3,
	"battalion": 9
}

static func create_plan(
	elements: Array[Dictionary],
	hexes: Array[Dictionary],
	sector_model: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var objective_mode: String = String(options.get("objectiveMode", "mixed_split")).strip_edges().to_lower().replace(" ", "_")
	var objectives: Array[Dictionary] = []
	for objective_variant in (options.get("objectives", []) as Array):
		if typeof(objective_variant) == TYPE_DICTIONARY:
			objectives.append(objective_variant as Dictionary)

	var state := _build_state(elements, hexes, sector_model, options)
	var stage_orders: Array[Dictionary] = []

	_stage_a_allocate_combat_anchors(state, objective_mode, stage_orders)
	_stage_b_attach_support(state, stage_orders)
	_stage_c_place_artillery(state, stage_orders)
	_stage_d_place_reserves(state, stage_orders)

	var ordered_orders := _sort_orders(stage_orders)
	for i in range(ordered_orders.size()):
		ordered_orders[i]["id"] = "deploy_%03d" % [i + 1]

	var plan := DeploymentTypes.make_deployment_plan(elements, objectives, ordered_orders, {
		"planner": "DeploymentPlanner",
		"objectiveMode": objective_mode,
		"frontage": _frontage_metadata(state),
		"decomposition": (options.get("decomposition", {}) as Dictionary).duplicate(true),
		"objectives": objectives.duplicate(true),
		"stages": ["A", "B", "C", "D", "S"],
		"deterministic": true,
		"idempotent": true,
		"constraints": {
			"maxCombatCapacity": MAX_COMBAT_CAPACITY,
			"maxSupportCapacity": MAX_SUPPORT_CAPACITY,
			"artilleryNotFrontline": true,
			"antiTankNeverAttack": true
		}
	})
	return DeploymentSanity.sanitize_plan(plan, hexes, sector_model)

static func _build_state(elements: Array[Dictionary], hexes: Array[Dictionary], sector_model: Dictionary, options: Dictionary = {}) -> Dictionary:
	var frontline: Dictionary = _set_from_array(sector_model.get("frontlineHexes", []))
	var contested: Dictionary = _set_from_array(sector_model.get("contestedArea", []))
	var rear: Dictionary = _set_from_array(sector_model.get("rearArea", []))
	var priorities: Dictionary = _extract_hex_priorities(sector_model.get("hexScores", {}))
	var hex_coords := _hex_coords(hexes)
	var all_hexes := _all_hex_ids(hexes)
	var terrain_by_hex := _terrain_by_hex(hexes)
	var pressure_by_hex := _extract_hex_pressures(sector_model.get("hexScores", {}))
	var max_front_pressure := 0.0
	for hex_id in frontline.keys():
		max_front_pressure = max(max_front_pressure, float(pressure_by_hex.get(hex_id, 0.0)))
	var objectives: Array[Dictionary] = []
	for objective_variant in options.get("objectives", []) as Array:
		if objective_variant is Dictionary:
			objectives.append((objective_variant as Dictionary).duplicate(true))
	objectives.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := int(a.get("priority", 1))
		var b_priority := int(b.get("priority", 1))
		if a_priority != b_priority:
			return a_priority > b_priority
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	var objective_schedule: Array[Dictionary] = []
	for objective in objectives:
		for _weight_index in range(clampi(int(objective.get("priority", 1)), 1, 2)):
			objective_schedule.append(objective)

	var state := {
		"frontline": frontline,
		"contested": contested,
		"rear": rear,
		"priorities": priorities,
		"pressureByHex": pressure_by_hex,
		"maxFrontPressure": max_front_pressure,
		"terrainByHex": terrain_by_hex,
		"hexCoords": hex_coords,
		"allHexes": all_hexes,
		"combatLoad": {},
		"supportLoad": {},
		"placementByUnit": {},
		"stackStanceByHex": {},
		"stackHasAttackByHex": {},
		"stackOrder": [],
		"reserveAnchors": [],
		"objectives": objectives,
		"objectiveSchedule": objective_schedule,
		"traceEventCallback": options.get("traceEventCallback", Callable()),
		"units": {
			"combat": [],
			"support": [],
			"artillery": [],
			"reserve": []
		},
		"unitById": {}
	}

	var unit_ordered := elements.duplicate(true)
	unit_ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)

	for unit in unit_ordered:
		state["unitById"][String(unit.get("id", ""))] = unit
		var role: String = String(unit.get("role", DeploymentTypes.ROLE_INFANTRY))
		if role == DeploymentTypes.ROLE_ARTILLERY_SUPPORT:
			(state["units"]["artillery"] as Array).append(unit)
		elif SUPPORT_ATTACH_ROLES.has(role):
			(state["units"]["support"] as Array).append(unit)
		elif role in [DeploymentTypes.ROLE_INFANTRY, DeploymentTypes.ROLE_ARMOR, DeploymentTypes.ROLE_MOBILITY]:
			(state["units"]["combat"] as Array).append(unit)
		else:
			(state["units"]["reserve"] as Array).append(unit)

	return state

static func _stage_a_allocate_combat_anchors(state: Dictionary, objective_mode: String, orders: Array[Dictionary]) -> void:
	var combat_units: Array = state["units"]["combat"]
	_emit_stage_started(state, "A", {"unitCount": combat_units.size(), "objectiveMode": objective_mode})
	if combat_units.is_empty():
		_emit_stage_completed(state, "A", {"orderCount": 0, "objectiveMode": objective_mode})
		return

	var uncovered_frontline := _sorted_frontline_hexes(state)
	var covered_frontline: Array[String] = []
	var committed := 0
	var reinforcement_index := 0

	for i in range(combat_units.size()):
		var unit: Dictionary = combat_units[i]
		var stance := _stance_for_combat_index(objective_mode, i)
		var selected := {}
		var assigned_objective := {}
		if not uncovered_frontline.is_empty():
			selected = _select_gap_aware_frontline_hex(state, unit, uncovered_frontline, covered_frontline, stance)
		else:
			assigned_objective = _objective_for_reinforcement(state, reinforcement_index)
			reinforcement_index += 1
			if not assigned_objective.is_empty():
				stance = _stance_for_objective(assigned_objective, stance)
			selected = _select_reinforcement_hex(state, unit, stance, assigned_objective)
		if selected.is_empty():
			selected = _first_legal_combat_hex(state, unit, _fallback_ranked_hexes(state), 0, "A", stance)
		if selected.is_empty():
			_emit_candidate_rejected(state, "A", unit, "", "combat_no_legal_hex", "Stage A: no legal combat hex available after evaluating candidate pools.", 0.0, {"stance": stance})
			continue

		var hex_id: String = String(selected.get("hexId", ""))
		_commit_combat_placement(state, unit, hex_id, stance)
		if uncovered_frontline.has(hex_id):
			uncovered_frontline.erase(hex_id)
			covered_frontline.append(hex_id)
		var stage_reason := _reason_stage_a(unit, hex_id, stance, state)
		var order := _make_order(unit, hex_id, "A", stance, stage_reason["reason"], stage_reason["reason_code"])
		order["reason_meta"] = stage_reason.get("meta", {})
		if not assigned_objective.is_empty():
			order["objectiveId"] = String(assigned_objective.get("id", ""))
			(order["reason_meta"] as Dictionary)["objectiveAssignment"] = assigned_objective.duplicate(true)
			order["reason"] = "%s Assigned to %s objective %s at %s." % [
				String(order.get("reason", "")),
				String(assigned_objective.get("type", "objective")),
				String(assigned_objective.get("id", "")),
				String(assigned_objective.get("targetHexId", ""))
			]
		orders.append(order)
		_emit_order_committed(state, "A", unit, hex_id, order)
		committed += 1
	_emit_stage_completed(state, "A", {"orderCount": committed, "objectiveMode": objective_mode})

static func _stance_for_combat_index(objective_mode: String, index: int) -> String:
	if objective_mode == "attack-only":
		return "attack"
	if objective_mode == "defense-only":
		return "defense"
	return "attack" if index % 2 == 0 else "defense"

static func _stance_for_objective(objective: Dictionary, fallback: String) -> String:
	return "defense" if String(objective.get("type", "")) == "defend" else ("attack" if String(objective.get("type", "")) == "attack" else fallback)

static func _select_gap_aware_frontline_hex(
	state: Dictionary,
	unit: Dictionary,
	candidates: Array[String],
	covered_frontline: Array[String],
	stance: String
) -> Dictionary:
	var cost := _combat_cost(unit)
	var best_hex := ""
	var best_score := -INF
	var best_gap_distance := 0
	for hex_id in candidates:
		var gap_distance := 0
		if not covered_frontline.is_empty():
			gap_distance = 999
			for covered_hex in covered_frontline:
				gap_distance = mini(gap_distance, _hex_distance(hex_id, covered_hex, state))
		var need_score := _frontline_need_score(hex_id, state)
		var score := float(gap_distance) * 100.0 + need_score
		_emit_candidate_scored(state, "A", unit, hex_id, score, "frontline_gap_coverage_score", "Stage A coverage: scored empty frontline hex by gap reduction and local need.", {
			"stance": stance,
			"gapDistance": gap_distance,
			"frontlineNeed": need_score,
			"combatCost": cost
		})
		if not _can_place_combat(state, hex_id, cost):
			_emit_candidate_rejected(state, "A", unit, hex_id, "combat_capacity_exceeded", "Stage A coverage: empty frontline candidate exceeded combat capacity.", score)
			continue
		if score > best_score or (is_equal_approx(score, best_score) and (best_hex.is_empty() or hex_id < best_hex)):
			best_hex = hex_id
			best_score = score
			best_gap_distance = gap_distance
	if best_hex.is_empty():
		return {}
	return {
		"hexId": best_hex,
		"scoreComponents": {
			"gapDistance": best_gap_distance,
			"frontlineNeed": _frontline_need_score(best_hex, state)
		}
	}

static func _select_reinforcement_hex(state: Dictionary, unit: Dictionary, stance: String, objective: Dictionary = {}) -> Dictionary:
	var candidates := _sorted_frontline_hexes(state)
	if candidates.is_empty():
		candidates = _fallback_ranked_hexes(state)
	var cost := _combat_cost(unit)
	var best_hex := ""
	var best_score := -INF
	var best_load := 999
	for hex_id in candidates:
		var combat_load := int(state["combatLoad"].get(hex_id, 0))
		var load_ratio := float(combat_load) / float(MAX_COMBAT_CAPACITY)
		var need_score := _frontline_need_score(hex_id, state)
		var objective_distance := -1
		var objective_score := 0.0
		if not objective.is_empty():
			var target_hex_id := String(objective.get("targetHexId", ""))
			objective_distance = _hex_distance(hex_id, target_hex_id, state)
			objective_score = (4.0 * float(clampi(int(objective.get("priority", 1)), 1, 2))) / float(objective_distance + 1)
		var score := need_score + objective_score - load_ratio * 3.0
		_emit_candidate_scored(state, "A", unit, hex_id, score, "frontline_reinforcement_score", "Stage A reinforcement: scored covered frontage by pressure, exposure, and existing load.", {
			"stance": stance,
			"frontlineNeed": need_score,
			"loadRatio": load_ratio,
			"combatLoad": combat_load,
			"objectiveId": String(objective.get("id", "")),
			"objectiveType": String(objective.get("type", "")),
			"objectiveDistance": objective_distance,
			"objectiveScore": objective_score,
			"combatCost": cost
		})
		if not _can_place_combat(state, hex_id, cost):
			_emit_candidate_rejected(state, "A", unit, hex_id, "combat_capacity_exceeded", "Stage A reinforcement: candidate exceeded combat capacity.", score)
			continue
		if score > best_score or (is_equal_approx(score, best_score) and (combat_load < best_load or (combat_load == best_load and (best_hex.is_empty() or hex_id < best_hex)))):
			best_hex = hex_id
			best_score = score
			best_load = combat_load
	if best_hex.is_empty():
		return {}
	return {"hexId": best_hex, "scoreComponents": {"frontlineNeed": _frontline_need_score(best_hex, state), "objectiveId": String(objective.get("id", "")), "combatLoad": best_load}}

static func _objective_for_reinforcement(state: Dictionary, reinforcement_index: int) -> Dictionary:
	var schedule := state.get("objectiveSchedule", []) as Array
	if schedule.is_empty():
		return {}
	var objective_variant: Variant = schedule[reinforcement_index % schedule.size()]
	return (objective_variant as Dictionary).duplicate(true) if objective_variant is Dictionary else {}

static func _sorted_frontline_hexes(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for hex_id in (state["frontline"] as Dictionary).keys():
		result.append(String(hex_id))
	result.sort()
	return result

static func _frontline_need_score(hex_id: String, state: Dictionary) -> float:
	var pressure := float(state["pressureByHex"].get(hex_id, state["priorities"].get(hex_id, 0.0)))
	var max_pressure := float(state.get("maxFrontPressure", 0.0))
	var normalized_pressure := pressure / max_pressure if max_pressure > 0.0 else 0.0
	var terrain := String(state["terrainByHex"].get(hex_id, DeploymentTypes.TERRAIN_LIGHT))
	var exposure := 0.9
	match terrain:
		DeploymentTypes.TERRAIN_HIGHWAY, DeploymentTypes.TERRAIN_ROAD:
			exposure = 1.0
		DeploymentTypes.TERRAIN_MEDIUM, DeploymentTypes.TERRAIN_HEAVY, DeploymentTypes.TERRAIN_WOODS:
			exposure = 0.2
		DeploymentTypes.TERRAIN_URBAN:
			exposure = 0.35
	return normalized_pressure + exposure

static func _stage_b_attach_support(state: Dictionary, orders: Array[Dictionary]) -> void:
	var support_units: Array = state["units"]["support"]
	_emit_stage_started(state, "B", {"unitCount": support_units.size()})
	if support_units.is_empty():
		_emit_stage_completed(state, "B", {"orderCount": 0})
		return

	var stacks: Array[String] = []
	for stack_id in state["stackOrder"] as Array:
		stacks.append(String(stack_id))
	var committed := 0
	for unit in support_units:
		var role: String = String(unit.get("role", ""))
		var ranked_stacks := stacks.duplicate()
		ranked_stacks.sort_custom(func(a: String, b: String) -> bool:
			var a_score := _support_stack_score(state, unit, a)
			var b_score := _support_stack_score(state, unit, b)
			if not is_equal_approx(a_score, b_score):
				return a_score > b_score
			return a < b
		)

		var placed := false
		for hex_id in ranked_stacks:
			var candidate_score := _support_stack_score(state, unit, hex_id)
			var candidate_meta := {}
			if role == DeploymentTypes.ROLE_RECON:
				var expected_floor := _expected_intel_floor_for_role(role, false)
				var recon_components := _recon_stack_heuristic_components(state, hex_id)
				candidate_meta = {
					"expectedIntelFloor": expected_floor,
					"intelComponents": _intel_score_components(state, hex_id, expected_floor),
					"reconHeuristicComponents": recon_components
				}
			_emit_candidate_scored(state, "B", unit, hex_id, candidate_score, "support_stack_score", "Stage B: scored support attachment candidate.", candidate_meta)
			if role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT and bool(state["stackHasAttackByHex"].get(hex_id, false)):
				_emit_candidate_rejected(state, "B", unit, hex_id, "anti_tank_attack_stack_blocked", "Stage B: anti-tank support cannot attach to attack stack.", candidate_score)
				continue
			if not _can_place_support(state, hex_id):
				_emit_candidate_rejected(state, "B", unit, hex_id, "support_capacity_exceeded", "Stage B: support cap reached for stack.", candidate_score)
				continue
			_commit_support_placement(state, unit, hex_id)
			var stance: String = "defense" if role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT else String(state["stackStanceByHex"].get(hex_id, "support"))
			var stage_reason := _reason_stage_b(unit, hex_id, state)
			var order := _make_order(unit, hex_id, "B", stance, stage_reason["reason"], stage_reason["reason_code"])
			order["reason_meta"] = stage_reason.get("meta", {})
			orders.append(order)
			_emit_order_committed(state, "B", unit, hex_id, order)
			committed += 1
			placed = true
			break

		if placed:
			continue

		# If no stack can accept support, place as reserve support in rear while preserving support cap.
		for rear_hex in _ranked_rear_hexes(state):
			_emit_candidate_scored(state, "B", unit, rear_hex, float(state["priorities"].get(rear_hex, 0.0)), "rear_support_fallback_score", "Stage B: scored rear fallback support candidate.")
			if not _can_place_support(state, rear_hex):
				_emit_candidate_rejected(state, "B", unit, rear_hex, "support_capacity_exceeded", "Stage B fallback: support cap reached for rear hex.", float(state["priorities"].get(rear_hex, 0.0)))
				continue
			_commit_support_placement(state, unit, rear_hex)
			var order := _make_order(unit, rear_hex, "B", "defense", "Stage B fallback: no legal combat stack with support capacity; attached to rear support node.", "support_rear_fallback")
			orders.append(order)
			_emit_order_committed(state, "B", unit, rear_hex, order)
			committed += 1
			break
	_emit_stage_completed(state, "B", {"orderCount": committed})

static func _stage_c_place_artillery(state: Dictionary, orders: Array[Dictionary]) -> void:
	var artillery_units: Array = state["units"]["artillery"]
	_emit_stage_started(state, "C", {"unitCount": artillery_units.size()})
	if artillery_units.is_empty():
		_emit_stage_completed(state, "C", {"orderCount": 0})
		return

	var ranked_rear := _ranked_rear_hexes(state)
	var committed := 0
	for unit in artillery_units:
		var best_hex := ""
		var best_score := -INF
		for hex_id in ranked_rear:
			if (state["frontline"] as Dictionary).has(hex_id):
				_emit_candidate_rejected(state, "C", unit, hex_id, "frontline_artillery_forbidden", "Stage C: artillery cannot be placed on frontline hexes.", 0.0)
				continue
			if not _can_place_support(state, hex_id):
				_emit_candidate_rejected(state, "C", unit, hex_id, "support_capacity_exceeded", "Stage C: support cap reached for artillery candidate.", 0.0)
				continue
			var coverage := _frontline_coverage_from(hex_id, state)
			var priority: float = float(state["priorities"].get(hex_id, 0.0))
			var score := coverage * 100.0 + priority
			_emit_candidate_scored(state, "C", unit, hex_id, score, "artillery_coverage_score", "Stage C: scored artillery candidate by frontline coverage and priority.", {"coverage": coverage})
			if score > best_score or (is_equal_approx(score, best_score) and hex_id < best_hex):
				best_score = score
				best_hex = hex_id
		if best_hex.is_empty():
			_emit_candidate_rejected(state, "C", unit, "", "artillery_no_legal_hex", "Stage C: no legal artillery placement candidate.", 0.0)
			continue

		_commit_support_placement(state, unit, best_hex)
		var stage_reason := _reason_stage_c(best_hex, state)
		var order := _make_order(unit, best_hex, "C", "support", stage_reason["reason"], stage_reason["reason_code"])
		orders.append(order)
		_emit_order_committed(state, "C", unit, best_hex, order)
		committed += 1
	_emit_stage_completed(state, "C", {"orderCount": committed})

static func _stage_d_place_reserves(state: Dictionary, orders: Array[Dictionary]) -> void:
	var reserve_units: Array = state["units"]["reserve"]
	_emit_stage_started(state, "D", {"unitCount": reserve_units.size()})
	if reserve_units.is_empty():
		_emit_stage_completed(state, "D", {"orderCount": 0})
		return

	var candidates := _ranked_rear_hexes(state)
	if candidates.is_empty():
		candidates = _fallback_ranked_hexes(state)

	var committed := 0
	for unit in reserve_units:
		var role: String = String(unit.get("role", ""))
		var is_support := _is_support_role(role)
		var best_hex := ""
		var best_score := -INF
		for hex_id in candidates:
			if is_support and not _can_place_support(state, hex_id):
				_emit_candidate_rejected(state, "D", unit, hex_id, "support_capacity_exceeded", "Stage D: reserve support candidate exceeded support cap.", 0.0, {"isSupport": true})
				continue
			if not is_support and not _can_place_combat(state, hex_id, _combat_cost(unit)):
				_emit_candidate_rejected(state, "D", unit, hex_id, "combat_capacity_exceeded", "Stage D: reserve combat candidate exceeded combat cap.", 0.0, {"isSupport": false})
				continue

			var base_priority: float = float(state["priorities"].get(hex_id, 0.0))
			var distance_to_front := _distance_to_high_need_frontline(hex_id, state)
			var response_bonus := 1.0 / float(distance_to_front + 1)
			var clump_penalty := _reserve_clumping_penalty(hex_id, state)
			var score := base_priority + response_bonus - clump_penalty
			_emit_candidate_scored(state, "D", unit, hex_id, score, "reserve_position_score", "Stage D: scored reserve candidate for response to high-need frontage and spacing.", {"distanceToHighNeedFront": distance_to_front, "clumpPenalty": clump_penalty})

			if score > best_score or (is_equal_approx(score, best_score) and hex_id < best_hex):
				best_score = score
				best_hex = hex_id

		if best_hex.is_empty():
			_emit_candidate_rejected(state, "D", unit, "", "reserve_no_legal_hex", "Stage D: no legal reserve candidate available.", 0.0, {"isSupport": is_support})
			continue

		if is_support:
			_commit_support_placement(state, unit, best_hex)
		else:
			_commit_combat_placement(state, unit, best_hex, "reserve")
			(state["reserveAnchors"] as Array).append(best_hex)
		var stage_reason := _reason_stage_d(best_hex, state)
		var order := _make_order(unit, best_hex, "D", "reserve", stage_reason["reason"], stage_reason["reason_code"])
		orders.append(order)
		_emit_order_committed(state, "D", unit, best_hex, order)
		committed += 1
	_emit_stage_completed(state, "D", {"orderCount": committed})

static func _ranked_hexes_for_mode(state: Dictionary, mode: String) -> Array[String]:
	var pool := {}
	if mode == "attack":
		for hex_id in (state["frontline"] as Dictionary).keys():
			pool[hex_id] = true
		for hex_id in (state["contested"] as Dictionary).keys():
			pool[hex_id] = true
	else:
		for hex_id in (state["frontline"] as Dictionary).keys():
			pool[hex_id] = true
		for hex_id in (state["rear"] as Dictionary).keys():
			pool[hex_id] = true

	var ranked: Array[String] = []
	for hex_id in pool.keys():
		ranked.append(String(hex_id))
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var a_priority: float = float(state["priorities"].get(a, 0.0))
		var b_priority: float = float(state["priorities"].get(b, 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return ranked

static func _ranked_rear_hexes(state: Dictionary) -> Array[String]:
	var ranked: Array[String] = []
	for hex_id in (state["rear"] as Dictionary).keys():
		ranked.append(String(hex_id))
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var a_priority: float = float(state["priorities"].get(a, 0.0))
		var b_priority: float = float(state["priorities"].get(b, 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return ranked

static func _fallback_ranked_hexes(state: Dictionary) -> Array[String]:
	var all_hexes: Array[String] = state["allHexes"]
	var ranked := all_hexes.duplicate()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var a_priority: float = float(state["priorities"].get(a, 0.0))
		var b_priority: float = float(state["priorities"].get(b, 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return ranked

static func _first_legal_combat_hex(state: Dictionary, unit: Dictionary, candidates: Array[String], start_index: int, stage: String, stance: String) -> Dictionary:
	var cost := _combat_cost(unit)
	var expected_floor := _expected_intel_floor_for_role(String(unit.get("role", "")), true)
	var best_hex_id := ""
	var best_next_index := -1
	var best_score := -INF
	var best_score_components := {}
	for i in range(start_index, candidates.size()):
		var hex_id := candidates[i]
		var base_priority: float = float(state["priorities"].get(hex_id, 0.0))
		var intel_components := _intel_score_components(state, hex_id, expected_floor)
		var score := base_priority + float(intel_components.get("total", 0.0))
		_emit_candidate_scored(state, stage, unit, hex_id, score, "combat_anchor_priority_score", "Stage A: scored combat anchor candidate.", {
			"stance": stance,
			"combatCost": cost,
			"basePriority": base_priority,
			"expectedIntelFloor": expected_floor,
			"intelComponents": intel_components
		})
		if _can_place_combat(state, hex_id, cost):
			if best_hex_id == "" or score > best_score:
				best_hex_id = hex_id
				best_next_index = i + 1
				best_score = score
				best_score_components = {"basePriority": base_priority, "expectedIntelFloor": expected_floor, "intelComponents": intel_components}
			continue
		_emit_candidate_rejected(state, stage, unit, hex_id, "combat_capacity_exceeded", "Stage A: candidate exceeded combat stack cap.", score, {"stance": stance, "combatCost": cost})
	if best_hex_id == "":
		return {}
	return {"hexId": best_hex_id, "nextIndex": best_next_index, "scoreComponents": best_score_components}

static func _commit_combat_placement(state: Dictionary, unit: Dictionary, hex_id: String, stance: String) -> void:
	var cost := _combat_cost(unit)
	state["combatLoad"][hex_id] = int(state["combatLoad"].get(hex_id, 0)) + cost
	state["placementByUnit"][String(unit.get("id", ""))] = hex_id
	state["stackStanceByHex"][hex_id] = stance
	var has_attack: bool = bool(state["stackHasAttackByHex"].get(hex_id, false))
	state["stackHasAttackByHex"][hex_id] = has_attack or stance == "attack"
	if not (state["stackOrder"] as Array).has(hex_id):
		(state["stackOrder"] as Array).append(hex_id)
		(state["stackOrder"] as Array).sort()

static func _commit_support_placement(state: Dictionary, unit: Dictionary, hex_id: String) -> void:
	state["supportLoad"][hex_id] = int(state["supportLoad"].get(hex_id, 0)) + 1
	state["placementByUnit"][String(unit.get("id", ""))] = hex_id

static func _can_place_combat(state: Dictionary, hex_id: String, cost: int) -> bool:
	return int(state["combatLoad"].get(hex_id, 0)) + cost <= MAX_COMBAT_CAPACITY

static func _can_place_support(state: Dictionary, hex_id: String) -> bool:
	return int(state["supportLoad"].get(hex_id, 0)) + 1 <= MAX_SUPPORT_CAPACITY

static func _support_stack_score(state: Dictionary, unit: Dictionary, hex_id: String) -> float:
	var stance: String = String(state["stackStanceByHex"].get(hex_id, "defense"))
	var has_attack: bool = bool(state["stackHasAttackByHex"].get(hex_id, false))
	var role: String = String(unit.get("role", ""))
	var base_priority: float = float(state["priorities"].get(hex_id, 0.0))
	var role_bonus := 0.0
	if role == DeploymentTypes.ROLE_RECON:
		role_bonus = 1.0 if stance == "attack" else 0.6
		var intel_components := _intel_score_components(state, hex_id, _expected_intel_floor_for_role(role, false))
		var recon_components := _recon_stack_heuristic_components(state, hex_id)
		return base_priority + role_bonus + float(intel_components.get("total", 0.0)) + float(recon_components.get("total", 0.0))
	elif role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT:
		role_bonus = -2.0 if has_attack else (1.0 if stance == "defense" else 0.6)
	elif role == DeploymentTypes.ROLE_WEAPONS:
		role_bonus = 0.8
	return base_priority + role_bonus

static func _expected_intel_floor_for_role(role: String, is_combat: bool = false) -> int:
	if is_combat:
		return int(ReconAIConfig.AI_SCOUT_COVERAGE["expected_floor"]["combat"])
	if role == DeploymentTypes.ROLE_RECON:
		return int(ReconAIConfig.AI_SCOUT_COVERAGE["expected_floor"]["recon_support"])
	return int(ReconAIConfig.AI_SCOUT_COVERAGE["expected_floor"]["default_support"])

static func _adjacent_enemy_importance(state: Dictionary, anchor_hex_id: String) -> float:
	var anchor: Vector2i = (state["hexCoords"] as Dictionary).get(anchor_hex_id, Vector2i.ZERO) as Vector2i
	var importance_sum := 0.0
	for frontline_hex in (state["frontline"] as Dictionary).keys():
		var enemy_hex_id: String = String(frontline_hex)
		var enemy_coords: Vector2i = (state["hexCoords"] as Dictionary).get(enemy_hex_id, Vector2i.ZERO) as Vector2i
		var distance: int = int((abs(anchor.x - enemy_coords.x) + abs(anchor.x + anchor.y - enemy_coords.x - enemy_coords.y) + abs(anchor.y - enemy_coords.y)) / 2)
		if distance > 1:
			continue
		importance_sum += float(state["priorities"].get(enemy_hex_id, 0.0))
	return importance_sum

static func _critical_adjacent_importance(state: Dictionary, anchor_hex_id: String) -> float:
	var anchor: Vector2i = (state["hexCoords"] as Dictionary).get(anchor_hex_id, Vector2i.ZERO) as Vector2i
	var importance_sum := 0.0
	for frontline_hex in (state["frontline"] as Dictionary).keys():
		var enemy_hex_id: String = String(frontline_hex)
		var enemy_coords: Vector2i = (state["hexCoords"] as Dictionary).get(enemy_hex_id, Vector2i.ZERO) as Vector2i
		var distance: int = int((abs(anchor.x - enemy_coords.x) + abs(anchor.x + anchor.y - enemy_coords.x - enemy_coords.y) + abs(anchor.y - enemy_coords.y)) / 2)
		if distance > 1:
			continue
		var importance: float = float(state["priorities"].get(enemy_hex_id, 0.0))
		if importance >= float(ReconAIConfig.AI_SCOUT_COVERAGE["ranges"]["critical_importance_threshold"]):
			importance_sum += importance
	return importance_sum

static func _expected_scout_coverage_score(state: Dictionary, anchor_hex_id: String, expected_floor: int) -> float:
	var importance_sum := _adjacent_enemy_importance(state, anchor_hex_id)
	return float(expected_floor) * importance_sum * float(ReconAIConfig.AI_SCOUT_COVERAGE["weights"]["expected_scout_level"])

static func _critical_sector_low_intel_penalty(state: Dictionary, anchor_hex_id: String, expected_floor: int) -> float:
	var critical_importance := _critical_adjacent_importance(state, anchor_hex_id)
	if expected_floor >= 3:
		return 0.0
	return float(ReconAIConfig.AI_SCOUT_COVERAGE["weights"]["critical_low_intel_penalty"]) * critical_importance

static func _uncertainty_reduction_score(state: Dictionary, anchor_hex_id: String, expected_floor: int) -> float:
	if expected_floor <= 1:
		return 0.0
	var importance_sum := _adjacent_enemy_importance(state, anchor_hex_id)
	return float(expected_floor - 1) * importance_sum * float(ReconAIConfig.AI_SCOUT_COVERAGE["weights"]["uncertainty_reduction"])

static func _intel_score_components(state: Dictionary, anchor_hex_id: String, expected_floor: int) -> Dictionary:
	var objective_importance := _adjacent_enemy_importance(state, anchor_hex_id)
	var sector_importance := _critical_adjacent_importance(state, anchor_hex_id)
	var floor_effect := _expected_scout_coverage_score(state, anchor_hex_id, expected_floor)
	var uncertainty_reduction := _uncertainty_reduction_score(state, anchor_hex_id, expected_floor)
	var critical_penalty := _critical_sector_low_intel_penalty(state, anchor_hex_id, expected_floor)
	var neighboring_importance_weight := float(ReconAIConfig.AI_SCOUT_COVERAGE["weights"]["neighboring_hex_importance"])
	var objective_relevance_weight := float(ReconAIConfig.AI_SCOUT_COVERAGE["weights"]["objective_relevance"])
	var neighboring_importance_effect := sector_importance * neighboring_importance_weight
	var objective_relevance_effect := objective_importance * objective_relevance_weight
	return {
		"objectiveImportance": objective_importance,
		"sectorImportance": sector_importance,
		"neighboringImportanceEffect": neighboring_importance_effect,
		"objectiveRelevanceEffect": objective_relevance_effect,
		"expectedIntelFloorEffect": floor_effect,
		"uncertaintyReduction": uncertainty_reduction,
		"criticalLowIntelPenalty": critical_penalty,
		"total": floor_effect + neighboring_importance_effect + objective_relevance_effect + uncertainty_reduction - critical_penalty
	}

static func _recon_stack_heuristic_components(state: Dictionary, hex_id: String) -> Dictionary:
	var critical_importance := _critical_adjacent_importance(state, hex_id)
	var objective_importance := _adjacent_enemy_importance(state, hex_id)
	var distance_to_frontline := _distance_to_frontline(hex_id, state)
	var has_combat_stack := int(state["combatLoad"].get(hex_id, 0)) > 0

	var stacked_combat_bonus := 0.0
	if has_combat_stack and critical_importance > 0.0:
		stacked_combat_bonus = critical_importance * 1.8

	var behind_line_no_intel_penalty := 0.0
	if objective_importance <= 0.0 and distance_to_frontline >= 2:
		behind_line_no_intel_penalty = float(distance_to_frontline - 1) * 1.4

	var isolated_critical_frontline_penalty := 0.0
	if not has_combat_stack and bool(state["frontline"].get(hex_id, false)) and critical_importance > 0.0:
		isolated_critical_frontline_penalty = critical_importance * 2.6

	return {
		"criticalAdjacentImportance": critical_importance,
		"objectiveImportance": objective_importance,
		"distanceToFrontline": distance_to_frontline,
		"hasCombatStack": has_combat_stack,
		"stackedCombatNearCriticalBonus": stacked_combat_bonus,
		"behindLineNoIntelPenalty": behind_line_no_intel_penalty,
		"isolatedCriticalFrontlinePenalty": isolated_critical_frontline_penalty,
		"total": stacked_combat_bonus - behind_line_no_intel_penalty - isolated_critical_frontline_penalty
	}

static func _frontline_coverage_from(hex_id: String, state: Dictionary) -> int:
	var coverage := 0
	for frontline_hex in (state["frontline"] as Dictionary).keys():
		if _hex_distance(hex_id, String(frontline_hex), state) <= ARTILLERY_RANGE:
			coverage += 1
	return coverage

static func _distance_to_frontline(hex_id: String, state: Dictionary) -> int:
	var best := 999
	for frontline_hex in (state["frontline"] as Dictionary).keys():
		best = min(best, _hex_distance(hex_id, String(frontline_hex), state))
	if best == 999:
		return 6
	return best

static func _distance_to_high_need_frontline(hex_id: String, state: Dictionary) -> int:
	var frontline_hexes := _sorted_frontline_hexes(state)
	if frontline_hexes.is_empty():
		return 6
	var highest_need := -INF
	for frontline_hex in frontline_hexes:
		highest_need = max(highest_need, _frontline_need_score(frontline_hex, state))
	var best := 999
	for frontline_hex in frontline_hexes:
		if not is_equal_approx(_frontline_need_score(frontline_hex, state), highest_need):
			continue
		best = mini(best, _hex_distance(hex_id, frontline_hex, state))
	return best if best < 999 else _distance_to_frontline(hex_id, state)

static func _reserve_clumping_penalty(hex_id: String, state: Dictionary) -> float:
	var penalty := 0.0
	for anchor in state["reserveAnchors"]:
		var dist := _hex_distance(hex_id, String(anchor), state)
		if dist <= 1:
			penalty += 1.5
		elif dist == 2:
			penalty += 0.6
	return penalty

static func _hex_distance(a_id: String, b_id: String, state: Dictionary) -> int:
	var coords: Dictionary = state["hexCoords"]
	if not coords.has(a_id) or not coords.has(b_id):
		return 99
	var a: Vector2i = coords[a_id]
	var b: Vector2i = coords[b_id]
	return HexGrid.distance(a, b)

static func _combat_cost(unit: Dictionary) -> int:
	if unit.has("prpCost"):
		var provided: int = int(unit.get("prpCost", 0))
		if provided > 0:
			return provided
	var size: String = String(unit.get("size", "company")).strip_edges().to_lower()
	return int(SIZE_COMBAT_COST.get(size, 3))

static func _is_support_role(role: String) -> bool:
	return role in [
		DeploymentTypes.ROLE_RECON,
		DeploymentTypes.ROLE_AIR_DEFENSE,
		DeploymentTypes.ROLE_ANTI_TANK_SUPPORT,
		DeploymentTypes.ROLE_ARTILLERY_SUPPORT,
		DeploymentTypes.ROLE_WEAPONS,
		DeploymentTypes.ROLE_COMMAND
	]

static func _make_order(unit: Dictionary, to_hex_id: String, stage: String, role: String, reason: String, reason_code: String) -> Dictionary:
	var unit_id: String = String(unit.get("id", ""))
	return {
		"id": "",
		"unitId": unit_id,
		"type": "deploy",
		"fromHexId": String(unit.get("hexId", "")),
		"toHexId": to_hex_id,
		"objectiveId": "",
		"stage": stage,
		"role": role,
		"reason": reason,
		"reason_code": reason_code,
		"score": _stage_weight(stage),
		"reason_meta": {}
	}

static func _stage_weight(stage: String) -> float:
	match stage:
		"A":
			return 4000.0
		"B":
			return 3000.0
		"C":
			return 2000.0
		"D":
			return 1000.0
		_:
			return 0.0

static func _reason_stage_a(unit: Dictionary, hex_id: String, stance: String, state: Dictionary) -> Dictionary:
	var p: float = float(state["priorities"].get(hex_id, 0.0))
	var expected_floor := _expected_intel_floor_for_role(String(unit.get("role", "")), true)
	var intel_components := _intel_score_components(state, hex_id, expected_floor)
	return {
		"reason": "Stage A: allocated combat anchor (%s) to %s (priority %.2f) with intel floor %d, objective importance %.2f, uncertainty reduction %.2f, and combat cap %d." % [stance, hex_id, p, expected_floor, float(intel_components.get("objectiveImportance", 0.0)), float(intel_components.get("uncertaintyReduction", 0.0)), MAX_COMBAT_CAPACITY],
		"reason_code": "combat_anchor_allocated",
		"meta": {"basePriority": p, "expectedIntelFloor": expected_floor, "intelComponents": intel_components}
	}

static func _reason_stage_b(unit: Dictionary, hex_id: String, state: Dictionary) -> Dictionary:
	var support_now: int = int(state["supportLoad"].get(hex_id, 0))
	var role: String = String(unit.get("role", "support"))
	var meta := {"supportSlotsNow": support_now, "supportCapacity": MAX_SUPPORT_CAPACITY}
	if role == DeploymentTypes.ROLE_RECON:
		var expected_floor := _expected_intel_floor_for_role(role, false)
		var recon_components := _recon_stack_heuristic_components(state, hex_id)
		meta["expectedIntelFloor"] = expected_floor
		meta["intelComponents"] = _intel_score_components(state, hex_id, expected_floor)
		meta["reconHeuristicComponents"] = recon_components
		return {
			"reason": "Stage B: attached recon to %s; support slots now %d/%d; critical-stack bonus %.2f, rear-no-intel penalty %.2f, isolated-critical-frontline penalty %.2f." % [hex_id, support_now, MAX_SUPPORT_CAPACITY, float(recon_components.get("stackedCombatNearCriticalBonus", 0.0)), float(recon_components.get("behindLineNoIntelPenalty", 0.0)), float(recon_components.get("isolatedCriticalFrontlinePenalty", 0.0))],
			"reason_code": "recon_support_attached_with_intel_heuristics",
			"meta": meta
		}
	return {
		"reason": "Stage B: attached %s to combat stack at %s; support slots now %d/%d." % [role, hex_id, support_now, MAX_SUPPORT_CAPACITY],
		"reason_code": "support_attached_to_stack",
		"meta": meta
	}

static func _reason_stage_c(hex_id: String, state: Dictionary) -> Dictionary:
	var coverage := _frontline_coverage_from(hex_id, state)
	return {
		"reason": "Stage C: placed artillery in rear hex %s for range-%d coverage of %d frontline hexes (not frontline)." % [hex_id, ARTILLERY_RANGE, coverage],
		"reason_code": "artillery_rear_coverage"
	}

static func _reason_stage_d(hex_id: String, state: Dictionary) -> Dictionary:
	var dist := _distance_to_frontline(hex_id, state)
	return {
		"reason": "Stage D: assigned reserve to %s with anti-clumping spacing and response distance %d from frontline." % [hex_id, dist],
		"reason_code": "reserve_positioned_response_spacing"
	}

static func _emit_stage_started(state: Dictionary, stage: String, meta: Dictionary = {}) -> void:
	_emit_trace_event(state, "stage_started", stage, {"reason_code": "stage_started", "reason_text": "Stage %s started." % stage, "meta": meta})

static func _emit_stage_completed(state: Dictionary, stage: String, meta: Dictionary = {}) -> void:
	_emit_trace_event(state, "stage_completed", stage, {"reason_code": "stage_completed", "reason_text": "Stage %s completed." % stage, "meta": meta})

static func _emit_candidate_scored(state: Dictionary, stage: String, unit: Dictionary, candidate_id: String, score: float, reason_code: String, reason_text: String, meta: Dictionary = {}) -> void:
	_emit_trace_event(state, "candidate_scored", stage, {"unit_id": String(unit.get("id", "")), "candidate_id": candidate_id, "reason_code": reason_code, "reason_text": reason_text, "score": score, "meta": meta})

static func _emit_candidate_rejected(state: Dictionary, stage: String, unit: Dictionary, candidate_id: String, reason_code: String, reason_text: String, score: float = 0.0, meta: Dictionary = {}) -> void:
	_emit_trace_event(state, "candidate_rejected", stage, {"unit_id": String(unit.get("id", "")), "candidate_id": candidate_id, "reason_code": reason_code, "reason_text": reason_text, "score": score, "meta": meta})

static func _emit_order_committed(state: Dictionary, stage: String, unit: Dictionary, hex_id: String, order: Dictionary) -> void:
	var order_meta := {}
	if order.get("reason_meta", null) is Dictionary:
		order_meta = (order.get("reason_meta", {}) as Dictionary).duplicate(true)
	order_meta["orderId"] = String(order.get("id", ""))
	order_meta["role"] = String(order.get("role", ""))
	_emit_trace_event(state, "order_committed", stage, {
		"unit_id": String(unit.get("id", "")),
		"candidate_id": hex_id,
		"reason_code": String(order.get("reason_code", "")),
		"reason_text": String(order.get("reason", "")),
		"score": float(order.get("score", 0.0)),
		"meta": order_meta
	})

static func _emit_trace_event(state: Dictionary, event_type: String, stage: String, payload: Dictionary) -> void:
	var callback_variant: Variant = state.get("traceEventCallback", Callable())
	if typeof(callback_variant) != TYPE_CALLABLE:
		return
	var callback := callback_variant as Callable
	if not callback.is_valid():
		return
	var event_payload := payload.duplicate(true)
	event_payload["stage"] = stage
	callback.call(event_type, event_payload)

static func _extract_hex_priorities(hex_scores: Dictionary) -> Dictionary:
	var priorities := {}
	for hex_id in hex_scores.keys():
		var score: Dictionary = hex_scores[hex_id] as Dictionary
		priorities[String(hex_id)] = float(score.get("priority", 0.0))
	return priorities

static func _extract_hex_pressures(hex_scores: Dictionary) -> Dictionary:
	var pressures := {}
	for hex_id in hex_scores.keys():
		var score: Dictionary = hex_scores[hex_id] as Dictionary
		pressures[String(hex_id)] = float(score.get("pressure", score.get("priority", 0.0)))
	return pressures

static func _terrain_by_hex(hexes: Array[Dictionary]) -> Dictionary:
	var terrain_by_hex := {}
	for hex in hexes:
		var hex_id := String(hex.get("id", ""))
		if hex_id.is_empty():
			continue
		terrain_by_hex[hex_id] = String(hex.get("terrain", DeploymentTypes.TERRAIN_LIGHT))
	return terrain_by_hex

static func _frontage_metadata(state: Dictionary) -> Dictionary:
	var covered: Array[String] = []
	var uncovered: Array[String] = []
	for hex_id in _sorted_frontline_hexes(state):
		if int((state["combatLoad"] as Dictionary).get(hex_id, 0)) > 0:
			covered.append(hex_id)
		else:
			uncovered.append(hex_id)

	var maximum_uncovered_distance := 0
	for hex_id in uncovered:
		if covered.is_empty():
			maximum_uncovered_distance = maxi(maximum_uncovered_distance, uncovered.size())
			continue
		var nearest_covered := 999
		for covered_hex in covered:
			nearest_covered = mini(nearest_covered, _hex_distance(hex_id, covered_hex, state))
		maximum_uncovered_distance = maxi(maximum_uncovered_distance, nearest_covered)

	return {
		"totalFrontlineHexes": covered.size() + uncovered.size(),
		"coveredFrontlineHexes": covered.size(),
		"coverageComplete": uncovered.is_empty(),
		"manpowerShortfall": uncovered.size(),
		"maximumUncoveredDistance": maximum_uncovered_distance,
		"coveredHexIds": covered,
		"uncoveredHexIds": uncovered
	}

static func _set_from_array(values: Array) -> Dictionary:
	var output := {}
	for value in values:
		output[String(value)] = true
	return output

static func _hex_coords(hexes: Array[Dictionary]) -> Dictionary:
	var coords := {}
	for hex in hexes:
		var hex_id: String = String(hex.get("id", ""))
		coords[hex_id] = Vector2i(int(hex.get("q", 0)), int(hex.get("r", 0)))
	return coords

static func _all_hex_ids(hexes: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for hex in hexes:
		var hex_id: String = String(hex.get("id", ""))
		if hex_id.is_empty():
			continue
		ids.append(hex_id)
	ids.sort()
	return ids

static func _sort_orders(orders: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_orders := orders.duplicate(true)
	sorted_orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var stage_a: String = String(a.get("stage", ""))
		var stage_b: String = String(b.get("stage", ""))
		if stage_a != stage_b:
			return stage_a < stage_b
		var unit_a: String = String(a.get("unitId", ""))
		var unit_b: String = String(b.get("unitId", ""))
		if unit_a != unit_b:
			return unit_a < unit_b
		return String(a.get("toHexId", "")) < String(b.get("toHexId", ""))
	)
	return sorted_orders
