extends RefCounted
class_name OperationalScoringModel

const DEFAULT_CONFIG := {
	"shared": {
		"scoreRange": {"min": -4.0, "max": 4.0},
		"componentDefaults": {"min": 0.0, "max": 1.0, "default": 0.0}
	},
	"friendlyStrength": {
		"components": {
			"combat_strength": {"input": "combatStrength", "weight": 1.40, "min": 0.0, "max": 1.0, "default": 0.0},
			"support_strength": {"input": "supportStrength", "weight": 1.00, "min": 0.0, "max": 1.0, "default": 0.0},
			"terrain_defense": {"input": "terrainDefense", "weight": 0.70, "min": 0.0, "max": 1.0, "default": 0.5},
			"artillery_proximity": {"input": "artilleryProximity", "weight": 0.55, "min": 0.0, "max": 1.0, "default": 0.0},
			"recon_proximity": {"input": "reconProximity", "weight": 0.45, "min": 0.0, "max": 1.0, "default": 0.0},
			"reserve_proximity": {"input": "reserveProximity", "weight": 0.60, "min": 0.0, "max": 1.0, "default": 0.0},
			"isolation_penalty": {"input": "isolation", "weight": -0.85, "min": 0.0, "max": 1.0, "default": 0.0},
			"overstack_penalty": {"input": "overstack", "weight": -0.55, "min": 0.0, "max": 1.0, "default": 0.0}
		}
	},
	"enemyPressure": {
		"components": {
			"enemy_combat_strength": {"input": "enemyCombatStrength", "weight": 1.20, "min": 0.0, "max": 1.0, "default": 0.0},
			"enemy_support_strength": {"input": "enemySupportStrength", "weight": 0.85, "min": 0.0, "max": 1.0, "default": 0.0},
			"enemy_artillery_proximity": {"input": "enemyArtilleryProximity", "weight": 0.65, "min": 0.0, "max": 1.0, "default": 0.0},
			"enemy_recon_proximity": {"input": "enemyReconProximity", "weight": 0.50, "min": 0.0, "max": 1.0, "default": 0.0},
			"ownership_adjacency": {"input": "ownershipAdjacency", "weight": 0.70, "min": 0.0, "max": 1.0, "default": 0.0},
			"route_access": {"input": "routeAccess", "weight": 0.60, "min": 0.0, "max": 1.0, "default": 0.0},
			"recent_advances": {"input": "recentAdvances", "weight": 0.75, "min": 0.0, "max": 1.0, "default": 0.0},
			"scout_uncertainty": {"input": "scoutUncertainty", "weight": 0.50, "min": 0.0, "max": 1.0, "default": 0.0}
		}
	},
	"sectorDanger": {
		"components": {
			"enemy_pressure": {"input": "enemyPressure", "weight": 1.05, "min": 0.0, "max": 1.0, "default": 0.0},
			"friendly_weakness": {"input": "friendlyWeakness", "weight": 0.95, "min": 0.0, "max": 1.0, "default": 0.0},
			"ownership_adjacency": {"input": "ownershipAdjacency", "weight": 0.70, "min": 0.0, "max": 1.0, "default": 0.0},
			"route_access": {"input": "routeAccess", "weight": 0.55, "min": 0.0, "max": 1.0, "default": 0.0},
			"objective_proximity": {"input": "objectiveProximity", "weight": 0.65, "min": 0.0, "max": 1.0, "default": 0.0},
			"recent_advances": {"input": "recentAdvances", "weight": 0.50, "min": 0.0, "max": 1.0, "default": 0.0},
			"scout_uncertainty": {"input": "scoutUncertainty", "weight": 0.45, "min": 0.0, "max": 1.0, "default": 0.0},
			"isolation": {"input": "isolation", "weight": 0.45, "min": 0.0, "max": 1.0, "default": 0.0},
			"overstack": {"input": "overstack", "weight": 0.35, "min": 0.0, "max": 1.0, "default": 0.0}
		}
	},
	"attackOpportunity": {
		"components": {
			"objective_value": {"input": "objectiveValue", "weight": 0.95, "min": 0.0, "max": 1.0, "default": 0.0},
			"enemy_weakness_estimate": {"input": "enemyWeaknessEstimate", "weight": 1.10, "min": 0.0, "max": 1.0, "default": 0.0},
			"local_friendly_power": {"input": "localFriendlyPower", "weight": 1.05, "min": 0.0, "max": 1.0, "default": 0.0},
			"artillery_support": {"input": "artillerySupport", "weight": 0.60, "min": 0.0, "max": 1.0, "default": 0.0},
			"recon_support": {"input": "reconSupport", "weight": 0.45, "min": 0.0, "max": 1.0, "default": 0.0},
			"terrain_suitability": {"input": "terrainSuitability", "weight": 0.55, "min": 0.0, "max": 1.0, "default": 0.0},
			"defensive_coherence_risk": {"input": "defensiveCoherenceRisk", "weight": -0.85, "min": 0.0, "max": 1.0, "default": 0.0},
			"overextension_risk": {"input": "overextensionRisk", "weight": -0.95, "min": 0.0, "max": 1.0, "default": 0.0}
		}
	},
	"counterattackOpportunity": {
		"components": {
			"objective_value": {"input": "objectiveValue", "weight": 0.80, "min": 0.0, "max": 1.0, "default": 0.0},
			"enemy_weakness_estimate": {"input": "enemyWeaknessEstimate", "weight": 1.20, "min": 0.0, "max": 1.0, "default": 0.0},
			"local_friendly_power": {"input": "localFriendlyPower", "weight": 1.10, "min": 0.0, "max": 1.0, "default": 0.0},
			"artillery_support": {"input": "artillerySupport", "weight": 0.70, "min": 0.0, "max": 1.0, "default": 0.0},
			"recon_support": {"input": "reconSupport", "weight": 0.60, "min": 0.0, "max": 1.0, "default": 0.0},
			"terrain_suitability": {"input": "terrainSuitability", "weight": 0.45, "min": 0.0, "max": 1.0, "default": 0.0},
			"defensive_coherence_risk": {"input": "defensiveCoherenceRisk", "weight": -1.00, "min": 0.0, "max": 1.0, "default": 0.0},
			"overextension_risk": {"input": "overextensionRisk", "weight": -1.10, "min": 0.0, "max": 1.0, "default": 0.0}
		}
	}
}

static func scoring_config(overrides: Dictionary = {}) -> Dictionary:
	return _deep_merge(DEFAULT_CONFIG, overrides)

# context keys include: combat/support strength, terrain defense, artillery/recon/reserve proximity,
# isolation and overstack pressure.
static func score_friendly_strength(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	return _score_from_section("friendlyStrength", context, overrides)

# context keys include: enemy combat/support strength, artillery/recon proximity,
# ownership adjacency, route access, recent advances, scout uncertainty.
static func score_enemy_pressure(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	return _score_from_section("enemyPressure", context, overrides)

# context keys include: enemy pressure, friendly weakness, ownership adjacency,
# route/objective proximity, recent advances, scout uncertainty, isolation and overstack.
static func score_sector_danger(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	return _score_from_section("sectorDanger", context, overrides)

# context keys include: objective value, enemy weakness estimate, local friendly power, artillery/recon support,
# terrain suitability and defensive coherence / overextension risk.
static func score_attack_opportunity(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	return _score_from_section("attackOpportunity", context, overrides)

# context keys include: objective value, enemy weakness estimate, local friendly power, artillery/recon support,
# terrain suitability and defensive coherence / overextension risk.
static func score_counterattack_opportunity(context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	return _score_from_section("counterattackOpportunity", context, overrides)

static func _score_from_section(section_key: String, context: Dictionary, overrides: Dictionary) -> Dictionary:
	var cfg := scoring_config(overrides)
	var section: Dictionary = cfg.get(section_key, {})
	var components: Dictionary = section.get("components", {})
	var defaults: Dictionary = cfg.get("shared", {}).get("componentDefaults", {})

	var score := 0.0
	var reasons: Array[String] = []
	var component_names: Array[String] = []
	for key_variant in components.keys():
		component_names.append(String(key_variant))
	component_names.sort()

	for component_name in component_names:
		var component_cfg: Dictionary = components.get(component_name, {})
		var contribution := _component_contribution(component_cfg, defaults, context)
		score += contribution
		reasons.append(_reason(component_name, contribution))

	var bounded_score := _clamp_score(score, cfg)
	return {
		"score": bounded_score,
		"reasons": reasons,
		"rawScore": score
	}

static func _component_contribution(component_cfg: Dictionary, defaults: Dictionary, context: Dictionary) -> float:
	var input_key := String(component_cfg.get("input", ""))
	var min_value := float(component_cfg.get("min", defaults.get("min", 0.0)))
	var max_value := float(component_cfg.get("max", defaults.get("max", 1.0)))
	var default_value := float(component_cfg.get("default", defaults.get("default", 0.0)))
	var weight := float(component_cfg.get("weight", 0.0))

	var raw_value := float(context.get(input_key, default_value))
	var normalized := _normalize(raw_value, min_value, max_value)
	return normalized * weight

static func _normalize(value: float, min_value: float, max_value: float) -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return clamp((value - min_value) / (max_value - min_value), 0.0, 1.0)

static func _clamp_score(score: float, cfg: Dictionary) -> float:
	var score_range: Dictionary = cfg.get("shared", {}).get("scoreRange", {})
	var min_score := float(score_range.get("min", -4.0))
	var max_score := float(score_range.get("max", 4.0))
	return clamp(score, min_score, max_score)

static func _reason(label: String, value: float) -> String:
	return "%s%+.2f" % [label + ":", value]

static func _deep_merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in overrides.keys():
		var base_value = merged.get(key)
		var override_value = overrides[key]
		if base_value is Dictionary and override_value is Dictionary:
			merged[key] = _deep_merge(base_value, override_value)
		else:
			merged[key] = override_value
	return merged
