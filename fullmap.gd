extends Control
const MapData := preload("res://map_data.gd")
var tex: Texture2D
var player_xy := Vector2.ZERO
var heading := 0.0

func _ready() -> void:
	if ResourceLoader.exists("res://map/makkah_map.jpg"):
		tex = load("res://map/makkah_map.jpg")

func to_panel(g: Vector2) -> Vector2:
	var px := g / MapData.MAP_SCALE + MapData.MAP_CENTER_PX
	return px / MapData.MAP_SIZE_PX * size

func _draw() -> void:
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.14), true)
	for road in MapData.ROADS:
		var pts: Array = road[1]
		var w: float = road[0]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			draw_line(to_panel(a), to_panel(b), Color(1.0, 0.25, 0.9, 0.55), 2.0 if w >= 11.0 else 1.3, true)
	var p := to_panel(player_xy)
	var f := Vector2(-sin(heading), -cos(heading))
	var r := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([p + f * 12.0, p + r * 7.0 - f * 8.0, p - r * 7.0 - f * 8.0]), Color(0.2, 1.0, 0.4))
	draw_arc(p, 14.0, 0.0, TAU, 20, Color.WHITE, 2.0, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.85, 0.55), false, 3.0)
