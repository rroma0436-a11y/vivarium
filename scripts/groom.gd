extends "res://scripts/farmhand.gd"
## Конюх Семен: живе в хаті села. Зранку приходить на ферму й випускає коней пастися, одного запрягає
## у віз і їде до копиці біля пшеничного поля по сіно; привозить сіно на ферму. Увечері заганяє коней у стайні.

const STABLE_DOOR := Vector3(-187.0, 0, 39.7)          # перша стайня на фермі за ставком (двері на схід)
const STABLE_DOORS := [Vector3(-187.0, 0, 39.7), Vector3(-187.0, 0, 55.7), Vector3(-187.0, 0, 71.7)]
const HAY_WAY: Array = [Vector3(-152.0, 0, 47.0), Vector3(-152.0, 0, 32.0), Vector3(-171.5, 0, 32.0), Vector3(-171.5, 0, 20.0),
	Vector3(-160.0, 0, 10.0), Vector3(-120.0, 0, 9.5), Vector3(-45.0, 0, 9.5), Vector3(-25.5, 0, 9.0), Vector3(-24.5, 0, -30.0),
	Vector3(-24.5, 0, -50.0)]
const HAY_IN := Vector3(-21.9, 0, -57.0)              # звертає з дороги до копиці
const HAY_STOP := Vector3(-21.9, 0, -68.9)            # кінь став так, що віз — боком упритул до копиці (HAY_N)
const HAY_OUT := Vector3(-26.0, 0, -62.0)             # розвертається від копиці назад на дорогу
const MOUNT_X := 1.0                                   # де стає збоку воза, щоб вилізти на передок
var _stand_h := 0.95                                   # висота стегон, коли стоїть

var riding: Node3D = null
var _trip_day := -1
var hay_load: Node3D                 # сіно на возі (росте, коли накладає)


func setup_groom(home: Vector3, route: Array) -> void:
	setup("groom", 1.78, {"idle": ["idle_13"], "walk": ["walking"], "run": ["running"], "talk": ["talk_with_hands"],
			"wave": ["big_wave"], "proud": ["proud_strut"], "pick": ["collect_object"], "drink": ["stand_and_drink"]},
		["idle", "walk", "run", "pick"],
		["Я — Семен, конюх. Мій гнідий — найкращий у селі!", "Коня треба чистити щодня й говорити з ним лагідно.",
		 "Зранку випускаю коней пастися, а сам — возом по сіно до копиці.", "Овес, вода й добре слово — ось уся наука.", "Тпру-у! Стій, красеню!"],
		[], "npc")
	Models.give_nika_anims(ap, anims)
	setup_pose()
	for h in horses():
		h.keeper_only = true
	start_farm(home, route, 6.8, 19.5)


func horses() -> Array:
	var list: Array = []
	if main.horse:
		list.append(main.horse)
	list.append_array(main.extra_horses)
	return list


func _process(delta: float) -> void:
	if riding:
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		place_hips(riding.seat_global())
		rotation.y = riding.rotation.y
		return
	super(delta)


func on_arrived() -> void:
	await horses_out()


func horses_out() -> void:
	## Обходить стайні й випускає коней пастися на леваду.
	var first := true
	for d in STABLE_DOORS:
		var inside: Array = []
		for h in horses():
			if h.mode == "inside" and (h.door as Vector3).distance_to(d) < 2.0:
				inside.append(h)
		if inside.is_empty():
			continue
		await _goto(d + Vector3(1.6, 0, 0))
		face(d + Vector3(-3, 0, 0))
		say("Доброго ранку, коні! Ідіть пастися!" if first else "Виходь, красеню, на траву!", 2.5)
		first = false
		await act("wave", 2.0)
		for h in inside:
			h.send_out()
			await wait(0.8)


func horses_in() -> void:
	## Заганяє всіх коней у стайні (запряженого — коли віз повернеться).
	var t := 0.0
	while main.horse and main.horse.mode == "hitched" and riding == null and t < 120.0:
		t += 1.0
		await wait(1.0)
	await _goto(STABLE_DOOR + Vector3(3.5, 0, 6.0), 1.5)
	say("Ходіть у стайні, мої коні!", 2.5)
	await act("wave", 2.0)
	for h in horses():
		if h.mode == "free" or h.mode == "to_pasture":
			h.kept_in = true
			h.send_home()
	t = 0.0
	while t < 45.0:
		var all_in := true
		for h in horses():
			if h.mode == "free" or h.mode == "to_pasture" or h.mode == "to_shed":
				all_in = false
		if all_in:
			break
		t += 1.0
		await wait(1.0)


func can_go_hay() -> bool:
	var h = main.horse
	var c = main.horse_cart
	return c != null and h != null and not c.hitched and (h.mode == "free" or h.mode == "to_pasture" or h.mode == "inside") \
		and main._ctl_veh == null and main.grandpa.doing != "cart"


func work_step() -> void:
	var id := begin_job("stable")
	var h = main.horse
	var day := int(Game.state["day"])
	var hr := Game.hour()
	if can_go_hay() and _trip_day != day and hr > 8.5 and hr < 16.0:
		_trip_day = day
		await trip(id)
	else:
		var p := Vector3(randf_range(-181.0, -169.0), 0, randf_range(37.0, 70.0))
		await _goto(p, 1.5)
		if id == job:
			if randf() < 0.5:
				face(h.global_position if h else p)
				say(lines[randi() % lines.size()], 2.5)
				await act("talk", 3.0)
			else:
				await act("proud", minf(anim_length("proud"), 4.0))
	end_job(id)


func command(what: String) -> void:
	## Із меню конюха.
	if not on_duty:
		say("Зараз прийду на ферму!", 2.0)
		return
	if riding:
		say("Я на возі — от приїдемо, тоді!", 2.5)
		return
	match what:
		"out":
			cancel_job()
			var id := begin_job("stable")
			await horses_out()
			end_job(id)
		"in":
			cancel_job()
			var id := begin_job("stable")
			await horses_in()
			if id == job:
				say("Усі коні в стайнях!", 2.0)
			end_job(id)
		"hay":
			if not can_go_hay():
				say("Віз зайнятий — поїду пізніше.", 2.5)
				return
			cancel_job()
			var id := begin_job("stable")
			_trip_day = int(Game.state["day"])
			await trip(id)
			end_job(id)


# ------------------------------------------------------------------ віз по сіно до копиці біля пшеничного поля
func _hay_bundle() -> MeshInstance3D:
	return Util.sphere(0.28, Util.mat(Color(0.86, 0.74, 0.38), 0.95), Vector3.ZERO, Vector3(1.4, 0.8, 1.1))


func _make_load(cart: Node3D) -> void:
	if hay_load and is_instance_valid(hay_load):
		return
	hay_load = Node3D.new()
	hay_load.position = Vector3(0, 0.75, -0.75)
	hay_load.add_child(Util.sphere(0.5, Util.mat(Color(0.86, 0.74, 0.38), 0.95), Vector3(0, 0.2, 0), Vector3(1.4, 0.7, 1.6)))
	cart.add_child(hay_load)
	hay_load.visible = false


func trip(id: int) -> void:
	var cart = main.horse_cart
	var horse = main.horse
	_make_load(cart)
	if horse.mode == "inside":
		horse.send_out()
	say("Запряжу коня — поїду по сіно!", 3.0)
	await _goto(cart.to_global(Vector3(1.9, 0, 0.0)), 1.5)
	if id != job:
		return
	say("Но-о, мій коню, ходи сюди!", 2.0)
	await cart.bring_horse(horse)
	await _harness(cart)
	await _mount(cart)
	say("Но-о, рушаймо до копиці!", 2.0)
	cart.start_manual()
	for wp in HAY_WAY:
		await cart._horse_to(wp, 2.6, 2.0)
	await cart._horse_to(HAY_IN, 2.0, 1.0, false)
	await cart._horse_to(HAY_STOP, 1.4, 0.3, false)
	cart.speed = 0.0
	var hs: Vector3 = main.world.outer.HAY_N
	var side := -1.0 if cart.to_local(hs).x < 0.0 else 1.0
	await _dismount(cart, side)
	say("Наберу сінця з копиці.", 2.5)
	hay_load.visible = true
	for i in 3:
		hay_load.scale = Vector3.ONE * (0.4 + i * 0.3)
		var at: Vector3 = hs + (cart.global_position - hs).normalized() * 1.85
		at.y = 0.0
		await _goto(at, 0.5)
		face(hs)
		await act("pick", minf(anim_length("pick"), 2.5))
		var b := _hay_bundle()
		hold(b, Vector3(0, 0.2, 0.0))
		face(cart.global_position)
		await wait(0.5)
		await act("pick", minf(anim_length("pick"), 1.6))
		var l := drop()
		if l:
			l.queue_free()
		hay_load.scale = Vector3.ONE * (0.4 + (i + 1) * 0.2)
	hay_load.scale = Vector3.ONE
	say("Повний віз! Додому, коню!", 2.5)
	await _mount(cart, side)
	await cart._horse_to(HAY_OUT, 2.0, 1.5)
	for i in range(HAY_WAY.size() - 1, -1, -1):
		await cart._horse_to(HAY_WAY[i], 2.6, 2.0)
	await cart.drive_back()
	await _dismount(cart)
	# розвантажує сіно в копицю на фермі
	var fh: Node3D = main.farm_hay
	for i in 2:
		await _goto(cart.to_global(Vector3(1.4, 0, -0.6)), 1.2)
		face(cart.global_position)
		await act("pick", minf(anim_length("pick"), 2.0))
		hay_load.scale = Vector3.ONE * (0.6 - i * 0.3)
		hold(_hay_bundle(), Vector3(0, 0.2, 0.0))
		if fh:
			await _goto(fh.global_position + (cart.global_position - fh.global_position).normalized() * 1.8, 1.0)
			face(fh.global_position)
		var l2 := drop()
		if l2:
			l2.queue_free()
		if fh:
			main.add_farm_hay(0.25)
	hay_load.visible = false
	say("Сіно на фермі — Тарасик нагодує худобу.", 3.0)
	await _unharness(cart)
	cart.unhitch()
	say("Дякую, красеню! Відпочивай.", 2.5)


func _harness(cart: Node3D) -> void:
	## Бере упряж із воза й одягає коневі.
	await _goto(cart.to_global(Vector3(1.05, 0, -0.35)), 0.4)
	face(cart.to_global(Vector3(0, 0, -0.35)))
	await act("pick", minf(anim_length("pick"), 2.0))
	hold_upright(cart.take_harness(), 0.05, false, 0.3)
	say("Ось хомут — зараз одягнемо, красеню!", 2.0)
	await _goto(cart.to_global(Vector3(0.95, 0, 2.6)), 0.4)
	face(cart.to_global(Vector3(0, 0, 2.6)))
	await wait(0.4)
	await act("talk", 2.2)
	var l := drop()
	if l:
		l.queue_free()
	cart.harness_on()
	await wait(0.4)


func _unharness(cart: Node3D) -> void:
	## Знімає упряж із коня й кладе на віз.
	await _goto(cart.to_global(Vector3(0.95, 0, 2.6)), 0.4)
	face(cart.to_global(Vector3(0, 0, 2.6)))
	await wait(0.4)
	await act("talk", 2.0)
	hold_upright(cart.harness_off(), 0.05, false, 0.3)
	await _goto(cart.to_global(Vector3(1.05, 0, -0.35)), 0.4)
	face(cart.to_global(Vector3(0, 0, -0.35)))
	await act("pick", minf(anim_length("pick"), 2.0))
	var l := drop()
	if l:
		l.queue_free()
	cart.harness_to_cart()


func _climb(cart: Node3D, pts: Array, yaws: Array, sits: Array, durs: Array, moves: Array) -> void:
	## Перелазить (на віз чи з воза): стегна йдуть через точки pts (у системі воза), поворот і посадка — поступово.
	for i in durs.size():
		var d: float = durs[i]
		var t := 0.0
		play(String(moves[i]), 0.55)
		while t < d:
			t = minf(d, t + get_process_delta_time())
			var k := smoothstep(0.0, 1.0, t / d)
			var p: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], k)
			p.y += sin(k * PI) * 0.1
			if pose:
				pose.sit = lerpf(float(sits[i]), float(sits[i + 1]), k)
			rotation.y = cart.rotation.y + lerp_angle(float(yaws[i]), float(yaws[i + 1]), k)
			place_hips(cart.to_global(p))
			await get_tree().process_frame


func _mount(cart: Node3D, side := 1.0) -> void:
	## Підходить збоку до передка, стає ногою на маточину колеса, перелазить через борт і сідає.
	await _goto(cart.to_global(Vector3(side * MOUNT_X, 0, 0.4)), 0.35)
	stop()
	_face_to = NAN
	busy = true
	if pose:
		pose.sit = 0.0
	_stand_h = maxf(0.5, hips_world().y - global_position.y)
	var seat: Vector3 = cart.to_local(cart.seat_global())
	var inside := -side * PI / 2.0
	var pts := [cart.to_local(hips_world()), Vector3(side * 0.74, _stand_h + 0.36, 0.42),
		Vector3(side * 0.3, 0.6 + _stand_h * 0.9, 0.38), seat]
	var rel0 := wrapf(rotation.y - cart.rotation.y, -PI, PI)
	await _climb(cart, pts, [rel0, inside, inside * 0.5, 0.0], [0.0, 0.0, 0.15, 1.0], [0.6, 0.6, 0.7], ["walk", "walk", "idle"])
	if pose:
		pose.sit = 1.0
	busy = false
	riding = cart


func _dismount(cart: Node3D, side := 1.0) -> void:
	## Встає з передка, перелазить через борт, стає на маточину колеса й злазить на землю.
	riding = null
	stop()
	_face_to = NAN
	busy = true
	var seat: Vector3 = cart.to_local(cart.seat_global())
	var out := side * PI / 2.0
	var pts := [seat, Vector3(side * 0.3, 0.6 + _stand_h * 0.9, 0.38), Vector3(side * 0.74, _stand_h + 0.36, 0.42),
		Vector3(side * MOUNT_X, _stand_h, 0.4)]
	await _climb(cart, pts, [0.0, out, out, out], [1.0, 0.15, 0.0, 0.0], [0.7, 0.6, 0.6], ["idle", "walk", "walk"])
	var g: Vector3 = cart.to_global(Vector3(side * MOUNT_X, 0, 0.4))
	g.y = Util.hill_y(g) if Util.on_hill(g) else 0.0
	global_position = g
	if pose:
		pose.sit = 0.0
	model.position.y = _base_y
	busy = false
	play("idle")


func _obs() -> Array:
	## Крім звичайних перешкод — віз і кінь (щоб не проходив крізь них).
	var list: Array = Obstacles.items + extra_obs
	var c = main.horse_cart if main else null
	if c and is_instance_valid(c):
		for z in [-1.05, -0.35, 0.35, 1.05]:
			var p: Vector3 = c.to_global(Vector3(0, 0, z))
			list.append([Vector2(p.x, p.z), 0.62 if z < 1.0 else 0.45, 1.2])
	var h = main.horse if main else null
	if h and is_instance_valid(h) and h.visible:
		var f := Vector3(sin(h.rotation.y), 0, cos(h.rotation.y))
		for k in [-0.65, 0.0, 0.65]:
			var p2: Vector3 = h.global_position + f * k
			list.append([Vector2(p2.x, p2.z), 0.42, 1.5])
	return list


func before_leave() -> void:
	await horses_in()
	say("Добраніч, коні!", 2.0)


func debug_trip() -> void:
	position = STABLE_DOOR + Vector3(3.0, 0, 2.0)
	on_duty = true
	_show(true)
	var id := begin_job("stable")
	await trip(id)
	end_job(id)
