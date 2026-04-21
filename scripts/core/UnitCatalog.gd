extends Node

const NATIONS_PATH := "res://data/nations.json"
const UNIT_TEMPLATES_PATH := "res://data/unit_templates.json"

var nations: Dictionary = {}
var unit_templates: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	nations = _read_json_file(NATIONS_PATH)
	unit_templates = _read_json_file(UNIT_TEMPLATES_PATH)

func get_nation(nation_id: String) -> Dictionary:
	return nations.get(nation_id, {})

func get_template(template_id: String) -> Dictionary:
	return unit_templates.get(template_id, {})

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
