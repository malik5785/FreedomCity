extends Node3D
# City Freedom: compact, original offline prototype. No Google Maps tiles or proprietary assets.
const WORLD := 240.0
const ROAD_STEP := 40.0
var player: CharacterBody3D
var car: CharacterBody3D
var camera: Camera3D
var npc_list: Array[CharacterBody3D] = []
var npc_targets: Array[Vector3] = []
var driving := false
var first_person := false
var yaw := 0.0
var pitch := -0.18
var car_heading := 0.0
var speed := 0.0
var hud: Label
var rng := RandomNumberGenerator.new()
var player_visual: Node3D
var walk_clock := 0.0
var time_of_day := 10.0
var sun_light: DirectionalLight3D
var city_environment: Environment
var street_lights: Array[OmniLight3D] = []
var outfit_index := 0
var wardrobe_open := false
var wardrobe_label: Label
var game_paused := false
var minimap: Control
var speed_label: Label
var district_label: Label
var headlamps: Array[SpotLight3D] = []
var parked_cars: Array[StaticBody3D] = []
var npc_visuals: Array[Node3D] = []
var wardrobe_panel: PanelContainer
var sound_status: Label
var all_cars: Array[CharacterBody3D] = []
var traffic_paths: Array = []
var traffic_progress: Array[float] = []
var traffic_speeds: Array[float] = []
var active_car_index := 0
var car_sounds: Array[AudioStreamPlayer3D] = []
var city_audio: AudioStreamPlayer
var bird_audio: AudioStreamPlayer3D
var ambient_timer := 0.0
var map_panel: PanelContainer
var nav_panel: PanelContainer
var time_label: Label
var weather_label: Label
var hud_layer: CanvasLayer
var ui_buttons: Array[Button] = []
var ai_traffic_count := 0
var ui_root: Control
var ui_base_size := Vector2(960, 540)
var traffic_wait: Array[float] = []




func _ready() -> void:
 rng.seed = 4261
 _create_world()
 _create_player()
 _create_car()
 _create_traffic()
 _create_npcs()
 _create_audio()
 _create_ui()
 get_viewport().size_changed.connect(_resize_ui)
 _resize_ui()
 camera = Camera3D.new()
 camera.current = true
 add_child(camera)
 Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _mat(c: Color) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = c
 m.roughness = 1.0
 return m

func _solid_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
 var solid := StaticBody3D.new()
 solid.position = pos
 parent.add_child(solid)
 var shape := CollisionShape3D.new()
 var box_shape := BoxShape3D.new()
 box_shape.size = size
 shape.shape = box_shape
 solid.add_child(shape)
 _box(solid, Vector3.ZERO, size, color)

func _sign(parent: Node3D, pos: Vector3, caption: String) -> void:
 var sign := Label3D.new()
 sign.text = caption
 sign.font_size = 40
 sign.pixel_size = 0.008
 sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 sign.position = pos
 sign.modulate = Color(0.97, 0.93, 0.82)
 parent.add_child(sign)

func _street_lamp(pos: Vector3) -> void:
 var pole := Node3D.new()
 pole.position = pos
 add_child(pole)
 _solid_box(pole, Vector3(0, 3.2, 0), Vector3(0.18, 6.4, 0.18), Color(0.24, 0.27, 0.29))
 _box(pole, Vector3(0.6, 6.3, 0), Vector3(1.35, 0.12, 0.15), Color(0.26, 0.28, 0.3))
 _box(pole, Vector3(1.15, 6.18, 0), Vector3(0.55, 0.08, 0.38), Color(1.0, 0.94, 0.72))
 var lamp := OmniLight3D.new()
 lamp.position = Vector3(1.15, 6.1, 0)
 lamp.light_energy = 0.0
 lamp.omni_range = 10.0
 pole.add_child(lamp)
 street_lights.append(lamp)

func _tree(pos: Vector3) -> void:
 var trunk := Node3D.new()
 trunk.position = pos
 add_child(trunk)
 _solid_box(trunk, Vector3(0, 1.5, 0), Vector3(0.38, 3.0, 0.38), Color(0.34, 0.22, 0.13))
 var leaves := MeshInstance3D.new()
 var mesh := SphereMesh.new()
 mesh.radial_segments = 8
 mesh.rings = 4
 mesh.radius = 1.7
 mesh.height = 3.2
 leaves.mesh = mesh
 leaves.position.y = 4.0
 leaves.material_override = _mat(Color(0.19, 0.38, 0.20))
 trunk.add_child(leaves)

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 n.mesh = mesh
 n.material_override = _mat(color)
 n.position = pos
 parent.add_child(n)
 return n

# Artistic route sketch, NOT georeferenced OSM data. Coordinates in game units.
const MAIN_ROUTE := [Vector2(0, 0), Vector2(-12, -22), Vector2(-27, -47), Vector2(-51, -67), Vector2(-67, -88), Vector2(-83, -115), Vector2(-102, -143)]
const SIDE_ROADS := [
 [Vector2(-12,-22),Vector2(15,-35),Vector2(44,-44),Vector2(74,-40)],
 [Vector2(-27,-47),Vector2(-5,-65),Vector2(20,-86),Vector2(56,-101)],
 [Vector2(-51,-67),Vector2(-70,-48),Vector2(-100,-37)],
 [Vector2(-67,-88),Vector2(-39,-105),Vector2(-14,-131)],
 [Vector2(-83,-115),Vector2(-105,-99),Vector2(-130,-88)],
 [Vector2(15,-35),Vector2(29,-9),Vector2(55,14)],
 [Vector2(-5,-65),Vector2(4,-38),Vector2(15,-35)]
]
var all_road_segments: Array = []
func _road_segment(a: Vector2, b: Vector2, width: float) -> void:
 var d := b - a
 var middle := (a + b) * 0.5
 var angle := atan2(d.x, d.y)
 var road := Node3D.new()
 road.position = Vector3(middle.x, 0, middle.y)
 road.rotation.y = angle
 add_child(road)
 _box(road, Vector3(0,0.015,0), Vector3(width,0.05,d.length()+0.7), Color(0.19,0.20,0.22))
 for side in [-1,1]:
  _box(road,Vector3(side*(width*0.5+1.0),0.045,0),Vector3(1.8,0.09,d.length()+0.5),Color(0.74,0.70,0.60))
 for side in [-1.0,1.0]:
  _box(road,Vector3(side*(width*0.5-0.30),0.060,0),Vector3(0.12,0.012,d.length()),Color(0.94,0.91,0.77))
 for j in range(int(d.length()/8.0)):
  _box(road,Vector3(0,0.056,-d.length()*0.5+4+j*8),Vector3(0.13,0.012,3.0),Color(0.91,0.83,0.55))
 all_road_segments.append([a,b,width])
func _create_world() -> void:
 var sky := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(0.65,0.79,0.91)
 city_environment = env
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(0.85,0.83,0.76)
 env.ambient_light_energy = 0.68
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 sky.environment = env
 add_child(sky)
 sun_light = DirectionalLight3D.new()
 var sun := sun_light
 sun.rotation_degrees = Vector3(-55,35,0)
 sun.light_energy = 1.45
 sun.shadow_enabled = true
 add_child(sun)
 _solid_box(self,Vector3(-25,-0.28,-55),Vector3(360,0.5,360),Color(0.72,0.65,0.49))
 for i in range(MAIN_ROUTE.size()-1):
  _road_segment(MAIN_ROUTE[i],MAIN_ROUTE[i+1],10.0)
 for path in SIDE_ROADS:
  for i in range(path.size()-1):
   _road_segment(path[i],path[i+1],7.0)
 # Extended continuous loop network, with branches that reconnect rather than dead-end.
 # This is an original approximation, not an imported geographic street dataset.
 var ring: Array[Vector2] = [Vector2(-150,-155),Vector2(-150,-105),Vector2(-147,-55),Vector2(-115,-18),Vector2(-80,22),Vector2(-28,36),Vector2(24,32),Vector2(82,9),Vector2(105,-40),Vector2(101,-94),Vector2(65,-151),Vector2(10,-181),Vector2(-54,-188),Vector2(-113,-179),Vector2(-150,-155)]
 for k in range(ring.size()-1):
  _road_segment(ring[k],ring[k+1],9.0)
 var connectors: Array = [
  [Vector2(-102,-143),Vector2(-113,-179)],
  [Vector2(-130,-88),Vector2(-150,-105)],
  [Vector2(-100,-37),Vector2(-115,-18)],
  [Vector2(55,14),Vector2(82,9)],
  [Vector2(74,-40),Vector2(105,-40)],
  [Vector2(56,-101),Vector2(101,-94)],
  [Vector2(-14,-131),Vector2(10,-181)],
  [Vector2(0,0),Vector2(24,32)]
 ]
 for link in connectors:
  _road_segment(link[0],link[1],7.0)


 # Building placement beside roads. Not actual building footprints.
 for segment in all_road_segments:
  var a: Vector2 = segment[0]
  var b: Vector2 = segment[1]
  var d: Vector2 = (b-a).normalized()
  var normal := Vector2(-d.y,d.x)
  var length := a.distance_to(b)
  for j in range(int(length/14.0)):
   for side in [-1,1]:
    if rng.randf()<0.26: continue
    var center: Vector2 = a + d * (7.0 + j * 14.0) + normal * side * (float(segment[2]) * 0.5 + 8.5)
    var intersects_road := false
    for other in all_road_segments:
     var start_pt: Vector2 = other[0]
     var end_pt: Vector2 = other[1]
     var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(center,start_pt,end_pt)
     if center.distance_to(nearest) < float(other[2])*0.5 + 7.5:
      intersects_road = true
      break
    if intersects_road: continue
    var height := rng.randf_range(6.5,18.0)
    var building := Node3D.new()
    building.position=Vector3(center.x,0,center.y)
    building.rotation.y=atan2(d.x,d.y)
    add_child(building)
    _solid_box(building,Vector3(0,height*0.5,0),Vector3(10,height,10),Color(0.76+rng.randf_range(-0.14,0.10),0.71+rng.randf_range(-0.09,0.08),0.59+rng.randf_range(-0.05,0.12)))
    if rng.randf() < 0.22:
     var names := ["بقالة الحي", "صيدلية", "مخبز", "سوبرماركت", "مغسلة", "مطعم"]
     _sign(building, Vector3(0, 2.5, -5.18), names[rng.randi_range(0, names.size()-1)])
    _box(building,Vector3(0,height+0.18,0),Vector3(10.5,0.35,10.5),Color(0.63,0.59,0.52))
    # Architectural detail: recessed storefront, cornices, window frames and balconies.
    _box(building,Vector3(0,0.12,-5.10),Vector3(9.7,0.22,1.2),Color(0.42,0.39,0.34))
    _box(building,Vector3(0,1.55,-5.10),Vector3(3.0,2.65,0.12),Color(0.18,0.23,0.24))
    _box(building,Vector3(0,3.00,-5.25),Vector3(10.2,0.24,0.7),Color(0.63,0.57,0.47))
    for ledge_y in range(1,int(height/3.2)+1):
     var yy := float(ledge_y)*3.0+0.15
     _box(building,Vector3(0,yy,-5.12),Vector3(10.15,0.14,0.42),Color(0.66,0.61,0.52))
    for pillar_x in [-4.75,4.75]:
     _box(building,Vector3(pillar_x,height*0.5,-5.11),Vector3(0.18,height,0.26),Color(0.67,0.61,0.52))
    for floor in range(1,int(height/3.2)+1):
     for wx in [-2.8,0,2.8]:
      _box(building,Vector3(wx,floor*3.0-0.8,-5.10),Vector3(1.42,1.58,0.10),Color(0.81,0.78,0.68))
      _box(building,Vector3(wx,floor*3.0-0.8,-5.17),Vector3(1.15,1.32,0.09),Color(0.16,0.26,0.31))
      _box(building,Vector3(wx,floor*3.0-0.8,-5.23),Vector3(0.08,1.30,0.04),Color(0.72,0.70,0.65))
 for i in range(22):
  var hill := MeshInstance3D.new()
  var mesh := SphereMesh.new()
  mesh.radius=rng.randf_range(18,36)
  mesh.height=rng.randf_range(35,75)
  hill.mesh=mesh
  hill.material_override=_mat(Color(0.51,0.43,0.32))
  var angle:=float(i)/22.0*TAU
  hill.position=Vector3(-25+cos(angle)*170,-7,-55+sin(angle)*170)
  add_child(hill)
  var hill_body := StaticBody3D.new()
  hill_body.position = hill.position
  add_child(hill_body)
  var hill_collision := CollisionShape3D.new()
  var sphere := SphereShape3D.new()
  sphere.radius = mesh.radius
  hill_collision.shape = sphere
  hill_body.add_child(hill_collision)
 for segment in all_road_segments:
  var a: Vector2 = segment[0]
  var b: Vector2 = segment[1]
  var tangent: Vector2 = (b-a).normalized()
  var side := Vector2(-tangent.y, tangent.x)
  var count := int(a.distance_to(b) / 24.0)
  for j in range(count):
   var xy := a.lerp(b, (float(j)+0.5)/maxf(float(count),1.0))
   var lamp_xy := xy + side * (float(segment[2])*0.5+2.4)
   _street_lamp(Vector3(lamp_xy.x,0,lamp_xy.y))
   if j % 2 == 0:
    var tree_xy := xy - side * (float(segment[2])*0.5+3.5)
    _tree(Vector3(tree_xy.x,0,tree_xy.y))
 _sign(self, Vector3(-12, 7, -24), "العدل  |  Al Adl")
 _sign(self, Vector3(-63, 7, -88), "اتجاه الحرم  |  Al Haram")
 _sign(self, Vector3(-28, 6, -48), "العزيزية  |  Al Aziziyah")
 _sign(self, Vector3(-85, 6, -118), "المسفلة  |  Al Misfalah")
 for i in range(13):
  var x := rng.randf_range(-125, 75)
  var z := rng.randf_range(-155, 15)
  if i % 3 == 0: _tree(Vector3(x, 0, z))

# Low-poly child and Saudi-inspired NPCs, made from primitives so no external assets are required.
func _human(parent: Node3D, child_size: bool, outfit: int) -> Node3D:
 var root := Node3D.new()
 parent.add_child(root)
 root.scale = Vector3.ONE * (0.79 if child_size else 1.0)
 var robe := Color(0.95,0.95,0.91) if outfit == 0 else (Color(0.12,0.13,0.16) if outfit == 1 else Color(0.48,0.57,0.66))
 var skin := Color(0.70,0.49,0.35)
 var body := MeshInstance3D.new()
 var skirt := CylinderMesh.new()
 skirt.top_radius = 0.27
 skirt.bottom_radius = 0.40
 skirt.height = 1.13
 skirt.radial_segments = 12
 body.mesh = skirt
 body.position.y = 0.77
 body.material_override = _mat(robe)
 root.add_child(body)
 var neck := MeshInstance3D.new()
 var head := SphereMesh.new()
 head.radius = 0.245
 head.height = 0.45
 head.radial_segments = 12
 head.rings = 6
 neck.mesh = head
 neck.position = Vector3(0,1.55,0)
 neck.material_override = _mat(skin)
 root.add_child(neck)
 var hair := MeshInstance3D.new()
 var hairmesh := SphereMesh.new()
 hairmesh.radius = 0.25
 hairmesh.height = 0.19
 hairmesh.radial_segments = 12
 hair.mesh = hairmesh
 hair.position = Vector3(0,1.75,0.02)
 hair.material_override = _mat(Color(0.10,0.08,0.07) if child_size else Color(0.87,0.87,0.84))
 root.add_child(hair)
 for x in [-0.34,0.34]:
  _box(root,Vector3(x,1.0,0),Vector3(0.16,0.70,0.19),robe)
 for x in [-0.16,0.16]:
  _box(root,Vector3(x,0.10,-0.04),Vector3(0.20,0.16,0.34),Color(0.13,0.12,0.12))
  _box(root,Vector3(x*0.58,1.56,-0.22),Vector3(0.033,0.036,0.018),Color(0.10,0.08,0.08))
 _box(root,Vector3(0,1.15,-0.28),Vector3(0.10,0.08,0.025),Color(0.98,0.98,0.95))
 return root

func _actor(pos: Vector3, outfit: int, is_child: bool = false) -> CharacterBody3D:
 var body := CharacterBody3D.new()
 body.position = pos
 add_child(body)
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.30
 capsule.height = 1.5 if is_child else 1.8
 var collider := CollisionShape3D.new()
 collider.shape = capsule
 collider.position.y = 0.75 if is_child else 0.9
 body.add_child(collider)
 var visual := _human(body, is_child, outfit)
 if is_child: player_visual = visual
 return body

func _create_player() -> void:
 player = _actor(Vector3(0, 0.05, 0), 0, true)

func _create_car() -> void:
 car = CharacterBody3D.new()
 car.position = Vector3(4, 0.08, 1)
 add_child(car)
 var car_collision := CollisionShape3D.new()
 var car_shape := BoxShape3D.new()
 car_shape.size = Vector3(2.1, 1.6, 4.0)
 car_collision.shape = car_shape
 car_collision.position.y = 0.8
 car.add_child(car_collision)
 _vehicle_model(car,Color(0.83,0.83,0.81),false)
 # Main driveable car: wheel geometry, glass and light details.

func _vehicle_model(parent: Node3D, color: Color, suv: bool, police: bool = false) -> void:
 var h := 0.92 if suv else 0.72
 _box(parent,Vector3(0,h,0),Vector3(2.0,0.58,4.15),color)
 _box(parent,Vector3(0,h+0.56,-0.23),Vector3(1.73,0.62 if suv else 0.48,2.25),Color(0.18,0.28,0.35))
 _box(parent,Vector3(0,h+0.23,-2.08),Vector3(1.62,0.18,0.07),Color(0.12,0.13,0.14))
 for x in [-0.74,0.74]:
  _box(parent,Vector3(x,h,-2.10),Vector3(0.39,0.20,0.08),Color(1,0.97,0.77))
  _box(parent,Vector3(x,h,2.10),Vector3(0.39,0.18,0.08),Color(0.9,0.09,0.07))
 for x in [-1.04,1.04]:
  for z in [-1.32,1.32]:
   var wheel := MeshInstance3D.new()
   var mesh := CylinderMesh.new()
   mesh.top_radius = 0.40
   mesh.bottom_radius = 0.40
   mesh.height = 0.23
   mesh.radial_segments = 12
   wheel.mesh = mesh
   wheel.rotation.z = PI * 0.5
   wheel.position = Vector3(x,0.41,z)
   wheel.material_override = _mat(Color(0.08,0.09,0.10))
   parent.add_child(wheel)
 # Detailed bodywork: bonnet, bumpers, side sills, grille, door seams and mirrors.
 _box(parent,Vector3(0,h+0.20,-1.62),Vector3(1.88,0.10,0.80),color.lightened(0.06))
 _box(parent,Vector3(0,h-0.18,-2.14),Vector3(1.85,0.20,0.15),Color(0.13,0.14,0.16))
 _box(parent,Vector3(0,h-0.18,2.14),Vector3(1.85,0.18,0.15),Color(0.14,0.15,0.17))
 for side in [-1.0,1.0]:
  _box(parent,Vector3(side*1.02,h-0.16,0),Vector3(0.10,0.14,2.45),Color(0.13,0.14,0.15))
  _box(parent,Vector3(side*0.96,h+0.54,-1.15),Vector3(0.28,0.15,0.42),color.darkened(0.25))
  for door_z in [-0.45,0.75]:
   _box(parent,Vector3(side*1.01,h+0.10,door_z),Vector3(0.025,0.04,0.72),Color(0.18,0.19,0.20))
  for wheel_z in [-1.32,1.32]:
   var rim := MeshInstance3D.new()
   var rim_mesh := CylinderMesh.new()
   rim_mesh.top_radius = 0.23
   rim_mesh.bottom_radius = 0.23
   rim_mesh.height = 0.245
   rim_mesh.radial_segments = 12
   rim.mesh = rim_mesh
   rim.rotation.z = PI*0.5
   rim.position = Vector3(side*1.045,0.41,wheel_z)
   rim.material_override = _mat(Color(0.65,0.68,0.70))
   parent.add_child(rim)
 if police:
  _box(parent,Vector3(0,h+0.94,-0.25),Vector3(0.85,0.15,0.3),Color(0.1,0.22,0.8))
  _sign(parent,Vector3(0,h+0.4,-2.15),"الشرطة")

func _spawn_driveable_vehicle(xy: Vector2, heading: float, color: Color, suv: bool, police: bool, route: Array, progress: float, moving: bool) -> void:
 var vehicle := CharacterBody3D.new()
 vehicle.position = Vector3(xy.x,0.08,xy.y)
 vehicle.rotation.y = heading
 vehicle.collision_layer = 1
 vehicle.collision_mask = 1
 add_child(vehicle)
 var collider := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = Vector3(2.05,1.65,4.1)
 collider.position.y = 0.82
 collider.shape = shape
 vehicle.add_child(collider)
 _vehicle_model(vehicle,color,suv,police)
 all_cars.append(vehicle)
 traffic_paths.append(route)
 traffic_progress.append(progress)
 traffic_speeds.append((4.5 + rng.randf_range(0,2.0)) if moving else 0.0)
 traffic_wait.append(0.0)
 var audio := AudioStreamPlayer3D.new()
 audio.stream = load("res://audio/engine.wav")
 audio.unit_size = 5.0
 audio.max_distance = 30.0
 audio.volume_db = -14.0
 vehicle.add_child(audio)
 car_sounds.append(audio)

func _create_traffic() -> void:
 # Every vehicle is enterable; AI vehicles move along their own closed circuits.
 all_cars.append(car)
 traffic_paths.append([])
 traffic_progress.append(0.0)
 traffic_speeds.append(0.0)
 traffic_wait.append(0.0)
 var primary_sound := AudioStreamPlayer3D.new()
 primary_sound.stream = load("res://audio/engine.wav")
 primary_sound.unit_size = 5.0
 primary_sound.max_distance = 30.0
 primary_sound.volume_db = -14.0
 car.add_child(primary_sound)
 car_sounds.append(primary_sound)
 var colors := [Color(0.93,0.93,0.91),Color(0.13,0.17,0.21),Color(0.72,0.73,0.75),Color(0.65,0.13,0.11),Color(0.84,0.73,0.48),Color(0.18,0.39,0.49)]
 var circuits: Array = [
  [Vector2(-150,-155),Vector2(-150,-105),Vector2(-147,-55),Vector2(-115,-18),Vector2(-80,22),Vector2(-28,36),Vector2(24,32),Vector2(82,9),Vector2(105,-40),Vector2(101,-94),Vector2(65,-151),Vector2(10,-181),Vector2(-54,-188),Vector2(-113,-179),Vector2(-150,-155)],
  [Vector2(0,0),Vector2(-12,-22),Vector2(-27,-47),Vector2(-51,-67),Vector2(-67,-88),Vector2(-83,-115),Vector2(-102,-143),Vector2(-113,-179),Vector2(-54,-188),Vector2(10,-181),Vector2(65,-151),Vector2(101,-94),Vector2(56,-101),Vector2(20,-86),Vector2(-5,-65),Vector2(4,-38),Vector2(15,-35),Vector2(29,-9),Vector2(55,14),Vector2(82,9),Vector2(24,32),Vector2(0,0)]
 ]
 for i in range(24):
  var route: Array = circuits[i % circuits.size()]
  var seg := i % (route.size()-1)
  var t := 0.16 + rng.randf()*0.64
  var a: Vector2 = route[seg]
  var b: Vector2 = route[seg+1]
  var xy: Vector2 = a.lerp(b,t)
  var tangent: Vector2 = (b-a).normalized()
  xy += Vector2(-tangent.y,tangent.x)*1.45
  var heading := atan2(-tangent.x,-tangent.y)
  _spawn_driveable_vehicle(xy,heading,colors[i % colors.size()],i % 3 == 0,i % 8 == 0,route,float(seg)+t,true)
 ai_traffic_count = 24

func _create_npcs() -> void:
 for i in range(36):
  var p := _actor(Vector3(rng.randf_range(-105, 65), 0.05, rng.randf_range(-145, 15)), i % 3)
  npc_list.append(p)
  npc_targets.append(p.position + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12)))

func _ui_button(parent: Control, caption: String, pos: Vector2, width: float, action: String) -> void:
 var b := Button.new()
 b.text = caption
 b.position = pos
 b.size = Vector2(width,40)
 b.add_theme_font_size_override("font_size",15)
 b.pressed.connect(_ui_action.bind(action))
 parent.add_child(b)
 ui_buttons.append(b)

func _ui_action(action: String) -> void:
 match action:
  "map": map_panel.visible = not map_panel.visible
  "vehicles": _toggle_car()
  "clothes": _toggle_wardrobe()
  "camera": first_person = not first_person
  "night": time_of_day = 22.0 if time_of_day < 18.0 else 10.0
  "sound": city_audio.stream_paused = not city_audio.stream_paused
  "police": _enter_nearest_car(true)

func _create_ui() -> void:
 hud_layer = CanvasLayer.new()
 add_child(hud_layer)
 ui_root = Control.new()
 ui_root.size = ui_base_size
 hud_layer.add_child(ui_root)
 var button_container := Control.new()
 button_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ui_root.add_child(button_container)
 var top := ColorRect.new()
 top.color = Color(0.02,0.035,0.055,0.84)
 top.position = Vector2(0,0)
 top.size = Vector2(960,66)
 ui_root.add_child(top)
 hud = Label.new()
 hud.position = Vector2(20,6)
 hud.add_theme_font_size_override("font_size",23)
 hud.add_theme_color_override("font_color",Color(1,0.80,0.29))
 ui_root.add_child(hud)
 district_label = Label.new()
 district_label.position = Vector2(21,39)
 district_label.add_theme_font_size_override("font_size",13)
 ui_root.add_child(district_label)
 time_label = Label.new()
 time_label.position = Vector2(786,7)
 time_label.add_theme_font_size_override("font_size",16)
 ui_root.add_child(time_label)
 weather_label = Label.new()
 weather_label.position = Vector2(786,32)
 weather_label.text = "MAKKAH  |  28 C"
 weather_label.add_theme_font_size_override("font_size",13)
 ui_root.add_child(weather_label)
 var left := ColorRect.new()
 left.position = Vector2(0,68)
 left.size = Vector2(133,268)
 left.color = Color(0.02,0.035,0.055,0.78)
 ui_root.add_child(left)
 _ui_button(button_container,"MAP / خريطة",Vector2(5,73),122,"map")
 _ui_button(button_container,"VEHICLES",Vector2(5,117),122,"vehicles")
 _ui_button(button_container,"CLOTHES",Vector2(5,161),122,"clothes")
 _ui_button(button_container,"CAMERA",Vector2(5,205),122,"camera")
 _ui_button(button_container,"DAY / NIGHT",Vector2(5,249),122,"night")
 _ui_button(button_container,"POLICE CAR",Vector2(5,293),122,"police")
 speed_label = Label.new()
 speed_label.position = Vector2(782,445)
 speed_label.add_theme_font_size_override("font_size",28)
 speed_label.add_theme_color_override("font_color",Color(1,0.86,0.35))
 ui_root.add_child(speed_label)
 minimap = Control.new()
 minimap.set_script(load("res://minimap.gd"))
 minimap.position = Vector2(14,345)
 minimap.size = Vector2(170,170)
 ui_root.add_child(minimap)
 minimap.set("roads",all_road_segments)
 map_panel = PanelContainer.new()
 map_panel.position = Vector2(195,90)
 map_panel.custom_minimum_size = Vector2(560,380)
 map_panel.visible = false
 ui_root.add_child(map_panel)
 var map_text := Label.new()
 map_text.text = "MAKKAH DISTRICTS / أحياء مكة\n\nAl Adl  |  Al Haram  |  Al Aziziyah\nAl Misfalah  |  Al Rusayfah  |  Al Shisha\n\nThe map is an approximate game layout, not yet real GPS roads.\nPress MAP again to close."
 map_text.add_theme_font_size_override("font_size", 17)
 map_text.add_theme_color_override("font_color",Color(0.95,0.94,0.88))
 map_panel.add_child(map_text)
 var bottom := ColorRect.new()
 bottom.position = Vector2(190,511)
 bottom.size = Vector2(770,29)
 bottom.color = Color(0.02,0.035,0.055,0.84)
 ui_root.add_child(bottom)
 var note := Label.new()
 note.text = "WASD / STICK: MOVE   |   E / A: ENTER ANY CAR   |   C / Y: CAMERA   |   B: CLOTHES   |   N: NIGHT"
 note.position = Vector2(197,518)
 note.add_theme_font_size_override("font_size",11)
 ui_root.add_child(note)
 wardrobe_panel = PanelContainer.new()
 wardrobe_panel.position = Vector2(245,105)
 wardrobe_panel.custom_minimum_size = Vector2(470,290)
 wardrobe_panel.visible = false
 ui_root.add_child(wardrobe_panel)
 wardrobe_label = Label.new()
 wardrobe_label.add_theme_font_size_override("font_size",24)
 wardrobe_label.add_theme_color_override("font_color",Color(0.95,0.94,0.88))
 wardrobe_panel.add_child(wardrobe_label)
 sound_status = Label.new()
 sound_status.position = Vector2(645,78)
 sound_status.add_theme_font_size_override("font_size",12)
 ui_root.add_child(sound_status)

func _resize_ui() -> void:
 if ui_root == null: return
 var actual := get_viewport().get_visible_rect().size
 var factor: float = minf(actual.x / ui_base_size.x, actual.y / ui_base_size.y)
 ui_root.scale = Vector2.ONE * factor
 ui_root.position = (actual - ui_base_size * factor) * 0.5

func _create_audio() -> void:
 city_audio = AudioStreamPlayer.new()
 city_audio.stream = load("res://audio/city.wav")
 city_audio.volume_db = -23.0
 add_child(city_audio)
 city_audio.play()
 bird_audio = AudioStreamPlayer3D.new()
 bird_audio.stream = load("res://audio/birds.wav")
 bird_audio.position = Vector3(-10,3,-23)
 bird_audio.max_distance = 75.0
 bird_audio.volume_db = -9.0
 add_child(bird_audio)
 bird_audio.play()

func _advance_traffic(delta: float) -> void:
 for i in range(1, all_cars.size()):
  if driving and i == active_car_index: continue
  var vehicle: CharacterBody3D = all_cars[i]
  var route: Array = traffic_paths[i]
  if route.size() < 2: continue
  var idx := int(floor(traffic_progress[i])) % (route.size()-1)
  var a: Vector2 = route[idx]
  var b: Vector2 = route[idx+1]
  var direction_2d: Vector2 = (b-a).normalized()
  var forward := Vector3(direction_2d.x, 0.0, direction_2d.y)
  var target := Vector3(b.x, vehicle.position.y, b.y)
  if vehicle.position.distance_to(target) < 3.0:
   traffic_progress[i] = float((idx+1) % (route.size()-1))
   idx = int(traffic_progress[i])
   a = route[idx]
   b = route[idx+1]
   direction_2d = (b-a).normalized()
   forward = Vector3(direction_2d.x,0.0,direction_2d.y)
  var blocked := false
  for j in range(all_cars.size()):
   if i == j: continue
   var offset: Vector3 = all_cars[j].position - vehicle.position
   if offset.length() < 5.5 and offset.dot(forward) > 0.5:
    blocked = true
    break
  var desired_speed := 0.0 if blocked else traffic_speeds[i]
  # Never assign positive vertical velocity: the cars must stay on the ground.
  vehicle.velocity = forward * desired_speed
  vehicle.velocity.y = -2.0
  vehicle.move_and_slide()
  if vehicle.position.y > 1.0:
   vehicle.position.y = move_toward(vehicle.position.y, 0.08, delta*12.0)
  elif vehicle.position.y < -0.15:
   vehicle.position.y = 0.08
  var desired_angle := atan2(-forward.x,-forward.z)
  vehicle.rotation.y = lerp_angle(vehicle.rotation.y,desired_angle,delta*3.0)
  if vehicle.velocity.length() > 1.0 and not car_sounds[i].playing: car_sounds[i].play()
  if vehicle.velocity.length() <= 1.0 and car_sounds[i].playing: car_sounds[i].stop()

func _axis(negative: int, positive: int, joy_axis: int) -> float:
 var value := Input.get_joy_axis(0, joy_axis)
 if abs(value) < 0.16: value = 0.0
 return clampf(value + float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative)), -1.0, 1.0)

func _physics_process(delta: float) -> void:
 time_of_day = fposmod(time_of_day + delta * 0.035, 24.0)
 var daylight := clampf(sin((time_of_day-6.0)*PI/12.0), 0.0, 1.0)
 sun_light.rotation_degrees.x = -15.0 - daylight * 60.0
 sun_light.light_energy = 0.08 + daylight * 1.05
 city_environment.background_color = Color(0.035,0.055,0.12).lerp(Color(0.65,0.79,0.91),daylight)
 city_environment.ambient_light_energy = 0.23 + daylight * 0.62
 for lamp in street_lights:
  lamp.light_energy = 0.8 if daylight < 0.25 else 0.0
 _advance_traffic(delta)
 if wardrobe_open:
  wardrobe_label.text = "  WARDROBE  |  غرفة الملابس\n\n  [1]  WHITE THOBE\n  [2]  DARK THOBE\n  [3]  CASUAL OUTFIT\n\n  Press B / Back to close"
  return
 var lx := _axis(KEY_A, KEY_D, JOY_AXIS_LEFT_X)
 var ly := _axis(KEY_W, KEY_S, JOY_AXIS_LEFT_Y)
 var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
 var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
 if abs(rx) > 0.15: yaw -= rx * delta * 2.2
 if abs(ry) > 0.15: pitch = clampf(pitch - ry * delta * 1.6, -0.75, 0.45)
 if Input.is_key_pressed(KEY_LEFT): yaw += delta * 1.6
 if Input.is_key_pressed(KEY_RIGHT): yaw -= delta * 1.6
 if Input.is_key_pressed(KEY_UP): pitch = clampf(pitch + delta, -0.75, 0.45)
 if Input.is_key_pressed(KEY_DOWN): pitch = clampf(pitch - delta, -0.75, 0.45)
 if driving:
  var gas := maxf(maxf(0.0,Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)), float(Input.is_key_pressed(KEY_W)))
  var brake := maxf(maxf(0.0,Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)), float(Input.is_key_pressed(KEY_S)))
  # Arcade driving: 0–115 km/h forward, 0–25 km/h reverse.
  # Acceleration is in metres/second squared; steering reduces at high speed.
  var target_speed: float = gas * 32.0 - brake * 7.0
  var acceleration: float = 17.0 if gas > 0.1 else (13.0 if brake > 0.1 else 8.0)
  speed = move_toward(speed, target_speed, acceleration * delta)
  var steer_strength: float = lerpf(1.9, 0.75, clampf(absf(speed) / 32.0, 0.0, 1.0))
  if absf(speed) > 0.5:
   car_heading -= lx * delta * steer_strength * signf(speed)
  car.rotation.y = car_heading
  car.velocity = Vector3(-sin(car_heading) * speed, -2.0, -cos(car_heading) * speed)
  car.move_and_slide()
  # Only slow for a real wall/vehicle impact, not contact with the road.
  for collision_index in range(car.get_slide_collision_count()):
   var hit_normal: Vector3 = car.get_slide_collision(collision_index).get_normal()
   if absf(hit_normal.y) < 0.45:
    speed *= 0.35
    break
  if abs(speed) > 0.4 and not car_sounds[active_car_index].playing: car_sounds[active_car_index].play()
  if abs(speed) < 0.4 and car_sounds[active_car_index].playing: car_sounds[active_car_index].stop()
  player.position = car.position + Vector3(0, 2.7, 0)
 else:
  var forward := Vector3(-sin(yaw), 0, -cos(yaw))
  var right := Vector3(cos(yaw), 0, -sin(yaw))
  var move := (right * lx - forward * ly).limit_length(1.0)
  var walk_speed := 7.0 if Input.is_key_pressed(KEY_SHIFT) else 4.2
  player.velocity = move * walk_speed
  player.velocity.y = -2.0
  player.move_and_slide()
  if move.length() > 0.1:
   player.rotation.y = atan2(-move.x, -move.z)
   walk_clock += delta * 8.0
   player_visual.position.y = sin(walk_clock) * 0.035
  else:
   player_visual.position.y = 0.0

 for i in range(npc_list.size()):
  var n := npc_list[i]
  var v := npc_targets[i] - n.position
  if v.length() < 0.8:
   npc_targets[i] = n.position + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
  else:
   n.velocity = v.normalized() * (0.6 + float(i % 3) * 0.23)
   n.velocity.y = -2.0
   n.move_and_slide()
   n.rotation.y = atan2(-v.x, -v.z)
 var focus := car.position if driving else player.position
 var camera_yaw := car_heading if driving else yaw
 var facing := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
 if first_person:
  camera.position = focus + Vector3(0, 1.65, 0)
 else:
  camera.position = focus - facing * 6.5 + Vector3(0, 3.5, 0)
 camera.look_at(focus + facing * 7 + Vector3(0, 1.3 + pitch * 8, 0), Vector3.UP)
 player.visible = not driving and not first_person
 hud.text = "CITY FREEDOM  |  MAKKAH  V8"
 district_label.text = "AL ADL → AL HARAM  •  %s  •  %02d:%02d  •  %s" % ["DRIVING" if driving else "WALKING",int(time_of_day),int(fposmod(time_of_day,1.0)*60.0),"1ST PERSON" if first_person else "3RD PERSON"]
 speed_label.text = "%02d KM/H" % int(abs(speed)*3.6) if driving else "ON FOOT"
 time_label.text = "%02d:%02d" % [int(time_of_day),int(fposmod(time_of_day,1.0)*60.0)]
 sound_status.text = "ENGINE + CITY + BIRDS | ORIGINAL AUDIO"
 minimap.set("player_xy",Vector2(focus.x,focus.z))
 minimap.queue_redraw()

func _input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
  yaw -= event.relative.x * 0.003
  pitch = clampf(pitch - event.relative.y * 0.002, -0.75, 0.45)
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_ESCAPE: Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
  if event.keycode == KEY_C: first_person = not first_person
  if event.keycode == KEY_E: _toggle_car()
  if event.keycode == KEY_B: _toggle_wardrobe()
  if event.keycode == KEY_N: time_of_day = 22.0 if time_of_day < 18.0 else 10.0
  if wardrobe_open and event.keycode in [KEY_1, KEY_2, KEY_3]: _set_outfit(event.keycode - KEY_1)
 if event is InputEventJoypadButton and event.pressed:
  if event.button_index == JOY_BUTTON_A: _toggle_car()
  if event.button_index == JOY_BUTTON_Y: first_person = not first_person
  if event.button_index == JOY_BUTTON_B: _toggle_wardrobe()

func _enter_nearest_car(police_only: bool = false) -> void:
 var best := -1
 var distance := 7.0
 for i in range(all_cars.size()):
  var candidate: CharacterBody3D = all_cars[i]
  if police_only and i > 0 and (i-1) % 8 != 0: continue
  if police_only and i == 0: continue
  var d := player.position.distance_to(candidate.position)
  if d < distance:
   distance = d
   best = i
 if best >= 0:
  active_car_index = best
  car = all_cars[best]
  driving = true
  player.collision_layer = 0
  player.collision_mask = 0
  car_heading = car.rotation.y
  speed = 0.0

func _toggle_car() -> void:
 if driving:
  driving = false
  player.collision_layer = 1
  player.collision_mask = 1
  speed = 0.0
  if car_sounds[active_car_index].playing: car_sounds[active_car_index].stop()
  var exit_pos := car.position + car.global_transform.basis.x * 3.0
  player.position = exit_pos
 else:
  _enter_nearest_car()

func _toggle_wardrobe() -> void:
 wardrobe_open = not wardrobe_open
 wardrobe_panel.visible = wardrobe_open
 Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if wardrobe_open else Input.MOUSE_MODE_CAPTURED)

func _set_outfit(index: int) -> void:
 outfit_index = index
 if is_instance_valid(player_visual):
  player_visual.queue_free()
 player_visual = _human(player, true, outfit_index)
