extends Node

const CURRENT_GAME_SAVE_PATH := "user://current_game.save"
const DIVISION_TEMPLATES_DIR := "user://division_templates"
const MAPS_DIR := "user://maps"

func _ensure_templates_dir() -> void:
	if DirAccess.dir_exists_absolute(DIVISION_TEMPLATES_DIR):
		return
	DirAccess.make_dir_recursive_absolute(DIVISION_TEMPLATES_DIR)

func _ensure_maps_dir() -> void:
	if DirAccess.dir_exists_absolute(MAPS_DIR):
		return
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)

func _safe_file_name(raw_name: String) -> String:
	var safe_name := raw_name.strip_edges().replace(" ", "_")
	safe_name = safe_name.replace("/", "_").replace("\\", "_").replace(":", "_")
	return safe_name

func sanitize_name(raw_name: String) -> String:
	return _safe_file_name(raw_name)

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
	var safe_name := _safe_file_name(template_name)
	if safe_name.is_empty():
		return false
	_ensure_templates_dir()
	return _write_json("%s/%s.json" % [DIVISION_TEMPLATES_DIR, safe_name], payload)

func load_division_template(template_name: String) -> Dictionary:
	var safe_name := _safe_file_name(template_name)
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

func save_map(map_name: String, payload: Dictionary) -> bool:
	var safe_name := _safe_file_name(map_name)
	if safe_name.is_empty():
		return false
	_ensure_maps_dir()
	var now_unix := Time.get_unix_time_from_system()
	var existing_payload := load_map(map_name)
	var map_payload := payload.duplicate(true)
	map_payload["version"] = int(map_payload.get("version", 1))
	map_payload["name"] = String(map_payload.get("name", map_name))
	map_payload["grid"] = (map_payload.get("grid", {}) as Dictionary).duplicate(true)
	map_payload["terrain"] = (map_payload.get("terrain", {}) as Dictionary).duplicate(true)
	map_payload["territory"] = (map_payload.get("territory", {}) as Dictionary).duplicate(true)
	map_payload["created_at"] = int(existing_payload.get("created_at", int(map_payload.get("created_at", now_unix))))
	map_payload["updated_at"] = now_unix
	return _write_json("%s/%s.json" % [MAPS_DIR, safe_name], map_payload)

func load_map(map_name: String) -> Dictionary:
	var safe_name := _safe_file_name(map_name)
	if safe_name.is_empty():
		return {}
	return _read_json("%s/%s.json" % [MAPS_DIR, safe_name])

func list_maps() -> PackedStringArray:
	_ensure_maps_dir()
	var result := PackedStringArray()
	var dir := DirAccess.open(MAPS_DIR)
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

func delete_map(map_name: String) -> bool:
	var safe_name := _safe_file_name(map_name)
	if safe_name.is_empty():
		return false
	var full_path := "%s/%s.json" % [MAPS_DIR, safe_name]
	if not FileAccess.file_exists(full_path):
		return false
	return DirAccess.remove_absolute(full_path) == OK
