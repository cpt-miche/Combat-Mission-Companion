class_name UnitSize
extends RefCounted

enum Value {
	SQUAD = 0,
	SECTION = 1,
	PLATOON = 2,
	COMPANY = 3,
	BATTALION = 4,
	REGIMENT = 5,
	DIVISION = 6,
	ARMY = 7,
}

const _DISPLAY_NAMES := {
	Value.BATTALION: "Battalion",
	Value.COMPANY: "Company",
	Value.PLATOON: "Platoon",
	Value.SECTION: "Section",
	Value.SQUAD: "Squad",
	Value.REGIMENT: "Regiment",
	Value.DIVISION: "Division",
	Value.ARMY: "Army",
}

static func rank(size: Value) -> int:
	return int(size)

static func display_name(size: Value) -> String:
	return _DISPLAY_NAMES.get(size, "Unknown")

static func can_contain(parent_size: Value, child_size: Value) -> bool:
	return rank(parent_size) > rank(child_size)
