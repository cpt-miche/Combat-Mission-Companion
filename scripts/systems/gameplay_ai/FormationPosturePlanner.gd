class_name FormationPosturePlanner
extends RefCounted

const FormationOperations = preload("res://scripts/domain/units/FormationOperations.gd")
const FormationHierarchy = preload("res://scripts/domain/units/FormationHierarchy.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const Rules = preload("res://scripts/core/Rules.gd")

const REORGANIZATION_COOLDOWN_TURNS := 2
const URGENT_OVERRIDE := 0.85
const ATTACK_THRESHOLDS := {"aggressive": 0.60, "balanced": 0.70, "defensive": 0.80}
const DEFENSE_THRESHOLDS := {"aggressive": 0.78, "balanced": 0.68, "defensive": 0.58}
const COVERAGE_TARGETS := {"aggressive": 0.75, "balanced": 1.0, "defensive": 1.25}
const CONCENTRATION_FRACTIONS := {"aggressive": 0.80, "balanced": 0.67, "defensive": 0.55}

static func prepare_ai_turn(
	units: Dictionary,
	owner: int,
	root: Dictionary,
	operational_state: Dictionary,
	objectives: Dictionary,
	territory: Dictionary,
	terrain: Dictionary,
	doctrine: String,
	turn_index: int,
	prior_state: Dictionary = {}
) -> Dictionary:
	var next_units := units.duplicate(true)
	var state := prior_state.duplicate(true)
	if not state.has("lineages"):
		state["lineages"] = {}
	var decisions: Array[Dictionary] = []
	_reconcile_combined_units(next_units, root, owner, decisions)

	var area := _best_area(operational_state, objectives, territory, owner)
	var target_hex := _parse_hex(String(area.get("target_hex", "")))
	var urgency := float(area.get("urgency", 0.0))
	var defending := bool(area.get("defending", false))
	var normalized_doctrine := doctrine if doctrine in ATTACK_THRESHOLDS else "balanced"
	var threshold := float((DEFENSE_THRESHOLDS if defending else ATTACK_THRESHOLDS).get(normalized_doctrine, 0.70))
	var frontline_hexes := _frontline_hexes(operational_state)
	var coverage_ratio := _coverage_ratio(next_units, owner, frontline_hexes.size())
	var coverage_target := float(COVERAGE_TARGETS.get(normalized_doctrine, 1.0))
	var should_concentrate := target_hex != Vector2i(-9999, -9999) and urgency >= threshold
	var should_spread := not should_concentrate and not frontline_hexes.is_empty() and coverage_ratio < coverage_target
	var assignments := {}
	var transaction := {"changed": false, "mode": "hold", "requires_atomic_validation": false, "created_component_ids": [], "source_lineage_ids": []}

	if should_concentrate:
		var desired_size := "battalion" if urgency >= threshold + 0.15 else "company"
		_concentrate(next_units, root, owner, target_hex, desired_size, urgency, turn_index, state, decisions)
		_assign_concentration(next_units, owner, target_hex, normalized_doctrine, urgency, terrain, assignments)
		_attach_support_assignments(next_units, owner, assignments, target_hex)
	elif should_spread:
		var coverage_targets := _ranked_coverage_targets(frontline_hexes, objectives, terrain)
		var before_spread := next_units.duplicate(true)
		var before_state := state.duplicate(true)
		var decision_start := decisions.size()
		_spread(next_units, root, owner, urgency, turn_index, state, decisions, true)
		if _friendly_unit_count(next_units, owner) > coverage_targets.size() * 4:
			next_units = before_spread
			state = before_state
			decisions.resize(decision_start)
			decisions.append({"action": "split_rejected", "reason": "insufficient legal coverage capacity", "target_count": coverage_targets.size()})
			should_spread = false
		else:
			_assign_coverage(next_units, owner, coverage_targets, assignments)
			var created_component_ids: Array[String] = []
			var source_lineage_ids: Array[String] = []
			for decision_index in range(decision_start, decisions.size()):
				var decision := decisions[decision_index]
				if String(decision.get("action", "")) != "split":
					continue
				var lineage_id := String(decision.get("lineage_id", ""))
				if not lineage_id.is_empty() and not source_lineage_ids.has(lineage_id):
					source_lineage_ids.append(lineage_id)
				for result_id_variant in decision.get("result_ids", []) as Array:
					var result_id := String(result_id_variant)
					if next_units.has(result_id) and not created_component_ids.has(result_id):
						created_component_ids.append(result_id)
			if not created_component_ids.is_empty():
				transaction = {
					"changed": true,
					"mode": "spread",
					"requires_atomic_validation": true,
					"created_component_ids": created_component_ids,
					"source_lineage_ids": source_lineage_ids
				}
	else:
		decisions.append({"action": "hold_structure", "reason": "posture_between_thresholds", "urgency": urgency, "coverage_ratio": coverage_ratio})

	state["last_plan_turn"] = turn_index
	state["posture"] = "concentrate" if should_concentrate else ("spread" if should_spread else "hold")
	state["target_hex"] = _hex_key(target_hex) if target_hex != Vector2i(-9999, -9999) else ""
	return {
		"units": next_units,
		"assignments": assignments,
		"decisions": decisions,
		"state": state,
		"posture": state["posture"],
		"defending": defending,
		"urgency": urgency,
		"coverage_ratio": coverage_ratio,
		"target_hex": state["target_hex"],
		"transaction": transaction
	}

static func _best_area(operational_state: Dictionary, objectives: Dictionary, territory: Dictionary, owner: int) -> Dictionary:
	var assessment := operational_state.get("assessment", {}) as Dictionary
	var urgency_by_sector := {}
	for entry_variant in assessment.get("sectorAssessments", []) as Array:
		if entry_variant is Dictionary:
			var entry := entry_variant as Dictionary
			urgency_by_sector[String(entry.get("sectorId", ""))] = float(entry.get("urgency", 0.0))
	var snapshot := operational_state.get("snapshot", {}) as Dictionary
	var best := {"urgency": 0.0, "target_hex": "", "defending": false, "sector_id": ""}
	for sector_variant in snapshot.get("sectors", []) as Array:
		if not (sector_variant is Dictionary):
			continue
		var sector := sector_variant as Dictionary
		var sector_id := String(sector.get("sectorId", ""))
		var score := maxf(float(sector.get("pressure", 0.0)), float(urgency_by_sector.get(sector_id, 0.0)))
		var targets: Array = sector.get("objectiveHexIds", []) as Array
		var target_hex_id := String(targets[0]) if not targets.is_empty() else ""
		for objective_hex_variant in targets:
			var objective_hex_id := String(objective_hex_variant)
			var priority := String((objectives.get(objective_hex_id, {}) as Dictionary).get("priority", "secondary"))
			var weight := 1.0 if priority == "primary" else 0.65
			if weight > score or target_hex_id.is_empty():
				score = maxf(score, weight)
				target_hex_id = objective_hex_id
		if target_hex_id.is_empty():
			var frontline := sector.get("frontlineHexIds", []) as Array
			if not frontline.is_empty():
				target_hex_id = String(frontline[0])
		if score > float(best["urgency"]) or (is_equal_approx(score, float(best["urgency"])) and target_hex_id < String(best["target_hex"])):
			best = {
				"urgency": score,
				"target_hex": target_hex_id,
				"defending": int(territory.get(target_hex_id, GameState.TerritoryOwnership.NEUTRAL)) == owner + 1,
				"sector_id": sector_id
			}
	if String(best["target_hex"]).is_empty():
		for objective_hex_variant in objectives.keys():
			var objective_hex_id := String(objective_hex_variant)
			var priority := String((objectives[objective_hex_id] as Dictionary).get("priority", "secondary"))
			var weight := 1.0 if priority == "primary" else 0.65
			if weight > float(best["urgency"]):
				best = {"urgency": weight, "target_hex": objective_hex_id, "defending": int(territory.get(objective_hex_id, 0)) == owner + 1, "sector_id": ""}
	return best

static func _concentrate(units: Dictionary, root: Dictionary, owner: int, target_hex: Vector2i, desired_size: String, urgency: float, turn_index: int, state: Dictionary, decisions: Array[Dictionary]) -> void:
	_combine_echelon(units, root, owner, "company", target_hex, urgency, turn_index, state, decisions)
	if desired_size == "battalion":
		_combine_echelon(units, root, owner, "battalion", target_hex, urgency, turn_index, state, decisions)

static func _combine_echelon(units: Dictionary, root: Dictionary, owner: int, parent_size: String, target_hex: Vector2i, urgency: float, turn_index: int, state: Dictionary, decisions: Array[Dictionary]) -> void:
	var parents: Array[Dictionary] = []
	_collect_nodes_by_size(root, parent_size, parents)
	for parent in parents:
		var parent_id := String(parent.get("id", ""))
		if not _cooldown_allows(parent_id, "concentrate", urgency, turn_index, state):
			continue
		var candidate_ids: Array[String] = []
		if units.has(parent_id) and bool((units[parent_id] as Dictionary).get("is_combined_formation", false)):
			candidate_ids.append(parent_id)
		for child_variant in parent.get("children", []) as Array:
			if not (child_variant is Dictionary):
				continue
			var child_id := String((child_variant as Dictionary).get("id", ""))
			if units.has(child_id) and int((units[child_id] as Dictionary).get("owner", -1)) == owner:
				candidate_ids.append(child_id)
		var by_hex := {}
		for candidate_id in candidate_ids:
			var hex := (units[candidate_id] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
			var key := _hex_key(hex)
			if not by_hex.has(key):
				by_hex[key] = []
			(by_hex[key] as Array).append(candidate_id)
		var group_keys: Array = by_hex.keys()
		group_keys.sort_custom(func(a: String, b: String) -> bool:
			return Pathfinding.hex_distance(_parse_hex(a), target_hex) < Pathfinding.hex_distance(_parse_hex(b), target_hex)
		)
		for group_key_variant in group_keys:
			var selected_raw := by_hex[group_key_variant] as Array
			if selected_raw.size() < 2:
				continue
			var selected: Array[String] = []
			for selected_id_variant in selected_raw:
				selected.append(String(selected_id_variant))
			var result := FormationOperations.combine(units, {}, root, selected, owner)
			if not bool(result.get("ok", false)):
				decisions.append({"action": "combine_rejected", "lineage_id": parent_id, "reason": String(result.get("reason", "unknown"))})
				continue
			_replace_dictionary(units, result.get("units", {}) as Dictionary)
			_record_state(parent_id, "concentrate", turn_index, _hex_key(target_hex), state)
			decisions.append({"action": "combine", "lineage_id": parent_id, "selected_ids": selected, "target_hex": _hex_key(target_hex), "urgency": urgency})
			break

static func _spread(units: Dictionary, root: Dictionary, owner: int, urgency: float, turn_index: int, state: Dictionary, decisions: Array[Dictionary], allow_temporary_overstack: bool = false) -> void:
	for wanted_size in ["battalion", "company"]:
		var ids: Array[String] = []
		for unit_id_variant in units.keys():
			var unit_id := String(unit_id_variant)
			var unit := units[unit_id] as Dictionary
			if int(unit.get("owner", -1)) == owner and _size_name(unit) == wanted_size and GameState.is_unit_alive(unit):
				ids.append(unit_id)
		ids.sort()
		for unit_id in ids:
			if not units.has(unit_id) or not _cooldown_allows(unit_id, "spread", urgency, turn_index, state):
				continue
			var result := FormationOperations.split(units, {}, root, unit_id, owner, not allow_temporary_overstack)
			if not bool(result.get("ok", false)):
				decisions.append({"action": "split_rejected", "lineage_id": unit_id, "reason": String(result.get("reason", "unknown"))})
				continue
			_replace_dictionary(units, result.get("units", {}) as Dictionary)
			_record_state(unit_id, "spread", turn_index, "", state)
			decisions.append({"action": "split", "lineage_id": unit_id, "result_ids": result.get("selected_ids", [])})

static func _assign_coverage(units: Dictionary, owner: int, targets: Array[Vector2i], assignments: Dictionary) -> void:
	if targets.is_empty():
		return
	var combat_ids: Array[String] = []
	var support_ids: Array[String] = []
	for unit_id_variant in units.keys():
		var unit_id := String(unit_id_variant)
		var unit := units[unit_id] as Dictionary
		if int(unit.get("owner", -1)) != owner or not GameState.is_unit_alive(unit):
			continue
		if _is_support(unit):
			support_ids.append(unit_id)
		else:
			combat_ids.append(unit_id)
	combat_ids.sort()
	support_ids.sort()
	var load_by_target := {}
	for index in range(combat_ids.size()):
		var target := targets[index % targets.size()]
		assignments[combat_ids[index]] = target
		load_by_target[_hex_key(target)] = int(load_by_target.get(_hex_key(target), 0)) + 1
	for support_id in support_ids:
		if combat_ids.is_empty():
			break
		var best_target := targets[0]
		var best_load := 999999
		for target in targets:
			var target_load := int(load_by_target.get(_hex_key(target), 0))
			if target_load > 0 and target_load < best_load and target_load < 4:
				best_target = target
				best_load = target_load
		if best_load == 999999:
			break
		assignments[support_id] = best_target
		load_by_target[_hex_key(best_target)] = best_load + 1

static func _assign_concentration(units: Dictionary, owner: int, target_hex: Vector2i, doctrine: String, urgency: float, terrain: Dictionary, assignments: Dictionary) -> void:
	var combat_ids: Array[String] = []
	for unit_id_variant in units.keys():
		var unit_id := String(unit_id_variant)
		var unit := units[unit_id] as Dictionary
		if int(unit.get("owner", -1)) == owner and GameState.is_unit_alive(unit) and not _is_support(unit):
			combat_ids.append(unit_id)
	combat_ids.sort_custom(func(a: String, b: String) -> bool:
		var a_hex := (units[a] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
		var b_hex := (units[b] as Dictionary).get("hex", Vector2i.ZERO) as Vector2i
		var a_distance := Pathfinding.hex_distance(a_hex, target_hex)
		var b_distance := Pathfinding.hex_distance(b_hex, target_hex)
		return a_distance < b_distance if a_distance != b_distance else a < b
	)
	var fraction := float(CONCENTRATION_FRACTIONS.get(doctrine, 0.67))
	if urgency >= URGENT_OVERRIDE:
		fraction = minf(fraction + 0.15, 0.90)
	var assigned_count := mini(combat_ids.size(), maxi(1, int(ceil(float(combat_ids.size()) * fraction))))
	if combat_ids.size() > 2:
		assigned_count = mini(assigned_count, combat_ids.size() - 1)
	var candidate_targets := _concentration_targets(target_hex, terrain)
	var projected_units := units.duplicate(true)
	for index in range(assigned_count):
		var unit_id := combat_ids[index]
		var assigned_target := _first_legal_projected_target(projected_units, unit_id, candidate_targets)
		if assigned_target == Vector2i(-9999, -9999):
			continue
		assignments[unit_id] = assigned_target
		var projected_unit := (projected_units[unit_id] as Dictionary).duplicate(true)
		projected_unit["hex"] = assigned_target
		projected_units[unit_id] = projected_unit

static func _attach_support_assignments(units: Dictionary, owner: int, assignments: Dictionary, target_hex: Vector2i) -> void:
	if assignments.is_empty():
		return
	var assigned_targets: Array[Vector2i] = [target_hex]
	for target_variant in assignments.values():
		if target_variant is Vector2i and not assigned_targets.has(target_variant as Vector2i):
			assigned_targets.append(target_variant as Vector2i)
	var projected_units := units.duplicate(true)
	for assigned_id_variant in assignments.keys():
		var assigned_id := String(assigned_id_variant)
		if projected_units.has(assigned_id) and assignments[assigned_id_variant] is Vector2i:
			var assigned_unit := (projected_units[assigned_id] as Dictionary).duplicate(true)
			assigned_unit["hex"] = assignments[assigned_id_variant] as Vector2i
			projected_units[assigned_id] = assigned_unit
	for unit_id_variant in units.keys():
		var unit_id := String(unit_id_variant)
		var unit := units[unit_id] as Dictionary
		if int(unit.get("owner", -1)) == owner and GameState.is_unit_alive(unit) and _is_support(unit):
			var assigned_target := _first_legal_projected_target(projected_units, unit_id, assigned_targets)
			if assigned_target == Vector2i(-9999, -9999):
				continue
			assignments[unit_id] = assigned_target
			var projected_unit := (projected_units[unit_id] as Dictionary).duplicate(true)
			projected_unit["hex"] = assigned_target
			projected_units[unit_id] = projected_unit

static func _concentration_targets(target_hex: Vector2i, terrain: Dictionary) -> Array[Vector2i]:
	var targets: Array[Vector2i] = [target_hex]
	var dimensions := GameState.selected_map_dimensions
	for q in range(maxi(0, target_hex.x - 1), mini(maxi(dimensions.x, 1), target_hex.x + 2)):
		for r in range(maxi(0, target_hex.y - 1), mini(maxi(dimensions.y, 1), target_hex.y + 2)):
			var candidate := Vector2i(q, r)
			if candidate != target_hex and Pathfinding.are_adjacent(target_hex, candidate):
				targets.append(candidate)
	if targets.size() > 2:
		var ring := targets.slice(1)
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_score := _terrain_defense_score(String(terrain.get(_hex_key(a), "light")))
			var b_score := _terrain_defense_score(String(terrain.get(_hex_key(b), "light")))
			return a_score > b_score if not is_equal_approx(a_score, b_score) else _hex_key(a) < _hex_key(b)
		)
		targets = [target_hex]
		for candidate in ring:
			targets.append(candidate)
	return targets

static func _first_legal_projected_target(projected_units: Dictionary, unit_id: String, targets: Array[Vector2i]) -> Vector2i:
	if not projected_units.has(unit_id):
		return Vector2i(-9999, -9999)
	var moving_unit := projected_units[unit_id] as Dictionary
	for target in targets:
		var occupants: Array[Dictionary] = []
		for other_id_variant in projected_units.keys():
			if String(other_id_variant) == unit_id:
				continue
			var other := projected_units[other_id_variant] as Dictionary
			if int(other.get("owner", -1)) == int(moving_unit.get("owner", -1)) and GameState.is_unit_alive(other) and (other.get("hex", Vector2i.ZERO) as Vector2i) == target:
				occupants.append(other)
		if bool(Rules.can_enter_stack(moving_unit, occupants).get("ok", false)):
			return target
	return Vector2i(-9999, -9999)

static func _ranked_coverage_targets(frontline_hexes: Array[Vector2i], objectives: Dictionary, terrain: Dictionary) -> Array[Vector2i]:
	var targets := frontline_hexes.duplicate()
	for objective_hex_variant in objectives.keys():
		var hex := _parse_hex(String(objective_hex_variant))
		if hex != Vector2i(-9999, -9999) and not targets.has(hex):
			targets.append(hex)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_score := _terrain_defense_score(String(terrain.get(_hex_key(a), "light"))) + _objective_weight(objectives, _hex_key(a))
		var b_score := _terrain_defense_score(String(terrain.get(_hex_key(b), "light"))) + _objective_weight(objectives, _hex_key(b))
		return a_score > b_score if not is_equal_approx(a_score, b_score) else _hex_key(a) < _hex_key(b)
	)
	return targets

static func _frontline_hexes(operational_state: Dictionary) -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	var snapshot := operational_state.get("snapshot", {}) as Dictionary
	for sector_variant in snapshot.get("sectors", []) as Array:
		if not (sector_variant is Dictionary):
			continue
		for hex_id_variant in (sector_variant as Dictionary).get("frontlineHexIds", []) as Array:
			var hex := _parse_hex(String(hex_id_variant))
			if hex != Vector2i(-9999, -9999) and not output.has(hex):
				output.append(hex)
	output.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _hex_key(a) < _hex_key(b))
	return output

static func _coverage_ratio(units: Dictionary, owner: int, frontline_count: int) -> float:
	if frontline_count <= 0:
		return 1.0
	var elements := 0.0
	for unit_variant in units.values():
		if not (unit_variant is Dictionary):
			continue
		var unit := unit_variant as Dictionary
		if int(unit.get("owner", -1)) != owner or not GameState.is_unit_alive(unit) or _is_support(unit):
			continue
		elements += 1.0
	return elements / float(frontline_count)

static func _friendly_unit_count(units: Dictionary, owner: int) -> int:
	var count := 0
	for unit_variant in units.values():
		if unit_variant is Dictionary and int((unit_variant as Dictionary).get("owner", -1)) == owner and GameState.is_unit_alive(unit_variant as Dictionary):
			count += 1
	return count

static func _reconcile_combined_units(units: Dictionary, root: Dictionary, owner: int, decisions: Array[Dictionary]) -> void:
	for unit_id_variant in units.keys().duplicate():
		var unit_id := String(unit_id_variant)
		if not units.has(unit_id):
			continue
		var unit := units[unit_id] as Dictionary
		if int(unit.get("owner", -1)) != owner or not bool(unit.get("is_combined_formation", false)):
			continue
		var living_components: Array[Dictionary] = []
		for component_variant in unit.get("combined_components", []) as Array:
			if not (component_variant is Dictionary):
				continue
			var component := (component_variant as Dictionary).duplicate(true)
			var tree_node := FormationHierarchy.find_node(root, String(component.get("id", "")))
			if not tree_node.is_empty() and GameState.is_unit_alive(tree_node):
				living_components.append(FormationOperations.gameplay_snapshot(tree_node, component, owner))
		if living_components.size() >= 2:
			unit["combined_components"] = living_components
			units[unit_id] = unit
			continue
		units.erase(unit_id)
		if living_components.size() == 1:
			var survivor := living_components[0]
			survivor["owner"] = owner
			survivor["hex"] = unit.get("hex", Vector2i.ZERO)
			units[String(survivor.get("id", ""))] = survivor
		decisions.append({"action": "dissolve_invalid_combined", "lineage_id": unit_id, "survivor_count": living_components.size()})

static func _cooldown_allows(lineage_id: String, requested_mode: String, urgency: float, turn_index: int, state: Dictionary) -> bool:
	if urgency >= URGENT_OVERRIDE:
		return true
	var lineages := state.get("lineages", {}) as Dictionary
	if not lineages.has(lineage_id):
		return true
	var prior := lineages[lineage_id] as Dictionary
	if String(prior.get("mode", "")) == requested_mode:
		return true
	return turn_index - int(prior.get("turn", -999)) >= REORGANIZATION_COOLDOWN_TURNS

static func _record_state(lineage_id: String, mode: String, turn_index: int, target_hex: String, state: Dictionary) -> void:
	var lineages := state.get("lineages", {}) as Dictionary
	lineages[lineage_id] = {"mode": mode, "turn": turn_index, "target_hex": target_hex}
	state["lineages"] = lineages

static func _collect_nodes_by_size(node: Dictionary, wanted_size: String, output: Array[Dictionary]) -> void:
	if node.is_empty():
		return
	if _size_name(node) == wanted_size:
		output.append(node)
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			_collect_nodes_by_size(child_variant as Dictionary, wanted_size, output)

static func _replace_dictionary(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	target.merge(source, true)

static func _is_support(unit: Dictionary) -> bool:
	var role := String(unit.get("role", "")).to_lower().replace("_", "")
	return role.contains("weapon") or role.contains("machinegun") or role.contains("mortar") or role.contains("artillery") or role.contains("howitzer") or role.contains("antitank") or role.contains("airdefense") or role.contains("headquarters") or role == "cannon"

static func _size_name(unit: Dictionary) -> String:
	return String(unit.get("size", "")).strip_edges().to_lower()

static func _objective_weight(objectives: Dictionary, key: String) -> float:
	if not objectives.has(key) or not (objectives[key] is Dictionary):
		return 0.0
	return 1.0 if String((objectives[key] as Dictionary).get("priority", "secondary")) == "primary" else 0.65

static func _terrain_defense_score(terrain_id: String) -> float:
	var normalized := terrain_id.to_lower()
	if normalized.contains("urban") or normalized.contains("building"):
		return 0.5
	if normalized.contains("wood") or normalized.contains("rough"):
		return 0.35
	if normalized.contains("road"):
		return 0.05
	return 0.15

static func _parse_hex(hex_id: String) -> Vector2i:
	var parts := hex_id.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-9999, -9999)
	return Vector2i(int(parts[0]), int(parts[1]))

static func _hex_key(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]
