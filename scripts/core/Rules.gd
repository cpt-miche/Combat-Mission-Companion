extends Node

const MAX_PLAYERS := 2
const MIN_POINT_LIMIT := 100
const MAX_POINT_LIMIT := 5000

func is_valid_player_count(player_count: int) -> bool:
	return player_count >= 1 and player_count <= MAX_PLAYERS

func is_valid_points_limit(points: int) -> bool:
	return points >= MIN_POINT_LIMIT and points <= MAX_POINT_LIMIT

func can_advance_from_phase(current_phase: GameState.Phase, target_phase: GameState.Phase) -> bool:
	return int(target_phase) >= int(current_phase)
