extends RefCounted
class_name HexCellData

var terrain: String = TerrainCatalog.DEFAULT_TERRAIN_ID

func _init(initial_terrain: String = TerrainCatalog.DEFAULT_TERRAIN_ID) -> void:
	terrain = TerrainCatalog.normalize_terrain_id(initial_terrain)
