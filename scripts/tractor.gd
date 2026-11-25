extends Node3D
## Червоний трактор із плугом. Колеса крутяться від пройденої відстані, передні повертають,
## плуг на дорозі піднятий, на полі — опускається й лишає зорані борозни (маска на шейдері поля).
## Кермує дідусь (grandpa.gd: on_tractor). Модель: ніс −X, плуг +X → у вузлі трактор дивиться вздовж +Z.

signal parked

const LENGTH := 4.6
const S := LENGTH / 3.672                       # масштаб моделі
const SEAT := Vector3(0, 1.15, 0.31)            # де сидить водій (стегна)
const WHEEL_R_REAR := 0.49 * S
const WHEEL_R_FRONT := 0.27 * S
const REAR_AXLE := Vector2(-0.33, 0.50)          # центр заднього колеса (x, y у координатах моделі)
const FRONT_AXLE := Vector2(-1.571, 0.278)       # центр переднього колеса
# кермо (у координатах моделі: центр, нормаль до площини керма — до водія, радіус обода)
const SW_MODEL_C := Vector3(-0.681, 1.237, 0.005)
const SW_MODEL_N := Vector3(0.685, 0.728, 0.0)
const SW_R := 0.165 * S
const STEER_RATIO := 2.4
const WHEELBASE := 1.55                          # від задньої осі до передньої, м                         # кермо обертається в стільки разів більше за колеса
# де людина ставить ноги й руки, коли лізе на трактор і сидить (у вузлі трактора: +Z — уперед, +X — ліворуч водія)
const SEAT_HIPS := Vector3(0.0, 1.26, 0.24)      # стегна водія на сидінні
const FEET := [Vector3(0.27, 0.66, 0.86), Vector3(-0.27, 0.66, 0.86)]   # ліва, права ступні водія
const CLIMB_FROM := Vector3(-1.05, 0.0, 1.22)    # де стати на землі, щоб залізти (праворуч, перед заднім колесом)
const STEP := Vector3(-0.47, 0.52, 1.2)          # приступка
const FENDER := Vector3(-0.6, 1.08, 0.86)        # передній край правого крила — за нього тримаються

var model: Node3D
var wheels_rear: Array = []
var wheels_front: Array = []
var plow: Node3D
var steer_wheel: Node3D                         # кермо (обертається разом із передніми колесами)
var sw_angle := 0.0
var _sw_c := Vector3(0, 1.55, 0.85)
var _sw_n := Vector3(0, 0.73, -0.68)
var _spin := 0.0
var steer := 0.0
var plow_down := false
var _plow_k := 0.0                              # 0 — піднятий, 1 — опущений
var speed := 0.0
var state := "parked"                           # parked / drive / plow
var shed_pos := Vector3.ZERO
var shed_yaw := 0.0
var field: Rect2                                # поле під оранку (x, z)
var driver: Node3D
var _mask: Image
var _mask_tex: ImageTexture
var _mask_dirty := false
var _mask_t := 0.0
var _field_mat: ShaderMaterial
var plowed := 0.0                               # частка зораного поля 0..1
var _smoke: CPUParticles3D
var _clods: CPUParticles3D
var _engine: AudioStreamPlayer3D
var _gen: AudioStreamGeneratorPlayback
var _phase := 0.0
var _rpm := 0.0
var area: Area3D
var _bubble: Label3D
var _bubble_left := 0.0
var _job := 0

const MASK_N := 64


func setup(shed: Vector3, yaw: float, field_rect: Rect2) -> void:
	shed_pos = shed
	shed_yaw = yaw
	field = field_rect
	position = shed
	rotation.y = yaw
	model = Models.spawn(self, "tractor", LENGTH, "realx")
	if model == null:
		return
	model.rotation.y = PI / 2.0
	_cut_parts()
	area = Util.pick_area("tractor", Vector3(2.4, 2.2, 4.8), Vector3(0, 1.1, -0.3))
	add_child(area)
	_bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 52)
	_bubble.pixel_size = 0.006
	_bubble.position = Vector3(0, 2.9, 0)
	add_child(_bubble)
	_make_fx()
	_make_engine()


func _cut_parts() -> void:
	var mis := model.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return
	var mi: MeshInstance3D = mis[0]
	# задні колеса (великі) і передні — вирізаємо циліндром навколо справжньої осі колеса.
	# Межі підібрані по геометрії моделі: лише шина з диском. Крило (воно ширше за шину,
	# r ≥ 0.53, і заходить усередину до z ≈ 0.3) та балка переднього моста (z < 0.4) лишаються на місці.
	for sz in [1.0, -1.0]:
		var rz := Vector2(0.385, 0.80) if sz > 0.0 else Vector2(-0.80, -0.385)
		var rc := REAR_AXLE
		var rp := Models.cut(model, AABB(Vector3(rc.x - 0.53, rc.y - 0.53, rz.x), Vector3(1.06, 1.06, rz.y - rz.x)), 100.0, mi, 0.525)
		if rp:
			var h := Models.hinge(rp, mi.to_global(Vector3(rc.x, rc.y, sz * 0.58)))
			wheels_rear.append(h)
		var fz := Vector2(0.405, 0.62) if sz > 0.0 else Vector2(-0.62, -0.405)
		var fc := FRONT_AXLE
		var fp := Models.cut(model, AABB(Vector3(fc.x - 0.3, fc.y - 0.3, fz.x), Vector3(0.6, 0.6, fz.y - fz.x)), 100.0, mi, 0.285)
		if fp:
			var hf := Models.hinge(fp, mi.to_global(Vector3(fc.x, fc.y, sz * 0.48)))
			wheels_front.append(hf)
	# кермо: лише обід зі спицями (колонка лежить на осі, тож обертати її разом — не страшно)
	var sw := Models.cut(model, AABB(Vector3(-0.815, 1.105, -0.195), Vector3(0.285, 0.27, 0.39)), 100.0, mi)
	var to_node := global_transform.affine_inverse() * mi.global_transform
	_sw_c = to_node * SW_MODEL_C
	_sw_n = (to_node.basis * SW_MODEL_N).normalized()
	if sw:
		steer_wheel = Models.hinge(sw, mi.to_global(SW_MODEL_C))
	# плуг (усе позаду навісного механізму)
	var pp := Models.cut(model, AABB(Vector3(0.70, -0.02, -0.5), Vector3(1.25, 0.85, 1.0)), 100.0, mi)
	if pp:
		plow = Models.hinge(pp, mi.to_global(Vector3(0.70, 0.62, 0.0)))
		_plow_parent = plow.get_parent()
		_plow_pos0 = plow.position
	hitch_local = to_local(mi.to_global(Vector3(0.70, 0.62, 0.0)))
	hitch_local.y = 0.62
	_plow_k = 0.0
	_apply_plow()


func _make_fx() -> void:
	# дим із труби
	_smoke = CPUParticles3D.new()
	_smoke.position = Vector3(0.35, 2.15, 1.63)
	_smoke.amount = 14
	_smoke.lifetime = 1.6
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.0
	_smoke.gravity = Vector3(0, 0.3, 0)
	_smoke.scale_amount_min = 0.15
	_smoke.scale_amount_max = 0.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	_smoke.scale_amount_curve = sc
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.55, 0.55, 0.55, 0.45)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	_smoke.mesh = sm
	_smoke.emitting = false
	add_child(_smoke)
	# грудочки землі з-під плуга
	_clods = CPUParticles3D.new()
	_clods.position = Vector3(0, 0.15, -2.0)
	_clods.amount = 22
	_clods.lifetime = 0.8
	_clods.direction = Vector3(0, 1, -0.3)
	_clods.spread = 40.0
	_clods.initial_velocity_min = 1.0
	_clods.initial_velocity_max = 2.2
	_clods.gravity = Vector3(0, -9.0, 0)
	_clods.scale_amount_min = 0.05
	_clods.scale_amount_max = 0.11
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = Util.mat(Color(0.3, 0.2, 0.12), 1.0)
	_clods.mesh = bm
	_clods.emitting = false
	add_child(_clods)


func _make_engine() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = 22050.0
	g.buffer_length = 0.25
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = g
	_engine.bus = "SFX"
	_engine.unit_size = 6.0
	_engine.max_distance = 60.0
	_engine.volume_db = -12.0
	add_child(_engine)


func _engine_step() -> void:
	var on := state != "parked"
	if on and not _engine.playing:
		_engine.play()
		_gen = _engine.get_stream_playback()
	elif not on and _engine.playing:
		_engine.stop()
		_gen = null
	_smoke.emitting = on
	if _gen == null:
		return
	# «тр-р-р»: імпульси, частота яких росте з обертами
	var f := 9.0 + _rpm * 6.0
	var n := _gen.get_frames_available()
	for i in n:
		_phase += f / 22050.0
		if _phase >= 1.0:
			_phase -= 1.0
		var env := exp(-_phase * 7.0)
		var s := (randf() * 2.0 - 1.0) * 0.35 * env + sin(_phase * TAU * 3.0) * 0.25 * env
		_gen.push_frame(Vector2(s, s) * 0.6)


# ------------------------------------------------------------------ поле
func make_field(parent: Node3D) -> void:
	## Земля під оранку: стерня, а де пройшов плуг — темні борозни (маска 64×64).
	_mask = Image.create(MASK_N, MASK_N, false, Image.FORMAT_L8)
	_mask.fill(Color(0, 0, 0))
	_mask_tex = ImageTexture.create_from_image(_mask)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 rect;
varying vec3 wp;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// зорана рілля трохи піднімається скибами (рельєф борозен), стерня лишається рівною
	float m = smoothstep(0.25, 0.75, textureLod(mask, (wp.xz - rect.xy) / rect.zw, 0.0).r);
	float fur = 0.5 + 0.5 * sin(wp.x * 6.2831 / 0.5);
	VERTEX.y += m * (0.02 + 0.05 * fur + 0.02 * vn(wp.xz * 2.5));
}
void fragment() {
	vec2 uv = (wp.xz - rect.xy) / rect.zw;
	float m = smoothstep(0.25, 0.75, texture(mask, uv).r);
	float n = vn(wp.xz * 3.0) * 0.5 + vn(wp.xz * 13.0) * 0.5;
	float fine = vn(wp.xz * vec2(40.0, 6.0));
	float rows = smoothstep(0.2, 0.8, abs(sin(wp.x * 3.14159 / 0.32)));
	// стерня: рядки, солом'яні пасма, зелені латки бур'яну й сухіші плями
	vec3 stub = mix(vec3(0.48, 0.42, 0.24), vec3(0.70, 0.60, 0.35), rows * 0.5 + n * 0.3 + fine * 0.2);
	stub = mix(stub, vec3(0.36, 0.45, 0.2), smoothstep(0.45, 0.85, vn(wp.xz * 0.35)) * 0.55);
	stub = mix(stub, vec3(0.78, 0.7, 0.48), smoothstep(0.6, 0.9, vn(wp.xz * 0.8 + 7.0)) * 0.35);
	// поворотні смуги (краї поля) — утоптані, світліші, з колією
	vec2 e = min(uv, 1.0 - uv) * rect.zw;
	float head = 1.0 - smoothstep(1.2, 2.6, e.y);
	stub = mix(stub, vec3(0.55, 0.5, 0.33), head * 0.45);
	// рілля: борозни й скиби, грудки землі, вологіші темні місця
	float fur = 0.5 + 0.5 * sin(wp.x * 6.2831 / 0.5);
	float clod = smoothstep(0.55, 0.8, vn(wp.xz * 9.0 + 3.0));
	vec3 soil = mix(vec3(0.16, 0.1, 0.06), vec3(0.36, 0.25, 0.15), fur * 0.6 + n * 0.25 + clod * 0.15);
	soil *= mix(0.82, 1.08, vn(wp.xz * 0.25));
	ALBEDO = mix(stub, soil, m);
	ROUGHNESS = mix(0.95, 0.99, m);
}
"""
	_field_mat = ShaderMaterial.new()
	_field_mat.shader = sh
	_field_mat.set_shader_parameter("mask", _mask_tex)
	_field_mat.set_shader_parameter("rect", Vector4(field.position.x, field.position.y, field.size.x, field.size.y))
	var pm := PlaneMesh.new()
	pm.size = field.size
	pm.subdivide_width = int(field.size.x * 6.0)       # густіша сітка — під рельєф борозен
	pm.subdivide_depth = int(field.size.y * 1.5)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _field_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(field.get_center().x, 0.035, field.get_center().y)
	parent.add_child(mi)
	# межа поля — невеликий валок землі по краях і трав'яна межа за ним
	var margin := Util.mat(Color(0.42, 0.52, 0.26), 1.0)
	for e in [[Vector3(field.get_center().x, 0.02, field.position.y - 0.9), Vector3(field.size.x + 2.2, 0.03, 1.1)],
			[Vector3(field.position.x - 0.9, 0.02, field.get_center().y), Vector3(1.1, 0.03, field.size.y)],
			[Vector3(field.end.x + 0.9, 0.02, field.get_center().y), Vector3(1.1, 0.03, field.size.y)]]:
		var g := Util.box(e[1], margin, e[0])
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(g)
	var edge := Util.mat(Color(0.36, 0.28, 0.17), 1.0)
	for e in [[Vector3(field.get_center().x, 0.05, field.position.y), Vector3(field.size.x + 0.4, 0.12, 0.35)],
			[Vector3(field.get_center().x, 0.05, field.end.y), Vector3(field.size.x + 0.4, 0.12, 0.35)],
			[Vector3(field.position.x, 0.05, field.get_center().y), Vector3(0.35, 0.12, field.size.y)],
			[Vector3(field.end.x, 0.05, field.get_center().y), Vector3(0.35, 0.12, field.size.y)]]:
		var b := Util.box(e[1], edge, e[0])
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(b)


func reset_field() -> void:
	if _mask == null:
		return
	_mask.fill(Color(0, 0, 0))
	_mask_tex.update(_mask)
	plowed = 0.0


func _paint(p: Vector3) -> void:
	var u := (p.x - field.position.x) / field.size.x
	var v := (p.z - field.position.y) / field.size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return
	var cx := u * MASK_N
	var cy := v * MASK_N
	var r := 0.95 / field.size.x * MASK_N + 0.6
	for y in range(int(cy - r - 1), int(cy + r + 2)):
		for x in range(int(cx - r - 1), int(cx + r + 2)):
			if x < 0 or y < 0 or x >= MASK_N or y >= MASK_N:
				continue
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= r:
				var old := _mask.get_pixel(x, y).r
				if old < 1.0:
					_mask.set_pixel(x, y, Color(1, 1, 1))
					plowed += 1.0 / float(MASK_N * MASK_N)
	_mask_dirty = true


# ------------------------------------------------------------------ рух
func say(t: String, secs := 2.0) -> void:
	if _bubble == null:
		return
	_bubble.text = t
	_bubble.visible = true
	_bubble_left = secs


func seat_global() -> Vector3:
	return to_global(SEAT)


func sw_axis() -> Vector3:
	## Вісь керма у вузлі трактора (дивиться на водія й угору).
	return _sw_n


func sw_center() -> Vector3:
	return _sw_c


func grip_global(left: bool) -> Vector3:
	## Де тримається кисть водія (зап'ясток): на ободі керма «за дев'ятою й третьою»,
	## трохи ближче до водія. Кермо повертається — кисті їдуть разом з ободом.
	var n := sw_axis()
	var e1 := Vector3.RIGHT                         # ліворуч водія
	var e2 := n.cross(e1).normalized()              # до верху керма
	if e2.y < 0.0:
		e2 = -e2
	var a := deg_to_rad(-12.0 if left else 192.0)
	var rim := (e1 * cos(a) + e2 * sin(a)) * (SW_R + 0.025)
	return to_global(sw_center() + Basis(n, sw_angle) * rim + n * 0.045)


func local_to_global(p: Vector3) -> Vector3:
	return to_global(p)


func plow_pos() -> Vector3:
	return to_global(Vector3(0, 0, -2.0))


func _apply_plow() -> void:
	if plow == null or not plow_on:
		return
	var k := 1.0 - _plow_k
	plow.basis = Basis(Vector3.RIGHT, k * 0.32)
	plow.position.y = 0.62 * S + k * 0.3


var _day := -1


func _process(delta: float) -> void:
	if model == null:
		return
	var dd := int(Game.state.get("day", 1))
	if dd != _day:
		if _day != -1 and state == "parked":
			reset_field()                # за ніч поле знову заростає стернею
		_day = dd
	if plow_on:
		_plow_k = move_toward(_plow_k, 1.0 if plow_down else 0.0, delta * 0.8)
		_apply_plow()
	else:
		plow_down = false
	_spin += speed * delta / WHEEL_R_REAR
	var spin_f := _spin * WHEEL_R_REAR / WHEEL_R_FRONT
	for w in wheels_rear:
		(w as Node3D).basis = Basis(Vector3.RIGHT, _spin)
	for w in wheels_front:
		(w as Node3D).basis = Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, spin_f)
	sw_angle = steer * STEER_RATIO
	if steer_wheel:
		steer_wheel.basis = Basis(sw_axis(), sw_angle)
	_rpm = lerpf(_rpm, 1.0 + absf(speed) * 0.6 + (0.5 if plow_down and _plow_k > 0.9 else 0.0), 1.0 - exp(-delta * 2.0))
	_engine_step()
	# легке тремтіння корпусу
	if state != "parked":
		model.position.y = sin(Time.get_ticks_msec() * 0.045) * 0.008
	var digging := plow_down and _plow_k > 0.9 and absf(speed) > 0.2 and field.grow(0.5).has_point(Vector2(plow_pos().x, plow_pos().z))
	_clods.emitting = digging
	if digging:
		_paint(plow_pos())
	if trailer:
		trailer.follow(hitch_global())
	_mask_t += delta
	if _mask_dirty and _mask_t > 0.15:
		_mask_t = 0.0
		_mask_dirty = false
		_mask_tex.update(_mask)
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.visible = false


func _drive_to(p: Vector3, v: float, reach := 0.7) -> void:
	## Їде до точки, як справжня машина: повертає кермом (плавно), а не на місці; обминає хати й дерева.
	var id := _job
	var t := 0.0
	while id == _job:
		var dt := get_process_delta_time()
		t += dt
		var to := p - global_position
		to.y = 0.0
		var d := to.length()
		if d < reach or t > 90.0:
			return
		var g := Vehicles.steer_target(global_position, p, 1.5) if d > 6.0 else p
		var tg := g - global_position
		var want := atan2(tg.x, tg.z)
		var diff := angle_difference(rotation.y, want)
		steer = lerpf(steer, clampf(diff * 1.6, -0.55, 0.55), 1.0 - exp(-dt * 4.0))
		var vv := v * clampf(1.2 - absf(diff) * 0.5, 0.35, 1.0)
		if d < 2.0:
			vv = minf(vv, maxf(0.6, d))
		speed = move_toward(speed, vv, dt * 1.8)
		rotation.y += clampf(diff, -1.0, 1.0) * dt * speed / 1.9 * 1.6
		global_position += Vector3(sin(rotation.y), 0, cos(rotation.y)) * speed * dt
		await get_tree().process_frame


func _stop() -> void:
	while absf(speed) > 0.05:
		speed = move_toward(speed, 0.0, get_process_delta_time() * 3.0)
		global_position += Vector3(sin(rotation.y), 0, cos(rotation.y)) * speed * get_process_delta_time()
		await get_tree().process_frame
	speed = 0.0
	steer = 0.0


func start_engine() -> void:
	state = "drive"
	say("Тр-р-р-р!", 1.5)


# ------------------------------------------------------------------ ручне керування (джойстик гравця)
var manual := false


func begin_manual() -> void:
	## Гравець бере кермо: автоматичні рухи припиняються.
	_job += 1
	manual = true
	state = "drive"
	plow_down = false


func manual_step(j: Vector2, climb: float, dt: float) -> void:
	## Щокадру: j.y — газ (вперед) чи задній хід, j.x — кермо; ▲ піднімає плуг, ▼ опускає.
	## Їздити можна куди завгодно (окрім річки поза містком, ставка, пагорба й подвір'я).
	if trailer:
		if climb > 0.3:
			trailer.tip_want = 1.0                  # ▲ — кузов причепа вгору, ▼ — униз
		elif climb < -0.3:
			trailer.tip_want = 0.0
	elif climb > 0.3:
		plow_down = false
	elif climb < -0.3:
		plow_down = true
	var vmax := 2.3 if plow_down else 4.2
	var want := j.y * vmax if j.y >= 0.0 else j.y * 1.6
	# розгін плавний, гальмування трохи швидше
	var acc := 1.6 if absf(want) > absf(speed) and signf(want) == signf(speed) else 3.0
	speed = move_toward(speed, want, dt * acc)
	if speed < -0.2:
		plow_down = false                          # заднім ходом плуг піднято
	# кермо крутиться поступово (≈0,5 с від краю до краю), а не стрибає
	var st := clampf(-j.x, -1.0, 1.0) * 0.55
	steer = move_toward(steer, st, dt * 1.3)
	rotation.y += steer * speed / WHEELBASE * dt
	var from := global_position
	var np := global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * speed * dt
	np = Vehicles.keep_out(np, 1.3, from)
	if trailer_blocked(np, rotation.y):
		rotation.y -= steer * speed / WHEELBASE * dt
		np = from
		speed = 0.0
	# уперлися — швидкість гасне (не «пролазимо» крізь хату)
	var moved := np.distance_to(from)
	if absf(speed) * dt > 0.001 and moved < absf(speed) * dt * 0.3:
		speed = move_toward(speed, 0.0, dt * 6.0)
	global_position = np


func end_manual() -> void:
	## Гравець віддав кермо: плуг угору, плавно зупиняємось.
	manual = false
	plow_down = false
	_job += 1
	await _stop()


func drive_route(points: Array, v := 3.2) -> void:
	_job += 1
	state = "drive"
	for p in points:
		await _drive_to(p, v)
	await _stop()


func plow_field() -> void:
	## Оранка: ряди вздовж z, на кінці ряду плуг піднімається, розворот — і наступний ряд.
	_job += 1
	var id := _job
	state = "plow"
	var x0 := field.position.x + 0.9
	var x1 := field.end.x - 0.6
	var z_in := field.end.y - 0.4            # південний край (ближче до дороги)
	var z_far := field.position.y + 0.4
	var step := 1.5
	var x := x0
	var dir := -1.0                           # спершу на північ (до z_far)
	await _drive_to(Vector3(x, 0, field.end.y + 2.6), 2.5)
	while x <= x1 and id == _job:
		var a := Vector3(x, 0, z_in if dir < 0.0 else z_far)
		var b := Vector3(x, 0, z_far if dir < 0.0 else z_in)
		await _drive_to(a, 1.8, 0.5)
		if id != _job:
			return
		plow_down = true
		say("Оремо!", 1.2)
		await _drive_to(b, 2.0, 0.5)
		plow_down = false
		if id != _job:
			return
		# розворот на краю поля
		var out := b + Vector3(0.0, 0, 2.4 * (1.0 if dir > 0.0 else -1.0))
		if x + step <= x1:
			await _drive_to(out + Vector3(step * 0.5, 0, 0), 1.6, 0.6)
		x += step
		dir = -dir
	plow_down = false
	_mask_tex.update(_mask)
	state = "drive"


func go_park(route: Array) -> void:
	# з далекої дороги — спершу до поля (через місток і село, якщо треба), далі звичним шляхом
	var far := global_position.distance_to(shed_pos) > 25.0
	var pre: Array = Vehicles.route(global_position, route[0]) if far else []
	if not pre.is_empty():
		pre.pop_back()
	await drive_route(pre + route + [shed_pos + Vector3(0, 0, 2.0)], 3.2)
	# заднім ходом під навіс не їздимо — просто стаємо носом до виїзду
	var t := 0.0
	while t < 1.2:
		t += get_process_delta_time()
		rotation.y = lerp_angle(rotation.y, shed_yaw, 0.08)
		global_position = global_position.lerp(shed_pos, 0.06)
		await get_tree().process_frame
	global_position = shed_pos
	rotation.y = shed_yaw
	state = "parked"
	parked.emit()


func dbg_steer(v: String) -> void:
	steer = float(v)


func poke() -> void:
	say(["Тр-тр!", "Я трактор Червоненький!", "Поле орати — то моя робота!"][randi() % 3], 2.0)


# ------------------------------------------------------------------ Ніка за кермом (main.gd → start_mount("tractor"))
func cab_points() -> Dictionary:
	## Точки для Ніки у системі трактора: де стати, приступка, площадка біля сидіння, сидіння, педалі.
	return {"climb": CLIMB_FROM, "steps": [STEP], "sill": Vector3(-0.28, 0.66, 0.72), "seat": SEAT_HIPS + Vector3(0.0, 0.07, 0.18),
		"feet": FEET, "side": -1.0, "hold": FENDER}


func ride_anim(v: float, steer_to: float, dt: float) -> void:
	## Колеса й кермо крутяться самі (_process) — від швидкості й повороту.
	speed = v
	steer = move_toward(steer, clampf(steer_to, -0.55, 0.55), dt * 1.3)


func open_door(_on: bool) -> void:
	pass


func solid(_on: bool) -> void:
	pass


func nika_begin() -> void:
	begin_manual()
	start_engine()


func nika_end() -> void:
	manual = false
	plow_down = false
	_job += 1
	speed = 0.0
	steer = 0.0
	state = "parked"                 # стоїть там, де Ніка злізла


# ------------------------------------------------------------------ причепи: плуг і причіп-самоскид (trailer.gd)
var plow_on := true                    # плуг на навісці
var trailer = null                     # причеплений причіп
var hitch_local := Vector3(0, 0.62, -1.6)
var _plow_parent: Node3D
var _plow_pos0 := Vector3.ZERO


func hitch_global() -> Vector3:
	return to_global(hitch_local + Vector3(0, 0, -0.12))


func detach_plow() -> bool:
	## Плуг опускаємо на землю й лишаємо там, де стоїть трактор.
	if plow == null or not plow_on:
		return false
	plow_down = false
	_plow_k = 1.0
	_apply_plow()
	plow.reparent(get_parent(), true)
	plow_on = false
	return true


func attach_plow() -> String:
	## "ok", або чому ні: "on" (уже), "trailer" (заважає причіп), "far" (плуг далеко від навіски).
	if plow == null or plow_on:
		return "on"
	if trailer:
		return "trailer"
	if plow.global_position.distance_to(_plow_parent.to_global(_plow_pos0)) > 3.0:
		return "far"
	plow.reparent(_plow_parent, false)
	plow.position = _plow_pos0
	plow_on = true
	_plow_k = 0.0
	plow_down = false
	_apply_plow()
	return "ok"


func attach_trailer(t) -> String:
	if trailer:
		return "on"
	if plow_on:
		return "plow"
	if t == null or t.eye_global().distance_to(hitch_global()) > 3.5:
		return "far"
	trailer = t
	t.hitched = true
	return "ok"


func detach_trailer() -> void:
	if trailer:
		trailer.hitched = false
		trailer = null



# ------------------------------------------------------------------ причіп не проїжджає крізь хати, паркани, дерева й людей
func _trailer_pose(np: Vector3, yaw: float) -> Transform3D:
	## Де опиниться причіп, якщо трактор стане в np з поворотом yaw (так само, як trailer.follow).
	var h: Vector3 = Transform3D(Basis(Vector3.UP, yaw), np) * (hitch_local + Vector3(0, 0, -0.12))
	var axle: Vector3 = trailer.to_global(Vector3(0, 0, trailer.AXLE_Z))
	var hh := Vector3(h.x, 0, h.z)
	var dir := hh - Vector3(axle.x, 0, axle.z)
	if dir.length() < 0.1:
		return trailer.global_transform
	dir = dir.normalized()
	var na: Vector3 = hh - dir * (trailer.EYE.z - trailer.AXLE_Z)
	var b := Basis(Vector3.UP, atan2(dir.x, dir.z))
	return Transform3D(b, na - b * Vector3(0, 0, trailer.AXLE_Z))


const TRL_PTS := [Vector3(-0.95, 0, -1.5), Vector3(0.95, 0, -1.5), Vector3(0.95, 0, 0.4), Vector3(0.95, 0, 1.9),
	Vector3(-0.95, 0, 1.9), Vector3(-0.95, 0, 0.4), Vector3(0, 0, -1.5)]


func _trailer_pen(xf: Transform3D) -> float:
	## Наскільки причіп у цьому положенні «в'їхав» у перешкоди (0 — вільно).
	var pen := 0.0
	var sk := [self, trailer]
	var g = get_node_or_null("/root/Main")
	if g and "girl" in g and g.girl:
		sk.append(g.girl)
	var bz = null
	if g and "world" in g and g.world and g.world.outer:
		bz = g.world.outer.bazaar
	var pts: Array = []
	for q in TRL_PTS:
		var p: Vector3 = xf * (q as Vector3)
		p.y = 0.0
		pts.append(p)
		if bz == null or not bz.in_area(p):
			pen += Vehicles.keep_out(p, 0.15, p).distance_to(p)
		elif bz.building_at(p) != null:
			pen += 0.5
		pen += Util.push_solids(p, 0.2, sk).distance_to(p)
	# стіни базару, хат, сараїв і паркани (шар 1 << 17) — промені вздовж бортів
	var space := get_world_3d().direct_space_state
	for i in 6:
		var a: Vector3 = pts[i] + Vector3(0, 0.7, 0)
		var b: Vector3 = pts[(i + 1) % 6] + Vector3(0, 0.7, 0)
		var rq := PhysicsRayQueryParameters3D.create(a, b, 1 << 17)
		var hit := space.intersect_ray(rq)
		if not hit.is_empty():
			pen += 0.4
	return pen


func trailer_blocked(np: Vector3, yaw: float) -> bool:
	if trailer == null or trailer.model == null:
		return false
	var now := _trailer_pen(trailer.global_transform)
	var nxt := _trailer_pen(_trailer_pose(np, yaw))
	return nxt > 0.05 and nxt > now + 0.01
