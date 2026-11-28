extends "res://scripts/farmhand.gd"
## Пастух дід Іван: живе в хаті села. Зранку приходить на ферму, відчиняє корівники й жене худобу
## за задні ворота ферми — пастися за 40 м від ферми; напуває худобу на річці; увечері заганяє в корівники.

var door := Vector3.ZERO
var pasture: Rect2                                     # пасовисько біля корівників (на фермі)
const FENCE_N := 28.0                                  # північний (задній) бік забору ферми
const FENCE_S := 83.0                                  # південний (передній) бік — до річки
const EAST_X := -158.0                                 # схід від корівників — пасовисько на фермі
const N_IN := Vector3(-171.5, 0, 32.0)                 # задні ворота: зсередини ферми
const N_OUT := Vector3(-171.5, 0, 23.0)                # задні ворота: ззовні
const S_IN := Vector3(-171.5, 0, 78.0)                 # передні ворота: зсередини
const S_OUT := Vector3(-171.5, 0, 88.0)                # передні ворота: ззовні (до річки)
const GAPS := [31.0, 47.0, 63.0, 80.0]                 # проходи між корівниками (z): зі сходу на захід
const GAP_E := -153.5
const GAP_W := -168.5
const OUT_PASTURE := Rect2(-184.0, -17.0, 26.0, 8.0)   # пасовисько за задніми воротами (≈40 м від ферми)
const OUT_STOP := Vector3(-171.0, 0, -5.0)             # де пастух стоїть біля худоби за фермою
const DRINK_Z := 96.7                                  # де худоба стає на березі річки
const DRINK_X := -157.0
const RIVER_WAIT := Vector3(-149.5, 0, 92.0)           # де пастух чекає, поки худоба п'є
const COWS_STOP := Vector3(-171.0, 0, 62.0)            # біля дверей корівників (зовні)

var _talk_t := 0.0


func setup_shepherd(cow_door: Vector3, past: Rect2, home: Vector3, route: Array) -> void:
	door = cow_door
	pasture = past
	setup("shepherd", 1.7, {"walk": ["walking"], "run": ["running"], "talk": ["talk_with_left"],
			"scratch": ["confused_scratch"], "shrug": ["shrug"], "drink": ["stand_and_drink"], "pick": ["female_bend_over"]},
		["walk", "run"],
		["Я — Іван, пасу худобу з-змалечку.", "Зірка сьогодні норовлива, а Ласка — тиха.", "Трава цього року соковита!",
		 "Бичок у нас сильний — не підходь ззаду.", "Зранку виганяю худобу за задні ворота, вдень веду на річку напитися."],
		[], "npc")
	Models.give_nika_anims(ap, anims)
	make_idle_from("walk")
	setup_pose()
	for c in main.cows:
		c.keeper_only = true
	start_farm(home, route, 6.6, 19.3)


func _process(delta: float) -> void:
	if _talk_t > 0.0 and not _on_bike:
		# розмовляє з Нікою: стоїть лицем до неї (справа, яку робив, чекає)
		_talk_t -= delta
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		var nk: Node3D = main.girl if main and main.girl else null
		if nk:
			var d := nk.global_position - global_position
			if Vector2(d.x, d.z).length() > 0.05:
				rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-delta * 5.0))
		play("talk")
		if pose:
			pose.life = lerpf(pose.life, 1.0, 1.0 - exp(-delta * 3.0))
		return
	super(delta)


func on_arrived() -> void:
	await cows_out()


# ------------------------------------------------------------------ де що є
func _zone(p: Vector3) -> String:
	if p.z < FENCE_N:
		return "back"
	if p.z > FENCE_S:
		return "river"
	if p.x > EAST_X:
		return "east"
	return "farm"


func _gap(z: float) -> float:
	var best: float = GAPS[0]
	for g in GAPS:
		if absf(g - z) < absf(best - z):
			best = g
	return best


func _via(a: String, b: String, p: Vector3) -> Array:
	## Точки переходу з зони a в зону b (крізь ворота ферми й проходи між корівниками).
	if a == b:
		return []
	if a != "farm" and b != "farm":
		return _via(a, "farm", p) + _via("farm", b, p)
	var gz := _gap(p.z)
	match [a, b]:
		["farm", "back"]:
			return [N_IN, N_OUT]
		["back", "farm"]:
			return [N_OUT, N_IN]
		["farm", "river"]:
			return [S_IN, S_OUT]
		["river", "farm"]:
			return [S_OUT, S_IN]
		["farm", "east"]:
			return [Vector3(GAP_W, 0, gz), Vector3(GAP_E, 0, gz)]
		["east", "farm"]:
			return [Vector3(GAP_E, 0, gz), Vector3(GAP_W, 0, gz)]
	return []


func _walk(p: Vector3) -> void:
	## Іде до точки, обходячи корівники й забір ферми крізь ворота.
	for v in _via(_zone(global_position), _zone(p), p):
		await _goto(v, 1.5)
	await _goto(p, 1.5)


func _herdable() -> Array:
	## Худоба, яку можна гнати (не в корівнику, не на доїнні).
	var list: Array = []
	for c in main.cows:
		if c.mode in ["free", "to_pasture", "herded", "drinking", "to_shed"]:
			list.append(c)
	return list


func _out_spot(i: int, n: int) -> Vector3:
	var r := OUT_PASTURE
	var x := r.position.x + r.size.x * (i + 0.5) / maxf(1.0, n) + randf_range(-1.5, 1.5)
	return Vector3(x, 0, randf_range(r.position.y + 1.0, r.end.y - 1.0))


func _home_spot() -> Vector3:
	return Vector3(randf_range(pasture.position.x + 1.0, pasture.end.x - 1.0), 0, randf_range(pasture.position.y + 1.0, pasture.end.y - 1.0))


func _behind(herd: Array, toward: Vector3) -> Vector3:
	## Місце позаду гурту (з протилежного боку від того, куди гнати).
	var c := Vector3.ZERO
	for h in herd:
		c += h.global_position
	c /= maxf(1.0, herd.size())
	c.y = 0.0
	var d := c - toward
	d.y = 0.0
	if d.length() < 0.5:
		d = Vector3(0, 0, 1)
	return c + d.normalized() * 5.0


func _passed(herd: Array, m: int, i: int) -> bool:
	for h in herd:
		if h.mode == "herded" and h._path.size() >= m - 1 - i:
			return false
	return true


func _drive(herd: Array, pts: Array, finals: Array, end_mode: String, stop_at: Vector3, pre := {}, skip := []) -> void:
	## Жене худобу: кожна тварина — спершу своїми точками pre[тварина], далі спільними pts (трохи збоку, щоб не товклися),
	## наприкінці — у своє місце finals[i]. Ті, що в skip, — одразу на своє місце. Сам іде слідом і стає в stop_at.
	var my := job
	var n := herd.size()
	for i in n:
		var ofs := Vector3((i - (n - 1) / 2.0) * 0.9, 0, 0)
		var path: Array = []
		for p in pre.get(herd[i], []):
			path.append(p + ofs)
		if not (herd[i] in skip):
			for p in pts:
				path.append(p + ofs)
		path.append(finals[i])
		herd[i].herd(path, end_mode)
		await wait(1.2)
		if job != my:
			return
	var m := pts.size() + 1
	for i in pts.size():
		var t := 0.0
		while t < 90.0 and not _passed(herd, m, i):
			t += 0.5
			await wait(0.5)
		if job != my:
			return
		await _walk(pts[i])
	await _walk(stop_at)


func _wait_settled(herd: Array, secs: float) -> void:
	var t := 0.0
	while t < secs and herd.any(func(h): return h.mode == "herded"):
		t += 0.5
		await wait(0.5)


# ------------------------------------------------------------------ справи
func _open_sheds() -> void:
	## Обходить корівники: відчиняє ворота, заходить, кличе — і худоба виходить надвір (стає біля дверей).
	var my := job
	var first := true
	var out: Array = []
	for d in main.COW_DOORS:
		var inside: Array = []
		for c in main.cows:
			if c.mode == "inside" and (c.door as Vector3).distance_to(d) < 2.0:
				inside.append(c)
		if inside.is_empty():
			continue
		await _walk(d + Vector3(-0.6, 0, 0))
		if job != my:
			return
		await go(d + Vector3(2.6, 0, 0), false, false)          # відчиняє ворота й заходить у корівник
		face(d + Vector3(5.0, 0, 0))
		say("Доброго ранку, мої красуні! Виходьте!" if first else "Ходіть, ходіть надвір!", 2.5)
		first = false
		await act("talk", 2.0)
		await go(d + Vector3(-0.6, 0, 0), false, false)          # виходить надвір
		await go(d + Vector3(-1.6, 0, -2.2), false, false)       # і стає збоку від воріт
		face(d)
		for c in inside:
			var s := d + Vector3(-2.6, 0, randf_range(-2.5, 2.5))
			c.pasture = Rect2(s.x - 1.0, d.z - 2.5, 1.5, 5.0)
			c.herd([s], "free")
			out.append(c)
			await wait(0.8)
	await _wait_settled(out, 15.0)


func cows_out() -> void:
	## Відчиняє корівники й випускає худобу, а тоді жене її за задні ворота — пастися за 40 м від ферми.
	var my := job
	await _open_sheds()
	if job != my:
		return
	var herd: Array = []
	for c in _herdable():
		if _zone(c.global_position) != "back":
			herd.append(c)
	if herd.is_empty():
		say("Худоба вже пасеться за фермою!", 2.5)
		return
	var pre := {}
	for c in herd:
		match _zone(c.global_position):
			"east":
				pre[c] = [Vector3(GAP_E, 0, GAPS[0]), Vector3(GAP_W, 0, GAPS[0])]
			"river":
				pre[c] = [S_OUT, S_IN]
	await _walk(_behind(herd, N_IN))
	if job != my:
		return
	say("Гей-гей, на пасовисько! Через задні ворота!", 2.5)
	await act("talk", 1.5)
	var fin: Array = []
	for i in herd.size():
		herd[i].pasture = OUT_PASTURE
		herd[i].gate_way = [N_IN, N_OUT]
		fin.append(_out_spot(i, herd.size()))
	await _drive(herd, [N_IN, N_OUT], fin, "free", OUT_STOP, pre)
	if job == my:
		face(Vector3(OUT_PASTURE.get_center().x, 0, OUT_PASTURE.get_center().y))
		say("Пасіться, мої красуні! Увечері прийду по вас.", 3.0)
		await act("talk", 1.5)


func cows_drink() -> void:
	## Жене худобу до річки: з ферми — крізь передні ворота, з пасовиська за фермою — через усю ферму.
	## Худоба стає на березі, нахиляє голови й п'є; потім жене її назад — на ферму або на пасовисько.
	var my := job
	if main.cows.any(func(c): return c.mode == "inside"):
		await _open_sheds()
		if job != my:
			return
	var herd := _herdable()
	if herd.is_empty():
		say("Худоба зараз зайнята — напою пізніше.", 2.5)
		return
	var back: Array = []
	var pre := {}
	var skip: Array = []
	for c in herd:
		match _zone(c.global_position):
			"back":
				back.append(c)
				pre[c] = [N_OUT, N_IN]
			"east":
				pre[c] = [Vector3(GAP_E, 0, GAPS[3]), Vector3(GAP_W, 0, GAPS[3])]
			"river":
				skip.append(c)
	var to_back := back.size() * 2 >= herd.size()
	if not back.is_empty():
		await _walk(_behind(back, N_OUT))
	else:
		await _walk(_behind(herd, S_IN))
	if job != my:
		return
	say("Ходіть, мої хороші, до річки — водички поп'ємо!", 2.5)
	await act("talk", 1.5)
	var n := herd.size()
	var fin: Array = []
	for i in n:
		var s := Vector3(DRINK_X + (i - (n - 1) / 2.0) * 2.4, 0, DRINK_Z)
		fin.append(s)
		herd[i].drink_face = s + Vector3(0, 0, 3.0)
		herd[i].gate_way = [S_IN, S_OUT]
		herd[i].pasture = herd[i].home_pasture
	await _drive(herd, [S_IN, S_OUT], fin, "drinking", RIVER_WAIT, pre, skip)
	if job != my:
		return
	await _wait_settled(herd, 40.0)
	face(Vector3(DRINK_X, 0, DRINK_Z))
	say("Пийте, мої хороші, пийте…", 3.0)
	await act("talk", 3.0)
	await wait(8.0)
	if job != my:
		return
	herd = herd.filter(func(c): return c.mode == "drinking")
	if herd.is_empty():
		return
	say("Напилися? Гайда назад — " + ("на пасовисько!" if to_back else "на ферму!"), 2.5)
	await act("talk", 1.5)
	fin = []
	for i in herd.size():
		if to_back:
			herd[i].pasture = OUT_PASTURE
			herd[i].gate_way = [N_IN, N_OUT]
			fin.append(_out_spot(i, herd.size()))
		else:
			herd[i].pasture = herd[i].home_pasture
			herd[i].gate_way = []
			fin.append(_home_spot())
	if to_back:
		await _drive(herd, [S_OUT, S_IN, N_IN, N_OUT], fin, "free", OUT_STOP)
	else:
		await _drive(herd, [S_OUT, S_IN, Vector3(GAP_W, 0, GAPS[3]), Vector3(GAP_E, 0, GAPS[3])], fin, "free",
			Vector3(pasture.get_center().x, 0, pasture.end.y + 1.5))
	if job == my:
		say("Отак, напоєні!", 2.0)


func cows_in() -> void:
	## Заганяє всю худобу в корівники: з пасовиська за фермою — крізь задні ворота, від річки — крізь передні.
	var my := job
	var herd := _herdable()
	if herd.is_empty():
		return
	var back := herd.filter(func(c): return _zone(c.global_position) == "back")
	var river := herd.filter(func(c): return _zone(c.global_position) == "river")
	var east := herd.filter(func(c): return _zone(c.global_position) == "east")
	if not back.is_empty():
		await _walk(_behind(back, N_OUT))
	elif not river.is_empty():
		await _walk(RIVER_WAIT)
	elif not east.is_empty():
		await _walk(_behind(east, Vector3(GAP_E, 0, GAPS[1])))
	else:
		await _walk(COWS_STOP)
	if job != my:
		return
	say("Додому, корівки, у корівник!", 2.5)
	await act("talk", 2.0)
	for c in herd:
		c.kept_in = true
		c.send_home(true)
	var outside: Array = back + river
	var t := 0.0
	while t < 60.0 and outside.any(func(c): return c.mode == "to_shed" and _zone(c.global_position) != "farm" and _zone(c.global_position) != "east"):
		t += 1.0
		await wait(1.0)
	if job != my:
		return
	await _walk(COWS_STOP)
	face(COWS_STOP + Vector3(5.0, 0, 0))
	t = 0.0
	while t < 60.0:
		if not main.cows.any(func(c): return c.mode in ["free", "to_pasture", "to_shed", "herded", "drinking"]):
			break
		t += 1.0
		await wait(1.0)


func command(what: String) -> void:
	## Із меню пастуха.
	if not on_duty:
		say("Зараз прийду на ферму!", 2.0)
		return
	cancel_job()
	var id := begin_job("herd")
	match what:
		"out":
			await cows_out()
		"water":
			await cows_drink()
		"in":
			await cows_in()
			if id == job:
				say("Уся худоба в корівниках!", 2.0)
	end_job(id)


func talk_nika() -> void:
	## «Поговорити»: обертається лицем до Ніки й заводить розмову.
	var nk: Node3D = main.girl
	_talk_t = 60.0
	if nk and main._mount_state == "":
		main._girl_face(global_position)
	var txt: String = lines[_line % lines.size()] if lines.size() > 0 else ""
	_line += 1
	say(txt, 3.5)
	main.audio.play_at("question", self, -4.0)
	var f := "res://assets/ui/shepherd.png"
	main.hud.show_dialog("Пастух Іван", txt + "\n" + _cows_news(), load(f) if ResourceLoader.exists(f) else null,
		func(): _talk_t = 0.0)


func _cows_news() -> String:
	var inside := 0
	var back := 0
	var river := 0
	var farm := 0
	for c in main.cows:
		if c.mode == "inside" or c.mode == "to_shed":
			inside += 1
		elif c.mode == "milking":
			farm += 1
		elif _zone(c.global_position) == "back":
			back += 1
		elif _zone(c.global_position) == "river":
			river += 1
		else:
			farm += 1
	var parts: Array = []
	if inside > 0:
		parts.append("у корівниках — %d" % inside)
	if farm > 0:
		parts.append("на фермі — %d" % farm)
	if back > 0:
		parts.append("на пасовиську за фермою — %d" % back)
	if river > 0:
		parts.append("біля річки — %d" % river)
	var t := ("Худоба зараз: " + ", ".join(parts) + ".\n") if not parts.is_empty() else ""
	return t + "Скажи, що робити: випустити худобу пастися, напоїти чи загнати в корівники."


func work_step() -> void:
	var id := begin_job("herd")
	var back: Array = main.cows.filter(func(c): return c.mode == "free" and _zone(c.global_position) == "back")
	var p: Vector3
	if not back.is_empty():
		p = Vector3(randf_range(OUT_PASTURE.position.x, OUT_PASTURE.end.x), 0, randf_range(OUT_PASTURE.end.y, OUT_PASTURE.end.y + 4.0))
	else:
		p = Vector3(randf_range(pasture.position.x, pasture.end.x), 0, randf_range(pasture.position.y, pasture.end.y + 2.0))
	await _walk(p)
	if id == job:
		var k: String = ["scratch", "shrug", "drink"][randi() % 3]
		await act(k, minf(anim_length(k), 4.0))
		if randf() < 0.3:
			say("Пасіться, пасіться…", 2.0)
	end_job(id)


func before_leave() -> void:
	await cows_in()
	say("Уся худоба вдома. Добраніч!", 2.0)
