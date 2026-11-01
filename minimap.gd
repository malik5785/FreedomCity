extends Control
var roads := []
var road_cells := {}
var player_xy := Vector2.ZERO
var zoom := 0.7

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.025, 0.045, 0.065, 0.87), true)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.9, 0.8, 0.55, 0.8), false, 2.0)
	var center := rect_size * 0.5
	var cx := int(floor(player_xy.x / 100.0))
	var cz := int(floor(player_xy.y / 100.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var key := "%d_%d" % [cx + dx, cz + dz]
			if not road_cells.has(key):
				continue
			for idx in road_cells[key]:
				var seg: Array = roads[idx]
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[1]
				var pa := center + (a - player_xy) * zoom
				var pb := center + (b - player_xy) * zoom
				draw_line(pa, pb, Color(0.55, 0.58, 0.60), max(1.5, float(seg[2]) * 0.25), true)
	draw_circle(center, 5.0, Color(1.0, 0.78, 0.17))
	draw_arc(center, 8.0, 0.0, TAU, 24, Color(1, 1, 1), 2.0, true)
