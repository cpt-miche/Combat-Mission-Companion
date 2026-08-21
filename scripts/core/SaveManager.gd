extends Node

const CURRENT_GAME_SAVE_PATH := "user://current_game.save"
const CURRENT_GAME_SAVE_VERSION := 2
const DIVISION_TEMPLATES_DIR := "user://division_templates"
const DIVISION_TEMPLATE_VERSION := 1
const MAPS_DIR := "user://maps"
const SCENARIOS_DIR := "res://data/scenarios"
const SCENARIO_DRAFTS_DIR := "user://scenario_drafts"
const SCENARIO_VERSION_CURRENT := 3
const SCENARIO_DRAFT_VERSION_CURRENT := 2
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
const DISPLAY_SETTINGS_VERSION := 1
const AI_TRACE_INDEX_VERSION := 2

var last_load_error: String = ""
var last_save_error: String = ""

func get_last_load_error() -> String:
	return last_load_error

func get_last_save_error() -> String:
	return last_save_error

func _set_load_error(message: String) -> void:
	last_load_error = message
	if not message.is_empty():
		push_warning(message)

func _set_save_error(message: String) -> void:
	last_save_error = message
	if not message.is_empty():
		push_warning(message)

func _ensure_templates_dir() -> void:
	if DirAccess.dir_exists_absolute(DIVISION_TEMPLATES_DIR):
		return
	DirAccess.make_dir_recursive_absolute(DIVISION_TEMPLATES_DIR)

func _ensure_maps_dir() -> void:
	if DirAccess.dir_exists_absolute(MAPS_DIR):
		return
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)

func _ensure_scenarios_dir() -> void:
	if DirAccess.dir_exists_absolute(SCENARIOS_DIR):
		return
	DirAccess.make_dir_recursive_absolute(SCENARIOS_DIR)

func _ensure_scenario_drafts_dir() -> void:
	if DirAccess.dir_exists_absolute(SCENARIO_DRAFTS_DIR):
		return
	DirAccess.make_dir_recursive_absolute(SCENARIO_DRAFTS_DIR)

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
	return _write_text_atomically(path, JSON.stringify(payload))

func _write_pretty_json(path: String, payload: Dictionary) -> bool:
	return _write_text_atomically(path, JSON.stringify(payload, "  ") + "\n")

func _write_text_atomically(path: String, contents: String) -> bool:
	last_save_error = ""
	var temporary_path := "%s.tmp" % path
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		_set_save_error("Could not open temporary save file for writing: %s" % ProjectSettings.globalize_path(temporary_path))
		return false
	file.store_string(contents)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		_set_save_error("Could not finish writing save file: %s" % ProjectSettings.globalize_path(path))
		return false
	var rename_error := DirAccess.rename_absolute(temporary_path, path)
	if rename_error == OK:
		return true
	DirAccess.remove_absolute(temporary_path)
	_set_save_error("Could not replace save file atomically: %s" % ProjectSettings.globalize_path(path))
	return false

func _read_json(path: String) -> Dictionary:
	last_load_error = ""
	if not FileAccess.file_exists(path):
		_set_load_error("File does not exist: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_load_error("Could not open file for reading: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_load_error("File contains invalid JSON data: %s" % path)
		return {}

	return parsed as Dictionary

func _load_ai_trace_index() -> Dictionary:
	if not FileAccess.file_exists(AI_TRACE_INDEX_PATH):
		return _new_ai_trace_index()
	var file := FileAccess.open(AI_TRACE_INDEX_PATH, FileAccess.READ)
	if file == null:
		return _reset_ai_debug_storage("the trace index could not be read")
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(contents)
	var parsed: Variant = parser.data if parse_error == OK else null
	var index: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	if not _is_valid_ai_trace_index(index):
		return _reset_ai_debug_storage("the trace index format was incompatible")
	return index

func _new_ai_trace_index() -> Dictionary:
	return {
		"version": AI_TRACE_INDEX_VERSION,
		"traces": []
	}

func _is_valid_ai_trace_index(index: Dictionary) -> bool:
	if int(index.get("version", -1)) != AI_TRACE_INDEX_VERSION or not (index.get("traces") is Array):
		return false
	for metadata_variant in index.get("traces", []) as Array:
		if not (metadata_variant is Dictionary):
			return false
		var metadata := metadata_variant as Dictionary
		for field_name in ["file", "timestamp", "trace_id", "turn", "player_id", "phase", "debug_level", "size_bytes"]:
			if not metadata.has(field_name):
				return false
		if metadata.has("player"):
			return false
		var trace_file := String(metadata.get("file", ""))
		if not trace_file.begins_with(AI_TRACE_FILE_PREFIX) or not trace_file.ends_with(".json"):
			return false
		if String(metadata.get("trace_id", "")).is_empty() or String(metadata.get("phase", "")).is_empty():
			return false
		for numeric_field in ["timestamp", "turn", "player_id", "debug_level", "size_bytes"]:
			if not _is_whole_json_number(metadata.get(numeric_field)):
				return false
	return true

func _reset_ai_debug_storage(reason: String) -> Dictionary:
	_ensure_ai_debug_dir()
	var directory := DirAccess.open(AI_DEBUG_DIR)
	if directory == null:
		_set_load_error("AI debug storage could not be reset because its directory could not be opened.")
		return {}
	var generated_files := PackedStringArray()
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and _is_generated_ai_debug_file(entry):
			generated_files.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	for generated_file in generated_files:
		if DirAccess.remove_absolute("%s/%s" % [AI_DEBUG_DIR, generated_file]) != OK:
			_set_load_error("AI debug storage could not be reset because %s could not be removed." % generated_file)
			return {}
	var fresh_index := _new_ai_trace_index()
	if not _save_ai_trace_index(fresh_index):
		return {}
	_set_load_error("AI debug storage was reset because %s; old debug traces were discarded." % reason)
	return fresh_index

func _is_generated_ai_debug_file(file_name: String) -> bool:
	if file_name in ["index.json", "index.json.tmp", "ai_trace_lines.log", "ai_trace_lines.log.tmp"]:
		return true
	return file_name.begins_with(AI_TRACE_FILE_PREFIX) and (file_name.ends_with(".json") or file_name.ends_with(".json.tmp"))

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
		"player_id": int(trace.get("player_id", -1)),
		"phase": str(trace.get("phase", "")),
		"debug_level": int(trace.get("debug_level", 0)),
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
	var save_payload := payload.duplicate(true)
	save_payload["save_version"] = CURRENT_GAME_SAVE_VERSION
	var validation_error := _current_game_validation_error(save_payload)
	if not validation_error.is_empty():
		push_warning("Current-game payload was not saved: %s" % validation_error)
		return false
	return _write_json(CURRENT_GAME_SAVE_PATH, save_payload)

func load_current_game() -> Dictionary:
	var payload := _read_json(CURRENT_GAME_SAVE_PATH)
	if payload.is_empty():
		return {}
	if not _is_valid_current_game_payload(payload):
		_set_load_error("The current-game save uses an incompatible format and was left unchanged.")
		return {}
	return payload

func save_display_settings(payload: Dictionary) -> bool:
	var settings := payload.duplicate(true)
	settings["settings_version"] = DISPLAY_SETTINGS_VERSION
	if not _is_valid_display_settings(settings):
		push_warning("Display settings payload is incomplete and was not saved.")
		return false
	return _write_json(DISPLAY_SETTINGS_PATH, settings)

func load_display_settings() -> Dictionary:
	if not FileAccess.file_exists(DISPLAY_SETTINGS_PATH):
		return {}
	var settings := _read_json(DISPLAY_SETTINGS_PATH)
	if settings.is_empty():
		return {}
	if not _is_valid_display_settings(settings):
		_set_load_error("Display settings use an incompatible format and were left unchanged.")
		return {}
	return settings

func save_division_template(template_name: String, payload: Dictionary) -> bool:
	var safe_name := _safe_file_name(template_name)
	if safe_name.is_empty():
		return false
	var template_payload := payload.duplicate(true)
	template_payload["template_version"] = DIVISION_TEMPLATE_VERSION
	if not _is_valid_division_template_payload(template_payload):
		push_warning("Division template payload is incomplete and was not saved: %s" % template_name)
		return false
	_ensure_templates_dir()
	return _write_json("%s/%s.json" % [DIVISION_TEMPLATES_DIR, safe_name], template_payload)

func load_division_template(template_name: String) -> Dictionary:
	var safe_name := _safe_file_name(template_name)
	if safe_name.is_empty():
		return {}
	var payload := _read_json("%s/%s.json" % [DIVISION_TEMPLATES_DIR, safe_name])
	if payload.is_empty():
		return {}
	if not _is_valid_division_template_payload(payload):
		_set_load_error("Division template '%s' uses an incompatible format and was left unchanged." % template_name)
		return {}
	return payload

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
	var map_payload := payload.duplicate(true)
	map_payload["version"] = GameState.MAP_PAYLOAD_VERSION_CURRENT
	map_payload["name"] = map_name
	if not GameState.validate_map_payload(map_payload):
		push_warning("Map payload is incomplete and was not saved: %s" % map_name)
		return false
	var existing_created_at := now_unix
	var existing_path := "%s/%s.json" % [MAPS_DIR, safe_name]
	if FileAccess.file_exists(existing_path):
		var existing_payload := _read_json(existing_path)
		if GameState.validate_map_payload(existing_payload):
			existing_created_at = int(existing_payload.get("created_at", now_unix))
	map_payload["created_at"] = int(map_payload.get("created_at", existing_created_at))
	map_payload["updated_at"] = now_unix
	return _write_json(existing_path, map_payload)

func load_map(map_name: String) -> Dictionary:
	var safe_name := _safe_file_name(map_name)
	if safe_name.is_empty():
		return {}
	var payload := _read_json("%s/%s.json" % [MAPS_DIR, safe_name])
	if payload.is_empty():
		return {}
	if not GameState.validate_map_payload(payload):
		_set_load_error("Map '%s' uses an incompatible format and was left unchanged." % map_name)
		return {}
	return payload

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

func save_scenario(scenario_name: String, payload: Dictionary) -> bool:
	last_save_error = ""
	var safe_name := _safe_file_name(scenario_name)
	if safe_name.is_empty():
		_set_save_error("Scenario name cannot be empty.")
		return false
	var scenario_payload := payload.duplicate(true)
	scenario_payload["scenario_version"] = SCENARIO_VERSION_CURRENT
	scenario_payload["name"] = scenario_name.strip_edges()
	var validation_errors := scenario_validation_errors(scenario_payload)
	if not validation_errors.is_empty():
		_set_save_error("Scenario '%s' was not saved: %s" % [scenario_name, "; ".join(validation_errors)])
		return false
	_ensure_scenarios_dir()
	var now_unix := int(Time.get_unix_time_from_system())
	var existing_created_at := now_unix
	var scenario_path := "%s/%s.json" % [SCENARIOS_DIR, safe_name]
	if FileAccess.file_exists(scenario_path):
		var existing_payload := _read_json(scenario_path)
		if _is_valid_scenario_payload(existing_payload):
			existing_created_at = int(existing_payload.get("created_at", now_unix))
	scenario_payload["created_at"] = int(scenario_payload.get("created_at", existing_created_at))
	scenario_payload["updated_at"] = now_unix
	return _write_json(scenario_path, scenario_payload)

func load_scenario(scenario_name: String) -> Dictionary:
	var safe_name := _safe_file_name(scenario_name)
	if safe_name.is_empty():
		return {}
	var payload := _read_json("%s/%s.json" % [SCENARIOS_DIR, safe_name])
	if payload.is_empty():
		return {}
	if not _is_valid_scenario_payload(payload):
		_set_load_error("Starting scenario '%s' uses an incompatible format and was left unchanged." % scenario_name)
		return {}
	return payload

func list_scenarios() -> PackedStringArray:
	_ensure_scenarios_dir()
	var result := PackedStringArray()
	var dir := DirAccess.open(SCENARIOS_DIR)
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

func list_scenario_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for scenario_id in list_scenarios():
		var payload := load_scenario(scenario_id)
		if payload.is_empty():
			continue
		records.append({
			"id": scenario_id,
			"name": String(payload.get("name", scenario_id)),
			"briefing": String(payload.get("briefing", ""))
		})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	return records

func load_scenario_ref(scenario_ref: Dictionary) -> Dictionary:
	var scenario_id := _safe_file_name(String(scenario_ref.get("id", "")))
	if scenario_id.is_empty():
		return {}
	return load_scenario(scenario_id)

func save_scenario_draft(draft_name: String, payload: Dictionary) -> bool:
	last_save_error = ""
	var safe_name := _safe_file_name(draft_name)
	if safe_name.is_empty():
		_set_save_error("Draft name cannot be empty.")
		return false
	if int(payload.get("draft_version", -1)) != SCENARIO_DRAFT_VERSION_CURRENT:
		_set_save_error("Draft format version is unsupported.")
		return false
	if not (payload.get("scenario") is Dictionary):
		_set_save_error("Draft does not contain scenario data.")
		return false
	_ensure_scenario_drafts_dir()
	return _write_pretty_json("%s/%s.json" % [SCENARIO_DRAFTS_DIR, safe_name], payload)

func load_scenario_draft(draft_name: String) -> Dictionary:
	var safe_name := _safe_file_name(draft_name)
	if safe_name.is_empty():
		return {}
	var payload := _read_json("%s/%s.json" % [SCENARIO_DRAFTS_DIR, safe_name])
	if int(payload.get("draft_version", -1)) != SCENARIO_DRAFT_VERSION_CURRENT or not (payload.get("scenario") is Dictionary):
		return {}
	return payload

func list_scenario_drafts() -> PackedStringArray:
	_ensure_scenario_drafts_dir()
	return _list_json_file_stems(SCENARIO_DRAFTS_DIR)

func scenario_draft_exists(draft_name: String) -> bool:
	var safe_name := _safe_file_name(draft_name)
	return not safe_name.is_empty() and FileAccess.file_exists("%s/%s.json" % [SCENARIO_DRAFTS_DIR, safe_name])

func delete_scenario_draft(draft_name: String) -> bool:
	var safe_name := _safe_file_name(draft_name)
	if safe_name.is_empty():
		return false
	var path := "%s/%s.json" % [SCENARIO_DRAFTS_DIR, safe_name]
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

func export_scenario(scenario_ref: Dictionary, destination_path: String) -> bool:
	var payload := load_scenario_ref(scenario_ref)
	if payload.is_empty() or destination_path.strip_edges().is_empty():
		return false
	return _write_pretty_json(destination_path, payload)

func import_scenario(source_path: String, replace_existing: bool = false) -> Dictionary:
	var payload := load_external_scenario(source_path)
	if payload.is_empty():
		return {}
	var base_name := String(payload.get("name", "Imported Scenario")).strip_edges()
	var candidate := _safe_file_name(base_name)
	if candidate.is_empty():
		candidate = "Imported_Scenario"
	if not replace_existing:
		var suffix := 2
		var original := candidate
		while scenario_exists(candidate):
			candidate = "%s_%d" % [original, suffix]
			suffix += 1
	var saved_name := base_name if candidate == _safe_file_name(base_name) else candidate.replace("_", " ")
	if not save_scenario(saved_name, payload):
		return {}
	return {"id": _safe_file_name(saved_name)}

func load_external_scenario(source_path: String) -> Dictionary:
	var payload := _read_json(source_path)
	if not _is_valid_scenario_payload(payload):
		_set_load_error("Imported scenario uses an invalid or incompatible format.")
		return {}
	return payload

func validate_scenario_payload(payload: Dictionary) -> bool:
	return _is_valid_scenario_payload(payload)

func scenario_validation_errors(payload: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(payload.get("scenario_version", -1)) != SCENARIO_VERSION_CURRENT:
		errors.append("Scenario format version is unsupported.")
	if String(payload.get("name", "")).strip_edges().is_empty():
		errors.append("Scenario name is required.")
	if not (payload.get("briefing", "") is String):
		errors.append("Scenario briefing must be text.")
	if not GameState.validate_map_payload(payload):
		errors.append("Scenario map data is incomplete or invalid.")
	var players_variant: Variant = payload.get("players", null)
	if not (players_variant is Array):
		errors.append("Scenario must contain a players array.")
		return errors
	var players := players_variant as Array
	if players.size() != 2:
		errors.append("Scenario must contain exactly two player forces.")
	if players.size() < 2:
		return errors
	var all_unit_ids := {}
	for player_index in range(2):
		var player_label := "Player %d" % (player_index + 1)
		if not (players[player_index] is Dictionary):
			errors.append("%s force data is invalid." % player_label)
			continue
		var player := players[player_index] as Dictionary
		if player.has("is_ai") or player.has("controller"):
			errors.append("%s contains runtime-only controller data." % player_label)
		if String(player.get("name", "")).strip_edges().is_empty():
			errors.append("%s force name is required." % player_label)
		if String(player.get("nation_id", "")).strip_edges().is_empty():
			errors.append("%s nation is required." % player_label)
		var tree_variant: Variant = player.get("division_tree", null)
		if not (tree_variant is Dictionary) or (tree_variant as Dictionary).is_empty():
			errors.append("%s force structure is missing." % player_label)
			continue
		var tree := tree_variant as Dictionary
		if not _is_valid_unit_tree(tree):
			errors.append("%s force structure contains invalid unit data." % player_label)
		elif not _collect_unique_unit_ids(tree, all_unit_ids):
			errors.append("%s force structure contains missing or duplicate unit IDs." % player_label)
		var deployments_variant: Variant = player.get("deployments", null)
		if not (deployments_variant is Dictionary):
			errors.append("%s deployment data is missing." % player_label)
			continue
		if not _is_valid_deployments(deployments_variant as Dictionary):
			errors.append("%s deployment snapshots contain invalid unit data." % player_label)
		errors.append_array(_scenario_deployment_errors(payload, player, player_index))
	return errors

func validate_scenario_player_deployment(payload: Dictionary, player_index: int) -> bool:
	var players := payload.get("players", []) as Array
	if player_index < 0 or player_index >= players.size() or not (players[player_index] is Dictionary):
		return false
	return _scenario_deployments_match_map_and_tree(payload, players[player_index] as Dictionary, player_index)

func _list_json_file_stems(directory_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(directory_path)
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

func scenario_exists(scenario_name: String) -> bool:
	var safe_name := _safe_file_name(scenario_name)
	if safe_name.is_empty():
		return false
	return FileAccess.file_exists("%s/%s.json" % [SCENARIOS_DIR, safe_name])

func delete_scenario(scenario_name: String) -> bool:
	var safe_name := _safe_file_name(scenario_name)
	if safe_name.is_empty():
		return false
	var full_path := "%s/%s.json" % [SCENARIOS_DIR, safe_name]
	if not FileAccess.file_exists(full_path):
		return false
	return DirAccess.remove_absolute(full_path) == OK

func _is_valid_scenario_payload(payload: Dictionary) -> bool:
	return scenario_validation_errors(payload).is_empty()

func _scenario_deployments_match_map_and_tree(payload: Dictionary, player: Dictionary, player_index: int) -> bool:
	return _scenario_deployment_errors(payload, player, player_index).is_empty()

func _scenario_deployment_errors(payload: Dictionary, player: Dictionary, player_index: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var player_label := "Player %d" % (player_index + 1)
	var grid := payload.get("grid", {}) as Dictionary
	var columns := int(grid.get("columns", 0))
	var rows := int(grid.get("rows", 0))
	var territory := payload.get("territory", {}) as Dictionary
	var expected_owner := GameState.TerritoryOwnership.PLAYER_1 if player_index == 0 else GameState.TerritoryOwnership.PLAYER_2
	var tree_ids := {}
	_collect_unit_ids(player.get("division_tree", {}) as Dictionary, tree_ids)
	var seen_ids := {}
	var deployments := player.get("deployments", {}) as Dictionary
	if deployments.is_empty():
		errors.append("%s has no deployed units." % player_label)
		return errors
	var coordinates := PackedStringArray()
	for coordinate_variant in deployments.keys():
		coordinates.append(String(coordinate_variant))
	coordinates.sort()
	for coordinate in coordinates:
		var parts := coordinate.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			errors.append("%s deployment hex '%s' is malformed." % [player_label, coordinate])
			continue
		var column := int(parts[0])
		var row := int(parts[1])
		if column < 0 or row < 0 or column >= columns or row >= rows:
			errors.append("%s deployment hex %s is outside the map." % [player_label, coordinate])
			continue
		if int(territory.get(coordinate, GameState.TerritoryOwnership.NEUTRAL)) != expected_owner:
			errors.append("%s hex %s is outside that player's deployment territory." % [player_label, coordinate])
		var deployment_variant: Variant = deployments[coordinate]
		if not (deployment_variant is Dictionary) and not (deployment_variant is Array):
			errors.append("%s hex %s contains malformed deployment data." % [player_label, coordinate])
			continue
		var deployed_units: Array = [deployment_variant] if deployment_variant is Dictionary else deployment_variant as Array
		var stack: Array[Dictionary] = []
		for unit_variant in deployed_units:
			if not (unit_variant is Dictionary):
				errors.append("%s hex %s contains malformed unit data." % [player_label, coordinate])
				continue
			var unit := unit_variant as Dictionary
			var unit_id := String(unit.get("id", ""))
			if not tree_ids.has(unit_id):
				errors.append("%s hex %s contains a unit not present in its force structure." % [player_label, coordinate])
				continue
			if seen_ids.has(unit_id):
				errors.append("%s unit '%s' is deployed more than once." % [player_label, unit_id])
				continue
			seen_ids[unit_id] = true
			stack.append(unit)
		var stack_result := Rules.validate_stack(stack)
		if not bool(stack_result.get("ok", false)):
			errors.append("%s hex %s: %s" % [player_label, coordinate, String(stack_result.get("reason", "Illegal stack."))])
	var coverage := _scenario_deployment_coverage(player.get("division_tree", {}) as Dictionary, seen_ids)
	if not bool(coverage.get("has_deployable", false)):
		errors.append("%s force contains no deployable formations." % player_label)
	elif not bool(coverage.get("satisfied", false)):
		errors.append("%s still has undeployed formations." % player_label)
	return errors

func _scenario_deployment_coverage(node: Dictionary, deployed_ids: Dictionary) -> Dictionary:
	if node.is_empty():
		return {"has_deployable": false, "satisfied": true}
	var unit_id := String(node.get("id", ""))
	var is_deployable := DeploymentValidator.placement_block_reason(node, []).is_empty()
	var has_deployable_descendant := false
	var descendants_satisfied := true
	for child_variant in node.get("children", []) as Array:
		if not (child_variant is Dictionary):
			continue
		var child_result := _scenario_deployment_coverage(child_variant as Dictionary, deployed_ids)
		if bool(child_result.get("has_deployable", false)):
			has_deployable_descendant = true
			if not bool(child_result.get("satisfied", false)):
				descendants_satisfied = false
	var satisfied := descendants_satisfied
	if is_deployable:
		satisfied = deployed_ids.has(unit_id) or (has_deployable_descendant and descendants_satisfied)
	return {
		"has_deployable": is_deployable or has_deployable_descendant,
		"satisfied": satisfied
	}

func _collect_unit_ids(node: Dictionary, result: Dictionary) -> void:
	if node.is_empty():
		return
	var unit_id := String(node.get("id", ""))
	if unit_id.is_empty() or result.has(unit_id):
		return
	result[unit_id] = true
	for child_variant in node.get("children", []) as Array:
		if child_variant is Dictionary:
			_collect_unit_ids(child_variant as Dictionary, result)

func _collect_unique_unit_ids(node: Dictionary, result: Dictionary) -> bool:
	if node.is_empty():
		return false
	var unit_id := String(node.get("id", ""))
	if unit_id.is_empty() or result.has(unit_id):
		return false
	result[unit_id] = true
	for child_variant in node.get("children", []) as Array:
		if not (child_variant is Dictionary) or not _collect_unique_unit_ids(child_variant as Dictionary, result):
			return false
	return true

func _is_valid_current_game_payload(payload: Dictionary) -> bool:
	return _current_game_validation_error(payload).is_empty()

func _current_game_validation_error(payload: Dictionary) -> String:
	for retired_key in ["terrain", "territory", "objectives", "map_size", "map_dimensions"]:
		if payload.has(retired_key):
			return "retired top-level field '%s'" % retired_key
	if int(payload.get("save_version", -1)) != CURRENT_GAME_SAVE_VERSION:
		return "unsupported save_version"
	for dictionary_key in ["map", "ai_debug", "ai_formation_state", "scout_intel_by_observer", "units", "orders", "casualties"]:
		if not (payload.get(dictionary_key) is Dictionary):
			return "missing dictionary '%s'" % dictionary_key
	if not (payload.get("players") is Array):
		return "missing players array"
	if not (payload.get("combat_log_entries") is Array):
		return "missing combat_log_entries array"
	if not GameState.validate_map_payload(payload.get("map", {}) as Dictionary):
		return "invalid map"
	var player_index := 0
	for player_variant in payload.get("players", []) as Array:
		if not (player_variant is Dictionary):
			return "player %d is not a dictionary" % player_index
		var player := player_variant as Dictionary
		if player.has("is_ai"):
			return "player %d uses retired field 'is_ai'" % player_index
		if not _is_valid_unit_tree(player.get("division_tree", {}) as Dictionary):
			return "player %d has an invalid division_tree" % player_index
		if not _is_valid_deployments(player.get("deployments", {}) as Dictionary):
			return "player %d has invalid deployments" % player_index
		player_index += 1
	for unit_id_variant in (payload.get("units", {}) as Dictionary).keys():
		var unit_variant: Variant = (payload.get("units", {}) as Dictionary)[unit_id_variant]
		if not (unit_variant is Dictionary) or not _is_valid_unit_record(unit_variant as Dictionary, false):
			return "runtime unit '%s' is invalid" % String(unit_id_variant)
	return ""

func _is_valid_division_template_payload(payload: Dictionary) -> bool:
	return (
		int(payload.get("template_version", -1)) == DIVISION_TEMPLATE_VERSION
		and _is_whole_json_number(payload.get("id_counter"))
		and payload.get("root_unit") is Dictionary
		and _is_valid_unit_tree(payload.get("root_unit", {}) as Dictionary)
	)

func _is_whole_json_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(float(value), floorf(float(value)))

func _is_valid_unit_tree(unit: Dictionary) -> bool:
	if not _is_valid_unit_record(unit, true):
		return false
	for child_variant in unit.get("children", []) as Array:
		if not (child_variant is Dictionary) or not _is_valid_unit_tree(child_variant as Dictionary):
			return false
	return true

func _is_valid_unit_record(unit: Dictionary, requires_children: bool) -> bool:
	for retired_field in ["name", "unit_type", "formation_size", "is_alive", "entrenched", "is_entrenched", "is_tank"]:
		if unit.has(retired_field):
			return false
	for field_name in ["id", "display_name", "type", "size", "role", "status"]:
		if not (unit.get(field_name) is String) or String(unit.get(field_name)).strip_edges().is_empty():
			return false
	if String(unit.get("status")).to_lower() not in ["alive", "dead"]:
		return false
	if not (unit.get("designation") is Dictionary):
		return false
	if unit.has("is_attached") and not (unit.get("is_attached") is bool):
		return false
	if requires_children and not (unit.get("children") is Array):
		return false
	if unit.has("vehicles") and not (unit.get("vehicles") is Array):
		return false
	for vehicle_variant in unit.get("vehicles", []) as Array:
		if not (vehicle_variant is Dictionary):
			return false
		var vehicle := vehicle_variant as Dictionary
		if vehicle.has("is_alive"):
			return false
		if not (vehicle.get("id") is String) or String(vehicle.get("id")).is_empty():
			return false
		if String(vehicle.get("status", "")).to_lower() not in ["alive", "dead"]:
			return false
	return true

func _is_valid_deployments(deployments: Dictionary) -> bool:
	for deployed_variant in deployments.values():
		var units: Array = [deployed_variant] if deployed_variant is Dictionary else (deployed_variant as Array if deployed_variant is Array else [])
		if units.is_empty():
			return false
		for unit_variant in units:
			if not (unit_variant is Dictionary) or not _is_valid_unit_record(unit_variant as Dictionary, false):
				return false
	return true

func _is_valid_display_settings(settings: Dictionary) -> bool:
	return (
		int(settings.get("settings_version", -1)) == DISPLAY_SETTINGS_VERSION
		and settings.get("preset_id") is String
		and settings.get("window_mode") is String
		and settings.get("ui_scale_mode") is String
		and (settings.get("ui_scale_value") is float or settings.get("ui_scale_value") is int)
	)

func save_ai_trace(trace: Dictionary) -> bool:
	_ensure_ai_debug_dir()
	var index := _load_ai_trace_index()
	if index.is_empty():
		return false
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
	if not _write_pretty_json(full_path, trace):
		return false

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
	if index.is_empty():
		return
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
		if file.get_error() != OK:
			file.close()
			push_warning("Could not append all AI trace lines to: %s" % AI_TRACE_LINE_LOG_PATH)
			return false
	file.close()
	return true
