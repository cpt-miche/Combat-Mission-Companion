class_name FormationOperations
extends RefCounted

const UnitEquipmentWeight = preload("res://scripts/domain/units/UnitEquipmentWeight.gd")

static func combine(units: Dictionary, orders: Dictionary, root: Dictionary, selected_ids: Array[String], owner: int) -> Dictionary:
	var selection := _selected_units(units, selected_ids)
	if selection.size() < 2:
		return _failure(units, orders, "Select at least two formation components to combine.")
	var validation := _validate_common_state(selection, owner)
	if not bool(validation.get("ok", false)):
		return _failure(units, orders, String(validation.get("reason", "Selected formations cannot combine.")))

	var existing_parent: Dictionary = {}
	for unit in selection:
		if bool(unit.get("is_combined_formation", false)):
			if not existing_parent.is_empty():
				return _failure(units, orders, "Only one existing combined parent can absorb components at a time.")
			existing_parent = unit

	var target_parent: Dictionary = {}
	if not existing_parent.is_empty():
		target_parent = FormationHierarchy.find_node(root, String(existing_parent.get("id", "")))
		for unit in selection:
			if unit == existing_parent:
				continue
			var parent := FormationHierarchy.parent_node(root, String(unit.get("id", "")))
			if String(parent.get("id", "")) != String(target_parent.get("id", "")):
				return _failure(units, orders, "Combined formations must belong to the same immediate parent unit.")
	else:
		var first_parent := FormationHierarchy.parent_node(root, String(selection[0].get("id", "")))
		if first_parent.is_empty():
			return _failure(units, orders, "The selected formations have no common organization parent.")
		for unit in selection:
			var parent := FormationHierarchy.parent_node(root, String(unit.get("id", "")))
			if String(parent.get("id", "")) != String(first_parent.get("id", "")):
				return _failure(units, orders, "Combined formations must belong to the same immediate parent unit.")
		target_parent = first_parent

	var parent_size := _size_name(target_parent)
	if parent_size not in ["company", "battalion"]:
		return _failure(units, orders, "Formations can only combine into a company or battalion.")
	var target_id := String(target_parent.get("id", ""))
	if target_id.is_empty():
		return _failure(units, orders, "The parent formation is missing an ID.")
	if units.has(target_id) and existing_parent.is_empty():
		return _failure(units, orders, "The parent formation is already present on the map.")

	var components: Array[Dictionary] = []
	if not existing_parent.is_empty():
		for component_variant in existing_parent.get("combined_components", []) as Array:
			if component_variant is Dictionary:
				components.append((component_variant as Dictionary).duplicate(true))
	for unit in selection:
		if unit == existing_parent:
			continue
		components.append(unit.duplicate(true))

	var combined := gameplay_snapshot(target_parent, selection[0], owner)
	combined["is_combined_formation"] = true
	combined["combined_components"] = components
	_merge_component_state(combined, components)

	var next_units := units.duplicate(true)
	for selected_id in selected_ids:
		next_units.erase(selected_id)
	next_units[target_id] = combined
	var stack_check := _validate_result_stack(next_units, combined)
	if not bool(stack_check.get("ok", false)):
		return _failure(units, orders, String(stack_check.get("reason", "The combined formation would exceed the stack limit.")))
	var next_orders := orders.duplicate(true)
	for selected_id in selected_ids:
		next_orders.erase(selected_id)
	return {"ok": true, "reason": "Combined into %s." % _unit_name(combined), "units": next_units, "orders": next_orders, "selected_ids": [target_id]}

static func split(units: Dictionary, orders: Dictionary, root: Dictionary, selected_id: String, owner: int, validate_result_stack: bool = true) -> Dictionary:
	if selected_id.is_empty() or not units.has(selected_id) or not (units[selected_id] is Dictionary):
		return _failure(units, orders, "Select one company or battalion to split.")
	var parent := units[selected_id] as Dictionary
	if int(parent.get("owner", -1)) != owner or not GameState.is_unit_alive(parent):
		return _failure(units, orders, "Only a living friendly formation can be split.")
	if _size_name(parent) not in ["company", "battalion"]:
		return _failure(units, orders, "Only companies and battalions can be split.")

	var components: Array[Dictionary] = []
	if bool(parent.get("is_combined_formation", false)):
		for component_variant in parent.get("combined_components", []) as Array:
			if component_variant is Dictionary:
				components.append((component_variant as Dictionary).duplicate(true))
	else:
		var tree_parent := FormationHierarchy.find_node(root, selected_id)
		for child_variant in tree_parent.get("children", []) as Array:
			if not (child_variant is Dictionary):
				continue
			var child := child_variant as Dictionary
			if not GameState.is_unit_alive(child) or _is_headquarters(child) or _size_rank(child) < UnitSize.Value.PLATOON:
				continue
			components.append(gameplay_snapshot(child, parent, owner))
	if components.size() < 2:
		return _failure(units, orders, "This formation does not contain at least two deployable components.")

	var parent_hex := parent.get("hex", Vector2i.ZERO) as Vector2i
	for component in components:
		var component_id := String(component.get("id", ""))
		if component_id.is_empty() or (units.has(component_id) and component_id != selected_id):
			return _failure(units, orders, "A component of this formation is already present on the map.")
		component["owner"] = owner
		component["hex"] = parent_hex
		if bool(parent.get("moved", false)):
			component["moved"] = true
		if bool(parent.get("acted", false)):
			component["acted"] = true
		if bool(parent.get("dug_in", false)):
			component["dug_in"] = true

	var next_units := units.duplicate(true)
	next_units.erase(selected_id)
	var component_ids: Array[String] = []
	for component in components:
		var component_id := String(component.get("id", ""))
		next_units[component_id] = component
		component_ids.append(component_id)
	if validate_result_stack:
		var stack_check := _validate_result_stack(next_units, components[0])
		if not bool(stack_check.get("ok", false)):
			return _failure(units, orders, String(stack_check.get("reason", "The split components would exceed the stack limit.")))
	var next_orders := orders.duplicate(true)
	next_orders.erase(selected_id)
	return {"ok": true, "reason": "Split %s into %d components." % [_unit_name(parent), components.size()], "units": next_units, "orders": next_orders, "selected_ids": component_ids}

static func _selected_units(units: Dictionary, selected_ids: Array[String]) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for unit_id in selected_ids:
		if units.has(unit_id) and units[unit_id] is Dictionary:
			selected.append(units[unit_id] as Dictionary)
	return selected

static func _validate_common_state(selection: Array[Dictionary], owner: int) -> Dictionary:
	var expected_hex := selection[0].get("hex", Vector2i.ZERO) as Vector2i
	for unit in selection:
		if int(unit.get("owner", -1)) != owner or not GameState.is_unit_alive(unit):
			return {"ok": false, "reason": "Only living friendly formations can combine."}
		if unit.get("hex", Vector2i.ZERO) as Vector2i != expected_hex:
			return {"ok": false, "reason": "Combined formations must occupy the same hex."}
		if _size_rank(unit) < UnitSize.Value.PLATOON:
			return {"ok": false, "reason": "Formations below platoon level cannot combine."}
	return {"ok": true}

static func gameplay_snapshot(tree_node: Dictionary, source: Dictionary, owner: int) -> Dictionary:
	var unit_type: Variant = tree_node.get("type", "infantry")
	var display_name := String(tree_node.get("display_name", tree_node.get("id", "Unit")))
	var snapshot := {
		"id": String(tree_node.get("id", "")),
		"template_id": String(tree_node.get("template_id", "")),
		"display_name": display_name,
		"short_name": String(tree_node.get("short_name", display_name)),
		"designation": (tree_node.get("designation", {}) as Dictionary).duplicate(true),
		"owner": owner,
		"hex": source.get("hex", Vector2i.ZERO),
		"initiative": int(source.get("initiative", 50)),
		"type": String(unit_type),
		"role": UnitRole.normalize(tree_node.get("role", ""), unit_type),
		"equipment_weight": UnitEquipmentWeight.for_unit(tree_node),
		"size": _size_name(tree_node),
		"is_attached": bool(tree_node.get("is_attached", false)),
		"status": String(tree_node.get("status", "alive")).to_lower(),
		"recon_bonus": int(source.get("recon_bonus", 5)),
		"concealment": int(source.get("concealment", 5)),
		"moved": bool(source.get("moved", false)),
		"acted": bool(source.get("acted", false)),
		"dug_in": bool(source.get("dug_in", false))
	}
	var vehicles := tree_node.get("vehicles", []) as Array
	if not vehicles.is_empty():
		snapshot["vehicles"] = vehicles.duplicate(true)
		snapshot["live_sub_units"] = _living_vehicle_count(vehicles)
		snapshot["max_sub_units"] = vehicles.size()
	if source.has("label"):
		snapshot["label"] = String(source.get("label", ""))
	if source.has("combined_components"):
		snapshot["combined_components"] = (source.get("combined_components", []) as Array).duplicate(true)
		snapshot["is_combined_formation"] = bool(source.get("is_combined_formation", false))
	return snapshot

static func _living_vehicle_count(vehicles: Array) -> int:
	var living := 0
	for vehicle_variant in vehicles:
		if vehicle_variant is Dictionary and GameState.is_unit_alive(vehicle_variant as Dictionary):
			living += 1
	return living

static func _merge_component_state(combined: Dictionary, components: Array[Dictionary]) -> void:
	var all_dug_in := not components.is_empty()
	var any_moved := false
	var any_acted := false
	var concealment := 999999
	for component in components:
		all_dug_in = all_dug_in and bool(component.get("dug_in", false))
		any_moved = any_moved or bool(component.get("moved", false))
		any_acted = any_acted or bool(component.get("acted", false))
		concealment = mini(concealment, int(component.get("concealment", 5)))
	combined["dug_in"] = all_dug_in
	combined["moved"] = any_moved
	combined["acted"] = any_acted
	combined["concealment"] = 5 if concealment == 999999 else concealment

static func _validate_result_stack(units: Dictionary, changed_unit: Dictionary) -> Dictionary:
	var changed_hex := changed_unit.get("hex", Vector2i.ZERO) as Vector2i
	var owner := int(changed_unit.get("owner", -1))
	var stack: Array[Dictionary] = []
	for unit_variant in units.values():
		if unit_variant is Dictionary:
			var unit := unit_variant as Dictionary
			if int(unit.get("owner", -1)) == owner and (unit.get("hex", Vector2i.ZERO) as Vector2i) == changed_hex:
				stack.append(unit)
	return Rules.validate_stack(stack)

static func _failure(units: Dictionary, orders: Dictionary, reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "units": units, "orders": orders, "selected_ids": []}

static func _size_name(unit: Dictionary) -> String:
	var raw_size: Variant = unit.get("size", "")
	if typeof(raw_size) == TYPE_INT:
		return UnitSize.display_name(int(raw_size)).to_lower()
	return String(raw_size).strip_edges().to_lower()

static func _size_rank(unit: Dictionary) -> int:
	match _size_name(unit):
		"squad": return UnitSize.Value.SQUAD
		"section": return UnitSize.Value.SECTION
		"platoon": return UnitSize.Value.PLATOON
		"company": return UnitSize.Value.COMPANY
		"battalion": return UnitSize.Value.BATTALION
		"regiment": return UnitSize.Value.REGIMENT
		"division": return UnitSize.Value.DIVISION
		"army": return UnitSize.Value.ARMY
	return -1

static func _is_headquarters(unit: Dictionary) -> bool:
	var role := String(unit.get("role", "")).strip_edges().to_lower()
	if role == "headquarters":
		return true
	var raw_type: Variant = unit.get("type", "")
	return (typeof(raw_type) == TYPE_INT and int(raw_type) == UnitType.Value.HEADQUARTERS) or String(raw_type).strip_edges().to_lower() == "headquarters"

static func _unit_name(unit: Dictionary) -> String:
	return String(unit.get("display_name", unit.get("id", "formation")))
