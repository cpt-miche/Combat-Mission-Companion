class_name AIDebugFormatter
extends RefCounted

const AIDebugTypes = preload("res://scripts/systems/ai_debug/AIDebugTypes.gd")

static func debug_level_label(level: int) -> String:
	match level:
		AIDebugTypes.DebugLevel.L1:
			return "L1"
		AIDebugTypes.DebugLevel.L2:
			return "L2"
		AIDebugTypes.DebugLevel.L3:
			return "L3"
		_:
			return "OFF"

static func format_trace_lines(trace: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var level: int = int(trace.get("debug_level", AIDebugTypes.DebugLevel.OFF))
	if level <= AIDebugTypes.DebugLevel.OFF:
		return lines

	for event_variant in (trace.get("events", []) as Array):
		if typeof(event_variant) != TYPE_DICTIONARY:
			continue
		var event := event_variant as Dictionary
		lines.append(_format_event_line(trace, event, level))
	return lines

static func _format_event_line(trace: Dictionary, event: Dictionary, level: int) -> String:
	var timestamp: int = int(event.get("timestamp_unix", trace.get("timestamp_unix", 0)))
	var unit_id: int = int(event.get("unit_id", -1))
	var action: String = _action_for_event(event)
	var reason: String = str(event.get("reason_text", event.get("reason_code", "")))
	var details := ""
	if level >= AIDebugTypes.DebugLevel.L2:
		details = _l2_details(event)
	if level >= AIDebugTypes.DebugLevel.L3:
		details = _l3_details(event)

	var base := "[%s] phase=%s turn=%d player=%d unit=%s action=%s reason=%s" % [
		Time.get_datetime_string_from_unix_time(timestamp, true),
		str(trace.get("phase", "unknown")),
		int(trace.get("turn", -1)),
		int(trace.get("player_id", -1)),
		"-" if unit_id < 0 else str(unit_id),
		action,
		reason
	]
	if details.is_empty():
		return base
	return "%s details=%s" % [base, details]

static func _action_for_event(event: Dictionary) -> String:
	var type_name := str(event.get("type", "event"))
	var stage := str(event.get("stage", ""))
	if stage.is_empty():
		return type_name
	return "%s/%s" % [stage, type_name]

static func _l2_details(event: Dictionary) -> String:
	var meta: Dictionary = event.get("meta", {}) as Dictionary
	if meta.is_empty():
		return "score=%.3f" % float(event.get("score", 0.0))
	var pieces: Array[String] = ["score=%.3f" % float(event.get("score", 0.0))]
	for key in ["candidate_count", "selected_index", "factor", "threshold", "tie_breaker"]:
		if meta.has(key):
			pieces.append("%s=%s" % [key, str(meta.get(key))])
	return " ".join(pieces)

static func _l3_details(event: Dictionary) -> String:
	var meta: Dictionary = event.get("meta", {}) as Dictionary
	var payload := {
		"score": float(event.get("score", 0.0)),
		"candidate_id": int(event.get("candidate_id", -1)),
		"reason_code": str(event.get("reason_code", "")),
		"meta": meta
	}
	return JSON.stringify(payload)
