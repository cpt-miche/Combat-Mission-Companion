class_name UnitRole
extends RefCounted

const UNKNOWN := "unknown"

const DISPLAY_OVERRIDES := {
	"anti_tank": "Anti-Tank",
	"anti_tank_gun": "Anti-Tank Gun",
	"medium_anti_tank_gun": "Medium Anti-Tank Gun",
	"air_defense": "Air Defense",
	"heavy_machine_gun": "Heavy Machine Gun",
	"medium_machine_gun": "Medium Machine Gun",
	"light_machine_gun": "Light Machine Gun",
	"60mm_mortar": "60mm Mortar",
	"81mm_mortar": "81mm Mortar",
	"8cm_mortar": "8cm Mortar",
	"12cm_mortar": "12cm Mortar",
	"105mm_howitzer": "105mm Howitzer",
	"155mm_howitzer": "155mm Howitzer",
	"light_tank": "Light Tank",
	"medium_tank": "Medium Tank",
	"heavy_tank": "Heavy Tank",
	"tank_destroyer": "Tank Destroyer",
	"assault_gun": "Assault Gun"
}

static func normalize(raw_role: Variant, fallback_type: Variant = "") -> String:
	var explicit_role := _identifier(String(raw_role))
	if not explicit_role.is_empty() and explicit_role != UNKNOWN:
		return explicit_role
	var broad_role := _identifier(_type_text(fallback_type))
	return broad_role if not broad_role.is_empty() else UNKNOWN

static func display_name(raw_role: Variant, fallback_type: Variant = "") -> String:
	var role := normalize(raw_role, fallback_type)
	if role == UNKNOWN:
		return "Unknown"
	if DISPLAY_OVERRIDES.has(role):
		return String(DISPLAY_OVERRIDES[role])
	return role.replace("_", " ").capitalize()

static func is_valid(raw_role: Variant) -> bool:
	var text := String(raw_role).strip_edges()
	return not text.is_empty() and text == _identifier(text) and text != UNKNOWN

static func _type_text(raw_type: Variant) -> String:
	if raw_type == null:
		return ""
	if typeof(raw_type) == TYPE_INT or typeof(raw_type) == TYPE_FLOAT:
		var enum_value := int(raw_type)
		if UnitType.Value.values().has(enum_value):
			return UnitType.display_name(enum_value)
	return String(raw_type)

static func _identifier(raw_value: String) -> String:
	var original := raw_value.strip_edges().replace("-", "_").replace("/", "_")
	var source := ""
	for index in range(original.length()):
		var character := original.substr(index, 1)
		if index > 0 and character == character.to_upper() and character != character.to_lower():
			var previous := original.substr(index - 1, 1)
			if previous == previous.to_lower() and previous != previous.to_upper() and not source.ends_with("_"):
				source += "_"
		source += character.to_lower()
	var result := ""
	var previous_was_separator := false
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var is_alphanumeric := character.to_lower() != character.to_upper() or character.is_valid_int()
		if is_alphanumeric:
			result += character
			previous_was_separator = false
		elif not previous_was_separator and not result.is_empty():
			result += "_"
			previous_was_separator = true
	return result.trim_prefix("_").trim_suffix("_")
