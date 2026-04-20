class_name UnitType
extends RefCounted

enum Value {
	INFANTRY,
	TANK,
	ENGINEER,
	ARTILLERY,
	RECON,
	AIRBORNE,
	MECHANIZED,
	MOTORIZED,
	ANTI_TANK,
	AIR_DEFENSE,
	HEADQUARTERS,
}

const _DISPLAY_NAMES := {
	Value.INFANTRY: "Infantry",
	Value.TANK: "Tank",
	Value.ENGINEER: "Engineer",
	Value.ARTILLERY: "Artillery",
	Value.RECON: "Recon",
	Value.AIRBORNE: "Airborne",
	Value.MECHANIZED: "Mechanized",
	Value.MOTORIZED: "Motorized",
	Value.ANTI_TANK: "Anti-Tank",
	Value.AIR_DEFENSE: "Air Defense",
	Value.HEADQUARTERS: "Headquarters",
}

static func display_name(unit_type: Value) -> String:
	return _DISPLAY_NAMES.get(unit_type, "Unknown")
