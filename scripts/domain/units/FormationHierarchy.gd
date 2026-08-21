class_name FormationHierarchy
extends RefCounted

static func find_node(root: Dictionary, unit_id: String) -> Dictionary:
	var path := path_to(root, unit_id)
	return path[path.size() - 1] as Dictionary if not path.is_empty() else {}

static func parent_node(root: Dictionary, unit_id: String) -> Dictionary:
	var path := path_to(root, unit_id)
	return path[path.size() - 2] as Dictionary if path.size() >= 2 else {}

static func path_to(root: Dictionary, unit_id: String) -> Array[Dictionary]:
	var path: Array[Dictionary] = []
	if unit_id.is_empty():
		return path
	_find_path_recursive(root, unit_id, path)
	return path

static func verbal_path(root: Dictionary, unit_id: String) -> String:
	var labels: Array[String] = []
	for node in path_to(root, unit_id):
		var size := _size_name(node)
		if size == "army" or _is_headquarters(node):
			continue
		var label := _verbal_label(node)
		if not label.is_empty():
			labels.append(label)
	return ", ".join(labels)

static func casualty_name(root: Dictionary, unit_id: String) -> String:
	var path := path_to(root, unit_id)
	if path.is_empty():
		return unit_id
	var unit := path[path.size() - 1]
	var size := _size_name(unit)
	if size == "squad":
		var company := _nearest_size(path, "company")
		var squad_number := _descendant_ordinal(company, unit_id, "squad")
		var designation := unit.get("designation", {}) as Dictionary
		var company_letter := String(designation.get("company_letter", "")).strip_edges().to_upper()
		var battalion_number := int(designation.get("battalion_number", 0))
		var regiment_number := int(designation.get("regiment_number", 0))
		if squad_number > 0 and not company_letter.is_empty() and battalion_number > 0 and regiment_number > 0:
			return "%d/%s/%d/%d Squad" % [squad_number, company_letter, battalion_number, regiment_number]
	return _display_name(unit, unit_id)

static func _find_path_recursive(node: Dictionary, unit_id: String, path: Array[Dictionary]) -> bool:
	if node.is_empty():
		return false
	path.append(node)
	if String(node.get("id", "")) == unit_id:
		return true
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) == TYPE_ARRAY:
		for child_variant in children_variant as Array:
			if child_variant is Dictionary and _find_path_recursive(child_variant as Dictionary, unit_id, path):
				return true
	path.pop_back()
	return false

static func _verbal_label(node: Dictionary) -> String:
	var size := _size_name(node)
	var designation := node.get("designation", {}) as Dictionary
	match size:
		"regiment":
			var regiment_number := int(designation.get("regiment_number", 0))
			if regiment_number > 0:
				return "%s Regiment" % _ordinal(regiment_number)
		"battalion":
			var battalion_number := int(designation.get("battalion_number", 0))
			if battalion_number > 0:
				return "%s Battalion" % _ordinal(battalion_number)
		"company":
			var company_letter := String(designation.get("company_letter", "")).strip_edges().to_upper()
			if not company_letter.is_empty():
				return "%s Company" % company_letter
		"platoon":
			var platoon_number := int(designation.get("platoon_number", 0))
			if platoon_number > 0:
				return "%s Platoon" % _ordinal(platoon_number)
	return _display_name(node, UnitSize.display_name(_size_value(node)))

static func _display_name(node: Dictionary, fallback: String) -> String:
	for key in ["name", "display_name", "short_name"]:
		var value := String(node.get(key, "")).strip_edges()
		if not value.is_empty() and not value.begins_with("unit_"):
			return value
	return fallback

static func _nearest_size(path: Array[Dictionary], wanted_size: String) -> Dictionary:
	for index in range(path.size() - 1, -1, -1):
		var node := path[index]
		if _size_name(node) == wanted_size:
			return node
	return {}

static func _descendant_ordinal(root: Dictionary, unit_id: String, wanted_size: String) -> int:
	if root.is_empty():
		return 0
	var ids: Array[String] = []
	_collect_descendants_by_size(root, wanted_size, ids)
	var index := ids.find(unit_id)
	return index + 1 if index >= 0 else 0

static func _collect_descendants_by_size(node: Dictionary, wanted_size: String, ids: Array[String]) -> void:
	if _size_name(node) == wanted_size and not _is_headquarters(node):
		ids.append(String(node.get("id", "")))
	var children_variant: Variant = node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	for child_variant in children_variant as Array:
		if child_variant is Dictionary:
			_collect_descendants_by_size(child_variant as Dictionary, wanted_size, ids)

static func _is_headquarters(node: Dictionary) -> bool:
	var role := String(node.get("role", "")).strip_edges().to_lower()
	if role == "headquarters":
		return true
	var raw_type: Variant = node.get("type", "")
	if typeof(raw_type) == TYPE_INT:
		return int(raw_type) == UnitType.Value.HEADQUARTERS
	return String(raw_type).strip_edges().to_lower() == "headquarters"

static func _size_name(node: Dictionary) -> String:
	var raw_size: Variant = node.get("size", "")
	if typeof(raw_size) == TYPE_INT:
		return UnitSize.display_name(int(raw_size)).to_lower()
	return String(raw_size).strip_edges().to_lower()

static func _size_value(node: Dictionary) -> int:
	var size := _size_name(node)
	match size:
		"squad": return UnitSize.Value.SQUAD
		"section": return UnitSize.Value.SECTION
		"platoon": return UnitSize.Value.PLATOON
		"company": return UnitSize.Value.COMPANY
		"battalion": return UnitSize.Value.BATTALION
		"regiment": return UnitSize.Value.REGIMENT
		"division": return UnitSize.Value.DIVISION
		"army": return UnitSize.Value.ARMY
	return UnitSize.Value.PLATOON

static func _ordinal(number: int) -> String:
	var remainder_100 := number % 100
	if remainder_100 >= 11 and remainder_100 <= 13:
		return "%dth" % number
	match number % 10:
		1: return "%dst" % number
		2: return "%dnd" % number
		3: return "%drd" % number
		_: return "%dth" % number
