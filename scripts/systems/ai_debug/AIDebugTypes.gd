class_name AIDebugTypes
extends RefCounted

enum DebugLevel {
	OFF,
	L1,
	L2,
	L3
}

const DEBUG_LEVEL_LABELS := {
	DebugLevel.OFF: "OFF",
	DebugLevel.L1: "L1",
	DebugLevel.L2: "L2",
	DebugLevel.L3: "L3"
}

static func gameplay_debug_to_ai_level(gameplay_debug_level: int) -> int:
	return clampi(gameplay_debug_level, DebugLevel.L1, DebugLevel.L3)

const REQUIRED_TRACE_FIELDS := [
	"trace_id",
	"timestamp_unix",
	"phase",
	"turn",
	"player_id",
	"ai_version",
	"debug_level",
	"inputs_hash",
	"events",
	"line_log_path",
	"outputs",
	"anomalies",
	"timings_ms"
]

static func make_trace_contract(
	trace_id: String,
	timestamp_unix: int,
	phase: String,
	turn: int,
	player_id: int,
	ai_version: String,
	debug_level: int,
	inputs_hash: String
) -> Dictionary:
	return {
		"trace_id": trace_id,
		"timestamp_unix": timestamp_unix,
		"phase": phase,
		"turn": turn,
		"player_id": player_id,
		"ai_version": ai_version,
		"debug_level": debug_level,
		"inputs_hash": inputs_hash,
		"events": [],
		"outputs": {},
		"anomalies": [],
		"timings_ms": {}
	}

static func has_required_fields(trace: Dictionary) -> bool:
	for field_name in REQUIRED_TRACE_FIELDS:
		if not trace.has(field_name):
			return false
	return true
