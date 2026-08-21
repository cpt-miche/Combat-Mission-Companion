class_name DeploymentTypes
extends RefCounted

const TERRAIN_HIGHWAY := "highway"
const TERRAIN_ROAD := "road"
const TERRAIN_LIGHT := "light"
const TERRAIN_MEDIUM := "medium"
const TERRAIN_HEAVY := "heavy"
const TERRAIN_WOODS := "woods"
const TERRAIN_URBAN := "urban"

# Planner-compatible unit role names.
const ROLE_INFANTRY := "infantry"
const ROLE_ARMOR := "armor"
const ROLE_RECON := "recon"
const ROLE_AIR_DEFENSE := "airDefense"
const ROLE_ANTI_TANK_SUPPORT := "antiTankSupport"
const ROLE_ARTILLERY_SUPPORT := "artillerySupport"
const ROLE_WEAPONS := "weapons"
const ROLE_MOBILITY := "mobility"
const ROLE_COMMAND := "command"

# Dictionary contract helpers used by planner conversion code.

static func make_hex(
	hex_id: String,
	q: int,
	r: int,
	terrain: String,
	owner: int,
	neighbor_ids: Array[String]
) -> Dictionary:
	return {
		"id": hex_id,
		"q": q,
		"r": r,
		"terrain": terrain,
		"owner": owner,
		"neighborIds": neighbor_ids
	}

static func make_formation(
	formation_id: String,
	name: String,
	unit_type: String,
	size: String,
	parent_id: String,
	child_ids: Array[String],
	status: String = "alive"
) -> Dictionary:
	return {
		"id": formation_id,
		"name": name,
		"type": unit_type,
		"size": size,
		"parentId": parent_id,
		"childIds": child_ids,
		"status": status
	}

static func make_deployable_element(
	element_id: String,
	player_index: int,
	name: String,
	role: String,
	size: String,
	formation_id: String,
	hex_id: String,
	status: String = "alive"
) -> Dictionary:
	return {
		"id": element_id,
		"playerIndex": player_index,
		"name": name,
		"role": role,
		"size": size,
		"formationId": formation_id,
		"hexId": hex_id,
		"status": status
	}

static func make_ai_objective(
	objective_id: String,
	objective_type: String,
	priority: int,
	target_hex_id: String,
	details: Dictionary = {}
) -> Dictionary:
	return {
		"id": objective_id,
		"type": objective_type,
		"priority": priority,
		"targetHexId": target_hex_id,
		"details": details.duplicate(true)
	}

static func make_unit_order(
	order_id: String,
	unit_id: String,
	order_type: String,
	from_hex_id: String,
	to_hex_id: String,
	objective_id: String = ""
) -> Dictionary:
	return {
		"id": order_id,
		"unitId": unit_id,
		"type": order_type,
		"fromHexId": from_hex_id,
		"toHexId": to_hex_id,
		"objectiveId": objective_id
	}

static func make_deployment_plan(
	elements: Array[Dictionary],
	objectives: Array[Dictionary],
	orders: Array[Dictionary],
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"elements": elements.duplicate(true),
		"objectives": objectives.duplicate(true),
		"orders": orders.duplicate(true),
		"metadata": metadata.duplicate(true)
	}
