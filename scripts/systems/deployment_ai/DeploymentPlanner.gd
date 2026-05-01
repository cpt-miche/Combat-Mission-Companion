extends RefCounted
class_name DeploymentPlanner

const ReconAIConfig = preload("res://scripts/core/ReconAIConfig.gd")

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
	var objectives: Array[Dictionary] = options.get("objectives", [])

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

	var state := {
		"frontline": frontline,
		"contested": contested,
		"rear": rear,
		"priorities": priorities,
		"hexCoords": hex_coords,
		"allHexes": all_hexes,
		"combatLoad": {},
		"supportLoad": {},
		"placementByUnit": {},
		"stackStanceByHex": {},
		"stackHasAttackByHex": {},
		"stackOrder": [],
		"reserveAnchors": [],
		"traceEventCallback": options.get("traceEventCallback", Callable()),
		"units": {
			"combat": [],
			"support": [],
			"artillery": [],
			"reserve": []
		}
	}

	var unit_ordered := elements.duplicate(true)
	unit_ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)

	for unit in unit_ordered:
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

	var attack_hexes := _ranked_hexes_for_mode(state, "attack")
	var defense_hexes := _ranked_hexes_for_mode(state, "defense")
	var mixed_cursor_attack := 0
	var mixed_cursor_defense := 0
	var committed := 0

	for i in range(combat_units.size()):
		var unit: Dictionary = combat_units[i]
		var stance := "defense"
		if objective_mode == "attack-only":
			stance = "attack"
		elif objective_mode == "defense-only":
			stance = "defense"
		else:
			stance = "attack" if i % 2 == 0 else "defense"

		var candidates := attack_hexes if stance == "attack" else defense_hexes
		var start_idx := mixed_cursor_attack if stance == "attack" else mixed_cursor_defense
		var selected := _first_legal_combat_hex(state, unit, candidates, start_idx, "A", stance)
		if selected.is_empty():
			selected = _first_legal_combat_hex(state, unit, _fallback_ranked_hexes(state), 0, "A", stance)
		if selected.is_empty():
			_emit_candidate_rejected(state, "A", unit, "", "combat_no_legal_hex", "Stage A: no legal combat hex available after evaluating candidate pools.", 0.0, {"stance": stance})
			continue

		if stance == "attack":
			mixed_cursor_attack = int(selected.get("nextIndex", 0))
		else:
			mixed_cursor_defense = int(selected.get("nextIndex", 0))

		var hex_id: String = String(selected.get("hexId", ""))
		_commit_combat_placement(state, unit, hex_id, stance)
		var stage_reason := _reason_stage_a(unit, hex_id, stance, state)
		var order := _make_order(unit, hex_id, "A", stance, stage_reason["reason"], stage_reason["reason_code"])
		order["reason_meta"] = stage_reason.get("meta", {})
		orders.append(order)
		_emit_order_committed(state, "A", unit, hex_id, order)
		committed += 1
	_emit_stage_completed(state, "A", {"orderCount": committed, "objectiveMode": objective_mode})

static func _stage_b_attach_support(state: Dictionary, orders: Array[Dictionary]) -> void:
	var support_units: Array = state["units"]["support"]
	_emit_stage_started(state, "B", {"unitCount": support_units.size()})
	if support_units.is_empty():
		_emit_stage_completed(state, "B", {"orderCount": 0})
		return

	var stacks: Array[String] = state["stackOrder"]
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
				candidate_meta = {
					"expectedIntelFloor": expected_floor,
					"intelComponents": _intel_score_components(state, hex_id, expected_floor)
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
			var distance_to_front := _distance_to_frontline(hex_id, state)
			var response_bonus := 1.0 / float(distance_to_front + 1)
			var clump_penalty := _reserve_clumping_penalty(hex_id, state)
			var score := base_priority + response_bonus - clump_penalty
			_emit_candidate_scored(state, "D", unit, hex_id, score, "reserve_position_score", "Stage D: scored reserve candidate for response and spacing.", {"distanceToFront": distance_to_front, "clumpPenalty": clump_penalty})

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
		return base_priority + role_bonus + float(intel_components.get("total", 0.0))
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
	return float(expected_floor) * importance_sum * float(ReconAIConfig.AI_SCOUT_COVERAGE["weights"]["coverage"])

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
	return {
		"objectiveImportance": objective_importance,
		"sectorImportance": sector_importance,
		"expectedIntelFloorEffect": floor_effect,
		"uncertaintyReduction": uncertainty_reduction,
		"criticalLowIntelPenalty": critical_penalty,
		"total": floor_effect + uncertainty_reduction - critical_penalty
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
	return int((abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2)

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
		"elementId": unit_id,
		"type": "deploy",
		"fromHexId": String(unit.get("hexId", "")),
		"toHexId": to_hex_id,
		"hexId": to_hex_id,
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
		meta["expectedIntelFloor"] = expected_floor
		meta["intelComponents"] = _intel_score_components(state, hex_id, expected_floor)
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
	var event_meta := meta.duplicate(true)
	event_meta["unitId"] = String(unit.get("id", ""))
	event_meta["candidateId"] = candidate_id
	_emit_trace_event(state, "candidate_scored", stage, {"reason_code": reason_code, "reason_text": reason_text, "score": score, "meta": event_meta})

static func _emit_candidate_rejected(state: Dictionary, stage: String, unit: Dictionary, candidate_id: String, reason_code: String, reason_text: String, score: float = 0.0, meta: Dictionary = {}) -> void:
	var event_meta := meta.duplicate(true)
	event_meta["unitId"] = String(unit.get("id", ""))
	event_meta["candidateId"] = candidate_id
	_emit_trace_event(state, "candidate_rejected", stage, {"reason_code": reason_code, "reason_text": reason_text, "score": score, "meta": event_meta})

static func _emit_order_committed(state: Dictionary, stage: String, unit: Dictionary, hex_id: String, order: Dictionary) -> void:
	var order_meta := {}
	if order.get("reason_meta", null) is Dictionary:
		order_meta = (order.get("reason_meta", {}) as Dictionary).duplicate(true)
	order_meta["unitId"] = String(unit.get("id", ""))
	order_meta["candidateId"] = hex_id
	order_meta["orderId"] = String(order.get("id", ""))
	order_meta["role"] = String(order.get("role", ""))
	_emit_trace_event(state, "order_committed", stage, {
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
