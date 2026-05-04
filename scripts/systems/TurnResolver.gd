extends RefCounted
class_name TurnResolver

const Pathfinding = preload("res://scripts/systems/Pathfinding.gd")
const OrderSystem = preload("res://scripts/systems/OrderSystem.gd")
const ReconSystem = preload("res://scripts/systems/ReconSystem.gd")
const OperationalAIService = preload("res://scripts/systems/operational_ai/OperationalAIService.gd")
const Rules = preload("res://scripts/core/Rules.gd")
const MatchSetupTypes = preload("res://scripts/core/MatchSetupTypes.gd")

static func resolve_turn(units: Dictionary, orders: Dictionary, combat_log: CombatLog, trace_context: Dictionary = {}) -> Dictionary:
	var execution_queue: Array[Dictionary] = []
	var known_enemy_units: Array[String] = []
	var own_casualties: Array[Dictionary] = []
	var enemy_casualties: Array[Dictionary] = []
	var trace_events: Array[Dictionary] = []
	var trace_anomalies: Array[Dictionary] = []
	var base_units := units.duplicate(true)
	var turn_trace := _resolve_turn_trace_context(orders, trace_context)

	var rng_seed := int(turn_trace.get("rng_seed", 0))
	if rng_seed == 0:
		rng_seed = int(Time.get_unix_time_from_system())
		turn_trace["rng_seed"] = rng_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var order_list: Array[Dictionary] = []
	for order in orders.values():
		if typeof(order) == TYPE_DICTIONARY:
			order_list.append(order)
	order_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _initiative_score(a, units) > _initiative_score(b, units)
	)
	var active_owner := _resolve_active_owner(order_list, units, int(trace_context.get("active_owner", 0)))
	var prior_scout_intel_by_observer := trace_context.get("scout_intel_by_observer", {}) as Dictionary
	if prior_scout_intel_by_observer == null:
		prior_scout_intel_by_observer = {}
	var prior_owner_intel := prior_scout_intel_by_observer.get(str(active_owner), {}) as Dictionary
	if prior_owner_intel == null:
		prior_owner_intel = {}
	var updated_owner_intel := ReconSystem.resolve_turn_start_intel(units, active_owner, prior_owner_intel, rng)
	var updated_scout_intel_by_observer := prior_scout_intel_by_observer.duplicate(true)
	updated_scout_intel_by_observer[str(active_owner)] = updated_owner_intel
	_add_trace_event(trace_events, turn_trace, "rng_initialized", {
		"rng_seed": rng_seed,
		"rng_state": str(rng.state)
	})
	var operational_result := OperationalAIService.run_for_active_player(turn_trace)
	_add_trace_event(trace_events, turn_trace, "operational_assessment", {
		"enabled": bool(operational_result.get("enabled", false)),
		"reason": String(operational_result.get("reason", "")),
		"ok": bool(operational_result.get("ok", false))
	})

	for order in order_list:
		var unit_id := String(order.get("unit_id", ""))
		if unit_id.is_empty():
			_add_anomaly(trace_anomalies, turn_trace, "invalid_order", {
				"reason": "order missing unit_id",
				"order": order.duplicate(true)
			})
			continue
		if not units.has(unit_id):
			_add_anomaly(trace_anomalies, turn_trace, "missing_unit", {
				"reason": "order references unknown unit",
				"unit_id": unit_id
			})
			continue

		var unit_state := units[unit_id] as Dictionary
		var owner := int(unit_state.get("owner", 0))
		var order_type := int(order.get("type", OrderSystem.OrderType.MOVE))
		var path := order.get("path", []) as Array[Vector2i]
		if order_type != OrderSystem.OrderType.DIG_IN and path.is_empty():
			_add_anomaly(trace_anomalies, turn_trace, "invalid_order", {
				"reason": "order path is empty",
				"unit_id": unit_id
			})
			continue

		if path.size() > 1:
			for i in range(1, path.size()):
				var next_hex: Vector2i = path[i]
				var stack_check := _validate_destination_stack(units, unit_id, unit_state, next_hex)
				if not bool(stack_check.get("ok", false)):
					var stack_payload := {
						"unit_id": unit_id,
						"step_index": i,
						"to": _hex_to_dict(next_hex),
						"reason": String(stack_check.get("reason", "stack violation"))
					}
					_add_anomaly(trace_anomalies, turn_trace, "illegal_stack_move", stack_payload)
					combat_log.add_entry("%s halted: %s at %d,%d." % [unit_id, String(stack_check.get("reason", "stack violation")), next_hex.x, next_hex.y], stack_payload)
					break
				execution_queue.append({"type": "move", "unit_id": unit_id, "to": next_hex})
				unit_state["hex"] = next_hex
				_add_trace_event(trace_events, turn_trace, "move_step", {
					"unit_id": unit_id,
					"step_index": i,
					"to": _hex_to_dict(next_hex)
				})
				if _is_enemy_adjacent(next_hex, owner, units):
					var halted_payload := {
						"unit_id": unit_id,
						"hex": _hex_to_dict(next_hex)
					}
					_add_trace_event(trace_events, turn_trace, "halted_enemy_proximity", halted_payload)
					combat_log.add_entry("%s halted due to enemy proximity at %d,%d." % [unit_id, next_hex.x, next_hex.y], halted_payload)
					break
			units[unit_id] = unit_state

		if order_type != OrderSystem.OrderType.MOVE and order_type != OrderSystem.OrderType.ATTACK and order_type != OrderSystem.OrderType.DIG_IN:
			_add_anomaly(trace_anomalies, turn_trace, "invalid_order", {
				"reason": "unknown order type",
				"unit_id": unit_id,
				"order_type": order_type
			})
			continue

		if order_type == OrderSystem.OrderType.DIG_IN:
			var was_dug_in := bool(unit_state.get("dug_in", false))
			unit_state["dug_in"] = true
			unit_state["entrenched"] = true
			units[unit_id] = unit_state
			var dig_in_payload := {
				"unit_id": unit_id,
				"hex": _hex_to_dict(unit_state.get("hex", Vector2i.ZERO)),
				"was_dug_in": was_dug_in,
				"is_dug_in": true,
				"is_entrenched": true
			}
			_add_trace_event(trace_events, turn_trace, "dig_in_applied", dig_in_payload)
			combat_log.add_entry("%s dug in at %d,%d." % [unit_id, int(dig_in_payload["hex"]["q"]), int(dig_in_payload["hex"]["r"])], dig_in_payload)
			continue

		if order_type == OrderSystem.OrderType.ATTACK:
			var target_id := String(order.get("target_unit_id", ""))
			if target_id.is_empty() or not units.has(target_id):
				_add_anomaly(trace_anomalies, turn_trace, "missing_unit", {
					"reason": "attack target unit is missing",
					"unit_id": unit_id,
					"target_unit_id": target_id
				})
				continue
			var target := units[target_id] as Dictionary
			if not Pathfinding.are_adjacent(unit_state.get("hex", Vector2i.ZERO), target.get("hex", Vector2i.ZERO)):
				_add_anomaly(trace_anomalies, turn_trace, "illegal_attack_range", {
					"unit_id": unit_id,
					"target_unit_id": target_id,
					"attacker_hex": _hex_to_dict(unit_state.get("hex", Vector2i.ZERO)),
					"target_hex": _hex_to_dict(target.get("hex", Vector2i.ZERO))
				})
				continue

			var recon := ReconSystem.resolve_recon(unit_state, target, 0, rng)
			known_enemy_units.append(target_id)
			var rng_state_before := str(rng.state)
			var enemy_losses := rng.randi_range(1, 12)
			var own_a_losses := rng.randi_range(0, 4)
			var own_b_losses := rng.randi_range(0, 4)
			var rng_state_after := str(rng.state)

			enemy_casualties.append({"unit_id": target_id, "losses": enemy_losses})
			own_casualties.append({
				"unit_id": unit_id,
				"children": [
					{"unit_id": unit_id, "segment": "A", "losses": own_a_losses},
					{"unit_id": unit_id, "segment": "B", "losses": own_b_losses}
				]
			})

			var attack_payload := {
				"unit_id": unit_id,
				"target_unit_id": target_id,
				"recon_band": recon.get("band", "Unknown"),
				"rng_seed": rng_seed,
				"rng_state_before": rng_state_before,
				"rng_state_after": rng_state_after
			}
			_add_trace_event(trace_events, turn_trace, "attack_resolved", attack_payload)
			_add_trace_event(trace_events, turn_trace, "casualties_generated", {
				"unit_id": unit_id,
				"target_unit_id": target_id,
				"enemy_losses": enemy_losses,
				"own_losses": {"A": own_a_losses, "B": own_b_losses},
				"own_casualties_by_unit_id": {
					unit_id: {
						"total_losses": own_a_losses + own_b_losses,
						"segments": {"A": own_a_losses, "B": own_b_losses}
					}
				}
			})
			combat_log.add_entry("%s attacked %s (%s)." % [unit_id, target_id, recon.get("band", "Unknown")], attack_payload)

	_detect_unexpected_state_mutations(base_units, units, turn_trace, trace_anomalies)

	return {
		"units": units,
		"execution_queue": execution_queue,
		"known_enemy_units": known_enemy_units,
		"own_casualties": own_casualties,
		"enemy_casualties": enemy_casualties,
		"trace_id": String(turn_trace.get("trace_id", "")),
		"session_id": String(turn_trace.get("session_id", "")),
		"rng_seed": rng_seed,
		"scout_intel_by_observer": updated_scout_intel_by_observer,
		"trace_events": trace_events,
		"trace_anomalies": trace_anomalies
	}

static func _resolve_active_owner(order_list: Array[Dictionary], units: Dictionary, fallback_owner: int = 0) -> int:
	for order in order_list:
		var unit_id := String(order.get("unit_id", ""))
		if unit_id.is_empty() or not units.has(unit_id):
			continue
		var unit_state := units[unit_id] as Dictionary
		return int(unit_state.get("owner", 0))
	return fallback_owner

static func _initiative_score(order: Dictionary, units: Dictionary) -> int:
	var unit := units.get(order.get("unit_id", ""), {}) as Dictionary
	var base := int(unit.get("initiative", 50))
	var path := order.get("path", []) as Array[Vector2i]
	return base - path.size()

static func _is_enemy_adjacent(hex: Vector2i, owner: int, units: Dictionary) -> bool:
	for unit in units.values():
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		if not GameState.is_unit_alive(unit):
			continue
		if int(unit.get("owner", owner)) == owner:
			continue
		if Pathfinding.are_adjacent(hex, unit.get("hex", Vector2i.ZERO)):
			return true
	return false

static func _resolve_turn_trace_context(orders: Dictionary, trace_context: Dictionary) -> Dictionary:
	var context := trace_context.duplicate(true)
	var trace_id := String(context.get("trace_id", ""))
	var session_id := String(context.get("session_id", ""))

	if trace_id.is_empty() or session_id.is_empty():
		for order in orders.values():
			if typeof(order) != TYPE_DICTIONARY:
				continue
			if trace_id.is_empty():
				trace_id = String((order as Dictionary).get("trace_id", ""))
			if session_id.is_empty():
				session_id = String((order as Dictionary).get("session_id", ""))
			if not trace_id.is_empty() and not session_id.is_empty():
				break

	var now_unix := int(Time.get_unix_time_from_system())
	if session_id.is_empty():
		session_id = "session_%d" % now_unix
	if trace_id.is_empty():
		trace_id = session_id
	var doctrine := MatchSetupTypes.sanitize_ai_doctrine(context.get("ai_doctrine", GameState.selected_ai_doctrine))
	var difficulty := MatchSetupTypes.sanitize_difficulty(context.get("difficulty", GameState.selected_difficulty))
	return {
		"trace_id": trace_id,
		"session_id": session_id,
		"rng_seed": int(context.get("rng_seed", 0)),
		"ai_doctrine": doctrine,
		"difficulty": difficulty,
		"ai_doctrine_overridden": context.has("ai_doctrine"),
		"difficulty_overridden": context.has("difficulty")
	}

static func _add_trace_event(trace_events: Array[Dictionary], trace_context: Dictionary, event_type: String, payload: Dictionary) -> void:
	trace_events.append({
		"timestamp_unix": Time.get_unix_time_from_system(),
		"type": event_type,
		"trace_id": String(trace_context.get("trace_id", "")),
		"session_id": String(trace_context.get("session_id", "")),
		"payload": payload.duplicate(true)
	})

static func _add_anomaly(trace_anomalies: Array[Dictionary], trace_context: Dictionary, code: String, details: Dictionary) -> void:
	trace_anomalies.append({
		"timestamp_unix": Time.get_unix_time_from_system(),
		"code": code,
		"trace_id": String(trace_context.get("trace_id", "")),
		"session_id": String(trace_context.get("session_id", "")),
		"details": details.duplicate(true)
	})

static func _detect_unexpected_state_mutations(base_units: Dictionary, resolved_units: Dictionary, trace_context: Dictionary, anomalies: Array[Dictionary]) -> void:
	if base_units.keys().size() != resolved_units.keys().size():
		_add_anomaly(anomalies, trace_context, "unexpected_state_mutation", {
			"reason": "unit count changed during resolve_turn",
			"base_count": base_units.keys().size(),
			"resolved_count": resolved_units.keys().size()
		})
	for unit_id in base_units.keys():
		if not resolved_units.has(unit_id):
			_add_anomaly(anomalies, trace_context, "unexpected_state_mutation", {
				"reason": "unit missing after resolve_turn",
				"unit_id": String(unit_id)
			})
			continue
		var before := base_units[unit_id] as Dictionary
		var after := resolved_units[unit_id] as Dictionary
		for key in before.keys():
			if String(key) == "hex":
				continue
			if not after.has(key):
				_add_anomaly(anomalies, trace_context, "unexpected_state_mutation", {
					"reason": "unit key removed",
					"unit_id": String(unit_id),
					"key": String(key)
				})
				continue
			if before.get(key) != after.get(key):
				_add_anomaly(anomalies, trace_context, "unexpected_state_mutation", {
					"reason": "unit field mutated outside expected movement",
					"unit_id": String(unit_id),
					"key": String(key),
					"before": before.get(key),
					"after": after.get(key)
				})

static func _hex_to_dict(hex: Vector2i) -> Dictionary:
	return {"q": hex.x, "r": hex.y}

static func _validate_destination_stack(units: Dictionary, moving_unit_id: String, moving_unit: Dictionary, target_hex: Vector2i) -> Dictionary:
	var occupants: Array[Dictionary] = []
	for candidate_id in units.keys():
		if String(candidate_id) == moving_unit_id:
			continue
		var candidate := units[candidate_id] as Dictionary
		if not GameState.is_unit_alive(candidate):
			continue
		if int(candidate.get("owner", -1)) != int(moving_unit.get("owner", -1)):
			continue
		if (candidate.get("hex", Vector2i.ZERO) as Vector2i) != target_hex:
			continue
		occupants.append(candidate)
	return Rules.can_enter_stack(moving_unit, occupants)
