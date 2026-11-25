extends "res://scripts/farmhand.gd"
## Бабуся Галя: живе з дідусем у хаті. Годує курей, порається на городі, п'є воду біля криниці,
## варить борщ і пече пиріжки. Зранку бере дійницю (відро для молока) й стільчик і йде
## на пасовисько доїти корову — дійниця наповнюється молоком, поки вона доїть.
## Свої справи бабуся робить сама, а ще їх можна замовити в її меню (торкнись бабусі).

var spots := {}
var _cooked_day := -1
var _milk_day := -1
var outside := false                  # за ворітьми (дорогою на пасовисько чи там)
var in_house := false                 # зайшла в хату — її не видно

var pail: Node3D                      # дійниця
var pail_milk: MeshInstance3D         # молоко в дійниці (піднімається, поки доїть)
var milk_level := 0.0                 # 0 — порожня, 1 — повна
var stool: Node3D                     # низенький стільчик для доїння
var stool_h := 0.34
var _stool_home := Transform3D()
var _stool_carry := false
var _cow                              # корова, яку зараз доїть
var _milking := false
var _milk_t := 0.0
var _teats: Array = []                # дві точки на вимені: [для лівої руки, для правої]
var _jet: CPUParticles3D              # цівки молока у відро
var plate: Node3D                     # таця з пиріжками на столі (pies_left — скільки лишилось)
var pies_left := 0

const GRANNY_BOUNDS := Rect2(-60.0, -130.0, 105.0, 164.0)
# дорога від воріт на пасовисько (та сама, якою ходить пастух)
const PASTURE_WAY := [Vector3(-24.0, 0, 8.5), Vector3(-45.0, 0, 9.0), Vector3(-120.0, 0, 9.0), Vector3(-166.0, 0, 9.0)]  # до пасовиська на фермі за ставком
const FARM_BOUNDS := Rect2(-200.0, -130.0, 245.0, 200.0)
const PAIL_H := 0.29                  # висота дійниці (без дужки)
const PAIL_R_BOT := 0.115
const PAIL_R_TOP := 0.145
const MILK_MAX := 0.24                # до якої висоти доливається молоко
const TABLE_TOP := Vector3(4.9, 0.8, 2.9)     # де на столі ставить пиріжки
const TABLE_STAND := Vector3(5.95, 0, 2.9)      # де стоїть біля столу


func setup_granny(sp: Dictionary) -> void:
	spots = sp
	setup("granny", 1.6, {"idle": ["short_breathe"], "walk": ["walking"], "run": ["running"], "talk": ["talk_with_hands"],
			"pick": ["female_stand_pick_fruit"], "pocket": ["female_walk_pick"], "bend": ["male_bend_over"],
			"wave": ["wave_one_hand"], "drink": ["stand_and_drink"], "sit": ["sit_and_drink"]},
		["idle", "walk", "run", "pick", "bend", "sit"],
		["Я — бабуся Галя. Усе господарство на мені!", "Курочки сьогодні несуться, як навіжені.",
		 "Борщ уже варю, а ти вже їла?", "Дідусь знову в майстерні? Кличте обідати!", "Онучку, візьми пиріжка!",
		 "Зранку подою Зірку — буде парне молочко.", "Без дійниці на пасовисько не ходжу!"],
		[], "granny")
	Models.give_nika_anims(ap, anims)
	bounds = YARD_BOUNDS
	setup_pose()
	_make_tools()
	start_life(spots["door"] + Vector3(0.1, 0, 0.5), [], 6.6, 20.8)


func _process(delta: float) -> void:
	super(delta)
	if _stool_carry and stool and hand_l:
		# стільчик несе в лівій руці, тримаючи за сидіння
		var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
		stool.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), hand_l.global_position - Vector3(0, stool_h - 0.02, 0) + f * 0.05)
	if _milking:
		_milk_step(delta)


# ------------------------------------------------------------------ дійниця, стільчик, пиріжки
func _make_tools() -> void:
	var root: Node3D = main.world.yard_root
	pail = _make_pail()
	root.add_child(pail)
	pail.position = spots["porch"] + Vector3(-1.2, 0, -0.5)
	Walker.remember_home(pail)
	stool = Node3D.new()
	stool.name = "MilkStool"
	root.add_child(stool)
	_build_stool(stool_h)
	stool.position = spots["porch"] + Vector3(-1.65, 0, -0.45)
	stool.rotation.y = 0.4
	_stool_home = stool.transform
	_jet = _make_jet()
	root.add_child(_jet)
	_jet.emitting = false


func _tin() -> StandardMaterial3D:
	var m := Util.mat(Color(0.74, 0.77, 0.8), 0.32, 0.75)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_pail() -> Node3D:
	## Дійниця: оцинковане відро, що трохи ширшає догори, з закоченим краєм, ребром жорсткості,
	## дротяною дужкою й дерев'яною ручкою. Усередині — молоко (pail_milk), рівень задає _set_milk().
	var n := Node3D.new()
	n.name = "MilkPail"
	var tin := _tin()
	var rb := PAIL_R_BOT
	var rt := PAIL_R_TOP
	var H := PAIL_H
	# профіль (радіус, висота): низ → зовнішня стінка з ребром → закочений край → внутрішня стінка → дно
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(rb - 0.004, 0.0), Vector2(rb, 0.008),
		Vector2(lerpf(rb, rt, 0.3) , H * 0.3 - 0.006), Vector2(lerpf(rb, rt, 0.3) + 0.004, H * 0.3), Vector2(lerpf(rb, rt, 0.3), H * 0.3 + 0.006),
		Vector2(rt, H - 0.012), Vector2(rt + 0.007, H - 0.008), Vector2(rt + 0.008, H), Vector2(rt + 0.003, H + 0.005),
		Vector2(rt - 0.004, H + 0.002), Vector2(rt - 0.006, H - 0.01),
		Vector2(rb - 0.006, 0.014), Vector2(0.0, 0.014)])
	n.add_child(_lathe(prof, 28, tin))
	# вушка, за які тримається дужка
	for sx in [-1.0, 1.0]:
		n.add_child(Util.box(Vector3(0.012, 0.035, 0.03), tin, Vector3(sx * (rt + 0.006), H - 0.03, 0)))
	# дужка — дротяна дуга над відром
	var arc := PackedVector3Array()
	var R := rt + 0.008
	for i in 17:
		var a := PI * float(i) / 16.0
		arc.append(Vector3(cos(a) * R, H - 0.03 + sin(a) * R * 0.95, 0))
	n.add_child(_tube(arc, 0.0045, tin))
	# дерев'яна ручка посередині дужки
	var wood := Util.mat(Color(0.5, 0.33, 0.18), 0.8)
	n.add_child(Util.cyl(0.013, 0.013, 0.085, wood, Vector3(0, H - 0.03 + R * 0.95, 0), Vector3(0, 0, 90)))
	# молоко
	pail_milk = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = 0.004
	cm.radial_segments = 24
	cm.rings = 1
	pail_milk.mesh = cm
	pail_milk.material_override = Util.mat(Color(0.99, 0.98, 0.93), 0.35)
	n.add_child(pail_milk)
	_set_milk(0.0)
	return n


func _set_milk(k: float) -> void:
	## Рівень молока в дійниці (0..1).
	milk_level = clampf(k, 0.0, 1.0)
	if pail_milk == null:
		return
	var y := 0.016 + (MILK_MAX - 0.016) * milk_level
	var r := lerpf(PAIL_R_BOT - 0.006, PAIL_R_TOP - 0.006, y / PAIL_H) - 0.001
	var cm: CylinderMesh = pail_milk.mesh
	cm.top_radius = r
	cm.bottom_radius = r
	pail_milk.position = Vector3(0, y, 0)
	pail_milk.visible = milk_level > 0.02


func _lathe(prof: PackedVector2Array, segs: int, m: Material) -> MeshInstance3D:
	## Тіло обертання: профіль (радіус, висота) обертаємо навколо осі y. Нормалі рахуємо з профілю.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		var d := b - a
		var n2 := Vector2(d.y, -d.x).normalized()
		for s in segs:
			var t0 := TAU * float(s) / float(segs)
			var t1 := TAU * float(s + 1) / float(segs)
			var c0 := Vector3(cos(t0), 0, sin(t0))
			var c1 := Vector3(cos(t1), 0, sin(t1))
			var na := c0 * n2.x + Vector3(0, n2.y, 0)
			var nb := c1 * n2.x + Vector3(0, n2.y, 0)
			var p00 := c0 * a.x + Vector3(0, a.y, 0)
			var p01 := c1 * a.x + Vector3(0, a.y, 0)
			var p10 := c0 * b.x + Vector3(0, b.y, 0)
			var p11 := c1 * b.x + Vector3(0, b.y, 0)
			for v in [[p00, na], [p11, nb], [p10, na], [p00, na], [p01, nb], [p11, nb]]:
				st.set_normal((v[1] as Vector3).normalized())
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi


func _tube(pts: PackedVector3Array, r: float, m: Material) -> MeshInstance3D:
	## Тонка трубка вздовж ламаної (дужка відра).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in pts.size():
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var u := t.cross(Vector3(0, 0, 1)).normalized()
		var w := t.cross(u).normalized()
		var ring: Array = []
		for k in 6:
			var a := TAU * float(k) / 6.0
			var nrm := u * cos(a) + w * sin(a)
			ring.append([pts[i] + nrm * r, nrm])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in 6:
			var k2 := (k + 1) % 6
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi


func _build_stool(h: float) -> void:
	## Стільчик: кругле дерев'яне сидіння на трьох ніжках. h — висота сидіння.
	stool_h = h
	for c in stool.get_children():
		c.queue_free()
	var wood := Util.mat(Color(0.58, 0.4, 0.23), 0.85)
	var dark := Util.mat(Color(0.45, 0.3, 0.17), 0.9)
	stool.add_child(Util.cyl(0.14, 0.135, 0.035, wood, Vector3(0, h - 0.0175, 0)))
	for i in 3:
		var a := TAU * float(i) / 3.0
		var dir := Vector3(cos(a), 0, sin(a))
		var leg := Util.cyl(0.016, 0.02, h - 0.02, dark, dir * 0.1 + Vector3(0, (h - 0.02) * 0.5, 0))
		# ніжки трохи розставлені врізнобіч
		leg.rotation = Vector3(0, -a, 0)
		leg.rotate_object_local(Vector3(0, 0, 1), 0.12)
		stool.add_child(leg)


func _make_jet() -> CPUParticles3D:
	var fx := CPUParticles3D.new()
	fx.amount = 24
	fx.lifetime = 0.35
	fx.direction = Vector3(0, -1, 0)
	fx.spread = 6.0
	fx.initial_velocity_min = 0.4
	fx.initial_velocity_max = 0.7
	fx.gravity = Vector3(0, -7, 0)
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 0.02
	var sm := SphereMesh.new()
	sm.radius = 0.006
	sm.height = 0.016
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 0.97)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	fx.mesh = sm
	return fx


func _make_plate() -> Node3D:
	## Таця з пиріжками (шість рум'яних пиріжків). Торкнешся — Beep пригоститься.
	var n := Node3D.new()
	n.name = "Pies"
	var china := Util.mat(Color(0.97, 0.96, 0.93), 0.3)
	n.add_child(Util.cyl(0.17, 0.12, 0.022, china, Vector3(0, 0.011, 0)))
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.158
	tm.outer_radius = 0.172
	tm.rings = 24
	tm.ring_segments = 4
	rim.mesh = tm
	rim.material_override = Util.mat(Color(0.2, 0.35, 0.7), 0.4)
	rim.position = Vector3(0, 0.022, 0)
	n.add_child(rim)
	var crust := Util.mat(Color(0.86, 0.56, 0.24), 0.55)
	var pies := Node3D.new()
	pies.name = "pies"
	n.add_child(pies)
	for i in 6:
		var a := TAU * float(i) / 5.0
		var p := Vector3(cos(a) * 0.085, 0.04, sin(a) * 0.085) if i < 5 else Vector3(0, 0.06, 0)
		var pie := Util.sphere(0.045, crust, p, Vector3(1.45, 0.6, 0.85))
		pie.rotation.y = -a + 0.4
		pies.add_child(pie)
	var ar := Util.pick_area("pies", Vector3(0.45, 0.25, 0.45), Vector3(0, 0.1, 0))
	n.add_child(ar)
	return n


func eat_pie() -> bool:
	## Хтось узяв пиріжок із таці. false — пиріжків уже немає.
	if plate == null or not is_instance_valid(plate) or pies_left <= 0:
		return false
	var pies: Node3D = plate.get_node("pies")
	pies_left -= 1
	if pies.get_child_count() > 0:
		pies.get_child(pies.get_child_count() - 1).queue_free()
	if pies_left <= 0:
		var p := plate
		plate = null
		var tw := p.create_tween()
		tw.tween_interval(1.5)
		tw.tween_property(p, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(p.queue_free)
	return true


# ------------------------------------------------------------------ справи: скасування й підготовка
func begin_job(n: String) -> int:
	var id: int = super(n)
	_reset_tools()
	return id


func cancel_job() -> void:
	super()
	_reset_tools()


func _reset_tools() -> void:
	## Справу перервали: руки вільні, стільчик і дійниця — на своїх місцях, корова — знову пасеться.
	_stop_milking()
	_stool_carry = false
	if pose:
		pose.carry = 0.0
	if stool and stool.get_parent() == null:
		main.world.yard_root.add_child(stool)
	if stool:
		stool.transform = _stool_home
	if pail and held != pail and pail.get_parent() != null:
		pail.transform = pail.get_meta("home_tr", pail.transform)
	if _cow != null and is_instance_valid(_cow):
		_cow.milk_end()
	_cow = null
	if busy:
		busy = false
		if ap:
			ap.speed_scale = 1.0


func _ready_in_yard(id: int) -> bool:
	## Перед справою на подвір'ї: вийти з хати, а якщо бабуся за ворітьми — повернутися.
	if not visible or in_house:
		on_duty = true
		await appear()
		if id != job:
			return false
	if outside:
		if not await _come_in(id):
			return false
	return id == job


func _go_out(id: int) -> bool:
	## Через ворота — на дорогу.
	await _goto(spots["inside_gate"] + Vector3(-0.2, 0, 0))
	if id != job:
		return false
	await main.world.pass_gate(self, true)
	bounds = GRANNY_BOUNDS
	extra_obs = Obstacles.outer
	outside = true
	return id == job


func _come_in(id: int) -> bool:
	## Дорогою назад до воріт і на подвір'я.
	var near := 0
	var bd := INF
	for i in PASTURE_WAY.size():
		var d := global_position.distance_to(PASTURE_WAY[i])
		if d < bd:
			bd = d
			near = i
	if global_position.distance_to(spots["outside_gate"]) < bd:
		near = -1
	for i in range(near, -1, -1):
		await _goto(PASTURE_WAY[i])
		if id != job:
			return false
	await _goto(spots["outside_gate"] + Vector3(-0.2, 0, 0))
	if id != job:
		return false
	await main.world.pass_gate(self, false)
	bounds = YARD_BOUNDS
	extra_obs = []
	outside = false
	return id == job


# ------------------------------------------------------------------ вихід із хати / у хату
func appear() -> void:
	var w = main.world
	position = spots["door"] + Vector3(0.1, 0, -0.9)
	_show(true)
	in_house = false
	w.set_door("house", true, 0.4)
	await wait(0.4)
	await go(spots["door"] + Vector3(0.1, 0, 0.9), false, false)
	w.set_door("house", false, 0.4)


func vanish() -> void:
	var w = main.world
	var id := job
	await _goto(spots["door"] + Vector3(0.1, 0, 0.5), 1.0)
	if id != job:
		return                            # передумала: нова справа — лишається надворі
	face(spots["door"] + Vector3(0, 0, -2))
	w.set_door("house", true, 0.4)
	await wait(0.5)
	await go(spots["door"] + Vector3(0.1, 0, -0.9), false, false)
	if id != job:
		w.set_door("house", false, 0.4)
		return
	_show(false)
	in_house = true
	w.set_door("house", false, 0.4)


func on_arrived() -> void:
	say("Доброго ранку, любі!", 2.5)


func before_leave() -> void:
	if outside:
		var id := job
		await _come_in(id)


# ------------------------------------------------------------------ розпорядок дня
func work_step() -> void:
	var h := Game.hour()
	var d := int(Game.state["day"])
	if h >= 7.3 and h < 11.0 and _milk_day != d and _pick_cow(false) != null:
		var mid := begin_job("milk")
		await _milk(mid, false)
		end_job(mid)
		return
	var id := begin_job("chores")
	var r := randi() % 4
	match r:
		0:
			await _feed_hens(id)
		1:
			await _garden(id)
		2:
			await _well(id)
		3:
			await _house_chores(id)
	end_job(id)


# ------------------------------------------------------------------ справи з меню бабусі
func milk_job() -> void:
	var id := begin_job("milk")
	if await _milk(id, true):
		Game.emit_event("milked")
	end_job(id)


func hens_job() -> void:
	var id := begin_job("hens")
	if not await _ready_in_yard(id):
		return
	await _feed_hens(id)
	if id == job:
		Game.add_coins(2)
		Game.emit_event("granny_hens")
	end_job(id)


func garden_job() -> void:
	var id := begin_job("garden")
	if not await _ready_in_yard(id):
		return
	await _garden(id)
	if id == job:
		say("Ось і чисто на грядках!", 2.5)
		Game.add_coins(2)
		Game.emit_event("weeded")
	end_job(id)


func borscht_job() -> void:
	var id := begin_job("borscht")
	if not await _ready_in_yard(id):
		return
	_cooked_day = -1
	await _house_chores(id)
	if id == job:
		Game.add_coins(3)
		Game.emit_event("borscht")
	end_job(id)


func pies_job() -> void:
	## Іде в хату пекти пиріжки, виносить тацю й ставить на стіл.
	var id := begin_job("pies")
	if not await _ready_in_yard(id):
		return
	say("Спечу пиріжків із вишнями!", 2.5)
	await vanish()
	if id != job:
		return
	await wait(randf_range(18.0, 26.0))
	if id != job:
		return
	if plate != null and is_instance_valid(plate):
		plate.queue_free()
	plate = _make_plate()
	pies_left = 6
	await appear()
	if id != job:
		plate.queue_free()
		plate = null
		return
	hold_upright(plate, 0.05, false, 0.1)
	plate.set_meta("home_parent", null)
	if pose:
		pose.carry = 1.0                 # несе тацю перед собою
	say("Гарячі пиріжки!", 2.0)
	await _goto(TABLE_STAND, 0.5)
	if id != job:
		return
	face(TABLE_TOP)
	await wait(0.5)
	place_held(main.world.yard_root, TABLE_TOP)
	if pose:
		pose.carry = 0.0
	say("Пиріжки на столі — пригощайтеся!", 3.0)
	Game.add_coins(3)
	Game.emit_event("pies")
	await act("wave", 2.5)
	end_job(id)


func _feed_hens(id: int) -> void:
	var g: Vector3 = spots["grain"]
	await _goto(g + Vector3(0.4, 0, 0.9))
	if id != job:
		return
	face(g)
	say("Цип-цип-цип, курочки!", 2.5)
	Game.state["hens_fed"] = 100.0
	for b in main.birds:
		b.go_eat(g)
	await act("pick", 5.0)
	await wait(5.0)
	for b in main.birds:
		if b.mode == "grain":
			b.roam()


func _garden(id: int) -> void:
	var g: Vector3 = spots["garden"]
	await _goto(g + Vector3(0.6, 0, 1.0))
	if id != job:
		return
	face(g)
	say("Бур'яни геть, гарбузи — ростіть!", 2.5)
	await act("bend", 6.0)


func _well(id: int) -> void:
	await _goto(spots["well_front"] + Vector3(0.2, 0, 0.6))
	if id != job:
		return
	face(spots["well"])
	await act("drink", 6.0)


func _house_chores(id: int) -> void:
	## Прибирає й готує — заходить до хати, виходить із пирогом на ґанок.
	var d := int(Game.state["day"])
	say("Піду приберу в хаті й зготую обід.", 2.5)
	await vanish()
	if id != job:
		return
	await wait(randf_range(25.0, 40.0))
	if id != job:
		return
	await appear()
	if _cooked_day != d:
		_cooked_day = d
		say("Борщ готовий! Ідіть їсти!", 3.0)
	await act("wave", 3.0)


# ------------------------------------------------------------------ доїння
func _pick_cow(allow_inside: bool):
	## Корова, яку доїти: та, що пасеться ближче до дороги; якщо всі в корівнику — покличемо одну.
	var best = null
	var bd := INF
	var start: Vector3 = PASTURE_WAY[PASTURE_WAY.size() - 1]
	for c in main.cows:
		if c.kind != "cow" or not c.has_method("milk_begin"):
			continue
		if c.mode in ["free", "to_pasture"] and c.visible:
			var d: float = c.global_position.distance_to(start)
			if d < bd:
				bd = d
				best = c
	if best == null and allow_inside:
		for c in main.cows:
			if c.kind == "cow" and c.mode == "inside":
				return c
	return best


func _milk_spots(cow) -> Dictionary:
	## Де сісти, куди поставити дійницю й де вим'я.
	var u: Vector3 = cow.udder_point()
	var side: Vector3 = cow.global_transform.basis.x
	side.y = 0.0
	side = side.normalized()
	if (global_position - u).dot(side) < 0.0:
		side = -side                      # сідає з того боку, з якого підійшла
	var fwd: Vector3 = cow.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ug := Vector3(u.x, 0, u.z)
	return {"u": u, "side": side, "fwd": fwd, "seat": ug + side * 0.6, "pail": ug + side * 0.16,
		"approach": ug + side * 1.5}


func _milk(id: int, asked: bool) -> bool:
	## Бере дійницю й стільчик, іде на пасовисько, сідає біля корови й доїть — молоко в дійниці
	## піднімається. Потім несе повну дійницю додому й ставить біля ґанку.
	var cow = _pick_cow(asked)
	if cow == null:
		say("Корівок не видно… Мабуть, Іван їх ще не вигнав." if main.cows.size() > 0 else "Ой, а корівки ж у нас немає…", 3.0)
		return false
	_milk_day = int(Game.state["day"])
	if not await _ready_in_yard(id):
		return false
	say("Піду подою корівку!", 2.5)
	# дійниця й стільчик стоять біля ґанку
	await _goto(pail.global_position + Vector3(0.15, 0, 0.65), 0.6)
	if id != job:
		return false
	face(pail.global_position)
	await wait(0.4)
	busy = true
	play("bend")
	await wait(0.9)
	if id != job:
		return false
	_set_milk(0.0)                       # учорашнє молоко вже в глечиках
	hold_upright(pail, 0.41, false, 0.06)
	_stool_carry = true
	await wait(0.5)
	busy = false
	if id != job:
		return false
	# корова зупиняється й чекає (із корівника — виходить до дверей)
	_cow = cow
	cow.milk_begin()
	if not await _go_out(id):
		return false
	bounds = FARM_BOUNDS
	for wp in PASTURE_WAY:
		await _goto(wp)
		if id != job:
			return false
	var t := 0.0
	while cow.milk_walking() and t < 25.0:
		await wait(0.5)
		t += 0.5
		if id != job:
			return false
	var ms := _milk_spots(cow)
	await _goto(ms["approach"], 0.5)
	if id != job:
		return false
	ms = _milk_spots(cow)
	await go(ms["seat"], false, false)
	if id != job:
		return false
	var F: Vector3 = -(ms["side"] as Vector3)
	var yaw := atan2(F.x, F.z)
	_face_to = yaw
	await wait(0.5)
	if id != job:
		return false
	# ставить стільчик і дійницю під вим'я
	busy = true
	play("bend")
	await wait(0.8)
	if id != job:
		return false
	_stool_carry = false
	stool.global_transform = Transform3D(Basis(Vector3.UP, yaw), ms["seat"])
	place_held(main.world.yard_root, ms["pail"])
	pail.rotation.y = yaw
	await wait(0.6)
	if id != job:
		return false
	await _sit_on_stool(ms["seat"], yaw)
	if id != job:
		return false
	say("Ну, %s, давай молочко…" % _vocative(String(cow.get_meta("name", ""))), 3.0)
	# руки — до вимені: ліва рука до ближчого зліва дійка
	var u: Vector3 = ms["u"]
	var cf: Vector3 = ms["fwd"]
	var toward: Vector3 = ms["side"]
	var a := u + cf * 0.07 + toward * 0.05 - Vector3(0, 0.03, 0)
	var b := u - cf * 0.07 + toward * 0.05 - Vector3(0, 0.03, 0)
	var left := Vector3.UP.cross(F)
	_teats = [a, b] if (a - u).dot(left) > 0.0 else [b, a]
	_milk_t = 0.0
	_milking = true
	_jet.global_position = (a + b) * 0.5 - Vector3(0, 0.05, 0)
	_jet.emitting = true
	var dur := 15.0
	var tm := 0.0
	var next_snd := 0.0
	var mooed := false
	while tm < dur:
		await get_tree().process_frame
		if id != job:
			return false
		tm += get_process_delta_time()
		_set_milk(tm / dur * 0.92)
		if tm >= next_snd:
			next_snd = tm + 0.55
			if main.audio:
				main.audio.play_at("pop", pail, -18.0, 1.7)
		if tm > 6.0 and not mooed:
			mooed = true
			cow.say("Му-у-у…", 2.0)
	_stop_milking()
	say("Ох і молочко! Повна дійниця!", 3.0)
	# устає, бере дійницю й стільчик
	await _stand_up()
	if id != job:
		return false
	play("bend")
	await wait(0.8)
	if id != job:
		return false
	hold_upright(pail, 0.41, false, 0.06)
	_stool_carry = true
	await wait(0.4)
	busy = false
	cow.milk_end()
	_cow = null
	Game.state["milk"] = int(Game.state.get("milk", 0)) + 1
	Game.add_coins(3)
	# додому
	if not await _come_in(id):
		return false
	await _goto(pail.get_meta("home_tr", Transform3D()).origin + Vector3(0.15, 0, 0.65), 0.6)
	if id != job:
		return false
	face(pail.get_meta("home_tr", Transform3D()).origin)
	await wait(0.3)
	busy = true
	play("bend")
	await wait(0.8)
	put_back_held()                      # повна дійниця — біля ґанку
	_stool_carry = false
	stool.transform = _stool_home
	await wait(0.4)
	busy = false
	say("Парне молочко! Хто хоче — наливайте.", 3.0)
	return id == job


func _vocative(nm: String) -> String:
	## «Зірка» → «Зірко», «Красуля» → «Красуле».
	if nm == "":
		return "корівко"
	if nm.ends_with("я"):
		return nm.substr(0, nm.length() - 1) + "е"
	if nm.ends_with("а"):
		return nm.substr(0, nm.length() - 1) + "о"
	return nm


func _sit_on_stool(seat: Vector3, yaw: float) -> void:
	## Сідає на стільчик: рух «сидить і п'є» (руки потім ведемо до вимені), стегна — над сидінням.
	busy = true
	rotation.y = yaw
	_face_to = NAN
	if ap and anims.get("sit", "") != "":
		current = "sit"
		ap.play(anims["sit"], 0.5)
		ap.speed_scale = 0.5
	await wait(0.6)
	var h := hips_world()
	global_position += Vector3(seat.x - h.x, 0, seat.z - h.z)
	# висота стільчика — під стегна саме цієї моделі
	var top := clampf(h.y - global_position.y - 0.09, 0.24, 0.5)
	if absf(top - stool_h) > 0.015:
		_build_stool(top)


func _stand_up() -> void:
	if pose:
		pose.ik = {}
	if ap and anims.get("idle", "") != "":
		current = "idle"
		ap.play(anims["idle"], 0.5)
		ap.speed_scale = 1.0
	await wait(0.6)


func _milk_step(delta: float) -> void:
	## Доїть: тулуб нахилений уперед, руки по черзі тягнуть дійки донизу.
	_milk_t += delta
	if pose == null or _teats.size() < 2:
		return
	pose.lean = lerpf(float(pose.lean), 0.42, 1.0 - exp(-delta * 3.0))
	var k := clampf(_milk_t / 0.8, 0.0, 1.0)
	var s := sin(_milk_t * 7.0)
	pose.ik["LeftHand"] = [(_teats[0] as Vector3) - Vector3(0, 0.035 * maxf(s, 0.0), 0), k]
	pose.ik["RightHand"] = [(_teats[1] as Vector3) - Vector3(0, 0.035 * maxf(-s, 0.0), 0), k]


func _stop_milking() -> void:
	_milking = false
	_teats = []
	if _jet:
		_jet.emitting = false
	if pose:
		pose.ik = {}
		pose.lean = 0.0
