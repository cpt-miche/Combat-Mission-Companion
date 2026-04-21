extends Node

const CURRENT_GAME_SAVE_PATH := "user://current_game.save"
const DIVISION_TEMPLATES_DIR := "user://division_templates"

func _ensure_templates_dir() -> void:
	if DirAccess.dir_exists_absolute(DIVISION_TEMPLATES_DIR):
		return
	DirAccess.make_dir_recursive_absolute(DIVISION_TEMPLATES_DIR)

func _write_json(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open save file for writing: %s" % path)
		return false

	file.store_string(JSON.stringify(payload))
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open save file for reading: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file content is invalid: %s" % path)
		return {}

	return parsed as Dictionary

func autosave(payload: Dictionary) -> bool:
	return save_current_game(payload)

func save_current_game(payload: Dictionary) -> bool:
	return _write_json(CURRENT_GAME_SAVE_PATH, payload)

func load_current_game() -> Dictionary:
	return _read_json(CURRENT_GAME_SAVE_PATH)

func save_division_template(template_name: String, payload: Dictionary) -> bool:
	var safe_name := template_name.strip_edges().replace(" ", "_")
	if safe_name.is_empty():
		return false
	_ensure_templates_dir()
	return _write_json("%s/%s.json" % [DIVISION_TEMPLATES_DIR, safe_name], payload)

func load_division_template(template_name: String) -> Dictionary:
	var safe_name := template_name.strip_edges().replace(" ", "_")
	if safe_name.is_empty():
		return {}
	return _read_json("%s/%s.json" % [DIVISION_TEMPLATES_DIR, safe_name])

func list_division_templates() -> PackedStringArray:
	_ensure_templates_dir()
	var result := PackedStringArray()
	var dir := DirAccess.open(DIVISION_TEMPLATES_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			result.append(entry.trim_suffix(".json"))
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
