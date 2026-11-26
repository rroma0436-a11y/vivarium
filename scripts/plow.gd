extends Node3D
## Кінний плуг (plow.glb): стоїть біля воза під садком. Дідусь чіпляє його позаду воза — і віз тягне плуг.
## У полі під оранку плуг сам заглиблюється й лишає борозни (малює маску поля трактора), поза полем — піднятий.
## Модель: серга (гачок) спереду по +X; модель повернута, щоб серга дивилась на +Z вузла.

const LEN := 2.22
const HALF := 1.11                       # від центру плуга до серги
const SHARE := Vector3(0, 0, 0.25)       # лемех (у системі вузла)

var model: Node3D
var area: Area3D
var cart: Node3D = null                  # до якого воза причеплений (null — стоїть на місці)
var rest_pos := Vector3.ZERO
var rest_yaw := 0.0
var field := Rect2()
var painter: Node = null                 # трактор: у нього маска зораного поля
var down := 0.0                          # 0 — піднятий, 1 — у землі
var _moving := false


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
	area = Util.pick_area("garden_cart", Vector3(0.9, 1.1, LEN), Vector3(0, 0.55, 0))
	add_child(area)


func _hitch_xf(c: Node3D) -> Transform3D:
	## Де стоїть плуг, причеплений позаду воза (віз рівно).
	var yaw: float = c.rotation.y
	var h: Vector3 = c.plow_hitch()
	var p := h - Vector3(sin(yaw), 0, cos(yaw)) * HALF
	p.y = 0.0
	return Transform3D(Basis(Vector3.UP, yaw), p)


func _glide(to: Transform3D, secs: float) -> void:
	## Плавно переносимо плуг (дідусь піднімає й ставить).
	_moving = true
	var from := global_transform
	var k := 0.0
	while k < 1.0:
		k = minf(1.0, k + get_process_delta_time() / secs)
		var t := from.interpolate_with(to, k)
		t.origin.y += sin(k * PI) * 0.35
		global_transform = t
		await get_tree().process_frame
	global_transform = to
	_moving = false


func attach(c: Node3D) -> void:
	if c == null or model == null:
		return
	await _glide(_hitch_xf(c), 1.0)
	cart = c


func detach() -> void:
	if model == null:
		return
	cart = null
	down = 0.0
	model.position.y = 0.0
	await _glide(Transform3D(Basis(Vector3.UP, rest_yaw), rest_pos), 1.0)


func _process(delta: float) -> void:
	if model == null or cart == null or _moving or not is_instance_valid(cart):
		return
	# тягнеться за возом, як причіп: серга — у гаку воза, сам плуг — слідом
	var h: Vector3 = cart.plow_hitch()
	var d := h - global_position
	d.y = 0.0
	if d.length() > 0.01:
		var dir := d.normalized()
		var p := h - dir * HALF
		p.y = Util.hill_y(p) if Util.on_hill(p) else 0.0
		global_position = p
		rotation.y = atan2(dir.x, dir.z)
	var s := to_global(SHARE)
	var in_field := field.has_point(Vector2(s.x, s.z))
	down = move_toward(down, 1.0 if in_field else 0.0, delta * 1.5)
	model.position.y = lerpf(0.14, -0.06, down)
	if down > 0.9 and absf(float(cart.speed)) > 0.2 and painter and is_instance_valid(painter):
		painter._paint(s)
