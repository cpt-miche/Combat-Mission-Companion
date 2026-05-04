extends SceneTree

const OperationalEvaluator = preload("res://scripts/systems/operational_ai/OperationalEvaluator.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_evaluator_applies_selected_profile_values()
	_test_difficulty_relative_behavior_shifts()

	if _failures.is_empty():
		print("OperationalEvaluator profile tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)

func _test_evaluator_applies_selected_profile_values() -> void:
	var base := _fixture_input()
	var defensive := base.duplicate(true)
	defensive["doctrine"] = "defensive"
	defensive["difficulty"] = "medium"
	var aggressive := base.duplicate(true)
	aggressive["doctrine"] = "aggressive"
	aggressive["difficulty"] = "medium"
	var defensive_assessment := OperationalEvaluator.evaluate(defensive)
	var aggressive_assessment := OperationalEvaluator.evaluate(aggressive)
	var defensive_attack_reasons := _find_reasons_by_id(defensive_assessment.get("attackOpportunities", []), "attack_candidate_alpha")
	var aggressive_attack_reasons := _find_reasons_by_id(aggressive_assessment.get("attackOpportunities", []), "attack_candidate_alpha")
	_assert_true(defensive_attack_reasons.any(func(reason: String) -> bool: return reason.contains("doctrine_adjusted_component=defensive")), "Defensive doctrine should inject defensive doctrine reason tags")
	_assert_true(aggressive_attack_reasons.any(func(reason: String) -> bool: return reason.contains("doctrine_adjusted_component=aggressive")), "Aggressive doctrine should inject aggressive doctrine reason tags")

func _test_difficulty_relative_behavior_shifts() -> void:
	var base := _fixture_input()
	base["doctrine"] = "balanced"
	var easy_input := base.duplicate(true)
	easy_input["difficulty"] = "easy"
	var medium_input := base.duplicate(true)
	medium_input["difficulty"] = "medium"
	var hard_input := base.duplicate(true)
	hard_input["difficulty"] = "hard"

	var easy_assessment := OperationalEvaluator.evaluate(easy_input)
	var medium_assessment := OperationalEvaluator.evaluate(medium_input)
	var hard_assessment := OperationalEvaluator.evaluate(hard_input)

	var easy_actions := _intent_actions(easy_assessment.get("recommendedIntents", []))
	var medium_actions := _intent_actions(medium_assessment.get("recommendedIntents", []))
	var hard_actions := _intent_actions(hard_assessment.get("recommendedIntents", []))
	_assert_true(not easy_actions.has("reinforce"), "Easy should be less reactive and skip reinforce at threshold-edge sector urgency")
	_assert_true(medium_actions.has("reinforce"), "Medium should reinforce at baseline threshold-edge sector urgency")
	_assert_true(hard_actions.has("reinforce"), "Hard should reinforce at least as often as medium")

	var easy_warnings := easy_assessment.get("warnings", []) as Array
	var medium_warnings := medium_assessment.get("warnings", []) as Array
	var hard_warnings := hard_assessment.get("warnings", []) as Array
	_assert_equal(medium_warnings, easy_warnings, "Difficulty should not introduce warning nondeterminism for identical inputs")
	_assert_equal(medium_warnings, hard_warnings, "Difficulty should not introduce warning nondeterminism for identical inputs")

func _fixture_input() -> Dictionary:
	return {
		"operationId": "profile_fixture",
		"turnIndex": 1,
		"sectors": [
			{"id": "sector_a", "pressure": 0.56, "readiness": 0.60, "supply": 0.58, "objectiveCriticality": 0.58, "defensibility": 0.50, "recentEnemyAdvance": 0.12, "supportAvailability": 0.48}
		],
		"enemyAdjacentHexes": [
			{"id": "candidate_alpha", "sectorId": "sector_a", "objectiveValue": 0.66, "enemyWeaknessEstimate": 0.62, "localFriendlyPower": 0.61, "artillerySupport": 0.57, "reconSupport": 0.52, "terrainSuitability": 0.55, "defensiveCoherenceRisk": 0.40, "overextensionRisk": 0.45}
		],
		"breakthroughs": [],
		"threats": [],
		"reserveRequests": [],
		"reinforcementRequests": [],
		"responseIntents": []
	}

func _find_reasons_by_id(entries: Array, entry_id: String) -> Array[String]:
	for entry in entries:
		var item: Dictionary = entry
		if String(item.get("id", "")) == entry_id:
			var reasons: Array[String] = []
			for reason in item.get("reasons", []):
				reasons.append(String(reason))
			return reasons
	return []

func _intent_actions(entries: Array) -> Dictionary:
	var idx := {}
	for entry in entries:
		idx[String((entry as Dictionary).get("action", ""))] = true
	return idx

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
