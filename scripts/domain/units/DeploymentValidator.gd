extends RefCounted
class_name DeploymentValidator

static func can_deploy_in_territory(territory_owner: int, player_index: int) -> bool:
	if player_index == 0:
		return territory_owner == GameState.TerritoryOwnership.PLAYER_1
	return territory_owner == GameState.TerritoryOwnership.PLAYER_2

static func can_place_unit(unit: Dictionary, existing_units: Array[Dictionary]) -> bool:
	var is_tank := bool(unit.get("is_tank", false))
	var is_battalion := bool(unit.get("is_battalion", false))
	var is_company := bool(unit.get("is_company", false))

	if is_tank:
		if not is_battalion:
			return false
		for placed in existing_units:
			if bool(placed.get("is_tank", false)) and bool(placed.get("is_battalion", false)):
				return false
		return true

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
		return non_tank_battalion_count < 1 and non_tank_company_count == 0

	if is_company:
		return non_tank_battalion_count == 0 and non_tank_company_count < 3

	return false
