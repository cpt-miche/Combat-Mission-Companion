extends RefCounted
class_name OperationalEvaluator

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
	}
}

static func evaluate(input: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var cfg := _merge_dict(DEFAULT_WEIGHTS, overrides)
	var operation_id := String(input.get("operationId", ""))
	var turn_index := int(input.get("turnIndex", 0))

	var threat_assessments := _evaluate_threats(input.get("threats", []), cfg)
	var breakthrough_pipeline := _evaluate_breakthrough_pipeline(input.get("breakthroughs", []), cfg)
	var breakthrough_assessments: Array[Dictionary] = breakthrough_pipeline.get("breakthroughHexes", [])
	var sector_assessments := _evaluate_sectors(input.get("sectors", []), cfg)
	var reserve_requests := _evaluate_reserve_requests(input.get("reserveRequests", []), cfg)
	reserve_requests.append_array(breakthrough_pipeline.get("reserveNeeds", []))
	var reinforcement_requests := _evaluate_reinforcement_requests(input.get("reinforcementRequests", []), cfg)
	reinforcement_requests.append_array(breakthrough_pipeline.get("reinforcementRequests", []))
	var response_intents := _evaluate_response_intents(input.get("responseIntents", []), cfg)
	var warnings: Array[String] = breakthrough_pipeline.get("warnings", [])

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
	assessment["warnings"] = warnings
	return assessment

static func _evaluate_threats(threats: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("threat", {})
	var assessments: Array[Dictionary] = []
	for item in threats:
		var threat: Dictionary = item
		var strength := clamp(float(threat.get("enemyStrength", 0.0)), 0.0, 1.0)
		var proximity := clamp(float(threat.get("proximity", 0.0)), 0.0, 1.0)
		var momentum := clamp(float(threat.get("momentum", 0.0)), 0.0, 1.0)
		var score := (
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
		var opportunity := clamp(float(breakthrough.get("opportunity", 0.0)), 0.0, 1.0)
		var readiness := clamp(float(breakthrough.get("readiness", 0.0)), 0.0, 1.0)
		var terrain := clamp(float(breakthrough.get("terrainFit", 0.0)), 0.0, 1.0)
		var score := (
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
	var reserve_threshold := clamp(float(thresholds.get("reserveNeed", 0.55)), 0.0, 1.0)
	var reinforcement_threshold := clamp(float(thresholds.get("reinforcementRequest", 0.75)), 0.0, 1.0)
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
		var prior_frontline_size := max(previous_hexes.size(), 1)
		var penetration_factor := clamp(float(penetration_count) / float(prior_frontline_size), 0.0, 1.0)
		var objective_distance := max(float(breakthrough.get("playerDistanceToObjective", 99.0)), 0.0)
		var objective_proximity := clamp(1.0 - objective_distance / max(float(breakthrough.get("objectiveThreatRange", 6.0)), 1.0), 0.0, 1.0)
		var road_access := clamp(max(
			float(breakthrough.get("roadAccess", 0.0)),
			float(breakthrough.get("highwayAccess", 0.0))
		), 0.0, 1.0)
		var sector_gap := clamp(float(breakthrough.get("sectorGapExposure", breakthrough.get("sectorGap", 0.0))), 0.0, 1.0)
		var momentum := clamp(float(breakthrough.get("momentum", 0.0)), 0.0, 1.0)
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
			var requested_strength := clamp(severity * float(breakthrough.get("reserveStrengthScale", 1.0)), 0.1, 1.0)
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
			var reinf_strength := clamp(severity * float(breakthrough.get("reinforcementStrengthScale", 1.25)), 0.1, 1.25)
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
	var assessments: Array[Dictionary] = []
	for item in sectors:
		var sector: Dictionary = item
		var pressure := clamp(float(sector.get("pressure", 0.0)), 0.0, 1.0)
		var readiness := clamp(float(sector.get("readiness", 0.0)), 0.0, 1.0)
		var supply := clamp(float(sector.get("supply", 0.0)), 0.0, 1.0)
		var score := (
			pressure * float(weights.get("pressure", 0.0))
			+ readiness * float(weights.get("readiness", 0.0))
			+ supply * float(weights.get("supply", 0.0))
		)
		var reasons: Array[String] = [
			"pressure=%.3f" % pressure,
			"readiness=%.3f" % readiness,
			"supply=%.3f" % supply
		]
		assessments.append(OperationalTypes.make_sector_assessment(
			String(sector.get("id", "")),
			score,
			score,
			reasons,
			sector
		))
	return assessments

static func _evaluate_reserve_requests(requests: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("reserveRequest", {})
	var assessments: Array[Dictionary] = []
	for item in requests:
		var request: Dictionary = item
		var urgency := clamp(float(request.get("urgency", 0.0)), 0.0, 1.0)
		var deficit := clamp(float(request.get("deficit", 0.0)), 0.0, 1.0)
		var score := (
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

static func _evaluate_reinforcement_requests(requests: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("reinforcementRequest", {})
	var assessments: Array[Dictionary] = []
	for item in requests:
		var request: Dictionary = item
		var urgency := clamp(float(request.get("urgency", 0.0)), 0.0, 1.0)
		var deficit := clamp(float(request.get("deficit", 0.0)), 0.0, 1.0)
		var score := (
			urgency * float(weights.get("urgency", 0.0))
			+ deficit * float(weights.get("deficit", 0.0))
		)
		var reasons: Array[String] = [
			"urgency=%.3f" % urgency,
			"deficit=%.3f" % deficit
		]
		assessments.append(OperationalTypes.make_reinforcement_request(
			String(request.get("id", "")),
			String(request.get("sectorId", "")),
			urgency,
			score,
			reasons,
			float(request.get("requestedStrength", 0.0)),
			request
		))
	return assessments

static func _evaluate_response_intents(intents: Array, cfg: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = cfg.get("responseIntent", {})
	var assessments: Array[Dictionary] = []
	for item in intents:
		var intent: Dictionary = item
		var urgency := clamp(float(intent.get("urgency", 0.0)), 0.0, 1.0)
		var feasibility := clamp(float(intent.get("feasibility", 0.0)), 0.0, 1.0)
		var score := (
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
