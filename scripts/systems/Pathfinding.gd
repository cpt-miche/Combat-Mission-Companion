extends RefCounted
class_name Pathfinding

const TERRAIN_COSTS := {
	"Highway": 1,
	"Road": 1,
	"Light": 2,
	"Heavy": 3,
	"Woods": 4
}

static func find_path(start: Vector2i, goal: Vector2i, terrain_map: Dictionary, blocked_cells: Dictionary = {}) -> Array[Vector2i]:
	if start == goal:
		return [start]

	var frontier := [start]
	var came_from := {start: start}
	var cost_so_far := {start: 0}

	while not frontier.is_empty():
		frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ca := int(cost_so_far[a]) + _heuristic(a, goal)
			var cb := int(cost_so_far[b]) + _heuristic(b, goal)
			return ca < cb
		)
		var current: Vector2i = frontier.pop_front()

		if current == goal:
			break

		for next in _neighbors(current):
			if blocked_cells.get(_key_for(next), false):
				continue
			var new_cost := int(cost_so_far[current]) + _move_cost(next, terrain_map)
			if not cost_so_far.has(next) or new_cost < int(cost_so_far[next]):
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not frontier.has(next):
					frontier.append(next)

	if not came_from.has(goal):
		return []

	var path: Array[Vector2i] = [goal]
	var step: Vector2i = goal
	while step != start:
		step = came_from[step]
		path.push_front(step)
	return path

static func _move_cost(hex: Vector2i, terrain_map: Dictionary) -> int:
	var terrain := String(terrain_map.get(_key_for(hex), "Light"))
	return int(TERRAIN_COSTS.get(terrain, 2))

static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	var dq: int = abs(a.x - b.x)
	var dr: int = abs(a.y - b.y)
	return int(max(dq, dr))

static func _neighbors(hex: Vector2i) -> Array[Vector2i]:
	var offsets_even: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, -1), Vector2i(-1, -1),
		Vector2i(0, 1), Vector2i(-1, 1)
	]
	var offsets_odd: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(0, 1)
	]
	var offsets: Array[Vector2i] = offsets_odd if hex.y % 2 == 1 else offsets_even
	var results: Array[Vector2i] = []
	for offset in offsets:
		var candidate := hex + offset
		if candidate.x >= 0 and candidate.x < 8 and candidate.y >= 0 and candidate.y < 6:
			results.append(candidate)
	return results

static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return _neighbors(a).has(b)

static func _key_for(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x, hex.y]
