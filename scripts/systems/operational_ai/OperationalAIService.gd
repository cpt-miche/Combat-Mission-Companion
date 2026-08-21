extends RefCounted
class_name OperationalAIService

const OperationalEvaluator = preload("res://scripts/systems/operational_ai/OperationalEvaluator.gd")
const OperationalMapAnalyzer = preload("res://scripts/systems/operational_ai/OperationalMapAnalyzer.gd")
const AIDebugTracer = preload("res://scripts/systems/ai_debug/AIDebugTracer.gd")
const AIDebugFormatter = preload("res://scripts/systems/ai_debug/AIDebugFormatter.gd")
const MatchSetupTypes = preload("res://scripts/core/MatchSetupTypes.gd")
const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const ReconSystem = preload("res://scripts/systems/ReconSystem.gd")

static func run_for_active_player(trace_context: Dictionary = {}) -> Dictionary:
	var ai_player_index: int = int(GameState.active_player)
	if ai_player_index < 0 or ai_player_index >= GameState.players.size():
		return {"ok": false, "reason": "invalid_player_index"}

	var ai_player: Dictionary = GameState.players[ai_player_index] as Dictionary
	if ai_player.is_empty():
		return {"ok": false, "reason": "missing_player"}

	var ai_config: Dictionary = _resolve_ai_config(ai_player, trace_context)
	var tracer: AIDebugTracer = AIDebugTracer.new()
	var trace: Dictionary = tracer.start_trace({
		"phase": "operational_ai",
		"turn": int(GameState.current_turn),
		"player_id": ai_player_index,
		"ai_version": "OperationalEvaluator",
		"debug_level": int(GameState.ai_debug_level),
		"inputs_hash": AIDebugTracer.make_deterministic_id({
			"activePlayer": ai_player_index,
			"turn": int(GameState.current_turn),
			"trace_id": String(trace_context.get("trace_id", "")),
			"session_id": String(trace_context.get("session_id", "")),
			"doctrine": String(ai_config.get("doctrine", "balanced")),
			"difficulty": String(ai_config.get("difficulty", "medium"))
		})
	})

	var ai_controlled := String(ai_player.get("controller", "human")).strip_edges().to_lower() == "ai"
	if not bool(GameState.operational_ai_enabled) and not ai_controlled:
		tracer.add_event(trace, "feature_flag_disabled", {
			"stage": "operational_assessment",
			"reason_code": "operational_ai_disabled",
			"reason_text": "Operational assessment rollout flag is disabled.",
			"meta": {"flag": "GameState.operational_ai_enabled"}
		})
		var disabled_trace: Dictionary = tracer.finish_trace(trace, {
			"enabled": false,
			"playerIndex": ai_player_index,
			"assessment": {},
			"snapshot": {}
		}, {"evaluation_ms": 0})
		GameState.operational_ai_debug["player_%d" % ai_player_index] = disabled_trace.duplicate(true)
		_persist_trace(disabled_trace)
		return {"ok": true, "reason": "feature_flag_disabled", "enabled": false, "assessment": {}}

	var snapshot: Dictionary = _build_operational_snapshot(ai_player_index, ai_config)
	tracer.add_event(trace, "input_snapshot_built", {
		"stage": "operational_assessment",
		"reason_code": "snapshot_ready",
		"reason_text": "Operational assessment input snapshot built from GameState.",
		"meta": {
			"sector_count": (snapshot.get("sectors", []) as Array).size(),
			"threat_count": (snapshot.get("threats", []) as Array).size(),
			"breakthrough_count": (snapshot.get("breakthroughs", []) as Array).size(),
			"enemy_adjacent_count": (snapshot.get("enemyAdjacentHexes", []) as Array).size(),
			"active_doctrine": String(ai_config.get("doctrine", "balanced")),
			"active_difficulty": String(ai_config.get("difficulty", "medium"))
		}
	})

	var assessment: Dictionary = OperationalEvaluator.evaluate(snapshot)
	tracer.add_event(trace, "assessment_completed", {
		"stage": "operational_assessment",
		"reason_code": "evaluation_complete",
		"reason_text": "OperationalEvaluator returned a deterministic assessment.",
		"meta": {
			"recommended_intents": (assessment.get("recommendedIntents", []) as Array).size(),
			"warnings": (assessment.get("warnings", []) as Array).size()
		}
	})

	var finished_trace: Dictionary = tracer.finish_trace(trace, {
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
	GameState.operational_ai_debug["player_%d" % ai_player_index] = finished_trace.duplicate(true)
	_persist_trace(finished_trace)
	return {"ok": true, "reason": "assessed", "enabled": true, "assessment": assessment}

static func _build_operational_snapshot(ai_player_index: int, ai_config: Dictionary = {}) -> Dictionary:
	var ai_owner: int = _territory_owner_for_player(ai_player_index)
	var enemy_player_index: int = 1 - ai_player_index
	var enemy_owner: int = _territory_owner_for_player(enemy_player_index)
	var sector_map: Array[Dictionary] = OperationalMapAnalyzer.analyze(GameState.territory_map, ai_owner, enemy_owner)
	var observer_intel: Dictionary = _observer_intel_for_player(ai_player_index, ai_owner)
	var units_by_hex: Dictionary = _units_by_hex_for_observer(ai_player_index, enemy_player_index, observer_intel)
	var objectives_by_sector := _objectives_by_sector(sector_map)
	var ai_player: Dictionary = {}
	if ai_player_index >= 0 and ai_player_index < GameState.players.size():
		ai_player = GameState.players[ai_player_index] as Dictionary

	var threats: Array[Dictionary] = []
	var breakthroughs: Array[Dictionary] = []
	var sectors: Array[Dictionary] = []
	var enemy_adjacent: Array[Dictionary] = []

	for sector_variant in sector_map:
		var sector: Dictionary = sector_variant as Dictionary
		var sector_id: String = String(sector.get("sectorId", ""))
		var frontline: Array[String] = sector.get("frontlineHexIds", [])
		var rear: Array[String] = sector.get("rearHexIds", [])
		var contested: Array[String] = sector.get("contestedHexIds", [])
		var objective_hex_ids: Array[String] = []
		for objective_hex_variant in objectives_by_sector.get(sector_id, []) as Array:
			objective_hex_ids.append(String(objective_hex_variant))
		var primary_objectives: Array[String] = []
		var secondary_objectives: Array[String] = []
		for objective_hex_id in objective_hex_ids:
			var objective_entry := GameState.key_objectives.get(objective_hex_id, {}) as Dictionary
			if String(objective_entry.get("priority", "secondary")) == "primary":
				primary_objectives.append(objective_hex_id)
			else:
				secondary_objectives.append(objective_hex_id)

		var enemy_adjacent_count: int = 0
		var enemy_strength: float = 0.0
		var friendly_strength: float = 0.0
		var sector_adjacent_enemy_hexes: Dictionary = {}
		for hex_id_variant in frontline:
			var hex_id: String = String(hex_id_variant)
			var friendly_units: Array = (units_by_hex.get(hex_id, {}) as Dictionary).get("friendly", []) as Array
			friendly_strength += float(friendly_units.size())
			var adjacent_enemies: Array = _adjacent_enemy_units(hex_id, enemy_player_index, units_by_hex)
			enemy_adjacent_count += adjacent_enemies.size()
			enemy_strength += _estimated_strength(adjacent_enemies)
			for enemy_hex_id in _adjacent_enemy_hex_ids(hex_id, enemy_player_index, units_by_hex):
				sector_adjacent_enemy_hexes[String(enemy_hex_id)] = true

		var sector_enemy_hex_ids: Array[String] = []
		for enemy_hex_id in sector_adjacent_enemy_hexes.keys():
			sector_enemy_hex_ids.append(String(enemy_hex_id))
		sector_enemy_hex_ids.sort()
		var sector_intel: Dictionary = _intel_metrics_for_enemy_hexes(sector_enemy_hex_ids, observer_intel)

		var total_line_cells: int = max(1, frontline.size())
		var pressure: float = clamp(float(enemy_adjacent_count) / float(total_line_cells * 3), 0.0, 1.0)
		var readiness: float = clamp(float(friendly_strength) / float(max(1.0, enemy_strength + friendly_strength)), 0.0, 1.0)
		var supply: float = clamp(float(rear.size()) / float(max(1, (sector.get("hexIds", []) as Array).size())), 0.0, 1.0)

		var objective_criticality: float = clamp(float(frontline.size()) / 6.0, 0.0, 1.0)
		if not secondary_objectives.is_empty():
			objective_criticality = maxf(objective_criticality, 0.65)
		if not primary_objectives.is_empty():
			objective_criticality = 1.0
		sectors.append({
			"sectorId": sector_id,
			"frontlineHexIds": frontline.duplicate(),
			"contestedHexIds": contested.duplicate(),
			"rearHexIds": rear.duplicate(),
			"objectiveHexIds": objective_hex_ids.duplicate(),
			"primaryObjectiveHexIds": primary_objectives,
			"secondaryObjectiveHexIds": secondary_objectives,
			"pressure": pressure,
			"readiness": readiness,
			"supply": supply,
			"objectiveCriticality": objective_criticality,
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
			var hex_id: String = String(hex_id_variant)
			var adjacent_enemies: Array = _adjacent_enemy_units(hex_id, enemy_player_index, units_by_hex)
			if adjacent_enemies.is_empty():
				continue
			var adjacent_enemy_hex_ids: Array[String] = _adjacent_enemy_hex_ids(hex_id, enemy_player_index, units_by_hex)
			adjacent_enemy_hex_ids.sort()
			var adjacent_intel: Dictionary = _intel_metrics_for_enemy_hexes(adjacent_enemy_hex_ids, observer_intel)
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

	var doctrine: String = String(ai_config.get("doctrine", "balanced"))
	var difficulty: String = String(ai_config.get("difficulty", "medium"))
	return {
		"operationId": "turn_%d_player_%d" % [int(GameState.current_turn), ai_player_index],
		"turnIndex": int(GameState.current_turn),
		"posture": "balanced",
		"doctrine": doctrine,
		"difficulty": difficulty,
		"threats": threats,
		"breakthroughs": breakthroughs,
		"sectors": sectors,
		"reserveRequests": [],
		"reinforcementRequests": [],
		"responseIntents": [],
		"enemyAdjacentHexes": enemy_adjacent,
		"objectiveHexIds": GameState.key_objectives.keys(),
		"metadata": {
			"activePlayer": ai_player_index,
			"featureFlag": bool(GameState.operational_ai_enabled),
			"doctrine": doctrine,
			"difficulty": difficulty
		}
	}



static func _resolve_ai_config(ai_player: Dictionary, trace_context: Dictionary) -> Dictionary:
	var default_doctrine := "balanced"
	var default_difficulty := "medium"
	var context_doctrine := _map_ai_doctrine_to_operational(String(trace_context.get("ai_doctrine", default_doctrine)))
	var context_difficulty := MatchSetupTypes.sanitize_difficulty(trace_context.get("difficulty", default_difficulty))
	var doctrine: String = _resolve_operational_doctrine(ai_player)
	if bool(trace_context.get("ai_doctrine_overridden", false)):
		doctrine = context_doctrine
	if doctrine.strip_edges().is_empty():
		doctrine = default_doctrine
	var difficulty: String = MatchSetupTypes.sanitize_difficulty(GameState.selected_difficulty)
	if bool(trace_context.get("difficulty_overridden", false)):
		difficulty = context_difficulty
	if difficulty.strip_edges().is_empty():
		difficulty = default_difficulty
	return {"doctrine": doctrine, "difficulty": difficulty}

static func _resolve_operational_doctrine(ai_player: Dictionary) -> String:
	var selected_ai_doctrine: String = MatchSetupTypes.sanitize_ai_doctrine(GameState.selected_ai_doctrine)
	var player_doctrine: String = MatchSetupTypes.sanitize_ai_doctrine(ai_player.get("doctrine", selected_ai_doctrine))
	return _map_ai_doctrine_to_operational(player_doctrine)

static func _map_ai_doctrine_to_operational(doctrine: String) -> String:
	var normalized := doctrine.strip_edges().to_lower()
	var doctrine_map := {
		"balanced": "balanced",
		"aggressive": "maneuver",
		"defensive": "security",
		"maneuver": "maneuver",
		"attrition": "attrition",
		"security": "security"
	}
	return String(doctrine_map.get(normalized, "balanced"))


static func _observer_intel_for_player(ai_player_index: int, ai_owner: int) -> Dictionary:
	var by_observer: Dictionary = GameState.scout_intel_by_observer
	if by_observer == null:
		return {}
	var player_key: String = str(ai_player_index)
	if by_observer.has(player_key) and by_observer[player_key] is Dictionary:
		return (by_observer[player_key] as Dictionary).duplicate(true)
	var owner_key: String = str(ai_owner)
	if by_observer.has(owner_key) and by_observer[owner_key] is Dictionary:
		return (by_observer[owner_key] as Dictionary).duplicate(true)
	return {}

static func _adjacent_enemy_hex_ids(hex_id: String, enemy_player_index: int, units_by_hex: Dictionary) -> Array[String]:
	var result_map: Dictionary = {}
	var parsed: Variant = _parse_hex_id(hex_id)
	if not parsed is Vector2i:
		return []
	for offset in [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]:
		var neighbor: Vector2i = (parsed as Vector2i) + offset
		var neighbor_id: String = "%d,%d" % [neighbor.x, neighbor.y]
		if not units_by_hex.has(neighbor_id):
			continue
		var enemy_units: Array = ((units_by_hex[neighbor_id] as Dictionary).get("enemy", []) as Array)
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
	var observed_count: int = 0
	var confidence_sum: float = 0.0
	for enemy_hex_id in enemy_hex_ids:
		var scout_level: int = _scout_level_for_enemy_hex(observer_intel, String(enemy_hex_id))
		if scout_level > 0:
			observed_count += 1
		confidence_sum += float(scout_level) / 4.0
	var total: float = float(max(1, enemy_hex_ids.size()))
	var coverage: float = float(clamp(float(observed_count) / total, 0.0, 1.0))
	var confidence: float = float(clamp(confidence_sum / total, 0.0, 1.0))
	var uncertainty: float = float(clamp(1.0 - ((coverage + confidence) * 0.5), 0.0, 1.0))
	return {"coverage": coverage, "confidence": confidence, "uncertainty": uncertainty}

static func _scout_level_for_enemy_hex(observer_intel: Dictionary, enemy_hex_id: String) -> int:
	var intel: Variant = observer_intel.get(enemy_hex_id, null)
	if intel is Dictionary:
		return int(clamp(int((intel as Dictionary).get("scoutLevel", 0)), 0, 4))
	return 0

static func _units_by_hex_for_observer(ai_player_index: int, enemy_player_index: int, observer_intel: Dictionary) -> Dictionary:
	var by_hex: Dictionary = {}
	var visible_enemy_ids := {}
	for unit_variant in GameState.gameplay_units.values():
		if typeof(unit_variant) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_variant as Dictionary
		var owner: int = int(unit.get("owner", ai_player_index))
		if owner == enemy_player_index and not _enemy_directly_visible(unit, ai_player_index):
			continue
		if owner == enemy_player_index:
			visible_enemy_ids[String(unit.get("id", ""))] = true
		var hex: Variant = unit.get("hex", null)
		if not hex is Vector2i:
			continue
		var hex_id: String = "%d,%d" % [hex.x, hex.y]
		if not by_hex.has(hex_id):
			by_hex[hex_id] = {"friendly": [], "enemy": []}
		if owner == ai_player_index:
			((by_hex[hex_id] as Dictionary)["friendly"] as Array).append(unit)
		else:
			((by_hex[hex_id] as Dictionary)["enemy"] as Array).append(unit)
	var memory_variant: Variant = observer_intel.get(ReconSystem.UNIT_INTEL_KEY, {})
	if memory_variant is Dictionary:
		for unit_id_variant in (memory_variant as Dictionary).keys():
			var unit_id := String(unit_id_variant)
			if visible_enemy_ids.has(unit_id):
				continue
			var known_variant: Variant = (memory_variant as Dictionary).get(unit_id, {})
			if not (known_variant is Dictionary):
				continue
			var known: Dictionary = known_variant as Dictionary
			var confidence: float = float(known.get("memoryConfidence", 0.0))
			var last_hex_id: String = String(known.get("lastKnownHex", ""))
			var parsed: Variant = _parse_hex_id(last_hex_id)
			if confidence <= 0.0 or parsed == null:
				continue
			if not by_hex.has(last_hex_id):
				by_hex[last_hex_id] = {"friendly": [], "enemy": []}
			var estimated: Dictionary = {
				"id": unit_id,
				"owner": enemy_player_index,
				"hex": parsed,
				"size": String(known.get("reportedSize", "")),
				"type": String(known.get("reportedType", "")),
				"intel_confidence": confidence,
				"is_estimated_contact": true,
				"status": "alive"
			}
			((by_hex[last_hex_id] as Dictionary)["enemy"] as Array).append(estimated)
	return by_hex

static func _enemy_directly_visible(enemy: Dictionary, ai_player_index: int) -> bool:
	var enemy_hex := enemy.get("hex", Vector2i.ZERO) as Vector2i
	for unit_variant in GameState.gameplay_units.values():
		if not (unit_variant is Dictionary):
			continue
		var friendly := unit_variant as Dictionary
		if int(friendly.get("owner", -1)) != ai_player_index or not GameState.is_unit_alive(friendly):
			continue
		var friendly_hex := friendly.get("hex", Vector2i.ZERO) as Vector2i
		if friendly_hex == enemy_hex or Pathfinding.are_adjacent(friendly_hex, enemy_hex):
			return true
	return false

static func _estimated_strength(units: Array) -> float:
	var total := 0.0
	for unit_variant in units:
		if not (unit_variant is Dictionary):
			continue
		var unit := unit_variant as Dictionary
		var size := String(unit.get("size", "")).to_lower()
		var base := 0.5
		match size:
			"platoon": base = 0.33
			"company": base = 1.0
			"battalion": base = 4.0
		total += base * float(unit.get("intel_confidence", 1.0))
	return total

static func _objectives_by_sector(sectors: Array[Dictionary]) -> Dictionary:
	var assignments := {}
	for sector in sectors:
		assignments[String(sector.get("sectorId", ""))] = []
	for objective_hex_variant in GameState.key_objectives.keys():
		var objective_hex_id := String(objective_hex_variant)
		var objective_parsed: Variant = _parse_hex_id(objective_hex_id)
		if objective_parsed == null:
			continue
		var objective_hex := objective_parsed as Vector2i
		var best_sector_id := ""
		var best_distance := 999999
		for sector in sectors:
			var candidates := sector.get("frontlineHexIds", []) as Array
			if candidates.is_empty():
				candidates = sector.get("hexIds", []) as Array
			for candidate_variant in candidates:
				var candidate_parsed: Variant = _parse_hex_id(String(candidate_variant))
				if candidate_parsed == null:
					continue
				var candidate := candidate_parsed as Vector2i
				var distance := maxi(abs(objective_hex.x - candidate.x), abs(objective_hex.y - candidate.y))
				var sector_id := String(sector.get("sectorId", ""))
				if distance < best_distance or (distance == best_distance and (best_sector_id.is_empty() or sector_id < best_sector_id)):
					best_distance = distance
					best_sector_id = sector_id
		if not best_sector_id.is_empty():
			(assignments[best_sector_id] as Array).append(objective_hex_id)
	for sector_id in assignments.keys():
		(assignments[sector_id] as Array).sort()
	return assignments

static func _adjacent_enemy_units(hex_id: String, enemy_player_index: int, units_by_hex: Dictionary) -> Array:
	var results: Array = []
	var parsed: Variant = _parse_hex_id(hex_id)
	if not parsed is Vector2i:
		return results
	for offset in [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]:
		var neighbor: Vector2i = (parsed as Vector2i) + offset
		var neighbor_id: String = "%d,%d" % [neighbor.x, neighbor.y]
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
	var parts: PackedStringArray = hex_id.split(",")
	if parts.size() != 2:
		return null
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))

static func _persist_trace(final_trace: Dictionary) -> void:
	var trace_payload := final_trace.duplicate(true)
	trace_payload["line_entries"] = AIDebugFormatter.format_trace_lines(final_trace)
	trace_payload["line_log_path"] = SaveManager.AI_TRACE_LINE_LOG_PATH
	if not SaveManager.save_ai_trace(trace_payload):
		push_warning("Operational AI trace was not fully persisted for player %d." % int(final_trace.get("player_id", -1)))
