extends RefCounted
class_name OperationalEvaluator

const OperationalScoringModel = preload("res://scripts/systems/operational_ai/OperationalScoringModel.gd")

const DEFAULT_WEIGHTS := {
	"threat": {
		"enemyStrength": 0.45,
		"proximity": 0.35,
		"momentum": 0.20
	},
	"breakthrough": {
		"opportunity": 0.45,
		"readiness": 0.35,
		"terrain": 0.20
	},
	"sector": {
		"pressure": 0.40,
		"readiness": 0.35,
		"supply": 0.25
	},
	"reserveRequest": {
		"urgency": 0.65,
		"deficit": 0.35
	},
	"reinforcementRequest": {
		"urgency": 0.60,
		"deficit": 0.40
	},
	"responseIntent": {
		"urgency": 0.55,
		"feasibility": 0.45
	},
	"breakthroughSeverity": {
		"penetration": 0.30,
		"objectiveProximity": 0.25,
		"roadAccess": 0.20,
		"sectorGap": 0.15,
		"momentum": 0.10
	},
	"breakthroughThresholds": {
		"reserveNeed": 0.55,
		"reinforcementRequest": 0.75
	},
	"quietSectorThresholds": {
		"maxPressure": 0.35,
		"maxObjectiveCriticality": 0.45,
		"minDefensibility": 0.55,
		"maxRecentEnemyAdvance": 0.10,
		"minSupport": 0.50
	},
	"donorRanking": {
		"mobility": 0.65,
		"routeEfficiency": 0.35,
		"defaultDefenseRetention": 0.65
	},
	"opportunityThresholds": {
		"counterattack": 0.72,
		"attack": 0.67,
		"moveReserve": 0.62,
		"reinforce": 0.58,
		"delay": 0.48,
		"withdraw": 0.68
	}
}

static func evaluate(input: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var posture := String(input.get("posture", overrides.get("posture", "balanced")))
	var cfg := _merge_dict(DEFAULT_WEIGHTS, overrides)
	cfg.erase("posture")
	cfg = OperationalScoringModel.weights_for_posture(posture, cfg)
	var operation_id := String(input.get("operationId", ""))
	var turn_index := int(input.get("turnIndex", 0))

	var threat_assessments := _evaluate_threats(input.get("threats", []), cfg)
	var breakthrough_pipeline := _evaluate_breakthrough_pipeline(input.get("breakthroughs", []), cfg)
	var breakthrough_assessments: Array[Dictionary] = breakthrough_pipeline.get("breakthroughHexes", [])
	var sector_assessments := _evaluate_sectors(input.get("sectors", []), cfg)
	var reserve_requests := _evaluate_reserve_requests(input.get("reserveRequests", []), cfg)
	reserve_requests.append_array(breakthrough_pipeline.get("reserveNeeds", []))
	var quiet_sector_index := _build_quiet_sector_index(sector_assessments)
	var reinforcement_pipeline := _evaluate_reinforcement_requests(input.get("reinforcementRequests", []), cfg, quiet_sector_index)
	var reinforcement_requests: Array[Dictionary] = reinforcement_pipeline.get("assessments", [])
	reinforcement_requests.append_array(breakthrough_pipeline.get("reinforcementRequests", []))
	var response_intents := _evaluate_response_intents(input.get("responseIntents", []), cfg)
	var opportunity_pipeline := _evaluate_enemy_adjacent_opportunities(input.get("enemyAdjacentHexes", []), cfg)
	var recommended_intents := _derive_recommended_intents(
		opportunity_pipeline.get("attackOpportunities", []),
		opportunity_pipeline.get("counterattackOpportunities", []),
		sector_assessments,
		breakthrough_pipeline.get("breakthroughHexes", []),
		cfg
	)
	var warnings: Array[String] = breakthrough_pipeline.get("warnings", [])
	warnings.append_array(reinforcement_pipeline.get("warnings", []))
	warnings.append_array(_evaluate_structural_warnings(
		input,
		sector_assessments,
		opportunity_pipeline.get("counterattackOpportunities", []),
		cfg
	))

	var assessment := OperationalTypes.make_operational_assessment(
		operation_id,
		turn_index,
		_sort_scored(threat_assessments),
		_sort_scored(breakthrough_assessments),
		_sort_scored(sector_assessments),
		_sort_scored(reserve_requests),
		_sort_scored(reinforcement_requests),
		_sort_scored(response_intents),
		{"deterministic": true}
	)
	assessment["breakthroughHexes"] = _sort_scored(breakthrough_assessments)
	assessment["reserveNeeds"] = _sort_scored(breakthrough_pipeline.get("reserveNeeds", []))
	assessment["attackOpportunities"] = _sort_scored(opportunity_pipeline.get("attackOpportunities", []))
	assessment["counterattackOpportunities"] = _sort_scored(opportunity_pipeline.get("counterattackOpportunities", []))
	assessment["recommendedIntents"] = _sort_scored(recommended_intents)
	assessment["warnings"] = _dedupe_sorted_strings(warnings)
	assessment["posture"] = _normalize_posture(posture)
	return assessment

static func _evaluate_enemy_adjacent_opportunities(candidate_hexes: Array, cfg: Dictionary) -> Dictionary:
	var attack_opportunities: Array[Dictionary] = []
	var counterattack_opportunities: Array[Dictionary] = []
	for index in candidate_hexes.size():
		var candidate: Dictionary = candidate_hexes[index]
		var normalized := _normalize_candidate_hex(candidate)
		var attack_score := OperationalScoringModel.score_attack_opportunity(normalized, cfg)
		var counterattack_score := OperationalScoringModel.score_counterattack_opportunity(normalized, cfg)
		var candidate_id := String(candidate.get("id", candidate.get("hexId", "enemy_adjacent_%d" % index)))
		var sector_id := String(candidate.get("sectorId", ""))
		var attack_urgency := _score_to_confidence(float(attack_score.get("score", 0.0)), cfg)
		var counterattack_urgency := _score_to_confidence(float(counterattack_score.get("score", 0.0)), cfg)
		var attack_details := candidate.duplicate(true)
		attack_details["normalizedFactors"] = normalized
		attack_details["rawScore"] = float(attack_score.get("rawScore", 0.0))
		attack_details["confidence"] = attack_urgency
		var counterattack_details := candidate.duplicate(true)
		counterattack_details["normalizedFactors"] = normalized
		counterattack_details["rawScore"] = float(counterattack_score.get("rawScore", 0.0))
		counterattack_details["confidence"] = counterattack_urgency
		attack_opportunities.append(OperationalTypes.make_breakthrough_assessment(
			"attack_%s" % candidate_id,
			sector_id,
			attack_urgency,
			attack_urgency,
			attack_score.get("reasons", []),
			attack_details
		))
		counterattack_opportunities.append(OperationalTypes.make_breakthrough_assessment(
			"counterattack_%s" % candidate_id,
			sector_id,
			counterattack_urgency,
			counterattack_urgency,
			counterattack_score.get("reasons", []),
			counterattack_details
		))
	return {
		"attackOpportunities": _sort_scored(attack_opportunities),
		"counterattackOpportunities": _sort_scored(counterattack_opportunities)
	}

static func _normalize_candidate_hex(candidate: Dictionary) -> Dictionary:
	return {
		"objectiveValue": clamp(float(candidate.get("objectiveValue", candidate.get("objective", 0.0))), 0.0, 1.0),
		"enemyWeaknessEstimate": clamp(float(candidate.get("enemyWeaknessEstimate", candidate.get("enemyWeakness", 0.0))), 0.0, 1.0),
		"localFriendlyPower": clamp(float(candidate.get("localFriendlyPower", candidate.get("friendlyPower", 0.0))), 0.0, 1.0),
		"artillerySupport": clamp(float(candidate.get("artillerySupport", 0.0)), 0.0, 1.0),
		"reconSupport": clamp(float(candidate.get("reconSupport", 0.0)), 0.0, 1.0),
		"terrainSuitability": clamp(float(candidate.get("terrainSuitability", candidate.get("terrainFit", 0.0))), 0.0, 1.0),
		"defensiveCoherenceRisk": clamp(float(candidate.get("defensiveCoherenceRisk", candidate.get("coherenceRisk", 0.0))), 0.0, 1.0),
		"overextensionRisk": clamp(float(candidate.get("overextensionRisk", 0.0)), 0.0, 1.0)
	}

static func _score_to_confidence(score: float, cfg: Dictionary = {}) -> float:
	var score_range: Dictionary = cfg.get("shared", {}).get("scoreRange", {})
	var min_score := float(score_range.get("min", -4.0))
	var max_score := float(score_range.get("max", 4.0))
	if max_score <= min_score:
		return 0.0
	return clamp((score - min_score) / (max_score - min_score), 0.0, 1.0)

static func _derive_recommended_intents(
	attack_opportunities: Array[Dictionary],
	counterattack_opportunities: Array[Dictionary],
	sector_assessments: Array[Dictionary],
	breakthrough_hexes: Array[Dictionary],
	cfg: Dictionary
) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var thresholds: Dictionary = cfg.get("opportunityThresholds", {})
	for opportunity in counterattack_opportunities:
		var confidence: float = clamp(float(opportunity.get("urgency", 0.0)), 0.0, 1.0)
		if confidence < float(thresholds.get("counterattack", 0.72)):
			continue
		intents.append(_make_advisory_intent(opportunity, "counterattack", confidence, "high_counterattack_confidence"))
	for opportunity in attack_opportunities:
		var confidence: float = clamp(float(opportunity.get("urgency", 0.0)), 0.0, 1.0)
		if confidence >= float(thresholds.get("attack", 0.67)):
			intents.append(_make_advisory_intent(opportunity, "moveReserve", confidence, "high_attack_confidence"))
			intents.append(_make_advisory_intent(opportunity, "shiftArtillerySupport", confidence, "high_attack_confidence"))
		elif confidence >= float(thresholds.get("moveReserve", 0.62)):
			intents.append(_make_advisory_intent(opportunity, "requestRecon", confidence, "moderate_attack_confidence"))
	for assessment in sector_assessments:
		var sector_id := String(assessment.get("sectorId", assessment.get("id", "")))
		var urgency: float = clamp(float(assessment.get("urgency", assessment.get("score", 0.0))), 0.0, 1.0)
		var details: Dictionary = assessment.get("details", {})
		var quiet := bool(details.get("quietSector", false))
		if quiet and urgency <= float(thresholds.get("delay", 0.48)):
			intents.append(OperationalTypes.make_response_intent(
				"pull_quiet_%s" % sector_id,
				sector_id,
				0.55,
				0.55,
				["quiet_sector_reallocation_candidate=true"],
				"pullFromQuietSector",
				{"source": "sectorAssessment", "quietSector": true}
			))
		if urgency >= float(thresholds.get("reinforce", 0.58)):
			intents.append(OperationalTypes.make_response_intent(
				"reinforce_%s" % sector_id,
				sector_id,
				urgency,
				urgency,
				["sector_pressure_requires_reinforcement=true"],
				"reinforce",
				{"source": "sectorAssessment"}
			))
		elif urgency >= float(thresholds.get("delay", 0.48)):
			intents.append(OperationalTypes.make_response_intent(
				"delay_%s" % sector_id,
				sector_id,
				urgency,
				urgency,
				["sector_pressure_favors_delay=true"],
				"delay",
				{"source": "sectorAssessment"}
			))
		else:
			intents.append(OperationalTypes.make_response_intent(
				"hold_%s" % sector_id,
				sector_id,
				max(0.35, 1.0 - urgency),
				max(0.35, 1.0 - urgency),
				["sector_stability_supports_hold=true"],
				"hold",
				{"source": "sectorAssessment"}
			))
	for breakthrough in breakthrough_hexes:
		var severity: float = clamp(float(breakthrough.get("urgency", breakthrough.get("score", 0.0))), 0.0, 1.0)
		if severity < float(thresholds.get("withdraw", 0.68)):
			continue
		intents.append(OperationalTypes.make_response_intent(
			"withdraw_%s" % String(breakthrough.get("id", "")),
			String(breakthrough.get("sectorId", "")),
			severity,
			severity,
			["breakthrough_severity_exceeds_withdraw_threshold=true"],
			"withdraw",
			{"source": "breakthroughHexes"}
		))
	return _dedupe_intents(_sort_scored(intents))

static func _make_advisory_intent(opportunity: Dictionary, action: String, confidence: float, reason: String) -> Dictionary:
	return OperationalTypes.make_response_intent(
		"%s_%s" % [action, String(opportunity.get("id", ""))],
		String(opportunity.get("sectorId", "")),
		confidence,
		confidence,
		[reason],
		action,
		{"source": "opportunityAssessment", "opportunityId": String(opportunity.get("id", ""))}
	)

static func _dedupe_intents(intents: Array[Dictionary]) -> Array[Dictionary]:
	var deduped: Array[Dictionary] = []
	var seen := {}
	for intent in intents:
		var sector_id := String(intent.get("sectorId", ""))
		var action := String(intent.get("action", ""))
		var fallback_identity := ""
		if sector_id.is_empty():
			var details: Dictionary = intent.get("details", {})
			fallback_identity = String(details.get("opportunityId", intent.get("id", "")))
		var key := "%s|%s|%s" % [sector_id, action, fallback_identity]
		if seen.has(key):
			continue
		seen[key] = true
		deduped.append(intent)
	return deduped

static func _normalize_posture(posture: String) -> String:
	var trimmed := posture.strip_edges()
	if trimmed.is_empty():
		return "balanced"
	var allowed := {
		"aggressive": true,
		"balanced": true,
		"defensive": true,
		"cautious": true,
		"armorHeavy": true,
		"infantryHeavy": true
	}
	if bool(allowed.get(trimmed, false)):
		return trimmed
	return "balanced"

static func _evaluate_threats(threats: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("threat", {})
	var assessments: Array[Dictionary] = []
	for item in threats:
		var threat: Dictionary = item
		var strength: float = clamp(float(threat.get("enemyStrength", 0.0)), 0.0, 1.0)
		var proximity: float = clamp(float(threat.get("proximity", 0.0)), 0.0, 1.0)
		var momentum: float = clamp(float(threat.get("momentum", 0.0)), 0.0, 1.0)
		var score: float = (
			strength * float(weights.get("enemyStrength", 0.0))
			+ proximity * float(weights.get("proximity", 0.0))
			+ momentum * float(weights.get("momentum", 0.0))
		)
		var reasons: Array[String] = [
			"enemy_strength=%.3f" % strength,
			"proximity=%.3f" % proximity,
			"momentum=%.3f" % momentum
		]
		assessments.append(OperationalTypes.make_threat_assessment(
			String(threat.get("id", "")),
			String(threat.get("sectorId", "")),
			score,
			score,
			reasons,
			threat
		))
	return assessments

static func _evaluate_breakthroughs(breakthroughs: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("breakthrough", {})
	var assessments: Array[Dictionary] = []
	for item in breakthroughs:
		var breakthrough: Dictionary = item
		var opportunity: float = clamp(float(breakthrough.get("opportunity", 0.0)), 0.0, 1.0)
		var readiness: float = clamp(float(breakthrough.get("readiness", 0.0)), 0.0, 1.0)
		var terrain: float = clamp(float(breakthrough.get("terrainFit", 0.0)), 0.0, 1.0)
		var score: float = (
			opportunity * float(weights.get("opportunity", 0.0))
			+ readiness * float(weights.get("readiness", 0.0))
			+ terrain * float(weights.get("terrain", 0.0))
		)
		var reasons: Array[String] = [
			"opportunity=%.3f" % opportunity,
			"readiness=%.3f" % readiness,
			"terrain_fit=%.3f" % terrain
		]
		assessments.append(OperationalTypes.make_breakthrough_assessment(
			String(breakthrough.get("id", "")),
			String(breakthrough.get("sectorId", "")),
			score,
			score,
			reasons,
			breakthrough
		))
	return assessments

static func _evaluate_breakthrough_pipeline(breakthroughs: Array, cfg: Dictionary) -> Dictionary:
	var severity_weights: Dictionary = cfg.get("breakthroughSeverity", {})
	var thresholds: Dictionary = cfg.get("breakthroughThresholds", {})
	var reserve_threshold: float = clamp(float(thresholds.get("reserveNeed", 0.55)), 0.0, 1.0)
	var reinforcement_threshold: float = clamp(float(thresholds.get("reinforcementRequest", 0.75)), 0.0, 1.0)
	var breakthrough_hexes: Array[Dictionary] = []
	var reserve_needs: Array[Dictionary] = []
	var reinforcement_requests: Array[Dictionary] = []
	var warnings: Array[String] = []
	for index in breakthroughs.size():
		var breakthrough: Dictionary = breakthroughs[index]
		var previous_hexes := _string_set(breakthrough.get("previousHexes", []))
		var current_hexes := _string_set(breakthrough.get("currentHexes", []))
		var penetration_count := 0
		for hex_id in current_hexes.keys():
			if not previous_hexes.has(hex_id):
				penetration_count += 1
		var prior_frontline_size: int = max(previous_hexes.size(), 1)
		var penetration_factor: float = clamp(float(penetration_count) / float(prior_frontline_size), 0.0, 1.0)
		var objective_distance: float = max(float(breakthrough.get("playerDistanceToObjective", 99.0)), 0.0)
		var objective_proximity: float = clamp(1.0 - objective_distance / max(float(breakthrough.get("objectiveThreatRange", 6.0)), 1.0), 0.0, 1.0)
		var road_access: float = clamp(max(
			float(breakthrough.get("roadAccess", 0.0)),
			float(breakthrough.get("highwayAccess", 0.0))
		), 0.0, 1.0)
		var sector_gap: float = clamp(float(breakthrough.get("sectorGapExposure", breakthrough.get("sectorGap", 0.0))), 0.0, 1.0)
		var momentum: float = clamp(float(breakthrough.get("momentum", 0.0)), 0.0, 1.0)
		var severity := _score_breakthrough_severity(
			penetration_factor,
			objective_proximity,
			road_access,
			sector_gap,
			momentum,
			severity_weights
		)
		var reasons := _build_breakthrough_reasons(
			penetration_count,
			prior_frontline_size,
			objective_distance,
			objective_proximity,
			road_access,
			sector_gap,
			momentum,
			severity
		)
		var breakthrough_id := String(breakthrough.get("id", "breakthrough_%d" % index))
		var sector_id := String(breakthrough.get("sectorId", ""))
		breakthrough_hexes.append(OperationalTypes.make_breakthrough_assessment(
			breakthrough_id,
			sector_id,
			severity,
			severity,
			reasons,
			breakthrough
		))
		if severity >= reserve_threshold:
			var reserve_id := "%s_reserve_need" % breakthrough_id
			var reserve_reasons := reasons.duplicate()
			reserve_reasons.append("trigger=breakthrough_severity>=%.2f" % reserve_threshold)
			var requested_strength: float = clamp(severity * float(breakthrough.get("reserveStrengthScale", 1.0)), 0.1, 1.0)
			reserve_needs.append(OperationalTypes.make_reserve_request(
				reserve_id,
				sector_id,
				severity,
				severity,
				reserve_reasons,
				requested_strength,
				breakthrough
			))
		if severity >= reinforcement_threshold:
			var reinf_id := "%s_reinforcement_request" % breakthrough_id
			var reinf_reasons := reasons.duplicate()
			reinf_reasons.append("trigger=breakthrough_severity>=%.2f" % reinforcement_threshold)
			var reinf_strength: float = clamp(severity * float(breakthrough.get("reinforcementStrengthScale", 1.25)), 0.1, 1.25)
			reinforcement_requests.append(OperationalTypes.make_reinforcement_request(
				reinf_id,
				sector_id,
				severity,
				severity,
				reinf_reasons,
				reinf_strength,
				breakthrough
			))
		var has_breakthrough := severity > 0.0 and penetration_count > 0
		if has_breakthrough and not _has_reserve_in_window(breakthrough):
			var required_window := int(breakthrough.get("requiredReserveTurns", 2))
			warnings.append(
				"breakthrough=%s sector=%s no_reserve_response_within=%d_turns" % [breakthrough_id, sector_id, required_window]
			)
	breakthrough_hexes = _sort_scored(breakthrough_hexes)
	return {
		"breakthroughHexes": breakthrough_hexes,
		"reserveNeeds": _sort_scored(reserve_needs),
		"reinforcementRequests": _sort_scored(reinforcement_requests),
		"warnings": warnings
	}

static func _score_breakthrough_severity(
	penetration: float,
	objective_proximity: float,
	road_access: float,
	sector_gap: float,
	momentum: float,
	weights: Dictionary
) -> float:
	return clamp(
		penetration * float(weights.get("penetration", 0.30))
		+ objective_proximity * float(weights.get("objectiveProximity", 0.25))
		+ road_access * float(weights.get("roadAccess", 0.20))
		+ sector_gap * float(weights.get("sectorGap", 0.15))
		+ momentum * float(weights.get("momentum", 0.10)),
		0.0,
		1.0
	)

static func _build_breakthrough_reasons(
	penetration_count: int,
	prior_frontline_size: int,
	objective_distance: float,
	objective_proximity: float,
	road_access: float,
	sector_gap: float,
	momentum: float,
	severity: float
) -> Array[String]:
	return [
		"penetration=%d/%d" % [penetration_count, prior_frontline_size],
		"objective_distance=%.2f" % objective_distance,
		"objective_proximity=%.3f" % objective_proximity,
		"road_or_highway_access=%.3f" % road_access,
		"sector_gap_exposure=%.3f" % sector_gap,
		"momentum=%.3f" % momentum,
		"severity=%.3f" % severity
	]

static func _has_reserve_in_window(breakthrough: Dictionary) -> bool:
	var reserve_candidates: Array = breakthrough.get("reserveCandidates", [])
	var required_window := int(breakthrough.get("requiredReserveTurns", 2))
	for item in reserve_candidates:
		var reserve: Dictionary = item
		if bool(reserve.get("available", true)) and int(reserve.get("etaTurns", 999)) <= required_window:
			return true
	if bool(breakthrough.get("reserveAvailable", false)) and int(breakthrough.get("reserveEtaTurns", 999)) <= required_window:
		return true
	return false

static func _string_set(values: Array) -> Dictionary:
	var set := {}
	for value in values:
		set[String(value)] = true
	return set

static func _evaluate_sectors(sectors: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("sector", {})
	var quiet_thresholds: Dictionary = cfg.get("quietSectorThresholds", {})
	var assessments: Array[Dictionary] = []
	for item in sectors:
		var sector: Dictionary = item
		var pressure: float = clamp(float(sector.get("pressure", 0.0)), 0.0, 1.0)
		var readiness: float = clamp(float(sector.get("readiness", 0.0)), 0.0, 1.0)
		var supply: float = clamp(float(sector.get("supply", 0.0)), 0.0, 1.0)
		var objective_criticality: float = clamp(float(sector.get("objectiveCriticality", sector.get("criticality", 0.0))), 0.0, 1.0)
		var defensibility: float = clamp(float(sector.get("defensibility", sector.get("terrainDefensibility", 0.0))), 0.0, 1.0)
		var recent_enemy_advance: float = clamp(float(sector.get("recentEnemyAdvance", 0.0)), 0.0, 1.0)
		var support: float = clamp(max(
			float(sector.get("artillerySupport", 0.0)),
			float(sector.get("reserveSupport", 0.0)),
			float(sector.get("supportCoverage", 0.0))
		), 0.0, 1.0)
		var is_quiet_sector: bool = (
			pressure <= float(quiet_thresholds.get("maxPressure", 0.35))
			and objective_criticality <= float(quiet_thresholds.get("maxObjectiveCriticality", 0.45))
			and defensibility >= float(quiet_thresholds.get("minDefensibility", 0.55))
			and recent_enemy_advance <= float(quiet_thresholds.get("maxRecentEnemyAdvance", 0.10))
			and support >= float(quiet_thresholds.get("minSupport", 0.50))
		)
		var score: float = (
			pressure * float(weights.get("pressure", 0.0))
			+ readiness * float(weights.get("readiness", 0.0))
			+ supply * float(weights.get("supply", 0.0))
		)
		var reasons: Array[String] = [
			"pressure=%.3f" % pressure,
			"readiness=%.3f" % readiness,
			"supply=%.3f" % supply,
			"objective_criticality=%.3f" % objective_criticality,
			"defensibility=%.3f" % defensibility,
			"recent_enemy_advance=%.3f" % recent_enemy_advance,
			"support=%.3f" % support,
			"quiet_sector=%s" % str(is_quiet_sector)
		]
		var details := sector.duplicate(true)
		details["quietSector"] = is_quiet_sector
		details["objectiveCriticality"] = objective_criticality
		details["defensibility"] = defensibility
		details["recentEnemyAdvance"] = recent_enemy_advance
		details["supportCoverage"] = support
		assessments.append(OperationalTypes.make_sector_assessment(
			String(sector.get("id", "")),
			score,
			score,
			reasons,
			details
		))
	return assessments

static func _evaluate_reserve_requests(requests: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("reserveRequest", {})
	var assessments: Array[Dictionary] = []
	for item in requests:
		var request: Dictionary = item
		var urgency: float = clamp(float(request.get("urgency", 0.0)), 0.0, 1.0)
		var deficit: float = clamp(float(request.get("deficit", 0.0)), 0.0, 1.0)
		var score: float = (
			urgency * float(weights.get("urgency", 0.0))
			+ deficit * float(weights.get("deficit", 0.0))
		)
		var reasons: Array[String] = [
			"urgency=%.3f" % urgency,
			"deficit=%.3f" % deficit
		]
		assessments.append(OperationalTypes.make_reserve_request(
			String(request.get("id", "")),
			String(request.get("sectorId", "")),
			urgency,
			score,
			reasons,
			float(request.get("requestedStrength", 0.0)),
			request
		))
	return assessments

static func _evaluate_reinforcement_requests(requests: Array, cfg: Dictionary, quiet_sector_index: Dictionary) -> Dictionary:
	var weights: Dictionary = cfg.get("reinforcementRequest", {})
	var ranking_weights: Dictionary = cfg.get("donorRanking", {})
	var assessments: Array[Dictionary] = []
	var warnings: Array[String] = []
	for item in requests:
		var request: Dictionary = item
		var urgency: float = clamp(float(request.get("urgency", 0.0)), 0.0, 1.0)
		var deficit: float = clamp(float(request.get("deficit", 0.0)), 0.0, 1.0)
		var score: float = (
			urgency * float(weights.get("urgency", 0.0))
			+ deficit * float(weights.get("deficit", 0.0))
		)
		var reasons: Array[String] = [
			"urgency=%.3f" % urgency,
			"deficit=%.3f" % deficit
		]
		var donor_outcome := _evaluate_donor_candidates(request, quiet_sector_index, ranking_weights)
		reasons.append_array(donor_outcome.get("reasons", []))
		var details := request.duplicate(true)
		details["preferredSources"] = donor_outcome.get("preferredSources", [])
		details["donorCandidates"] = donor_outcome.get("donorCandidates", [])
		if not donor_outcome.get("warning", "").is_empty():
			warnings.append(donor_outcome.get("warning", ""))
		assessments.append(OperationalTypes.make_reinforcement_request(
			String(request.get("id", "")),
			String(request.get("sectorId", "")),
			urgency,
			score,
			reasons,
			float(request.get("requestedStrength", 0.0)),
			details
		))
	return {
		"assessments": assessments,
		"warnings": warnings
	}

static func _evaluate_donor_candidates(request: Dictionary, quiet_sector_index: Dictionary, ranking_weights: Dictionary) -> Dictionary:
	var donor_candidates: Array = request.get("donorCandidates", [])
	var legal_ranked: Array[Dictionary] = []
	var evaluated_candidates: Array[Dictionary] = []
	var preferred_sources: Array[String] = []
	var request_id := String(request.get("id", ""))
	var request_sector := String(request.get("sectorId", ""))
	var requested_strength: float = clamp(float(request.get("requestedStrength", 0.0)), 0.0, 1.5)
	var reasons: Array[String] = []
	var retention_default: float = clamp(float(ranking_weights.get("defaultDefenseRetention", 0.65)), 0.0, 1.0)
	for item in donor_candidates:
		var donor: Dictionary = item
		var donor_sector := String(donor.get("sectorId", donor.get("id", "")))
		var pre_transfer_score: float = clamp(float(donor.get("preTransferDefenseScore", donor.get("defenseScore", donor.get("currentDefenseScore", 0.0)))), 0.0, 1.5)
		var transfer_cost: float = max(
			float(donor.get("transferDefenseCost", donor.get("defenseContributionLost", 0.0))),
			requested_strength * (1.0 - retention_default)
		)
		var post_transfer_score: float = clamp(float(donor.get("postTransferDefenseScore", pre_transfer_score - transfer_cost)), 0.0, 1.5)
		var minimum_required: float = clamp(float(donor.get("minimumRequiredDefenseScore", request.get("minimumRequiredDefenseScore", pre_transfer_score * retention_default))), 0.0, 1.5)
		var quiet_sector_gate := bool(quiet_sector_index.get(donor_sector, false))
		var stays_above_threshold: bool = post_transfer_score >= minimum_required
		var legal: bool = quiet_sector_gate and stays_above_threshold
		var mobility: float = clamp(float(donor.get("mobility", donor.get("mobileFactor", 0.0))), 0.0, 1.0)
		var route_length: float = max(float(donor.get("responseRouteLength", donor.get("routeDistance", donor.get("responseDistance", donor.get("travelTurns", 99.0))))), 0.0)
		var route_efficiency: float = clamp(1.0 / (1.0 + route_length), 0.0, 1.0)
		var rank_score: float = (
			mobility * float(ranking_weights.get("mobility", 0.65))
			+ route_efficiency * float(ranking_weights.get("routeEfficiency", 0.35))
		)
		var evaluated := donor.duplicate(true)
		evaluated["postTransferDefenseScore"] = post_transfer_score
		evaluated["minimumRequiredDefenseScore"] = minimum_required
		evaluated["legalForTransfer"] = legal
		evaluated["routeEfficiency"] = route_efficiency
		evaluated["rankScore"] = rank_score
		evaluated_candidates.append(evaluated)
		if legal:
			legal_ranked.append({
				"sectorId": donor_sector,
				"rankScore": rank_score,
				"routeLength": route_length
			})
	legal_ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.get("rankScore", 0.0)), float(b.get("rankScore", 0.0))):
			return float(a.get("rankScore", 0.0)) > float(b.get("rankScore", 0.0))
		if not is_equal_approx(float(a.get("routeLength", 999.0)), float(b.get("routeLength", 999.0))):
			return float(a.get("routeLength", 999.0)) < float(b.get("routeLength", 999.0))
		return String(a.get("sectorId", "")) < String(b.get("sectorId", ""))
	)
	for ranked in legal_ranked:
		preferred_sources.append(String(ranked.get("sectorId", "")))
	preferred_sources = _unique_strings(preferred_sources)
	reasons.append("legal_donor_candidates=%d/%d" % [preferred_sources.size(), donor_candidates.size()])
	var warning := ""
	if donor_candidates.size() > 0 and preferred_sources.is_empty():
		warning = "reinforcement_request=%s sector=%s has_no_legal_donor_source" % [request_id, request_sector]
		reasons.append("blocked_transfer=no_legal_donor_source")
	elif preferred_sources.is_empty():
		reasons.append("blocked_transfer=no_donor_candidates")
	else:
		reasons.append("preferred_sources=%s" % ",".join(preferred_sources))
	return {
		"preferredSources": preferred_sources,
		"donorCandidates": evaluated_candidates,
		"reasons": reasons,
		"warning": warning
	}

static func _build_quiet_sector_index(sector_assessments: Array[Dictionary]) -> Dictionary:
	var quiet_sector_index := {}
	for assessment in sector_assessments:
		var sector_id := String(assessment.get("sectorId", assessment.get("id", "")))
		if sector_id.is_empty():
			continue
		var details: Dictionary = assessment.get("details", {})
		quiet_sector_index[sector_id] = bool(details.get("quietSector", false))
	return quiet_sector_index

static func _unique_strings(items: Array[String]) -> Array[String]:
	var deduped: Array[String] = []
	var seen := {}
	for item in items:
		if seen.has(item):
			continue
		seen[item] = true
		deduped.append(item)
	return deduped

static func _dedupe_sorted_strings(items: Array[String]) -> Array[String]:
	var deduped := _unique_strings(items)
	deduped.sort()
	return deduped

static func _evaluate_structural_warnings(
	input: Dictionary,
	sector_assessments: Array[Dictionary],
	counterattack_opportunities: Array[Dictionary],
	cfg: Dictionary
) -> Array[String]:
	var warnings: Array[String] = []
	var thresholds: Dictionary = cfg.get("opportunityThresholds", {})
	var counterattack_threshold := float(thresholds.get("counterattack", 0.72))
	var sectors: Array = input.get("sectors", [])
	var breakthroughs: Array = input.get("breakthroughs", [])
	for item in sectors:
		var sector: Dictionary = item
		var sector_id := String(sector.get("id", ""))
		var objective_criticality: float = clamp(float(sector.get("objectiveCriticality", sector.get("criticality", 0.0))), 0.0, 1.0)
		var pressure: float = clamp(float(sector.get("pressure", 0.0)), 0.0, 1.0)
		var readiness: float = clamp(float(sector.get("readiness", 0.0)), 0.0, 1.0)
		var defensibility: float = clamp(float(sector.get("defensibility", sector.get("terrainDefensibility", 0.0))), 0.0, 1.0)
		var artillery_coverage: float = clamp(max(
			float(sector.get("artilleryCoverage", 0.0)),
			float(sector.get("artillerySupport", 0.0))
		), 0.0, 1.0)
		var recon_support: float = clamp(float(sector.get("reconSupport", sector.get("reconCoverage", 0.0))), 0.0, 1.0)
		var uncertainty: float = clamp(float(sector.get("scoutUncertainty", sector.get("uncertainty", 0.0))), 0.0, 1.0)
		var importance: float = clamp(max(
			float(sector.get("importance", 0.0)),
			objective_criticality
		), 0.0, 1.0)
		var danger: float = clamp(max(
			float(sector.get("danger", 0.0)),
			pressure,
			float(sector.get("enemyPressure", 0.0))
		), 0.0, 1.0)
		if _is_defend_sector(sector) and objective_criticality >= 0.70 and (pressure >= 0.65 or readiness <= 0.35 or defensibility <= 0.35):
			warnings.append("warning=exposed_defend_objective sector=%s" % sector_id)
		if _is_frontline_sector(sector) and _is_understrength_frontline_sector(sector):
			warnings.append("warning=understrength_frontline_sector sector=%s" % sector_id)
		if danger >= 0.70 and artillery_coverage <= 0.10:
			warnings.append("warning=no_artillery_coverage_high_danger_sector sector=%s" % sector_id)
		if importance >= 0.70 and uncertainty >= 0.60 and recon_support <= 0.35:
			warnings.append("warning=poor_recon_high_importance_uncertain_sector sector=%s" % sector_id)
		if _has_coherent_line_gap_path_to_rear(sector):
			warnings.append("warning=coherent_line_gap_path_to_rear sector=%s" % sector_id)
	for item in breakthroughs:
		var breakthrough: Dictionary = item
		if _has_coherent_line_gap_path_to_rear(breakthrough):
			warnings.append("warning=coherent_line_gap_path_to_rear sector=%s" % String(breakthrough.get("sectorId", breakthrough.get("id", ""))))
	if _has_reserve_clumping_in_input(input):
		warnings.append("warning=reserve_clumping")
	for opportunity in counterattack_opportunities:
		var confidence: float = clamp(float(opportunity.get("urgency", opportunity.get("score", 0.0))), 0.0, 1.0)
		if confidence < counterattack_threshold:
			continue
		if _counterattack_exposes_defend_objective(opportunity):
			warnings.append("warning=counterattack_exposes_defend_objective opportunity=%s" % String(opportunity.get("id", "")))
	return _dedupe_sorted_strings(warnings)

static func _is_defend_sector(sector: Dictionary) -> bool:
	var objective_mode := String(sector.get("objectiveMode", sector.get("objectiveType", sector.get("mission", "")))).to_lower()
	return objective_mode.find("defend") >= 0 or bool(sector.get("defendObjective", false))

static func _is_frontline_sector(sector: Dictionary) -> bool:
	if bool(sector.get("frontline", false)) or bool(sector.get("isFrontline", false)) or bool(sector.get("frontlineSector", false)):
		return true
	return String(sector.get("type", sector.get("sectorType", ""))).to_lower() == "frontline"

static func _is_understrength_frontline_sector(sector: Dictionary) -> bool:
	var ratio := float(sector.get("strengthRatio", sector.get("friendlyToEnemyRatio", sector.get("combatRatio", -1.0))))
	if ratio >= 0.0:
		ratio = clamp(ratio, 0.0, 3.0)
	if ratio >= 0.0 and ratio < 0.75:
		return true
	var friendly: float = max(float(sector.get("friendlyStrength", sector.get("friendlyCombatPower", 0.0))), 0.0)
	var enemy: float = max(float(sector.get("enemyStrength", sector.get("enemyCombatPower", 0.0))), 0.0)
	return enemy > 0.0 and friendly < enemy * 0.85

static func _has_coherent_line_gap_path_to_rear(item: Dictionary) -> bool:
	if bool(item.get("coherentLineGapPathToRear", false)):
		return true
	var coherence_risk: float = clamp(float(item.get("coherenceRisk", item.get("defensiveCoherenceRisk", 0.0))), 0.0, 1.0)
	var rear_path_risk: float = clamp(float(item.get("rearPathRisk", item.get("pathToRearRisk", 0.0))), 0.0, 1.0)
	return coherence_risk >= 0.70 and rear_path_risk >= 0.70

static func _has_reserve_clumping_in_input(input: Dictionary) -> bool:
	var reserve_positions: Array[Dictionary] = []
	for collection_key in ["reserveUnits", "reservePositions"]:
		var collection: Array = input.get(collection_key, [])
		for item in collection:
			var entry: Dictionary = item
			if not _is_reserve_combat_entry(entry):
				continue
			var axial := _extract_axial(entry)
			if axial.x == 9999:
				continue
			reserve_positions.append({
				"id": String(entry.get("id", entry.get("unitId", ""))),
				"q": axial.x,
				"r": axial.y
			})
	var metadata: Dictionary = input.get("metadata", {})
	var metadata_positions: Array = metadata.get("reservePositions", [])
	for item in metadata_positions:
		var entry: Dictionary = item
		if not _is_reserve_combat_entry(entry):
			continue
		var axial := _extract_axial(entry)
		if axial.x == 9999:
			continue
		reserve_positions.append({
			"id": String(entry.get("id", entry.get("unitId", ""))),
			"q": axial.x,
			"r": axial.y
		})
	if reserve_positions.size() <= 1:
		return bool(input.get("reserveClumping", false)) or float(input.get("reserveClumpingScore", 0.0)) >= 0.70
	for i in range(reserve_positions.size()):
		for j in range(i + 1, reserve_positions.size()):
			var a: Dictionary = reserve_positions[i]
			var b: Dictionary = reserve_positions[j]
			if _axial_distance(int(a.get("q", 0)), int(a.get("r", 0)), int(b.get("q", 0)), int(b.get("r", 0))) <= 1:
				return true
	return false

static func _is_reserve_combat_entry(entry: Dictionary) -> bool:
	var role := String(entry.get("role", "")).to_lower()
	if role == "reserve":
		return true
	if bool(entry.get("isReserve", false)) or bool(entry.get("reserve", false)):
		return true
	return false

static func _extract_axial(entry: Dictionary) -> Vector2i:
	if entry.has("q") and entry.has("r"):
		return Vector2i(int(entry.get("q", 0)), int(entry.get("r", 0)))
	if entry.has("x") and entry.has("y"):
		return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	var hex: Dictionary = entry.get("hex", {})
	if hex.has("q") and hex.has("r"):
		return Vector2i(int(hex.get("q", 0)), int(hex.get("r", 0)))
	return Vector2i(9999, 9999)

static func _axial_distance(aq: int, ar: int, bq: int, br: int) -> int:
	return int((abs(aq - bq) + abs(aq + ar - bq - br) + abs(ar - br)) / 2)

static func _counterattack_exposes_defend_objective(opportunity: Dictionary) -> bool:
	var details: Dictionary = opportunity.get("details", {})
	if bool(details.get("exposesDefendObjective", false)):
		return true
	var normalized: Dictionary = details.get("normalizedFactors", {})
	var coherence_risk: float = clamp(float(normalized.get("defensiveCoherenceRisk", details.get("defensiveCoherenceRisk", 0.0))), 0.0, 1.0)
	var overextension: float = clamp(float(normalized.get("overextensionRisk", details.get("overextensionRisk", 0.0))), 0.0, 1.0)
	var objective_value: float = clamp(float(normalized.get("objectiveValue", details.get("objectiveValue", 0.0))), 0.0, 1.0)
	var defend_tag := bool(details.get("defendObjective", false)) or String(details.get("objectiveType", details.get("objectiveMode", ""))).to_lower().find("defend") >= 0
	return coherence_risk >= 0.65 and overextension >= 0.55 and (defend_tag or objective_value >= 0.75)

static func _evaluate_response_intents(intents: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("responseIntent", {})
	var assessments: Array[Dictionary] = []
	for item in intents:
		var intent: Dictionary = item
		var urgency: float = clamp(float(intent.get("urgency", 0.0)), 0.0, 1.0)
		var feasibility: float = clamp(float(intent.get("feasibility", 0.0)), 0.0, 1.0)
		var score: float = (
			urgency * float(weights.get("urgency", 0.0))
			+ feasibility * float(weights.get("feasibility", 0.0))
		)
		var reasons: Array[String] = [
			"urgency=%.3f" % urgency,
			"feasibility=%.3f" % feasibility
		]
		assessments.append(OperationalTypes.make_response_intent(
			String(intent.get("id", "")),
			String(intent.get("sectorId", "")),
			urgency,
			score,
			reasons,
			String(intent.get("action", "hold")),
			intent
		))
	return assessments

static func _sort_scored(items: Array[Dictionary]) -> Array[Dictionary]:
	var ordered := items.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_urgency := float(a.get("urgency", a.get("score", 0.0)))
		var b_urgency := float(b.get("urgency", b.get("score", 0.0)))
		if not is_equal_approx(a_urgency, b_urgency):
			return a_urgency > b_urgency
		var a_score := float(a.get("score", 0.0))
		var b_score := float(b.get("score", 0.0))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return ordered

static func _merge_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in overrides.keys():
		var base_value = merged.get(key)
		var override_value = overrides[key]
		if base_value is Dictionary and override_value is Dictionary:
			merged[key] = _merge_dict(base_value, override_value)
		else:
			merged[key] = override_value
	return merged
