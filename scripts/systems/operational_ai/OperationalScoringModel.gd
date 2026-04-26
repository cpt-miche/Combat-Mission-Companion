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

const POSTURE_PROFILES := {
	"balanced": {},
	"aggressive": {
		"attackOpportunity": {
			"components": {
				"objective_value": {"weight": 1.15},
				"enemy_weakness_estimate": {"weight": 1.30},
				"local_friendly_power": {"weight": 1.20},
				"overextension_risk": {"weight": -0.75}
			}
		},
		"counterattackOpportunity": {
			"components": {
				"enemy_weakness_estimate": {"weight": 1.35},
				"local_friendly_power": {"weight": 1.20},
				"overextension_risk": {"weight": -0.90}
			}
		},
		"opportunityThresholds": {
			"counterattack": 0.65,
			"attack": 0.60,
			"moveReserve": 0.56,
			"reinforce": 0.54,
			"withdraw": 0.76
		},
		"breakthroughThresholds": {
			"reserveNeed": 0.58,
			"reinforcementRequest": 0.78
		}
	},
	"defensive": {
		"friendlyStrength": {
			"components": {
				"terrain_defense": {"weight": 0.90},
				"isolation_penalty": {"weight": -1.00},
				"overstack_penalty": {"weight": -0.70}
			}
		},
		"sectorDanger": {
			"components": {
				"friendly_weakness": {"weight": 1.15},
				"isolation": {"weight": 0.55}
			}
		},
		"opportunityThresholds": {
			"counterattack": 0.79,
			"attack": 0.75,
			"moveReserve": 0.68,
			"reinforce": 0.55,
			"delay": 0.45,
			"withdraw": 0.62
		},
		"quietSectorThresholds": {
			"maxPressure": 0.30,
			"minDefensibility": 0.60,
			"minSupport": 0.55
		},
		"breakthroughThresholds": {
			"reserveNeed": 0.50,
			"reinforcementRequest": 0.69
		}
	},
	"cautious": {
		"attackOpportunity": {
			"components": {
				"defensive_coherence_risk": {"weight": -1.05},
				"overextension_risk": {"weight": -1.15}
			}
		},
		"counterattackOpportunity": {
			"components": {
				"defensive_coherence_risk": {"weight": -1.15},
				"overextension_risk": {"weight": -1.25}
			}
		},
		"opportunityThresholds": {
			"counterattack": 0.82,
			"attack": 0.78,
			"moveReserve": 0.72,
			"reinforce": 0.62,
			"delay": 0.42,
			"withdraw": 0.60
		},
		"breakthroughThresholds": {
			"reserveNeed": 0.48,
			"reinforcementRequest": 0.66
		}
	},
	"armorHeavy": {
		"attackOpportunity": {
			"components": {
				"local_friendly_power": {"weight": 1.25},
				"terrain_suitability": {"weight": 0.70}
			}
		},
		"counterattackOpportunity": {
			"components": {
				"local_friendly_power": {"weight": 1.30},
				"terrain_suitability": {"weight": 0.60}
			}
		},
		"opportunityThresholds": {
			"counterattack": 0.68,
			"attack": 0.62,
			"moveReserve": 0.57,
			"withdraw": 0.73
		}
	},
	"infantryHeavy": {
		"friendlyStrength": {
			"components": {
				"terrain_defense": {"weight": 0.85},
				"support_strength": {"weight": 1.10}
			}
		},
		"sectorDanger": {
			"components": {
				"route_access": {"weight": 0.45},
				"objective_proximity": {"weight": 0.75}
			}
		},
		"attackOpportunity": {
			"components": {
				"terrain_suitability": {"weight": 0.70},
				"artillery_support": {"weight": 0.72},
				"overextension_risk": {"weight": -1.05}
			}
		},
		"opportunityThresholds": {
			"counterattack": 0.76,
			"attack": 0.70,
			"moveReserve": 0.65,
			"withdraw": 0.65
		}
	}
}


static func scoring_config(overrides: Dictionary = {}) -> Dictionary:
	return _deep_merge(DEFAULT_CONFIG, overrides)

static func weights_for_posture(posture: String, base_config: Dictionary = {}) -> Dictionary:
	var normalized_posture := _normalize_posture(posture)
	var posture_overrides: Dictionary = POSTURE_PROFILES.get(normalized_posture, {})
	var merged := _deep_merge(base_config, posture_overrides)
	if normalized_posture == "balanced":
		return merged
	var adjusted_components := _collect_adjusted_components(posture_overrides)
	var adjusted_thresholds := _collect_adjusted_thresholds(posture_overrides)
	return _deep_merge(merged, {
		"shared": {
			"postureMeta": {
				"active": normalized_posture,
				"adjustedComponents": adjusted_components,
				"adjustedThresholds": adjusted_thresholds
			}
		}
	})

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

	var posture_meta: Dictionary = cfg.get("shared", {}).get("postureMeta", {})
	var active_posture := String(posture_meta.get("active", "balanced"))
	var adjusted_components: Dictionary = posture_meta.get("adjustedComponents", {})
	var section_adjusted: Dictionary = adjusted_components.get(section_key, {})
	for component_name in component_names:
		var component_cfg: Dictionary = components.get(component_name, {})
		var contribution := _component_contribution(component_cfg, defaults, context)
		score += contribution
		reasons.append(_reason(component_name, contribution))
		if active_posture != "balanced" and bool(section_adjusted.get(component_name, false)):
			reasons.append("posture_adjusted_component=%s:%s" % [active_posture, component_name])

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

static func _normalize_posture(posture: String) -> String:
	var trimmed := posture.strip_edges()
	if trimmed.is_empty():
		return "balanced"
	if POSTURE_PROFILES.has(trimmed):
		return trimmed
	return "balanced"

static func _collect_adjusted_components(overrides: Dictionary) -> Dictionary:
	var adjusted := {}
	for section_key_variant in overrides.keys():
		var section_key := String(section_key_variant)
		var section_value = overrides.get(section_key)
		if not (section_value is Dictionary):
			continue
		var components: Dictionary = section_value.get("components", {})
		if components.is_empty():
			continue
		adjusted[section_key] = {}
		for component_key_variant in components.keys():
			adjusted[section_key][String(component_key_variant)] = true
	return adjusted

static func _collect_adjusted_thresholds(overrides: Dictionary) -> Array[String]:
	var thresholds: Array[String] = []
	for section_key_variant in overrides.keys():
		var section_key := String(section_key_variant)
		if section_key.ends_with("Thresholds"):
			thresholds.append(section_key)
	thresholds.sort()
	return thresholds

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
