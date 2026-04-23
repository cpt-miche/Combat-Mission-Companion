extends RefCounted
class_name TerrainCatalog

const DEFAULT_TERRAIN_ID := "light"

const TERRAIN_IDS := PackedStringArray([
	"highway",
	"road",
	"light",
	"medium",
	"heavy",
	"woods",
	"urban"
])

const _LEGACY_NAME_TO_ID := {
	"highway": "highway",
	"road": "road",
	"light": "light",
	"light terrain": "light",
	"open": "light",
	"clear": "light",
	"medium": "medium",
	"medium terrain": "medium",
	"rough": "medium",
	"heavy": "heavy",
	"heavy terrain": "heavy",
	"dense": "heavy",
	"woods": "woods",
	"forest": "woods",
	"urban": "urban"
}

const _CATALOG := {
	"highway": {
		"display_name": "Highway",
		"movement": {"cost": 1.0, "speed_multiplier": 1.25, "passable": true},
		"combat": {"cover": 0.0, "concealment": 0.0, "defense_modifier": 0.0},
		"editor_color": Color(0.25, 0.25, 0.25, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	},
	"road": {
		"display_name": "Road",
		"movement": {"cost": 1.0, "speed_multiplier": 1.1, "passable": true},
		"combat": {"cover": 0.05, "concealment": 0.0, "defense_modifier": 0.0},
		"editor_color": Color(0.75, 0.75, 0.75, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	},
	"light": {
		"display_name": "Light Terrain",
		"movement": {"cost": 2.0, "speed_multiplier": 1.0, "passable": true},
		"combat": {"cover": 0.1, "concealment": 0.05, "defense_modifier": 0.05},
		"editor_color": Color(0.68, 0.88, 0.62, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	},
	"medium": {
		"display_name": "Medium Terrain",
		"movement": {"cost": 3.0, "speed_multiplier": 0.85, "passable": true},
		"combat": {"cover": 0.2, "concealment": 0.1, "defense_modifier": 0.1},
		"editor_color": Color(0.74, 0.62, 0.46, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	},
	"heavy": {
		"display_name": "Heavy Terrain",
		"movement": {"cost": 4.0, "speed_multiplier": 0.7, "passable": true},
		"combat": {"cover": 0.35, "concealment": 0.25, "defense_modifier": 0.2},
		"editor_color": Color(0.42, 0.28, 0.17, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	},
	"woods": {
		"display_name": "Woods",
		"movement": {"cost": 4.0, "speed_multiplier": 0.7, "passable": true},
		"combat": {"cover": 0.4, "concealment": 0.3, "defense_modifier": 0.2},
		"editor_color": Color(0.13, 0.38, 0.18, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	},
	"urban": {
		"display_name": "Urban",
		"movement": {"cost": 3.0, "speed_multiplier": 0.9, "passable": true},
		"combat": {"cover": 0.45, "concealment": 0.15, "defense_modifier": 0.25},
		"editor_color": Color(0.88, 0.81, 0.68, 1.0),
		"icons": {"road": "", "tree": "", "hills": ""}
	}
}

static func all_ids() -> PackedStringArray:
	return TERRAIN_IDS

static func default_terrain_id() -> String:
	return DEFAULT_TERRAIN_ID

static func normalize_terrain_id(terrain: String) -> String:
	var normalized := terrain.strip_edges().to_lower()
	if normalized.is_empty():
		return DEFAULT_TERRAIN_ID
	return String(_LEGACY_NAME_TO_ID.get(normalized, DEFAULT_TERRAIN_ID))

static func display_name(terrain_id: String) -> String:
	var id := normalize_terrain_id(terrain_id)
	var entry: Dictionary = _CATALOG.get(id, {})
	return String(entry.get("display_name", "Light Terrain"))

static func movement_metadata(terrain_id: String) -> Dictionary:
	var id := normalize_terrain_id(terrain_id)
	var entry: Dictionary = _CATALOG.get(id, {})
	return (entry.get("movement", {}) as Dictionary).duplicate(true)

static func combat_metadata(terrain_id: String) -> Dictionary:
	var id := normalize_terrain_id(terrain_id)
	var entry: Dictionary = _CATALOG.get(id, {})
	return (entry.get("combat", {}) as Dictionary).duplicate(true)

static func editor_color(terrain_id: String, alpha: float = 0.45) -> Color:
	var id := normalize_terrain_id(terrain_id)
	var entry: Dictionary = _CATALOG.get(id, {})
	var base := entry.get("editor_color", Color(0.68, 0.88, 0.62, 1.0)) as Color
	base.a = alpha
	return base

static func icon_path(terrain_id: String, icon_key: String) -> String:
	var id := normalize_terrain_id(terrain_id)
	var entry: Dictionary = _CATALOG.get(id, {})
	var icons := entry.get("icons", {}) as Dictionary
	return String(icons.get(icon_key, ""))
