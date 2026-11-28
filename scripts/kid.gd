extends "res://scripts/farmhand.gd"
## Тарасик, сусідський хлопчик: живе в хаті села, зранку йде на ферму працювати — розносить сіно з копиці
## по корівниках і стайнях, вивозить тачкою гній під паркан; увечері — додому.
## Як попросять — іде на подвір'я, носить воду з криниці: Бімові в мисочку й курям у корито.

const COW_DOORS := [Vector3(-166.9, 0, 39.0), Vector3(-166.9, 0, 55.0), Vector3(-166.9, 0, 71.0)]
const STABLE_DOORS := [Vector3(-187.0, 0, 39.7), Vector3(-187.0, 0, 55.7), Vector3(-187.0, 0, 71.7)]

var bucket: Node3D
var bucket_water: MeshInstance3D
var _water_day := -1


func make_bucket() -> void:
	## Відро стоїть біля криниці, коли ним не користуються.
	bucket = Node3D.new()
	var tin := Util.mat(Color(0.62, 0.66, 0.7), 0.35, 0.6)
	bucket.add_child(Util.cyl(0.13, 0.1, 0.24, tin, Vector3(0, 0.12, 0)))
	bucket_water = Util.cyl(0.12, 0.12, 0.01, Util.mat(Color(0.5, 0.75, 1.0), 0.05, 0.0, Color(0.3, 0.6, 0.9), 0.2), Vector3(0, 0.21, 0))
	bucket.add_child(bucket_water)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.12
	tm.outer_radius = 0.13
	tm.rings = 12
	tm.ring_segments = 4
	handle.mesh = tm
	handle.material_override = tin
	handle.rotation_degrees = Vector3(90, 0, 0)
	handle.position = Vector3(0, 0.24, 0)
	handle.scale = Vector3(1, 1, 1.0)
	bucket.add_child(handle)
	bucket_water.visible = false
	main.world.yard_root.add_child(bucket)
	bucket.position = main.world.spots["well_front"] + Vector3(-0.3, 0, -0.5)
	Walker.remember_home(bucket)
	make_barrow()


func _barns() -> Array:
	## [двері, звідки підходити (зовні), корівник?, у дверях (всередині), у кінці (годувати), куди класти сіно, де стати з тачкою]
	var list: Array = []
	for d in COW_DOORS:
		var z: float = d.z
		list.append([d, d + Vector3(-1.3, 0, 0), true, Vector3(-164.6, 0, z), Vector3(-159.9, 0, z), Vector3(-159.2, 0.12, z - 0.5),
			Vector3(-162.0, 0, z)])
	for d in STABLE_DOORS:
		var z2: float = d.z
		list.append([d, d + Vector3(1.3, 0, 0), false, Vector3(-189.3, 0, z2), Vector3(-192.1, 0, z2), Vector3(-192.8, 0.12, z2 - 0.5),
			Vector3(-189.9, 0, z2)])
	return list


func _bundle() -> MeshInstance3D:
	return Util.sphere(0.22, Util.mat(Color(0.86, 0.74, 0.38), 0.95), Vector3.ZERO, Vector3(1.3, 0.8, 1.0))


func _fork() -> Node3D:
	## Вила-гнойовики: держак і зубці.
	var f := Node3D.new()
	var wood := Util.mat(Color(0.6, 0.44, 0.26), 0.9)
	var iron := Util.mat(Color(0.45, 0.45, 0.48), 0.4, 0.6)
	f.add_child(Util.cyl(0.018, 0.018, 1.1, wood, Vector3(0, 0, 0)))
	f.add_child(Util.box(Vector3(0.2, 0.03, 0.03), iron, Vector3(0, -0.55, 0)))
	for k in 4:
		f.add_child(Util.cyl(0.008, 0.004, 0.2, iron, Vector3(-0.09 + k * 0.06, -0.66, 0)))
	return f


# ------------------------------------------------------------------ тачка й вила (стоять біля дідового плуга під садком)
const BARROW_HOME := Vector3(21.5, 0, 13.6)          # тачка: колесом до плуга, ручками до дороги
const BARROW_WAY := Vector3(21.5, 0, 11.3)           # звідти підходить до тачки з дороги
const BARROW_PARK := Vector3(21.5, 0, 12.55)         # де стоїть, ставлячи тачку на місце
const FORK_HOME := Vector3(20.7, 0.74, 14.4)         # вила стоять, сперті на плуг
const FORK_IN := Vector3(0.0, 0.55, 0.12)            # вила лежать у тачці
const BARROW_SIZE := 0.55
const GRIP := Vector3(0.8, 0.4, 0.25)                # ручки тачки (у системі тачки; +X — до ручок, колесо — на −X)
const PUSH_AHEAD := 1.05                             # центр тачки перед Тарасиком
const DUMP := Vector3(-161.5, 0, 29.6)               # купа гною під парканом: 10 м праворуч від задніх воріт
const DUMP_STAND := Vector3(-161.5, 0, 32.4)
const FARM_LANE := Vector3(-170.0, 0, 34.0)

var barrow: Node3D
var barrow_fork: Node3D
var barrow_load: MeshInstance3D
var dung_heap: MeshInstance3D
var _heap_n := 0
var _pushing := false
var _talk_t := 0.0
var _fed_day := -1
var _clean_day := -1


func make_barrow() -> void:
	var root: Node3D = main.world.yard_root
	barrow = Node3D.new()
	barrow.name = "KidBarrow"
	root.add_child(barrow)
	if Models.spawn(barrow, "wheelbarrow", BARROW_SIZE) == null:
		barrow.add_child(Util.box(Vector3(1.2, 0.3, 0.6), Util.mat(Color(0.5, 0.36, 0.22), 0.9), Vector3(-0.1, 0.35, 0)))
	barrow_load = Util.sphere(0.3, Util.mat(Color(0.32, 0.24, 0.14), 1.0), Vector3(-0.15, 0.42, 0), Vector3(1.4, 0.4, 0.9))
	barrow_load.visible = false
	barrow.add_child(barrow_load)
	barrow.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), BARROW_HOME)
	barrow_fork = _fork()
	root.add_child(barrow_fork)
	barrow_fork.transform = Transform3D(Basis(Vector3.RIGHT, 0.2), FORK_HOME)
	Walker.remember_home(barrow_fork)
	dung_heap = Util.sphere(1.0, Util.mat(Color(0.3, 0.22, 0.13), 1.0), DUMP, Vector3(1.0, 0.45, 0.8))
	dung_heap.visible = false
	root.add_child(dung_heap)


func _fork_into_barrow() -> void:
	if barrow_fork.get_parent():
		barrow_fork.get_parent().remove_child(barrow_fork)
	barrow.add_child(barrow_fork)
	barrow_fork.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0 + 0.15), FORK_IN)


func _stow_tools() -> void:
	## Тачка й вила — на свої місця біля плуга (справу перервали чи закінчили).
	_pushing = false
	if barrow == null:
		return
	if pose:
		pose.ik = {}
	var root: Node3D = main.world.yard_root
	if barrow.get_parent() != root:
		barrow.reparent(root, false)
	barrow.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), BARROW_HOME)
	barrow_load.visible = false
	if barrow_fork != held:
		if barrow_fork.get_parent():
			barrow_fork.get_parent().remove_child(barrow_fork)
		root.add_child(barrow_fork)
		barrow_fork.transform = Transform3D(Basis(Vector3.RIGHT, 0.2), FORK_HOME)


func put_back_held() -> void:
	super()
	_stow_tools()


func _barrow_ik() -> void:
	if not _pushing or pose == null or barrow == null:
		return
	pose.ik = {"LeftHand": [barrow.to_global(Vector3(GRIP.x, GRIP.y, GRIP.z)), 1.0],
		"RightHand": [barrow.to_global(Vector3(GRIP.x, GRIP.y, -GRIP.z)), 1.0]}


func _grab_barrow(id: int) -> void:
	## Стає між ручками, береться за них і піднімає тачку (колесо — уперед).
	var f: Vector3 = -barrow.global_transform.basis.x
	f.y = 0.0
	f = f.normalized()
	var at: Vector3 = barrow.global_position - f * PUSH_AHEAD
	at.y = 0.0
	await go(at, false, false)
	if id != job:
		return
	stop()
	_face_to = NAN
	global_position = Vector3(at.x, global_position.y, at.z)
	rotation.y = atan2(f.x, f.z)
	barrow.reparent(self, false)
	barrow.transform = Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.BACK, deg_to_rad(8.0)), Vector3(0, 0.1, PUSH_AHEAD))
	_pushing = true
	_barrow_ik()
	await wait(0.3)


func _park_barrow() -> void:
	## Опускає тачку на землю там, де стоїть.
	_pushing = false
	if pose:
		pose.ik = {}
	var g := barrow.global_transform
	var f := -g.basis.x
	f.y = 0.0
	barrow.reparent(main.world.yard_root, false)
	barrow.global_transform = Transform3D(Basis(Vector3.UP, atan2(f.z, -f.x)), Vector3(g.origin.x, global_position.y, g.origin.z))
	await wait(0.3)


func _tip_barrow() -> void:
	## Піднімає ручки — гній висипається під паркан.
	var b0 := barrow.transform
	var t := 0.0
	while t < 1.6:
		t += get_process_delta_time()
		var k := sin(clampf(t / 1.6, 0.0, 1.0) * PI)
		barrow.transform = Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.BACK, deg_to_rad(8.0 + 32.0 * k)), b0.origin + Vector3(0, 0.25 * k, 0))
		if t > 0.8 and barrow_load.visible:
			barrow_load.visible = false
			_heap_n += 1
			dung_heap.visible = true
			dung_heap.scale = Vector3(1.0, 0.45, 0.8) * minf(1.6, 0.45 + _heap_n * 0.12)
			_sound("pop")
		await get_tree().process_frame
	barrow.transform = b0


func _near_way() -> int:
	var near := way.size() - 1
	var bd := INF
	for i in way.size():
		var d: float = global_position.distance_to(way[i])
		if d < bd:
			bd = d
			near = i
	return near


func _to_road(id: int) -> void:
	## З ферми (чи з подвір'я) — на дорогу біля воріт подвір'я.
	if in_yard:
		var w = main.world
		await go(w.spots["inside_gate"], false, false)
		await w.pass_gate(self, true)
		bounds = _wide
		in_yard = false
	var near := _near_way()
	var step := -1 if near >= road_i else 1
	for i in range(near, road_i + step, step):
		await _goto(way[i])
		if id != job:
			return


func _road_to_farm(id: int) -> void:
	for i in range(road_i, way.size()):
		await _goto(way[i])
		if id != job:
			return


func work_step() -> void:
	## На фермі: раз на день годує худобу й коней і раз на день прибирає в корівниках та стайнях.
	var d := int(Game.state["day"])
	var h := Game.hour()
	if _fed_day != d and h < 17.0:
		await feed_job()
	elif _clean_day != d and h > 9.0 and h < 15.5:
		await clean_job()
	else:
		var id := begin_job("farm")
		await _goto(Vector3(randf_range(-182.0, -170.0), 0, randf_range(36.0, 70.0)), 1.5)
		end_job(id)


func feed_job() -> void:
	## Бере сіно з копиці й розносить: заходить у кожен корівник і стайню, іде до кінця, кладе сіно й виходить.
	var id := begin_job("feed")
	_fed_day = int(Game.state["day"])
	await back_farm()
	if id != job:
		return
	say("Зараз нагодую всіх!", 2.0)
	for b in _barns():
		var fh: Node3D = main.farm_hay
		if fh:
			await _goto(fh.global_position + (b[1] - fh.global_position).normalized() * 1.5, 1.0)
			if id != job:
				return
			face(fh.global_position)
			await act("pick", minf(anim_length("pick"), 2.0))
			main.add_farm_hay(-0.04)
		hold(_bundle(), Vector3(0, 0.15, 0.0))
		await _goto(b[1], 0.8)
		if id == job:
			await go(b[3], false, false)           # заходить у двері
		if id == job:
			await go(b[4], false, false)           # іде до кінця
		if id != job:
			var l := drop()
			if l:
				l.queue_free()
			return
		face(b[5])
		await act("crouch_pick", minf(anim_length("crouch_pick"), 1.8))
		var hay := drop()
		if hay:
			get_parent().add_child(hay)
			hay.global_position = b[5]
			hay.rotation = Vector3.ZERO
			get_tree().create_timer(150.0).timeout.connect(hay.queue_free)
		_sound("pop")
		say(("Їжте, корівки, сінце!" if b[2] else "Сінце й овес для коників!"), 2.0)
		await wait(0.8)
		if id != job:
			return
		await go(b[3], false, false)               # назад до дверей
		await go(b[1], false, false)               # і надвір
		if id != job:
			return
	Game.emit_event("barn_fed")
	end_job(id)


func clean_job() -> void:
	## Бере біля плуга тачку, кладе в неї вила й по черзі вивозить гній із корівників і стаєнь під паркан;
	## наприкінці відвозить тачку й вила назад.
	var id := begin_job("clean")
	_clean_day = int(Game.state["day"])
	say("Піду по тачку й вила!", 2.5)
	await _to_road(id)
	if id != job:
		return
	await _goto(BARROW_WAY, 0.6)
	if id != job:
		return
	# бере вила й кладе в тачку
	await go(Vector3(FORK_HOME.x - 0.5, 0, FORK_HOME.z - 0.4), false, false)
	if id != job:
		return
	face(Vector3(FORK_HOME.x, 0, FORK_HOME.z))
	await act("pick", minf(anim_length("pick"), 1.4))
	hold(barrow_fork, Vector3(0, 0.05, 0.0))
	await go(barrow.to_global(Vector3(0, 0, -0.8)), false, false)
	if id != job:
		return
	face(barrow.global_position)
	await act("pick", minf(anim_length("pick"), 1.2))
	drop()
	_fork_into_barrow()
	await _grab_barrow(id)
	if id != job:
		return
	say("Поїхали прибирати!", 2.0)
	await _goto(way[road_i])
	if id != job:
		return
	await _road_to_farm(id)
	if id != job:
		return
	for b in _barns():
		# завозить тачку в корівник (стайню)
		await _goto(b[1], 0.8)
		if id == job:
			await go(b[6], false, false)
		if id != job:
			return
		await _park_barrow()
		await go(barrow.to_global(Vector3(0, 0, 0.85)), false, false)
		if id != job:
			return
		face(barrow.global_position)
		await act("pick", minf(anim_length("pick"), 1.0))
		hold(barrow_fork, Vector3(0, 0.05, 0.0))
		# накидає гній вилами в тачку
		for k in 3:
			face(global_position * 2.0 - barrow.global_position)
			await wait(0.3)
			await act("crouch_pick", minf(anim_length("crouch_pick"), 1.4))
			_sound("chop")
			face(barrow.global_position)
			await wait(0.3)
			await act("pick", minf(anim_length("pick"), 1.0))
			barrow_load.visible = true
			barrow_load.scale = Vector3(1.4, 0.4, 0.9) * (0.5 + k * 0.25)
			if id != job:
				return
		say("Чистенько!" if b[2] else "Свіжа підстилка коникам!", 2.0)
		await act("pick", minf(anim_length("pick"), 0.8))
		drop()
		_fork_into_barrow()
		await _grab_barrow(id)
		if id != job:
			return
		# вивозить надвір і до паркана
		await go(b[1], false, false)
		if id != job:
			return
		await _goto(FARM_LANE, 1.2)
		await _goto(DUMP_STAND, 0.5)
		if id != job:
			return
		face(DUMP + Vector3(0, 0, -5.0))
		await wait(0.8)
		await _tip_barrow()
		if id != job:
			return
		await _goto(FARM_LANE, 1.2)
		if id != job:
			return
	# тачку й вила — назад до плуга
	say("Усе прибрав! Відвезу тачку на місце.", 2.5)
	await _to_road(id)
	if id != job:
		return
	await _goto(BARROW_WAY, 0.6)
	if id == job:
		await go(BARROW_PARK, false, false)
	if id != job:
		return
	face(BARROW_PARK + Vector3(0, 0, 3.0))
	await wait(0.5)
	await _park_barrow()
	barrow.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), BARROW_HOME)
	await go(barrow.to_global(Vector3(0, 0, -0.8)), false, false)
	if id != job:
		return
	face(barrow.global_position)
	await act("pick", minf(anim_length("pick"), 1.2))
	hold(barrow_fork, Vector3(0, 0.05, 0.0))
	await go(Vector3(FORK_HOME.x - 0.5, 0, FORK_HOME.z - 0.4), false, false)
	if id != job:
		return
	face(Vector3(FORK_HOME.x, 0, FORK_HOME.z))
	await act("pick", minf(anim_length("pick"), 1.2))
	drop()
	_stow_tools()
	Game.emit_event("barn_cleaned")
	await _goto(way[road_i])
	await _road_to_farm(id)
	end_job(id)


func command(what: String) -> void:
	## Із меню Тарасика.
	if not on_duty:
		say("Іду на ферму!", 2.0)
		return
	cancel_job()
	if held == bucket:
		put_back_held()
		bucket_water.visible = false
	else:
		var l := drop()
		if l and l != barrow_fork:
			l.queue_free()
		_stow_tools()
	match what:
		"feed":
			await feed_job()
		"clean":
			await clean_job()
		"water":
			await water_job()


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
		_barrow_ik()
		return
	super(delta)
	_barrow_ik()


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
	var f := "res://assets/ui/kid.png"
	var now: String = {"feed": "Зараз розношу сіно корівкам і коникам.", "clean": "Зараз прибираю в корівниках і стайнях.",
		"water": "Зараз ношу воду з криниці."}.get(doing, "")
	main.hud.show_dialog("Тарасик", txt + "\n" + (now + "\n" if now != "" else "") +
		"Скажи, що робити: нагодувати корів і коней чи прибрати в корівниках і стайнях.",
		load(f) if ResourceLoader.exists(f) else null, func(): _talk_t = 0.0)


func choose_job() -> bool:
	var s := Game.state
	var h := Game.hour()
	if h > 8.0 and h < 19.0 and _water_day != int(s["day"]) and (float(s["water_bowl"]) < 25.0 or float(s["trough"]) < 25.0) and randf() < 0.5:
		water_job()
		return true
	var r := randf()
	if r < 0.15:
		play_with_bim()
		return true
	if r < 0.25:
		look_at_field()
		return true
	return false


func water_job() -> void:
	## Двічі по воду: Бімові в мисочку, потім курочкам у корито.
	if doing == "water":
		return
	var id := begin_job("water")
	_water_day = int(Game.state["day"])
	say("Піду наберу води!", 2.5)
	await go_yard()
	if id != job:
		return
	var sp: Dictionary = main.world.spots
	for target in ["water_bowl", "trough"]:
		await go(bucket.global_position + Vector3(0.0, 0, 0.45))
		if id != job:
			return
		face(sp["well"])
		await wait(0.4)
		# бере відро й набирає воду з криниці
		hold(bucket, Vector3(0, 0.3, 0.0), false, Basis(Vector3.RIGHT, PI))
		bucket_water.visible = false
		face(sp["well"])
		_sound("metal_drop")
		await main.world.well_draw()     # відро криниці опускається й піднімається, коловорот крутиться
		if id != job:
			return
		bucket_water.visible = true
		_sound("well_done" if false else "pop")
		var tp: Vector3 = sp[target]
		var wf: Vector3 = sp["well_front"]
		var stand: Vector3 = tp + (wf - tp).normalized() * 0.55
		await go(stand)
		if id != job:
			return
		face(tp)
		await wait(0.4)
		await _pour(id)
		if id != job:
			return
		Game.state[target] = 100.0
		Game.emit_event("water_carried")
		if target == "water_bowl":
			say("Пий, Біме!", 2.0)
			if main.puppy and not main.puppy.in_house:
				main.puppy.go_drink()
		else:
			say("Курочки, водичка!", 2.0)
			for b in main.world.yard_root.get_children():
				if "rooster" in b and b.mode == "free":
					b.go_eat(tp, "trough")
		# назад до криниці з порожнім відром
		await go(main.world.spots["well_front"] + Vector3(0.5, 0, 0.35))
		if id != job:
			return
		put_back_held()
	bucket_water.visible = false
	await back_farm()
	end_job(id)


func _pour(id: int) -> void:
	## Нахиляє відро — ллється вода.
	if bucket == null:
		return
	var fx := CPUParticles3D.new()
	fx.amount = 30
	fx.lifetime = 0.5
	fx.direction = Vector3(0, -1, 0)
	fx.spread = 18.0
	fx.initial_velocity_min = 0.5
	fx.initial_velocity_max = 1.0
	fx.gravity = Vector3(0, -6, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.03
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.8, 1.0, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	fx.mesh = sm
	main.world.yard_root.add_child(fx)
	fx.global_position = global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 0.35 + Vector3(0, 0.35, 0)
	_sound("sparkle")
	var b0 := bucket.rotation
	var t := 0.0
	while t < 1.8 and id == job:
		t += get_process_delta_time()
		bucket.rotation.x = b0.x + deg_to_rad(70.0) * clampf(t / 0.5, 0.0, 1.0)
		if t > 1.3:
			bucket_water.visible = false
		await get_tree().process_frame
	bucket.rotation = b0
	fx.emitting = false
	await wait(0.6)
	fx.queue_free()


func play_with_bim() -> void:
	## Доганялки: Тарасик бігає, Бім — за ним.
	if main.puppy == null or main.puppy.doing != "" or main.puppy.in_house:
		return
	var id := begin_job("play")
	say("Біме, наздоганяй!", 2.5)
	var pup = main.puppy
	var old = pup.follow
	pup.follow = self
	for i in 4:
		var p := Vector3(randf_range(-6.0, 3.0), 0, randf_range(-3.5, 3.5))
		walk_to(p, true)
		pup.walk_to(p + Vector3(randf_range(-0.6, 0.6), 0, 0.8), true)
		await arrived
		if id != job:
			break
		await wait(0.5)
	pup.follow = old
	if id == job:
		say("Ха-ха! Ти швидкий!", 2.0)
		pup.act("wag", 2.0)
	end_job(id)


func look_at_field() -> void:
	var id := begin_job("field")
	await go(Vector3(8.2, 0, randf_range(-5.0, -1.0)))
	if id != job:
		return
	face(Vector3(14, 0, -4))
	await wait(0.8)
	var h: float = float(Game.state["field"]["growth"])
	say("Ого, які соняшники!" if h > 0.6 else ("Соняшники хочуть пити…" if float(Game.state["field"]["water"]) < 25.0 else "Ростуть, ростуть!"), 3.0)
	await wait(3.0)
	end_job(id)


func _sound(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -10.0)
