extends Node

const MAX_PLAYERS := 2
const MIN_POINT_LIMIT := 100
const MAX_POINT_LIMIT := 5000
const STACK_LIMIT_COMPANY_EQUIVALENTS := 4.0

const UnitSize = preload("res://scripts/domain/units/UnitSize.gd")

func is_valid_player_count(player_count: int) -> bool:
	return player_count >= 1 and player_count <= MAX_PLAYERS

func is_valid_points_limit(points: int) -> bool:
	return points >= MIN_POINT_LIMIT and points <= MAX_POINT_LIMIT

func can_advance_from_phase(current_phase: GameState.Phase, target_phase: GameState.Phase) -> bool:
	return int(target_phase) >= int(current_phase)

static func can_enter_stack(moving_unit: Dictionary, occupants: Array[Dictionary]) -> Dictionary:
	var projected := occupants.duplicate()
	projected.append(moving_unit)
	return validate_stack(projected)

static func validate_stack(units_in_hex: Array[Dictionary]) -> Dictionary:
	var total_company_equivalents := 0.0
	var battalion_count := 0
	var non_battalion_count := 0

	for unit in units_in_hex:
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		if not GameState.is_unit_alive(unit):
			continue
		var size_value := _unit_size_value(unit)
		if size_value == UnitSize.Value.BATTALION:
			battalion_count += 1
		else:
			non_battalion_count += 1
		total_company_equivalents += _company_equivalent_for_size(size_value)

	if battalion_count > 0 and non_battalion_count > 0:
		return {
			"ok": false,
			"reason": "Battalions cannot stack with other unit sizes."
		}

	if total_company_equivalents > STACK_LIMIT_COMPANY_EQUIVALENTS:
		return {
			"ok": false,
			"reason": "Stack exceeds %.0f company-equivalents." % STACK_LIMIT_COMPANY_EQUIVALENTS
		}

	return {"ok": true, "reason": ""}

static func _company_equivalent_for_size(size_value: int) -> float:
	if size_value <= UnitSize.Value.COMPANY:
		return 1.0
	if size_value == UnitSize.Value.BATTALION:
		return STACK_LIMIT_COMPANY_EQUIVALENTS
	return STACK_LIMIT_COMPANY_EQUIVALENTS

static func _unit_size_value(unit: Dictionary) -> int:
	if unit.has("size_value"):
		return int(unit.get("size_value", UnitSize.Value.COMPANY))
	var formation_size := String(unit.get("formation_size", unit.get("size", "company"))).strip_edges().to_lower()
	match formation_size:
		"squad":
			return UnitSize.Value.SQUAD
		"section":
			return UnitSize.Value.SECTION
		"platoon":
			return UnitSize.Value.PLATOON
		"company":
			return UnitSize.Value.COMPANY
		"battalion":
			return UnitSize.Value.BATTALION
		"regiment":
			return UnitSize.Value.REGIMENT
		"division":
			return UnitSize.Value.DIVISION
		"army":
			return UnitSize.Value.ARMY
	return UnitSize.Value.COMPANY
