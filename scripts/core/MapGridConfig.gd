extends RefCounted
class_name MapGridConfig

const DEFAULT_COLUMNS := 32
const DEFAULT_ROWS := 32
const ALLOWED_SQUARE_SIZES: Array[int] = [8, 12, 16, 24, 32, 64]

# Backward-compatibility alias.
const ALLOWED_GRID_SIZES = ALLOWED_SQUARE_SIZES

static func default_columns() -> int:
	return DEFAULT_COLUMNS

static func default_rows() -> int:
	return DEFAULT_ROWS

static func allowed_sizes() -> Array[int]:
	return ALLOWED_SQUARE_SIZES.duplicate()

static func is_allowed_size(value: int) -> bool:
	return ALLOWED_SQUARE_SIZES.has(value)

static func normalize_size(value: int, fallback: int = DEFAULT_COLUMNS) -> int:
	if is_allowed_size(value):
		return value
	if is_allowed_size(fallback):
		return fallback
	return DEFAULT_COLUMNS

# Backward-compatibility helper.
static func is_allowed_grid_size(value: int) -> bool:
	return is_allowed_size(value)
