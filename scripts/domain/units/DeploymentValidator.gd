extends RefCounted
class_name DeploymentValidator

static func can_deploy_in_territory(territory_owner: int, player_index: int) -> bool:
	if player_index == 0:
		return territory_owner == GameState.TerritoryOwnership.PLAYER_1
	return territory_owner == GameState.TerritoryOwnership.PLAYER_2

static func can_place_unit(unit: Dictionary, existing_units: Array[Dictionary]) -> bool:
	return placement_block_reason(unit, existing_units).is_empty()

static func placement_block_reason(unit: Dictionary, existing_units: Array[Dictionary]) -> String:
	var is_tank := bool(unit.get("is_tank", false))
	var is_battalion := bool(unit.get("is_battalion", false))
	var is_company := bool(unit.get("is_company", false))
	var unit_name := String(unit.get("name", unit.get("id", "Unit")))

	if is_tank:
		if not is_battalion:
			return "%s is a tank but not a battalion, and cannot be deployed." % unit_name
		for placed in existing_units:
			if bool(placed.get("is_tank", false)) and bool(placed.get("is_battalion", false)):
				return "Tank battalion limit reached (max 1)."
		return ""

	var non_tank_battalion_count := 0
	var non_tank_company_count := 0
	for placed in existing_units:
		if bool(placed.get("is_tank", false)):
			continue
		if bool(placed.get("is_battalion", false)):
			non_tank_battalion_count += 1
		elif bool(placed.get("is_company", false)):
			non_tank_company_count += 1

	if is_battalion:
		if non_tank_battalion_count >= 1:
			return "Non-tank battalion limit reached (max 1)."
		if non_tank_company_count > 0:
			return "Cannot place a non-tank battalion after non-tank companies are deployed."
		return ""

	if is_company:
		if non_tank_battalion_count > 0:
			return "Cannot place non-tank companies after a non-tank battalion is deployed."
		if non_tank_company_count >= 3:
			return "Non-tank company limit reached (max 3)."
		return ""

	return "%s is not a deployable battalion or company under current deployment rules." % unit_name
