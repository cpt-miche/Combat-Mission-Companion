extends Node

const PRESET_720P := Vector2i(1280, 720)
const PRESET_1080P := Vector2i(1920, 1080)
const PRESET_1440P := Vector2i(2560, 1440)

const PRESET_ID_720P := "720p"
const PRESET_ID_1080P := "1080p"
const PRESET_ID_1440P := "1440p"
const DEFAULT_PRESET_ID := PRESET_ID_1080P

const PRESETS := {
	PRESET_ID_720P: PRESET_720P,
	PRESET_ID_1080P: PRESET_1080P,
	PRESET_ID_1440P: PRESET_1440P
}

var _selected_preset_id := DEFAULT_PRESET_ID

func get_preset_size(preset_id: String) -> Vector2i:
	var resolved_preset_id := _resolve_preset_id(preset_id)
	return PRESETS.get(resolved_preset_id, PRESET_1080P)

func get_selected_preset_id() -> String:
	return _selected_preset_id

func get_available_presets() -> Dictionary:
	return PRESETS.duplicate(true)

func get_window_size() -> Vector2i:
	return DisplayServer.window_get_size()

func set_selected_preset_id(preset_id: String, persist := true) -> String:
	var applied_preset_id := _apply_preset_id(preset_id)
	if persist:
		SaveManager.save_display_settings({"preset_id": applied_preset_id})
	return applied_preset_id

func load_and_apply() -> String:
	var settings := SaveManager.load_display_settings()
	var stored_preset_id := String(settings.get("preset_id", DEFAULT_PRESET_ID))
	return _apply_preset_id(stored_preset_id)

func _apply_preset_id(preset_id: String) -> String:
	var resolved_preset_id := _resolve_preset_id(preset_id)
	var target_size: Vector2i = PRESETS.get(resolved_preset_id, PRESET_1080P)

	DisplayServer.window_set_size(target_size)
	_center_window(target_size)
	_selected_preset_id = resolved_preset_id

	return _selected_preset_id

func _resolve_preset_id(preset_id: String) -> String:
	if not PRESETS.has(preset_id):
		return DEFAULT_PRESET_ID

	var preset_size: Vector2i = PRESETS.get(preset_id, PRESET_1080P)
	if not _is_resolution_available(preset_size):
		return DEFAULT_PRESET_ID

	return preset_id

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
