extends Node
class_name SaveManager

const SAVE_FILE_PATH := "user://savegame.json"

func save_game(payload: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open save file for writing")
		return false

	file.store_string(JSON.stringify(payload))
	return true

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return {}

	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open save file for reading")
		return {}

	var parsed := JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file content is invalid")
		return {}

	return parsed

func autosave(payload: Dictionary) -> bool:
	return save_game(payload)
