extends "res://scripts/farmhand.gd"
## Бабуся Галя: живе з дідусем у хаті. Годує курей, порається на городі, п'є воду біля криниці,
## варить борщ і пече пиріжки. Зранку бере дійницю (відро для молока) й стільчик і йде
## на пасовисько доїти корову — дійниця наповнюється молоком, поки вона доїть.
## Свої справи бабуся робить сама, а ще їх можна замовити в її меню (торкнись бабусі):
## подоїти корову, нагодувати курей (відерце з пшеницею — із сараю), приготувати їсти (у хаті: борщ на плиті
## або пиріжки в печі), прополоти свій город за соняшниками (сапка — із сараю), поїхати з дідом возом
## на ринок чи в ліс, відпочити на ліжку.

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

var in_room := false                  # у кімнаті хати (кімната стоїть окремо)
var _lying := false                   # лежить на ліжку
var grain_bucket: Node3D              # маленьке відерце з пшеницею (у сараї біля дверей)
var hoe: Node3D                       # сапка (у сараї під стіною)
var patch: Node3D                     # бабусин город за соняшниками
var weeds: Array = []                 # [вузол, z грядки]
var _weed_day := -1
var _hoe_on := false                  # сапка в обох руках (несе навскіс або сапає)
var _hoe_w := 0.0                     # вага пози рук на сапці
var _hoe_dig := 0.0                   # 0 — несе навскіс перед собою, 1 — сапає грядку
var _hoe_dig_to := 0.0
var _hoe_ph := 0.0                    # фаза помаху: замах — удар у землю — тягне до себе
var pot: Node3D                       # баняк (на столику в хаті)
var _soup: MeshInstance3D
var tray: Node3D                      # деко для пиріжків
var _tray_pies: Node3D
var _pie_mat: StandardMaterial3D
var _dough: Node3D
var _spoon: Node3D
var _steam: CPUParticles3D
var _grain_fx: CPUParticles3D
var _dirt_fx: CPUParticles3D
var on_tractor: Node3D = null         # віз, на якому сидить (так її не об'їжджає кінь — vehicles.gd)
var _boarding := false
var _hip_stand := 0.9
var trip_done := false                # набрала в лісі чи накупила на ринку — дід може повертати
var trip_basket: Node3D
var _porch_basket: Node3D
var _bale: Node3D                     # в'язка сіна на возі, на якій бабуся сидить
var _home_way: Array = []             # дорога від воріт туди, де бабуся зараз (назад — у зворотному порядку)

const GRANNY_BOUNDS := Rect2(-60.0, -130.0, 105.0, 164.0)
# дорога від воріт на пасовисько (та сама, якою ходить пастух)
const PASTURE_WAY := [Vector3(-24.0, 0, 8.5), Vector3(-45.0, 0, 9.0), Vector3(-120.0, 0, 9.0), Vector3(-166.0, 0, 9.0)]  # до пасовиська на фермі за ставком
const PASTURE_BOUNDS := Rect2(-200.0, -130.0, 245.0, 200.0)
const PAIL_H := 0.29                  # висота дійниці (без дужки)
const PAIL_R_BOT := 0.115
const PAIL_R_TOP := 0.145
const MILK_MAX := 0.24                # до якої висоти доливається молоко
const TABLE_TOP := Vector3(4.9, 0.8, 2.9)     # де на столі ставить пиріжки
const TABLE_STAND := Vector3(5.95, 0, 2.9)      # де стоїть біля столу
# сарай
const BUCKET_HOME := Vector3(-14.6, 0, -9.5)     # відерце з пшеницею — за дверима сараю
const BARN_IN := Vector3(-14.95, 0, -9.0)        # у дверях сараю
const HOE_WAY := [Vector3(-15.3, 0, -9.9), Vector3(-14.1, 0, -10.7), Vector3(-13.45, 0, -11.5)]   # до сапки під правою стіною
# бабусин город за соняшниками (соняшники — x 11…18, z −9.5…0.5)
const GARDEN_PATH := [Vector3(1.5, 0, 6.2), Vector3(10.5, 0, 6.0), Vector3(19.6, 0, 4.2), Vector3(19.6, 0, -9.9), Vector3(17.8, 0, -11.0)]
const BED_X0 := 12.3
const BED_LEN := 4.4
const PATCH_BEDS := [-11.0, -12.2, -13.4]       # z грядок (тягнуться вздовж x)
# хата (у системі кімнати)
const TABLE_K := Vector3(-0.65, 0, -0.95)        # столик, де місить тісто
const K_STAND := Vector3(-0.65, 0, -0.32)
const POT_HOME := Vector3(-0.3, 0.76, -0.95)     # баняк на столику
const POT_STAND := Vector3(-0.3, 0, -0.32)
const BOWL_AT := Vector3(-1.0, 0.76, -0.95)      # макітра з тістом
const TRAY_AT := Vector3(-0.65, 0.76, -0.95)     # деко
const POT_H := 0.2
const HOB := Vector3(2.09, 0, -0.975)            # припічок із плитою ліворуч від челюстей печі
const HOB_TOP := Vector3(2.09, 0.84, -0.97)
const HOB_STAND := Vector3(2.09, 0, -0.42)
const OVEN_MOUTH := Vector3(2.6, 0.4, -1.08)     # челюсті печі
const OVEN_IN := Vector3(2.6, 0.4, -1.75)
const OVEN_STAND := Vector3(2.62, 0, -0.42)
const BED_SIDE := Vector3(0.24, 0, -1.55)        # біля ліжка, з лівого боку
const LIE_ROOT := Vector3(1.1, 1.04, -0.98)      # лежить: ноги тут, голова — до подушки (−z)
# віз
const GR_SEAT := Vector3(0.0, 0.95, -1.05)       # де сидить (стегна) — ззаду воза на в'язці сіна, у системі воза
const GR_BASKET := Vector3(-0.3, 0.57, -0.62)    # її кошик на возі (під ногами, ліворуч)
const GR_BALE := Vector3(0.0, 0.72, -1.12)       # в'язка сіна під бабусею
const CART_REAR := -2.05                         # z за возом, звідки вилазить і куди злазить
# як вилазить на віз (у системі воза): стає збоку біля заднього колеса, хапається за борт,
# ставить ногу на маточину колеса, підтягується через борт, стає на дно воза — і сідає в сіно
const CLIMB_AT := Vector3(0.98, 0, -1.28)        # де стоїть перед тим, як лізти
const CLIMB_GRIP_L := Vector3(0.53, 0.99, -1.02) # ліва рука — верх борту ближче до колеса
const CLIMB_GRIP_R := Vector3(0.5, 1.03, -1.47)  # права рука — задній стовпчик борту
const CLIMB_STEP := Vector3(0.66, 0.56, -0.98)   # ліва нога — на маточину заднього колеса
const CLIMB_EDGE := Vector3(0.52, 1.06, -1.34)   # права нога — на верх борту
const CART_FLOOR := 0.68                         # дно воза (з сіном)
const GATE_WAIT := Vector3(-1.5, 0, 7.8)         # чекає на віз біля воріт
const TRIP_BOUNDS := Rect2(-235.0, -140.0, 385.0, 350.0)
const MARKET_WALK := [Vector3(1.8, 0, 12.5), Vector3(2.0, 0, 20.0), Vector3(3.0, 0, 31.0), Vector3(5.5, 0, 50.0), Vector3(5.5, 0, 68.0),
	Vector3(2.2, 0, 82.0), Vector3(0.6, 0, 96.5), Vector3(0.6, 0, 110.0), Vector3(0.8, 0, 150.0)]
const SHOP_ASK := {"fruit": "Яблучок і груш, будь ласка!", "bread": "Паляничку й булочок онукам!", "sweets": "І пряників — дітям на гостинці!"}
const SHOP_COL := {"fruit": Color(0.85, 0.15, 0.1), "bread": Color(0.85, 0.62, 0.3), "sweets": Color(0.75, 0.45, 0.2)}
const BERRIES := ["sunytsi", "malyna", "chornytsi", "ozhyna", "brusnytsi", "malynnyk", "romashka", "zvirobii", "chebrets", "myata",
	"deryvii", "dzvinochky"]


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
	if _hoe_on:
		_hoe_step(delta)
	if on_tractor and not _boarding:
		if not is_instance_valid(on_tractor):
			on_tractor = null
		else:
			# сидить на возі поруч із дідом
			_face_to = NAN
			rotation.y = on_tractor.rotation.y
			place_hips(on_tractor.to_global(GR_SEAT))


# ------------------------------------------------------------------ дійниця, стільчик, пиріжки
func _make_tools() -> void:
	var root: Node3D = main.world.yard_root
	_make_barn_things(root)
	_make_patch(root)
	_make_kitchen(main.world.room_root)
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


# ------------------------------------------------------------------ відерце з пшеницею, сапка, город за соняшниками
func _make_barn_things(root: Node3D) -> void:
	grain_bucket = _make_small_bucket()
	root.add_child(grain_bucket)
	grain_bucket.position = BUCKET_HOME
	Walker.remember_home(grain_bucket)
	# сапка — та, що стоїть у сараї під стіною (якщо її немає — своя)
	hoe = root.find_child("Thing_hoe", true, false) as Node3D
	if hoe == null:
		hoe = Util.thing("hoe")
		if hoe:
			root.add_child(hoe)
			hoe.position = Vector3(-12.8, 0, -11.74)
			hoe.rotation = Vector3(0.16, PI / 2.0, 0)
	if hoe:
		Walker.remember_home(hoe)
	_grain_fx = _make_burst(Color(0.9, 0.75, 0.3), 0.012)
	root.add_child(_grain_fx)
	_dirt_fx = _make_burst(Color(0.4, 0.29, 0.18), 0.02)
	root.add_child(_dirt_fx)


func _make_small_bucket() -> Node3D:
	## Маленьке оцинковане відерце з дужкою, повне пшениці.
	var n := Node3D.new()
	n.name = "GrainBucket"
	var tin := _tin()
	var rb := 0.075
	var rt := 0.095
	var H := 0.17
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(rb, 0.0), Vector2(rt, H), Vector2(rt + 0.005, H + 0.004),
		Vector2(rt - 0.004, H), Vector2(rb - 0.005, 0.01), Vector2(0.0, 0.01)])
	n.add_child(_lathe(prof, 20, tin))
	var arc := PackedVector3Array()
	for i in 13:
		var a := PI * float(i) / 12.0
		arc.append(Vector3(cos(a) * (rt + 0.005), H - 0.02 + sin(a) * rt * 0.9, 0))
	n.add_child(_tube(arc, 0.0035, tin))
	var grain := Util.mat(Color(0.86, 0.7, 0.32), 0.95)
	n.add_child(Util.cyl(rt - 0.006, rt - 0.006, 0.01, grain, Vector3(0, H - 0.025, 0)))
	n.add_child(Util.sphere(rt - 0.01, grain, Vector3(0, H - 0.02, 0), Vector3(1, 0.25, 1)))
	return n


func _make_burst(c: Color, r: float) -> CPUParticles3D:
	## Жменя зерна чи грудочки землі: один викид (restart()).
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.emitting = false
	fx.amount = 28
	fx.lifetime = 0.9
	fx.explosiveness = 0.85
	fx.direction = Vector3(0, 0.6, 1)
	fx.spread = 28.0
	fx.initial_velocity_min = 1.0
	fx.initial_velocity_max = 1.8
	fx.gravity = Vector3(0, -9.0, 0)
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.6
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	sm.material = m
	fx.mesh = sm
	return fx


func _burst(fx: CPUParticles3D, at: Vector3, dir: Vector3, v := 1.4) -> void:
	if fx == null:
		return
	fx.global_position = at
	fx.direction = dir.normalized()
	fx.initial_velocity_min = v * 0.7
	fx.initial_velocity_max = v
	fx.restart()
	fx.emitting = true


func _no_shadow(g: GeometryInstance3D) -> GeometryInstance3D:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


func _make_patch(root: Node3D) -> void:
	## Невеличкий бабусин город за соняшниками: три грядки — капуста й буряки, між ними бур'ян (його й полоть).
	patch = Node3D.new()
	patch.name = "GrannyPatch"
	root.add_child(patch)
	var ground := Util.mat(Color(0.47, 0.37, 0.24), 1.0)
	var soil := Util.mat(Color(0.35, 0.24, 0.15), 1.0)
	var leaf := Util.mat(Color(0.36, 0.6, 0.26), 0.8)
	var cab := Util.mat(Color(0.66, 0.8, 0.48), 0.7)
	var beet := Util.mat(Color(0.5, 0.1, 0.18), 0.6)
	var weed := Util.mat(Color(0.52, 0.74, 0.2), 0.9)
	var cx := BED_X0 + BED_LEN / 2.0
	patch.add_child(_no_shadow(Util.box(Vector3(BED_LEN + 1.2, 0.02, 4.2), ground, Vector3(cx, 0.01, -12.2))))
	# низенький тин з кілочків довкола
	var stake := Util.mat(Color(0.5, 0.36, 0.22), 0.9)
	for side in [-1.0, 1.0]:
		patch.add_child(Util.box(Vector3(BED_LEN + 1.2, 0.04, 0.04), stake, Vector3(cx, 0.35, -12.2 + side * 2.1)))
		patch.add_child(Util.box(Vector3(0.04, 0.04, 4.2), stake, Vector3(cx + side * (BED_LEN / 2.0 + 0.6), 0.35, -12.2)))
		for k in 7:
			patch.add_child(Util.cyl(0.025, 0.03, 0.5, stake, Vector3(cx - BED_LEN / 2.0 - 0.6 + k * (BED_LEN + 1.2) / 6.0, 0.25, -12.2 + side * 2.1)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b in PATCH_BEDS.size():
		var bz: float = PATCH_BEDS[b]
		patch.add_child(_no_shadow(Util.box(Vector3(BED_LEN, 0.12, 0.7), soil, Vector3(cx, 0.06, bz))))
		for i in 6:
			var x := BED_X0 + 0.35 + i * 0.74
			if b != 1:
				patch.add_child(Util.sphere(0.2, leaf, Vector3(x, 0.16, bz), Vector3(1.0, 0.32, 1.0)))
				patch.add_child(Util.sphere(0.13, cab, Vector3(x, 0.22, bz), Vector3(1.0, 0.85, 1.0)))
			else:
				patch.add_child(_no_shadow(Util.sphere(0.05, beet, Vector3(x, 0.14, bz))))
				for k in 4:
					var lf := _no_shadow(Util.sphere(0.05, leaf, Vector3(x, 0.26, bz), Vector3(0.45, 2.2, 0.2)))
					lf.rotation = Vector3(0, k * PI / 2.0, 0.45)
					lf.position += Vector3(cos(k * PI / 2.0) * 0.05, 0, -sin(k * PI / 2.0) * 0.05)
					patch.add_child(lf)
		for i in 7:
			var w := Node3D.new()
			w.position = Vector3(BED_X0 + 0.2 + rng.randf() * (BED_LEN - 0.4), 0.12, bz + rng.randf_range(-0.27, 0.27))
			for k in 3:
				var a := TAU * k / 3.0 + rng.randf()
				var bl := _no_shadow(Util.sphere(0.03, weed, Vector3(cos(a) * 0.03, 0.07, sin(a) * 0.03), Vector3(0.45, 2.6, 0.45)))
				bl.rotation = Vector3(sin(a) * 0.4, 0, cos(a) * 0.4)
				w.add_child(bl)
			patch.add_child(w)
			weeds.append([w, bz])


# ------------------------------------------------------------------ у хаті: столик, припічок із плитою, баняк, макітра, деко
func _rp(v: Vector3) -> Vector3:
	## Точка кімнати (у системі кімнати) — у світі.
	return main.world.ROOM + v


func _make_kitchen(room: Node3D) -> void:
	if room == null:
		return
	var wood := Util.mat(Color(0.6, 0.42, 0.25), 0.85)
	room.add_child(Util.box(Vector3(1.0, 0.04, 0.5), wood, TABLE_K + Vector3(0, 0.74, 0)))
	for sx in [-0.45, 0.45]:
		for sz in [-0.2, 0.2]:
			room.add_child(Util.box(Vector3(0.05, 0.72, 0.05), wood, TABLE_K + Vector3(sx, 0.36, sz)))
	# припічок (біленький, як піч) із чавунною плитою
	var clay := Util.mat(Color(0.88, 0.85, 0.79), 0.95)
	room.add_child(Util.box(Vector3(0.46, 0.82, 0.35), clay, HOB + Vector3(0, 0.41, 0)))
	var iron := Util.mat(Color(0.16, 0.15, 0.15), 0.5, 0.6)
	room.add_child(Util.box(Vector3(0.44, 0.02, 0.33), iron, HOB + Vector3(0, 0.83, 0)))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.12
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = Util.mat(Color(0.25, 0.23, 0.22), 0.5, 0.6)
	ring.position = HOB_TOP
	room.add_child(ring)
	# баняк
	pot = _make_pot()
	room.add_child(pot)
	pot.position = POT_HOME
	Walker.remember_home(pot)
	# макітра з тістом
	var bowl := Node3D.new()
	room.add_child(bowl)
	bowl.position = BOWL_AT
	var clay2 := Util.mat(Color(0.72, 0.45, 0.28), 0.8)
	clay2.cull_mode = BaseMaterial3D.CULL_DISABLED
	bowl.add_child(_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.08, 0.0), Vector2(0.15, 0.1), Vector2(0.16, 0.13),
		Vector2(0.145, 0.125), Vector2(0.07, 0.012), Vector2(0.0, 0.012)]), 20, clay2))
	_dough = Node3D.new()
	bowl.add_child(_dough)
	_dough.position = Vector3(0, 0.07, 0)
	_dough.add_child(Util.sphere(0.11, Util.mat(Color(0.96, 0.9, 0.76), 0.9), Vector3.ZERO, Vector3(1, 0.6, 1)))
	# деко з пиріжками (сирі — блідо-кремові, спечені — рум'яні)
	tray = Node3D.new()
	tray.name = "Tray"
	room.add_child(tray)
	tray.position = TRAY_AT
	Walker.remember_home(tray)
	var tin := Util.mat(Color(0.3, 0.3, 0.32), 0.45, 0.6)
	tray.add_child(Util.box(Vector3(0.38, 0.012, 0.28), tin, Vector3(0, 0.006, 0)))
	for s in [-1.0, 1.0]:
		tray.add_child(Util.box(Vector3(0.38, 0.025, 0.01), tin, Vector3(0, 0.017, s * 0.135)))
		tray.add_child(Util.box(Vector3(0.01, 0.025, 0.28), tin, Vector3(s * 0.185, 0.017, 0)))
	_pie_mat = Util.mat(Color(0.95, 0.88, 0.7), 0.7)
	_tray_pies = Node3D.new()
	tray.add_child(_tray_pies)
	for i in 6:
		var p := Util.sphere(0.042, _pie_mat, Vector3(-0.11 + (i % 3) * 0.11, 0.03, -0.065 + floorf(i / 3.0) * 0.13), Vector3(1.45, 0.6, 0.85))
		p.visible = false
		_tray_pies.add_child(p)
	# дерев'яна ложка (у руці, коли мішає борщ)
	_spoon = Node3D.new()
	room.add_child(_spoon)
	_spoon.add_child(Util.cyl(0.009, 0.009, 0.34, wood, Vector3(0, 0.17, 0)))
	_spoon.add_child(Util.sphere(0.025, wood, Vector3(0, 0.0, 0), Vector3(1, 0.4, 1.3)))
	_spoon.visible = false
	# пара над баняком
	_steam = CPUParticles3D.new()
	_steam.amount = 14
	_steam.lifetime = 1.8
	_steam.direction = Vector3.UP
	_steam.spread = 12.0
	_steam.initial_velocity_min = 0.2
	_steam.initial_velocity_max = 0.35
	_steam.gravity = Vector3(0, 0.12, 0)
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_steam.emission_sphere_radius = 0.07
	_steam.scale_amount_min = 1.0
	_steam.scale_amount_max = 2.4
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 6
	sm.rings = 3
	var sml := StandardMaterial3D.new()
	sml.albedo_color = Color(1, 1, 1, 0.3)
	sml.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sml.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = sml
	_steam.mesh = sm
	_steam.emitting = false
	room.add_child(_steam)


func _make_pot() -> Node3D:
	## Емальований баняк із вушками; усередині — вода, що стає борщем (_set_soup).
	var n := Node3D.new()
	n.name = "Pot"
	var en := Util.mat(Color(0.92, 0.9, 0.84), 0.3)
	en.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rb := 0.115
	var rt := 0.13
	var H := POT_H
	n.add_child(_lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(rb, 0.0), Vector2(rt, H), Vector2(rt + 0.006, H + 0.004),
		Vector2(rt - 0.004, H), Vector2(rb - 0.005, 0.01), Vector2(0.0, 0.01)]), 24, en))
	var blue := Util.mat(Color(0.2, 0.32, 0.65), 0.35)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = rt - 0.002
	tm.outer_radius = rt + 0.01
	tm.rings = 24
	tm.ring_segments = 4
	rim.mesh = tm
	rim.material_override = blue
	rim.position = Vector3(0, H, 0)
	n.add_child(rim)
	for s in [-1.0, 1.0]:
		n.add_child(Util.box(Vector3(0.05, 0.015, 0.035), blue, Vector3(s * (rt + 0.02), H - 0.03, 0)))
	_soup = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt - 0.008
	cm.bottom_radius = rt - 0.008
	cm.height = 0.004
	cm.radial_segments = 20
	cm.rings = 1
	_soup.mesh = cm
	_soup.material_override = StandardMaterial3D.new()
	_soup.position = Vector3(0, H - 0.035, 0)
	n.add_child(_soup)
	_set_soup(1.0)
	return n


func _set_soup(k: float) -> void:
	## 0 — вода, 1 — червоний борщ.
	if _soup:
		(_soup.material_override as StandardMaterial3D).albedo_color = Color(0.72, 0.8, 0.86).lerp(Color(0.68, 0.1, 0.12), clampf(k, 0.0, 1.0))


func _steam_at(p) -> void:
	## Пара над баняком (null — вимкнути).
	if _steam == null:
		return
	if p == null:
		_steam.emitting = false
		return
	_steam.global_position = (p as Vector3) + Vector3(0, POT_H + 0.03, 0)
	_steam.emitting = true


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
	_hoe_stop()
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
	# лежала на ліжку чи сиділа на возі — стає на ноги
	if _lying:
		_lying = false
		if in_room:
			global_position = _rp(BED_SIDE)
	rotation = Vector3(0, rotation.y, 0)
	if on_tractor or _boarding:
		var c := on_tractor
		on_tractor = null
		_boarding = false
		if c and is_instance_valid(c):
			global_position = c.to_global(Vector3(0, 0, CART_REAR))
		global_position.y = 0.0
		current = ""
	if trip_basket and is_instance_valid(trip_basket) and held != trip_basket:
		trip_basket.queue_free()
	trip_basket = null
	_drop_bale()
	# у хаті: ложку сховати, пару вимкнути, баняк і деко — на столик
	if _spoon:
		_spoon.visible = false
	_steam_at(null)
	if pot and held != pot and pot.get_parent() != null:
		pot.transform = pot.get_meta("home_tr", pot.transform)
	if tray and held != tray and tray.get_parent() != null:
		tray.transform = tray.get_meta("home_tr", tray.transform)
		tray.visible = true
	if busy:
		busy = false
		if ap:
			ap.speed_scale = 1.0


func _ready_in_yard(id: int) -> bool:
	## Перед справою на подвір'ї: вийти з хати, а якщо бабуся за ворітьми — повернутися.
	if in_room:
		if not await _walk_out_room(id):
			return false
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
	var way: Array = _home_way if not _home_way.is_empty() else PASTURE_WAY
	var near := 0
	var bd := INF
	for i in way.size():
		var d := global_position.distance_to(way[i])
		if d < bd:
			bd = d
			near = i
	if global_position.distance_to(spots["outside_gate"]) < bd:
		near = -1
	for i in range(near, -1, -1):
		await _goto(way[i])
		if id != job:
			return false
	_home_way = []
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
	if in_room:
		await _walk_out_room(job)
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


func cook_job() -> void:
	## «Приготую їсти»: борщ на плиті або пиріжки в печі (коли бабуся просить пиріжків — пиріжки).
	if String(Game.current_quest().get("id", "")) == "granny_pies" or randi() % 2 == 0:
		pies_job()
	else:
		borscht_job()


func _pick_up(obj: Node3D, below: float, fwd: float, carry: bool, low := false) -> void:
	## Бере річ: зі столу — тягнеться рукою, з долівки — нахиляється. carry — несе перед собою обома руками.
	busy = true
	play("bend" if low else "pick")
	await wait(0.7)
	hold_upright(obj, below, false, fwd)
	if pose and carry:
		pose.carry = 1.0
	await wait(0.25)
	busy = false


func _put_down(where: Node3D, at: Vector3, low := false) -> void:
	busy = true
	play("bend" if low else "pick")
	await wait(0.6)
	place_held(where, at)
	if pose:
		pose.carry = 0.0
	await wait(0.25)
	busy = false


func borscht_job() -> void:
	## Іде в хату, бере зі столика баняк, ставить на плиту й варить борщ (мішає ложкою, іде пара).
	var id := begin_job("borscht")
	if not await _ready_in_yard(id):
		return
	var room: Node3D = main.world.room_root
	say("Піду зварю борщику!", 2.5)
	if not await _walk_in_room(id):
		return
	await go(_rp(POT_STAND), false, false)
	if id != job:
		return
	face(pot.global_position)
	await wait(0.3)
	await _pick_up(pot, 0.1, 0.16, true)
	if id != job:
		return
	await go(_rp(HOB_STAND), false, false)
	if id != job:
		return
	face(_rp(HOB_TOP))
	await wait(0.3)
	await _put_down(room, HOB_TOP)
	if id != job:
		return
	_set_soup(0.0)
	_steam_at(pot.global_position)
	say("Буряк, капустка, морквинка, картопелька…", 3.0)
	# мішає ложкою по колу
	busy = true
	_spoon.visible = true
	var dur := 14.0
	var T := 0.0
	var said := false
	while T < dur:
		await get_tree().process_frame
		if id != job:
			return
		T += get_process_delta_time()
		_set_soup(T / dur)
		var top: Vector3 = pot.global_position + Vector3(0, POT_H + 0.13, 0)
		var a := T * 3.5
		if pose:
			pose.lean = lerpf(float(pose.lean), 0.15, 0.1)
			pose.ik = {"RightHand": [top + Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), clampf(T / 0.6, 0.0, 1.0)]}
		if hand:
			_spoon.global_transform = Transform3D(Basis(), hand.global_position - Vector3(0, 0.3, 0))
		if T > dur * 0.6 and not said:
			said = true
			say("Ще часничку — і буде смакота!", 2.5)
	_spoon.visible = false
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	busy = false
	say("Ох і запашний борщ!", 2.5)
	# баняк — на столик
	await _pick_up(pot, 0.1, 0.16, true)
	_steam_at(null)
	if id != job:
		return
	await go(_rp(POT_STAND), false, false)
	if id != job:
		return
	face(_rp(POT_HOME))
	await wait(0.3)
	await _put_down(room, POT_HOME)
	_steam_at(pot.global_position)
	if id != job:
		return
	if not await _walk_out_room(id):
		return
	_steam_at(null)
	_cooked_day = int(Game.state["day"])
	say("Борщ готовий! Ідіть їсти!", 3.0)
	Game.add_coins(3)
	Game.emit_event("borscht")
	await act("wave", 2.5)
	end_job(id)


func pies_job() -> void:
	## Іде в хату: місить тісто, ліпить пиріжки на деко, ставить у піч, виймає, перекладає на тацю
	## і виносить на стіл на подвір'ї.
	var id := begin_job("pies")
	if not await _ready_in_yard(id):
		return
	var room: Node3D = main.world.room_root
	say("Спечу пиріжків із вишнями!", 2.5)
	if not await _walk_in_room(id):
		return
	_pie_mat.albedo_color = Color(0.95, 0.88, 0.7)
	for p in _tray_pies.get_children():
		(p as Node3D).visible = false
	_dough.scale = Vector3.ONE
	await go(_rp(K_STAND), false, false)
	if id != job:
		return
	face(_rp(BOWL_AT))
	await wait(0.3)
	say("Спершу замішу тісто…", 2.5)
	# місить: руки по черзі тиснуть тісто
	busy = true
	var dp: Vector3 = _dough.global_position
	var T := 0.0
	while T < 7.0:
		await get_tree().process_frame
		if id != job:
			return
		var dt := get_process_delta_time()
		T += dt
		var s := sin(T * 6.0)
		var k := clampf(T / 0.6, 0.0, 1.0)
		if pose:
			pose.lean = lerpf(float(pose.lean), 0.3, 1.0 - exp(-dt * 3.0))
			pose.ik = {"LeftHand": [dp + Vector3(-0.05, 0.07 - 0.04 * maxf(s, 0.0), 0.02), k],
				"RightHand": [dp + Vector3(0.05, 0.07 - 0.04 * maxf(-s, 0.0), 0.02), k]}
		_dough.scale = Vector3(1.0 + 0.08 * absf(s), 1.0 - 0.12 * absf(s), 1.0 + 0.08 * absf(s))
	# ліпить пиріжки й кладе на деко
	say("А тепер — пиріжечки з вишнями.", 2.5)
	var pies := _tray_pies.get_children()
	for i in pies.size():
		var to: Vector3 = (pies[i] as Node3D).global_position
		var t2 := 0.0
		while t2 < 0.8:
			await get_tree().process_frame
			if id != job:
				return
			t2 += get_process_delta_time()
			var u := clampf(t2 / 0.8, 0.0, 1.0)
			var hp: Vector3 = (dp + Vector3(0, 0.08, 0)).lerp(to + Vector3(0, 0.06, 0), u) + Vector3(0, sin(u * PI) * 0.08, 0)
			if pose:
				pose.ik = {"RightHand": [hp, 1.0], "LeftHand": [dp + Vector3(-0.05, 0.07, 0.02), 1.0 - u * 0.5]}
		(pies[i] as Node3D).visible = true
		_dough.scale = Vector3.ONE * maxf(0.25, 1.0 - float(i + 1) * 0.12)
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	busy = false
	# деко — у піч
	await _pick_up(tray, 0.04, 0.14, true)
	if id != job:
		return
	await go(_rp(OVEN_STAND), false, false)
	if id != job:
		return
	face(_rp(OVEN_MOUTH))
	await wait(0.3)
	await _put_down(room, OVEN_MOUTH)
	if id != job:
		return
	var tw := tray.create_tween()
	tw.tween_property(tray, "position", OVEN_IN, 0.8)
	await wait(0.85)
	if id != job:
		return
	tray.visible = false
	say("У піч — хай печуться!", 2.5)
	var bake := randf_range(16.0, 22.0)
	while bake > 0.0:
		await wait(1.0)
		if id != job:
			return
		bake -= 1.0
		if absf(bake - 8.0) < 0.5:
			say("Ох, як пахне! Уже рум'яніють.", 2.5)
	# виймає
	busy = true
	play("pick")
	await wait(0.5)
	_pie_mat.albedo_color = Color(0.86, 0.56, 0.24)
	tray.visible = true
	tw = tray.create_tween()
	tw.tween_property(tray, "position", OVEN_MOUTH, 0.8)
	await wait(0.85)
	busy = false
	if id != job:
		return
	say("Готові! Рум'яні!", 2.0)
	await _pick_up(tray, 0.04, 0.14, true)
	if id != job:
		return
	await go(_rp(K_STAND), false, false)
	if id != job:
		return
	face(_rp(TRAY_AT))
	await wait(0.3)
	await _put_down(room, TRAY_AT)
	if id != job:
		return
	# перекладає на тацю
	busy = true
	play("pick")
	await wait(0.7)
	for p in _tray_pies.get_children():
		(p as Node3D).visible = false
	if plate != null and is_instance_valid(plate):
		plate.queue_free()
	plate = _make_plate()
	pies_left = 6
	hold_upright(plate, 0.05, false, 0.1)
	plate.set_meta("home_parent", null)
	if pose:
		pose.carry = 1.0                 # несе тацю перед собою
	await wait(0.3)
	busy = false
	if id != job:
		return
	say("Гарячі пиріжки!", 2.0)
	if not await _walk_out_room(id):
		return
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


func rest_job() -> void:
	## «Піду відпочину»: заходить у хату й лягає на ліжко, а потім знову виходить на подвір'я.
	var id := begin_job("rest")
	if not await _ready_in_yard(id):
		return
	say("Піду трохи відпочину…", 2.5)
	if not await _walk_in_room(id):
		return
	await go(_rp(Vector3(0.3, 0, -0.4)), false, false)
	if id != job:
		return
	await go(_rp(BED_SIDE), false, false)
	if id != job:
		return
	face(_rp(Vector3(1.1, 0, BED_SIDE.z)))
	await wait(0.5)
	if id != job:
		return
	busy = true
	_lying = true
	await _lie_tween(id, true)
	if id != job:
		return
	if ap:
		ap.speed_scale = 0.4             # лежить тихо, ледь дихає
	say("Ох, і добре полежати…", 2.5)
	var t := randf_range(35.0, 50.0)
	while t > 0.0:
		await wait(5.0)
		if id != job:
			return
		t -= 5.0
		if randf() < 0.5:
			say("z-z-z…", 2.0)
	if ap:
		ap.speed_scale = 1.0
	await _lie_tween(id, false)
	if id != job:
		return
	_lying = false
	busy = false
	say("Відпочила — можна й до роботи!", 2.5)
	if not await _walk_out_room(id):
		return
	end_job(id)


func _lie_tween(id: int, down: bool) -> void:
	## Лягає на ліжко (down) чи встає: піднімається на постіль і вкладається на спину, головою до подушки.
	var a := _rp(BED_SIDE)
	var b := _rp(LIE_ROOT)
	_face_to = NAN
	var T := 0.0
	while T < 1.0:
		await get_tree().process_frame
		if id != job:
			return
		T = minf(1.0, T + get_process_delta_time() / 2.2)
		var k := T if down else 1.0 - T
		var e := k * k * (3.0 - 2.0 * k)
		var p := a.lerp(b, e)
		p.y += sin(e * PI) * 0.3
		global_position = p
		rotation = Vector3(-PI / 2.0 * clampf((e - 0.2) / 0.8, 0.0, 1.0), lerp_angle(PI / 2.0, 0.0, e), 0)
	if not down:
		rotation = Vector3(0, PI / 2.0, 0)
		global_position = a


func _feed_hens(id: int) -> void:
	## Бере в сараї маленьке відерце з пшеницею, сипле курям зерно, а відерце відносить назад.
	var has: bool = grain_bucket != null and is_instance_valid(grain_bucket) and grain_bucket.get_parent() != null
	if has:
		say("Візьму в сараї пшенички курочкам.", 2.5)
		if not await _into_barn(id, []):
			return
		face(BUCKET_HOME)
		await wait(0.3)
		await _pick_up(grain_bucket, 0.27, 0.06, false, true)
		if id != job:
			return
		if not await _out_of_barn(id, []):
			return
	var g: Vector3 = spots["grain"]
	await _goto(g + Vector3(0.4, 0, 0.9))
	if id != job:
		return
	face(g)
	say("Цип-цип-цип, курочки!", 2.5)
	Game.state["hens_fed"] = 100.0
	for b in main.birds:
		b.go_eat(g)
	for i in 3:
		busy = true
		play("pick")
		await wait(0.55)
		if id != job:
			return
		var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
		var from: Vector3 = (hand.global_position if hand else global_position + Vector3(0, 1.0, 0)) + f * 0.1
		_burst(_grain_fx, from, f + Vector3(randf_range(-0.4, 0.4), 0.5, 0), 1.6)
		await wait(1.0)
		if id != job:
			return
	busy = false
	await wait(4.0)
	for b in main.birds:
		if b.mode == "grain":
			b.roam()
	if id != job or not has or held != grain_bucket:
		return
	say("Відерце — назад у сарай.", 2.0)
	if not await _into_barn(id, []):
		return
	face(BUCKET_HOME)
	await wait(0.3)
	busy = true
	play("bend")
	await wait(0.6)
	put_back_held()
	await wait(0.3)
	busy = false
	await _out_of_barn(id, [])


func _into_barn(id: int, inner: Array) -> bool:
	## До сараю (двері відчиняються самі) і всередину.
	await _goto(spots["barn"], 0.6)
	if id != job:
		return false
	for p in [BARN_IN] + inner:
		await go(p, false, false)
		if id != job:
			return false
	return true


func _out_of_barn(id: int, inner: Array) -> bool:
	var back := inner.duplicate()
	back.reverse()
	for p in back + [BARN_IN, spots["barn"]]:
		await go(p, false, false)
		if id != job:
			return false
	return true


func _garden(id: int) -> void:
	## Бере в сараї сапку, іде на свій город за соняшниками й полоть грядки, а потім ставить сапку на місце.
	var tool_ok: bool = hoe != null and is_instance_valid(hoe) and hoe.get_parent() == hoe.get_meta("home_parent", null)
	if tool_ok:
		say("Візьму сапку — і на город.", 2.5)
		if not await _into_barn(id, HOE_WAY.slice(0, HOE_WAY.size() - 1)):
			return
		await go(HOE_WAY[HOE_WAY.size() - 1], false, false)
		if id != job:
			return
		face(hoe.global_position)
		await wait(0.3)
		await _pick_up(hoe, 0.42, 0.1, false)
		if id != job:
			return
		_hoe_on = true
		_hoe_w = 0.0
		_hoe_dig = 0.0
		_hoe_dig_to = 0.0
		_hoe_ph = 0.0
		if not await _out_of_barn(id, HOE_WAY):
			return
	else:
		say("Де ж це моя сапка? Ну, руками пополю.", 2.5)
	if not await _go_out(id):
		return
	_home_way = GARDEN_PATH
	for wp in GARDEN_PATH:
		await _goto(wp)
		if id != job:
			return
	var d := int(Game.state["day"])
	if _weed_day != d:
		for w in weeds:
			(w[0] as Node3D).visible = true      # за добу бур'ян знову повилазив
	say("Бур'яни геть, капусточко — рости!", 2.5)
	for b in PATCH_BEDS.size():
		var bz: float = PATCH_BEDS[b]
		var xs: Array = []
		for i in 5:
			xs.append(BED_X0 + 0.45 + i * 0.88)
		if b % 2 == 1:
			xs.reverse()                         # змійкою: туди — і назад по сусідній грядці
		for x in xs:
			await go(Vector3(x, 0, bz + 0.62), false, false)
			if id != job:
				return
			face(Vector3(x, 0, bz))
			if tool_ok:
				_hoe_dig_to = 1.0
				_hoe_ph = 0.0
			await wait(0.2)
			busy = true
			if not tool_ok:
				play("bend")
			for c in 2:
				var t := 0.0
				var hit := false
				while t < 0.8:
					await get_tree().process_frame
					if id != job:
						return
					var dt := get_process_delta_time()
					t += dt
					if tool_ok and pose:
						var u := clampf(t / 0.8, 0.0, 1.0)
						_hoe_ph = u
						# низько нагнулась над грядкою: на замаху ледь випрямляється, на ударі — ще нижче
						var want := 0.78 - 0.1 * sin(clampf(u / 0.5, 0.0, 1.0) * PI) + 0.06 * clampf((u - 0.5) / 0.15, 0.0, 1.0)
						pose.lean = lerpf(float(pose.lean), want, clampf(dt * 8.0, 0.0, 1.0))
					if not hit and t >= (0.52 if tool_ok else 0.8):
						hit = true
						_burst(_dirt_fx, Vector3(x, 0.15, bz + 0.1), Vector3(0, 1.0, 0.4), 1.0)
			_hoe_dig_to = 0.0
			_hoe_ph = 0.0
			if pose:
				var t2 := 0.0
				while t2 < 0.25 and pose:
					await get_tree().process_frame
					if id != job:
						return
					t2 += get_process_delta_time()
					pose.lean = lerpf(float(pose.lean), 0.0, clampf(t2 / 0.25, 0.0, 1.0))
				pose.lean = 0.0
			for w in weeds:
				if float(w[1]) == bz and absf((w[0] as Node3D).position.x - x) < 0.5:
					(w[0] as Node3D).visible = false
			busy = false
	_weed_day = d
	if not await _come_in(id):
		return
	if tool_ok and held == hoe:
		if not await _into_barn(id, HOE_WAY.slice(0, HOE_WAY.size() - 1)):
			return
		await go(HOE_WAY[HOE_WAY.size() - 1], false, false)
		if id != job:
			return
		face(hoe.get_meta("home_tr", Transform3D()).origin + (hoe.get_meta("home_parent") as Node3D).global_position)
		await wait(0.3)
		_hoe_stop()
		busy = true
		play("pick")
		await wait(0.6)
		put_back_held()
		await wait(0.3)
		busy = false
		await _out_of_barn(id, HOE_WAY)


func _hoe_stop() -> void:
	if not _hoe_on:
		return
	_hoe_on = false
	_hoe_dig = 0.0
	_hoe_dig_to = 0.0
	if pose:
		var ik0: Dictionary = pose.ik.duplicate()
		ik0.erase("RightHand")
		ik0.erase("LeftHand")
		pose.ik = ik0


func _hoe_step(delta: float) -> void:
	## Сапка в обох руках, як на відео: несе навскіс перед собою (держак — над правим плечем,
	## полотно — спереду внизу), а на грядці — замах угору, удар у землю й тягне сапку до себе.
	if held != hoe or hoe == null or not is_instance_valid(hoe) or pose == null:
		_hoe_stop()
		return
	_hoe_w = move_toward(_hoe_w, 1.0, delta * 3.0)
	_hoe_dig = move_toward(_hoe_dig, _hoe_dig_to, delta * 4.0)
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var l := Vector3(cos(rotation.y), 0, -sin(rotation.y))      # уліво
	var up := Vector3.UP
	var hp := hips_world()
	var sy := maxf(_held_scale.y, 0.01)
	# несе: права рука на держаку біля грудей, полотно — спереду ліворуч над землею
	var dc := (-l * 0.5 + up * 0.8 - f * 0.35).normalized()
	var rc := hp + f * 0.28 + up * 0.22 - l * 0.08
	var head_c := rc - dc * 0.95 * sy
	# сапає: полотно ходить над землею перед ногами, руки — низько (тулуб нахилений)
	var p := _hoe_ph
	var reach := 0.58
	var lift := 0.0
	if p < 0.5:                                   # замах
		var e := sin(p / 0.5 * PI * 0.5)
		reach = lerpf(0.58, 0.8, e)
		lift = 0.4 * e
	elif p < 0.65:                                # удар у землю
		var e := (p - 0.5) / 0.15
		reach = 0.8
		lift = 0.4 * (1.0 - e * e)
	else:                                         # тягне до себе
		var e := (p - 0.65) / 0.35
		reach = lerpf(0.8, 0.58, e * e * (3.0 - 2.0 * e))
	var head_d := global_position + f * reach + up * (0.04 + lift) + l * 0.04
	var rd := hp + f * (0.24 + (reach - 0.58) * 0.5) + up * (-0.08 + lift * 0.4) - l * 0.1
	var k := _hoe_dig * _hoe_dig * (3.0 - 2.0 * _hoe_dig)
	var head := head_c.lerp(head_d, k)
	var r := rc.lerp(rd, k)
	var d := r - head
	if d.length() < 0.05:
		d = dc
	d = d.normalized()
	if r.distance_to(head) > 1.2 * sy:
		r = head + d * 1.2 * sy
	var z := -up + d * d.dot(up)                  # полотно — донизу, до себе
	if z.length() < 0.01:
		z = f
	z = z.normalized()
	var x := d.cross(z).normalized()
	hoe.global_transform = Transform3D(Basis(x, d, z) * Basis.from_scale(_held_scale), head - d * 0.12 * sy)
	var ik: Dictionary = pose.ik.duplicate()
	ik["RightHand"] = [r, _hoe_w]
	ik["LeftHand"] = [r - d * 0.32 * sy, _hoe_w]
	pose.ik = ik


# ------------------------------------------------------------------ поїздки возом із дідусем: на ринок і в ліс
func trip_job(kind: String) -> void:
	## kind: "market" — на ринок, "forest" — у ліс. Дід запрягає коня й під'їжджає до воріт, бабуся бере
	## кошик і сідає на віз. На ринок: біля містка злазять і йдуть пішки; у лісі: дід — по гриби, бабуся —
	## по ягоди й трави. Потім — у зворотному порядку.
	var gp = main.grandpa
	var id := begin_job("trip")
	trip_done = false
	if gp == null or main.garden_cart == null:
		say("Ой, а воза ж немає…", 2.5)
		end_job(id)
		return
	_put_bale(main.garden_cart)
	if not await _ready_in_yard(id):
		return
	say("Поїду з дідом на ринок!" if kind == "market" else "Поїдемо з дідом у ліс по ягоди!", 2.5)
	# кошик — з ґанку
	await _goto(spots["porch"] + Vector3(0.5, 0, 0.6), 0.6)
	if id != job:
		return
	face(spots["porch"])
	busy = true
	play("bend")
	await wait(0.8)
	trip_basket = Util.basket()
	hold_upright(trip_basket, 0.3, false, 0.1)
	await wait(0.3)
	busy = false
	if id != job:
		return
	if not await _go_out(id):
		return
	bounds = TRIP_BOUNDS
	await _goto(GATE_WAIT, 0.6)
	if id != job:
		return
	face(GATE_WAIT + Vector3(-3.0, 0, 1.5))
	if gp.granny_ride != "board":
		say("Чекаю на діда з возом…", 2.5)
	if not await _wait_gp(id, ["board"]):
		await _trip_fail(id)
		return
	var cart: Node3D = main.garden_cart
	if not await _board(id, cart):
		return
	_home_way = MARKET_WALK if kind == "market" else FOREST_WAY
	if not await _wait_gp(id, ["there"]):
		await _trip_fail(id)
		return
	if not await _alight(id, cart, true):
		return
	var got := 0
	if kind == "market":
		got = await _shop(id)
	else:
		got = await _berries(id)
	if id != job:
		return
	trip_done = true
	# назад до воза
	if kind == "market":
		for wp in [Vector3(0.8, 0, 150.0), Vector3(0.6, 0, 110.0), Vector3(0.6, 0, 96.5)]:
			await _goto(wp)
			if id != job:
				return
	else:
		await _goto(FOREST_WAY[6])
		if id != job:
			return
	if gp.granny_ride == "" or gp.doing != "trip":
		await _trip_fail(id)
		return
	if not await _board(id, cart):
		return
	if not await _wait_gp(id, ["home"]):
		await _trip_fail(id)
		return
	_home_way = []
	if not await _alight(id, cart, false):
		return
	await _trip_end(id, got)


func _wait_gp(id: int, stages: Array) -> bool:
	## Чекає, поки поїздка діда дійде до одного з етапів (granny_ride у grandpa.gd). false — дід поїздку покинув.
	var gp = main.grandpa
	var t := 0.0
	while id == job and t < 300.0:
		var st: String = gp.granny_ride
		if st in stages:
			return true
		if st == "" or gp.doing != "trip":
			return false
		await wait(0.4)
		t += 0.4
	return false


func _cart_way(cart: Node3D, from_front: bool, to_rear: bool) -> Array:
	## Обхід воза праворуч: спереду (повз коня) — уздовж борту — ззаду.
	var pts: Array = [cart.to_global(Vector3(1.5, 0, cart.BEHIND + 1.2)), cart.to_global(Vector3(1.2, 0, 0.3)),
		cart.to_global(Vector3(1.1, 0, CART_REAR)), cart.to_global(Vector3(0, 0, CART_REAR))]
	if not from_front:
		pts = pts.slice(2)
	if not to_rear:
		pts.reverse()
	return pts


func _put_bale(cart: Node3D) -> void:
	## Дід підстелив на возі в'язку сіна — бабусі сидіти ззаду.
	_drop_bale()
	_bale = Node3D.new()
	_bale.name = "GrannyBale"
	cart.add_child(_bale)
	_bale.position = GR_BALE
	var hay := Util.mat(Color(0.9, 0.76, 0.36), 1.0)
	_bale.add_child(Util.sphere(0.3, hay, Vector3.ZERO, Vector3(1.25, 0.55, 0.9)))
	_bale.add_child(Util.sphere(0.2, Util.mat(Color(0.82, 0.68, 0.3), 1.0), Vector3(0.12, 0.08, 0.05), Vector3(1.2, 0.5, 1.0)))


func _drop_bale() -> void:
	if _bale and is_instance_valid(_bale):
		_bale.queue_free()
	_bale = null


func _board(id: int, cart: Node3D) -> bool:
	## Обходить віз, ставить кошик на віз і вилазить ззаду на в'язку сіна (обличчям уперед, за дідом).
	## Підходить до воза збоку біля заднього колеса, кладе кошик, хапається руками за борт,
	## ставить ногу на маточину колеса, підтягується й перелазить через борт, стає на дно воза,
	## повертається обличчям уперед і всідається в сіно.
	var ahead: bool = cart.to_local(global_position).z > 0.0
	var way: Array = [cart.to_global(Vector3(1.5, 0, cart.BEHIND + 1.2)), cart.to_global(Vector3(1.2, 0, 0.3))] if ahead \
		else [cart.to_global(Vector3(1.1, 0, CART_REAR))]
	way.append(cart.to_global(CLIMB_AT))
	for p in way:
		var q: Vector3 = p
		q.y = 0.0
		await go(q, false, false)
		if id != job:
			return false
	face(cart.to_global(Vector3(0, 0, CLIMB_AT.z)))
	await wait(0.5)
	if id != job:
		return false
	if held == trip_basket and trip_basket:
		busy = true
		play("pick")
		await wait(0.6)
		place_held(cart, GR_BASKET)
		await wait(0.2)
	if id != job:
		return false
	stop()
	busy = true
	_boarding = true
	_face_to = NAN
	current = ""
	play("idle")
	_hip_stand = maxf(0.5, hips_world().y - global_position.y)
	var hs := _hip_stand
	var s0 := {"h": cart.to_local(hips_world()), "yaw": wrapf(rotation.y - cart.rotation.y, -PI, PI), "lean": 0.0, "ik": {}}
	var cs := _climb_stages(hs)
	var s1: Dictionary = cs[0]
	var s2: Dictionary = cs[1]
	var s3: Dictionary = cs[2]
	var s4: Dictionary = cs[3]
	var s5: Dictionary = cs[4]
	for st in [[s0, s1, 0.8], [s1, s2, 0.7], [s2, s3, 1.1], [s3, s4, 1.0], [s4, s5, 0.9]]:
		if not await _climb_lerp(id, cart, st[0], st[1], float(st[2])):
			if pose:
				pose.ik = {}
				pose.lean = 0.0
			_boarding = false
			return false
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	await wait(0.3)
	if id != job:
		_boarding = false
		return false
	# 6) сідає в сіно
	var h0 := hips_world()
	var n: String = anims.get("sit", "")
	var t := 0.0
	var paused := false
	var sat := false
	while t < 1.0:
		await get_tree().process_frame
		if id != job:
			_boarding = false
			return false
		t = minf(1.0, t + get_process_delta_time() / 1.3)
		var e := t * t * (3.0 - 2.0 * t)
		rotation.y = cart.rotation.y
		place_hips(h0.lerp(cart.to_global(GR_SEAT), e))
		if t > 0.15 and not sat and ap and n != "":
			sat = true
			current = "sit"
			ap.speed_scale = 1.0
			ap.play(n, 0.5)
			ap.seek(0.0, true)
		if t > 0.7 and sat and not paused and current == "sit":
			paused = true
			ap.pause()                   # перший кадр «сидить» — і тримаємо
	_boarding = false
	on_tractor = cart
	say("Ох, як м'якенько на сінці! Рушай, діду!", 2.5)
	await wait(1.2)
	return id == job


func _climb_lerp(id: int, cart: Node3D, a: Dictionary, b: Dictionary, secs: float) -> bool:
	## Один крок вилазіння на віз: стегна, поворот, нахил і руки-ноги (IK) плавно з a в b (у системі воза).
	var t := 0.0
	while t < 1.0:
		await get_tree().process_frame
		if id != job or not is_instance_valid(cart):
			return false
		t = minf(1.0, t + get_process_delta_time() / secs)
		var e := t * t * (3.0 - 2.0 * t)
		rotation.y = cart.rotation.y + lerp_angle(float(a["yaw"]), float(b["yaw"]), e)
		if pose:
			pose.life = 0.0
			pose.lean = lerpf(float(a["lean"]), float(b["lean"]), e)
			var ik := {}
			var ia: Dictionary = a["ik"]
			var ib: Dictionary = b["ik"]
			for k in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				if not ia.has(k) and not ib.has(k):
					continue
				var pa: Array = ia.get(k, [])
				var pb: Array = ib.get(k, [])
				var p0: Vector3 = pa[0] if not pa.is_empty() else pb[0]
				var p1: Vector3 = pb[0] if not pb.is_empty() else pa[0]
				var w0 := float(pa[1]) if not pa.is_empty() else 0.0
				var w1 := float(pb[1]) if not pb.is_empty() else 0.0
				var p := p0.lerp(p1, e)
				if k.ends_with("Foot") and p0.distance_to(p1) > 0.2:
					p.y += sin(e * PI) * 0.15          # ногу піднімає дугою, а не волочить
				ik[k] = [cart.to_global(p), lerpf(w0, w1, e)]
			pose.ik = ik
		place_hips(cart.to_global((a["h"] as Vector3).lerp(b["h"], e)))
	return true


func _alight(id: int, cart: Node3D, ahead: bool) -> bool:
	## Злазить так само, як вилазила, тільки навпаки: встає з сіна, повертається до борту, хапається руками,
	## перекидає ногу через борт, ставить ногу на маточину колеса й спускається на землю біля заднього колеса.
	## Потім бере свій кошик із воза й обходить віз.
	on_tractor = null
	_boarding = true
	busy = true
	stop()
	_face_to = NAN
	current = ""
	if ap:
		ap.speed_scale = 1.0
	play("idle")
	var hs := _hip_stand
	var cs := _climb_stages(hs)
	var r0 := {"h": cart.to_local(hips_world()), "yaw": 0.0, "lean": 0.0, "ik": {}}
	var down := {"h": Vector3(CLIMB_AT.x, hs, CLIMB_AT.z), "yaw": -PI / 2.0, "lean": 0.0, "ik": {}}
	for st in [[r0, cs[4], 1.0], [cs[4], cs[3], 0.9], [cs[3], cs[2], 1.1], [cs[2], cs[1], 0.9], [cs[1], cs[0], 0.7], [cs[0], down, 0.6]]:
		if not await _climb_lerp(id, cart, st[0], st[1], float(st[2])):
			if pose:
				pose.ik = {}
				pose.lean = 0.0
			_boarding = false
			busy = false
			return false
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	var foot := cart.to_global(CLIMB_AT)
	foot.y = 0.0
	global_position = foot
	_boarding = false
	busy = false
	if trip_basket and is_instance_valid(trip_basket) and trip_basket.get_parent() == cart:
		face(cart.to_global(GR_BASKET))
		await wait(0.3)
		busy = true
		play("pick")
		await wait(0.6)
		hold_upright(trip_basket, 0.3, false, 0.1)
		await wait(0.2)
		busy = false
	if id != job:
		return false
	var away: Array = [cart.to_global(Vector3(1.2, 0, 0.3)), cart.to_global(Vector3(1.5, 0, cart.BEHIND + 1.2))] if ahead \
		else [cart.to_global(Vector3(1.1, 0, CART_REAR)), cart.to_global(Vector3(0, 0, CART_REAR))]
	for p in away:
		var q: Vector3 = p
		q.y = 0.0
		await go(q, false, false)
		if id != job:
			return false
	return id == job


func _climb_stages(hs: float) -> Array:
	## Пози вилазіння на віз (у системі воза), по черзі: 1) тримається за борт, 2) ліва нога на колесі,
	## 3) тіло над бортом, права нога на борті, 4) стоїть на дні воза, 5) стоїть обличчям уперед.
	## Злазить — ті самі пози у зворотному порядку.
	var side := -PI / 2.0                                  # обличчям до борту (до −x воза)
	var hands := {"LeftHand": [CLIMB_GRIP_L, 1.0], "RightHand": [CLIMB_GRIP_R, 1.0]}
	return [
		{"h": Vector3(CLIMB_AT.x - 0.06, hs - 0.02, CLIMB_AT.z), "yaw": side, "lean": 0.35, "ik": hands},
		{"h": Vector3(CLIMB_AT.x - 0.14, hs + 0.1, CLIMB_AT.z + 0.04), "yaw": side, "lean": 0.5,
			"ik": hands.merged({"LeftFoot": [CLIMB_STEP, 1.0]})},
		{"h": Vector3(0.74, 1.42, CLIMB_AT.z + 0.02), "yaw": side, "lean": 0.6,
			"ik": hands.merged({"LeftFoot": [CLIMB_STEP, 1.0], "RightFoot": [CLIMB_EDGE, 1.0]})},
		{"h": Vector3(0.28, CART_FLOOR + hs, -1.2), "yaw": side + 0.3, "lean": 0.2,
			"ik": {"LeftHand": [CLIMB_GRIP_L, 0.4], "RightHand": [CLIMB_GRIP_R, 0.4],
				"LeftFoot": [Vector3(0.2, CART_FLOOR + 0.08, -1.05), 1.0], "RightFoot": [Vector3(0.24, CART_FLOOR + 0.08, -1.38), 1.0]}},
		{"h": Vector3(0.12, CART_FLOOR + hs, -1.15), "yaw": 0.0, "lean": 0.0, "ik": {}},
	]


func _shop(id: int) -> int:
	## Від містка — на ринок: фрукти, хліб і пряники онукам.
	for wp in [Vector3(0.6, 0, 96.5), Vector3(0.6, 0, 110.0), Vector3(0.8, 0, 150.0)]:
		await _goto(wp)
		if id != job:
			return 0
	var bz = main.world.outer.bazaar
	var bought := 0
	if bz:
		for shop in ["fruit", "bread", "sweets"]:
			var sd: Dictionary = {}
			for s in bz.sellers:
				if String(s.get("shop", "")) == shop and s.has("front"):
					sd = s
					break
			if sd.is_empty():
				continue
			await go(sd["front"])
			if id != job:
				return bought
			face((sd["node"] as Node3D).global_position)
			say(SHOP_ASK[shop], 2.5)
			await wait(1.6)
			bz.seller_say(sd["node"], "Прошу, бабо Галю! На здоров'я!")
			bz.seller_give(sd)
			await wait(1.0)
			for i in 4:
				Util.basket_add(trip_basket, SHOP_COL[shop], 0.045)
			bought += 1
			say("Дякую, будьте здорові!", 1.8)
			await wait(1.4)
			if id != job:
				return bought
	say("Повний кошик гостинців — ходімо до воза!" if bought > 0 else "Щось ринок сьогодні порожній…", 2.5)
	return bought


func _berries(id: int) -> int:
	## У лісі: ягоди й трави на чай (гриби збирає дід).
	var fr = main.grandpa.forest
	await _goto(FOREST_WAY[6])
	if id != job:
		return 0
	var got := 0
	if fr and fr.has_method("nearest_kinds"):
		var end: Vector3 = FOREST_WAY[FOREST_WAY.size() - 1]
		for it in fr.nearest_kinds(end, 6, BERRIES):
			await go(fr.goods_pos(it) + Vector3(0.45, 0, 0.45))
			if id != job:
				return got
			face(fr.goods_pos(it))
			busy = true
			play("bend")
			await wait(0.9)
			busy = false
			if id != job:
				return got
			var n: int = fr.take(it)
			got += n
			if n > 0:
				Util.basket_add(trip_basket, fr.kind_color(it), 0.035)
	say("Назбирала ягідок і травички на чай!" if got > 0 else "Ягідки вже хтось позбирав…", 3.0)
	return got


func _trip_fail(id: int) -> void:
	## Дід кудись подівся — бабуся злазить (якщо сиділа на возі) й іде додому пішки.
	if id != job:
		return
	if on_tractor:
		if not await _alight(id, on_tractor, false):
			return
	say("Ой, дід кудись подівся… Піду пішки.", 2.5)
	await _trip_end(id, 0)


func _trip_end(id: int, got: int) -> void:
	## Додому: у двір, кошик із гостинцями — на ґанок.
	_drop_bale()
	if outside:
		if not await _come_in(id):
			return
	await _goto(spots["porch"] + Vector3(0.5, 0, 0.6), 0.6)
	if id != job:
		return
	face(spots["porch"])
	busy = true
	play("bend")
	await wait(0.7)
	if held == trip_basket and trip_basket:
		if _porch_basket and is_instance_valid(_porch_basket):
			_porch_basket.queue_free()
		_porch_basket = trip_basket
		place_held(main.world.yard_root, spots["porch"] + Vector3(0.35, 0, 0.05))
		trip_basket = null
	await wait(0.3)
	busy = false
	if got > 0:
		say("Ось і гостинці! Пригощайтеся, діточки.", 3.0)
		Game.add_coins(3)
	end_job(id)


# ------------------------------------------------------------------ у кімнату хати й назад (кімната стоїть окремо)
func _walk_in_room(id: int) -> bool:
	## Подвір'я → кімната: двері хати відчиняються, заходить, двері кімнати — і всередину.
	if in_room:
		return true
	var w = main.world
	await _goto(spots["door"] + Vector3(0.1, 0, 0.5), 1.0)
	if id != job:
		return false
	face(spots["door"] + Vector3(0, 0, -2))
	w.set_door("house", true, 0.4)
	await wait(0.5)
	if id != job:
		w.set_door("house", false, 0.4)
		return false
	await go(spots["door"] + Vector3(0.1, 0, -0.9), false, false)
	w.set_door("house", false, 0.4)
	var R: Vector3 = w.ROOM
	in_room = true
	bounds = Rect2(R.x - 3.2, R.z - 2.4, 6.4, 5.6)
	extra_obs = []
	position = spots["room_door"] + Vector3(0, 0, 0.9)
	rotation.y = PI
	w.set_door("room", true, 0.4)
	await wait(0.3)
	await go(spots["room_door"] + Vector3(0.3, 0, -0.5), false, false)
	w.set_door("room", false, 0.4)
	return id == job


func _walk_out_room(id: int) -> bool:
	## Кімната → подвір'я.
	if not in_room:
		return true
	var w = main.world
	await go(spots["room_door"] + Vector3(0, 0, -0.3), false, false)
	if id != job:
		return false
	face(spots["room_door"] + Vector3(0, 0, 2))
	w.set_door("room", true, 0.4)
	await wait(0.5)
	await go(spots["room_door"] + Vector3(0, 0, 0.9), false, false)
	w.set_door("room", false, 0.4)
	in_room = false
	bounds = YARD_BOUNDS
	position = spots["door"] + Vector3(0.1, 0, -0.9)
	rotation.y = 0.0
	w.set_door("house", true, 0.4)
	await wait(0.3)
	await go(spots["door"] + Vector3(0.1, 0, 0.9), false, false)
	w.set_door("house", false, 0.4)
	return id == job


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
	var hc = main.home_cow
	if hc != null and hc.mode == "free" and hc.visible:
		return hc                         # своя корова біля хати Тарасика
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
	if cow == main.home_cow:
		# корова біля хати Тарасика — одразу за дорогою від воріт
		await _goto(PASTURE_WAY[0])
		if id != job:
			return false
	else:
		bounds = PASTURE_BOUNDS
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
