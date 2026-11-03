extends Node2D
# CITY FREEDOM MAKKAH - entirely new 2D engine, no legacy 3D scenes.
# Single CanvasItem renderer, deterministic map, no imported city geometry.
const CELL = 320.0
const ROAD = 84.0
const LIMIT = 5
const WALK_SPEED = 205.0
const DRIVE_SPEED = 590.0
var player = Vector2(0, 0)
var heading = Vector2(0, -1)
var driving = false
var car_index = -1
var cars = []
var walkers = []
var buildings = []
var rng = RandomNumberGenerator.new()
var camera = null
var hud = null
var fps_label = null
var show_map = false
var frame = 0
var selftest = false
var palette = [Color("#d9b88d"),Color("#d2aa7e"),Color("#e5c7a1"),Color("#bfa081"),Color("#edcf9d")]
func _ready():
	rng.seed = 1879
	selftest = "--selftest" in OS.get_cmdline_args()
	_build_city()
	_build_traffic()
	camera = Camera2D.new()
	camera.current = true
	camera.zoom = Vector2(1,1)
	add_child(camera)
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.add_color_override("font_color", Color(1,1,1))
	hud.rect_position = Vector2(18,14)
	layer.add_child(hud)
	fps_label = Label.new()
	fps_label.rect_position = Vector2(18,50)
	layer.add_child(fps_label)
	_update_hud()
	set_process(true)
	set_physics_process(true)
func _build_city():
	for gx in range(-LIMIT,LIMIT):
		for gy in range(-LIMIT,LIMIT):
			var x = gx * CELL + ROAD * 0.5 + 18.0
			var y = gy * CELL + ROAD * 0.5 + 18.0
			var w = CELL - ROAD - 36.0
			var h = CELL - ROAD - 36.0
			# A small number of buildings per block, with pedestrian lanes.
			for ix in range(2):
				for iy in range(2):
					var gap = 12.0
					var r = Rect2(x+ix*w*0.5+gap,y+iy*h*0.5+gap,w*0.5-2*gap,h*0.5-2*gap)
					buildings.append([r,palette[rng.randi_range(0,palette.size()-1)],rng.randi_range(0,2)])
func _build_traffic():
	for i in range(12):
		var lane = rng.randi_range(-LIMIT+1,LIMIT-1) * CELL
		var p = Vector2(rng.randf_range(-1300,1300),lane+(-19 if i%2==0 else 19))
		var v = Vector2(1 if i%2==0 else -1,0)
		cars.append({"pos":p,"dir":v,"speed":rng.randf_range(90,155),"color":Color("#fafafa") if i%3==0 else Color("#336e8a")})
	for i in range(16):
		var gx = rng.randi_range(-LIMIT+1,LIMIT-1)
		var gy = rng.randi_range(-LIMIT+1,LIMIT-1)
		walkers.append({"pos":Vector2(gx*CELL+55,gy*CELL+60),"phase":rng.randf()*6.28,"dir":Vector2(1,0) if i%2==0 else Vector2(0,1)})
func _axis(neg, pos, axis):
	var v = Input.get_joy_axis(0,axis) if Input.get_connected_joypads().size()>0 else 0.0
	if abs(v)<0.17: v=0.0
	return clamp(v + float(Input.is_key_pressed(pos))-float(Input.is_key_pressed(neg)),-1.0,1.0)
func _physics_process(delta):
	frame += 1
	if selftest and frame>240:
		get_tree().quit()
	var inp = Vector2(_axis(KEY_A,KEY_D,0),_axis(KEY_W,KEY_S,1))
	# TV D-pad and keyboard arrows.
	inp.x += float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT))
	inp.y += float(Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_UP))
	inp.x += float(Input.is_joy_button_pressed(0,15))-float(Input.is_joy_button_pressed(0,14))
	inp.y += float(Input.is_joy_button_pressed(0,13))-float(Input.is_joy_button_pressed(0,12))
	inp = inp.clamped(1.0)
	if inp.length_squared()>0.01:
		heading = inp.normalized()
		var next_pos = player + heading * (DRIVE_SPEED if driving else WALK_SPEED)*delta
		if not _blocked(next_pos,driving):
			player=next_pos
	if driving and car_index>=0:
		cars[car_index]["pos"]=player
		cars[car_index]["dir"]=heading
	for i in range(cars.size()):
		if i==car_index: continue
		var c=cars[i]
		c["pos"] += c["dir"]*c["speed"]*delta
		if c["pos"].x>LIMIT*CELL: c["pos"].x=-LIMIT*CELL
		if c["pos"].x< -LIMIT*CELL: c["pos"].x=LIMIT*CELL
		cars[i]=c
	for i in range(walkers.size()):
		var p=walkers[i]
		p["phase"]+=delta*2.0
		var target=p["pos"]+p["dir"]*delta*42.0
		if not _blocked(target,false): p["pos"]=target
		else: p["dir"]=-p["dir"]
		walkers[i]=p
	camera.position=player
	update()
	if frame%20==0: _update_hud()
func _blocked(p,vehicle):
	if abs(p.x)>LIMIT*CELL+120 or abs(p.y)>LIMIT*CELL+120: return true
	for item in buildings:
		var r = item[0].grow(16 if vehicle else 9)
		if r.has_point(p): return true
	return false
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode==KEY_E or event.scancode==KEY_ENTER or event.scancode==KEY_SPACE: _toggle_car()
		if event.scancode==KEY_M: show_map=!show_map
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index==0 or event.button_index==1: _toggle_car()
		if event.button_index==3: show_map=!show_map
func _toggle_car():
	if driving:
		driving=false
		car_index=-1
	else:
		var closest=100.0
		for i in range(cars.size()):
			var d=player.distance_to(cars[i]["pos"])
			if d<closest:
				closest=d
				car_index=i
		if car_index>=0:
			driving=true
			player=cars[car_index]["pos"]
	_update_hud()
func _update_hud():
	hud.text="CITY FREEDOM  |  MAKKAH    %s   [A: ENTER / EXIT]   [Y: MAP]" % ("DRIVING" if driving else "WALKING")
	fps_label.text="FPS: %d   |   NEW LIGHTWEIGHT 2D CITY   |   Left stick / D-pad to move" % Engine.get_frames_per_second()
func _draw():
	var extent = LIMIT*CELL
	draw_rect(Rect2(-extent-200,-extent-200,2*extent+400,2*extent+400),Color("#d7c9a2"))
	# Roads: batched 2D primitives, no 3D mesh or physics world.
	for n in range(-LIMIT,LIMIT+1):
		var v=n*CELL
		draw_rect(Rect2(v-ROAD*0.5,-extent-200,ROAD,2*extent+400),Color("#515963"))
		draw_rect(Rect2(-extent-200,v-ROAD*0.5,2*extent+400,ROAD),Color("#515963"))
		for t in range(-LIMIT*2,LIMIT*2):
			var q=t*160.0
			draw_rect(Rect2(v-1.5,q+40,3,55),Color("#ead8a0"))
			draw_rect(Rect2(q+40,v-1.5,55,3),Color("#ead8a0"))
	for b in buildings:
		var r=b[0]
		if r.get_center().distance_squared_to(player)>850*850: continue
		draw_rect(r,Color("#947c61"))
		draw_rect(Rect2(r.position+Vector2(0,-6),r.size-Vector2(6,6)),b[1])
		draw_rect(Rect2(r.position+Vector2(12,12),Vector2(18,12)),Color("#608b9d"))
		if b[2]==1:
			draw_rect(Rect2(r.position+Vector2(32,10),Vector2(28,12)),Color("#eee4ce"))
	for w in walkers:
		if w["pos"].distance_squared_to(player)<750*750:
			draw_circle(w["pos"],9,Color("#f1ddba"))
			draw_circle(w["pos"]+Vector2(0,-4),5,Color("#ffffff"))
	for i in range(cars.size()):
		var c=cars[i]
		if c["pos"].distance_squared_to(player)>800*800: continue
		var p=c["pos"]
		var rot=c["dir"].angle()
		draw_set_transform(p,rot)
		draw_rect(Rect2(-23,-12,46,24),Color("#151b22"))
		draw_rect(Rect2(-19,-10,38,20),c["color"])
		draw_rect(Rect2(-6,-8,14,16),Color("#83b6c7"))
		draw_set_transform(Vector2.ZERO,0)
	if not driving:
		draw_circle(player,14,Color("#f8f8ed"))
		draw_circle(player+heading*8,6,Color("#e4ae75"))
		draw_line(player,player+heading*20,Color("#1b554a"),4)
	if show_map:
		draw_rect(Rect2(player-Vector2(150,110),Vector2(300,220)),Color(0.1,0.18,0.2,0.85))
		draw_circle(player,7,Color("#ffe45c"))
