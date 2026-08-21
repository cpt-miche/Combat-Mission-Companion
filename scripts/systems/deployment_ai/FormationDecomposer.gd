extends RefCounted
class_name FormationDecomposer

const COMBAT_PRP_COST_BY_SIZE := {
	"platoon": 1,
	"company": 3,
	"battalion": 9
}

const SIZE_RANKS := {
	"squad": 0,
	"section": 1,
	"platoon": 2,
	"company": 3,
	"battalion": 4,
	"regiment": 5,
	"division": 6,
	"army": 7
}

const SUPPORT_TYPES := {
	"artillery": true,
	"artillerysupport": true,
	"air_defense": true,
	"airdefense": true,
	"anti_tank": true,
	"antitanksupport": true,
	"engineer": true,
	"headquarters": true,
	"weapons": true,
	"mobility": true,
	"command": true,
	"support": true
}

const ROLE_CANONICAL_MAP := {
	"infantry": "infantry",
	"tank": "armor",
	"panzer": "armor",
	"light_tank": "armor",
	"medium_tank": "armor",
	"heavy_tank": "armor",
	"assault_gun": "armor",
	"tank_destroyer": "antiTankSupport",
	"armor": "armor",
	"recon": "recon",
	"airdefense": "airDefense",
	"air_defense": "airDefense",
	"antitank": "antiTankSupport",
	"anti_tank": "antiTankSupport",
	"antitanksupport": "antiTankSupport",
	"artillery": "artillerySupport",
	"artillerysupport": "artillerySupport",
	"engineer": "weapons",
	"weapons": "weapons",
	"mobility": "mobility",
	"mechanized": "mobility",
	"motorized": "mobility",
	"headquarters": "command",
	"command": "command",
	"support": "weapons"
}

const DEFAULT_WEIGHTS := {
	"frontage": 2.2,
	"screenStrongpoint": 1.8,
	"reserve": 1.4,
	"cohesionPenalty": 1.5,
	"overSplitPenalty": 1.3,
	"isolationPenalty": 1.2
}

static func decompose_formation_tree(root: Dictionary, options: Dictionary = {}) -> Dictionary:
	var weights: Dictionary = DEFAULT_WEIGHTS.merged(options.get("weights", {}), true)
	var min_deploy_size := String(options.get("minDeploySize", "platoon")).strip_edges().to_lower()
	var support_capacity_per_hex := int(options.get("supportCapacityPerHex", 3))
	var player_index := int(options.get("playerIndex", -1))
	var hex_id := String(options.get("hexId", "")).strip_edges()
	var context := options.get("context", {}) as Dictionary
	var target_combat_elements := int(options.get("targetCombatElements", -1))
	var preferred_base_size := String(options.get("preferredBaseSize", "company")).strip_edges().to_lower()

	var state := {
		"elements": [],
		"audit": [],
		"supportCountByHex": {},
		"weights": weights,
		"context": context,
		"minDeploySize": min_deploy_size,
		"supportCapacityPerHex": support_capacity_per_hex,
		"playerIndex": player_index,
		"hexId": hex_id,
		"targetCombatElements": target_combat_elements,
		"preferredBaseSize": preferred_base_size
	}

	if target_combat_elements >= 0:
		_decompose_for_frontage(root, state)
	else:
		_decompose_node(root, "", 0, state)

	var sanity := {
		"supportCapacityViolations": _support_capacity_violations(state["supportCountByHex"] as Dictionary, support_capacity_per_hex),
		"illegalSizeSplits": _illegal_size_splits(state["audit"] as Array),
		"model": "formationDecomposerV1"
	}

	return {
		"deployableElements": state["elements"],
		"splitAudit": state["audit"],
		"metadata": {
			"supportCountByHex": state["supportCountByHex"],
			"weights": weights,
			"context": context,
			"targetCombatElements": target_combat_elements,
			"selectedCombatElements": _combat_element_count(state["elements"] as Array),
			"frontageShortfall": maxi(0, target_combat_elements - _combat_element_count(state["elements"] as Array)) if target_combat_elements >= 0 else 0,
			"sanity": sanity
		}
	}

static func _decompose_for_frontage(root: Dictionary, state: Dictionary) -> void:
	var candidates: Array[Dictionary] = []
	_collect_company_first_candidates(root, "", 0, state, candidates)
	var target := maxi(0, int(state.get("targetCombatElements", 0)))

	while _candidate_combat_count(candidates) < target:
		var best_index := -1
		var best_gain := 0
		var best_id := ""
		var best_replacements: Array[Dictionary] = []
		for i in range(candidates.size()):
			var candidate := candidates[i]
			var formation := candidate.get("formation", {}) as Dictionary
			if _normalized_size(formation.get("size", "")) != "company":
				continue
			if not _is_combat_role(_formation_role(formation)):
				continue
			var replacements: Array[Dictionary] = []
			_collect_split_replacements(
				formation,
				String(formation.get("id", "")),
				int(candidate.get("depth", 0)) + 1,
				state,
				replacements
			)
			var gain := _candidate_combat_count(replacements) - 1
			var unit_id := String(formation.get("id", ""))
			if gain > best_gain or (gain == best_gain and gain > 0 and (best_id.is_empty() or unit_id < best_id)):
				best_index = i
				best_gain = gain
				best_id = unit_id
				best_replacements = replacements
		if best_index < 0:
			break
		var split_candidate := candidates[best_index]
		var split_formation := split_candidate.get("formation", {}) as Dictionary
		candidates.remove_at(best_index)
		for replacement in best_replacements:
			candidates.append(replacement)
		(state["audit"] as Array).append({
			"formationId": String(split_formation.get("id", "")),
			"formationName": String(split_formation.get("display_name", split_formation.get("id", ""))),
			"depth": int(split_candidate.get("depth", 0)),
			"action": "adaptive_split",
			"reason": "split company into real sub-units to meet frontage target",
			"decision": {
				"targetCombatElements": target,
				"combatElementsBefore": _candidate_combat_count(candidates) - best_gain,
				"combatElementsAfter": _candidate_combat_count(candidates),
				"combatElementGain": best_gain
			}
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_formation := a.get("formation", {}) as Dictionary
		var b_formation := b.get("formation", {}) as Dictionary
		return String(a_formation.get("id", "")) < String(b_formation.get("id", ""))
	)
	for candidate in candidates:
		_append_element(
			candidate.get("formation", {}) as Dictionary,
			String(candidate.get("parentId", "")),
			state
		)

static func _collect_company_first_candidates(
	node: Variant,
	parent_id: String,
	depth: int,
	state: Dictionary,
	output: Array[Dictionary]
) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return
	var formation := node as Dictionary
	if formation.is_empty() or not _is_formation_alive(formation):
		return
	var unit_id := String(formation.get("id", "")).strip_edges()
	if unit_id.is_empty():
		return
	var role := _formation_role(formation)
	var size := _normalized_size(formation.get("size", ""))
	var children := _dictionary_children(formation)

	if role == DeploymentTypes.ROLE_COMMAND or _size_rank(size) > _size_rank(String(state.get("preferredBaseSize", "company"))):
		var before := output.size()
		for child in children:
			_collect_company_first_candidates(child, unit_id, depth + 1, state, output)
		if output.size() > before:
			(state["audit"] as Array).append({
				"formationId": unit_id,
				"formationName": String(formation.get("display_name", unit_id)),
				"depth": depth,
				"action": "company_first_split",
				"reason": "split higher echelon to company-or-lower deployment elements"
			})
			return

	if _is_eligible_deployment_element(formation, state):
		output.append({"formation": formation, "parentId": parent_id, "depth": depth})
		return

	for child in children:
		_collect_company_first_candidates(child, unit_id, depth + 1, state, output)

static func _collect_split_replacements(
	formation: Dictionary,
	parent_id: String,
	depth: int,
	state: Dictionary,
	output: Array[Dictionary]
) -> void:
	for child in _dictionary_children(formation):
		if not _is_formation_alive(child):
			continue
		var child_id := String(child.get("id", ""))
		var role := _canonical_role(child.get("role", "infantry"))
		if role == DeploymentTypes.ROLE_COMMAND:
			_collect_split_replacements(child, child_id, depth + 1, state, output)
		elif _is_eligible_deployment_element(child, state):
			output.append({"formation": child, "parentId": parent_id, "depth": depth})
		else:
			_collect_split_replacements(child, child_id, depth + 1, state, output)

static func _is_eligible_deployment_element(formation: Dictionary, state: Dictionary) -> bool:
	var role := _formation_role(formation)
	if role == DeploymentTypes.ROLE_COMMAND:
		return false
	var size := _normalized_size(formation.get("size", ""))
	var rank := _size_rank(size)
	if rank > _size_rank("battalion"):
		return false
	if rank >= _size_rank(String(state.get("minDeploySize", "platoon"))):
		return true
	return role == DeploymentTypes.ROLE_ANTI_TANK_SUPPORT and rank in [_size_rank("squad"), _size_rank("section")]

static func _is_formation_alive(formation: Dictionary) -> bool:
	return String(formation.get("status", "")).strip_edges().to_lower() != "dead"

static func _dictionary_children(formation: Dictionary) -> Array[Dictionary]:
	var children: Array[Dictionary] = []
	var children_variant: Variant = formation.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return children
	for child_variant in children_variant as Array:
		if typeof(child_variant) == TYPE_DICTIONARY:
			children.append(child_variant as Dictionary)
	return children

static func _candidate_combat_count(candidates: Array[Dictionary]) -> int:
	var count := 0
	for candidate in candidates:
		var formation := candidate.get("formation", {}) as Dictionary
		if _is_combat_role(_formation_role(formation)):
			count += 1
	return count

static func _combat_element_count(elements: Array) -> int:
	var count := 0
	for element_variant in elements:
		if typeof(element_variant) != TYPE_DICTIONARY:
			continue
		if not bool((element_variant as Dictionary).get("isSupport", false)):
			count += 1
	return count

static func formation_split_score(formation: Dictionary, options: Dictionary = {}) -> Dictionary:
	var weights := DEFAULT_WEIGHTS.merged(options.get("weights", {}), true)
	var context := options.get("context", {}) as Dictionary
	var depth := int(options.get("depth", 0))
	var sibling_count := int(options.get("siblingCount", 1))
	var child_count := _valid_child_count(formation)
	var deployable_child_count := _deployable_child_count(formation, String(options.get("minDeploySize", "platoon")))
	var split_factor: int = max(0, deployable_child_count - 1)

	var frontage_need: float = clamp(float(context.get("frontageCoverageNeed", 0.5)), 0.0, 1.0)
	var screen_need: float = clamp(float(context.get("screenNeed", 0.5)), 0.0, 1.0)
	var strongpoint_need: float = clamp(float(context.get("strongpointNeed", 0.5)), 0.0, 1.0)
	var reserve_need: float = clamp(float(context.get("reservePreservationNeed", 0.5)), 0.0, 1.0)

	var frontage_component: float = frontage_need * float(weights.get("frontage", 0.0)) * float(split_factor)
	var screen_component: float = max(screen_need, strongpoint_need) * float(weights.get("screenStrongpoint", 0.0)) * float(split_factor)
	var reserve_component: float = reserve_need * float(weights.get("reserve", 0.0)) * float(split_factor)

	var cohesion_penalty := (float(depth) / 3.0) * float(weights.get("cohesionPenalty", 0.0))
	var over_split_penalty: float = max(0.0, float(child_count - 3) / 2.0) * float(weights.get("overSplitPenalty", 0.0))
	var isolation_risk: float = clamp(float(context.get("isolationRisk", 0.25)) + float(sibling_count - 1) * 0.08, 0.0, 1.0)
	var isolation_penalty: float = isolation_risk * float(weights.get("isolationPenalty", 0.0))

	var score: float = frontage_component + screen_component + reserve_component
	score -= cohesion_penalty + over_split_penalty + isolation_penalty

	return {
		"formationSplitScore": score,
		"components": {
			"frontageCoverage": frontage_component,
			"screenStrongpoint": screen_component,
			"reservePreservation": reserve_component,
			"cohesionPenalty": -cohesion_penalty,
			"overSplittingPenalty": -over_split_penalty,
			"isolationPenalty": -isolation_penalty
		},
		"signals": {
			"childCount": child_count,
			"deployableChildCount": deployable_child_count,
			"depth": depth,
			"isolationRisk": isolation_risk
		}
	}

static func _decompose_node(node: Variant, parent_id: String, depth: int, state: Dictionary) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return

	var formation := node as Dictionary
	if formation.is_empty():
		return

	var unit_id := String(formation.get("id", "")).strip_edges()
	if unit_id.is_empty():
		return

	var can_split := bool(formation.get("canSplit", true))
	var min_deploy_size := String(state["minDeploySize"])
	var child_count := _valid_child_count(formation)
	var has_children := child_count > 0
	var has_legal_children := _deployable_child_count(formation, min_deploy_size) > 0
	var decision := {
		"canSplit": can_split,
		"hasChildren": has_children,
		"hasLegalChildren": has_legal_children,
		"minDeploySize": min_deploy_size
	}

	var score_result := formation_split_score(formation, {
		"weights": state["weights"],
		"context": state["context"],
		"depth": depth,
		"siblingCount": child_count,
		"minDeploySize": min_deploy_size
	})
	var split_score := float(score_result.get("formationSplitScore", 0.0))
	var should_split := can_split and has_children and has_legal_children and split_score > 0.0

	var action := "deploy_as_element"
	if should_split:
		action = "split"

	var audit_entry := {
		"formationId": unit_id,
		"formationName": String(formation.get("display_name", unit_id)),
		"depth": depth,
		"action": action,
		"decision": decision,
		"score": score_result,
		"reason": _reason_string(action, score_result, decision)
	}
	(state["audit"] as Array).append(audit_entry)

	if should_split:
		for child_variant in formation.get("children", []):
			if typeof(child_variant) != TYPE_DICTIONARY:
				continue
			var child := child_variant as Dictionary
			if not _meets_min_deploy_size(child, min_deploy_size):
				(state["audit"] as Array).append({
					"formationId": String(child.get("id", "")),
					"action": "blocked_child",
					"reason": "child below minDeploySize",
					"decision": {"minDeploySize": min_deploy_size}
				})
				continue
			_decompose_node(child, unit_id, depth + 1, state)
		return

	_append_element(formation, parent_id, state)

static func _append_element(formation: Dictionary, parent_id: String, state: Dictionary) -> void:
	var unit_id := String(formation.get("id", "")).strip_edges()
	var role := _formation_role(formation)
	var size := _normalized_size(formation.get("size", "company"))
	var hex_id := String(formation.get("hexId", state.get("hexId", ""))).strip_edges()
	var support_count_by_hex := state["supportCountByHex"] as Dictionary
	var is_support := _is_support_role(role)

	if is_support and not hex_id.is_empty():
		var support_count := int(support_count_by_hex.get(hex_id, 0))
		if support_count >= int(state.get("supportCapacityPerHex", 3)):
			(state["audit"] as Array).append({
				"formationId": unit_id,
				"action": "blocked_support_capacity",
				"reason": "support capacity max reached for hex",
				"hexId": hex_id,
				"supportCount": support_count
			})
			return
		support_count_by_hex[hex_id] = support_count + 1

	(state["elements"] as Array).append({
		"id": unit_id,
		"playerIndex": int(state.get("playerIndex", -1)),
		"name": String(formation.get("display_name", unit_id)),
		"role": role,
		"size": size,
		"formationId": parent_id,
		"hexId": hex_id,
		"prpCost": _prp_cost(role, size),
		"isSupport": is_support,
		"supportCapacityCost": 1 if is_support else 0,
		"status": String(formation.get("status", "alive")).to_lower()
	})

static func _prp_cost(role: String, size: String) -> int:
	if _is_support_role(role):
		return 0
	return int(COMBAT_PRP_COST_BY_SIZE.get(size, 0))

static func _meets_min_deploy_size(formation: Dictionary, min_deploy_size: String) -> bool:
	var size := _normalized_size(formation.get("size", ""))
	if size.is_empty():
		return false
	return _size_rank(size) >= _size_rank(min_deploy_size)

static func _size_rank(size: String) -> int:
	return int(SIZE_RANKS.get(_normalized_size(size), -1))

static func _normalized_size(size: Variant) -> String:
	return String(size).strip_edges().to_lower()

static func _normalized_role(role: Variant) -> String:
	return String(role).strip_edges().to_lower().replace("_", "")

static func _canonical_role(role: Variant) -> String:
	var normalized := _normalized_role(role)
	if normalized.contains("antitank"):
		return "antiTankSupport"
	if normalized.contains("airdefense"):
		return "airDefense"
	if normalized.contains("howitzer") or normalized.contains("artillery"):
		return "artillerySupport"
	if normalized.contains("weapon") or normalized.contains("machinegun") or normalized.contains("mortar") or normalized == "cannon":
		return "weapons"
	if normalized == "pionier":
		return "weapons"
	return String(ROLE_CANONICAL_MAP.get(normalized, "infantry"))

static func _formation_role(formation: Dictionary) -> String:
	return _canonical_role(formation.get("role", "infantry"))

static func _is_support_role(role: String) -> bool:
	return not _is_combat_role(role)

static func _is_combat_role(role: String) -> bool:
	return role in ["infantry", "armor", "mobility"]

static func _valid_child_count(formation: Dictionary) -> int:
	var count := 0
	for child_variant in formation.get("children", []):
		if typeof(child_variant) == TYPE_DICTIONARY:
			count += 1
	return count

static func _deployable_child_count(formation: Dictionary, min_deploy_size: String) -> int:
	var count := 0
	for child_variant in formation.get("children", []):
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var child := child_variant as Dictionary
		if _meets_min_deploy_size(child, min_deploy_size):
			count += 1
	return count

static func _reason_string(action: String, score_result: Dictionary, decision: Dictionary) -> String:
	var score: float = snapped(float(score_result.get("formationSplitScore", 0.0)), 0.01)
	if action == "split":
		return "split selected: formationSplitScore=%s (canSplit=%s, legalChildren=%s)" % [
			str(score),
			str(decision.get("canSplit", false)),
			str(decision.get("hasLegalChildren", false))
		]
	return "kept intact: formationSplitScore=%s (canSplit=%s, legalChildren=%s)" % [
		str(score),
		str(decision.get("canSplit", false)),
		str(decision.get("hasLegalChildren", false))
	]

static func _support_capacity_violations(support_count_by_hex: Dictionary, support_capacity_per_hex: int) -> Array[Dictionary]:
	var violations: Array[Dictionary] = []
	for hex_id in support_count_by_hex.keys():
		var used := int(support_count_by_hex[hex_id])
		if used > support_capacity_per_hex:
			violations.append({
				"hexId": String(hex_id),
				"used": used,
				"capacity": support_capacity_per_hex
			})
	return violations

static func _illegal_size_splits(audit: Array) -> Array[Dictionary]:
	var illegal: Array[Dictionary] = []
	for entry_variant in audit:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		if String(entry.get("action", "")) != "blocked_child":
			continue
		illegal.append(entry)
	return illegal
