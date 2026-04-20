class_name Veterancy
extends RefCounted

enum Value {
	CONSCRIPT,
	GREEN,
	REGULAR,
	VETERAN,
	HARDENED,
}

const _DISPLAY_NAMES := {
	Value.CONSCRIPT: "Conscript",
	Value.GREEN: "Green",
	Value.REGULAR: "Regular",
	Value.VETERAN: "Veteran",
	Value.HARDENED: "Hardened",
}

static func display_name(level: Value) -> String:
	return _DISPLAY_NAMES.get(level, "Unknown")
