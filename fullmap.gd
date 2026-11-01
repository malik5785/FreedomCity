extends Control
var lines := []
var world_min := Vector2.ZERO
var world_max := Vector2.ONE
var player_xy := Vector2.ZERO
var heading := 0.0

func _scale() -> float:
	return min(rect_size.x / (world_max.x - world_min.x), rect_size.y / (world_max.y - world_min.y))

func to_panel(g: Vector2) -> Vector2:
	var sc := _scale()
	var off := (rect_size - (world_max - world_min) * sc) * 0.5
	return (g - world_min) * sc + off

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.07, 0.09, 0.11), true)
	for ln in lines:
		var cls: int = ln[0]
		var pts: Array = ln[1]
		var col := Color(0.75, 0.78, 0.8)
		var wd := 1.0
		if cls == 0:
			col = Color(1.0, 0.6, 0.25)
			wd = 2.4
		elif cls == 1:
			col = Color(1.0, 0.85, 0.3)
			wd = 1.8
		elif cls == 2:
			col = Color(0.95, 0.95, 0.85)
			wd = 1.4
		var poly := PoolVector2Array()
		for p in pts:
			poly.append(to_panel(p))
		if poly.size() >= 2:
			draw_polyline(poly, col, wd, true)
	var kaaba := to_panel(Vector2.ZERO)
	draw_rect(Rect2(kaaba - Vector2(3, 3), Vector2(6, 6)), Color(0, 0, 0), true)
	draw_rect(Rect2(kaaba - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.85, 0.3), false, 1.5)
	var p2 := to_panel(player_xy)
	var f := Vector2(-sin(heading), -cos(heading))
	var r := Vector2(-f.y, f.x)
	draw_colored_polygon(PoolVector2Array([p2 + f * 11.0, p2 + r * 6.0 - f * 7.0, p2 - r * 6.0 - f * 7.0]), Color(0.2, 1.0, 0.4))
	draw_arc(p2, 13.0, 0.0, TAU, 20, Color(1, 1, 1), 2.0, true)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.95, 0.85, 0.55), false, 3.0)
