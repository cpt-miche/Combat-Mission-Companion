class_name NatoUnitSymbolRenderer
extends RefCounted

const UnitRole = preload("res://scripts/domain/units/UnitRole.gd")
const UnitNotationFormatter = preload("res://scripts/domain/units/UnitNotationFormatter.gd")
const UnitEquipmentWeight = preload("res://scripts/domain/units/UnitEquipmentWeight.gd")

const REFERENCE_HEX_RADIUS := 32.0
const FRAME_SIZE := Vector2(40.0, 24.0)
const IDENTITY_ZOOM_THRESHOLD := 0.8
const PLAYER_ONE_FILL := Color("7ea7d8")
const PLAYER_TWO_FILL := Color("d9867f")
const INK := Color("101318")
const STACK_BADGE_FILL := Color("151a21")
const STACK_BADGE_TEXT := Color("f4f6f8")
const SELECTED_OUTLINE := Color("ffe26a")
const PRIMARY_OUTLINE := Color("ffb633")

static func build_symbol_spec(unit: Dictionary) -> Dictionary:
	var broad_type := _identifier(String(unit.get("type", "")))
	var role := UnitRole.normalize(unit.get("role", ""), broad_type)
	var function := "unknown"
	var mobility := ""

	match role:
		"infantry", "rifle", "grenadier":
			function = "infantry"
		"mechanized":
			function = "mechanized"
		"motorized":
			function = "motorized"
		"light_tank":
			function = "armor"
		"medium_tank":
			function = "armor"
		"heavy_tank":
			function = "armor"
		"tank_destroyer":
			function = "anti_armor"
			mobility = "tracked"
		"assault_gun":
			function = "assault_gun"
			mobility = "tracked"
		"anti_tank", "anti_tank_gun", "medium_anti_tank_gun":
			function = "anti_armor"
		"weapons", "heavy_weapons", "machine_gun":
			function = "machine_gun"
		"light_machine_gun":
			function = "machine_gun"
		"medium_machine_gun":
			function = "machine_gun"
		"heavy_machine_gun":
			function = "machine_gun"
		"60mm_mortar", "81mm_mortar", "8cm_mortar", "12cm_mortar", "mortar":
			function = "mortar"
		"105mm_howitzer", "155mm_howitzer", "howitzer", "cannon", "artillery":
			function = "artillery"
		"engineer", "pionier":
			function = "engineer"
		"recon":
			function = "recon"
		"airborne":
			function = "airborne"
		"air_defense":
			function = "air_defense"
		"headquarters":
			function = "headquarters"
		_:
			function = _function_for_type(broad_type)

	return {
		"function": function,
		"qualifier": "",
		"equipment_weight": equipment_weight_for_unit(unit, role),
		"identity_text": UnitNotationFormatter.format_counter_unit(unit),
		"mobility": mobility,
		"echelon": echelon_for_size(String(unit.get("size", "")))
	}

static func equipment_weight_for_unit(unit: Dictionary, normalized_role: String = "") -> String:
	return UnitEquipmentWeight.for_unit(unit, normalized_role)

static func echelon_for_size(raw_size: String) -> Dictionary:
	match _identifier(raw_size):
		"squad":
			return {"kind": "dot", "count": 1}
		"section":
			return {"kind": "dot", "count": 2}
		"platoon":
			return {"kind": "dot", "count": 3}
		"company":
			return {"kind": "bar", "count": 1}
		"battalion":
			return {"kind": "bar", "count": 2}
		"regiment":
			return {"kind": "bar", "count": 3}
		"division":
			return {"kind": "x", "count": 2}
		"army":
			return {"kind": "x", "count": 4}
		_:
			return {"kind": "none", "count": 0}

static func symbol_bounds(hex_radius: float, stack_count: int = 1) -> Rect2:
	var scale := hex_radius / REFERENCE_HEX_RADIUS
	var backplate_offset := float(mini(maxi(stack_count - 1, 0), 3))
	return Rect2(Vector2(-20.0, -12.0) * scale, Vector2(40.0 + backplate_offset, 24.0 + backplate_offset) * scale)

static func contains_point(center: Vector2, point: Vector2, scale: float = 1.0) -> bool:
	var frame_rect := Rect2(center - FRAME_SIZE * scale * 0.5, FRAME_SIZE * scale)
	return frame_rect.grow(3.0 * scale).has_point(point)

static func draw_stack(
	canvas: CanvasItem,
	center: Vector2,
	front_unit: Dictionary,
	owner: int,
	stack_count: int,
	font: Font,
	scale: float = 1.0,
	is_selected: bool = false,
	is_primary: bool = false,
	alpha: float = 1.0,
	detail_scale: float = -1.0
) -> void:
	var fill := PLAYER_ONE_FILL if owner == 0 else PLAYER_TWO_FILL
	fill.a *= alpha
	var ink := INK
	ink.a *= alpha
	var visible_backplates := mini(maxi(stack_count - 1, 0), 3)
	for layer in range(visible_backplates, 0, -1):
		var offset := Vector2(float(layer), float(layer)) * scale
		_draw_frame(canvas, center + offset, fill.darkened(0.12), ink, scale)

	if is_primary:
		_draw_outline(canvas, center, PRIMARY_OUTLINE, scale, 3.0)
	if is_selected:
		_draw_outline(canvas, center, SELECTED_OUTLINE, scale, 2.5)

	_draw_frame(canvas, center, fill, ink, scale)
	var spec := build_symbol_spec(front_unit)
	_draw_function(canvas, center, spec, font, ink, scale)
	_draw_identity(canvas, center, String(spec.get("identity_text", "")), font, ink, scale, detail_scale if detail_scale >= 0.0 else scale)
	_draw_echelon(canvas, center, spec.get("echelon", {}) as Dictionary, ink, scale)
	_draw_mobility(canvas, center, String(spec.get("mobility", "")), ink, scale)

	if stack_count > 1:
		_draw_stack_badge(canvas, center, stack_count, font, scale, alpha)

static func _draw_frame(canvas: CanvasItem, center: Vector2, fill: Color, ink: Color, scale: float) -> void:
	var rect := Rect2(center - FRAME_SIZE * scale * 0.5, FRAME_SIZE * scale)
	canvas.draw_rect(rect, fill, true)
	canvas.draw_rect(rect, ink, false, maxf(1.0, 1.5 * scale), true)

static func _draw_outline(canvas: CanvasItem, center: Vector2, color: Color, scale: float, grow: float) -> void:
	var rect := Rect2(center - FRAME_SIZE * scale * 0.5, FRAME_SIZE * scale).grow(grow * scale)
	canvas.draw_rect(rect, color, false, maxf(1.5, 2.0 * scale), true)

static func _draw_function(canvas: CanvasItem, center: Vector2, spec: Dictionary, font: Font, ink: Color, scale: float) -> void:
	var function := String(spec.get("function", "unknown"))
	var equipment_weight := String(spec.get("equipment_weight", ""))
	var glyph_center := center + Vector2(0, -3) * scale
	match function:
		"infantry":
			_draw_infantry(canvas, glyph_center, ink, scale)
		"mechanized":
			_draw_ellipse(canvas, glyph_center, Vector2(10.0, 4.5), ink, scale)
			_draw_infantry(canvas, glyph_center, ink, scale)
		"motorized":
			_draw_infantry(canvas, glyph_center, ink, scale)
			_draw_wheeled_mobility(canvas, center, ink, scale)
		"armor":
			_draw_ellipse(canvas, glyph_center, Vector2(10.0, 4.5), ink, scale)
		"anti_armor":
			_draw_polyline(canvas, glyph_center, [Vector2(-8, 5), Vector2(0, -5), Vector2(8, 5)], ink, scale)
		"assault_gun":
			canvas.draw_circle(glyph_center, 2.8 * scale, ink)
			canvas.draw_line(glyph_center + Vector2(1, -1) * scale, glyph_center + Vector2(9, -5) * scale, ink, maxf(1.0, 1.5 * scale), true)
		"machine_gun":
			_draw_machine_gun(canvas, glyph_center, ink, scale, equipment_weight)
		"mortar":
			canvas.draw_line(glyph_center + Vector2(-6, 5) * scale, glyph_center + Vector2(4, -5) * scale, ink, maxf(1.5, 2.0 * scale), true)
			canvas.draw_line(glyph_center + Vector2(-8, 5) * scale, glyph_center + Vector2(1, 5) * scale, ink, maxf(1.0, 1.5 * scale), true)
			canvas.draw_circle(glyph_center + Vector2(4, -5) * scale, 1.8 * scale, ink)
		"artillery":
			canvas.draw_circle(glyph_center, 3.2 * scale, ink)
		"engineer":
			_draw_engineer(canvas, glyph_center, ink, scale)
		"recon":
			canvas.draw_line(glyph_center + Vector2(-9, 5) * scale, glyph_center + Vector2(9, -5) * scale, ink, maxf(1.5, 2.0 * scale), true)
		"airborne":
			_draw_infantry(canvas, glyph_center, ink, scale)
			_draw_airborne(canvas, glyph_center, ink, scale)
		"air_defense":
			canvas.draw_arc(glyph_center + Vector2(0, 4) * scale, 8.0 * scale, PI, TAU, 18, ink, maxf(1.5, 2.0 * scale), true)
		"headquarters":
			_draw_centered_text(canvas, glyph_center + Vector2(0, 3) * scale, "HQ", font, ink, maxi(6, roundi(8.0 * scale)))
		_:
			_draw_centered_text(canvas, glyph_center + Vector2(0, 4) * scale, "?", font, ink, maxi(7, roundi(10.0 * scale)))

	if function != "machine_gun":
		_draw_weight_bar(canvas, glyph_center, equipment_weight, ink, scale)

static func _draw_machine_gun(canvas: CanvasItem, center: Vector2, ink: Color, scale: float, equipment_weight: String) -> void:
	var width := maxf(1.0, 1.4 * scale)
	if equipment_weight == "medium":
		width = maxf(1.6, 2.0 * scale)
	elif equipment_weight == "heavy":
		width = maxf(2.4, 3.0 * scale)
	var points := PackedVector2Array([
		center + Vector2(-8, 5) * scale,
		center + Vector2(0, -5) * scale,
		center + Vector2(8, 5) * scale
	])
	canvas.draw_polyline(points, ink, width, true)
	canvas.draw_line(center + Vector2(0, -5) * scale, center + Vector2(0, 5) * scale, ink, width, true)
	if equipment_weight == "heavy":
		canvas.draw_circle(center + Vector2(0, 5) * scale, 2.0 * scale, ink)

static func _draw_weight_bar(canvas: CanvasItem, center: Vector2, equipment_weight: String, ink: Color, scale: float) -> void:
	if equipment_weight not in ["medium", "heavy"]:
		return
	var width := maxf(1.2, 1.5 * scale) if equipment_weight == "medium" else maxf(2.8, 3.4 * scale)
	canvas.draw_line(center + Vector2(-7, 0) * scale, center + Vector2(7, 0) * scale, ink, width, true)

static func _draw_identity(canvas: CanvasItem, center: Vector2, identity: String, font: Font, ink: Color, scale: float, detail_scale: float) -> void:
	if detail_scale < IDENTITY_ZOOM_THRESHOLD or identity.strip_edges().is_empty():
		return
	var font_size := maxi(6, roundi(7.0 * scale))
	var fitted := _fit_text(font, identity.strip_edges(), 34.0 * scale, font_size)
	_draw_centered_text(canvas, center + Vector2(0, 9.5) * scale, fitted, font, ink, font_size)

static func _fit_text(font: Font, value: String, maximum_width: float, font_size: int) -> String:
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= maximum_width:
		return value
	var suffix := "…"
	var fitted := value
	while fitted.length() > 1:
		fitted = fitted.left(fitted.length() - 1)
		if font.get_string_size(fitted + suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= maximum_width:
			return fitted + suffix
	return suffix

static func _draw_infantry(canvas: CanvasItem, center: Vector2, ink: Color, scale: float) -> void:
	var width := maxf(1.0, 1.5 * scale)
	canvas.draw_line(center + Vector2(-9, -6) * scale, center + Vector2(9, 6) * scale, ink, width, true)
	canvas.draw_line(center + Vector2(9, -6) * scale, center + Vector2(-9, 6) * scale, ink, width, true)

static func _draw_engineer(canvas: CanvasItem, center: Vector2, ink: Color, scale: float) -> void:
	var width := maxf(1.0, 1.5 * scale)
	canvas.draw_line(center + Vector2(-5, -6) * scale, center + Vector2(-5, 6) * scale, ink, width, true)
	for y in [-6.0, 0.0, 6.0]:
		canvas.draw_line(center + Vector2(-5, y) * scale, center + Vector2(6, y) * scale, ink, width, true)

static func _draw_airborne(canvas: CanvasItem, center: Vector2, ink: Color, scale: float) -> void:
	var width := maxf(1.0, 1.2 * scale)
	canvas.draw_arc(center + Vector2(-5, 1) * scale, 4.0 * scale, PI, TAU, 8, ink, width, true)
	canvas.draw_arc(center + Vector2(5, 1) * scale, 4.0 * scale, PI, TAU, 8, ink, width, true)

static func _draw_ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, ink: Color, scale: float) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * scale)
	canvas.draw_polyline(points, ink, maxf(1.0, 1.5 * scale), true)

static func _draw_polyline(canvas: CanvasItem, center: Vector2, raw_points: Array[Vector2], ink: Color, scale: float) -> void:
	var points := PackedVector2Array()
	for point in raw_points:
		points.append(center + point * scale)
	canvas.draw_polyline(points, ink, maxf(1.0, 1.5 * scale), true)

static func _draw_echelon(canvas: CanvasItem, center: Vector2, echelon: Dictionary, ink: Color, scale: float) -> void:
	var kind := String(echelon.get("kind", "none"))
	var count := int(echelon.get("count", 0))
	if count <= 0 or kind == "none":
		return
	var spacing := 5.0 * scale
	var start_x := -float(count - 1) * spacing * 0.5
	for index in range(count):
		var mark_center := center + Vector2(start_x + float(index) * spacing, -16.0 * scale)
		match kind:
			"dot":
				canvas.draw_circle(mark_center, 1.5 * scale, ink)
			"bar":
				canvas.draw_line(mark_center + Vector2(0, -2.5) * scale, mark_center + Vector2(0, 2.5) * scale, ink, maxf(1.0, 1.5 * scale), true)
			"x":
				var delta := Vector2(1.8, 2.4) * scale
				canvas.draw_line(mark_center - delta, mark_center + delta, ink, maxf(1.0, 1.2 * scale), true)
				canvas.draw_line(mark_center + Vector2(delta.x, -delta.y), mark_center + Vector2(-delta.x, delta.y), ink, maxf(1.0, 1.2 * scale), true)

static func _draw_mobility(canvas: CanvasItem, center: Vector2, mobility: String, ink: Color, scale: float) -> void:
	if mobility != "tracked":
		return
	_draw_ellipse(canvas, center + Vector2(0, 15) * scale, Vector2(8.0, 2.3), ink, scale)

static func _draw_wheeled_mobility(canvas: CanvasItem, center: Vector2, ink: Color, scale: float) -> void:
	for x in [-7.0, 7.0]:
		canvas.draw_circle(center + Vector2(x, 15) * scale, 2.2 * scale, ink, false, maxf(1.0, 1.3 * scale), true)

static func _draw_stack_badge(canvas: CanvasItem, center: Vector2, count: int, font: Font, scale: float, alpha: float) -> void:
	var badge_center := center + Vector2(16, -7) * scale
	var badge_fill := STACK_BADGE_FILL
	badge_fill.a *= alpha
	var badge_text := STACK_BADGE_TEXT
	badge_text.a *= alpha
	canvas.draw_circle(badge_center, 5.5 * scale, badge_fill)
	_draw_centered_text(canvas, badge_center + Vector2(0, 3) * scale, str(count), font, badge_text, maxi(6, roundi(8.0 * scale)))

static func _draw_centered_text(canvas: CanvasItem, baseline_center: Vector2, value: String, font: Font, color: Color, font_size: int) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	canvas.draw_string(font, baseline_center - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

static func _function_for_type(broad_type: String) -> String:
	match broad_type:
		"infantry":
			return "infantry"
		"tank":
			return "armor"
		"mechanized":
			return "mechanized"
		"motorized":
			return "motorized"
		"anti_tank":
			return "anti_armor"
		"engineer":
			return "engineer"
		"artillery":
			return "artillery"
		"recon":
			return "recon"
		"airborne":
			return "airborne"
		"air_defense":
			return "air_defense"
		"headquarters":
			return "headquarters"
	return "unknown"

static func _identifier(raw_value: String) -> String:
	return raw_value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
