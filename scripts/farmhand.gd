extends "res://scripts/npc.gd"
## Працівник ферми: зранку з'являється (приходить із хати біля базару), робить свої справи,
## ввечері, коли все зроблено, іде додому й зникає до ранку.
## Похідні класи (groom, shepherd, granny) задають work_step() і before_leave().

const WIDE := Rect2(-70.0, -62.0, 140.0, 160.0)
var home_spot := Vector3.ZERO          # де «заходить у хату» (перед будинком)
var way: Array = []                    # від хати до ферми
var arrive_h := 6.8
var leave_h := 19.3
var on_duty := false
var _pause_work := 2.0


func start_life(home: Vector3, route: Array, from_h: float, to_h: float) -> void:
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
	await appear()
	for wp in way:
		await _goto(wp)
	on_duty = true
	await on_arrived()
	end_job(id)


func _leave() -> void:
	var id := begin_job("leave")
	await before_leave()
	for i in range(way.size() - 1, -1, -1):
		await _goto(way[i])
	await vanish()
	on_duty = false
	end_job(id)


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
