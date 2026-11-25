extends Node3D
## Світ: небо-панорама (день/ніч), сонце й місяць, земля з травою, пагорби на обрії,
## подвір'я (хата, тин, дерева, соняшники, будка, криниця, лавка) і кімната з тераріумом.
## Усе, чого ще немає моделлю з Meshy, будується простими формами.

const ROOM := Vector3(0, 0, -900)           # кімната стоїть окремо, далеко за межами світу
const YARD := Rect2(-21.0, -15.0, 30.0, 20.0) # x, z — межі двору всередині тину (подвір'я вдвічі більше)
const HOUSE_POS := Vector3(0, 0, -10.3)

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var room_light: OmniLight3D
var window_lights: Array = []       # теплі вогники у вікнах хати
var window_mats: Array = []
var window_quads: Array = []
var room_windows: Array = []
var fireflies: CPUParticles3D
var grass: MultiMeshInstance3D
var house: Node3D
var yard_flower_heads: Array = []   # куди літають бджоли
var doors := {}                     # назва → [петля, кут зачинених, напрям відчинення]
var outer                           # відкритий світ за ворітьми
var room_door_light: MeshInstance3D
var well_crank: Node3D              # коловорот криниці (крутиться)
var well_bucket: Node3D             # відро криниці (опускається й піднімається)
var well_rope: MeshInstance3D
var _well_busy := false
var spots := {}                     # іменовані точки: миска, будка, лавка, двері…
var props := {}                     # розставлені моделі: назва → [вузли]
var room_root: Node3D
var yard_root: Node3D
var _t := 0.0
var _day_tex: Texture2D = preload("res://assets/sky/day.jpg")
var _night_tex: Texture2D = preload("res://assets/sky/night.jpg")


func _ready() -> void:
	_make_environment()
	yard_root = Node3D.new()
	add_child(yard_root)
	room_root = Node3D.new()
	room_root.position = ROOM
	add_child(room_root)
	_make_ground()
	_make_horizon()
	_make_yard()
	_make_room()
	_make_fireflies()
	_register_obstacles()
	update_time(true)


# ------------------------------------------------------------------ небо, світло
func _make_environment() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform sampler2D day_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D night_tex : source_color, filter_linear, repeat_enable;
uniform float night = 0.0;
uniform vec3 tint = vec3(1.0);
uniform float spin = 0.0;
void sky() {
	vec3 d = normalize(EYEDIR);
	float u = atan(d.x, -d.z) / 6.2831853 + 0.5 + spin;
	// горизонт картинки трохи нижче середини (≈0.47) — підганяємо під лінію землі
	float v = acos(clamp(d.y, -1.0, 1.0)) / 3.14159265;
	v = v < 0.5 ? v * 0.94 : 0.47 + (v - 0.5) * 1.06;
	vec2 uv = vec2(fract(u), clamp(v, 0.002, 0.998));
	vec3 c = mix(texture(day_tex, uv).rgb, texture(night_tex, uv).rgb, night);
	COLOR = c * tint;
}
"""
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("day_tex", load("res://assets/sky/day.jpg"))
	sky_mat.set_shader_parameter("night_tex", load("res://assets/sky/night.jpg"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.76
	env.fog_enabled = true
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_blur = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.rotation_degrees = Vector3(-50, 30, 0)
	add_child(moon)


var in_building := false               # Ніка всередині хати, ларька чи церкви (main.gd)


func update_time(_force := false) -> void:
	## Сонце, місяць, кольори неба й туману, вогники — за часом доби з Game.
	var h := Game.hour()
	var n := Game.night_amount()
	# сонце: сходить о 6 на сході, о 13 найвище, сідає о 20 на заході
	var k := clampf((h - 6.0) / 14.0, 0.0, 1.0)
	var elev := sin(k * PI) * 58.0 + 4.0
	sun.rotation_degrees = Vector3(-elev, lerpf(-100.0, 100.0, k), 0)
	# тепле світло зранку й увечері, біле вдень
	var warm := 1.0 - clampf(abs(h - 13.0) / 6.0, 0.0, 1.0)
	var sun_col := Color(1.0, 0.72, 0.5).lerp(Color(1.0, 0.96, 0.9), warm)
	sun.light_color = sun_col
	var indoor: bool = Game.state["location"] == "room"
	sun.light_energy = 0.86 * (1.0 - n) * (0.35 if indoor else (0.45 if in_building else 1.0))
	# Ніка в хаті чи церкві: сонячні тіні вимкнено — інакше світло між колодами й вікнами
	# лягає смугами на підлогу, і вона мерехтить, коли камера рухається
	sun.shadow_enabled = not in_building
	sun.visible = n < 0.97
	moon.light_energy = 0.32 * n
	moon.visible = n > 0.03
	var amb_day := Color(0.78, 0.8, 0.86)
	var amb_night := Color(0.22, 0.27, 0.45)
	env.ambient_light_color = amb_day.lerp(amb_night, n)
	env.ambient_light_energy = lerpf(0.5, 0.55, n) * (0.55 if indoor else 1.0)
	var dusk := clampf(1.0 - abs(n - 0.5) * 2.0, 0.0, 1.0)     # найбільше на межі дня й ночі
	var tint := Color(0.86, 0.86, 0.88).lerp(Color(0.95, 0.78, 0.72), dusk * 0.8)
	sky_mat.set_shader_parameter("night", n)
	sky_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	env.fog_light_color = Color(0.7, 0.78, 0.82).lerp(Color(0.16, 0.2, 0.36), n).lerp(Color(0.95, 0.75, 0.62), dusk * 0.5)
	# вогники: вікна хати, кімнати, світлячки
	for l in window_lights:
		(l as OmniLight3D).light_energy = 1.4 * smoothstep(0.3, 0.8, n)
	var night_win := n > 0.5
	for w in room_windows:
		var want: Texture2D = _night_tex if night_win else _day_tex
		if (w as StandardMaterial3D).albedo_texture != want:
			(w as StandardMaterial3D).albedo_texture = want
	for q in window_quads:
		(q as Node3D).visible = n > 0.25
	for m in window_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 2.2 * smoothstep(0.3, 0.8, n)
		(m as StandardMaterial3D).albedo_color = Color(0.35, 0.3, 0.25).lerp(Color(1.0, 0.8, 0.45), smoothstep(0.3, 0.8, n))
	if fireflies:
		fireflies.emitting = n > 0.6 and Game.state["location"] == "yard"
	if room_light:
		room_light.light_energy = lerpf(1.6, 1.8, n)


func _process(delta: float) -> void:
	_t += delta
	update_time()
	# двері, які хтось забув зачинити, зачиняються самі
	for n in _door_open_t.keys():
		_door_open_t[n] = float(_door_open_t[n]) + delta
		if float(_door_open_t[n]) > (14.0 if n == "gate" else 7.0):
			set_door(n, false, 0.6)
	if water_bowl_water:
		water_bowl_water.visible = float(Game.state.get("water_bowl", 0.0)) > 1.0
		trough_water.visible = float(Game.state.get("trough", 0.0)) > 1.0
		grain.visible = float(Game.state.get("hens_fed", 0.0)) > 40.0
		if room_door_light:
			(room_door_light.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.92, 0.75).lerp(Color(0.08, 0.1, 0.22), Game.night_amount())
		_field_t += delta
		if _field_t > 0.1:
			_field_t = 0.0
			_update_field(_t)


# ------------------------------------------------------------------ земля, трава, обрій
func _make_ground() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 grass_a : source_color = vec3(0.26, 0.45, 0.15);
uniform vec3 grass_b : source_color = vec3(0.4, 0.56, 0.21);
uniform vec3 dirt : source_color = vec3(0.58, 0.45, 0.3);
uniform vec3 far_col : source_color = vec3(0.42, 0.54, 0.3);
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_tex = 0.0;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nz(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a; vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float n = nz(p * 0.18) * 0.55 + nz(p * 0.7) * 0.3 + nz(p * 3.0) * 0.15;
	vec3 g = mix(grass_a, grass_b, n);
	vec3 gt = texture(grass_tex, p / 3.2).rgb;
	vec3 st = texture(sand_tex, p / 2.6).rgb;
	g = mix(g, g * gt / vec3(0.325, 0.494, 0.141), use_tex * 0.9);
	// стежки: від воріт до хати, до криниці, до будки; витоптане місце біля ґанку
	float d = seg(p, vec2(0.0, 6.0), vec2(-0.7, -6.6));
	d = min(d, seg(p, vec2(0.0, -2.5), vec2(5.8, -4.2)));
	d = min(d, seg(p, vec2(0.0, -3.5), vec2(-4.6, -5.0)));
	d = min(d, seg(p, vec2(-4.6, -5.0), vec2(-15.5, -8.0)));
	d = min(d, seg(p, vec2(-4.6, -5.0), vec2(-13.0, -2.0)));
	d = min(d, seg(p, vec2(0.0, 6.0), vec2(0.0, 9.0)));
	d = min(d, seg(p, vec2(0.0, 9.0), vec2(-14.0, 12.5)));
	// відкритий світ: дорога до села й за річку, стежки до ставка, вітряка й поля
	d = min(d, seg(p, vec2(0.0, 9.0), vec2(0.0, 150.0)));
	d = min(d, length(p - vec2(0.0, 60.0)) - 9.0);
	d = min(d, seg(p, vec2(0.0, 30.0), vec2(-46.0, 22.0)));
	d = min(d, seg(p, vec2(-46.0, 22.0), vec2(-72.0, -30.0)));
	d = min(d, seg(p, vec2(0.0, 36.0), vec2(26.0, 32.0)));
	// дорога до грибного лісу (на півночі): від воріт на захід, повз подвір'я й далі до лісу
	d = min(d, seg(p, vec2(0.0, 9.0), vec2(-24.0, 8.5)));
	d = min(d, seg(p, vec2(-24.0, 8.5), vec2(-24.0, -50.0)));
	d = min(d, seg(p, vec2(-24.0, -50.0), vec2(-29.0, -70.0)));
	d = min(d, seg(p, vec2(-29.0, -70.0), vec2(-30.0, -82.0)));
	d = min(d, length(p - vec2(-30.0, -84.0)) - 2.0);
	d = min(d, length(p - vec2(0.0, -6.6)) - 1.6);
	float w = 0.75 + nz(p * 1.3) * 0.35;
	float path = 1.0 - smoothstep(w - 0.25, w + 0.15, d);
	vec3 dc = dirt * (0.9 + nz(p * 4.0) * 0.2);
	dc = mix(dc, dc * st / vec3(0.83, 0.70, 0.55), use_tex);
	vec3 c = mix(g, dc, path);
	// пісочок на берегах річки й ставка
	float bank = 1.0 - smoothstep(4.0, 7.0, abs(p.y - 102.0));
	vec2 pq = abs(p - vec2(-70.0, 31.0)) - vec2(15.0, 8.0);      // ставок: прямокутник 42×28 м, кути R 6 м
	float psd = length(max(pq, vec2(0.0))) + min(max(pq.x, pq.y), 0.0) - 6.0;
	bank = max(bank, 1.0 - smoothstep(1.0, 3.5, psd));
	c = mix(c, mix(vec3(0.78, 0.7, 0.5), vec3(0.78, 0.7, 0.5) * st / vec3(0.83, 0.70, 0.55), use_tex), bank * 0.85);
	float far = smoothstep(160.0, 420.0, length(p - vec2(0.0, 20.0)));
	ALBEDO = mix(c, far_col, far * 0.7);
	ROUGHNESS = 1.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	if ResourceLoader.exists("res://assets/textures/grass.jpg") and ResourceLoader.exists("res://assets/textures/sand.jpg"):
		m.set_shader_parameter("grass_tex", load("res://assets/textures/grass.jpg"))
		m.set_shader_parameter("sand_tex", load("res://assets/textures/sand.jpg"))
		m.set_shader_parameter("use_tex", 1.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1000, 1000)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var g := MeshInstance3D.new()
	g.mesh = pm
	g.material_override = m
	yard_root.add_child(g)
	_make_grass()


func _grass_mesh() -> ArrayMesh:
	## Пучок трави з п'яти травинок; колір від темного низу до світлого верху.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var a := float(i) / 5.0 * TAU + randf() * 0.6
		var off := Vector3(cos(a), 0, sin(a)) * 0.05
		var lean := Vector3(cos(a), 0, sin(a)) * randf_range(0.04, 0.1)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.025
		var hgt := randf_range(0.22, 0.38)
		st.set_color(Color(0.16, 0.32, 0.09))
		st.add_vertex(off - side)
		st.add_vertex(off + side)
		st.set_color(Color(0.46, 0.64, 0.24))
		st.add_vertex(off + lean + Vector3(0, hgt, 0))
	st.generate_normals()
	return st.commit()


func _make_grass() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform float t = 0.0;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = VERTEX.y * 2.5;
	VERTEX.x += sin(TIME * 1.7 + w.x * 0.6 + w.z * 0.4) * 0.05 * k;
	VERTEX.z += cos(TIME * 1.3 + w.x * 0.3) * 0.03 * k;
}
void fragment() { ALBEDO = COLOR.rgb; ROUGHNESS = 1.0; }
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = _grass_mesh()
	var pts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while pts.size() < 4200:
		var p := Vector3(rng.randf_range(-27, 16), 0, rng.randf_range(-19, 10))
		if _in_building(p):
			continue
		if _on_path(Vector2(p.x, p.z)) or _in_house(p):
			continue
		if p.x > 10.9 and p.x < 18.0 and p.z > -9.8 and p.z < 0.8 and fmod(p.x - 10.75, 1.2) < 0.8:
			continue     # на грядках городу трава не росте
		if Vector2(p.x + 6.4, p.z + 7.3).length() < 1.15:
			continue     # ряднина під деревом
		pts.append(p)
	mm.instance_count = pts.size()
	for i in pts.size():
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
		mm.set_instance_transform(i, Transform3D(b, pts[i]))
	grass = MultiMeshInstance3D.new()
	grass.multimesh = mm
	grass.material_override = mat
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	yard_root.add_child(grass)
	# квіточки серед трави
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 3
	fm.mesh = sm
	var cols := [Color(1, 1, 1), Color(1, 0.85, 0.2), Color(0.75, 0.55, 1), Color(1, 0.55, 0.6), Color(0.5, 0.7, 1)]
	var fl: Array = []
	while fl.size() < 360:
		var p := Vector3(rng.randf_range(-15, 15), rng.randf_range(0.12, 0.28), rng.randf_range(-15, 9))
		if _on_path(Vector2(p.x, p.z)) or _in_house(p):
			continue
		fl.append(p)
	fm.instance_count = fl.size()
	for i in fl.size():
		fm.set_instance_transform(i, Transform3D(Basis(), fl[i]))
		fm.set_instance_color(i, cols[rng.randi() % cols.size()])
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.roughness = 0.8
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fm
	fmi.material_override = fmat
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	yard_root.add_child(fmi)


func _on_path(p: Vector2) -> bool:
	var d := _seg(p, Vector2(0, 6), Vector2(-0.7, -6.6))
	d = minf(d, _seg(p, Vector2(0, -2.5), Vector2(5.8, -4.2)))
	d = minf(d, _seg(p, Vector2(0, -3.5), Vector2(-4.6, -5.0)))
	d = minf(d, _seg(p, Vector2(-4.6, -5.0), Vector2(-15.5, -8.0)))
	d = minf(d, _seg(p, Vector2(-4.6, -5.0), Vector2(-13.0, -2.0)))
	d = minf(d, _seg(p, Vector2(0, 9.0), Vector2(-14.0, 12.5)))
	d = minf(d, p.distance_to(Vector2(0, -6.6)) - 1.6)
	return d < 0.95


const BARN_POS := Vector3(-15.5, 0, -11.2)      # сарай (дверима до подвір'я)
const SHOP_POS := Vector3(-16.5, 0, -2.0)       # майстерня (відкритий бік — до подвір'я)
const KID_HOME := Vector3(-14.0, 0, 15.5)       # хата Тарасика за дорогою
const PAD_POS := Vector3(3.8, 0, -8.4)          # майданчик для дрона біля хати


func _in_building(p: Vector3) -> bool:
	return (abs(p.x - BARN_POS.x) < 3.6 and abs(p.z - BARN_POS.z) < 2.9) \
		or (abs(p.x - SHOP_POS.x) < 2.6 and abs(p.z - SHOP_POS.z) < 2.3)


func _planks_mat(col: Color, horizontal := false) -> ShaderMaterial:
	## Дошки: смужки за координатами світу, з темними щілинами й різним відтінком кожної дошки.
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 col : source_color;
uniform float horiz = 0.0;
varying vec3 wp;
float h(float x) { return fract(sin(x * 91.7) * 4375.85); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float a = mix(wp.x + wp.z, wp.y * 1.3, horiz) * 4.0;
	float id = floor(a);
	float f = fract(a);
	float gap = smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f);
	float grain = sin((mix(wp.y, wp.x + wp.z, horiz)) * 23.0 + id * 3.0) * 0.04;
	vec3 c = col * (0.85 + h(id) * 0.25 + grain);
	ALBEDO = mix(col * 0.45, c, gap);
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("horiz", 1.0 if horizontal else 0.0)
	return m


func _gable(parent: Node3D, w: float, d: float, h: float, wall_h: float, roof: Material, pos: Vector3) -> void:
	## Двосхилий дах з двох похилих площин (гребінь уздовж осі X).
	var half := d / 2.0 + 0.35
	var slope := sqrt(half * half + h * h)
	var ang := atan2(h, half)
	for sgn in [-1.0, 1.0]:
		var pl := Util.box(Vector3(w + 0.6, 0.12, slope), roof, pos + Vector3(0, wall_h + h / 2.0, sgn * half / 2.0))
		pl.rotation.x = sgn * ang
		parent.add_child(pl)


func _make_barn() -> void:
	## Сарай: дерев'яні стіни, червонуватий дах, великі двостулкові двері з хрестовинами, сіно всередині видно в щілину.
	var n := Node3D.new()
	n.position = BARN_POS
	yard_root.add_child(n)
	var W := 6.0
	var D := 4.6
	var H := 3.0
	var wall := _planks_mat(Color(0.62, 0.38, 0.24))
	var trim := Util.mat(Color(0.92, 0.88, 0.8), 0.8)
	# сарай порожнистий: Ніка заходить у двері; всередині сіно, дідове сідло з вуздечкою й реманент під стіною
	var V := 1.2
	var sb := StaticBody3D.new()
	sb.collision_layer = 1 << 17
	sb.collision_mask = 0
	n.add_child(sb)
	var wall_at := func(size: Vector3, pos: Vector3) -> void:
		n.add_child(Util.box(size, wall, pos))
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = size
		cs.shape = bx
		cs.position = pos
		sb.add_child(cs)
	wall_at.call(Vector3(W, H, 0.08), Vector3(0, H / 2.0, -D / 2.0 + 0.04))
	for sx in [-1.0, 1.0]:
		wall_at.call(Vector3(0.08, H, D), Vector3(sx * (W / 2.0 - 0.04), H / 2.0, 0))
		wall_at.call(Vector3(W / 2.0 - 1.25, H, 0.08), Vector3(sx * (W / 2.0 + 1.25) / 2.0, H / 2.0, D / 2.0 - 0.04))
	n.add_child(Util.box(Vector3(2.5, H - 2.3, 0.08), wall, Vector3(0, (H + 2.3) / 2.0, D / 2.0 - 0.04)))
	n.add_child(Util.box(Vector3(W, 0.05, D), wall, Vector3(0, H - 0.025, 0)))
	n.add_child(Util.box(Vector3(W - 0.16, 0.03, D - 0.16), Util.mat(Color(0.78, 0.65, 0.38), 1.0), Vector3(0, 0.015, 0)))
	var hay := Util.mat(Color(0.9, 0.76, 0.36), 1.0)
	n.add_child(Util.sphere(1.0, hay, Vector3(-1.6, 0.35, -D / 2.0 + 0.9), Vector3(1.3, 0.75, 0.8)))
	n.add_child(Util.sphere(0.8, hay, Vector3(-0.3, 0.3, -D / 2.0 + 0.8), Vector3(1.2, 0.7, 0.8)))
	_barn_tack(n, D / 2.0 - V)
	_barn_tools(n, W, D)
	walk_in.append([n, AABB(Vector3(-W / 2.0, 0, -D / 2.0), Vector3(W, H, D))])
	# фронтон (трикутник над дверима) — двосхилий дах ховає верх
	var gab := Util.mesh(PrismMesh.new(), wall, Vector3(0, H + 0.8, 0), Vector3.ZERO, Vector3(W, 1.6, D))
	n.add_child(gab)
	_gable(n, W, D, 1.7, H, _planks_mat(Color(0.55, 0.22, 0.16), true), Vector3.ZERO)
	# двері (дві стулки на петлях — відчиняються назовні, коли хтось підходить)
	var door := _planks_mat(Color(0.5, 0.3, 0.18))
	for sx in [-1.0, 1.0]:
		var hg := Node3D.new()
		hg.position = Vector3(sx * 1.265, 0, D / 2.0 + 0.04)
		n.add_child(hg)
		var lx: float = -sx * 0.625
		var leaf := Util.box(Vector3(1.25, 2.3, 0.08), door, Vector3(lx, 1.15, 0))
		hg.add_child(leaf)
		for k in [1, -1]:
			var br := Util.box(Vector3(0.1, 2.5, 0.04), trim, Vector3(lx, 1.15, 0.06))
			br.rotation.z = k * 0.48
			hg.add_child(br)
		hg.add_child(Util.box(Vector3(1.25, 0.1, 0.04), trim, Vector3(lx, 2.25, 0.06)))
		hg.add_child(Util.box(Vector3(1.25, 0.1, 0.04), trim, Vector3(lx, 0.05, 0.06)))
		doors["barn_l" if sx < 0.0 else "barn_r"] = [hg, 0.0, sx]
	add_auto_door("barn", ["barn_l", "barn_r"], BARN_POS + Vector3(0, 0, D / 2.0 + 0.6), 2.6)
	# віконце під дахом із сіном
	n.add_child(Util.box(Vector3(1.0, 0.7, 0.05), Util.mat(Color(0.12, 0.08, 0.05), 1.0), Vector3(0, H + 0.35, D / 2.0 + 0.02)))
	n.add_child(Util.sphere(0.45, Util.mat(Color(0.9, 0.75, 0.35), 1.0), Vector3(0, H + 0.2, D / 2.0 + 0.05), Vector3(1.0, 0.45, 0.3)))
	# кути білим
	for cx in [-W / 2.0, W / 2.0]:
		for cz in [-D / 2.0, D / 2.0]:
			n.add_child(Util.box(Vector3(0.14, H, 0.14), trim, Vector3(cx, H / 2.0, cz)))
	n.add_child(Util.pick_area("barn", Vector3(W, H + 1.5, D), Vector3(0, (H + 1.5) / 2.0, 0)))
	spots["barn"] = BARN_POS + Vector3(0, 0, D / 2.0 + 0.9)
	# біля сараю: тачка й копиця
	var wb := Models.spawn(yard_root, "wheelbarrow", 0.75)
	if wb:
		wb.position = BARN_POS + Vector3(3.9, 0, 2.0)
		wb.rotation.y = deg_to_rad(-30)


var walk_in: Array = []              # будівлі подвір'я, куди Ніка заходить: [вузол, коробка в його системі]


func _barn_tools(n: Node3D, W: float, D: float) -> void:
	## Дідів реманент під правою стіною: граблі, лопата, вила, сапа, мітла; сокира — у колоді.
	var x := W / 2.0 - 0.2
	var z := -D / 2.0 + 0.5
	for k in ["rake", "shovel", "fork", "hoe", "broom"]:
		var t := Util.thing(k)
		if t == null:
			continue
		n.add_child(t)
		t.position = Vector3(x - 0.1, 0, z)
		t.rotation = Vector3(0.16, PI / 2.0, 0)
		z += 0.42
	var block := Util.cyl(0.2, 0.22, 0.4, Util.mat(Color(0.5, 0.36, 0.22), 0.9), Vector3(x - 0.45, 0.2, z + 0.4))
	n.add_child(block)
	var ax := Util.thing("axe")
	if ax:
		n.add_child(ax)
		ax.position = Vector3(x - 0.45, 0.4, z + 0.4)
		ax.rotation = Vector3(0.35, 0.4, 0)
	var hm := Util.thing("hammer")
	if hm:
		n.add_child(hm)
		hm.position = Vector3(x - 0.2, 0.0, z + 0.9)
		hm.rotation = Vector3(PI / 2.0, 0, 0)


func _barn_tack(n: Node3D, wall_z: float) -> void:
	## Дідове сідло на козлах і вуздечка на кілку (моделі saddle.glb, bridle.glb з Blender).
	if not Models.exists("saddle"):
		return
	var wood := Util.mat(Color(0.42, 0.28, 0.17), 0.9)
	var at := Vector3(-0.55, 0, wall_z + 0.55)
	n.add_child(Util.mesh(PrismMesh.new(), wood, at + Vector3(0, 0.85, 0), Vector3(0, 90, 0), Vector3(0.5, 0.3, 0.7)))
	for sx in [-0.3, 0.3]:
		for sz in [-0.12, 0.12]:
			n.add_child(Util.box(Vector3(0.05, 0.72, 0.05), wood, at + Vector3(sx, 0.36, sz)))
	var sd: Node3D = load(Models.DIR % "saddle").instantiate()
	sd.position = at
	n.add_child(sd)
	if Models.exists("bridle"):
		var peg := Vector3(0.75, 1.95, wall_z + 0.25)
		n.add_child(Util.box(Vector3(0.04, 0.04, 0.3), wood, peg - Vector3(0, 0, 0.12)))
		var br: Node3D = load(Models.DIR % "bridle").instantiate()
		br.basis = Basis(Vector3.UP, -PI / 2.0)
		br.position = peg - br.basis * Vector3(-1.3, 1.4, 0)
		n.add_child(br)


func _make_workshop() -> void:
	## Майстерня: навіс на стовпах із задньою й бічними стінами; всередині верстак і ковадло на бочці.
	var n := Node3D.new()
	n.position = SHOP_POS
	n.rotation.y = PI / 2.0          # відкритий бік дивиться на подвір'я (+x)
	yard_root.add_child(n)
	var W := 4.6
	var D := 3.4
	var H := 2.6
	var wall := _planks_mat(Color(0.66, 0.5, 0.32), true)
	var post := Util.mat(Color(0.42, 0.3, 0.2), 0.9)
	n.add_child(Util.box(Vector3(W, H + 0.4, 0.12), wall, Vector3(0, (H + 0.4) / 2.0, -D / 2.0)))
	for sx in [-W / 2.0, W / 2.0]:
		n.add_child(Util.box(Vector3(0.12, H + 0.2, D), wall, Vector3(sx, (H + 0.2) / 2.0, 0)))
	for sx in [-W / 2.0, 0.0, W / 2.0]:
		n.add_child(Util.box(Vector3(0.14, H, 0.14), post, Vector3(sx, H / 2.0, D / 2.0)))
	# односхилий дах
	var roof := Util.box(Vector3(W + 0.5, 0.12, D + 0.7), _planks_mat(Color(0.45, 0.32, 0.22), true), Vector3(0, H + 0.25, 0))
	roof.rotation.x = -0.18
	n.add_child(roof)
	# підлога з дощок
	var fl := Util.box(Vector3(W, 0.05, D), _planks_mat(Color(0.6, 0.45, 0.3)), Vector3(0, 0.025, 0))
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(fl)
	# вивіска
	var sign := Label3D.new()
	sign.text = "МАЙСТЕРНЯ"
	sign.font = load("res://assets/fonts/RuslanDisplay-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/RuslanDisplay-Regular.ttf") else null
	sign.font_size = 64
	sign.pixel_size = 0.004
	sign.modulate = Color(0.35, 0.2, 0.1)
	sign.outline_size = 0
	sign.position = Vector3(0, H + 0.0, D / 2.0 + 0.09)
	n.add_child(Util.box(Vector3(2.2, 0.4, 0.05), Util.mat(Color(0.9, 0.82, 0.6), 0.9), Vector3(0, H + 0.0, D / 2.0 + 0.06)))
	n.add_child(sign)
	var wbch := Models.spawn(n, "workbench", 0.95)
	if wbch:
		wbch.position = Vector3(0, 0, -D / 2.0 + 0.55)
	var anv := Models.spawn(n, "anvil", 0.85)
	if anv:
		anv.position = Vector3(1.3, 0, 0.3)
		anv.rotation.y = 0.4
	n.add_child(Util.pick_area("workshop", Vector3(W, H + 0.5, D), Vector3(0, (H + 0.5) / 2.0, 0)))
	spots["workshop"] = SHOP_POS + Vector3(D / 2.0 + 0.6, 0, 0)
	spots["workbench"] = SHOP_POS + Vector3(-D / 2.0 + 1.35, 0, 0)


func _make_kid_home() -> void:
	## Хата Тарасика за дорогою (туди ввечері йдуть Тарасик і Гвинтик).
	var h := Models.spawn(yard_root, "kid_house", 4.6)
	if h:
		h.position = KID_HOME
		h.rotation.y = PI
		make_house_door(h, AABB(Vector3(-4.6, 0.12, 2.8), Vector3(0.95, 2.3, 2.7)), "kid_door")
	spots["kid_home"] = KID_HOME + Vector3(2.5, 0, -3.0)
	spots["outside_gate"] = Vector3(0, 0, 7.0)
	spots["inside_gate"] = Vector3(0, 0, 3.6)


func _make_pad() -> void:
	## Майданчик, де дрон ночує: дерев'яне коло з літерою «Д».
	var n := Node3D.new()
	n.position = PAD_POS
	yard_root.add_child(n)
	n.add_child(Util.cyl(0.6, 0.62, 0.08, _planks_mat(Color(0.6, 0.45, 0.3)), Vector3(0, 0.04, 0)))
	n.add_child(Util.cyl(0.5, 0.5, 0.01, Util.mat(Color(0.95, 0.85, 0.3), 0.7), Vector3(0, 0.085, 0)))
	var l := Label3D.new()
	l.text = "Д"
	l.font_size = 120
	l.pixel_size = 0.004
	l.modulate = Color(0.3, 0.2, 0.1)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(0, 0.095, 0)
	n.add_child(l)
	spots["drone_pad"] = PAD_POS + Vector3(0, 0.12, 0)


func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ba := b - a
	var t := clampf((p - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
	return p.distance_to(a + ba * t)


func _in_house(p: Vector3) -> bool:
	if big_house:
		return abs(p.x - HOUSE_POS.x) < 3.5 and p.z - HOUSE_POS.z > -3.9 and p.z - HOUSE_POS.z < 3.6
	return abs(p.x - HOUSE_POS.x) < 3.4 and abs(p.z - HOUSE_POS.z) < 2.8


func _make_horizon() -> void:
	## Кільце м'яких пагорбів і дерев довкола — ховає край землі й зливається з панорамою.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hill := Util.mat(Color(0.42, 0.56, 0.27), 1.0)
	var hill2 := Util.mat(Color(0.5, 0.62, 0.3), 1.0)
	for i in 46:
		var a := float(i) / 46.0 * TAU + rng.randf() * 0.08
		var r := rng.randf_range(300, 340)
		var p := Vector3(sin(a) * r, -rng.randf_range(6.0, 12.0), cos(a) * r + 20.0)
		var s := Vector3(rng.randf_range(45, 70), rng.randf_range(24.0, 42.0), rng.randf_range(30, 45))
		var hm := Util.sphere(1.0, hill if i % 2 == 0 else hill2, p, s)
		hm.rotation.y = a
		hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		yard_root.add_child(hm)
	# сосни з Meshy за тином (одна модель, кілька копій різного розміру)
	if Models.exists("pine"):
		var pines := [Vector3(-13, 0, -19.5), Vector3(-25, 0, -9), Vector3(12, 0, -17), Vector3(-28, 0, -16),
			Vector3(-25.5, 0, 3), Vector3(-27, 0, 12), Vector3(-17.5, 0, -21), Vector3(17, 0, -23)]
		for pp in pines:
			var pn := Models.spawn(yard_root, "pine", rng.randf_range(6.5, 9.5))
			pn.position = pp
			pn.rotation.y = rng.randf() * TAU
	# дерева за тином: берези, старі дерева й сосни з Meshy, між ними — тополі й круглі крони різних відтінків
	var kinds := ["birch_a", "birch_b", "old_tree", "pine", "birch_b", "old_tree"]
	for i in 90:
		var a := rng.randf() * TAU
		var r := rng.randf_range(17, 38)
		var p := Vector3(sin(a) * r, 0, cos(a) * r - 3.0)
		if p.z > 14.0 and abs(p.x) < 6.0:
			continue     # не заступати вид з боку воріт
		if p.x > 9.5 and p.x < 23.0 and p.z > -13.0 and p.z < 4.0:
			continue     # тут город із соняшниками
		if p.x > -23.0 and p.x < 11.0 and p.z > -17.0 and p.z < 7.0:
			continue     # тут подвір'я
		if p.x > -21.0 and p.x < -7.0 and p.z > 9.0 and p.z < 21.0:
			continue     # тут хата Тарасика
		if p.x < -26.0 and absf(p.z + 2.0) < 11.0:
			continue     # аеродром
		if p.x > 1.5 and p.x < 45.0 and p.z > -21.0 and p.z < 23.0:
			continue     # садок, поле й навіс трактора
		if p.x > -22.0 and p.x < 26.0 and p.z > -47.0 and p.z < -15.0:
			continue     # стайня, корівник і пасовисько
		if Vector2(p.x + 9.0, p.z - 33.0).length() < 10.0:
			continue     # садиба хати старого села
		var k: String = kinds[i % kinds.size()]
		if Models.exists(k):
			var hgt := rng.randf_range(6.0, 10.0)
			if k == "old_tree":
				hgt = rng.randf_range(4.5, 7.0)
			elif k == "pine":
				hgt = rng.randf_range(7.0, 11.0)
			var tm := Models.spawn(yard_root, k, hgt)
			tm.position = p
			tm.rotation.y = rng.randf() * TAU


func _poplar(p: Vector3, rng: RandomNumberGenerator) -> Node3D:
	## Струнка тополя — висока вузька крона.
	var t := Node3D.new()
	t.position = p
	var h := rng.randf_range(8.0, 12.0)
	t.add_child(Util.cyl(0.12, 0.22, h * 0.35, Util.mat(Color(0.5, 0.45, 0.38), 0.9), Vector3(0, h * 0.17, 0)))
	var c := Color(0.3, 0.5, 0.2).lerp(Color(0.55, 0.68, 0.3), rng.randf())
	for k in 3:
		var y := h * (0.45 + k * 0.17)
		t.add_child(Util.sphere(1.0, Util.mat(c.lerp(Color(0.62, 0.74, 0.34), k * 0.2), 0.95), Vector3(rng.randf_range(-0.1, 0.1), y, 0), Vector3(1.0, h * 0.16, 1.0) * (1.0 - k * 0.12)))
	return t


func _crown(t: Node3D, base: Vector3, s: float, rng: RandomNumberGenerator, dark: Color, light: Color, n: int) -> void:
	## Пишна крона: великі темні кулі всередині, менші світлі — зверху й з боків.
	for i in n:
		var k := float(i) / n
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.2, 0.95) * s
		var o := base + Vector3(cos(a) * r, rng.randf_range(-0.35, 0.65) * s + k * 0.5 * s, sin(a) * r)
		var c := dark.lerp(light, clampf(k * 0.8 + rng.randf() * 0.35, 0.0, 1.0))
		var sz := rng.randf_range(0.45, 0.8) * s * (1.25 - k * 0.5)
		var sp := Util.sphere(sz, Util.mat(c, 0.95), o, Vector3(1, rng.randf_range(0.75, 0.95), 1))
		t.add_child(sp)


func _tree(p: Vector3, s: float, birch: bool, rng: RandomNumberGenerator) -> Node3D:
	var t := Node3D.new()
	t.position = p
	t.rotation.y = rng.randf() * TAU
	var bark := Util.mat(Color(0.9, 0.89, 0.85) if birch else Color(0.38, 0.27, 0.17), 0.9)
	var hgt := (3.4 if birch else 2.4) * s
	t.add_child(Util.cyl(0.08 * s, 0.17 * s, hgt, bark, Vector3(0, hgt / 2.0, 0), Vector3(0, 0, rng.randf_range(-4, 4))))
	if birch:
		for i in 5:
			t.add_child(Util.box(Vector3(0.13, 0.03, 0.13) * s, Util.mat(Color(0.15, 0.15, 0.15)), Vector3(0, rng.randf_range(0.4, hgt * 0.8), 0)))
		_crown(t, Vector3(0, hgt * 0.95, 0), 1.0 * s, rng, Color(0.36, 0.52, 0.2), Color(0.66, 0.78, 0.36), 9)
	else:
		for i in 2:
			var br := Util.cyl(0.04 * s, 0.07 * s, 1.1 * s, bark, Vector3(0, hgt * 0.75, 0), Vector3(0, i * 120.0, 45.0 if i == 0 else -40.0))
			t.add_child(br)
		var dk: Color = [Color(0.2, 0.38, 0.14), Color(0.28, 0.42, 0.12), Color(0.18, 0.34, 0.2), Color(0.35, 0.45, 0.15)][rng.randi() % 4]
		_crown(t, Vector3(0, hgt + 0.5 * s, 0), 1.35 * s, rng, dk, dk.lerp(Color(0.7, 0.8, 0.35), 0.6), 11)
	return t


# ------------------------------------------------------------------ подвір'я
func _make_yard() -> void:
	# хата
	big_house = Models.exists("grandpa_house")
	house = Models.spawn(yard_root, "grandpa_house", 6.5) if big_house else Models.spawn(yard_root, "hata", 4.4)
	if house == null:
		house = Node3D.new()
		yard_root.add_child(house)
		house.add_child(Util.box(Vector3(6, 2.6, 4.2), Util.mat(Color(0.97, 0.96, 0.92)), Vector3(0, 1.3, 0)))
		house.add_child(Util.mesh(PrismMesh.new(), Util.mat(Color(0.8, 0.62, 0.3)), Vector3(0, 3.4, 0), Vector3.ZERO, Vector3(6.6, 1.8, 4.8)))
	house.position = HOUSE_POS
	if big_house:
		house.add_child(Util.pick_area("house", Vector3(6.2, 6.0, 6.6), Vector3(0, 3.0, -0.2)))
		spots["door"] = HOUSE_POS + Vector3(-0.7, 0, 3.75)
	else:
		house.add_child(Util.pick_area("house", Vector3(5.6, 4.0, 4.6), Vector3(0, 2.0, 0)))
		spots["door"] = HOUSE_POS + Vector3(-0.1, 0, 2.6)
	# вікна: теплі вогники вночі
	for wx in ([0.9, -2.0] if big_house else [-1.22, 1.3]):
		var wm := StandardMaterial3D.new()
		wm.emission_enabled = true
		wm.emission = Color(1.0, 0.75, 0.4)
		wm.albedo_color = Color(0.35, 0.3, 0.25)
		window_mats.append(wm)
		pass
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.omni_range = 4.0
		l.position = HOUSE_POS + Vector3(wx, 1.5, 3.6 if big_house else 2.6)
		yard_root.add_child(l)
		window_lights.append(l)
	_make_fence()
	# будка Біма, миска, криниця, лавка, яблуні, соняшники
	spots["doghouse"] = Vector3(-5.2, 0, -5.6)
	_doghouse(spots["doghouse"])
	spots["bowl"] = Vector3(-3.6, 0, -4.2)
	spots["well"] = Vector3(6.2, 0, -4.6)
	_well(spots["well"])
	spots["bench"] = Vector3(3.6, 0, -6.6)
	if not Models.exists("bench"):
		yard_root.add_child(_bench(spots["bench"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if not Models.exists("old_tree"):
		for tp in [Vector3(-7.4, 0, -9.8), Vector3(7.6, 0, -10.4), Vector3(-7.8, 0, 2.6), Vector3(7.8, 0, 1.8)]:
			yard_root.add_child(_apple_tree(tp, rng.randf_range(0.9, 1.15), rng))
	for i in 9:
		var sp := Vector3(-8.4 + (i % 2) * 0.5, 0, -6.6 + i * 0.85)
		var sh := rng.randf_range(1.6, 2.1)
		yard_flower_heads.append(sp + Vector3(0.12, sh * 0.9, 0))
		if Models.exists("sunflower"):
			var sf := Models.spawn(yard_root, "sunflower", sh)
			sf.position = sp
			sf.rotation.y = rng.randf_range(-0.6, 0.6) + PI * 0.5
		else:
			yard_root.add_child(_sunflower(sp, rng))
	_props_yard(rng)
	# точки, куди можуть ходити персонажі
	spots["porch"] = HOUSE_POS + (Vector3(-0.7, 0, 4.5) if big_house else Vector3(-0.1, 0, 3.4))
	spots["garden"] = Vector3(-6.8, 0, -2.0)
	spots["gate"] = Vector3(0, 0, 4.2)


func _make_fence() -> void:
	## Плетений тин довкола двору з воротами спереду.
	var post := Util.mat(Color(0.42, 0.3, 0.2), 0.9)
	var weave := Util.mat(Color(0.6, 0.45, 0.28), 0.95)
	var x0 := YARD.position.x - 0.5
	var x1 := YARD.end.x + 0.5
	var z0 := YARD.position.y - 0.5
	var z1 := YARD.end.y + 0.5
	var gap := 2.05 if Models.exists("gate") else 1.4
	var sides := [[Vector2(x0, z1), Vector2(-gap, z1)], [Vector2(gap, z1), Vector2(x1, z1)],
		[Vector2(x1, z1), Vector2(x1, z0)], [Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x0, z0), Vector2(x0, z1)]]
	for s in sides:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var n := int(ceil(a.distance_to(b) / 1.2))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			var pm := Util.cyl(0.04, 0.05, 1.25, post, Vector3(p.x, 0.62, p.y))
			yard_root.add_child(pm)
			if i % 3 == 1:
				# глечик на кілку
				yard_root.add_child(Util.sphere(0.12, Util.mat(Color(0.7, 0.38, 0.22), 0.6), Vector3(p.x, 1.32, p.y), Vector3(1, 1.1, 1)))
		var mid := (a + b) / 2.0
		var ln := a.distance_to(b)
		var ang := atan2(b.x - a.x, b.y - a.y)
		for k in 6:
			var bar := Util.box(Vector3(0.07, 0.11, ln), weave, Vector3(mid.x, 0.22 + k * 0.17, mid.y))
			bar.rotation.y = ang
			yard_root.add_child(bar)
	# ворота
	var gm := Models.spawn(yard_root, "gate", 1.85)
	if gm:
		gm.position = Vector3(0, 0, z1)
		gm.rotation.y = PI       # лицем до двору
		return
	for gx in [-1.4, 1.4]:
		yard_root.add_child(Util.cyl(0.08, 0.09, 1.7, post, Vector3(gx, 0.85, z1)))
	var gate := Util.box(Vector3(2.6, 0.1, 0.06), weave, Vector3(0, 1.62, z1))
	yard_root.add_child(gate)


func _doghouse(p: Vector3) -> Node3D:
	var n := Models.spawn(yard_root, "doghouse", 1.55)
	if n:
		n.position = p
		n.rotation.y = deg_to_rad(35)
		return n
	n = Node3D.new()
	yard_root.add_child(n)
	n.position = p
	n.rotation.y = deg_to_rad(35)
	var wood := Util.mat(Color(0.72, 0.52, 0.32), 0.85)
	var roof := Util.mat(Color(0.78, 0.25, 0.2), 0.6)
	n.add_child(Util.box(Vector3(0.95, 0.7, 1.1), wood, Vector3(0, 0.35, 0)))
	var r := Util.mesh(PrismMesh.new(), roof, Vector3(0, 0.95, 0), Vector3.ZERO, Vector3(1.15, 0.5, 1.25))
	n.add_child(r)
	n.add_child(Util.cyl(0.22, 0.22, 0.02, Util.mat(Color(0.12, 0.08, 0.06)), Vector3(0, 0.32, 0.56), Vector3(90, 0, 0)))
	return n


func _well(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	yard_root.add_child(n)
	var wm := Models.spawn(n, "well", 2.5)
	if wm:
		wm.rotation.y = deg_to_rad(-35)
		n.add_child(Util.pick_area("well", Vector3(1.4, 2.4, 1.4), Vector3(0, 1.2, 0)))
		return n
	var stone := Util.mat(Color(0.72, 0.7, 0.66), 0.9)
	var wood := Util.mat(Color(0.5, 0.36, 0.22), 0.9)
	n.add_child(Util.cyl(0.62, 0.66, 0.8, stone, Vector3(0, 0.4, 0)))
	n.add_child(Util.cyl(0.48, 0.48, 0.02, Util.mat(Color(0.12, 0.2, 0.3), 0.1), Vector3(0, 0.79, 0)))
	for sx in [-0.6, 0.6]:
		n.add_child(Util.box(Vector3(0.08, 1.6, 0.08), wood, Vector3(sx, 1.3, 0)))
	n.add_child(Util.cyl(0.08, 0.08, 1.3, wood, Vector3(0, 1.75, 0), Vector3(0, 0, 90)))
	var rf := Util.mesh(PrismMesh.new(), Util.mat(Color(0.55, 0.38, 0.24), 0.8), Vector3(0, 2.3, 0), Vector3.ZERO, Vector3(1.6, 0.6, 1.1))
	n.add_child(rf)
	n.add_child(Util.cyl(0.13, 0.11, 0.2, wood, Vector3(0.25, 1.15, 0)))
	n.add_child(Util.pick_area("well", Vector3(1.4, 2.4, 1.4), Vector3(0, 1.2, 0)))
	return n


func _bench(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	n.rotation.y = deg_to_rad(-20)
	var wood := Util.mat(Color(0.6, 0.42, 0.26), 0.85)
	n.add_child(Util.box(Vector3(1.6, 0.08, 0.42), wood, Vector3(0, 0.45, 0)))
	n.add_child(Util.box(Vector3(1.6, 0.36, 0.06), wood, Vector3(0, 0.72, -0.2)))
	for sx in [-0.7, 0.7]:
		n.add_child(Util.box(Vector3(0.08, 0.45, 0.36), wood, Vector3(sx, 0.22, 0)))
	return n


func _apple_tree(p: Vector3, s: float, rng: RandomNumberGenerator) -> Node3D:
	var t := Node3D.new()
	t.position = p
	t.rotation.y = rng.randf() * TAU
	var bark := Util.mat(Color(0.4, 0.29, 0.2), 0.9)
	t.add_child(Util.cyl(0.12 * s, 0.22 * s, 1.7 * s, bark, Vector3(0, 0.85 * s, 0), Vector3(0, 0, 5)))
	for i in 3:
		t.add_child(Util.cyl(0.05 * s, 0.09 * s, 1.0 * s, bark, Vector3(0, 1.75 * s, 0), Vector3(0, i * 120.0, 38.0)))
	_crown(t, Vector3(0, 2.5 * s, 0), 1.25 * s, rng, Color(0.22, 0.42, 0.15), Color(0.48, 0.66, 0.27), 13)
	var apple := Util.mat(Color(0.82, 0.16, 0.13), 0.4)
	for i in 14:
		var a := rng.randf() * TAU
		var o := Vector3(cos(a) * 1.15, rng.randf_range(1.9, 3.0), sin(a) * 1.15) * s
		t.add_child(Util.sphere(0.08 * s, apple, o))
	return t


func _sunflower(p: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	n.position = p
	var hgt := rng.randf_range(1.5, 2.0)
	var green := Util.mat(Color(0.35, 0.55, 0.2), 0.9)
	n.add_child(Util.cyl(0.025, 0.035, hgt, green, Vector3(0, hgt / 2.0, 0)))
	for k in 2:
		n.add_child(Util.sphere(0.16, green, Vector3(0.12 * (1 - 2 * k), hgt * (0.45 + 0.2 * k), 0), Vector3(1.2, 0.2, 0.7)))
	var head := Node3D.new()
	head.position = Vector3(0, hgt, 0.04)
	head.rotation_degrees = Vector3(-60, rng.randf_range(-30, 30), 0)
	n.add_child(head)
	head.add_child(Util.cyl(0.24, 0.24, 0.04, Util.mat(Color(1.0, 0.78, 0.12), 0.7), Vector3.ZERO, Vector3(90, 0, 0)))
	head.add_child(Util.cyl(0.13, 0.13, 0.06, Util.mat(Color(0.32, 0.2, 0.1), 0.9), Vector3(0, 0, 0.01), Vector3(90, 0, 0)))
	return n


# «товщина» речей на землі для обходу: [радіус, висота]
const PROP_R := {
	"rocking_chair": [0.42, 1.1], "clay_pots": [0.32, 0.55], "pot_lid": [0.25, 0.45], "vase": [0.22, 0.5],
	"logs": [0.55, 0.75], "barrel": [0.42, 0.95], "barrels_crates": [0.9, 1.3], "crate": [0.38, 0.6],
	"haystack": [1.25, 1.8], "cart": [1.0, 1.15], "coop": [0.8, 1.7], "old_tree": [0.75, 5.0],
	"birch_b": [0.35, 7.0], "scarecrow": [0.3, 1.9], "pumpkins": [0.35, 0.45], "beehive": [0.4, 0.9],
	"skep": [0.35, 0.7], "old_cart": [1.2, 1.3], "barrel_tap": [0.55, 0.95],
}


func _register_obstacles() -> void:
	## Перешкоди для обходу: хата, криниця, будка, стіл, дерева, паркани, піч…
	Obstacles.clear()
	for pr in YARD_PROPS:
		if PROP_R.has(pr[0]):
			var p: Vector3 = pr[2]
			Obstacles.add(p.x, p.z, PROP_R[pr[0]][0], PROP_R[pr[0]][1])
	# хата (три кола вздовж стіни), криниця, будка, дровітня, лавка, стіл і стільці, корито
	if big_house:
		for x in [-2.0, 0.0, 2.0]:
			for z in [-2.3, 0.0, 2.1]:
				Obstacles.add(HOUSE_POS.x + x, HOUSE_POS.z + z, 1.55, 5.0)
	else:
		for x in [-1.2, 0.3, 1.6]:
			Obstacles.add(x, -9.9, 1.8, 3.0)
	Obstacles.add(6.0, -4.8, 1.0, 2.5)
	Obstacles.add(-5.2, -5.6, 0.62, 1.3)
	Obstacles.add_line(Vector2(-4.0, -9.4), Vector2(-4.0, -11.4), 0.5, 1.4)
	Obstacles.add_line(Vector2(4.3, -6.35), Vector2(4.9, -6.35), 0.33, 0.9)
	Obstacles.add_line(Vector2(4.6, 2.5), Vector2(5.4, 2.5), 0.5, 0.8)
	Obstacles.add(5.0, 3.85, 0.28, 0.95)
	Obstacles.add(5.0, 1.15, 0.28, 0.95)
	Obstacles.add_line(Vector2(4.3, -2.5), Vector2(5.1, -2.3), 0.22, 0.2)
	# сарай, майстерня, майданчик дрона
	Obstacles.add_line(Vector2(BARN_POS.x - 2.2, BARN_POS.z), Vector2(BARN_POS.x + 2.2, BARN_POS.z), 2.45, 4.0)
	Obstacles.add_line(Vector2(SHOP_POS.x - 1.2, SHOP_POS.z - 2.3), Vector2(SHOP_POS.x - 1.2, SHOP_POS.z + 2.3), 0.5, 3.0)
	Obstacles.add_line(Vector2(SHOP_POS.x - 1.6, SHOP_POS.z - 2.3), Vector2(SHOP_POS.x + 1.7, SHOP_POS.z - 2.3), 0.2, 3.0)
	Obstacles.add_line(Vector2(SHOP_POS.x - 1.6, SHOP_POS.z + 2.3), Vector2(SHOP_POS.x + 1.7, SHOP_POS.z + 2.3), 0.2, 3.0)
	Obstacles.add_line(Vector2(SHOP_POS.x - 1.15, SHOP_POS.z - 1.0), Vector2(SHOP_POS.x - 1.15, SHOP_POS.z + 1.0), 0.4, 0.95)
	Obstacles.add(SHOP_POS.x + 0.3, SHOP_POS.z - 1.3, 0.4, 0.85)
	Obstacles.add(BARN_POS.x + 3.9, BARN_POS.z + 2.0, 0.55, 0.75)
	# вузькі закутки біля паркану (між берізкою, бочками й парканом) — щоб Бім там не застрягав
	Obstacles.add(8.3, -9.3, 0.6, 0.5)
	Obstacles.add(8.3, -11.9, 0.6, 0.5)
	# кімната
	var R := ROOM
	Obstacles.add_line(Vector2(R.x + 1.2, R.z + 1.95), Vector2(R.x + 2.0, R.z + 1.95), 0.45, 0.95)
	Obstacles.add(R.x - 1.5, R.z + 0.9, 0.5, 1.0)
	Obstacles.add(R.x - 0.8, R.z + 1.5, 0.25, 0.45)
	Obstacles.add(R.x - 0.3, R.z - 2.45, 0.35, 1.6)
	Obstacles.add_line(Vector2(R.x + 3.1, R.z - 0.3), Vector2(R.x + 3.1, R.z + 0.9), 0.45, 2.0)
	Obstacles.add(R.x - 3.0, R.z + 2.0, 0.45, 0.6)
	for sx in [2.2, 3.0]:
		for sz in [-1.6, -2.3]:
			Obstacles.add(R.x + sx, R.z + sz, 0.55, 2.5)
	Obstacles.add_line(Vector2(R.x - 2.4, R.z - 1.75), Vector2(R.x - 1.6, R.z - 1.45), 0.38, 1.2)
	if Models.exists("bed"):
		Obstacles.add_line(Vector2(R.x + BED_POS.x, R.z + BED_POS.z - 0.55), Vector2(R.x + BED_POS.x, R.z + BED_POS.z + 0.55), 0.62, 0.7)
	if outer:
		outer.register_obstacles()
	Obstacles.finish()


const TAKEABLE := ["clay_pots", "pot_lid", "vase", "jug", "axe", "crate", "pumpkins", "stool"]

const YARD_PROPS := [
	# [модель, висота, позиція, поворот у градусах]
	["bench", 0.95, Vector3(4.6, 0, -6.3), -90.0],
	["rocking_chair", 1.1, Vector3(2.3, 0, -6.1), 10.0],
	["clay_pots", 0.55, Vector3(-2.7, 0, -6.4), 0.0],
	["pot_lid", 0.45, Vector3(-3.5, 0, -6.5), 0.0],
	["vase", 0.5, Vector3(1.2, 0, -6.5), 0.0],
	["firewood", 1.4, Vector3(-4.0, 0, -10.2), 90.0],
	["logs", 0.75, Vector3(-4.6, 0, -8.2), 70.0],
	["axe", 0.5, Vector3(-4.3, 0.55, -8.1), 20.0],
	["barrel", 0.95, Vector3(7.3, 0, -5.6), 0.0],
	["barrels_crates", 1.3, Vector3(7.5, 0, -10.6), -20.0],
	["crate", 0.6, Vector3(6.3, 0, -10.9), 15.0],
	["haystack", 1.8, Vector3(-6.6, 0, -10.7), 0.0],
	["coop", 1.7, Vector3(7.6, 0, -1.6), -90.0],
	["table", 0.8, Vector3(5.0, 0, 2.5), 0.0],
	["chair", 0.95, Vector3(5.0, 0, 3.85), 180.0],
	["chair", 0.95, Vector3(5.0, 0, 1.15), 0.0],
	["jug", 0.3, Vector3(5.1, 0.8, 2.45), 0.0],
	["old_tree", 5.2, Vector3(7.7, 0, 3.9), 0.0],
	["old_tree", 4.6, Vector3(-7.8, 0, -8.6), 120.0],
	["birch_b", 7.5, Vector3(8.0, 0, -8.0), 0.0],
	["scarecrow", 1.9, Vector3(-6.0, 0, 2.5), 20.0],
	["pumpkins", 0.45, Vector3(-5.2, 0, 3.2), 0.0],
	["pumpkins", 0.45, Vector3(-7.0, 0, 1.6), 140.0],
	["beehive", 0.9, Vector3(-7.9, 0, 4.2), 90.0],
	["skep", 0.7, Vector3(-8.1, 0, -0.9), 90.0],
	["old_cart", 1.3, Vector3(-10.6, 0, -12.9), -60.0],     # старий віз біля сараю
	["barrel_tap", 0.95, Vector3(-14.0, 0, 1.0), 90.0],     # бочка з краником біля майстерні
]


func _props_yard(rng: RandomNumberGenerator) -> void:
	for pr in YARD_PROPS:
		if not Models.exists(pr[0]):
			continue
		var n := Models.spawn(yard_root, pr[0], pr[1])
		n.position = pr[2]
		n.rotation.y = deg_to_rad(pr[3])
		if pr[0] in TAKEABLE:
			Util.make_takeable(n, "jug" if pr[0] == "jug" else "prop")
		if not props.has(pr[0]):
			props[pr[0]] = []
		props[pr[0]].append(n)
	spots["coop"] = Vector3(6.6, 0, -1.6)
	spots["coop_door"] = Vector3(6.75, 0, -1.6)
	spots["grain"] = Vector3(5.0, 0, -0.6)
	spots["trough"] = Vector3(4.7, 0, -2.4)
	spots["water_bowl"] = Vector3(-3.0, 0, -4.0)
	spots["well_front"] = Vector3(4.95, 0, -3.65)
	spots["table_chair"] = Vector3(5.0, 0, 1.5)
	spots["bench_seat"] = Vector3(4.6, 0, -6.25)
	spots["firewood_front"] = Vector3(-3.35, 0, -8.95)
	spots["room_door"] = ROOM + Vector3(-2.0, 0, 2.0)
	spots["armchair"] = ROOM + Vector3(-1.5, 0, 0.9)
	_make_water_things()
	_make_field()
	_make_bees()
	_make_barn()
	_make_workshop()
	_make_kid_home()
	_make_pad()
	_make_moving_parts()
	outer = preload("res://scripts/world_outer.gd").new()
	yard_root.add_child(outer)
	outer.build(self)


var water_bowl_water: MeshInstance3D
var trough_water: MeshInstance3D
const BOWL_STAND_H := 0.24           # миски Біма стоять на низенькій лавочці — щоб нахилявся до них, як справжній пес


func _bowl_stand() -> void:
	## Низенька дерев'яна лавочка під миски Біма (корм і вода).
	var a: Vector3 = spots["bowl"]
	var b: Vector3 = spots["water_bowl"]
	var c := (a + b) / 2.0
	var n := Node3D.new()
	n.position = c
	n.rotation.y = -atan2(b.z - a.z, b.x - a.x)
	yard_root.add_child(n)
	var len := a.distance_to(b) + 0.5
	var top := _planks_mat(Color(0.6, 0.42, 0.25))
	var leg := Util.mat(Color(0.45, 0.31, 0.19), 0.9)
	n.add_child(Util.box(Vector3(len, 0.05, 0.42), top, Vector3(0, BOWL_STAND_H - 0.025, 0)))
	for sx in [-len / 2.0 + 0.08, len / 2.0 - 0.08]:
		n.add_child(Util.box(Vector3(0.07, BOWL_STAND_H - 0.05, 0.36), leg, Vector3(sx, (BOWL_STAND_H - 0.05) / 2.0, 0)))
var grain: Node3D


func _make_water_things() -> void:
	# мисочка з водою для Біма (поруч із мискою корму)
	var wb := Node3D.new()
	wb.position = spots["water_bowl"] + Vector3(0, BOWL_STAND_H, 0)
	yard_root.add_child(wb)
	_bowl_stand()
	wb.add_child(Util.cyl(0.15, 0.12, 0.09, Util.mat(Color(0.25, 0.45, 0.85), 0.35), Vector3(0, 0.045, 0)))
	water_bowl_water = Util.cyl(0.125, 0.125, 0.01, Util.mat(Color(0.55, 0.8, 1.0), 0.05, 0.0, Color(0.3, 0.6, 0.9), 0.2), Vector3(0, 0.085, 0))
	wb.add_child(water_bowl_water)
	# дерев'яне корито для курей
	var tr := Node3D.new()
	tr.position = spots["trough"]
	tr.rotation.y = deg_to_rad(15)
	yard_root.add_child(tr)
	var wood := Util.mat(Color(0.5, 0.34, 0.2), 0.9)
	tr.add_child(Util.box(Vector3(1.0, 0.06, 0.32), wood, Vector3(0, 0.03, 0)))
	for z in [-0.15, 0.15]:
		tr.add_child(Util.box(Vector3(1.0, 0.18, 0.04), wood, Vector3(0, 0.12, z)))
	for x in [-0.5, 0.5]:
		tr.add_child(Util.box(Vector3(0.04, 0.18, 0.32), wood, Vector3(x, 0.12, 0)))
	trough_water = Util.box(Vector3(0.94, 0.01, 0.26), Util.mat(Color(0.55, 0.8, 1.0), 0.05, 0.0, Color(0.3, 0.6, 0.9), 0.2), Vector3(0, 0.17, 0))
	tr.add_child(trough_water)
	# зерно для курей (з'являється, коли дрон годує)
	grain = Node3D.new()
	grain.position = spots["grain"]
	yard_root.add_child(grain)
	var gm := Util.mat(Color(0.95, 0.8, 0.3), 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 60:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.9
		var g := Util.sphere(0.018, gm, Vector3(cos(a) * r, 0.012, sin(a) * r), Vector3(1, 0.6, 1))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grain.add_child(g)
	grain.visible = false


var _field_mm: Array = []          # [MultiMesh, локальна трансформація частини]
var _field_base: Array = []        # [позиція, поворот] кожного соняшника
var _field_t := 0.0


func _make_field() -> void:
	## Город за тином праворуч: грядки й соняшники, які ростуть, коли їх поливають.
	## Соняшники зібрані в MultiMesh — 54 рослини малюються за 4 виклики (легко для телефона).
	var x0 := 11.5
	var z0 := -9.5
	var soil := Util.mat(Color(0.4, 0.29, 0.19), 1.0)
	var soil2 := Util.mat(Color(0.34, 0.24, 0.15), 1.0)
	for r in 6:
		var row := Util.box(Vector3(0.75, 0.12, 10.0), soil if r % 2 == 0 else soil2, Vector3(x0 + r * 1.2, 0.03, z0 + 5.0))
		row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		yard_root.add_child(row)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for r in 6:
		for k in 9:
			var p := Vector3(x0 + r * 1.2 + rng.randf_range(-0.12, 0.12), 0.08, z0 + 0.6 + k * 1.1 + rng.randf_range(-0.15, 0.15))
			_field_base.append([p, rng.randf_range(-0.5, 0.5), rng.randf_range(0.9, 1.15)])
	var stem := CylinderMesh.new()
	stem.top_radius = 0.025
	stem.bottom_radius = 0.035
	stem.height = 1.7
	stem.radial_segments = 6
	stem.rings = 1
	var leaf := SphereMesh.new()
	leaf.radius = 0.17
	leaf.height = 0.34
	leaf.radial_segments = 8
	leaf.rings = 4
	var petals := CylinderMesh.new()
	petals.top_radius = 0.25
	petals.bottom_radius = 0.25
	petals.height = 0.04
	petals.radial_segments = 14
	petals.rings = 1
	var seeds := CylinderMesh.new()
	seeds.top_radius = 0.13
	seeds.bottom_radius = 0.13
	seeds.height = 0.06
	seeds.radial_segments = 10
	seeds.rings = 1
	var green := Util.mat(Color(0.35, 0.55, 0.2), 0.9)
	var head_t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-60), 0, 0)), Vector3(0, 1.7, 0.04))
	var parts := [
		[stem, green, Transform3D(Basis(), Vector3(0, 0.85, 0))],
		[leaf, green, Transform3D(Basis().scaled(Vector3(1.2, 0.2, 0.7)), Vector3(0.13, 0.8, 0))],
		[petals, Util.mat(Color(1.0, 0.78, 0.12), 0.7), head_t * Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3.ZERO)],
		[seeds, Util.mat(Color(0.32, 0.2, 0.1), 0.9), head_t * Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(0, 0, 0.012))],
	]
	for pt in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pt[0]
		mm.instance_count = _field_base.size()
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = pt[1]
		yard_root.add_child(mi)
		_field_mm.append([mm, pt[2]])
	# ще одне листя з другого боку (той самий меш, інша частина)
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = leaf
	mm2.instance_count = _field_base.size()
	var mi2 := MultiMeshInstance3D.new()
	mi2.multimesh = mm2
	mi2.material_override = green
	yard_root.add_child(mi2)
	_field_mm.append([mm2, Transform3D(Basis().scaled(Vector3(1.2, 0.2, 0.7)), Vector3(-0.13, 1.1, 0))])
	_update_field(0.0)
	# парканчик довкола городу (з того ж плетеного тину, якщо є модель)
	if Models.exists("garden_fence"):
		for k in 5:
			var f := Models.spawn(yard_root, "garden_fence", 0.85)
			f.position = Vector3(x0 + 0.8 + k * 1.3, 0, z0 + 10.6)
	spots["field_center"] = Vector3(x0 + 3.0, 0, z0 + 5.0)
	spots["field"] = Rect2(x0 - 0.4, z0, 6.8, 10.0)


func _make_moving_parts() -> void:
	## Вирізаємо з моделей рухомі частини: двері хати, хвіртку воріт, коловорот і відро криниці.
	# двері хати
	var dm: MeshInstance3D = null
	if big_house:
		var mis := house.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			make_house_door(house, AABB(Vector3(-0.3, -0.765, 0.70), Vector3(0.275, 0.44, 0.1)), "house", 1.7, mis[0])
	else:
		dm = Models.cut(house, AABB(Vector3(-0.33, 0.22, -8.7), Vector3(0.93, 1.66, 1.4)))
	if dm:
		var bb := Models.global_aabb(dm)
		var dark := Util.box(Vector3(bb.size.x, bb.size.y, 0.04), Util.mat(Color(0.08, 0.06, 0.05), 1.0),
			Vector3(bb.get_center().x, bb.get_center().y, bb.position.z - 0.05))
		yard_root.add_child(dark)
		var h := Models.hinge(dm, Vector3(bb.position.x, 0, bb.get_center().z))
		doors["house"] = [h, h.rotation.y, 1.0]
		add_auto_door("house", ["house"], Vector3(bb.get_center().x, 0, bb.get_center().z + 0.6), 1.7)
	# ворота (хвіртка між стовпами)
	var gate_holder: Node3D = null
	for c in yard_root.get_children():
		if c.name == "gate":
			gate_holder = c
	if gate_holder:
		var z1: float = gate_holder.position.z
		var gp := Models.cut(gate_holder, AABB(Vector3(-0.74, 0.03, z1 - 0.4), Vector3(1.48, 1.8, 0.8)))
		if gp:
			var gb := Models.global_aabb(gp)
			var gh := Models.hinge(gp, Vector3(gb.position.x, 0, gb.get_center().z))
			doors["gate"] = [gh, gh.rotation.y, 1.0]
			add_auto_door("gate", ["gate"], Vector3(gb.get_center().x, 0, gb.get_center().z), 2.4)
	# криниця: коловорот із мотузкою й ручкою, відро
	var wn: Node3D = null
	for c in yard_root.get_children():
		if c.get_child_count() > 0 and c.get_child(0).name == "well":
			wn = c
	if wn:
		var wm: Node3D = wn.get_child(0)
		var drum := Models.cut(wm, AABB(Vector3(-0.79, 1.2, -0.3), Vector3(1.12, 0.46, 0.65)), 100.0, wm)
		var crank := Models.cut(wm, AABB(Vector3(0.52, 1.15, -0.35), Vector3(0.65, 0.5, 0.8)), 100.0, wm)
		var axis := wm.global_transform * Vector3(0, 1.47, 0.0)
		if drum:
			well_crank = Node3D.new()
			wn.add_child(well_crank)
			well_crank.global_transform = Transform3D(wm.global_basis.orthonormalized(), axis)
			drum.reparent(well_crank, true)
			if crank:
				crank.reparent(well_crank, true)
		var bk := Models.cut(wm, AABB(Vector3(-0.48, 0.86, -0.32), Vector3(0.52, 0.38, 0.64)), 100.0, wm)
		if bk:
			well_bucket = Node3D.new()
			wm.add_child(well_bucket)
			bk.reparent(well_bucket, true)
			well_rope = Util.cyl(0.012, 0.012, 1.0, Util.mat(Color(0.75, 0.62, 0.4), 0.9))
			wm.add_child(well_rope)
			well_rope.visible = false


var _door_tw := {}
var _door_open_t := {}               # скільки часу двері вже відчинені (самі зачиняються)
var auto_doors := {}
var big_house := false              # нова велика хата діда (модель grandpa_house)                 # група → {names, pos, r, open, idle}: двері, що відчиняються, коли хтось поруч


func add_auto_door(group: String, names: Array, pos: Vector3, r: float) -> void:
	auto_doors[group] = {"names": names, "pos": pos, "r": r, "open": false, "idle": 0.0}


func door_watch(movers: Array, dt: float) -> void:
	## Кликати кілька разів на секунду: хтось підійшов — двері відчиняються, відійшли всі — зачиняються.
	for g in auto_doors:
		var d: Dictionary = auto_doors[g]
		var p: Vector3 = d["pos"]
		var r: float = d["r"]
		var near := false
		for m in movers:
			var q: Vector3 = m
			if absf(q.x - p.x) < r and absf(q.z - p.z) < r and Vector2(q.x - p.x, q.z - p.z).length() < r:
				near = true
				break
		if near:
			d["idle"] = 0.0
			if not d["open"]:
				d["open"] = true
				for n in d["names"]:
					set_door(n, true, 0.6)
			else:
				for n in d["names"]:
					_door_open_t[n] = 0.0
		elif d["open"]:
			d["idle"] = float(d["idle"]) + dt
			if float(d["idle"]) > 1.5:
				d["open"] = false
				for n in d["names"]:
					if n != "gate" or _gate_users <= 0:
						set_door(n, false, 0.7)


func set_door(name: String, open: bool, secs := 0.5) -> void:
	if not doors.has(name):
		return
	var d: Array = doors[name]
	var h: Node3D = d[0]
	var to: float = float(d[1]) + (deg_to_rad(100.0) * float(d[2]) if open else 0.0)
	if _door_tw.has(name) and is_instance_valid(_door_tw[name]):
		(_door_tw[name] as Tween).kill()          # попередній рух дверей — більше не діє
	var tw := create_tween()
	tw.tween_property(h, "rotation:y", to, secs).set_trans(Tween.TRANS_SINE)
	_door_tw[name] = tw
	if open:
		_door_open_t[name] = 0.0
	else:
		_door_open_t.erase(name)
	var au = get_node_or_null("/root/Main/Audio")
	if au and (name != "room") == (Game.state["location"] == "yard"):
		au.play_at("door_open" if open else "door_close", h, -8.0)


var _gate_users := 0


func pass_gate(who: Walker, going_out: bool) -> void:
	## Відчинити ворота, пройти крізь них і зачинити (якщо ніхто більше не йде).
	_gate_users += 1
	if _gate_users == 1:
		set_door("gate", true, 0.7)
	await get_tree().create_timer(0.7).timeout
	who.bounds = Rect2(-20.5, -14.5, 29.0, 33.0)
	var to: Vector3 = spots["outside_gate"] if going_out else spots["inside_gate"]
	await who.go(to + Vector3(randf_range(-0.2, 0.2), 0, 0), false, false)
	_gate_users -= 1
	await get_tree().create_timer(0.8).timeout
	if _gate_users <= 0:
		_gate_users = 0
		set_door("gate", false, 0.7)


func well_draw() -> void:
	## Опустити відро в криницю й підняти з водою (коловорот крутиться). await well_draw()
	if well_crank == null or well_bucket == null:
		await get_tree().create_timer(2.5).timeout
		return
	while _well_busy:
		await get_tree().process_frame
	_well_busy = true
	well_rope.visible = true
	var au = get_node_or_null("/root/Main/Audio")
	var depth := 1.25
	for phase in 2:          # 0 — опускаємо, 1 — піднімаємо
		var t := 0.0
		var dur := 1.8 if phase == 0 else 2.6
		while t < dur:
			var dt := get_process_delta_time()
			t += dt
			var u := clampf(t / dur, 0.0, 1.0)
			var y := -depth * (u if phase == 0 else 1.0 - u)
			well_bucket.position.y = y
			well_crank.rotate_object_local(Vector3.RIGHT, dt * (5.0 if phase == 0 else -3.6))
			# мотузка від коловорота до дужки відра
			var top := 1.36
			var bot := 1.18 + y
			well_rope.position = Vector3(-0.22, (top + bot) / 2.0, 0.0)
			well_rope.scale = Vector3(1, maxf(0.01, top - bot), 1)
			await get_tree().process_frame
		if phase == 0 and au and Game.state["location"] == "yard":
			au.play_at("pop", well_bucket, -6.0, 0.6)
			await get_tree().create_timer(0.4).timeout
	well_bucket.position.y = 0.0
	well_rope.visible = false
	_well_busy = false


func _make_bees() -> void:
	var bees := preload("res://scripts/bees.gd").new()
	yard_root.add_child(bees)
	# льотки: великий вулик у кутку та солом'яний вулик-бджолярка біля соняшників
	bees.setup([Vector3(-7.55, 0.28, 4.2), Vector3(-7.8, 0.15, -0.9)], bee_flowers)


func bee_flowers() -> Array:
	## Голівки соняшників: на подвір'ї та на городі (на городі — коли вже підросли).
	var out: Array = yard_flower_heads.duplicate()
	var gr: float = float(Game.state["field"]["growth"])
	if gr > 0.5:
		var s := 0.35 + 0.65 * gr
		for k in range(0, _field_base.size(), 3):
			var b: Array = _field_base[k]
			out.append((b[0] as Vector3) + Vector3(0, 1.7 * s * float(b[2]) + 0.05, 0.03))
	return out


func _update_field(t: float) -> void:
	var gr: float = float(Game.state["field"]["growth"])
	var dry: float = clampf(1.0 - float(Game.state["field"]["water"]) / 25.0, 0.0, 1.0)
	var s := 0.35 + 0.65 * gr
	for i in _field_base.size():
		var b: Array = _field_base[i]
		var sway := sin(t * 0.9 + float(i) * 0.37) * 0.035
		var droop := dry * 0.25     # сухі соняшники трохи похилені
		var basis := Basis.from_euler(Vector3(droop, b[1], sway)).scaled(Vector3.ONE * s * float(b[2]))
		var tr := Transform3D(basis, b[0])
		for m in _field_mm:
			(m[0] as MultiMesh).set_instance_transform(i, tr * (m[1] as Transform3D))


# ------------------------------------------------------------------ кімната
const BED_POS := Vector3(1.1, 0, -1.78)
const BED_YAW := -90.0


func _make_room() -> void:
	var W := 7.0
	var D := 5.5
	var H := 3.0
	var floor_sh := Shader.new()
	floor_sh.code = """
shader_type spatial;
render_mode diffuse_lambert;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float plank = floor(lp.x * 3.2);
	float r = fract(sin(plank * 12.9898) * 43758.5453);
	float edge = smoothstep(0.0, 0.04, fract(lp.x * 3.2)) * smoothstep(1.0, 0.96, fract(lp.x * 3.2));
	vec3 c = mix(vec3(0.55, 0.36, 0.22), vec3(0.68, 0.47, 0.3), r);
	ALBEDO = c * mix(0.7, 1.0, edge);
	ROUGHNESS = 0.7;
}
"""
	var fm := ShaderMaterial.new()
	fm.shader = floor_sh
	room_root.add_child(Util.box(Vector3(W, 0.1, D), fm, Vector3(0, -0.05, 0)))
	var wall := Util.mat(Color(0.86, 0.83, 0.76), 0.95)
	var band := Util.mat(Color(0.22, 0.36, 0.7), 0.8)
	var red := Util.mat(Color(0.78, 0.2, 0.2), 0.8)
	# задня й бічні стіни (передньої немає — «ляльковий будиночок»)
	room_root.add_child(Util.box(Vector3(W, H, 0.12), wall, Vector3(0, H / 2.0, -D / 2.0)))
	room_root.add_child(Util.box(Vector3(0.12, H, D), wall, Vector3(-W / 2.0, H / 2.0, 0)))
	room_root.add_child(Util.box(Vector3(0.12, H, D), wall, Vector3(W / 2.0, H / 2.0, 0)))
	# передня стіна з дверима (двері — ліворуч), тепер кімнату видно по колу
	var door_x := -2.0
	room_root.add_child(Util.box(Vector3(W / 2.0 + door_x - 0.55, H, 0.12), wall, Vector3((-W / 2.0 + door_x - 0.55) / 2.0, H / 2.0, D / 2.0)))
	room_root.add_child(Util.box(Vector3(W / 2.0 - door_x - 0.55, H, 0.12), wall, Vector3((W / 2.0 + door_x + 0.55) / 2.0, H / 2.0, D / 2.0)))
	room_root.add_child(Util.box(Vector3(1.1, H - 2.1, 0.12), wall, Vector3(door_x, 2.1 + (H - 2.1) / 2.0, D / 2.0)))
	var door_mat := Util.mat(Color(0.55, 0.36, 0.2), 0.8)
	# двері на петлі (ліворуч), щоб відчинялися
	var rd := Node3D.new()
	rd.position = Vector3(door_x - 0.5, 0, D / 2.0 - 0.03)
	room_root.add_child(rd)
	rd.add_child(Util.box(Vector3(1.0, 2.05, 0.06), door_mat, Vector3(0.5, 1.03, 0)))
	for k in 4:
		rd.add_child(Util.box(Vector3(0.9, 0.04, 0.02), Util.mat(Color(0.42, 0.27, 0.15), 0.8), Vector3(0.5, 0.3 + k * 0.5, -0.04)))
	rd.add_child(Util.sphere(0.04, Util.mat(Color(0.85, 0.7, 0.3), 0.3, 0.8), Vector3(0.88, 1.0, -0.06)))
	doors["room"] = [rd, 0.0, -1.0]          # відчиняються назовні — не закривають кімнату
	# за дверима — світло подвір'я
	var outside := StandardMaterial3D.new()
	outside.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outside.albedo_color = Color(0.85, 0.92, 0.75)
	room_door_light = Util.box(Vector3(1.1, 2.1, 0.02), outside, Vector3(door_x, 1.05, D / 2.0 + 0.12))
	room_root.add_child(room_door_light)
	# друге вікно — на передній стіні, з видом на подвір'я
	var win2 := StandardMaterial3D.new()
	win2.albedo_texture = load("res://assets/sky/day.jpg")
	win2.uv1_scale = Vector3(0.22, 0.4, 1)
	win2.uv1_offset = Vector3(0.62, 0.3, 0)
	win2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	room_windows.append(win2)
	room_root.add_child(Util.box(Vector3(1.4, 1.0, 0.02), win2, Vector3(1.0, 1.7, D / 2.0 - 0.08)))
	var fr := Util.mat(Color(0.25, 0.42, 0.75), 0.6)
	for fy in [1.17, 2.23]:
		room_root.add_child(Util.box(Vector3(1.55, 0.08, 0.06), fr, Vector3(1.0, fy, D / 2.0 - 0.1)))
	for fx in [0.3, 1.0, 1.7]:
		room_root.add_child(Util.box(Vector3(0.06, 1.1, 0.06), fr, Vector3(fx, 1.7, D / 2.0 - 0.1)))
	# стеля з дерев'яними сволоками
	room_root.add_child(Util.box(Vector3(W, 0.1, D), Util.mat(Color(0.93, 0.91, 0.86), 0.95), Vector3(0, H + 0.05, 0)))
	for bx in [-2.2, 0.0, 2.2]:
		room_root.add_child(Util.box(Vector3(0.22, 0.2, D), Util.mat(Color(0.45, 0.3, 0.18), 0.85), Vector3(bx, H - 0.1, 0)))
	# синьо-червоний розпис-смужка під стелею, як у хаті
	room_root.add_child(Util.box(Vector3(W, 0.08, 0.02), band, Vector3(0, H - 0.35, -D / 2.0 + 0.07)))
	for i in 18:
		room_root.add_child(Util.sphere(0.06, red if i % 2 == 0 else band, Vector3(-W / 2.0 + 0.3 + i * 0.38, H - 0.22, -D / 2.0 + 0.07), Vector3(1, 1, 0.3)))
	# вікно з видом на поля (шматок денної панорами)
	var win := StandardMaterial3D.new()
	win.albedo_texture = load("res://assets/sky/day.jpg")
	win.uv1_scale = Vector3(0.25, 0.45, 1)
	win.uv1_offset = Vector3(0.36, 0.28, 0)
	win.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	room_windows.append(win)
	room_root.add_child(Util.box(Vector3(1.6, 1.1, 0.02), win, Vector3(1.2, 1.7, -D / 2.0 + 0.08)))
	var frame := Util.mat(Color(0.25, 0.42, 0.75), 0.6)
	room_root.add_child(Util.box(Vector3(1.75, 0.08, 0.06), frame, Vector3(1.2, 2.27, -D / 2.0 + 0.1)))
	room_root.add_child(Util.box(Vector3(1.75, 0.08, 0.06), frame, Vector3(1.2, 1.13, -D / 2.0 + 0.1)))
	for fx in [0.4, 1.2, 2.0]:
		room_root.add_child(Util.box(Vector3(0.06, 1.2, 0.06), frame, Vector3(fx, 1.7, -D / 2.0 + 0.1)))
	# килим, піч, лавка-диван, столик
	room_root.add_child(Util.cyl(1.4, 1.4, 0.02, Util.mat(Color(0.78, 0.28, 0.25), 0.95), Vector3(0.6, 0.01, 0.3), Vector3.ZERO))
	room_root.add_child(Util.cyl(1.0, 1.0, 0.025, Util.mat(Color(0.95, 0.85, 0.55), 0.95), Vector3(0.6, 0.012, 0.3)))
	var stove := Util.mat(Color(0.88, 0.85, 0.79), 0.95)
	room_root.add_child(Util.box(Vector3(1.6, 1.6, 1.5), stove, Vector3(W / 2.0 - 0.9, 0.8, -D / 2.0 + 0.85)))
	room_root.add_child(Util.box(Vector3(0.7, 0.9, 0.7), stove, Vector3(W / 2.0 - 0.5, 2.05, -D / 2.0 + 0.5)))
	room_root.add_child(Util.cyl(0.25, 0.25, 0.05, Util.mat(Color(0.15, 0.1, 0.08)), Vector3(W / 2.0 - 0.9, 0.55, -D / 2.0 + 1.61), Vector3(90, 0, 0)))
	for i in 5:
		room_root.add_child(Util.sphere(0.07, band if i % 2 == 0 else red, Vector3(W / 2.0 - 1.5 + i * 0.3, 1.25, -D / 2.0 + 1.61), Vector3(1, 1, 0.3)))
	var room_props := [
		["sofa", 0.95, Vector3(1.6, 0, 1.9), 180.0],
		["armchair", 1.0, Vector3(-1.5, 0, 0.9), 130.0],
		["stool", 0.45, Vector3(-0.8, 0, 1.5), 0.0],
		["jug", 0.3, Vector3(-0.8, 0.41, 1.5), 0.0],
		["shelf", 1.6, Vector3(-0.3, 0, -2.55), 0.0],
		["wardrobe", 2.0, Vector3(3.15, 0, 0.3), -90.0],
		["chest", 0.6, Vector3(-3.0, 0, 2.0), 90.0],
	]
	# ліжко дідуся: узголів'ям до задньої стіни, між полицею й піччю
	if Models.exists("bed"):
		var bd := Models.spawn(room_root, "bed", 1.95, "x")
		bd.position = BED_POS
		bd.rotation.y = deg_to_rad(BED_YAW)
		props["room_bed"] = [bd]
		spots["bed"] = ROOM + BED_POS
	var any := false
	for pr in room_props:
		if Models.exists(pr[0]):
			any = true
			var n := Models.spawn(room_root, pr[0], pr[1])
			n.position = pr[2]
			n.rotation.y = deg_to_rad(pr[3])
			props["room_" + pr[0]] = [n]
			if pr[0] in TAKEABLE:
				Util.make_takeable(n, "jug" if pr[0] == "jug" else "prop")
	# меблі тверді для Ніки (шар стін 1 << 17): не проходить крізь крісло, ліжко, диван, шафу
	var fsb := StaticBody3D.new()
	fsb.collision_layer = 1 << 17
	fsb.collision_mask = 0
	room_root.add_child(fsb)
	for k in ["room_bed", "room_sofa", "room_armchair", "room_shelf", "room_wardrobe", "room_chest"]:
		if not props.has(k):
			continue
		var fn: Node3D = props[k][0]
		var fab := Models.measure(fn)
		if fab.size == Vector3.ZERO:
			continue
		var fh := maxf(fab.size.y, 1.2)
		var fcs := CollisionShape3D.new()
		var fbx := BoxShape3D.new()
		fbx.size = Vector3(fab.size.x * 0.85, fh, fab.size.z * 0.85)
		fcs.shape = fbx
		fcs.transform = fn.transform * Transform3D(Basis(), Vector3(fab.get_center().x, fab.position.y + fh * 0.5, fab.get_center().z))
		fsb.add_child(fcs)
	if not any:
		var sofa := Util.mat(Color(0.86, 0.78, 0.62), 0.9)
		room_root.add_child(Util.box(Vector3(2.0, 0.45, 0.8), sofa, Vector3(1.5, 0.22, 1.7)))
		room_root.add_child(Util.box(Vector3(0.9, 0.06, 0.6), Util.mat(Color(0.55, 0.37, 0.22), 0.7), Vector3(0.6, 0.48, 0.5)))
	room_root.add_child(Util.pick_area("room_exit", Vector3(1.1, 2.1, 0.3), Vector3(-2.0, 1.05, D / 2.0 - 0.15)))
	spots["grandpa_home"] = ROOM + Vector3(0.3, 0, -0.4)
	var lawn := Util.box(Vector3(60, 0.02, 60), Util.mat(Color(0.28, 0.45, 0.17), 1.0), Vector3(0, -0.12, 0))
	room_root.add_child(lawn)
	room_light = OmniLight3D.new()
	room_light.light_color = Color(1.0, 0.86, 0.68)
	room_light.omni_range = 9.0
	room_light.position = Vector3(0.0, 2.6, 0.0)
	var wl := OmniLight3D.new()
	wl.light_color = Color(1.0, 0.95, 0.85)
	wl.omni_range = 5.0
	wl.light_energy = 0.8
	wl.position = Vector3(1.2, 1.8, -D / 2.0 + 0.6)
	room_root.add_child(wl)
	room_light.shadow_enabled = false
	room_root.add_child(room_light)
	spots["terrarium"] = ROOM + Vector3(-2.0, 0, -1.6)
	spots["room_center"] = ROOM + Vector3(0, 0, 0.6)


func _make_fireflies() -> void:
	fireflies = CPUParticles3D.new()
	fireflies.amount = 50
	fireflies.lifetime = 6.0
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(9, 0.8, 8)
	fireflies.position = Vector3(0, 1.0, -3)
	fireflies.direction = Vector3(0, 1, 0)
	fireflies.spread = 180.0
	fireflies.gravity = Vector3.ZERO
	fireflies.initial_velocity_min = 0.05
	fireflies.initial_velocity_max = 0.25
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.9, 0.35)
	m.emission_energy_multiplier = 3.0
	sm.material = m
	fireflies.mesh = sm
	fireflies.emitting = false
	yard_root.add_child(fireflies)


func test_moving() -> void:
	## Для перевірки: відчинити все й набрати води.
	for d in doors:
		set_door(d, true)
	well_draw()


func make_house_door(holder: Node3D, box: AABB, name: String, r := 2.2, ref: Node3D = null, face_x := false, backing := true) -> void:
	## Вирізає двері з моделі будинку (box — у просторі самого holder), ставить їх на петлю
	## й реєструє як «двері, що відчиняються, коли хтось підходить».
	var dm := Models.cut(holder, box, 100.0, ref if ref else holder)
	if dm == null:
		return
	var pa: AABB = dm.get_meta("part_aabb") if dm.has_meta("part_aabb") else dm.get_aabb()
	var T := holder.global_transform.affine_inverse() * dm.global_transform
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in 8:
		var c := T * pa.get_endpoint(i)
		lo = lo.min(c)
		hi = hi.max(c)
	var w := hi.x - lo.x
	var h := hi.y - lo.y
	if face_x:
		# двері дивляться вздовж +X (стайня, корівник): ширина — по z
		if backing:
			var bk := Util.box(Vector3(0.03, h * 0.98, (hi.z - lo.z) * 0.96), Util.mat(Color(0.08, 0.06, 0.05), 1.0),
				Vector3(lo.x - 0.04, (lo.y + hi.y) / 2.0, (lo.z + hi.z) / 2.0))
			holder.add_child(bk)
		var hx := Models.hinge(dm, holder.to_global(Vector3((lo.x + hi.x) / 2.0, 0, lo.z)))
		doors[name] = [hx, hx.rotation.y, 1.0]
		add_auto_door(name, [name], holder.to_global(Vector3(hi.x + 0.8, 0, (lo.z + hi.z) / 2.0)), r)
		return
	var back := Util.box(Vector3(w * 0.96, h * 0.98, 0.03), Util.mat(Color(0.08, 0.06, 0.05), 1.0),
		Vector3((lo.x + hi.x) / 2.0, (lo.y + hi.y) / 2.0, lo.z - 0.04))
	holder.add_child(back)
	var hg := Models.hinge(dm, holder.to_global(Vector3(lo.x, 0, (lo.z + hi.z) / 2.0)))
	doors[name] = [hg, hg.rotation.y, 1.0]
	add_auto_door(name, [name], holder.to_global(Vector3((lo.x + hi.x) / 2.0, 0, hi.z + 0.5)), r)
