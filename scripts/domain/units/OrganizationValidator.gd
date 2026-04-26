class_name OrganizationValidator
extends RefCounted

const MAX_CHILDREN := 6
const MAX_SAME_TYPE_CHILDREN := 4
const _ANY_TYPE_KEY := -1
const _DESCENDANT_FALLBACK_TYPES := {
	UnitType.Value.ENGINEER: true,
}
const REQUIRED_CHILD_MIX_BY_ECHELON_AND_TYPE := {
	UnitSize.Value.DIVISION: {
		_ANY_TYPE_KEY: {
			UnitType.Value.INFANTRY: 2,
			UnitType.Value.ARTILLERY: 1,
			UnitType.Value.ENGINEER: 1,
		}
	},
	UnitSize.Value.REGIMENT: {
		UnitType.Value.INFANTRY: {
			UnitType.Value.INFANTRY: 2,
			UnitType.Value.ARTILLERY: 1,
		}
	},
	UnitSize.Value.BATTALION: {
		UnitType.Value.INFANTRY: {
			UnitType.Value.INFANTRY: 2,
		}
	},
	UnitSize.Value.COMPANY: {
		UnitType.Value.INFANTRY: {
			UnitType.Value.INFANTRY: 2,
		}
	},
	UnitSize.Value.PLATOON: {
		UnitType.Value.INFANTRY: {
			UnitType.Value.INFANTRY: 1,
		}
	},
}

static func can_add_child(parent: UnitModel, candidate: UnitModel) -> bool:
	return bool(can_add_child_detailed(parent, candidate).get("ok", false))

static func can_add_child_detailed(parent: UnitModel, candidate: UnitModel, enforce_composition: bool = false) -> Dictionary:
	if parent == null or candidate == null:
		return {
			"ok": false,
			"error": "Invalid parent or child."
		}

	if parent.children.size() >= MAX_CHILDREN:
		return {
			"ok": false,
			"error": "%s already has the maximum of %d children." % [UnitSize.display_name(parent.size), MAX_CHILDREN]
		}

	var same_type_count := 0
	for child in parent.children:
		if child != null and child.type == candidate.type:
			same_type_count += 1
	if same_type_count >= MAX_SAME_TYPE_CHILDREN:
		return {
			"ok": false,
			"error": "%s already has %d %s child units (max %d)." % [
				UnitSize.display_name(parent.size),
				same_type_count,
				UnitType.display_name(candidate.type),
				MAX_SAME_TYPE_CHILDREN
			]
		}

	if not UnitSize.can_contain(parent.size, candidate.size):
		return {
			"ok": false,
			"error": "%s cannot contain %s." % [UnitSize.display_name(parent.size), UnitSize.display_name(candidate.size)]
		}

	if enforce_composition:
		var simulated_children: Array[UnitModel] = parent.children.duplicate()
		simulated_children.append(candidate)
		var mix_result := _validate_required_child_mix(parent, simulated_children)
		if not bool(mix_result.get("ok", false)):
			return mix_result

	return {
		"ok": true
	}

static func validate_subtree(root: UnitModel) -> Dictionary:
	if root == null:
		return {
			"ok": false,
			"error": "Organization root is missing."
		}

	return _validate_subtree_recursive(root)

static func _validate_subtree_recursive(node: UnitModel) -> Dictionary:
	if node == null:
		return {
			"ok": false,
			"error": "Organization contains an invalid unit."
		}

	var mix_result := _validate_required_child_mix(node, node.children)
	if not bool(mix_result.get("ok", false)):
		return mix_result

	for child in node.children:
		if child == null:
			return {
				"ok": false,
				"error": "Organization contains an empty child slot under %s." % UnitSize.display_name(node.size)
			}
		if not UnitSize.can_contain(node.size, child.size):
			return {
				"ok": false,
				"error": "%s cannot contain %s." % [UnitSize.display_name(node.size), UnitSize.display_name(child.size)]
			}
		var child_result := _validate_subtree_recursive(child)
		if not bool(child_result.get("ok", false)):
			return child_result

	return {
		"ok": true
	}

static func _validate_required_child_mix(parent: UnitModel, children: Array[UnitModel]) -> Dictionary:
	var mix := _required_mix_for_parent(parent)
	if mix.is_empty():
		return {
			"ok": true
		}

	# Allow placeholder/leaf organizations to be submitted without forcing
	# synthetic child units. Composition checks are enforced once a parent
	# actually has subordinate formations.
	if children.is_empty():
		return {
			"ok": true
		}

	var child_counts := _count_children_by_type(children)
	var descendant_counts := _count_descendants_by_type(children)
	var missing_parts: Array[String] = []
	for unit_type in mix.keys():
		var required_count := int(mix.get(unit_type, 0))
		if required_count <= 0:
			continue
		var actual_count := int(child_counts.get(unit_type, 0))
		if actual_count < required_count and _DESCENDANT_FALLBACK_TYPES.has(unit_type):
			actual_count = int(descendant_counts.get(unit_type, 0))
		if actual_count < required_count:
			missing_parts.append("%d %s (has %d)" % [required_count, UnitType.display_name(unit_type), actual_count])

	if missing_parts.is_empty():
		return {
			"ok": true
		}

	return {
		"ok": false,
		"error": "%s requires child mix: %s." % [UnitSize.display_name(parent.size), ", ".join(missing_parts)]
	}

static func _required_mix_for_parent(parent: UnitModel) -> Dictionary:
	if parent == null:
		return {}
	var by_type: Dictionary = REQUIRED_CHILD_MIX_BY_ECHELON_AND_TYPE.get(parent.size, {})
	if by_type.is_empty():
		return {}
	if by_type.has(parent.type):
		return by_type[parent.type]
	return by_type.get(_ANY_TYPE_KEY, {})

static func _count_children_by_type(children: Array[UnitModel]) -> Dictionary:
	var counts := {}
	for child in children:
		if child == null:
			continue
		counts[child.type] = int(counts.get(child.type, 0)) + 1
	return counts

static func _count_descendants_by_type(children: Array[UnitModel]) -> Dictionary:
	var counts := {}
	for child in children:
		_count_descendants_recursive(child, counts)
	return counts

static func _count_descendants_recursive(unit: UnitModel, counts: Dictionary) -> void:
	if unit == null:
		return
	counts[unit.type] = int(counts.get(unit.type, 0)) + 1
	for child in unit.children:
		_count_descendants_recursive(child, counts)
