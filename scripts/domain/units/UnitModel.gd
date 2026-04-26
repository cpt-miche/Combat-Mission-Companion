class_name UnitModel
extends Resource

@export var id: String = ""
@export var template_id: String = ""
@export var display_name: String = ""
@export var short_name: String = ""
@export var nation: String = ""
@export var type: UnitType.Value = UnitType.Value.INFANTRY
@export var size: UnitSize.Value = UnitSize.Value.PLATOON
@export var veterancy: Veterancy.Value = Veterancy.Value.REGULAR
@export var children: Array[UnitModel] = []

func child_count() -> int:
	return children.size()
