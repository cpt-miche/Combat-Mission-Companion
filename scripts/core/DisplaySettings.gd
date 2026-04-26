extends Node
signal runtime_display_updated(applied: Dictionary)

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
const UI_SCALE_MODE_AUTO := "auto"
const UI_SCALE_MODE_MANUAL := "manual"
const DEFAULT_UI_SCALE_MODE := UI_SCALE_MODE_AUTO
const DEFAULT_UI_SCALE_VALUE := 1.0
const MIN_UI_SCALE_VALUE := 0.85
const MAX_UI_SCALE_VALUE := 1.35

const PRESETS := {
	PRESET_ID_720P: PRESET_720P,
	PRESET_ID_1080P: PRESET_1080P,
	PRESET_ID_1440P: PRESET_1440P
}

const AUTO_UI_SCALE_BY_PRESET := {
	PRESET_ID_720P: 1.0,
	PRESET_ID_1080P: 1.0,
	PRESET_ID_1440P: 1.2
}

var _selected_preset_id := DEFAULT_PRESET_ID
var _selected_window_mode := DEFAULT_WINDOW_MODE
var _selected_ui_scale_mode := DEFAULT_UI_SCALE_MODE
var _selected_ui_scale_value := DEFAULT_UI_SCALE_VALUE
var _connected_root_window: Window
var _last_known_window_size := Vector2i.ZERO

func get_preset_size(preset_id: String) -> Vector2i:
	var resolved_preset_id := _resolve_preset_id(preset_id)
	return PRESETS.get(resolved_preset_id, PRESET_1080P)

func get_selected_preset_id() -> String:
	return _selected_preset_id

func get_selected_window_mode() -> String:
	return _selected_window_mode

func get_selected_ui_scale_mode() -> String:
	return _selected_ui_scale_mode

func get_selected_ui_scale_value() -> float:
	return _selected_ui_scale_value

func get_effective_ui_scale() -> float:
	if _selected_ui_scale_mode == UI_SCALE_MODE_MANUAL:
		return _selected_ui_scale_value
	return get_auto_ui_scale_for_preset(_selected_preset_id)

func get_auto_ui_scale_for_preset(preset_id: String) -> float:
	var resolved_preset_id := _resolve_preset_id(preset_id)
	var fallback := AUTO_UI_SCALE_BY_PRESET.get(DEFAULT_PRESET_ID, DEFAULT_UI_SCALE_VALUE)
	return _clamp_ui_scale(float(AUTO_UI_SCALE_BY_PRESET.get(resolved_preset_id, fallback)))

func get_available_presets() -> Dictionary:
	return PRESETS.duplicate(true)

func get_window_size() -> Vector2i:
	return DisplayServer.window_get_size()

func get_available_manual_ui_scales() -> PackedFloat32Array:
	return PackedFloat32Array([0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35])

func set_selected_preset_id(preset_id: String, persist := true) -> String:
	var applied := set_display_settings(preset_id, _selected_window_mode, _selected_ui_scale_mode, _selected_ui_scale_value, persist)
	return String(applied.get("preset_id", DEFAULT_PRESET_ID))

func set_display_settings(preset_id: String, window_mode: String, ui_scale_mode: String = _selected_ui_scale_mode, ui_scale_value: float = _selected_ui_scale_value, persist := true) -> Dictionary:
	var applied_preset_id := _apply_preset_id(preset_id)
	var applied_window_mode := _apply_window_mode(window_mode)
	var applied_ui_scale_mode := _apply_ui_scale_mode(ui_scale_mode)
	var applied_ui_scale_value := _apply_ui_scale_value(ui_scale_value)
	_apply_effective_ui_scale()
	_last_known_window_size = get_window_size()
	if persist:
		SaveManager.save_display_settings({
			"preset_id": applied_preset_id,
			"window_mode": applied_window_mode,
			"ui_scale_mode": applied_ui_scale_mode,
			"ui_scale_value": applied_ui_scale_value
		})
	var applied_settings := get_current_settings()
	runtime_display_updated.emit(applied_settings)
	return applied_settings

func load_and_apply() -> String:
	var settings := SaveManager.load_display_settings()
	var stored_preset_id := String(settings.get("preset_id", DEFAULT_PRESET_ID))
	var stored_window_mode := String(settings.get("window_mode", DEFAULT_WINDOW_MODE))
	var stored_ui_scale_mode := String(settings.get("ui_scale_mode", DEFAULT_UI_SCALE_MODE))
	var stored_ui_scale_value := float(settings.get("ui_scale_value", DEFAULT_UI_SCALE_VALUE))
	_apply_preset_id(stored_preset_id)
	_apply_window_mode(stored_window_mode)
	_apply_ui_scale_mode(stored_ui_scale_mode)
	_apply_ui_scale_value(stored_ui_scale_value)
	_apply_effective_ui_scale()
	_last_known_window_size = get_window_size()
	runtime_display_updated.emit(get_current_settings())
	return _selected_preset_id

func connect_runtime_resize_notifications(root_window: Window) -> void:
	if root_window == null:
		return
	if is_instance_valid(_connected_root_window) and _connected_root_window.size_changed.is_connected(_on_root_window_size_changed):
		_connected_root_window.size_changed.disconnect(_on_root_window_size_changed)
	_connected_root_window = root_window
	if not _connected_root_window.size_changed.is_connected(_on_root_window_size_changed):
		_connected_root_window.size_changed.connect(_on_root_window_size_changed)
	_last_known_window_size = _connected_root_window.size

func reapply_runtime_settings() -> Dictionary:
	_apply_effective_ui_scale()
	_last_known_window_size = get_window_size()
	var applied_settings := get_current_settings()
	runtime_display_updated.emit(applied_settings)
	return applied_settings

func get_current_settings() -> Dictionary:
	return {
		"preset_id": _selected_preset_id,
		"window_mode": _selected_window_mode,
		"ui_scale_mode": _selected_ui_scale_mode,
		"ui_scale_value": _selected_ui_scale_value,
		"effective_ui_scale": get_effective_ui_scale(),
		"window_size": get_window_size()
	}

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

func _apply_ui_scale_mode(ui_scale_mode: String) -> String:
	var normalized_mode := ui_scale_mode.strip_edges().to_lower()
	if normalized_mode != UI_SCALE_MODE_MANUAL:
		normalized_mode = UI_SCALE_MODE_AUTO
	_selected_ui_scale_mode = normalized_mode
	return _selected_ui_scale_mode

func _apply_ui_scale_value(ui_scale_value: float) -> float:
	_selected_ui_scale_value = _clamp_ui_scale(ui_scale_value)
	return _selected_ui_scale_value

func _apply_effective_ui_scale() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var root_window := tree.root
	if root_window == null:
		return
	root_window.content_scale_factor = get_effective_ui_scale()

func _on_root_window_size_changed() -> void:
	var current_size := get_window_size()
	if current_size == _last_known_window_size:
		return
	_last_known_window_size = current_size
	reapply_runtime_settings()

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

func _clamp_ui_scale(ui_scale_value: float) -> float:
	return clampf(ui_scale_value, MIN_UI_SCALE_VALUE, MAX_UI_SCALE_VALUE)

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
