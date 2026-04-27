class_name OrganizationValidator
extends RefCounted

const MAX_CHILDREN := 6
const MAX_SAME_TYPE_CHILDREN := 4

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

	var structure_result := _validate_subtree_recursive(root)
	if not bool(structure_result.get("ok", false)):
		return structure_result

	if not _has_deployable_company_or_larger(root):
		return {
			"ok": false,
			"error": "Organization must include at least 1 company-sized unit (or larger) before deployment."
		}

	return {
		"ok": true
	}

static func _validate_subtree_recursive(node: UnitModel) -> Dictionary:
	if node == null:
		return {
			"ok": false,
			"error": "Organization contains an invalid unit."
		}

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

static func _validate_required_child_mix(_parent: UnitModel, _children: Array[UnitModel]) -> Dictionary:
	# Minimum composition requirements are intentionally disabled.
	# Force structure is constrained by containment and upper limits only.
	return {
		"ok": true
	}

static func _has_deployable_company_or_larger(root: UnitModel) -> bool:
	if root == null:
		return false
	for child in root.children:
		if _contains_company_or_larger(child):
			return true
	return false

static func _contains_company_or_larger(unit: UnitModel) -> bool:
	if unit == null:
		return false
	if UnitSize.rank(unit.size) >= UnitSize.rank(UnitSize.Value.COMPANY):
		return true
	for child in unit.children:
		if _contains_company_or_larger(child):
			return true
	return false
