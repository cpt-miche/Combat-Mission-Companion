class_name UnitEquipmentWeight
extends RefCounted

static func for_unit(unit: Dictionary, normalized_role: String = "") -> String:
	var explicit_weight := _identifier(String(unit.get("equipment_weight", "")))
	if explicit_weight in ["light", "medium", "heavy"]:
		return explicit_weight
	var role := normalized_role
	if role.is_empty():
		role = UnitRole.normalize(unit.get("role", ""), unit.get("type", ""))
	match role:
		"light_tank", "light_machine_gun":
			return "light"
		"medium_tank", "medium_machine_gun", "medium_anti_tank_gun":
			return "medium"
		"heavy_tank", "heavy_machine_gun":
			return "heavy"

	var template_id := _identifier(String(unit.get("template_id", unit.get("id", ""))))
	if template_id.contains("m18"):
		return "light"
	if template_id.contains("m36") or template_id.contains("stug"):
		return "medium"
	if template_id.contains("heavy_antitank") or template_id.contains("heavy_anti_tank"):
		return "heavy"
	if role in ["tank_destroyer", "assault_gun", "anti_tank", "anti_tank_gun"]:
		return "medium"
	return ""

static func _identifier(raw_value: String) -> String:
	return raw_value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
