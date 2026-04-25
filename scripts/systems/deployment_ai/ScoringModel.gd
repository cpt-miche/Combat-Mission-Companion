extends RefCounted
class_name ScoringModel

const DEFAULT_CONFIG := {
	"combatAssignment": {
		"weights": {
			"roleAffinity": 2.4,
			"terrainSuitability": 2.0,
			"frontlineProximity": 1.5,
			"objectiveFocus": 1.2,
			"enemyPressure": 1.1,
			"supportCoverage": 0.8,
			"supportAlonePenalty": -1.4
		},
		"roleAffinity": {
			"infantry": {"frontline": 1.0, "contested": 0.8, "rear": 0.2},
			"armor": {"frontline": 0.9, "contested": 1.0, "rear": 0.3},
			"recon": {"frontline": 0.7, "contested": 1.0, "rear": 0.4},
			"airDefense": {"frontline": 0.5, "contested": 0.8, "rear": 0.9},
			"antiTankSupport": {"frontline": 0.8, "contested": 0.9, "rear": 0.5},
			"artillerySupport": {"frontline": 0.2, "contested": 0.6, "rear": 1.0},
			"weapons": {"frontline": 0.6, "contested": 0.8, "rear": 0.5},
			"mobility": {"frontline": 0.7, "contested": 0.8, "rear": 0.7},
			"command": {"frontline": 0.1, "contested": 0.4, "rear": 1.0}
		},
		"terrainSuitability": {
			"infantry": {"open": 0.7, "road": 0.6, "rough": 1.0, "urban": 1.0, "river": 0.4},
			"armor": {"open": 1.0, "road": 0.9, "rough": 0.4, "urban": 0.5, "river": 0.2},
			"recon": {"open": 0.9, "road": 0.9, "rough": 0.8, "urban": 0.6, "river": 0.3},
			"airDefense": {"open": 0.7, "road": 0.7, "rough": 0.7, "urban": 0.8, "river": 0.3},
			"antiTankSupport": {"open": 0.8, "road": 0.7, "rough": 0.7, "urban": 0.9, "river": 0.4},
			"artillerySupport": {"open": 0.8, "road": 0.8, "rough": 0.6, "urban": 0.5, "river": 0.3},
			"weapons": {"open": 0.7, "road": 0.7, "rough": 0.8, "urban": 0.8, "river": 0.4},
			"mobility": {"open": 0.8, "road": 1.0, "rough": 0.7, "urban": 0.6, "river": 0.4},
			"command": {"open": 0.5, "road": 0.8, "rough": 0.4, "urban": 0.9, "river": 0.3}
		}
	},
	"supportAttachment": {
		"weights": {
			"roleAffinity": 1.8,
			"distance": 1.2,
			"threatMatch": 1.0,
			"coverage": 0.9,
			"supportAlonePenalty": -1.8
		},
		"roleAffinity": {
			"airDefense": {"armor": 1.0, "artillerySupport": 0.9, "infantry": 0.8},
			"antiTankSupport": {"infantry": 1.0, "armor": 0.9, "weapons": 0.8},
			"artillerySupport": {"infantry": 1.0, "armor": 0.8, "recon": 0.7},
			"weapons": {"infantry": 0.9, "armor": 0.7, "mobility": 0.8},
			"command": {"infantry": 0.7, "armor": 0.8, "artillerySupport": 0.9}
		}
	},
	"artilleryPlacement": {
		"weights": {
			"standoffDistance": 1.8,
			"targetCoverage": 1.6,
			"terrain": 1.2,
			"counterBatteryRisk": -1.1,
			"roadAccess": 0.7,
			"supportAlonePenalty": -0.9
		},
		"terrainSuitability": {
			"open": 0.7,
			"road": 0.8,
			"rough": 0.6,
			"urban": 0.5,
			"river": 0.3
		}
	},
	"reservePlacement": {
		"weights": {
			"responseDistance": 1.7,
			"interiorLines": 1.3,
			"terrain": 1.0,
			"cover": 0.7,
			"reserveClumpingPenalty": -1.6,
			"frontlineExposurePenalty": -1.2
		},
		"terrainSuitability": {
			"open": 0.7,
			"road": 0.9,
			"rough": 0.8,
			"urban": 0.9,
			"river": 0.2
		}
	}
}

static func scoring_config(overrides: Dictionary = {}) -> Dictionary:
	return _merge_dict(DEFAULT_CONFIG, overrides)

# context keys:
# unitRole, sectorType(frontline|contested|rear), terrain, frontlineDistanceNormalized(0..1),
# enemyPressureNormalized(0..1), supportNeighbors, isObjectiveHex
static func score_combat_assignment(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var cfg := scoring_config(overrides)
	var section: Dictionary = cfg.get("combatAssignment", {})
	var weights: Dictionary = section.get("weights", {})
	var unit_role := String(context.get("unitRole", "infantry"))
	var sector_type := String(context.get("sectorType", "frontline"))
	var terrain := String(context.get("terrain", "open"))
	var support_neighbors := int(context.get("supportNeighbors", 0))

	var role_affinity := _table_lookup(section.get("roleAffinity", {}), unit_role, sector_type, 0.5)
	var terrain_fit := _table_lookup(section.get("terrainSuitability", {}), unit_role, terrain, 0.5)
	var proximity := clamp(1.0 - float(context.get("frontlineDistanceNormalized", 1.0)), 0.0, 1.0)
	var objective_focus := 1.0 if bool(context.get("isObjectiveHex", false)) else 0.0
	var pressure := clamp(float(context.get("enemyPressureNormalized", 0.0)), 0.0, 1.0)
	var support_coverage := clamp(float(support_neighbors) / 3.0, 0.0, 1.0)
	var support_alone := 1.0 if _is_support_role(unit_role) and support_neighbors <= 0 else 0.0

	var score := 0.0
	score += role_affinity * float(weights.get("roleAffinity", 0.0))
	score += terrain_fit * float(weights.get("terrainSuitability", 0.0))
	score += proximity * float(weights.get("frontlineProximity", 0.0))
	score += objective_focus * float(weights.get("objectiveFocus", 0.0))
	score += pressure * float(weights.get("enemyPressure", 0.0))
	score += support_coverage * float(weights.get("supportCoverage", 0.0))
	score += support_alone * float(weights.get("supportAlonePenalty", 0.0))

	var reasons := [
		_reason("role", role_affinity * float(weights.get("roleAffinity", 0.0))),
		_reason("terrain", terrain_fit * float(weights.get("terrainSuitability", 0.0))),
		_reason("prox", proximity * float(weights.get("frontlineProximity", 0.0))),
		_reason("obj", objective_focus * float(weights.get("objectiveFocus", 0.0))),
		_reason("press", pressure * float(weights.get("enemyPressure", 0.0))),
		_reason("cover", support_coverage * float(weights.get("supportCoverage", 0.0)))
	]
	if support_alone > 0.0:
		reasons.append(_reason("alone", support_alone * float(weights.get("supportAlonePenalty", 0.0))))
	return {"score": score, "reasons": reasons}

# context keys:
# supportRole, supportedRole, distanceNormalized(0..1 where 1 is far), threatMatchNormalized,
# coverageNeedNormalized, leavesSupportAlone
static func score_support_attachment(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var cfg := scoring_config(overrides)
	var section: Dictionary = cfg.get("supportAttachment", {})
	var weights: Dictionary = section.get("weights", {})
	var support_role := String(context.get("supportRole", "weapons"))
	var supported_role := String(context.get("supportedRole", "infantry"))

	var role_affinity := _table_lookup(section.get("roleAffinity", {}), support_role, supported_role, 0.5)
	var distance_fit := clamp(1.0 - float(context.get("distanceNormalized", 1.0)), 0.0, 1.0)
	var threat_match := clamp(float(context.get("threatMatchNormalized", 0.0)), 0.0, 1.0)
	var coverage := clamp(float(context.get("coverageNeedNormalized", 0.0)), 0.0, 1.0)
	var support_alone := 1.0 if bool(context.get("leavesSupportAlone", false)) else 0.0

	var score := 0.0
	score += role_affinity * float(weights.get("roleAffinity", 0.0))
	score += distance_fit * float(weights.get("distance", 0.0))
	score += threat_match * float(weights.get("threatMatch", 0.0))
	score += coverage * float(weights.get("coverage", 0.0))
	score += support_alone * float(weights.get("supportAlonePenalty", 0.0))

	var reasons := [
		_reason("role", role_affinity * float(weights.get("roleAffinity", 0.0))),
		_reason("dist", distance_fit * float(weights.get("distance", 0.0))),
		_reason("threat", threat_match * float(weights.get("threatMatch", 0.0))),
		_reason("need", coverage * float(weights.get("coverage", 0.0)))
	]
	if support_alone > 0.0:
		reasons.append(_reason("alone", support_alone * float(weights.get("supportAlonePenalty", 0.0))))
	return {"score": score, "reasons": reasons}

# context keys:
# terrain, standoffDistanceFitNormalized, targetCoverageNormalized,
# counterBatteryRiskNormalized, roadAccessNormalized, isolatedFromMainForce
static func score_artillery_placement(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var cfg := scoring_config(overrides)
	var section: Dictionary = cfg.get("artilleryPlacement", {})
	var weights: Dictionary = section.get("weights", {})
	var terrain := String(context.get("terrain", "open"))

	var standoff := clamp(float(context.get("standoffDistanceFitNormalized", 0.0)), 0.0, 1.0)
	var coverage := clamp(float(context.get("targetCoverageNormalized", 0.0)), 0.0, 1.0)
	var terrain_fit := float(section.get("terrainSuitability", {}).get(terrain, 0.5))
	var counter_battery_risk := clamp(float(context.get("counterBatteryRiskNormalized", 0.0)), 0.0, 1.0)
	var road_access := clamp(float(context.get("roadAccessNormalized", 0.0)), 0.0, 1.0)
	var support_alone := 1.0 if bool(context.get("isolatedFromMainForce", false)) else 0.0

	var score := 0.0
	score += standoff * float(weights.get("standoffDistance", 0.0))
	score += coverage * float(weights.get("targetCoverage", 0.0))
	score += terrain_fit * float(weights.get("terrain", 0.0))
	score += counter_battery_risk * float(weights.get("counterBatteryRisk", 0.0))
	score += road_access * float(weights.get("roadAccess", 0.0))
	score += support_alone * float(weights.get("supportAlonePenalty", 0.0))

	var reasons := [
		_reason("standoff", standoff * float(weights.get("standoffDistance", 0.0))),
		_reason("coverage", coverage * float(weights.get("targetCoverage", 0.0))),
		_reason("terrain", terrain_fit * float(weights.get("terrain", 0.0))),
		_reason("cbrisk", counter_battery_risk * float(weights.get("counterBatteryRisk", 0.0))),
		_reason("road", road_access * float(weights.get("roadAccess", 0.0)))
	]
	if support_alone > 0.0:
		reasons.append(_reason("alone", support_alone * float(weights.get("supportAlonePenalty", 0.0))))
	return {"score": score, "reasons": reasons}

# context keys:
# terrain, responseDistanceFitNormalized, interiorLinesNormalized,
# coverNormalized, reserveClumpingNormalized, frontlineExposureNormalized
static func score_reserve_placement(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var cfg := scoring_config(overrides)
	var section: Dictionary = cfg.get("reservePlacement", {})
	var weights: Dictionary = section.get("weights", {})
	var terrain := String(context.get("terrain", "open"))

	var response_distance := clamp(float(context.get("responseDistanceFitNormalized", 0.0)), 0.0, 1.0)
	var interior_lines := clamp(float(context.get("interiorLinesNormalized", 0.0)), 0.0, 1.0)
	var terrain_fit := float(section.get("terrainSuitability", {}).get(terrain, 0.5))
	var cover := clamp(float(context.get("coverNormalized", 0.0)), 0.0, 1.0)
	var clumping := clamp(float(context.get("reserveClumpingNormalized", 0.0)), 0.0, 1.0)
	var exposure := clamp(float(context.get("frontlineExposureNormalized", 0.0)), 0.0, 1.0)

	var score := 0.0
	score += response_distance * float(weights.get("responseDistance", 0.0))
	score += interior_lines * float(weights.get("interiorLines", 0.0))
	score += terrain_fit * float(weights.get("terrain", 0.0))
	score += cover * float(weights.get("cover", 0.0))
	score += clumping * float(weights.get("reserveClumpingPenalty", 0.0))
	score += exposure * float(weights.get("frontlineExposurePenalty", 0.0))

	var reasons := [
		_reason("resp", response_distance * float(weights.get("responseDistance", 0.0))),
		_reason("interior", interior_lines * float(weights.get("interiorLines", 0.0))),
		_reason("terrain", terrain_fit * float(weights.get("terrain", 0.0))),
		_reason("cover", cover * float(weights.get("cover", 0.0))),
		_reason("clump", clumping * float(weights.get("reserveClumpingPenalty", 0.0))),
		_reason("expose", exposure * float(weights.get("frontlineExposurePenalty", 0.0)))
	]
	return {"score": score, "reasons": reasons}

# Deterministic ordering for equal scores:
# score desc, unitId asc, hexId asc.
static func sort_scored_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var ordered := candidates.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := float(a.get("score", 0.0))
		var b_score := float(b.get("score", 0.0))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		var a_unit := String(a.get("unitId", a.get("unit_id", "")))
		var b_unit := String(b.get("unitId", b.get("unit_id", "")))
		if a_unit != b_unit:
			return a_unit < b_unit
		var a_hex := String(a.get("hexId", a.get("hex_id", "")))
		var b_hex := String(b.get("hexId", b.get("hex_id", "")))
		return a_hex < b_hex
	)
	return ordered

static func _table_lookup(table: Dictionary, primary_key: String, secondary_key: String, default_value: float) -> float:
	var primary: Dictionary = table.get(primary_key, {})
	if primary.is_empty():
		return default_value
	return float(primary.get(secondary_key, default_value))

static func _is_support_role(role: String) -> bool:
	return role in [
		DeploymentTypes.ROLE_AIR_DEFENSE,
		DeploymentTypes.ROLE_ANTI_TANK_SUPPORT,
		DeploymentTypes.ROLE_ARTILLERY_SUPPORT,
		DeploymentTypes.ROLE_WEAPONS,
		DeploymentTypes.ROLE_COMMAND
	]

static func _reason(label: String, value: float) -> String:
	return "%s%+.2f" % [label + ":", value]

static func _merge_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in overrides.keys():
		var incoming := overrides[key]
		if merged.has(key) and merged[key] is Dictionary and incoming is Dictionary:
			merged[key] = _merge_dict(merged[key], incoming)
		else:
			merged[key] = incoming
	return merged
