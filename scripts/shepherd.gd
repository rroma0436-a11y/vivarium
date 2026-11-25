extends "res://scripts/farmhand.gd"
## Пастух дід Іван: зранку виганяє худобу з корівника на пасовисько, цілий день пасе,
## увечері заганяє назад і йде додому.

var door := Vector3.ZERO
var pasture: Rect2


func setup_shepherd(cow_door: Vector3, past: Rect2, home: Vector3, route: Array) -> void:
	door = cow_door
	pasture = past
	setup("shepherd", 1.7, {"walk": ["walking"], "run": ["running"], "talk": ["talk_with_left"],
			"scratch": ["confused_scratch"], "shrug": ["shrug"], "drink": ["stand_and_drink"], "pick": ["female_bend_over"]},
		["walk", "run"],
		["Я — Іван, пасу худобу з-змалечку.", "Зірка сьогодні норовлива, а Ласка — тиха.", "Трава цього року соковита!",
		 "Бичок у нас сильний — не підходь ззаду.", "Ввечері заганяю їх у корівник."],
		[], "npc")
	Models.give_nika_anims(ap, anims)
	make_idle_from("walk")
	setup_pose()
	bounds = Rect2(-200.0, -62.0, 270.0, 160.0)      # до ферми за ставком
	extra_obs = Obstacles.outer
	for c in main.cows:
		c.keeper_only = true
	start_life(home, route, 6.6, 19.3)


func on_arrived() -> void:
	await _goto(door + Vector3(1.5, 0, 0.0))
	face(door)
	say("Виходьте, мої красуні!", 2.5)
	await act("talk", 2.5)
	for c in main.cows:
		if c.mode != "hitched":
			c.send_out()
			await wait(0.9)
	await _goto(Vector3(pasture.get_center().x, 0, pasture.end.y + 1.5))


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
	say("Пора додому, корівки!", 2.5)
	await _goto(door + Vector3(3.5, 0, 0.0))
	for c in main.cows:
		if c.mode != "inside" and c.mode != "hitched":
			c.kept_in = true
			c.send_home()
	var t := 0.0
	while t < 60.0:
		var all_in := true
		for c in main.cows:
			if c.mode != "inside":
				all_in = false
		if all_in:
			break
		t += 1.0
		await wait(1.0)
	say("Усі вдома. Добраніч!", 2.0)
