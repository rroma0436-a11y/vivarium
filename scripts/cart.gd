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
	area = Util.pick_area("cart", Vector3(1.8, 1.4, 3.2), Vector3(0, 0.7, 0))
	add_child(area)


# колеса (у координатах моделі: центр [y, z], радіус); вісь — уздовж x моделі
const WHEELS := [[Vector2(-0.083, -0.054), 0.112], [Vector2(-0.033, 0.312), 0.152]]
var wheels: Array = []                   # [петля, радіус у метрах]
var _last_pos := Vector3.INF
var _roll := 0.0


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
				wheels.append([Models.hinge(part, mi.to_global(Vector3(sx * 0.15, c.x, c.y))), r * k * 0.97])


func _spin_wheels() -> void:
	if _last_pos == Vector3.INF:
		_last_pos = global_position
	var mv := global_position - _last_pos
	_last_pos = global_position
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	_roll += mv.dot(fwd)
	for w in wheels:
		(w[0] as Node3D).basis = Basis(Vector3.RIGHT, _roll / float(w[1]))


func seat_global() -> Vector3:
	return to_global(SEAT)


func hitch_pos() -> Vector3:
	## Де стоїть кінь, коли віз запаркований.
	return park_pos + Vector3(sin(park_yaw), 0, cos(park_yaw)) * BEHIND


func _process(delta: float) -> void:
	if model == null:
		return
	if hitched and horse and is_instance_valid(horse):
		_follow(delta)
	_spin_wheels()
	# легке підскакування на ходу
	_bob += delta * 7.0 * clampf(absf(speed), 0.0, 3.0)
	model.position.y = absf(sin(_bob)) * 0.012 * clampf(absf(speed) / 2.0, 0.0, 1.0)


func _follow(_dt: float) -> void:
	## Віз тягнеться за конем, як справжній причіп: оглобля завжди дивиться на коня, а центр воза
	## йде слідом на відстані BEHIND (на поворотах віз плавно «заходить» за конем, а не крутиться на місці).
	var hp: Vector3 = horse.global_position
	var d := hp - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	var dir := d.normalized()
	var p := hp - dir * BEHIND
	p.y = Util.hill_y(p)
	global_position = p
	rotation.y = atan2(dir.x, dir.z)


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


func drive_back() -> void:
	## Гравець віддав віжки: кінь сам везе віз додому до стайні.
	speed = 0.0
	var hp := hitch_pos()
	var south := Vector3(sin(park_yaw + PI), 0, cos(park_yaw + PI))      # звідки заїжджаємо (позаду воза)
	var way: Array = Vehicles.route(horse.global_position, hp + south * 9.0)
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
	if horse and is_instance_valid(horse):
		horse.hitch_release()
	horse = null

