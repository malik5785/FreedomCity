extends Spatial
# City Freedom Makkah - fresh low-poly 3D engine for GLES2 Android TV.
const BLOCK = 140.0
const ROAD = 26.0
const WORLD = 3
const VIEW = 260.0
const WALK = 16.0
const DRIVE = 55.0
var avatar: Spatial
var vehicle: Spatial
var camera: Camera
var road_mesh: MultiMeshInstance
var house_mesh: MultiMeshInstance
var traffic = []
var citizens = []
var driving = false
var yaw = 0.0
var frame = 0
var selftest = false
var rng = RandomNumberGenerator.new()
var ui: Label
var last_toggle = false
var blocks = []
var collision_boxes = []
var arm_left: Spatial
var arm_right: Spatial
var leg_left: Spatial
var leg_right: Spatial
var clock_time = 9.0
var wardrobe = false
var map_visible = false
var day_light: DirectionalLight
var world_env: WorldEnvironment
var clothes_index = 0
var display_map: Label
var info: Label
var active_car = -1
var car_specs = []
var player_speed = 0.0
var turn_angle = 0.0
var horn_frames = 0
var collision_objects = []
var landmarks = []
var material_cache = {}
var road_names = ["العزيزية  Al Aziziyah", "العـدل  Al Adl", "المسفلة  Al Misfalah", "الشوقية  Al Shawqiyah"]
func _ready():
	rng.seed = 20261103
	selftest = "--selftest" in OS.get_cmdline_args()
	_setup_world()
	_make_city()
	_make_player()
	_make_traffic()
	_make_landmarks()
	_make_streetscape()
	_make_ui()
	set_physics_process(true)
func _mat(c):
	var key = c.to_html()
	if material_cache.has(key): return material_cache[key]
	var m = SpatialMaterial.new()
	m.albedo_color = c
	m.flags_unshaded = true
	material_cache[key] = m
	return m
func _cube(parent, pos, size, color):
	var mi = MeshInstance.new()
	var mesh = CubeMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.translation = pos
	parent.add_child(mi)
	return mi
func _setup_world():
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8fc2dc")
	e.ambient_light_color = Color("#eeeeee")
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	world_env=env
	var light = DirectionalLight.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_energy = 0.65
	light.shadow_enabled = false
	add_child(light)
	day_light=light
	var ground = _cube(self,Vector3(0,-0.5,0),Vector3(1100,1,1100),Color("#cbb68c"))
	ground.name="Sand"
func _make_city():
	var roads = []
	var houses = []
	for n in range(-WORLD,WORLD+1):
		roads.append(Transform(Basis(),Vector3(n*BLOCK,0.02,0)))
		roads.append(Transform(Basis().rotated(Vector3.UP,PI/2),Vector3(0,0.02,n*BLOCK)))
	for gx in range(-WORLD,WORLD):
		for gz in range(-WORLD,WORLD):
			var cx = (gx+0.5)*BLOCK
			var cz = (gz+0.5)*BLOCK
			var pos = Vector3(cx,0,cz)
			var h = rng.randf_range(16,34)
			houses.append(Transform(Basis().scaled(Vector3(35,h,38)),pos+Vector3(-24,h*0.5,-22)))
			h = rng.randf_range(14,30)
			houses.append(Transform(Basis().scaled(Vector3(30,h,35)),pos+Vector3(23,h*0.5,-22)))
			h = rng.randf_range(18,37)
			houses.append(Transform(Basis().scaled(Vector3(35,h,30)),pos+Vector3(-20,h*0.5,24)))
			h = rng.randf_range(15,29)
			houses.append(Transform(Basis().scaled(Vector3(32,h,30)),pos+Vector3(24,h*0.5,23)))
			blocks.append([Vector2(cx,cz),h])
			collision_boxes.append(Rect2(cx-44,cz-42,39,40))
			collision_boxes.append(Rect2(cx+8,cz-42,32,37))
			collision_boxes.append(Rect2(cx-39,cz+9,37,32))
			collision_boxes.append(Rect2(cx+8,cz+8,34,33))
	var road = CubeMesh.new()
	road.size=Vector3(ROAD,0.1,1600)
	var mm=MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.instance_count=roads.size()
	for i in range(roads.size()):
		mm.set_instance_transform(i,roads[i])
	road_mesh=MultiMeshInstance.new()
	road_mesh.multimesh=mm
	road_mesh.multimesh.mesh=road
	road_mesh.material_override=_mat(Color("#444a50"))
	add_child(road_mesh)
	var box=CubeMesh.new()
	box.size=Vector3.ONE
	var hm=MultiMesh.new()
	hm.transform_format=MultiMesh.TRANSFORM_3D
	hm.instance_count=houses.size()
	for i in range(houses.size()):
		hm.set_instance_transform(i,houses[i])
	house_mesh=MultiMeshInstance.new()
	house_mesh.multimesh=hm
	house_mesh.multimesh.mesh=box
	house_mesh.material_override=_mat(Color("#d9b994"))
	add_child(house_mesh)
	# Draw lane stripes as a single MultiMesh.
	var stripes=[]
	for n in range(-WORLD,WORLD+1):
		for j in range(-18,19):
			stripes.append(Transform(Basis().scaled(Vector3(0.5,0.06,8)),Vector3(n*BLOCK,0.13,j*18)))
			stripes.append(Transform(Basis().scaled(Vector3(8,0.06,0.5)),Vector3(j*18,0.13,n*BLOCK)))
	var stripe=MultiMesh.new()
	stripe.transform_format=MultiMesh.TRANSFORM_3D
	stripe.instance_count=stripes.size()
	for i in range(stripes.size()):
		stripe.set_instance_transform(i,stripes[i])
	var sm=MultiMeshInstance.new()
	sm.multimesh=stripe
	sm.multimesh.mesh=box
	sm.material_override=_mat(Color("#e9d59c"))
	add_child(sm)
func _make_player():
	avatar=Spatial.new()
	add_child(avatar)
	_cube(avatar,Vector3(0,1.25,0),Vector3(0.9,2.1,0.65),Color("#f4f2e9"))
	_cube(avatar,Vector3(0,2.65,0),Vector3(0.75,0.75,0.7),Color("#d6a06c"))
	_cube(avatar,Vector3(0,3.08,0),Vector3(0.8,0.18,0.8),Color("#ffffff"))
	_cube(avatar,Vector3(-0.3,0.28,0),Vector3(0.25,0.55,0.3),Color("#333333"))
	_cube(avatar,Vector3(0.3,0.28,0),Vector3(0.25,0.55,0.3),Color("#333333"))
	arm_left=Spatial.new()
	arm_right=Spatial.new()
	leg_left=Spatial.new()
	leg_right=Spatial.new()
	avatar.add_child(arm_left)
	avatar.add_child(arm_right)
	avatar.add_child(leg_left)
	avatar.add_child(leg_right)
	arm_left.translation=Vector3(-0.62,2.05,0)
	arm_right.translation=Vector3(0.62,2.05,0)
	leg_left.translation=Vector3(-0.22,0.75,0)
	leg_right.translation=Vector3(0.22,0.75,0)
	_cube(arm_left,Vector3(0,-0.5,0),Vector3(0.32,1.05,0.38),Color("#f4f2e9"))
	_cube(arm_right,Vector3(0,-0.5,0),Vector3(0.32,1.05,0.38),Color("#f4f2e9"))
	_cube(leg_left,Vector3(0,-0.36,0),Vector3(0.3,0.7,0.36),Color("#f4f2e9"))
	_cube(leg_right,Vector3(0,-0.36,0),Vector3(0.3,0.7,0.36),Color("#f4f2e9"))
	_cube(avatar,Vector3(-0.2,2.72,-0.36),Vector3(0.12,0.1,0.05),Color("#2d251d"))
	_cube(avatar,Vector3(0.2,2.72,-0.36),Vector3(0.12,0.1,0.05),Color("#2d251d"))
	vehicle=Spatial.new()
	add_child(vehicle)
	_cube(vehicle,Vector3(0,0.75,0),Vector3(2.3,0.85,4.4),Color("#f4f4ef"))
	_cube(vehicle,Vector3(0,1.48,-0.3),Vector3(1.9,0.85,2.1),Color("#5e9cac"))
	for x in [-1.05,1.05]:
		for z in [-1.45,1.45]:
			_cube(vehicle,Vector3(x,0.45,z),Vector3(0.4,0.8,0.9),Color("#22262c"))
	vehicle.visible=false
	camera=Camera.new()
	camera.current=true
	camera.far=220
	camera.fov=67
	add_child(camera)
	_update_camera()
func _make_traffic():
	for i in range(18):
		var root=Spatial.new()
		add_child(root)
		var axis=i%2
		var lane=rng.randi_range(-WORLD+1,WORLD-1)*BLOCK
		var p=Vector3(rng.randf_range(-360,360),0,lane+(-7 if i%2==0 else 7))
		if axis==1: p=Vector3(lane+7,0,rng.randf_range(-600,600))
		if i==0: p=Vector3(5,0,4)
		root.translation=p
		var car_colors=[Color("#f1f0e9"),Color("#222d3c"),Color("#a6b4b7"),Color("#8a3b35"),Color("#c7c3b6"),Color("#1d6583"),Color("#d5ad60"),Color("#3b3d3c"),Color("#7d8a70"),Color("#e8e5df")]
		var typ=i%9
		var size=Vector3(2.2,1.0,4.0)
		if typ==1 or typ==4: size=Vector3(2.7,1.5,4.9)
		if typ==5 or typ==6: size=Vector3(3.2,2.5,7.4)
		if typ==2: size=Vector3(2.0,0.9,3.3)
		_cube(root,Vector3(0,0.7,0),size,car_colors[i%10])
		_cube(root,Vector3(0,1.55,0),Vector3(size.x*0.82,0.65,size.z*0.52),Color("#8cbac4"))
		for wx in [-1,1]:
			for wz in [-1,1]:
				_cube(root,Vector3(wx*size.x*0.49,0.4,wz*size.z*0.32),Vector3(0.3,0.7,0.75),Color("#222428"))
		if typ==8:
			_cube(root,Vector3(0,2.05,0),Vector3(0.9,0.15,0.4),Color("#e33a36"))
		traffic.append([root,axis,1 if i%2==0 else -1,rng.randf_range(12,23)])
		car_specs.append([i%9,i%10])
	for i in range(8):
		var root=Spatial.new()
		add_child(root)
		_cube(root,Vector3(0,0.95,0),Vector3(0.65,1.8,0.6),Color("#f7f3e8") if i%3!=0 else Color("#282d36"))
		_cube(root,Vector3(0,2.1,0),Vector3(0.55,0.55,0.55),Color("#c8996c"))
		_cube(root,Vector3(0,2.5,0),Vector3(0.68,0.18,0.65),Color("#f7f4ea") if i%2==0 else Color("#222b35"))
		for arm in [-1,1]:
			_cube(root,Vector3(arm*0.43,1.35,0),Vector3(0.2,1.0,0.25),Color("#f7f3e8") if i%3!=0 else Color("#282d36"))
		root.translation=Vector3(rng.randi_range(-2,2)*BLOCK+18,0,rng.randi_range(-4,4)*BLOCK+24)
		citizens.append([root,Vector3(1 if i%2==0 else -1,0,0)])
func _make_ui():
	var layer=CanvasLayer.new()
	add_child(layer)
	ui=Label.new()
	ui.rect_position=Vector2(20,16)
	ui.add_color_override("font_color",Color("#ffffff"))
	layer.add_child(ui)
	ui.text="CITY FREEDOM | MAKKAH 3D    Left stick: move    A: drive / exit"
	info=Label.new()
	info.rect_position=Vector2(20,42)
	layer.add_child(info)
	info.text="B: Clothes    Y: Map    X: Horn    Back: Resume"
	display_map=Label.new()
	display_map.rect_position=Vector2(20,70)
	layer.add_child(display_map)
func _axis(neg,pos,index):
	var v=Input.get_joy_axis(0,index) if Input.get_connected_joypads().size()>0 else 0.0
	if abs(v)<0.18: v=0.0
	return clamp(v+float(Input.is_key_pressed(pos))-float(Input.is_key_pressed(neg)),-1,1)
func _physics_process(delta):
	frame+=1
	if selftest and frame>240: get_tree().quit()
	var input=Vector2(_axis(KEY_A,KEY_D,0),_axis(KEY_W,KEY_S,1))
	var remote_turn=float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT))
	var remote_forward=float(Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_UP))
	if abs(remote_forward)>0.01 or abs(remote_turn)>0.01:
		yaw+=remote_turn*delta*2.4
		input=Vector2(sin(yaw)*remote_forward,cos(yaw)*remote_forward)
	var dpad_turn=float(Input.is_joy_button_pressed(0,15))-float(Input.is_joy_button_pressed(0,14))
	var dpad_forward=float(Input.is_joy_button_pressed(0,13))-float(Input.is_joy_button_pressed(0,12))
	if abs(dpad_forward)>0.01 or abs(dpad_turn)>0.01:
		yaw+=dpad_turn*delta*2.4
		input=Vector2(sin(yaw)*dpad_forward,cos(yaw)*dpad_forward)
	input=input.clamped(1)
	if input.length_squared()>0.01:
		var direction=Vector3(input.x,0,input.y).normalized()
		if abs(remote_forward)<0.01 and abs(dpad_forward)<0.01: yaw=atan2(direction.x,direction.z)
		var next=avatar.translation+direction*(DRIVE if driving else WALK)*delta
		if abs(next.x)<410 and abs(next.z)<410 and not _hits_building(next) and not _hits_obstacle(next):
			player_speed=next.distance_to(avatar.translation)/max(delta,0.001)
			avatar.translation=next
			vehicle.translation=next
			if driving and active_car>=0:
				traffic[active_car][0].translation=next
				traffic[active_car][0].rotation.y=yaw
	else:
		player_speed=0.0
	var swing=sin(frame*0.23)*0.42 if input.length_squared()>0.01 else 0.0
	arm_left.rotation.x=swing
	arm_right.rotation.x=-swing
	leg_left.rotation.x=-swing
	leg_right.rotation.x=swing
	avatar.rotation.y=yaw
	vehicle.rotation.y=yaw
	for t in traffic:
		if driving and active_car>=0 and t[0]==traffic[active_car][0]: continue
		var p=t[0].translation
		if t[1]==0: p.x+=t[2]*t[3]*delta
		else: p.z+=t[2]*t[3]*delta
		if p.x>400: p.x=-400
		if p.x< -400: p.x=400
		if p.z>400: p.z=-400
		if p.z< -400: p.z=400
		var near_player=p.distance_to(avatar.translation)<5.5
		var near_ped=false
		for c in citizens:
			if p.distance_to(c[0].translation)<4.0: near_ped=true
		if not near_player and not near_ped: t[0].translation=p
	for c in citizens:
		var p=c[0].translation+c[1]*delta*2.5
		if abs(p.x)>350: c[1]=-c[1]
		else: c[0].translation=p
	_update_camera()
	if frame%30==0:
		clock_time=fmod(clock_time+0.012,24.0)
		var daylight=clock_time>6.0 and clock_time<18.5
		world_env.environment.background_color=Color("#8fc2dc") if daylight else Color("#1a2540")
		day_light.light_energy=0.65 if daylight else 0.12
		display_map.text=("MAP  " + str(avatar.translation.x).pad_decimals(0) + " / " + str(avatar.translation.z).pad_decimals(0) + "   AL ADL - MAKKAH") if map_visible else ("CLOTHES  " + str(clothes_index+1) + " / 4  [B TO CHANGE]") if wardrobe else ""
		ui.text="CITY FREEDOM | MAKKAH 3D    %s    FPS: %d    [OK] CAR  [B] CLOTHES  [Y] MAP" % ["DRIVING" if driving else "WALKING",Engine.get_frames_per_second()]
func _update_camera():
	var target=avatar.translation
	camera.translation=target+Vector3(0,5.7,14.0)
	camera.look_at(target+Vector3(0,1.8,0),Vector3.UP)
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode==KEY_ENTER or event.scancode==KEY_SPACE or event.scancode==KEY_E:
			_toggle_drive()
		if event.scancode==KEY_B: _change_clothes()
		if event.scancode==KEY_H: horn_frames=20
		if event.scancode==KEY_M: map_visible=!map_visible
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index==0: _toggle_drive()
		if event.button_index==1: _change_clothes()
		if event.button_index==3: map_visible=!map_visible
		if event.button_index==2: horn_frames=20
func _toggle_drive():
	if driving:
		driving=false
		active_car=-1
		avatar.visible=true
		vehicle.visible=false
		return
	var nearest=12.0
	var choice=-1
	for i in range(traffic.size()):
		var d=traffic[i][0].translation.distance_to(avatar.translation)
		if d<nearest:
			nearest=d
			choice=i
	if choice<0: return
	active_car=choice
	driving=true
	avatar.translation=traffic[choice][0].translation
	vehicle.visible=false
	avatar.visible=false

func _hits_building(p):
	var q=Vector2(p.x,p.z)
	for rect in collision_boxes:
		if rect.grow(1.4 if driving else 0.4).has_point(q): return true
	return false
func _change_clothes():
	wardrobe=true
	clothes_index=(clothes_index+1)%4
	var colors=[Color("#f4f2e9"),Color("#c7b48e"),Color("#353d4a"),Color("#e5d6bd")]
	for child in avatar.get_children():
		if child is MeshInstance and child.translation.y>0.8 and child.translation.y<2.5:
			child.material_override=_mat(colors[clothes_index])
func _make_landmarks():
	# Lightweight 3D Makkah-inspired landmarks, all meshes generated at runtime.
	var tower=Spatial.new()
	tower.translation=Vector3(-235,0,-255)
	add_child(tower)
	_cube(tower,Vector3(0,52,0),Vector3(32,104,32),Color("#b9a68a"))
	_cube(tower,Vector3(0,110,0),Vector3(36,16,36),Color("#d8c8a0"))
	_cube(tower,Vector3(0,122,0),Vector3(24,12,24),Color("#365a61"))
	_cube(tower,Vector3(0,135,0),Vector3(3,20,3),Color("#d6bc65"))
	for side in [-1,1]:
		_cube(tower,Vector3(0,110,side*18.1),Vector3(18,13,0.3),Color("#f0ead6"))
	var haram=Spatial.new()
	haram.translation=Vector3(225,0,-235)
	add_child(haram)
	_cube(haram,Vector3(0,2,0),Vector3(64,4,58),Color("#e9e1ce"))
	for x in [-25,25]:
		for z in [-21,21]:
			_cube(haram,Vector3(x,21,z),Vector3(5,38,5),Color("#eee6d4"))
			_cube(haram,Vector3(x,41,z),Vector3(7,3,7),Color("#b8aa8b"))
	# Mountain silhouettes in the distance; not expensive terrain geometry.
	for i in range(8):
		var mountain=Spatial.new()
		add_child(mountain)
		var angle=float(i)*TAU/16.0
		mountain.translation=Vector3(sin(angle)*480,0,cos(angle)*480)
		_cube(mountain,Vector3(0,45,0),Vector3(rng.randf_range(45,85),90,rng.randf_range(40,70)),Color("#8b816c"))

func _hits_obstacle(p):
	var q=Vector2(p.x,p.z)
	for obj in collision_objects:
		if q.distance_squared_to(obj[0])<pow(obj[1]+(1.4 if driving else 0.5),2): return true
	return false
func _make_streetscape():
	# Street furniture is fixed in world coordinates and checked with cheap 2D circles.
	for gx in range(-WORLD,WORLD):
		for gz in range(-WORLD,WORLD):
			var x=(gx+0.5)*BLOCK
			var z=(gz+0.5)*BLOCK
			var lamp=Spatial.new()
			lamp.translation=Vector3(x-54,0,z-54)
			add_child(lamp)
			_cube(lamp,Vector3(0,5,0),Vector3(0.35,10,0.35),Color("#4b5558"))
			_cube(lamp,Vector3(0,10,0),Vector3(2.0,0.45,1.0),Color("#f7e8af"))
			collision_objects.append([Vector2(lamp.translation.x,lamp.translation.z),0.8])
			if (gx+gz)%2==0:
				var palm=Spatial.new()
				palm.translation=Vector3(x+53,0,z-53)
				add_child(palm)
				_cube(palm,Vector3(0,5,0),Vector3(1.1,10,1.1),Color("#8e6947"))
				for n in range(4):
					var leaf=_cube(palm,Vector3(0,10.8,0),Vector3(1.0,0.6,9),Color("#49744a"))
					leaf.rotation.y=float(n)*PI/4.0
				collision_objects.append([Vector2(palm.translation.x,palm.translation.z),1.3])
			var street_sign=Spatial.new()
			street_sign.translation=Vector3(x-54,0,z+53)
			add_child(street_sign)
			_cube(street_sign,Vector3(0,3,0),Vector3(0.25,6,0.25),Color("#555c59"))
			_cube(street_sign,Vector3(0,6,0),Vector3(7,2.1,0.35),Color("#237153"))
			collision_objects.append([Vector2(street_sign.translation.x,street_sign.translation.z),0.7])
