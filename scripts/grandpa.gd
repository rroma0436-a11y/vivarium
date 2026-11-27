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
	_make_trip_props()


func _jug(key: String) -> Node3D:
	var arr: Array = world.props.get(key, [])
	if arr.is_empty():
		return null
	var j: Node3D = arr[0]
	Walker.remember_home(j)
	return j


func _process(delta: float) -> void:
	if behind_plow:
		_behind_step(delta)
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		return
	if on_tractor or _climbing:
		if on_tractor and not _climbing:
			_ride_step()
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		return
	_physics_step(delta)
	if seated == "" and not lying and not Util.pier.is_empty() and Util.on_pier(global_position, 0.35):
		global_position.y = Util.pier_y(global_position)      # по причалу — по настилу
	if _rod_hand:
		_rod_step()
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
	# віз: тримає віжки обома руками
	if t.has_method("rein_global") and t.rein_global(true) != Vector3.INF:
		pose.ik = {"LeftHand": [t.rein_global(true), 1.0], "RightHand": [t.rein_global(false), 1.0]}
	else:
		pose.ik = {}


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
	pose.ik = {}
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


func _obs() -> Array:
	## Крім звичайних перешкод — коні й вози (щоб не проходив крізь них).
	var list: Array = Obstacles.items + extra_obs
	var m := get_node_or_null("/root/Main")
	if m == null:
		return list
	for c in [m.get("horse_cart"), m.get("garden_cart")]:
		if c == null or not is_instance_valid(c) or not (c is Node3D) or c == on_tractor or not (c as Node3D).is_visible_in_tree():
			continue
		for z in [-1.05, -0.35, 0.35, 1.05]:
			var p: Vector3 = (c as Node3D).to_global(Vector3(0, 0, z))
			list.append([Vector2(p.x, p.z), 0.62 if z < 1.0 else 0.45, 1.2])
	var hs: Array = [m.get("horse"), m.get("garden_horse")]
	for k in ["extra_horses", "riding_horses"]:
		var a = m.get(k)
		if a is Array:
			hs.append_array(a)
	for h in hs:
		if h == null or not is_instance_valid(h) or not (h is Node3D) or not (h as Node3D).is_visible_in_tree():
			continue
		var hn: Node3D = h
		var f := Vector3(sin(hn.rotation.y), 0, cos(hn.rotation.y))
		for k in [-0.65, 0.0, 0.65]:
			var p2: Vector3 = hn.global_position + f * k
			list.append([Vector2(p2.x, p2.z), 0.4, 1.5])
	return list


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
# від воза на дорогу й до поля під оранку: віз стає біля поля, на південь від дороги
const GARDEN_TO_FIELD := [Vector3(23.3, 0, 8.0), Vector3(26.0, 0, 5.6), Vector3(66.0, 0, 6.2), Vector3(73.0, 0, 6.6)]
# заїзд на стоянку: уздовж садка на південь, розворот — і з півдня оглоблями на північ
const GARDEN_LOOP := [Vector3(24.8, 0, 7.5), Vector3(25.0, 0, 21.0), Vector3(24.0, 0, 25.5), Vector3(22.0, 0, 24.5), Vector3(23.3, 0, 22.6)]
const GARDEN_PADDOCK := Vector3(23.7, 0, 20.8)           # де пасеться розпряжений кінь (main.gd)
const LEAD_AT := Vector3(0.75, 0, 0.8)                   # де йде дідусь, ведучи коня за вуздечку (зліва від голови)
const BRIDLE := Vector3(0.16, 1.3, 0.95)                 # вуздечка біля морди (у системі коня)
var behind_plow: Node3D = null                           # дідусь іде позаду плуга, тримаючись за чепіги
var _bp_v := 0.0
var _cart_hs := 0.95                                     # висота стегон стоячи (для злізання з воза)


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


func cancel_job() -> void:
	if behind_plow:
		_garden_abort()
	if _trip != "":
		_trip_abort()
	super()


func _garden_abort() -> void:
	behind_plow = null
	_climbing = false
	if pose:
		pose.ik = {}
		pose.lean = 0.0


# ---------------- дідусь позаду плуга: руки на чепігах, іде слідом
func _behind_step(delta: float) -> void:
	var p: Node3D = behind_plow
	if not is_instance_valid(p):
		behind_plow = null
		return
	var at: Vector3 = p.rear_stand()
	var mv := Vector2(at.x - global_position.x, at.z - global_position.z).length() / maxf(delta, 0.001)
	_bp_v = lerpf(_bp_v, mv, 1.0 - exp(-delta * 6.0))
	global_position = at
	rotation.y = p.rotation.y
	model.position = Vector3(0, _base_y, 0)
	if _bp_v > 0.15:
		play("walk", clampf(_bp_v / walk_speed, 0.3, 1.6))
	else:
		play("idle")
	if pose:
		pose.lean = 0.25
		pose.ik = {"LeftHand": [p.grip(true), 1.0], "RightHand": [p.grip(false), 1.0]}


func _take_plow(id: int, plow: Node3D) -> bool:
	## Підходить ззаду до плуга й береться за чепіги.
	await go(plow.rear_stand())
	if id != job:
		return false
	_face_to = plow.rotation.y
	await wait(0.3)
	stop()
	_bp_v = 0.0
	behind_plow = plow
	await wait(0.4)
	return id == job


func _carry_plow(id: int, plow: Node3D, to: Transform3D) -> bool:
	## Несе плуг за чепіги (плуг піднятий) і кладе його туди, куди треба (на віз чи на землю).
	if not await _take_plow(id, plow):
		_garden_abort()
		return false
	var d := plow.global_position.distance_to(to.origin)
	await plow.glide(to, maxf(1.4, d / 0.8))
	behind_plow = null
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	play("idle")
	return id == job


# ---------------- коня — за вуздечку
func _lead_pose(h: Node3D, sp: float) -> void:
	var at: Vector3 = h.to_global(LEAD_AT)
	global_position = Vector3(at.x, 0, at.z)
	rotation.y = h.rotation.y
	model.position = Vector3(0, _base_y, 0)
	if absf(sp) > 0.1:
		play("walk", clampf(absf(sp) / walk_speed, 0.4, 1.4))
	else:
		play("idle")
	if pose:
		pose.lean = 0.0
		pose.ik = {"RightHand": [h.to_global(BRIDLE), 0.8]}


func _lead_horse(id: int, h: Node3D, way: Array) -> bool:
	## Підходить до коня, бере за вуздечку й веде через точки way.
	h.hitch_begin()
	if h.to_local(global_position).x < 0.0:
		await go(h.to_global(Vector3(0, 0, 2.6)))         # обходить коня спереду
	await go(h.to_global(LEAD_AT))
	if id != job:
		return false
	stop()
	_climbing = true
	for wp in way:
		var t := 0.0
		while t < 40.0:
			var dt := get_process_delta_time()
			t += dt
			var to: Vector3 = (wp as Vector3) - h.global_position
			to.y = 0.0
			var d := to.length()
			if d < 0.3 or id != job:
				break
			var hd := lerp_angle(h.rotation.y, atan2(to.x, to.z), 1.0 - exp(-dt * 2.5))
			var sp := minf(1.0, maxf(0.35, d * 1.2))
			h.hitch_move(hd, sp, dt)
			_lead_pose(h, sp)
			await get_tree().process_frame
		if id != job:
			_garden_abort()
			return false
	h.hitch_move(h.rotation.y, 0.0, 0.0)
	_lead_pose(h, 0.0)
	return true


func _turn_horse(h: Node3D, yaw: float) -> void:
	while absf(angle_difference(h.rotation.y, yaw)) > 0.03:
		var dt := get_process_delta_time()
		var a: float = h.rotation.y + clampf(angle_difference(h.rotation.y, yaw), -1.2 * dt, 1.2 * dt)
		h.hitch_move(a, 0.0, dt)
		h._play("walk", 0.5)
		_lead_pose(h, 0.3)
		await get_tree().process_frame
	h.hitch_move(yaw, 0.0, 0.0)


func _back_horse(h: Node3D, p: Vector3) -> void:
	## Кінь задкує (в оглоблі).
	var t := 0.0
	while t < 12.0:
		var dt := get_process_delta_time()
		t += dt
		var to := p - h.global_position
		to.y = 0.0
		if to.length() < 0.05:
			break
		h.global_position += to.normalized() * minf(0.6 * dt, to.length())
		h._play("walk", -0.6)
		_lead_pose(h, 0.6)
		await get_tree().process_frame
	h.global_position = Vector3(p.x, h.global_position.y, p.z)
	h.hitch_move(h.rotation.y, 0.0, 0.0)


func _release_lead() -> void:
	_climbing = false
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	play("idle")


func _harness_horse(id: int, cart: Node3D, h: Node3D) -> bool:
	## Веде коня до воза, заводить задки в оглоблі й запрягає.
	if cart.hitched:
		return true
	var way := [cart.to_global(Vector3(-2.4, 0, -3.2)), cart.to_global(Vector3(-2.4, 0, cart.BEHIND + 2.8)), cart.to_global(Vector3(0, 0, cart.BEHIND + 2.8))]
	if not await _lead_horse(id, h, way):
		return false
	await _turn_horse(h, cart.rotation.y)
	await _back_horse(h, cart.to_global(Vector3(0, 0, cart.BEHIND)))
	_release_lead()
	if id != job:
		return false
	say("Тпру-у… Стій, запрягаю!", 2.0)
	_face_to = atan2(h.global_position.x - global_position.x, h.global_position.z - global_position.z)
	play("wave", 1.0)
	await wait(1.2)
	cart.horse = h
	cart.harness_now()
	cart.hitched = true
	h.hitch_move(cart.rotation.y, 0.0, 0.0)
	play("idle")
	return id == job


func _unharness_horse(id: int, cart: Node3D) -> bool:
	## Розпрягає коня й відводить пастися біля садка.
	var h: Node3D = cart.horse
	if h == null:
		return true
	say("Розпрягаю, відпочивай, коню!", 2.0)
	if h.to_local(global_position).x < 0.0:
		await go(h.to_global(Vector3(0, 0, 2.6)))
	await go(h.to_global(LEAD_AT))
	if id != job:
		return false
	_face_to = h.rotation.y
	play("wave", 1.0)
	await wait(1.0)
	cart.hitched = false
	h.show_harness(false)
	cart.harness_to_cart()
	var way := [cart.to_global(Vector3(0, 0, cart.BEHIND + 2.2)), cart.to_global(Vector3(-2.4, 0, cart.BEHIND + 1.0)),
		cart.to_global(Vector3(-2.4, 0, -3.2)), GARDEN_PADDOCK]
	if not await _lead_horse(id, h, way):
		return false
	_release_lead()
	cart.unhitch()
	return id == job


# ---------------- на віз і з воза — по-справжньому: нога на маточину колеса, руки на борт
func _cart_hub(c: Node3D) -> Vector3:
	for w in c.wheels:
		if w[2]:
			var p: Vector3 = c.to_local((w[0] as Node3D).global_position)
			if p.x < 0.0:
				return p
	return Vector3(-0.7, 0.33, c._pz)


func _cart_climb_on(c: Node3D) -> void:
	_climbing = true
	stop()
	put_back_held()
	if pose:
		pose.sit = 0.0
		pose.life = 0.0
		pose.ik = {}
	play("idle")
	model.position = Vector3(0, _base_y, 0)
	var hub := _cart_hub(c)
	var C := Vector3(hub.x - 0.5, 0, hub.z - 0.1)
	var yaw_in := PI / 2.0
	var tw := 0.0
	var from := global_position
	var at: Vector3 = c.to_global(C)
	at.y = 0.0
	while tw < 0.4:
		tw += get_process_delta_time()
		global_position = from.lerp(at, minf(1.0, tw / 0.4))
		rotation.y = lerp_angle(rotation.y, c.rotation.y + yaw_in, minf(1.0, tw / 0.35))
		await get_tree().process_frame
	await get_tree().process_frame
	var H0: Vector3 = c.to_local(hips_world())
	var hs := H0.y
	_cart_hs = hs
	var ank := 0.08
	var bed := 0.55
	var S: Vector3 = c.SEAT
	var ra := Vector3(hub.x + 0.08, 0.8, hub.z - 0.45)
	var rb := Vector3(hub.x + 0.08, 0.8, hub.z + 0.25)
	var keys := [
		{"t": 0.0, "hips": H0, "yaw": yaw_in, "lean": 0.0,
			"ik": {"LeftFoot": [C + Vector3(0, ank, 0.12), 1.0], "RightFoot": [C + Vector3(0, ank, -0.12), 1.0]}},
		{"t": 0.55, "hips": H0 + Vector3(0.06, -0.05, 0.0), "yaw": yaw_in, "lean": 0.25,
			"ik": {"LeftFoot": [C + Vector3(0, ank, 0.12), 1.0], "RightFoot": [hub + Vector3(-0.08, ank * 0.5, -0.05), 1.0],
				"LeftHand": [ra, 1.0], "RightHand": [rb, 1.0]}},
		{"t": 1.25, "hips": Vector3(hub.x - 0.15, hub.y + hs - 0.08, hub.z - 0.05), "yaw": yaw_in, "lean": 0.3,
			"ik": {"LeftFoot": [hub + Vector3(-0.2, 0.15, 0.2), 0.6], "RightFoot": [hub + Vector3(-0.08, ank * 0.5, -0.05), 1.0],
				"LeftHand": [ra, 1.0], "RightHand": [rb, 1.0]}},
		{"t": 1.95, "hips": Vector3(-0.28, bed + hs - 0.05, S.z - 0.15), "yaw": yaw_in * 0.6, "lean": 0.15,
			"ik": {"LeftFoot": [Vector3(-0.3, bed + ank, S.z - 0.05), 1.0], "RightFoot": [hub + Vector3(0.0, 0.2, 0.0), 0.5],
				"LeftHand": [ra, 0.6], "RightHand": [rb, 0.6]}},
		{"t": 2.55, "hips": Vector3(0.0, bed + hs - 0.05, S.z - 0.2), "yaw": 0.0, "lean": 0.1,
			"ik": {"LeftFoot": [Vector3(0.12, bed + ank, S.z - 0.1), 1.0], "RightFoot": [Vector3(-0.12, bed + ank, S.z - 0.1), 1.0]}},
		{"t": 3.2, "hips": S, "yaw": 0.0, "lean": 0.15,
			"ik": {"LeftFoot": [Vector3(0.15, bed + ank, S.z + 0.45), 1.0], "RightFoot": [Vector3(-0.15, bed + ank, S.z + 0.45), 1.0]}},
	]
	var sit_later := func():
		await wait(2.5)
		if _climbing:
			_hold_pose("sitdrink", 0.6)
	sit_later.call()
	await _play_keys(c, keys)
	pose.ik = {}
	pose.lean = 0.0
	seated = "tractor"
	on_tractor = c
	_climbing = false


func _cart_climb_off(c: Node3D) -> void:
	on_tractor = null
	_climbing = true
	await get_tree().process_frame
	var hub := _cart_hub(c)
	var C := Vector3(hub.x - 0.55, 0, hub.z - 0.1)
	var hs := _cart_hs
	var ank := 0.08
	var bed := 0.55
	var S: Vector3 = c.SEAT
	var ra := Vector3(hub.x + 0.08, 0.8, hub.z - 0.45)
	var rb := Vector3(hub.x + 0.08, 0.8, hub.z + 0.25)
	var H0: Vector3 = c.to_local(hips_world())
	var yaw_out := -PI / 2.0
	var keys := [
		{"t": 0.0, "hips": H0, "yaw": 0.0, "lean": 0.15,
			"ik": {"LeftFoot": [Vector3(0.15, bed + ank, S.z + 0.45), 1.0], "RightFoot": [Vector3(-0.15, bed + ank, S.z + 0.45), 1.0]}},
		{"t": 0.7, "hips": Vector3(0.0, bed + hs - 0.05, S.z - 0.2), "yaw": 0.0, "lean": 0.1,
			"ik": {"LeftFoot": [Vector3(0.12, bed + ank, S.z - 0.1), 1.0], "RightFoot": [Vector3(-0.12, bed + ank, S.z - 0.1), 1.0]}},
		{"t": 1.3, "hips": Vector3(-0.3, bed + hs - 0.05, S.z - 0.15), "yaw": yaw_out, "lean": 0.1,
			"ik": {"LeftFoot": [Vector3(-0.3, bed + ank, S.z - 0.25), 1.0], "RightFoot": [Vector3(-0.3, bed + ank, S.z), 1.0],
				"LeftHand": [rb, 0.6], "RightHand": [ra, 0.6]}},
		{"t": 2.0, "hips": Vector3(hub.x - 0.12, hub.y + hs - 0.1, hub.z - 0.05), "yaw": yaw_out, "lean": 0.2,
			"ik": {"LeftFoot": [hub + Vector3(-0.08, ank * 0.5, 0.05), 1.0], "RightFoot": [hub + Vector3(-0.25, 0.1, -0.2), 0.5],
				"LeftHand": [rb, 1.0], "RightHand": [ra, 1.0]}},
		{"t": 2.7, "hips": C + Vector3(0, hs, 0), "yaw": yaw_out, "lean": 0.0,
			"ik": {"LeftFoot": [C + Vector3(0, ank, -0.12), 0.0], "RightFoot": [C + Vector3(0, ank, 0.12), 0.0],
				"LeftHand": [rb, 0.0], "RightHand": [ra, 0.0]}},
	]
	play("idle")
	await _play_keys(c, keys)
	pose.ik = {}
	pose.lean = 0.0
	seated = ""
	global_position.y = 0.0
	model.position = Vector3(0, _base_y, 0)
	ap.speed_scale = 1.0
	play("idle")
	_climbing = false


# ---------------- справи з возом біля садка
func _garden_parts() -> Array:
	var m := _main()
	return [m, m.garden_cart, m.garden_horse, m.garden_plow]


func _ready_plow_and_horse(id: int, cart: Node3D, h: Node3D, plow: Node3D, load_plow: bool) -> bool:
	## Біля садка: (за потреби) кладе плуг на віз, запрягає коня й сідає на віз.
	if load_plow and plow and plow.state != "cart":
		if plow.state == "horse":
			plow.unhitch()
		say("Покладу плуга на віз.", 2.0)
		await go(Vector3(25.2, 0, 19.2))              # повз віз ззаду
		if not await _carry_plow(id, plow, plow.bed_xf(cart)):
			return false
		plow.put_in_cart(cart)
	if not cart.hitched:
		if not await _harness_horse(id, cart, h):
			return false
	if not await _to_climb_spot(id, cart):
		return false
	await _cart_climb_on(cart)
	if id != job:
		await _cart_climb_off(cart)
		return false
	return true


func _to_climb_spot(id: int, cart: Node3D) -> bool:
	## До лівого переднього колеса воза (обходить коня спереду, якщо стоїть з іншого боку).
	if cart.to_local(global_position).x > -0.3:
		await go(cart.to_global(Vector3(0, 0, cart.BEHIND + 2.6)))
		if id != job:
			return false
	await go(cart.to_global(_cart_hub(cart) + Vector3(-0.9, 0, -0.1)))
	return id == job


func _home_and_unload(id: int, cart: Node3D, plow: Node3D) -> void:
	## Додому: віз — під садок, плуг — з воза на місце, коня — розпрягти.
	say("Додому, коню!", 2.0)
	await cart.drive_back(_garden_way_home(cart))
	await _cart_climb_off(cart)
	if id != job:
		return
	if plow and plow.state == "cart":
		say("Зніму плуга.", 2.0)
		await go(Vector3(25.2, 0, 19.2))
		if not await _carry_plow(id, plow, plow.rest_xf()):
			return
		plow.put_down()
		await go(Vector3(20.6, 0, 15.0))              # повз плуг — до коня
	if not await _unharness_horse(id, cart):
		return
	await _walk_from_garden(id)


func garden_cart_job() -> void:
	## Дідусь запрягає коня, лізе на віз — гравець кермує. «Готово» — додому, розпрягти коня.
	var parts := _garden_parts()
	var m = parts[0]
	var cart = parts[1]
	var h = parts[2]
	if cart == null or h == null:
		say("Ех, коня чи воза в нас нема…", 2.5)
		return
	var id := begin_job("garden")
	say("Піду запрягати коня!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _ready_plow_and_horse(id, cart, h, parts[3], false):
		return
	say("Ну, онучку, кермуй конем! Я — пасажиром.", 2.5)
	cart.start_manual()
	m.vehicle_control_start("garden_cart", cart)
	while id == job and m._ctl_veh == cart:
		await get_tree().process_frame
	m.vehicle_control_stop()
	await _home_and_unload(id, cart, null)


func garden_plow_job() -> void:
	## Покласти плуг на віз або зняти з воза й поставити біля садка.
	var parts := _garden_parts()
	var cart = parts[1]
	var plow = parts[3]
	if cart == null or plow == null:
		say("Ех, плуга в нас нема…", 2.5)
		return
	var to_cart: bool = plow.state != "cart"
	var id := begin_job("garden")
	say("Покладу плуга на віз!" if to_cart else "Зніму плуга з воза!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if plow.state == "horse":
		plow.unhitch()
	await go(Vector3(25.2, 0, 19.2))
	if not await _carry_plow(id, plow, plow.bed_xf(cart) if to_cart else plow.rest_xf()):
		return
	if to_cart:
		plow.put_in_cart(cart)
	else:
		plow.put_down()
	say("Готово — плуг на возі!" if to_cart else "Хай плуг постоїть біля садка.", 2.5)
	await _walk_from_garden(id)


func garden_field_job() -> void:
	## Плуг — на віз, запрягти коня, на поле. Там: злізти, зняти плуг, відпрягти коня й підвести до плуга,
	## зачепити, взятися ззаду за чепіги й орати. Потім: відчепити, плуг — на віз, запрягти, додому,
	## плуг — на місце, коня — розпрягти.
	var parts := _garden_parts()
	var m = parts[0]
	var cart = parts[1]
	var h = parts[2]
	var plow = parts[3]
	if cart == null or plow == null or h == null:
		say("Ех, коня чи плуга в нас нема…", 2.5)
		return
	var f: Rect2 = m.world.outer.PLOW_FIELD
	var id := begin_job("garden")
	say("Поїду орати поле конем!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _ready_plow_and_horse(id, cart, h, plow, true):
		return
	say("Но-о, коню! Гайда на поле!", 2.5)
	for wp in GARDEN_TO_FIELD:
		await cart._horse_to(wp, 2.6, 1.0)
	cart.speed = 0.0
	h.hitch_move(h.rotation.y, 0.0, 0.0)
	await _cart_climb_off(cart)
	if id != job:
		return
	cart.drop_shafts()
	# плуг — з воза на край поля
	say("Знімаю плуга.", 2.0)
	var start := Transform3D(Basis(Vector3.UP, PI), Vector3(f.position.x + 1.0, 0, f.end.y + 1.4))
	if not await _carry_plow(id, plow, plow.side_xf(cart)):
		return
	if not await _carry_plow(id, plow, start):
		return
	plow.put_down()
	# коня — з оглобель до плуга
	say("Ходи, коню, до плуга.", 2.0)
	var way := [h.to_global(Vector3(0, 0, 2.0)), plow.to_global(Vector3(-2.2, 0, plow.HALF + plow.TRACE - 0.6)),
		plow.to_global(Vector3(0, 0, plow.HALF + plow.TRACE))]
	if not await _lead_horse(id, h, way):
		return
	await _turn_horse(h, plow.rotation.y)
	_release_lead()
	if id != job:
		return
	await go(plow.to_global(Vector3(-0.6, 0, plow.HALF + 0.4)))
	if id != job:
		return
	_face_to = atan2(plow.global_position.x - global_position.x, plow.global_position.z - global_position.z)
	play("wave", 1.0)
	await wait(1.0)
	plow.hitch_horse(h)
	# оранка: дідусь іде позаду, тримається за чепіги
	if not await _take_plow(id, plow):
		_garden_abort()
		return
	say("Оремо!", 1.5)
	await cart.plow_field(f, func(): return id == job)
	if id != job:
		_garden_abort()
		return
	say("Ото гарно зорали конем!", 2.5)
	Game.emit_event("plowed")
	# з плугом — назад до воза
	await cart._horse_to(cart.to_global(Vector3(3.2, 0, 2.0)), 1.2, 0.6)
	cart.speed = 0.0
	h.hitch_move(h.rotation.y, 0.0, 0.0)
	behind_plow = null
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	if id != job:
		return
	await go(plow.to_global(Vector3(-0.6, 0, plow.HALF + 0.4)))
	if id != job:
		return
	play("wave", 1.0)
	await wait(1.0)
	plow.unhitch()
	say("Плуга — на віз.", 2.0)
	if not await _carry_plow(id, plow, plow.bed_xf(cart)):
		return
	plow.put_in_cart(cart)
	if not await _harness_horse(id, cart, h):
		return
	if not await _to_climb_spot(id, cart):
		return
	await _cart_climb_on(cart)
	await _home_and_unload(id, cart, plow)


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


# ------------------------------------------------------------------ «Іду почитаю»
func read_job() -> void:
	## У хату, у крісло — і за книжку.
	if at_home and seated == "armchair" and doing != "sleep" and not lying:
		say("Я вже читаю, онучку!", 2.0)
		return
	say("Піду почитаю книжку.", 2.5)
	bed_now = false
	cancel_job()
	if seated != "":
		var id0 := begin_job("stand")
		await stand_up()
		end_job(id0)
	if lying:
		_wake_reset()
	var id := begin_job("home")
	if not at_home:
		if not await _walk_in(id):
			return
	end_job(id)
	sit_job("armchair", 90.0)


# ------------------------------------------------------------------ поїздки возом від садка (меню дідуся)
const TRIP_BOUNDS := Rect2(-235.0, -140.0, 385.0, 350.0)
const CART_SLOTS := [Vector3(0.25, 0.56, -0.45), Vector3(-0.25, 0.56, -0.5), Vector3(0.22, 0.56, -1.0), Vector3(-0.22, 0.56, -1.0)]
const ROD_IN_CART := Vector3(0.45, 0.62, 0.3)
const ROD_LEN := 2.4
const SHOP_GEAR := {"rod": Vector3(-17.1, 0, 0.05), "stool": Vector3(-16.4, 0, -0.35), "bucket": Vector3(-15.8, 0, -0.4)}
const SHOP_STAND := Vector3(-15.2, 0, -1.1)              # де стати в майстерні, щоб узяти вудку, стільчик, відро
const BARN_SACKS := Vector3(-14.7, 0, -9.6)              # мішки з пшеницею в сараї, біля дверей
const BARN_REACH := Vector3(-15.0, 0, -8.5)
const GATE_STOP := Vector3(-6.0, 0, 9.2)                 # віз перед подвір'ям, кінь — на захід від воріт
# від стоянки — в обхід садка: на південь уздовж садка, дорогою на захід до сільської дороги
const OUT_SOUTH := [Vector3(23.3, 0, 11.0), Vector3(26.6, 0, 13.0), Vector3(26.8, 0, 22.0), Vector3(25.5, 0, 30.5),
	Vector3(12.0, 0, 32.5), Vector3(3.0, 0, 31.0)]
const GATE_WAY := [Vector3(2.0, 0, 20.0), Vector3(1.8, 0, 12.5)]       # сільською дорогою на північ — до подвір'я
const HOME_SOUTH := [Vector3(12.0, 0, 32.5), Vector3(25.5, 0, 30.5)]    # назад — тією ж дорогою за садком
const FROM_SOUTH := [Vector3(25.8, 0, 26.0), Vector3(23.4, 0, 22.8)]    # заїзд на стоянку з півдня
const TO_EAST := [Vector3(23.3, 0, 8.0), Vector3(26.0, 0, 5.6)]
const VILLAGE_DOWN := [Vector3(5.5, 0, 50.0), Vector3(5.5, 0, 68.0), Vector3(2.2, 0, 82.0)]
const VILLAGE_UP := [Vector3(5.5, 0, 68.0), Vector3(5.5, 0, 50.0), Vector3(3.0, 0, 36.0), Vector3(12.0, 0, 32.5), Vector3(25.5, 0, 30.5)]
const POND_ROAD_HOME := [Vector3(-2.0, 0, 29.5), Vector3(3.0, 0, 32.0), Vector3(12.0, 0, 32.5), Vector3(25.5, 0, 30.5)]
const NORTH_HOME := [Vector3(-160.0, 0, 9.5), Vector3(-120.0, 0, 9.5), Vector3(-45.0, 0, 10.0), Vector3(-24.0, 0, 9.8),
	Vector3(-6.0, 0, 11.5), Vector3(1.5, 0, 20.0), Vector3(3.0, 0, 31.0), Vector3(12.0, 0, 32.5), Vector3(25.5, 0, 30.5)]
const FARM_HAY_STOP := Vector3(-172.0, 0, 34.0)
const SHOP_ASK := {"bread": "Дайте паляницю й булочок!", "sausage": "Мені кільце ковбаски, будь ласка!", "fruit": "І яблучок для онуків!"}
const SHOP_COL := {"bread": Color(0.85, 0.62, 0.3), "sausage": Color(0.6, 0.2, 0.15), "fruit": Color(0.85, 0.15, 0.1)}

var _trip := ""
var _cargo: Array = []         # що лежить на возі
var _carry: Array = []         # що несе в'язкою: перше — в руці, решта — зверху
var _gear := {}                # вудка, стільчик, відро (живуть у майстерні)
var _rod_hand := false         # вудка в руці (ловить рибу)
var _rod_lift := 0.0
var _line: MeshInstance3D
var _bobber: Node3D
var _bob_dip := 0.0
var _seed_fx: CPUParticles3D


func _make_trip_props() -> void:
	## Вудка, стільчик і відро — у майстерні; мішки з пшеницею — у сараї.
	var root: Node3D = world.yard_root
	var wood := Util.mat(Color(0.5, 0.36, 0.22), 0.9)
	var rod := Node3D.new()
	rod.name = "FishingRod"
	rod.add_child(Util.cyl(0.006, 0.014, ROD_LEN, Util.mat(Color(0.55, 0.42, 0.25), 0.6), Vector3(0, ROD_LEN / 2.0, 0)))
	rod.add_child(Util.cyl(0.035, 0.035, 0.03, Util.mat(Color(0.25, 0.25, 0.28), 0.4, 0.6), Vector3(0.03, 0.35, 0), Vector3(0, 0, PI / 2.0)))
	root.add_child(rod)
	rod.position = SHOP_GEAR["rod"]
	rod.basis = Basis(Vector3.RIGHT, 0.12)
	var stool := Node3D.new()
	stool.name = "FishStool"
	root.add_child(stool)
	if Models.spawn(stool, "stool", 0.3) == null:
		stool.add_child(Util.cyl(0.16, 0.16, 0.04, wood, Vector3(0, 0.32, 0)))
		for i in 3:
			var a := TAU * i / 3.0
			stool.add_child(Util.cyl(0.018, 0.022, 0.31, wood, Vector3(cos(a) * 0.11, 0.155, sin(a) * 0.11)))
	stool.position = SHOP_GEAR["stool"]
	var bucket := _bucket()
	root.add_child(bucket)
	bucket.position = SHOP_GEAR["bucket"]
	_gear = {"rod": rod, "stool": stool, "bucket": bucket}
	for k in _gear:
		var o: Node3D = _gear[k]
		remember_home(o)
		o.set_meta("to", "workshop")
	for i in 3:
		var sk := _sack("wheat")
		root.add_child(sk)
		sk.position = BARN_SACKS + (Vector3(0, 0, -0.45 * i) if i < 2 else Vector3(0.05, 0.5, -0.22))
		sk.rotation.y = 0.4 * i


func _bucket() -> Node3D:
	var b := Node3D.new()
	b.name = "Bucket"
	var zinc := Util.mat(Color(0.62, 0.64, 0.66), 0.35, 0.7)
	b.add_child(Util.cyl(0.15, 0.12, 0.3, zinc, Vector3(0, 0.15, 0)))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.14
	tm.outer_radius = 0.152
	tm.rings = 14
	tm.ring_segments = 4
	var hd := MeshInstance3D.new()
	hd.mesh = tm
	hd.material_override = zinc
	hd.rotation_degrees = Vector3(90, 0, 0)
	hd.position = Vector3(0, 0.3, 0)
	b.add_child(hd)
	var fill := Node3D.new()
	fill.name = "fill"
	b.add_child(fill)
	return b


func _sack(kind: String) -> Node3D:
	## Мішок: "wheat" — з пшеницею, "flour" — з борошном, "empty" — порожній.
	var sk := Node3D.new()
	sk.name = "Sack"
	var m := Util.mat(Color(0.93, 0.92, 0.88) if kind == "flour" else Color(0.72, 0.6, 0.4), 0.95)
	if kind == "empty":
		sk.add_child(Util.sphere(0.24, m, Vector3(0, 0.05, 0), Vector3(1.15, 0.22, 0.8)))
	else:
		sk.add_child(Util.sphere(0.22, m, Vector3(0, 0.3, 0), Vector3(1.0, 1.4, 0.8)))
		sk.add_child(Util.cyl(0.04, 0.07, 0.12, m, Vector3(0, 0.62, 0)))
		sk.add_child(Util.cyl(0.045, 0.045, 0.025, Util.mat(Color(0.4, 0.3, 0.18), 0.9), Vector3(0, 0.6, 0)))
	sk.set_meta("to", "barn")
	sk.set_meta("kind", "sack")
	return sk


func _hay() -> Node3D:
	var hy := Node3D.new()
	hy.name = "Hay"
	hy.add_child(Util.sphere(0.36, Util.mat(Color(0.86, 0.74, 0.38), 0.95), Vector3(0, 0.2, 0), Vector3(1.3, 0.6, 0.95)))
	hy.set_meta("to", "barn")
	return hy


# ---------------- речі: на віз, з воза, у руки, на місце
func _cart_side(cart: Node3D) -> Vector3:
	return cart.to_global(Vector3(-1.05, 0, -0.7))


func _hold_carry(items: Array) -> void:
	## Бере кілька речей в'язкою: перша — в руці, решта — зверху на ній (вудка — збоку).
	var list := items.duplicate()
	var rod = _gear.get("rod")
	if rod != null and rod in list and list.size() > 1:
		list.erase(rod)
		list.append(rod)
	_carry = list
	if list.is_empty():
		return
	var root: Node3D = list[0]
	for i in range(1, list.size()):
		var o: Node3D = list[i]
		if o.get_parent():
			o.get_parent().remove_child(o)
		root.add_child(o)
		if o == rod:
			o.transform = Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0.12, 0.05, 0))
		else:
			o.transform = Transform3D(Basis(), Vector3(0, 0.3 * i, 0))
	hold_upright(root, 0.3, false, 0.1)


func _drop_carry() -> Array:
	## Опускає з рук усю в'язку; повертає речі (вже без батьків).
	var items := _carry.duplicate()
	_carry.clear()
	drop()
	for o in items:
		if is_instance_valid(o) and o.get_parent():
			o.get_parent().remove_child(o)
	return items


func _store(o) -> void:
	## Річ — на своє місце (вудка, стільчик, відро — у майстерню), решта — прибрати.
	if o == null or not is_instance_valid(o):
		return
	if o.get_parent():
		o.get_parent().remove_child(o)
	var home: Node = o.get_meta("home_parent", null)
	if home and is_instance_valid(home):
		home.add_child(o)
		o.transform = o.get_meta("home_tr", Transform3D())
		o.set_meta("to", "workshop")
		var fill: Node = o.get_node_or_null("fill")
		if fill:
			for c in fill.get_children():
				c.queue_free()
	else:
		o.queue_free()


func _put_in_cart(id: int, cart: Node3D) -> bool:
	## Кладе на віз усе, що несе.
	if _carry.is_empty():
		return id == job
	await go(_cart_side(cart))
	if id != job:
		return false
	face(cart.to_global(Vector3(0, 0, -0.7)))
	await wait(0.35)
	play("pick")
	await wait(0.8)
	for o in _drop_carry():
		cart.add_child(o)
		if o == _gear.get("rod"):
			o.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), ROD_IN_CART)
		else:
			var slot: Vector3 = CART_SLOTS[_cargo.size() % CART_SLOTS.size()]
			o.transform = Transform3D(Basis(Vector3.UP, randf_range(-0.4, 0.4)), slot)
		_cargo.append(o)
	play("idle")
	return id == job


func _take_from_cart(id: int, cart: Node3D, items: Array) -> bool:
	await go(_cart_side(cart))
	if id != job:
		return false
	face(cart.to_global(Vector3(0, 0, -0.7)))
	await wait(0.35)
	play("pick")
	await wait(0.8)
	if id != job:
		return false
	for o in items:
		_cargo.erase(o)
	_hold_carry(items)
	play("idle")
	await wait(0.3)
	return id == job


func _cargo_kind(k: String) -> Node3D:
	for o in _cargo:
		if is_instance_valid(o) and String(o.get_meta("kind", "")) == k:
			return o
	return null


func _deliver(id: int) -> void:
	## Удома: мішки й солому — у сарай, вудку, стільчик і відро — у майстерню, кошик — на ґанок.
	for dest in ["barn", "workshop", "granny", "porch"]:
		var here: Array = []
		for o in _carry:
			if is_instance_valid(o) and String(o.get_meta("to", "porch")) == dest:
				here.append(o)
		if here.is_empty():
			continue
		if dest == "granny":
			await _give_granny(id)
			if id != job:
				return
			continue
		var p: Vector3 = spots["barn"] if dest == "barn" else (SHOP_STAND if dest == "workshop" else spots["porch"] + Vector3(0.6, 0, 0.7))
		await go(p)
		if id != job:
			return
		play("pick")
		await wait(0.8)
		var rest: Array = []
		for o in _drop_carry():
			if o in here:
				_store(o)
			else:
				rest.append(o)
		play("idle")
		if not rest.is_empty():
			_hold_carry(rest)
		await wait(0.3)
	say("Ось і вдома!", 2.0)


func _give_granny(id: int) -> void:
	## Відро з рибою — бабусі Галі (якщо її нема на подвір'ї чи руки зайняті — лишає на ґанку).
	var gr = _main().granny
	var bucket: Node3D = _gear.get("bucket")
	var ok: bool = gr != null and is_instance_valid(gr) and gr.visible and not bool(gr.get("outside")) \
		and not bool(gr.get("in_house")) and gr.held == null
	if ok:
		for i in 4:
			var to: Vector3 = (gr as Node3D).global_position
			var dir := global_position - to
			dir.y = 0.0
			if dir.length() < 1.6:
				break
			await go(to + dir.normalized() * 1.1)
			if id != job:
				return
		ok = is_instance_valid(gr) and gr.visible and gr.held == null
	if not ok:
		await go(spots["porch"] + Vector3(0.6, 0, 0.7))
		if id != job:
			return
	if ok:
		face((gr as Node3D).global_position)
		gr.face(global_position)
		say("Галю, ось рибка — звари юшки!", 3.0)
	else:
		say("Галю, рибку на ґанку лишаю — на юшку!", 3.0)
	play("pick")
	await wait(0.8)
	var items := _drop_carry()
	play("idle")
	for o in items:
		if o != bucket or not ok:
			_store(o)
	if ok:
		gr.hold_upright(bucket, 0.3, false, 0.1)
		await wait(1.0)
		if is_instance_valid(gr):
			gr.say("Ой, дякую, діду! Буде юшка!", 3.0)
		_bucket_back_later(gr, bucket)
	await wait(0.5)


func _bucket_back_later(gr, bucket: Node3D) -> void:
	## Бабуся забрала рибу — порожнє відро знову в майстерні.
	await get_tree().create_timer(6.0).timeout
	if not is_instance_valid(bucket) or bucket in _carry or bucket in _cargo or _rod_hand:
		return
	if gr != null and is_instance_valid(gr) and gr.held == bucket:
		gr.drop()
	_store(bucket)


# ---------------- віз: сісти, злізти, їхати, розпрягти й запрягти в дорозі
func _hitch_and_mount(id: int, cart: Node3D, h: Node3D) -> bool:
	if not cart.hitched:
		if not await _harness_horse(id, cart, h):
			return false
	if not await _to_climb_spot(id, cart):
		return false
	await _cart_climb_on(cart)
	bounds = TRIP_BOUNDS
	extra_obs = Obstacles.outer
	return id == job


func _get_off(id: int, cart: Node3D) -> bool:
	cart.speed = 0.0
	var h: Node3D = cart.horse
	if h:
		h.hitch_move(h.rotation.y, 0.0, 0.0)
	await _cart_climb_off(cart)
	bounds = TRIP_BOUNDS
	extra_obs = Obstacles.outer
	return id == job


func _unhitch_here(id: int, cart: Node3D) -> bool:
	## Розпрягає коня там, де став віз; кінь стоїть поруч і чекає.
	var h: Node3D = cart.horse
	if h == null or not cart.hitched:
		return id == job
	say("Тпру! Розпряжу — відпочинь, коню.", 2.0)
	if h.to_local(global_position).x < 0.0:
		await go(h.to_global(Vector3(0, 0, 2.6)))
	await go(h.to_global(LEAD_AT))
	if id != job:
		return false
	_face_to = h.rotation.y
	play("wave", 1.0)
	await wait(1.0)
	if id != job:
		return false
	cart.drop_shafts()
	h.show_harness(false)
	cart.harness_to_cart()
	if not await _lead_horse(id, h, [h.to_global(Vector3(0, 0, 2.2)), cart.to_global(Vector3(-3.4, 0, 1.6))]):
		return false
	_release_lead()
	return id == job


func _horse_go(id: int, cart: Node3D, p: Vector3, v: float, reach: float, steer: bool) -> bool:
	## Кінь із возом іде до точки (на пагорбі — по схилу).
	var h: Node3D = cart.horse
	var t := 0.0
	while t < 70.0:
		if id != job or h == null or not is_instance_valid(h) or cart.horse != h:
			cart.speed = 0.0
			return false
		var dt := get_process_delta_time()
		t += dt
		var hp: Vector3 = h.global_position
		if Vector2(p.x - hp.x, p.z - hp.z).length() < reach:
			break
		var tgt: Vector3 = Vehicles.steer_target(hp, p, 2.0) if steer else p
		var to := tgt - hp
		to.y = 0.0
		var hd := lerp_angle(h.rotation.y, atan2(to.x, to.z), 1.0 - exp(-dt * 2.2))
		var sp := minf(v, maxf(0.5, to.length() * 1.2))
		cart.speed = move_toward(cart.speed, sp, dt * 1.5)
		h.hitch_move(hd, cart.speed, dt)
		Vehicles.avoid_people(h)
		if steer:
			# не в'їжджаємо в дерева, хати, паркани, ставок: виштовхуємо точку між конем і возом
			var mid: Vector3 = h.global_position - Vector3(sin(h.rotation.y), 0, cos(h.rotation.y)) * 0.9
			var mid2 := Vehicles.keep_out(mid, 1.3, cart.global_position)
			mid2.y = mid.y
			if mid2.distance_to(mid) > 0.001:
				h.global_position += mid2 - mid
				cart.speed = move_toward(cart.speed, 0.6, dt * 3.0)
			# і віз позаду — щоб не зачепив дерево чи хату на повороті
			var c0: Vector3 = cart.global_position
			var c2 := Vehicles.keep_out(c0, 1.0, c0)
			c2.y = c0.y
			if c2.distance_to(c0) > 0.001:
				h.global_position += (c2 - c0) * 0.5
		h.global_position.y = Util.hill_y(h.global_position) if Util.on_hill(h.global_position) else 0.0
		await get_tree().process_frame
	return id == job


func _drive(id: int, cart: Node3D, way: Array, v := 2.6) -> bool:
	for wp in way:
		if not await _horse_go(id, cart, wp, v, 1.3, true):
			return false
	cart.speed = 0.0
	var h: Node3D = cart.horse
	if h:
		h.hitch_move(h.rotation.y, 0.0, 0.0)
	return id == job


func _park_home(id: int, cart: Node3D) -> bool:
	## Під садок, на стоянку (оглоблями на північ).
	var h0: Node3D = cart.horse
	if not await _drive(id, cart, FROM_SOUTH if h0 and h0.global_position.z > 18.0 else GARDEN_LOOP, 2.2):
		return false
	var hp: Vector3 = cart.hitch_pos()
	if not await _horse_go(id, cart, hp, 1.3, 0.4, false):
		return false
	var h: Node3D = cart.horse
	var t := 0.0
	while t < 0.8 and h and id == job:
		t += get_process_delta_time()
		h.global_position = h.global_position.lerp(hp, 0.15)
		h.rotation.y = lerp_angle(h.rotation.y, cart.park_yaw, 0.15)
		await get_tree().process_frame
	cart.speed = 0.0
	return id == job


func _trip_home(id: int, cart: Node3D, way: Array) -> void:
	## Додому: стоянка під садком, злізти, розпрягти, забрати з воза привезене й рознести.
	say("Но-о, коню! Додому!", 2.5)
	if not await _drive(id, cart, way):
		return
	if not await _park_home(id, cart):
		return
	if not await _get_off(id, cart):
		return
	if not await _unharness_horse(id, cart):
		return
	if not _cargo.is_empty():
		if not await _take_from_cart(id, cart, _cargo.duplicate()):
			return
	bounds = FOREST_BOUNDS
	for k in range(GARDEN_WALK.size() - 1, -1, -1):
		await go(GARDEN_WALK[k])
		if id != job:
			return
	if not await _come_back(id):
		return
	await _deliver(id)
	if id != job:
		return
	_trip = ""
	end_job(id)


func _yard_out(id: int) -> bool:
	await go(spots["inside_gate"] + Vector3(0.2, 0, 0))
	if id != job:
		return false
	await world.pass_gate(self, true)
	bounds = TRIP_BOUNDS
	extra_obs = Obstacles.outer
	return id == job


func _fetch_from_yard(id: int, what: String) -> bool:
	## Від воза біля воріт — у двір: мішок пшениці із сараю чи відро з майстерні — і знову за ворота.
	if not await _come_back(id):
		return false
	if what == "sack":
		await go(spots["barn"])
		if id != job:
			return false
		await go(BARN_REACH, false, false)
		if id != job:
			return false
		face(BARN_SACKS)
		await wait(0.4)
		play("pick")
		await wait(0.9)
		_hold_carry([_sack("wheat")])
	else:
		await go(SHOP_STAND)
		if id != job:
			return false
		face(SHOP_GEAR["bucket"])
		await wait(0.4)
		play("pick")
		await wait(0.9)
		_hold_carry([_gear["bucket"]])
	play("idle")
	if id != job:
		return false
	return await _yard_out(id)


func _trip_setup(id: int) -> bool:
	if seated != "":
		await stand_up()
	if lying:
		_wake_reset()
	if at_home:
		if not await _walk_out(id):
			return false
	return id == job


func _trip_abort() -> void:
	## Поїздку перервали: віз і кінь — під садок, речі — на місце, дідусь — на подвір'я.
	_trip = ""
	granny_ride = ""
	_rod_hand = false
	_rod_lift = 0.0
	if _line:
		_line.visible = false
	if _bobber:
		_bobber.visible = false
	_sowing = false
	if _seed_fx:
		_seed_fx.emitting = false
	var m := _main()
	var cart: Node3D = m.garden_cart
	var h: Node3D = m.garden_horse
	_climbing = false
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	if cart and on_tractor == cart:
		on_tractor = null
		seated = ""
		global_position = cart.to_global(Vector3(-1.0, 0, 0))
		global_position.y = 0.0
		model.position = Vector3(0, _base_y, 0)
	elif seated == "stool":
		seated = ""
		_seat_dy = 0.0
		current = ""
		model.position = Vector3(0, _base_y, 0)
		if ap:
			ap.speed_scale = 1.0
	for o in _drop_carry() + _cargo:
		_store(o)
	_cargo.clear()
	for k in _gear:
		_store(_gear[k])
	if cart:
		cart.unhitch()
	if h:
		if h.mode == "hitched":
			h.hitch_release()
		h.global_position = GARDEN_PADDOCK
		h.rotation.y = 0.0
		h._target = h.position
	if not at_home and not YARD_BOUNDS.grow(0.5).has_point(Vector2(global_position.x, global_position.z)):
		position = spots["inside_gate"]
		bounds = YARD_BOUNDS
		extra_obs = []


func trip_job(kind: String) -> void:
	## Поїздки возом: "mush" — по гриби, "market" — на ринок, "fish" — на рибу, "mill" — у млин,
	## "sow" — сіяти пшеницю, "farm" — на ферму.
	var m := _main()
	var cart: Node3D = m.garden_cart
	var h: Node3D = m.garden_horse
	if cart == null or h == null:
		say("Ех, коня чи воза в нас нема…", 2.5)
		return
	var id := begin_job("trip")
	_trip = kind
	if not await _trip_setup(id):
		return
	match kind:
		"mush":
			await _mush_trip(id, cart, h)
		"market":
			await _market_trip(id, m, cart, h)
		"fish":
			await _fish_trip(id, cart, h)
		"mill":
			await _mill_trip(id, cart, h)
		"sow":
			await _sow_trip(id, m, cart, h)
		"farm":
			await _farm_trip(id, m, cart, h)


# ---------------- з бабусею (її меню): запрягти, під'їхати до воріт, бабуся сідає — і на ринок чи в ліс
const GATE_LOOP := [Vector3(-10.0, 0, 10.6), Vector3(-7.0, 0, 13.6), Vector3(-1.5, 0, 14.5)]     # від воріт — розворот на дорозі
# від воріт — розворот і сільською дорогою на південь, в обхід садка (повз садок біля тину віз застрягає)
const GATE_BACK := [Vector3(-10.0, 0, 10.6), Vector3(-7.0, 0, 13.6), Vector3(-1.5, 0, 14.5), Vector3(2.0, 0, 20.0),
	Vector3(3.0, 0, 31.0), Vector3(12.0, 0, 32.5), Vector3(25.5, 0, 30.5)]
const AROUND_ORCHARD := [Vector3(26.8, 0, 22.0), Vector3(26.8, 0, 13.0), Vector3(30.0, 0, 5.5)]   # далі — за садком на схід
const MUSHROOMS := ["borovyk", "lysychky", "pidberezovyk", "openky", "syroizhky", "pidosykovyk", "maslyuk", "ryzhyk"]
var granny_ride := ""          # етап поїздки з бабусею: prep, board, ride, there, back, ride_home, home ("" — немає)


func granny_trip(kind: String) -> void:
	var m := _main()
	var cart: Node3D = m.garden_cart
	var h: Node3D = m.garden_horse
	var g = m.granny
	if cart == null or h == null or g == null:
		say("Ех, коня чи воза в нас нема…", 2.5)
		return
	var id := begin_job("trip")
	_trip = "granny"
	granny_ride = "prep"
	if not await _trip_setup(id):
		return
	say("Зараз запряжу коня — і поїдемо, бабо!", 2.5)
	var basket: Node3D = null
	if kind == "forest":
		basket = Util.basket()
		basket.set_meta("to", "porch")
		_hold_carry([basket])
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if basket and not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	if not await _drive(id, cart, OUT_SOUTH + GATE_WAY + [GATE_STOP]):
		return
	granny_ride = "board"
	say("Тпру! Сідай, бабо, поїхали!", 2.5)
	if not await _wait_granny(id, g, true):
		return
	granny_ride = "ride"
	if kind == "market":
		say("Но-о! На ринок!", 2.0)
		if not await _drive(id, cart, GATE_LOOP + [Vector3(2.0, 0, 20.0), Vector3(3.0, 0, 31.0)] + VILLAGE_DOWN + [Vector3(1.6, 0, 90.0)]):
			return
		granny_ride = "there"
		if not await _get_off(id, cart):
			return
		say("Далі — пішки, через місток.", 2.5)
		for wp in [Vector3(-0.6, 0, 96.5), Vector3(-0.6, 0, 110.0), Vector3(-1.5, 0, 148.0)]:
			await go(wp)
			if id != job:
				return
		var bz = m.world.outer.bazaar
		if bz:
			for s in bz.sellers:
				if String(s.get("shop", "")) == "tools" and s.has("front"):
					await go(s["front"])
					if id != job:
						return
					face((s["node"] as Node3D).global_position)
					say("Почім, куме, сокири? Подивлюся, поки баба купує.", 3.0)
					break
		var t := 0.0
		while id == job and not g.trip_done and g.doing == "trip" and t < 240.0:
			await wait(1.0)
			t += 1.0
		if id != job:
			return
		say("Ходімо, бабо, до воза.", 2.0)
		for wp in [Vector3(-0.6, 0, 110.0), Vector3(-0.6, 0, 96.5)]:
			await go(wp)
			if id != job:
				return
		if not await _hitch_and_mount(id, cart, h):
			return
		granny_ride = "back"
		if not await _wait_granny(id, g, true):
			return
		granny_ride = "ride_home"
		say("Но-о, коню! Додому!", 2.0)
		if not await _drive(id, cart, [Vector3(-5.0, 0, 93.5), Vector3(-7.0, 0, 88.0), Vector3(-2.0, 0, 82.0), Vector3(5.5, 0, 68.0),
				Vector3(5.5, 0, 50.0), Vector3(3.0, 0, 36.0)] + GATE_WAY + [GATE_STOP]):
			return
	else:
		say("Гайда в ліс!", 2.0)
		if not await _drive(id, cart, GATE_BACK + AROUND_ORCHARD + [Vector3(71.0, 0, 5.0), Vector3(100.0, 0, 5.5), Vector3(110.0, 0, 1.5)]):
			return
		granny_ride = "there"
		if not await _get_off(id, cart):
			return
		if not await _unhitch_here(id, cart):
			return
		if not await _take_from_cart(id, cart, [basket]):
			return
		var end: Vector3 = FOREST_WAY[FOREST_WAY.size() - 1]
		await go(FOREST_WAY[6])
		if id != job:
			return
		var got := 0
		if forest and forest.has_method("nearest_kinds"):
			for it in forest.nearest_kinds(end, 6, MUSHROOMS):
				await go(forest.goods_pos(it) + Vector3(0.5, 0, 0.5))
				if id != job:
					return
				face(forest.goods_pos(it))
				play("pick")
				await wait(0.9)
				if id != job:
					return
				var n: int = forest.take(it)
				got += n
				if n > 0:
					Util.basket_add(basket, forest.kind_color(it), 0.05)
				play("idle")
		say("Назбирав %d грибочків!" % got if got > 0 else "Сьогодні гриби вже позбирали…", 3.0)
		if got > 0:
			Game.emit_event("forest")
		await go(FOREST_WAY[6])
		if id != job:
			return
		if not await _put_in_cart(id, cart):
			return
		if not await _hitch_and_mount(id, cart, h):
			return
		granny_ride = "back"
		if not await _wait_granny(id, g, true):
			return
		granny_ride = "ride_home"
		say("Но-о, коню! Додому!", 2.0)
		# повз подвір'я з боку садка віз не проїде (тин близько) — додому, як із млина: за садком і сільською дорогою
		if not await _drive(id, cart, [Vector3(100.0, 0, 5.5), Vector3(71.0, 0, 5.0), Vector3(30.0, 0, 5.5), Vector3(26.8, 0, 13.0)]
				+ OUT_SOUTH.slice(2) + GATE_WAY + [GATE_STOP]):
			return
	granny_ride = "home"
	say("Тпру! Злазь, бабо, приїхали.", 2.5)
	if not await _wait_granny(id, g, false):
		return
	granny_ride = ""
	await _trip_home(id, cart, GATE_BACK)


func _wait_granny(id: int, g, on: bool) -> bool:
	## Чекає, поки бабуся сяде на віз (on) чи злізе з нього. Передумала їхати — дід їде сам.
	var t := 0.0
	while id == job and t < 150.0:
		if (g.on_tractor != null) == on or g.doing != "trip":
			break
		await wait(0.5)
		t += 0.5
	return id == job


# ---------------- по гриби
func _mush_trip(id: int, cart: Node3D, h: Node3D) -> void:
	if forest == null:
		say("Ліс далеко, а грибів нема…", 2.5)
		_trip = ""
		end_job(id)
		return
	say("Візьму кошика й поїду конем у ліс по гриби!", 3.0)
	var basket := Util.basket()
	basket.set_meta("to", "porch")
	_hold_carry([basket])
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	say("Гайда в ліс!", 2.0)
	if not await _drive(id, cart, TO_EAST + [Vector3(71.0, 0, 5.0), Vector3(100.0, 0, 5.5), Vector3(110.0, 0, 1.5)]):
		return
	if not await _get_off(id, cart):
		return
	if not await _unhitch_here(id, cart):
		return
	if not await _take_from_cart(id, cart, [basket]):
		return
	var end: Vector3 = FOREST_WAY[FOREST_WAY.size() - 1]
	for wp in [FOREST_WAY[6], end]:
		await go(wp)
		if id != job:
			return
	var got := 0
	for it in forest.nearest_goods(end, 6):
		await go(forest.goods_pos(it) + Vector3(0.5, 0, 0.5))
		if id != job:
			return
		face(forest.goods_pos(it))
		play("pick")
		await wait(0.9)
		if id != job:
			return
		var col: Color = forest.kind_color(it)
		var n: int = forest.take(it)
		got += n
		if n > 0:
			Util.basket_add(basket, col, 0.05)
		play("idle")
	say("Назбирав %d — буде на вечерю!" % got if got > 0 else "Сьогодні все вже позбирали…", 3.0)
	if got > 0:
		Game.emit_event("forest")
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	await _trip_home(id, cart, [Vector3(104.0, 0, 9.0), Vector3(100.0, 0, 5.5), Vector3(71.0, 0, 5.0), Vector3(30.0, 0, 5.5)])


# ---------------- на ринок
func _market_trip(id: int, m: Node, cart: Node3D, h: Node3D) -> void:
	say("Поїду на ринок, куплю чогось смачненького!", 3.0)
	var basket := Util.basket()
	basket.set_meta("to", "porch")
	_hold_carry([basket])
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	if not await _drive(id, cart, OUT_SOUTH + VILLAGE_DOWN + [Vector3(1.6, 0, 90.0)]):
		return
	if not await _get_off(id, cart):
		return
	if not await _take_from_cart(id, cart, [basket]):
		return
	for wp in [Vector3(0, 0, 96.5), Vector3(0, 0, 110.0), Vector3(0, 0, 160.0)]:
		await go(wp)
		if id != job:
			return
	var bz = m.world.outer.bazaar
	var bought := 0
	if bz:
		for shop in ["bread", "sausage", "fruit"]:
			var sd: Dictionary = {}
			for s in bz.sellers:
				if String(s.get("shop", "")) == shop and s.has("front"):
					sd = s
					break
			if sd.is_empty():
				continue
			await go(sd["front"])
			if id != job:
				return
			face((sd["node"] as Node3D).global_position)
			say(SHOP_ASK[shop], 2.5)
			await wait(1.6)
			bz.seller_say(sd["node"], "Прошу, діду Петре! Смачного!")
			bz.seller_give(sd)
			await wait(1.0)
			for i in 4:
				Util.basket_add(basket, SHOP_COL[shop], 0.045)
			bought += 1
			say("Дякую, будьте здорові!", 1.8)
			await wait(1.4)
			if id != job:
				return
	say("Повний кошик гостинців!" if bought > 0 else "Щось ринок сьогодні порожній…", 2.5)
	for wp in [Vector3(0, 0, 160.0), Vector3(0, 0, 110.0), Vector3(0, 0, 96.5)]:
		await go(wp)
		if id != job:
			return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	await _trip_home(id, cart, [Vector3(-5.0, 0, 93.5), Vector3(-7.0, 0, 88.0), Vector3(-2.0, 0, 82.0)] + VILLAGE_UP)


# ---------------- на рибу
func _pier_pt(s: float) -> Vector3:
	## Точка на осі причалу: s метрів від берегового краю (від'ємне — на березі).
	var a: Vector2 = Util.pier["a"]
	var b: Vector2 = Util.pier["b"]
	var q := a + (b - a).normalized() * s
	return Vector3(q.x, 0, q.y)


static func _basis_y(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _rod_step() -> void:
	## Вудка в правій руці; волосінь — від кінчика до поплавця.
	var rod: Node3D = _gear.get("rod")
	if rod == null or hand == null or not rod.is_inside_tree():
		return
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var d := (f * 0.85 + Vector3.UP * (0.5 + _rod_lift)).normalized()
	rod.global_transform = Transform3D(_basis_y(d), hand.global_position)
	if _bobber and _bobber.visible:
		var bp := _bobber.global_position
		bp.y = 0.06 - _bob_dip + sin(Time.get_ticks_msec() * 0.003) * 0.008
		_bobber.global_position = bp
	if _line and _line.visible and _bobber:
		var tip := hand.global_position + d * ROD_LEN
		var v := _bobber.global_position + Vector3(0, 0.03, 0) - tip
		var bs := _basis_y(v)
		bs.y = bs.y * maxf(v.length(), 0.01)
		_line.global_transform = Transform3D(bs, tip + v * 0.5)


func _show_line(at: Vector3) -> void:
	if _line == null:
		_line = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.003
		cm.bottom_radius = 0.003
		cm.height = 1.0
		cm.radial_segments = 4
		_line.mesh = cm
		_line.material_override = Util.mat(Color(0.9, 0.9, 0.85), 0.5)
		_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.yard_root.add_child(_line)
		_bobber = Node3D.new()
		_bobber.add_child(Util.sphere(0.03, Util.mat(Color(0.9, 0.15, 0.1), 0.4), Vector3(0, 0.02, 0)))
		_bobber.add_child(Util.sphere(0.028, Util.mat(Color(0.95, 0.95, 0.95), 0.4), Vector3(0, -0.01, 0)))
		world.yard_root.add_child(_bobber)
	_bobber.global_position = Vector3(at.x, 0.06, at.z)
	_bobber.visible = true
	_line.visible = true


func _make_fish() -> Node3D:
	## Рибка завдовжки ~20 см.
	var f := Node3D.new()
	world.yard_root.add_child(f)
	var kinds := ["fish_orange", "fish_blue", "fish_spotted", "fish_guppy"]
	var hold := Models.spawn(f, kinds[randi() % kinds.size()], 0.2, "realx")
	if hold == null:
		f.add_child(Util.sphere(0.05, Util.mat(Color(0.95, 0.55, 0.15), 0.4), Vector3.ZERO, Vector3(2.0, 0.9, 0.7)))
	elif hold.get_child_count() > 0:
		var mdl := hold.get_child(0) as Node3D
		if mdl:
			var bb := Models.measure(mdl)
			var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) * mdl.scale.x
			if longest > 0.001:
				hold.scale = Vector3.ONE * (0.2 / longest)
	return f


func _catch_fish(id: int, bucket: Node3D, cast_at: Vector3) -> void:
	## Підсікає й витягує рибку на волосіні, бере її лівою рукою й кладе у відро, потім закидає знову.
	var f := _make_fish()
	var from := _bobber.global_position
	f.global_position = from - Vector3(0, 0.15, 0)
	_bobber.visible = false
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var left := Vector3(cos(rotation.y), 0, -sin(rotation.y))
	var near := global_position + fwd * 0.6 + left * 0.2 + Vector3(0, 0.95, 0)
	var t := 0.0
	while t < 1.0:
		t = minf(1.0, t + get_process_delta_time())
		if id != job or not is_instance_valid(f):
			break
		var k := smoothstep(0.0, 1.0, t)
		var p := from.lerp(near, k) + Vector3(0, sin(k * PI) * 0.6, 0)
		_rod_lift = k
		_bobber.global_position = p
		f.global_position = p - Vector3(0, 0.12, 0)
		f.rotation.z = sin(t * 30.0) * 0.4             # трепиться на гачку
		await get_tree().process_frame
	# бере рибку лівою рукою
	t = 0.0
	while t < 0.5 and id == job and is_instance_valid(f):
		t += get_process_delta_time()
		if pose:
			pose.ik = {"LeftHand": [f.global_position + Vector3(0, 0.08, 0), clampf(t / 0.5, 0.0, 1.0)]}
		f.rotation.z = sin(t * 30.0) * 0.3
		await get_tree().process_frame
	# несе в руці до відра
	var top := bucket.global_position + Vector3(0, 0.4, 0)
	t = 0.0
	while t < 0.9 and id == job and is_instance_valid(f):
		t += get_process_delta_time()
		var k2 := smoothstep(0.0, 1.0, t / 0.9)
		if pose:
			pose.ik = {"LeftHand": [near.lerp(top, k2), 1.0]}
		if hand_l:
			f.global_position = hand_l.global_position - Vector3(0, 0.1, 0)
		_bobber.global_position = f.global_position + Vector3(0, 0.1, 0)
		_rod_lift = lerpf(1.0, 0.2, k2)
		await get_tree().process_frame
	if id != job or not is_instance_valid(f) or not is_instance_valid(bucket):
		if is_instance_valid(f):
			f.queue_free()
		if pose:
			pose.ik = {}
		return
	# у відро
	var fill: Node = bucket.get_node_or_null("fill")
	f.reparent(fill if fill else bucket, true)
	f.position = Vector3(randf_range(-0.04, 0.04), 0.22, randf_range(-0.04, 0.04))
	f.rotation = Vector3(0, randf() * TAU, PI / 2.0)
	await wait(0.3)
	if pose:
		pose.ik = {}
	_rod_lift = 0.0
	# закидає знову
	_bobber.global_position = Vector3(cast_at.x, 0.06, cast_at.z)
	_bobber.visible = true


func _fish_trip(id: int, cart: Node3D, h: Node3D) -> void:
	var rod: Node3D = _gear.get("rod")
	var stool: Node3D = _gear.get("stool")
	var bucket: Node3D = _gear.get("bucket")
	if rod == null or Util.pier.is_empty():
		_trip = ""
		end_job(id)
		return
	say("Поїду на ставок рибку ловити!", 2.5)
	bucket.set_meta("to", "granny")                    # відро з рибою — бабусі
	await go(SHOP_STAND)
	if id != job:
		return
	face(SHOP_GEAR["stool"])
	await wait(0.4)
	play("pick")
	await wait(0.9)
	_hold_carry([bucket, stool, rod])
	play("idle")
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	var park := _pier_pt(-5.5)
	say("Гайда на ставок!", 2.0)
	if not await _drive(id, cart, OUT_SOUTH + [Vector3(-2.0, 0, 29.5), Vector3(-36.0, 0, 25.0), Vector3(-41.0, 0, 36.0), park]):
		return
	if not await _get_off(id, cart):
		return
	if not await _unhitch_here(id, cart):
		return
	if not await _take_from_cart(id, cart, [bucket, stool, rod]):
		return
	# на причал
	var a: Vector2 = Util.pier["a"]
	var b: Vector2 = Util.pier["b"]
	var L := a.distance_to(b)
	var u := (b - a).normalized()
	var deck := float(Util.pier["y"])
	var yaw := atan2(u.x, u.y)
	var fwd := Vector3(u.x, 0, u.y)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var back := (HIPS_SIT + HIPS_SITANIM_STAND - HIPS_IDLE - HIPS_SITANIM_SIT) * _k
	var seat_s := L - 1.6
	await go(_pier_pt(-1.2))
	if id != job:
		return
	for s in [0.6, seat_s - 0.9]:
		await go(_pier_pt(s), false, false)
		if id != job:
			return
	_face_to = yaw
	await wait(0.4)
	play("pick")
	await wait(0.8)
	if id != job:
		return
	var seat_p := _pier_pt(seat_s)
	seat_p.y = deck
	var root: Node3D = world.yard_root
	_drop_carry()
	root.add_child(stool)
	stool.global_transform = Transform3D(Basis(Vector3.UP, yaw), seat_p)
	root.add_child(bucket)
	bucket.global_transform = Transform3D(Basis(), seat_p + side * 0.5)
	root.add_child(rod)
	_rod_hand = true
	play("idle")
	await wait(0.4)
	await go(seat_p + fwd * back, false, false)
	if id != job:
		return
	_face_to = yaw
	await wait(0.6)
	rotation.y = yaw
	await _sit_down("stool", seat_p, 0.0)
	if id != job:
		return
	_show_line(seat_p + fwd * 3.4)
	say("Ловись, рибко, велика й маленька!", 3.0)
	for i in 3:
		await wait(randf_range(5.0, 9.0))
		if id != job:
			return
		say("Клює!", 1.2)
		_bob_dip = 0.05
		await wait(0.7)
		_bob_dip = 0.0
		await _catch_fish(id, bucket, seat_p + fwd * 3.4)
		_rod_lift = 0.0
		if id != job:
			return
	say("Три рибки — буде юшка!", 3.0)
	await wait(1.5)
	if id != job:
		return
	_line.visible = false
	_bobber.visible = false
	_rod_hand = false
	await stand_up()
	if id != job:
		return
	play("pick")
	await wait(0.8)
	_hold_carry([bucket, stool, rod])
	play("idle")
	await go(_pier_pt(0.6), false, false)
	if id != job:
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	await _trip_home(id, cart, [_pier_pt(-12.0) + Vector3(6.0, 0, 0), Vector3(-36.0, 0, 38.0), Vector3(-34.0, 0, 26.0)] + POND_ROAD_HOME)


# ---------------- у млин
func _mill_trip(id: int, cart: Node3D, h: Node3D) -> void:
	say("Поїду в млин, змелю пшениці!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	if not await _drive(id, cart, OUT_SOUTH + GATE_WAY + [GATE_STOP]):
		return
	if not await _get_off(id, cart):
		return
	if not await _fetch_from_yard(id, "sack"):
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	var c := Vector3(Util.HILL_C.x, 0, Util.HILL_C.y)
	var dv := Vector3(0.4472136, 0, 0.8944272)            # від млина вздовж дороги вниз
	var sd := Vector3(dv.z, 0, -dv.x)
	say("Гайда до млина на пагорбі!", 2.5)
	if not await _drive(id, cart, [Vector3(-20.0, 0, 9.5), Vector3(-36.0, 0, 9.5), Vector3(-44.0, 0, 13.0), Vector3(-58.5, 0, -3.0),
			c + dv * 34.0, c + dv * 20.0, c + dv * 9.5], 2.4):
		return
	if not await _get_off(id, cart):
		return
	var sack := _cargo_kind("sack")
	if sack == null:
		return
	if not await _take_from_cart(id, cart, [sack]):
		return
	await go(c + dv * 4.0 + sd * 1.3)
	if id != job:
		return
	await go(c + dv * 1.3, false, false)
	if id != job:
		return
	play("pick")
	await wait(0.8)
	for o in _drop_carry():
		_store(o)
	say("Мели, млинку, борошенце!", 3.0)
	play("idle")
	await wait(10.0)
	if id != job:
		return
	play("pick")
	await wait(0.8)
	_hold_carry([_sack("flour")])
	play("idle")
	say("Ось і борошно — будуть пиріжки!", 2.5)
	await go(c + dv * 4.0 + sd * 1.3, false, false)
	if id != job:
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	await _trip_home(id, cart, [c + dv * 7.0 + sd * 5.0, c + dv * 13.0 + sd * 2.5, c + dv * 22.0, c + dv * 34.0,
		Vector3(-46.0, 0, 22.0)] + POND_ROAD_HOME)


# ---------------- сіяти пшеницю
var _sowing := false


func _throw_seeds(at: Vector3, dir: Vector3) -> void:
	## Жменя зерна широким віялом.
	if _seed_fx == null:
		_seed_fx = CPUParticles3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.024
		sm.radial_segments = 4
		sm.rings = 2
		sm.material = Util.mat(Color(0.92, 0.8, 0.4), 0.6)
		_seed_fx.mesh = sm
		_seed_fx.amount = 120
		_seed_fx.lifetime = 1.1
		_seed_fx.one_shot = true
		_seed_fx.explosiveness = 0.8
		_seed_fx.spread = 28.0
		_seed_fx.initial_velocity_min = 2.2
		_seed_fx.initial_velocity_max = 4.6
		_seed_fx.gravity = Vector3(0, -9.8, 0)
		_seed_fx.local_coords = false
		world.yard_root.add_child(_seed_fx)
	_seed_fx.global_position = at
	_seed_fx.direction = dir.normalized()
	_seed_fx.restart()
	_seed_fx.emitting = true


func _sow_arms(bucket: Node3D) -> void:
	## Як сіяч: відро — під лівою рукою біля пояса, права бере жменю зерна й широким помахом розкидає.
	var cyc := 0.0
	var thrown := false
	while _sowing and is_instance_valid(bucket) and is_inside_tree():
		cyc = fmod(cyc + get_process_delta_time() / 1.4, 1.0)
		var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
		var lft := Vector3(cos(rotation.y), 0, -sin(rotation.y))
		var base := global_position
		var bpos := base + lft * 0.2 + f * 0.3 + Vector3(0, 0.78, 0)
		bucket.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), bpos)
		var dip := bpos + Vector3(0, 0.3, 0)
		var front := base + f * 0.6 + Vector3(0, 1.15, 0)
		var out := base + f * 0.45 - lft * 0.7 + Vector3(0, 1.3, 0)
		var rh: Vector3
		if cyc < 0.3:
			rh = out.lerp(dip, smoothstep(0.0, 1.0, cyc / 0.3))               # рука — назад до відра
		elif cyc < 0.45:
			rh = dip + Vector3(0, sin(cyc * 60.0) * 0.03, 0)                  # набирає жменю
			thrown = false
		else:
			var k := smoothstep(0.0, 1.0, (cyc - 0.45) / 0.55)
			rh = dip.lerp(front, k).lerp(front.lerp(out, k), k)               # широкий помах
			if cyc > 0.7 and not thrown:
				thrown = true
				_throw_seeds(hand.global_position if hand else rh, (out - front).normalized() + f * 0.6 + Vector3(0, 0.35, 0))
		if pose:
			pose.ik = {"LeftHand": [bpos + lft * 0.16 + Vector3(0, 0.14, 0), 1.0], "RightHand": [rh, 1.0]}
		await get_tree().process_frame
	if pose:
		pose.ik = {}


func _sow_trip(id: int, m: Node, cart: Node3D, h: Node3D) -> void:
	say("Поїду сіяти пшеницю!", 2.5)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	if not await _drive(id, cart, OUT_SOUTH + GATE_WAY + [GATE_STOP]):
		return
	if not await _get_off(id, cart):
		return
	if not await _fetch_from_yard(id, "sack"):
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _fetch_from_yard(id, "bucket"):
		return
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	say("Гайда на поле!", 2.0)
	if not await _drive(id, cart, [Vector3(-12.0, 0, 10.5), Vector3(-12.0, 0, 15.0), Vector3(-5.0, 0, 18.0), Vector3(1.5, 0, 22.0),
			Vector3(2.5, 0, 30.0), Vector3(12.0, 0, 32.5), Vector3(25.5, 0, 30.5), Vector3(26.8, 0, 22.0), Vector3(26.8, 0, 9.0)] +
			GARDEN_TO_FIELD.slice(1)):
		return
	if not await _get_off(id, cart):
		return
	var f: Rect2 = m.world.outer.PLOW_FIELD
	var bucket: Node3D = _gear["bucket"]
	var sack := _cargo_kind("sack")
	var corner := Vector3(f.position.x + 0.8, 0, f.end.y + 0.8)
	var sack_at := corner + Vector3(0.6, 0, 0.3)
	if sack:
		if not await _take_from_cart(id, cart, [sack]):
			return
		await go(corner)
		if id != job:
			return
		play("pick")
		await wait(0.8)
		_drop_carry()
		world.yard_root.add_child(sack)
		sack.global_position = sack_at
		play("idle")
	if not await _take_from_cart(id, cart, [bucket]):
		return
	await go(corner)
	if id != job:
		return
	face(sack_at)
	say("Насиплю зерна у відро.", 2.0)
	play("pick")
	await wait(1.2)
	var fill: Node = bucket.get_node_or_null("fill")
	if fill:
		fill.add_child(Util.cyl(0.14, 0.14, 0.03, Util.mat(Color(0.88, 0.75, 0.38), 0.9), Vector3(0, 0.26, 0)))
	play("idle")
	if id != job:
		return
	say("Сію-вію, посіваю!", 3.0)
	_drop_carry()
	world.yard_root.add_child(bucket)
	_sowing = true
	_sow_arms(bucket)
	var east := true
	var z := f.position.y + 2.0
	while z < f.end.y - 0.5:
		await go(Vector3(f.position.x + 1.0 if east else f.end.x - 1.0, 0, z))
		if id != job:
			_sowing = false
			return
		await go(Vector3(f.end.x - 1.0 if east else f.position.x + 1.0, 0, z))
		if id != job:
			_sowing = false
			return
		east = not east
		z += 3.0
	_sowing = false
	await get_tree().process_frame
	if fill:
		for ch in fill.get_children():
			ch.queue_free()
	say("Посіяв! Рости, пшеничко, колосиста!", 3.0)
	await go(corner)
	if id != job:
		return
	play("pick")
	await wait(0.8)
	if sack and is_instance_valid(sack):
		sack.queue_free()
	_hold_carry([bucket, _sack("empty")])
	play("idle")
	if not await _put_in_cart(id, cart):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	await _trip_home(id, cart, [Vector3(79.0, 0, 9.5), Vector3(72.0, 0, 11.0), Vector3(30.0, 0, 5.5)])


# ---------------- на ферму
func _talk_worker(id: int, m: Node) -> void:
	## Іде до когось із робітників ферми й говорить.
	var w = null
	var nm := ""
	var bd := INF
	for pair in [[m.groom, "Семене"], [m.shepherd, "Іване"]]:
		var c = pair[0]
		if c != null and is_instance_valid(c) and c.visible and c.process_mode != Node.PROCESS_MODE_DISABLED:
			var d: float = (c as Node3D).global_position.distance_to(global_position)
			if d < 90.0 and d < bd:
				bd = d
				w = c
				nm = pair[1]
	if w == null:
		say("Хлопців не видно — мабуть, обідають.", 3.0)
		await wait(2.5)
		return
	for i in 4:
		var to: Vector3 = (w as Node3D).global_position
		var dir := global_position - to
		dir.y = 0.0
		if dir.length() < 2.2:
			break
		await go(to + dir.normalized() * 1.4)
		if id != job:
			return
	face((w as Node3D).global_position)
	w.face(global_position)
	say("Здоров був, %s! Як там на фермі?" % nm, 3.0)
	play("talk")
	await wait(3.0)
	if id != job:
		return
	w.say("Добрий день, діду Петре! Усе гаразд, худоба ситенька!", 3.5)
	await wait(3.5)
	if id != job:
		return
	say("От і добре! Візьму в вас соломки.", 2.5)
	await wait(2.5)
	play("idle")


func _farm_trip(id: int, m: Node, cart: Node3D, h: Node3D) -> void:
	say("Поїду на ферму, провідаю хлопців і візьму соломи.", 3.0)
	if not await _go_outside(id):
		return
	if not await _walk_to_garden(id):
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	if not await _drive(id, cart, OUT_SOUTH + VILLAGE_DOWN + [Vector3(-3.0, 0, 93.0), Vector3(-12.0, 0, 95.0), Vector3(-160.0, 0, 95.0),
			Vector3(-171.5, 0, 89.0), Vector3(-171.5, 0, 78.0)]):
		return
	if not await _get_off(id, cart):
		return
	await _talk_worker(id, m)
	if id != job:
		return
	if not await _hitch_and_mount(id, cart, h):
		return
	if not await _drive(id, cart, [Vector3(-171.5, 0, 60.0), Vector3(-172.0, 0, 42.0), FARM_HAY_STOP], 2.0):
		return
	if not await _get_off(id, cart):
		return
	var hay_at: Vector3 = m.FARM_HAY
	for i in 2:
		await go(hay_at + Vector3(2.0, 0, 1.0 + i * 0.6))
		if id != job:
			return
		face(hay_at)
		await wait(0.3)
		play("pick")
		await wait(1.0)
		_hold_carry([_hay()])
		if m.has_method("add_farm_hay"):
			m.add_farm_hay(-0.08)
		play("idle")
		if not await _put_in_cart(id, cart):
			return
	say("Соломки набрав — додому!", 2.0)
	if not await _hitch_and_mount(id, cart, h):
		return
	await _trip_home(id, cart, [Vector3(-171.5, 0, 24.0), Vector3(-168.0, 0, 15.0)] + NORTH_HOME)
