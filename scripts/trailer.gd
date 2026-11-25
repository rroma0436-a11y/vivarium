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
	_apply()


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
