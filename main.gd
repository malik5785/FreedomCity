extends Node3D
# City Freedom - Makkah  V10
# Roads come from map_data.gd (traced from the user's FULL MAP picture).
# World geometry is merged into few meshes per area ("batching") so it runs on a TV.
const MapData := preload("res://map_data.gd")
const CHUNK := 90.0
const WORLD_HALF := Vector2(520.0, 380.0)

var player: CharacterBody3D
var car: CharacterBody3D
var camera: Camera3D
var rng := RandomNumberGenerator.new()
var driving := false
var first_person := false
var yaw := 0.0
var pitch := -0.18
var car_heading := 0.0
var speed := 0.0
var walk_clock := 0.0
var time_of_day := 10.0
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var city_environment: Environment
var sky_mat: ProceduralSkyMaterial
var sun_mesh: MeshInstance3D
var moon_mesh: MeshInstance3D
var cloud_nodes: Array = []
var cloud_mat: StandardMaterial3D
var player_visual: Node3D
var outfit := {"top": 0, "bottom": 0, "shoes": 0, "head": 0, "glasses": 0}
var wardrobe_open := false
var wardrobe_panel: Control
var wardrobe_info: Label
var wardrobe_spin := 0.0

# UI
var hud: Label
var district_label: Label
var time_label: Label
var weather_label: Label
var speed_label: Label
var sound_status: Label
var hud_layer: CanvasLayer
var ui_root: Control
var ui_base_size := Vector2(960, 540)
var minimap: Control
var full_map: Control
var map_open := false

# traffic
var all_cars: Array = []
var traffic_routes: Array = []
var traffic_idx: Array = []
var traffic_speeds: Array = []
var traffic_wait: Array = []
var traffic_stuck: Array = []
var car_sounds: Array = []
var car_kinds: Array = []
var active_car_index := 0
var roads: Array = []          # [a(Vector2), b(Vector2), width]
var road_grid := {}
var building_grid := {}
var npc_list: Array = []
var npc_seg: Array = []
var npc_t: Array = []
var npc_dir: Array = []
var npc_side: Array = []
var npc_speed: Array = []
var npc_clock: Array = []

# batching / materials
var batches := {}
var box_cache := {}
var mats := {}
var night_mats: Array = []     # [material, day_energy, night_energy]
var lamp_positions: Array = []
var lamp_pool: Array = []
var lamp_timer := 0.0
var tree_positions: Array = []
var headlight_pair: Array = []
var police_flash_mats: Array = []
var flash_clock := 0.0

# audio
var city_audio: AudioStreamPlayer
var horn_audio: AudioStreamPlayer
var azan_audio: AudioStreamPlayer3D
var azan_status := ""
var last_prayer_hour := -1

func _ready() -> void:
	rng.seed = 4261
	_create_world()
	_create_roads_and_city()
	_create_haram()
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
	camera.far = 900.0
	add_child(camera)
	_flush_batches()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ---------------------------------------------------------------- materials
func _mat_key(c: Color) -> String:
	return "c:" + c.to_html(false)

func _get_mat(key: String) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	if key.begins_with("c:"):
		m.albedo_color = Color.html(key.substr(2))
	elif key.begins_with("w:") or key.begins_with("tex:"):
		var tname := "plaster"
		if key.begins_with("w:"):
			m.albedo_color = Color.html(key.substr(2))
			m.roughness = 0.95
		else:
			tname = key.substr(4)
			m.roughness = 0.88 if tname == "asphalt" else 0.8
			m.albedo_color = Color(1, 1, 1)
		var tpath := "res://tex/" + tname + ".png"
		if ResourceLoader.exists(tpath):
			m.albedo_texture = load(tpath)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			var sc := 0.2 if tname == "asphalt" else (0.5 if tname == "sidewalk" else 0.18)
			m.uv1_scale = Vector3(sc, sc, sc)
	elif key.begins_with("p:"):
		m.albedo_color = Color.html(key.substr(2))
		m.metallic = 0.35
		m.roughness = 0.38
	elif key.begins_with("e:"):
		# emissive: colour glows at night (shop signs, lamps, headlights)
		var col := Color.html(key.substr(2))
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.15
		night_mats.append([m, 0.15, 1.6])
	elif key == "win_lit":
		m.albedo_color = Color(0.16, 0.26, 0.31)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.82, 0.45)
		m.emission_energy_multiplier = 0.0
		night_mats.append([m, 0.0, 1.3])
	elif key == "win_dark":
		m.albedo_color = Color(0.13, 0.20, 0.25)
	elif key == "flash_red" or key == "flash_blue":
		var fc := Color(1.0, 0.1, 0.1) if key == "flash_red" else Color(0.15, 0.3, 1.0)
		m.albedo_color = fc
		m.emission_enabled = true
		m.emission = fc
		m.emission_energy_multiplier = 0.3
		police_flash_mats.append(m)
	mats[key] = m
	return m

func _mat(c: Color) -> StandardMaterial3D:
	return _get_mat(_mat_key(c))

# ---------------------------------------------------------------- batching
func _bm(size: Vector3) -> BoxMesh:
	var k := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if box_cache.has(k):
		return box_cache[k]
	var m := BoxMesh.new()
	m.size = size
	box_cache[k] = m
	return m

func _batch_mesh(mesh: Mesh, t: Transform3D, mat_key: String) -> void:
	var cx := int(floor(t.origin.x / CHUNK))
	var cz := int(floor(t.origin.z / CHUNK))
	var key := "%s|%d|%d" % [mat_key, cx, cz]
	var st: SurfaceTool
	if batches.has(key):
		st = batches[key]
	else:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_get_mat(mat_key))
		batches[key] = st
	st.append_from(mesh, 0, t)

# box in a local frame xf (rotation+position), local offset, size
func _bb(xf: Transform3D, local: Vector3, size: Vector3, mat_key: String) -> void:
	_batch_mesh(_bm(size), Transform3D(xf.basis, xf * local), mat_key)

func _wb(pos: Vector3, size: Vector3, mat_key: String) -> void:
	_batch_mesh(_bm(size), Transform3D(Basis.IDENTITY, pos), mat_key)

func _flush_batches() -> void:
	for key in batches.keys():
		var st: SurfaceTool = batches[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.visibility_range_end = 420.0
		mi.visibility_range_end_margin = 40.0
		add_child(mi)
	batches.clear()

func _solid(pos: Vector3, size: Vector3, yaw_rot: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw_rot
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)

func _label(parent: Node, text: String, pos: Vector3, px: float, col: Color, vis_end: float, rot_y: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 6
	l.position = pos
	l.rotation.y = rot_y
	l.visibility_range_end = vis_end
	parent.add_child(l)
	return l

# ---------------------------------------------------------------- world, sky
func _create_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_color = Color(0.65, 0.79, 0.91)
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.18
	sky_mat.ground_curve = 0.05
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	env.sky = sky_res
	env.background_mode = Environment.BG_SKY
	env.glow_enabled = true
	env.glow_intensity = 0.0
	env.glow_hdr_threshold = 0.9
	env.glow_bloom = 0.08
	city_environment = env
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.83, 0.76)
	env.ambient_light_energy = 0.68
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.78, 0.84, 0.9)
	we.environment = env
	add_child(we)
	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 110.0
	add_child(sun_light)
	moon_light = DirectionalLight3D.new()
	moon_light.light_color = Color(0.62, 0.72, 1.0)
	moon_light.light_energy = 0.0
	add_child(moon_light)
	# ground
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1500, 1.0, 1200)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.86, 0.78, 0.60)
	gmat.roughness = 1.0
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gn.frequency = 0.02
	var gtex := NoiseTexture2D.new()
	gtex.width = 256
	gtex.height = 256
	gtex.seamless = true
	gtex.noise = gn
	var gramp := Gradient.new()
	gramp.set_color(0, Color(0.70, 0.66, 0.58))
	gramp.set_color(1, Color(1.0, 1.0, 1.0))
	gtex.color_ramp = gramp
	gmat.albedo_texture = gtex
	gmat.uv1_scale = Vector3(34, 28, 1)
	if ResourceLoader.exists("res://tex/sand.png"):
		gmat.albedo_texture = load("res://tex/sand.png")
		gmat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		gmat.uv1_triplanar = true
		gmat.uv1_world_triplanar = true
	ground.material_override = gmat
	ground.position = Vector3(0, -0.53, 0)
	add_child(ground)
	_solid(Vector3(0, -0.53, 0), Vector3(1500, 1.0, 1200))
	# invisible walls so nothing leaves the map
	var wx := WORLD_HALF.x + 12.0
	var wz := WORLD_HALF.y + 12.0
	_solid(Vector3(wx, 10, 0), Vector3(4, 40, 1200))
	_solid(Vector3(-wx, 10, 0), Vector3(4, 40, 1200))
	_solid(Vector3(0, 10, wz), Vector3(1500, 40, 4))
	_solid(Vector3(0, 10, -wz), Vector3(1500, 40, 4))
	# mountains ring (visible and solid)
	for i in range(30):
		var ang := float(i) / 30.0 * TAU
		var r := rng.randf_range(38.0, 80.0)
		var hill := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 14
		sm.rings = 7
		hill.mesh = sm
		var shade := rng.randf_range(-0.07, 0.05)
		hill.material_override = _mat(Color(0.50 + shade, 0.42 + shade, 0.32 + shade))
		hill.position = Vector3(cos(ang) * 660.0, -r * 0.55, sin(ang) * 520.0)
		add_child(hill)
		var hb := StaticBody3D.new()
		hb.position = hill.position
		var hc := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = r
		hc.shape = ss
		hb.add_child(hc)
		add_child(hb)
	# sun, moon (unshaded discs that follow the camera)
	sun_mesh = _sky_disc(Color(1.0, 0.93, 0.62), 22.0)
	moon_mesh = _sky_disc(Color(0.88, 0.92, 1.0), 14.0)
	# clouds
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.albedo_color = Color(1, 1, 1, 0.92)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(18):
		var cloud := Node3D.new()
		cloud.position = Vector3(rng.randf_range(-650, 650), rng.randf_range(95, 150), rng.randf_range(-550, 550))
		for k in range(5):
			var puff := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = rng.randf_range(14, 26)
			pm.height = pm.radius * 1.1
			pm.radial_segments = 8
			pm.rings = 4
			puff.mesh = pm
			puff.material_override = cloud_mat
			puff.position = Vector3(k * 20.0 - 40.0, rng.randf_range(-3, 5), rng.randf_range(-8, 8))
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(puff)
		add_child(cloud)
		cloud_nodes.append(cloud)

func _sky_disc(col: Color, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

# ---------------------------------------------------------------- roads + buildings
const WALLS := ["d9c7a3", "c9b48a", "e6d8bb", "b89f7a", "d8b49a", "c7a58a", "e7ddc8", "cdbf9f", "a89577", "d3c1ae", "bfa88f", "e1cfb0", "c58f6b", "d6a67a", "9fb5b5", "b9c4a6", "e2b9a0", "c9d3d8"]
const SIGN_COLORS := ["c8102e", "6a1b9a", "00704a", "d4a017", "1565c0", "e65100", "ad1457", "263238", "2e7d32", "f9a825"]
const STORES := [["BinDawood", "بن داود"], ["stc", "stc"], ["McDonald's", "ماكدونالدز"], ["Starbucks", "ستاربكس"], ["Al Baik", "البيك"], ["Nahdi Pharmacy", "صيدلية النهدي"], ["Panda", "بنده"], ["Al Rajhi Bank", "مصرف الراجحي"], ["Jarir Bookstore", "مكتبة جرير"], ["Bakery", "مخبز"], ["Zamzam Perfumes", "عطور زمزم"], ["Dates & Sweets", "تمور وحلويات"], ["Pharmacy", "صيدلية"], ["Laundry", "مغسلة"], ["Barber", "حلاق"], ["Mobile Shop", "جوالات"], ["Restaurant", "مطعم"], ["Supermarket", "سوبرماركت"], ["Gold Souq", "سوق الذهب"], ["Cafe", "مقهى"]]
const HOTELS := [["Makkah Towers Hotel", "فندق أبراج مكة"], ["Zamzam Hotel", "فندق زمزم"], ["Al Safwah Hotel", "فندق الصفوة"], ["Elaf Hotel", "فندق إيلاف"], ["Al Marwa Hotel", "فندق المروة"], ["Dar Al Salam Hotel", "فندق دار السلام"], ["Al Aziziyah Suites", "أجنحة العزيزية"]]

func _grid_key(p: Vector2, cell: float) -> Vector2i:
	return Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))

func _add_road(a: Vector2, b: Vector2, w: float) -> void:
	var idx := roads.size()
	roads.append([a, b, w])
	var steps := int(a.distance_to(b) / 8.0) + 1
	for s in range(steps + 1):
		var p := a.lerp(b, float(s) / float(steps))
		var c := _grid_key(p, 24.0)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k := Vector2i(c.x + dx, c.y + dz)
				if not road_grid.has(k):
					road_grid[k] = []
				var lst: Array = road_grid[k]
				if not lst.has(idx):
					lst.append(idx)

func _road_visual(a: Vector2, b: Vector2, w: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.5:
		return
	var mid := (a + b) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(mid.x, 0, mid.y))
	_bb(xf, Vector3(0, 0.015, 0), Vector3(w, 0.05, length + 0.8), "tex:asphalt")
	for side in [-1.0, 1.0]:
		_bb(xf, Vector3(side * (w * 0.5 + 1.0), 0.0, 0), Vector3(1.8, 0.1, length + 0.5), "tex:sidewalk")
		_bb(xf, Vector3(side * (w * 0.5 - 0.3), 0.046, 0), Vector3(0.12, 0.012, length), "c:f0eac4")
	if w >= 11.0:
		for off in [-0.14, 0.14]:
			_bb(xf, Vector3(off, 0.046, 0), Vector3(0.1, 0.012, length), "c:e6b800")
		for j in range(int(length / 9.0)):
			for lane in [-w * 0.25, w * 0.25]:
				_bb(xf, Vector3(lane, 0.046, -length * 0.5 + 5.0 + j * 9.0), Vector3(0.13, 0.012, 3.2), "c:f0f0f0")
	else:
		for j in range(int(length / 8.0)):
			_bb(xf, Vector3(0, 0.046, -length * 0.5 + 4.0 + j * 8.0), Vector3(0.13, 0.012, 3.0), "c:e8d9a0")
	if length > 50.0:
		for s in range(-4, 5):
			_bb(xf, Vector3(s * 1.0, 0.047, 0), Vector3(0.5, 0.012, 3.2), "c:f4f4f4")

func _create_roads_and_city() -> void:
	for road in MapData.ROADS:
		var w: float = road[0]
		var pts: Array = road[1]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			_add_road(a, b, w)
			_road_visual(a, b, w)
	# lamps, trees, buildings
	var excl: Array = [[Vector2(0, 0), 92.0], [Vector2(-20, 85), 40.0]]
	for seg in roads:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var w: float = seg[2]
		var length := a.distance_to(b)
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var mid := (a + b) * 0.5
		var near_city := mid.length() < 300.0
		var spacing := 20.0 if near_city else 46.0
		var lamp_count := int(length / 26.0)
		for j in range(lamp_count):
			var p := a + d * ((float(j) + 0.5) * length / maxf(float(lamp_count), 1.0))
			var lp := p + n * (w * 0.5 + 2.2)
			if _in_excl(lp, excl):
				continue
			_lamp(lp, atan2(n.x, n.y))
			if j % 2 == 1:
				var bp := lp + d * 1.8 - n * 0.4
				_wb(Vector3(bp.x, 0.5, bp.y), Vector3(0.6, 1.0, 0.6), "c:2f5d3a")
			elif near_city and j % 4 == 2:
				var bn := lp + d * 1.8 - n * 0.2
				var bxf := Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(bn.x, 0, bn.y))
				_bb(bxf, Vector3(0, 0.45, 0), Vector3(1.7, 0.1, 0.5), "c:6b4a2b")
				_bb(bxf, Vector3(0, 0.8, 0.22), Vector3(1.7, 0.45, 0.06), "c:6b4a2b")
			if j % 2 == 0 and near_city:
				var tp := p - n * (w * 0.5 + 2.7)
				if not _in_excl(tp, excl):
					_tree(tp)
		var slots := int(length / spacing)
		for j in range(slots):
			for side_v in [-1.0, 1.0]:
				var side: float = side_v
				if rng.randf() < (0.1 if near_city else 0.6):
					continue
				var wd := snappedf(rng.randf_range(8.0, 13.0), 0.5)
				var dp := snappedf(rng.randf_range(9.0, 12.0), 0.5)
				var center := a + d * (spacing * 0.5 + float(j) * spacing + (length - float(slots) * spacing) * 0.5) + n * side * (w * 0.5 + 4.4 + dp * 0.5)
				if absf(center.x) > WORLD_HALF.x - 18.0 or absf(center.y) > WORLD_HALF.y - 18.0:
					continue
				if _in_excl(center, excl):
					continue
				if _hits_road(center, w):
					continue
				var bk := _grid_key(center, 20.0)
				var overlap := false
				for ddx in range(-1, 2):
					for ddz in range(-1, 2):
						var kk := Vector2i(bk.x + ddx, bk.y + ddz)
						if building_grid.has(kk):
							for other in building_grid[kk]:
								var oc: Vector2 = other
								if absf(oc.x - center.x) < 12.5 and absf(oc.y - center.y) < 12.5:
									overlap = true
				if overlap:
					continue
				if not building_grid.has(bk):
					building_grid[bk] = []
				building_grid[bk].append(center)
				var toward: Vector2 = -n * side
				_building(center, atan2(-toward.x, -toward.y), wd, dp, near_city)
	_direction_signs()

func _in_excl(p: Vector2, excl: Array) -> bool:
	if absf(p.x) < 82.0 and absf(p.y) < 68.0:
		return true
	for e in excl:
		var c: Vector2 = e[0]
		var r: float = e[1]
		if p.distance_to(c) < r:
			return true
	return false

func _hits_road(center: Vector2, own_w: float) -> bool:
	var k := _grid_key(center, 24.0)
	if not road_grid.has(k):
		return false
	for idx in road_grid[k]:
		var seg: Array = roads[idx]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var w: float = seg[2]
		var q := Geometry2D.get_closest_point_to_segment(center, a, b)
		if center.distance_to(q) < w * 0.5 + 8.2:
			return true
	return false

func _building(center: Vector2, theta: float, wd: float, dp: float, near_city: bool) -> void:
	var hotel := near_city and rng.randf() < 0.22
	var h: float
	if hotel:
		h = snappedf(rng.randf_range(24.0, 48.0), 3.0)
	elif near_city:
		h = snappedf(rng.randf_range(9.0, 22.0), 3.0)
	else:
		h = snappedf(rng.randf_range(4.0, 10.0), 3.0)
	var pos := Vector3(center.x, 0, center.y)
	var xf := Transform3D(Basis(Vector3.UP, theta), pos)
	var wall: String = "w:" + str(WALLS[rng.randi_range(0, WALLS.size() - 1)])
	if hotel:
		wall = "w:" + ["e8e1d2", "cfd8dc", "d7ccc8", "e0d4b8"][rng.randi_range(0, 3)]
	_bb(xf, Vector3(0, h * 0.5, 0), Vector3(wd, h, dp), wall)
	_solid(pos + Vector3(0, h * 0.5, 0), Vector3(wd, h, dp), theta)
	_bb(xf, Vector3(0, h + 0.17, 0), Vector3(wd + 0.5, 0.35, dp + 0.5), "c:8c8170")
	_bb(xf, Vector3(0, 1.5, -dp * 0.5 - 0.04), Vector3(wd - 1.6, 2.5, 0.12), "win_lit")
	var sign_hex: String = SIGN_COLORS[rng.randi_range(0, SIGN_COLORS.size() - 1)]
	_bb(xf, Vector3(0, 3.35, -dp * 0.5 - 0.12), Vector3(minf(wd - 1.0, 8.0), 1.0, 0.2), "e:" + sign_hex)
	var floors := int(h / 3.2)
	for f in range(1, floors):
		var y := float(f) * 3.2
		_bb(xf, Vector3(0, y, -dp * 0.5 - 0.1), Vector3(wd + 0.2, 0.12, 0.4), "c:8c8170")
		for wx in [-wd * 0.28, 0.0, wd * 0.28]:
			var key := "win_lit" if rng.randf() < 0.6 else "win_dark"
			_bb(xf, Vector3(wx, y + 1.7, -dp * 0.5 - 0.04), Vector3(1.3, 1.5, 0.1), key)
	_bb(xf, Vector3(0, 2.95, -dp * 0.5 - 0.75), Vector3(wd - 1.2, 0.12, 1.4), "c:" + sign_hex)
	if floors >= 2:
		for f2 in range(1, floors):
			if rng.randf() < 0.3:
				var bx := wd * 0.28 if rng.randf() < 0.5 else -wd * 0.28
				var by := float(f2) * 3.2
				_bb(xf, Vector3(bx, by + 0.1, -dp * 0.5 - 0.5), Vector3(2.2, 0.14, 1.0), "c:8c8170")
				_bb(xf, Vector3(bx, by + 0.65, -dp * 0.5 - 0.98), Vector3(2.2, 0.8, 0.05), "c:3d4549")
			elif rng.randf() < 0.25:
				_bb(xf, Vector3(wd * 0.12, float(f2) * 3.2 + 0.6, -dp * 0.5 - 0.25), Vector3(0.7, 0.5, 0.4), "c:e8e8e8")
	if rng.randf() < 0.7:
		_bb(xf, Vector3(wd * 0.25, h + 1.0, dp * 0.2), Vector3(1.6, 1.4, 1.6), "c:3a3f44")
		_bb(xf, Vector3(-wd * 0.25, h + 0.6, -dp * 0.1), Vector3(1.0, 0.8, 1.0), "c:9a9a96")
	# facade text (only drawn when close)
	var nm: Array
	if hotel:
		nm = HOTELS[rng.randi_range(0, HOTELS.size() - 1)]
	else:
		nm = STORES[rng.randi_range(0, STORES.size() - 1)]
	var lp := xf * Vector3(0, 3.35, -dp * 0.5 - 0.27)
	_label(self, "%s\n%s" % [nm[0], nm[1]], lp, 0.0085, Color(1, 1, 1), 70.0, theta + PI)
	# dark alley beside the building: floor strip, bin, no lights
	if rng.randf() < 0.5:
		var ap := xf * Vector3(wd * 0.5 + 1.6, 0, 0)
		var axf := Transform3D(Basis(Vector3.UP, theta), ap)
		_bb(axf, Vector3(0, 0.01, 0), Vector3(2.6, 0.05, dp + 3.0), "c:1d1f21")
		if rng.randf() < 0.6:
			_bb(axf, Vector3(0.6, 0.55, dp * 0.3), Vector3(1.0, 1.1, 1.4), "c:2f5d3a")
			var bp := axf * Vector3(0.6, 0.55, dp * 0.3)
			_solid(bp, Vector3(1.0, 1.1, 1.4), theta)

func _lamp(p: Vector2, face: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, face), Vector3(p.x, 0, p.y))
	_bb(xf, Vector3(0, 3.2, 0), Vector3(0.18, 6.4, 0.18), "c:3d4549")
	_bb(xf, Vector3(0, 6.3, -0.6), Vector3(0.15, 0.12, 1.35), "c:3d4549")
	_bb(xf, Vector3(0, 6.2, -1.15), Vector3(0.4, 0.08, 0.55), "e:fff0b8")
	_solid(Vector3(p.x, 3.2, p.y), Vector3(0.3, 6.4, 0.3))
	lamp_positions.append(xf * Vector3(0, 6.0, -1.15))

func _tree(p: Vector2) -> void:
	var pos := Vector3(p.x, 0, p.y)
	tree_positions.append(pos)
	if rng.randf() < 0.55:
		# date palm
		var hgt := rng.randf_range(6.0, 9.0)
		_wb(pos + Vector3(0, hgt * 0.5, 0), Vector3(0.36, hgt, 0.36), "c:6e5238")
		for k in range(7):
			var a := float(k) / 7.0 * TAU
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.45)
			var fr := Transform3D(b, pos + Vector3(0, hgt, 0) + Vector3(cos(a), 0, sin(a)) * 0.9)
			_batch_mesh(_bm(Vector3(0.7, 0.08, 3.4)), fr, "c:3c7a36")
			var b2 := Basis(Vector3.UP, a + 0.4) * Basis(Vector3.RIGHT, 0.95)
			_batch_mesh(_bm(Vector3(0.6, 0.07, 2.6)), Transform3D(b2, pos + Vector3(0, hgt - 0.5, 0) + Vector3(cos(a + 0.4), 0, sin(a + 0.4)) * 0.6), "c:4c8c3e")
	else:
		_wb(pos + Vector3(0, 1.6, 0), Vector3(0.38, 3.2, 0.38), "c:57391f")
		var sm := SphereMesh.new()
		sm.radius = 1.8
		sm.height = 3.2
		sm.radial_segments = 8
		sm.rings = 4
		var leaf: String = ["c:2f6b34", "c:3b7a3a", "c:4f8a3f"][rng.randi_range(0, 2)]
		_batch_mesh(sm, Transform3D(Basis.IDENTITY, pos + Vector3(0, 4.2, 0)), leaf)
		_batch_mesh(sm, Transform3D(Basis.IDENTITY, pos + Vector3(1.1, 3.7, 0.5)), leaf)
		_batch_mesh(sm, Transform3D(Basis.IDENTITY, pos + Vector3(-0.9, 3.9, -0.7)), leaf)
	_solid(pos + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5))

func _direction_signs() -> void:
	var count := 0
	for road in MapData.ROADS:
		var pts: Array = road[1]
		if pts.size() < 3:
			continue
		var p: Vector2 = pts[1]
		var w: float = road[0]
		var best := _nearest_districts(p)
		var q := p + Vector2(w * 0.5 + 3.4, 0)
		var pos := Vector3(q.x, 0, q.y)
		_wb(pos + Vector3(0, 2.6, 0), Vector3(0.2, 5.2, 0.2), "c:555b5f")
		_wb(pos + Vector3(0, 5.2, 0), Vector3(5.6, 1.7, 0.15), "c:0b6b3a")
		_wb(pos + Vector3(0, 5.2, 0), Vector3(5.8, 1.9, 0.1), "c:f2f2f2")
		_wb(pos + Vector3(0, 5.2, 0.02), Vector3(5.6, 1.7, 0.15), "c:0b6b3a")
		var text := "%s  %s\n%s  %s" % [best[0][0], best[0][1], best[1][0], best[1][1]]
		_label(self, text, pos + Vector3(0, 5.2, 0.12), 0.0105, Color.WHITE, 90.0, 0.0)
		_label(self, text, pos + Vector3(0, 5.2, -0.12), 0.0105, Color.WHITE, 90.0, PI)
		_solid(pos + Vector3(0, 2.6, 0), Vector3(0.4, 5.2, 0.4))
		count += 1

func _nearest_districts(p: Vector2) -> Array:
	var list: Array = []
	for dd in MapData.DISTRICTS:
		var pos: Vector2 = dd[2]
		list.append([p.distance_to(pos), dd[0], dd[1]])
	list.sort_custom(func(x, y): return x[0] < y[0])
	return [[list[0][1], list[0][2]], [list[1][1], list[1][2]]]

func _district_at(p: Vector2) -> Array:
	return _nearest_districts(p)[0]

# ---------------------------------------------------------------- Al Haram + clock tower
func _create_haram() -> void:
	_wb(Vector3(0, 0.03, 0), Vector3(160, 0.06, 130), "c:e8e2d2")
	_wb(Vector3(0, 7.0, 0), Vector3(84, 14, 64), "w:e9dfc6")
	_wb(Vector3(0, 14.3, 0), Vector3(86, 0.6, 66), "c:b8ad96")
	_solid(Vector3(0, 7.0, 0), Vector3(84, 14, 64))
	for i in range(-9, 10):
		for zs in [-32.15, 32.15]:
			_wb(Vector3(i * 4.4, 5.0, zs), Vector3(2.6, 6.0, 0.3), "c:3b3326")
			_wb(Vector3(i * 4.4, 8.4, zs), Vector3(3.2, 0.5, 0.35), "c:cfc6ae")
	for i in range(-6, 7):
		for xs in [-42.15, 42.15]:
			_wb(Vector3(xs, 5.0, i * 4.4), Vector3(0.3, 6.0, 2.6), "c:3b3326")
	var sm := SphereMesh.new()
	sm.radius = 9.0
	sm.height = 18.0
	sm.radial_segments = 16
	sm.rings = 8
	_batch_mesh(sm, Transform3D(Basis.IDENTITY, Vector3(0, 14.5, 0)), "c:d9d4c6")
	for sx in [-20.0, 20.0]:
		_batch_mesh(sm, Transform3D(Basis.IDENTITY.scaled(Vector3(0.6, 0.6, 0.6)), Vector3(sx, 14.5, 0)), "c:d9d4c6")
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.9
	cyl.height = 56.0
	cyl.radial_segments = 10
	var tip := SphereMesh.new()
	tip.radius = 1.6
	tip.height = 3.2
	tip.radial_segments = 8
	tip.rings = 4
	for cx in [-44.0, 44.0]:
		for cz in [-34.0, 34.0]:
			_batch_mesh(cyl, Transform3D(Basis.IDENTITY, Vector3(cx, 28.0, cz)), "c:efe7d3")
			_batch_mesh(tip, Transform3D(Basis.IDENTITY, Vector3(cx, 57.0, cz)), "c:d4a53a")
			_solid(Vector3(cx, 28.0, cz), Vector3(3.6, 56.0, 3.6))
	_label(self, "Al Masjid Al Haram\nالمسجد الحرام", Vector3(0, 11.0, -32.4), 0.03, Color(0.15, 0.12, 0.05), 400.0, PI)
	_label(self, "Al Masjid Al Haram\nالمسجد الحرام", Vector3(0, 11.0, 32.4), 0.03, Color(0.15, 0.12, 0.05), 400.0, 0.0)
	# Clock tower
	var tp := Vector3(-20, 0, 85)
	_wb(tp + Vector3(0, 8, 0), Vector3(30, 16, 30), "c:cdbf9f")
	_wb(tp + Vector3(0, 60, 0), Vector3(16, 120, 16), "c:d8cdb2")
	_solid(tp + Vector3(0, 60, 0), Vector3(30, 120, 30))
	_wb(tp + Vector3(0, 104, 0), Vector3(24, 24, 24), "c:e6e0cf")
	_wb(tp + Vector3(0, 125, 0), Vector3(14, 14, 14), "c:cdbf9f")
	_wb(tp + Vector3(0, 142, 0), Vector3(2.0, 22, 2.0), "c:d4a53a")
	for face in range(4):
		var ang := float(face) * PI * 0.5
		var fx := Transform3D(Basis(Vector3.UP, ang), tp + Vector3(0, 104, 0))
		_bb(fx, Vector3(0, 0, -12.2), Vector3(17, 17, 0.4), "c:f8f8f4")
		_bb(fx, Vector3(0, 2.4, -12.5), Vector3(0.5, 5.0, 0.3), "c:202020")
		_bb(fx, Vector3(1.6, 0, -12.5), Vector3(3.4, 0.5, 0.3), "c:202020")
	_label(self, "Abraj Al Bait\nأبراج البيت", tp + Vector3(0, 15, -15.2), 0.03, Color.WHITE, 300.0, PI)
	# parking sign
	_label(self, "Haram Parking  مواقف الحرم   P", Vector3(95, 4, 0), 0.02, Color(0.4, 0.7, 1.0), 150.0, -PI * 0.5)

# ---------------------------------------------------------------- people
const TOPS := [["White thobe", "f4f1e8", 0], ["Black thobe", "1d1f24", 0], ["Cream thobe", "d9c9a0", 0], ["Blue shirt", "3a6ea5", 1], ["Red shirt", "b03a2e", 1], ["Green jacket", "3e6b4a", 1]]
const BOTTOMS := [["Dark jeans", "2b3a55"], ["Khaki", "b5a278"], ["Black pants", "1c1c1e"], ["Grey pants", "6b6f75"]]
const SHOES := [["White sneakers", "f2f2f2"], ["Black shoes", "151515"], ["Brown sandals", "7a5230"], ["Red sneakers", "b3261e"]]
const HEADS := [["No head wear", ""], ["White ghutra", "f6f6f2"], ["Red ghutra", "c0392b"], ["Black cap", "1b1b1b"], ["White kufi", "ecece6"]]
const GLASSES := [["No glasses", false], ["Sunglasses", true]]

func _pm(spec: String) -> StandardMaterial3D:
	if spec.begins_with("p:") or spec.begins_with("e:") or spec.begins_with("flash") or spec.begins_with("win"):
		return _get_mat(spec)
	return _get_mat("c:" + spec)

func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, hex: String) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _pm(hex)
	n.position = pos
	parent.add_child(n)
	return n

func _bxm(parent: Node3D, pos: Vector3, size: Vector3, hex: String) -> MeshInstance3D:
	return _mi(parent, _bm(size), pos, hex)

# Builds a stylised person. o = outfit dictionary. Returns root; limbs stored in meta for walking animation.
func _human(parent: Node3D, child_size: bool, o: Dictionary) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.scale = Vector3.ONE * (0.8 if child_size else 1.0)
	var top: Array = TOPS[int(o["top"])]
	var top_hex: String = top[1]
	var is_thobe: bool = int(top[2]) == 0
	var skin := "b27d58"
	var bottom_hex: String = BOTTOMS[int(o["bottom"])][1]
	var shoe_hex: String = SHOES[int(o["shoes"])][1]
	var female: bool = o.has("female") and bool(o["female"])
	if female:
		top_hex = "15151a"
		is_thobe = true
	# torso
	_bxm(root, Vector3(0, 1.22, 0), Vector3(0.52, 0.62, 0.30), top_hex)
	# legs (pivoted at hip for walking)
	var legs: Array = []
	for lx in [-0.13, 0.13]:
		var pivot := Node3D.new()
		pivot.position = Vector3(lx, 0.90, 0)
		root.add_child(pivot)
		var leg_hex := top_hex if is_thobe else bottom_hex
		_bxm(pivot, Vector3(0, -0.40, 0), Vector3(0.20, 0.80, 0.22), leg_hex)
		_bxm(pivot, Vector3(0, -0.84, -0.05), Vector3(0.22, 0.12, 0.34), shoe_hex)
		legs.append(pivot)
	if is_thobe:
		var skirt := CylinderMesh.new()
		skirt.top_radius = 0.27
		skirt.bottom_radius = 0.36
		skirt.height = 0.95
		skirt.radial_segments = 12
		_mi(root, skirt, Vector3(0, 0.62, 0), top_hex)
	# arms (pivoted at shoulder)
	var arms: Array = []
	for ax in [-0.37, 0.37]:
		var pv := Node3D.new()
		pv.position = Vector3(ax, 1.48, 0)
		root.add_child(pv)
		_bxm(pv, Vector3(0, -0.30, 0), Vector3(0.14, 0.60, 0.16), top_hex)
		_bxm(pv, Vector3(0, -0.64, 0), Vector3(0.12, 0.12, 0.13), skin)
		arms.append(pv)
	# head
	var head := SphereMesh.new()
	head.radius = 0.19
	head.height = 0.38
	head.radial_segments = 14
	head.rings = 8
	_mi(root, head, Vector3(0, 1.74, 0), skin)
	_bxm(root, Vector3(0, 1.58, 0), Vector3(0.10, 0.10, 0.10), skin)
	_bxm(root, Vector3(0, 1.72, -0.19), Vector3(0.05, 0.08, 0.06), "9d6b49")
	for ex in [-0.07, 0.07]:
		_bxm(root, Vector3(ex, 1.78, -0.175), Vector3(0.045, 0.03, 0.02), "151515")
	for ex2 in [-0.19, 0.19]:
		_bxm(root, Vector3(ex2, 1.74, 0), Vector3(0.03, 0.09, 0.06), skin)
	var hair_hex := "1b1410"
	var head_style: int = int(o["head"])
	if female:
		head_style = -1
		var hij := SphereMesh.new()
		hij.radius = 0.215
		hij.height = 0.46
		hij.radial_segments = 12
		hij.rings = 6
		_mi(root, hij, Vector3(0, 1.74, 0.02), "15151a")
		_bxm(root, Vector3(0, 1.74, -0.2), Vector3(0.22, 0.2, 0.05), skin)
	elif head_style == 1 or head_style == 2:
		var gh := SphereMesh.new()
		gh.radius = 0.235
		gh.height = 0.40
		gh.radial_segments = 12
		gh.rings = 6
		_mi(root, gh, Vector3(0, 1.83, 0.02), str(HEADS[head_style][1]))
		_bxm(root, Vector3(0, 1.74, 0.19), Vector3(0.40, 0.34, 0.08), str(HEADS[head_style][1]))
		var ring := TorusMesh.new()
		ring.inner_radius = 0.20
		ring.outer_radius = 0.235
		ring.rings = 12
		ring.ring_segments = 6
		_mi(root, ring, Vector3(0, 1.86, 0.01), "111111")
	elif head_style == 3 or head_style == 4:
		var cap := SphereMesh.new()
		cap.radius = 0.20
		cap.height = 0.22 if head_style == 4 else 0.26
		cap.radial_segments = 12
		cap.rings = 4
		_mi(root, cap, Vector3(0, 1.88, 0), str(HEADS[head_style][1]))
		if head_style == 3:
			_bxm(root, Vector3(0, 1.84, -0.22), Vector3(0.26, 0.03, 0.14), "1b1b1b")
	else:
		var hair := SphereMesh.new()
		hair.radius = 0.20
		hair.height = 0.2
		hair.radial_segments = 10
		hair.rings = 4
		_mi(root, hair, Vector3(0, 1.88, 0.01), hair_hex)
	if bool(GLASSES[int(o["glasses"])][1]) and not female:
		_bxm(root, Vector3(0, 1.78, -0.2), Vector3(0.36, 0.06, 0.03), "0a0a0a")
	root.set_meta("legs", legs)
	root.set_meta("arms", arms)
	return root

func _animate_walker(vis: Node3D, clock: float, moving: bool) -> void:
	if not is_instance_valid(vis):
		return
	var legs: Array = vis.get_meta("legs")
	var arms: Array = vis.get_meta("arms")
	var swing := sin(clock) * 0.55 if moving else 0.0
	if legs.size() == 2:
		legs[0].rotation.x = swing
		legs[1].rotation.x = -swing
	if arms.size() == 2:
		arms[0].rotation.x = -swing * 0.8
		arms[1].rotation.x = swing * 0.8
	vis.position.y = absf(sin(clock)) * 0.03 if moving else 0.0

func _random_outfit() -> Dictionary:
	var female := rng.randf() < 0.3
	return {"top": rng.randi_range(0, 5), "bottom": rng.randi_range(0, 3), "shoes": rng.randi_range(0, 3), "head": rng.randi_range(0, 4), "glasses": rng.randi_range(0, 1) if rng.randf() < 0.3 else 0, "female": female}

func _actor(pos: Vector3, o: Dictionary, is_child: bool) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 3
	add_child(body)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.5 if is_child else 1.8
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.75 if is_child else 0.9
	body.add_child(collider)
	var vis := _human(body, is_child, o)
	body.set_meta("visual", vis)
	return body

func _create_player() -> void:
	player = _actor(Vector3(MapData.START_POS.x, 0.05, MapData.START_POS.y), outfit, true)
	player_visual = player.get_meta("visual")

func _rebuild_player_visual() -> void:
	if is_instance_valid(player_visual):
		player_visual.queue_free()
	player_visual = _human(player, true, outfit)
	player.set_meta("visual", player_visual)

func _create_npcs() -> void:
	var people_stream := _loop_wav("res://audio/people.wav")
	var n_npc := 44
	for i in range(n_npc):
		var si := rng.randi_range(0, roads.size() - 1)
		var seg: Array = roads[si]
		var t := rng.randf()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := _sidewalk_point(seg, t, side)
		var npc := _actor(Vector3(p.x, 0.05, p.y), _random_outfit(), rng.randf() < 0.18)
		npc_list.append(npc)
		npc_seg.append(si)
		npc_t.append(t)
		npc_dir.append(1.0 if rng.randf() < 0.5 else -1.0)
		npc_side.append(side)
		npc_speed.append(rng.randf_range(0.9, 1.5))
		npc_clock.append(rng.randf() * 6.0)
		if i % 3 == 0 and people_stream != null:
			var voice := AudioStreamPlayer3D.new()
			voice.stream = people_stream
			voice.unit_size = 4.0
			voice.max_distance = 24.0
			voice.volume_db = -8.0
			voice.pitch_scale = rng.randf_range(0.85, 1.2)
			npc.add_child(voice)
			voice.play(rng.randf() * 5.0)

func _sidewalk_point(seg: Array, t: float, side: float) -> Vector2:
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var w: float = seg[2]
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return a.lerp(b, t) + n * side * (w * 0.5 + 1.0)

func _update_npcs(delta: float) -> void:
	for i in range(npc_list.size()):
		var npc: CharacterBody3D = npc_list[i]
		var seg: Array = roads[npc_seg[i]]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var length := a.distance_to(b)
		var t_target: float = clampf(float(npc_t[i]) + float(npc_dir[i]) * 3.0 / maxf(length, 1.0), 0.0, 1.0)
		var tp := _sidewalk_point(seg, t_target, float(npc_side[i]))
		var to := Vector3(tp.x, npc.position.y, tp.y) - npc.position
		var moving := true
		if to.length() < 0.6:
			npc_t[i] = t_target
			if t_target <= 0.001 or t_target >= 0.999:
				# at a road end: switch to a nearby road or turn around
				var end_pt := a if t_target <= 0.001 else b
				var found := -1
				for k in range(roads.size()):
					if k == npc_seg[i]:
						continue
					var s2: Array = roads[k]
					var a2: Vector2 = s2[0]
					var b2: Vector2 = s2[1]
					if a2.distance_to(end_pt) < 2.0:
						found = k
						npc_t[i] = 0.0
						npc_dir[i] = 1.0
						break
					if b2.distance_to(end_pt) < 2.0:
						found = k
						npc_t[i] = 1.0
						npc_dir[i] = -1.0
						break
				if found >= 0 and rng.randf() < 0.7:
					npc_seg[i] = found
				else:
					npc_dir[i] = -float(npc_dir[i])
		else:
			var v := to.normalized() * float(npc_speed[i])
			# stop for traffic or the player's car close ahead
			for c in all_cars:
				var off: Vector3 = (c as Node3D).position - npc.position
				if off.length() < 4.5 and off.dot(v.normalized()) > 0.0 and absf(float(c.velocity.length())) > 1.0:
					moving = false
			if moving:
				npc.velocity = Vector3(v.x, -2.0, v.z)
				npc.move_and_slide()
				npc.rotation.y = lerp_angle(npc.rotation.y, atan2(-v.x, -v.z), delta * 6.0)
				npc_clock[i] = float(npc_clock[i]) + delta * 7.0 * float(npc_speed[i])
		_animate_walker(npc.get_meta("visual"), float(npc_clock[i]), moving)

# ---------------------------------------------------------------- vehicles
# kind: 0 sedan, 1 SUV, 2 pickup, 3 van, 4 bus, 5 truck, 6 hatchback, 7 taxi, 8 police
const MAKES := [["TOYOTA", 0], ["LEXUS", 1], ["HYUNDAI", 2], ["KIA", 3], ["NISSAN", 4], ["FORD", 5], ["GMC", 6], ["CHEVROLET", 7], ["MERCEDES", 8], ["HONDA", 9]]
const CAR_COLORS := ["eeeeea", "1f262e", "b9bbbe", "a3201c", "d6bb7a", "2d6073", "4a4f55", "f2f2f2", "3b4a2f", "7a1f2b"]

func _emblem(parent: Node3D, kind: int, pos: Vector3, face_z: float) -> void:
	# simple original badge shapes, one per make
	var chrome := "c9ced2"
	match kind:
		0:
			for dx in [-0.07, 0.0, 0.07]:
				var oval := CylinderMesh.new()
				oval.top_radius = 0.035
				oval.bottom_radius = 0.035
				oval.height = 0.02
				var m := _mi(parent, oval, pos + Vector3(dx, 0, 0), chrome)
				m.rotation.x = PI * 0.5
		1:
			_bxm(parent, pos, Vector3(0.14, 0.09, 0.02), chrome)
		2:
			_bxm(parent, pos + Vector3(-0.05, 0, 0), Vector3(0.025, 0.1, 0.02), chrome)
			_bxm(parent, pos + Vector3(0.05, 0, 0), Vector3(0.025, 0.1, 0.02), chrome)
			_bxm(parent, pos, Vector3(0.1, 0.025, 0.02), chrome)
		3:
			_bxm(parent, pos, Vector3(0.22, 0.04, 0.02), chrome)
		4:
			var ring := TorusMesh.new()
			ring.inner_radius = 0.05
			ring.outer_radius = 0.07
			ring.rings = 12
			ring.ring_segments = 5
			var rm := _mi(parent, ring, pos, chrome)
			rm.rotation.x = PI * 0.5
			_bxm(parent, pos, Vector3(0.2, 0.03, 0.02), chrome)
		5:
			_bxm(parent, pos, Vector3(0.2, 0.1, 0.02), "123a7a")
		6:
			_bxm(parent, pos, Vector3(0.16, 0.06, 0.02), "c0392b")
		7:
			var bt := _bxm(parent, pos, Vector3(0.2, 0.06, 0.02), "d4a53a")
			bt.rotation.z = 0.0
		8:
			var star := TorusMesh.new()
			star.inner_radius = 0.06
			star.outer_radius = 0.075
			star.rings = 12
			star.ring_segments = 5
			var sm := _mi(parent, star, pos, chrome)
			sm.rotation.x = PI * 0.5
		_:
			_bxm(parent, pos, Vector3(0.14, 0.14, 0.02), "b71c1c")

func _vehicle_model(parent: Node3D, color_hex: String, kind: int, make_idx: int) -> void:
	# dimensions per body type
	var L := 4.15
	var W := 1.95
	var body_h := 0.58
	var base := 0.72
	var cab_len := 2.25
	var cab_h := 0.5
	var cab_z := -0.2
	var wheel_r := 0.40
	match kind:
		1:
			L = 4.5; body_h = 0.75; base = 0.9; cab_len = 2.9; cab_h = 0.7; wheel_r = 0.45
		2:
			L = 5.1; body_h = 0.7; base = 0.9; cab_len = 1.6; cab_h = 0.65; cab_z = -0.9; wheel_r = 0.45
		3:
			L = 5.0; W = 2.0; body_h = 1.3; base = 1.1; cab_len = 3.8; cab_h = 0.8; cab_z = 0.1
		4:
			L = 11.0; W = 2.5; body_h = 2.2; base = 1.55; cab_len = 9.8; cab_h = 0.8; cab_z = 0.3; wheel_r = 0.55
		5:
			L = 7.0; W = 2.3; body_h = 1.0; base = 1.0; cab_len = 1.8; cab_h = 1.0; cab_z = -2.4; wheel_r = 0.55
		6:
			L = 3.7; body_h = 0.55; cab_len = 2.1; cab_h = 0.55
	var chassis_z := 0.0
	_bxm(parent, Vector3(0, base, chassis_z), Vector3(W, body_h, L), "p:" + color_hex)
	var glass := "26414f"
	var cab_hex := glass
	if kind == 4 or kind == 3:
		cab_hex = "2b4a5a"
	_bxm(parent, Vector3(0, base + body_h * 0.5 + cab_h * 0.5, cab_z), Vector3(W - 0.22, cab_h, cab_len), cab_hex)
	_bxm(parent, Vector3(0, base + body_h * 0.5 + cab_h + 0.04, cab_z), Vector3(W - 0.3, 0.08, cab_len - 0.2), "p:" + color_hex)
	if kind == 5:
		_bxm(parent, Vector3(0, base + 1.0, 1.4), Vector3(W, 2.0, 3.6), "d8d8d2")
	if kind == 2:
		_bxm(parent, Vector3(0, base + 0.45, 1.5), Vector3(W - 0.1, 0.12, 2.0), "2b2b2b")
	# lights
	var front_z := -L * 0.5 - 0.02
	var rear_z := L * 0.5 + 0.02
	for x in [-W * 0.36, W * 0.36]:
		_bxm(parent, Vector3(x, base + 0.05, front_z), Vector3(0.42, 0.2, 0.08), "e:fff4c2")
		_bxm(parent, Vector3(x, base + 0.05, rear_z), Vector3(0.4, 0.18, 0.08), "e:e01b12")
	# mirrors, door seams, roof rails
	for mx in [-1.0, 1.0]:
		_bxm(parent, Vector3(mx * (W * 0.5 + 0.08), base + body_h * 0.5 + 0.12, cab_z - cab_len * 0.42), Vector3(0.14, 0.12, 0.22), "p:" + color_hex)
		for dz in [-0.45, 0.45]:
			_bxm(parent, Vector3(mx * (W * 0.5 + 0.005), base + 0.05, cab_z + dz * cab_len * 0.5), Vector3(0.02, body_h * 0.85, 0.03), "101214")
	if kind == 1 or kind == 3:
		for rx in [-0.65, 0.65]:
			_bxm(parent, Vector3(rx, base + body_h * 0.5 + cab_h + 0.14, cab_z), Vector3(0.05, 0.05, cab_len * 0.8), "2a2d30")
	# grille, bumpers, plate
	_bxm(parent, Vector3(0, base - 0.12, front_z - 0.02), Vector3(W * 0.5, 0.22, 0.06), "15171a")
	_bxm(parent, Vector3(0, base - 0.30, front_z), Vector3(W + 0.02, 0.2, 0.14), "1c1e21")
	_bxm(parent, Vector3(0, base - 0.30, rear_z), Vector3(W + 0.02, 0.2, 0.14), "1c1e21")
	_bxm(parent, Vector3(0, base - 0.28, rear_z + 0.09), Vector3(0.5, 0.14, 0.02), "f4f2e8")
	# wheels + rims
	var wz: Array = [-L * 0.32, L * 0.32]
	if kind == 4:
		wz = [-L * 0.33, L * 0.27]
	for x in [-W * 0.52, W * 0.52]:
		for z in wz:
			var wheel := CylinderMesh.new()
			wheel.top_radius = wheel_r
			wheel.bottom_radius = wheel_r
			wheel.height = 0.24
			wheel.radial_segments = 12
			var wn := _mi(parent, wheel, Vector3(x, wheel_r, z), "0d0e10")
			wn.rotation.z = PI * 0.5
			var rim := CylinderMesh.new()
			rim.top_radius = wheel_r * 0.58
			rim.bottom_radius = wheel_r * 0.58
			rim.height = 0.26
			rim.radial_segments = 10
			var rn := _mi(parent, rim, Vector3(x * 1.005, wheel_r, z), "b7bcc0")
			rn.rotation.z = PI * 0.5
	# make badge + name
	var make: Array = MAKES[make_idx % MAKES.size()]
	if kind < 4 or kind == 6 or kind >= 7:
		_emblem(parent, int(make[1]), Vector3(0, base - 0.12, front_z - 0.06), -1.0)
		_emblem(parent, int(make[1]), Vector3(0.5, base + 0.2, rear_z + 0.04), 1.0)
		_label(parent, str(make[0]), Vector3(-0.45, base + 0.2, rear_z + 0.05), 0.0035, Color(0.85, 0.87, 0.9), 22.0, 0.0)
	if kind == 7:
		_bxm(parent, Vector3(0, base + body_h * 0.5 + cab_h + 0.2, cab_z), Vector3(0.7, 0.22, 0.3), "f2f2f2")
		_bxm(parent, Vector3(0, base + 0.05, 0), Vector3(W + 0.01, 0.12, 1.6), "00a651")
	if kind == 8:
		_bxm(parent, Vector3(0, base + 0.1, 0), Vector3(W + 0.01, 0.18, L * 0.7), "0f5c2e")
		_bxm(parent, Vector3(-0.3, base + body_h * 0.5 + cab_h + 0.2, cab_z), Vector3(0.55, 0.16, 0.3), "flash_red")
		_bxm(parent, Vector3(0.3, base + body_h * 0.5 + cab_h + 0.2, cab_z), Vector3(0.55, 0.16, 0.3), "flash_blue")
		_label(parent, "POLICE  الشرطة", Vector3(-W * 0.5 - 0.03, base + 0.3, 0), 0.0055, Color(0.05, 0.3, 0.12), 25.0, -PI * 0.5)
		_label(parent, "POLICE  الشرطة", Vector3(W * 0.5 + 0.03, base + 0.3, 0), 0.0055, Color(0.05, 0.3, 0.12), 25.0, PI * 0.5)
	if kind == 4:
		_label(parent, "Makkah Bus  حافلة مكة", Vector3(-W * 0.5 - 0.03, base + 0.9, 0), 0.008, Color.WHITE, 40.0, -PI * 0.5)

func _vehicle_size(kind: int) -> Vector3:
	match kind:
		1: return Vector3(2.0, 1.7, 4.5)
		2: return Vector3(2.0, 1.7, 5.1)
		3: return Vector3(2.0, 2.2, 5.0)
		4: return Vector3(2.5, 3.2, 11.0)
		5: return Vector3(2.3, 2.8, 7.0)
		6: return Vector3(1.95, 1.5, 3.7)
	return Vector3(1.95, 1.5, 4.15)

func _make_vehicle(pos: Vector3, heading: float, color_hex: String, kind: int, make_idx: int) -> CharacterBody3D:
	var v := CharacterBody3D.new()
	v.position = pos
	v.rotation.y = heading
	add_child(v)
	var vsize := _vehicle_size(kind)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = vsize
	cs.shape = bs
	cs.position.y = vsize.y * 0.5 + 0.1
	v.add_child(cs)
	# the model is built with materials from the cache; "flash" boxes use the police light materials
	_vehicle_model(v, color_hex, kind, make_idx)
	return v

func _create_car() -> void:
	car = _make_vehicle(Vector3(MapData.START_POS.x + 5.0, 0.08, MapData.START_POS.y + 2.0), 0.0, "eeeeea", 0, 0)
	car.collision_layer = 1
	car.collision_mask = 3
	all_cars.append(car)
	traffic_routes.append([])
	traffic_idx.append(0)
	traffic_speeds.append(0.0)
	traffic_wait.append(0.0)
	traffic_stuck.append(0.0)
	car_kinds.append(0)
	_add_engine_sound(car)

func _add_engine_sound(v: Node3D) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = _loop_wav("res://audio/engine.wav")
	a.unit_size = 5.0
	a.max_distance = 35.0
	a.volume_db = -14.0
	v.add_child(a)
	car_sounds.append(a)

func _build_routes() -> Array:
	var routes: Array = []
	for road in MapData.ROADS:
		var pts: Array = road[1]
		if pts.size() < 2:
			continue
		var r: Array = []
		for p in pts:
			r.append(p)
		var closed: bool = (pts[0] as Vector2).distance_to(pts[pts.size() - 1]) < 1.0
		if not closed:
			# out and back, so the car turns around at the end
			for k in range(pts.size() - 2, -1, -1):
				r.append(pts[k])
		routes.append(r)
	return routes

func _create_traffic() -> void:
	var routes := _build_routes()
	var kinds := [0, 1, 0, 6, 2, 1, 3, 0, 7, 8, 1, 4, 0, 5, 6, 7, 1, 0, 8, 2, 0, 3, 1, 6, 0, 4, 7, 1, 0, 5, 8, 0, 6, 1, 3, 0]
	for i in range(kinds.size()):
		var route: Array = routes[i % routes.size()]
		var seg := rng.randi_range(0, route.size() - 2)
		var a: Vector2 = route[seg]
		var b: Vector2 = route[seg + 1]
		var t := 0.2 + rng.randf() * 0.6
		var tangent := (b - a).normalized()
		var right := Vector2(-tangent.y, tangent.x)
		var xy := a.lerp(b, t) + right * 2.4
		var heading := atan2(-tangent.x, -tangent.y)
		var kind: int = kinds[i]
		var hex: String = CAR_COLORS[rng.randi_range(0, CAR_COLORS.size() - 1)]
		if kind == 4:
			hex = "1f7a45"
		elif kind == 5:
			hex = "c9c9c4"
		elif kind == 7:
			hex = "f4f4f0"
		elif kind == 8:
			hex = "f4f4f0"
		var v := _make_vehicle(Vector3(xy.x, 0.08, xy.y), heading, hex, kind, rng.randi_range(0, 9))
		v.collision_layer = 2
		v.collision_mask = 1
		all_cars.append(v)
		traffic_routes.append(route)
		traffic_idx.append(seg)
		traffic_speeds.append(rng.randf_range(5.5, 9.0) if kind != 4 else 5.0)
		traffic_wait.append(0.0)
		traffic_stuck.append(0.0)
		car_kinds.append(kind)
		_add_engine_sound(v)

func _advance_traffic(delta: float) -> void:
	for i in range(1, all_cars.size()):
		if driving and i == active_car_index:
			continue
		var v: CharacterBody3D = all_cars[i]
		var route: Array = traffic_routes[i]
		if route.size() < 2:
			continue
		var idx: int = int(traffic_idx[i])
		var a: Vector2 = route[idx]
		var b: Vector2 = route[idx + 1]
		var tangent := (b - a).normalized()
		var right := Vector2(-tangent.y, tangent.x)
		var target2 := b + right * 2.4
		var pos2 := Vector2(v.position.x, v.position.z)
		var to := target2 - pos2
		if to.length() < 5.0 or to.dot(tangent) < 0.0:
			idx += 1
			if idx >= route.size() - 1:
				idx = 0
				var first: Vector2 = route[0]
				v.position = Vector3(first.x, 0.08, first.y)
			traffic_idx[i] = idx
			continue
		var dir2 := to.normalized()
		var forward := Vector3(dir2.x, 0.0, dir2.y)
		var rightv := Vector3(-forward.z, 0.0, forward.x)
		var blocked := false
		for j in range(all_cars.size()):
			if j == i:
				continue
			var off: Vector3 = (all_cars[j] as Node3D).position - v.position
			var ahead := off.dot(forward)
			if ahead > 0.5 and ahead < 9.0 and absf(off.dot(rightv)) < 2.4:
				blocked = true
				break
		if not blocked:
			var off_p: Vector3 = player.position - v.position
			var ahead_p := off_p.dot(forward)
			if not driving and ahead_p > 0.5 and ahead_p < 8.0 and absf(off_p.dot(rightv)) < 2.2:
				blocked = true
			if not blocked:
				for npc in npc_list:
					var off_n: Vector3 = (npc as Node3D).position - v.position
					var ahead_n := off_n.dot(forward)
					if ahead_n > 0.5 and ahead_n < 7.0 and absf(off_n.dot(rightv)) < 2.0:
						blocked = true
						break
		if blocked:
			traffic_wait[i] = float(traffic_wait[i]) + delta
			if float(traffic_wait[i]) > 6.0:
				blocked = false
				if float(traffic_wait[i]) > 8.0:
					traffic_wait[i] = 0.0
		else:
			traffic_wait[i] = 0.0
		var want := 0.0 if blocked else float(traffic_speeds[i])
		v.velocity = forward * want
		v.velocity.y = -2.0
		v.move_and_slide()
		if want > 1.0 and v.get_real_velocity().length() < 0.6:
			traffic_stuck[i] = float(traffic_stuck[i]) + delta
			if float(traffic_stuck[i]) > 6.0:
				traffic_stuck[i] = 0.0
				v.position = Vector3(target2.x, 0.08, target2.y)
		else:
			traffic_stuck[i] = 0.0
		v.rotation.y = lerp_angle(v.rotation.y, atan2(-forward.x, -forward.z), delta * 3.0)
		var snd: AudioStreamPlayer3D = car_sounds[i]
		if want > 1.0 and not snd.playing:
			snd.play(rng.randf())
		if want <= 1.0 and snd.playing:
			snd.stop()

# ---------------------------------------------------------------- audio
func _loop_wav(path: String) -> AudioStreamWAV:
	var res = load(path)
	if res == null or not (res is AudioStreamWAV):
		return null
	var w := (res as AudioStreamWAV).duplicate() as AudioStreamWAV
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(w.data.size() / 2)
	return w

var step_audio: AudioStreamPlayer
var last_step_sign := 1.0

func _create_audio() -> void:
	city_audio = AudioStreamPlayer.new()
	city_audio.stream = _loop_wav("res://audio/city.wav")
	city_audio.volume_db = -22.0
	add_child(city_audio)
	city_audio.play()
	horn_audio = AudioStreamPlayer.new()
	horn_audio.stream = load("res://audio/horn.wav")
	horn_audio.volume_db = -4.0
	add_child(horn_audio)
	step_audio = AudioStreamPlayer.new()
	step_audio.stream = load("res://audio/step.wav")
	step_audio.volume_db = -14.0
	add_child(step_audio)
	# birds near trees: every Nth tree gets its own bird emitter (max 26)
	var birds := _loop_wav("res://audio/birds.wav")
	var placed := 0
	var stride := maxi(1, int(tree_positions.size() / 26))
	for i in range(0, tree_positions.size(), stride):
		if placed >= 26 or birds == null:
			break
		var tp: Vector3 = tree_positions[i]
		var b := AudioStreamPlayer3D.new()
		b.stream = birds
		b.position = tp + Vector3(0, 5.0, 0)
		b.unit_size = 6.0
		b.max_distance = 30.0
		b.volume_db = -9.0
		b.pitch_scale = rng.randf_range(0.9, 1.25)
		add_child(b)
		b.play(rng.randf() * 5.0)
		placed += 1
	# Azan: plays only if you add a recording (audio/azan.ogg, .mp3 or .wav)
	azan_audio = AudioStreamPlayer3D.new()
	azan_audio.position = Vector3(0, 45, 0)
	azan_audio.unit_size = 60.0
	azan_audio.max_distance = 900.0
	azan_audio.volume_db = 6.0
	add_child(azan_audio)
	for p in ["res://audio/azan.ogg", "res://audio/azan.mp3", "res://audio/azan.wav"]:
		if ResourceLoader.exists(p):
			azan_audio.stream = load(p)
			break
	azan_status = "AZAN: READY" if azan_audio.stream != null else "AZAN: add audio/azan.ogg"

func _play_azan() -> void:
	if azan_audio.stream != null:
		azan_audio.play()

func _check_prayer_times(prev_t: float, now_t: float) -> void:
	for p in [4.8, 12.2, 15.6, 18.4, 19.8]:
		if prev_t < p and now_t >= p:
			_play_azan()

# ---------------------------------------------------------------- light pools
func _create_lamp_pool() -> void:
	for i in range(8):
		var l := OmniLight3D.new()
		l.omni_range = 16.0
		l.light_color = Color(1.0, 0.86, 0.55)
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lamp_pool.append(l)
	for x in [-0.65, 0.65]:
		var s := SpotLight3D.new()
		s.spot_range = 38.0
		s.spot_angle = 34.0
		s.light_energy = 0.0
		s.shadow_enabled = false
		s.position = Vector3(x, 0.95, -2.3)
		add_child(s)
		headlight_pair.append(s)
	_attach_headlights(car)

func _attach_headlights(v: Node3D) -> void:
	var offsets := [-0.65, 0.65]
	var vs := _vehicle_size(int(car_kinds[all_cars.find(v)])) if all_cars.has(v) else Vector3(2, 1.5, 4.2)
	for i in range(2):
		var s: SpotLight3D = headlight_pair[i]
		if s.get_parent() != null:
			s.get_parent().remove_child(s)
		v.add_child(s)
		s.position = Vector3(offsets[i], 0.95, -vs.z * 0.5 - 0.2)
		s.rotation = Vector3.ZERO

func _update_lamp_pool(focus: Vector3, night_factor: float) -> void:
	if night_factor < 0.05:
		for l in lamp_pool:
			(l as OmniLight3D).light_energy = 0.0
		return
	var best: Array = []   # [dist, pos]
	for lp in lamp_positions:
		var p: Vector3 = lp
		var d := p.distance_squared_to(focus)
		if d > 2500.0:
			continue
		if best.size() < lamp_pool.size():
			best.append([d, p])
			best.sort_custom(func(a, b): return a[0] < b[0])
		elif d < best[best.size() - 1][0]:
			best[best.size() - 1] = [d, p]
			best.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(lamp_pool.size()):
		var l: OmniLight3D = lamp_pool[i]
		if i < best.size():
			l.global_position = best[i][1]
			l.light_energy = 2.2 * night_factor
		else:
			l.light_energy = 0.0

# ---------------------------------------------------------------- UI
func _ui_button(parent: Control, caption: String, pos: Vector2, width: float, action: String) -> void:
	var b := Button.new()
	b.text = caption
	b.position = pos
	b.size = Vector2(width, 33)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(_ui_action.bind(action))
	parent.add_child(b)

func _ui_action(action: String) -> void:
	match action:
		"map": _toggle_map()
		"vehicles": _toggle_car()
		"clothes": _toggle_wardrobe()
		"camera": first_person = not first_person
		"night": time_of_day = 22.0 if (time_of_day < 18.0 and time_of_day > 5.0) else 10.0
		"police": _enter_nearest_car(true)
		"azan": _play_azan()
		"horn": _horn()

func _toggle_map() -> void:
	map_open = not map_open
	full_map.visible = map_open

func _horn() -> void:
	horn_audio.play()

func _create_ui() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	ui_root = Control.new()
	ui_root.size = ui_base_size
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(ui_root)
	var top := ColorRect.new()
	top.color = Color(0.02, 0.035, 0.055, 0.84)
	top.size = Vector2(960, 62)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(top)
	hud = Label.new()
	hud.position = Vector2(20, 4)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_color", Color(1, 0.80, 0.29))
	ui_root.add_child(hud)
	district_label = Label.new()
	district_label.position = Vector2(21, 34)
	district_label.add_theme_font_size_override("font_size", 14)
	ui_root.add_child(district_label)
	time_label = Label.new()
	time_label.position = Vector2(800, 6)
	time_label.add_theme_font_size_override("font_size", 18)
	ui_root.add_child(time_label)
	weather_label = Label.new()
	weather_label.position = Vector2(800, 32)
	weather_label.text = "مكة المكرمة  Makkah"
	weather_label.add_theme_font_size_override("font_size", 13)
	ui_root.add_child(weather_label)
	var left := ColorRect.new()
	left.position = Vector2(0, 64)
	left.size = Vector2(133, 318)
	left.color = Color(0.02, 0.035, 0.055, 0.78)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(left)
	var names := [["MAP / خريطة", "map"], ["VEHICLES", "vehicles"], ["CLOTHES", "clothes"], ["CAMERA", "camera"], ["DAY / NIGHT", "night"], ["POLICE CAR", "police"], ["HORN", "horn"], ["AZAN", "azan"]]
	for i in range(names.size()):
		_ui_button(ui_root, names[i][0], Vector2(5, 68 + i * 38), 122, names[i][1])
	speed_label = Label.new()
	speed_label.position = Vector2(780, 490)
	speed_label.add_theme_font_size_override("font_size", 28)
	speed_label.add_theme_color_override("font_color", Color(1, 0.86, 0.35))
	ui_root.add_child(speed_label)
	minimap = Control.new()
	minimap.set_script(load("res://minimap.gd"))
	minimap.position = Vector2(8, 386)
	minimap.size = Vector2(150, 150)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(minimap)
	minimap.set("roads", roads)
	# full map
	full_map = Control.new()
	full_map.set_script(load("res://fullmap.gd"))
	full_map.position = Vector2(150, 70)
	full_map.size = Vector2(700, 436)
	full_map.visible = false
	ui_root.add_child(full_map)
	for dd in MapData.DISTRICTS:
		var pos: Vector2 = dd[2]
		var pp := pos / MapData.MAP_SCALE + MapData.MAP_CENTER_PX
		pp = pp / MapData.MAP_SIZE_PX * full_map.size
		var box := Label.new()
		box.text = "%s\n%s" % [dd[0], dd[1]]
		box.add_theme_font_size_override("font_size", 12)
		box.add_theme_color_override("font_color", Color.WHITE)
		box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.06, 0.08, 0.88)
		st.set_corner_radius_all(4)
		st.content_margin_left = 6
		st.content_margin_right = 6
		box.add_theme_stylebox_override("normal", st)
		box.position = pp - Vector2(40, 16)
		full_map.add_child(box)
	var bottom := ColorRect.new()
	bottom.position = Vector2(140, 520)
	bottom.size = Vector2(820, 20)
	bottom.color = Color(0.02, 0.035, 0.055, 0.84)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bottom)
	var note := Label.new()
	note.text = "UP/DOWN/W/S/STICK: MOVE · LEFT/RIGHT: TURN · ENTER/A: CAR · H/X: HORN · C/Y: CAMERA · B: CLOTHES · M: MAP · N: NIGHT · Z: AZAN"
	note.position = Vector2(146, 521)
	note.add_theme_font_size_override("font_size", 10)
	ui_root.add_child(note)
	sound_status = Label.new()
	sound_status.position = Vector2(560, 8)
	sound_status.add_theme_font_size_override("font_size", 11)
	ui_root.add_child(sound_status)
	_create_wardrobe_ui()
	_create_lamp_pool()

var wardrobe_row := 0
var wardrobe_rows: Array = []

func _create_wardrobe_ui() -> void:
	wardrobe_panel = PanelContainer.new()
	wardrobe_panel.position = Vector2(560, 90)
	wardrobe_panel.custom_minimum_size = Vector2(360, 330)
	wardrobe_panel.visible = false
	ui_root.add_child(wardrobe_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	wardrobe_panel.add_child(vb)
	var title := Label.new()
	title.text = "CHANGING ROOM  |  غرفة الملابس"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vb.add_child(title)
	var cats := [["TOP", "top"], ["BOTTOM", "bottom"], ["SHOES", "shoes"], ["HEAD", "head"], ["GLASSES", "glasses"]]
	for i in range(cats.size()):
		var row := HBoxContainer.new()
		vb.add_child(row)
		var lb := Button.new()
		lb.text = "<"
		lb.focus_mode = Control.FOCUS_NONE
		lb.pressed.connect(_wardrobe_change.bind(i, -1))
		row.add_child(lb)
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(290, 36)
		lab.add_theme_font_size_override("font_size", 17)
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lab)
		var rb := Button.new()
		rb.text = ">"
		rb.focus_mode = Control.FOCUS_NONE
		rb.pressed.connect(_wardrobe_change.bind(i, 1))
		row.add_child(rb)
		wardrobe_rows.append([cats[i][0], cats[i][1], lab])
	wardrobe_info = Label.new()
	wardrobe_info.add_theme_font_size_override("font_size", 12)
	wardrobe_info.text = "UP/DOWN: choose   LEFT/RIGHT: change   B / BACK: done"
	vb.add_child(wardrobe_info)
	_refresh_wardrobe()

func _option_list(key: String) -> Array:
	match key:
		"top": return TOPS
		"bottom": return BOTTOMS
		"shoes": return SHOES
		"head": return HEADS
	return GLASSES

func _wardrobe_change(row: int, delta_i: int) -> void:
	wardrobe_row = row
	var key: String = wardrobe_rows[row][1]
	var opts := _option_list(key)
	outfit[key] = posmod(int(outfit[key]) + delta_i, opts.size())
	_rebuild_player_visual()
	_refresh_wardrobe()

func _refresh_wardrobe() -> void:
	for i in range(wardrobe_rows.size()):
		var r: Array = wardrobe_rows[i]
		var opts := _option_list(r[1])
		var lab: Label = r[2]
		var nm: String = str(opts[int(outfit[r[1]])][0])
		lab.text = ("> " if i == wardrobe_row else "   ") + str(r[0]) + ":  " + nm
		lab.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if i == wardrobe_row else Color(0.9, 0.9, 0.88))

func _toggle_wardrobe() -> void:
	if driving:
		return
	wardrobe_open = not wardrobe_open
	wardrobe_panel.visible = wardrobe_open
	if wardrobe_open:
		_refresh_wardrobe()

func _resize_ui() -> void:
	if ui_root == null:
		return
	var actual := get_viewport().get_visible_rect().size
	var factor: float = minf(actual.x / ui_base_size.x, actual.y / ui_base_size.y)
	ui_root.scale = Vector2.ONE * factor
	ui_root.position = (actual - ui_base_size * factor) * 0.5

# ---------------------------------------------------------------- input helpers
func _axis(negative: int, positive: int, joy_axis: int) -> float:
	var value := Input.get_joy_axis(0, joy_axis)
	if absf(value) < 0.18:
		value = 0.0
	return clampf(value + float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative)), -1.0, 1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not wardrobe_open:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.002, -0.75, 0.45)
	if wardrobe_open:
		_wardrobe_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_C: first_person = not first_person
			KEY_E, KEY_ENTER, KEY_KP_ENTER: _toggle_car()
			KEY_B: _toggle_wardrobe()
			KEY_N: _ui_action("night")
			KEY_M: _toggle_map()
			KEY_H: _horn()
			KEY_Z: _play_azan()
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _toggle_car()
			JOY_BUTTON_Y: first_person = not first_person
			JOY_BUTTON_B: _toggle_wardrobe()
			JOY_BUTTON_X: _horn()
			JOY_BUTTON_BACK: _toggle_map()
			JOY_BUTTON_START: _toggle_map()

func _wardrobe_input(event: InputEvent) -> void:
	var row_delta := 0
	var col_delta := 0
	var close := false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W: row_delta = -1
			KEY_DOWN, KEY_S: row_delta = 1
			KEY_LEFT, KEY_A: col_delta = -1
			KEY_RIGHT, KEY_D, KEY_ENTER, KEY_KP_ENTER: col_delta = 1
			KEY_B, KEY_ESCAPE, KEY_BACK: close = true
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: row_delta = -1
			JOY_BUTTON_DPAD_DOWN: row_delta = 1
			JOY_BUTTON_DPAD_LEFT: col_delta = -1
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A: col_delta = 1
			JOY_BUTTON_B, JOY_BUTTON_BACK: close = true
	if close:
		_toggle_wardrobe()
		return
	if row_delta != 0:
		wardrobe_row = posmod(wardrobe_row + row_delta, wardrobe_rows.size())
		_refresh_wardrobe()
	if col_delta != 0:
		_wardrobe_change(wardrobe_row, col_delta)

# ---------------------------------------------------------------- day / night
func _update_time(delta: float) -> void:
	var prev := time_of_day
	time_of_day = fposmod(time_of_day + delta * 0.035, 24.0)
	if time_of_day > prev:
		_check_prayer_times(prev, time_of_day)
	var a := (time_of_day - 6.0) / 24.0 * TAU
	var sun_dir := Vector3(cos(a), sin(a), 0.35).normalized()
	var moon_dir := Vector3(-sun_dir.x, -sun_dir.y, sun_dir.z).normalized()
	var daylight := clampf(sin(a) * 2.0, 0.0, 1.0)
	var night_factor := 1.0 - clampf(daylight * 3.0, 0.0, 1.0)
	sun_light.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	moon_light.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	sun_light.light_energy = 0.05 + daylight * 1.2
	sun_light.visible = sun_dir.y > -0.08
	moon_light.light_energy = clampf(moon_dir.y, 0.0, 1.0) * 0.55
	moon_light.visible = moon_dir.y > 0.0
	var dusk := clampf(1.0 - absf(daylight - 0.22) * 4.0, 0.0, 1.0) * clampf(daylight * 10.0, 0.0, 1.0)
	var sky := Color(0.03, 0.05, 0.11).lerp(Color(0.65, 0.79, 0.91), daylight)
	sky = sky.lerp(Color(0.95, 0.52, 0.30), dusk * 0.45)
	city_environment.background_color = sky
	var top_c := Color(0.02, 0.04, 0.10).lerp(Color(0.22, 0.47, 0.83), daylight)
	var hor_c := Color(0.05, 0.08, 0.15).lerp(Color(0.74, 0.85, 0.95), daylight)
	hor_c = hor_c.lerp(Color(1.0, 0.56, 0.30), dusk * 0.55)
	top_c = top_c.lerp(Color(0.45, 0.40, 0.62), dusk * 0.25)
	sky_mat.sky_top_color = top_c
	sky_mat.sky_horizon_color = hor_c
	sky_mat.ground_horizon_color = hor_c
	sky_mat.ground_bottom_color = Color(0.20, 0.17, 0.12).lerp(Color(0.50, 0.44, 0.33), daylight)
	city_environment.glow_intensity = 0.15 + night_factor * 0.7
	city_environment.fog_light_color = sky
	city_environment.ambient_light_color = Color(0.30, 0.36, 0.55).lerp(Color(0.85, 0.83, 0.76), daylight)
	city_environment.ambient_light_energy = 0.30 + daylight * 0.55
	for entry in night_mats:
		var m: StandardMaterial3D = entry[0]
		m.emission_energy_multiplier = lerpf(float(entry[1]), float(entry[2]), night_factor)
	cloud_mat.albedo_color = Color(0.25 + 0.75 * daylight, 0.27 + 0.73 * daylight, 0.35 + 0.65 * daylight, 0.92)
	for cloud in cloud_nodes:
		var c: Node3D = cloud
		c.position.x += delta * 2.5
		if c.position.x > 700.0:
			c.position.x = -700.0
	# headlights
	for s in headlight_pair:
		(s as SpotLight3D).light_energy = (3.0 * night_factor) if driving else 0.0
	# police lights
	flash_clock += delta
	var phase := int(flash_clock * 4.0) % 2 == 0
	if police_flash_mats.size() >= 2:
		var boost := 1.5 + 3.5 * night_factor
		(police_flash_mats[0] as StandardMaterial3D).emission_energy_multiplier = boost if phase else 0.2
		(police_flash_mats[1] as StandardMaterial3D).emission_energy_multiplier = 0.2 if phase else boost
	lamp_timer -= delta
	if lamp_timer <= 0.0:
		lamp_timer = 0.4
		var focus := car.position if driving else player.position
		_update_lamp_pool(focus, night_factor)
	sun_mesh.visible = sun_dir.y > -0.05
	moon_mesh.visible = moon_dir.y > -0.05
	set_meta("sun_dir", sun_dir)
	set_meta("moon_dir", moon_dir)

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	_update_time(delta)
	_advance_traffic(delta)
	_update_npcs(delta)
	if wardrobe_open:
		_wardrobe_camera(delta)
		_update_hud()
		return
	player.rotation.x = 0.0
	var lx := _axis(KEY_A, KEY_D, JOY_AXIS_LEFT_X)
	var ly := _axis(KEY_W, KEY_S, JOY_AXIS_LEFT_Y)
	var arrows_turn := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	var arrows_move := float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
	ly = clampf(ly + arrows_move, -1.0, 1.0)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15:
		yaw -= rx * delta * 2.2
	if absf(ry) > 0.15:
		pitch = clampf(pitch - ry * delta * 1.6, -0.75, 0.45)
	if driving:
		var steer_in := clampf(lx + arrows_turn, -1.0, 1.0)
		var gas := maxf(maxf(0.0, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)), maxf(float(Input.is_key_pressed(KEY_W)) + float(Input.is_key_pressed(KEY_UP)), maxf(0.0, -ly)))
		var brake := maxf(maxf(0.0, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)), maxf(float(Input.is_key_pressed(KEY_S)) + float(Input.is_key_pressed(KEY_DOWN)), maxf(0.0, ly)))
		gas = clampf(gas, 0.0, 1.0)
		brake = clampf(brake, 0.0, 1.0)
		var top_speed := 32.0
		if int(car_kinds[active_car_index]) == 4:
			top_speed = 20.0
		var target_speed := gas * top_speed - brake * 7.0
		var accel := 17.0 if gas > 0.1 else (13.0 if brake > 0.1 else 8.0)
		speed = move_toward(speed, target_speed, accel * delta)
		var steer_strength := lerpf(1.9, 0.75, clampf(absf(speed) / 32.0, 0.0, 1.0))
		if absf(speed) > 0.5:
			car_heading -= steer_in * delta * steer_strength * signf(speed)
		car.rotation.y = car_heading
		car.velocity = Vector3(-sin(car_heading) * speed, -2.0, -cos(car_heading) * speed)
		car.move_and_slide()
		for ci in range(car.get_slide_collision_count()):
			var hit_normal: Vector3 = car.get_slide_collision(ci).get_normal()
			if absf(hit_normal.y) < 0.45:
				speed *= 0.35
				break
		var snd: AudioStreamPlayer3D = car_sounds[active_car_index]
		snd.pitch_scale = 0.75 + absf(speed) / 32.0 * 1.3
		if absf(speed) > 0.4 and not snd.playing:
			snd.play()
		if absf(speed) < 0.4 and snd.playing:
			snd.stop()
		player.position = car.position + Vector3(0, 2.7, 0)
	else:
		yaw -= arrows_turn * delta * 1.8
		var forward := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var move := (right * lx - forward * ly).limit_length(1.0)
		var walk_speed := 7.0 if Input.is_key_pressed(KEY_SHIFT) else 4.2
		player.velocity = move * walk_speed
		player.velocity.y = -2.0
		player.move_and_slide()
		var moving := move.length() > 0.1
		if moving:
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-move.x, -move.z), delta * 10.0)
			walk_clock += delta * 8.0
			var sgn := signf(sin(walk_clock))
			if sgn != last_step_sign:
				last_step_sign = sgn
				step_audio.pitch_scale = rng.randf_range(0.9, 1.15)
				step_audio.play()
		_animate_walker(player_visual, walk_clock, moving)
	_update_camera()
	_update_hud()

func _update_camera() -> void:
	var focus := car.position if driving else player.position
	var camera_yaw := car_heading if driving else yaw
	var facing := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
	if first_person:
		if driving:
			camera.position = focus + Vector3(0, 1.5, 0) + facing * 0.4
		else:
			camera.position = focus + Vector3(0, 1.45, 0) + facing * 0.2
	else:
		var dist := 6.5
		if driving:
			dist = 5.5 + _vehicle_size(int(car_kinds[active_car_index])).z * 0.5
		camera.position = focus - facing * dist + Vector3(0, 3.5 if driving else 2.6, 0)
	camera.look_at(focus + facing * 7.0 + Vector3(0, 1.3 + pitch * 8.0, 0), Vector3.UP)
	player.visible = not driving and not first_person
	_place_sky()

func _place_sky() -> void:
	var sd: Vector3 = get_meta("sun_dir")
	var md: Vector3 = get_meta("moon_dir")
	sun_mesh.position = camera.position + sd * 700.0
	moon_mesh.position = camera.position + md * 700.0

func _wardrobe_camera(delta: float) -> void:
	wardrobe_spin += delta * 0.6
	player.rotation.y = wardrobe_spin
	player.visible = true
	camera.position = player.position + Vector3(0.0, 1.15, 3.0)
	camera.look_at(player.position + Vector3(0, 0.95, 0), Vector3.UP)
	_place_sky()

func _update_hud() -> void:
	var focus := car.position if driving else player.position
	var dist_name: Array = _district_at(Vector2(focus.x, focus.z))
	hud.text = "CITY FREEDOM  |  MAKKAH  V10"
	district_label.text = "%s  %s  •  %s  •  %02d:%02d  •  %s" % [str(dist_name[0]).to_upper(), dist_name[1], "DRIVING" if driving else "WALKING", int(time_of_day), int(fposmod(time_of_day, 1.0) * 60.0), "1ST PERSON" if first_person else "3RD PERSON"]
	speed_label.text = ("%02d KM/H" % int(absf(speed) * 3.6)) if driving else "ON FOOT"
	time_label.text = "%02d:%02d" % [int(time_of_day), int(fposmod(time_of_day, 1.0) * 60.0)]
	sound_status.text = azan_status
	minimap.set("player_xy", Vector2(focus.x, focus.z))
	minimap.queue_redraw()
	if map_open:
		full_map.set("player_xy", Vector2(focus.x, focus.z))
		full_map.set("heading", car_heading if driving else yaw)
		full_map.queue_redraw()

# ---------------------------------------------------------------- cars: enter / exit
func _enter_nearest_car(police_only: bool = false) -> void:
	var best := -1
	var best_d := 8.0
	for i in range(all_cars.size()):
		if police_only and int(car_kinds[i]) != 8:
			continue
		var cand: Node3D = all_cars[i]
		var d := player.position.distance_to(cand.position)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return
	active_car_index = best
	car = all_cars[best]
	driving = true
	player.collision_layer = 0
	player.collision_mask = 0
	car.collision_layer = 1
	car.collision_mask = 3
	car_heading = car.rotation.y
	speed = 0.0
	_attach_headlights(car)

func _toggle_car() -> void:
	if driving:
		driving = false
		player.collision_layer = 1
		player.collision_mask = 3
		speed = 0.0
		var snd: AudioStreamPlayer3D = car_sounds[active_car_index]
		if snd.playing:
			snd.stop()
		if active_car_index > 0:
			car.collision_layer = 2
			car.collision_mask = 1
		player.position = car.position + car.global_transform.basis.x * 3.0 + Vector3(0, 0.3, 0)
		yaw = car_heading
	else:
		_enter_nearest_car()
