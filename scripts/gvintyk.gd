extends "res://scripts/farmhand.gd"
## Гвинтик — маленький робот-помічник. Живе в хаті села, зранку йде на ферму й працює біля техніки
## під навісом: оглядає, доглядає й ремонтує трактор і комбайн, а після ремонту випробовує.
## Як попросять — іде на подвір'я збирати яйця й несе кошик дідусеві на ґанок.

var _fixed := {}                         # що полагоджено сьогодні й ще не випробувано: "tractor"/"combine" → true

var basket: Node3D
var porch_basket: Node3D
var woodpile: Node3D
var _eggs_day := -1
var _wood_day := -1


func make_props() -> void:
	var wp: Dictionary = main.world.spots
	# кошик, з яким ходить по яйця (стоїть біля курника)
	basket = _basket(false)
	main.world.yard_root.add_child(basket)
	basket.position = wp["coop_door"] + Vector3(-0.5, 0, 0.7)
	Walker.remember_home(basket)
	# кошик з яйцями на ґанку (з'являється, коли Гвинтик їх приніс)
	porch_basket = _basket(true)
	main.world.yard_root.add_child(porch_basket)
	porch_basket.position = wp["porch"] + Vector3(1.0, 0, -0.5)
	porch_basket.visible = int(Game.state.get("eggs", 0)) > 0
	# купка дров біля дверей, яка росте
	woodpile = Node3D.new()
	main.world.yard_root.add_child(woodpile)
	woodpile.position = wp["porch"] + Vector3(-1.5, 0, -0.6)


func _basket(with_eggs: bool) -> Node3D:
	var n := Node3D.new()
	var wick := Util.mat(Color(0.72, 0.52, 0.28), 0.95)
	n.add_child(Util.cyl(0.17, 0.13, 0.15, wick, Vector3(0, 0.075, 0)))
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.14
	tm.outer_radius = 0.16
	tm.rings = 14
	tm.ring_segments = 4
	handle.mesh = tm
	handle.material_override = wick
	handle.rotation_degrees = Vector3(90, 0, 0)
	handle.position = Vector3(0, 0.15, 0)
	n.add_child(handle)
	var eggs := Node3D.new()
	eggs.name = "eggs"
	var em := Util.mat(Color(0.98, 0.95, 0.88), 0.5)
	var em2 := Util.mat(Color(0.88, 0.72, 0.55), 0.5)
	for i in 5:
		var a := i * TAU / 5.0
		eggs.add_child(Util.sphere(0.035, em if i % 2 == 0 else em2, Vector3(cos(a) * 0.07, 0.15, sin(a) * 0.07), Vector3(1, 1.3, 1)))
	eggs.visible = with_eggs
	n.add_child(eggs)
	return n


func _machines() -> Array:
	## [назва, вузол, де стати (збоку), що каже]
	var list: Array = []
	var tr = main.tractor
	if tr and is_instance_valid(tr):
		list.append(["tractor", tr, tr.global_position + tr.global_transform.basis.x * 1.6, "трактор"])
	var cb = main.combine
	if cb and is_instance_valid(cb):
		list.append(["combine", cb, cb.global_position + cb.global_transform.basis.x * 2.4, "комбайн"])
	return list


func _sparks(at: Vector3, secs: float) -> void:
	var fx := CPUParticles3D.new()
	fx.amount = 24
	fx.lifetime = 0.35
	fx.direction = Vector3(0, 1, 0)
	fx.spread = 70.0
	fx.initial_velocity_min = 1.0
	fx.initial_velocity_max = 2.2
	fx.gravity = Vector3(0, -6, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	sm.material = m
	fx.mesh = sm
	main.world.yard_root.add_child(fx)
	fx.global_position = at
	await wait(secs)
	fx.emitting = false
	await wait(0.5)
	fx.queue_free()


func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


func _wrench() -> MeshInstance3D:
	return Util.box(Vector3(0.04, 0.22, 0.02), Util.mat(Color(0.6, 0.62, 0.66), 0.35, 0.7))


func work_step() -> void:
	## Біля техніки: що полагодив — випробовує, інакше оглядає й ремонтує.
	var list := _machines()
	if list.is_empty():
		await dance()
		return
	for m in list:
		if _fixed.get(m[0], false):
			await test_job(m[0])
			return
	if randf() < 0.75:
		await repair_job(list[randi() % list.size()][0])
	else:
		await dance()


func _busy_machine(n) -> bool:
	var st = n.get("state")
	return (st != null and st != "parked") or n.get("driver") != null or (main._ctl_veh == n)


func repair_job(which := "") -> void:
	var id := begin_job("repair")
	await back_farm()
	var list := _machines()
	var m: Array = []
	for x in list:
		if which == "" or x[0] == which:
			m = x
			break
	if m.is_empty():
		say("Біп… Техніки немає.", 2.0)
		end_job(id)
		return
	if _busy_machine(m[1]):
		say("Біп! %s зараз працює — огляну пізніше." % _cap(m[3]), 2.5)
		end_job(id)
		return
	say("Біп! Огляну %s." % m[3], 2.0)
	await _goto(m[2], 0.8)
	if id != job:
		return
	face(m[1].global_position)
	await act("crouch_pick", minf(anim_length("crouch_pick"), 2.0))
	if id != job:
		return
	say("Ага… треба підкрутити гайки!", 2.5)
	hold(_wrench(), Vector3(0, 0.05, 0.0))
	for k in 3:
		_sparks(global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 0.5 + Vector3(0, 0.5, 0), 1.2)
		_sound("metal_drop")
		await act("crouch_pick", minf(anim_length("crouch_pick"), 1.6))
		if id != job:
			var l0 := drop()
			if l0:
				l0.queue_free()
			return
	var l := drop()
	if l:
		l.queue_free()
	_fixed[m[0]] = true
	say("Полагоджено! Тепер випробую. Біп!", 2.5)
	end_job(id)


func test_job(which := "") -> void:
	## Випробування після ремонту: трактор заводить і ганяє мотор, комбайн — оглядає на ходу дверцят.
	var id := begin_job("test")
	await back_farm()
	var m: Array = []
	for x in _machines():
		if (which == "" and _fixed.get(x[0], false)) or x[0] == which:
			m = x
			break
	if m.is_empty():
		for x in _machines():
			m = x
			break
	if m.is_empty() or _busy_machine(m[1]):
		say("Біп… Зараз не можна випробувати.", 2.0)
		end_job(id)
		return
	await _goto(m[2], 0.8)
	if id != job:
		return
	face(m[1].global_position)
	if m[0] == "tractor":
		say("Заводжу! Три… два… один…", 2.0)
		await wait(1.5)
		m[1].start_engine()
		await wait(6.0)
		if m[1].get("driver") == null and main._ctl_veh != m[1]:
			m[1].state = "parked"
			m[1].say("Пух-пух…", 1.2)
	else:
		say("Перевіряю дверцята й мотовило…", 2.5)
		if m[1].has_method("open_door"):
			m[1].open_door(true)
			await wait(2.0)
			m[1].open_door(false)
		await wait(2.0)
	_fixed.erase(m[0])
	if id == job:
		say("Випробування пройдено! %s як новий! Біп-біп!" % _cap(m[3]), 3.0)
		_sound("coin")
		end_job(id)


func command(what: String) -> void:
	## Із меню Гвинтика.
	if not on_duty:
		say("Біп! Іду на ферму!", 2.0)
		return
	cancel_job()
	if held == basket:
		basket.get_node("eggs").visible = false
		put_back_held()
	else:
		var l := drop()
		if l:
			l.queue_free()
	match what:
		"repair":
			await repair_job()
		"test":
			await test_job()
		"eggs":
			await eggs_job()


func choose_job() -> bool:
	var h := Game.hour()
	var d := int(Game.state["day"])
	if h > 8.0 and h < 18.0 and _eggs_day != d and randf() < 0.35 and Game.current_quest().get("id", "") != "eggs":
		eggs_job()
		return true
	if h > 9.0 and h < 19.0 and _wood_day != d and randf() < 0.35:
		firewood_job()
		return true
	if randf() < 0.2:
		dance()
		return true
	return false


func eggs_job() -> void:
	if doing == "eggs":
		return
	var id := begin_job("eggs")
	_eggs_day = int(Game.state["day"])
	var sp: Dictionary = main.world.spots
	say("Біп! Іду по яйця!", 2.5)
	await go_yard()
	if id != job:
		return
	await go(basket.global_position + Vector3(0, 0, 0.4))
	if id != job:
		return
	hold(basket, Vector3(0, 0.22, 0.0), false, Basis(Vector3.RIGHT, PI))
	await go(sp["coop_door"] + Vector3(-0.45, 0, 0))
	if id != job:
		return
	face(sp["coop"])
	say("Раз… два… три яйця!", 2.5)
	_sound("pop")
	await wait(1.0)
	basket.get_node("eggs").visible = true
	await wait(1.4)
	if id != job:
		return
	await go(porch_basket.global_position + Vector3(0.4, 0, 0.5))
	if id != job:
		return
	face(porch_basket.global_position)
	await wait(0.5)
	basket.get_node("eggs").visible = false
	put_back_held()
	porch_basket.visible = true
	Game.state["eggs"] = int(Game.state.get("eggs", 0)) + 3
	Game.emit_event("eggs_collected")
	say("Кошик яєць для дідуся! Біп!", 3.0)
	_sound("coin")
	await back_farm()
	end_job(id)


func firewood_job() -> void:
	## Три ходки від дровітні до хати — по одному поліну.
	if doing == "wood":
		return
	var id := begin_job("wood")
	_wood_day = int(Game.state["day"])
	var sp: Dictionary = main.world.spots
	say("Принесу дров для печі!", 2.5)
	for i in 3:
		await go(sp["firewood_front"])
		if id != job:
			return
		await wait(0.6)
		var lg := Util.cyl(0.06, 0.06, 0.42, Util.mat(Color(0.55, 0.38, 0.22), 0.9), Vector3.ZERO, Vector3(0, 0, 90))
		hold(lg, Vector3(0, 0.1, 0.05))
		_sound("chop")
		await go(woodpile.global_position + Vector3(0.45, 0, 0.35))
		if id != job:
			var l := drop()
			if l:
				l.queue_free()
			return
		face(woodpile.global_position)
		await wait(0.4)
		var l2 := drop()
		if l2:
			l2.queue_free()
		_add_log()
	say("Дідусю, дрова є!", 2.5)
	end_job(id)


func _add_log() -> void:
	var n := woodpile.get_child_count()
	if n >= 9:
		return
	var row := n / 3
	var col := n % 3
	var l := Util.cyl(0.06, 0.06, 0.42, Util.mat(Color(0.55, 0.38, 0.22).darkened(randf() * 0.15), 0.9),
		Vector3(0, 0.06 + row * 0.11, (col - 1) * 0.13 + (0.06 if row % 2 == 1 else 0.0)), Vector3(0, 0, 90))
	woodpile.add_child(l)


func dance() -> void:
	if anims.get("dance", "") == "":
		return
	var id := begin_job("dance")
	say("Біп-біп! Танцюю!", 2.0)
	busy = true
	play("dance")
	await wait(clampf(anim_length("dance"), 3.0, 7.0))
	busy = false
	end_job(id)


func _sound(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -10.0)
