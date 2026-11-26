extends Node3D
## Кінний плуг (plow.glb). Стоїть біля воза під садком; дідусь кладе його на віз, на полі знімає,
## чіпляє посторонками до коня й оре, тримаючись ззаду за чепіги.
## У полі під оранку плуг сам заглиблюється й лишає борозни (малює маску поля трактора), поза полем — піднятий.
## Модель: серга (гачок) спереду по +X; модель повернута, щоб серга дивилась на +Z вузла.

const LEN := 2.22
const HALF := 1.11                       # від центру плуга до серги
const TRACE := 2.0                       # від серги до центру коня (посторонки)
const SHARE := Vector3(0, 0, 0.25)       # лемех (у системі вузла)
const BED := Vector3(0.5, 0.88, -0.7)    # де лежить на возі (на боці), у системі воза
const STAND := 1.65                      # де стоїть дідусь позаду (від центру плуга)

var model: Node3D
var area: Area3D
var state := "ground"                    # ground / cart / horse / carry
var cart: Node3D = null
var horse: Node3D = null
var rest_pos := Vector3.ZERO
var rest_yaw := 0.0
var field := Rect2()
var painter: Node = null                 # трактор: у нього маска зораного поля
var down := 0.0                          # 0 — піднятий, 1 — у землі
var _grips: Array = []
var _traces: Array = []                  # посторонки й вага (валок)
var _last := Vector3.INF
var _v := 0.0


func setup(at: Vector3, yaw: float, f: Rect2, p: Node) -> void:
	rest_pos = at
	rest_yaw = yaw
	field = f
	painter = p
	position = at
	rotation.y = yaw
	model = Models.spawn(self, "plow", LEN, "realx")
	if model == null:
		return
	model.rotation.y = -PI / 2.0
	for nm in ["Grip_L", "Grip_R"]:
		_grips.append(model.find_child(nm + "*", true, false))
	area = Util.pick_area("garden_cart", Vector3(0.9, 1.1, LEN), Vector3(0, 0.55, 0))
	add_child(area)
	var rope := Util.mat(Color(0.32, 0.22, 0.12), 0.9)
	for i in 4:
		var b := BoxMesh.new()
		b.size = Vector3(0.025, 0.025, 1.0) if i < 3 else Vector3(0.62, 0.05, 0.05)
		var mi := MeshInstance3D.new()
		mi.mesh = b
		mi.material_override = rope
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_traces.append(mi)


# ---------------- для дідуся
func grip(left: bool) -> Vector3:
	## Де чепіга (ліва — для лівої руки дідуся, що стоїть позаду обличчям уперед).
	var g = _grips[0 if left else 1] if _grips.size() == 2 else null
	if g and is_instance_valid(g):
		return (g as Node3D).global_position
	return to_global(Vector3(0.31 if left else -0.31, 1.0, -1.11))


func rear_stand() -> Vector3:
	var p := to_global(Vector3(0, 0, -STAND))
	p.y = 0.0
	return p


func bed_xf(c: Node3D) -> Transform3D:
	return c.global_transform * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), BED)


func side_xf(c: Node3D) -> Transform3D:
	## На землі біля воза (з правого боку), уздовж воза.
	var t: Transform3D = c.global_transform * Transform3D(Basis(), Vector3(1.7, 0, -0.6))
	t.origin.y = 0.0
	return Transform3D(Basis(Vector3.UP, c.rotation.y), t.origin)


func rest_xf() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rest_yaw), rest_pos)


func glide(to: Transform3D, secs: float) -> void:
	## Дідусь несе плуг: плавно переносимо його (трохи піднятий).
	state = "carry"
	cart = null
	_show_traces(false)
	if model:
		model.position.y = 0.0
	var from := global_transform
	var k := 0.0
	while k < 1.0:
		k = minf(1.0, k + get_process_delta_time() / secs)
		var t := from.interpolate_with(to, k)
		t.origin.y += sin(k * PI) * 0.25
		global_transform = t
		await get_tree().process_frame
	global_transform = to


func put_in_cart(c: Node3D) -> void:
	state = "cart"
	cart = c


func put_down() -> void:
	state = "ground"
	cart = null
	var y := rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, y), Vector3(global_position.x, 0.0, global_position.z))


func hitch_horse(h: Node3D) -> void:
	state = "horse"
	horse = h
	_last = Vector3.INF
	_show_traces(true)


func unhitch() -> void:
	state = "ground"
	horse = null
	down = 0.0
	if model:
		model.position.y = 0.0
	_show_traces(false)


func _show_traces(on: bool) -> void:
	for t in _traces:
		(t as Node3D).visible = on


func _span(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var bs := Basis.looking_at(d / l, Vector3.UP) * Basis.from_scale(Vector3(1, 1, l))
	mi.global_transform = Transform3D(bs, (a + b) * 0.5)


func _draw_traces() -> void:
	## Посторонки від хомута до валка, валок — до серги плуга.
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var right := Vector3(fwd.z, 0, -fwd.x)
	var eye := to_global(Vector3(0, 0.49, HALF))
	var bar := eye + fwd * 0.45 + Vector3(0, 0.12, 0)
	_span(_traces[0], horse.to_global(Vector3(0.3, 1.05, 0.45)), bar - right * 0.3)
	_span(_traces[1], horse.to_global(Vector3(-0.3, 1.05, 0.45)), bar + right * 0.3)
	_span(_traces[2], bar, eye)
	var bt: MeshInstance3D = _traces[3]
	bt.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), bar)


func _process(delta: float) -> void:
	if model == null:
		return
	if state == "cart" and cart and is_instance_valid(cart):
		global_transform = bed_xf(cart)
		model.position.y = 0.0
		return
	if state != "horse" or horse == null or not is_instance_valid(horse):
		return
	# тягнеться за конем: серга — позаду коня на посторонках, сам плуг — слідом
	var h: Vector3 = horse.to_global(Vector3(0, 0, -TRACE))
	var d := h - global_position
	d.y = 0.0
	if d.length() > 0.01:
		var dir := d.normalized()
		var p := h - dir * HALF
		p.y = Util.hill_y(p) if Util.on_hill(p) else 0.0
		global_position = p
		rotation.y = atan2(dir.x, dir.z)
	if _last != Vector3.INF:
		_v = lerpf(_v, global_position.distance_to(_last) / maxf(delta, 0.001), 1.0 - exp(-delta * 5.0))
	_last = global_position
	var s := to_global(SHARE)
	var in_field := field.has_point(Vector2(s.x, s.z))
	down = move_toward(down, 1.0 if in_field else 0.0, delta * 1.5)
	model.position.y = lerpf(0.1, -0.06, down)
	if down > 0.9 and _v > 0.2 and painter and is_instance_valid(painter):
		painter._paint(s)
	_draw_traces()
