extends RefCounted
class_name AITraceReplay

const DeploymentPlanner = preload("res://scripts/systems/deployment_ai/DeploymentPlanner.gd")

const SUPPORTED_PHASE := "deployment_ai"

static func replay_trace_file(path: String) -> Dictionary:
	var parsed := _read_json_file(path)
	if parsed.is_empty():
		return {
			"ok": false,
			"error": "trace_file_unreadable",
			"path": path
		}
	return replay_trace(parsed)

static func replay_trace(trace: Dictionary) -> Dictionary:
	var phase: String = String(trace.get("phase", ""))
	if phase != SUPPORTED_PHASE:
		return {
			"ok": false,
			"error": "unsupported_phase",
			"phase": phase,
			"supported": [SUPPORTED_PHASE]
		}

	var reconstruction := _reconstruct_deployment_inputs(trace)
	if not bool(reconstruction.get("ok", false)):
		return reconstruction

	var tracer_events: Array[Dictionary] = []
	var options: Dictionary = {
		"objectiveMode": String(reconstruction.get("objectiveMode", "mixed_split")),
		"traceEventCallback": func(event_type: String, payload: Dictionary) -> void:
			tracer_events.append(_normalize_event_for_compare(event_type, payload))
	}
	var plan := DeploymentPlanner.create_plan(
		reconstruction.get("elements", []) as Array[Dictionary],
		reconstruction.get("hexes", []) as Array[Dictionary],
		reconstruction.get("sectorModel", {}) as Dictionary,
		options
	)

	var expected_events := _normalize_events_from_trace(trace)
	var actual_events := tracer_events
	var diff := _diff_events_and_orders(expected_events, actual_events, trace, plan)

	return {
		"ok": true,
		"phase": phase,
		"inputs": {
			"elements": (reconstruction.get("elements", []) as Array).size(),
			"hexes": (reconstruction.get("hexes", []) as Array).size(),
			"objectiveMode": reconstruction.get("objectiveMode", "mixed_split")
		},
		"expected_count": expected_events.size(),
		"actual_count": actual_events.size(),
		"diff": diff,
		"report": _format_diff_report(diff)
	}

static func _reconstruct_deployment_inputs(trace: Dictionary) -> Dictionary:
	var outputs: Dictionary = trace.get("outputs", {}) as Dictionary
	if outputs.is_empty():
		return {"ok": false, "error": "missing_outputs"}

	var plan: Dictionary = outputs.get("plan", {}) as Dictionary
	var elements: Array = plan.get("elements", []) as Array
	if elements.is_empty():
		return {"ok": false, "error": "missing_plan_elements"}

	var sector_model: Dictionary = outputs.get("sectorModel", {}) as Dictionary
	if sector_model.is_empty():
		return {"ok": false, "error": "missing_sector_model"}

	var all_hex_ids := _collect_hex_ids(sector_model)
	if all_hex_ids.is_empty():
		return {"ok": false, "error": "missing_hex_candidates"}

	var hexes := _build_hexes_from_sector_model(all_hex_ids, sector_model)
	return {
		"ok": true,
		"elements": _typed_dict_array(elements),
		"hexes": hexes,
		"sectorModel": sector_model.duplicate(true),
		"objectiveMode": String(outputs.get("objectiveMode", (plan.get("metadata", {}) as Dictionary).get("objectiveMode", "mixed_split")))
	}

static func _typed_dict_array(values: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		output.append((value as Dictionary).duplicate(true))
	return output

static func _collect_hex_ids(sector_model: Dictionary) -> Array[String]:
	var ids := {}
	for value in (sector_model.get("frontlineHexes", []) as Array):
		ids[String(value)] = true
	for value in (sector_model.get("contestedArea", []) as Array):
		ids[String(value)] = true
	for value in (sector_model.get("rearArea", []) as Array):
		ids[String(value)] = true
	for key_variant in (sector_model.get("hexScores", {}) as Dictionary).keys():
		ids[String(key_variant)] = true

	var sorted: Array[String] = []
	for hex_id in ids.keys():
		sorted.append(String(hex_id))
	sorted.sort()
	return sorted

static func _build_hexes_from_sector_model(hex_ids: Array[String], _sector_model: Dictionary) -> Array[Dictionary]:
	var known_hexes := {}
	for hex_id in hex_ids:
		known_hexes[hex_id] = true

	var output: Array[Dictionary] = []
	for hex_id in hex_ids:
		var coords := _parse_axial_id(hex_id)
		var neighbor_ids: Array[String] = []
		for delta in _axial_neighbor_deltas():
			var neighbor_coord := coords + delta
			var neighbor_id := "%d,%d" % [neighbor_coord.x, neighbor_coord.y]
			if known_hexes.has(neighbor_id):
				neighbor_ids.append(neighbor_id)
		output.append({
			"id": hex_id,
			"q": coords.x,
			"r": coords.y,
			"terrain": "open",
			"owner": 0,
			"neighborIds": neighbor_ids
		})
	return output

static func _axial_neighbor_deltas() -> Array[Vector2i]:
	return [
		Vector2i(1, 0),
		Vector2i(1, -1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1)
	]

static func _parse_axial_id(hex_id: String) -> Vector2i:
	var parts := hex_id.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

static func _normalize_events_from_trace(trace: Dictionary) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	for raw_event in (trace.get("events", []) as Array):
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw_event as Dictionary
		var meta: Dictionary = event.get("meta", {}) as Dictionary
		normalized.append({
			"type": String(event.get("type", "")),
			"stage": String(event.get("stage", "")),
			"reason_code": String(event.get("reason_code", "")),
			"score": _round_score(float(event.get("score", 0.0))),
			"unitId": String(meta.get("unitId", "")),
			"candidateId": String(meta.get("candidateId", ""))
		})
	return normalized

static func _normalize_event_for_compare(event_type: String, payload: Dictionary) -> Dictionary:
	var meta: Dictionary = payload.get("meta", {}) as Dictionary
	return {
		"type": event_type,
		"stage": String(payload.get("stage", "")),
		"reason_code": String(payload.get("reason_code", "")),
		"score": _round_score(float(payload.get("score", 0.0))),
		"unitId": String(meta.get("unitId", "")),
		"candidateId": String(meta.get("candidateId", ""))
	}

static func _round_score(score: float) -> float:
	return roundf(score * 1000.0) / 1000.0

static func _diff_events_and_orders(expected_events: Array[Dictionary], actual_events: Array[Dictionary], expected_trace: Dictionary, actual_plan: Dictionary) -> Dictionary:
	var missing_events: Array[Dictionary] = []
	var unexpected_events: Array[Dictionary] = []
	var different_orders: Array[Dictionary] = []
	var changed_scores: Array[Dictionary] = []

	var compare_len := mini(expected_events.size(), actual_events.size())
	for i in range(compare_len):
		var expected: Dictionary = expected_events[i]
		var actual: Dictionary = actual_events[i]
		if _event_identity(expected) != _event_identity(actual):
			different_orders.append({
				"index": i,
				"expected": expected,
				"actual": actual
			})
		if not is_equal_approx(float(expected.get("score", 0.0)), float(actual.get("score", 0.0))):
			changed_scores.append({
				"index": i,
				"expected": expected.get("score", 0.0),
				"actual": actual.get("score", 0.0),
				"event": _event_identity(expected)
			})

	if expected_events.size() > actual_events.size():
		for i in range(actual_events.size(), expected_events.size()):
			missing_events.append(expected_events[i])
	elif actual_events.size() > expected_events.size():
		for i in range(expected_events.size(), actual_events.size()):
			unexpected_events.append({
				"kind": "event",
				"index": i,
				"actual": actual_events[i]
			})

	var expected_plan: Dictionary = (expected_trace.get("outputs", {}) as Dictionary).get("plan", {}) as Dictionary
	var expected_orders: Array = expected_plan.get("orders", []) as Array
	var actual_orders: Array = actual_plan.get("orders", []) as Array
	var order_compare_len := mini(expected_orders.size(), actual_orders.size())
	for i in range(order_compare_len):
		if _order_identity(expected_orders[i]) != _order_identity(actual_orders[i]):
			different_orders.append({
				"index": i,
				"expected_order": _order_identity(expected_orders[i]),
				"actual_order": _order_identity(actual_orders[i])
			})

	if expected_orders.size() > actual_orders.size():
		for i in range(actual_orders.size(), expected_orders.size()):
			missing_events.append({
				"kind": "order",
				"index": i,
				"expected": _order_identity(expected_orders[i])
			})
	elif actual_orders.size() > expected_orders.size():
		for i in range(expected_orders.size(), actual_orders.size()):
			unexpected_events.append({
				"kind": "order",
				"index": i,
				"actual": _order_identity(actual_orders[i])
			})

	return {
		"missing_events": missing_events,
		"unexpected_events": unexpected_events,
		"changed_scores": changed_scores,
		"different_orders": different_orders,
		"summary": {
			"missing_events": missing_events.size(),
			"unexpected_events": unexpected_events.size(),
			"changed_scores": changed_scores.size(),
			"different_orders": different_orders.size()
		}
	}

static func _event_identity(event: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [
		String(event.get("type", "")),
		String(event.get("stage", "")),
		String(event.get("reason_code", "")),
		String(event.get("unitId", "")),
		String(event.get("candidateId", ""))
	]

static func _order_identity(order_variant: Variant) -> String:
	if typeof(order_variant) != TYPE_DICTIONARY:
		return ""
	var order: Dictionary = order_variant as Dictionary
	return "%s|%s|%s|%s|%s" % [
		String(order.get("stage", "")),
		String(order.get("unitId", order.get("elementId", ""))),
		String(order.get("toHexId", order.get("hexId", ""))),
		String(order.get("role", "")),
		String(order.get("reason_code", ""))
	]

static func _format_diff_report(diff: Dictionary) -> String:
	var summary: Dictionary = diff.get("summary", {}) as Dictionary
	return "missing_events=%d unexpected_events=%d changed_scores=%d different_orders=%d" % [
		int(summary.get("missing_events", 0)),
		int(summary.get("unexpected_events", 0)),
		int(summary.get("changed_scores", 0)),
		int(summary.get("different_orders", 0))
	]

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
