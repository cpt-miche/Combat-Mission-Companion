class_name OperationalTypes
extends RefCounted

# Dictionary contract helpers for Operational AI evaluation.

static func make_operational_evaluator_input(
	operation_id: String,
	turn_index: int,
	threats: Array[Dictionary],
	breakthroughs: Array[Dictionary],
	sectors: Array[Dictionary],
	reserve_requests: Array[Dictionary],
	reinforcement_requests: Array[Dictionary],
	response_intents: Array[Dictionary],
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"operationId": operation_id,
		"turnIndex": turn_index,
		"threats": threats.duplicate(true),
		"breakthroughs": breakthroughs.duplicate(true),
		"sectors": sectors.duplicate(true),
		"reserveRequests": reserve_requests.duplicate(true),
		"reinforcementRequests": reinforcement_requests.duplicate(true),
		"responseIntents": response_intents.duplicate(true),
		"metadata": metadata.duplicate(true)
	}

static func make_operational_assessment(
	operation_id: String,
	turn_index: int,
	threat_assessments: Array[Dictionary],
	breakthrough_assessments: Array[Dictionary],
	sector_assessments: Array[Dictionary],
	reserve_requests: Array[Dictionary],
	reinforcement_requests: Array[Dictionary],
	response_intents: Array[Dictionary],
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"operationId": operation_id,
		"turnIndex": turn_index,
		"threatAssessments": threat_assessments.duplicate(true),
		"breakthroughAssessments": breakthrough_assessments.duplicate(true),
		"sectorAssessments": sector_assessments.duplicate(true),
		"reserveRequests": reserve_requests.duplicate(true),
		"reinforcementRequests": reinforcement_requests.duplicate(true),
		"responseIntents": response_intents.duplicate(true),
		"metadata": metadata.duplicate(true)
	}

static func make_threat_assessment(
	threat_id: String,
	sector_id: String,
	urgency: float,
	score: float,
	reasons: Array[String],
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": threat_id,
		"sectorId": sector_id,
		"urgency": urgency,
		"score": score,
		"reasons": reasons.duplicate(),
		"details": details.duplicate(true)
	}

static func make_breakthrough_assessment(
	breakthrough_id: String,
	sector_id: String,
	urgency: float,
	score: float,
	reasons: Array[String],
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": breakthrough_id,
		"sectorId": sector_id,
		"urgency": urgency,
		"score": score,
		"reasons": reasons.duplicate(),
		"details": details.duplicate(true)
	}

static func make_sector_assessment(
	sector_id: String,
	urgency: float,
	score: float,
	reasons: Array[String],
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": sector_id,
		"urgency": urgency,
		"score": score,
		"reasons": reasons.duplicate(),
		"details": details.duplicate(true)
	}

static func make_reserve_request(
	request_id: String,
	sector_id: String,
	urgency: float,
	score: float,
	reasons: Array[String],
	requested_strength: float,
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": request_id,
		"sectorId": sector_id,
		"urgency": urgency,
		"score": score,
		"reasons": reasons.duplicate(),
		"requestedStrength": requested_strength,
		"details": details.duplicate(true)
	}

static func make_reinforcement_request(
	request_id: String,
	sector_id: String,
	urgency: float,
	score: float,
	reasons: Array[String],
	requested_strength: float,
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": request_id,
		"sectorId": sector_id,
		"urgency": urgency,
		"score": score,
		"reasons": reasons.duplicate(),
		"requestedStrength": requested_strength,
		"details": details.duplicate(true)
	}

static func make_response_intent(
	intent_id: String,
	sector_id: String,
	urgency: float,
	score: float,
	reasons: Array[String],
	action: String,
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": intent_id,
		"sectorId": sector_id,
		"urgency": urgency,
		"score": score,
		"reasons": reasons.duplicate(),
		"action": action,
		"details": details.duplicate(true)
	}
