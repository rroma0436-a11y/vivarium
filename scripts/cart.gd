extends Node3D
## Віз, який тягне кінь. Стоїть біля стайні. Коли кінь запряжений, віз їде за ним (оглобля до коня).
## На возі сидить дідусь (grandpa.gd: on_tractor = цей вузол), а гравець кермує конем джойстиком.
## Модель (tripo) має оглобельний кінець у бік −Z; SHAFT_YAW повертає модель оглоблею до +Z вузла.
## Якщо віз стоїть оглоблями від коня — змініть SHAFT_YAW на 0.0.

const LENGTH := 3.05                     # довжина воза разом з оглоблями
const BEHIND := 1.9                      # від центру коня до центру воза
const SEAT := Vector3(0, 0.78, 0.35)     # де сидить водій (стегна), у системі воза
const SHAFT_YAW := PI

var model: Node3D
var area: Area3D
var horse: Node3D
var hitched := false
var speed := 0.0
var park_pos := Vector3.ZERO
var park_yaw := PI
var _heading := 0.0
var _bob := 0.0
var front: Node3D                        # передок: оглоблі, передня вісь і передні колеса — повертається на шворні
var _pz := 0.0                           # де шворінь (передня вісь), z у системі воза
var _rz := 0.0                           # задня вісь, z у системі воза
const MAX_STEER := 1.1                   # найбільший кут передка відносно воза
var harness_parts: Array = []            # упряж (хомут із дугою) лежить на возі, поки кінь не запряжений
const HARNESS_AT := Vector3(0, 0.86, -0.35)


func setup(at: Vector3, yaw: float) -> void:
	park_pos = at
	park_yaw = yaw
	position = at
	rotation.y = yaw
	model = Models.spawn(self, "cart", LENGTH, "z")
	if model == null:
		return
	model.rotation.y = SHAFT_YAW
	_cut_wheels()
	_cut_front()
	_add_harness()
	area = Util.pick_area("cart", Vector3(1.8, 1.4, 3.2), Vector3(0, 0.7, 0))
	add_child(area)


# колеса (у координатах моделі: центр [y, z], радіус); вісь — уздовж x моделі
const WHEELS := [[Vector2(-0.083, -0.054), 0.112], [Vector2(-0.033, 0.312), 0.152]]
var wheels: Array = []                   # [петля, радіус у метрах]
var _last_pos := Vector3.INF
var _roll := 0.0
var _last_f := Vector3.INF
var _roll_f := 0.0


func _cut_wheels() -> void:
	## Вирізаємо чотири колеса з моделі, щоб вони крутилися, коли віз їде.
	var mis := model.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return
	var mi: MeshInstance3D = mis[0]
	var k := (global_transform.affine_inverse() * mi.global_transform).basis.get_scale().x
	for w in WHEELS:
		var c: Vector2 = w[0]
		var r: float = w[1]
		for sx in [1.0, -1.0]:
			var x0 := 0.112 if sx > 0.0 else -0.195
			var box := AABB(Vector3(x0, c.x - r, c.y - r), Vector3(0.083, r * 2.0, r * 2.0))
			var part := Models.cut(model, box, 100.0, mi, r, 0, 0.116)
			if part:
				wheels.append([Models.hinge(part, mi.to_global(Vector3(sx * 0.15, c.x, c.y))), r * k * 0.97, c.y < 0.1])


func _cut_front() -> void:
	## Передок (оглоблі + передня вісь + передні колеса) — окремо, щоб на поворотах він заходив у радіус повороту.
	var mis := model.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return
	var mi: MeshInstance3D = mis[0]
	front = Node3D.new()
	add_child(front)
	front.position = to_local(mi.to_global(Vector3(0, -0.083, -0.054)))
	_pz = front.position.z
	_rz = to_local(mi.to_global(Vector3(0, -0.033, 0.312))).z
	for box in [AABB(Vector3(-0.2, -0.2, -0.178), Vector3(0.4, 0.188, 0.178)), AABB(Vector3(-0.2, -0.06, -0.52), Vector3(0.4, 0.09, 0.342))]:
		var part := Models.cut(model, box, 100.0, mi)
		if part:
			part.reparent(front, true)
	for w in wheels:
		if w[2]:
			(w[0] as Node3D).reparent(front, true)


func _harness_copy(at: Vector3) -> Array:
	## Хомут із дугою з harness.glb (центр хомута — у точці at, дугою вгору, отвором уперед).
	var out: Array = []
	if not Models.exists("harness"):
		return out
	var src: Node3D = load(Models.DIR % "harness").instantiate()
	var B := Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3.ONE * 0.92)
	var T := Transform3D(B, at - B * Vector3(0, 0.70, -1.35))
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).begins_with("Collar"):
			continue
		var part := MeshInstance3D.new()
		part.mesh = (mi as MeshInstance3D).mesh
		part.transform = T * Models._rel(mi, src)
		out.append(part)
	src.free()
	return out


func _add_harness() -> void:
	for p in _harness_copy(HARNESS_AT):
		add_child(p)
		harness_parts.append(p)


func _bundle() -> Node3D:
	var b := Node3D.new()
	for p in _harness_copy(Vector3(0, -0.45, 0)):
		b.add_child(p)
	return b


func take_harness() -> Node3D:
	## Конюх бере упряж із воза (повертає те, що він несе в руках).
	for p in harness_parts:
		(p as Node3D).visible = false
	return _bundle()


func harness_on() -> void:
	## Упряж — на коня.
	if horse and is_instance_valid(horse):
		horse.show_harness(true)


func harness_now() -> void:
	for p in harness_parts:
		(p as Node3D).visible = false
	harness_on()


func harness_off() -> Node3D:
	## Знімає упряж із коня (повертає те, що несе в руках).
	if horse and is_instance_valid(horse):
		horse.show_harness(false)
	return _bundle()


func harness_to_cart() -> void:
	for p in harness_parts:
		(p as Node3D).visible = true


func _spin_wheels() -> void:
	if _last_pos == Vector3.INF:
		_last_pos = global_position
	var mv := global_position - _last_pos
	_last_pos = global_position
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	_roll += mv.dot(fwd)
	if front:
		# передні колеса котяться туди, куди дивиться передок
		if _last_f == Vector3.INF:
			_last_f = front.global_position
		var ff := front.global_transform.basis.z
		ff.y = 0.0
		_roll_f += (front.global_position - _last_f).dot(ff.normalized())
		_last_f = front.global_position
	else:
		_roll_f = _roll
	for w in wheels:
		(w[0] as Node3D).basis = Basis(Vector3.RIGHT, (_roll_f if w[2] else _roll) / float(w[1]))


func seat_global() -> Vector3:
	return to_global(SEAT)


func plow_hitch() -> Vector3:
	## Гак позаду воза — сюди чіпляють плуг (plow.gd).
	return to_global(Vector3(0, 0, -LENGTH * 0.5 - 0.05))


func plow_field(f: Rect2, alive: Callable) -> void:
	## Оранка конем: ряди вздовж z; плуг позаду воза сам заглиблюється в полі, на краях — розворот.
	var step := 1.8
	var x := f.position.x + 1.0
	var x1 := f.end.x - 0.8
	var zs := f.end.y + 3.2                  # кінь виходить за край, поки плуг дооре ряд
	var zn := f.position.y - 3.2
	var north := true
	await _horse_to(Vector3(x, 0, zs), 1.6, 0.8, false)
	while horse and alive.call():
		await _horse_to(Vector3(x, 0, zn if north else zs), 1.5, 0.5, false)
		if x + step > x1 or not alive.call():
			break
		await _horse_to(Vector3(x + step * 0.5, 0, (zn - 2.0) if north else (zs + 2.0)), 1.1, 0.6, false)
		x += step
		north = not north
	speed = 0.0


func hitch_pos() -> Vector3:
	## Де стоїть кінь, коли віз запаркований.
	return park_pos + Vector3(sin(park_yaw), 0, cos(park_yaw)) * BEHIND


func _process(delta: float) -> void:
	if model == null:
		return
	if hitched and horse and is_instance_valid(horse):
		_follow(delta)
		if absf(speed) < 0.05:
			horse.hitch_move(horse.rotation.y, 0.0, 0.0)      # стоїть — то просто стоїть
	_spin_wheels()
	# легке підскакування на ходу
	_bob += delta * 7.0 * clampf(absf(speed), 0.0, 3.0)
	model.position.y = absf(sin(_bob)) * 0.012 * clampf(absf(speed) / 2.0, 0.0, 1.0)


func _follow(_dt: float) -> void:
	## Віз тягнеться за конем, як справжній причіп: оглобля завжди дивиться на коня, а центр воза
	## йде слідом на відстані BEHIND (на поворотах віз плавно «заходить» за конем, а не крутиться на місці).
	## Передок з оглоблями й передніми колесами повертається на шворні за конем, а сам віз (задня вісь)
	## котиться слідом за шворнем — передні колеса заходять у радіус повороту.
	var hp: Vector3 = horse.global_position
	var d := hp - to_global(Vector3(0, 0, _pz))
	d.y = 0.0
	if d.length() < 0.01:
		return
	var df := d.normalized()
	var f := hp - df * (BEHIND - _pz)
	var e := f - to_global(Vector3(0, 0, _rz))
	e.y = 0.0
	var db := e.normalized() if e.length() > 0.01 else df
	var yf := atan2(df.x, df.z)
	var yb := atan2(db.x, db.z)
	var rel := wrapf(yf - yb, -PI, PI)
	if absf(rel) > MAX_STEER:
		yb = yf - signf(rel) * MAX_STEER
		db = Vector3(sin(yb), 0, cos(yb))
	var p := f - db * _pz
	p.y = Util.hill_y(p)
	global_position = p
	rotation.y = yb
	if front:
		front.rotation.y = wrapf(yf - yb, -PI, PI)


func bring_horse(h: Node3D) -> void:
	## Кінь іде до воза (обходить його збоку) і стає в оглобли.
	horse = h
	h.hitch_begin()
	var hp := hitch_pos()
	var side := Vector3(cos(park_yaw), 0, -sin(park_yaw)) * 3.0      # збоку від воза (із заходу), щоб не пройти крізь нього
	var way: Array = [park_pos + side + Vector3(sin(park_yaw), 0, cos(park_yaw)) * -3.0,
		park_pos + side + Vector3(sin(park_yaw), 0, cos(park_yaw)) * 2.2, hp]
	for wp in way:
		await _horse_to(wp, 1.5, 0.35, false)
	_heading = park_yaw
	h.hitch_move(park_yaw, 0.0, 0.0)
	hitched = true


func _horse_to(p: Vector3, v: float, reach: float, steer_around := true) -> void:
	## Кінь (із возом, якщо запряжений) іде до точки; обходить перешкоди.
	var t := 0.0
	var h: Node3D = horse
	while t < 70.0 and is_instance_valid(h):
		var dt := get_process_delta_time()
		t += dt
		var hp: Vector3 = h.global_position
		var tgt := Vehicles.steer_target(hp, p, 1.4) if steer_around else p
		var to := tgt - hp
		to.y = 0.0
		var d := to.length()
		if (p - hp).length() < reach:
			break
		var hd := lerp_angle(h.rotation.y, atan2(to.x, to.z), 1.0 - exp(-dt * 2.2))
		var sp := minf(v, maxf(0.5, d * 1.2))
		speed = move_toward(speed, sp, dt * 1.5)
		h.hitch_move(hd, speed, dt)
		await get_tree().process_frame
	speed = 0.0


func start_manual() -> void:
	_heading = horse.rotation.y if horse else 0.0
	speed = 0.0
	_turn_v = 0.0


var _turn_v := 0.0                       # кутова швидкість (згладжена — поворот плавний)


func manual_step(j: Vector2, dt: float) -> void:
	## Щокадру: j.y — вперед (газу назад кінь із возом не має), j.x — поворот.
	## Їхати можна куди завгодно: в обхід хат, через річку — лише містком.
	if horse == null:
		return
	var vmax := 3.4
	var want := maxf(j.y, 0.0) * vmax
	speed = move_toward(speed, want, dt * (1.2 if want > speed else 2.2))
	# поворот: кут змінюється з розгоном і гальмуванням, а не одразу
	var tv := -j.x * 1.1 * (0.35 + 0.65 * clampf(speed / 1.5, 0.0, 1.0))
	_turn_v = move_toward(_turn_v, tv, dt * 2.2)
	_heading += _turn_v * dt
	horse.hitch_move(_heading, speed, dt)
	# обходимо хати, дерева, стайню, річку: виштовхуємо точку посередині між конем і возом
	var hp: Vector3 = horse.global_position
	var back := Vector3(sin(_heading), 0, cos(_heading)) * 0.9
	var mid := hp - back
	var mid2 := Vehicles.keep_out(mid, 1.3, global_position)
	mid2.y = mid.y
	if mid2.distance_to(mid) > 0.001:
		horse.global_position += mid2 - mid
		speed = move_toward(speed, 0.0, dt * 4.0)
	if Util.on_hill(horse.global_position):
		horse.global_position.y = Util.hill_y(horse.global_position)


func drive_back(custom: Array = []) -> void:
	## Гравець віддав віжки: кінь сам везе віз додому до стайні (custom — свій шлях до місця стоянки).
	speed = 0.0
	var hp := hitch_pos()
	var south := Vector3(sin(park_yaw + PI), 0, cos(park_yaw + PI))      # звідки заїжджаємо (позаду воза)
	var way: Array = custom if not custom.is_empty() else Vehicles.route(horse.global_position, hp + south * 9.0)
	for wp in way:
		await _horse_to(wp, 2.4, 1.2)
	await _horse_to(hp, 1.4, 0.4, false)
	horse.hitch_move(park_yaw, 0.0, 0.0)
	await get_tree().process_frame
	# точно ставимо на місце
	var t := 0.0
	while t < 0.8:
		t += get_process_delta_time()
		horse.global_position = horse.global_position.lerp(hp, 0.15)
		horse.rotation.y = lerp_angle(horse.rotation.y, park_yaw, 0.15)
		await get_tree().process_frame
	speed = 0.0


func unhitch() -> void:
	## Кінь відпряжений — до стайні чи на вигін; віз стоїть на своєму місці.
	hitched = false
	speed = 0.0
	position = park_pos
	rotation.y = park_yaw
	if front:
		front.rotation.y = 0.0
	harness_to_cart()
	if horse and is_instance_valid(horse):
		horse.hitch_release()
	horse = null

