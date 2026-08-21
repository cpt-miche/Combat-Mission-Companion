extends Node

const NATIONS_PATH := "res://data/nations.json"
const NATION_UNITS_DIR := "res://data/units"

var nations: Dictionary = {}
var nation_unit_templates: Dictionary = {}
var nation_template_definitions: Dictionary = {}
var nation_catalog_errors: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	nations = _read_json_file(NATIONS_PATH)
	nation_template_definitions.clear()
	nation_catalog_errors.clear()
	nation_unit_templates = _read_nation_unit_templates(NATION_UNITS_DIR)

func get_nation(nation_id: String) -> Dictionary:
	return nations.get(nation_id, {})

func get_nation_templates(nation_id: String) -> Array:
	return (nation_unit_templates.get(nation_id, []) as Array).duplicate(true)

func get_nation_template(nation_id: String, template_id: String) -> Dictionary:
	var definitions_variant: Variant = nation_template_definitions.get(nation_id, {})
	if not (definitions_variant is Dictionary):
		return {}
	var definitions := definitions_variant as Dictionary
	var template_variant: Variant = definitions.get(template_id, {})
	if not (template_variant is Dictionary):
		return {}
	return (template_variant as Dictionary).duplicate(true)

func get_nation_catalog_errors(nation_id: String) -> Array[String]:
	var output: Array[String] = []
	for error_variant in nation_catalog_errors.get(nation_id, []) as Array:
		output.append(String(error_variant))
	return output

func _read_nation_unit_templates(directory_path: String) -> Dictionary:
	var catalog := {}
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_warning("Unable to open nation units directory: %s" % directory_path)
		return catalog

	directory.list_dir_begin()
	while true:
		var file_name := directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir() or file_name.begins_with("."):
			continue
		if file_name.get_extension().to_lower() != "json":
			continue

		var full_path := "%s/%s" % [directory_path, file_name]
		var nation_data := _read_json_file(full_path)
		if nation_data.is_empty():
			continue

		var nation_id := String(nation_data.get("nation", file_name.get_basename()))
		var resolved_catalog := _resolve_nation_catalog(nation_data, full_path)
		var errors := resolved_catalog.get("errors", []) as Array
		if not errors.is_empty():
			nation_catalog_errors[nation_id] = errors.duplicate()
			for error_variant in errors:
				push_error("Nation unit catalog '%s' is invalid: %s" % [nation_id, String(error_variant)])
			continue

		catalog[nation_id] = (resolved_catalog.get("templates", []) as Array).duplicate(true)
		nation_template_definitions[nation_id] = (resolved_catalog.get("definitions", {}) as Dictionary).duplicate(true)

	directory.list_dir_end()
	return catalog

func _resolve_nation_catalog(nation_data: Dictionary, source_name: String = "catalog") -> Dictionary:
	var errors: Array[String] = []
	var registry := {}
	var root_ids: Array[String] = []
	var templates_variant: Variant = nation_data.get("templates", null)
	var definitions_variant: Variant = nation_data.get("definitions", [])
	if not (templates_variant is Array):
		errors.append("Expected a templates array in %s." % source_name)
		return {"templates": [], "definitions": {}, "errors": errors}
	if not (definitions_variant is Array):
		errors.append("Expected a definitions array in %s." % source_name)
		return {"templates": [], "definitions": {}, "errors": errors}

	_register_definitions(templates_variant as Array, true, registry, root_ids, errors)
	_register_definitions(definitions_variant as Array, false, registry, root_ids, errors)
	if registry.is_empty() and errors.is_empty():
		errors.append("Catalog contains no template definitions.")

	var resolved_by_id := {}
	var definition_ids: Array[String] = []
	for id_variant in registry.keys():
		definition_ids.append(String(id_variant))
	definition_ids.sort()
	for template_id in definition_ids:
		_resolve_template_by_id(template_id, registry, {}, resolved_by_id, errors)

	if not errors.is_empty():
		return {"templates": [], "definitions": {}, "errors": errors}

	var resolved_roots: Array[Dictionary] = []
	for root_id in root_ids:
		resolved_roots.append((resolved_by_id[root_id] as Dictionary).duplicate(true))
	return {
		"templates": resolved_roots,
		"definitions": resolved_by_id,
		"errors": errors
	}

func _register_definitions(raw_definitions: Array, roots: bool, registry: Dictionary, root_ids: Array[String], errors: Array[String]) -> void:
	for definition_variant in raw_definitions:
		if not (definition_variant is Dictionary):
			_append_catalog_error(errors, "Every template definition must be a dictionary.")
			continue
		var definition := definition_variant as Dictionary
		var template_id := String(definition.get("id", "")).strip_edges()
		if template_id.is_empty():
			_append_catalog_error(errors, "Every template definition must have a non-empty id.")
			continue
		if registry.has(template_id):
			_append_catalog_error(errors, "Duplicate template id '%s'." % template_id)
			continue
		var error_count_before := errors.size()
		for required_field in ["display_name", "type", "size", "role", "children"]:
			if not definition.has(required_field):
				_append_catalog_error(errors, "Template '%s' is missing required field '%s'." % [template_id, required_field])
		if not (definition.get("display_name") is String) or String(definition.get("display_name")).strip_edges().is_empty():
			_append_catalog_error(errors, "Template '%s' must have a display_name." % template_id)
		if not (definition.get("type") is String) or not (definition.get("size") is String):
			_append_catalog_error(errors, "Template '%s' must use string type and size identifiers." % template_id)
		if not UnitRole.is_valid(definition.get("role", "")):
			_append_catalog_error(errors, "Template '%s' must declare a canonical role." % template_id)
		if not (definition.get("children") is Array):
			_append_catalog_error(errors, "Template '%s' must declare children as an array." % template_id)
		if errors.size() > error_count_before:
			continue
		registry[template_id] = definition.duplicate(true)
		if roots:
			root_ids.append(template_id)

func _resolve_template_by_id(template_id: String, registry: Dictionary, resolving: Dictionary, cache: Dictionary, errors: Array[String]) -> Dictionary:
	if cache.has(template_id):
		return (cache[template_id] as Dictionary).duplicate(true)
	if resolving.has(template_id):
		_append_catalog_error(errors, "Template reference cycle includes '%s'." % template_id)
		return {}
	if not registry.has(template_id):
		_append_catalog_error(errors, "Missing nation-local template reference '%s'." % template_id)
		return {}

	resolving[template_id] = true
	var resolved := (registry[template_id] as Dictionary).duplicate(true)
	resolved.erase("count")
	var children_variant: Variant = resolved.get("children", [])
	if not (children_variant is Array):
		_append_catalog_error(errors, "Template '%s' must declare children as an array." % template_id)
		resolving.erase(template_id)
		return {}

	var resolved_children: Array[Dictionary] = []
	for reference_variant in children_variant as Array:
		if not (reference_variant is Dictionary):
			_append_catalog_error(errors, "Template '%s' has a non-dictionary child reference." % template_id)
			continue
		var reference := reference_variant as Dictionary
		var referenced_id := String(reference.get("template_ref", "")).strip_edges()
		if referenced_id.is_empty():
			_append_catalog_error(errors, "Template '%s' contains an inline or missing child definition; template_ref is required." % template_id)
			continue
		if reference.has("id") or reference.has("children"):
			_append_catalog_error(errors, "Template '%s' reference to '%s' mixes inline definition fields with template_ref." % [template_id, referenced_id])
			continue
		for reference_key_variant in reference.keys():
			var reference_key := String(reference_key_variant)
			if reference_key not in ["template_ref", "count"]:
				_append_catalog_error(errors, "Template '%s' reference to '%s' has unsupported field '%s'." % [template_id, referenced_id, reference_key])
		var raw_count: Variant = reference.get("count", 1)
		var numeric_count := float(raw_count) if raw_count is int or raw_count is float else -1.0
		var child_count := int(numeric_count)
		if numeric_count < 1.0 or not is_equal_approx(numeric_count, floorf(numeric_count)):
			_append_catalog_error(errors, "Template '%s' references '%s' with an invalid count." % [template_id, referenced_id])
			continue
		var child := _resolve_template_by_id(referenced_id, registry, resolving, cache, errors)
		if child.is_empty():
			continue
		child["count"] = child_count
		resolved_children.append(child)
	resolved["children"] = resolved_children
	resolving.erase(template_id)
	if errors.is_empty():
		cache[template_id] = resolved.duplicate(true)
	return resolved

func _append_catalog_error(errors: Array[String], message: String) -> void:
	if not errors.has(message):
		errors.append(message)

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Data file does not exist: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Unable to open data file: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Expected dictionary JSON in file: %s" % path)
		return {}

	return parsed as Dictionary
