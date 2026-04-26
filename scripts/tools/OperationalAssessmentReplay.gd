extends RefCounted
class_name OperationalAssessmentReplay

const OperationalEvaluator = preload("res://scripts/systems/operational_ai/OperationalEvaluator.gd")
const OperationalMapAnalyzer = preload("res://scripts/systems/operational_ai/OperationalMapAnalyzer.gd")
const OperationalScoringModel = preload("res://scripts/systems/operational_ai/OperationalScoringModel.gd")

const SUPPORTED_FIXTURE_VERSION := 1

static func replay_fixture_file(path: String) -> Dictionary:
	var fixture := _read_json_file(path)
	if fixture.is_empty():
		return {"ok": false, "path": path, "error": "fixture_unreadable"}
	var replay := replay_fixture(fixture)
	replay["path"] = path
	return replay

static func replay_fixture(fixture: Dictionary) -> Dictionary:
	var fixture_id := String(fixture.get("id", ""))
	var failures: Array[String] = []
	var warnings: Array[String] = []
	var outputs := {}

	if int(fixture.get("fixtureVersion", SUPPORTED_FIXTURE_VERSION)) > SUPPORTED_FIXTURE_VERSION:
		warnings.append("fixture_version_newer_than_runner")

	var map_analysis: Dictionary = fixture.get("mapAnalysis", {})
	if not map_analysis.is_empty():
		outputs["mapSectors"] = OperationalMapAnalyzer.analyze(
			map_analysis.get("territoryMap", {}),
			int(map_analysis.get("aiOwner", 1)),
			int(map_analysis.get("playerOwner", 2))
		)

	var op_input: Dictionary = fixture.get("operationalInput", {})
	if not op_input.is_empty():
		outputs["assessment"] = OperationalEvaluator.evaluate(_normalize_operational_input(op_input))

	var scoring_comparison: Dictionary = fixture.get("scoringComparison", {})
	if not scoring_comparison.is_empty():
		outputs["scoringComparison"] = _run_scoring_comparison(scoring_comparison)

	_fail_if_needed(failures, not _assert_frontline_expectations(fixture.get("expected", {}), outputs), "frontline assertions failed")
	_fail_if_needed(failures, not _assert_breakthrough_expectations(fixture.get("expected", {}), outputs), "breakthrough assertions failed")
	_fail_if_needed(failures, not _assert_donor_expectations(fixture.get("expected", {}), outputs), "quiet donor legality assertions failed")
	_fail_if_needed(failures, not _assert_warning_expectations(fixture.get("expected", {}), outputs), "warning assertions failed")
	_fail_if_needed(failures, not _assert_recommended_actions(fixture.get("expected", {}), outputs), "recommended action assertions failed")
	_fail_if_needed(failures, not _assert_counterattack_expectations(fixture.get("expected", {}), outputs), "counterattack assertions failed")
	_fail_if_needed(failures, not _assert_scoring_comparison(fixture.get("expected", {}), outputs), "scoring comparison assertions failed")
	_fail_if_needed(failures, not _assert_deterministic_sort(fixture.get("expected", {}), outputs), "deterministic sorting assertions failed")

	return {
		"ok": failures.is_empty(),
		"fixtureId": fixture_id,
		"warnings": warnings,
		"failures": failures,
		"outputs": outputs,
		"report": _format_report(fixture_id, failures, warnings)
	}

static func replay_fixture_dir(dir_path: String) -> Dictionary:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {"ok": false, "error": "directory_unreadable", "path": dir_path}
	var fixture_files: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if name.get_extension().to_lower() != "json":
			continue
		fixture_files.append(dir_path.path_join(name))
	dir.list_dir_end()
	fixture_files.sort()

	var results: Array[Dictionary] = []
	var failed := 0
	for path in fixture_files:
		var result := replay_fixture_file(path)
		if not bool(result.get("ok", false)):
			failed += 1
		results.append(result)
	return {
		"ok": failed == 0,
		"fixtures": fixture_files.size(),
		"failed": failed,
		"results": results
	}

static func _normalize_operational_input(input: Dictionary) -> Dictionary:
	var normalized := {
		"operationId": String(input.get("operationId", "fixture")),
		"turnIndex": int(input.get("turnIndex", 0)),
		"threats": _typed_dict_array(input.get("threats", [])),
		"breakthroughs": _typed_dict_array(input.get("breakthroughs", [])),
		"sectors": _typed_dict_array(input.get("sectors", [])),
		"reserveRequests": _typed_dict_array(input.get("reserveRequests", [])),
		"reinforcementRequests": _typed_dict_array(input.get("reinforcementRequests", [])),
		"responseIntents": _typed_dict_array(input.get("responseIntents", [])),
		"enemyAdjacentHexes": _typed_dict_array(input.get("enemyAdjacentHexes", [])),
		"reserveUnits": _typed_dict_array(input.get("reserveUnits", [])),
		"reservePositions": _typed_dict_array(input.get("reservePositions", [])),
		"metadata": (input.get("metadata", {}) as Dictionary).duplicate(true)
	}
	if input.has("posture"):
		normalized["posture"] = String(input.get("posture", "balanced"))
	return normalized

static func _typed_dict_array(values: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in values:
		if typeof(value) == TYPE_DICTIONARY:
			output.append((value as Dictionary).duplicate(true))
	return output

static func _assert_frontline_expectations(expected: Dictionary, outputs: Dictionary) -> bool:
	if not expected.has("frontlineHexIds") and not expected.has("sectorCount"):
		return true
	var sectors: Array = outputs.get("mapSectors", [])
	var frontline: Array[String] = []
	for sector in sectors:
		for hex_id in (sector as Dictionary).get("frontlineHexIds", []):
			frontline.append(String(hex_id))
	frontline.sort()
	if expected.has("frontlineHexIds"):
		var want: Array[String] = []
		for hex_id in expected.get("frontlineHexIds", []):
			want.append(String(hex_id))
		want.sort()
		if frontline != want:
			return false
	if expected.has("sectorCount") and sectors.size() != int(expected.get("sectorCount", -1)):
		return false
	return true

static func _assert_breakthrough_expectations(expected: Dictionary, outputs: Dictionary) -> bool:
	if not expected.has("breakthroughSeverityMin") and not expected.has("reserveNeedsMustInclude"):
		return true
	var assessment: Dictionary = outputs.get("assessment", {})
	var breakthroughs: Array = assessment.get("breakthroughHexes", [])
	if expected.has("breakthroughSeverityMin"):
		var minima: Dictionary = expected.get("breakthroughSeverityMin", {})
		for breakthrough_id in minima.keys():
			var found := false
			for item in breakthroughs:
				var entry: Dictionary = item
				if String(entry.get("id", "")) != String(breakthrough_id):
					continue
				if float(entry.get("urgency", 0.0)) < float(minima.get(breakthrough_id, 0.0)):
					return false
				found = true
				break
			if not found:
				return false
	if expected.has("reserveNeedsMustInclude"):
		var reserve_needs: Array = assessment.get("reserveNeeds", [])
		var ids := {}
		for item in reserve_needs:
			ids[String((item as Dictionary).get("id", ""))] = true
		for reserve_id in expected.get("reserveNeedsMustInclude", []):
			if not ids.has(String(reserve_id)):
				return false
	return true

static func _assert_donor_expectations(expected: Dictionary, outputs: Dictionary) -> bool:
	if not expected.has("reinforcementPreferredSources") and not expected.has("donorLegalityBySector"):
		return true
	var assessment: Dictionary = outputs.get("assessment", {})
	var requests: Array = assessment.get("reinforcementRequests", [])
	var by_id := {}
	for item in requests:
		var entry: Dictionary = item
		by_id[String(entry.get("id", ""))] = entry
	if expected.has("reinforcementPreferredSources"):
		var pref_map: Dictionary = expected.get("reinforcementPreferredSources", {})
		for request_id in pref_map.keys():
			if not by_id.has(String(request_id)):
				return false
			var details: Dictionary = (by_id[String(request_id)] as Dictionary).get("details", {})
			var got: Array = details.get("preferredSources", [])
			var want: Array = pref_map.get(request_id, [])
			if got.size() != want.size():
				return false
			for i in range(want.size()):
				if String(got[i]) != String(want[i]):
					return false
	if expected.has("donorLegalityBySector"):
		var legal_map: Dictionary = expected.get("donorLegalityBySector", {})
		for request_id in legal_map.keys():
			if not by_id.has(String(request_id)):
				return false
			var details: Dictionary = (by_id[String(request_id)] as Dictionary).get("details", {})
			var donor_candidates: Array = details.get("donorCandidates", [])
			var donor_index := {}
			for donor in donor_candidates:
				donor_index[String((donor as Dictionary).get("sectorId", (donor as Dictionary).get("id", "")))] = donor
			for sector_id in (legal_map.get(request_id, {}) as Dictionary).keys():
				if not donor_index.has(String(sector_id)):
					return false
				var expected_legal := bool((legal_map.get(request_id, {}) as Dictionary).get(sector_id, false))
				var actual_legal := bool((donor_index[String(sector_id)] as Dictionary).get("legalForTransfer", false))
				if expected_legal != actual_legal:
					return false
	return true

static func _assert_warning_expectations(expected: Dictionary, outputs: Dictionary) -> bool:
	if not expected.has("warningsMustContain"):
		return true
	var assessment: Dictionary = outputs.get("assessment", {})
	var warnings: Array = assessment.get("warnings", [])
	for required_warning in expected.get("warningsMustContain", []):
		if not warnings.has(String(required_warning)):
			return false
	return true

static func _assert_recommended_actions(expected: Dictionary, outputs: Dictionary) -> bool:
	if not expected.has("recommendedActionsMustInclude"):
		return true
	var assessment: Dictionary = outputs.get("assessment", {})
	var actions := {}
	for item in assessment.get("recommendedIntents", []):
		actions[String((item as Dictionary).get("action", ""))] = true
	for action in expected.get("recommendedActionsMustInclude", []):
		if not actions.has(String(action)):
			return false
	return true

static func _assert_counterattack_expectations(expected: Dictionary, outputs: Dictionary) -> bool:
	if not expected.has("counterattackUrgencyMin"):
		return true
	var assessment: Dictionary = outputs.get("assessment", {})
	var opportunities: Array = assessment.get("counterattackOpportunities", [])
	var minima: Dictionary = expected.get("counterattackUrgencyMin", {})
	for opportunity_id in minima.keys():
		var found := false
		for item in opportunities:
			var entry: Dictionary = item
			if String(entry.get("id", "")) != String(opportunity_id):
				continue
			if float(entry.get("urgency", 0.0)) < float(minima.get(opportunity_id, 0.0)):
				return false
			found = true
			break
		if not found:
			return false
	return true

static func _run_scoring_comparison(config: Dictionary) -> Dictionary:
	var model := String(config.get("model", "enemyPressure"))
	var low_context: Dictionary = config.get("lowContext", {})
	var high_context: Dictionary = config.get("highContext", {})
	var minimum_delta := float(config.get("minimumDelta", 0.0))
	var low_score := 0.0
	var high_score := 0.0
	match model:
		"enemyPressure":
			low_score = float(OperationalScoringModel.score_enemy_pressure(low_context).get("score", 0.0))
			high_score = float(OperationalScoringModel.score_enemy_pressure(high_context).get("score", 0.0))
		"sectorDanger":
			low_score = float(OperationalScoringModel.score_sector_danger(low_context).get("score", 0.0))
			high_score = float(OperationalScoringModel.score_sector_danger(high_context).get("score", 0.0))
		_:
			low_score = 0.0
			high_score = 0.0
	return {
		"model": model,
		"lowScore": low_score,
		"highScore": high_score,
		"delta": high_score - low_score,
		"minimumDelta": minimum_delta,
		"pass": (high_score - low_score) >= minimum_delta
	}

static func _assert_scoring_comparison(expected: Dictionary, outputs: Dictionary) -> bool:
	if not outputs.has("scoringComparison"):
		return true
	if not expected.has("scoringComparisonPass"):
		return true
	var comparison: Dictionary = outputs.get("scoringComparison", {})
	return bool(comparison.get("pass", false)) == bool(expected.get("scoringComparisonPass", false))

static func _assert_deterministic_sort(expected: Dictionary, outputs: Dictionary) -> bool:
	var assertions: Array = expected.get("deterministicSortAssertions", [])
	if assertions.is_empty():
		return true
	for assertion in assertions:
		var rule: Dictionary = assertion
		var collection_name := String(rule.get("collection", ""))
		var expected_order: Array = rule.get("expectedOrder", [])
		var field := String(rule.get("field", ""))
		var collection := _resolve_collection(collection_name, outputs)
		if collection.size() != expected_order.size():
			return false
		for i in range(expected_order.size()):
			var expected_value := String(expected_order[i])
			var actual_value := ""
			if field.is_empty():
				actual_value = String(collection[i])
			else:
				actual_value = String((collection[i] as Dictionary).get(field, ""))
			if actual_value != expected_value:
				return false
	return true

static func _resolve_collection(collection_name: String, outputs: Dictionary) -> Array:
	if collection_name == "mapSectors":
		return outputs.get("mapSectors", [])
	var assessment: Dictionary = outputs.get("assessment", {})
	if assessment.has(collection_name):
		return assessment.get(collection_name, [])
	return []

static func _fail_if_needed(failures: Array[String], condition: bool, message: String) -> void:
	if condition:
		failures.append(message)

static func _format_report(fixture_id: String, failures: Array[String], warnings: Array[String]) -> String:
	if failures.is_empty():
		return "fixture=%s ok warnings=%d" % [fixture_id, warnings.size()]
	return "fixture=%s failed=%d warnings=%d :: %s" % [fixture_id, failures.size(), warnings.size(), "; ".join(failures)]

static func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary
