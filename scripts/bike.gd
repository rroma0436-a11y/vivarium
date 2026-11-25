extends Node3D
## Дитячий велосипед Ніки (Велосипед.blend → bicycle.glb). Коли Ніка їде — крутяться колеса й педалі,
## кермо повертає. Вперед — вісь +z, лівий бік — +x.

const K := 0.45                                   # модель велосипеда дорослого розміру → дитячий
const SEAT_HIPS := Vector3(0, 0.55, -0.16)        # де стегна Ніки, коли сидить на сідлі
const R_WHEEL := 0.153
var model: Node3D
var steer: Node3D
var wheel_f: Node3D
var wheel_r: Node3D
var crank: Node3D
var pedal_l: Node3D
var pedal_r: Node3D
var area: Area3D
var _base := {}
var _grip := [Vector3.ZERO, Vector3.ZERO]          # точки руків'їв у системі керма
var _wheel_a := 0.0
var _steer := 0.0


func setup() -> bool:
	if not ResourceLoader.exists("res://assets/models/bicycle.glb"):
		return false
	model = load("res://assets/models/bicycle.glb").instantiate()
	model.scale = Vector3.ONE * K
	add_child(model)
	steer = model.find_child("Рульова_вісь", true, false)
	wheel_f = model.find_child("Колесо_П", true, false)
	wheel_r = model.find_child("Колесо_З", true, false)
	crank = model.find_child("Шатуни", true, false)
	pedal_l = model.find_child("Педаль_Л", true, false)
	pedal_r = model.find_child("Педаль_П", true, false)
	for n in [steer, wheel_f, wheel_r, crank, pedal_l, pedal_r]:
		if n:
			_base[n] = (n as Node3D).transform
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 90.0
	area = Util.pick_area("bike", Vector3(0.6, 0.75, 0.95), Vector3(0, 0.38, 0))
	add_child(area)
	add_child(Util.blob_shadow(0.4, 0.3))
	return true


func _grip_init() -> void:
	if steer == null or _grip[0] != Vector3.ZERO:
		return
	var inv := steer.global_transform.affine_inverse()
	_grip[0] = inv * (model.global_transform * Vector3(0.31, 1.16, 0.17))
	_grip[1] = inv * (model.global_transform * Vector3(-0.31, 1.16, 0.17))


func grip_global(left: bool) -> Vector3:
	if steer == null:
		return to_global(Vector3(0.14 if left else -0.14, 0.52, 0.08))
	_grip_init()
	return steer.global_transform * (_grip[0] if left else _grip[1])


func pedal_global(left: bool) -> Vector3:
	var p: Node3D = pedal_l if left else pedal_r
	if p == null:
		return to_global(Vector3(0.07 if left else -0.07, 0.12, 0.0))
	return p.global_transform * Vector3(0.07 if left else -0.07, 0, 0)


func set_tilt(a: float) -> void:
	## Нахиляє велосипед уліво (до Ніки), коли вона на нього сідає чи злазить.
	if model:
		model.rotation.z = -a


func ride_anim(v: float, steer_to: float, dt: float) -> void:
	## v — швидкість (м/с), steer_to — куди повернуто кермо (рад).
	_grip_init()
	_wheel_a = wrapf(_wheel_a + v / R_WHEEL * dt, 0.0, TAU * 2.0)
	_steer = lerpf(_steer, steer_to, 1.0 - exp(-dt * 6.0))
	for w in [wheel_f, wheel_r]:
		if w:
			var b: Transform3D = _base[w]
			(w as Node3D).transform = Transform3D(b.basis * Basis(Vector3.RIGHT, _wheel_a), b.origin)
	var ca := _wheel_a * 0.5
	if crank:
		var b2: Transform3D = _base[crank]
		crank.transform = Transform3D(b2.basis * Basis(Vector3.RIGHT, ca), b2.origin)
	for p in [pedal_l, pedal_r]:
		if p:
			var b3: Transform3D = _base[p]
			(p as Node3D).transform = Transform3D(b3.basis * Basis(Vector3.RIGHT, -ca), b3.origin)
	if steer:
		var b4: Transform3D = _base[steer]
		steer.transform = Transform3D(b4.basis * Basis(Vector3.UP, _steer), b4.origin)
