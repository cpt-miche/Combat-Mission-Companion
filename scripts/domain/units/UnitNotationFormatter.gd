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
	if bool(unit.get("is_attached", false)) or int(designation.get("attached_company_index", 0)) > 0:
		return _fallback_label(unit, String(unit.get("id", "Unit")))
	var unit_type := String(unit.get("type", "")).strip_edges().to_lower()
	var size := String(unit.get("size", "")).strip_edges().to_lower()
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

	if unit_type == "headquarters" and size == "battalion":
		if bn_reg.is_empty():
			return "Battalion HQ"
		return "HQ/%s" % bn_reg
	if size == "company":
		if company_letter.is_empty():
			if bn_reg.is_empty():
				return _fallback_label(unit, "Company")
			push_warning("UnitNotationFormatter: company unit '%s' missing company letter. Using fallback label." % String(unit.get("id", "Unit")))
			company_letter = "?"
		if bn_reg.is_empty():
			return "%s Company" % company_letter
		return "%s/%s" % [company_letter, bn_reg]
	if size == "platoon":
		if bn_reg.is_empty():
			if platoon_number <= 0:
				return _fallback_label(unit, "Platoon")
			return "%s Platoon" % _ordinal(platoon_number)
		if platoon_number <= 0:
			push_warning("UnitNotationFormatter: platoon unit '%s' missing platoon number. Using fallback label." % String(unit.get("id", "Unit")))
		if company_letter.is_empty():
			push_warning("UnitNotationFormatter: platoon unit '%s' missing parent company letter. Using fallback label." % String(unit.get("id", "Unit")))
		var platoon_text := str(platoon_number) if platoon_number > 0 else "?"
		var company_text := company_letter if not company_letter.is_empty() else "?"
		return "%s/%s/%s" % [platoon_text, company_text, bn_reg]

	if bn_reg.is_empty():
		if size == "battalion" and battalion_number > 0:
			var type_label := unit_type.replace("_", " ").capitalize()
			if type_label.is_empty() or type_label == "Headquarters":
				type_label = ""
			return "%s %sBattalion" % [_ordinal(battalion_number), "%s " % type_label if not type_label.is_empty() else ""]
		return String(unit.get("short_name", unit.get("display_name", unit.get("id", "Unit"))))

	if size == "platoon" and platoon_number > 0 and not company_letter.is_empty():
		return "%d/%s/%s" % [platoon_number, company_letter, bn_reg]

	var support_abbrev := _support_abbreviation(unit_type, options)
	if not support_abbrev.is_empty():
		return "%s/%s" % [support_abbrev, bn_reg]

	return String(unit.get("short_name", unit.get("display_name", unit.get("id", "Unit"))))

static func format_counter_unit(unit: Dictionary) -> String:
	var designation: Dictionary = unit.get("designation", {}) as Dictionary
	var size := String(unit.get("size", "")).strip_edges().to_lower()
	var unit_type := String(unit.get("type", "")).strip_edges().to_lower()
	var battalion_number := maxi(int(designation.get("battalion_number", unit.get("battalion_number", 0))), 0)
	var company_letter := String(designation.get("company_letter", unit.get("company_letter", ""))).strip_edges().to_upper()
	var platoon_number := maxi(int(designation.get("platoon_number", unit.get("platoon_number", 0))), 0)

	# Counter identity intentionally stops at battalion. Regiment and division
	# fields may remain in the model for the organization tree, but are never
	# included here.
	if size == "battalion":
		return "%d Bn" % battalion_number if battalion_number > 0 else _compact_fallback(unit, "Bn")
	if size == "company":
		if not company_letter.is_empty() and battalion_number > 0:
			return "%s/%d" % [company_letter, battalion_number]
		if not company_letter.is_empty():
			return "%s Co" % company_letter
	if size == "platoon":
		if platoon_number > 0 and not company_letter.is_empty() and battalion_number > 0:
			return "%d/%s/%d" % [platoon_number, company_letter, battalion_number]
		if platoon_number > 0 and not company_letter.is_empty():
			return "%d/%s" % [platoon_number, company_letter]
		if platoon_number > 0:
			return "%d Plt" % platoon_number

	var support_abbrev := _support_abbreviation(unit_type, {})
	if not support_abbrev.is_empty() and battalion_number > 0:
		return "%s/%d" % [support_abbrev, battalion_number]
	return _compact_fallback(unit, String(unit.get("id", "Unit")))

static func _bn_reg(battalion_number: int, regiment_number: int) -> String:
	if battalion_number <= 0 or regiment_number <= 0:
		return ""
	return "%d-%d" % [battalion_number, regiment_number]

static func _fallback_label(unit: Dictionary, default_label: String) -> String:
	var label := String(unit.get("display_name", unit.get("short_name", ""))).strip_edges()
	return label if not label.is_empty() else default_label

static func _compact_fallback(unit: Dictionary, default_label: String) -> String:
	var label := String(unit.get("short_name", "")).strip_edges()
	if label.is_empty():
		label = String(unit.get("display_name", "")).strip_edges()
	if label.is_empty():
		return default_label
	# Saved names from the full formatter may still contain a regiment suffix
	# such as 1/A/2-9. Strip that suffix when no structured designation was
	# available to format directly.
	if label.contains("/") and label.rfind("-") > label.rfind("/"):
		label = label.left(label.rfind("-"))
	var lower_label := label.to_lower()
	for echelon_word in [" regiment", " division"]:
		var echelon_index := lower_label.find(echelon_word)
		if echelon_index >= 0:
			label = label.left(echelon_index).strip_edges()
			lower_label = label.to_lower()
	return label if not label.is_empty() else default_label

static func _ordinal(value: int) -> String:
	var mod_100 := value % 100
	if mod_100 >= 11 and mod_100 <= 13:
		return "%dth" % value
	match value % 10:
		1:
			return "%dst" % value
		2:
			return "%dnd" % value
		3:
			return "%drd" % value
		_:
			return "%dth" % value

static func _support_abbreviation(unit_type: String, options: Dictionary) -> String:
	if unit_type == "heavy_weapons" and bool(options.get("use_hvy_for_weapons", false)):
		return "Hvy"
	if SUPPORT_TYPE_ABBREVIATIONS.has(unit_type):
		if unit_type == "heavy_weapons":
			return "W"
		return String(SUPPORT_TYPE_ABBREVIATIONS[unit_type])
	return ""
