extends RefCounted
class_name ReconFixtureReplay

const ReconSystem = preload("res://scripts/systems/ReconSystem.gd")

const SUPPORTED_FIXTURE_VERSION := 1

static func replay_fixture_file(path: String) -> Dictionary:
	var fixture := _read_json_file(path)
	if fixture.is_empty():
		return {"ok": false, "path": path, "error": "fixture_unreadable"}
	var replay := replay_fixture(fixture)
	replay["path"] = path
	return replay

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

static func replay_fixture(fixture: Dictionary) -> Dictionary:
	var fixture_id := String(fixture.get("id", ""))
	var failures: Array[String] = []
	var warnings: Array[String] = []
	var outputs := {}

	if int(fixture.get("fixtureVersion", SUPPORTED_FIXTURE_VERSION)) > SUPPORTED_FIXTURE_VERSION:
		warnings.append("fixture_version_newer_than_runner")

	var prior_intel := (fixture.get("initialPriorIntel", {}) as Dictionary).duplicate(true)
	var turn_outputs: Array[Dictionary] = []
	for turn in fixture.get("turns", []):
		if not (turn is Dictionary):
			continue
		var turn_dict := turn as Dictionary
		if turn_dict.has("priorIntelOverride"):
			var override_prior := turn_dict.get("priorIntelOverride", null)
			if override_prior is Dictionary:
				prior_intel = (override_prior as Dictionary).duplicate(true)
		var units := _units_dictionary(turn_dict.get("units", []))
		var observer_owner := int(turn_dict.get("observerOwner", int(fixture.get("observerOwner", 1))))
		var seed := int(turn_dict.get("seed", int(fixture.get("seed", 1))))
		var result := _resolve_once(units, observer_owner, prior_intel, seed)
		var expected := turn_dict.get("expected", {}) as Dictionary
		_assert_turn_expectations(failures, fixture_id, String(turn_dict.get("id", "turn")), expected, result)
		turn_outputs.append({
			"turnId": String(turn_dict.get("id", "")),
			"seed": seed,
			"result": result.duplicate(true)
		})
		prior_intel = result.duplicate(true)
	outputs["turns"] = turn_outputs

	for check in fixture.get("deterministicChecks", []):
		if not (check is Dictionary):
			continue
		var deterministic_result := _run_deterministic_check(check as Dictionary)
		if not bool(deterministic_result.get("ok", false)):
			failures.append("%s: deterministic check failed (%s)" % [fixture_id, String(deterministic_result.get("message", ""))])

	for progression_check in fixture.get("progressionChecks", []):
		if not (progression_check is Dictionary):
			continue
		var progression_result := _run_progression_check(progression_check as Dictionary)
		if not bool(progression_result.get("ok", false)):
			failures.append("%s: progression check failed (%s)" % [fixture_id, String(progression_result.get("message", ""))])

	return {
		"ok": failures.is_empty(),
		"fixtureId": fixture_id,
		"warnings": warnings,
		"failures": failures,
		"outputs": outputs,
		"report": _format_report(fixture_id, failures, warnings)
	}

static func _resolve_once(units: Dictionary, observer_owner: int, prior_intel: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return ReconSystem.resolve_turn_start_intel(units, observer_owner, prior_intel, rng)

static func _assert_turn_expectations(failures: Array[String], fixture_id: String, turn_id: String, expected: Dictionary, result: Dictionary) -> void:
	if expected.is_empty():
		return

	var expected_hex_levels := expected.get("hexLevels", {}) as Dictionary
	for hex_id in expected_hex_levels.keys():
		if not result.has(hex_id):
			failures.append("%s/%s: missing hex intel %s" % [fixture_id, turn_id, String(hex_id)])
			continue
		var intel := result.get(hex_id, {}) as Dictionary
		if int(intel.get("scoutLevel", -1)) != int(expected_hex_levels.get(hex_id, -999)):
			failures.append("%s/%s: hex %s scoutLevel expected=%d got=%d" % [fixture_id, turn_id, String(hex_id), int(expected_hex_levels.get(hex_id, -999)), int(intel.get("scoutLevel", -1))])

	var expected_hex_level_min := expected.get("hexLevelMin", {}) as Dictionary
	for hex_id in expected_hex_level_min.keys():
		if not result.has(hex_id):
			failures.append("%s/%s: missing hex intel %s" % [fixture_id, turn_id, String(hex_id)])
			continue
		var intel := result.get(hex_id, {}) as Dictionary
		if int(intel.get("scoutLevel", -1)) < int(expected_hex_level_min.get(hex_id, 0)):
			failures.append("%s/%s: hex %s scoutLevel below min=%d got=%d" % [fixture_id, turn_id, String(hex_id), int(expected_hex_level_min.get(hex_id, 0)), int(intel.get("scoutLevel", -1))])

	var expected_hex_level_max := expected.get("hexLevelMax", {}) as Dictionary
	for hex_id in expected_hex_level_max.keys():
		if not result.has(hex_id):
			failures.append("%s/%s: missing hex intel %s" % [fixture_id, turn_id, String(hex_id)])
			continue
		var intel := result.get(hex_id, {}) as Dictionary
		if int(intel.get("scoutLevel", -1)) > int(expected_hex_level_max.get(hex_id, ReconSystem.SCOUT_LEVEL_MAX)):
			failures.append("%s/%s: hex %s scoutLevel above max=%d got=%d" % [fixture_id, turn_id, String(hex_id), int(expected_hex_level_max.get(hex_id, ReconSystem.SCOUT_LEVEL_MAX)), int(intel.get("scoutLevel", -1))])

	for hex_id in expected.get("clearedHexes", []):
		var key := String(hex_id)
		if not result.has(key):
			failures.append("%s/%s: expected stale hex %s to exist" % [fixture_id, turn_id, key])
			continue
		var stale := result.get(key, {}) as Dictionary
		if int(stale.get("scoutLevel", -1)) != 0:
			failures.append("%s/%s: stale hex %s scoutLevel not reset" % [fixture_id, turn_id, key])
		var known := stale.get("knownEnemyUnits", []) as Array
		if not known.is_empty():
			failures.append("%s/%s: stale hex %s still has known units" % [fixture_id, turn_id, key])

	var expected_units := expected.get("knownByUnit", {}) as Dictionary
	for unit_id in expected_units.keys():
		var actual_known := _unit_intel(result, String(unit_id))
		if actual_known == null:
			failures.append("%s/%s: missing unit intel for %s" % [fixture_id, turn_id, String(unit_id)])
			continue
		var wanted := expected_units.get(unit_id, {}) as Dictionary
		_assert_known_fields(failures, fixture_id, turn_id, String(unit_id), wanted, actual_known as Dictionary)

	for missing_unit_id in expected.get("missingUnitIntel", []):
		if _unit_intel(result, String(missing_unit_id)) != null:
			failures.append("%s/%s: expected missing unit intel for %s" % [fixture_id, turn_id, String(missing_unit_id)])

static func _assert_known_fields(failures: Array[String], fixture_id: String, turn_id: String, unit_id: String, expected: Dictionary, actual: Dictionary) -> void:
	for field_name in expected.keys():
		var want := expected.get(field_name)
		var got := actual.get(field_name)
		if want != got:
			failures.append("%s/%s: unit %s field %s expected=%s got=%s" % [fixture_id, turn_id, unit_id, field_name, var_to_str(want), var_to_str(got)])

static func _unit_intel(result: Dictionary, unit_id: String) -> Variant:
	var by_id := result.get(ReconSystem.UNIT_INTEL_KEY, null)
	if not (by_id is Dictionary):
		return null
	var known := (by_id as Dictionary).get(unit_id, null)
	if known is Dictionary:
		return (known as Dictionary)
	return null

static func _run_deterministic_check(config: Dictionary) -> Dictionary:
	var units := _units_dictionary(config.get("units", []))
	var prior := (config.get("priorIntel", {}) as Dictionary).duplicate(true)
	var observer_owner := int(config.get("observerOwner", 1))
	var seed := int(config.get("seed", 1))
	var runs := maxi(int(config.get("runs", 2)), 2)
	var baseline := _resolve_once(units, observer_owner, prior, seed)
	for i in range(1, runs):
		var rerun := _resolve_once(units, observer_owner, prior, seed)
		if not baseline.hash() == rerun.hash() and baseline != rerun:
			return {"ok": false, "message": "seed %d produced non-identical replay on run %d" % [seed, i + 1]}
	return {"ok": true, "message": "repeatable"}

static func _run_progression_check(config: Dictionary) -> Dictionary:
	var units := _unit_array(config.get("adjacentFriendlies", []))
	var seed := int(config.get("seed", 1))
	var rng_direct := RandomNumberGenerator.new()
	rng_direct.seed = seed
	var direct_gain := ReconSystem._roll_scout_progression(units, rng_direct)
	var manual_gain := _manual_progression_gain(units, seed)
	if direct_gain != manual_gain:
		return {"ok": false, "message": "manual gain mismatch direct=%d manual=%d" % [direct_gain, manual_gain]}
	var min_gain := int(config.get("minGain", -1))
	if min_gain >= 0 and direct_gain < min_gain:
		return {"ok": false, "message": "gain %d below minGain %d" % [direct_gain, min_gain]}
	return {"ok": true, "message": "gain=%d" % direct_gain}

static func _manual_progression_gain(units: Array[Dictionary], seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var gain := 0
	for unit in units:
		var denominator := int(ReconSystem.ROLL_DENOMINATOR_BY_TYPE.get(ReconSystem._normalized_type(unit), 0))
		if denominator <= 0:
			continue
		if rng.randi_range(1, denominator) == 1:
			gain += 1
	return gain

static func _units_dictionary(raw_units: Variant) -> Dictionary:
	var as_array := raw_units as Array
	var by_id := {}
	if as_array == null:
		return by_id
	for entry in as_array:
		if not (entry is Dictionary):
			continue
		var unit := _normalize_unit(entry as Dictionary)
		var unit_id := String(unit.get("id", ""))
		if unit_id.is_empty():
			continue
		by_id[unit_id] = unit
	return by_id

static func _unit_array(raw_units: Variant) -> Array[Dictionary]:
	var as_array := raw_units as Array
	var output: Array[Dictionary] = []
	if as_array == null:
		return output
	for entry in as_array:
		if not (entry is Dictionary):
			continue
		output.append(_normalize_unit(entry as Dictionary))
	return output

static func _normalize_unit(raw: Dictionary) -> Dictionary:
	var unit := raw.duplicate(true)
	unit["id"] = String(raw.get("id", ""))
	unit["owner"] = int(raw.get("owner", 0))
	unit["unit_type"] = String(raw.get("unit_type", raw.get("type", "infantry")))
	unit["size"] = String(raw.get("size", "company"))
	unit["hex"] = _hex_from_value(raw.get("hex", Vector2i.ZERO))
	return unit

static func _hex_from_value(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		var dict := value as Dictionary
		return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
	if value is Array:
		var parts := value as Array
		if parts.size() >= 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO

static func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed := JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary)

static func _format_report(fixture_id: String, failures: Array[String], warnings: Array[String]) -> String:
	if failures.is_empty():
		return "fixture=%s ok warnings=%d" % [fixture_id, warnings.size()]
	return "fixture=%s failed=%d warnings=%d :: %s" % [fixture_id, failures.size(), warnings.size(), "; ".join(failures)]
