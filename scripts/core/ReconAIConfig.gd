extends RefCounted
class_name ReconAIConfig

const SCOUT_LEVEL_MIN := 0
const SCOUT_LEVEL_MAX := 4

const UNIT_CATEGORIES := {
	"combat": {
		"infantry": true,
		"tank": true,
		"mechanized": true,
		"motorized": true
	},
	"support": {
		"recon": true,
		"antiTank": true,
		"weapons": true,
		"artillery": true
	}
}

const AUTOMATIC_SCOUT_FLOOR_BY_TYPE := {
	"infantry": 1,
	"tank": 1,
	"mechanized": 1,
	"motorized": 1,
	"recon": 3
}

const SCOUT_PROGRESSION_DENOMINATOR_BY_TYPE := {
	"recon": 2,
	"infantry": 4,
	"tank": 4,
	"mechanized": 4,
	"motorized": 4
}

const DISCOVERY_ODDS := {
	"level_1_type_known_denominator": 4,
	"level_2_support_type_known_denominator": 4,
	"level_3_combat_size_known_denominator": 4,
	"level_4_size_drift_denominator": 8,
	"level_4_size_drift_direction_denominator": 2,
	"level_3_size_drift_roll_denominator": 4
}

const AI_SCOUT_COVERAGE := {
	"expected_floor": {
		"combat": 1,
		"recon_support": 3,
		"default_support": 1
	},
	"weights": {
		"coverage": 1.0,
		"uncertainty_reduction": 1.0,
		"critical_low_intel_penalty": 2.0
	},
	"ranges": {
		"critical_importance_threshold": 0.75
	}
}
