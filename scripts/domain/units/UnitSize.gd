class_name UnitSize
extends RefCounted

enum Value {
	PLATOON,
	COMPANY,
	BATTALION,
	REGIMENT,
	DIVISION,
	ARMY,
}

const _DISPLAY_NAMES := {
	Value.PLATOON: "Platoon",
	Value.COMPANY: "Company",
	Value.BATTALION: "Battalion",
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
