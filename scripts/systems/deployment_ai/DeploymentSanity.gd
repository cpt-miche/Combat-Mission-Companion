extends RefCounted
class_name DeploymentSanity

const MAX_COMBAT_CAPACITY := 9
const MAX_SUPPORT_CAPACITY := 3
const ARTILLERY_RANGE := 6
const MAX_REPAIR_PASSES := 4

const SIZE_COMBAT_COST := {
	"platoon": 1,
	"company": 3,
	"battalion": 9
}

const SUPPORT_ROLES := {
	DeploymentTypes.ROLE_RECON: true,
	DeploymentTypes.ROLE_AIR_DEFENSE: true,
	DeploymentTypes.ROLE_ANTI_TANK_SUPPORT: true,
	DeploymentTypes.ROLE_ARTILLERY_SUPPORT: true,
	DeploymentTypes.ROLE_WEAPONS: true,
	DeploymentTypes.ROLE_COMMAND: true
}

const COMBAT_ROLES := {
	DeploymentTypes.ROLE_INFANTRY: true,
	DeploymentTypes.ROLE_ARMOR: true,
	DeploymentTypes.ROLE_MOBILITY: true
}

static func sanitize_plan(plan: Dictionary, hexes: Array[Dictionary], sector_model: Dictionary) -> Dictionary:
	var sanitized := plan.duplicate(true)
	var warnings: Array[String] = []
	var state := _build_state(sanitized, hexes, sector_model)

	for _pass_idx in range(MAX_REPAIR_PASSES):
		var changed := false
		changed = _repair_isolated_support(state, warnings) or changed
		changed = _repair_exposed_artillery(state, warnings) or changed
		changed = _repair_reserve_clumping(state, warnings) or changed
		changed = _repair_empty_important_frontage(state, warnings) or changed
		changed = _repair_over_split_screens(state, warnings) or changed
		changed = _repair_tank_misuse(state, warnings) or changed
		if not changed:
			break

	_append_unresolved_warnings(state, warnings)
	sanitized["orders"] = _sorted_orders(state["orders"])
	sanitized["warnings"] = _dedupe_sorted_strings(warnings)
	return sanitized

static func _build_state(plan: Dictionary, hexes: Array[Dictionary], sector_model: Dictionary) -> Dictionary:
	var units_by_id := {}
	var unit_ids: Array[String] = []
	for unit in (plan.get("elements", []) as Array):
		var as_dict := unit as Dictionary
		var unit_id := String(as_dict.get("id", ""))
		if unit_id.is_empty():
			continue
		units_by_id[unit_id] = as_dict
		unit_ids.append(unit_id)
	unit_ids.sort()

	var orders: Array[Dictionary] = []
	for order in (plan.get("orders", []) as Array):
		orders.append((order as Dictionary).duplicate(true))

	var latest_order_idx := {}
	for i in range(orders.size()):
		var order := orders[i]
		var unit_id := String(order.get("unitId", order.get("elementId", "")))
		if unit_id.is_empty():
			continue
		latest_order_idx[unit_id] = i

	var hex_ids: Array[String] = []
	var terrain_by_hex := {}
	var neighbors := {}
	var coords := {}
	for hex in hexes:
		var hex_id := String(hex.get("id", ""))
		if hex_id.is_empty():
			continue
		hex_ids.append(hex_id)
		terrain_by_hex[hex_id] = String(hex.get("terrain", DeploymentTypes.TERRAIN_OPEN))
		coords[hex_id] = Vector2i(int(hex.get("q", 0)), int(hex.get("r", 0)))
		var neighbor_ids: Array[String] = []
		for n in (hex.get("neighborIds", []) as Array):
			neighbor_ids.append(String(n))
		neighbor_ids.sort()
		neighbors[hex_id] = neighbor_ids
	hex_ids.sort()

	var priorities := {}
	var max_priority := 0.0
	var hex_scores := sector_model.get("hexScores", {}) as Dictionary
	for hex_id in hex_scores.keys():
		var score := hex_scores[hex_id] as Dictionary
		var p := float(score.get("priority", 0.0))
		priorities[String(hex_id)] = p
		max_priority = max(max_priority, p)

	var frontline := _set_from_array(sector_model.get("frontlineHexes", []))
	var rear := _set_from_array(sector_model.get("rearArea", []))

	var placements := {}
	for unit_id in unit_ids:
		var idx := int(latest_order_idx.get(unit_id, -1))
		if idx >= 0:
			placements[unit_id] = String(orders[idx].get("toHexId", orders[idx].get("hexId", "")))
		else:
			placements[unit_id] = String((units_by_id[unit_id] as Dictionary).get("hexId", ""))

	var attack_stacks := {}
	for order in orders:
		var as_order := order as Dictionary
		var unit_id := String(as_order.get("unitId", as_order.get("elementId", "")))
		if unit_id.is_empty():
			continue
		var unit := units_by_id.get(unit_id, {}) as Dictionary
		if not COMBAT_ROLES.has(String(unit.get("role", ""))):
			continue
		if String(as_order.get("stance", "")).to_lower() != "attack":
			continue
		var to_hex := String(as_order.get("toHexId", as_order.get("hexId", "")))
		if to_hex.is_empty():
			continue
		attack_stacks[to_hex] = true

	return {
		"unitsById": units_by_id,
		"unitIds": unit_ids,
		"orders": orders,
		"latestOrderIdx": latest_order_idx,
		"placements": placements,
		"hexIds": hex_ids,
		"terrainByHex": terrain_by_hex,
		"neighbors": neighbors,
		"coords": coords,
		"priorities": priorities,
		"maxPriority": max_priority,
		"frontline": frontline,
		"rear": rear,
		"attackStacks": attack_stacks
	}

static func _repair_isolated_support(state: Dictionary, warnings: Array[String]) -> bool:
	var changed := false
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		var role := String(unit.get("role", ""))
		if role == DeploymentTypes.ROLE_ARTILLERY_SUPPORT or not SUPPORT_ROLES.has(role):
			continue
		var from_hex := String(state["placements"].get(unit_id, ""))
		if not _is_support_isolated(unit_id, from_hex, state):
			continue
		var to_hex := _best_combat_stack_for_support(unit_id, state)
		if to_hex.is_empty():
			warnings.append("repair deferred: isolated support %s has no legal compatible combat stack" % unit_id)
			continue
		_move_unit(unit_id, to_hex, state, "S", "Sanity: moved isolated support to nearest high-value combat stack.")
		changed = true
	return changed

static func _repair_exposed_artillery(state: Dictionary, warnings: Array[String]) -> bool:
	var changed := false
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if String(unit.get("role", "")) != DeploymentTypes.ROLE_ARTILLERY_SUPPORT:
			continue
		var from_hex := String(state["placements"].get(unit_id, ""))
		if not _is_artillery_exposed(from_hex, state):
			continue
		var to_hex := _best_safe_rear_hex_for_artillery(unit_id, state)
		if to_hex.is_empty():
			warnings.append("repair deferred: exposed artillery %s has no safe rear support hex" % unit_id)
			continue
		_move_unit(unit_id, to_hex, state, "S", "Sanity: relocated artillery to safer rear support hex.")
		changed = true
	return changed

static func _repair_reserve_clumping(state: Dictionary, warnings: Array[String]) -> bool:
	var changed := false
	var reserve_combat_ids := _reserve_combat_ids(state)
	var reserve_by_hex := {}
	for unit_id in reserve_combat_ids:
		var hex_id := String(state["placements"].get(unit_id, ""))
		if not reserve_by_hex.has(hex_id):
			reserve_by_hex[hex_id] = []
		(reserve_by_hex[hex_id] as Array).append(unit_id)

	for hex_id in reserve_by_hex.keys():
		var ids := reserve_by_hex[hex_id] as Array
		ids.sort()
		while ids.size() > 1:
			var unit_id := String(ids.pop_back())
			var to_hex := _best_reserve_spread_hex(unit_id, state)
			if to_hex.is_empty():
				warnings.append("repair deferred: reserve clumping for %s could not be redistributed legally" % unit_id)
				continue
			_move_unit(unit_id, to_hex, state, "S", "Sanity: redistributed clumped reserve element.")
			changed = true
	return changed

static func _repair_empty_important_frontage(state: Dictionary, warnings: Array[String]) -> bool:
	var changed := false
	for hex_id in _important_frontline_hexes(state):
		if _combat_load(hex_id, state) > 0:
			continue
		var donor := _best_frontage_donor(hex_id, state)
		if donor.is_empty():
			warnings.append("unresolved: empty important frontage at %s has no legal donor" % hex_id)
			continue
		_move_unit(donor, hex_id, state, "S", "Sanity: filled important empty frontage with reassigned combat element.")
		changed = true
	return changed

static func _repair_over_split_screens(state: Dictionary, warnings: Array[String]) -> bool:
	var changed := false
	var weak_ids := _weak_screen_unit_ids(state)
	for unit_id in weak_ids:
		var from_hex := String(state["placements"].get(unit_id, ""))
		var target := _best_adjacent_weak_merge_target(unit_id, state)
		if target.is_empty():
			continue
		if _can_place_combat(target, _combat_cost(state["unitsById"][unit_id]), state):
			_move_unit(unit_id, target, state, "S", "Sanity: recombined over-split weak screen.")
			changed = true
		else:
			warnings.append("repair deferred: weak screen %s cannot legally merge due to combat capacity" % unit_id)
		if from_hex == target:
			continue
	return changed

static func _repair_tank_misuse(state: Dictionary, warnings: Array[String]) -> bool:
	var changed := false
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if String(unit.get("role", "")) != DeploymentTypes.ROLE_ARMOR:
			continue
		var from_hex := String(state["placements"].get(unit_id, ""))
		var terrain := String(state["terrainByHex"].get(from_hex, DeploymentTypes.TERRAIN_OPEN))
		if terrain not in [DeploymentTypes.TERRAIN_ROUGH, DeploymentTypes.TERRAIN_URBAN]:
			continue
		var to_hex := _best_non_restrictive_hex(unit_id, state)
		if to_hex.is_empty():
			warnings.append("accepted: armor %s remains on %s terrain because no legal alternative exists" % [unit_id, terrain])
			continue
		_move_unit(unit_id, to_hex, state, "S", "Sanity: moved armor out of rough/urban when avoidable.")
		changed = true
	return changed

static func _append_unresolved_warnings(state: Dictionary, warnings: Array[String]) -> void:
	for hex_id in _important_frontline_hexes(state):
		if _combat_load(hex_id, state) <= 0:
			warnings.append("unresolved: empty critical frontage remains at %s" % hex_id)

	for unit_id in state["unitIds"]:
		var role := String((state["unitsById"][unit_id] as Dictionary).get("role", ""))
		var at_hex := String(state["placements"].get(unit_id, ""))
		if role == DeploymentTypes.ROLE_ARTILLERY_SUPPORT and _is_artillery_exposed(at_hex, state):
			warnings.append("unresolved: artillery %s still exposed at %s" % [unit_id, at_hex])
		if role == DeploymentTypes.ROLE_RECON and _is_support_isolated(unit_id, at_hex, state):
			warnings.append("unresolved: recon %s remains isolated at %s" % [unit_id, at_hex])
		if role == DeploymentTypes.ROLE_ARMOR:
			var terrain := String(state["terrainByHex"].get(at_hex, DeploymentTypes.TERRAIN_OPEN))
			if terrain in [DeploymentTypes.TERRAIN_ROUGH, DeploymentTypes.TERRAIN_URBAN] and not _has_non_restrictive_hex_option(unit_id, state):
				warnings.append("accepted: armor %s in %s terrain is unavoidable" % [unit_id, terrain])

	for hex_id in state["hexIds"]:
		if _combat_load(hex_id, state) > MAX_COMBAT_CAPACITY - 1 and _is_overconcentrated(hex_id, state):
			warnings.append("unresolved: overconcentration risk at %s" % hex_id)
	if _has_reserve_clumping(state):
		warnings.append("unresolved: reserve clumping persists after bounded repair passes")

static func _move_unit(unit_id: String, to_hex: String, state: Dictionary, stage: String, reason: String) -> void:
	var from_hex := String(state["placements"].get(unit_id, ""))
	if from_hex == to_hex or to_hex.is_empty():
		return
	state["placements"][unit_id] = to_hex
	var idx := int(state["latestOrderIdx"].get(unit_id, -1))
	if idx >= 0:
		var order := state["orders"][idx] as Dictionary
		order["toHexId"] = to_hex
		order["hexId"] = to_hex
		order["stage"] = stage
		order["reason"] = reason
		state["orders"][idx] = order
		return

	var unit := state["unitsById"][unit_id] as Dictionary
	var order := {
		"id": "",
		"unitId": unit_id,
		"elementId": unit_id,
		"type": "deploy",
		"fromHexId": String(unit.get("hexId", "")),
		"toHexId": to_hex,
		"hexId": to_hex,
		"objectiveId": "",
		"stage": stage,
		"role": "sanity",
		"reason": reason,
		"score": 5000.0
	}
	(state["orders"] as Array).append(order)
	state["latestOrderIdx"][unit_id] = (state["orders"] as Array).size() - 1

static func _important_frontline_hexes(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var threshold := max(0.6 * float(state.get("maxPriority", 0.0)), 1.0)
	for hex_id in (state["frontline"] as Dictionary).keys():
		var as_str := String(hex_id)
		if float(state["priorities"].get(as_str, 0.0)) >= threshold:
			result.append(as_str)
	result.sort_custom(func(a: String, b: String) -> bool:
		var ap := float(state["priorities"].get(a, 0.0))
		var bp := float(state["priorities"].get(b, 0.0))
		if not is_equal_approx(ap, bp):
			return ap > bp
		return a < b
	)
	return result

static func _best_frontage_donor(target_hex: String, state: Dictionary) -> String:
	var candidates: Array[Dictionary] = []
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if not COMBAT_ROLES.has(String(unit.get("role", ""))):
			continue
		var from_hex := String(state["placements"].get(unit_id, ""))
		if from_hex == target_hex:
			continue
		var cost := _combat_cost(unit)
		if _combat_load(from_hex, state) - cost <= 0:
			continue
		if not _can_place_combat(target_hex, cost, state):
			continue
		var donor_priority := float(state["priorities"].get(from_hex, 0.0))
		var target_priority := float(state["priorities"].get(target_hex, 0.0))
		if donor_priority > target_priority and _combat_load(from_hex, state) <= MAX_COMBAT_CAPACITY - 1:
			continue
		candidates.append({
			"unitId": unit_id,
			"distance": _hex_distance(from_hex, target_hex, state),
			"donorPriority": donor_priority
		})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		if not is_equal_approx(float(a["donorPriority"]), float(b["donorPriority"])):
			return float(a["donorPriority"]) < float(b["donorPriority"])
		return String(a["unitId"]) < String(b["unitId"])
	)
	return String(candidates[0]["unitId"])

static func _best_combat_stack_for_support(unit_id: String, state: Dictionary) -> String:
	var from_hex := String(state["placements"].get(unit_id, ""))
	var unit := state["unitsById"].get(unit_id, {}) as Dictionary
	var is_anti_tank := String(unit.get("role", "")) == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT
	var candidates: Array[Dictionary] = []
	for hex_id in state["hexIds"]:
		if _combat_load(hex_id, state) <= 0:
			continue
		if is_anti_tank and bool((state["attackStacks"] as Dictionary).get(hex_id, false)):
			continue
		if not _can_place_support(hex_id, state):
			continue
		var distance := _hex_distance(from_hex, hex_id, state)
		var p := float(state["priorities"].get(hex_id, 0.0))
		candidates.append({"hex": hex_id, "distance": distance, "priority": p})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		if not is_equal_approx(float(a["priority"]), float(b["priority"])):
			return float(a["priority"]) > float(b["priority"])
		return String(a["hex"]) < String(b["hex"])
	)
	return String(candidates[0]["hex"])

static func _best_safe_rear_hex_for_artillery(unit_id: String, state: Dictionary) -> String:
	var from_hex := String(state["placements"].get(unit_id, ""))
	var candidates: Array[Dictionary] = []
	for hex_id in (state["rear"] as Dictionary).keys():
		var as_str := String(hex_id)
		if (state["frontline"] as Dictionary).has(as_str):
			continue
		if not _can_place_support(as_str, state):
			continue
		var coverage := _frontline_coverage(as_str, state)
		var nearest_combat := _nearest_combat_distance(as_str, state)
		var p := float(state["priorities"].get(as_str, 0.0))
		candidates.append({
			"hex": as_str,
			"coverage": coverage,
			"distance": _hex_distance(from_hex, as_str, state),
			"combatNear": nearest_combat,
			"priority": p
		})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["coverage"]) != int(b["coverage"]):
			return int(a["coverage"]) > int(b["coverage"])
		if int(a["combatNear"]) != int(b["combatNear"]):
			return int(a["combatNear"]) < int(b["combatNear"])
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		if not is_equal_approx(float(a["priority"]), float(b["priority"])):
			return float(a["priority"]) > float(b["priority"])
		return String(a["hex"]) < String(b["hex"])
	)
	return String(candidates[0]["hex"])

static func _best_reserve_spread_hex(unit_id: String, state: Dictionary) -> String:
	var unit := state["unitsById"][unit_id] as Dictionary
	var cost := _combat_cost(unit)
	var from_hex := String(state["placements"].get(unit_id, ""))
	var candidates: Array[Dictionary] = []
	for hex_id in (state["rear"] as Dictionary).keys():
		var as_str := String(hex_id)
		if as_str == from_hex:
			continue
		if not _can_place_combat(as_str, cost, state):
			continue
		var nearby_reserve := _reserve_neighbors(as_str, state)
		var p := float(state["priorities"].get(as_str, 0.0))
		candidates.append({
			"hex": as_str,
			"reserveNeighbors": nearby_reserve,
			"distance": _hex_distance(from_hex, as_str, state),
			"priority": p
		})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["reserveNeighbors"]) != int(b["reserveNeighbors"]):
			return int(a["reserveNeighbors"]) < int(b["reserveNeighbors"])
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		if not is_equal_approx(float(a["priority"]), float(b["priority"])):
			return float(a["priority"]) > float(b["priority"])
		return String(a["hex"]) < String(b["hex"])
	)
	return String(candidates[0]["hex"])

static func _best_adjacent_weak_merge_target(unit_id: String, state: Dictionary) -> String:
	var from_hex := String(state["placements"].get(unit_id, ""))
	var neighbors := state["neighbors"].get(from_hex, []) as Array
	var candidates: Array[String] = []
	for n in neighbors:
		var n_hex := String(n)
		if _combat_load(n_hex, state) <= 0:
			continue
		if not _has_weak_screen_on_hex(n_hex, state):
			continue
		if (state["frontline"] as Dictionary).has(from_hex) and (state["frontline"] as Dictionary).has(n_hex):
			if float(state["priorities"].get(from_hex, 0.0)) >= float(state["priorities"].get(n_hex, 0.0)):
				continue
		candidates.append(n_hex)
	if candidates.is_empty():
		return ""
	candidates.sort()
	return candidates[0]

static func _best_non_restrictive_hex(unit_id: String, state: Dictionary) -> String:
	var unit := state["unitsById"][unit_id] as Dictionary
	var cost := _combat_cost(unit)
	var from_hex := String(state["placements"].get(unit_id, ""))
	var candidates: Array[Dictionary] = []
	for hex_id in state["hexIds"]:
		var terrain := String(state["terrainByHex"].get(hex_id, DeploymentTypes.TERRAIN_OPEN))
		if terrain in [DeploymentTypes.TERRAIN_ROUGH, DeploymentTypes.TERRAIN_URBAN]:
			continue
		if not _can_place_combat(hex_id, cost, state):
			continue
		if _combat_load(hex_id, state) <= 0 and not (state["frontline"] as Dictionary).has(hex_id):
			continue
		candidates.append({
			"hex": hex_id,
			"distance": _hex_distance(from_hex, hex_id, state),
			"priority": float(state["priorities"].get(hex_id, 0.0))
		})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		if not is_equal_approx(float(a["priority"]), float(b["priority"])):
			return float(a["priority"]) > float(b["priority"])
		return String(a["hex"]) < String(b["hex"])
	)
	return String(candidates[0]["hex"])

static func _has_non_restrictive_hex_option(unit_id: String, state: Dictionary) -> bool:
	return not _best_non_restrictive_hex(unit_id, state).is_empty()

static func _is_support_isolated(unit_id: String, hex_id: String, state: Dictionary) -> bool:
	if _combat_load(hex_id, state) > 0:
		return false
	for n in (state["neighbors"].get(hex_id, []) as Array):
		if _combat_load(String(n), state) > 0:
			return false
	return true

static func _is_artillery_exposed(hex_id: String, state: Dictionary) -> bool:
	if (state["frontline"] as Dictionary).has(hex_id):
		return true
	return _nearest_combat_distance(hex_id, state) > 2

static func _nearest_combat_distance(hex_id: String, state: Dictionary) -> int:
	var best := 99
	for other_hex in state["hexIds"]:
		if _combat_load(other_hex, state) <= 0:
			continue
		best = min(best, _hex_distance(hex_id, other_hex, state))
	return best

static func _reserve_combat_ids(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if not COMBAT_ROLES.has(String(unit.get("role", ""))):
			continue
		var idx := int(state["latestOrderIdx"].get(unit_id, -1))
		if idx < 0:
			continue
		var role := String((state["orders"][idx] as Dictionary).get("role", ""))
		if role == "reserve":
			ids.append(unit_id)
	ids.sort()
	return ids

static func _weak_screen_unit_ids(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if not COMBAT_ROLES.has(String(unit.get("role", ""))):
			continue
		if _combat_cost(unit) > 1:
			continue
		var hex_id := String(state["placements"].get(unit_id, ""))
		if not (state["frontline"] as Dictionary).has(hex_id):
			continue
		if _combat_load(hex_id, state) != 1:
			continue
		ids.append(unit_id)
	ids.sort()
	return ids

static func _has_weak_screen_on_hex(hex_id: String, state: Dictionary) -> bool:
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if not COMBAT_ROLES.has(String(unit.get("role", ""))):
			continue
		if _combat_cost(unit) > 1:
			continue
		if String(state["placements"].get(unit_id, "")) == hex_id:
			return true
	return false

static func _reserve_neighbors(hex_id: String, state: Dictionary) -> int:
	var count := 0
	for unit_id in _reserve_combat_ids(state):
		var at_hex := String(state["placements"].get(unit_id, ""))
		if _hex_distance(hex_id, at_hex, state) <= 1:
			count += 1
	return count

static func _has_reserve_clumping(state: Dictionary) -> bool:
	var ids := _reserve_combat_ids(state)
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a_hex := String(state["placements"].get(String(ids[i]), ""))
			var b_hex := String(state["placements"].get(String(ids[j]), ""))
			if _hex_distance(a_hex, b_hex, state) <= 1:
				return true
	return false

static func _is_overconcentrated(hex_id: String, state: Dictionary) -> bool:
	for n in (state["neighbors"].get(hex_id, []) as Array):
		if _combat_load(String(n), state) == 0 and (state["frontline"] as Dictionary).has(String(n)):
			return true
	return false

static func _combat_load(hex_id: String, state: Dictionary) -> int:
	var load := 0
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if not COMBAT_ROLES.has(String(unit.get("role", ""))):
			continue
		if String(state["placements"].get(unit_id, "")) != hex_id:
			continue
		load += _combat_cost(unit)
	return load

static func _support_load(hex_id: String, state: Dictionary) -> int:
	var load := 0
	for unit_id in state["unitIds"]:
		var unit := state["unitsById"][unit_id] as Dictionary
		if not SUPPORT_ROLES.has(String(unit.get("role", ""))):
			continue
		if String(state["placements"].get(unit_id, "")) != hex_id:
			continue
		load += 1
	return load

static func _can_place_combat(hex_id: String, cost: int, state: Dictionary) -> bool:
	return _combat_load(hex_id, state) + cost <= MAX_COMBAT_CAPACITY

static func _can_place_support(hex_id: String, state: Dictionary) -> bool:
	return _support_load(hex_id, state) + 1 <= MAX_SUPPORT_CAPACITY

static func _frontline_coverage(hex_id: String, state: Dictionary) -> int:
	var covered := 0
	for frontline_hex in (state["frontline"] as Dictionary).keys():
		if _hex_distance(hex_id, String(frontline_hex), state) <= ARTILLERY_RANGE:
			covered += 1
	return covered

static func _combat_cost(unit: Dictionary) -> int:
	if unit.has("prpCost"):
		var provided := int(unit.get("prpCost", 0))
		if provided > 0:
			return provided
	var size := String(unit.get("size", "company")).to_lower()
	return int(SIZE_COMBAT_COST.get(size, 3))

static func _hex_distance(a_id: String, b_id: String, state: Dictionary) -> int:
	if a_id.is_empty() or b_id.is_empty():
		return 99
	var coords: Dictionary = state["coords"]
	if not coords.has(a_id) or not coords.has(b_id):
		return 99
	var a: Vector2i = coords[a_id]
	var b: Vector2i = coords[b_id]
	return int((abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2)

static func _set_from_array(values: Array) -> Dictionary:
	var mapped := {}
	for value in values:
		mapped[String(value)] = true
	return mapped

static func _sorted_orders(orders: Array[Dictionary]) -> Array[Dictionary]:
	var sorted := orders.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var stage_a := String(a.get("stage", ""))
		var stage_b := String(b.get("stage", ""))
		if stage_a != stage_b:
			return stage_a < stage_b
		var unit_a := String(a.get("unitId", a.get("elementId", "")))
		var unit_b := String(b.get("unitId", b.get("elementId", "")))
		if unit_a != unit_b:
			return unit_a < unit_b
		return String(a.get("toHexId", "")) < String(b.get("toHexId", ""))
	)
	for i in range(sorted.size()):
		sorted[i]["id"] = "deploy_%03d" % [i + 1]
	return sorted

static func _dedupe_sorted_strings(values: Array[String]) -> Array[String]:
	var set := {}
	for value in values:
		set[value] = true
	var output: Array[String] = []
	for value in set.keys():
		output.append(String(value))
	output.sort()
	return output
