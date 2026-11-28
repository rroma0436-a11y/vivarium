extends "res://scripts/farmhand.gd"
## Гвинтик — маленький робот-помічник. Живе в хаті села, зранку йде на ферму й працює біля техніки
## під навісом: оглядає техніку, ремонтує трактор і комбайн набором ключів і викруток,
## а після ремонту сідає за кермо й проїжджає трохи по фермі — і ставить назад.
## Як попросять — іде на подвір'я збирати яйця й несе кошик дідусеві на ґанок.

var _fixed := {}                         # що полагоджено сьогодні й ще не випробувано: "tractor"/"combine" → true

var basket: Node3D
var porch_basket: Node3D
var woodpile: Node3D
var toolbox: Node3D                      # набір ключів і викруток (стоїть під навісом)
const TOOLS_AT := Vector3(-129.8, 0, 37.0)
var riding: Node3D = null                # у кабіні трактора чи комбайна
var _seat_l := Vector3.ZERO
var _talk_t := 0.0
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
	# ящик з ключами й викрутками під навісом для техніки
	toolbox = _toolbox()
	main.world.yard_root.add_child(toolbox)
	toolbox.position = TOOLS_AT
	toolbox.rotation.y = PI / 2.0
	Walker.remember_home(toolbox)


func _toolbox() -> Node3D:
	var n := Node3D.new()
	var red := Util.mat(Color(0.78, 0.16, 0.12), 0.5, 0.3)
	var steel := Util.mat(Color(0.6, 0.62, 0.66), 0.35, 0.7)
	n.add_child(Util.box(Vector3(0.42, 0.16, 0.2), red, Vector3(0, 0.08, 0)))
	n.add_child(Util.box(Vector3(0.44, 0.03, 0.22), red.duplicate(), Vector3(0, 0.175, 0)))
	n.add_child(Util.box(Vector3(0.025, 0.07, 0.025), steel, Vector3(-0.1, 0.22, 0)))
	n.add_child(Util.box(Vector3(0.025, 0.07, 0.025), steel, Vector3(0.1, 0.22, 0)))
	n.add_child(Util.box(Vector3(0.22, 0.025, 0.03), steel, Vector3(0, 0.255, 0)))
	return n


func _tools_home() -> void:
	## Ящик з інструментами — на своє місце (якщо справу перервали, а він лишився біля техніки).
	if toolbox == null or held == toolbox:
		return
	var home: Node = toolbox.get_meta("home_parent", null)
	if home == null:
		return
	if toolbox.get_parent() != home:
		if toolbox.get_parent():
			toolbox.get_parent().remove_child(toolbox)
		home.add_child(toolbox)
	toolbox.transform = toolbox.get_meta("home_tr", toolbox.transform)


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
	## [назва, вузол, де стати для ремонту (збоку), як звати, півдовжина, півширина]
	var list: Array = []
	var tr = main.tractor
	if tr and is_instance_valid(tr):
		list.append(["tractor", tr, tr.global_position + tr.global_transform.basis.x * 1.6, "трактор", 3.2, 1.9])
	var cb = main.combine
	if cb and is_instance_valid(cb):
		list.append(["combine", cb, cb.global_position + cb.global_transform.basis.x * 2.4, "комбайн", 4.6, 2.8])
	return list


func _machine(which: String) -> Array:
	for x in _machines():
		if x[0] == which:
			return x
	return []


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


func _screwdriver() -> Node3D:
	var n := Node3D.new()
	n.add_child(Util.cyl(0.018, 0.018, 0.09, Util.mat(Color(0.95, 0.75, 0.15), 0.5), Vector3(0, -0.02, 0)))
	n.add_child(Util.cyl(0.006, 0.006, 0.13, Util.mat(Color(0.7, 0.72, 0.76), 0.3, 0.8), Vector3(0, 0.09, 0)))
	return n


func _drop_free() -> void:
	var l := drop()
	if l and l != toolbox:
		l.queue_free()


func _busy_machine(n) -> bool:
	var st = n.get("state")
	return (st != null and st != "parked") or n.get("driver") != null or main._ctl_veh == n or main._mount == n


# ------------------------------------------------------------------ сидить за кермом
func _process(delta: float) -> void:
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
	if _talk_t > 0.0 and not _on_bike:
		# розмовляє з Нікою: стоїть лицем до неї
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


func _hop(v: Node3D, pts: Array, rels: Array, sits: Array, seg := 0.45) -> void:
	## Лізе по точках pts (у системі машини): стегна йдуть від точки до точки, поворот і посадка — поступово.
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
	## Від землі біля машини — приступками до порога й на сидіння (стегна; у системі машини).
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
	## Підходить до приступки, лізе в кабіну й сідає за кермо.
	var cp: Dictionary = v.cab_points()
	await _goto(v.to_global(cp["climb"]), 0.4)
	stop()
	_face_to = NAN
	busy = true
	if v.has_method("open_door"):
		v.open_door(true)
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
	if v.has_method("open_door"):
		v.open_door(false)
	_seat_l = pts.back()
	if pose:
		pose.sit = 1.0
	busy = false
	riding = v


func _alight(v: Node3D) -> void:
	## Встає з сидіння й злазить на землю.
	riding = null
	if pose:
		pose.ik = {}
	stop()
	_face_to = NAN
	busy = true
	if v.has_method("open_door"):
		v.open_door(true)
		await wait(0.6)
	var pts := _cab_path(v)
	pts.reverse()
	var side := float(v.cab_points().get("side", -1.0))
	var rels: Array = [0.0]
	var sits: Array = [1.0]
	for i in pts.size() - 1:
		rels.append(-side * PI / 2.0)
		sits.append(0.0)
	await _hop(v, pts, rels, sits)
	if v.has_method("open_door"):
		v.open_door(false)
	var g: Vector3 = v.to_global(v.cab_points()["climb"])
	g.y = 0.0
	global_position = g
	if pose:
		pose.sit = 0.0
	model.position.y = _base_y
	busy = false
	play("idle")


# ------------------------------------------------------------------ їзда
func _veh_to(v: Node3D, p: Vector3, vmax: float, reach := 0.9) -> void:
	## Їде до точки, як справжня машина: кермом повертає плавно, а не на місці.
	var t := 0.0
	var sp: float = absf(float(v.get("speed")))
	while t < 40.0:
		var dt := get_process_delta_time()
		t += dt
		var to := p - v.global_position
		to.y = 0.0
		var d := to.length()
		if d < reach:
			break
		var want := atan2(to.x, to.z)
		var diff := angle_difference(v.rotation.y, want)
		var vv := vmax * clampf(1.2 - absf(diff) * 0.5, 0.35, 1.0)
		sp = move_toward(sp, vv, dt * 1.6)
		v.rotation.y += clampf(diff, -1.0, 1.0) * dt * sp / 1.9 * 1.6
		v.global_position += Vector3(sin(v.rotation.y), 0, cos(v.rotation.y)) * sp * dt
		v.ride_anim(sp, clampf(diff * 1.6, -0.55, 0.55), dt)
		await get_tree().process_frame


func _veh_stop(v: Node3D) -> void:
	var sp: float = float(v.get("speed"))
	while absf(sp) > 0.05:
		var dt := get_process_delta_time()
		sp = move_toward(sp, 0.0, dt * 2.5)
		v.global_position += Vector3(sin(v.rotation.y), 0, cos(v.rotation.y)) * sp * dt
		v.ride_anim(sp, 0.0, dt)
		await get_tree().process_frame
	v.ride_anim(0.0, 0.0, get_process_delta_time())


func _veh_back(v: Node3D, park: Transform3D) -> void:
	## Заднім ходом — точно на своє місце під навісом.
	var p0 := v.global_position
	var y0 := v.rotation.y
	var y1 := park.basis.get_euler().y
	var dist := p0.distance_to(park.origin)
	var secs := maxf(1.5, dist / 1.3)
	var t := 0.0
	while t < secs:
		var dt := get_process_delta_time()
		t = minf(secs, t + dt)
		var k := smoothstep(0.0, 1.0, t / secs)
		v.global_position = p0.lerp(park.origin, k)
		v.rotation.y = lerp_angle(y0, y1, k)
		v.ride_anim(-1.3 * sin(k * PI) - 0.1, 0.0, dt)
		await get_tree().process_frame
	v.global_transform = park
	v.ride_anim(0.0, 0.0, get_process_delta_time())


func _test_drive(m: Array) -> void:
	## Виїжджає з-під навісу, робить коло по фермі й заднім ходом ставить машину на місце.
	var v: Node3D = m[1]
	var park := v.global_transform
	var P := park.origin
	var f := Vector3(sin(v.rotation.y), 0, cos(v.rotation.y))
	var s := Vector3(f.z, 0, -f.x)
	var r := 4.0 if m[0] == "tractor" else 4.5
	var c := P + f * 11.0 + s * r
	var route := [P + f * 5.0, P + f * 11.0, c + f * r, c + s * r, c - f * r, P + f * 11.0]
	if m[0] == "tractor":
		v._job += 1
		v.driver = self
		v.state = "drive"
	v.say("Тр-р-р-р!" if m[0] == "tractor" else "Ур-р-р-р!", 1.5)
	_sound("metal_drop")
	await wait(1.2)
	for p in route:
		await _veh_to(v, p, 2.6)
	await _veh_stop(v)
	await wait(0.6)
	say("А тепер — заднім ходом на місце!", 2.0)
	await _veh_back(v, park)
	if m[0] == "tractor":
		v.state = "parked"
		v.driver = null


# ------------------------------------------------------------------ справи
func work_step() -> void:
	## Біля техніки: що полагодив — випробовує, інакше оглядає чи ремонтує.
	var list := _machines()
	if list.is_empty():
		await dance()
		return
	for m in list:
		if _fixed.get(m[0], false) and not _busy_machine(m[1]):
			await test_job(m[0])
			return
	var r := randf()
	if r < 0.3:
		await inspect_job()
	elif r < 0.7:
		await repair_job(list[randi() % list.size()][0])
	else:
		await dance()


func inspect_job() -> void:
	## Обходить усю техніку по колу й оглядає її з усіх боків.
	var id := begin_job("inspect")
	_tools_home()
	await back_farm()
	if id != job:
		return
	var list := _machines()
	if list.is_empty():
		say("Біп… Техніки немає.", 2.0)
		end_job(id)
		return
	say("Біп! Огляну всю техніку!", 2.0)
	for m in list:
		var v: Node3D = m[1]
		var a: float = m[4]
		var b: float = m[5]
		var n := 8
		for i in n + 1:
			var ang := TAU * float(i) / n
			var p := v.to_global(Vector3(sin(ang) * b, 0, cos(ang) * a))
			p.y = 0.0
			await _goto(p, 0.6)
			if id != job:
				return
			face(v.global_position)
			if i == 2 or i == 6:
				await act("crouch_pick", minf(anim_length("crouch_pick"), 1.6))
				if id != job:
					return
			else:
				await wait(0.5)
			if i == 4:
				say(["Колеса цілі…", "Фари світять…", "Мастило є…"][randi() % 3], 1.8)
		var st := "полагоджено — треба випробувати" if _fixed.get(m[0], false) else "усе гаразд"
		say("%s оглянуто: %s! Біп!" % [_cap(m[3]), st], 2.5)
		await wait(1.5)
		if id != job:
			return
	end_job(id)


func repair_job(which := "") -> void:
	## Іде по ящик з ключами й викрутками, несе до машини й ремонтує її, а тоді відносить ящик на місце.
	var id := begin_job("repair")
	_tools_home()
	await back_farm()
	if id != job:
		return
	var m: Array = _machine(which) if which != "" else (_machines()[0] if not _machines().is_empty() else [])
	if m.is_empty():
		say("Біп… Техніки немає.", 2.0)
		end_job(id)
		return
	if _busy_machine(m[1]):
		say("Біп! %s зараз зайнятий — відремонтую пізніше." % _cap(m[3]), 2.5)
		end_job(id)
		return
	say("Біп! Відремонтую %s. Де мої ключі?" % m[3], 2.5)
	var tb := toolbox.global_position
	await _goto(tb + Vector3(-0.55, 0, 0.0), 0.4)
	if id != job:
		return
	face(tb)
	await act("crouch_pick", minf(anim_length("crouch_pick"), 1.4))
	if id != job:
		return
	hold_upright(toolbox, 0.22)
	say("Ключі й викрутки — є!", 2.0)
	await _goto(m[2], 0.7)
	if id != job:
		return
	face(m[1].global_position)
	# ставить ящик поруч
	var box := drop()
	main.world.yard_root.add_child(box)
	var sd := Vector3(cos(rotation.y), 0, -sin(rotation.y))
	box.global_position = Vector3(global_position.x, 0, global_position.z) + sd * 0.45
	box.rotation.y = rotation.y
	await act("crouch_pick", minf(anim_length("crouch_pick"), 1.2))
	if id != job:
		return
	say("Так… підкрутимо гайки ключем!", 2.5)
	hold(_wrench(), Vector3(0, 0.05, 0.0))
	for k in 3:
		_sparks(global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 0.5 + Vector3(0, 0.5, 0), 1.2)
		_sound("metal_drop")
		await act("crouch_pick", minf(anim_length("crouch_pick"), 1.6))
		if id != job:
			_drop_free()
			return
	_drop_free()
	say("А тепер — викруткою!", 2.0)
	hold(_screwdriver(), Vector3(0, 0.04, 0.0))
	for k in 2:
		_sound("metal_drop")
		await act("crouch_pick", minf(anim_length("crouch_pick"), 1.6))
		if id != job:
			_drop_free()
			return
	_drop_free()
	_fixed[m[0]] = true
	say("%s відремонтовано! Тепер можна випробувати. Біп!" % _cap(m[3]), 3.0)
	# складає інструменти й відносить ящик на місце
	await act("crouch_pick", minf(anim_length("crouch_pick"), 1.2))
	if id != job:
		return
	hold_upright(toolbox, 0.22)
	await _goto(TOOLS_AT + Vector3(-0.55, 0, 0.0), 0.4)
	if id != job:
		return
	face(TOOLS_AT)
	put_back_held()
	_tools_home()
	end_job(id)


func test_job(which := "") -> void:
	## Після ремонту: сідає в трактор чи комбайн, проїжджає трохи по фермі й ставить машину назад.
	var id := begin_job("test")
	_tools_home()
	await back_farm()
	if id != job:
		return
	var m: Array = []
	for x in _machines():
		if _fixed.get(x[0], false) and (which == "" or x[0] == which):
			m = x
			break
	if m.is_empty():
		say("Біп! Спершу треба щось відремонтувати — тоді випробую.", 2.5)
		end_job(id)
		return
	if _busy_machine(m[1]):
		say("Біп… %s зараз зайнятий — випробую пізніше." % _cap(m[3]), 2.5)
		end_job(id)
		return
	say("Випробую %s після ремонту! Біп!" % m[3], 2.5)
	await _board(m[1])
	await _test_drive(m)
	await wait(0.5)
	await _alight(m[1])
	_fixed.erase(m[0])
	say("Випробування пройдено! %s як новий! Біп-біп!" % _cap(m[3]), 3.0)
	_sound("coin")
	end_job(id)


func command(what: String) -> void:
	## Із меню Гвинтика.
	if not on_duty:
		say("Біп! Іду на ферму!", 2.0)
		return
	if riding or doing == "test":
		say("Біп! Спершу поставлю техніку на місце!", 2.5)
		return
	cancel_job()
	if held == basket:
		basket.get_node("eggs").visible = false
		put_back_held()
	elif held == toolbox:
		put_back_held()
	else:
		_drop_free()
	_tools_home()
	match what:
		"inspect":
			await inspect_job()
		"repair_tractor":
			await repair_job("tractor")
		"repair_combine":
			await repair_job("combine")
		"repair":
			await repair_job()
		"test":
			await test_job()
		"eggs":
			await eggs_job()


func talk_nika() -> void:
	## «Поговорити»: обертається лицем до Ніки й заводить розмову.
	var nk: Node3D = main.girl
	if riding == null:
		_talk_t = 60.0
	if nk and main._mount_state == "":
		main._girl_face(global_position)
	var txt: String = lines[_line % lines.size()] if lines.size() > 0 else ""
	_line += 1
	say(txt, 3.5)
	main.audio.play_at("robot_beep", self, -4.0)
	var f := "res://assets/ui/gvintyk.png"
	main.hud.show_dialog("Гвинтик", txt + "\n" + _machines_news(), load(f) if ResourceLoader.exists(f) else null,
		func(): _talk_t = 0.0)


func _machines_news() -> String:
	var parts: Array = []
	for m in _machines():
		var st := "відремонтовано, чекає випробування" if _fixed.get(m[0], false) else "справний"
		if _busy_machine(m[1]):
			st = "зараз у роботі"
		parts.append("%s — %s" % [_cap(m[3]), st])
	var t := ("Техніка: " + "; ".join(parts) + ".\n") if not parts.is_empty() else ""
	return t + "Скажи, що робити: оглянути техніку, відремонтувати трактор чи комбайн або випробувати після ремонту."


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
