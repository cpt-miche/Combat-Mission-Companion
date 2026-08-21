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
@onready var undo_button: Button = %UndoButton
@onready var root_margin: MarginContainer = $RootMargin
@onready var scenario_editor_chrome: Control = %ScenarioEditorChrome

const MAX_UNDO_HISTORY := 50

var _root_unit: UnitModel
var _selected_unit: UnitModel
var _pending_unit_data: Dictionary = {}
var _id_counter := 1
var _builder_player_index := 0
var _undo_history: Array[Dictionary] = []
var _restoring_snapshot := false
var _last_selected_nation := ""

func _ready() -> void:
	if ScenarioEditorState.active:
		_builder_player_index = ScenarioEditorState.editor_side
	_build_nation_selector()
	_build_veterancy_selector()
	if ScenarioEditorState.active:
		_load_editor_builder_player(_builder_player_index, false)
	else:
		_initialize_organization(_default_nation_for_builder_player(_builder_player_index))
	_last_selected_nation = _selected_nation()

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
	undo_button.pressed.connect(_on_undo_pressed)

	_refresh_template_selector()
	_refresh_all()
	_update_builder_phase_ui()
	if ScenarioEditorState.active:
		root_margin.offset_top = 56.0
		scenario_editor_chrome.configure()
		scenario_editor_chrome.back_requested.connect(_on_scenario_editor_back)
		scenario_editor_chrome.before_draft_save.connect(_on_scenario_editor_before_draft_save)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_Z and key_event.ctrl_pressed:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return
		_on_undo_pressed()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode != KEY_DELETE:
		return
	if _selected_unit == null or _selected_unit == _root_unit:
		return
	_delete_unit(_selected_unit)
	get_viewport().set_input_as_handled()

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

	_root_unit = _create_unit("army_root", default_nation, UnitType.Value.HEADQUARTERS, UnitSize.Value.ARMY, "headquarters")
	_assign_unit_names()
	_selected_unit = _root_unit

func _create_unit(template_id: String, nation: String, unit_type: UnitType.Value, unit_size: UnitSize.Value, unit_role: String = "") -> UnitModel:
	var unit := UnitModel.new()
	unit.id = "unit_%d" % _id_counter
	_id_counter += 1
	unit.template_id = template_id
	unit.nation = nation
	unit.type = unit_type
	unit.role = UnitRole.normalize(unit_role, unit_type)
	unit.equipment_weight = ""
	unit.size = unit_size
	unit.display_name = UnitSize.display_name(unit_size)
	unit.short_name = unit.display_name
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

	for template_variant in nation_templates:
		if typeof(template_variant) != TYPE_DICTIONARY:
			continue
		_collect_template_and_children(template_variant as Dictionary, selected_nation, grouped)

	return grouped

func _collect_template_and_children(template_data: Dictionary, nation_id: String, grouped: Dictionary) -> void:
	var unit_type := _type_from_template(template_data)
	if unit_type == UnitType.Value.HEADQUARTERS:
		return
	var unit_size := _size_from_template(template_data)
	if UnitSize.rank(unit_size) < UnitSize.rank(UnitSize.Value.PLATOON):
		return

	var normalized_role := UnitRole.normalize(
		template_data.get("role", ""),
		unit_type
	)
	var category := "Tank Destroyer" if normalized_role == "tank_destroyer" else UnitType.display_name(unit_type)
	if not grouped.has(category):
		grouped[category] = []

	var template_id := String(template_data.get("id", template_data.get("display_name", "template")))
	var base_name := _normalize_template_name(String(template_data.get("display_name", template_id)))
	if _has_grouped_template(grouped[category], nation_id, template_id):
		return

	var template := {
		"id": template_id,
		"name": base_name,
		"display_name": base_name,
		"nation": nation_id,
		"type": _serialize_unit_type(unit_type),
		"role": normalized_role,
		"size": _serialize_unit_size(unit_size),
		"count": 1,
		"vehicle_roster": template_data.get("vehicle_roster", []).duplicate(true),
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
	var candidate := _create_unit("preview", String(template_data.get("nation", "usa")), _type_from_template(template_data), _size_from_template(template_data), String(template_data.get("role", "")))
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
	if not _restoring_snapshot and not _last_selected_nation.is_empty() and _last_selected_nation != _selected_nation():
		var snapshot := _capture_builder_snapshot()
		snapshot["selected_nation"] = _last_selected_nation
		_record_undo_snapshot(snapshot)
	_last_selected_nation = _selected_nation()
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
	var undo_snapshot := _capture_builder_snapshot()
	var nation := String(_pending_unit_data.get("nation", _selected_nation()))
	var top_level_count := maxi(int(_pending_unit_data.get("count", 1)), 1)
	var added_roots: Array[UnitModel] = []
	var added_requested_units: Array[UnitModel] = []

	for i in range(top_level_count):
		var requested_unit := _create_unit_from_template_tree(_pending_unit_data, nation, i + 1, top_level_count)
		requested_unit.is_attached = selected_parent.size != UnitSize.Value.ARMY
		var insertion_result := _insert_subtree_with_validation(selected_parent, requested_unit)
		if not bool(insertion_result.get("ok", false)):
			for added_root in added_roots:
				selected_parent.children.erase(added_root)
			pending_unit_label.text = "Cannot add template subtree: %s" % String(insertion_result.get("error", "Unknown validation failure"))
			_selected_unit = selected_parent
			_refresh_all()
			return
		added_roots.append(requested_unit)
		added_requested_units.append(requested_unit)

	if added_roots.is_empty():
		return

	_record_undo_snapshot(undo_snapshot)
	_assign_unit_names()
	_selected_unit = added_requested_units[0] if not added_requested_units.is_empty() else added_roots[0]
	_refresh_all()

func _has_grouped_template(grouped_templates: Array, nation_id: String, template_id: String) -> bool:
	for grouped_template_variant in grouped_templates:
		if typeof(grouped_template_variant) != TYPE_DICTIONARY:
			continue
		var grouped_template := grouped_template_variant as Dictionary
		if String(grouped_template.get("nation", "")) != nation_id:
			continue
		if String(grouped_template.get("id", "")) == template_id:
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

func _create_unit_from_template_tree(template_node: Dictionary, nation: String, instance_number: int = 1, instance_total: int = 1) -> UnitModel:
	var raw_template_id := String(template_node.get("id", "template"))

	var parsed_type := _parse_unit_type(template_node.get("type", ""))
	var parsed_size := _parse_unit_size(template_node.get("size", ""))
	var unit := _create_unit(
		raw_template_id,
		nation,
		parsed_type,
		parsed_size,
		UnitRole.normalize(template_node.get("role", ""), parsed_type)
	)
	unit.vehicles = _expand_vehicle_roster(unit.id, template_node.get("vehicle_roster", []))
	unit.equipment_weight = String(template_node.get("equipment_weight", "")).strip_edges().to_lower()

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

func _expand_vehicle_roster(unit_id: String, roster_variant: Variant) -> Array[Dictionary]:
	var vehicles: Array[Dictionary] = []
	if not (roster_variant is Array):
		return vehicles
	var vehicle_index := 1
	for entry_variant in roster_variant as Array:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var model := String(entry.get("model", "Vehicle")).strip_edges()
		var slot := String(entry.get("slot", "line_vehicle")).strip_edges().to_lower()
		var count := maxi(int(entry.get("count", 1)), 1)
		for slot_index in range(count):
			var display_name := _vehicle_display_name(model, slot, slot_index + 1)
			vehicles.append({
				"id": "%s:vehicle:%d" % [unit_id, vehicle_index],
				"model": model,
				"slot": slot,
				"display_name": display_name,
				"status": "alive"
			})
			vehicle_index += 1
	return vehicles

func _vehicle_display_name(model: String, slot: String, line_number: int) -> String:
	match slot:
		"platoon_commander":
			return "Commander %s" % model
		"battalion_commander":
			return "Battalion Commander %s" % model
		"company_commander":
			return "Company Commander %s" % model
		"executive_officer":
			return "Executive Officer %s" % model
		_:
			return "%s %d" % [model, line_number]

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
	return "%s — %s [%s]" % [label, UnitRole.display_name(unit.role, unit.type), unit.template_id]

func _on_delete_button_pressed() -> void:
	_delete_unit(_selected_unit)

func _on_org_chart_delete_requested(unit: UnitModel) -> void:
	_delete_unit(unit)

func _on_org_chart_move_requested(unit: UnitModel, new_parent: UnitModel) -> void:
	_move_unit(unit, new_parent)

func _delete_unit(unit: UnitModel) -> void:
	if unit == null or unit == _root_unit:
		return
	var undo_snapshot := _capture_builder_snapshot()
	if _remove_child_recursive(_root_unit, unit.id):
		_record_undo_snapshot(undo_snapshot)
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

	var undo_snapshot := _capture_builder_snapshot()
	current_parent.children.erase(unit)
	new_parent.children.append(unit)
	_record_undo_snapshot(undo_snapshot)
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
	var next_veterancy: Veterancy.Value = veterancy_selector.get_item_metadata(index)
	if _selected_unit.veterancy == next_veterancy:
		return
	var undo_snapshot := _capture_builder_snapshot()
	_selected_unit.veterancy = next_veterancy
	_record_undo_snapshot(undo_snapshot)
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
	selected_meta_label.text = "Role: %s\nClass: %s\nNation: %s\nChildren: %d" % [
		UnitRole.display_name(_selected_unit.role, _selected_unit.type),
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
		UnitRole.display_name(unit.role, unit.type).to_lower()
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
		pending_unit_label.text = SaveManager.get_last_load_error()
		return
	var loaded_root := _dict_to_unit(payload.get("root_unit", {}))
	if loaded_root == null:
		pending_unit_label.text = "Template data invalid."
		return
	var undo_snapshot := _capture_builder_snapshot()
	_root_unit = loaded_root
	_selected_unit = _root_unit
	_id_counter = int(payload.get("id_counter", _next_id_from_tree(_root_unit)))
	_pending_unit_data.clear()
	_record_undo_snapshot(undo_snapshot)
	_refresh_all()
	pending_unit_label.text = "Template loaded: %s" % template_name

func _on_start_deployment_pressed() -> void:
	var organization_validation := OrganizationValidator.validate_subtree(_root_unit)
	if not bool(organization_validation.get("ok", false)):
		pending_unit_label.text = "Cannot start deployment: %s" % String(organization_validation.get("error", "Organization validation failed."))
		return

	_ensure_players_initialized()
	if ScenarioEditorState.active:
		_commit_scenario_editor_force()
	else:
		GameState.players[_builder_player_index]["division_tree"] = _unit_to_dict(_root_unit)
		GameState.players[_builder_player_index]["deployments"] = {}
	if ScenarioEditorState.active:
		if _builder_player_index == 0:
			ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_2_FORCES, 1)
			_clear_undo_history()
			_load_editor_builder_player(1)
			return
		ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_DEPLOYMENT, 0)
		_clear_undo_history()
		GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)
		return
	if _builder_player_index == 0:
		GameState.players[1]["controller"] = "ai"
		_builder_player_index = 1
		_clear_undo_history()
		_reset_builder_for_next_player()
		return
	if GameState.map_flow == GameState.MapFlow.PLAY_SAVED_MAP:
		_clear_undo_history()
		GameState.set_phase(GameState.Phase.DEPLOYMENT_P1)
		return
	_clear_undo_history()
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
	_last_selected_nation = _selected_nation()
	_refresh_all()
	_update_builder_phase_ui()

func _update_builder_phase_ui() -> void:
	if ScenarioEditorState.active:
		start_deployment_button.text = "Continue to Player %d" % (2 if _builder_player_index == 0 else 1)
		if _builder_player_index == 1:
			start_deployment_button.text = "Continue to Player 1 Deployment"
		pending_unit_label.text = "Author Player %d's complete force structure." % (_builder_player_index + 1)
		return
	if _builder_player_index == 0:
		start_deployment_button.text = "Submit Player Units"
		return
	start_deployment_button.text = "Submit AI Units & Continue"
	pending_unit_label.text = "Configure AI unit structure, then submit to continue."

func _default_nation_for_builder_player(player_index: int) -> String:
	if ScenarioEditorState.active and player_index >= 0 and player_index < GameState.players.size():
		var authored_nation := String((GameState.players[player_index] as Dictionary).get("nation_id", "")).strip_edges().to_lower()
		if not authored_nation.is_empty():
			return authored_nation
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

func _load_editor_builder_player(player_index: int, refresh: bool = true) -> void:
	_ensure_players_initialized()
	_builder_player_index = clampi(player_index, 0, 1)
	ScenarioEditorState.editor_side = _builder_player_index
	var tree := (GameState.players[_builder_player_index] as Dictionary).get("division_tree", {}) as Dictionary
	if tree.is_empty():
		_id_counter = maxi(_id_counter, _next_editor_global_id())
		_initialize_organization(_default_nation_for_builder_player(_builder_player_index))
	else:
		var loaded := _dict_to_unit(tree)
		if loaded == null:
			_initialize_organization(_default_nation_for_builder_player(_builder_player_index))
		else:
			_root_unit = loaded
			_selected_unit = _root_unit
			_id_counter = _next_id_from_tree(_root_unit)
			_id_counter = maxi(_id_counter, _next_editor_global_id())
			_select_builder_nation(String(_root_unit.nation))
	_last_selected_nation = _selected_nation()
	_pending_unit_data.clear()
	if refresh:
		_refresh_all()
		_update_builder_phase_ui()
		scenario_editor_chrome.configure()

func _next_editor_global_id() -> int:
	var highest := 0
	for player_variant in GameState.players:
		if player_variant is Dictionary:
			highest = maxi(highest, _highest_generated_id((player_variant as Dictionary).get("division_tree", {}) as Dictionary))
	return highest + 1

func _highest_generated_id(node: Dictionary) -> int:
	if node.is_empty():
		return 0
	var highest := 0
	var unit_id := String(node.get("id", ""))
	if unit_id.begins_with("unit_") and unit_id.trim_prefix("unit_").is_valid_int():
		highest = int(unit_id.trim_prefix("unit_"))
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			highest = maxi(highest, _highest_generated_id(child_variant as Dictionary))
	return highest

func _select_builder_nation(nation_id: String) -> void:
	for index in range(nation_selector.item_count):
		if String(nation_selector.get_item_metadata(index)) == nation_id:
			nation_selector.select(index)
			return

func _commit_scenario_editor_force() -> void:
	_ensure_players_initialized()
	var player := GameState.players[_builder_player_index] as Dictionary
	var previous_nation := String(player.get("nation_id", ""))
	var selected_nation := _selected_nation()
	if not previous_nation.is_empty() and previous_nation != selected_nation:
		player["deployments"] = {}
	player["nation_id"] = selected_nation
	GameState.players[_builder_player_index] = player
	GameState.players[_builder_player_index]["division_tree"] = _unit_to_dict(_root_unit)
	ScenarioEditorState.reconcile_deployments(_builder_player_index)
	ScenarioEditorState.capture_from_game_state()

func _on_scenario_editor_before_draft_save() -> void:
	_commit_scenario_editor_force()

func _on_scenario_editor_back() -> void:
	_commit_scenario_editor_force()
	if _builder_player_index == 1:
		ScenarioEditorState.set_step(ScenarioEditorState.Step.PLAYER_1_FORCES, 0)
		_load_editor_builder_player(0)
		return
	ScenarioEditorState.set_step(ScenarioEditorState.Step.MAP)
	GameState.set_phase(GameState.Phase.MAP_SETUP)

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
		"type": _serialize_unit_type(unit.type),
		"role": UnitRole.normalize(unit.role, unit.type),
		"equipment_weight": unit.equipment_weight,
		"size": _serialize_unit_size(unit.size),
		"is_attached": unit.is_attached,
		"veterancy": int(unit.veterancy),
		"status": String(unit.status).to_lower(),
		"vehicles": unit.vehicles.duplicate(true),
		"children": serialized_children
	}

func _capture_builder_snapshot() -> Dictionary:
	return {
		"root_unit": _unit_to_dict(_root_unit),
		"selected_unit_id": _selected_unit.id if _selected_unit != null else "",
		"selected_nation": _selected_nation(),
		"id_counter": _id_counter,
		"pending_unit_data": _pending_unit_data.duplicate(true)
	}

func _record_undo_snapshot(snapshot: Dictionary) -> void:
	if _restoring_snapshot or snapshot.is_empty():
		return
	_undo_history.append(snapshot.duplicate(true))
	while _undo_history.size() > MAX_UNDO_HISTORY:
		_undo_history.pop_front()
	_update_undo_button()

func _on_undo_pressed() -> void:
	if _undo_history.is_empty():
		return
	var snapshot := _undo_history.pop_back() as Dictionary
	_restore_builder_snapshot(snapshot)
	_update_undo_button()

func _restore_builder_snapshot(snapshot: Dictionary) -> void:
	var restored_root := _dict_to_unit(snapshot.get("root_unit", {}))
	if restored_root == null:
		return
	_restoring_snapshot = true
	var nation_id := String(snapshot.get("selected_nation", _selected_nation()))
	for index in range(nation_selector.item_count):
		if String(nation_selector.get_item_metadata(index)) == nation_id:
			nation_selector.select(index)
			break
	_root_unit = restored_root
	_id_counter = int(snapshot.get("id_counter", _next_id_from_tree(_root_unit)))
	_pending_unit_data = (snapshot.get("pending_unit_data", {}) as Dictionary).duplicate(true)
	var selected_id := String(snapshot.get("selected_unit_id", ""))
	_selected_unit = _find_unit_by_id(_root_unit, selected_id)
	if _selected_unit == null:
		_selected_unit = _root_unit
	_last_selected_nation = _selected_nation()
	_restoring_snapshot = false
	_refresh_all()
	pending_unit_label.text = "Undid organization edit."

func _find_unit_by_id(unit: UnitModel, unit_id: String) -> UnitModel:
	if unit == null:
		return null
	if unit.id == unit_id:
		return unit
	for child in unit.children:
		var found := _find_unit_by_id(child, unit_id)
		if found != null:
			return found
	return null

func _clear_undo_history() -> void:
	_undo_history.clear()
	_update_undo_button()

func _update_undo_button() -> void:
	if is_instance_valid(undo_button):
		undo_button.disabled = _undo_history.is_empty()

func _serialize_unit_size(size: UnitSize.Value) -> String:
	match size:
		UnitSize.Value.SQUAD:
			return "squad"
		UnitSize.Value.SECTION:
			return "section"
		UnitSize.Value.PLATOON:
			return "platoon"
		UnitSize.Value.COMPANY:
			return "company"
		UnitSize.Value.BATTALION:
			return "battalion"
		UnitSize.Value.REGIMENT:
			return "regiment"
		UnitSize.Value.DIVISION:
			return "division"
		UnitSize.Value.ARMY:
			return "army"
		_:
			return "platoon"

func _serialize_unit_type(type: UnitType.Value) -> String:
	return UnitType.display_name(type).to_lower().replace("-", "_").replace(" ", "_")

func _dict_to_unit(data: Variant) -> UnitModel:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var raw := data as Dictionary
	for field_name in ["id", "display_name", "type", "role", "size", "status"]:
		if not (raw.get(field_name) is String) or String(raw.get(field_name)).strip_edges().is_empty():
			return null
	if not (raw.get("designation") is Dictionary) or not (raw.get("children") is Array):
		return null
	if not (raw.get("is_attached") is bool):
		return null
	var unit := UnitModel.new()
	unit.id = String(raw.get("id", ""))
	unit.template_id = String(raw.get("template_id", ""))
	unit.display_name = String(raw.get("display_name", ""))
	unit.short_name = String(raw.get("short_name", ""))
	unit.nation = String(raw.get("nation", ""))
	unit.type = _parse_unit_type(raw.get("type"))
	unit.role = UnitRole.normalize(raw.get("role", ""), unit.type)
	unit.equipment_weight = String(raw.get("equipment_weight", "")).strip_edges().to_lower()
	unit.size = _parse_unit_size(raw.get("size"))
	unit.is_attached = bool(raw.get("is_attached"))
	unit.set_meta("designation_payload", _normalize_designation_payload(raw.get("designation") as Dictionary, unit))
	unit.veterancy = int(raw.get("veterancy", Veterancy.Value.REGULAR))
	unit.status = String(raw.get("status")).to_lower()
	if unit.status not in ["alive", "dead"]:
		return null
	unit.vehicles = []
	for vehicle_variant in raw.get("vehicles", []) as Array:
		if vehicle_variant is Dictionary:
			unit.vehicles.append((vehicle_variant as Dictionary).duplicate(true))
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
	var names := _display_names_for_designation(unit, designation, sibling_index)
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
	var attached_company_index := 0
	if parent != null:
		var parent_designation := parent.get_meta("designation_payload", {}) as Dictionary
		regiment_number = int(parent_designation.get("regiment_number", 0))
		battalion_number = int(parent_designation.get("battalion_number", 0))
		company_letter = String(parent_designation.get("company_letter", ""))
		attached_company_index = int(parent_designation.get("attached_company_index", 0))
	match size:
		UnitSize.Value.REGIMENT:
			regiment_number = sibling_index
		UnitSize.Value.BATTALION:
			battalion_number = sibling_index
		UnitSize.Value.COMPANY:
			if unit.is_attached:
				attached_company_index = _attachment_index_for(parent, unit)
				company_letter = ""
			else:
				attached_company_index = 0
				company_letter = _company_letter_for(unit, parent, sibling_index, battalion_number)
		UnitSize.Value.PLATOON:
			platoon_number = sibling_index
	return _normalize_designation_payload({
		"regiment_number": regiment_number,
		"battalion_number": battalion_number,
		"company_letter": company_letter,
		"platoon_number": platoon_number,
		"attached_company_index": attached_company_index,
		"role_echelon": UnitSize.display_name(size)
	}, unit)

func _company_letter_for(unit: UnitModel, parent: UnitModel, sibling_index: int, battalion_number: int) -> String:
	if unit.is_attached:
		return ""
	if unit.nation.strip_edges().to_lower() != "usa" or battalion_number < 1 or battalion_number > 3:
		return _alphabet_designation(sibling_index)
	var company_slot := _usa_company_slot(parent, unit)
	var letter_blocks := {
		1: ["A", "B", "C", "D"],
		2: ["E", "F", "G", "H"],
		3: ["I", "K", "L", "M"]
	}
	var battalion_letters := letter_blocks[battalion_number] as Array
	if company_slot >= 1 and company_slot <= battalion_letters.size():
		return String(battalion_letters[company_slot - 1])
	return _alphabet_designation(sibling_index)

func _usa_company_slot(parent: UnitModel, unit: UnitModel) -> int:
	if unit.role in ["weapons", "heavy_weapons"]:
		return 4
	var line_company_index := 0
	if parent == null:
		return 1
	for sibling in parent.children:
		if sibling == null or sibling.size != UnitSize.Value.COMPANY or sibling.type == UnitType.Value.HEADQUARTERS:
			continue
		if sibling.is_attached:
			continue
		if sibling.role in ["weapons", "heavy_weapons"]:
			continue
		line_company_index += 1
		if sibling == unit:
			return line_company_index
	return maxi(line_company_index, 1)

func _attachment_index_for(parent: UnitModel, unit: UnitModel) -> int:
	if parent == null:
		return 1
	var attached_index := 0
	for sibling in parent.children:
		if sibling == null or sibling.size != unit.size or not sibling.is_attached:
			continue
		attached_index += 1
		if sibling == unit:
			return attached_index
	return maxi(attached_index, 1)


func _display_names_for_designation(unit: UnitModel, designation: Dictionary, sibling_index: int) -> Dictionary:
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
			designation_nth = maxi(sibling_index, 1)
		UnitSize.Value.SQUAD:
			designation_nth = maxi(sibling_index, 1)
		_:
			designation_nth = max(int(designation.get("battalion_number", 0)), 1)
	var nth := _ordinal(designation_nth)
	var type_label := UnitType.display_name(unit.type)
	if unit.is_attached:
		var attachment_index := _attachment_index_for(_find_parent(_root_unit, unit.id), unit)
		var attached_name := "%s %s %s (Attached)" % [
			_ordinal(attachment_index),
			UnitRole.display_name(unit.role, unit.type),
			UnitSize.display_name(unit.size)
		]
		return {"display_name": attached_name, "short_name": attached_name}
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
	match size:
		UnitSize.Value.BATTALION:
			var bn_notation := UnitNotationFormatter.format_unit({
				"type": type_label.to_lower(),
				"size": "battalion",
				"designation": designation,
				"short_name": unit.short_name,
				"display_name": unit.display_name,
				"id": unit.id
			})
			return {"display_name": bn_notation, "short_name": bn_notation}
		UnitSize.Value.COMPANY:
			var company_notation := UnitNotationFormatter.format_unit({
				"type": type_label.to_lower(),
				"size": "company",
				"designation": designation,
				"short_name": unit.short_name,
				"display_name": unit.display_name,
				"id": unit.id
			})
			return {"display_name": company_notation, "short_name": company_notation}
		UnitSize.Value.PLATOON:
			if int(designation.get("attached_company_index", 0)) > 0:
				var attached_platoon_name := "%s %s Platoon" % [
					_ordinal(maxi(int(designation.get("platoon_number", 0)), 1)),
					UnitRole.display_name(unit.role, unit.type)
				]
				return {"display_name": attached_platoon_name, "short_name": attached_platoon_name}
			var platoon_notation := UnitNotationFormatter.format_unit({
				"type": type_label.to_lower(),
				"size": "platoon",
				"designation": designation,
				"short_name": unit.short_name,
				"display_name": unit.display_name,
				"id": unit.id
			})
			return {"display_name": platoon_notation, "short_name": platoon_notation}
		_:
			return {"display_name": "%s %s" % [nth, UnitSize.display_name(size)], "short_name": "%s" % nth}
	return {"display_name": "%s %s" % [nth, UnitSize.display_name(size)], "short_name": "%s" % nth}

func _normalize_designation_payload(raw_designation: Dictionary, unit: UnitModel) -> Dictionary:
	return {
		"regiment_number": maxi(int(raw_designation.get("regiment_number", 0)), 0),
		"battalion_number": maxi(int(raw_designation.get("battalion_number", 0)), 0),
		"company_letter": String(raw_designation.get("company_letter", "")).strip_edges().to_upper(),
		"platoon_number": maxi(int(raw_designation.get("platoon_number", 0)), 0),
		"attached_company_index": maxi(int(raw_designation.get("attached_company_index", 0)), 0),
		"role_echelon": String(raw_designation.get("role_echelon", UnitSize.display_name(unit.size))).strip_edges()
	}

func _sibling_index_for_naming(parent: UnitModel, unit: UnitModel) -> int:
	var same_size_index := 0
	for sibling in parent.children:
		if sibling == null:
			continue
		if sibling.size != unit.size:
			continue
		if sibling.is_attached != unit.is_attached:
			continue
		if (sibling.type == UnitType.Value.HEADQUARTERS) != (unit.type == UnitType.Value.HEADQUARTERS):
			continue

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
	return _parse_unit_type(data.get("type", ""))

func _size_from_template(data: Dictionary) -> UnitSize.Value:
	return _parse_unit_size(data.get("size", ""))

func _parse_unit_type(raw_type: Variant) -> UnitType.Value:
	if typeof(raw_type) == TYPE_STRING:
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
	return UnitType.Value.INFANTRY

func _parse_unit_size(raw_size: Variant) -> UnitSize.Value:
	if typeof(raw_size) == TYPE_STRING:
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
	return UnitSize.Value.PLATOON
