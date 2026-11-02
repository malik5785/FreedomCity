extends Spatial
# City Freedom - Makkah  V12 for Godot 3.6 (GLES2) - runs on older Android TVs.
# Real OpenStreetMap data of central Makkah is loaded from data/city.json (1 unit = 1 metre).
const CHUNK := 400.0
const MAX_BATCH_VERTS := 50000

var player: KinematicBody
var car: KinematicBody
var camera: Camera
var rng := RandomNumberGenerator.new()
var city := {}
var world_min := Vector2(-4000.0, -1500.0)
var world_max := Vector2(2300.0, 2100.0)
var start_pos := Vector2(0.0, 300.0)
var start_dir := Vector2(0.0, -1.0)
var districts := []

var driving := false
var first_person := false
var yaw := 0.0
var pitch := -0.18
var car_heading := 0.0
var speed := 0.0
var walk_clock := 0.0
var time_of_day := 10.0
var sun_light: DirectionalLight
var moon_light: DirectionalLight
var city_env: Environment
var sun_mesh: MeshInstance
var moon_mesh: MeshInstance
var cloud_nodes := []
var cloud_mat: SpatialMaterial
var player_visual: Spatial
var outfit := {"top": 0, "bottom": 0, "shoes": 0, "head": 0, "glasses": 0}
var wardrobe_open := false
var wardrobe_panel: Control
var wardrobe_row := 0
var wardrobe_rows := []
var wardrobe_spin := 0.0
var use_shadows := false
var frame_count := 0
var selftest := false

# UI
var hud_layer: CanvasLayer
var label_layer: CanvasLayer
var ui_root: Control
var ui_base_size := Vector2(960, 540)
var hud: Label
var district_label: Label
var time_label: Label
var speed_label: Label
var sound_status: Label
var minimap: Control
var full_map: Control
var map_open := false
var map_redraw_timer := 0.0
var font_cache := {}
var label_items := []
var label_pool := []
var label_pick := []
var label_timer := 0.0

# vehicles / people
var all_cars := []
var car_vel := []
var traffic_routes := []
var traffic_idx := []
var traffic_speeds := []
var traffic_wait := []
var traffic_stuck := []
var car_sounds := []
var car_kinds := []
var last_pos := []
var active_car_index := 0
var roads := []
var road_cells := {}
var npc_roads := []
var npc_list := []
var npc_vel := []
var npc_seg := []
var npc_t := []
var npc_dir := []
var npc_side := []
var npc_speed := []
var npc_clock := []
var pilgrims := []
var player_vel := Vector3.ZERO

# batching / materials
var render_chunks := []
var render_cull_clock := 0.0
var building_collision_cells := {}
var active_collision_cells := {}
var collision_clock := 0.0
const COLLISION_CELL := 250.0
const COLLISION_RADIUS := 420.0
var hud_update_clock := 0.0
var environment_update_clock := 0.0
var joystick_axes := {}
var joystick_device := -1
const RENDER_RANGE_SQ := 800.0 * 800.0
var batches := {}
var batch_part := {}
var batch_cnt := {}
var box_cache := {}
var mats := {}
var tex_cache := {}
var night_mats := []
var lamp_positions := []
var lamp_pool := []
var lamp_timer := 0.0
var tree_positions := []
var headlight_pair := []
var police_flash_mats := []
var flash_clock := 0.0

# audio
var city_audio: AudioStreamPlayer
var horn_audio: AudioStreamPlayer
var step_audio: AudioStreamPlayer
var azan_audio: AudioStreamPlayer3D
var azan_status := ""
var last_step_sign := 1.0

func _ready() -> void:
	rng.seed = 4261
	selftest = "--selftest" in OS.get_cmdline_args()
	_load_city()
	_create_world()
	_create_roads_and_city()
	_create_haram()
	_create_player()
	_create_car()
	_create_traffic()
	_create_npcs()
	_create_audio()
	_create_ui()
	get_viewport().connect("size_changed", self, "_resize_ui")
	_resize_ui()
	camera = Camera.new()
	camera.current = true
	camera.near = 0.5
	camera.far = 6000.0
	add_child(camera)
	_flush_batches()
	_cull_render_chunks()
	_stream_building_collisions()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		if wardrobe_open:
			_toggle_wardrobe()
		elif map_open:
			_toggle_map()

# ---------------------------------------------------------------- textures, fonts, wav (raw files, no import step)
func _read_bytes(path: String) -> PoolByteArray:
	var f := File.new()
	if not f.file_exists(path):
		return PoolByteArray()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var buf := f.get_buffer(f.get_len())
	f.close()
	return buf

func _tex(tname: String) -> Texture:
	if tex_cache.has(tname):
		return tex_cache[tname]
	var t: Texture = null
	var buf := _read_bytes("res://data/%s.dat" % tname)
	if buf.size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(buf) == OK:
			var it := ImageTexture.new()
			it.create_from_image(img, Texture.FLAGS_DEFAULT)
			t = it
	tex_cache[tname] = t
	return t

func _wav_from_bytes(buf: PoolByteArray, looped: bool) -> AudioStreamSample:
	if buf.size() < 48:
		return null
	var pos := 12
	var stereo := false
	var rate := 16000
	var bits := 16
	var data_start := -1
	var data_len := 0
	while pos + 8 <= buf.size():
		var cid := buf.subarray(pos, pos + 3).get_string_from_ascii()
		var clen := buf[pos + 4] + (buf[pos + 5] << 8) + (buf[pos + 6] << 16) + (buf[pos + 7] << 24)
		if cid == "fmt ":
			stereo = (buf[pos + 10] + (buf[pos + 11] << 8)) == 2
			rate = buf[pos + 12] + (buf[pos + 13] << 8) + (buf[pos + 14] << 16) + (buf[pos + 15] << 24)
			bits = buf[pos + 22] + (buf[pos + 23] << 8)
		elif cid == "data":
			data_start = pos + 8
			data_len = min(clen, buf.size() - data_start)
			break
		pos += 8 + clen + (clen % 2)
	if data_start < 0:
		return null
	var s := AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS if bits == 16 else AudioStreamSample.FORMAT_8_BITS
	s.mix_rate = rate
	s.stereo = stereo
	s.data = buf.subarray(data_start, data_start + data_len - 1)
	if looped:
		s.loop_mode = AudioStreamSample.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(data_len / ((2 if bits == 16 else 1) * (2 if stereo else 1)))
	return s

func _sound(sname: String, looped: bool) -> AudioStreamSample:
	return _wav_from_bytes(_read_bytes("res://data/%s.dat" % sname), looped)

func _font(sz: int) -> DynamicFont:
	if font_cache.has(sz):
		return font_cache[sz]
	var f := DynamicFont.new()
	var fd := DynamicFontData.new()
	fd.font_path = "res://data/font.dat"
	f.font_data = fd
	f.size = sz
	f.use_filter = true
	font_cache[sz] = f
	return f

# ---------------------------------------------------------------- materials
func _mat_key(c: Color) -> String:
	return "c:" + c.to_html(false)

func _get_mat(key: String) -> SpatialMaterial:
	key = key.replace("#sky", "")
	if mats.has(key):
		return mats[key]
	var m := SpatialMaterial.new()
	m.roughness = 1.0
	m.metallic = 0.0
	if key.begins_with("c:"):
		m.albedo_color = Color(key.substr(2))
	elif key.begins_with("d:"):
		m.albedo_color = Color(key.substr(2))
		m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	elif key.begins_with("p:"):
		m.albedo_color = Color(key.substr(2))
		m.roughness = 0.4
	elif key.begins_with("e:"):
		var col := Color(key.substr(2))
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy = 0.15
		night_mats.append([m, 0.15, 1.6])
	elif key.begins_with("f:"):
		m.albedo_color = Color(key.substr(2))
		m.params_cull_mode = SpatialMaterial.CULL_DISABLED
		var t := _tex("facade")
		if t != null:
			m.albedo_texture = t
		var te := _tex("facade_emit")
		if te != null:
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_texture = te
			m.emission_energy = 0.0
			night_mats.append([m, 0.0, 1.4])
	elif key.begins_with("w:"):
		m.albedo_color = Color(key.substr(2))
		m.params_cull_mode = SpatialMaterial.CULL_DISABLED
		var tp := _tex("plaster")
		if tp != null:
			m.albedo_texture = tp
	elif key == "r:atlas":
		m.params_cull_mode = SpatialMaterial.CULL_DISABLED
		var ta := _tex("road_atlas")
		if ta != null:
			m.albedo_texture = ta
		else:
			m.albedo_color = Color(0.25, 0.26, 0.27)
	elif key == "g:sand":
		m.albedo_color = Color(0.95, 0.88, 0.70)
		var tg := _tex("sand")
		if tg != null:
			m.albedo_texture = tg
	elif key == "flash_red" or key == "flash_blue":
		var fc := Color(1.0, 0.1, 0.1) if key == "flash_red" else Color(0.15, 0.3, 1.0)
		m.albedo_color = fc
		m.emission_enabled = true
		m.emission = fc
		m.emission_energy = 0.3
		police_flash_mats.append(m)
	mats[key] = m
	return m

func _mat(c: Color) -> SpatialMaterial:
	return _get_mat(_mat_key(c))

# ---------------------------------------------------------------- batching
func _bm(size: Vector3) -> CubeMesh:
	var k := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if box_cache.has(k):
		return box_cache[k]
	var m := CubeMesh.new()
	m.size = size
	box_cache[k] = m
	return m

func _batch_for(mat_key: String, at: Vector3, nverts: int, custom: bool) -> SurfaceTool:
	var cx := int(floor(at.x / CHUNK))
	var cz := int(floor(at.z / CHUNK))
	var cell := "%s|%d|%d|%d" % [mat_key, cx, cz, 1 if custom else 0]
	var part: int = batch_part.get(cell, 0)
	var key := "%s|%d" % [cell, part]
	var cnt: int = batch_cnt.get(key, 0)
	if cnt + nverts > MAX_BATCH_VERTS and cnt > 0:
		part += 1
		batch_part[cell] = part
		key = "%s|%d" % [cell, part]
		cnt = 0
	batch_cnt[key] = cnt + nverts
	if batches.has(key):
		return batches[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_get_mat(mat_key))
	batches[key] = st
	return st

func _batch_mesh(mesh: Mesh, t: Transform, mat_key: String, nverts: int = 24) -> void:
	_batch_for(mat_key, t.origin, nverts, false).append_from(mesh, 0, t)

func _bb(xf: Transform, local: Vector3, size: Vector3, mat_key: String) -> void:
	_batch_mesh(_bm(size), Transform(xf.basis, xf.xform(local)), mat_key)

func _wb(pos: Vector3, size: Vector3, mat_key: String) -> void:
	_batch_mesh(_bm(size), Transform(Basis(), pos), mat_key)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.add_normal(nrm)
	st.add_uv(ua)
	st.add_vertex(a)
	st.add_normal(nrm)
	st.add_uv(ub)
	st.add_vertex(b)
	st.add_normal(nrm)
	st.add_uv(uc)
	st.add_vertex(c)

func _flush_batches() -> void:
	for key in batches.keys():
		var st: SurfaceTool = batches[key]
		var mi := MeshInstance.new()
		mi.mesh = st.commit()
		var ks := str(key)
		var vis := 520.0
		if "#sky" in ks:
			vis = 4500.0
		elif ks.begins_with("f:") or ks.begins_with("w:"):
			vis = 850.0

		if ks.begins_with("r:") or ks.begins_with("d:") or ks.begins_with("g:"):
			mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var parts := ks.split("|")
		if parts.size() >= 5:
			var center := Vector2((int(parts[1]) + 0.5) * CHUNK, (int(parts[2]) + 0.5) * CHUNK)
			render_chunks.append([mi, center])
	batches.clear()

func _cull_render_chunks() -> void:
	var focus: Vector3 = car.translation if driving else player.translation
	var at := Vector2(focus.x, focus.z)
	for entry in render_chunks:
		var center: Vector2 = entry[1]
		(entry[0] as MeshInstance).visible = center.distance_squared_to(at) < RENDER_RANGE_SQ


func _solid(pos: Vector3, size: Vector3, yaw_rot: float = 0.0) -> void:
	var body := StaticBody.new()
	body.translation = pos
	body.rotation.y = yaw_rot
	var cs := CollisionShape.new()
	var bs := BoxShape.new()
	bs.extents = size * 0.5
	cs.shape = bs
	body.add_child(cs)
	add_child(body)

# ---------------------------------------------------------------- world, sky
func _create_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.40, 0.60, 0.86)
	city_env = env
	env.ambient_light_color = Color(0.85, 0.83, 0.76)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_color = Color(0.78, 0.84, 0.9)
	env.fog_depth_enabled = true
	env.fog_depth_begin = 400.0
	env.fog_depth_end = 9000.0
	env.fog_depth_curve = 1.0
	we.environment = env
	add_child(we)
	sun_light = DirectionalLight.new()
	sun_light.shadow_enabled = use_shadows
	sun_light.directional_shadow_max_distance = 120.0
	add_child(sun_light)
	moon_light = DirectionalLight.new()
	moon_light.light_color = Color(0.62, 0.72, 1.0)
	moon_light.light_energy = 0.0
	add_child(moon_light)
	var wcenter := (world_min + world_max) * 0.5
	var wsize := world_max - world_min
	# ground
	var ground := MeshInstance.new()
	var gm := CubeMesh.new()
	gm.size = Vector3(wsize.x + 9000.0, 1.0, wsize.y + 9000.0)
	ground.mesh = gm
	var gmat := _get_mat("g:sand")
	gmat.uv1_scale = Vector3((wsize.x + 9000.0) / 45.0, (wsize.y + 9000.0) / 45.0, 1.0)
	ground.material_override = gmat
	ground.translation = Vector3(wcenter.x, -0.53, wcenter.y)
	ground.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	_solid(Vector3(wcenter.x, -0.53, wcenter.y), Vector3(wsize.x + 9000.0, 1.0, wsize.y + 9000.0))
	# invisible walls so nothing leaves the map
	var wl := world_min.x - 30.0
	var wr := world_max.x + 30.0
	var wt := world_min.y - 30.0
	var wb := world_max.y + 30.0
	_solid(Vector3(wr, 20, wcenter.y), Vector3(4, 80, wsize.y + 200.0))
	_solid(Vector3(wl, 20, wcenter.y), Vector3(4, 80, wsize.y + 200.0))
	_solid(Vector3(wcenter.x, 20, wb), Vector3(wsize.x + 200.0, 80, 4))
	_solid(Vector3(wcenter.x, 20, wt), Vector3(wsize.x + 200.0, 80, 4))
	# mountains around Makkah
	for i in range(40):
		var ang := float(i) / 40.0 * TAU
		var r := rng.randf_range(160.0, 380.0)
		var hill := MeshInstance.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 14
		sm.rings = 7
		hill.mesh = sm
		var shade := rng.randf_range(-0.07, 0.05)
		hill.material_override = _mat(Color(0.50 + shade, 0.42 + shade, 0.32 + shade))
		hill.translation = Vector3(wcenter.x + cos(ang) * (wsize.x * 0.5 + 650.0), -r * 0.62, wcenter.y + sin(ang) * (wsize.y * 0.5 + 600.0))
		hill.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		add_child(hill)
		var hb := StaticBody.new()
		hb.translation = hill.translation
		var hc := CollisionShape.new()
		var ss := SphereShape.new()
		ss.radius = r
		hc.shape = ss
		hb.add_child(hc)
		add_child(hb)
	# sun, moon discs and clouds follow the camera
	sun_mesh = _sky_disc(Color(1.0, 0.93, 0.62), 130.0)
	moon_mesh = _sky_disc(Color(0.88, 0.92, 1.0), 85.0)
	cloud_mat = SpatialMaterial.new()
	cloud_mat.flags_unshaded = true
	cloud_mat.flags_transparent = true
	cloud_mat.albedo_color = Color(1, 1, 1, 0.9)
	for i in range(22):
		var cloud := Spatial.new()
		cloud.translation = Vector3(rng.randf_range(world_min.x - 600.0, world_max.x + 600.0), rng.randf_range(140, 240), rng.randf_range(world_min.y - 600.0, world_max.y + 600.0))
		for k in range(4):
			var puff := MeshInstance.new()
			var pm := SphereMesh.new()
			pm.radius = rng.randf_range(30, 55)
			pm.height = pm.radius * 1.1
			pm.radial_segments = 8
			pm.rings = 4
			puff.mesh = pm
			puff.material_override = cloud_mat
			puff.translation = Vector3(k * 45.0 - 70.0, rng.randf_range(-5, 8), rng.randf_range(-16, 16))
			puff.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(puff)
		add_child(cloud)
		cloud_nodes.append(cloud)

func _sky_disc(col: Color, radius: float) -> MeshInstance:
	var mi := MeshInstance.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

# ---------------------------------------------------------------- city data (OpenStreetMap)
func _load_city() -> void:
	var txt := _read_bytes("res://data/city.json").get_string_from_utf8()
	var parsed = JSON.parse(txt)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		push_error("city.json could not be loaded")
		city = {"bounds": [-500, -500, 500, 500], "start": [0, 0], "sdir": [0, -1], "roads": [], "bld": [], "areas": [], "poi": [], "bus": [], "sig": [], "mosq": [], "trees": [], "dist": []}
	else:
		city = parsed.result
	var b: Array = city["bounds"]
	world_min = Vector2(float(b[0]), float(b[1]))
	world_max = Vector2(float(b[2]), float(b[3]))
	var s: Array = city["start"]
	start_pos = Vector2(float(s[0]), float(s[1]))
	var sd: Array = city["sdir"]
	start_dir = Vector2(float(sd[0]), float(sd[1])).normalized()
	districts = city["dist"]

func _v2list(arr: Array) -> Array:
	var out := []
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out

func _grid_key(p: Vector2, cell: float) -> String:
	return "%d_%d" % [int(floor(p.x / cell)), int(floor(p.y / cell))]

func _add_road(a: Vector2, b: Vector2, w: float) -> void:
	var idx := roads.size()
	roads.append([a, b, w])
	var steps := int(a.distance_to(b) / 40.0) + 1
	for s in range(steps + 1):
		var c := _grid_key(a.linear_interpolate(b, float(s) / float(steps)), 100.0)
		if not road_cells.has(c):
			road_cells[c] = []
		var lst: Array = road_cells[c]
		if not lst.has(idx):
			lst.append(idx)

func _road_pieces(pts: Array, max_len: float) -> Array:
	var pieces := []
	var cur := [pts[0]]
	var acc := 0.0
	for i in range(1, pts.size()):
		var prev: Vector2 = cur[cur.size() - 1]
		var nxt: Vector2 = pts[i]
		acc += prev.distance_to(nxt)
		cur.append(nxt)
		if acc >= max_len and i < pts.size() - 1:
			pieces.append(cur)
			cur = [nxt]
			acc = 0.0
	if cur.size() >= 2:
		pieces.append(cur)
	return pieces

# One road piece as a single textured ribbon: sidewalk | edge line | asphalt | centre line | asphalt | edge line | sidewalk
func _road_ribbon(pts: Array, w: float, cls: int) -> void:
	var n := pts.size()
	if n < 2:
		return
	var hw := w * 0.5
	var sw := 2.2 if cls <= 4 else 0.8
	var y := 0.08 - 0.01 * float(cls)
	var centre := w >= 9.0 and cls <= 3
	var lat := [-hw - sw, -hw, -hw + 0.22, -0.12, 0.12, hw - 0.22, hw, hw + sw]
	# atlas u for each of the 7 strips: [u0, u1]
	var us := [[0.28, 0.47], [0.52, 0.55], [0.03, 0.22], [0.60, 0.65] if centre else [0.03, 0.22], [0.03, 0.22], [0.52, 0.55], [0.28, 0.47]]
	var rows := []
	var vdist := 0.0
	for i in range(n):
		var p: Vector2 = pts[i]
		var d1 := Vector2.ZERO
		var d2 := Vector2.ZERO
		if i > 0:
			d1 = (p - (pts[i - 1] as Vector2)).normalized()
			vdist += p.distance_to(pts[i - 1])
		if i < n - 1:
			d2 = ((pts[i + 1] as Vector2) - p).normalized()
		var refd := d2 if i < n - 1 else d1
		var d := (d1 + d2).normalized()
		if d.length() < 0.5:
			d = refd
		var nrm := Vector2(-d.y, d.x)
		var refn := Vector2(-refd.y, refd.x)
		var k: float = 1.0 / max(nrm.dot(refn), 0.6)
		var row := []
		for li in range(lat.size()):
			row.append(p + nrm * float(lat[li]) * k)
		rows.append([row, vdist / 6.0])
	var first: Vector2 = pts[0]
	var st := _batch_for("r:atlas", Vector3(first.x, 0, first.y), (n - 1) * 7 * 6, true)
	for i in range(n - 1):
		var r0: Array = rows[i][0]
		var r1: Array = rows[i + 1][0]
		var v0: float = rows[i][1]
		var v1: float = rows[i + 1][1]
		for s in range(7):
			var a0: Vector2 = r0[s]
			var a1: Vector2 = r0[s + 1]
			var b0: Vector2 = r1[s]
			var b1: Vector2 = r1[s + 1]
			var u0: float = us[s][0]
			var u1: float = us[s][1]
			_tri(st, Vector3(a0.x, y, a0.y), Vector3(a1.x, y, a1.y), Vector3(b1.x, y, b1.y), Vector3.UP, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1))
			_tri(st, Vector3(a0.x, y, a0.y), Vector3(b1.x, y, b1.y), Vector3(b0.x, y, b0.y), Vector3.UP, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1))

func _poly_area(p: Array) -> float:
	var a := 0.0
	for i in range(p.size()):
		var q: Vector2 = p[i]
		var r: Vector2 = p[(i + 1) % p.size()]
		a += q.x * r.y - r.x * q.y
	return abs(a) * 0.5

func _create_roads_and_city() -> void:
	var lamp_candidates := []
	for r in city["roads"]:
		var w: float = float(r[0])
		var cls: int = int(r[1])
		var pts := _v2list(r[2])
		if pts.size() < 2:
			continue
		for k in range(pts.size() - 1):
			_add_road(pts[k], pts[k + 1], w)
		for piece in _road_pieces(pts, 110.0):
			_road_ribbon(piece, w, cls)
		if cls <= 3 and w >= 9.0:
			lamp_candidates.append([pts, w])
	for a in city["areas"]:
		_city_area(a)
	for b in city["bld"]:
		_city_building(b)
	_place_lamps(lamp_candidates)
	for t in city["trees"]:
		_tree(Vector2(float(t[0]), float(t[1])))
	for p in city["poi"]:
		_city_poi(p)
	for bs in city["bus"]:
		_bus_stop(Vector2(float(bs[0]), float(bs[1])), str(bs[2]))
	for sg in city["sig"]:
		_traffic_signal(Vector2(float(sg[0]), float(sg[1])))
	for m in city["mosq"]:
		_minaret(Vector2(float(m[0]), float(m[1])), str(m[2]))
	for dd in districts:
		label_items.append([Vector3(float(dd[2]), 60.0, float(dd[3])), str(dd[0]).to_upper(), Color(1.0, 0.85, 0.4), 1400.0])

func _city_area(a: Dictionary) -> void:
	var verts := _v2list(a["v"])
	var tri: Array = a["t"]
	var kind: String = a["k"]
	if verts.size() < 3:
		return
	var key := "d:e9e5db#sky"
	var y := 0.1
	if kind == "park":
		key = "d:5f8f45#sky"
		y = 0.09
	elif kind == "parking":
		key = "d:45484c#sky"
		y = 0.09
	var first: Vector2 = verts[0]
	var st := _batch_for(key, Vector3(first.x, 0, first.y), tri.size(), true)
	for i in range(0, tri.size() - 2, 3):
		var p0: Vector2 = verts[int(tri[i])]
		var p1: Vector2 = verts[int(tri[i + 1])]
		var p2: Vector2 = verts[int(tri[i + 2])]
		_tri(st, Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)

func _city_building(b: Dictionary) -> void:
	var v: Array = b["v"]
	var rs: Array = b["r"]
	var h: float = float(b["h"])
	var mh: float = float(b["m"])
	var hex: String = b["c"]
	var kind: String = b["k"]
	var verts := _v2list(v)
	var outer_n := int(rs[0])
	var cen := Vector2.ZERO
	for i in range(outer_n):
		cen += verts[i] as Vector2
	cen /= float(outer_n)
	var sky := "#sky" if h > 70.0 else ""
	var wall_key := "f:" + hex + sky
	var roof_key := "w:b8ad98" + sky
	if kind == "kaaba":
		wall_key = "d:101010" + sky
		roof_key = "d:101010" + sky
	var wall_cnt := 0
	for ri in range(rs.size()):
		wall_cnt += int(rs[ri]) * 6
	var st := _batch_for(wall_key, Vector3(cen.x, 0, cen.y), wall_cnt, true)
	var off := 0
	for ri in range(rs.size()):
		var cnt := int(rs[ri])
		for i in range(cnt):
			var a: Vector2 = verts[off + i]
			var c2: Vector2 = verts[off + (i + 1) % cnt]
			var dd := c2 - a
			var ln := dd.length()
			if ln < 0.05:
				continue
			var nrm := Vector3(dd.y, 0.0, -dd.x) / ln
			var a0 := Vector3(a.x, mh, a.y)
			var a1 := Vector3(a.x, h, a.y)
			var b0 := Vector3(c2.x, mh, c2.y)
			var b1 := Vector3(c2.x, h, c2.y)
			var uw := ln / 3.2
			var v0 := mh / 3.2
			var v1 := h / 3.2
			_tri(st, a0, b0, b1, nrm, Vector2(0, v0), Vector2(uw, v0), Vector2(uw, v1))
			_tri(st, a0, b1, a1, nrm, Vector2(0, v0), Vector2(uw, v1), Vector2(0, v1))
		off += cnt
	var rverts := verts
	if b.has("p"):
		rverts = _v2list(b["p"])
	var tri: Array = b["t"]
	var rst := _batch_for(roof_key, Vector3(cen.x, 0, cen.y), tri.size(), true)
	for i in range(0, tri.size() - 2, 3):
		var p0: Vector2 = rverts[int(tri[i])]
		var p1: Vector2 = rverts[int(tri[i + 1])]
		var p2: Vector2 = rverts[int(tri[i + 2])]
		_tri(rst, Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p2.x, h, p2.y), Vector3.UP, p0 / 6.0, p1 / 6.0, p2 / 6.0)
	var area := _poly_area(verts.slice(0, outer_n - 1))
	var en: String = b["n"]
	var open_mosque := area > 60000.0 or "Great Mosque" in en or "Grand Mosque" in en
	if not open_mosque and mh < 3.0 and h - mh > 2.0 and area > 6.0:
		# Stream collision geometry near the player instead of creating
		# thousands of active physics bodies across the entire city.
		var cell := Vector2(int(floor(cen.x / COLLISION_CELL)), int(floor(cen.y / COLLISION_CELL)))
		if not building_collision_cells.has(cell):
			building_collision_cells[cell] = []
		building_collision_cells[cell].append([verts, rs, mh, h, area > 2500.0])
	if en != "":
		var col := Color(1.0, 0.86, 0.5) if kind == "hotel" else Color(1, 1, 1)
		label_items.append([Vector3(cen.x, h + 6.0, cen.y), en, col, 260.0 if h < 100.0 else 900.0])

func _stream_building_collisions() -> void:
	var pos: Vector3 = car.translation if driving else player.translation
	var at := Vector2(pos.x, pos.z)
	for cell in building_collision_cells.keys():
		var center := (cell as Vector2) * COLLISION_CELL + Vector2(COLLISION_CELL * 0.5, COLLISION_CELL * 0.5)
		var nearby := center.distance_squared_to(at) < (COLLISION_RADIUS * COLLISION_RADIUS)
		if not nearby and active_collision_cells.has(cell):
			for body in active_collision_cells[cell]:
				(body as StaticBody).collision_layer = 0
			active_collision_cells.erase(cell)
		elif nearby and not active_collision_cells.has(cell):
			var bodies := []
			for item in building_collision_cells[cell]:
				var body: StaticBody = _building_collision(item[0], item[1], item[2], item[3], item[4])
				if body != null:
					bodies.append(body)
			active_collision_cells[cell] = bodies
			building_collision_cells.erase(cell)

func _building_collision(verts: Array, rs: Array, mh: float, h: float, big: bool) -> StaticBody:
	var body := StaticBody.new()
	var outer_n := int(rs[0])
	if rs.size() == 1 and outer_n <= 24 and not big:
		var poly := PoolVector2Array()
		for i in range(outer_n):
			poly.append(verts[i])
		var hull := Geometry.convex_hull_2d(poly)
		var pts := PoolVector3Array()
		for hp in hull:
			pts.append(Vector3(hp.x, mh, hp.y))
			pts.append(Vector3(hp.x, h, hp.y))
		if pts.size() < 6:
			return null
		var cs := CollisionShape.new()
		var shape := ConvexPolygonShape.new()
		shape.points = pts
		cs.shape = shape
		body.add_child(cs)
	else:
		var off := 0
		var count := 0
		for ri in range(rs.size()):
			var cnt := int(rs[ri])
			for i in range(cnt):
				var a: Vector2 = verts[off + i]
				var b: Vector2 = verts[off + (i + 1) % cnt]
				var dd := b - a
				if dd.length() < 2.0 or count > 160:
					continue
				var cs2 := CollisionShape.new()
				var bs := BoxShape.new()
				bs.extents = Vector3(dd.length() * 0.5, (h - mh) * 0.5, 0.6)
				cs2.shape = bs
				cs2.translation = Vector3((a.x + b.x) * 0.5, (h + mh) * 0.5, (a.y + b.y) * 0.5)
				cs2.rotation.y = atan2(-dd.y, dd.x)
				body.add_child(cs2)
				count += 1
			off += cnt
	add_child(body)
	return body

func _city_poi(p: Array) -> void:
	var en := str(p[2])
	if en == "":
		return
	var kind := str(p[4])
	var col := Color(1, 1, 1)
	match kind:
		"food":
			col = Color(1.0, 0.55, 0.35)
		"pharm":
			col = Color(0.45, 1.0, 0.55)
		"bank":
			col = Color(0.55, 0.75, 1.0)
		"shop":
			col = Color(1.0, 0.9, 0.4)
		"hotel":
			col = Color(1.0, 0.86, 0.5)
	label_items.append([Vector3(float(p[0]), 4.4, float(p[1])), en, col, 110.0])
	var sign_cols := ["c8102e", "00704a", "1565c0", "d4a017", "6a1b9a"]
	var sc: String = sign_cols[int(fposmod(float(p[0]) * 7.0, 5.0))]
	_wb(Vector3(float(p[0]), 3.7, float(p[1])), Vector3(1.2, 0.7, 0.2), "e:" + sc)

func _bus_stop(p: Vector2, nm: String) -> void:
	var pos := Vector3(p.x, 0, p.y)
	_wb(pos + Vector3(0, 2.6, 0), Vector3(3.2, 0.12, 1.5), "c:2b5f7a")
	_wb(pos + Vector3(-1.5, 1.3, 0), Vector3(0.1, 2.6, 0.1), "c:3d4549")
	_wb(pos + Vector3(1.5, 1.3, 0), Vector3(0.1, 2.6, 0.1), "c:3d4549")
	_wb(pos + Vector3(0, 1.4, -0.65), Vector3(3.0, 2.2, 0.06), "c:9fd4e4")
	_wb(pos + Vector3(0, 0.5, 0.2), Vector3(2.2, 0.08, 0.4), "c:6b4a2b")
	label_items.append([pos + Vector3(0, 3.4, 0), "BUS STOP" if nm == "" else nm, Color(0.5, 1, 0.6), 70.0])

func _traffic_signal(p: Vector2) -> void:
	var pos := Vector3(p.x, 0, p.y)
	_wb(pos + Vector3(0, 2.8, 0), Vector3(0.2, 5.6, 0.2), "c:3d4549")
	_wb(pos + Vector3(0, 5.0, 0), Vector3(0.45, 1.3, 0.4), "c:1c1e21")
	for zs in [0.22, -0.22]:
		_wb(pos + Vector3(0, 5.45, zs), Vector3(0.24, 0.24, 0.08), "e:ff3b30")
		_wb(pos + Vector3(0, 5.0, zs), Vector3(0.24, 0.24, 0.08), "e:ffcc00")
		_wb(pos + Vector3(0, 4.55, zs), Vector3(0.24, 0.24, 0.08), "e:34c759")
	_solid(pos + Vector3(0, 2.8, 0), Vector3(0.3, 5.6, 0.3))

func _minaret(p: Vector2, en: String) -> void:
	var pos := Vector3(p.x, 0, p.y)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.3
	cyl.height = 30.0
	cyl.radial_segments = 10
	cyl.rings = 1
	var ring := CylinderMesh.new()
	ring.top_radius = 1.8
	ring.bottom_radius = 1.8
	ring.height = 0.5
	ring.radial_segments = 10
	ring.rings = 1
	var tip := SphereMesh.new()
	tip.radius = 1.0
	tip.height = 2.0
	tip.radial_segments = 8
	tip.rings = 4
	_batch_mesh(cyl, Transform(Basis(), pos + Vector3(0, 15.0, 0)), "c:efe7d3", 70)
	_batch_mesh(ring, Transform(Basis(), pos + Vector3(0, 24.0, 0)), "c:cfc6ae", 70)
	_batch_mesh(tip, Transform(Basis(), pos + Vector3(0, 31.2, 0)), "c:d4a53a", 70)
	_solid(pos + Vector3(0, 15.0, 0), Vector3(2.6, 30.0, 2.6))
	if en != "":
		label_items.append([pos + Vector3(0, 35.0, 0), en, Color(0.7, 1.0, 0.8), 400.0])

func _place_lamps(cands: Array) -> void:
	var spots := []
	for c in cands:
		var pts: Array = c[0]
		var w: float = c[1]
		var carry := 20.0
		var flip := 1.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg_len := a.distance_to(b)
			if seg_len < 0.5:
				continue
			var d := (b - a) / seg_len
			var nrm := Vector2(-d.y, d.x)
			var t := carry
			while t < seg_len:
				var q := a + d * t + nrm * flip * (w * 0.5 + 3.0)
				spots.append([q.distance_squared_to(start_pos), q, atan2(nrm.x * flip, nrm.y * flip)])
				flip = -flip
				t += 42.0
			carry = t - seg_len
	spots.sort_custom(self, "_cmp_first")
	var count := int(min(spots.size(), 700))
	for i in range(count):
		_lamp(spots[i][1], float(spots[i][2]))

func _cmp_first(a, b) -> bool:
	return a[0] < b[0]

func _lamp(p: Vector2, face: float) -> void:
	var xf := Transform(Basis(Vector3.UP, face), Vector3(p.x, 0, p.y))
	_bb(xf, Vector3(0, 3.2, 0), Vector3(0.18, 6.4, 0.18), "c:3d4549")
	_bb(xf, Vector3(0, 6.3, -0.6), Vector3(0.15, 0.12, 1.35), "c:3d4549")
	_bb(xf, Vector3(0, 6.2, -1.15), Vector3(0.4, 0.08, 0.55), "e:fff0b8")
	_solid(Vector3(p.x, 3.2, p.y), Vector3(0.3, 6.4, 0.3))
	lamp_positions.append(xf.xform(Vector3(0, 6.0, -1.15)))

func _tree(p: Vector2) -> void:
	var pos := Vector3(p.x, 0, p.y)
	tree_positions.append(pos)
	if rng.randf() < 0.55:
		var hgt := rng.randf_range(6.0, 9.0)
		_wb(pos + Vector3(0, hgt * 0.5, 0), Vector3(0.36, hgt, 0.36), "c:6e5238")
		for k in range(7):
			var a := float(k) / 7.0 * TAU
			var bs := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.45)
			var fr := Transform(bs, pos + Vector3(0, hgt, 0) + Vector3(cos(a), 0, sin(a)) * 0.9)
			_batch_mesh(_bm(Vector3(0.7, 0.08, 3.4)), fr, "c:3c7a36")
	else:
		_wb(pos + Vector3(0, 1.6, 0), Vector3(0.38, 3.2, 0.38), "c:57391f")
		var sm := SphereMesh.new()
		sm.radius = 1.8
		sm.height = 3.2
		sm.radial_segments = 8
		sm.rings = 4
		var leaf: String = ["c:2f6b34", "c:3b7a3a", "c:4f8a3f"][rng.randi_range(0, 2)]
		_batch_mesh(sm, Transform(Basis(), pos + Vector3(0, 4.2, 0)), leaf, 60)
		_batch_mesh(sm, Transform(Basis(), pos + Vector3(1.1, 3.7, 0.5)), leaf, 60)
	_solid(pos + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5))

func _nearest_districts(p: Vector2) -> Array:
	var best_d := 1.0e20
	var best := ["Makkah", ""]
	for dd in districts:
		var d := p.distance_to(Vector2(float(dd[2]), float(dd[3])))
		if d < best_d:
			best_d = d
			best = [dd[0], dd[1]]
	return [best]

func _district_at(p: Vector2) -> Array:
	return _nearest_districts(p)[0]

# ---------------------------------------------------------------- Al Haram: clock faces + pilgrims around the Kaaba
func _create_haram() -> void:
	var clock = city.get("clock")
	if clock != null:
		var cx := float(clock[0])
		var cz := float(clock[1])
		var hw := float(clock[2])
		var hd := float(clock[3])
		var faces := [[0.0, -hd - 0.6, 0.0], [0.0, hd + 0.6, PI], [-hw - 0.6, 0.0, PI * 0.5], [hw + 0.6, 0.0, -PI * 0.5]]
		for f in faces:
			var xf := Transform(Basis(Vector3.UP, float(f[2])), Vector3(cx + float(f[0]), 395.0, cz + float(f[1])))
			_bb(xf, Vector3.ZERO, Vector3(43, 43, 1.0), "c:f8f8f4#sky")
			_bb(xf, Vector3(0, 5.5, -0.7), Vector3(1.8, 12.0, 0.3), "c:202020#sky")
			_bb(xf, Vector3(6.0, 0, -0.7), Vector3(13.0, 1.4, 0.3), "c:202020#sky")
			_bb(xf, Vector3(0, 0, -0.7), Vector3(3.0, 3.0, 0.3), "c:d4a53a#sky")
	for i in range(24):
		var o := _random_outfit()
		o["top"] = 0
		o["head"] = 0
		o["glasses"] = 0
		var node := Spatial.new()
		add_child(node)
		var vis := _human(node, false, o)
		node.set_meta("visual", vis)
		var r := rng.randf_range(22.0, 44.0)
		var ang := rng.randf() * TAU
		node.translation = Vector3(cos(ang) * r, 0.1, sin(ang) * r)
		pilgrims.append([node, r, ang, rng.randf_range(0.8, 1.1), rng.randf() * 6.0])

func _update_pilgrims(delta: float) -> void:
	for p in pilgrims:
		var node: Spatial = p[0]
		var r: float = p[1]
		var ang: float = float(p[2]) + delta * float(p[3]) / r
		p[2] = ang
		p[4] = float(p[4]) + delta * 6.0
		node.translation = Vector3(cos(ang) * r, 0.1, sin(ang) * r)
		node.rotation.y = atan2(sin(ang), -cos(ang))
		_animate_walker(node.get_meta("visual"), float(p[4]), true)
# ---------------------------------------------------------------- people
const TOPS = [["White thobe", "f4f1e8", 0], ["Black thobe", "1d1f24", 0], ["Cream thobe", "d9c9a0", 0], ["Blue shirt", "3a6ea5", 1], ["Red shirt", "b03a2e", 1], ["Green jacket", "3e6b4a", 1]]
const BOTTOMS = [["Dark jeans", "2b3a55"], ["Khaki", "b5a278"], ["Black pants", "1c1c1e"], ["Grey pants", "6b6f75"]]
const SHOES = [["White sneakers", "f2f2f2"], ["Black shoes", "151515"], ["Brown sandals", "7a5230"], ["Red sneakers", "b3261e"]]
const HEADS = [["No head wear", ""], ["White ghutra", "f6f6f2"], ["Red ghutra", "c0392b"], ["Black cap", "1b1b1b"], ["White kufi", "ecece6"]]
const GLASSES = [["No glasses", false], ["Sunglasses", true]]

func _pm(spec: String) -> SpatialMaterial:
	if spec.begins_with("p:") or spec.begins_with("e:") or spec.begins_with("flash") or spec.begins_with("win"):
		return _get_mat(spec)
	return _get_mat("c:" + spec)

func _mi(parent: Spatial, mesh: Mesh, pos: Vector3, hex: String) -> MeshInstance:
	var n := MeshInstance.new()
	n.mesh = mesh
	n.material_override = _pm(hex)
	n.translation = pos
	parent.add_child(n)
	return n

func _bxm(parent: Spatial, pos: Vector3, size: Vector3, hex: String) -> MeshInstance:
	return _mi(parent, _bm(size), pos, hex)

# Builds a stylised person. o = outfit dictionary. Returns root; limbs stored in meta for walking animation.
func _human(parent: Spatial, child_size: bool, o: Dictionary) -> Spatial:
	var root := Spatial.new()
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
		var pivot := Spatial.new()
		pivot.translation = Vector3(lx, 0.90, 0)
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
		var pv := Spatial.new()
		pv.translation = Vector3(ax, 1.48, 0)
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
		var ring := CylinderMesh.new()
		ring.top_radius = 0.235
		ring.bottom_radius = 0.235
		ring.height = 0.04
		ring.radial_segments = 12
		ring.rings = 1
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

func _animate_walker(vis: Spatial, clock: float, moving: bool) -> void:
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
	vis.translation.y = abs(sin(clock)) * 0.03 if moving else 0.0

func _random_outfit() -> Dictionary:
	var female := rng.randf() < 0.3
	return {"top": rng.randi_range(0, 5), "bottom": rng.randi_range(0, 3), "shoes": rng.randi_range(0, 3), "head": rng.randi_range(0, 4), "glasses": rng.randi_range(0, 1) if rng.randf() < 0.3 else 0, "female": female}

func _actor(pos: Vector3, o: Dictionary, is_child: bool) -> KinematicBody:
	var body := KinematicBody.new()
	body.translation = pos
	body.collision_layer = 1
	body.collision_mask = 3
	add_child(body)
	var cyl := CylinderShape.new()
	cyl.radius = 0.32
	cyl.height = 1.4 if is_child else 1.7
	var collider := CollisionShape.new()
	collider.shape = cyl
	collider.translation.y = 0.75 if is_child else 0.9
	body.add_child(collider)
	var vis := _human(body, is_child, o)
	body.set_meta("visual", vis)
	return body

func _create_player() -> void:
	var perp := Vector2(-start_dir.y, start_dir.x)
	var pp := start_pos + perp * 2.4
	player = _actor(Vector3(pp.x, 0.05, pp.y), outfit, true)
	yaw = atan2(-start_dir.x, -start_dir.y)
	player_visual = player.get_meta("visual")

func _rebuild_player_visual() -> void:
	if is_instance_valid(player_visual):
		player_visual.queue_free()
	player_visual = _human(player, true, outfit)
	player.set_meta("visual", player_visual)

func _create_npcs() -> void:
	var people_stream := _sound("people", true)
	for sg in roads:
		var sa: Vector2 = sg[0]
		if sa.distance_to(start_pos) < 450.0 and float(sg[2]) >= 6.0:
			npc_roads.append(sg)
	if npc_roads.empty():
		return
	var n_npc := 14
	for i in range(n_npc):
		var si := rng.randi_range(0, npc_roads.size() - 1)
		var seg: Array = npc_roads[si]
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
			voice.unit_db = -8.0
			voice.pitch_scale = rng.randf_range(0.85, 1.2)
			npc.add_child(voice)
			voice.play(rng.randf() * 5.0)

func _sidewalk_point(seg: Array, t: float, side: float) -> Vector2:
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var w: float = seg[2]
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return a.linear_interpolate(b, t) + n * side * (w * 0.5 + 1.0)

func _update_npcs(delta: float) -> void:
	for i in range(npc_list.size()):
		var npc: KinematicBody = npc_list[i]
		var seg: Array = npc_roads[npc_seg[i]]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var length := a.distance_to(b)
		var t_target: float = clamp(float(npc_t[i]) + float(npc_dir[i]) * 3.0 / max(length, 1.0), 0.0, 1.0)
		var tp := _sidewalk_point(seg, t_target, float(npc_side[i]))
		var to := Vector3(tp.x, npc.translation.y, tp.y) - npc.translation
		var moving := true
		if to.length() < 0.6:
			npc_t[i] = t_target
			if t_target <= 0.001 or t_target >= 0.999:
				# at a road end: switch to a nearby road or turn around
				var end_pt := a if t_target <= 0.001 else b
				var found := -1
				for k in range(npc_roads.size()):
					if k == npc_seg[i]:
						continue
					var s2: Array = npc_roads[k]
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
			for ci in range(all_cars.size()):
				var off: Vector3 = (all_cars[ci] as Spatial).translation - npc.translation
				if off.length() < 4.5 and off.dot(v.normalized()) > 0.0 and abs(float(car_vel[ci])) > 1.0:
					moving = false
			if moving:
				npc.move_and_slide(Vector3(v.x, -2.0, v.z), Vector3.UP)
				npc.rotation.y = lerp_angle(npc.rotation.y, atan2(-v.x, -v.z), delta * 6.0)
				npc_clock[i] = float(npc_clock[i]) + delta * 7.0 * float(npc_speed[i])
		_animate_walker(npc.get_meta("visual"), float(npc_clock[i]), moving)

# ---------------------------------------------------------------- vehicles
# kind: 0 sedan, 1 SUV, 2 pickup, 3 van, 4 bus, 5 truck, 6 hatchback, 7 taxi, 8 police
const MAKES = [["TOYOTA", 0], ["LEXUS", 1], ["HYUNDAI", 2], ["KIA", 3], ["NISSAN", 4], ["FORD", 5], ["GMC", 6], ["CHEVROLET", 7], ["MERCEDES", 8], ["HONDA", 9]]
const CAR_COLORS = ["eeeeea", "1f262e", "b9bbbe", "a3201c", "d6bb7a", "2d6073", "4a4f55", "f2f2f2", "3b4a2f", "7a1f2b"]

func _emblem(parent: Spatial, kind: int, pos: Vector3, face_z: float) -> void:
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
			var ring := CylinderMesh.new()
			ring.top_radius = 0.07
			ring.bottom_radius = 0.07
			ring.height = 0.02
			ring.radial_segments = 12
			ring.rings = 1
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
			var star := CylinderMesh.new()
			star.top_radius = 0.075
			star.bottom_radius = 0.075
			star.height = 0.02
			star.radial_segments = 12
			star.rings = 1
			var sm := _mi(parent, star, pos, chrome)
			sm.rotation.x = PI * 0.5
		_:
			_bxm(parent, pos, Vector3(0.14, 0.14, 0.02), "b71c1c")

func _vehicle_model(parent: Spatial, color_hex: String, kind: int, make_idx: int) -> void:
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
	if kind == 7:
		_bxm(parent, Vector3(0, base + body_h * 0.5 + cab_h + 0.2, cab_z), Vector3(0.7, 0.22, 0.3), "f2f2f2")
		_bxm(parent, Vector3(0, base + 0.05, 0), Vector3(W + 0.01, 0.12, 1.6), "00a651")
	if kind == 8:
		_bxm(parent, Vector3(0, base + 0.1, 0), Vector3(W + 0.01, 0.18, L * 0.7), "0f5c2e")
		_bxm(parent, Vector3(-0.3, base + body_h * 0.5 + cab_h + 0.2, cab_z), Vector3(0.55, 0.16, 0.3), "flash_red")
		_bxm(parent, Vector3(0.3, base + body_h * 0.5 + cab_h + 0.2, cab_z), Vector3(0.55, 0.16, 0.3), "flash_blue")

func _vehicle_size(kind: int) -> Vector3:
	match kind:
		1: return Vector3(2.0, 1.7, 4.5)
		2: return Vector3(2.0, 1.7, 5.1)
		3: return Vector3(2.0, 2.2, 5.0)
		4: return Vector3(2.5, 3.2, 11.0)
		5: return Vector3(2.3, 2.8, 7.0)
		6: return Vector3(1.95, 1.5, 3.7)
	return Vector3(1.95, 1.5, 4.15)

func _make_vehicle(pos: Vector3, heading: float, color_hex: String, kind: int, make_idx: int) -> KinematicBody:
	var v := KinematicBody.new()
	v.translation = pos
	v.rotation.y = heading
	add_child(v)
	var vsize := _vehicle_size(kind)
	var cs := CollisionShape.new()
	var bs := BoxShape.new()
	bs.extents = vsize * 0.5
	cs.shape = bs
	cs.translation.y = vsize.y * 0.5 + 0.1
	v.add_child(cs)
	# the model is built with materials from the cache; "flash" boxes use the police light materials
	_vehicle_model(v, color_hex, kind, make_idx)
	return v

func _create_car() -> void:
	var cperp := Vector2(-start_dir.y, start_dir.x)
	var cp := start_pos - cperp * 2.4 + start_dir * 3.0
	var cheading := atan2(-start_dir.x, -start_dir.y)
	car = _make_vehicle(Vector3(cp.x, 0.08, cp.y), cheading, "eeeeea", 0, 0)
	car_heading = cheading
	car.collision_layer = 1
	car.collision_mask = 3
	all_cars.append(car)
	traffic_routes.append([])
	traffic_idx.append(0)
	traffic_speeds.append(0.0)
	traffic_wait.append(0.0)
	traffic_stuck.append(0.0)
	last_pos.append(car.translation)
	car_vel.append(0.0)
	car_kinds.append(0)
	_add_engine_sound(car)

func _build_routes() -> Array:
	var routes: Array = []
	for r in city["roads"]:
		var cls := int(r[1])
		if cls > 4:
			continue
		var pts: Array = _v2list(r[2])
		if pts.size() < 2:
			continue
		var length := 0.0
		for i in range(pts.size() - 1):
			length += (pts[i] as Vector2).distance_to(pts[i + 1])
		var near := false
		for p in pts:
			if (p as Vector2).distance_to(start_pos) < 900.0:
				near = true
				break
		if not near or length < 90.0:
			continue
		var route: Array = pts.duplicate()
		var closed: bool = (pts[0] as Vector2).distance_to(pts[pts.size() - 1]) < 1.0
		if not closed:
			for k in range(pts.size() - 2, -1, -1):
				route.append(pts[k])
		routes.append(route)
	return routes

func _create_traffic() -> void:
	var routes := _build_routes()
	if routes.empty():
		return
	var kinds := [0, 1, 0, 6, 2, 1, 3, 0, 7, 8, 1, 4, 0, 5, 6, 7, 1, 0, 8, 2, 0, 3, 1, 6, 0, 4]
	for i in range(min(kinds.size(), 14)):
		var route: Array = routes[rng.randi_range(0, routes.size() - 1)]
		var seg := rng.randi_range(0, route.size() - 2)
		for tries in range(12):
			var cand: Vector2 = route[seg]
			if cand.distance_to(start_pos) < 800.0:
				break
			seg = rng.randi_range(0, route.size() - 2)
		var a: Vector2 = route[seg]
		var b: Vector2 = route[seg + 1]
		var t := 0.2 + rng.randf() * 0.6
		var tangent := (b - a).normalized()
		var right := Vector2(-tangent.y, tangent.x)
		var xy := a.linear_interpolate(b, t) + right * 2.4
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
		last_pos.append(v.translation)
		car_vel.append(0.0)
		car_kinds.append(kind)
		_add_engine_sound(v)

func _advance_traffic(delta: float) -> void:
	for i in range(1, all_cars.size()):
		if driving and i == active_car_index:
			continue
		var v: KinematicBody = all_cars[i]
		var route: Array = traffic_routes[i]
		if route.size() < 2:
			continue
		var idx: int = int(traffic_idx[i])
		var a: Vector2 = route[idx]
		var b: Vector2 = route[idx + 1]
		var tangent := (b - a).normalized()
		var right := Vector2(-tangent.y, tangent.x)
		var target2 := b + right * 2.4
		var pos2 := Vector2(v.translation.x, v.translation.z)
		var to := target2 - pos2
		if to.length() < 5.0 or to.dot(tangent) < 0.0:
			idx += 1
			if idx >= route.size() - 1:
				idx = 0
				var first: Vector2 = route[0]
				v.translation = Vector3(first.x, 0.08, first.y)
			traffic_idx[i] = idx
			continue
		var dir2 := to.normalized()
		var forward := Vector3(dir2.x, 0.0, dir2.y)
		var rightv := Vector3(-forward.z, 0.0, forward.x)
		var blocked := false
		for j in range(all_cars.size()):
			if j == i:
				continue
			var off: Vector3 = (all_cars[j] as Spatial).translation - v.translation
			var ahead := off.dot(forward)
			if ahead > 0.5 and ahead < 9.0 and abs(off.dot(rightv)) < 2.4:
				blocked = true
				break
		if not blocked:
			var off_p: Vector3 = player.translation - v.translation
			var ahead_p := off_p.dot(forward)
			if not driving and ahead_p > 0.5 and ahead_p < 8.0 and abs(off_p.dot(rightv)) < 2.2:
				blocked = true
			if not blocked:
				for npc in npc_list:
					var off_n: Vector3 = (npc as Spatial).translation - v.translation
					var ahead_n := off_n.dot(forward)
					if ahead_n > 0.5 and ahead_n < 7.0 and abs(off_n.dot(rightv)) < 2.0:
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
		car_vel[i] = want
		v.move_and_slide(Vector3(forward.x * want, -2.0, forward.z * want), Vector3.UP)
		var moved: float = (v.translation - (last_pos[i] as Vector3)).length()
		last_pos[i] = v.translation
		if want > 1.0 and moved < 0.6 * delta:
			traffic_stuck[i] = float(traffic_stuck[i]) + delta
			if float(traffic_stuck[i]) > 6.0:
				traffic_stuck[i] = 0.0
				v.translation = Vector3(target2.x, 0.08, target2.y)
		else:
			traffic_stuck[i] = 0.0
		v.rotation.y = lerp_angle(v.rotation.y, atan2(-forward.x, -forward.z), delta * 3.0)
		var snd: AudioStreamPlayer3D = car_sounds[i]
		if want > 1.0 and not snd.playing:
			snd.play(rng.randf())
		if want <= 1.0 and snd.playing:
			snd.stop()


# ---------------------------------------------------------------- audio
func _create_audio() -> void:
	city_audio = AudioStreamPlayer.new()
	city_audio.stream = _sound("city", true)
	city_audio.volume_db = -22.0
	add_child(city_audio)
	if city_audio.stream != null:
		city_audio.play()
	horn_audio = AudioStreamPlayer.new()
	horn_audio.stream = _sound("horn", false)
	horn_audio.volume_db = -4.0
	add_child(horn_audio)
	step_audio = AudioStreamPlayer.new()
	step_audio.stream = _sound("step", false)
	step_audio.volume_db = -14.0
	add_child(step_audio)
	var birds := _sound("birds", true)
	var placed := 0
	var stride := int(max(1, int(tree_positions.size() / 22)))
	for i in range(0, tree_positions.size(), stride):
		if placed >= 22 or birds == null:
			break
		var tp: Vector3 = tree_positions[i]
		var b := AudioStreamPlayer3D.new()
		b.stream = birds
		b.translation = tp + Vector3(0, 5.0, 0)
		b.unit_size = 6.0
		b.max_distance = 30.0
		b.unit_db = -6.0
		b.pitch_scale = rng.randf_range(0.9, 1.25)
		add_child(b)
		b.play(rng.randf() * 5.0)
		placed += 1
	# Azan: put a recording at data/azan.dat (WAV format) or azan.ogg in the project root
	azan_audio = AudioStreamPlayer3D.new()
	azan_audio.translation = Vector3(0, 60, 0)
	azan_audio.unit_size = 80.0
	azan_audio.max_distance = 1500.0
	azan_audio.unit_db = 6.0
	add_child(azan_audio)
	var az := _sound("azan", false)
	if az != null:
		azan_audio.stream = az
	elif ResourceLoader.exists("res://azan.ogg"):
		azan_audio.stream = load("res://azan.ogg")
	azan_status = "AZAN: READY" if azan_audio.stream != null else "AZAN: add data/azan.dat"

func _play_azan() -> void:
	if azan_audio.stream != null:
		azan_audio.play()

func _check_prayer_times(prev_t: float, now_t: float) -> void:
	for p in [4.8, 12.2, 15.6, 18.4, 19.8]:
		if prev_t < p and now_t >= p:
			_play_azan()

func _add_engine_sound(v: Spatial) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = _sound("engine", true)
	a.unit_size = 5.0
	a.max_distance = 35.0
	a.unit_db = -12.0
	v.add_child(a)
	car_sounds.append(a)

# ---------------------------------------------------------------- light pools
func _create_lamp_pool() -> void:
	for i in range(6):
		var l := OmniLight.new()
		l.omni_range = 16.0
		l.light_color = Color(1.0, 0.86, 0.55)
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lamp_pool.append(l)
	for x in [-0.65, 0.65]:
		var s := SpotLight.new()
		s.spot_range = 38.0
		s.spot_angle = 34.0
		s.light_energy = 0.0
		s.shadow_enabled = false
		add_child(s)
		headlight_pair.append(s)
	_attach_headlights(car)

func _attach_headlights(v: Spatial) -> void:
	var offsets := [-0.65, 0.65]
	var vs := Vector3(2, 1.5, 4.2)
	var idx := all_cars.find(v)
	if idx >= 0:
		vs = _vehicle_size(int(car_kinds[idx]))
	for i in range(2):
		var s: SpotLight = headlight_pair[i]
		if s.get_parent() != null:
			s.get_parent().remove_child(s)
		v.add_child(s)
		s.translation = Vector3(offsets[i], 0.95, -vs.z * 0.5 - 0.2)
		s.rotation = Vector3.ZERO

func _update_lamp_pool(focus: Vector3, night_factor: float) -> void:
	if night_factor < 0.05:
		for l in lamp_pool:
			(l as OmniLight).light_energy = 0.0
		return
	var best := []
	for lp in lamp_positions:
		var p: Vector3 = lp
		var d := p.distance_squared_to(focus)
		if d > 2500.0:
			continue
		if best.size() < lamp_pool.size():
			best.append([d, p])
			best.sort_custom(self, "_cmp_first")
		elif d < best[best.size() - 1][0]:
			best[best.size() - 1] = [d, p]
			best.sort_custom(self, "_cmp_first")
	for i in range(lamp_pool.size()):
		var l: OmniLight = lamp_pool[i]
		if i < best.size():
			l.global_transform = Transform(Basis(), best[i][1])
			l.light_energy = 2.2 * night_factor
		else:
			l.light_energy = 0.0

# ---------------------------------------------------------------- UI
func _mk_label(text: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", _font(sz))
	l.add_color_override("font_color", col)
	return l

func _ui_button(parent: Control, caption: String, pos: Vector2, width: float, action: String) -> void:
	var b := Button.new()
	b.text = caption
	b.rect_position = pos
	b.rect_size = Vector2(width, 33)
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", _font(14))
	b.connect("pressed", self, "_ui_action", [action])
	parent.add_child(b)

func _ui_action(action: String) -> void:
	match action:
		"map":
			_toggle_map()
		"vehicles":
			_toggle_car()
		"clothes":
			_toggle_wardrobe()
		"camera":
			first_person = not first_person
		"night":
			time_of_day = 22.0 if (time_of_day < 18.0 and time_of_day > 5.0) else 10.0
		"police":
			_enter_nearest_car(true)
		"azan":
			_play_azan()
		"horn":
			_horn()

func _toggle_map() -> void:
	map_open = not map_open
	full_map.visible = map_open

func _horn() -> void:
	if horn_audio.stream != null:
		horn_audio.play()

func _create_ui() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	ui_root = Control.new()
	ui_root.rect_size = ui_base_size
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(ui_root)
	var top := ColorRect.new()
	top.color = Color(0.02, 0.035, 0.055, 0.84)
	top.rect_size = Vector2(960, 62)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(top)
	hud = _mk_label("CITY FREEDOM | MAKKAH", 22, Color(1, 0.80, 0.29))
	hud.rect_position = Vector2(20, 4)
	ui_root.add_child(hud)
	district_label = _mk_label("", 14, Color(1, 1, 1))
	district_label.rect_position = Vector2(21, 34)
	ui_root.add_child(district_label)
	time_label = _mk_label("", 18, Color(1, 1, 1))
	time_label.rect_position = Vector2(860, 6)
	ui_root.add_child(time_label)
	var left := ColorRect.new()
	left.rect_position = Vector2(0, 64)
	left.rect_size = Vector2(133, 318)
	left.color = Color(0.02, 0.035, 0.055, 0.78)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(left)
	var names := [["MAP", "map"], ["VEHICLES", "vehicles"], ["CLOTHES", "clothes"], ["CAMERA", "camera"], ["DAY / NIGHT", "night"], ["POLICE CAR", "police"], ["HORN", "horn"], ["AZAN", "azan"]]
	for i in range(names.size()):
		_ui_button(ui_root, names[i][0], Vector2(5, 68 + i * 38), 122, names[i][1])
	speed_label = _mk_label("", 28, Color(1, 0.86, 0.35))
	speed_label.rect_position = Vector2(760, 490)
	ui_root.add_child(speed_label)
	minimap = Control.new()
	minimap.set_script(load("res://minimap.gd"))
	minimap.rect_position = Vector2(8, 386)
	minimap.rect_size = Vector2(150, 150)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(minimap)
	minimap.set("roads", roads)
	minimap.set("road_cells", road_cells)
	full_map = Control.new()
	full_map.set_script(load("res://fullmap.gd"))
	full_map.rect_position = Vector2(150, 70)
	full_map.rect_size = Vector2(700, 436)
	full_map.visible = false
	ui_root.add_child(full_map)
	var map_lines := []
	for r in city["roads"]:
		if int(r[1]) <= 3:
			map_lines.append([int(r[1]), _v2list(r[2])])
	full_map.set("lines", map_lines)
	full_map.set("world_min", world_min)
	full_map.set("world_max", world_max)
	var msc: float = min(full_map.rect_size.x / (world_max.x - world_min.x), full_map.rect_size.y / (world_max.y - world_min.y))
	var moff := (full_map.rect_size - (world_max - world_min) * msc) * 0.5
	for dd in districts:
		var pp := (Vector2(float(dd[2]), float(dd[3])) - world_min) * msc + moff
		var box := _mk_label(str(dd[0]), 11, Color(1, 1, 1))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.06, 0.08, 0.85)
		st.set_corner_radius_all(4)
		st.content_margin_left = 5
		st.content_margin_right = 5
		box.add_stylebox_override("normal", st)
		box.rect_position = pp - Vector2(30, 8)
		full_map.add_child(box)
	var bottom := ColorRect.new()
	bottom.rect_position = Vector2(140, 520)
	bottom.rect_size = Vector2(820, 20)
	bottom.color = Color(0.02, 0.035, 0.055, 0.84)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bottom)
	var note := _mk_label("UP/DOWN: MOVE  LEFT/RIGHT: TURN  OK/A: CAR  H/X: HORN  C/Y: CAMERA  B: CLOTHES  M: MAP  N: NIGHT  Z: AZAN", 10, Color(1, 1, 1))
	note.rect_position = Vector2(146, 522)
	ui_root.add_child(note)
	sound_status = _mk_label("", 11, Color(1, 1, 1))
	sound_status.rect_position = Vector2(560, 8)
	ui_root.add_child(sound_status)
	_create_wardrobe_ui()
	_create_lamp_pool()
	# floating names (a pool of labels placed over the nearest named places)
	label_layer = CanvasLayer.new()
	label_layer.layer = 0
	add_child(label_layer)
	for i in range(14):
		var l := _mk_label("", 16, Color(1, 1, 1))
		l.visible = false
		label_layer.add_child(l)
		label_pool.append(l)

func _update_labels(delta: float) -> void:
	label_timer -= delta
	if label_timer <= 0.0:
		label_timer = 0.3
		var cp := camera.global_transform.origin
		var fwd := -camera.global_transform.basis.z
		var best := []
		for it in label_items:
			var pos: Vector3 = it[0]
			var maxd: float = it[3]
			var off := pos - cp
			var d2 := off.length_squared()
			if d2 > maxd * maxd or off.dot(fwd) < 0.0:
				continue
			if best.size() < label_pool.size():
				best.append([d2, it])
				best.sort_custom(self, "_cmp_first")
			elif d2 < best[best.size() - 1][0]:
				best[best.size() - 1] = [d2, it]
				best.sort_custom(self, "_cmp_first")
		label_pick = best
	for i in range(label_pool.size()):
		var l: Label = label_pool[i]
		if i < label_pick.size():
			var it: Array = label_pick[i][1]
			var pos: Vector3 = it[0]
			if camera.is_position_behind(pos):
				l.visible = false
				continue
			var sp := camera.unproject_position(pos)
			l.text = str(it[1])
			l.add_color_override("font_color", it[2])
			l.rect_position = sp - Vector2(l.get_minimum_size().x * 0.5, 10.0)
			var dist := camera.global_transform.origin.distance_to(pos)
			l.modulate.a = clamp(1.4 - dist / float(it[3]), 0.25, 1.0)
			l.visible = true
		else:
			l.visible = false

func _create_wardrobe_ui() -> void:
	wardrobe_panel = PanelContainer.new()
	wardrobe_panel.rect_position = Vector2(560, 90)
	wardrobe_panel.rect_min_size = Vector2(360, 300)
	wardrobe_panel.visible = false
	ui_root.add_child(wardrobe_panel)
	var vb := VBoxContainer.new()
	vb.add_constant_override("separation", 6)
	wardrobe_panel.add_child(vb)
	vb.add_child(_mk_label("CHANGING ROOM", 20, Color(1, 0.8, 0.3)))
	var cats := [["TOP", "top"], ["BOTTOM", "bottom"], ["SHOES", "shoes"], ["HEAD", "head"], ["GLASSES", "glasses"]]
	for i in range(cats.size()):
		var row := HBoxContainer.new()
		vb.add_child(row)
		var lb := Button.new()
		lb.text = "<"
		lb.focus_mode = Control.FOCUS_NONE
		lb.connect("pressed", self, "_wardrobe_change", [i, -1])
		row.add_child(lb)
		var lab := _mk_label("", 16, Color(1, 1, 1))
		lab.rect_min_size = Vector2(290, 34)
		lab.valign = Label.VALIGN_CENTER
		row.add_child(lab)
		var rb := Button.new()
		rb.text = ">"
		rb.focus_mode = Control.FOCUS_NONE
		rb.connect("pressed", self, "_wardrobe_change", [i, 1])
		row.add_child(rb)
		wardrobe_rows.append([cats[i][0], cats[i][1], lab])
	vb.add_child(_mk_label("UP/DOWN: choose   LEFT/RIGHT: change   B / BACK: done", 12, Color(1, 1, 1)))
	_refresh_wardrobe()

func _option_list(key: String) -> Array:
	match key:
		"top":
			return TOPS
		"bottom":
			return BOTTOMS
		"shoes":
			return SHOES
		"head":
			return HEADS
	return GLASSES

func _wardrobe_change(row: int, delta_i: int) -> void:
	wardrobe_row = row
	var key: String = wardrobe_rows[row][1]
	var opts := _option_list(key)
	outfit[key] = int(posmod(int(outfit[key]) + delta_i, opts.size()))
	_rebuild_player_visual()
	_refresh_wardrobe()

func _refresh_wardrobe() -> void:
	for i in range(wardrobe_rows.size()):
		var r: Array = wardrobe_rows[i]
		var opts := _option_list(r[1])
		var lab: Label = r[2]
		var nm: String = str(opts[int(outfit[r[1]])][0])
		lab.text = ("> " if i == wardrobe_row else "   ") + str(r[0]) + ":  " + nm
		lab.add_color_override("font_color", Color(1, 0.85, 0.35) if i == wardrobe_row else Color(0.9, 0.9, 0.88))

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
	var factor: float = min(actual.x / ui_base_size.x, actual.y / ui_base_size.y)
	ui_root.rect_scale = Vector2.ONE * factor
	ui_root.rect_position = (actual - ui_base_size * factor) * 0.5

# ---------------------------------------------------------------- input
func _active_joy() -> int:
	if joystick_device >= 0:
		return joystick_device
	var devices := Input.get_connected_joypads()
	return int(devices[0]) if devices.size() > 0 else 0

func _joy_value(axis: int) -> float:
	var device := _active_joy()
	var live := Input.get_joy_axis(device, axis)
	var saved: float = float(joystick_axes.get(axis, 0.0))
	return saved if abs(saved) > abs(live) else live

func _axis(negative: int, positive: int, joy_axis: int) -> float:
	var value := _joy_value(joy_axis)
	if abs(value) < 0.18:
		value = 0.0
	return clamp(value + float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative)), -1.0, 1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		joystick_device = event.device
		joystick_axes[event.axis] = event.axis_value
	if event is InputEventJoypadButton:
		joystick_device = event.device
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not wardrobe_open:
		yaw -= event.relative.x * 0.003
		pitch = clamp(pitch - event.relative.y * 0.002, -0.75, 0.45)
	if wardrobe_open:
		_wardrobe_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_C:
				first_person = not first_person
			KEY_E, KEY_ENTER, KEY_KP_ENTER:
				_toggle_car()
			KEY_B:
				_toggle_wardrobe()
			KEY_N:
				_ui_action("night")
			KEY_M:
				_toggle_map()
			KEY_H:
				_horn()
			KEY_Z:
				_play_azan()
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			0:
				_toggle_car()
			3:
				first_person = not first_person
			1:
				_toggle_wardrobe()
			2:
				_horn()
			10, 11:
				_toggle_map()

func _wardrobe_input(event: InputEvent) -> void:
	var row_delta := 0
	var col_delta := 0
	var close := false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_UP, KEY_W:
				row_delta = -1
			KEY_DOWN, KEY_S:
				row_delta = 1
			KEY_LEFT, KEY_A:
				col_delta = -1
			KEY_RIGHT, KEY_D, KEY_ENTER, KEY_KP_ENTER:
				col_delta = 1
			KEY_B, KEY_ESCAPE:
				close = true
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			12:
				row_delta = -1
			13:
				row_delta = 1
			14:
				col_delta = -1
			15, 0:
				col_delta = 1
			1, 10:
				close = true
	if close:
		_toggle_wardrobe()
		return
	if row_delta != 0:
		wardrobe_row = int(posmod(wardrobe_row + row_delta, wardrobe_rows.size()))
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
	var daylight: float = clamp(sin(a) * 2.0, 0.0, 1.0)
	var night_factor: float = 1.0 - clamp(daylight * 3.0, 0.0, 1.0)
	sun_light.global_transform = Transform(Basis(), Vector3.ZERO).looking_at(-sun_dir, Vector3.UP)
	moon_light.global_transform = Transform(Basis(), Vector3.ZERO).looking_at(-moon_dir, Vector3.UP)
	sun_light.light_energy = 0.05 + daylight * 1.1
	sun_light.visible = sun_dir.y > -0.08
	moon_light.light_energy = clamp(moon_dir.y, 0.0, 1.0) * 0.55
	moon_light.visible = moon_dir.y > 0.0
	var dusk: float = clamp(1.0 - abs(daylight - 0.22) * 4.0, 0.0, 1.0) * clamp(daylight * 10.0, 0.0, 1.0)
	var top_c := Color(0.02, 0.04, 0.10).linear_interpolate(Color(0.30, 0.52, 0.86), daylight)
	var hor_c := Color(0.05, 0.08, 0.15).linear_interpolate(Color(0.76, 0.86, 0.95), daylight)
	hor_c = hor_c.linear_interpolate(Color(1.0, 0.56, 0.30), dusk * 0.55)
	top_c = top_c.linear_interpolate(Color(0.45, 0.40, 0.62), dusk * 0.25)
	city_env.background_color = top_c
	city_env.fog_color = hor_c
	city_env.ambient_light_color = Color(0.30, 0.36, 0.55).linear_interpolate(Color(0.85, 0.83, 0.76), daylight)
	city_env.ambient_light_energy = 0.32 + daylight * 0.5
	for entry in night_mats:
		var m: SpatialMaterial = entry[0]
		m.emission_energy = lerp(float(entry[1]), float(entry[2]), night_factor)
	cloud_mat.albedo_color = Color(0.25 + 0.75 * daylight, 0.27 + 0.73 * daylight, 0.35 + 0.65 * daylight, 0.9)
	for cloud in cloud_nodes:
		var c: Spatial = cloud
		c.translation.x += delta * 3.0
		if c.translation.x > world_max.x + 600.0:
			c.translation.x = world_min.x - 600.0
	for s in headlight_pair:
		(s as SpotLight).light_energy = (3.0 * night_factor) if driving else 0.0
	flash_clock += delta
	var phase := int(flash_clock * 4.0) % 2 == 0
	if police_flash_mats.size() >= 2:
		var boost := 1.5 + 3.5 * night_factor
		(police_flash_mats[0] as SpatialMaterial).emission_energy = boost if phase else 0.2
		(police_flash_mats[1] as SpatialMaterial).emission_energy = 0.2 if phase else boost
	lamp_timer -= delta
	if lamp_timer <= 0.0:
		lamp_timer = 0.4
		var focus := car.translation if driving else player.translation
		_update_lamp_pool(focus, night_factor)
	sun_mesh.visible = sun_dir.y > -0.05
	moon_mesh.visible = moon_dir.y > -0.05
	set_meta("sun_dir", sun_dir)
	set_meta("moon_dir", moon_dir)

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	frame_count += 1
	render_cull_clock += delta
	if render_cull_clock >= 0.4:
		render_cull_clock = 0.0
		_cull_render_chunks()
		_stream_building_collisions()
	if selftest and frame_count > 240:
		get_tree().quit()
	environment_update_clock += delta
	if environment_update_clock >= 0.10:
		_update_time(environment_update_clock)
		environment_update_clock = 0.0
	# move_and_slide uses the engine physics timestep, so cars and pedestrians
	# must be advanced on every physics tick (10 Hz made them ~6x slower).
	_advance_traffic(delta)
	_update_npcs(delta)
	_update_pilgrims(delta)
	if wardrobe_open:
		_wardrobe_camera(delta)
		_update_hud(delta)
		_update_labels(delta)
		return
	var lx := _axis(KEY_A, KEY_D, 0)
	var ly := _axis(KEY_W, KEY_S, 1)
	# Android TV remotes and many controllers send D-pad as buttons rather than axes.
	lx += float(Input.is_joy_button_pressed(_active_joy(), 15)) - float(Input.is_joy_button_pressed(_active_joy(), 14))
	ly += float(Input.is_joy_button_pressed(_active_joy(), 13)) - float(Input.is_joy_button_pressed(_active_joy(), 12))
	lx = clamp(lx, -1.0, 1.0)
	ly = clamp(ly, -1.0, 1.0)
	var arrows_turn := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	var arrows_move := float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
	ly = clamp(ly + arrows_move, -1.0, 1.0)
	var rx := _joy_value(2)
	var ry := _joy_value(3)
	if abs(rx) > 0.15:
		yaw -= rx * delta * 2.2
	if abs(ry) > 0.15:
		pitch = clamp(pitch - ry * delta * 1.6, -0.75, 0.45)
	if driving:
		var steer_in: float = clamp(lx + arrows_turn, -1.0, 1.0)
		var gas_key: float = clamp(float(Input.is_key_pressed(KEY_W)) + float(Input.is_key_pressed(KEY_UP)), 0.0, 1.0)
		var brake_key: float = clamp(float(Input.is_key_pressed(KEY_S)) + float(Input.is_key_pressed(KEY_DOWN)), 0.0, 1.0)
		var gas: float = clamp(max(max(0.0, _joy_value(7)), max(gas_key, max(0.0, -ly))), 0.0, 1.0)
		var brake: float = clamp(max(max(0.0, _joy_value(6)), max(brake_key, max(0.0, ly))), 0.0, 1.0)
		var top_speed := 32.0
		if int(car_kinds[active_car_index]) == 4:
			top_speed = 20.0
		var target_speed := gas * top_speed - brake * 7.0
		var accel := 17.0 if gas > 0.1 else (13.0 if brake > 0.1 else 8.0)
		speed = move_toward(speed, target_speed, accel * delta)
		var steer_strength: float = lerp(1.9, 0.75, clamp(abs(speed) / 32.0, 0.0, 1.0))
		if abs(speed) > 0.5:
			car_heading -= steer_in * delta * steer_strength * sign(speed)
		car.rotation.y = car_heading
		car.move_and_slide(Vector3(-sin(car_heading) * speed, -2.0, -cos(car_heading) * speed), Vector3.UP)
		car_vel[active_car_index] = speed
		for ci in range(car.get_slide_count()):
			var hit = car.get_slide_collision(ci)
			if abs(hit.normal.y) < 0.45:
				speed *= 0.35
				break
		var snd: AudioStreamPlayer3D = car_sounds[active_car_index]
		snd.pitch_scale = 0.75 + abs(speed) / 32.0 * 1.3
		if abs(speed) > 0.4 and not snd.playing:
			snd.play()
		if abs(speed) < 0.4 and snd.playing:
			snd.stop()
		player.translation = car.translation + Vector3(0, 2.7, 0)
	else:
		yaw -= arrows_turn * delta * 1.8
		var forward := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var move := (right * lx - forward * ly).limit_length(1.0)
		var walk_speed := 7.0 if Input.is_key_pressed(KEY_SHIFT) else 4.2
		player.move_and_slide(Vector3(move.x * walk_speed, -2.0, move.z * walk_speed), Vector3.UP)
		var moving := move.length() > 0.1
		if moving:
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-move.x, -move.z), delta * 10.0)
			walk_clock += delta * 8.0
			var sgn: float = sign(sin(walk_clock))
			if sgn != last_step_sign:
				last_step_sign = sgn
				if step_audio.stream != null:
					step_audio.pitch_scale = rng.randf_range(0.9, 1.15)
					step_audio.play()
		_animate_walker(player_visual, walk_clock, moving)
	_update_camera()
	hud_update_clock += delta
	if hud_update_clock >= 0.12:
		_update_hud(hud_update_clock)
		hud_update_clock = 0.0
	_update_labels(delta)

func _update_camera() -> void:
	var focus := car.translation if driving else player.translation
	var camera_yaw := car_heading if driving else yaw
	var facing := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
	if first_person:
		if driving:
			camera.translation = focus + Vector3(0, 1.5, 0) + facing * 0.4
		else:
			camera.translation = focus + Vector3(0, 1.45, 0) + facing * 0.2
	else:
		var dist := 6.5
		if driving:
			dist = 5.5 + _vehicle_size(int(car_kinds[active_car_index])).z * 0.5
		camera.translation = focus - facing * dist + Vector3(0, 3.5 if driving else 2.6, 0)
	camera.look_at(focus + facing * 7.0 + Vector3(0, 1.3 + pitch * 8.0, 0), Vector3.UP)
	player.visible = not driving and not first_person
	_place_sky()

func _place_sky() -> void:
	var sd: Vector3 = get_meta("sun_dir", Vector3(0.0, 1.0, 0.0))
	var md: Vector3 = get_meta("moon_dir", Vector3(0.0, -1.0, 0.0))
	sun_mesh.translation = camera.translation + sd * 3500.0
	moon_mesh.translation = camera.translation + md * 3500.0

func _wardrobe_camera(delta: float) -> void:
	wardrobe_spin += delta * 0.6
	player.rotation.y = wardrobe_spin
	player.visible = true
	camera.translation = player.translation + Vector3(0.0, 1.15, 3.0)
	camera.look_at(player.translation + Vector3(0, 0.95, 0), Vector3.UP)
	_place_sky()

func _update_hud(delta: float) -> void:
	var focus := car.translation if driving else player.translation
	var dist_name: Array = _district_at(Vector2(focus.x, focus.z))
	district_label.text = "%s  |  %s  |  %02d:%02d  |  %s" % [str(dist_name[0]).to_upper(), "DRIVING" if driving else "WALKING", int(time_of_day), int(fposmod(time_of_day, 1.0) * 60.0), "1ST PERSON" if first_person else "3RD PERSON"]
	speed_label.text = ("%02d KM/H" % int(abs(speed) * 3.6)) if driving else "ON FOOT"
	time_label.text = "%02d:%02d" % [int(time_of_day), int(fposmod(time_of_day, 1.0) * 60.0)]
	sound_status.text = azan_status
	minimap.set("player_xy", Vector2(focus.x, focus.z))
	minimap.update()
	if map_open:
		map_redraw_timer -= delta
		if map_redraw_timer <= 0.0:
			map_redraw_timer = 0.25
			full_map.set("player_xy", Vector2(focus.x, focus.z))
			full_map.set("heading", car_heading if driving else yaw)
			full_map.update()

# ---------------------------------------------------------------- cars: enter / exit
func _enter_nearest_car(police_only: bool = false) -> void:
	var best := -1
	var best_d := 8.0
	for i in range(all_cars.size()):
		if police_only and int(car_kinds[i]) != 8:
			continue
		var cand: Spatial = all_cars[i]
		var d := player.translation.distance_to(cand.translation)
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
		player.translation = car.translation + car.global_transform.basis.x * 3.0 + Vector3(0, 0.3, 0)
		yaw = car_heading
	else:
		_enter_nearest_car()
