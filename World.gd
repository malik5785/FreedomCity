extends Spatial
var player
var car
var camera
var driving = false
var velocity = 0.0
var heading = 0.0
var status
var rng = RandomNumberGenerator.new()
func box(parent, pos, size, color):
    var mesh = CubeMesh.new()
    mesh.size = size
    var inst = MeshInstance.new()
    inst.mesh = mesh
    var mat = SpatialMaterial.new()
    mat.albedo_color = color
    inst.material_override = mat
    inst.translation = pos
    parent.add_child(inst)
    return inst
func _ready():
    rng.seed = 20261103
    var env = WorldEnvironment.new()
    var e = Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.55,0.75,0.95)
    e.ambient_light_color = Color(0.85,0.85,0.9)
    e.ambient_light_energy = 0.85
    env.environment = e
    add_child(env)
    var sun = DirectionalLight.new()
    sun.rotation_degrees = Vector3(-55,30,0)
    add_child(sun)
    box(self,Vector3(0,-0.3,0),Vector3(600,0.5,600),Color(0.67,0.58,0.45))
    for i in range(-4,5):
        box(self,Vector3(i*55,0,0),Vector3(13,0.1,550),Color(0.16,0.18,0.21))
        box(self,Vector3(0,0,i*55),Vector3(550,0.1,13),Color(0.16,0.18,0.21))
        for j in range(-4,4):
            var x = i*55+27
            var z = j*55+27
            var h = rng.randf_range(15,60)
            box(self,Vector3(x,h/2,z),Vector3(30,h,30),Color(0.72,0.69,0.62))
            for floor_i in range(2,int(h/5)):
                box(self,Vector3(x, floor_i*5,z+15.1),Vector3(22,1.2,0.1),Color(0.18,0.25,0.3))
    box(self,Vector3(0,65,-190),Vector3(30,130,30),Color(0.68,0.61,0.47))
    box(self,Vector3(0,125,-173),Vector3(13,13,1),Color(0.9,0.9,0.83))
    player = Spatial.new()
    add_child(player)
    player.translation = Vector3(0,0,7)
    box(player,Vector3(0,1,0),Vector3(0.8,2,0.5),Color(0.96,0.96,0.93))
    box(player,Vector3(0,2.3,0),Vector3(0.5,0.5,0.5),Color(0.66,0.44,0.30))
    car = Spatial.new()
    add_child(car)
    car.translation = Vector3(5,0,0)
    box(car,Vector3(0,0.8,0),Vector3(2.2,1.1,4.4),Color(0.85,0.85,0.89))
    box(car,Vector3(0,1.5,-0.2),Vector3(1.8,0.65,2.2),Color(0.18,0.27,0.36))
    for x in [-1.1,1.1]:
        for z in [-1.3,1.3]:
            box(car,Vector3(x,0.35,z),Vector3(0.35,0.7,0.7),Color(0.08,0.08,0.08))
    camera = Camera.new()
    camera.current = true
    add_child(camera)
    var layer = CanvasLayer.new()
    add_child(layer)
    status = Label.new()
    status.rect_position = Vector2(20,20)
    status.add_color_override("font_color",Color(1,1,1))
    layer.add_child(status)
    set_process(true)
func _process(delta):
    var axis = Vector2(Input.get_action_strength("move_right")-Input.get_action_strength("move_left"),Input.get_action_strength("move_back")-Input.get_action_strength("move_forward"))
    if Input.is_action_just_pressed("interact"):
        driving = not driving
        player.visible = not driving
    if driving:
        velocity = lerp(velocity, -axis.y*22.0, min(1,delta*2))
        heading -= axis.x*delta*1.5
        car.rotation.y = heading
        car.translation += Vector3(sin(heading),0,cos(heading))*velocity*delta
    else:
        var move = Vector3(axis.x,0,axis.y)
        player.translation += move.normalized()*delta*7.0 if move.length()>0.1 else Vector3()
    var target = car if driving else player
    var behind = Vector3(sin(heading)*-10,6,cos(heading)*10) if driving else Vector3(0,5,10)
    camera.translation = camera.translation.linear_interpolate(target.translation+behind,min(1,delta*5))
    camera.look_at(target.translation+Vector3(0,1,0),Vector3.UP)
    status.text = "EYAD RAMMAH RAZZAM | MAKKAH\nA: Enter/Exit Car | Left Stick: Move/Drive\n"+("DRIVING  %d KM/H" % int(abs(velocity)*3.6) if driving else "WALKING")
