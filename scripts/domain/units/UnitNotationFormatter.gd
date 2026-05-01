class_name UnitNotationFormatter
extends RefCounted

const SUPPORT_TYPE_ABBREVIATIONS := {
	"recon": "recon",
	"anti_tank": "AT",
	"antitank": "AT",
	"engineer": "Eng",
	"weapons": "W",
	"heavy_weapons": "Hvy"
}

static func format_unit(unit: Dictionary, options: Dictionary = {}) -> String:
	var designation: Dictionary = unit.get("designation", {}) as Dictionary
	var unit_type := String(unit.get("unit_type", unit.get("type", ""))).strip_edges().to_lower()
	var size := String(unit.get("size", unit.get("formation_size", ""))).strip_edges().to_lower()
	var battalion_number := maxi(int(designation.get("battalion_number", 0)), 0)
	var regiment_number := maxi(int(designation.get("regiment_number", 0)), 0)
	var company_letter := String(designation.get("company_letter", "")).strip_edges().to_upper()
	var platoon_number := maxi(int(designation.get("platoon_number", 0)), 0)
	if battalion_number <= 0:
		battalion_number = maxi(int(unit.get("battalion_number", 0)), 0)
	if regiment_number <= 0:
		regiment_number = maxi(int(unit.get("regiment_number", 0)), 0)
	if company_letter.is_empty():
		company_letter = String(unit.get("company_letter", "")).strip_edges().to_upper()
	if platoon_number <= 0:
		platoon_number = maxi(int(unit.get("platoon_number", 0)), 0)
	var bn_reg := _bn_reg(battalion_number, regiment_number)
	if bn_reg.is_empty():
		push_warning("UnitNotationFormatter: missing battalion/regiment for %s unit '%s'. Using fallback label." % [size, String(unit.get("id", "Unit"))])

	if unit_type == "headquarters" and size == "battalion":
		if bn_reg.is_empty():
			return "HQ/?"
		return "HQ/%s" % bn_reg
	if size == "company":
		if company_letter.is_empty():
			push_warning("UnitNotationFormatter: company unit '%s' missing company letter. Using fallback label." % String(unit.get("id", "Unit")))
			company_letter = "?"
		if bn_reg.is_empty():
			return "%s/?" % company_letter
		return "%s/%s" % [company_letter, bn_reg]
	if size == "platoon":
		if platoon_number <= 0:
			push_warning("UnitNotationFormatter: platoon unit '%s' missing platoon number. Using fallback label." % String(unit.get("id", "Unit")))
		if company_letter.is_empty():
			push_warning("UnitNotationFormatter: platoon unit '%s' missing parent company letter. Using fallback label." % String(unit.get("id", "Unit")))
		var platoon_text := str(platoon_number) if platoon_number > 0 else "?"
		var company_text := company_letter if not company_letter.is_empty() else "?"
		if bn_reg.is_empty():
			return "%s/%s/?" % [platoon_text, company_text]
		return "%s/%s/%s" % [platoon_text, company_text, bn_reg]

	if bn_reg.is_empty():
		return String(unit.get("short_name", unit.get("display_name", unit.get("id", "Unit"))))

	if size == "platoon" and platoon_number > 0 and not company_letter.is_empty():
		return "%d/%s/%s" % [platoon_number, company_letter, bn_reg]

	var support_abbrev := _support_abbreviation(unit_type, options)
	if not support_abbrev.is_empty():
		return "%s/%s" % [support_abbrev, bn_reg]

	return String(unit.get("short_name", unit.get("display_name", unit.get("id", "Unit"))))

static func _bn_reg(battalion_number: int, regiment_number: int) -> String:
	if battalion_number <= 0 or regiment_number <= 0:
		return ""
	return "%d-%d" % [battalion_number, regiment_number]

static func _support_abbreviation(unit_type: String, options: Dictionary) -> String:
	if unit_type == "heavy_weapons" and bool(options.get("use_hvy_for_weapons", false)):
		return "Hvy"
	if SUPPORT_TYPE_ABBREVIATIONS.has(unit_type):
		if unit_type == "heavy_weapons":
			return "W"
		return String(SUPPORT_TYPE_ABBREVIATIONS[unit_type])
	return ""
