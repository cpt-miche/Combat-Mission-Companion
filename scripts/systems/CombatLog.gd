extends RefCounted
class_name CombatLog

var entries: Array[Dictionary] = []

func add_entry(summary: String, details: Dictionary = {}) -> void:
	entries.append({
		"timestamp": Time.get_datetime_string_from_system(),
		"summary": summary,
		"details": details
	})

func clear() -> void:
	entries.clear()

func to_feed_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in entries:
		lines.append("[%s] %s" % [entry.get("timestamp", "--"), entry.get("summary", "")])
	return lines
