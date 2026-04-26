class_name AIDebugTypes
extends RefCounted

enum DebugLevel {
	OFF,
	ERROR,
	NORMAL,
	VERBOSE
}

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
