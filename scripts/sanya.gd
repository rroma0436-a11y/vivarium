extends "res://scripts/npc.gd"
## Тракторист Саня — порається біля трактора під навісом на фермі. Що вміє (меню):
## поговорити; зорати пшеничне поле (лише коли пшеницю вже змолочено); забрати пшеницю від комбайна
## й висипати в бункер на фермі; завезти пшеницю дідові (від комбайна на дідовому полі — до воріт подвір'я);
## набрати зерна з бункера й відвезти в засік біля млина. Увесь час поїздки сидить за кермом,
## трактор їде сам (tractor.gd: drive_route, plow_field, reverse_to), причіп — trailer.gd.

var tractor
var trailer
var riding: Node3D = null                # сидить за кермом трактора
var _seat_l := Vector3.ZERO
var _talk_t := 0.0
var _day := -1
var _gp_heap: Node3D = null              # купка зерна біля воріт дідового подвір'я (до ранку)

# від причепа під навісом — проїздом на захід, між корівниками, до внутрішньої дороги ферми
const LANE_OUT := [Vector3(-145.0, 0, 48.6), Vector3(-150.5, 0, 47.2), Vector3(-158.0, 0, 46.8), Vector3(-166.0, 0, 47.0)]
# до передніх (південних) воріт і понад річкою на схід
const SOUTH_OUT := [Vector3(-171.5, 0, 53.0), Vector3(-171.5, 0, 78.0), Vector3(-171.5, 0, 86.0), Vector3(-169.0, 0, 93.0),
	Vector3(-160.0, 0, 95.0), Vector3(-120.0, 0, 95.0), Vector3(-60.0, 0, 95.0)]
# перед старим селом — ліворуч (на північ), повз подвір'я, польовою дорогою до пшеничного поля
const TO_WHEAT := [Vector3(-44.0, 0, 94.0), Vector3(-40.0, 0, 82.0), Vector3(-40.0, 0, 22.0), Vector3(-37.0, 0, 10.5),
	Vector3(-26.0, 0, 9.2), Vector3(-24.5, 0, -10.0), Vector3(-24.5, 0, -50.0), Vector3(-26.0, 0, -62.0)]
# понад річкою далі — до села, вулицею повз фонтан, перед садком праворуч — до дідового пшеничного поля
const TO_GP_FIELD := [Vector3(-6.0, 0, 94.8), Vector3(1.8, 0, 89.5), Vector3(2.0, 0, 72.0), Vector3(6.0, 0, 65.0),
	Vector3(7.5, 0, 60.0), Vector3(6.0, 0, 55.0), Vector3(1.5, 0, 50.0), Vector3(0.8, 0, 32.0), Vector3(2.5, 0, 27.0),
	Vector3(9.0, 0, 25.5), Vector3(22.0, 0, 25.5)]
# від дідового поля — повз садок на сільську вулицю (носом на південь), звідти заднім ходом до воріт подвір'я
const GP_AROUND := [Vector3(22.0, 0, 25.5), Vector3(9.0, 0, 26.0), Vector3(2.2, 0, 29.0), Vector3(0.7, 0, 34.0)]
const GP_HOME := [Vector3(0.8, 0, 30.0), Vector3(1.5, 0, 50.0), Vector3(6.0, 0, 55.0), Vector3(7.5, 0, 60.0), Vector3(6.0, 0, 65.0),
	Vector3(2.0, 0, 72.0), Vector3(1.8, 0, 89.5), Vector3(-6.0, 0, 94.8)]
const GP_GATE_Z := 7.6                   # задній борт причепа — перед ворітьми подвір'я (тин на z = 5.5)
# повернення на ферму: внутрішньою дорогою на північ, уздовж північного забору, повз навіс — на проїзд носом на захід
const LOOP_IN := [Vector3(-171.5, 0, 40.0), Vector3(-171.5, 0, 32.0), Vector3(-150.0, 0, 32.5), Vector3(-145.0, 0, 36.0),
	Vector3(-144.2, 0, 43.5), Vector3(-146.5, 0, 46.7), Vector3(-152.0, 0, 46.8), Vector3(-160.0, 0, 46.8)]
# через північні ворота — до пагорба з млином
const NORTH_OUT := [Vector3(-171.5, 0, 42.0), Vector3(-171.5, 0, 31.0), Vector3(-171.5, 0, 22.0), Vector3(-165.0, 0, 10.0),
	Vector3(-120.0, 0, 9.5), Vector3(-88.0, 0, 6.0), Vector3(-72.0, 0, -6.0)]
const LANE_Z := 46.8


# ------------------------------------------------------------------ кадр
func _process(delta: float) -> void:
	_day_step()
	if riding:
		if _bubble_left > 0.0:
			_bubble_left -= delta
			if _bubble_left <= 0.0:
				bubble.visible = false
		rotation.y = riding.rotation.y
		place_hips(riding.to_global(_seat_l))
		play("idle")
		if pose and riding.has_method("grip_global"):
			pose.ik = {"LeftHand": [riding.grip_global(true), 0.7], "RightHand": [riding.grip_global(false), 0.7]}
		return
	if _talk_t > 0.0:
		# розмовляє з героєм: стоїть лицем до нього
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
		play("idle")
		if pose:
			pose.life = lerpf(pose.life, 1.0, 1.0 - exp(-delta * 3.0))
		return
	super(delta)


func _day_step() -> void:
	## Новий день: зоране пшеничне поле знову колоситься, купка зерна біля дідових воріт зникає.
	var d := int(Game.state.get("day", 1))
	if d == _day or main == null or main.world == null:
		return
	if _day != -1:
		if str(Game.state.get("wheat_n", "ripe")) == "plowed":
			Game.state["wheat_n"] = "ripe"
		if _gp_heap:
			_gp_heap.queue_free()
			_gp_heap = null
	else:
		main.world.outer.set_mill_bin(int(Game.state.get("mill_grain", 0)))
	_day = d
	_apply_wheat()


func _apply_wheat() -> void:
	var st := str(Game.state.get("wheat_n", "ripe"))
	main.world.outer.set_wheat_ripe(st == "ripe")
	if tractor:
		var fn: Node3D = tractor.field_node(1)
		if fn:
			fn.visible = st != "ripe"


# ------------------------------------------------------------------ розмова й меню
func talk_nika() -> void:
	## «Поговорити»: обертається лицем до героя й заводить розмову.
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
	var f := "res://assets/ui/sanya.png"
	main.hud.show_dialog("Тракторист Саня", txt + "\n" + _news(), load(f) if ResourceLoader.exists(f) else null,
		func(): _talk_t = 0.0)


func _news() -> String:
	var t := ""
	if riding:
		t += "Я саме за кермом — %s.\n" % {"plow": "їду орати", "wheat": "вожу пшеницю в бункер", "grandpa": "везу пшеницю дідові",
			"mill": "везу зерно в млин"}.get(doing, "катаюся")
	match str(Game.state.get("wheat_n", "ripe")):
		"ripe":
			t += "Пшениця на полі ще стоїть — орати не можна, поки не змолотимо. "
		"threshed":
			t += "Пшеницю змолочено — поле можна орати. "
		"plowed":
			t += "Пшеничне поле зоране. "
	var b := int(Game.state.get("bunker", 0))
	t += "У бункері зерна: %d %s.\n" % [b, _loads(b)]
	return t + "Скажи, що робити: зорати поле, забрати пшеницю, завезти пшеницю дідові чи поїхати у млин."


func _loads(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "причіп"
	if n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		return "причепи"
	return "причепів"


func command(what: String) -> void:
	## Із меню тракториста.
	if doing != "" or riding:
		say("Я саме за кермом — спершу доїду!", 2.5)
		return
	_talk_t = 0.0
	match what:
		"plow":
			await plow_job()
		"wheat":
			await wheat_job()
		"grandpa":
			await grandpa_job()
		"mill":
			await mill_job()


func _check(need_plow: bool) -> String:
	## Чи можна їхати: трактор під навісом і вільний; плуг (для оранки) чи причіп (для зерна).
	if tractor == null or not is_instance_valid(tractor) or tractor.model == null:
		return "Трактора нема…"
	if tractor.state != "parked" or tractor.manual or tractor.driver != null or main._ctl_veh == tractor or main._mount == tractor:
		return "Трактор зараз зайнятий!"
	if Vector2(tractor.global_position.x - tractor.shed_pos.x, tractor.global_position.z - tractor.shed_pos.z).length() > 2.0:
		return "Трактор не під навісом — хтось на ньому поїхав!"
	if need_plow:
		if not tractor.plow_on or tractor.trailer:
			return "На тракторі нема плуга — нема чим орати!"
	elif trailer == null or trailer.model == null:
		return "Причепа нема — нема в що набрати пшеницю!"
	return ""


func _near(n: Node3D, r: Rect2) -> bool:
	return n != null and is_instance_valid(n) and r.grow(10.0).has_point(Vector2(n.global_position.x, n.global_position.z))


# ------------------------------------------------------------------ справи
func plow_job() -> void:
	var msg := _check(true)
	if msg != "":
		say(msg, 3.0)
		return
	match str(Game.state.get("wheat_n", "ripe")):
		"ripe":
			say("Пшениця ще не змолочена — орати не поїду!", 3.0)
			return
		"plowed":
			say("Пшеничне поле вже зоране!", 2.5)
			return
	var id := begin_job("plow")
	say("Поїду зорю пшеничне поле!", 2.5)
	await _get_in()
	await tractor.drive_route(LANE_OUT + SOUTH_OUT + TO_WHEAT, 3.4)
	tractor.use_field(1)
	await tractor.plow_field()
	tractor.use_field(0)
	Game.state["wheat_n"] = "plowed"
	say("Ото гарно зорали!", 2.5)
	await tractor.drive_route(_from_nearest(_rev(TO_WHEAT)) + _rev(SOUTH_OUT) + [Vector3(-166.0, 0, 47.0), Vector3(-158.0, 0, LANE_Z)], 3.4)
	await tractor.go_park([tractor.global_position])
	await _get_out()
	end_job(id)


func wheat_job() -> void:
	var msg := _check(false)
	if msg != "":
		say(msg, 3.0)
		return
	if str(Game.state.get("wheat_n", "ripe")) != "ripe":
		say("Пшеницю з поля вже забрали!", 2.5)
		return
	var cb: Node3D = main.combine
	if not _near(cb, main.world.outer.WHEAT_N):
		say("Комбайна на пшеничному полі нема — нема від кого брати пшеницю!", 3.5)
		return
	var id := begin_job("wheat")
	say("Поїду заберу пшеницю від комбайна!", 2.5)
	await _get_in()
	await _hitch()
	await tractor.drive_route(LANE_OUT + SOUTH_OUT + TO_WHEAT, 3.2)
	await _load_from_combine(cb)
	Game.state["wheat_n"] = "threshed"
	_apply_wheat()
	await tractor.drive_route(_from_nearest(_rev(TO_WHEAT)) + _rev(SOUTH_OUT) + LOOP_IN, 3.2)
	await _tip_into_bunker()
	Game.state["bunker"] = int(Game.state.get("bunker", 0)) + 1
	await _unhitch_and_park()
	await _get_out()
	end_job(id)


func grandpa_job() -> void:
	var msg := _check(false)
	if msg != "":
		say(msg, 3.0)
		return
	var cb: Node3D = main.combine
	if not _near(cb, main.world.outer.WHEAT):
		say("Комбайна на дідовому полі нема — нема від кого брати пшеницю!", 3.5)
		return
	var id := begin_job("grandpa")
	say("Завезу дідові пшениці!", 2.5)
	await _get_in()
	await _hitch()
	await tractor.drive_route(LANE_OUT + SOUTH_OUT + TO_GP_FIELD, 3.2)
	await _load_from_combine(cb)
	# об'їжджає садок, на вулиці — заднім ходом до воріт подвір'я
	await tractor.drive_route(GP_AROUND, 2.6)
	await tractor.reverse_to(Vector3(0.3, 0, GP_GATE_Z + _rear()), 0.0, 1.3)
	await _dump()
	_make_gp_heap()
	say("Дідусю, привіз тобі пшениці!", 3.0)
	await wait(1.0)
	await tractor.drive_route(GP_HOME + _rev(SOUTH_OUT) + LOOP_IN, 3.2)
	await _unhitch_and_park()
	await _get_out()
	end_job(id)


func mill_job() -> void:
	var msg := _check(false)
	if msg != "":
		say(msg, 3.0)
		return
	if int(Game.state.get("bunker", 0)) <= 0:
		say("Бункер порожній — спершу треба забрати пшеницю з поля!", 3.0)
		return
	var id := begin_job("mill")
	say("Повезу зерно в млин!", 2.5)
	await _get_in()
	await _hitch()
	await _load_from_bunker()
	Game.state["bunker"] = maxi(0, int(Game.state.get("bunker", 0)) - 1)
	var o = main.world.outer
	var m: Array = o.mill_dirs()
	var c: Vector3 = m[0]
	var dv: Vector3 = m[1]
	var sd: Vector3 = m[2]
	var bs: float = o.MILL_BIN_SIDE
	# угору дорогою, розворот на схилі — і носом униз уздовж засіку
	await tractor.drive_route([Vector3(-166.0, 0, 47.0)] + NORTH_OUT + [c + dv * 34.0, c + dv * 22.0, c + dv * 16.0,
		c + dv * 11.0 - sd * 1.0, c + dv * 8.5 + sd * 2.5, c + dv * 10.0 + sd * 5.5, c + dv * 15.0 + sd * bs], 3.0)
	await tractor.reverse_to(c + sd * bs + dv * (o.MILL_BIN_ALONG + 1.4 + _rear()), atan2(dv.x, dv.z), 1.2)
	await _dump()
	Game.state["mill_grain"] = int(Game.state.get("mill_grain", 0)) + 1
	o.set_mill_bin(int(Game.state["mill_grain"]))
	say("Є зерно в засіку — буде борошно!", 2.5)
	await wait(1.0)
	var back: Array = _rev(NORTH_OUT).slice(0, 5)
	await tractor.drive_route([c + dv * 20.0 + sd * 3.0, c + dv * 34.0] + back + LOOP_IN.slice(1), 3.0)
	await _unhitch_and_park()
	await _get_out()
	end_job(id)


# ------------------------------------------------------------------ причіп, зерно
func _rear() -> float:
	## Від трактора до заднього борту причепа (уздовж руху).
	return trailer.EYE.z + 1.4 + 0.12 - tractor.hitch_local.z


func _bed() -> float:
	## Від трактора до середини кузова причепа.
	return trailer.EYE.z - 0.12 + 0.12 - tractor.hitch_local.z


func _fwd(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))


func _hitch() -> void:
	## Плуг лишає під навісом, підганяє трактор задом до дишла причепа й причеплює його.
	if tractor.trailer == trailer:
		return
	if tractor.plow_on:
		tractor.detach_plow()
	var yaw: float = trailer.rotation.y
	var f := _fwd(yaw)
	var t0: Vector3 = tractor.hitch_pose_for(trailer.eye_global(), yaw)
	say("Причеплю причіп!", 2.0)
	await tractor.drive_route([tractor.global_position + _fwd(tractor.rotation.y) * 6.0, t0 + f * 9.5, t0 + f * 15.0], 2.2)
	await tractor.reverse_to(t0, yaw, 1.1)
	await wait(0.5)
	if tractor.attach_trailer(trailer) != "ok":
		# не дотягнулись до петлі — підсуваємо причіп точно до зчіпки
		var h: Vector3 = tractor.hitch_global()
		trailer.rotation.y = tractor.rotation.y
		trailer.global_position = Vector3(h.x, trailer.global_position.y, h.z) - Basis(Vector3.UP, tractor.rotation.y) * Vector3(0, 0, trailer.EYE.z)
		tractor.attach_trailer(trailer)
	await wait(0.4)


func _unhitch_and_park() -> void:
	## Ставить причіп на його місце під навісом (заднім ходом), відчіплює, а трактор — під навіс; плуг — назад.
	var o = main.world.outer
	var yaw: float = o.SHED_YAW
	var eye: Vector3 = o.TRAILER_PARK + Basis(Vector3.UP, yaw) * trailer.EYE
	var t0: Vector3 = tractor.hitch_pose_for(eye, yaw)
	await tractor.reverse_to(t0, yaw, 1.2)
	await wait(0.4)
	tractor.detach_trailer()
	trailer.global_position = Vector3(o.TRAILER_PARK.x, trailer.global_position.y, o.TRAILER_PARK.z)
	trailer.rotation.y = yaw
	say("Причіп — на місці.", 2.0)
	await tractor.drive_route([t0 + _fwd(yaw) * 9.0], 2.2)
	await tractor.go_park([tractor.global_position])
	tractor.attach_plow()


func _load_from_combine(cb: Node3D) -> void:
	## Під'їжджає до комбайна з боку шнека (причіп — під кінцем шнека) і чекає, доки комбайн висипле зерно.
	var f := cb.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var t: Vector3 = cb.to_global(Vector3(cb.SPOUT.x, 0, cb.SPOUT.z)) + f * _bed()
	t.y = 0.0
	await tractor.drive_route([t - f * 16.0, t - f * 7.0, t], 2.4)
	say("Висипай!", 1.5)
	cb.auger_out(true)
	while not cb.auger_ready():
		await get_tree().process_frame
	cb.pour(true)
	await _fill(8.0)
	cb.pour(false)
	cb.auger_out(false)
	say("Повний причіп!", 2.0)
	await wait(1.5)


func _load_from_bunker() -> void:
	## Підставляє причіп під жолоб бункера й набирає зерна.
	var o = main.world.outer
	var sp: Vector3 = o.BUNKER_SPOUT
	await tractor.drive_route([Vector3(-145.0, 0, 48.6), Vector3(-150.5, 0, 47.4), Vector3(sp.x - _bed(), 0, sp.z)], 2.0)
	say("Набираю зерно з бункера!", 2.0)
	await wait(0.6)
	o.bunker_stream.emitting = true
	await _fill(7.0)
	o.bunker_stream.emitting = false
	await wait(0.8)


func _fill(secs: float) -> void:
	var g0: float = trailer.grain
	var t := 0.0
	while t < secs:
		t += get_process_delta_time()
		trailer.set_grain(lerpf(g0, 1.0, t / secs))
		await get_tree().process_frame


func _tip_into_bunker() -> void:
	## Заднім ходом — бортом причепа над ґраткою ями біля бункера, піднімає кузов і висипає.
	var o = main.world.outer
	var pit: Vector3 = o.BUNKER_PIT
	await tractor.reverse_to(Vector3(pit.x - 0.5 - _rear(), 0, LANE_Z), -PI / 2.0, 1.2)
	await _dump()


func _dump() -> void:
	## Піднімає кузов причепа, зерно висипається, кузов опускається.
	say("Піднімаю кузов!", 1.8)
	trailer.tip_want = 1.0
	while trailer.tip_k < 0.5:
		await get_tree().process_frame
	trailer.pour(true)
	var g0: float = trailer.grain
	var t := 0.0
	while t < 4.5:
		t += get_process_delta_time()
		trailer.set_grain(g0 * (1.0 - t / 4.5))
		await get_tree().process_frame
	trailer.set_grain(0.0)
	trailer.pour(false)
	await wait(0.6)
	trailer.tip_want = 0.0
	while trailer.tip_k > 0.02:
		await get_tree().process_frame


func _make_gp_heap() -> void:
	## Купка зерна перед воротами дідового подвір'я.
	if _gp_heap:
		_gp_heap.queue_free()
	var gm := Util.mat(Color(0.84, 0.66, 0.3), 0.95)
	var hp := Util.sphere(1.0, gm, Vector3(0.3, 0.0, GP_GATE_Z - 0.6), Vector3(0.9, 0.38, 0.75))
	hp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.world.yard_root.add_child(hp)
	_gp_heap = hp


# ------------------------------------------------------------------ маршрути
func _rev(a: Array) -> Array:
	var r := a.duplicate()
	r.reverse()
	return r


func _from_nearest(route: Array) -> Array:
	var best := 0
	var bd := INF
	for i in route.size():
		var d: float = tractor.global_position.distance_to(route[i])
		if d < bd:
			bd = d
			best = i
	return route.slice(best)


# ------------------------------------------------------------------ у кабіну й з кабіни
func _get_in() -> void:
	## Підходить до трактора, лізе на сидіння й заводить мотор.
	tractor.driver = self
	await _board(tractor)
	tractor.start_engine()
	await wait(1.0)


func _get_out() -> void:
	tractor.state = "parked"
	await _alight(tractor)
	tractor.driver = null
	if not places.is_empty():
		await go(places[randi() % places.size()])


func _goto(p: Vector3, tol := 1.3) -> void:
	for i in 5:
		await go(p)
		if global_position.distance_to(p) < tol:
			return


func _hop(v: Node3D, pts: Array, rels: Array, sits: Array, seg := 0.45) -> void:
	## Лізе по точках pts (у системі трактора): стегна йдуть від точки до точки, поворот і посадка — поступово.
	for i in pts.size() - 1:
		var t := 0.0
		play("walk", 0.6)
		while t < seg:
			t = minf(seg, t + get_process_delta_time())
			var k := smoothstep(0.0, 1.0, t / seg)
			var p: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], k)
			p.y += sin(k * PI) * 0.08
			if pose:
				pose.sit = lerpf(float(sits[i]), float(sits[i + 1]), k)
			rotation.y = v.rotation.y + lerp_angle(float(rels[i]), float(rels[i + 1]), k)
			place_hips(v.to_global(p))
			await get_tree().process_frame


func _cab_path(v: Node3D) -> Array:
	## Від землі біля трактора — приступкою на площадку й на сидіння (стегна; у системі трактора).
	var cp: Dictionary = v.cab_points()
	var hh := maxf(0.3, hips_world().y - global_position.y)
	var pts: Array = [(cp["climb"] as Vector3) + Vector3(0, hh, 0)]
	var steps: Array = cp.get("steps", [])
	for i in range(0, steps.size(), 2):
		pts.append((steps[i] as Vector3) + Vector3(0, hh * 0.8, 0))
	if cp.has("sill"):
		pts.append((cp["sill"] as Vector3) + Vector3(0, hh * 0.8, 0))
	pts.append(cp["seat"])
	return pts


func _board(v: Node3D) -> void:
	var cp: Dictionary = v.cab_points()
	await _goto(v.to_global(cp["climb"]), 0.6)
	await go(v.to_global(cp["climb"]), false, false)
	stop()
	_face_to = NAN
	busy = true
	var pts := _cab_path(v)
	pts.push_front(v.to_local(hips_world()))
	var side := float(cp.get("side", -1.0))
	var rels: Array = [wrapf(rotation.y - v.rotation.y, -PI, PI)]
	var sits: Array = [0.0]
	for i in pts.size() - 1:
		var last := i == pts.size() - 2
		rels.append(0.0 if last else -side * PI / 2.0)
		sits.append(1.0 if last else 0.0)
	await _hop(v, pts, rels, sits)
	_seat_l = pts.back()
	if pose:
		pose.sit = 1.0
	busy = false
	riding = v


func _alight(v: Node3D) -> void:
	riding = null
	if pose:
		pose.ik = {}
	stop()
	_face_to = NAN
	busy = true
	var pts := _cab_path(v)
	pts.reverse()
	var side := float(v.cab_points().get("side", -1.0))
	var rels: Array = [0.0]
	var sits: Array = [1.0]
	for i in pts.size() - 1:
		rels.append(-side * PI / 2.0)
		sits.append(0.0)
	await _hop(v, pts, rels, sits)
	var g: Vector3 = v.to_global(v.cab_points()["climb"])
	g.y = 0.0
	global_position = g
	if pose:
		pose.sit = 0.0
	model.position.y = _base_y
	busy = false
	play("idle")
