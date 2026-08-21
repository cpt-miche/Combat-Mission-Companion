extends Control

const DIVISION_BUILDER_SCENE := preload("res://scenes/division_builder/DivisionBuilderScreen.tscn")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_test_catalog_reference_resolution_and_validation()
	_test_cmfb_catalog_roots_and_composition()
	_test_every_catalog_unit_has_a_specific_role()
	_test_every_root_instantiates_and_round_trips()
	_test_force_palette_stops_at_platoon_level()
	_test_usa_roles_and_company_designations()
	_test_generated_squad_and_section_numbering()
	_test_armored_vehicle_rosters()
	_test_attached_company_designations()
	_test_battalion_attachment_limits_and_delete_key()
	_test_downward_org_chart_and_undo()
	_test_battalions_attach_without_synthetic_hqs()
	_test_ai_catalog_allows_german_division_and_regiment()

	if _failures.is_empty():
		print("DivisionBuilderScreen integration tests passed.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)

func _test_catalog_reference_resolution_and_validation() -> void:
	var valid_fixture := {
		"nation": "test",
		"templates": [{"id": "root", "display_name": "Root", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": [{"template_ref": "leaf", "count": 2}]}],
		"definitions": [{"id": "leaf", "display_name": "Leaf", "type": "INFANTRY", "size": "PLATOON", "role": "infantry", "children": []}]
	}
	var valid_result := UnitCatalog._resolve_nation_catalog(valid_fixture, "valid fixture")
	_assert_true((valid_result.get("errors", []) as Array).is_empty(), "A valid canonical catalog should resolve without errors")
	var resolved_root := (valid_result.get("templates", []) as Array)[0] as Dictionary
	var resolved_leaf := (resolved_root.get("children", []) as Array)[0] as Dictionary
	_assert_equal("leaf", String(resolved_leaf.get("id", "")), "Template references should resolve to the canonical child definition")
	_assert_equal(2, int(resolved_leaf.get("count", 0)), "Reference counts should remain on the composition edge")
	resolved_leaf["display_name"] = "Mutated"
	var resolved_definitions := valid_result.get("definitions", {}) as Dictionary
	_assert_equal("Leaf", String((resolved_definitions["leaf"] as Dictionary).get("display_name", "")), "Resolved parents should receive deep copies")

	_assert_catalog_rejected({
		"nation": "test",
		"templates": [{"id": "duplicate", "display_name": "Duplicate", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": []}],
		"definitions": [{"id": "duplicate", "display_name": "Duplicate", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": []}]
	}, "Duplicate template id", "Duplicate canonical IDs should reject the catalog")
	_assert_catalog_rejected({
		"nation": "test",
		"templates": [{"id": "root", "display_name": "Root", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": [{"template_ref": "missing", "count": 1}]}],
		"definitions": []
	}, "Missing nation-local template reference", "Missing references should reject the catalog")
	_assert_catalog_rejected({
		"nation": "test",
		"templates": [{"id": "a", "display_name": "A", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": [{"template_ref": "b", "count": 1}]}],
		"definitions": [{"id": "b", "display_name": "B", "type": "INFANTRY", "size": "PLATOON", "role": "infantry", "children": [{"template_ref": "a", "count": 1}]}]
	}, "cycle", "Reference cycles should reject the catalog")
	_assert_catalog_rejected({
		"nation": "test",
		"templates": [{"id": "root", "display_name": "Root", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": [{"id": "inline", "children": []}]}],
		"definitions": []
	}, "template_ref is required", "Inline child definitions should reject the canonical schema")
	_assert_catalog_rejected({
		"nation": "test",
		"templates": [{"id": "root", "display_name": "Root", "type": "INFANTRY", "size": "COMPANY", "role": "infantry", "children": [{"template_ref": "leaf", "count": 1.5}]}],
		"definitions": [{"id": "leaf", "display_name": "Leaf", "type": "INFANTRY", "size": "PLATOON", "role": "infantry", "children": []}]
	}, "invalid count", "Composition counts should be positive whole numbers")

func _test_cmfb_catalog_roots_and_composition() -> void:
	UnitCatalog.reload()
	for path in ["res://data/units/usa.json", "res://data/units/germany.json"]:
		var file := FileAccess.open(path, FileAccess.READ)
		_assert_true(file != null, "Expected nation catalog file %s" % path)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		_assert_true(parsed is Dictionary, "Nation catalog %s should parse" % path)
		if not (parsed is Dictionary):
			continue
		for collection_key in ["templates", "definitions"]:
			for definition_variant in (parsed as Dictionary).get(collection_key, []) as Array:
				if definition_variant is Dictionary:
					var definition := definition_variant as Dictionary
					_assert_definition_uses_references(definition, path)
					if path.ends_with("germany.json"):
						var display_name := String(definition.get("display_name", ""))
						_assert_false(display_name.begins_with("Heer "), "German display name should omit the implied Heer prefix: %s" % display_name)

	_assert_equal([
		"usa_infantry_division_1944", "usa_armored_division_1944", "usa_airborne_division_1944", "usa_straggler_group",
		"usa_m4a3_75_tank_battalion", "usa_m4a3_76_tank_battalion", "usa_m18_tank_destroyer_battalion", "usa_m36_tank_destroyer_battalion"
	], _catalog_template_ids(UnitCatalog.get_nation_templates("usa")), "U.S. roots should cover CMFB-style high formations and major armor")
	_assert_equal([
		"ger_heer_infantry_division_44", "ger_volksgrenadier_division_44", "ger_panzer_division_44", "ger_panzergrenadier_division_44",
		"ger_fallschirmjager_division_44", "ger_gebirgsjager_division_44", "ger_waffen_ss_panzer_division_44", "ger_fortress_mg_battalion", "ger_straggler_group",
		"ger_panzer_iv_battalion", "ger_panther_battalion", "ger_tiger_heavy_tank_battalion", "ger_tiger_ii_heavy_tank_battalion",
		"ger_stug_iii_assault_gun_battalion", "ger_stug_iv_assault_gun_battalion", "ger_jagdpanzer_iv_battalion", "ger_hetzer_panzerjager_battalion"
	], _catalog_template_ids(UnitCatalog.get_nation_templates("germany")), "German roots should cover Heer, Waffen-SS, Fallschirmjager, and major armor")

	var infantry_division := UnitCatalog.get_nation_template("usa", "usa_infantry_division_1944")
	_assert_equal(6, _expanded_child_count(infantry_division), "A U.S. infantry division should expand to three regiments, artillery, engineers, and reconnaissance")
	var infantry_regiment := UnitCatalog.get_nation_template("usa", "usa_infantry_regiment_1944")
	_assert_equal(6, _expanded_child_count(infantry_regiment), "A U.S. infantry regiment should contain HQ, three battalions, cannon, and anti-tank companies")
	var infantry_battalion := UnitCatalog.get_nation_template("usa", "usa_infantry_battalion")
	_assert_equal(5, _expanded_child_count(infantry_battalion), "A U.S. infantry battalion should contain HQ, three rifle companies, and heavy weapons")
	var armored_division := UnitCatalog.get_nation_template("usa", "usa_armored_division_1944")
	_assert_equal(5, _expanded_child_count(armored_division), "A U.S. armored division should use three combat commands, recon, and engineers")
	var combat_command := UnitCatalog.get_nation_template("usa", "usa_armored_combat_command")
	_assert_equal(["usa_mixed_tank_battalion", "usa_armored_infantry_battalion", "usa_105mm_sp_artillery_battalion"], _catalog_child_ids(combat_command), "Each combat command should combine tanks, armored infantry, and SP artillery")

	var german_infantry_division := UnitCatalog.get_nation_template("germany", "ger_heer_infantry_division_44")
	_assert_equal(7, _expanded_child_count(german_infantry_division), "A Type-44 infantry division should fill the seven-child operational structure")
	var german_panzer_division := UnitCatalog.get_nation_template("germany", "ger_panzer_division_44")
	_assert_equal(7, _expanded_child_count(german_panzer_division), "A Type-44 Panzer division should include its seven principal combat formations")
	var volksgrenadier_battalion := UnitCatalog.get_nation_template("germany", "ger_volksgrenadier_battalion_44")
	_assert_equal(5, _expanded_child_count(volksgrenadier_battalion), "A Volksgrenadier battalion should contain HQ, three line companies, and a heavy company")

	var direct_usa := UnitCatalog.get_nation_template("usa", "usa_infantry_battalion")
	var nested_usa := _find_catalog_template_recursive(infantry_division, "usa_infantry_battalion")
	_assert_equal(_template_structure_signature(direct_usa), _template_structure_signature(nested_usa), "Direct and division-created U.S. battalions should share canonical structure")
	var direct_german := UnitCatalog.get_nation_template("germany", "ger_heer_grenadier_battalion_44")
	var nested_german := _find_catalog_template_recursive(german_infantry_division, "ger_heer_grenadier_battalion_44")
	_assert_equal(_template_structure_signature(direct_german), _template_structure_signature(nested_german), "Direct and division-created German battalions should share canonical structure")

	_assert_true(UnitCatalog.get_nation_template("germany", "ger_panzer_iii_medium_tank_company").is_empty(), "Generic Panzer III formations should not remain in the late-1944 catalog")
	for excluded_id in ["ger_jagdtiger_battalion", "ger_sturmtiger_company", "usa_m4a3e2_jumbo_company", "usa_m24_chaffee_company"]:
		_assert_true(_find_catalog_template("germany", excluded_id).is_empty() and _find_catalog_template("usa", excluded_id).is_empty(), "Rare specialist template %s should remain out of scope" % excluded_id)

func _test_every_catalog_unit_has_a_specific_role() -> void:
	UnitCatalog.reload()
	for nation_id_variant in UnitCatalog.nation_unit_templates.keys():
		var nation_id := String(nation_id_variant)
		_assert_true(UnitCatalog.get_nation_catalog_errors(nation_id).is_empty(), "%s catalog should resolve without validation errors" % nation_id)
		for template_variant in UnitCatalog.get_nation_templates(nation_id):
			if template_variant is Dictionary:
				_assert_catalog_roles_recursive(template_variant as Dictionary, nation_id)
	_assert_equal("Heavy Machine Gun", UnitRole.display_name("heavy_machine_gun"), "Role labels should expand machine-gun identifiers")
	_assert_equal("81mm Mortar", UnitRole.display_name("81mm_mortar"), "Role labels should preserve catalog weapon calibers")
	_assert_equal("Anti-Tank", UnitRole.display_name("anti_tank"), "Role labels should retain canonical punctuation")

func _test_every_root_instantiates_and_round_trips() -> void:
	for nation_id in ["usa", "germany"]:
		var screen := _spawn_builder_for_nation(nation_id)
		for template_variant in UnitCatalog.get_nation_templates(nation_id):
			var template := template_variant as Dictionary
			var model: UnitModel = screen._create_unit_from_template_tree(template, nation_id)
			var insert_result: Dictionary = screen._insert_subtree_with_validation(screen._root_unit, model)
			_assert_true(bool(insert_result.get("ok", false)), "%s root %s should instantiate within current organization limits: %s" % [nation_id, template.get("id", ""), insert_result.get("error", "")])
			if not bool(insert_result.get("ok", false)):
				continue
			var restored: UnitModel = screen._dict_to_unit(screen._unit_to_dict(model))
			_assert_true(restored != null, "%s root %s should survive current-build serialization" % [nation_id, template.get("id", "")])
			screen._root_unit.children.erase(model)
		_cleanup_screen(screen)

func _test_force_palette_stops_at_platoon_level() -> void:
	for nation_id in ["usa", "germany"]:
		var screen := _spawn_builder_for_nation(nation_id)
		var palette_ids: Array[String] = []
		for category_variant in screen._collect_templates_by_category().values():
			for template_variant in category_variant as Array:
				var template := template_variant as Dictionary
				palette_ids.append(String(template.get("id", "")))
				var size_text := String(template.get("size", ""))
				_assert_true(size_text not in ["squad", "section"], "%s palette should not expose sub-platoon template %s" % [nation_id, template.get("id", "")])
				_assert_true(String(template.get("type", "")) != "headquarters", "%s palette should not expose HQ template %s" % [nation_id, template.get("id", "")])
		_assert_false(palette_ids.is_empty(), "%s palette should contain selectable formations" % nation_id)
		_assert_false(palette_ids.has("usa_rifle_squad") or palette_ids.has("ger_grenadier_squad"), "Squads should never appear in the force palette")
		if nation_id == "usa":
			_assert_true(palette_ids.has("usa_rifle_platoon"), "U.S. rifle platoons should remain independently addable")
		else:
			_assert_true(palette_ids.has("ger_panzer_iv_platoon"), "German Panzer IV platoons should remain independently addable")
		_cleanup_screen(screen)

func _test_usa_roles_and_company_designations() -> void:
	var screen := _spawn_builder_for_nation("usa")
	var division_item := _find_template_item(screen.unit_tree.get_root(), "U.S. Infantry Division (1944)", UnitType.Value.INFANTRY, UnitSize.Value.DIVISION)
	_assert_true(division_item != null, "U.S. catalog should include its infantry division")
	if division_item == null:
		_cleanup_screen(screen)
		return
	_select_catalog_item(screen, division_item)
	screen._on_add_unit_pressed()
	var division := screen._root_unit.children[0] as UnitModel
	var regiment := _first_child_with_role_and_size(division, "infantry", UnitSize.Value.REGIMENT)
	_assert_true(regiment != null, "U.S. division should generate infantry regiments")
	if regiment != null:
		var battalions := _children_with_role_and_size(regiment, "infantry", UnitSize.Value.BATTALION)
		_assert_equal(3, battalions.size(), "A U.S. infantry regiment should contain three battalions")
		var expected_line_letters := [["A", "B", "C"], ["E", "F", "G"], ["I", "K", "L"]]
		var expected_weapons_letters := ["D", "H", "M"]
		for battalion_index in range(mini(battalions.size(), 3)):
			var line_companies := _children_with_role_and_size(battalions[battalion_index], "rifle", UnitSize.Value.COMPANY)
			var weapons_company := _first_child_with_role_and_size(battalions[battalion_index], "heavy_weapons", UnitSize.Value.COMPANY)
			_assert_equal(3, line_companies.size(), "Each U.S. infantry battalion should contain three rifle companies")
			for company_index in range(mini(line_companies.size(), 3)):
				_assert_equal(expected_line_letters[battalion_index][company_index], _company_letter(line_companies[company_index]), "U.S. rifle-company lettering should continue through the regiment")
			_assert_true(weapons_company != null, "Each U.S. infantry battalion should contain a heavy-weapons company")
			if weapons_company != null:
				_assert_equal(expected_weapons_letters[battalion_index], _company_letter(weapons_company), "U.S. heavy-weapons companies should be D, H, and M")
	_cleanup_screen(screen)

func _test_generated_squad_and_section_numbering() -> void:
	var screen := _spawn_builder_for_nation("usa")
	var rifle_company: UnitModel = screen._create_unit_from_template_tree(_find_catalog_template("usa", "usa_rifle_company"), "usa")
	screen._root_unit = rifle_company
	screen._assign_unit_names()
	var rifle_platoons := _children_with_role_and_size(rifle_company, "rifle", UnitSize.Value.PLATOON)
	_assert_equal(3, rifle_platoons.size(), "The rifle company should generate three rifle platoons")
	for rifle_platoon in rifle_platoons:
		var rifle_squads := _children_with_role_and_size(rifle_platoon, "rifle", UnitSize.Value.SQUAD)
		_assert_equal(["1st Squad", "2nd Squad", "3rd Squad"], _unit_display_names(rifle_squads), "Generated squads should be numbered locally beneath their platoon")
	var heavy_company: UnitModel = screen._create_unit_from_template_tree(_find_catalog_template("usa", "usa_heavy_weapons_company"), "usa")
	screen._root_unit = heavy_company
	screen._assign_unit_names()
	var mg_platoons := _children_with_role_and_size(heavy_company, "heavy_machine_gun", UnitSize.Value.PLATOON)
	_assert_equal(2, mg_platoons.size(), "The heavy-weapons company should generate two machine-gun platoons")
	for mg_platoon in mg_platoons:
		_assert_equal(["1st Section", "2nd Section"], _unit_display_names(_children_with_role_and_size(mg_platoon, "heavy_machine_gun", UnitSize.Value.SECTION)), "Machine-gun sections should be numbered locally")
	_cleanup_screen(screen)

func _test_armored_vehicle_rosters() -> void:
	var specs := [
		["usa", "usa_m4a3_75_tank_company", "usa_m4a3_75_tank_platoon", "usa_m4a3_75_company_hq_section", 3, 5, 2],
		["usa", "usa_m4a3_76_tank_company", "usa_m4a3_76_tank_platoon", "usa_m4a3_76_company_hq_section", 3, 5, 2],
		["usa", "usa_m5a1_light_tank_company", "usa_m5a1_light_tank_platoon", "usa_m5a1_company_hq_section", 3, 5, 2],
		["usa", "usa_m18_tank_destroyer_company", "usa_m18_tank_destroyer_platoon", "", 3, 4, 0],
		["usa", "usa_m36_tank_destroyer_company", "usa_m36_tank_destroyer_platoon", "", 3, 4, 0],
		["germany", "ger_panzer_iv_company", "ger_panzer_iv_platoon", "ger_panzer_iv_company_hq_section", 3, 5, 2],
		["germany", "ger_panther_company", "ger_panther_platoon", "ger_panther_company_hq_section", 3, 5, 2],
		["germany", "ger_tiger_heavy_tank_company", "ger_tiger_heavy_tank_platoon", "ger_tiger_company_hq_section", 3, 4, 2],
		["germany", "ger_tiger_ii_heavy_tank_company", "ger_tiger_ii_heavy_tank_platoon", "ger_tiger_ii_company_hq_section", 3, 4, 2],
		["germany", "ger_stug_iii_assault_gun_battery", "ger_stug_iii_assault_gun_platoon", "ger_stug_iii_battery_hq_section", 3, 3, 1],
		["germany", "ger_stug_iv_assault_gun_battery", "ger_stug_iv_assault_gun_platoon", "ger_stug_iv_battery_hq_section", 3, 3, 1],
		["germany", "ger_jagdpanzer_iv_company", "ger_jagdpanzer_iv_platoon", "ger_jagdpanzer_iv_company_hq_section", 3, 4, 2],
		["germany", "ger_hetzer_company", "ger_hetzer_platoon", "ger_hetzer_company_hq_section", 3, 4, 2]
	]
	for spec_variant in specs:
		var spec := spec_variant as Array
		var nation_id := String(spec[0])
		var company := _find_catalog_template(nation_id, String(spec[1]))
		var platoon := _find_catalog_template(nation_id, String(spec[2]))
		var platoon_edge := _find_direct_child(company, String(spec[2]))
		_assert_equal(int(spec[4]), int(platoon_edge.get("count", 0)), "%s should contain the representative platoon count" % spec[1])
		_assert_equal(int(spec[5]), _vehicle_roster_total(platoon), "%s should track every vehicle in the platoon" % spec[2])
		var hq_total := 0
		if not String(spec[3]).is_empty():
			hq_total = _vehicle_roster_total(_find_catalog_template(nation_id, String(spec[3])))
		_assert_equal(int(spec[6]), hq_total, "%s should track its company command vehicles without duplicating them" % spec[1])

	var screen := _spawn_builder_for_nation("usa")
	var sherman: UnitModel = screen._create_unit_from_template_tree(_find_catalog_template("usa", "usa_m4a3_75_tank_platoon"), "usa")
	_assert_equal(5, sherman.vehicles.size(), "A Sherman platoon should instantiate five individually tracked vehicles")
	var restored: UnitModel = screen._dict_to_unit(screen._unit_to_dict(sherman))
	_assert_equal(sherman.vehicles, restored.vehicles, "Vehicle rosters should survive organization serialization")
	var hellcat: UnitModel = screen._create_unit_from_template_tree(_find_catalog_template("usa", "usa_m18_tank_destroyer_platoon"), "usa")
	_assert_equal("light", hellcat.equipment_weight, "M18 formations should retain their light equipment weight")
	_cleanup_screen(screen)

func _test_attached_company_designations() -> void:
	var screen := _spawn_builder_for_nation("usa")
	var battalion_item := _find_template_item(screen.unit_tree.get_root(), "U.S. Infantry Battalion", UnitType.Value.INFANTRY, UnitSize.Value.BATTALION)
	_assert_true(battalion_item != null, "The U.S. catalog should expose an infantry battalion")
	if battalion_item == null:
		_cleanup_screen(screen)
		return
	_select_catalog_item(screen, battalion_item)
	screen._on_add_unit_pressed()
	var battalion := screen._root_unit.children[0] as UnitModel
	var tank_company_item := _find_template_item(screen.unit_tree.get_root(), "M4A3(75) Tank Company", UnitType.Value.TANK, UnitSize.Value.COMPANY)
	_assert_true(tank_company_item != null and tank_company_item.is_selectable(0), "A Sherman company should be attachable to an infantry battalion")
	if tank_company_item != null:
		_select_catalog_item(screen, tank_company_item)
		screen._on_add_unit_pressed()
	var attached := _first_child_with_role_and_size(battalion, "medium_tank", UnitSize.Value.COMPANY)
	_assert_true(attached != null and attached.is_attached, "A manually added tank company should be marked attached")
	if attached != null:
		_assert_equal("1st Medium Tank Company (Attached)", attached.display_name, "Attached companies should use role-based local designations")
		_assert_equal(3, _children_with_role_and_size(attached, "medium_tank", UnitSize.Value.PLATOON).size(), "Attached armor should retain its platoon subtree")
		var restored: UnitModel = screen._dict_to_unit(screen._unit_to_dict(attached))
		_assert_true(restored != null and restored.is_attached, "Attachment state should survive serialization")
	_cleanup_screen(screen)

func _test_battalion_attachment_limits_and_delete_key() -> void:
	var battalion := UnitModel.new()
	battalion.id = "battalion"
	battalion.size = UnitSize.Value.BATTALION
	battalion.type = UnitType.Value.INFANTRY
	for index in range(6):
		var company := UnitModel.new()
		company.id = "company_%d" % index
		company.size = UnitSize.Value.COMPANY
		company.type = UnitType.Value.INFANTRY
		battalion.children.append(company)
	var seventh_company := UnitModel.new()
	seventh_company.id = "company_6"
	seventh_company.size = UnitSize.Value.COMPANY
	seventh_company.type = UnitType.Value.INFANTRY
	_assert_false(OrganizationValidator.can_add_child(battalion, seventh_company), "A battalion should reject a seventh company")
	var platoon := UnitModel.new()
	platoon.id = "platoon"
	platoon.size = UnitSize.Value.PLATOON
	platoon.type = UnitType.Value.INFANTRY
	_assert_true(OrganizationValidator.can_add_child(battalion, platoon), "Six companies should still allow a seventh non-company child")
	battalion.children.append(platoon)
	var eighth := UnitModel.new()
	eighth.id = "eighth"
	eighth.size = UnitSize.Value.PLATOON
	eighth.type = UnitType.Value.ENGINEER
	_assert_false(OrganizationValidator.can_add_child(battalion, eighth), "A battalion should reject an eighth child")

	var screen := _spawn_builder_for_nation("usa")
	var child: UnitModel = screen._create_unit("delete_test", "usa", UnitType.Value.INFANTRY, UnitSize.Value.PLATOON, "infantry")
	screen._root_unit.children.append(child)
	screen._selected_unit = child
	var delete_event := InputEventKey.new()
	delete_event.keycode = KEY_DELETE
	delete_event.pressed = true
	screen._unhandled_key_input(delete_event)
	_assert_true(screen._root_unit.children.is_empty(), "Delete should remove the highlighted non-root organization unit")
	_cleanup_screen(screen)

func _test_downward_org_chart_and_undo() -> void:
	var screen := _spawn_builder_for_nation("usa")
	var left: UnitModel = screen._create_unit("left_company", "usa", UnitType.Value.INFANTRY, UnitSize.Value.COMPANY, "rifle")
	var right: UnitModel = screen._create_unit("right_company", "usa", UnitType.Value.INFANTRY, UnitSize.Value.COMPANY, "rifle")
	screen._root_unit.children.clear()
	screen._root_unit.children.append(left)
	screen._root_unit.children.append(right)
	screen._selected_unit = left
	screen._refresh_all()
	var chart: OrgChartView = screen.org_chart_view
	chart._node_rects.clear()
	chart._layout_subtree(screen._root_unit, 0, 0.0)
	var root_rect := chart._node_rects[screen._root_unit.id] as Rect2
	var left_rect := chart._node_rects[left.id] as Rect2
	var right_rect := chart._node_rects[right.id] as Rect2
	_assert_true(left_rect.position.y > root_rect.position.y and right_rect.position.y > root_rect.position.y, "Organization chart children should build downward")
	_assert_true(left_rect.position.x < right_rect.position.x, "Organization chart siblings should spread horizontally")
	screen._delete_unit(left)
	_assert_equal(1, screen._root_unit.children.size(), "Delete should remove a unit before undo")
	screen._on_undo_pressed()
	_assert_equal(2, screen._root_unit.children.size(), "Undo should restore a deleted subtree")
	_cleanup_screen(screen)

func _test_battalions_attach_without_synthetic_hqs() -> void:
	var screen := _spawn_builder_for_nation("usa")
	var battalion_item := _find_template_item(screen.unit_tree.get_root(), "U.S. Infantry Battalion", UnitType.Value.INFANTRY, UnitSize.Value.BATTALION)
	_assert_true(battalion_item != null and battalion_item.is_selectable(0), "A U.S. infantry battalion should be selectable beneath the army root")
	if battalion_item == null:
		_cleanup_screen(screen)
		return
	_select_catalog_item(screen, battalion_item)
	screen._on_add_unit_pressed()
	_assert_equal(1, screen._root_unit.children.size(), "Adding a battalion should create one direct child")
	var army_battalion := screen._root_unit.children[0] as UnitModel
	_assert_equal("usa_infantry_battalion", army_battalion.template_id, "The direct child should be the requested battalion")
	_assert_equal(5, army_battalion.children.size(), "Direct attachment should preserve the battalion's company subtree")
	_assert_false(_subtree_has_template_prefix(army_battalion, "auto_hq_"), "Direct attachment should not create synthetic HQ templates")
	screen._on_undo_pressed()
	_assert_true(screen._root_unit.children.is_empty(), "One undo should remove the directly added battalion")
	_cleanup_screen(screen)

func _test_ai_catalog_allows_german_division_and_regiment() -> void:
	var screen := _spawn_builder_for_nation("germany")
	var division_item := _find_template_item(screen.unit_tree.get_root(), "Infantry Division (Type 44)", UnitType.Value.INFANTRY, UnitSize.Value.DIVISION)
	_assert_true(division_item != null and division_item.is_selectable(0), "Germany should expose the Type-44 infantry division without a redundant Heer prefix")
	if division_item != null:
		_select_catalog_item(screen, division_item)
		screen._on_add_unit_pressed()
		_assert_equal(1, screen._root_unit.children.size(), "Adding the German division should create one division")
		screen._on_undo_pressed()
	var regiment_item := _find_template_item(screen.unit_tree.get_root(), "Grenadier Regiment (Type 44)", UnitType.Value.INFANTRY, UnitSize.Value.REGIMENT)
	_assert_true(regiment_item != null and regiment_item.is_selectable(0), "Germany should expose the Type-44 Grenadier regiment without a redundant Heer prefix")
	if regiment_item != null:
		_select_catalog_item(screen, regiment_item)
		screen._on_add_unit_pressed()
		_assert_equal(UnitSize.Value.REGIMENT, (screen._root_unit.children[0] as UnitModel).size, "The requested German regiment should attach directly")
	_cleanup_screen(screen)

func _spawn_builder_for_nation(nation_id: String) -> Control:
	GameState.reset()
	GameState.selected_nation_id = nation_id
	UnitCatalog.reload()
	var screen: Control = DIVISION_BUILDER_SCENE.instantiate()
	add_child(screen)
	for index in range(screen.nation_selector.item_count):
		if String(screen.nation_selector.get_item_metadata(index)) == nation_id:
			screen.nation_selector.select(index)
			break
	screen._initialize_organization(nation_id)
	screen._last_selected_nation = nation_id
	screen._pending_unit_data.clear()
	screen._refresh_all()
	return screen

func _cleanup_screen(screen: Control) -> void:
	screen.queue_free()

func _select_catalog_item(screen: Control, item: TreeItem) -> void:
	if item == null:
		return
	screen.unit_tree.set_selected(item, 0)
	screen._on_unit_tree_selected()

func _find_template_item(item: TreeItem, display_name: String, unit_type: UnitType.Value, unit_size: UnitSize.Value) -> TreeItem:
	if item == null:
		return null
	var child := item.get_first_child()
	while child != null:
		var metadata: Variant = child.get_metadata(0)
		if metadata is Dictionary:
			var template := metadata as Dictionary
			var type_id := UnitType.display_name(unit_type).to_lower().replace("-", "_").replace(" ", "_")
			var size_id := UnitSize.display_name(unit_size).to_lower()
			if String(template.get("name", "")) == display_name and String(template.get("type", "")) == type_id and String(template.get("size", "")) == size_id:
				return child
		var nested := _find_template_item(child, display_name, unit_type, unit_size)
		if nested != null:
			return nested
		child = child.get_next()
	return null

func _find_catalog_template(nation_id: String, template_id: String) -> Dictionary:
	return UnitCatalog.get_nation_template(nation_id, template_id)

func _find_catalog_template_recursive(template: Dictionary, template_id: String) -> Dictionary:
	if String(template.get("id", "")) == template_id:
		return template
	for child_variant in template.get("children", []) as Array:
		if child_variant is Dictionary:
			var found := _find_catalog_template_recursive(child_variant as Dictionary, template_id)
			if not found.is_empty():
				return found
	return {}

func _find_direct_child(template: Dictionary, template_id: String) -> Dictionary:
	for child_variant in template.get("children", []) as Array:
		if child_variant is Dictionary and String((child_variant as Dictionary).get("id", "")) == template_id:
			return child_variant as Dictionary
	return {}

func _catalog_child_ids(template: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for child_variant in template.get("children", []) as Array:
		if child_variant is Dictionary:
			ids.append(String((child_variant as Dictionary).get("id", "")))
	return ids

func _catalog_template_ids(templates: Array) -> Array[String]:
	var ids: Array[String] = []
	for template_variant in templates:
		if template_variant is Dictionary:
			ids.append(String((template_variant as Dictionary).get("id", "")))
	return ids

func _expanded_child_count(template: Dictionary) -> int:
	var result := 0
	for child_variant in template.get("children", []) as Array:
		if child_variant is Dictionary:
			result += int((child_variant as Dictionary).get("count", 1))
	return result

func _vehicle_roster_total(template: Dictionary) -> int:
	var total := 0
	for entry_variant in template.get("vehicle_roster", []) as Array:
		if entry_variant is Dictionary:
			total += int((entry_variant as Dictionary).get("count", 0))
	return total

func _assert_definition_uses_references(definition: Dictionary, source_name: String) -> void:
	var template_id := String(definition.get("id", "missing"))
	for child_variant in definition.get("children", []) as Array:
		_assert_true(child_variant is Dictionary, "%s template %s should contain dictionary child references" % [source_name, template_id])
		if not (child_variant is Dictionary):
			continue
		var child := child_variant as Dictionary
		_assert_true(not String(child.get("template_ref", "")).is_empty(), "%s template %s should reference a canonical child ID" % [source_name, template_id])
		_assert_true(not child.has("id"), "%s template %s should not embed an inline child" % [source_name, template_id])
		_assert_true(int(child.get("count", 0)) >= 1, "%s template %s should declare a positive count" % [source_name, template_id])

func _assert_catalog_rejected(fixture: Dictionary, expected_error_text: String, message: String) -> void:
	var errors := UnitCatalog._resolve_nation_catalog(fixture, "test fixture").get("errors", []) as Array
	var matched := false
	for error_variant in errors:
		if String(error_variant).contains(expected_error_text):
			matched = true
	_assert_true(not errors.is_empty() and matched, "%s | errors=%s" % [message, errors])

func _assert_catalog_roles_recursive(template: Dictionary, nation_id: String) -> void:
	var template_id := String(template.get("id", "missing_id"))
	var role := String(template.get("role", ""))
	_assert_true(UnitRole.is_valid(role), "%s catalog unit %s should declare a canonical role" % [nation_id, template_id])
	_assert_true(UnitRole.display_name(role, template.get("type", "")) != "Unknown", "%s catalog unit %s should have a readable role" % [nation_id, template_id])
	for child_variant in template.get("children", []) as Array:
		if child_variant is Dictionary:
			_assert_catalog_roles_recursive(child_variant as Dictionary, nation_id)

func _template_structure_signature(template: Dictionary, include_count: bool = false) -> Dictionary:
	var child_signatures: Array[Dictionary] = []
	for child_variant in template.get("children", []) as Array:
		if child_variant is Dictionary:
			child_signatures.append(_template_structure_signature(child_variant as Dictionary, true))
	var signature := {"id": String(template.get("id", "")), "type": String(template.get("type", "")), "size": String(template.get("size", "")), "role": String(template.get("role", "")), "children": child_signatures}
	if include_count:
		signature["count"] = int(template.get("count", 1))
	return signature

func _children_with_role_and_size(parent: UnitModel, role: String, size: UnitSize.Value) -> Array[UnitModel]:
	var matches: Array[UnitModel] = []
	if parent == null:
		return matches
	for child in parent.children:
		if child != null and child.role == role and child.size == size:
			matches.append(child)
	return matches

func _first_child_with_role_and_size(parent: UnitModel, role: String, size: UnitSize.Value) -> UnitModel:
	var matches := _children_with_role_and_size(parent, role, size)
	return matches[0] if not matches.is_empty() else null

func _company_letter(company: UnitModel) -> String:
	return String((company.get_meta("designation_payload", {}) as Dictionary).get("company_letter", ""))

func _unit_display_names(units: Array[UnitModel]) -> Array[String]:
	var names: Array[String] = []
	for unit in units:
		names.append(unit.display_name)
	return names

func _subtree_has_template_prefix(unit: UnitModel, prefix: String) -> bool:
	if unit == null:
		return false
	if unit.template_id.begins_with(prefix):
		return true
	for child in unit.children:
		if _subtree_has_template_prefix(child, prefix):
			return true
	return false

func _assert_equal(expected: Variant, actual: Variant, message: String) -> void:
	if expected != actual:
		_fail("%s | expected=%s actual=%s" % [message, expected, actual])

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _assert_false(value: bool, message: String) -> void:
	if value:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
