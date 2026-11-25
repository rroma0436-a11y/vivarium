extends Walker
## Цуценя Бім (модель з Meshy, 9 рухів): гуляє двором, нюхає землю, біжить за Beep,
## їсть із миски, радіє, коли гладять, виляє хвостом, увечері йде до будки.

const HEIGHT := 0.78

var busy := false
var idle_left := 2.0
var bowl_pos := Vector3.ZERO
var bowl_front := Vector3.ZERO      # з якого боку підходити до мисок на лавочці
var home_pos := Vector3.ZERO
var follow: Node3D                 # за ким іноді бігає (Beep)
var _pet_alt := false
var _act_left := 0.0
var _act_then: Callable
var door_dir := Vector3(0.3, 0, 0.95).normalized()   # куди дивляться дверцята будки
var water_pos := Vector3.ZERO
var in_house := false
var ball: Node3D                   # м'ячик у зубах
var main


func _ready() -> void:
	var ok := setup_model("puppy", HEIGHT, {
		"idle": ["dog_idle"], "sniff": ["idle1", "chigouliang"], "walk": ["walk"], "run": ["run"],
		"eat": ["chigouliang"], "pet": ["beifumo"], "pet2": ["dog_petting", "squat"],
		"wag": ["yaoweiba", "dog_idle"], "over": ["dog_over"],
	}, ["idle", "walk", "run", "wag", "eat"])
	if ok:
		anims["idle"] = Models.find_anim(ap, ["dog_idle"])
		# «dog_idle1» теж містить «dog_idle» — шукаємо точну назву
		for n in ap.get_animation_list():
			if String(n).to_lower().ends_with("dog_idle"):
				anims["idle"] = n
		Models.set_loop(ap, [anims["idle"]])
		_straighten()
	else:
		_placeholder()
	walk_speed = 0.75
	run_speed = 2.1
	setup_common("puppy", Vector3(0.55, 0.8, 1.0), 1.15, 0.4)
	play("idle")


func _straighten() -> void:
	## Модель з Meshy стоїть у файлі під кутом, а голова повернута до глядача.
	## Розвертаємо тіло вздовж руху й довертаємо шию, щоб Бім дивився туди, куди біжить.
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var hips := sk.find_bone("hips")
	var chest := sk.find_bone("chest")
	var neck := sk.find_bone("neck_01")
	if neck < 0:
		neck = sk.find_bone("neck1")
	var neck2 := sk.find_bone("neck2")
	var head := sk.find_bone("head")
	if hips < 0 or chest < 0 or neck < 0 or head < 0:
		return
	var b := sk.get_bone_global_rest(chest).origin - sk.get_bone_global_rest(hips).origin
	var a_body := atan2(b.x, b.z)
	var h := sk.get_bone_global_rest(head).origin - sk.get_bone_global_rest(neck2 if neck2 >= 0 else neck).origin
	var a_head := atan2(h.x, h.z)
	model.rotation.y = -a_body
	var fix := preload("res://scripts/head_fix.gd").new()
	fix.bone = neck
	fix.yaw = wrapf(a_body - a_head, -PI, PI)
	sk.add_child(fix)
	_fix = fix
	_sk = sk
	dpose = preload("res://scripts/dog_pose.gd").new()
	dpose.axis_node = self
	dpose.setup(sk)
	sk.add_child(dpose)
	_model_base = model.transform
	_refine_head.call_deferred()


var _fix
var _sk: Skeleton3D
var dpose
var _model_base := Transform3D()
var _jump := 0.0
var trick := ""


func _refine_head() -> void:
	## Після кількох кадрів анімації міряємо, куди насправді дивиться голова, і довертаємо залишок.
	for i in 6:
		await get_tree().process_frame
	if _sk == null:
		return
	var hb := _sk.find_bone("head")
	var nb := _sk.find_bone("neck2")
	var cb := _sk.find_bone("chest")
	var hp := _sk.find_bone("hips")
	if hb < 0 or nb < 0 or cb < 0 or hp < 0:
		return
	var g := _sk.global_transform
	var body := (g * _sk.get_bone_global_pose(cb).origin) - (g * _sk.get_bone_global_pose(hp).origin)
	var head := (g * _sk.get_bone_global_pose(hb).origin) - (g * _sk.get_bone_global_pose(nb).origin)
	var d := wrapf(atan2(body.x, body.z) - atan2(head.x, head.z), -PI, PI)
	if absf(d) < 0.6:
		_fix.yaw = wrapf(_fix.yaw + d * 0.8, -PI, PI)


func _pose_model(delta: float) -> void:
	## Нахил і висота тіла для поз «сидіти», «лежати» та стрибка.
	if dpose == null:
		return
	var k := HEIGHT / 0.52
	var pitch := -deg_to_rad(22.0) * float(dpose.sit) * (1.0 - float(dpose.lie))
	var drop := (0.13 * float(dpose.sit) * (1.0 - float(dpose.lie)) + 0.17 * float(dpose.lie)) * k
	var pivot := Vector3(0, 0.24, -0.16) * k
	var r := Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	var t := Transform3D(Basis(), pivot) * r * Transform3D(Basis(), -pivot)
	if _jump > 0.0:
		_jump = maxf(0.0, _jump - delta)
	var hop := sin(clampf(1.0 - _jump / 0.7, 0.0, 1.0) * PI) * 0.45 if _jump > 0.0 else 0.0
	model.transform = Transform3D(Basis(), Vector3(0, hop - drop, 0)) * t * _model_base


func _set_pose(name: String, v: float, secs := 0.35) -> void:
	if dpose == null:
		return
	create_tween().tween_property(dpose, name, v, secs)


func do_trick(kind := "") -> void:
	## Трюки, коли торкаєшся Біма: сидіти, лежати, дати лапу, стрибнути.
	if kind == "":
		kind = ["sit", "lie", "paw", "jump"][randi() % 4]
	trick = kind
	stop()
	busy = true
	play("idle")
	match kind:
		"sit":
			say("Сиджу!", 1.6)
			if anims.get("pet", "") != "":
				play("pet")
				await wait(minf(anim_length("pet"), 5.0))
				play("idle")
			else:
				_set_pose("sit", 1.0)
				await wait(2.6)
				_set_pose("sit", 0.0)
		"lie":
			say("Лежу…", 1.6)
			_set_pose("sit", 1.0, 0.3)
			await wait(0.3)
			_set_pose("lie", 1.0, 0.45)
			await wait(3.0)
			_set_pose("lie", 0.0, 0.4)
			await wait(0.3)
			_set_pose("sit", 0.0, 0.3)
		"paw":
			say("Лапу!", 1.6)
			_set_pose("sit", 1.0)
			await wait(0.4)
			_set_pose("paw", 1.0, 0.3)
			await wait(1.8)
			_set_pose("paw", 0.0, 0.3)
			await wait(0.3)
			_set_pose("sit", 0.0)
		"jump":
			say("Гоп!", 1.4)
			_jump = 0.7
			await wait(0.8)
	await wait(0.4)
	trick = ""
	busy = false
	act("wag", 1.5)


func _placeholder() -> void:
	var body := Util.capsule(0.12, 0.45, Util.mat(Color(0.9, 0.85, 0.75)), Vector3(0, 0.25, 0), Vector3(90, 0, 0))
	add_child(body)
	add_child(Util.sphere(0.12, Util.mat(Color(0.8, 0.55, 0.25)), Vector3(0, 0.4, 0.22)))


func _process(delta: float) -> void:
	_physics_step(delta)
	_pose_model(delta)
	if moving and doing != "doghouse":
		in_house = false
	if in_house and idle_left > 50.0 and not Game.is_night():
		idle_left = 0.5
	if _act_left > 0.0:
		_act_left -= delta
		if _act_left <= 0.0:
			var cb := _act_then
			_act_then = Callable()
			busy = false
			if cb.is_valid():
				cb.call()
	if moving:
		play("run" if running else "walk", 1.0)
		return
	if busy or doing != "":
		return
	idle_left -= delta
	if idle_left > 0.0:
		return
	_choose_next()


func _choose_next() -> void:
	idle_left = randf_range(2.5, 6.0)
	if Game.state["puppy"]["bowl"] > 0.0:
		go_eat()          # у мисці є корм — Бім про нього не забуде
		return
	if Game.is_night():
		if not in_house:
			go_doghouse()
		return
	if in_house:
		leave_doghouse()
		return
	if float(Game.state.get("water_bowl", 0.0)) > 20.0 and Game.state["puppy"]["hunger"] < 70.0 and randf() < 0.12:
		go_drink()
		return
	var r := randf()
	if follow and follow.global_position.distance_to(global_position) > 4.5 and r < 0.5:
		var p := follow.global_position
		walk_to(Vector3(p.x, 0, p.z) + Vector3(randf_range(-0.8, 0.8), 0, 0.9), true)
	elif r < 0.45:
		walk_to(position + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.0, 3.0)))
	elif r < 0.7:
		act("sniff")
	elif r < 0.85:
		act("wag", 2.0)
	else:
		play("idle")


func act(kind: String, cycles := 1.0, then := Callable()) -> void:
	## Зіграти рух повністю (або кілька разів, якщо він по колу), потім then.
	stop()
	busy = true
	play(kind)
	_act_left = anim_length(kind) * cycles
	_act_then = then


func pet(from: Vector3) -> void:
	if doing != "":
		cancel_job()
		_drop_ball()
	face(from)
	Game.puppy_petted()
	if trick != "":
		return
	_tricks_n += 1
	if _tricks_n % 3 == 0:
		_pet_alt = not _pet_alt
		say("Гав! ❤" if randf() < 0.5 else "Ще-ще!", 2.0)
		act("pet2" if _pet_alt else "pet", 1.0, func():
			if Game.state["puppy"]["bowl"] > 0.0:
				go_eat()
			else:
				act("wag", 2.0))
		return
	await do_trick()
	if Game.state["puppy"]["bowl"] > 0.0:
		go_eat()


var _tricks_n := 0


func go_eat() -> void:
	if doing != "":
		cancel_job()
		_drop_ball()
	busy = false
	var dirb := bowl_front if bowl_front != Vector3.ZERO else (position - bowl_pos).normalized()
	walk_to(bowl_pos + dirb * 0.5, true, func():
		face(bowl_pos)
		_set_pose("eat_low", 1.0, 0.5)
		act("eat", 2.0, func():
			_set_pose("eat_low", 0.0, 0.4)
			Game.puppy_ate()
			say("Ням! Дякую!", 2.0)
			act("wag", 3.0)))


func greet(p: Vector3) -> void:
	## Радісно біжить до точки (наприклад, до дідуся) і виляє хвостом.
	walk_to(p, true, func():
		act("wag", 3.0))



# ------------------------------------------------------------------ будка
func go_doghouse() -> void:
	## Забігає в будку й лягає, виглядаючи з дверцят.
	var id := begin_job("doghouse")
	await go(home_pos + door_dir * 1.1, true)
	if id != job:
		return
	await go(home_pos + door_dir * 0.3, false, false)
	if id != job:
		return
	in_house = true
	face(home_pos + door_dir * 3.0)
	_face_to = atan2(door_dir.x, door_dir.z)
	rotation.y = _face_to
	play("idle", 0.4)
	say("Гав… (позіхає)", 2.0)
	end_job(id)
	idle_left = 1e9 if Game.is_night() else 3.0


func leave_doghouse() -> void:
	in_house = false
	idle_left = 1.0
	walk_to(home_pos + door_dir * 1.4, false, Callable(), false)


func check_morning() -> void:
	if in_house and not Game.is_night():
		idle_left = 0.0


# ------------------------------------------------------------------ вода
func go_drink() -> void:
	if doing == "geese":
		return
	var id := begin_job("drink")
	var dirw := bowl_front if bowl_front != Vector3.ZERO else (position - water_pos).normalized()
	await go(water_pos + dirw * 0.48, false)
	if id != job:
		return
	face(water_pos)
	play("eat")
	_set_pose("eat_low", 1.0, 0.5)
	say("Хлеп-хлеп!", 1.6)
	await wait(anim_length("eat") * 1.5)
	_set_pose("eat_low", 0.0, 0.4)
	if id != job:
		return
	act("wag", 1.5)
	end_job(id)


# ------------------------------------------------------------------ загнати курей у курник
func herd_hens(birds: Array, door: Vector3) -> void:
	## Оббігає кожну курку з дальнього боку й гавкає — вона біжить до курника.
	var id := begin_job("herd")
	if in_house:
		in_house = false
	say("Гав! Додому, курочки!", 2.0)
	for b in birds:
		if b.mode in ["inside", "to_coop", "ramp", "entering"]:
			continue
		var bp: Vector3 = b.global_position
		var away := (bp - door)
		away.y = 0.0
		var behind := bp + away.normalized() * 0.9 if away.length() > 0.05 else bp + Vector3(-0.9, 0, 0)
		await go(behind, true)
		if id != job:
			return
		face(bp)
		act("wag", 0.6)
		_bark()
		b.go_coop(door)
		await wait(0.5)
		if id != job:
			return
		busy = false
	# чекає, поки всі зайдуть
	var t := 0.0
	while t < 8.0:
		var all_in := true
		for b in birds:
			if b.mode != "inside":
				all_in = false
		if all_in:
			break
		await wait(0.5)
		t += 0.5
	if id != job:
		return
	say("Гав! Усі вдома!", 2.0)
	Game.emit_event("hens_home")
	end_job(id)
	if Game.is_night():
		go_doghouse()


# ------------------------------------------------------------------ гусей — на ставок і назад
const YARD_RECT := Rect2(-20.5, -14.5, 29.0, 19.0)
const OUT_RECT := Rect2(-70.0, -16.0, 92.0, 52.0)


func _dry(p: Vector3) -> Vector3:
	## Пес у воду не заходить: точку в ставку виносимо на берег.
	var wo = preload("res://scripts/world_outer.gd")
	if wo.pond_sd(p) >= 1.2:
		return p
	var d := Vector3(p.x - wo.POND.x, 0, p.z - wo.POND.z)
	d = d.normalized() if d.length() > 0.01 else Vector3(1, 0, 0)
	var q := p
	for i in 80:
		q += d * 0.5
		if wo.pond_sd(q) >= 1.2:
			break
	return q


func herd_geese(flock: Array, to_pond: bool, way_out: Array, start_flock: Callable) -> void:
	## Пес жене гусей: біжить позаду табунця й гавкає. to_pond — на ставок; інакше — зі ставка додому.
	## way_out — шлях від подвір'я до ставка; start_flock — рушити гусей (коли пес на місці).
	var id := begin_job("geese")
	in_house = false
	bounds = OUT_RECT
	if not to_pond:
		# спершу добігти до ставка
		say("Гав! Гуси, додому!", 2.0)
		for p in way_out:
			await go(_dry(p), true)
			if id != job:
				bounds = YARD_RECT
				return
		_bark()
	else:
		say("Гав-гав! Гуси, на ставок!", 2.5)
		_bark()
	start_flock.call()
	var started := false
	for g in flock:
		if g.trekking():
			started = true
	if not started:
		bounds = YARD_RECT
		end_job(id)
		return
	var t := 0.0
	var bark_t := 2.0
	while id == job and t < 240.0:
		var any := false
		var c := Vector3.ZERO
		var n := 0
		var lead := Vector3.ZERO
		for g in flock:
			if g.trekking():
				any = true
				c += g.global_position
				n += 1
				if not g.path.is_empty():
					lead = g.path[0]
		if not any:
			break
		c /= float(n)
		var dir: Vector3 = (lead - c)
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, 1)
		var want := _dry(c - dir * 2.3 + Vector3(-dir.z, 0, dir.x) * sin(t * 0.7) * 0.8)
		if global_position.distance_to(want) > 0.8:
			walk_to(want, global_position.distance_to(want) > 2.5)
		bark_t -= 0.4
		if bark_t <= 0.0:
			bark_t = randf_range(2.5, 5.0)
			_bark()
			if randf() < 0.4:
				say("Гав!", 1.0)
		await wait(0.4)
		t += 0.4
	if id != job:
		bounds = YARD_RECT
		return
	if to_pond:
		# посидіти біля води — і назад на подвір'я
		await wait(2.0)
		say("Гав! Плавайте!", 1.5)
		var back := way_out.duplicate()
		back.reverse()
		for p in back.slice(1):
			await go(_dry(p), false)
			if id != job:
				bounds = YARD_RECT
				return
	bounds = YARD_RECT
	end_job(id)
	idle_left = 2.0


func _bark() -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au:
		au.play_at("puppy_bark", self, -4.0, 1.1)


# ------------------------------------------------------------------ м'ячик
func fetch(b: Node3D, back_to: Node3D) -> void:
	## Біжить за м'ячиком, бере в зуби, приносить до Beep.
	var id := begin_job("fetch")
	if in_house:
		in_house = false
	var bp := b.global_position
	await go(Vector3(bp.x, 0, bp.z), true)
	if id != job:
		return
	# бере в зуби
	ball = b
	b.reparent(self)
	b.position = Vector3(0, 0.33, 0.33)
	var p := back_to.global_position
	await go(Vector3(p.x, 0, p.z) + Vector3(0.3, 0, 0.6), true)
	if id != job:
		_drop_ball()
		return
	face(p)
	_drop_ball()
	_bark()
	say("Гав! Ще!", 1.6)
	Game.emit_event("ball_fetched")
	act("wag", 2.0)
	end_job(id)


func _drop_ball() -> void:
	if ball and is_instance_valid(ball):
		var gp := ball.global_position
		ball.reparent(get_parent())
		ball.global_position = Vector3(gp.x + 0.2, 0.07, gp.z + 0.2)
	ball = null

