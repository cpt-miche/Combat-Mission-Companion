extends RefCounted
class_name MapGridConfig

const DEFAULT_COLUMNS := 32
const DEFAULT_ROWS := 32
const ALLOWED_GRID_SIZES := [8, 12, 16, 24, 32, 64]

static func default_columns() -> int:
	return DEFAULT_COLUMNS

static func default_rows() -> int:
	return DEFAULT_ROWS

static func is_allowed_grid_size(value: int) -> bool:
	return ALLOWED_GRID_SIZES.has(value)
