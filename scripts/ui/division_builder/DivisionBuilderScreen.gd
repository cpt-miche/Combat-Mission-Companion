extends Control


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

var _root_unit: UnitModel
var _selected_unit: UnitModel
var _pending_unit_data: Dictionary = {}
var _id_counter := 1

func _ready() -> void:
	_build_nation_selector()
	_build_veterancy_selector()
	_initialize_organization()

	unit_tree.cell_selected.connect(_on_unit_tree_selected)
	add_unit_button.pressed.connect(_on_add_unit_pressed)
	delete_button.pressed.connect(_on_delete_button_pressed)
	veterancy_selector.item_selected.connect(_on_veterancy_selected)
	org_chart_view.unit_selected.connect(_on_org_chart_selected)
	org_chart_view.delete_requested.connect(_on_org_chart_delete_requested)

	_refresh_all()

func _build_nation_selector() -> void:
	nation_selector.clear()
	var nation_ids := UnitCatalog.nations.keys()
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

func _initialize_organization() -> void:
	var default_nation := "usa"
	if nation_selector.item_count > 0:
		default_nation = String(nation_selector.get_item_metadata(0))

	_root_unit = _create_unit("army_root", default_nation, UnitType.Value.HEADQUARTERS, UnitSize.Value.ARMY)
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
	var category_names := categories.keys()
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

	for template_id in UnitCatalog.unit_templates.keys():
		var data: Dictionary = UnitCatalog.unit_templates[template_id]
		var template_nation := String(data.get("nation", ""))
		if template_nation != "" and template_nation != selected_nation:
			continue

		var unit_type := _type_from_template(data)
		var category := UnitType.display_name(unit_type)
		if not grouped.has(category):
			grouped[category] = []

		var template := {
			"id": template_id,
			"name": data.get("name", template_id),
			"nation": selected_nation,
			"type": unit_type,
			"size": _size_from_template(data)
		}
		grouped[category].append(template)

	return grouped

func _can_add_template(template_data: Dictionary) -> bool:
	if _selected_unit == null:
		return false
	var candidate := _create_unit("preview", String(template_data.get("nation", "usa")), template_data.get("type", UnitType.Value.INFANTRY), template_data.get("size", UnitSize.Value.COMPANY))
	candidate.id = "preview"
	return OrganizationValidator.can_add_child(_selected_unit, candidate)

func _template_display_name(template_data: Dictionary) -> String:
	return "%s (%s)" % [
		String(template_data.get("name", "Unknown")),
		UnitSize.display_name(template_data.get("size", UnitSize.Value.COMPANY))
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

	var candidate := _create_unit(
		String(_pending_unit_data.get("id", "template")),
		String(_pending_unit_data.get("nation", _selected_nation())),
		_pending_unit_data.get("type", UnitType.Value.INFANTRY),
		_pending_unit_data.get("size", UnitSize.Value.COMPANY)
	)

	if not OrganizationValidator.can_add_child(_selected_unit, candidate):
		_rebuild_unit_tree()
		return

	_selected_unit.children.append(candidate)
	_selected_unit = candidate
	_refresh_all()

func _on_delete_button_pressed() -> void:
	_delete_unit(_selected_unit)

func _on_org_chart_delete_requested(unit: UnitModel) -> void:
	_delete_unit(unit)

func _delete_unit(unit: UnitModel) -> void:
	if unit == null or unit == _root_unit:
		return
	if _remove_child_recursive(_root_unit, unit.id):
		_selected_unit = _root_unit
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

	selected_name_label.text = "%s (%s)" % [UnitSize.display_name(_selected_unit.size), _selected_unit.id]
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

func _type_from_template(data: Dictionary) -> UnitType.Value:
	var tags: Array = data.get("tags", [])
	if tags.has("infantry"):
		return UnitType.Value.INFANTRY
	if tags.has("line"):
		return UnitType.Value.MOTORIZED
	return UnitType.Value.RECON

func _size_from_template(data: Dictionary) -> UnitSize.Value:
	var points := int(data.get("points", 100))
	if points < 120:
		return UnitSize.Value.PLATOON
	if points < 180:
		return UnitSize.Value.COMPANY
	if points < 260:
		return UnitSize.Value.BATTALION
	if points < 360:
		return UnitSize.Value.REGIMENT
	return UnitSize.Value.DIVISION
