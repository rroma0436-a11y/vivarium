extends Node3D
## Комбайн (Комбайн.blend → combine.glb), на ньому їздить Ніка. Вперед — вісь +z (жатка спереду),
## кабіна над передніми колесами, двері кабіни й драбинка — з правого боку (вісь −x).
## Передні колеса ведучі, задні — керовані (повертають у протилежний бік), мотовило крутиться.
## Де Ніка злізла — там комбайн і стоїть.

const R_FRONT := 0.81
const R_REAR := 0.51
# точки для Ніки (у системі комбайна) — заміряно з Комбайн.blend: драбинка ліворуч перед переднім колесом
# (поперечини через 0.3 м, від 0.37 до 2.17 м), над нею — площадка вздовж кабіни (2.5 м), двері кабіни — з неї.
const CLIMB_FROM := Vector3(-2.3, 0.0, -0.6)        # де стати на землі перед драбинкою
const LADDER_Z := -0.6                              # середина драбинки (поручні — z −0.8 і −0.4)
const RUNG_Y0 := 0.37
const RUNG_DY := 0.3
const RUNGS := 7
const DECK_Y := 2.5                                 # площадка
const DECK_X := -1.28
const DOOR_Z := 1.12                                # навпроти дверей кабіни
const SILL := Vector3(-0.95, 2.6, 1.3)              # поріг кабіни
const SEAT_HIPS := Vector3(0.0, 3.02, 1.05)         # стегна Ніки на сидінні
const FEET := [Vector3(0.13, 2.66, 1.55), Vector3(-0.13, 2.66, 1.55)]
const WHEEL_C := Vector3(0.0, 3.3, 1.62)            # кермо

var model: Node3D
var body: StaticBody3D
var area: Area3D
var reel: Node3D
var door: Node3D
var wheels_f: Array = []
var wheels_r: Array = []
var pivots_r: Array = []
var _base := {}
var _spin_f := 0.0
var _spin_r := 0.0
var _steer := 0.0
var _door_k := 0.0
var _door_want := 0.0
var _door_spd := 1.6
var _handle := Vector3.INF                          # ручка дверей (у системі дверей)
var speed := 0.0
var reel_on := true
var auger: Node3D                                   # вивантажувальний шнек (складений уздовж лівого боку, кінцем назад)
var _auger_k := 0.0
var _auger_want := 0.0
var _stream: CPUParticles3D
const SPOUT := Vector3(-5.6, 3.35, -1.2)            # кінець розвернутого шнека (у системі комбайна)


func setup() -> bool:
	if not ResourceLoader.exists("res://assets/models/combine.glb"):
		return false
	model = load("res://assets/models/combine.glb").instantiate()
	add_child(model)
	reel = model.find_child("Мотовило", true, false)
	door = model.find_child("Двері", true, false)
	for nm in ["Колесо_ПЛ", "Колесо_ПП"]:
		var w := model.find_child(nm, true, false)
		if w:
			wheels_f.append(w)
	for nm in ["Колесо_ЗЛ", "Колесо_ЗП"]:
		var w := model.find_child(nm, true, false)
		if w:
			wheels_r.append(w)
	for nm in ["Поворот_ЗЛ", "Поворот_ЗП"]:
		var w := model.find_child(nm, true, false)
		if w:
			pivots_r.append(w)
	auger = model.find_child("Шнек", true, false)
	for n in wheels_f + wheels_r + pivots_r + [door, reel, auger]:
		if n:
			_base[n] = (n as Node3D).transform
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 170.0
	# тверде тіло — Ніка не проходить крізь комбайн (шар стін базару, 1 << 17)
	body = StaticBody3D.new()
	body.collision_layer = 1 << 17
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.2, 3.2, 8.6)
	cs.shape = bx
	cs.position = Vector3(0, 1.6, -0.9)
	body.add_child(cs)
	var cs2 := CollisionShape3D.new()                 # жатка спереду — ширша за корпус
	var bx2 := BoxShape3D.new()
	bx2.size = Vector3(4.3, 1.4, 3.4)
	cs2.shape = bx2
	cs2.position = Vector3(0, 0.75, 2.55)
	body.add_child(cs2)
	add_child(body)
	area = Util.pick_area("combine", Vector3(4.4, 4.4, 9.6), Vector3(0, 2.2, -0.6))
	add_child(area)
	add_child(Util.blob_shadow(3.2, 0.3))
	_stream = Util.grain_stream()
	_stream.position = SPOUT
	add_child(_stream)
	return true


func auger_out(on: bool) -> void:
	## Шнек розвертається вбік (до причепа) або складається назад.
	_auger_want = 1.0 if on else 0.0


func auger_ready() -> bool:
	return auger == null or _auger_k > 0.98


func pour(on: bool) -> void:
	## Зерно сиплеться зі шнека.
	if _stream:
		_stream.emitting = on


func solid(on: bool) -> void:
	## Поки Ніка в кабіні, комбайн сам себе не штовхає.
	if body:
		body.collision_layer = (1 << 17) if on else 0


func grip_global(left: bool) -> Vector3:
	## Кисті на ободі керма (кермо крутиться разом із колесами).
	var a := -_steer * 2.2
	var off := Vector3(0.17 if left else -0.17, 0.0, 0.0).rotated(Vector3(0, 0.6, -0.8).normalized(), a)
	return to_global(WHEEL_C + off)


static func rail_x(y: float) -> float:
	## Драбинка трохи похила: внизу x = −1.72, нагорі −1.49.
	return -1.72 + 0.23 * (clampf(y, 0.35, 2.45) - 0.35) / 2.1


func cab_points() -> Dictionary:
	var steps: Array = []
	for i in RUNGS:
		var y := RUNG_Y0 + RUNG_DY * i
		steps.append(Vector3(rail_x(y) - 0.05, y + 0.03, LADDER_Z))
	return {"climb": CLIMB_FROM, "steps": steps, "sill": SILL, "seat": SEAT_HIPS, "feet": FEET, "side": -1.0,
		"ladder": true, "deck_y": DECK_Y, "deck_x": DECK_X, "door_z": DOOR_Z, "ladder_z": LADDER_Z}


func open_door(on: bool, spd := 1.6) -> void:
	_door_want = 1.0 if on else 0.0
	_door_spd = spd


func door_k() -> float:
	return _door_k


func door_handle_global() -> Vector3:
	## Ручка дверей кабіни — на краю стулки, далі від завіс (рухається разом із дверима).
	if door == null:
		return to_global(SILL + Vector3(-0.1, 0.5, -0.4))
	if _handle == Vector3.INF:
		var ab := AABB()
		var first := true
		var ms: Array = []
		ms.append_array(door.find_children("*", "MeshInstance3D", true, false))
		if door is MeshInstance3D:
			ms.append(door)
		for mi in ms:
			var m := mi as MeshInstance3D
			var t := door.global_transform.affine_inverse() * m.global_transform
			for i in 8:
				var q := t * m.get_aabb().get_endpoint(i)
				ab = AABB(q, Vector3.ZERO) if first else ab.expand(q)
				first = false
		if first:
			ab = AABB(Vector3(-0.03, -0.55, -1.06), Vector3(0.06, 1.1, 1.04))
		var c := ab.get_center()
		var far := Vector3(c.x, 0, c.z)
		var h := far.normalized() * (far.length() + 0.4 * maxf(absf(ab.size.z), absf(ab.size.x))) if far.length() > 0.01 else Vector3(0, 0, -0.9)
		_handle = Vector3(h.x, c.y - 0.05, h.z)
	return door.global_transform * _handle


func ride_anim(v: float, steer_to: float, dt: float) -> void:
	## v — швидкість (м/с), steer_to — куди повернуто (рад; задні колеса — навпаки).
	speed = v
	_spin_f = wrapf(_spin_f + v / R_FRONT * dt, 0.0, TAU)
	_spin_r = wrapf(_spin_r + v / R_REAR * dt, 0.0, TAU)
	_steer = lerpf(_steer, steer_to, 1.0 - exp(-dt * 4.0))
	for w in wheels_f:
		var b: Transform3D = _base[w]
		(w as Node3D).transform = Transform3D(b.basis * Basis(Vector3.RIGHT, _spin_f), b.origin)
	for w in wheels_r:
		var b2: Transform3D = _base[w]
		(w as Node3D).transform = Transform3D(Basis(Vector3.UP, -_steer * 0.8) * b2.basis * Basis(Vector3.RIGHT, _spin_r), b2.origin)
	for p in pivots_r:
		var b3: Transform3D = _base[p]
		(p as Node3D).transform = Transform3D(Basis(Vector3.UP, -_steer * 0.8) * b3.basis, b3.origin)


func _process(delta: float) -> void:
	if auger and absf(_auger_k - _auger_want) > 0.001:
		_auger_k = move_toward(_auger_k, _auger_want, delta * 0.45)
		var ea := _auger_k * _auger_k * (3.0 - 2.0 * _auger_k)
		var ba: Transform3D = _base[auger]
		auger.transform = Transform3D(Basis(Vector3.UP, PI / 2.0 * ea) * ba.basis, ba.origin)
	if reel:
		# мотовило крутиться, коли комбайн їде (і поволі — коли стоїть із заведеним мотором)
		if reel_on:
			reel.rotate_object_local(Vector3.RIGHT, delta * (0.5 + absf(speed) * 0.6))
	if door and absf(_door_k - _door_want) > 0.001:
		_door_k = move_toward(_door_k, _door_want, delta * _door_spd)
		var e := _door_k * _door_k * (3.0 - 2.0 * _door_k)
		var bd: Transform3D = _base[door]
		door.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(80.0) * e) * bd.basis, bd.origin)
