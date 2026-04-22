extends Node

const NATIONS_PATH := "res://data/nations.json"
const UNIT_TEMPLATES_PATH := "res://data/unit_templates.json"
const NATION_UNITS_DIR := "res://data/units"

var nations: Dictionary = {}
var unit_templates: Dictionary = {}
var nation_unit_templates: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	nations = _read_json_file(NATIONS_PATH)
	unit_templates = _read_json_file(UNIT_TEMPLATES_PATH)
	nation_unit_templates = _read_nation_unit_templates(NATION_UNITS_DIR)

func get_nation(nation_id: String) -> Dictionary:
	return nations.get(nation_id, {})

func get_template(template_id: String) -> Dictionary:
	return unit_templates.get(template_id, {})

func get_nation_templates(nation_id: String) -> Array:
	return nation_unit_templates.get(nation_id, [])

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
		var templates_variant: Variant = nation_data.get("templates", [])
		if typeof(templates_variant) != TYPE_ARRAY:
			push_warning("Expected templates array in nation file: %s" % full_path)
			continue

		catalog[nation_id] = templates_variant.duplicate(true)

	directory.list_dir_end()
	return catalog

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
