extends Node

const PRESET_720P := Vector2i(1280, 720)
const PRESET_1080P := Vector2i(1920, 1080)
const PRESET_1440P := Vector2i(2560, 1440)

const PRESET_ID_720P := "720p"
const PRESET_ID_1080P := "1080p"
const PRESET_ID_1440P := "1440p"
const DEFAULT_PRESET_ID := PRESET_ID_1080P
const WINDOW_MODE_WINDOWED := "windowed"
const WINDOW_MODE_FULLSCREEN := "fullscreen"
const DEFAULT_WINDOW_MODE := WINDOW_MODE_WINDOWED

const PRESETS := {
	PRESET_ID_720P: PRESET_720P,
	PRESET_ID_1080P: PRESET_1080P,
	PRESET_ID_1440P: PRESET_1440P
}

var _selected_preset_id := DEFAULT_PRESET_ID
var _selected_window_mode := DEFAULT_WINDOW_MODE

func get_preset_size(preset_id: String) -> Vector2i:
	var resolved_preset_id := _resolve_preset_id(preset_id)
	return PRESETS.get(resolved_preset_id, PRESET_1080P)

func get_selected_preset_id() -> String:
	return _selected_preset_id

func get_selected_window_mode() -> String:
	return _selected_window_mode

func get_available_presets() -> Dictionary:
	return PRESETS.duplicate(true)

func get_window_size() -> Vector2i:
	return DisplayServer.window_get_size()

func set_selected_preset_id(preset_id: String, persist := true) -> String:
	var applied := set_display_settings(preset_id, _selected_window_mode, persist)
	return String(applied.get("preset_id", DEFAULT_PRESET_ID))

func set_display_settings(preset_id: String, window_mode: String, persist := true) -> Dictionary:
	var applied_preset_id := _apply_preset_id(preset_id)
	var applied_window_mode := _apply_window_mode(window_mode)
	if persist:
		SaveManager.save_display_settings({
			"preset_id": applied_preset_id,
			"window_mode": applied_window_mode
		})
	return {
		"preset_id": applied_preset_id,
		"window_mode": applied_window_mode
	}

func load_and_apply() -> String:
	var settings := SaveManager.load_display_settings()
	var stored_preset_id := String(settings.get("preset_id", DEFAULT_PRESET_ID))
	var stored_window_mode := String(settings.get("window_mode", DEFAULT_WINDOW_MODE))
	_apply_preset_id(stored_preset_id)
	_apply_window_mode(stored_window_mode)
	return _selected_preset_id

func _apply_preset_id(preset_id: String) -> String:
	var resolved_preset_id := _resolve_preset_id(preset_id)
	var target_size: Vector2i = PRESETS.get(resolved_preset_id, PRESET_1080P)
	var effective_size := _fit_size_to_usable_rect(target_size)

	DisplayServer.window_set_size(effective_size)
	_center_window(effective_size)
	_selected_preset_id = resolved_preset_id

	return _selected_preset_id

func _apply_window_mode(window_mode: String) -> String:
	var resolved_mode := _resolve_window_mode(window_mode)
	var server_mode := DisplayServer.WINDOW_MODE_WINDOWED
	if resolved_mode == WINDOW_MODE_FULLSCREEN:
		server_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(server_mode)
	_selected_window_mode = resolved_mode
	return _selected_window_mode

func _resolve_window_mode(window_mode: String) -> String:
	var normalized_mode := window_mode.strip_edges().to_lower()
	if normalized_mode == WINDOW_MODE_FULLSCREEN:
		return WINDOW_MODE_FULLSCREEN
	return WINDOW_MODE_WINDOWED

func _resolve_preset_id(preset_id: String) -> String:
	if PRESETS.has(preset_id):
		var preset_size: Vector2i = PRESETS.get(preset_id, PRESET_1080P)
		if _is_resolution_available(preset_size):
			return preset_id

	return _get_fallback_preset_id()

func _get_fallback_preset_id() -> String:
	var default_size: Vector2i = PRESETS.get(DEFAULT_PRESET_ID, PRESET_1080P)
	if _is_resolution_available(default_size):
		return DEFAULT_PRESET_ID

	for candidate_id in [PRESET_ID_720P, PRESET_ID_1080P, PRESET_ID_1440P]:
		var candidate_size: Vector2i = PRESETS.get(candidate_id, PRESET_1080P)
		if _is_resolution_available(candidate_size):
			return candidate_id

	return PRESET_ID_720P

func _is_resolution_available(size: Vector2i) -> bool:
	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		return true
	return size.x <= usable_rect.size.x and size.y <= usable_rect.size.y

func _center_window(size: Vector2i) -> void:
	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		return
	var centered_position := usable_rect.position + (usable_rect.size - size) / 2
	DisplayServer.window_set_position(centered_position)

func _fit_size_to_usable_rect(size: Vector2i) -> Vector2i:
	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		return size
	return Vector2i(
		min(size.x, usable_rect.size.x),
		min(size.y, usable_rect.size.y)
	)
