class_name AIDebugTracer
extends RefCounted

const DEFAULT_AI_VERSION := "unknown"
const DEFAULT_PHASE := "unknown"
const DEFAULT_INPUTS_HASH := ""


func start_trace(context: Dictionary) -> Dictionary:
	var trace_id: String = str(context.get("trace_id", ""))
	if trace_id.is_empty():
		trace_id = make_deterministic_id(context)

	var timestamp_unix: int = int(context.get("timestamp_unix", _capture_timestamp_unix()))
	var phase: String = str(context.get("phase", DEFAULT_PHASE))
	var turn: int = int(context.get("turn", -1))
	var player_id: int = int(context.get("player_id", -1))
	var ai_version: String = str(context.get("ai_version", DEFAULT_AI_VERSION))
	var debug_level: int = int(context.get("debug_level", AIDebugTypes.DebugLevel.NORMAL))
	var inputs_hash: String = str(context.get("inputs_hash", DEFAULT_INPUTS_HASH))

	return AIDebugTypes.make_trace_contract(
		trace_id,
		timestamp_unix,
		phase,
		turn,
		player_id,
		ai_version,
		debug_level,
		inputs_hash
	)


func add_event(trace: Dictionary, event_type: String, payload: Dictionary) -> void:
	if _should_drop_event(trace, payload):
		return

	var normalized_event := _normalize_event_shape(event_type, payload)
	normalized_event["timestamp_unix"] = _capture_timestamp_unix()
	trace["events"].append(normalized_event)


func add_anomaly(trace: Dictionary, code: String, details: Dictionary) -> void:
	trace["anomalies"].append({
		"code": code,
		"details": details.duplicate(true),
		"timestamp_unix": _capture_timestamp_unix()
	})


func finish_trace(trace: Dictionary, outputs: Dictionary, timings: Dictionary) -> Dictionary:
	var final_trace: Dictionary = trace.duplicate(true)
	final_trace["outputs"] = outputs.duplicate(true)
	final_trace["timings_ms"] = timings.duplicate(true)
	final_trace["completed_timestamp_unix"] = _capture_timestamp_unix()
	final_trace["event_count"] = final_trace.get("events", []).size()
	final_trace["anomaly_count"] = final_trace.get("anomalies", []).size()
	return final_trace


static func make_deterministic_id(context: Dictionary) -> String:
	var stable_input: String = _stable_serialize_value(context)
	return str(stable_input.sha256_text().substr(0, 16))


static func _capture_timestamp_unix() -> int:
	return Time.get_unix_time_from_system()


func _should_drop_event(trace: Dictionary, payload: Dictionary) -> bool:
	var event_level: int = _normalize_debug_level(
		int(payload.get("debug_level", AIDebugTypes.DebugLevel.NORMAL))
	)
	var trace_level: int = _normalize_debug_level(
		int(trace.get("debug_level", AIDebugTypes.DebugLevel.NORMAL))
	)
	return trace_level < event_level


func _normalize_debug_level(raw_level: int) -> int:
	return clampi(raw_level, AIDebugTypes.DebugLevel.OFF, AIDebugTypes.DebugLevel.VERBOSE)


func _normalize_event_shape(event_type: String, payload: Dictionary) -> Dictionary:
	return {
		"type": event_type,
		"stage": str(payload.get("stage", "")),
		"unit_id": int(payload.get("unit_id", -1)),
		"candidate_id": int(payload.get("candidate_id", -1)),
		"reason_code": str(payload.get("reason_code", "")),
		"reason_text": str(payload.get("reason_text", "")),
		"score": float(payload.get("score", 0.0)),
		"meta": payload.get("meta", {}).duplicate(true)
	}


static func _stable_serialize_value(value: Variant) -> String:
	if value is Dictionary:
		return _stable_serialize_dictionary(value)
	if value is Array:
		return _stable_serialize_array(value)
	return JSON.stringify(value)


static func _stable_serialize_dictionary(dict: Dictionary) -> String:
	var keys: Array = dict.keys()
	keys.sort()

	var parts: Array[String] = []
	for key in keys:
		var serialized_key := JSON.stringify(key)
		var serialized_value := _stable_serialize_value(dict[key])
		parts.append("%s:%s" % [serialized_key, serialized_value])

	return "{%s}" % [",".join(parts)]


static func _stable_serialize_array(values: Array) -> String:
	var parts: Array[String] = []
	for item in values:
		parts.append(_stable_serialize_value(item))
	return "[%s]" % [",".join(parts)]
