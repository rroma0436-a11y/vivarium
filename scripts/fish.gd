extends Node3D
## Риби у ставку й у річці (моделі fish_*.glb з Meshy): плавають зграйками, хвости виляють (шейдер),
## під водою їх видно крізь воду: що глибше — то тьмяніші й зеленкуватіші.
## Малюємо лише ті, що поблизу камери (MultiMesh — одна команда малювання на вид риби).

const KINDS := [
	# id моделі, довжина (м), скільки в зграйці (від, до), сила виляння, швидкість (від, до)
	["fish_orange", 0.42, 5, 7, 1.0, 0.35, 0.8],
	["fish_blue", 0.40, 4, 6, 1.0, 0.35, 0.75],
	["fish_spotted", 0.30, 2, 3, 0.55, 0.2, 0.45],
	["fish_guppy", 0.26, 8, 11, 1.2, 0.45, 1.0],
]
const POND_SCHOOLS := [0, 1, 3, 2, 0, 3, 1, 2]          # вид риби в кожній зграйці ставка
const RIVER_SCHOOL_COUNT := 18
const NEAR := 60.0                                      # далі від камери риб не малюємо
const SIM := 80.0                                       # далі — зграйка «спить» (не рахуємо кожну рибу)
const TOP := -0.35                                      # найвище, куди підпливає риба (вода — на 0.05)
const BOTTOM := -1.05                                   # найглибше (глибше крізь воду вже майже не видно)
const UP_FLOW := Vector3(-1, 0, 0)                      # проти течії річки (RIVER_FLOW тече вздовж +x)

const _SH := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.04, 0.2, 0.26);
uniform vec3 shallow : source_color = vec3(0.3, 0.55, 0.5);
uniform float surface_y = 0.05;
uniform float wag = 1.0;
varying vec3 wp;
void vertex() {
	// модель: голова в +Z (z = 0.5), хвіст у -Z (z = -0.5); INSTANCE_CUSTOM.x — фаза, .y — сила
	float z = VERTEX.z;
	float bend = smoothstep(0.3, -0.5, z);
	float ph = INSTANCE_CUSTOM.x - z * 6.0;
	float a = INSTANCE_CUSTOM.y * wag;
	VERTEX.x += sin(ph) * a * 0.11 * bend * bend + sin(INSTANCE_CUSTOM.x + 1.6) * a * 0.012;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec4 t = texture(tex, UV);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float d = max(surface_y - wp.y, 0.0);
	float path = d / max(V.y, 0.2);
	float absorb = 1.0 - exp(-path * 0.9);
	vec3 c = mix(t.rgb, deep, absorb * 0.6);
	c = mix(c, shallow, 0.1);
	// збоку вода — як дзеркало: риб майже не видно; згори — добре видно
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(V.y, 0.0, 1.0), 5.0);
	ALBEDO = c;
	ALPHA = clamp((1.0 - absorb * 0.75) * (1.0 - fres * 0.9) * 0.95, 0.0, 1.0);
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
}
"""

var outer
var _mm: Array = []            # MultiMesh для кожного виду (або null, якщо моделі нема)
var _schools: Array = []
var _rng := RandomNumberGenerator.new()


func setup(o) -> void:
	outer = o
	_rng.seed = 2611
	var sh := Shader.new()
	sh.code = _SH
	for k in KINDS:
		_mm.append(_make_mm(k[0], sh, k[4]))
	# ставок
	for kind in POND_SCHOOLS:
		_add_school(0, kind, outer.POND.x)
	# річка: зграйки вздовж усієї річки, дві — біля містка
	for i in RIVER_SCHOOL_COUNT:
		var hx := -380.0 + i * 760.0 / (RIVER_SCHOOL_COUNT - 1) + _rng.randf_range(-12.0, 12.0)
		_add_school(1, i % 4, hx)
	_add_school(1, 0, 12.0)
	_add_school(1, 3, -14.0)
	var counts := [0, 0, 0, 0]
	for s in _schools:
		counts[s["kind"]] += s["fish"].size()
	for i in _mm.size():
		if _mm[i]:
			(_mm[i] as MultiMeshInstance3D).multimesh.instance_count = counts[i]
			(_mm[i] as MultiMeshInstance3D).multimesh.visible_instance_count = 0


func _make_mm(id: String, sh: Shader, wag: float) -> MultiMeshInstance3D:
	var path := "res://assets/models/%s.glb" % id
	if not ResourceLoader.exists(path):
		return null
	var sc: Node = load(path).instantiate()
	var mis := sc.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		sc.free()
		return null
	var mesh: Mesh = (mis[0] as MeshInstance3D).mesh
	var tex: Texture2D = null
	var sm := mesh.surface_get_material(0)
	if sm is BaseMaterial3D:
		tex = (sm as BaseMaterial3D).albedo_texture
	sc.free()
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 1                 # після води (вона прозора) — інакше вода «з'їдає» риб
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("wag", wag)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var box := AABB(Vector3(-600, -3, -40), Vector3(1200, 4, 180))      # ставок і вся річка
	mm.custom_aabb = box
	var mmi := MultiMeshInstance3D.new()
	mmi.name = id
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = box
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ------------------------------------------------------------------ де вода
func _depth(body: int, p: Vector3) -> float:
	## Глибина води в точці (м); від'ємна — це вже берег.
	if body == 0:
		var sd: float = outer.pond_sd(p)
		return outer.POND_DEPTH * smoothstep(0.0, 7.0, -sd) if sd < 0.0 else -sd
	var e: float = outer.RIVER_W / 2.0 - absf(p.z - outer.RIVER_Z)
	return outer.RIVER_DEPTH * smoothstep(0.0, 3.0, e) if e > 0.0 else e


func _near_boat(p: Vector3, r: float) -> bool:
	var b: Node3D = outer.boat
	return b != null and Vector2(p.x - b.position.x, p.z - b.position.z).length() < r


func _spot(body: int, home_x: float) -> Vector3:
	## Випадкова точка, де достатньо глибоко.
	for i in 40:
		var p: Vector3
		if body == 0:
			p = outer.POND + Vector3(_rng.randf_range(-outer.POND_HALF.x, outer.POND_HALF.x), 0,
				_rng.randf_range(-outer.POND_HALF.y, outer.POND_HALF.y))
		else:
			p = Vector3(home_x + _rng.randf_range(-25.0, 25.0), 0, outer.RIVER_Z + _rng.randf_range(-2.2, 2.2))
		var d := _depth(body, p)
		if d < 0.9 or _near_boat(p, 3.0):
			continue
		p.y = _rng.randf_range(maxf(BOTTOM, -(d - 0.3)), TOP - 0.1)
		return p
	return Vector3(outer.POND.x, -0.6, outer.POND.z) if body == 0 else Vector3(home_x, -0.6, outer.RIVER_Z)


func _add_school(body: int, kind: int, home_x: float) -> void:
	var k: Array = KINDS[kind]
	var a := _spot(body, home_x)
	var s := {"body": body, "kind": kind, "home": home_x, "a": a, "target": _spot(body, home_x),
		"speed": _rng.randf_range(k[5], k[6]), "pause": 0.0, "sleep": true, "fish": []}
	var n := _rng.randi_range(k[2], k[3])
	for i in n:
		var off := Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-0.15, 0.15), _rng.randf_range(-1.6, 1.6))
		s["fish"].append({"off": off, "p": a + off, "v": Vector3.ZERO,
			"yaw": _rng.randf() * TAU, "pitch": 0.0, "ph": _rng.randf() * TAU,
			"size": k[1] * _rng.randf_range(0.85, 1.15), "t": _rng.randf_range(2.0, 6.0)})
	_schools.append(s)


# ------------------------------------------------------------------ рух
func _process(delta: float) -> void:
	if outer == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = outer.to_local(cam.global_position)
	delta = minf(delta, 0.1)
	var used := [0, 0, 0, 0]
	for s in _schools:
		_step_school(s, delta)
		var near: bool = (s["a"] as Vector3).distance_to(cp) < SIM
		if not near:
			s["sleep"] = true
			continue
		if s["sleep"]:
			# прокинулась — риби одразу біля ватажка, а не пливуть здалеку
			s["sleep"] = false
			for f in s["fish"]:
				f["p"] = s["a"] + f["off"]
				f["v"] = Vector3.ZERO
		_step_fish(s, delta)
		var mmi: MultiMeshInstance3D = _mm[s["kind"]]
		if mmi == null:
			continue
		var mm := mmi.multimesh
		var k: Array = KINDS[s["kind"]]
		for f in s["fish"]:
			var p: Vector3 = f["p"]
			if p.distance_to(cp) > NEAR:
				continue
			var b := Basis(Vector3.UP, float(f["yaw"])) * Basis(Vector3.RIGHT, -float(f["pitch"]))
			b = b.scaled(Vector3.ONE * float(f["size"]))
			var i: int = used[s["kind"]]
			mm.set_instance_transform(i, Transform3D(b, p))
			var spd: float = (f["v"] as Vector3).length()
			mm.set_instance_custom_data(i, Color(fmod(float(f["ph"]), TAU * 8.0), 0.45 + minf(spd, 1.2) * 0.7, 0, 0))
			used[s["kind"]] = i + 1
	for i in _mm.size():
		if _mm[i]:
			(_mm[i] as MultiMeshInstance3D).multimesh.visible_instance_count = used[i]


func _step_school(s: Dictionary, delta: float) -> void:
	## Ватажок зграйки (невидима точка): пливе до цілі, іноді зупиняється й стоїть.
	if s["pause"] > 0.0:
		s["pause"] -= delta
		return
	var a: Vector3 = s["a"]
	var to: Vector3 = s["target"] - a
	if to.length() < 0.8:
		s["target"] = _spot(s["body"], s["home"])
		s["pause"] = _rng.randf_range(0.0, 4.0) if _rng.randf() < 0.6 else 0.0
		var k: Array = KINDS[s["kind"]]
		s["speed"] = _rng.randf_range(k[5], k[6])
		return
	s["a"] = a + to.normalized() * minf(to.length(), float(s["speed"]) * delta)


func _step_fish(s: Dictionary, delta: float) -> void:
	var fish: Array = s["fish"]
	var body: int = s["body"]
	var k: Array = KINDS[s["kind"]]
	var vmax: float = float(k[6]) * 1.6
	for i in fish.size():
		var f: Dictionary = fish[i]
		f["t"] -= delta
		if f["t"] <= 0.0:
			# риба трохи міняє своє місце в зграйці
			f["t"] = _rng.randf_range(2.0, 6.0)
			f["off"] = (f["off"] as Vector3).lerp(Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-0.15, 0.15), _rng.randf_range(-1.6, 1.6)), 0.6)
		var p: Vector3 = f["p"]
		var v: Vector3 = f["v"]
		var want: Vector3 = s["a"] + f["off"]
		# місце в зграйці не має виходити на мілину
		if body == 1:
			want.z = clampf(want.z, outer.RIVER_Z - 2.3, outer.RIVER_Z + 2.3)
		elif _depth(body, want) < 0.8:
			want = want.lerp(s["a"], 0.7)
		var acc := (want - p) * 1.4 - v * 1.5
		# не налазити одна на одну
		for j in fish.size():
			if j == i:
				continue
			var d: Vector3 = p - fish[j]["p"]
			var l := d.length()
			if l < 0.45 and l > 0.001:
				acc += d / l * (0.45 - l) * 6.0
		# не пливти під човен і на мілину
		if body == 0 and _near_boat(p, 2.2):
			var bp: Vector3 = outer.boat.position
			var aw := Vector3(p.x - bp.x, 0, p.z - bp.z)
			acc += aw.normalized() * 2.0
		v += acc * delta
		if v.length() > vmax:
			v = v.normalized() * vmax
		var np := p + v * delta
		var dep := _depth(body, np)
		if dep < 0.55:
			v = (s["a"] - p).normalized() * minf(v.length(), 0.4)
			np = p + v * delta
			dep = _depth(body, np)
		if body == 1:
			np.z = clampf(np.z, outer.RIVER_Z - 2.6, outer.RIVER_Z + 2.6)       # до берега річки не підпливає
			dep = _depth(body, np)
		np.y = clampf(np.y, maxf(BOTTOM, -(maxf(dep, 0.6) - 0.25)), TOP)
		f["p"] = np
		f["v"] = v
		# поворот: туди, куди пливе; коли стоїть у річці — головою проти течії
		var hv := Vector2(v.x, v.z)
		var spd := hv.length()
		var yaw: float = f["yaw"]
		if spd > 0.08:
			yaw = lerp_angle(yaw, atan2(v.x, v.z), minf(1.0, delta * 3.5))
		elif body == 1:
			yaw = lerp_angle(yaw, atan2(UP_FLOW.x, UP_FLOW.z), minf(1.0, delta * 1.2))
		f["yaw"] = yaw
		f["pitch"] = lerpf(f["pitch"], clampf(atan2(v.y, maxf(spd, 0.05)), -0.35, 0.35), minf(1.0, delta * 3.0))
		# хвіст: що швидше пливе — то частіше виляє
		f["ph"] = float(f["ph"]) + delta * (5.0 + v.length() * 12.0)
