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
func _ready():
	rng.seed = 20261103
	selftest = "--selftest" in OS.get_cmdline_args()
	_setup_world()
	_make_city()
	_make_player()
	_make_traffic()
	_make_ui()
	set_physics_process(true)
func _mat(c):
	var m = SpatialMaterial.new()
	m.albedo_color = c
	m.flags_unshaded = true
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
	var light = DirectionalLight.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_energy = 0.65
	light.shadow_enabled = false
	add_child(light)
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
		for j in range(-22,23):
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
	camera.far=245
	camera.fov=67
	add_child(camera)
	_update_camera()
func _make_traffic():
	for i in range(5):
		var root=Spatial.new()
		add_child(root)
		var axis=i%2
		var lane=rng.randi_range(-WORLD+1,WORLD-1)*BLOCK
		var p=Vector3(rng.randf_range(-600,600),0,lane+(-7 if i%2==0 else 7))
		if axis==1: p=Vector3(lane+7,0,rng.randf_range(-600,600))
		root.translation=p
		_cube(root,Vector3(0,0.7,0),Vector3(2.2,1.2,4.0),Color("#5a829a") if i%3==0 else Color("#d9d6cb"))
		_cube(root,Vector3(0,1.55,0),Vector3(1.8,0.7,2.1),Color("#8cbac4"))
		traffic.append([root,axis,1 if i%2==0 else -1,rng.randf_range(12,23)])
	for i in range(5):
		var root=Spatial.new()
		add_child(root)
		_cube(root,Vector3(0,0.95,0),Vector3(0.65,1.8,0.6),Color("#f7f3e8"))
		_cube(root,Vector3(0,2.1,0),Vector3(0.55,0.55,0.55),Color("#c8996c"))
		root.translation=Vector3(rng.randi_range(-4,4)*BLOCK+18,0,rng.randi_range(-4,4)*BLOCK+24)
		citizens.append([root,Vector3(1 if i%2==0 else -1,0,0)])
func _make_ui():
	var layer=CanvasLayer.new()
	add_child(layer)
	ui=Label.new()
	ui.rect_position=Vector2(20,16)
	ui.add_color_override("font_color",Color("#ffffff"))
	layer.add_child(ui)
	ui.text="CITY FREEDOM | MAKKAH 3D    Left stick: move    A: drive / exit"
func _axis(neg,pos,index):
	var v=Input.get_joy_axis(0,index) if Input.get_connected_joypads().size()>0 else 0.0
	if abs(v)<0.18: v=0.0
	return clamp(v+float(Input.is_key_pressed(pos))-float(Input.is_key_pressed(neg)),-1,1)
func _physics_process(delta):
	frame+=1
	if selftest and frame>240: get_tree().quit()
	var input=Vector2(_axis(KEY_A,KEY_D,0),_axis(KEY_W,KEY_S,1))
	input.x+=float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT))
	input.y+=float(Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_UP))
	input.x+=float(Input.is_joy_button_pressed(0,15))-float(Input.is_joy_button_pressed(0,14))
	input.y+=float(Input.is_joy_button_pressed(0,13))-float(Input.is_joy_button_pressed(0,12))
	input=input.clamped(1)
	if input.length_squared()>0.01:
		var direction=Vector3(input.x,0,input.y).normalized()
		yaw=atan2(direction.x,direction.z)
		var next=avatar.translation+direction*(DRIVE if driving else WALK)*delta
		if abs(next.x)<410 and abs(next.z)<410:
			avatar.translation=next
			vehicle.translation=next
	avatar.rotation.y=yaw
	vehicle.rotation.y=yaw
	for t in traffic:
		var p=t[0].translation
		if t[1]==0: p.x+=t[2]*t[3]*delta
		else: p.z+=t[2]*t[3]*delta
		if p.x>400: p.x=-400
		if p.x< -400: p.x=400
		if p.z>400: p.z=-400
		if p.z< -400: p.z=400
		t[0].translation=p
	for c in citizens:
		var p=c[0].translation+c[1]*delta*2.5
		if abs(p.x)>350: c[1]=-c[1]
		else: c[0].translation=p
	_update_camera()
	if frame%30==0:
		ui.text="CITY FREEDOM | MAKKAH 3D    %s    FPS: %d    [A] Drive / Walk" % ["DRIVING" if driving else "WALKING",Engine.get_frames_per_second()]
func _update_camera():
	var target=avatar.translation
	camera.translation=target+Vector3(0,10,17)
	camera.look_at(target+Vector3(0,1.8,0),Vector3.UP)
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode==KEY_ENTER or event.scancode==KEY_SPACE or event.scancode==KEY_E:
			_toggle_drive()
	if event is InputEventJoypadButton and event.pressed and (event.button_index==0 or event.button_index==1):
		_toggle_drive()
func _toggle_drive():
	driving=!driving
	avatar.visible=!driving
	vehicle.visible=driving
