extends "res://scripts/npc.gd"
## Працівник ферми: зранку з'являється (виходить із своєї хати в селі), іде на ферму, робить свої справи,
## ввечері, коли все зроблено, іде додому й зникає до ранку.
## Похідні класи (groom, shepherd, granny) задають work_step() і before_leave().

const WIDE := Rect2(-70.0, -62.0, 140.0, 160.0)
var home_spot := Vector3.ZERO          # де «заходить у хату» (перед будинком)
var way: Array = []                    # від хати до ферми
var arrive_h := 6.8
var leave_h := 19.3
var on_duty := false
var _pause_work := 2.0
var _wide := Rect2()                   # межі ходіння по світу (до ферми)
var road_i := 0                        # у way: точка на дорозі біля воріт подвір'я (звідти — на подвір'я)
const FARM_BOUNDS := Rect2(-200.0, -75.0, 270.0, 173.0)


func start_farm(home: Vector3, route: Array, from_h: float, to_h: float, at_road := 4) -> void:
	## Живе в хаті села, на ферму ходить пішки.
	bounds = FARM_BOUNDS
	extra_obs = Obstacles.outer
	road_i = at_road
	start_life(home, route, from_h, to_h)


func start_life(home: Vector3, route: Array, from_h: float, to_h: float) -> void:
	_wide = bounds
	home_spot = home
	way = route
	arrive_h = from_h
	leave_h = to_h
	walk_speed = 1.15
	run_speed = 2.2
	if on_time():
		on_duty = true
		position = route[route.size() - 1] if not route.is_empty() else home
		_show(true)
	else:
		_show(false)
	_life()


func on_time() -> bool:
	var h := Game.hour()
	return h >= arrive_h and h < leave_h


func _show(on: bool) -> void:
	visible = on
	if area:
		area.input_ray_pickable = on


func _life() -> void:
	while is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		if process_mode == Node.PROCESS_MODE_DISABLED:
			continue                       # цим персонажем грає гравець
		if doing != "" or busy or moving:
			continue
		if on_time():
			if not on_duty:
				await _arrive()
			else:
				_pause_work -= 1.0
				if _pause_work <= 0.0:
					_pause_work = randf_range(2.0, 6.0)
					await work_step()
		elif on_duty:
			await _leave()


func _goto(p: Vector3, tol := 1.3) -> void:
	for i in 5:
		await go(p)
		if global_position.distance_to(p) < tol:
			return


func act(kind: String, secs: float) -> void:
	## Робить рух kind протягом secs секунд.
	busy = true
	play(kind)
	await wait(secs)
	busy = false


func _arrive() -> void:
	var id := begin_job("arrive")
	if bike:
		await _out_of_hut()
		await _mount_bike()
		await _ride(_ride_go())
		await _dismount_bike(bike_farm)
		for wp in farm_walk:
			await _goto(wp)
		on_duty = true
		await on_arrived()
		end_job(id)
		return
	await appear()
	for wp in way:
		await _goto(wp)
	on_duty = true
	await on_arrived()
	end_job(id)


func _leave() -> void:
	var id := begin_job("leave")
	await before_leave()
	if bike:
		if in_yard:
			await back_farm()
		for i in range(farm_walk.size() - 1, -1, -1):
			await _goto(farm_walk[i])
		on_duty = false                    # уже йде додому — справ на фермі не бере
		await _mount_bike()
		await _ride(_ride_back())
		await _dismount_bike(hut["bike"])
		await _into_hut()
		on_duty = false
		end_job(id)
		return
	var from := way.size() - 1
	if in_yard:
		var w = main.world
		await go(w.spots["inside_gate"], false, false)
		await w.pass_gate(self, true)
		bounds = _wide
		in_yard = false
		from = road_i
	for i in range(from, -1, -1):
		await _goto(way[i])
	await vanish()
	on_duty = false
	end_job(id)


var in_yard := false


func go_yard() -> void:
	## З ферми — дорогою до воріт подвір'я і крізь них (для справ на подвір'ї).
	if in_yard or way.is_empty():
		return
	var w = main.world
	var near := way.size() - 1
	var bd := INF
	for i in way.size():
		var d: float = global_position.distance_to(way[i])
		if d < bd:
			bd = d
			near = i
	if near >= road_i:
		for i in range(near, road_i - 1, -1):
			await _goto(way[i])
	else:
		for i in range(near, road_i + 1):
			await _goto(way[i])
	await go(w.spots["outside_gate"], false, false)
	await w.pass_gate(self, false)
	in_yard = true


func back_farm() -> void:
	## З подвір'я — назад на ферму.
	if not in_yard:
		return
	var w = main.world
	await go(w.spots["inside_gate"], false, false)
	await w.pass_gate(self, true)
	bounds = _wide
	in_yard = false
	for i in range(road_i, way.size()):
		await _goto(way[i])


# ----- те, що змінюють нащадки
func appear() -> void:
	position = home_spot
	_show(true)


func vanish() -> void:
	await _goto(home_spot, 1.6)
	_show(false)


func on_arrived() -> void:
	pass


func before_leave() -> void:
	pass


func work_step() -> void:
	pass


# ----- велосипед: зранку з хати (крізь двері й хвіртку) — велосипедом на ферму, увечері — назад
var bike: Node3D = null
var hut := {}                          # хата: точки від дверей до вулиці, двері, хвіртка, де стоїть велосипед
var ride_way: Array = []               # велосипедом: від під'їзду до хати — до ферми (дорогою понад річкою)
var bike_farm := Transform3D()         # де велосипед стоїть на фермі
var farm_walk: Array = []              # від велосипеда на фермі — пішки до роботи
var _on_bike := false
var _near_hut := false
var _ride_pts: Array = []
var _ride_i := 0
var _ride_v := 0.0
var _ride_t := 0.0
var _ride_end := false
var _hip_h := 0.9


func give_bike(b: Node3D, info: Dictionary, route: Array, park: Transform3D, walk: Array) -> void:
	bike = b
	hut = info
	ride_way = route
	bike_farm = park
	farm_walk = walk
	bike.global_transform = park if on_duty else (info["bike"] as Transform3D)
	if not on_duty and Game.hour() >= 12.0:
		_hut_light(true)


func _hut_light(on: bool) -> void:
	var bz = main.world.outer.bazaar if main and main.world and main.world.outer else null
	if bz and hut.has("door") and hut["door"]:
		bz.house_light(hut["door"], on)


func _process(delta: float) -> void:
	if _on_bike and bike:
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		_ride_step(delta)
		return
	super(delta)
	if _near_hut and visible and main:
		var bz = main.world.outer.bazaar
		if bz:
			global_position.y = bz.floor_y(global_position, global_position.y)


func _entry() -> Array:
	## З вулиці біля хвіртки — на під'їзд до головної дороги.
	if hut.has("entry"):
		return (hut["entry"] as Array).duplicate()          # хата нового села: далі — ride_way
	var st: Vector3 = hut["street"]
	if absf(st.x) > 6.5:
		return [st, Vector3(signf(st.x) * 6.0, 0, st.z)]
	return [st]


func _ride_go() -> Array:
	return _entry() + ride_way + [bike_farm.origin]


func _ride_back() -> Array:
	var back := ride_way.duplicate()
	back.reverse()
	var en := _entry()
	en.reverse()
	return back + en + [(hut["bike"] as Transform3D).origin]


func _hand_to(at: Vector3) -> void:
	## Повертається до дверей (хвіртки) і тягне рукою — відчиняє чи зачиняє.
	face(at)
	await wait(0.4)
	busy = true
	if anims.get("open_door", "") != "":
		current = ""
		play("open_door", 1.25)
		await wait(clampf(anim_length("open_door") / 1.25, 0.6, 1.3))
	elif pose:
		var t := 0.0
		while t < 0.7:
			t += get_process_delta_time()
			pose.carry = sin(clampf(t / 0.7, 0.0, 1.0) * PI)
			await get_tree().process_frame
		pose.carry = 0.0
	busy = false
	play("idle")


func _through(n: Node, at: Vector3, beyond: Vector3) -> void:
	## Відчиняє двері (хвіртку), проходить крізь них і зачиняє за собою.
	var bz = main.world.outer.bazaar if main else null
	await _hand_to(at)
	if bz:
		bz.npc_door(n, true, global_position)
	await wait(0.6)
	await go(beyond, false, false)
	await _hand_to(at)
	if bz:
		bz.npc_door(n, false)
	await wait(0.3)


func _out_of_hut() -> void:
	## Зранку виходить із хати крізь двері, двором до хвіртки, відчиняє її, виходить і зачиняє.
	position = hut["inside"]
	_hut_light(false)
	var to: Vector3 = (hut["door_out"] as Vector3) - (hut["inside"] as Vector3)
	rotation.y = atan2(to.x, to.z)
	_near_hut = true
	_show(true)
	await _through(hut["door"], hut["door_at"], hut["door_out"])
	await go(hut["gate_in"], false, false)
	await _through(hut["gate"], hut["gate_at"], hut["gate_out"])
	_near_hut = false
	global_position.y = 0.0


func _into_hut() -> void:
	## Увечері: крізь хвіртку у двір (відчиняє й зачиняє), крізь двері в хату — і там до ранку.
	_near_hut = true
	await go(hut["gate_out"], false, false)
	await _through(hut["gate"], hut["gate_at"], hut["gate_in"])
	await go(hut["door_out"], false, false)
	await _through(hut["door"], hut["door_at"], hut["inside"])
	_hut_light(true)                       # зайшов у хату — світиться у вікнах
	_show(false)
	_near_hut = false


func _bike_ik(w: float) -> Dictionary:
	var bb := bike.global_transform.basis.orthonormalized()
	return {"LeftHand": [bike.grip_global(true) + bb * Vector3(0, 0.02, -0.035), w],
		"RightHand": [bike.grip_global(false) + bb * Vector3(0, 0.02, -0.035), w],
		"LeftFoot": [bike.pedal_global(true) + bb * Vector3(0, 0.06, -0.03), w],
		"RightFoot": [bike.pedal_global(false) + bb * Vector3(0, 0.06, -0.03), w]}


func _mount_bike() -> void:
	## Підходить до велосипеда зліва, бере кермо й сідає на сідло.
	var b := bike
	var left: Vector3 = b.global_transform.basis.x.normalized()
	await go(b.global_position + left * 0.55, false, false)
	face(b.global_position + b.global_transform.basis.z * 3.0)
	await wait(0.5)
	stop()
	busy = true
	_hip_h = maxf(0.4, hips_world().y - global_position.y)
	var h0 := hips_world()
	var y0 := rotation.y
	var t := 0.0
	while t < 1.0:
		t = minf(1.0, t + get_process_delta_time() / 0.9)
		var e := t * t * (3.0 - 2.0 * t)
		rotation.y = lerp_angle(y0, b.rotation.y, e)
		if pose:
			pose.life = 0.0
			pose.lean = 0.5 * e
			pose.ik = _bike_ik(e)
		place_hips(h0.lerp(b.to_global(b.seat_local()), e) + Vector3(0, sin(t * PI) * 0.12, 0))
		await get_tree().process_frame
	busy = false
	_on_bike = true


func _dismount_bike(park: Transform3D) -> void:
	## Зупиняється, злазить ліворуч і ставить велосипед на місце.
	_on_bike = false
	busy = true
	var b := bike
	var left: Vector3 = b.global_transform.basis.x.normalized()
	var g := b.global_position + left * 0.55
	g.y = 0.0
	var h0 := hips_world()
	var t := 0.0
	while t < 1.0:
		t = minf(1.0, t + get_process_delta_time() / 0.8)
		var e := t * t * (3.0 - 2.0 * t)
		if pose:
			pose.lean = 0.5 * (1.0 - e)
			pose.ik = _bike_ik(1.0 - e)
		place_hips(h0.lerp(g + Vector3(0, _hip_h, 0), e) + Vector3(0, sin(t * PI) * 0.1, 0))
		await get_tree().process_frame
	global_position = g
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	# ставить велосипед рівно на його місце
	var t0 := b.global_transform
	t = 0.0
	while t < 1.0:
		t = minf(1.0, t + get_process_delta_time() / 0.6)
		b.global_transform = t0.interpolate_with(park, t * t * (3.0 - 2.0 * t))
		await get_tree().process_frame
	busy = false
	play("idle")


func _ride(pts: Array) -> void:
	_ride_pts = pts
	_ride_i = 0
	_ride_v = 0.0
	_ride_t = 0.0
	_ride_end = false
	while not _ride_end and is_inside_tree():
		await get_tree().process_frame


func _ride_step(delta: float) -> void:
	var b := bike
	if _ride_i < _ride_pts.size():
		var tg: Vector3 = _ride_pts[_ride_i]
		var to := tg - b.global_position
		to.y = 0.0
		var d := to.length()
		var last := _ride_i == _ride_pts.size() - 1
		if last:
			_ride_t += delta
		if d < (0.35 if last else 1.6) or (last and _ride_t > 8.0):
			_ride_i += 1
		var want := atan2(to.x, to.z) if d > 0.05 else b.rotation.y
		var diff := angle_difference(b.rotation.y, want)
		b.rotation.y = lerp_angle(b.rotation.y, want, 1.0 - exp(-delta * 2.6))
		var vmax := clampf(d * 0.9, 0.5, 4.0) if last else 4.0
		vmax *= clampf(1.0 - absf(diff) / 1.6, 0.3, 1.0)
		_ride_v = move_toward(_ride_v, vmax, delta * 1.6)
		b.global_position += Vector3(sin(b.rotation.y), 0, cos(b.rotation.y)) * _ride_v * delta
		b.ride_anim(_ride_v, clampf(diff * 0.8, -0.5, 0.5), delta)
	else:
		_ride_v = 0.0
		b.ride_anim(0.0, 0.0, delta)
		_ride_end = true
	rotation.y = b.rotation.y
	if pose:
		pose.life = 0.0
		pose.lean = 0.5
		pose.ik = _bike_ik(1.0)
	place_hips(b.to_global(b.seat_local()))
