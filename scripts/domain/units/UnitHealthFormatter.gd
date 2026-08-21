class_name UnitHealthFormatter
extends RefCounted

const LIVE_SUB_UNIT_KEYS := ["live_sub_units", "sub_units_alive", "alive_sub_units", "current_sub_units"]
const MAX_SUB_UNIT_KEYS := ["max_sub_units", "sub_units_max", "total_sub_units"]
const HEALTH_KEYS := ["hp", "health", "strength", "current_hp", "current_health"]
const MAX_HEALTH_KEYS := ["max_hp", "max_health", "hp_max", "health_max", "max_strength"]

static func summary(unit: Dictionary) -> String:
	var live_sub_units: Variant = _first_int_for_keys(unit, LIVE_SUB_UNIT_KEYS)
	var max_sub_units: Variant = _first_int_for_keys(unit, MAX_SUB_UNIT_KEYS)
	if live_sub_units != null and max_sub_units != null:
		return "Health: %d/%d sub-units" % [maxi(0, int(live_sub_units)), maxi(0, int(max_sub_units))]

	if _has_any_key(unit, HEALTH_KEYS):
		var health: Variant = _first_int_for_keys(unit, HEALTH_KEYS)
		var max_health: Variant = _first_int_for_keys(unit, MAX_HEALTH_KEYS)
		if max_health != null and int(max_health) > 0:
			return "Health: %d/%d" % [maxi(0, int(health)), maxi(0, int(max_health))]
		return "Health: %d" % maxi(0, int(health))

	if unit.has("steps"):
		return "Health: %d steps" % maxi(0, int(unit.get("steps", 0)))

	var children := _dictionary_children(unit)
	if not children.is_empty():
		var living_children := 0
		for child in children:
			if GameState.is_unit_alive(child):
				living_children += 1
		return "Strength: %d/%d sub-units" % [living_children, children.size()]

	return "Health: %s" % ("Alive" if GameState.is_unit_alive(unit) else "Dead")

static func _dictionary_children(unit: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var children_variant: Variant = unit.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return result
	for child_variant in children_variant as Array:
		if typeof(child_variant) == TYPE_DICTIONARY:
			result.append(child_variant as Dictionary)
	return result

static func _has_any_key(unit: Dictionary, keys: Array) -> bool:
	for key in keys:
		if unit.has(key):
			return true
	return false

static func _first_int_for_keys(unit: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if unit.has(key):
			return int(unit.get(key, 0))
	return null
