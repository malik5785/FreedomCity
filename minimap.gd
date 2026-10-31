extends Control
var roads: Array = []
var player_xy := Vector2.ZERO
func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.045,0.065,0.87),true)
 draw_rect(Rect2(Vector2.ZERO,size),Color(0.9,0.8,0.55,0.8),false,2.0)
 var center := size * 0.5
 for seg in roads:
  var a: Vector2 = seg[0]
  var b: Vector2 = seg[1]
  var pa := center + (a-player_xy) * 1.0
  var pb := center + (b-player_xy) * 1.0
  draw_line(pa,pb,Color(0.48,0.52,0.54),maxf(2.0,float(seg[2])*0.36),true)
 draw_circle(center,6.0,Color(1.0,0.78,0.17))
 draw_arc(center,9.0,0.0,TAU,24,Color.WHITE,2.0,true)
