extends Control
const UnitNotationFormatter = preload("res://scripts/domain/units/UnitNotationFormatter.gd")


@onready var nation_selector: OptionButton = %NationSelector
@onready var unit_tree: Tree = %UnitTree
@onready var add_unit_button: Button = %AddUnitButton
@onready var delete_button: Button = %DeleteButton
@onready var pending_unit_label: Label = %PendingUnitLabel
@onready var org_chart_view: OrgChartView = %OrgChartView
@onready var selected_name_label: Label = %SelectedUnitName
@onready var selected_meta_label: Label = %SelectedUnitMeta
@onready var veterancy_selector: OptionButton = %VeterancySelector
@onready var historical_description: RichTextLabel = %HistoricalDescription
@onready var template_name_input: LineEdit = %TemplateNameInput
@onready var template_selector: OptionButton = %TemplateSelector
@onready var save_template_button: Button = %SaveTemplateButton
@onready var load_template_button: Button = %LoadTemplateButton
@onready var start_deployment_button: Button = %StartDeploymentButton

var _root_unit: UnitModel
var _selected_unit: UnitModel
var _pending_unit_data: Dictionary = {}
var _id_counter := 1
var _builder_player_index := 0

func _ready() -> void:
	_build_nation_selector()
	_build_veterancy_selector()
	_initialize_organization(_default_nation_for_builder_player(_builder_player_index))

	unit_tree.cell_selected.connect(_on_unit_tree_selected)
	add_unit_button.pressed.connect(_on_add_unit_pressed)
	delete_button.pressed.connect(_on_delete_button_pressed)
	veterancy_selector.item_selected.connect(_on_veterancy_selected)
	org_chart_view.unit_selected.connect(_on_org_chart_selected)
	org_chart_view.delete_requested.connect(_on_org_chart_delete_requested)
	org_chart_view.unit_move_requested.connect(_on_org_chart_move_requested)
	save_template_button.pressed.connect(_on_save_template_pressed)
	load_template_button.pressed.connect(_on_load_template_pressed)
	start_deployment_button.pressed.connect(_on_start_deployment_pressed)

	_refresh_template_selector()
	_refresh_all()
	_update_builder_phase_ui()

func _build_nation_selector() -> void:
	nation_selector.clear()
	var nation_ids: Array = UnitCatalog.nations.keys()
	nation_ids.sort()
	for nation_id in nation_ids:
		var nation_data: Dictionary = UnitCatalog.nations[nation_id]
		nation_selector.add_item("%s (%s)" % [nation_data.get("name", nation_id), nation_id])
		nation_selector.set_item_metadata(nation_selector.item_count - 1, nation_id)
	nation_selector.item_selected.connect(_on_nation_changed)

func _build_veterancy_selector() -> void:
	veterancy_selector.clear()
	for level in Veterancy.Value.values():
		veterancy_selector.add_item(Veterancy.display_name(level))
		veterancy_selector.set_item_metadata(veterancy_selector.item_count - 1, level)

func _initialize_organization(default_nation: String = "") -> void:
	if default_nation.is_empty():
		default_nation = _default_nation_for_builder_player(_builder_player_index)
	if nation_selector.item_count > 0:
		var matching_index := 0
		for i in range(nation_selector.item_count):
			if String(nation_selector.get_item_metadata(i)) == default_nation:
				matching_index = i
				break
		nation_selector.select(matching_index)
		default_nation = String(nation_selector.get_item_metadata(matching_index))

	_root_unit = _create_unit("army_root", default_nation, UnitType.Value.HEADQUARTERS, UnitSize.Value.ARMY)
	_assign_unit_names()
	_selected_unit = _root_unit

func _create_unit(template_id: String, nation: String, unit_type: UnitType.Value, unit_size: UnitSize.Value) -> UnitModel:
	var unit := UnitModel.new()
	unit.id = "unit_%d" % _id_counter
	_id_counter += 1
	unit.template_id = template_id
	unit.nation = nation
	unit.type = unit_type
	unit.size = unit_size
	unit.veterancy = Veterancy.Value.REGULAR
	unit.status = "alive"
	unit.children = []
	return unit

func _refresh_all() -> void:
	_rebuild_unit_tree()
	org_chart_view.set_organization(_root_unit, _selected_unit)
	_update_pending_label()
	_update_right_panel()

func _rebuild_unit_tree() -> void:
	unit_tree.clear()
	unit_tree.columns = 1
	unit_tree.hide_root = true

	var root := unit_tree.create_item()
	var categories := _collect_templates_by_category()
	var category_names: Array = categories.keys()
	category_names.sort()

	for category_name in category_names:
		var category_item := unit_tree.create_item(root)
		category_item.set_text(0, category_name)
		category_item.set_selectable(0, false)
		category_item.collapsed = false

		for template_data in categories[category_name]:
			var template_item := unit_tree.create_item(category_item)
			var can_add := _can_add_template(template_data)
			template_item.set_text(0, _template_display_name(template_data))
			template_item.set_metadata(0, template_data)
			template_item.set_custom_color(0, Color(0.87, 0.87, 0.87) if can_add else Color(0.45, 0.45, 0.45))
			template_item.set_selectable(0, can_add)
			template_item.set_tooltip_text(0, "Can be added" if can_add else "Invalid for selected parent")

func _collect_templates_by_category() -> Dictionary:
	var grouped := {}
	var selected_nation := _selected_nation()
	var nation_templates: Array = UnitCatalog.get_nation_templates(selected_nation)
	if nation_templates.is_empty():
		nation_templates = _legacy_templates_for_nation(selected_nation)

	for template_variant in nation_templates:
		if typeof(template_variant) != TYPE_DICTIONARY:
			continue
		_collect_template_and_children(template_variant as Dictionary, selected_nation, grouped)

	return grouped

func _legacy_templates_for_nation(nation_id: String) -> Array:
	var legacy_templates: Array = []
	for template_id in UnitCatalog.unit_templates.keys():
		var template_variant: Variant = UnitCatalog.unit_templates.get(template_id, {})
		if typeof(template_variant) != TYPE_DICTIONARY:
			continue
		var template_data := (template_variant as Dictionary).duplicate(true)
		if String(template_data.get("nation", "")) != nation_id:
			continue
		template_data["id"] = String(template_data.get("id", template_id))
		template_data["display_name"] = String(template_data.get("display_name", template_data.get("name", template_id)))
		legacy_templates.append(template_data)
	return legacy_templates

func _collect_template_and_children(template_data: Dictionary, nation_id: String, grouped: Dictionary) -> void:
	var unit_type := _type_from_template(template_data)
	if unit_type == UnitType.Value.HEADQUARTERS:
		return

	var category := UnitType.display_name(unit_type)
	if not grouped.has(category):
		grouped[category] = []

	var template_id := String(template_data.get("id", template_data.get("display_name", "template")))
	var base_name := _normalize_template_name(String(template_data.get("display_name", template_id)))
	var base_template_id := _normalize_template_id(template_id)
	if _has_grouped_template(grouped[category], nation_id, unit_type, _size_from_template(template_data), base_name):
		return

	var template := {
		"id": base_template_id,
		"name": base_name,
		"display_name": base_name,
		"nation": nation_id,
		"type": unit_type,
		"size": _size_from_template(template_data),
		"count": 1,
		"children": template_data.get("children", []).duplicate(true)
	}
	grouped[category].append(template)

	var children_variant: Variant = template_data.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return
	for child_variant in children_variant:
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		_collect_template_and_children(child_variant as Dictionary, nation_id, grouped)

func _can_add_template(template_data: Dictionary) -> bool:
	if _selected_unit == null:
		return false
	var candidate := _create_unit("preview", String(template_data.get("nation", "usa")), template_data.get("type", UnitType.Value.INFANTRY), template_data.get("size", UnitSize.Value.COMPANY))
	candidate.id = "preview"
	return OrganizationValidator.can_add_child(_selected_unit, candidate)

func _template_display_name(template_data: Dictionary) -> String:
	var count := maxi(int(template_data.get("count", 1)), 1)
	var count_prefix := "%dx " % count if count > 1 else ""
	return "%s%s" % [
		count_prefix,
		String(template_data.get("name", "Unknown"))
	]

func _selected_nation() -> String:
	if nation_selector.item_count == 0:
		return "usa"
	return String(nation_selector.get_item_metadata(nation_selector.selected))

func _on_nation_changed(_index: int) -> void:
	_pending_unit_data.clear()
	_rebuild_unit_tree()
	_update_pending_label()

func _on_unit_tree_selected() -> void:
	var item := unit_tree.get_selected()
	if item == null:
		return
	var data = item.get_metadata(0)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_pending_unit_data = data
	_update_pending_label()

func _on_add_unit_pressed() -> void:
	if _pending_unit_data.is_empty() or _selected_unit == null:
		return

	var selected_parent := _selected_unit
	var nation := String(_pending_unit_data.get("nation", _selected_nation()))
	var top_level_count := maxi(int(_pending_unit_data.get("count", 1)), 1)
	var added_roots: Array[UnitModel] = []
	var added_requested_units: Array[UnitModel] = []

	for i in range(top_level_count):
		var requested_unit := _create_unit_from_template_tree(_pending_unit_data, nation, i + 1, top_level_count)
		var candidate := _wrap_candidate_with_required_hq(selected_parent, requested_unit, nation)
		_apply_auto_variant_to_candidate(selected_parent, candidate)
		var insertion_result := _insert_subtree_with_validation(selected_parent, candidate)
		if not bool(insertion_result.get("ok", false)):
			for added_root in added_roots:
				selected_parent.children.erase(added_root)
			pending_unit_label.text = "Cannot add template subtree: %s" % String(insertion_result.get("error", "Unknown validation failure"))
			_selected_unit = selected_parent
			_refresh_all()
			return
		added_roots.append(candidate)
		added_requested_units.append(requested_unit)

	if added_roots.is_empty():
		return

	_assign_unit_names()
	_selected_unit = added_requested_units[0] if not added_requested_units.is_empty() else added_roots[0]
	_refresh_all()

func _has_grouped_template(grouped_templates: Array, nation_id: String, unit_type: UnitType.Value, unit_size: UnitSize.Value, template_name: String) -> bool:
	for grouped_template_variant in grouped_templates:
		if typeof(grouped_template_variant) != TYPE_DICTIONARY:
			continue
		var grouped_template := grouped_template_variant as Dictionary
		if String(grouped_template.get("nation", "")) != nation_id:
			continue
		if int(grouped_template.get("type", UnitType.Value.INFANTRY)) != int(unit_type):
			continue
		if int(grouped_template.get("size", UnitSize.Value.COMPANY)) != int(unit_size):
			continue
		if _normalize_template_name(String(grouped_template.get("name", ""))) == template_name:
			return true
	return false

func _normalize_template_name(raw_name: String) -> String:
	var words := raw_name.strip_edges().split(" ")
	if words.is_empty():
		return raw_name
	var last_word := String(words[words.size() - 1])
	if last_word.is_valid_int():
		words.remove_at(words.size() - 1)
	return " ".join(words).strip_edges()

func _normalize_template_id(raw_template_id: String) -> String:
	var parts := raw_template_id.split("_")
	if parts.size() <= 1:
		return raw_template_id
	var last_part := String(parts[parts.size() - 1])
	if last_part.is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)

func _apply_auto_variant_to_candidate(parent: UnitModel, candidate: UnitModel) -> void:
	if parent == null or candidate == null:
		return

	var base_template_id := _normalize_template_id(candidate.template_id)
	var next_variant := _next_variant_index_for_parent(parent, base_template_id)
	candidate.template_id = base_template_id if next_variant <= 1 else "%s_%d" % [base_template_id, next_variant]

func _wrap_candidate_with_required_hq(parent: UnitModel, candidate: UnitModel, nation: String) -> UnitModel:
	if parent == null or candidate == null:
		return candidate
	if candidate.size != UnitSize.Value.BATTALION:
		return candidate

	var required_echelons: Array[int] = []
	if UnitSize.rank(parent.size) > UnitSize.rank(UnitSize.Value.DIVISION):
		required_echelons.append(UnitSize.Value.DIVISION)
	if UnitSize.rank(parent.size) > UnitSize.rank(UnitSize.Value.REGIMENT):
		required_echelons.append(UnitSize.Value.REGIMENT)

	var wrapped := candidate
	for i in range(required_echelons.size() - 1, -1, -1):
		var echelon_size := required_echelons[i]
		var wrapper_template_id := "auto_hq_%s" % _serialize_unit_size(echelon_size).to_lower()
		var wrapper := _create_unit(wrapper_template_id, nation, wrapped.type, echelon_size)
		wrapper.children = [wrapped]
		wrapped = wrapper

	return wrapped

func _next_variant_index_for_parent(parent: UnitModel, base_template_id: String) -> int:
	var next_variant := 1
	for child in parent.children:
		if child == null:
			continue
		if _normalize_template_id(child.template_id) != base_template_id:
			continue
		var suffix := _numeric_suffix(child.template_id)
		next_variant = maxi(next_variant, suffix + 1)
	return next_variant

func _numeric_suffix(template_id: String) -> int:
	var parts := template_id.split("_")
	if parts.is_empty():
		return 1
	var last_part := String(parts[parts.size() - 1])
	if last_part.is_valid_int():
		return maxi(int(last_part), 1)
	return 1

func _create_unit_from_template_tree(template_node: Dictionary, nation: String, instance_number: int = 1, instance_total: int = 1) -> UnitModel:
	var raw_template_id := String(template_node.get("id", "template"))
	var instance_template_id := raw_template_id
	if instance_total > 1:
		instance_template_id = "%s_%d" % [raw_template_id, instance_number]

	var parsed_type := _parse_unit_type(template_node.get("type", UnitType.Value.INFANTRY), template_node)
	var parsed_size := _parse_unit_size(template_node.get("size", UnitSize.Value.COMPANY), template_node)
	var unit := _create_unit(
		instance_template_id,
		nation,
		parsed_type,
		parsed_size
	)

	var children_variant: Variant = template_node.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return unit

	for child_variant in children_variant:
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var child_template := child_variant as Dictionary
		var child_count := maxi(int(child_template.get("count", 1)), 1)
		for i in range(child_count):
			var child_unit := _create_unit_from_template_tree(child_template, nation, i + 1, child_count)
			unit.children.append(child_unit)

	return unit

func _insert_subtree_with_validation(parent: UnitModel, candidate: UnitModel) -> Dictionary:
	if parent == null or candidate == null:
		return {
			"ok": false,
			"error": "Invalid parent or candidate."
		}

	var add_result := OrganizationValidator.can_add_child_detailed(parent, candidate)
	if not bool(add_result.get("ok", false)):
		return {
			"ok": false,
			"error": String(add_result.get("error", "%s cannot contain %s." % [_unit_label(parent), _unit_label(candidate)]))
		}

	parent.children.append(candidate)

	var planned_children: Array[UnitModel] = candidate.children.duplicate()
	candidate.children.clear()
	for child in planned_children:
		var child_result := _insert_subtree_with_validation(candidate, child)
		if not bool(child_result.get("ok", false)):
			parent.children.erase(candidate)
			return child_result

	return {
		"ok": true
	}

func _unit_label(unit: UnitModel) -> String:
	if unit == null:
		return "Unknown unit"
	var label := unit.display_name if not unit.display_name.is_empty() else UnitSize.display_name(unit.size)
	return "%s [%s]" % [label, unit.template_id]

func _on_delete_button_pressed() -> void:
	_delete_unit(_selected_unit)

func _on_org_chart_delete_requested(unit: UnitModel) -> void:
	_delete_unit(unit)

func _on_org_chart_move_requested(unit: UnitModel, new_parent: UnitModel) -> void:
	_move_unit(unit, new_parent)

func _delete_unit(unit: UnitModel) -> void:
	if unit == null or unit == _root_unit:
		return
	if _remove_child_recursive(_root_unit, unit.id):
		_assign_unit_names()
		_selected_unit = _root_unit
		_refresh_all()

func _move_unit(unit: UnitModel, new_parent: UnitModel) -> void:
	if unit == null or new_parent == null:
		return
	if unit == _root_unit:
		pending_unit_label.text = "Root unit cannot be moved."
		return
	if unit == new_parent:
		return
	if _contains_unit(unit, new_parent.id):
		pending_unit_label.text = "Cannot move a unit into its own subtree."
		return

	var current_parent := _find_parent(_root_unit, unit.id)
	if current_parent == null:
		return
	if current_parent == new_parent:
		return

	var move_result := OrganizationValidator.can_add_child_detailed(new_parent, unit)
	if not bool(move_result.get("ok", false)):
		pending_unit_label.text = "Cannot move: %s" % String(move_result.get("error", "%s cannot contain %s." % [_unit_label(new_parent), _unit_label(unit)]))
		return

	current_parent.children.erase(unit)
	new_parent.children.append(unit)
	_assign_unit_names()
	_selected_unit = unit
	_refresh_all()

func _remove_child_recursive(parent: UnitModel, target_id: String) -> bool:
	for i in range(parent.children.size()):
		var child: UnitModel = parent.children[i]
		if child != null and child.id == target_id:
			parent.children.remove_at(i)
			return true

	for child in parent.children:
		if child != null and _remove_child_recursive(child, target_id):
			return true

	return false

func _find_parent(parent: UnitModel, child_id: String) -> UnitModel:
	if parent == null:
		return null
	for child in parent.children:
		if child == null:
			continue
		if child.id == child_id:
			return parent
		var nested := _find_parent(child, child_id)
		if nested != null:
			return nested
	return null

func _contains_unit(parent: UnitModel, target_id: String) -> bool:
	if parent == null:
		return false
	if parent.id == target_id:
		return true
	for child in parent.children:
		if _contains_unit(child, target_id):
			return true
	return false

func _on_org_chart_selected(unit: UnitModel) -> void:
	if unit == null:
		return
	_selected_unit = unit
	_refresh_all()

func _on_veterancy_selected(index: int) -> void:
	if _selected_unit == null:
		return
	_selected_unit.veterancy = veterancy_selector.get_item_metadata(index)
	_update_right_panel()
	org_chart_view.queue_redraw()

func _update_pending_label() -> void:
	if _pending_unit_data.is_empty():
		pending_unit_label.text = "Pending Unit: None"
		return
	pending_unit_label.text = "Pending Unit: %s" % _template_display_name(_pending_unit_data)

func _update_right_panel() -> void:
	if _selected_unit == null:
		selected_name_label.text = "No unit selected"
		selected_meta_label.text = ""
		historical_description.text = ""
		delete_button.disabled = true
		return

	var selected_display := _selected_unit.display_name if not _selected_unit.display_name.is_empty() else UnitSize.display_name(_selected_unit.size)
	selected_name_label.text = selected_display
	selected_meta_label.text = "Type: %s\nNation: %s\nChildren: %d" % [
		UnitType.display_name(_selected_unit.type),
		_selected_unit.nation,
		_selected_unit.child_count()
	]
	delete_button.disabled = _selected_unit == _root_unit
	_set_selected_veterancy(_selected_unit.veterancy)
	historical_description.text = _historical_text_for(_selected_unit)

func _set_selected_veterancy(veterancy: Veterancy.Value) -> void:
	for i in range(veterancy_selector.item_count):
		if veterancy_selector.get_item_metadata(i) == veterancy:
			veterancy_selector.select(i)
			return

func _historical_text_for(unit: UnitModel) -> String:
	return "[b]Historical Note[/b]\n%s formations in %s doctrine commonly integrated %s sub-elements as command depth increased." % [
		UnitSize.display_name(unit.size),
		unit.nation.to_upper(),
		UnitType.display_name(unit.type).to_lower()
	]

func _on_save_template_pressed() -> void:
	var template_name := template_name_input.text.strip_edges()
	if template_name.is_empty():
		pending_unit_label.text = "Template name required."
		return
	var payload := {
		"root_unit": _unit_to_dict(_root_unit),
		"id_counter": _id_counter
	}
	if not SaveManager.save_division_template(template_name, payload):
		pending_unit_label.text = "Failed to save template."
		return
	_refresh_template_selector()
	_select_template(template_name.replace(" ", "_"))
	pending_unit_label.text = "Template saved: %s" % template_name

func _on_load_template_pressed() -> void:
	if template_selector.item_count == 0:
		pending_unit_label.text = "No template selected."
		return
	var template_name := String(template_selector.get_item_text(template_selector.selected))
	var payload: Dictionary = SaveManager.load_division_template(template_name)
	if payload.is_empty():
		pending_unit_label.text = "Failed to load template."
		return
	var loaded_root := _dict_to_unit(payload.get("root_unit", {}))
	if loaded_root == null:
		pending_unit_label.text = "Template data invalid."
		return
	_root_unit = loaded_root
	_selected_unit = _root_unit
	_id_counter = int(payload.get("id_counter", _next_id_from_tree(_root_unit)))
	_pending_unit_data.clear()
	_refresh_all()
	pending_unit_label.text = "Template loaded: %s" % template_name

func _on_start_deployment_pressed() -> void:
	var organization_validation := OrganizationValidator.validate_subtree(_root_unit)
	if not bool(organization_validation.get("ok", false)):
		pending_unit_label.text = "Cannot start deployment: %s" % String(organization_validation.get("error", "Organization validation failed."))
		return

	_ensure_players_initialized()
	GameState.players[_builder_player_index]["division_tree"] = _unit_to_dict(_root_unit)
	GameState.players[_builder_player_index]["deployments"] = {}
	if _builder_player_index == 0:
		GameState.players[1]["controller"] = "ai"
		GameState.players[1]["is_ai"] = true
		_builder_player_index = 1
		_reset_builder_for_next_player()
		return
	if GameState.map_flow == GameState.MapFlow.PLAY_SAVED_MAP:
		GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)
		return
	GameState.set_phase(GameState.Phase.MAP_SETUP)

func _ensure_players_initialized() -> void:
	while GameState.players.size() < 2:
		GameState.players.append({
			"name": "Player %d" % (GameState.players.size() + 1),
			"division_tree": {},
			"deployments": {},
			"controller": "human"
		})

	for i in range(2):
		if not GameState.players[i].has("deployments"):
			GameState.players[i]["deployments"] = {}
		if not GameState.players[i].has("controller"):
			GameState.players[i]["controller"] = "human"

func _reset_builder_for_next_player() -> void:
	# Keep IDs globally unique across both sides so gameplay deployment dictionaries do not collide.
	_pending_unit_data.clear()
	_initialize_organization(_default_nation_for_builder_player(_builder_player_index))
	_refresh_all()
	_update_builder_phase_ui()

func _update_builder_phase_ui() -> void:
	if _builder_player_index == 0:
		start_deployment_button.text = "Submit Player Units"
		return
	start_deployment_button.text = "Submit AI Units & Continue"
	pending_unit_label.text = "Configure AI unit structure, then submit to continue."

func _default_nation_for_builder_player(player_index: int) -> String:
	var selected_nation := String(GameState.selected_nation_id)
	if selected_nation.is_empty():
		selected_nation = "usa"
	if player_index == 0:
		return selected_nation
	return _opposing_nation_id(selected_nation)

func _opposing_nation_id(nation_id: String) -> String:
	var normalized := nation_id.strip_edges().to_lower()
	if normalized == "usa":
		return "germany"
	if normalized == "germany":
		return "usa"
	return nation_id

func _refresh_template_selector() -> void:
	template_selector.clear()
	var templates: PackedStringArray = SaveManager.list_division_templates()
	for template_name in templates:
		template_selector.add_item(template_name)
	if template_selector.item_count > 0:
		template_selector.select(0)

func _select_template(template_name: String) -> void:
	for i in range(template_selector.item_count):
		if template_selector.get_item_text(i) == template_name:
			template_selector.select(i)
			return

func _unit_to_dict(unit: UnitModel) -> Dictionary:
	if unit == null:
		return {}
	var serialized_children: Array[Dictionary] = []
	for child in unit.children:
		serialized_children.append(_unit_to_dict(child))
	return {
		"id": unit.id,
		"template_id": unit.template_id,
		"display_name": unit.display_name,
		"short_name": unit.short_name,
		"designation": _normalize_designation_payload(unit.get_meta("designation_payload", {}), unit),
		"nation": unit.nation,
		"type": int(unit.type),
		"size": _serialize_unit_size(unit.size),
		"veterancy": int(unit.veterancy),
		"status": String(unit.status).to_lower(),
		"is_alive": String(unit.status).to_lower() != "dead",
		"children": serialized_children
	}

func _serialize_unit_size(size: UnitSize.Value) -> String:
	match size:
		UnitSize.Value.SQUAD:
			return "SQUAD"
		UnitSize.Value.SECTION:
			return "SECTION"
		UnitSize.Value.PLATOON:
			return "PLATOON"
		UnitSize.Value.COMPANY:
			return "COMPANY"
		UnitSize.Value.BATTALION:
			return "BATTALION"
		UnitSize.Value.REGIMENT:
			return "REGIMENT"
		UnitSize.Value.DIVISION:
			return "DIVISION"
		UnitSize.Value.ARMY:
			return "ARMY"
		_:
			return "PLATOON"

func _dict_to_unit(data: Variant) -> UnitModel:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var raw := data as Dictionary
	var unit := UnitModel.new()
	unit.id = String(raw.get("id", ""))
	unit.template_id = String(raw.get("template_id", ""))
	unit.display_name = String(raw.get("display_name", ""))
	unit.short_name = String(raw.get("short_name", ""))
	unit.set_meta("designation_payload", _designation_from_raw(raw, unit))
	unit.nation = String(raw.get("nation", ""))
	unit.type = _parse_unit_type(raw.get("type", UnitType.Value.INFANTRY), raw)
	var raw_size: Variant = raw.get("size", UnitSize.Value.PLATOON)
	var size_context := raw.duplicate(true)
	if typeof(raw_size) == TYPE_INT:
		size_context["_legacy_size_index"] = true
	unit.size = _parse_unit_size(raw_size, size_context)
	unit.veterancy = int(raw.get("veterancy", Veterancy.Value.REGULAR))
	var raw_status := String(raw.get("status", ""))
	if raw_status.is_empty():
		unit.status = "alive" if bool(raw.get("is_alive", true)) else "dead"
	else:
		unit.status = raw_status.to_lower()
	unit.children = []
	for child_data in raw.get("children", []):
		var child := _dict_to_unit(child_data)
		if child != null:
			unit.children.append(child)
	return unit

func _assign_unit_names() -> void:
	if _root_unit == null:
		return
	_assign_unit_names_recursive(_root_unit, null)

func _assign_unit_names_recursive(unit: UnitModel, parent: UnitModel) -> void:
	if unit == null:
		return

	var sibling_index := 1
	if parent != null:
		sibling_index = _sibling_index_for_naming(parent, unit)

	var designation := _designation_for_echelon(unit, sibling_index, parent)
	unit.set_meta("designation_payload", designation)
	var names := _display_names_for_designation(unit, designation)
	unit.display_name = String(names.get("display_name", "Unit"))
	unit.short_name = String(names.get("short_name", ""))

	for child in unit.children:
		_assign_unit_names_recursive(child, unit)

func _designation_for_echelon(unit: UnitModel, sibling_index: int, parent: UnitModel) -> Dictionary:
	var size := unit.size
	var regiment_number := 0
	var battalion_number := 0
	var company_letter := ""
	var platoon_number := 0
	if parent != null:
		var parent_designation := parent.get_meta("designation_payload", {}) as Dictionary
		regiment_number = int(parent_designation.get("regiment_number", 0))
		battalion_number = int(parent_designation.get("battalion_number", 0))
		company_letter = String(parent_designation.get("company_letter", ""))
	match size:
		UnitSize.Value.REGIMENT:
			regiment_number = sibling_index
		UnitSize.Value.BATTALION:
			battalion_number = sibling_index
		UnitSize.Value.COMPANY:
			company_letter = _alphabet_designation(sibling_index)
		UnitSize.Value.PLATOON:
			platoon_number = sibling_index
	return _normalize_designation_payload({
		"regiment_number": regiment_number,
		"battalion_number": battalion_number,
		"company_letter": company_letter,
		"platoon_number": platoon_number,
		"role_echelon": UnitSize.display_name(size)
	}, unit)


func _display_names_for_designation(unit: UnitModel, designation: Dictionary) -> Dictionary:
	var size := unit.size
	var designation_nth := 1
	match size:
		UnitSize.Value.DIVISION:
			designation_nth = max(int(designation.get("regiment_number", 0)), 1)
		UnitSize.Value.REGIMENT:
			designation_nth = max(int(designation.get("regiment_number", 0)), 1)
		UnitSize.Value.BATTALION:
			designation_nth = max(int(designation.get("battalion_number", 0)), 1)
		UnitSize.Value.SECTION:
			designation_nth = max(int(designation.get("platoon_number", 0)), 1)
		UnitSize.Value.SQUAD:
			designation_nth = max(int(designation.get("platoon_number", 0)), 1)
		_:
			designation_nth = max(int(designation.get("battalion_number", 0)), 1)
	var nth := _ordinal(designation_nth)
	var type_label := UnitType.display_name(unit.type)
	var is_auto_hq := unit.template_id.begins_with("auto_hq_")
	var battalion_number := int(designation.get("battalion_number", 0))
	var regiment_number := int(designation.get("regiment_number", 0))
	var company_letter := String(designation.get("company_letter", ""))
	var platoon_number := int(designation.get("platoon_number", 0))
	if unit.type == UnitType.Value.HEADQUARTERS:
		if size == UnitSize.Value.BATTALION:
			var battalion_hq := UnitNotationFormatter.format_unit({
				"type": "headquarters",
				"size": "battalion",
				"designation": designation
			})
			return {"display_name": battalion_hq, "short_name": battalion_hq}
		return {
			"display_name": "%s HQ" % UnitSize.display_name(size),
			"short_name": "%s HQ" % UnitSize.display_name(size)
		}
	if is_auto_hq and (size == UnitSize.Value.REGIMENT or size == UnitSize.Value.DIVISION):
		return {
			"display_name": "%s HQ" % UnitSize.display_name(size),
			"short_name": "%s HQ" % UnitSize.display_name(size)
		}
	match size:
		UnitSize.Value.BATTALION:
			var bn_notation := UnitNotationFormatter.format_unit({"type": type_label.to_lower(), "size": "battalion", "designation": designation})
			return {"display_name": bn_notation, "short_name": bn_notation}
		UnitSize.Value.COMPANY:
			var company_notation := UnitNotationFormatter.format_unit({"type": type_label.to_lower(), "size": "company", "designation": designation})
			return {"display_name": company_notation, "short_name": company_notation}
		UnitSize.Value.PLATOON:
			var platoon_notation := UnitNotationFormatter.format_unit({"type": type_label.to_lower(), "size": "platoon", "designation": designation})
			return {"display_name": platoon_notation, "short_name": platoon_notation}
		_:
			return {"display_name": "%s %s" % [nth, UnitSize.display_name(size)], "short_name": "%s" % nth}

func _designation_from_raw(raw: Dictionary, unit: UnitModel) -> Dictionary:
	var existing: Variant = raw.get("designation", {})
	if typeof(existing) == TYPE_DICTIONARY and not (existing as Dictionary).is_empty():
		return _normalize_designation_payload(existing as Dictionary, unit)
	return _migrate_designation_from_legacy_names(String(raw.get("display_name", "")), String(raw.get("short_name", "")), unit)

func _normalize_designation_payload(raw_designation: Dictionary, unit: UnitModel) -> Dictionary:
	return {
		"regiment_number": maxi(int(raw_designation.get("regiment_number", 0)), 0),
		"battalion_number": maxi(int(raw_designation.get("battalion_number", 0)), 0),
		"company_letter": String(raw_designation.get("company_letter", "")).strip_edges().to_upper(),
		"platoon_number": maxi(int(raw_designation.get("platoon_number", 0)), 0),
		"role_echelon": String(raw_designation.get("role_echelon", UnitSize.display_name(unit.size))).strip_edges()
	}

func _migrate_designation_from_legacy_names(display_name: String, short_name: String, unit: UnitModel) -> Dictionary:
	var merged := (display_name + " " + short_name).strip_edges()
	var company_letter := ""
	var platoon_number := 0
	var battalion_number := 0
	var regiment_number := 0
	var company_match := RegEx.new()
	company_match.compile("([A-Z]{1,2})\\s*(?:CO|COMPANY)")
	var cm := company_match.search(merged.to_upper())
	if cm != null:
		company_letter = cm.get_string(1)
	var platoon_match := RegEx.new()
	platoon_match.compile("(\\d+)\\s*(?:PLT|PLATOON)")
	var pm := platoon_match.search(merged.to_upper())
	if pm != null:
		platoon_number = int(pm.get_string(1))
	var bn_match := RegEx.new()
	bn_match.compile("(\\d+)\\s*(?:BN|BATTALION)")
	var bm := bn_match.search(merged.to_upper())
	if bm != null:
		battalion_number = int(bm.get_string(1))
	var reg_match := RegEx.new()
	reg_match.compile("(\\d+)\\s*(?:REGT|REGIMENT)")
	var rm := reg_match.search(merged.to_upper())
	if rm != null:
		regiment_number = int(rm.get_string(1))
	return _normalize_designation_payload({
		"regiment_number": regiment_number,
		"battalion_number": battalion_number,
		"company_letter": company_letter,
		"platoon_number": platoon_number,
		"role_echelon": UnitSize.display_name(unit.size)
	}, unit)

func _sibling_index_for_naming(parent: UnitModel, unit: UnitModel) -> int:
	var same_size_index := 0
	for sibling in parent.children:
		if sibling == null:
			continue
		if sibling.size != unit.size:
			continue

		var include_in_index := true
		if unit.size == UnitSize.Value.COMPANY and sibling.type == UnitType.Value.HEADQUARTERS:
			include_in_index = unit.type == UnitType.Value.HEADQUARTERS

		if include_in_index:
			same_size_index += 1
		if sibling == unit:
			return max(same_size_index, 1)

	return 1

func _ordinal(value: int) -> String:
	var positive_value := maxi(value, 1)
	var remainder_hundred := positive_value % 100
	var suffix := "th"
	if remainder_hundred < 11 or remainder_hundred > 13:
		match positive_value % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [positive_value, suffix]

func _alphabet_designation(value: int) -> String:
	var index := maxi(value, 1)
	var letters := ""
	while index > 0:
		var remainder := (index - 1) % 26
		letters = char(65 + remainder) + letters
		index = int((index - 1) / 26)
	return letters

func _next_id_from_tree(root: UnitModel) -> int:
	return _collect_highest_id(root, 0) + 1

func _collect_highest_id(unit: UnitModel, current_highest: int) -> int:
	if unit == null:
		return current_highest
	var pieces := unit.id.split("_")
	if pieces.size() > 1:
		current_highest = maxi(current_highest, int(pieces[pieces.size() - 1]))
	for child in unit.children:
		current_highest = _collect_highest_id(child, current_highest)
	return current_highest

func _type_from_template(data: Dictionary) -> UnitType.Value:
	return _parse_unit_type(data.get("type", ""), data)

func _size_from_template(data: Dictionary) -> UnitSize.Value:
	if data.has("size"):
		return _parse_unit_size(data.get("size", ""), {})

	var inferred_size: int = _infer_size_from_children(data)
	if inferred_size >= 0:
		return inferred_size

	return _parse_unit_size("", data)

func _infer_size_from_children(data: Dictionary) -> int:
	var children_variant: Variant = data.get("children", [])
	if typeof(children_variant) != TYPE_ARRAY:
		return -1

	var children := children_variant as Array
	if children.is_empty():
		return -1

	var largest_child_rank := -1
	for child_variant in children:
		if typeof(child_variant) != TYPE_DICTIONARY:
			continue
		var child_data := child_variant as Dictionary
		var child_size := _size_from_template(child_data)
		largest_child_rank = maxi(largest_child_rank, UnitSize.rank(child_size))

	if largest_child_rank < 0:
		return -1

	var inferred_rank := largest_child_rank + 1
	for size_value in UnitSize.Value.values():
		if UnitSize.rank(size_value) == inferred_rank:
			return size_value

	return -1

func _parse_unit_type(raw_type: Variant, fallback_data: Dictionary) -> UnitType.Value:
	if typeof(raw_type) == TYPE_INT:
		var type_value := int(raw_type)
		if UnitType.Value.values().has(type_value):
			return type_value
	elif typeof(raw_type) == TYPE_STRING:
		var normalized_type := String(raw_type).to_upper()
		var type_map := {
			"INFANTRY": UnitType.Value.INFANTRY,
			"TANK": UnitType.Value.TANK,
			"ENGINEER": UnitType.Value.ENGINEER,
			"ARTILLERY": UnitType.Value.ARTILLERY,
			"RECON": UnitType.Value.RECON,
			"AIRBORNE": UnitType.Value.AIRBORNE,
			"MECHANIZED": UnitType.Value.MECHANIZED,
			"MOTORIZED": UnitType.Value.MOTORIZED,
			"ANTI_TANK": UnitType.Value.ANTI_TANK,
			"AIR_DEFENSE": UnitType.Value.AIR_DEFENSE,
			"HEADQUARTERS": UnitType.Value.HEADQUARTERS
		}
		if type_map.has(normalized_type):
			return type_map[normalized_type]

	var tags: Array = fallback_data.get("tags", [])
	if tags.has("infantry"):
		return UnitType.Value.INFANTRY
	if tags.has("line"):
		return UnitType.Value.MOTORIZED
	return UnitType.Value.RECON

func _parse_unit_size(raw_size: Variant, fallback_data: Dictionary) -> UnitSize.Value:
	var legacy_size_map := {
		0: UnitSize.Value.PLATOON,
		1: UnitSize.Value.COMPANY,
		2: UnitSize.Value.BATTALION,
		3: UnitSize.Value.REGIMENT,
		4: UnitSize.Value.DIVISION,
		5: UnitSize.Value.ARMY,
		6: UnitSize.Value.SECTION,
		7: UnitSize.Value.SQUAD
	}

	if typeof(raw_size) == TYPE_INT:
		var size_value := int(raw_size)
		if bool(fallback_data.get("_legacy_size_index", false)) and legacy_size_map.has(size_value):
			return legacy_size_map[size_value]
		if UnitSize.Value.values().has(size_value):
			return size_value
		if legacy_size_map.has(size_value):
			return legacy_size_map[size_value]
	elif typeof(raw_size) == TYPE_STRING:
		var normalized_size := String(raw_size).strip_edges().to_upper()
		var size_map := {
			"PLATOON": UnitSize.Value.PLATOON,
			"SECTION": UnitSize.Value.SECTION,
			"SQUAD": UnitSize.Value.SQUAD,
			"COMPANY": UnitSize.Value.COMPANY,
			"BATTALION": UnitSize.Value.BATTALION,
			"REGIMENT": UnitSize.Value.REGIMENT,
			"DIVISION": UnitSize.Value.DIVISION,
			"ARMY": UnitSize.Value.ARMY
		}
		if size_map.has(normalized_size):
			return size_map[normalized_size]

	var points := int(fallback_data.get("points", 100))
	if points < 80:
		return UnitSize.Value.SQUAD
	if points < 120:
		return UnitSize.Value.SECTION
	if points < 180:
		return UnitSize.Value.PLATOON
	if points < 260:
		return UnitSize.Value.COMPANY
	if points < 360:
		return UnitSize.Value.BATTALION
	if points < 460:
		return UnitSize.Value.REGIMENT
	return UnitSize.Value.DIVISION
