class_name OrganizationValidator
extends RefCounted

const MAX_CHILDREN := 6
const MAX_SAME_TYPE_CHILDREN := 4

static func can_add_child(parent: UnitModel, candidate: UnitModel) -> bool:
	if parent == null or candidate == null:
		return false

	if parent.children.size() >= MAX_CHILDREN:
		return false

	var same_type_count := 0
	for child in parent.children:
		if child != null and child.type == candidate.type:
			same_type_count += 1
	if same_type_count >= MAX_SAME_TYPE_CHILDREN:
		return false

	if not UnitSize.can_contain(parent.size, candidate.size):
		return false

	return true
