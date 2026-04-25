extends RefCounted
class_name DeploymentPlanner

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
	var objective_mode := String(options.get("objectiveMode", "mixed_split")).strip_edges().to_lower().replace(" ", "_")
	var objectives: Array[Dictionary] = options.get("objectives", [])

	var state := _build_state(elements, hexes, sector_model)
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

static func _build_state(elements: Array[Dictionary], hexes: Array[Dictionary], sector_model: Dictionary) -> Dictionary:
	var frontline := _set_from_array(sector_model.get("frontlineHexes", []))
	var contested := _set_from_array(sector_model.get("contestedArea", []))
	var rear := _set_from_array(sector_model.get("rearArea", []))
	var priorities := _extract_hex_priorities(sector_model.get("hexScores", {}))
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
		var role := String(unit.get("role", DeploymentTypes.ROLE_INFANTRY))
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
	if combat_units.is_empty():
		return

	var attack_hexes := _ranked_hexes_for_mode(state, "attack")
	var defense_hexes := _ranked_hexes_for_mode(state, "defense")
	var mixed_cursor_attack := 0
	var mixed_cursor_defense := 0

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
		var selected := _first_legal_combat_hex(state, unit, candidates, start_idx)
		if selected.is_empty():
			selected = _first_legal_combat_hex(state, unit, _fallback_ranked_hexes(state), 0)
		if selected.is_empty():
			continue

		if stance == "attack":
			mixed_cursor_attack = int(selected.get("nextIndex", 0))
		else:
			mixed_cursor_defense = int(selected.get("nextIndex", 0))

		var hex_id := String(selected.get("hexId", ""))
		_commit_combat_placement(state, unit, hex_id, stance)
		orders.append(_make_order(unit, hex_id, "A", stance, _reason_stage_a(unit, hex_id, stance, state)))

static func _stage_b_attach_support(state: Dictionary, orders: Array[Dictionary]) -> void:
	var support_units: Array = state["units"]["support"]
	if support_units.is_empty():
		return

	var stacks: Array[String] = state["stackOrder"]
	for unit in support_units:
		var role := String(unit.get("role", ""))
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
			if role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT and bool(state["stackHasAttackByHex"].get(hex_id, false)):
				continue
			if not _can_place_support(state, hex_id):
				continue
			_commit_support_placement(state, unit, hex_id)
			var stance := "defense" if role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT else String(state["stackStanceByHex"].get(hex_id, "support"))
			orders.append(_make_order(unit, hex_id, "B", stance, _reason_stage_b(unit, hex_id, state)))
			placed = true
			break

		if placed:
			continue

		# If no stack can accept support, place as reserve support in rear while preserving support cap.
		for rear_hex in _ranked_rear_hexes(state):
			if not _can_place_support(state, rear_hex):
				continue
			_commit_support_placement(state, unit, rear_hex)
			orders.append(_make_order(unit, rear_hex, "B", "defense", "Stage B fallback: no legal combat stack with support capacity; attached to rear support node."))
			break

static func _stage_c_place_artillery(state: Dictionary, orders: Array[Dictionary]) -> void:
	var artillery_units: Array = state["units"]["artillery"]
	if artillery_units.is_empty():
		return

	var ranked_rear := _ranked_rear_hexes(state)
	for unit in artillery_units:
		var best_hex := ""
		var best_score := -INF
		for hex_id in ranked_rear:
			if (state["frontline"] as Dictionary).has(hex_id):
				continue
			if not _can_place_support(state, hex_id):
				continue
			var coverage := _frontline_coverage_from(hex_id, state)
			var priority := float(state["priorities"].get(hex_id, 0.0))
			var score := coverage * 100.0 + priority
			if score > best_score or (is_equal_approx(score, best_score) and hex_id < best_hex):
				best_score = score
				best_hex = hex_id
		if best_hex.is_empty():
			continue

		_commit_support_placement(state, unit, best_hex)
		orders.append(_make_order(unit, best_hex, "C", "support", _reason_stage_c(best_hex, state)))

static func _stage_d_place_reserves(state: Dictionary, orders: Array[Dictionary]) -> void:
	var reserve_units: Array = state["units"]["reserve"]
	if reserve_units.is_empty():
		return

	var candidates := _ranked_rear_hexes(state)
	if candidates.is_empty():
		candidates = _fallback_ranked_hexes(state)

	for unit in reserve_units:
		var role := String(unit.get("role", ""))
		var is_support := _is_support_role(role)
		var best_hex := ""
		var best_score := -INF
		for hex_id in candidates:
			if is_support and not _can_place_support(state, hex_id):
				continue
			if not is_support and not _can_place_combat(state, hex_id, _combat_cost(unit)):
				continue

			var base_priority := float(state["priorities"].get(hex_id, 0.0))
			var distance_to_front := _distance_to_frontline(hex_id, state)
			var response_bonus := 1.0 / float(distance_to_front + 1)
			var clump_penalty := _reserve_clumping_penalty(hex_id, state)
			var score := base_priority + response_bonus - clump_penalty

			if score > best_score or (is_equal_approx(score, best_score) and hex_id < best_hex):
				best_score = score
				best_hex = hex_id

		if best_hex.is_empty():
			continue

		if is_support:
			_commit_support_placement(state, unit, best_hex)
		else:
			_commit_combat_placement(state, unit, best_hex, "reserve")
			(state["reserveAnchors"] as Array).append(best_hex)
		orders.append(_make_order(unit, best_hex, "D", "reserve", _reason_stage_d(best_hex, state)))

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
		var a_priority := float(state["priorities"].get(a, 0.0))
		var b_priority := float(state["priorities"].get(b, 0.0))
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
		var a_priority := float(state["priorities"].get(a, 0.0))
		var b_priority := float(state["priorities"].get(b, 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return ranked

static func _fallback_ranked_hexes(state: Dictionary) -> Array[String]:
	var all_hexes: Array[String] = state["allHexes"]
	var ranked := all_hexes.duplicate()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var a_priority := float(state["priorities"].get(a, 0.0))
		var b_priority := float(state["priorities"].get(b, 0.0))
		if not is_equal_approx(a_priority, b_priority):
			return a_priority > b_priority
		return a < b
	)
	return ranked

static func _first_legal_combat_hex(state: Dictionary, unit: Dictionary, candidates: Array[String], start_index: int) -> Dictionary:
	var cost := _combat_cost(unit)
	for i in range(start_index, candidates.size()):
		var hex_id := candidates[i]
		if _can_place_combat(state, hex_id, cost):
			return {"hexId": hex_id, "nextIndex": i + 1}
	return {}

static func _commit_combat_placement(state: Dictionary, unit: Dictionary, hex_id: String, stance: String) -> void:
	var cost := _combat_cost(unit)
	state["combatLoad"][hex_id] = int(state["combatLoad"].get(hex_id, 0)) + cost
	state["placementByUnit"][String(unit.get("id", ""))] = hex_id
	state["stackStanceByHex"][hex_id] = stance
	var has_attack := bool(state["stackHasAttackByHex"].get(hex_id, false))
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
	var stance := String(state["stackStanceByHex"].get(hex_id, "defense"))
	var has_attack := bool(state["stackHasAttackByHex"].get(hex_id, false))
	var role := String(unit.get("role", ""))
	var role_bonus := 0.0
	if role == DeploymentTypes.ROLE_RECON:
		role_bonus = 1.0 if stance == "attack" else 0.6
	elif role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT:
		role_bonus = -2.0 if has_attack else (1.0 if stance == "defense" else 0.6)
	elif role == DeploymentTypes.ROLE_WEAPONS:
		role_bonus = 0.8
	return float(state["priorities"].get(hex_id, 0.0)) + role_bonus

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
		var provided := int(unit.get("prpCost", 0))
		if provided > 0:
			return provided
	var size := String(unit.get("size", "company")).strip_edges().to_lower()
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

static func _make_order(unit: Dictionary, to_hex_id: String, stage: String, role: String, reason: String) -> Dictionary:
	var unit_id := String(unit.get("id", ""))
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
		"score": _stage_weight(stage)
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

static func _reason_stage_a(unit: Dictionary, hex_id: String, stance: String, state: Dictionary) -> String:
	var p := float(state["priorities"].get(hex_id, 0.0))
	return "Stage A: allocated combat anchor (%s) to priority sector %s (priority %.2f) while respecting combat cap %d." % [stance, hex_id, p, MAX_COMBAT_CAPACITY]

static func _reason_stage_b(unit: Dictionary, hex_id: String, state: Dictionary) -> String:
	var support_now := int(state["supportLoad"].get(hex_id, 0))
	return "Stage B: attached %s to combat stack at %s; support slots now %d/%d." % [String(unit.get("role", "support")), hex_id, support_now, MAX_SUPPORT_CAPACITY]

static func _reason_stage_c(hex_id: String, state: Dictionary) -> String:
	var coverage := _frontline_coverage_from(hex_id, state)
	return "Stage C: placed artillery in rear hex %s for range-%d coverage of %d frontline hexes (not frontline)." % [hex_id, ARTILLERY_RANGE, coverage]

static func _reason_stage_d(hex_id: String, state: Dictionary) -> String:
	var dist := _distance_to_frontline(hex_id, state)
	return "Stage D: assigned reserve to %s with anti-clumping spacing and response distance %d from frontline." % [hex_id, dist]

static func _extract_hex_priorities(hex_scores: Dictionary) -> Dictionary:
	var priorities := {}
	for hex_id in hex_scores.keys():
		var score := hex_scores[hex_id] as Dictionary
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
		var hex_id := String(hex.get("id", ""))
		coords[hex_id] = Vector2i(int(hex.get("q", 0)), int(hex.get("r", 0)))
	return coords

static func _all_hex_ids(hexes: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for hex in hexes:
		var hex_id := String(hex.get("id", ""))
		if hex_id.is_empty():
			continue
		ids.append(hex_id)
	ids.sort()
	return ids

static func _sort_orders(orders: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_orders := orders.duplicate(true)
	sorted_orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var stage_a := String(a.get("stage", ""))
		var stage_b := String(b.get("stage", ""))
		if stage_a != stage_b:
			return stage_a < stage_b
		var unit_a := String(a.get("unitId", ""))
		var unit_b := String(b.get("unitId", ""))
		if unit_a != unit_b:
			return unit_a < unit_b
		return String(a.get("toHexId", "")) < String(b.get("toHexId", ""))
	)
	return sorted_orders
