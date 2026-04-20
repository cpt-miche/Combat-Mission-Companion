extends RefCounted
class_name HexCellData

var terrain: String = "Light"

func _init(initial_terrain: String = "Light") -> void:
	terrain = initial_terrain
