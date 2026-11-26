extends "res://scripts/farmhand.gd"
## Пастух дід Іван: живе в хаті села. Зранку приходить на ферму, виганяє худобу через задні ворота
## корівників на пасовисько, цілий день пасе, увечері заганяє в корівник і йде додому.

var door := Vector3.ZERO
var pasture: Rect2
const BACK_GATE := Vector3(-154.6, 0, 55.0)          # біля задніх воріт середнього корівника (з боку пасовиська)
const AROUND := Vector3(-152.0, 0, 32.0)             # обхід корівників з півночі


func setup_shepherd(cow_door: Vector3, past: Rect2, home: Vector3, route: Array) -> void:
	door = cow_door
	pasture = past
	setup("shepherd", 1.7, {"walk": ["walking"], "run": ["running"], "talk": ["talk_with_left"],
			"scratch": ["confused_scratch"], "shrug": ["shrug"], "drink": ["stand_and_drink"], "pick": ["female_bend_over"]},
		["walk", "run"],
		["Я — Іван, пасу худобу з-змалечку.", "Зірка сьогодні норовлива, а Ласка — тиха.", "Трава цього року соковита!",
		 "Бичок у нас сильний — не підходь ззаду.", "Зранку виганяю через задні ворота, а ввечері — у корівник."],
		[], "npc")
	Models.give_nika_anims(ap, anims)
	make_idle_from("walk")
	setup_pose()
	for c in main.cows:
		c.keeper_only = true
	start_farm(home, route, 6.6, 19.3)


func _to_back_gate() -> void:
	if global_position.x < -158.0:
		await _goto(AROUND)
	await _goto(BACK_GATE)
	face(BACK_GATE + Vector3(-3, 0, 0))


func on_arrived() -> void:
	await herd_out()
	await _goto(Vector3(pasture.get_center().x, 0, pasture.end.y + 1.5))


func herd_out() -> void:
	## Відчиняє задні ворота корівників і виганяє худобу на пасовисько.
	await _to_back_gate()
	say("Виходьте, мої красуні, — на пасовисько!", 2.5)
	await act("talk", 2.5)
	for c in main.cows:
		if c.mode == "inside" or c.mode == "to_shed":
			c.send_out()
			await wait(0.9)


func herd_in() -> void:
	## Заганяє худобу через задні ворота в корівники й чекає, поки всі зайдуть.
	await _goto(Vector3(pasture.get_center().x, 0, pasture.get_center().y))
	say("Додому, корівки, у корівник!", 2.5)
	await act("talk", 2.0)
	await _to_back_gate()
	for c in main.cows:
		if c.mode != "inside" and c.mode != "hitched" and c.mode != "milking":
			c.kept_in = true
			c.send_home()
	var t := 0.0
	while t < 60.0:
		var all_in := true
		for c in main.cows:
			if c.mode != "inside" and c.mode != "milking":
				all_in = false
		if all_in:
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
			await herd_out()
			if id == job:
				await _goto(Vector3(pasture.get_center().x, 0, pasture.end.y + 1.5))
		"in":
			await herd_in()
			if id == job:
				say("Усі в корівнику!", 2.0)
	end_job(id)


func work_step() -> void:
	var id := begin_job("herd")
	var p := Vector3(randf_range(pasture.position.x, pasture.end.x), 0, randf_range(pasture.position.y, pasture.end.y + 2.0))
	await _goto(p, 1.5)
	if id == job:
		var r := randi() % 3
		var k: String = ["scratch", "shrug", "drink"][r]
		await act(k, minf(anim_length(k), 4.0))
		if randf() < 0.3:
			say("Пасіться, пасіться…", 2.0)
	end_job(id)


func before_leave() -> void:
	await herd_in()
	say("Усі вдома. Добраніч!", 2.0)
	await _goto(AROUND)
