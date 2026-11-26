extends "res://scripts/farmhand.gd"
## Конюх Семен: живе в хаті села. Зранку приходить на ферму й випускає коней пастися, одного запрягає
## у віз і їде до копиці біля пшеничного поля по сіно; привозить сіно на ферму. Увечері заганяє коней у стайні.

const STABLE_DOOR := Vector3(-187.0, 0, 39.7)          # перша стайня на фермі за ставком (двері на схід)
const STABLE_DOORS := [Vector3(-187.0, 0, 39.7), Vector3(-187.0, 0, 55.7), Vector3(-187.0, 0, 71.7)]
const HAY_WAY: Array = [Vector3(-152.0, 0, 47.0), Vector3(-152.0, 0, 32.0), Vector3(-171.5, 0, 32.0), Vector3(-171.5, 0, 20.0),
	Vector3(-160.0, 0, 10.0), Vector3(-120.0, 0, 9.5), Vector3(-45.0, 0, 9.5), Vector3(-25.5, 0, 9.0), Vector3(-24.5, 0, -30.0),
	Vector3(-24.5, 0, -50.0)]
const HAY_STOP := Vector3(-27.0, 0, -61.5)             # на дорозі біля копиці (пшеничне поле)

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
	await _mount(cart)
	say("Но-о, рушаймо до копиці!", 2.0)
	cart.start_manual()
	for wp in HAY_WAY:
		await cart._horse_to(wp, 2.6, 2.0)
	await cart._horse_to(HAY_STOP, 2.0, 1.5)
	cart.speed = 0.0
	await _dismount(cart)
	say("Наберу сінця з копиці.", 2.5)
	var hs: Vector3 = main.world.outer.HAY_N
	hay_load.visible = true
	for i in 3:
		hay_load.scale = Vector3.ONE * (0.4 + i * 0.3)
		await _goto(hs + (cart.global_position - hs).normalized() * 1.9, 1.0)
		face(hs)
		await act("pick", minf(anim_length("pick"), 2.5))
		var b := _hay_bundle()
		hold(b, Vector3(0, 0.2, 0.0))
		await _goto(cart.to_global(Vector3(1.4, 0, -0.6)), 1.2)
		face(cart.global_position)
		var l := drop()
		if l:
			l.queue_free()
		hay_load.scale = Vector3.ONE * (0.4 + (i + 1) * 0.2)
	hay_load.scale = Vector3.ONE
	say("Повний віз! Додому, коню!", 2.5)
	await _goto(cart.to_global(Vector3(1.4, 0, 0.3)), 1.5)
	await _mount(cart)
	for i in range(HAY_WAY.size() - 1, -1, -1):
		await cart._horse_to(HAY_WAY[i], 2.6, 2.0)
	await cart.drive_back()
	await _dismount(cart)
	cart.unhitch()
	say("Дякую, красеню! Відпочивай.", 2.5)
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


func _mount(cart: Node3D) -> void:
	stop()
	var t := 0.0
	while t < 0.8:
		t += get_process_delta_time()
		pose.sit = clampf(t / 0.8, 0.0, 1.0)
		global_position += (cart.seat_global() - hips_world()) * clampf(t / 0.8 + 0.1, 0.0, 1.0) * 0.5
		rotation.y = lerp_angle(rotation.y, cart.rotation.y, 0.2)
		await get_tree().process_frame
	pose.sit = 1.0
	riding = cart


func _dismount(cart: Node3D) -> void:
	riding = null
	var to: Vector3 = cart.to_global(Vector3(1.4, 0, 0.3))
	to.y = 0.0
	var from := global_position
	var t := 0.0
	while t < 0.8:
		t += get_process_delta_time()
		var k := clampf(t / 0.8, 0.0, 1.0)
		pose.sit = 1.0 - k
		var p := from.lerp(to, k)
		p.y = lerpf(from.y, 0.0, k) + sin(k * PI) * 0.2
		global_position = p
		await get_tree().process_frame
	pose.sit = 0.0
	global_position = to


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
