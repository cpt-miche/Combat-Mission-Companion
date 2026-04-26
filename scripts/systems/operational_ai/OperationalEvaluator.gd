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
	}
}

static func evaluate(input: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var cfg := _merge_dict(DEFAULT_WEIGHTS, overrides)
	var operation_id := String(input.get("operationId", ""))
	var turn_index := int(input.get("turnIndex", 0))

	var threat_assessments := _evaluate_threats(input.get("threats", []), cfg)
	var breakthrough_assessments := _evaluate_breakthroughs(input.get("breakthroughs", []), cfg)
	var sector_assessments := _evaluate_sectors(input.get("sectors", []), cfg)
	var reserve_requests := _evaluate_reserve_requests(input.get("reserveRequests", []), cfg)
	var reinforcement_requests := _evaluate_reinforcement_requests(input.get("reinforcementRequests", []), cfg)
	var response_intents := _evaluate_response_intents(input.get("responseIntents", []), cfg)

	return OperationalTypes.make_operational_assessment(
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
