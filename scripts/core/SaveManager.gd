extends Node

const CURRENT_GAME_SAVE_PATH := "user://current_game.save"
const DIVISION_TEMPLATES_DIR := "user://division_templates"
const MAPS_DIR := "user://maps"
const AI_DEBUG_DIR := "user://ai_debug"
# user:// resolves per-platform. Typical paths:
# - Windows: %APPDATA%/Godot/app_userdata/<project_name>/ai_debug
# - macOS: ~/Library/Application Support/Godot/app_userdata/<project_name>/ai_debug
# - Linux: ~/.local/share/godot/app_userdata/<project_name>/ai_debug
const AI_TRACE_FILE_PREFIX := "ai_trace_"
const AI_TRACE_LINE_LOG_PATH := "%s/ai_trace_lines.log" % AI_DEBUG_DIR
const AI_TRACE_INDEX_PATH := "%s/index.json" % AI_DEBUG_DIR
const AI_TRACE_MAX_TOTAL_BYTES := 20 * 1024 * 1024
const AI_TRACE_DEFAULT_MAX_FILES := 100
const DISPLAY_SETTINGS_PATH := "user://display_settings.json"

func _ensure_templates_dir() -> void:
	if DirAccess.dir_exists_absolute(DIVISION_TEMPLATES_DIR):
		return
	DirAccess.make_dir_recursive_absolute(DIVISION_TEMPLATES_DIR)

func _ensure_maps_dir() -> void:
	if DirAccess.dir_exists_absolute(MAPS_DIR):
		return
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)

func _ensure_ai_debug_dir() -> void:
	if DirAccess.dir_exists_absolute(AI_DEBUG_DIR):
		return
	DirAccess.make_dir_recursive_absolute(AI_DEBUG_DIR)

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

func _load_ai_trace_index() -> Dictionary:
	var index := _read_json(AI_TRACE_INDEX_PATH)
	if index.is_empty():
		return {
			"version": 1,
			"traces": []
		}
	if typeof(index.get("traces", [])) != TYPE_ARRAY:
		index["traces"] = []
	if not index.has("version"):
		index["version"] = 1
	return index

func _save_ai_trace_index(index: Dictionary) -> bool:
	return _write_json(AI_TRACE_INDEX_PATH, index)

func _get_file_size_bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	return int(file.get_length())

func _build_ai_trace_metadata(trace: Dictionary, trace_file: String, timestamp: int) -> Dictionary:
	var metadata := {
		"file": trace_file,
		"timestamp": timestamp,
		"trace_id": str(trace.get("trace_id", "")),
		"turn": int(trace.get("turn", -1)),
		"player": str(trace.get("player", trace.get("player_id", ""))),
		"phase": str(trace.get("phase", "")),
		"debug_level": str(trace.get("debug_level", "")),
		"size_bytes": 0
	}
	metadata["size_bytes"] = _get_file_size_bytes("%s/%s" % [AI_DEBUG_DIR, trace_file])
	return metadata

func _remove_ai_trace_file(trace_file: String) -> void:
	if trace_file.is_empty() or trace_file == "index.json":
		return
	if not trace_file.begins_with(AI_TRACE_FILE_PREFIX) or not trace_file.ends_with(".json"):
		return
	var full_path := "%s/%s" % [AI_DEBUG_DIR, trace_file]
	if FileAccess.file_exists(full_path):
		DirAccess.remove_absolute(full_path)

func autosave(payload: Dictionary) -> bool:
	return save_current_game(payload)

func save_current_game(payload: Dictionary) -> bool:
	return _write_json(CURRENT_GAME_SAVE_PATH, payload)

func load_current_game() -> Dictionary:
	return _read_json(CURRENT_GAME_SAVE_PATH)

func save_display_settings(payload: Dictionary) -> bool:
	return _write_json(DISPLAY_SETTINGS_PATH, payload)

func load_display_settings() -> Dictionary:
	return _read_json(DISPLAY_SETTINGS_PATH)

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
	map_payload["version"] = int(map_payload.get("version", GameState.MAP_PAYLOAD_VERSION_CURRENT))
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

func save_ai_trace(trace: Dictionary) -> bool:
	_ensure_ai_debug_dir()
	var timestamp := int(Time.get_unix_time_from_system())
	var trace_id := _safe_file_name(str(trace.get("trace_id", "")))
	if trace_id.is_empty():
		trace_id = str(Time.get_ticks_msec() % 1000000)
	var trace_file := "%s%d_%s.json" % [AI_TRACE_FILE_PREFIX, timestamp, trace_id]
	var full_path := "%s/%s" % [AI_DEBUG_DIR, trace_file]
	var dedupe_index := 1
	while FileAccess.file_exists(full_path):
		trace_file = "%s%d_%s_%d.json" % [AI_TRACE_FILE_PREFIX, timestamp, trace_id, dedupe_index]
		full_path = "%s/%s" % [AI_DEBUG_DIR, trace_file]
		dedupe_index += 1
	if not _write_json(full_path, trace):
		return false

	var index := _load_ai_trace_index()
	var traces: Array = index.get("traces", [])
	traces.append(_build_ai_trace_metadata(trace, trace_file, timestamp))
	index["traces"] = traces
	if not _save_ai_trace_index(index):
		_remove_ai_trace_file(trace_file)
		return false

	var retention_count := int(trace.get("retention_max_files", AI_TRACE_DEFAULT_MAX_FILES))
	prune_ai_traces(retention_count)
	var line_append_succeeded := true
	if trace.has("line_entries") and trace.get("line_entries") is PackedStringArray:
		line_append_succeeded = append_ai_trace_lines(trace.get("line_entries") as PackedStringArray)
	elif trace.has("line_entries") and trace.get("line_entries") is Array:
		var normalized_lines := PackedStringArray()
		for line in (trace.get("line_entries") as Array):
			normalized_lines.append(String(line))
		line_append_succeeded = append_ai_trace_lines(normalized_lines)
	return line_append_succeeded

func list_ai_traces() -> PackedStringArray:
	_ensure_ai_debug_dir()
	var result := PackedStringArray()
	var index := _load_ai_trace_index()
	var traces: Array = index.get("traces", [])
	for meta in traces:
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var trace_file := String((meta as Dictionary).get("file", ""))
		if trace_file.is_empty():
			continue
		var full_path := "%s/%s" % [AI_DEBUG_DIR, trace_file]
		if FileAccess.file_exists(full_path):
			result.append(trace_file)
	result.sort()
	var descending := PackedStringArray()
	for i in range(result.size() - 1, -1, -1):
		descending.append(result[i])
	return descending

func load_ai_trace(trace_file: String) -> Dictionary:
	_ensure_ai_debug_dir()
	var safe_file := _safe_file_name(trace_file)
	if safe_file.is_empty() or safe_file == "index.json":
		return {}
	if not safe_file.begins_with(AI_TRACE_FILE_PREFIX) or not safe_file.ends_with(".json"):
		return {}
	return _read_json("%s/%s" % [AI_DEBUG_DIR, safe_file])

func prune_ai_traces(max_files: int) -> void:
	_ensure_ai_debug_dir()
	var retention_count := maxi(max_files, 0)
	var index := _load_ai_trace_index()
	var traces: Array = index.get("traces", [])
	var filtered: Array = []
	for meta in traces:
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var entry := (meta as Dictionary)
		var trace_file := String(entry.get("file", ""))
		if trace_file.is_empty():
			continue
		var full_path := "%s/%s" % [AI_DEBUG_DIR, trace_file]
		if not FileAccess.file_exists(full_path):
			continue
		entry["size_bytes"] = _get_file_size_bytes(full_path)
		filtered.append(entry)

	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) > int(b.get("timestamp", 0))
	)

	var to_remove: Array = []
	while filtered.size() > retention_count:
		to_remove.append(filtered.pop_back())

	var total_size := 0
	for entry in filtered:
		total_size += int((entry as Dictionary).get("size_bytes", 0))
	while total_size > AI_TRACE_MAX_TOTAL_BYTES and not filtered.is_empty():
		var removed := filtered.pop_back() as Dictionary
		total_size -= int(removed.get("size_bytes", 0))
		to_remove.append(removed)

	for meta in to_remove:
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		_remove_ai_trace_file(String((meta as Dictionary).get("file", "")))

	index["traces"] = filtered
	_save_ai_trace_index(index)


func get_ai_debug_help_text() -> String:
	return "AI debug traces are written to %s (line log: %s). On Windows/macOS/Linux this maps to each platform's app_userdata folder." % [AI_DEBUG_DIR, AI_TRACE_LINE_LOG_PATH]

func append_ai_trace_lines(lines: PackedStringArray) -> bool:
	if lines.is_empty():
		return true
	_ensure_ai_debug_dir()
	var file := FileAccess.open(AI_TRACE_LINE_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(AI_TRACE_LINE_LOG_PATH, FileAccess.WRITE)
		if file == null:
			push_warning("Could not open AI line log for writing: %s" % AI_TRACE_LINE_LOG_PATH)
			return false
	file.seek_end()
	for line in lines:
		file.store_line(String(line))
	return true
