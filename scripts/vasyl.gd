extends "res://scripts/sanya.gd"
## Комбайнер Василь — порається біля комбайна під навісом на фермі. Що вміє (меню):
## поговорити; змолотити пшеницю (поле за старим селом); змолотити діду (дідове поле за садком).
## Лізе в кабіну, через передні ворота й понад річкою їде на поле, молотить, чекає тракториста Саню
## (шнек повертається до причепа), висипає зерно й вертається на ферму. Живе в новому селі, на роботу — велосипедом.
## Посадка в кабіну, сидіння за кермом, розмова — як у Сані (sanya.gd); комбайн їде сам (combine.gd).

var combine

# з-під навісу: уперед на захід, повз бункер на північ, уздовж північного забору — до внутрішньої дороги ферми
const FARM_OUT := [Vector3(-143.0, 0, 40.0), Vector3(-146.0, 0, 36.5), Vector3(-150.0, 0, 32.6), Vector3(-162.0, 0, 32.2),
	Vector3(-171.5, 0, 36.0), Vector3(-171.5, 0, 44.0)]
# назад: внутрішньою дорогою на північ, уздовж забору, петлею носом на захід — і заднім ходом під навіс
const FARM_IN := [Vector3(-171.5, 0, 44.0), Vector3(-171.5, 0, 36.0), Vector3(-162.0, 0, 32.2), Vector3(-150.0, 0, 32.6),
	Vector3(-145.5, 0, 34.5), Vector3(-142.5, 0, 38.0), Vector3(-144.0, 0, 41.8), Vector3(-147.0, 0, 40.6)]
# пшеничне поле: з дороги — повз копицю на південно-східний ріг поля (звідти перший ряд)
const N_ENTER := [Vector3(-25.5, 0, -68.5), Vector3(-17.5, 0, -72.5)]
# після останнього ряду — петлею на місце, де чекає тракториста: носом на північ, шнек — до дороги
const N_WAIT := [Vector3(-44.5, 0, -66.5), Vector3(-39.5, 0, -65.5), Vector3(-36.2, 0, -69.5), Vector3(-36.0, 0, -76.0)]
const N_BACK := [Vector3(-36.0, 0, -84.0), Vector3(-31.0, 0, -86.0), Vector3(-28.0, 0, -80.0), Vector3(-27.0, 0, -70.0)]
# дідове поле: після останнього ряду — на місце, де чекає тракториста: носом на захід, шнек — на північ
const GP_WAIT := [Vector3(30.5, 0, 43.0), Vector3(36.0, 0, 42.0), Vector3(47.0, 0, 35.5), Vector3(44.5, 0, 30.3), Vector3(40.0, 0, 30.0)]


func _day_step() -> void:
	pass                                     # день на полі веде Саня


# ------------------------------------------------------------------ розмова й меню
func talk_nika() -> void:
	var nk: Node3D = main.girl
	if riding == null:
		stop()
		_talk_t = 60.0
	if nk and main._mount_state == "":
		main._girl_face(global_position)
	var txt: String = lines[_line % lines.size()] if lines.size() > 0 else ""
	_line += 1
	say(txt, 3.5)
	main.audio.play_at("question", self, -4.0)
	var f := "res://assets/ui/vasyl.png"
	main.hud.show_dialog("Комбайнер Василь", txt + "\n" + _news(), load(f) if ResourceLoader.exists(f) else null,
		func(): _talk_t = 0.0)


func _news() -> String:
	var t := ""
	if riding:
		t += "Я саме за кермом комбайна — %s.\n" % {"wheat": "молочу пшеницю", "grandpa": "молочу дідові"}.get(doing, "їду")
	if str(Game.state.get("wheat_n", "ripe")) == "ripe":
		t += "Пшениця на полі колоситься — можна молотити.\n"
	else:
		t += "Пшеничне поле вже змолочене.\n"
	return t + "Скажи, що робити: змолотити пшеницю чи змолотити діду."


func command(what: String) -> void:
	## Із меню комбайнера.
	if doing != "" or riding:
		say("Я саме за кермом — спершу доїду!" if riding else "Зачекай, я зайнятий!", 2.5)
		return
	_talk_t = 0.0
	match what:
		"wheat":
			await thresh_job(false)
		"grandpa":
			await thresh_job(true)


func _check_cb() -> String:
	## Чи можна їхати: комбайн під навісом і вільний.
	if combine == null or not is_instance_valid(combine) or combine.model == null:
		return "Комбайна нема…"
	if combine.driver != null or main._ctl_veh == combine or main._mount == combine:
		return "Комбайн зараз зайнятий!"
	var cp: Vector3 = main.world.outer.COMBINE_POS
	if Vector2(combine.global_position.x - cp.x, combine.global_position.z - cp.z).length() > 3.0:
		return "Комбайн не під навісом — хтось на ньому поїхав!"
	return ""


# ------------------------------------------------------------------ молотьба
func thresh_job(gp: bool) -> void:
	var msg := _check_cb()
	if msg != "":
		say(msg, 3.0)
		return
	if not gp and str(Game.state.get("wheat_n", "ripe")) != "ripe":
		say("Пшеницю на полі вже змолочено!", 2.5)
		return
	var o = main.world.outer
	var cb = combine
	var id := begin_job("grandpa" if gp else "wheat")
	say("Поїду змолочу дідові пшеницю!" if gp else "Поїду молотити пшеницю!", 2.5)
	await _get_in()
	# через передні ворота, понад річкою; перед старим селом — ліворуч (на пшеничне поле) чи перед садком — праворуч (на дідове)
	await cb.drive_route(FARM_OUT + SOUTH_OUT + (TO_GP_FIELD if gp else TO_WHEAT + N_ENTER), 3.0)
	say("Молотимо!", 2.0)
	await cb.harvest_field(o.WHEAT if gp else o.WHEAT_N, not gp)
	if not gp:
		o.set_wheat_ripe(false)
		var fn: Node3D = tractor.field_node(1) if tractor else null
		if fn:
			fn.visible = true                    # стерня
	await cb.drive_route(GP_WAIT if gp else N_WAIT, 2.2)
	cb.ready_unload = true
	say("Змолотив! Чекаю тракториста.", 3.0)
	var ok := await _wait_tractor(cb, gp)
	cb.ready_unload = false
	if ok:
		say("Ото гарне зерно!", 2.5)
		await wait(3.0)
		if gp:
			# хай трактор спершу відвезе пшеницю до дідових воріт і виїде з вулиці
			var sn = main.sanya
			while is_instance_valid(sn) and sn.doing == "grandpa" and tractor and tractor.global_position.z < 48.0:
				await wait(0.5)
	else:
		say("Тракторист уже пішов додому — завтра заберемо.", 3.5)
		await wait(2.0)
	# назад тією ж дорогою — на ферму
	var back: Array = _rev(TO_GP_FIELD) if gp else N_BACK + _rev(TO_WHEAT)
	await cb.drive_route(back + _rev(SOUTH_OUT) + FARM_IN, 3.0)
	await cb.reverse_to(o.COMBINE_POS, o.SHED_YAW, 1.0)
	cb.state = "parked"
	await _get_out()
	end_job(id)


func _wait_tractor(cb, gp: bool) -> bool:
	## Чекає, доки тракторист під'їде й забере зерно; вільного Саню кличе сам. false — Саня вже пішов додому.
	var u0: int = cb.unloads
	var job_n := "grandpa" if gp else "wheat"
	var call_t := 0.0
	while cb.unloads == u0:
		var sn = main.sanya
		var ok_sn: bool = sn != null and is_instance_valid(sn)
		var coming: bool = ok_sn and sn.doing == job_n
		var free: bool = ok_sn and sn.visible and sn.on_duty and sn.doing == "" and sn.riding == null and not sn._on_bike
		if free and call_t <= 0.0:
			call_t = 30.0
			say("Саню! Приїжджай по зерно!", 3.0)
			sn.command(job_n)
		elif not coming and not free and not on_time():
			return false
		call_t -= 1.0
		await wait(1.0)
	return true


# ------------------------------------------------------------------ у кабіну комбайна й з кабіни
func _cab_path(v: Node3D) -> Array:
	## Драбинкою на площадку, площадкою до дверей кабіни, порогом — на сидіння.
	var pts: Array = super(v)
	var cp: Dictionary = v.cab_points()
	if cp.get("ladder", false):
		var hh := maxf(0.3, hips_world().y - global_position.y)
		var y := float(cp["deck_y"]) + hh
		var i := pts.size() - 2                  # перед порогом
		pts.insert(i, Vector3(float(cp["deck_x"]), y, float(cp["door_z"])))
		pts.insert(i, Vector3(float(cp["deck_x"]), y, float(cp["ladder_z"])))
	return pts


func _get_in() -> void:
	## Підходить до драбинки, лізе в кабіну, зачиняє двері й заводить мотор.
	combine.driver = self
	combine.open_door(true)
	await _board(combine)
	combine.open_door(false)
	combine.start_engine()
	await wait(1.0)


func _get_out() -> void:
	combine.open_door(true)
	await _alight(combine)
	combine.open_door(false)
	combine.driver = null
	if not places.is_empty():
		await go(places[randi() % places.size()])
