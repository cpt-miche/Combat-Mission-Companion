extends RefCounted
class_name OperationalAIService

const OperationalEvaluator = preload("res://scripts/systems/operational_ai/OperationalEvaluator.gd")
const OperationalMapAnalyzer = preload("res://scripts/systems/operational_ai/OperationalMapAnalyzer.gd")
const AIDebugTracer = preload("res://scripts/systems/ai_debug/AIDebugTracer.gd")

static func run_for_active_player(trace_context: Dictionary = {}) -> Dictionary:
	var ai_player_index := int(GameState.active_player)
	if ai_player_index < 0 or ai_player_index >= GameState.players.size():
		return {"ok": false, "reason": "invalid_player_index"}

	var ai_player := GameState.players[ai_player_index] as Dictionary
	if ai_player.is_empty():
		return {"ok": false, "reason": "missing_player"}

	var tracer := AIDebugTracer.new()
	var trace := tracer.start_trace({
		"phase": "operational_ai",
		"turn": int(GameState.current_turn),
		"player_id": ai_player_index,
		"ai_version": "OperationalEvaluator",
		"debug_level": int(GameState.ai_debug_level),
		"inputs_hash": AIDebugTracer.make_deterministic_id({
			"activePlayer": ai_player_index,
			"turn": int(GameState.current_turn),
			"trace_id": String(trace_context.get("trace_id", "")),
			"session_id": String(trace_context.get("session_id", ""))
		})
	})

	if not bool(GameState.operational_ai_enabled):
		tracer.add_event(trace, "feature_flag_disabled", {
			"stage": "operational_assessment",
			"reason_code": "operational_ai_disabled",
			"reason_text": "Operational assessment rollout flag is disabled.",
			"meta": {"flag": "GameState.operational_ai_enabled"}
		})
		var disabled_trace := tracer.finish_trace(trace, {
			"enabled": false,
			"playerIndex": ai_player_index,
			"assessment": {},
			"snapshot": {}
		}, {"evaluation_ms": 0})
		GameState.operational_ai_debug["player_%d" % ai_player_index] = _legacy_debug_from_trace(disabled_trace)
		return {"ok": true, "reason": "feature_flag_disabled", "enabled": false, "assessment": {}}

	var snapshot := _build_operational_snapshot(ai_player_index)
	tracer.add_event(trace, "input_snapshot_built", {
		"stage": "operational_assessment",
		"reason_code": "snapshot_ready",
		"reason_text": "Operational assessment input snapshot built from GameState.",
		"meta": {
			"sector_count": (snapshot.get("sectors", []) as Array).size(),
			"threat_count": (snapshot.get("threats", []) as Array).size(),
			"breakthrough_count": (snapshot.get("breakthroughs", []) as Array).size(),
			"enemy_adjacent_count": (snapshot.get("enemyAdjacentHexes", []) as Array).size()
		}
	})

	var assessment := OperationalEvaluator.evaluate(snapshot)
	tracer.add_event(trace, "assessment_completed", {
		"stage": "operational_assessment",
		"reason_code": "evaluation_complete",
		"reason_text": "OperationalEvaluator returned a deterministic assessment.",
		"meta": {
			"recommended_intents": (assessment.get("recommendedIntents", []) as Array).size(),
			"warnings": (assessment.get("warnings", []) as Array).size()
		}
	})

	var finished_trace := tracer.finish_trace(trace, {
		"enabled": true,
		"playerIndex": ai_player_index,
		"snapshot": snapshot,
		"assessment": assessment
	}, {"evaluation_ms": 0})

	GameState.operational_ai_state = {
		"turn": int(GameState.current_turn),
		"playerIndex": ai_player_index,
		"snapshot": snapshot,
		"assessment": assessment,
		"traceId": String(finished_trace.get("trace_id", ""))
	}
	GameState.operational_ai_debug["player_%d" % ai_player_index] = _legacy_debug_from_trace(finished_trace)
	return {"ok": true, "reason": "assessed", "enabled": true, "assessment": assessment}

static func _build_operational_snapshot(ai_player_index: int) -> Dictionary:
	var ai_owner := _territory_owner_for_player(ai_player_index)
	var enemy_player_index := 1 - ai_player_index
	var enemy_owner := _territory_owner_for_player(enemy_player_index)
	var sector_map: Array[Dictionary] = OperationalMapAnalyzer.analyze(GameState.territory_map, ai_owner, enemy_owner)
	var units_by_hex := _units_by_hex()
	var observer_intel := _observer_intel_for_player(ai_player_index, ai_owner)

	var threats: Array[Dictionary] = []
	var breakthroughs: Array[Dictionary] = []
	var sectors: Array[Dictionary] = []
	var enemy_adjacent: Array[Dictionary] = []

	for sector_variant in sector_map:
		var sector := sector_variant as Dictionary
		var sector_id := String(sector.get("sectorId", ""))
		var frontline: Array[String] = sector.get("frontlineHexIds", [])
		var rear: Array[String] = sector.get("rearHexIds", [])
		var contested: Array[String] = sector.get("contestedHexIds", [])

		var enemy_adjacent_count := 0
		var enemy_strength := 0.0
		var friendly_strength := 0.0
		var sector_adjacent_enemy_hexes := {}
		for hex_id_variant in frontline:
			var hex_id := String(hex_id_variant)
			var friendly_units := (units_by_hex.get(hex_id, {}) as Dictionary).get("friendly", []) as Array
			friendly_strength += float(friendly_units.size())
			var adjacent_enemies := _adjacent_enemy_units(hex_id, enemy_player_index, units_by_hex)
			enemy_adjacent_count += adjacent_enemies.size()
			enemy_strength += float(adjacent_enemies.size())
			for enemy_hex_id in _adjacent_enemy_hex_ids(hex_id, enemy_player_index, units_by_hex):
				sector_adjacent_enemy_hexes[String(enemy_hex_id)] = true

		var sector_enemy_hex_ids: Array[String] = []
		for enemy_hex_id in sector_adjacent_enemy_hexes.keys():
			sector_enemy_hex_ids.append(String(enemy_hex_id))
		sector_enemy_hex_ids.sort()
		var sector_intel := _intel_metrics_for_enemy_hexes(sector_enemy_hex_ids, observer_intel)

		var total_line_cells: int = max(1, frontline.size())
		var pressure: float = clamp(float(enemy_adjacent_count) / float(total_line_cells * 3), 0.0, 1.0)
		var readiness: float = clamp(float(friendly_strength) / float(max(1.0, enemy_strength + friendly_strength)), 0.0, 1.0)
		var supply: float = clamp(float(rear.size()) / float(max(1, (sector.get("hexIds", []) as Array).size())), 0.0, 1.0)

		sectors.append({
			"id": sector_id,
			"pressure": pressure,
			"readiness": readiness,
			"supply": supply,
			"objectiveCriticality": clamp(float(frontline.size()) / 6.0, 0.0, 1.0),
			"defensibility": clamp(1.0 - pressure, 0.0, 1.0),
			"recentEnemyAdvance": 0.0,
			"support": clamp((readiness + supply) * 0.5, 0.0, 1.0),
			"enemyObservedConfidence": float(sector_intel.get("confidence", 0.0)),
			"intelCoverage": float(sector_intel.get("coverage", 0.0)),
			"scoutUncertainty": float(sector_intel.get("uncertainty", 0.0))
		})

		threats.append({
			"id": "threat_%s" % sector_id,
			"sectorId": sector_id,
			"enemyStrength": clamp(enemy_strength / 8.0, 0.0, 1.0),
			"proximity": pressure,
			"momentum": clamp(pressure * 0.6, 0.0, 1.0)
		})

		if pressure >= 0.6:
			breakthroughs.append({
				"id": "breakthrough_%s" % sector_id,
				"sectorId": sector_id,
				"opportunity": clamp(pressure, 0.0, 1.0),
				"readiness": clamp(readiness, 0.0, 1.0),
				"terrain": 0.5,
				"penetrationDepth": pressure,
				"objectiveProximity": clamp(float(frontline.size()) / 6.0, 0.0, 1.0),
				"roadAccess": 0.5,
				"sectorGap": clamp(float(contested.size()) / float(max(1, frontline.size())), 0.0, 1.0),
				"momentum": clamp(pressure * 0.7, 0.0, 1.0)
			})

		for hex_id_variant in frontline:
			var hex_id := String(hex_id_variant)
			var adjacent_enemies := _adjacent_enemy_units(hex_id, enemy_player_index, units_by_hex)
			if adjacent_enemies.is_empty():
				continue
			var adjacent_enemy_hex_ids := _adjacent_enemy_hex_ids(hex_id, enemy_player_index, units_by_hex)
			adjacent_enemy_hex_ids.sort()
			var adjacent_intel := _intel_metrics_for_enemy_hexes(adjacent_enemy_hex_ids, observer_intel)
			enemy_adjacent.append({
				"id": "adjacent_%s" % hex_id,
				"hexId": hex_id,
				"sectorId": sector_id,
				"objectiveValue": clamp(float(adjacent_enemies.size()) / 4.0, 0.0, 1.0),
				"enemyWeaknessEstimate": clamp(1.0 - (float(adjacent_enemies.size()) / 4.0), 0.0, 1.0),
				"localFriendlyPower": clamp(float(((units_by_hex.get(hex_id, {}) as Dictionary).get("friendly", []) as Array).size()) / 4.0, 0.0, 1.0),
				"artillerySupport": 0.5,
				"reconSupport": float(adjacent_intel.get("confidence", 0.0)),
				"scoutUncertainty": float(adjacent_intel.get("uncertainty", 0.0)),
				"terrainSuitability": 0.5,
				"defensiveCoherenceRisk": clamp(pressure, 0.0, 1.0),
				"overextensionRisk": clamp(pressure * 0.7, 0.0, 1.0)
			})

	return {
		"operationId": "turn_%d_player_%d" % [int(GameState.current_turn), ai_player_index],
		"turnIndex": int(GameState.current_turn),
		"posture": "balanced",
		"threats": threats,
		"breakthroughs": breakthroughs,
		"sectors": sectors,
		"reserveRequests": [],
		"reinforcementRequests": [],
		"responseIntents": [],
		"enemyAdjacentHexes": enemy_adjacent,
		"metadata": {
			"activePlayer": ai_player_index,
			"featureFlag": bool(GameState.operational_ai_enabled)
		}
	}


static func _observer_intel_for_player(ai_player_index: int, ai_owner: int) -> Dictionary:
	var by_observer: Dictionary = GameState.scout_intel_by_observer
	if by_observer == null:
		return {}
	var owner_key := str(ai_owner)
	if by_observer.has(owner_key) and by_observer[owner_key] is Dictionary:
		return (by_observer[owner_key] as Dictionary).duplicate(true)
	var player_key := str(ai_player_index)
	if by_observer.has(player_key) and by_observer[player_key] is Dictionary:
		return (by_observer[player_key] as Dictionary).duplicate(true)
	return {}

static func _adjacent_enemy_hex_ids(hex_id: String, enemy_player_index: int, units_by_hex: Dictionary) -> Array[String]:
	var result_map := {}
	var parsed: Variant = _parse_hex_id(hex_id)
	if not parsed is Vector2i:
		return []
	for offset in [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]:
		var neighbor: Vector2i = (parsed as Vector2i) + offset
		var neighbor_id := "%d,%d" % [neighbor.x, neighbor.y]
		if not units_by_hex.has(neighbor_id):
			continue
		var enemy_units := ((units_by_hex[neighbor_id] as Dictionary).get("enemy", []) as Array)
		for unit_variant in enemy_units:
			if typeof(unit_variant) != TYPE_DICTIONARY:
				continue
			if int((unit_variant as Dictionary).get("owner", -1)) == enemy_player_index:
				result_map[neighbor_id] = true
				break
	var result: Array[String] = []
	for enemy_hex_id in result_map.keys():
		result.append(String(enemy_hex_id))
	return result

static func _intel_metrics_for_enemy_hexes(enemy_hex_ids: Array[String], observer_intel: Dictionary) -> Dictionary:
	if enemy_hex_ids.is_empty():
		return {"coverage": 1.0, "confidence": 1.0, "uncertainty": 0.0}
	var observed_count := 0
	var confidence_sum := 0.0
	for enemy_hex_id in enemy_hex_ids:
		var scout_level := _scout_level_for_enemy_hex(observer_intel, String(enemy_hex_id))
		if scout_level > 0:
			observed_count += 1
		confidence_sum += float(scout_level) / 4.0
	var total := float(max(1, enemy_hex_ids.size()))
	var coverage := clamp(float(observed_count) / total, 0.0, 1.0)
	var confidence := clamp(confidence_sum / total, 0.0, 1.0)
	var uncertainty := clamp(1.0 - ((coverage + confidence) * 0.5), 0.0, 1.0)
	return {"coverage": coverage, "confidence": confidence, "uncertainty": uncertainty}

static func _scout_level_for_enemy_hex(observer_intel: Dictionary, enemy_hex_id: String) -> int:
	var intel := observer_intel.get(enemy_hex_id, null)
	if intel is Dictionary:
		return int(clamp(int((intel as Dictionary).get("scoutLevel", 0)), 0, 4))
	return 0

static func _units_by_hex() -> Dictionary:
	var by_hex := {}
	for unit_variant in GameState.gameplay_units.values():
		if typeof(unit_variant) != TYPE_DICTIONARY:
			continue
		var unit := unit_variant as Dictionary
		var hex: Variant = unit.get("hex", null)
		if not hex is Vector2i:
			continue
		var hex_id := "%d,%d" % [hex.x, hex.y]
		if not by_hex.has(hex_id):
			by_hex[hex_id] = {"friendly": [], "enemy": []}
		var owner := int(unit.get("owner", GameState.active_player))
		if owner == GameState.active_player:
			((by_hex[hex_id] as Dictionary)["friendly"] as Array).append(unit)
		else:
			((by_hex[hex_id] as Dictionary)["enemy"] as Array).append(unit)
	return by_hex

static func _adjacent_enemy_units(hex_id: String, enemy_player_index: int, units_by_hex: Dictionary) -> Array:
	var results: Array = []
	var parsed: Variant = _parse_hex_id(hex_id)
	if not parsed is Vector2i:
		return results
	for offset in [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]:
		var neighbor: Vector2i = (parsed as Vector2i) + offset
		var neighbor_id := "%d,%d" % [neighbor.x, neighbor.y]
		if not units_by_hex.has(neighbor_id):
			continue
		for unit_variant in ((units_by_hex[neighbor_id] as Dictionary).get("enemy", []) as Array):
			if typeof(unit_variant) != TYPE_DICTIONARY:
				continue
			if int((unit_variant as Dictionary).get("owner", -1)) == enemy_player_index:
				results.append(unit_variant)
	return results

static func _territory_owner_for_player(player_index: int) -> int:
	if player_index == 0:
		return GameState.TerritoryOwnership.PLAYER_1
	if player_index == 1:
		return GameState.TerritoryOwnership.PLAYER_2
	return GameState.TerritoryOwnership.NEUTRAL

static func _parse_hex_id(hex_id: String) -> Variant:
	var parts := hex_id.split(",")
	if parts.size() != 2:
		return null
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))

static func _legacy_debug_from_trace(final_trace: Dictionary) -> Dictionary:
	var outputs := final_trace.get("outputs", {}) as Dictionary
	var legacy := outputs.duplicate(true)
	legacy["traceId"] = String(final_trace.get("trace_id", ""))
	legacy["trace"] = final_trace.duplicate(true)
	legacy["events"] = (final_trace.get("events", []) as Array).duplicate(true)
	legacy["eventCount"] = int(final_trace.get("event_count", (final_trace.get("events", []) as Array).size()))
	return legacy
