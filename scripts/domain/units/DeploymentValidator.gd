extends RefCounted
class_name DeploymentValidator

static func can_deploy_in_territory(territory_owner: int, player_index: int) -> bool:
	if player_index == 0:
		return territory_owner == GameState.TerritoryOwnership.PLAYER_1
	return territory_owner == GameState.TerritoryOwnership.PLAYER_2

static func can_place_unit(unit: Dictionary, existing_units: Array[Dictionary]) -> bool:
	return placement_block_reason(unit, existing_units).is_empty()

static func placement_block_reason(unit: Dictionary, existing_units: Array[Dictionary]) -> String:
	var unit_size := String(unit.get("size", "")).to_lower()
	var is_headquarters := bool(unit.get("is_headquarters", false))
	var is_battalion := bool(unit.get("is_battalion", unit_size == "battalion"))
	var is_company := bool(unit.get("is_company", unit_size == "company"))
	var is_platoon := bool(unit.get("is_platoon", unit_size == "platoon"))
	var size_rank := int(unit.get("size_rank", _fallback_size_rank(unit_size)))
	var unit_name := String(unit.get("name", unit.get("id", "Unit")))
	var status := String(unit.get("status", "")).to_lower()
	var is_alive := bool(unit.get("is_alive", status != "dead"))

	if not status.is_empty() and status == "dead":
		return "%s is dead and cannot be deployed." % unit_name
	if status.is_empty() and not is_alive:
		return "%s is dead and cannot be deployed." % unit_name

	if is_headquarters:
		return "%s is a headquarters unit and cannot be deployed directly." % unit_name

	if size_rank < UnitSize.Value.PLATOON:
		return "%s is below platoon level and cannot be deployed directly." % unit_name

	if size_rank > UnitSize.Value.BATTALION:
		return "%s is a parent formation (regiment/division/army) and cannot be deployed directly. Deploy one of its battalions, companies, or platoons instead." % unit_name

	var battalion_count := _placed_battalion_count(existing_units)
	var company_count := _placed_company_count(existing_units)

	if is_battalion:
		if battalion_count >= 1:
			return "Battalion limit reached (max 1)."
		if company_count > 0:
			return "Cannot place a battalion after companies are deployed in this hex."
		return ""

	if is_company:
		if battalion_count > 0:
			return "Cannot place a company when a battalion is already deployed in this hex."
		if company_count >= 4:
			return "Company limit reached (max 4)."
		return ""

	if is_platoon:
		return ""

	return "%s is not deployable under current deployment rules." % unit_name

static func _fallback_size_rank(unit_size: String) -> int:
	match unit_size:
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
		_:
			return -1

static func _placed_battalion_count(existing_units: Array[Dictionary]) -> int:
	var count := 0
	for placed in existing_units:
		if bool(placed.get("is_battalion", String(placed.get("size", "")).to_lower() == "battalion")):
			count += 1
	return count

static func _placed_company_count(existing_units: Array[Dictionary]) -> int:
	var count := 0
	for placed in existing_units:
		if bool(placed.get("is_company", String(placed.get("size", "")).to_lower() == "company")):
			count += 1
	return count
