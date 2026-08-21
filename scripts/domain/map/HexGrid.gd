class_name HexGrid
extends RefCounted

const EVEN_ROW_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(0, 1),
	Vector2i(-1, 1)
]
const ODD_ROW_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(0, 1)
]

static func neighbor_offsets(row: int) -> Array[Vector2i]:
	return ODD_ROW_OFFSETS if row % 2 == 1 else EVEN_ROW_OFFSETS

static func neighbors(hex: Vector2i, dimensions: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for offset in neighbor_offsets(hex.y):
		var candidate := hex + offset
		if candidate.x < 0 or candidate.y < 0 or candidate.x >= dimensions.x or candidate.y >= dimensions.y:
			continue
		results.append(candidate)
	return results

static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return (b - a) in neighbor_offsets(a.y)

static func distance(a: Vector2i, b: Vector2i) -> int:
	var a_cube := _odd_row_to_cube(a)
	var b_cube := _odd_row_to_cube(b)
	return maxi(
		abs(a_cube.x - b_cube.x),
		maxi(abs(a_cube.y - b_cube.y), abs(a_cube.z - b_cube.z))
	)

static func _odd_row_to_cube(hex: Vector2i) -> Vector3i:
	var cube_x := hex.x - int((hex.y - (hex.y & 1)) / 2)
	var cube_z := hex.y
	return Vector3i(cube_x, -cube_x - cube_z, cube_z)
