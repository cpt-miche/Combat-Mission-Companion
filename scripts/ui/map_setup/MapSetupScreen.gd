extends Control

const TERRAIN_TYPES := ["Highway", "Road", "Light", "Heavy", "Woods"]

@onready var terrain_list: VBoxContainer = %TerrainList
@onready var hex_map_view: HexMapView = %HexMapView
@onready var clear_all_button: Button = %ClearAllButton
@onready var confirm_button: Button = %ConfirmButton
@onready var load_png_button: Button = %LoadPngButton

var _terrain_group := ButtonGroup.new()

func _ready() -> void:
	_build_palette()
	clear_all_button.pressed.connect(_on_clear_all_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	load_png_button.pressed.connect(hex_map_view.open_map_dialog)

func _build_palette() -> void:
	for terrain in TERRAIN_TYPES:
		var button := CheckButton.new()
		button.text = terrain
		button.toggle_mode = true
		button.button_group = _terrain_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(_on_terrain_toggled.bind(terrain))
		terrain_list.add_child(button)
		if terrain == "Light":
			button.button_pressed = true
			hex_map_view.set_selected_terrain(terrain)

func _on_terrain_toggled(is_toggled: bool, terrain: String) -> void:
	if not is_toggled:
		return
	hex_map_view.set_selected_terrain(terrain)

func _on_clear_all_pressed() -> void:
	hex_map_view.clear_all()

func _on_confirm_pressed() -> void:
	print("Map setup confirmed: %d customized hexes" % hex_map_view.hexes.size())
