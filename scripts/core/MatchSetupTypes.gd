class_name MatchSetupTypes
extends RefCounted

const AI_DOCTRINES: Array[String] = [
	"balanced",
	"aggressive",
	"defensive"
]

const DIFFICULTIES: Array[String] = [
	"easy",
	"medium",
	"hard"
]

const DEFAULT_AI_DOCTRINE := "balanced"
const DEFAULT_DIFFICULTY := "medium"

static func sanitize_ai_doctrine(raw_doctrine: Variant) -> String:
	var doctrine := String(raw_doctrine).strip_edges().to_lower()
	if AI_DOCTRINES.has(doctrine):
		return doctrine
	return DEFAULT_AI_DOCTRINE

static func sanitize_difficulty(raw_difficulty: Variant) -> String:
	var difficulty := String(raw_difficulty).strip_edges().to_lower()
	if DIFFICULTIES.has(difficulty):
		return difficulty
	return DEFAULT_DIFFICULTY

static func display_name(identifier: String) -> String:
	return identifier.capitalize()
