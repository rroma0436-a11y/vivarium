extends Walker
## Дідусь Петро (модель з Meshy, рухи Mixamo: стоїть, іде, біжить, махає, розмовляє,
## сідає/встає, п'є сидячи й стоячи, лягає).
## Порається на подвір'ї: сидить на лавці біля криниці, за столом п'є з глечика, п'є воду біля криниці,
## заходить у хату й сідає в крісло. Увечері сидить у кріслі, вночі спить на дивані.

const HEIGHT := 1.72
# де стегна (кістка Hips) уздовж «вперед» у різних рухах (сантиметри моделі) — щоб перехід
# з одного руху в інший не «стрибав»
const HIPS_IDLE := 5.0
const HIPS_SITANIM_STAND := -24.5     # кінець руху «встає»
const HIPS_SITANIM_SIT := -66.0       # початок руху «встає» (ще сидить)
const HIPS_SIT := 4.6                 # «сидить і п'є»

var busy := false
var idle_left := 4.0
var spots := {}
var world
var talking := false
var at_home := false
var seated := ""                      # на чому сидить ("" — стоїть)
var lying := false
var _act_left := 0.0
var _act_then: Callable
var _k := 0.01                        # метрів на одиницю скелета
var _seat_dy := 0.0

# де можна сісти: [точка (стегна над сидінням), куди дивиться (рад), у хаті?, глечик, підняти/опустити]
var seats := {}


func _ready() -> void:
	var ok := setup_model("grandpa", HEIGHT, {
		"idle": ["idle"], "walk": ["walk"], "run": ["run"], "wave": ["wave", "talk_with_left_hand_raised"], "talk": ["talk"],
		"sitdrink": ["sit_and_drink"], "stand_up": ["sit_to_stand_transition_m", "sit_to_stand"],
		"drink": ["stand_and_drink"], "lie": ["lie_down"], "jump_down": ["jumping_down"],
	}, ["idle", "walk", "run", "talk", "lie"])
	if not ok:
		add_child(Util.capsule(0.25, 1.5, Util.mat(Color(0.95, 0.95, 0.92)), Vector3(0, 0.85, 0)))
		add_child(Util.sphere(0.17, Util.mat(Color(0.95, 0.78, 0.65)), Vector3(0, 1.62, 0)))
	else:
		Models.give_nika_anims(ap, anims)
		setup_pose()
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if sks.size() > 0:
			_k = (sks[0] as Skeleton3D).global_transform.basis.get_scale().x
	walk_speed = 1.0
	run_speed = 2.6
	setup_common("grandpa", Vector3(0.7, 1.8, 0.6), 2.15, 0.45)
	play("idle")


func setup_seats() -> void:
	var R: Vector3 = world.ROOM
	seats = {
		"bench": [Vector3(4.35, 0, -6.35), 0.0, false, null, -0.04],
		"table": [Vector3(5.0, 0, 1.12), 0.0, false, _jug("jug"), 0.07],
		"rocking": [Vector3(2.3, 0, -6.15), deg_to_rad(10.0), false, null, 0.0],
		"armchair": [R + Vector3(-2.79, 0, -0.2), deg_to_rad(90.0), true, _jug("room_jug"), 0.16],
	}
	_make_blanket()


func _jug(key: String) -> Node3D:
	var arr: Array = world.props.get(key, [])
	if arr.is_empty():
		return null
	var j: Node3D = arr[0]
	Walker.remember_home(j)
	return j


func _process(delta: float) -> void:
	if on_tractor or _climbing:
		if on_tractor and not _climbing:
			_ride_step()
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		return
	_physics_step(delta)
	if _act_left > 0.0:
		_act_left -= delta
		if _act_left <= 0.0:
			busy = false
			var cb := _act_then
			_act_then = Callable()
			if cb.is_valid():
				cb.call()
	_update_book(delta)
	if seated != "" or lying:
		if doing == "" and not talking:
			idle_left -= delta
			if idle_left <= 0.0:
				idle_left = randf_range(3.0, 7.0)
				_daily_routine()
		return
	if moving:
		play("run" if running else "walk")
		return
	if talking:
		play("talk")
		return
	if busy or doing != "":
		return
	play("idle")
	idle_left -= delta
	if idle_left > 0.0:
		return
	idle_left = randf_range(3.0, 7.0)
	_daily_routine()


func sitting() -> bool:
	return seated != ""


# ------------------------------------------------------------------ розпорядок дня
func _daily_routine() -> void:
	var h := Game.hour()
	var bedtime := h >= 21.0 or h < 6.0 or bed_now
	if seated != "":
		if bedtime and seated == "armchair":
			sleep_job()
		elif not Game.is_night() or seated != "armchair":
			var id := begin_job("stand")
			await stand_up()
			end_job(id)
		return
	if bedtime or Game.is_night():
		if not at_home:
			go_home_and_sit()
		elif bedtime:
			sleep_job()
		else:
			sit_job("armchair", 30.0)
		return
	if at_home:
		if randf() < 0.3:
			sit_job("armchair", randf_range(15.0, 30.0))
		else:
			go_out()
		return
	if _wants_eggs():
		eggs_job()
		return
	var r := randf()
	if r < 0.16:
		inspect_job()
	elif r < 0.3:
		sit_job("bench", randf_range(15.0, 28.0))
	elif r < 0.42:
		sit_job("table", randf_range(15.0, 25.0))
	elif r < 0.5:
		sit_job("rocking", randf_range(12.0, 20.0))
	elif r < 0.58:
		go_home_and_sit()
	elif r < 0.68:
		well_drink_job()
	elif r < 0.76 and Game.hour() > 12.0 and Game.hour() < 17.0:
		nap_job()
	else:
		var choices := ["well", "garden", "porch", "coop", "gate"]
		walk_to(spots[choices[randi() % choices.size()]] + Vector3(randf_range(-0.6, 0.6), 0, 0.9))


func _enter_house() -> void:
	## Через двері — у кімнату (кімната стоїть окремо, тож переносимося до дверей зсередини).
	var R: Vector3 = world.ROOM
	at_home = true
	bounds = Rect2(R.x - 3.2, R.z - 2.4, 6.4, 5.6)
	position = spots["room_door"]
	rotation.y = PI
	_door_sound("door_close")


func _leave_house() -> void:
	at_home = false
	bounds = Rect2(-20.5, -14.5, 29.0, 19.0)
	position = spots["door"]
	rotation.y = 0.0
	_door_sound("door_open")


func _door_sound(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -8.0)


func _walk_in(id: int) -> bool:
	## Подвір'я → хата: двері відчиняються, заходить, двері зачиняються.
	var w = world
	await go(spots["door"])
	if id != job:
		return false
	_face_to = PI
	w.set_door("house", true)
	await wait(0.6)
	if id != job:
		w.set_door("house", false)
		return false
	await go(spots["door"] + Vector3(0.1, 0, -1.0), false, false)
	w.set_door("house", false, 0.4)
	_enter_house()
	position = spots["room_door"] + Vector3(0, 0, 0.9)
	w.set_door("room", true, 0.4)
	await wait(0.3)
	await go(spots["room_door"] + Vector3(0.3, 0, -0.5), false, false)
	w.set_door("room", false)
	return id == job


func _walk_out(id: int) -> bool:
	## Хата → подвір'я.
	var w = world
	await go(spots["room_door"] + Vector3(0, 0, -0.3))
	if id != job:
		return false
	_face_to = 0.0
	w.set_door("room", true)
	await wait(0.6)
	if id != job:
		w.set_door("room", false)
		return false
	await go(spots["room_door"] + Vector3(0, 0, 0.9), false, false)
	w.set_door("room", false, 0.4)
	_leave_house()
	position = spots["door"] + Vector3(0.1, 0, -1.0)
	rotation.y = 0.0
	w.set_door("house", true, 0.4)
	await wait(0.3)
	await go(spots["door"] + Vector3(0, 0, 0.4), false, false)
	w.set_door("house", false)
	return id == job


func go_home_and_sit() -> void:
	var id := begin_job("home")
	if not at_home:
		if not await _walk_in(id):
			return
	end_job(id)
	sit_job("armchair", 30.0 if Game.is_night() else randf_range(20.0, 40.0))


func go_out() -> void:
	var id := begin_job("out")
	if not await _walk_out(id):
		return
	await go(spots["porch"] + Vector3(randf_range(-0.8, 0.8), 0, 0.8))
	end_job(id)


func command_in() -> void:
	## Команда «Дідусю, ходи в хату».
	if at_home:
		say("Я вже в хаті!", 2.0)
		return
	say("Іду, іду!", 2.0)
	if seated != "":
		var id0 := begin_job("stand")
		await stand_up()
		end_job(id0)
	if lying:
		_wake_reset()
	go_home_and_sit()


func command_out() -> void:
	if not at_home:
		say("Я й так на подвір'ї!", 2.0)
		return
	say("Вже виходжу!", 2.0)
	if seated != "":
		var id0 := begin_job("stand")
		await stand_up()
		end_job(id0)
	if lying:
		_wake_reset()
	go_out()


# ------------------------------------------------------------------ обхід господарства
const INSPECT := [
	["coop", "Кури здорові, слава Богу.", "Курочки вже в курнику. Добре."],
	["well", "Вода в криниці чиста, холодна.", ""],
	["barn", "Сіна в сараї вистачить на всю зиму.", ""],
	["workshop", "Треба б граблі полагодити…", ""],
	["field_gate", "Ох, і гарні ж соняшники ростуть!", "Город просить води — хай дрон поллє."],
	["doghouse", "Будка ціла, Бімові тепло.", ""],
	["garden", "Гарбузики наливаються.", ""],
]


func inspect_job() -> void:
	## Дідусь обходить своє господарство: 3–4 місця, біля кожного зупиняється й щось каже.
	var id := begin_job("inspect")
	var list: Array = INSPECT.duplicate()
	list.shuffle()
	for i in mini(4, list.size()):
		var it: Array = list[i]
		var key: String = it[0]
		var p: Vector3
		match key:
			"field_gate":
				p = Vector3(8.0, 0, -4.5)
			"doghouse":
				p = spots["doghouse"] + Vector3(0.8, 0, 1.4)
			_:
				if not spots.has(key):
					continue
				p = spots[key]
		await go(p + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)))
		if id != job:
			return
		var txt: String = it[1]
		if key == "field_gate" and float(Game.state["field"]["water"]) < 30.0:
			txt = it[2]
		if key == "coop" and Game.is_night():
			txt = it[2]
		say(txt, 3.0)
		await wait(3.2)
		if id != job:
			return
	end_job(id)


# ------------------------------------------------------------------ яйця з ґанку — у хату
func _wants_eggs() -> bool:
	var g = world.get_node_or_null("/root/Main").get("gvintyk")
	return g != null and g.porch_basket != null and g.porch_basket.visible and g.doing == ""


func eggs_job() -> void:
	## Гвинтик приніс кошик яєць на ґанок — дідусь забирає й заносить у хату.
	var g = world.get_node("/root/Main").get("gvintyk")
	var b: Node3D = g.porch_basket
	var id := begin_job("eggs")
	say("О, Гвинтик яєць приніс!", 2.5)
	await go(b.global_position + Vector3(0.3, 0, 0.55))
	if id != job:
		return
	face(b.global_position)
	await wait(0.6)
	Walker.remember_home(b)
	hold_upright(b, 0.2, false, 0.08)
	if not await _walk_in(id):
		return
	await go(world.ROOM + Vector3(-2.6, 0, 1.5))
	if id != job:
		return
	# ставить кошик на скриню
	drop()
	world.room_root.add_child(b)
	b.position = Vector3(-3.0, 0.62, 2.0)
	b.rotation = Vector3.ZERO
	b.set_meta("home_parent", null)
	say("Будуть млинці!", 2.0)
	# порожній кошик для Гвинтика знову на ґанку (з'явиться завтра)
	g.porch_basket = g._basket(true)
	world.yard_root.add_child(g.porch_basket)
	g.porch_basket.position = spots["porch"] + Vector3(1.0, 0, -0.5)
	g.porch_basket.visible = false
	if is_instance_valid(_room_eggs):
		_room_eggs.queue_free()
	_room_eggs = b
	end_job(id)


var _room_eggs: Node3D


# ------------------------------------------------------------------ сісти / встати
func _fwd(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))


func sit_job(seat: String, secs := 25.0) -> void:
	## Підійти, сісти; за столом і в кріслі — попити з глечика; посидіти й устати.
	var s: Array = seats.get(seat, [])
	if s.is_empty() or (bool(s[2]) != at_home) or seated != "":
		return
	var id := begin_job("sit_" + seat)
	var seat_p: Vector3 = s[0]
	var yaw := float(s[1])
	# сідаючи, він відступає назад — тож стати треба трохи попереду сидіння
	var back := (HIPS_SIT + HIPS_SITANIM_STAND - HIPS_IDLE - HIPS_SITANIM_SIT) * _k
	var stand_p := seat_p + _fwd(yaw) * back
	# підходить збоку (щоб не йти крізь стіл чи лавку), останній крок — без обходу перешкод
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	if (position - stand_p).dot(side) < 0.0:
		side = -side
	await go(stand_p + side * 0.75 + _fwd(yaw) * 0.15)
	if id != job:
		return
	await go(stand_p, false, false)
	if id != job:
		return
	_face_to = yaw
	await wait(0.7)
	if id != job:
		return
	rotation.y = yaw
	await _sit_down(seat, seat_p, float(s[4]))
	if id != job:
		return
	var jug: Node3D = s[3]
	var left := secs
	while left > 0.0:
		var chunk := minf(left, randf_range(5.0, 9.0))
		await wait(chunk)
		left -= chunk
		if id != job or seated == "":
			return
		if jug and randf() < 0.6 and is_instance_valid(jug) and jug.get_parent() == jug.get_meta("home_parent", null):
			await _drink_seated(jug, id)
			if id != job:
				return
	if Game.is_night() and seat == "armchair":
		end_job(id)
		return              # увечері лишається в кріслі (встане, коли час спати)
	await stand_up()
	end_job(id)


func _sit_down(seat: String, seat_p: Vector3, dy: float) -> void:
	## Рух «встає», програний навпаки = сідає. Модель зсунута так, щоб початок руху збігся з тим, як він стоїть.
	seated = seat
	if ap == null or anims.get("stand_up", "") == "":
		position = seat_p
		return
	var n: String = anims["stand_up"]
	model.position.z = (HIPS_IDLE - HIPS_SITANIM_STAND) * _k
	current = "stand_up"
	ap.play_backwards(n, 0.2)
	ap.speed_scale = 1.35
	var len := ap.get_animation(n).length / 1.35
	var t := 0.0
	while t < len:
		t += get_process_delta_time()
		model.position.y = _base_y + dy * clampf(t / len, 0.0, 1.0)
		await get_tree().process_frame
	# тепер сидить: переходимо на «сидить і п'є» (перший кадр) без змішування
	position = seat_p
	model.position = Vector3(0, _base_y + dy, 0)
	_seat_dy = dy
	_sit_still()


func _sit_still() -> void:
	var n: String = anims.get("sitdrink", "")
	if n == "":
		return
	current = "sitdrink"
	ap.speed_scale = 1.0
	ap.play(n, 0.0)
	ap.seek(0.0, true)
	ap.pause()


func stand_up() -> void:
	if seated == "":
		return
	put_back_held()
	var yaw := rotation.y
	var n: String = anims.get("stand_up", "")
	if n == "":
		seated = ""
		play("idle")
		return
	model.position.z = (HIPS_SIT - HIPS_SITANIM_SIT) * _k
	current = "stand_up"
	ap.play(n, 0.0)
	ap.speed_scale = 1.35
	var len := ap.get_animation(n).length / 1.35
	var t := 0.0
	while t < len - 0.05:
		t += get_process_delta_time()
		model.position.y = _base_y + _seat_dy * (1.0 - clampf(t / len, 0.0, 1.0))
		await get_tree().process_frame
	position += _fwd(yaw) * (HIPS_SIT - HIPS_SITANIM_SIT + HIPS_SITANIM_STAND - HIPS_IDLE) * _k
	model.position = Vector3(0, _base_y, 0)
	_seat_dy = 0.0
	seated = ""
	current = ""
	ap.speed_scale = 1.0
	play("idle")
	# якщо встав «у» стіл чи лавку — відступає вбік
	var out := Obstacles.push_out(position, me_r)
	if out.distance_to(position) > 0.02:
		var dir := (out - position).normalized()
		await go(out + dir * 0.15, false, false)


func _drink_seated(jug: Node3D, id: int) -> void:
	## «Сидить і п'є»: глечик переходить у праву руку, поки він п'є, а потім — на своє місце.
	var n: String = anims.get("sitdrink", "")
	if n == "" or hand == null:
		return
	current = "sitdrink"
	ap.play(n, 0.0)
	ap.seek(0.0, true)
	ap.speed_scale = 1.0
	var len := ap.get_animation(n).length
	var took := false
	var t := 0.0
	while t < len:
		t += get_process_delta_time()
		if id != job:
			break
		if not took and t > 2.4:
			took = true
			hold_upright(jug, 0.2)
		if took and held and t > 8.6:
			put_back_held()
		await get_tree().process_frame
	put_back_held()
	if id == job and seated != "":
		say("Ох, і смачний узвар!", 2.5)
		_sit_still()


func well_drink_job() -> void:
	## Біля криниці: набирає кухоль води й п'є стоячи.
	var id := begin_job("well_drink")
	await go(spots["well_front"] + Vector3(-0.2, 0, 0.2))
	if id != job:
		return
	face(spots["well"])
	await wait(0.5)
	if id != job:
		return
	await world.well_draw()
	if id != job:
		return
	var n: String = anims.get("drink", "")
	if n == "":
		end_job(id)
		return
	current = "drink"
	ap.play(n, 0.3)
	var mug: Node3D = Models.spawn(world.yard_root, "cup", 0.11) if Models.exists("cup") else null      # червона глиняна чашка
	if mug:
		world.yard_root.remove_child(mug)
	else:
		mug = Util.cyl(0.045, 0.04, 0.1, Util.mat(Color(0.75, 0.45, 0.25), 0.6))
	var len := ap.get_animation(n).length
	var t := 0.0
	var took := false
	while t < len:
		t += get_process_delta_time()
		if id != job:
			break
		if not took and t > 1.2:
			took = true
			world.yard_root.add_child(mug)
			hold_upright(mug, 0.06, true)
		await get_tree().process_frame
	var m := drop()
	if m:
		m.queue_free()
	elif not took:
		mug.queue_free()
	if id == job:
		say("Ох, і смачна в нас вода!", 2.5)
	current = ""
	play("idle")
	end_job(id)


# ------------------------------------------------------------------ сон і відпочинок
var blanket: Node3D


func _make_blanket() -> void:
	## Ряднина під старою грушею — дідусь іноді лягає на ній подрімати.
	blanket = Node3D.new()
	blanket.position = Vector3(-6.4, 0, -7.3)
	blanket.rotation.y = deg_to_rad(-35.0)
	world.yard_root.add_child(blanket)
	var a := Util.mat(Color(0.75, 0.2, 0.18), 0.95)
	var b := Util.mat(Color(0.95, 0.88, 0.7), 0.95)
	for k in 6:
		var stripe := Util.box(Vector3(0.95, 0.012, 0.32), a if k % 2 == 0 else b, Vector3(0, 0.008, -0.8 + k * 0.32))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blanket.add_child(stripe)


var _plaid: Node3D


func cover(on: bool) -> void:
	## Плед на колінах (його вкриває Beep, коли дідусь дрімає в кріслі).
	if on and _plaid == null:
		_plaid = Node3D.new()
		add_child(_plaid)
		var red := Util.mat(Color(0.72, 0.18, 0.16), 0.95)
		var stripe := Util.mat(Color(0.95, 0.85, 0.55), 0.95)
		if lying:
			# лежить у ліжку — ковдра від грудей до ніг, краї звисають з боків
			var cy := _base_y + LIE_Y + 0.09
			_plaid.add_child(Util.box(Vector3(0.9, 0.05, 1.1), red, Vector3(0, cy, 0.3)))
			for k in [-0.05, 0.35, 0.75]:
				_plaid.add_child(Util.box(Vector3(0.91, 0.052, 0.06), stripe, Vector3(0, cy, k)))
			for sx in [-0.45, 0.45]:
				_plaid.add_child(Util.box(Vector3(0.04, 0.22, 1.1), red, Vector3(sx, cy - 0.1, 0.3)))
			_plaid.scale = Vector3(1.0, 0.1, 1.0)
			create_tween().tween_property(_plaid, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			return
		var p := Util.box(Vector3(0.62, 0.05, 0.62), red, Vector3(0, 0.66, 0.2))
		p.rotation.x = deg_to_rad(-12)
		_plaid.add_child(p)
		for k in [-0.18, 0.18]:
			var st := Util.box(Vector3(0.63, 0.052, 0.05), stripe, Vector3(0, 0.661, 0.2 + k))
			st.rotation.x = deg_to_rad(-12)
			_plaid.add_child(st)
		var hang := Util.box(Vector3(0.62, 0.42, 0.04), red, Vector3(0, 0.45, 0.5))
		_plaid.add_child(hang)
		_plaid.scale = Vector3(0.1, 0.1, 0.1)
		create_tween().tween_property(_plaid, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not on and _plaid:
		_plaid.queue_free()
		_plaid = null


var LIE_YAW := 0.0    # (налаштування пози на ліжку: головою до подушки)
var LIE_OFF := Vector3(0, 0, -0.2)
var LIE_Y := 0.87


var _lie_t := -1.0
var book: Node3D
var _book_k := 0.0
var _page: Node3D
var _page_t := 0.0
var bed_now := false               # «лягай спати» за командою — спить до ранку


func _make_book() -> void:
	## Книжка: червона палітурка, розгорнута, дві сторінки; сторінки час від часу перегортаються.
	book = Node3D.new()
	world.room_root.add_child(book)
	var cover := Util.mat(Color(0.62, 0.16, 0.14), 0.7)
	var paper := Util.mat(Color(0.97, 0.94, 0.85), 0.9)
	var lines := Util.mat(Color(0.55, 0.5, 0.45), 0.9)
	for sx in [-1.0, 1.0]:
		var half := Node3D.new()
		half.rotation.z = sx * deg_to_rad(-14.0)
		book.add_child(half)
		half.add_child(Util.box(Vector3(0.13, 0.008, 0.18), cover, Vector3(sx * 0.066, 0, 0)))
		half.add_child(Util.box(Vector3(0.12, 0.016, 0.17), paper, Vector3(sx * 0.062, 0.012, 0)))
		for k in 6:
			half.add_child(Util.box(Vector3(0.085, 0.002, 0.006), lines, Vector3(sx * 0.064, 0.021, -0.055 + k * 0.022)))
	_page = Node3D.new()
	book.add_child(_page)
	var pg := Util.box(Vector3(0.12, 0.003, 0.17), paper, Vector3(0.062, 0.022, 0))
	_page.add_child(pg)
	_page.visible = false
	book.visible = false


func _update_book(delta: float) -> void:
	## Сидячи в кріслі вдома (і не спить) — читає книжку: тримає її на колінах перед собою.
	var reading := seated == "armchair" and doing != "sleep" and not lying and hand != null and hand_l != null
	_book_k = move_toward(_book_k, 1.0 if reading else 0.0, delta * 1.5)
	if _book_k <= 0.001:
		if book:
			book.visible = false
		return
	if book == null:
		_make_book()
	book.visible = true
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var mid := (hand.global_position + hand_l.global_position) * 0.5 + f * 0.1 + Vector3(0, 0.13, 0)
	var x := Vector3(cos(rotation.y), 0, -sin(rotation.y))
	# сторінки нахилені до обличчя
	var tilt := Basis(x, deg_to_rad(-50.0))
	book.global_transform = Transform3D(tilt * Basis(Vector3.UP, rotation.y + PI), mid)
	book.scale = Vector3.ONE * (0.6 + 0.4 * _book_k)
	# перегортає сторінку
	_page_t -= delta
	if _page_t <= 0.0:
		_page_t = randf_range(6.0, 11.0)
		_page.visible = true
		_page.rotation.z = 0.0
		var tw := create_tween()
		tw.tween_property(_page, "rotation:z", PI, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func(): _page.visible = false)


func command_bed() -> void:
	## Beep попросив: «Дідусю, лягай спати».
	if lying:
		say("Я вже сплю… z-z-z", 2.0)
		return
	if not at_home:
		say("Іду вже, іду спати!", 2.0)
	bed_now = true
	cancel_job()
	if not at_home:
		var id := begin_job("in")
		if not await _walk_in(id):
			return
		end_job(id)
	sleep_job()


func _wake_reset() -> void:
	## Встає з ліжка (чи з ряднини) за будь-якої перерваної справи.
	lying = false
	bed_now = false
	ap.speed_scale = 1.0
	model.position.y = _base_y
	cover(false)
	current = ""
	play("idle")


func _lie_time() -> float:
	if _lie_t >= 0.0:
		return _lie_t
	var la: Animation = ap.get_animation(anims["lie"])
	_lie_t = la.length * 0.5
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return _lie_t
	var sk: Skeleton3D = sks[0]
	var hb: int = pose.find(sk, "Head") if pose else -1
	if hb < 0:
		return _lie_t
	var best := INF
	ap.play(anims["lie"], 0.0)
	for i in 40:
		var t := la.length * i / 40.0
		ap.seek(t, true)
		var y := sk.get_bone_global_pose(hb).origin.y
		if y < best - 0.0001:
			best = y
			_lie_t = t
	# трохи пізніше за найнижчу точку — коли вже спокійно лежить
	return _lie_t


func sleep_job() -> void:
	## Уночі спить у ліжку (якщо ліжка немає — дрімає в кріслі).
	var bed = world.spots.get("bed", null)
	if bed == null or anims.get("lie", "") == "":
		if seated != "armchair":
			sit_job("armchair", 1e9)
			return
		var id0 := begin_job("sleep")
		while id0 == job and (Game.hour() >= 21.0 or Game.hour() < 6.5):
			say("Хр-р-р… z-z-z", 2.5)
			await wait(6.0)
		if id0 != job:
			return
		cover(false)
		await stand_up()
		say("Доброго ранку!", 2.5)
		end_job(id0)
		return
	var id := begin_job("sleep")
	if seated != "":
		await stand_up()
		if id != job:
			return
	var bp: Vector3 = bed
	var side := bp + Vector3(-0.95, 0, 0.15)
	say("Пора спати…", 2.0)
	await go(side, false, false)
	if id != job:
		return
	face(bp)
	await wait(0.5)
	if id != job:
		return
	lying = true
	current = "lie"
	position = bp + LIE_OFF
	rotation.y = LIE_YAW
	_face_to = LIE_YAW
	model.position.y = _base_y + LIE_Y
	# одразу поза «лежить» (момент анімації, де голова найнижче) і тримаємо її
	var lt := _lie_time()
	# без плавного переходу: на швидкості 0 перехід «завмирає» на півдорозі — і дід «спав стоячи»
	ap.play(anims["lie"], 0.0)
	ap.seek(lt, true)
	ap.speed_scale = 0.0
	while id == job and (bed_now or Game.hour() >= 21.0 or Game.hour() < 6.5):
		if randf() < 0.6:
			say("Хр-р-р… z-z-z", 2.5)
		await wait(6.0)
	_wake_reset()
	if id != job:
		return
	position = side
	current = ""
	play("idle")
	say("Доброго ранку!", 2.5)
	end_job(id)


func nap_job() -> void:
	## Удень: лягає на ряднину під деревом і дрімає.
	if blanket == null or anims.get("lie", "") == "":
		return
	var id := begin_job("nap")
	var yaw := blanket.rotation.y + PI
	var f := _fwd(yaw)
	var spot := blanket.position - f * 0.22       # голова — до дерева
	await go(spot + f * 1.4)
	if id != job:
		return
	await go(spot + f * 0.5)
	if id != job:
		return
	_face_to = yaw
	await wait(0.6)
	lying = true
	position = spot
	rotation.y = yaw
	current = "lie"
	ap.play(anims["lie"], 1.0)
	say("Подрімаю трішки…", 2.5)
	var t := randf_range(20.0, 35.0)
	while t > 0.0 and id == job:
		await wait(5.0)
		t -= 5.0
		if randf() < 0.6:
			say("z-z-z", 2.0)
	lying = false
	if id != job:
		return
	position = spot + f * 0.5
	current = ""
	ap.play(anims["idle"], 1.0)
	end_job(id)


# ------------------------------------------------------------------ з гравцем
func wave_at(p: Vector3) -> void:
	if seated != "" or lying:
		say("Привіт, Beep!", 2.0)
		return
	stop()
	face(p)
	busy = true
	play("wave")
	_act_left = anim_length("wave")
	_act_then = Callable()


func start_talk(p: Vector3) -> void:
	if seated == "" and not lying:
		cancel_job()
		face(p)
		talking = true
	busy = false


func end_talk() -> void:
	talking = false
	idle_left = randf_range(3.0, 6.0)


func test(what: String) -> void:
	## Для перевірки в demo: call:grandpa:test:drink|bench|armchair|sleep|well
	match what:
		"tr_on", "tr_ride", "tr_off":
			# перевірка трактора: дідусь одразу біля трактора
			cancel_job()
			var id := begin_job("tractor")
			bounds = OUT_BOUNDS
			at_home = false
			visible = true
			global_position = tractor.to_global(tractor.CLIMB_FROM + Vector3(-0.5, 0, 0.3))
			await get_tree().process_frame
			if not await _go_to_tractor(id):
				return
			await _climb_on(tractor)
			if what == "tr_on":
				return
			tractor.start_engine()
			if what == "tr_ride":
				tractor.begin_manual()
				_main().vehicle_control_start("tractor", tractor)
				return
			await wait(1.0)
			await _climb_off(tractor)
		"drink":
			await sit_job("table", 0.1)
		"bench":
			sit_job("bench", 60.0)
		"armchair":
			_enter_house()
			sit_job("armchair", 60.0)
		"nap":
			nap_job()
		"sleep":
			_enter_house()
			sleep_job()
		"lie":
			# перевірка пози на ліжку без ходьби
			_enter_house()
			var bp: Vector3 = world.spots["bed"]
			lying = true
			current = "lie"
			ap.play(anims["lie"], 0.0)
			position = bp + LIE_OFF
			rotation.y = LIE_YAW
			model.position.y = _base_y + LIE_Y
		"well":
			well_drink_job()
		"sitdrink":
			var id := begin_job("t")
			var s: Array = seats["table"]
			position = s[0]
			rotation.y = 0.0
			seated = "table"
			model.position = Vector3(0, _base_y - 0.02, 0)
			await _drink_seated(s[3], id)



# ------------------------------------------------------------------ справи за межами двору: трактор, сад, ліс
var on_tractor: Node3D = null
var tractor: Node3D
var orchard: Node3D
var forest: Node3D
const YARD_BOUNDS := Rect2(-20.5, -14.5, 29.0, 19.0)
const OUT_BOUNDS := Rect2(-60.0, -130.0, 105.0, 164.0)


func _go_outside(id: int) -> bool:
	## З хати чи з двору — за ворота. Повертає false, якщо справу перервали.
	if seated != "":
		await stand_up()
	if lying:
		_wake_reset()
	if at_home:
		if not await _walk_out(id):
			return false
	await go(spots["inside_gate"] + Vector3(0.2, 0, 0))
	if id != job:
		return false
	await world.pass_gate(self, true)
	bounds = OUT_BOUNDS
	extra_obs = Obstacles.outer
	return id == job


func _come_back(id: int) -> bool:
	await go(spots["outside_gate"] + Vector3(-0.2, 0, 0))
	if id != job:
		return false
	await world.pass_gate(self, false)
	bounds = YARD_BOUNDS
	extra_obs = []
	return id == job


func _ride_step() -> void:
	var t: Node3D = on_tractor
	if t.has_method("grip_global"):
		# трактор: сидить, руки на кермі (їдуть разом з ободом), ноги на підніжках
		rotation.y = t.rotation.y
		model.position = Vector3(0, _base_y, 0)
		pose.lean = 0.2
		pose.ik = _driver_ik(t)
		place_hips(t.to_global(t.SEAT_HIPS) + Vector3(0, t.model.position.y, 0))
		return
	global_position = t.seat_global() - Vector3(0, HIPS_SIT * _k, 0) - t.global_transform.basis.z * 0.12
	rotation.y = t.rotation.y
	model.position = Vector3(0, _base_y, 0)


# ------------------------------------------------------------------ трактор: залазить, сидить за кермом, злазить
var _climbing := false
func _driver_ik(t: Node3D) -> Dictionary:
	return {
		"LeftHand": [t.grip_global(true), 1.0], "RightHand": [t.grip_global(false), 1.0],
		"LeftFoot": [t.to_global(t.FEET[0]), 1.0], "RightFoot": [t.to_global(t.FEET[1]), 1.0],
	}


func _hold_pose(kind: String, blend: float) -> void:
	## Перший кадр руху як нерухома поза (плавний перехід — і стоп).
	var n: String = anims.get(kind, "")
	if n == "" or ap == null:
		return
	current = kind
	ap.speed_scale = 1.0
	ap.play(n, blend)
	ap.seek(0.0, true)
	await wait(blend + 0.05)
	if current == kind:
		ap.pause()


func _kpt(t: Node3D, v) -> Variant:
	## Точка ключа в координатах трактора: Vector3, або "grip_l"/"grip_r" — обід керма.
	if v is Vector3:
		return v
	if v is String:
		return t.to_local(t.grip_global(v == "grip_l"))
	return null


func _play_keys(t: Node3D, keys: Array) -> void:
	## Програє «ключі» руху: стегна (шлях Catmull-Rom), поворот, нахил і точки для кистей та ступнів.
	## Усе — у координатах трактора, тож трактор може й трохи рухатися.
	var T := 0.0
	var total: float = keys[keys.size() - 1]["t"]
	while T < total:
		T = minf(total, T + get_process_delta_time())
		var i := 0
		while i < keys.size() - 2 and T > float(keys[i + 1]["t"]):
			i += 1
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var u := clampf((T - float(a["t"])) / maxf(0.001, float(b["t"]) - float(a["t"])), 0.0, 1.0)
		var sm := u * u * (3.0 - 2.0 * u)
		var p0: Vector3 = keys[maxi(i - 1, 0)]["hips"]
		var p3: Vector3 = keys[mini(i + 2, keys.size() - 1)]["hips"]
		var hp: Vector3 = (a["hips"] as Vector3).cubic_interpolate(b["hips"], p0, p3, sm)
		rotation.y = t.rotation.y + lerp_angle(float(a["yaw"]), float(b["yaw"]), sm)
		pose.lean = lerpf(float(a.get("lean", 0.0)), float(b.get("lean", 0.0)), sm)
		var ik := {}
		var ia: Dictionary = a.get("ik", {})
		var ib: Dictionary = b.get("ik", {})
		for k in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
			var ea: Array = ia.get(k, [null, 0.0])
			var eb: Array = ib.get(k, [null, 0.0])
			var pa = _kpt(t, ea[0])
			var pb = _kpt(t, eb[0])
			if pa == null:
				pa = pb
			if pb == null:
				pb = pa
			if pa == null:
				continue
			ik[k] = [t.to_global((pa as Vector3).lerp(pb, sm)), lerpf(float(ea[1]), float(eb[1]), sm)]
		pose.ik = ik
		place_hips(t.to_global(hp))
		await get_tree().process_frame


func _climb_on(t: Node3D) -> void:
	## Залазить на трактор, як справжній дідусь: рукою за крило, ногу на приступку, підтягується,
	## переступає на підніжку, розвертається й сідає. Тоді бере кермо обома руками.
	_climbing = true
	stop()
	put_back_held()
	if pose:
		pose.sit = 0.0
		pose.life = 0.0
	play("idle")
	model.position = Vector3(0, _base_y, 0)
	# спершу точно стає на місце, обличчям до трактора
	var yaw_in := PI / 2.0
	var tw := 0.0
	var from := global_position
	var at: Vector3 = t.to_global(t.CLIMB_FROM)
	while tw < 0.35:
		tw += get_process_delta_time()
		global_position = from.lerp(at, minf(1.0, tw / 0.35))
		rotation.y = lerp_angle(rotation.y, t.rotation.y + yaw_in, minf(1.0, tw / 0.3))
		await get_tree().process_frame
	await get_tree().process_frame
	var H0: Vector3 = t.to_local(hips_world())
	var hs := H0.y                                   # висота стегон стоячи
	var C: Vector3 = t.CLIMB_FROM
	var ST: Vector3 = t.STEP
	var ank := 0.08                                  # кісточка над підошвою
	var gl := C + Vector3(0, ank, -0.1)              # ступні на землі (ліва — ближче до заднього колеса)
	var gr := C + Vector3(0, ank, 0.1)
	var fl: Vector3 = t.FEET[0]
	var fr: Vector3 = t.FEET[1]
	var board := Vector3(-0.12, fr.y, 0.66)          # підніжка перед сидінням
	var keys := [
		{"t": 0.0, "hips": H0, "yaw": yaw_in, "lean": 0.0,
			"ik": {"LeftFoot": [gl, 1.0], "RightFoot": [gr, 1.0]}},
		{"t": 0.55, "hips": H0 + Vector3(0.04, -0.04, -0.03), "yaw": yaw_in, "lean": 0.22,
			"ik": {"LeftFoot": [gl, 1.0], "RightFoot": [gr + Vector3(0.12, 0.2, 0.02), 1.0],
				"LeftHand": [t.FENDER, 1.0], "RightHand": [Vector3(-0.3, 1.33, 1.38), 0.7]}},
		{"t": 1.0, "hips": H0 + Vector3(0.1, -0.05, 0.0), "yaw": yaw_in, "lean": 0.3,
			"ik": {"LeftFoot": [gl, 1.0], "RightFoot": [ST + Vector3(0, ank, 0.08), 1.0],
				"LeftHand": [t.FENDER, 1.0], "RightHand": [Vector3(-0.3, 1.33, 1.38), 1.0]}},
		{"t": 1.75, "hips": Vector3(ST.x - 0.06, ST.y + hs - 0.04, ST.z), "yaw": yaw_in, "lean": 0.2,
			"ik": {"LeftFoot": [Vector3(ST.x - 0.3, ST.y * 0.6, ST.z - 0.12), 1.0], "RightFoot": [ST + Vector3(0, ank, 0.08), 1.0],
				"LeftHand": [t.FENDER, 1.0], "RightHand": ["grip_r", 1.0]}},
		{"t": 2.2, "hips": Vector3(ST.x + 0.02, ST.y + hs, ST.z - 0.02), "yaw": yaw_in, "lean": 0.12,
			"ik": {"LeftFoot": [ST + Vector3(0.04, ank, -0.1), 1.0], "RightFoot": [ST + Vector3(0, ank, 0.08), 1.0],
				"LeftHand": [t.FENDER, 1.0], "RightHand": ["grip_r", 1.0]}},
		{"t": 2.85, "hips": Vector3(board.x - 0.05, board.y - ank + hs, board.z + 0.05), "yaw": 0.6, "lean": 0.1,
			"ik": {"LeftFoot": [board + Vector3(0.24, 0.12, 0.05), 1.0], "RightFoot": [board + Vector3(-0.08, 0, 0.08), 1.0],
				"LeftHand": ["grip_l", 0.6], "RightHand": ["grip_r", 1.0]}},
		{"t": 3.4, "hips": Vector3(0.0, board.y - ank + hs - 0.02, 0.5), "yaw": 0.0, "lean": 0.15,
			"ik": {"LeftFoot": [fl, 1.0], "RightFoot": [fr, 1.0],
				"LeftHand": ["grip_l", 1.0], "RightHand": ["grip_r", 1.0]}},
		{"t": 4.1, "hips": t.SEAT_HIPS, "yaw": 0.0, "lean": 0.2,
			"ik": {"LeftFoot": [fl, 1.0], "RightFoot": [fr, 1.0],
				"LeftHand": ["grip_l", 1.0], "RightHand": ["grip_r", 1.0]}},
	]
	# посередині руху тіло переходить у позу «сидить» (стегна вже керуються ключами)
	var sit_later := func():
		await wait(2.9)
		if _climbing:
			_hold_pose("sitdrink", 0.6)
	sit_later.call()
	await _play_keys(t, keys)
	seated = "tractor"
	on_tractor = t
	_climbing = false


func _climb_off(t: Node3D) -> void:
	## Устає, переступає на приступку, обертається обличчям назовні — і зістрибує на землю.
	_climbing = true
	await get_tree().process_frame
	var ST: Vector3 = t.STEP
	var ank := 0.08
	var fl: Vector3 = t.FEET[0]
	var fr: Vector3 = t.FEET[1]
	var board := Vector3(-0.12, fr.y, 0.66)
	var H0: Vector3 = t.to_local(hips_world())
	var hj := 90.0 * _k                              # стегна над ступнями на початку «зістрибує»
	var yaw_out := -PI / 2.0
	var keys := [
		{"t": 0.0, "hips": H0, "yaw": 0.0, "lean": 0.2,
			"ik": {"LeftFoot": [fl, 1.0], "RightFoot": [fr, 1.0], "LeftHand": ["grip_l", 1.0], "RightHand": ["grip_r", 1.0]}},
		{"t": 0.8, "hips": Vector3(-0.05, board.y - ank + hj, 0.5), "yaw": -0.3, "lean": 0.25,
			"ik": {"LeftFoot": [fl, 1.0], "RightFoot": [board + Vector3(-0.1, 0, 0.05), 1.0], "LeftHand": ["grip_l", 0.8], "RightHand": ["grip_r", 1.0]}},
		{"t": 1.6, "hips": Vector3(ST.x + 0.12, ST.y + hj + 0.02, ST.z - 0.05), "yaw": yaw_out + 0.4, "lean": 0.1,
			"ik": {"LeftFoot": [board + Vector3(0.1, 0.1, 0.1), 0.8], "RightFoot": [ST + Vector3(0.05, ank, -0.1), 1.0],
				"LeftHand": ["grip_r", 0.6], "RightHand": [t.FENDER, 0.8]}},
		{"t": 2.3, "hips": Vector3(ST.x - 0.02, ST.y + hj, ST.z), "yaw": yaw_out, "lean": 0.0,
			"ik": {"LeftFoot": [ST + Vector3(-0.02, ank, 0.1), 0.0], "RightFoot": [ST + Vector3(-0.02, ank, -0.1), 0.0],
				"LeftHand": [t.FENDER, 0.0], "RightHand": [t.FENDER, 0.0]}},
	]
	on_tractor = null
	var stand_later := func():
		await wait(0.5)
		if _climbing:
			_hold_pose("jump_down", 0.8)
	stand_later.call()
	await _play_keys(t, keys)
	pose.ik = {}
	pose.lean = 0.0
	seated = ""
	var n: String = anims.get("jump_down", "")
	if n != "" and ap:
		# зістрибує: рух сам несе його вперед і вниз, а ми лише опускаємо вузол на землю
		current = "jump_down"
		ap.play(n, 0.0)
		ap.speed_scale = 1.0
		var len := ap.get_animation(n).length
		var y0 := global_position.y
		var T := 0.0
		while T < len - 0.35:
			T += get_process_delta_time()
			global_position.y = lerpf(y0, 0.0, smoothstep(1.0, 1.65, T))
			await get_tree().process_frame
		var h := hips_world()
		ap.play(anims["idle"], 0.0)
		ap.seek(0.0, true)
		await get_tree().process_frame
		var off := hips_world() - global_position
		global_position = Vector3(h.x - off.x, 0.0, h.z - off.z)
	else:
		global_position = t.to_global(t.CLIMB_FROM)
	global_position.y = 0.0
	model.position = Vector3(0, _base_y, 0)
	current = ""
	ap.speed_scale = 1.0
	play("idle")
	_climbing = false


func _go_to_tractor(id: int) -> bool:
	## Підходить до трактора з правого боку, перед заднім колесом.
	await go(tractor.to_global(tractor.CLIMB_FROM + Vector3(-0.6, 0, 0.2)))
	if id != job:
		return false
	await go(tractor.to_global(tractor.CLIMB_FROM), false, false)
	return id == job


func _mount(t: Node3D) -> void:
	## Сідає на воза (трактор — див. _climb_on).
	_face_to = t.rotation.y
	var from := global_position
	_sit_still()
	var k := 0.0
	while k < 1.0:
		k = minf(1.0, k + get_process_delta_time() / 0.9)
		var to: Vector3 = t.seat_global() - Vector3(0, HIPS_SIT * _k, 0)
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * 0.35
		global_position = p
		rotation.y = lerp_angle(rotation.y, t.rotation.y, k)
		await get_tree().process_frame
	seated = "tractor"
	on_tractor = t


func _dismount(t: Node3D) -> void:
	on_tractor = null
	var from := global_position
	var to: Vector3 = t.to_global(Vector3(-1.35, 0, 0.3))
	to.y = 0.0
	var k := 0.0
	while k < 1.0:
		k = minf(1.0, k + get_process_delta_time() / 0.8)
		var p := from.lerp(to, k)
		p.y = lerpf(from.y, 0.0, k) + sin(k * PI) * 0.25
		global_position = p
		await get_tree().process_frame
	global_position = to
	seated = ""
	model.position = Vector3(0, _base_y, 0)
	ap.speed_scale = 1.0
	current = ""
	play("idle")


func plow_job() -> void:
	## Дідусь іде до трактора, заводить, оре поле рядами й ставить трактор під навіс.
	if tractor == null:
		say("Ех, трактора в нас нема…", 2.5)
		return
	if tractor.state != "parked":
		say("Трактор уже працює!", 2.0)
		return
	var id := begin_job("plow")
	say("Піду поорю поле!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_shed(id):
		return
	if not await _go_to_tractor(id):
		return
	await _climb_on(tractor)
	if id != job:
		_climb_off(tractor)
		return
	tractor.start_engine()
	say("Ну, Червоненький, поїхали!", 2.5)
	await wait(1.2)
	await tractor.drive_route(TRACTOR_OUT_WAY + [Vector3(23.0, 0, 4.0)], 3.2)
	if id != job:
		return
	await tractor.plow_field()
	if id != job:
		return
	say("Ото гарно зорали!", 2.5)
	Game.emit_event("plowed")
	await tractor.go_park(TRACTOR_PARK_WAY)
	await _climb_off(tractor)
	if id != job:
		return
	if not await _walk_from_shed(id):
		return
	if not await _come_back(id):
		return
	end_job(id)


func _main() -> Node:
	return get_node("/root/Main")


func tractor_drive_job() -> void:
	## Дідусь сідає на трактор, а гравець сам кермує (джойстик) і керує плугом (▲▼).
	## «Готово» — дідусь ставить трактор під навіс.
	if tractor == null:
		say("Ех, трактора в нас нема…", 2.5)
		return
	if tractor.state != "parked":
		say("Трактор уже працює!", 2.0)
		return
	var id := begin_job("tractor")
	say("Поїхали на тракторі!", 2.0)
	if not await _go_outside(id):
		return
	if not await _walk_to_shed(id):
		return
	if not await _go_to_tractor(id):
		return
	await _climb_on(tractor)
	if id != job:
		_climb_off(tractor)
		return
	tractor.start_engine()
	say("Ну, онучку, кермуй! Я — пасажиром.", 2.5)
	await wait(1.2)
	var m := _main()
	tractor.begin_manual()
	m.vehicle_control_start("tractor", tractor)
	while id == job and m._ctl_veh == tractor:
		await get_tree().process_frame
	m.vehicle_control_stop()
	await tractor.end_manual()
	say("Гарна їзда! Ставимо Червоненького додому.", 2.5)
	await tractor.go_park(TRACTOR_PARK_WAY)
	await _climb_off(tractor)
	if id != job:
		return
	if not await _walk_from_shed(id):
		return
	if not await _come_back(id):
		return
	end_job(id)


# дорога від воріт до стайні на фермі за ставком (північніше ставка, повз аеродром)
const STABLE_WAY := [Vector3(-24.0, 0, 8.5), Vector3(-45.0, 0, 9.0), Vector3(-120.0, 0, 9.0), Vector3(-158.0, 0, 30.0)]
const FARM_BOUNDS := Rect2(-200.0, -130.0, 245.0, 200.0)     # поза двором — аж до ферми
# навіс для техніки — на фермі біля східного забору (world_outer.gd → SHED)
const SHED_WALK := [Vector3(-24.0, 0, 8.5), Vector3(-45.0, 0, 9.0), Vector3(-120.0, 0, 9.0), Vector3(-166.0, 0, 9.0),
	Vector3(-171.5, 0, 22.0), Vector3(-171.5, 0, 31.0), Vector3(-150.0, 0, 32.0), Vector3(-143.0, 0, 44.5)]
const TRACTOR_OUT_WAY := [Vector3(-140.3, 0, 45.5), Vector3(-150.0, 0, 34.0), Vector3(-160.0, 0, 31.0), Vector3(-171.5, 0, 31.0),
	Vector3(-171.5, 0, 22.0), Vector3(-166.0, 0, 9.0), Vector3(-120.0, 0, 9.0), Vector3(-45.0, 0, 9.0), Vector3(-24.0, 0, 9.5), Vector3(12.0, 0, 9.5)]
const TRACTOR_PARK_WAY := [Vector3(12.0, 0, 9.5), Vector3(-24.0, 0, 9.5), Vector3(-45.0, 0, 9.0), Vector3(-120.0, 0, 9.0), Vector3(-166.0, 0, 9.0),
	Vector3(-171.5, 0, 22.0), Vector3(-171.5, 0, 31.0), Vector3(-160.0, 0, 31.0), Vector3(-150.0, 0, 34.0)]


func _walk_to_shed(id: int) -> bool:
	bounds = FARM_BOUNDS
	for wp in SHED_WALK:
		await go(wp)
		if id != job:
			return false
	return true


func _walk_from_shed(id: int) -> bool:
	bounds = FARM_BOUNDS
	extra_obs = Obstacles.outer
	for k in range(SHED_WALK.size() - 1, -1, -1):
		await go(SHED_WALK[k])
		if id != job:
			return false
	return true


func horse_job() -> void:
	## Дідусь запрягає коня у віз, сідає — і гравець кермує (джойстик). «Готово» — кінь сам везе віз до стайні.
	var m := _main()
	var cart = m.horse_cart
	var horse = m.horse
	if cart == null or horse == null:
		say("Ех, коня чи воза в нас нема…", 2.5)
		return
	if cart.hitched:
		say("Кінь уже запряжений!", 2.0)
		return
	var id := begin_job("cart")
	say("Піду запрягати коня!", 2.5)
	if not await _go_outside(id):
		return
	bounds = FARM_BOUNDS
	for wp in STABLE_WAY:
		await go(wp)
		if id != job:
			return
	await go(cart.to_global(Vector3(1.9, 0, 0.0)))     # збоку воза, з боку дороги
	if id != job:
		return
	say("Но-о, мій коню, ходи сюди!", 2.0)
	await cart.bring_horse(horse)
	cart.harness_now()
	if id != job:
		cart.unhitch()
		return
	await _mount(cart)
	if id != job:
		_dismount(cart)
		cart.unhitch()
		return
	say("Ну, онучку, кермуй конем! Я — пасажиром.", 2.5)
	cart.start_manual()
	m.vehicle_control_start("horse", cart)
	while id == job and m._ctl_veh == cart:
		await get_tree().process_frame
	m.vehicle_control_stop()
	say("Гарна їзда! Везімо коня додому.", 2.5)
	await cart.drive_back()
	await _dismount(cart)
	cart.unhitch()
	if id != job:
		return
	say("Дякую, коню! Іди відпочивай.", 2.0)
	await go(cart.park_pos + Vector3(1.4, 0, 3.5))       # крок убік від воза, на південь
	if id != job:
		return
	for k in range(STABLE_WAY.size() - 1, -1, -1):
		await go(STABLE_WAY[k])
		if id != job:
			return
	if not await _come_back(id):
		return
	end_job(id)


# ------------------------------------------------------------------ віз біля садка (main.gd: garden_cart) і кінний плуг
const GARDEN_WALK := [Vector3(1.5, 0, 6.2), Vector3(10.5, 0, 6.0), Vector3(21.0, 0, 6.3), Vector3(25.0, 0, 8.0)]
const GARDEN_BACK := Vector3(25.0, 0, 19.5)              # за возом (звідти підходить до плуга)
# від воза на дорогу й до поля під оранку
const GARDEN_TO_FIELD := [Vector3(23.3, 0, 8.0), Vector3(26.0, 0, 5.6), Vector3(71.0, 0, 5.0), Vector3(73.4, 0, 7.0)]
# заїзд на стоянку: уздовж садка на південь, розворот — і з півдня оглоблями на північ
const GARDEN_LOOP := [Vector3(24.8, 0, 7.5), Vector3(25.0, 0, 21.0), Vector3(24.0, 0, 25.5), Vector3(22.0, 0, 24.5), Vector3(23.3, 0, 22.6)]


func _garden_way_home(cart: Node3D) -> Array:
	var p: Vector3 = cart.horse.global_position
	var way: Array
	if p.x < 20.0:
		way = Vehicles.route(p, Vector3(1.5, 0, 6.2)) + [Vector3(10.5, 0, 6.0), Vector3(22.0, 0, 5.8)]
	else:
		way = Vehicles.route(p, Vector3(30.0, 0, 5.5))
	return way + GARDEN_LOOP


func _walk_to_garden(id: int) -> bool:
	bounds = FOREST_BOUNDS
	for wp in GARDEN_WALK:
		await go(wp)
		if id != job:
			return false
	return true


func _walk_from_garden(id: int) -> bool:
	bounds = FOREST_BOUNDS
	for k in range(GARDEN_WALK.size() - 1, -1, -1):
		await go(GARDEN_WALK[k])
		if id != job:
			return false
	if not await _come_back(id):
		return false
	end_job(id)
	return true


func _plow_move(id: int, cart: Node3D, plow: Node3D, attach: bool) -> void:
	## Підходить до чепіг плуга, береться — і чіпляє плуг позаду воза (або знімає й ставить на місце).
	await go(GARDEN_BACK)
	if id != job:
		return
	await go(plow.to_global(Vector3(0, 0, -1.9)))
	if id != job:
		return
	_face_to = atan2(plow.global_position.x - global_position.x, plow.global_position.z - global_position.z)
	play("wave", 1.0)
	await wait(0.6)
	if id != job:
		return
	if attach:
		await plow.attach(cart)
	else:
		await plow.detach()
	play("idle")
	await go(GARDEN_BACK)


func _ride_garden_cart(id: int, cart: Node3D) -> bool:
	await go(cart.to_global(Vector3(-1.35, 0, 0.3)))
	if id != job:
		return false
	await _mount(cart)
	if id != job:
		_dismount(cart)
		return false
	return true


func garden_cart_job() -> void:
	## Дідусь сідає на віз біля садка — гравець кермує конем. «Готово» — кінь сам везе віз під садок.
	var m := _main()
	var cart = m.garden_cart
	if cart == null or cart.horse == null:
		say("Ех, коня чи воза в нас нема…", 2.5)
		return
	var id := begin_job("garden")
	say("Піду до коня під садок!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _ride_garden_cart(id, cart):
		return
	say("Ну, онучку, кермуй конем! Я — пасажиром.", 2.5)
	cart.start_manual()
	m.vehicle_control_start("garden_cart", cart)
	while id == job and m._ctl_veh == cart:
		await get_tree().process_frame
	m.vehicle_control_stop()
	say("Гарна їзда! Ставимо віз під садок.", 2.5)
	await cart.drive_back(_garden_way_home(cart))
	await _dismount(cart)
	if id != job:
		return
	await _walk_from_garden(id)


func garden_plow_job() -> void:
	## Причепити плуг позаду воза або зняти й поставити біля садка.
	var m := _main()
	var cart = m.garden_cart
	var plow = m.garden_plow
	if cart == null or plow == null:
		say("Ех, плуга в нас нема…", 2.5)
		return
	var attach: bool = plow.cart == null
	var id := begin_job("garden")
	say("Причеплю плуга до воза!" if attach else "Зніму плуга з воза!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	await _plow_move(id, cart, plow, attach)
	if id != job:
		return
	say("Готово — плуг причеплений!" if attach else "Хай плуг постоїть до весни.", 2.5)
	await _walk_from_garden(id)


func garden_field_job() -> void:
	## Чіпляє плуг (якщо ще ні), сідає на віз, їде на поле й оре конем рядами, потім — назад під садок.
	var m := _main()
	var cart = m.garden_cart
	var plow = m.garden_plow
	if cart == null or plow == null or cart.horse == null:
		say("Ех, коня чи плуга в нас нема…", 2.5)
		return
	var id := begin_job("garden")
	say("Поїду орати поле конем!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if plow.cart == null:
		await _plow_move(id, cart, plow, true)
		if id != job:
			return
	if not await _ride_garden_cart(id, cart):
		return
	say("Но-о, коню! Гайда на поле!", 2.5)
	for wp in GARDEN_TO_FIELD:
		await cart._horse_to(wp, 2.6, 1.5)
		if id != job:
			break
	if id == job:
		say("Оремо!", 1.5)
		await cart.plow_field(m.world.outer.PLOW_FIELD, func(): return id == job)
	if id == job:
		say("Ото гарно зорали конем!", 2.5)
		Game.emit_event("plowed")
	await cart.drive_back(_garden_way_home(cart))
	await _dismount(cart)
	if id != job:
		return
	await _walk_from_garden(id)


func _fruit_color(fruit: String) -> Color:
	## Колір плоду в кошику — за назвою (яблука червоні, груші жовті, сливи фіолетові…).
	var f := fruit.to_lower()
	if "яблу" in f:
		return Color(0.85, 0.15, 0.12)
	if "груш" in f:
		return Color(0.8, 0.8, 0.25)
	if "слив" in f:
		return Color(0.45, 0.2, 0.55)
	if "вишн" in f or "черешн" in f:
		return Color(0.6, 0.05, 0.12)
	return Color(0.95, 0.6, 0.15)


func orchard_job() -> void:
	## Іде в садок із кошиком, збирає стиглі плоди (вони лягають у кошик) і несе додому.
	if orchard == null:
		return
	var id := begin_job("orchard")
	say("Піду в садок, позбираю яблучка!", 2.5)
	if not await _go_outside(id):
		return
	var basket := take_basket()
	# через хвіртку садка (з боку дороги)
	await go(Vector3(2.8, 0, 11.5))
	if id != job:
		return
	await go(Vector3(5.0, 0, 11.6), false)
	if id != job:
		return
	var got := 0
	var trees: Array = orchard.ripe_trees(4)
	if trees.is_empty():
		say("Ще нічого не достигло… Зайду завтра.", 3.0)
	for ti in trees:
		var p: Vector3 = orchard.pick_spot(ti, global_position)
		await go(p)
		if id != job:
			return
		_face_to = atan2(orchard.tree_pos(ti).x - global_position.x, orchard.tree_pos(ti).z - global_position.z)
		await wait(0.4)
		for k in 3:
			play("wave", 1.3)
			await wait(0.7)
			if id != job:
				return
			var n: int = orchard.pick(ti, 1)
			got += n
			if n > 0:
				Util.basket_add(basket, _fruit_color(orchard.fruit_name(ti)), 0.045)
		if id != job:
			return
	if got > 0:
		say("Повний кошик — %d шт.! Буде компот." % got, 3.0)
		Game.emit_event("fruit")
	await go(Vector3(5.0, 0, 11.6))
	if id != job:
		return
	await go(Vector3(2.8, 0, 11.5), false)
	if id != job:
		return
	if not await _come_back(id):
		return
	drop_basket()
	end_job(id)


var _forest_ride := true          # по гриби — то трактором, то пішки (по черзі)


func forest_job() -> void:
	## Іде (або їде трактором) дорогою в грибний ліс на сході, збирає гриби й ягоди (лісові дари відростають щодня).
	if forest == null:
		return
	var id := begin_job("forest")
	var ride: bool = _forest_ride and tractor != null and tractor.state == "parked"
	_forest_ride = not _forest_ride
	say("Поїду трактором у ліс по гриби!" if ride else "Піду в ліс по гриби та ягоди!", 2.5)
	if not await _go_outside(id):
		return
	bounds = FOREST_BOUNDS
	var end: Vector3 = FOREST_WAY[FOREST_WAY.size() - 1]
	if ride:
		if not await _walk_to_shed(id):
			return
		if not await _go_to_tractor(id):
			return
		bounds = FOREST_BOUNDS
		await _climb_on(tractor)
		if id != job:
			_climb_off(tractor)
			return
		tractor.start_engine()
		say("Ну, Червоненький, гайда в ліс!", 2.5)
		await wait(1.0)
		var there: Array = TRACTOR_OUT_WAY + [Vector3(23.0, 0, 4.0)]
		for k in range(3, FOREST_WAY.size()):
			there.append(FOREST_WAY[k])
		await tractor.drive_route(there, 3.4)
		if id != job:
			return
		await _climb_off(tractor)
		if id != job:
			return
		bounds = FOREST_BOUNDS
		extra_obs = Obstacles.outer
	var basket := take_basket()
	if not ride:
		for wp in FOREST_WAY:
			await go(wp)
			if id != job:
				return
	var got := 0
	for it in forest.nearest_goods(end, 6):
		await go(forest.goods_pos(it) + Vector3(0.5, 0, 0.5))
		if id != job:
			return
		_face_to = atan2(forest.goods_pos(it).x - global_position.x, forest.goods_pos(it).z - global_position.z)
		play("wave", 1.0)
		await wait(0.9)
		if id != job:
			return
		var col: Color = forest.kind_color(it)
		var n: int = forest.take(it)
		got += n
		if n > 0:
			Util.basket_add(basket, col, 0.05)
		if id != job:
			return
	say("Назбирав %d — буде на вечерю!" % got if got > 0 else "Сьогодні все вже позбирали…", 3.0)
	if got > 0:
		Game.emit_event("forest")
	if ride:
		drop_basket()
		if not await _go_to_tractor(id):
			return
		await _climb_on(tractor)
		if id != job:
			_climb_off(tractor)
			return
		tractor.start_engine()
		say("Додому, Червоненький!", 2.0)
		var back: Array = []
		for k in range(FOREST_WAY.size() - 2, 2, -1):
			back.append(FOREST_WAY[k])
		await tractor.drive_route(back, 3.4)
		await tractor.go_park(TRACTOR_PARK_WAY)
		await _climb_off(tractor)
		if id != job:
			return
		if not await _walk_from_shed(id):
			return
		if not await _come_back(id):
			return
		end_job(id)
		return
	for k in range(FOREST_WAY.size() - 1, -1, -1):
		await go(FOREST_WAY[k])
		if id != job:
			return
	if not await _come_back(id):
		return
	drop_basket()
	end_job(id)
