extends "res://scripts/farmhand.gd"
## Конюх Семен: випускає коня зранку, ввечері заганяє у стайню. Вдень запрягає коня й везе
## віз на базар, чекає там і везе назад.

const STABLE_DOOR := Vector3(-187.0, 0, 39.7)          # перша стайня на фермі за ставком (двері на схід)
const CART_WAY: Array = [Vector3(-160.0, 0, 56.0), Vector3(-60.0, 0, 55.0), Vector3(-40.0, 0, 51.0), Vector3(-41.0, 0, 25.0),
	Vector3(0.0, 0, 30.0), Vector3(1.0, 0, 36.0), Vector3(-6.0, 0, 45.0)]
const MARKET_STOP := Vector3(-8.0, 0, 50.0)

var riding: Node3D = null
var _trip_day := -1


func setup_groom(home: Vector3, route: Array) -> void:
	setup("groom", 1.78, {"idle": ["idle_13"], "walk": ["walking"], "run": ["running"], "talk": ["talk_with_hands"],
			"wave": ["big_wave"], "proud": ["proud_strut"], "pick": ["collect_object"], "drink": ["stand_and_drink"]},
		["idle", "walk", "run", "pick"],
		["Я — Семен, конюх. Мій гнідий — найкращий у селі!", "Коня треба чистити щодня й говорити з ним лагідно.",
		 "Хочеш, повезу на базар возом?", "Овес, вода й добре слово — ось уся наука.", "Тпру-у! Стій, красеню!"],
		[], "npc")
	setup_pose()
	bounds = Rect2(-200.0, -62.0, 270.0, 160.0)      # до ферми за ставком
	extra_obs = Obstacles.outer
	if main.horse:
		main.horse.keeper_only = true
	start_life(home, route, 6.8, 19.5)


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
	var h = main.horse
	await _goto(STABLE_DOOR + Vector3(1.6, 0, 0))
	face(STABLE_DOOR + Vector3(-3, 0, 0))
	if h and h.mode == "inside":
		say("Доброго ранку, коню! Іди пастися!", 2.5)
		await act("wave", 2.5)
		h.send_out()
	else:
		say("Доброго ранку!", 2.0)


func work_step() -> void:
	var id := begin_job("stable")
	var h = main.horse
	var c = main.horse_cart
	var day := int(Game.state["day"])
	var hr := Game.hour()
	var free_cart: bool = c != null and h != null and not c.hitched and h.mode == "free" and main._ctl_veh == null and main.grandpa.doing != "cart"
	if free_cart and _trip_day != day and hr > 9.5 and hr < 16.0:
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


# ------------------------------------------------------------------ віз на базар
func trip(id: int) -> void:
	var cart = main.horse_cart
	var horse = main.horse
	say("Запряжу коня — поїду на базар!", 3.0)
	await _goto(cart.to_global(Vector3(1.9, 0, 0.0)), 1.5)
	if id != job:
		return
	say("Но-о, мій коню, ходи сюди!", 2.0)
	await cart.bring_horse(horse)
	await _mount(cart)
	say("Но-о, рушаймо!", 2.0)
	cart.start_manual()
	for wp in CART_WAY:
		await cart._horse_to(wp, 2.6, 2.0)
	await cart._horse_to(MARKET_STOP, 2.0, 1.5)
	cart.speed = 0.0
	await _dismount(cart)
	say("Тут постоїмо, а я куплю на базарі гостинців.", 3.0)
	await wait(2.0)
	await _goto(MARKET_STOP + Vector3(3.0, 0, 3.5), 1.5)
	await act("talk", 3.0)
	await wait(randf_range(15.0, 25.0))
	await _goto(cart.to_global(Vector3(1.4, 0, 0.3)), 1.5)
	await _mount(cart)
	say("Додому, коню!", 2.0)
	for i in range(CART_WAY.size() - 1, -1, -1):
		await cart._horse_to(CART_WAY[i], 2.6, 2.0)
	await cart.drive_back()
	await _dismount(cart)
	cart.unhitch()
	say("Дякую, красеню! Відпочивай.", 2.5)


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
	var h = main.horse
	if h == null:
		return
	# дочекатися, поки віз повернеться (якщо дідусь чи гравець кермує)
	var t := 0.0
	while h.mode == "hitched" and t < 120.0:
		t += 1.0
		await wait(1.0)
	if h.mode == "inside":
		return
	await _goto(STABLE_DOOR + Vector3(3.5, 0, 0), 1.5)
	say("Ходи в стайню, мій гнідий!", 2.5)
	h.kept_in = true
	h.send_home()
	t = 0.0
	while h.mode != "inside" and t < 45.0:
		t += 1.0
		await wait(1.0)
	say("Добраніч, коню!", 2.0)


func debug_trip() -> void:
	position = STABLE_DOOR + Vector3(3.0, 0, 2.0)
	on_duty = true
	_show(true)
	var id := begin_job("stable")
	await trip(id)
	end_job(id)
