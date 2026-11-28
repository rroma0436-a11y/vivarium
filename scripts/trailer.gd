extends Node3D
## Тракторний причіп-самоскид (trailer.glb з Blender, Причіп.blend). Причеплений — їде за трактором
## (дишло на зчіпці, одна вісь), колеса крутяться від пройденої відстані. Гідроциліндр піднімає кузов
## на 45° навколо задньої осі, задній борт висить на верхніх петлях — і сам відчиняється знизу.
## У моделі вперед — +X, тож модель повернута: у вузлі причіп дивиться вздовж +Z.

const EYE := Vector3(0, 0.62, 3.24)      # петля дишла (у системі вузла)
const AXLE_Z := -0.6                      # вісь коліс
const WHEEL_R := 0.5
const TIP := 0.785                        # 45°

var model: Node3D
var bed: Node3D
var gate: Node3D
var top: Node3D
var base_p := Vector3(0.35, 0.45, 0)
var wheels: Array = []
var cyl: Array = []                       # корпус циліндра, середня ступінь, шток
var tip_k := 0.0
var tip_want := 0.0
var hitched := false
var area: Area3D
var _spin := 0.0
var grain := 0.0                          # скільки зерна в кузові: 0 — порожній, 1 — повний
var _heap: Node3D
var _stream: CPUParticles3D


func setup(at: Vector3, yaw: float) -> void:
	position = at
	rotation.y = yaw
	if not Models.exists("trailer"):
		return
	model = load(Models.DIR % "trailer").instantiate()
	model.basis = Basis(Vector3.UP, -PI / 2.0)
	add_child(model)
	bed = model.find_child("Кузов", true, false)
	gate = model.find_child("Задній_борт", true, false)
	top = model.find_child("Кріплення_штока", true, false)
	var bp := model.find_child("Опора_циліндра", true, false) as Node3D
	if bp:
		base_p = bp.position
	for n in ["Колесо_Л", "Колесо_П"]:
		var w := model.find_child(n, true, false)
		if w:
			wheels.append(w)
	for n in ["Гідроциліндр", "Гідроциліндр_2", "Шток"]:
		cyl.append(model.find_child(n, true, false))
	area = Util.pick_area("trailer", Vector3(2.1, 1.8, 4.6), Vector3(0, 0.9, 0.8))
	add_child(area)
	add_child(Util.blob_shadow(1.6))
	_make_heap()
	_apply()


func _make_heap() -> void:
	## Купа зерна в кузові (нахиляється разом із кузовом) і струмінь, що сиплеться з-під заднього борту.
	if bed == null:
		return
	var gm := Util.mat(Color(0.84, 0.66, 0.3), 0.95)
	_heap = Node3D.new()
	bed.add_child(_heap)
	_heap.add_child(Util.box(Vector3(2.9, 1.0, 1.9), gm, Vector3(1.52, 0.5, 0)))
	_heap.add_child(Util.sphere(1.0, gm, Vector3(1.52, 1.0, 0), Vector3(1.45, 0.3, 0.95)))
	_stream = Util.grain_stream()
	_stream.position = Vector3(0, 0.55, -1.55)
	_stream.direction = Vector3(0, -1, -0.5)
	add_child(_stream)
	set_grain(0.0)


func set_grain(k: float) -> void:
	grain = clampf(k, 0.0, 1.0)
	if _heap == null:
		return
	_heap.visible = grain > 0.01
	var h := 0.04 + 0.56 * grain
	_heap.scale = Vector3(1.0, h, 1.0)
	_heap.position = Vector3(0, -0.06, 0)


func pour(on: bool) -> void:
	if _stream:
		_stream.emitting = on


func eye_global() -> Vector3:
	return to_global(EYE)


func _apply() -> void:
	var a := tip_k * TIP
	if bed:
		bed.rotation.z = a
	if gate:
		gate.rotation.z = -a                  # борт лишається вертикальним — знизу щілина
	if bed == null or top == null:
		return
	var t: Vector3 = bed.transform * top.position
	var d := (t - base_p).normalized()
	var b := Basis(Quaternion(Vector3.UP, d))
	var pos := [base_p, (base_p + t) * 0.5, t]
	for i in cyl.size():
		if cyl[i]:
			(cyl[i] as Node3D).transform = Transform3D(b, pos[i])


func _process(delta: float) -> void:
	if model == null:
		return
	if tip_k != tip_want:
		tip_k = move_toward(tip_k, tip_want, delta * 0.35)
		_apply()


func follow_rigid(hitch: Vector3, yaw: float, dt: float) -> void:
	## Заднім ходом: причіп іде рівно за трактором (не «складається»), поступово стаючи в одну лінію з ним.
	if model == null:
		return
	var axle := to_global(Vector3(0, 0, AXLE_Z))
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-dt * 2.5))
	var b := Basis(Vector3.UP, rotation.y)
	var p := Vector3(hitch.x, 0, hitch.z) - b * Vector3(EYE.x, 0, EYE.z)
	global_position = Vector3(p.x, Util.hill_y(p) if Util.on_hill(p) else global_position.y, p.z)
	var na := to_global(Vector3(0, 0, AXLE_Z))
	_spin += (na - axle).dot(b.z) / WHEEL_R
	for w in wheels:
		(w as Node3D).rotation.z = -_spin


func follow(hitch: Vector3) -> void:
	## Дишло на зчіпці трактора: вісь тягнеться за ним (як справжній одновісний причіп).
	if model == null:
		return
	var axle := to_global(Vector3(0, 0, AXLE_Z))
	axle.y = 0.0
	var h := Vector3(hitch.x, 0, hitch.z)
	var dir := h - axle
	if dir.length() < 0.1:
		return
	dir = dir.normalized()
	var na := h - dir * (EYE.z - AXLE_Z)
	_spin += (na - axle).dot(dir) / WHEEL_R
	rotation.y = atan2(dir.x, dir.z)
	var p := na - Basis(Vector3.UP, rotation.y) * Vector3(0, 0, AXLE_Z)
	global_position = Vector3(p.x, Util.hill_y(p) if Util.on_hill(p) else global_position.y, p.z)
	for w in wheels:
		(w as Node3D).rotation.z = -_spin
