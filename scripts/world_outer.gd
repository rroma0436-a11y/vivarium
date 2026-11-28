extends Node3D
## Відкритий світ за ворітьми: дорога, село з церквою, річка з містком, ставок з очеретом,
## пагорб, ліс. Дерева лісу малюються «пачками» (MultiMesh по шматках),
## далекі шматки ховаються — щоб на телефоні не гальмувало.

const VILLAGE := Vector3(0, 0, 60)
const RIVER_Z := 102.0
const RIVER_W := 8.0
const POND := Vector3(-70, 0, 31)
const POND_R := 14.0                           # пів ширини ставка (з півночі на південь)
const POND_HALF := Vector2(21.0, 14.0)         # ставок — прямокутник із заокругленими кутами: пів довжини (x), пів ширини (z)
const POND_CORNER := 6.0                       # радіус заокруглення кутів
const PIER_W := 1.8                            # ширина настилу причалу (м)
const PIER_DECK := 0.38                        # настил причалу над землею (вода — на 0.05)
const WHEAT := Rect2(26, 14, 44, 30)          # x, z, ширина, глибина
const WHEAT_N := Rect2(-48, -106, 36, 36)     # пшеничне поле на місці старого грибного лісу: x, z, ширина, глибина
const HAY_N := Vector3(-19.0, 0, -67.0)        # копиця сіна біля пшеничного поля (конюх возить звідси сіно на ферму)
const MILL_HILL := Vector3(-82, 0, -50)
const MILL_HILL_R := 30.0
const MILL_HILL_H := 4.0
const MILL_DIR := Vector2(0.4472136, 0.8944272)    # від вершини пагорба вздовж дороги (на ворота села)
const MILL_ROAD := [34.0, 2.6, 2.6]                 # піщана дорога: від (м від центру), до, ширина
const MILL_TREES := [                               # дерева грибного лісу збоку дороги: вид, (x, z), висота, кут Y°
	["pine_lo", Vector2(-62.77, -24.95), 10.0, 35.0],
	["birch_b_lo", Vector2(-57.41, -23.17), 8.5, 120.0],
	["birch_a_lo", Vector2(-73.51, -19.59), 7.5, 230.0],
	["pine_lo", Vector2(-65.90, -35.69), 9.0, 75.0],
	["birch_b_lo", Vector2(-81.56, -31.22), 8.0, 300.0],
]
const LIMIT := 440.0                                               # межа, куди можна зайти (до грибного лісу)
const ZONE_LIMIT := 245.0                                          # стара межа — інші зони стоять як були
const HANGAR := Vector3(-220, 0, 68)                               # ангар літака: задом до річки (задня стіна за 25 м від берега), ворота на північ
const AIR_ROT := -PI / 2.0                                         # поворот аеродрому (у своїй системі ворота дивляться на −X)
const AIR_X := Vector3(0, 0, 1)                                    # своя вісь X аеродрому у світі (від воріт до задньої стіни)
const AIR_Z := Vector3(-1, 0, 0)                                   # своя вісь Z аеродрому у світі
const RUNWAY_A := HANGAR - AIR_X * 11.0                            # початок злітної смуги
const RUNWAY_B := HANGAR - AIR_X * 79.0                            # кінець смуги
const AIR_ROAD := [Vector2(0, 95), Vector2(-200, 95), Vector2(-207, 80), Vector2(-207, 61), Vector2(-214, 61)]   # піщана дорога від головної дороги до ангара
const AIR_ROAD_W := 3.0
const DRAGON_HOME := HANGAR

var world
var _water_mats: Array = []
var _obst: Array = []                          # [x, z, r, h]
var places := []                               # [назва, центр, радіус] — для назви місця й мапи
var houses: Array = []                         # для мапи: [x, z]
var trees: Array = []                          # для мапи: [x, z]
var _t := 0.0


func build(w) -> void:
	world = w
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_make_village(rng)
	_make_extra_buildings()
	_make_bazaar()
	# стару церкву в селі прибрано (дерев'яна церква тепер на базарі)
	_make_river()
	# комбайн тепер їздить (main.gd → combine.gd, на ньому катається Ніка)
	_make_pond(rng)
	_make_fish()
	_make_wheat(rng)
	_make_wheat_field()
	_make_field_road()
	_make_east_road()
	_make_mill()
	_make_grain_bunker()
	_make_mill_bin()
	_make_forest(rng)
	_make_meadow(rng)
	_make_airfield()
	_make_sky_birds()
	apply_view_ranges(self)
	places = [
		["Подвір'я", Vector3(-6, 0, -5), 16.0],
		["Город", Vector3(14.5, 0, -4.5), 6.0],
		["Село", VILLAGE, 30.0],
		["Річка", Vector3(0, 0, RIVER_Z), 0.0],
		["Ставок", POND, 24.0],
		["Аеродром", Vector3((HANGAR.x + RUNWAY_B.x) / 2.0, 0, HANGAR.z), 0.0],
		["Грибний ліс", FOREST_C, FOREST_R + 2.0],
		["Пшеничне поле", Vector3(WHEAT_N.get_center().x, 0, WHEAT_N.get_center().y), 20.0],
		["Садок", Vector3(11.2, 0, 14.2), 7.0],
		["Поле", Vector3(PLOW_FIELD.get_center().x, 0, PLOW_FIELD.get_center().y), 12.0],
		["Грибний ліс", EAST_FOREST_C, 0.0],
		["Базар", Vector3(0, 0, 182), 22.0],
	]


func register_obstacles() -> void:
	for o in _obst:
		Obstacles.add_outer(o[0], o[1], o[2], o[3])


func place_name(p: Vector3) -> String:
	## Як називається місце, де зараз Beep.
	if p.x > -21.5 and p.x < 9.5 and p.z > -15.5 and p.z < 5.5:
		return "Подвір'я"
	if absf(p.z - RIVER_Z) < RIVER_W:
		return "Річка"
	var bb = bazaar.building_at(p) if bazaar else null
	if bb:
		return {"house": "Хата", "church": "Церква", "stall": "Ларьок"}.get(bb["kind"], "Базар")
	if BAZAAR_AREA.has_point(Vector2(p.x, p.z)):
		return "Базар" if absf(p.x) < 9.0 and p.z > 160.0 and p.z < 200.0 else "Вулиця біля базару"
	if in_east_forest(Vector2(p.x, p.z)):
		return "Грибний ліс"
	if p.x > 70.0 or p.z > 115.0 or (p.x > 25.0 and p.z < 10.0):
		return "Ліс"
	var al := air_local(p)
	if al.x < 6.0 and al.x > -85.0 and absf(al.y) < 9.0:
		return "Аеродром"
	if p.z < -318.0:
		return "Грибний ліс"
	var best := "Луки"
	var bd := INF
	for pl in places:
		var r: float = pl[2]
		if r <= 0.0:
			continue
		var d := Vector2(p.x - pl[1].x, p.z - pl[1].z).length()
		if d < r and d < bd:
			bd = d
			best = pl[0]
	return best


func _process(delta: float) -> void:
	if combine_reel:
		combine_reel.rotate_object_local(Vector3.RIGHT, delta * 0.9)
	_t += delta
	_boat_step(delta)
	_sky_birds_step(delta)
	_sedge_step(delta)


# ------------------------------------------------------------------ село
const MARKET_POS := Vector3(-14, 0, 59)      # фентезі-ринок (захід площі)
const MANSION_POS := Vector3(16.5, 0, 57)     # кам'яний особняк (схід)
const TEA_POS := Vector3(9.5, 0, 70.5)        # чайна «Tea Kadai» (південний схід)


func _make_village(rng: RandomNumberGenerator) -> void:
	# по 3 хати з кожного боку дороги (x = 0), перша — за 50 м від подвір'я (z 5.5), крок HUT_STEP; фасадом до дороги
	var spots := [
		["hata", 4.4, Vector3(-HUT_X, 0, HUT_Z0), 90.0],
		["kid_house", 4.4, Vector3(HUT_X, 0, HUT_Z0), -90.0],
		["hata", 4.4, Vector3(HUT_X, 0, HUT_Z0 + HUT_STEP), -90.0],
		["kid_house", 4.4, Vector3(-HUT_X, 0, HUT_Z0 + HUT_STEP), 90.0],
		["hata", 4.4, Vector3(-HUT_X, 0, HUT_Z0 + HUT_STEP * 2.0), 90.0],
		["kid_house", 4.4, Vector3(HUT_X, 0, HUT_Z0 + HUT_STEP * 2.0), -90.0],
	]
	for sp in spots:
		# хати села — копії базарних хат (з Blender): двері відчиняються, всередині піч, стіл, лава, ліжко
		var di := spots.find(sp)
		village_huts.append([sp[2], deg_to_rad(sp[3]), di % 2 == 1])
		var hp: Vector3 = sp[2]
		_obst.append([hp.x, hp.z, 3.0, 4.0])
		# тин довкола садиби, хвіртка спереду посередині
		var bs := Basis(Vector3.UP, deg_to_rad(sp[3]))
		var hx := 6.0
		var zf := 7.2
		var zb := -6.4
		var pts := [[Vector3(-1.1, 0, zf), Vector3(-hx, 0, zf)], [Vector3(-hx, 0, zf), Vector3(-hx, 0, zb)],
			[Vector3(-hx, 0, zb), Vector3(hx, 0, zb)], [Vector3(hx, 0, zb), Vector3(hx, 0, zf)],
			[Vector3(hx, 0, zf), Vector3(1.1, 0, zf)]]
		if not ResourceLoader.exists("res://assets/models/bazaar/bz_village.glb"):
			for seg in pts:
				_low_fence(hp + bs * (seg[0] as Vector3), hp + bs * (seg[1] as Vector3))
	if not ResourceLoader.exists("res://assets/models/bazaar/bz_village.glb"):
		_make_yard_roads()
	_make_farm_buildings()
	_make_farm_fence()
	_make_farm_paths()
	# площа: посередині фонтан (старий ринок, особняк, чайну й ларки прибрано — тепер великий базар за річкою)
	_make_fountain(VILLAGE)
	for b in []:
		var m := Models.spawn(self, b[0], b[1])
		if m == null:
			continue
		m.position = b[2]
		var to: Vector3 = VILLAGE - (b[2] as Vector3)
		m.rotation.y = atan2(to.x, to.z) + float(SQUARE_FRONT.get(b[0], 0.0))
		_obst.append([m.position.x, m.position.z, b[3], 3.0])
		houses.append([m.position.x, m.position.z])
	# криниця трохи осторонь, лавки довкола фонтану — сидінням до фонтану
	var wl := Models.spawn(self, "well", 2.3)
	if wl:
		wl.position = VILLAGE + Vector3(-8, 0, -13)
		wl.rotation.y = 0.5
		_obst.append([wl.position.x, wl.position.z, 1.0, 2.3])
	for k in 4:
		var b2 := Models.spawn(self, "bench", 0.9)
		if b2:
			var a := PI / 4.0 + k * PI / 2.0
			b2.position = VILLAGE + Vector3(cos(a) * 5.6, 0, sin(a) * 5.6)
			var to2: Vector3 = VILLAGE - b2.position
			b2.rotation.y = atan2(to2.x, to2.z) + BENCH_FRONT
			_sit_zone(b2)
	for k in 10:
		var sf := Models.spawn(self, "sunflower", rng.randf_range(1.6, 2.0))
		if sf:
			var hp2: Array = spots[k % spots.size()]
			sf.position = (hp2[2] as Vector3) + Basis(Vector3.UP, deg_to_rad(hp2[3])) * Vector3(rng.randf_range(1.6, 5.0) * (1.0 if k % 2 == 0 else -1.0), 0, 6.7)
			sf.rotation.y = rng.randf() * TAU


const HUT_X := 16.0          # хати старого села: відступ від осі дороги (x = 0)
const HUT_Z0 := 55.5         # перша пара хат: 50 м від подвір'я (край подвір'я z = 5.5)
const HUT_STEP := 15.0       # крок між хатами вздовж дороги
const YARD_ROAD_W := 2.6     # ширина під'їзду до подвір'я
const YARD_GATE := 7.2       # хвіртка — спереду садиби, 7.2 м від хати


func _yard_road_segs() -> Array:
	## Під'їзди: від осі дороги до хвіртки кожної садиби старого села.
	var segs := []
	for i in 3:
		for sx in [-1.0, 1.0]:
			var z := HUT_Z0 + HUT_STEP * i
			segs.append([Vector2(0, z), Vector2(sx * (HUT_X - YARD_GATE), z)])
	return segs


func _make_yard_roads() -> void:
	## Піщані під'їзні дороги від головної дороги до хвірток садиб.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := YARD_ROAD_W / 2.0
	for sg in _yard_road_segs():
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var sd := (b - a).normalized()
		var side := Vector2(sd.y, -sd.x) * hw
		var b2 := b + sd * 0.3                  # трохи під хвіртку, щоб не було щілини
		for v in [a + side, b2 + side, a - side, a - side, b2 + side, b2 - side]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, 0.02, v.y))
	var sand := Util.road_mat()
	var road := MeshInstance3D.new()
	road.name = "yard_roads"
	road.mesh = st.commit()
	road.material_override = sand
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)


func _sit_zone(n: Node3D) -> void:
	## Лавка, на яку Ніка сідає (торкнись — підійде й сяде), як на меблі в хаті.
	var best: MeshInstance3D = null
	var bv := -1.0
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var v := mi.get_aabb().get_volume()
		if v > bv:
			bv = v
			best = mi
	if best == null:
		return
	var ab := best.get_aabb()
	var a := Util.pick_area("bz_furn", ab.size + Vector3(0.12, 0.12, 0.12), ab.get_center())
	a.set_meta("act", "sit")
	a.set_meta("box", ab)
	best.add_child(a)


# у який бік «дивиться» модель (поправка до повороту, щоб фасад був до фонтану)
const SQUARE_FRONT := {"market": 0.0, "mansion": 0.0, "tea_stall": 0.0}
const BENCH_FRONT := -PI / 2.0


# ферма за ставком: 100 м на захід від західного берега (x = −91), фасадами (дверима) на схід, до ставка
const COWSHED_POS := [Vector3(-162.0, 0, 39.0), Vector3(-162.0, 0, 55.0), Vector3(-162.0, 0, 71.0)]   # перед стайнями, 20 м від них
const STABLE_POS := [Vector3(-191.0, 0, 39.0), Vector3(-191.0, 0, 55.0), Vector3(-191.0, 0, 71.0)]
const FARM_AREA := Rect2(-200.0, -18.0, 50.0, 98.0)     # будівлі, пасовисько й левада — тут випадкового лісу немає


func _make_farm_buildings() -> void:
	## Три корівники й три стайні — за ставком, дверима на схід.
	var list := []
	for i in COWSHED_POS.size():
		list.append(["cowshed", 5.0, COWSHED_POS[i], PI, "cowshed" + ("" if i == 0 else str(i + 1))])
	for i in STABLE_POS.size():
		list.append(["stable", 5.0, STABLE_POS[i], 0.0, "stable" + ("" if i == 0 else str(i + 1))])
	for b in list:
		var m := Models.spawn(self, b[0], b[1])
		if m == null:
			continue
		m.name = String(b[4])
		m.position = b[2]
		m.rotation.y = b[3]
		_obst.append([m.position.x, m.position.z, 4.6, 3.0])
		houses.append([m.position.x, m.position.z])
		var pa := Util.pick_area("barn", Vector3(8.0, 5.0, 7.0), Vector3(0, 2.5, 0))
		pa.set_meta("no_solid", true)             # Ніка й працівники заходять усередину крізь двері
		m.add_child(pa)
		# двері (у моделі вони дивляться вздовж +X) — вирізаємо й ставимо на петлю
		var mis := m.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			var box := AABB(Vector3(0.165, -0.252, -0.03), Vector3(0.07, 0.18, 0.205)) if b[0] == "stable" else AABB(Vector3(0.38, -0.362, -0.118), Vector3(0.08, 0.235, 0.236))
			world.make_house_door(m, box, String(b[4]) + "_door", 3.0, mis[0], true, false)
			_walk_in_shed(m, String(b[0]), String(b[4]) + "_door")


const FARM_FENCE := Rect2(-199.0, 28.0, 71.0, 55.0)    # забір із жердин довкола ферми: x, z, ширина, глибина
const FARM_GATE_X := -171.5                             # ворота — у північному боці забору (z = 28)
const FARM_GATE_W := 5.0
const FARM_GATE_S_X := -171.5                           # другі ворота — у південному боці (z = 83), заїзд з дороги біля річки


func _make_farm_fence() -> void:
	## Простий забір із жердин (стовпчики + три жердини) довкола ферми; ворота з двох стулок відчиняються всередину.
	var post_m := Util.mat(Color(0.42, 0.3, 0.19), 0.95)
	var rail_m := Util.mat(Color(0.6, 0.46, 0.3), 0.95)
	var f := FARM_FENCE
	var x0 := f.position.x
	var x1 := f.end.x
	var z0 := f.position.y
	var z1 := f.end.y
	var g0 := FARM_GATE_X - FARM_GATE_W / 2.0
	var g1 := FARM_GATE_X + FARM_GATE_W / 2.0
	var s0 := FARM_GATE_S_X - FARM_GATE_W / 2.0
	var s1 := FARM_GATE_S_X + FARM_GATE_W / 2.0
	var segs := [
		[Vector2(x0, z0), Vector2(g0, z0)], [Vector2(g1, z0), Vector2(x1, z0)],
		[Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(s1, z1)], [Vector2(s0, z1), Vector2(x0, z1)],
		[Vector2(x0, z1), Vector2(x0, z0)],
	]
	var posts: Array = []
	var rails: Array = []                       # [центр, кут, довжина]
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 2.5)))
		for i in n + 1:
			posts.append(a.lerp(b, float(i) / n))
		for i in n:
			var p := a.lerp(b, float(i) / n)
			var q := a.lerp(b, float(i + 1) / n)
			rails.append([(p + q) / 2.0, atan2(q.x - p.x, q.y - p.y), p.distance_to(q) + 0.1])
		var m := maxi(1, int(ceil(a.distance_to(b) / 0.6)))
		for i in m + 1:
			var o := a.lerp(b, float(i) / m)
			_obst.append([o.x, o.y, 0.5, 1.3])
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.08
	pm.height = 1.4
	pm.radial_segments = 6
	pm.rings = 1
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = pm
	pmm.instance_count = posts.size()
	for i in posts.size():
		var p: Vector2 = posts[i]
		pmm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.7, p.y)))
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "farm_fence_posts"
	pmi.multimesh = pmm
	pmi.material_override = post_m
	add_child(pmi)
	var rm := CylinderMesh.new()
	rm.top_radius = 0.045
	rm.bottom_radius = 0.045
	rm.height = 1.0
	rm.radial_segments = 6
	rm.rings = 1
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.mesh = rm
	rmm.instance_count = rails.size() * 3
	var k := 0
	for r in rails:
		var c: Vector2 = r[0]
		var bs := Basis(Vector3.UP, float(r[1])) * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1, float(r[2]), 1))
		for h in [0.45, 0.8, 1.15]:
			rmm.set_instance_transform(k, Transform3D(bs, Vector3(c.x, h, c.y)))
			k += 1
	var rmi := MultiMeshInstance3D.new()
	rmi.name = "farm_fence_rails"
	rmi.multimesh = rmm
	rmi.material_override = rail_m
	add_child(rmi)
	_farm_gate("farm_gate", FARM_GATE_X, z0, 1.0)          # північні — відчиняються всередину (на південь)
	_farm_gate("farm_gate_s", FARM_GATE_S_X, z1, -1.0)     # південні (від річки) — всередину (на північ)


func _farm_gate(gname: String, gx: float, gz: float, inward: float) -> void:
	## Дерев'яні ворота з двох дощаних стулок між товстими стовпами з дашком; відчиняються всередину ферми.
	var post_m := Util.mat(Color(0.36, 0.25, 0.15), 0.95)
	var plank_m := Util.mat(Color(0.58, 0.42, 0.26), 0.9)
	var frame_m := Util.mat(Color(0.45, 0.31, 0.18), 0.9)
	var roof_m := Util.mat(Color(0.32, 0.22, 0.14), 0.95)
	var w := FARM_GATE_W
	var g0 := gx - w / 2.0
	var g1 := gx + w / 2.0
	# стовпи й дашок над воротами
	for x in [g0 - 0.14, g1 + 0.14]:
		add_child(Util.box(Vector3(0.26, 3.4, 0.26), post_m, Vector3(x, 1.7, gz)))
		_obst.append([x, gz, 0.3, 3.4])
	add_child(Util.box(Vector3(w + 0.9, 0.22, 0.3), post_m, Vector3(gx, 3.3, gz)))
	for sz in [-1.0, 1.0]:
		add_child(Util.box(Vector3(w + 1.3, 0.05, 0.62), roof_m, Vector3(gx, 3.55, gz + sz * 0.26), Vector3(sz * 0.45, 0, 0)))
	# стулки
	var half := w / 2.0 - 0.04
	for sx in [-1.0, 1.0]:
		var hg := Node3D.new()
		hg.name = gname + ("_l" if sx < 0.0 else "_r")
		hg.position = Vector3(g0 if sx < 0.0 else g1, 0, gz)
		add_child(hg)
		var dirx: float = -sx                   # стулка тягнеться від петлі до середини воріт
		# дошки
		var n := int(floor(half / 0.2))
		var bw := half / n
		for i in n:
			hg.add_child(Util.box(Vector3(bw - 0.025, 1.55, 0.05), plank_m, Vector3(dirx * (bw * (i + 0.5)), 0.95, 0)))
		# рама: верх, низ, середина й укіс
		for h in [0.3, 0.95, 1.62]:
			hg.add_child(Util.box(Vector3(half, 0.12, 0.07), frame_m, Vector3(dirx * half / 2.0, h, -0.05)))
			hg.add_child(Util.box(Vector3(half, 0.12, 0.07), frame_m, Vector3(dirx * half / 2.0, h, 0.05)))
		hg.add_child(Util.box(Vector3(0.12, 1.6, 0.08), frame_m, Vector3(dirx * 0.06, 0.95, 0)))
		hg.add_child(Util.box(Vector3(0.12, 1.6, 0.08), frame_m, Vector3(dirx * (half - 0.06), 0.95, 0)))
		var dl := sqrt(half * half + 1.32 * 1.32)
		hg.add_child(Util.box(Vector3(dl, 0.1, 0.06), frame_m, Vector3(dirx * half / 2.0, 0.95, -0.09), Vector3(0, 0, dirx * atan2(1.32, half))))
		world.doors[String(hg.name)] = [hg, 0.0, sx * inward]
	world.add_auto_door(gname, [gname + "_l", gname + "_r"], Vector3(gx, 0, gz), 5.0)


func _farm_path_pts(pts: Array) -> Array:
	## Ламана → плавна крива (згладжування Чайкіна, кінці лишаються на місці).
	var p := pts
	for _it in 4:
		var q := [p[0]]
		for i in p.size() - 1:
			var a: Vector2 = p[i]
			var b: Vector2 = p[i + 1]
			q.append(a.lerp(b, 0.25))
			q.append(a.lerp(b, 0.75))
		q.append(p[p.size() - 1])
		p = q
	return p


func _make_farm_paths() -> void:
	## Коричневі заокруглені доріжки від воріт до дверей кожного корівника й стайні.
	var gx := FARM_GATE_X
	var gz := FARM_FENCE.position.y
	var routes := []
	for c in COWSHED_POS:
		var z: float = c.z
		var mid: float = (COWSHED_POS[0].x + STABLE_POS[0].x) / 2.0
		routes.append([Vector2(gx, gz - 2.0), Vector2(gx, gz + 3.5), Vector2(mid, gz + 5.0), Vector2(mid, z - 2.5), Vector2(mid + 2.5, z), Vector2(c.x - 4.5, z)])
	for s in STABLE_POS:
		var z: float = s.z + 0.7
		routes.append([Vector2(gx, gz - 2.0), Vector2(gx, gz + 3.5), Vector2(-183.0, gz + 5.0), Vector2(-183.0, z - 2.5), Vector2(s.x + 3.7, z)])
	routes.append([Vector2(gx, gz - 2.0), Vector2(gx, FARM_FENCE.end.y + 2.0)])     # проїзд до південних воріт
	const W := 0.75                              # пів ширини доріжки
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ri := 0
	for r in routes:
		var pts := _farm_path_pts(r)
		var y := 0.035 + ri * 0.002
		ri += 1
		var sides := []
		for i in pts.size():
			var a: Vector2 = pts[maxi(i - 1, 0)]
			var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
			var d := (b - a).normalized()
			sides.append(Vector2(-d.y, d.x) * W)
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var s0: Vector2 = sides[i]
			var s1: Vector2 = sides[i + 1]
			for v in [p0 + s0, p1 + s1, p0 - s0, p0 - s0, p1 + s1, p1 - s1]:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(v.x, y, v.y))
		# заокруглені кінці
		for e in [pts[0], pts[pts.size() - 1]]:
			var c: Vector2 = e
			for k in 16:
				var a0 := TAU * k / 16.0
				var a1 := TAU * (k + 1) / 16.0
				for v in [c, c + Vector2(cos(a1), sin(a1)) * W, c + Vector2(cos(a0), sin(a0)) * W]:
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(v.x, y, v.y))
	var mi := MeshInstance3D.new()
	mi.name = "farm_paths"
	mi.mesh = st.commit()
	mi.material_override = Util.road_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# заїзд з піщаної дороги біля річки до південних воріт
	var da: Vector2 = FARM_DRIVE[0]
	var db: Vector2 = FARM_DRIVE[1]
	var dside := Vector2((db - da).normalized().y, -(db - da).normalized().x) * (AIR_ROAD_W / 2.0)
	var ds := SurfaceTool.new()
	ds.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [da + dside, db + dside, da - dside, da - dside, db + dside, db - dside]:
		ds.set_normal(Vector3.UP)
		ds.add_vertex(Vector3(v.x, 0.03, v.y))
	var dmi := MeshInstance3D.new()
	dmi.name = "farm_drive"
	dmi.mesh = ds.commit()
	dmi.material_override = Util.road_mat()
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dmi)


var walk_in: Array = []              # стайня й корівник: Ніка заходить усередину ([вузол, коробка в його системі])


func _walk_in_shed(m: Node3D, kind: String, door_name := "") -> void:
	## Стайню й корівник можна відвідати: стіни зсередини теж видно, двері — прохід, усередині солома й сіно.
	var inv := m.global_transform.affine_inverse()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := inv * mi.global_transform
		for i in 8:
			var q := t * mi.get_aabb().get_endpoint(i)
			lo = lo.min(q)
			hi = hi.max(q)
		for si in mi.mesh.get_surface_count():
			var mt := mi.get_active_material(si)
			if mt is BaseMaterial3D:
				var d := (mt as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(si, d)
	if lo == Vector3.INF:
		return
	# двері (вирізані й на петлі) — де в стіні прохід
	var dz0 := lo.z + (hi.z - lo.z) * 0.4
	var dz1 := lo.z + (hi.z - lo.z) * 0.6
	var dd = world.doors.get(door_name if door_name != "" else kind + "_door")
	if dd != null:
		var dlo := Vector3.INF
		var dhi := -Vector3.INF
		for n in (dd[0] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var dm := n as MeshInstance3D
			var t2 := inv * dm.global_transform
			for i in 8:
				var q2 := t2 * dm.get_aabb().get_endpoint(i)
				dlo = dlo.min(q2)
				dhi = dhi.max(q2)
		if dlo != Vector3.INF:
			dz0 = dlo.z
			dz1 = dhi.z
	var sc := m.global_transform.basis.get_scale().x
	var th := 0.18 / maxf(sc, 0.001)
	var g := m.global_transform
	var sb := StaticBody3D.new()
	sb.collision_layer = 1 << 17
	sb.collision_mask = 0
	add_child(sb)
	var add_wall := func(c: Vector3, sz: Vector3) -> void:
		if sz.x <= 0.01 or sz.z <= 0.01:
			return
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sz * sc
		cs.shape = bx
		sb.add_child(cs)
		cs.global_transform = Transform3D(g.basis.orthonormalized(), g * c)
	var H := hi.y - lo.y
	var cy := lo.y + H / 2.0
	var x0 := lo.x + (hi.x - lo.x) * 0.04
	var x1 := hi.x - (hi.x - lo.x) * 0.04
	var z0 := lo.z + (hi.z - lo.z) * 0.04
	var z1 := hi.z - (hi.z - lo.z) * 0.04
	add_wall.call(Vector3(x0, cy, (z0 + z1) / 2.0), Vector3(th, H, z1 - z0))
	add_wall.call(Vector3((x0 + x1) / 2.0, cy, z0), Vector3(x1 - x0, H, th))
	add_wall.call(Vector3((x0 + x1) / 2.0, cy, z1), Vector3(x1 - x0, H, th))
	add_wall.call(Vector3(x1, cy, (z0 + dz0) / 2.0), Vector3(th, H, dz0 - z0))           # фасад — з проходом у дверях
	add_wall.call(Vector3(x1, cy, (dz1 + z1) / 2.0), Vector3(th, H, z1 - dz1))
	# усередині: солома на підлозі, сіно; у корівнику — ясла, у стайні — драбинка для сіна
	var straw := Util.box(Vector3((x1 - x0) * 0.92, 0.02 / sc, (z1 - z0) * 0.92), Util.mat(Color(0.8, 0.67, 0.38), 1.0), Vector3((x0 + x1) / 2.0, lo.y + 0.03 / sc, (z0 + z1) / 2.0))
	m.add_child(straw)
	var hay := Util.mat(Color(0.88, 0.74, 0.35), 1.0)
	m.add_child(Util.sphere(0.9 / sc, hay, Vector3(x0 + 1.1 / sc, lo.y + 0.3 / sc, z0 + 1.0 / sc), Vector3(1.2, 0.7, 1.0)))
	var wood := Util.mat(Color(0.5, 0.34, 0.2), 0.9)
	m.add_child(Util.box(Vector3(0.5, 0.5, 2.4) / sc, wood, Vector3(x0 + 0.4 / sc, lo.y + 0.25 / sc, (z0 + z1) / 2.0 + (0.6 if kind == "cowshed" else -0.6) / sc)))
	walk_in.append([m, AABB(Vector3(x0, lo.y, z0), Vector3(x1 - x0, H * 0.75, z1 - z0))])


func _make_fountain(p: Vector3) -> void:
	## Фонтан: порожниста чаша з мозаїчним дном і прозорою водою, колона з верхньою чашею, струмені.
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var cream := Util.mat(Color(0.93, 0.87, 0.74), 0.7)
	var sand := Util.mat(Color(0.86, 0.74, 0.56), 0.8)
	var plinth := Util.mat(Color(0.55, 0.47, 0.4), 0.9)
	var turq := Util.mat(Color(0.2, 0.58, 0.66), 0.25)
	var cobalt := Util.mat(Color(0.12, 0.28, 0.62), 0.35)
	var gold := Util.mat(Color(0.95, 0.75, 0.3), 0.3, 0.8)
	# нижня чаша — зовнішня стінка з кахлями, бортик, внутрішня стінка (заглибина)
	n.add_child(_lathe(PackedVector2Array([Vector2(3.05, 0.0), Vector2(3.05, 0.12), Vector2(2.82, 0.16)]), plinth))
	n.add_child(_lathe(PackedVector2Array([Vector2(2.82, 0.16), Vector2(2.82, 0.66)]), _tile_mat(44.0)))
	n.add_child(_lathe(PackedVector2Array([Vector2(2.82, 0.66), Vector2(2.98, 0.7), Vector2(2.98, 0.8),
		Vector2(2.9, 0.86), Vector2(2.52, 0.86), Vector2(2.47, 0.8)]), cream))
	n.add_child(_lathe(PackedVector2Array([Vector2(2.47, 0.8), Vector2(2.43, 0.14)]), turq))
	var floor_m := ShaderMaterial.new()
	floor_m.shader = Shader.new()
	floor_m.shader.code = _MOSAIC_SH
	n.add_child(Util.cyl(2.44, 2.44, 0.02, floor_m, Vector3(0, 0.14, 0)))
	n.add_child(_fountain_water(2.47, 1.12, Vector3(0, 0.62, 0)))
	# колона
	n.add_child(Util.cyl(0.55, 0.65, 0.25, cream, Vector3(0, 0.27, 0)))
	n.add_child(Util.cyl(0.3, 0.4, 1.75, sand, Vector3(0, 1.27, 0)))
	n.add_child(Util.cyl(0.37, 0.37, 0.08, cobalt, Vector3(0, 0.95, 0)))
	n.add_child(Util.cyl(0.33, 0.33, 0.06, gold, Vector3(0, 1.95, 0)))
	# верхня чаша
	n.add_child(_lathe(PackedVector2Array([Vector2(0.34, 2.12), Vector2(0.8, 2.3), Vector2(1.1, 2.46)]), _tile_mat(18.0)))
	n.add_child(_lathe(PackedVector2Array([Vector2(1.1, 2.46), Vector2(1.14, 2.56), Vector2(1.06, 2.6), Vector2(0.98, 2.54)]), cream))
	n.add_child(_lathe(PackedVector2Array([Vector2(0.98, 2.54), Vector2(0.85, 2.42), Vector2(0.0, 2.4)]), turq))
	n.add_child(_fountain_water(0.95, 0.35, Vector3(0, 2.5, 0)))
	n.add_child(Util.cyl(0.1, 0.14, 0.6, cream, Vector3(0, 2.75, 0)))
	n.add_child(Util.cyl(0.2, 0.1, 0.1, gold, Vector3(0, 3.05, 0)))
	n.add_child(Util.sphere(0.14, gold, Vector3(0, 3.18, 0)))
	var drop := StandardMaterial3D.new()
	drop.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
	drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dm := SphereMesh.new()
	dm.radius = 0.05
	dm.height = 0.1
	dm.radial_segments = 6
	dm.rings = 3
	# струмінь угору з верхівки
	var jet := CPUParticles3D.new()
	jet.mesh = dm
	jet.material_override = drop
	jet.amount = 70
	jet.lifetime = 1.1
	jet.direction = Vector3.UP
	jet.spread = 14.0
	jet.initial_velocity_min = 2.6
	jet.initial_velocity_max = 3.0
	jet.gravity = Vector3(0, -6.5, 0)
	jet.scale_amount_min = 0.6
	jet.scale_amount_max = 1.0
	jet.position = Vector3(0, 3.28, 0)
	n.add_child(jet)
	# вода переливається з верхньої чаші вниз
	var fall := CPUParticles3D.new()
	fall.mesh = dm
	fall.material_override = drop
	fall.amount = 90
	fall.lifetime = 0.8
	fall.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	fall.emission_ring_axis = Vector3.UP
	fall.emission_ring_radius = 1.14
	fall.emission_ring_inner_radius = 1.08
	fall.emission_ring_height = 0.01
	fall.direction = Vector3.DOWN
	fall.spread = 6.0
	fall.initial_velocity_min = 0.3
	fall.initial_velocity_max = 0.5
	fall.gravity = Vector3(0, -6.0, 0)
	fall.scale_amount_min = 0.5
	fall.scale_amount_max = 0.8
	fall.position = Vector3(0, 2.52, 0)
	n.add_child(fall)
	# бризки там, де вода падає в нижню чашу
	var splash := CPUParticles3D.new()
	splash.mesh = dm
	splash.material_override = drop
	splash.amount = 60
	splash.lifetime = 0.35
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	splash.emission_ring_axis = Vector3.UP
	splash.emission_ring_radius = 1.16
	splash.emission_ring_inner_radius = 1.06
	splash.emission_ring_height = 0.01
	splash.direction = Vector3.UP
	splash.spread = 35.0
	splash.initial_velocity_min = 0.6
	splash.initial_velocity_max = 1.1
	splash.gravity = Vector3(0, -6.0, 0)
	splash.scale_amount_min = 0.4
	splash.scale_amount_max = 0.7
	splash.position = Vector3(0, 0.64, 0)
	n.add_child(splash)
	fountain_jets = [jet, fall, splash]
	n.add_child(Util.pick_area("fountain", Vector3(5.6, 3.2, 5.6), Vector3(0, 1.6, 0)))
	_obst.append([p.x, p.z, 3.0, 1.0])


func _lathe(prof: PackedVector2Array, material: Material, segs := 48) -> MeshInstance3D:
	## Тіло обертання з профілю (r, y); нормаль — праворуч від напрямку профілю.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := 0.0
	for i in prof.size() - 1:
		total += prof[i].distance_to(prof[i + 1])
	var acc := 0.0
	for i in prof.size() - 1:
		var a := prof[i]
		var b := prof[i + 1]
		var ln := a.distance_to(b)
		var d := (b - a).normalized()
		var nr := Vector2(d.y, -d.x)
		var va := acc / total
		var vb := (acc + ln) / total
		acc += ln
		for s in segs:
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var a0 := Vector3(a.x * sin(t0), a.y, a.x * cos(t0))
			var a1 := Vector3(a.x * sin(t1), a.y, a.x * cos(t1))
			var b0 := Vector3(b.x * sin(t0), b.y, b.x * cos(t0))
			var b1 := Vector3(b.x * sin(t1), b.y, b.x * cos(t1))
			var n0 := Vector3(nr.x * sin(t0), nr.y, nr.x * cos(t0))
			var n1 := Vector3(nr.x * sin(t1), nr.y, nr.x * cos(t1))
			var u0 := float(s) / segs
			var u1 := float(s + 1) / segs
			for v in [[b0, n0, Vector2(u0, vb)], [b1, n1, Vector2(u1, vb)], [a1, n1, Vector2(u1, va)],
					[b0, n0, Vector2(u0, vb)], [a1, n1, Vector2(u1, va)], [a0, n0, Vector2(u0, va)]]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	return mi


func _tile_mat(tiles: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = _TILE_SH
	m.set_shader_parameter("tiles", tiles)
	return m


func _fountain_water(r: float, ring_r: float, pos: Vector3) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = _FWATER_SH
	m.set_shader_parameter("ring_r", ring_r)
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.01
	cm.radial_segments = 40
	cm.cap_bottom = false
	return Util.mesh(cm, m, pos)


const _TILE_SH := """
shader_type spatial;
uniform float tiles = 44.0;
uniform vec3 base_col : source_color = vec3(0.12, 0.3, 0.62);
uniform vec3 orn : source_color = vec3(0.96, 0.76, 0.26);
uniform vec3 orn2 : source_color = vec3(0.78, 0.2, 0.15);
uniform vec3 grout : source_color = vec3(0.95, 0.92, 0.84);
void fragment() {
	float v = UV.y;
	vec2 f = vec2(fract(UV.x * tiles), clamp((v - 0.14) / 0.72, 0.0, 1.0));
	float dm = abs(f.x - 0.5) + abs(f.y - 0.5);
	float aa = fwidth(dm) + 0.01;
	vec3 c = base_col;
	c = mix(c, grout, smoothstep(0.44 + aa, 0.44, dm) - smoothstep(0.37 + aa, 0.37, dm));
	c = mix(c, orn, smoothstep(0.3 + aa, 0.3, dm));
	c = mix(c, orn2, smoothstep(0.14 + aa, 0.14, dm));
	float g = min(f.x, 1.0 - f.x);
	c = mix(grout, c, smoothstep(0.012, 0.03, g));
	float band = step(v, 0.14) + step(0.86, v);
	float zig = step(abs(fract(UV.x * tiles * 2.0) - 0.5) * 2.0, fract(v * 7.0));
	vec3 bc = mix(orn2, orn, zig * 0.35);
	c = mix(c, bc, clamp(band, 0.0, 1.0));
	float line = smoothstep(0.012, 0.0, abs(v - 0.14)) + smoothstep(0.012, 0.0, abs(v - 0.86));
	c = mix(c, grout, clamp(line, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
}
"""

const _MOSAIC_SH := """
shader_type spatial;
varying vec2 lp;
float hh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nz(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hh(i), hh(i + vec2(1, 0)), f.x), mix(hh(i + vec2(0, 1)), hh(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float r = length(lp);
	float a = atan(lp.y, lp.x);
	vec2 g = lp / 0.09;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float n = hh(id);
	vec3 c = mix(vec3(0.15, 0.6, 0.65), vec3(0.32, 0.76, 0.76), n);
	float star = 0.42 + 0.3 * pow(abs(cos(a * 4.0)), 3.0);
	if (r < star) c = mix(vec3(0.98, 0.8, 0.32), vec3(1.0, 0.93, 0.62), n);
	else if (r < 0.95) c = mix(vec3(0.1, 0.24, 0.6), vec3(0.16, 0.32, 0.7), n);
	else if (r < 1.05) c = vec3(0.95, 0.93, 0.85);
	else if (r > 2.05 + 0.08 * sin(a * 16.0)) c = mix(vec3(0.1, 0.26, 0.6), vec3(0.16, 0.34, 0.7), n);
	c *= 0.88 + 0.2 * hh(id + 7.0);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	c = mix(vec3(0.62, 0.62, 0.58), c, smoothstep(0.04, 0.1, edge));
	float ca = nz(lp * 3.0 + vec2(TIME * 0.4, TIME * 0.25)) * nz(lp * 4.3 - vec2(TIME * 0.3, -TIME * 0.35));
	c += vec3(0.28, 0.33, 0.33) * smoothstep(0.25, 0.6, ca);
	ALBEDO = c;
	ROUGHNESS = 0.5;
}
"""

const _FWATER_SH := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(0.5, 0.82, 0.88);
uniform vec3 sky : source_color = vec3(0.72, 0.85, 0.95);
uniform float ring_r = 1.0;
varying vec2 lp;
float hh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nz(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hh(i), hh(i + vec2(1, 0)), f.x), mix(hh(i + vec2(0, 1)), hh(i + vec2(1, 1)), f.x), f.y);
}
float rip(vec2 p, float t) {
	return nz(p * 3.0 + vec2(t * 0.5, t * 0.3)) * 0.6 + nz(p * 7.0 - vec2(t * 0.4, -t * 0.6)) * 0.4;
}
void vertex() { lp = VERTEX.xz; }
void fragment() {
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float e = 0.04;
	float r0 = rip(lp, TIME);
	vec2 dg = vec2(rip(lp + vec2(e, 0.0), TIME) - r0, rip(lp + vec2(0.0, e), TIME) - r0) / e * 0.05;
	float r = length(lp);
	float d = abs(r - ring_r);
	vec2 dir = lp / max(r, 0.001) * sign(r - ring_r);
	vec2 rg = dir * cos(d * 30.0 - TIME * 7.0) * exp(-d * 3.5) * 0.08;
	vec3 nw = normalize(vec3(-(dg.x + rg.x), 1.0, -(dg.y + rg.y)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, V), 0.0, 1.0), 5.0);
	vec3 col = mix(tint, sky, fres);
	float alpha = mix(0.2, 0.9, fres);
	float foam = exp(-d * 9.0) * (0.5 + 0.5 * nz(lp * 6.0 + vec2(TIME * 1.5, -TIME)));
	col = mix(col, vec3(0.97), foam * 0.7);
	alpha = max(alpha, foam * 0.7);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = 0.03;
	SPECULAR = 0.7;
}
"""


var _fence_post: Material
var _fence_weave: Material


func _low_fence(a: Vector3, b: Vector3) -> void:
	if _fence_post == null:
		_fence_post = Util.mat(Color(0.45, 0.32, 0.2), 0.9)
		_fence_weave = Util.mat(Color(0.62, 0.47, 0.3), 0.95)
	var post := _fence_post
	var weave := _fence_weave
	var n := int(ceil(a.distance_to(b) / 1.2))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		add_child(Util.cyl(0.04, 0.05, 1.0, post, Vector3(p.x, 0.5, p.z)))
	var mid := (a + b) / 2.0
	var ang := atan2(b.x - a.x, b.z - a.z)
	for k in 4:
		var bar := Util.box(Vector3(0.06, 0.1, a.distance_to(b)), weave, Vector3(mid.x, 0.2 + k * 0.18, mid.z))
		bar.rotation.y = ang
		add_child(bar)


func _make_church(p: Vector3) -> void:
	## Біла дерев'яна церковка з блакитною банею — видно здалеку.
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var white := Util.mat(Color(0.96, 0.95, 0.9), 0.85)
	var blue := Util.mat(Color(0.3, 0.55, 0.9), 0.4)
	var gold := Util.mat(Color(0.95, 0.75, 0.25), 0.3, 0.7)
	var wood := Util.mat(Color(0.5, 0.33, 0.2), 0.9)
	n.add_child(Util.box(Vector3(6.0, 4.5, 8.0), white, Vector3(0, 2.25, 0)))
	n.add_child(Util.mesh(PrismMesh.new(), blue, Vector3(0, 5.3, 0), Vector3.ZERO, Vector3(6.6, 1.6, 8.6)))
	n.add_child(Util.box(Vector3(3.0, 3.0, 3.0), white, Vector3(0, 6.5, 0)))
	n.add_child(Util.cyl(1.3, 1.3, 1.2, white, Vector3(0, 8.6, 0)))
	n.add_child(Util.sphere(1.5, blue, Vector3(0, 9.9, 0), Vector3(1, 1.25, 1)))
	n.add_child(Util.cyl(0.05, 0.15, 1.2, gold, Vector3(0, 11.9, 0)))
	n.add_child(Util.box(Vector3(0.08, 1.0, 0.08), gold, Vector3(0, 12.9, 0)))
	n.add_child(Util.box(Vector3(0.6, 0.08, 0.08), gold, Vector3(0, 13.1, 0)))
	n.add_child(Util.box(Vector3(1.4, 2.4, 0.1), wood, Vector3(0, 1.2, -4.03)))
	for wx in [-1.8, 1.8]:
		n.add_child(Util.box(Vector3(0.8, 1.3, 0.1), blue, Vector3(wx, 2.6, -4.03)))
	_obst.append([p.x, p.z, 5.0, 12.0])
	houses.append([p.x, p.z])


# ------------------------------------------------------------------ вода
const RIVER_FLOW := Vector2(0.7, 0.0)          # куди й як швидко тече річка (м/с)
const RIVER_DEPTH := 1.6
const POND_DEPTH := 2.0

const _WATER_SH := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform vec2 flow = vec2(0.0);
uniform float amp = 1.0;
uniform float fixed_depth = -1.0;
uniform vec3 shallow : source_color = vec3(0.3, 0.55, 0.5);
uniform vec3 deep : source_color = vec3(0.04, 0.2, 0.26);
uniform vec3 sky : source_color = vec3(0.62, 0.77, 0.9);
varying vec3 wp;
varying float dep;
varying vec2 wg;
float hh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nz(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hh(i), hh(i + vec2(1, 0)), f.x), mix(hh(i + vec2(0, 1)), hh(i + vec2(1, 1)), f.x), f.y);
}
void wave(vec2 p, vec2 d, float f, float a, float s, float t, inout float h, inout vec2 g) {
	float ph = dot(d, p) * f + t * s;
	h += a * sin(ph);
	g += a * f * d * cos(ph);
}
float ripple(vec2 p, float t) {
	return nz(p * 1.7 + vec2(t * 0.35, t * 0.22)) * 0.55 + nz(p * 4.1 - vec2(t * 0.3, -t * 0.45)) * 0.3
		+ nz(p * 9.0 + vec2(-t * 0.6, t * 0.5)) * 0.15;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dep = fixed_depth >= 0.0 ? fixed_depth : UV.x;
	// хвилі: три хвилі різної довжини й напрямку; біля берега стихають
	float k = amp * smoothstep(0.08, 0.9, dep);
	vec2 p = wp.xz - flow * TIME * 0.6;
	float h = 0.0;
	vec2 g = vec2(0.0);
	wave(p, vec2(0.8, 0.6), 0.9, 0.035, 1.3, TIME, h, g);
	wave(p, vec2(-0.5, 0.866), 1.4, 0.022, 1.7, TIME, h, g);
	wave(p, vec2(0.196, -0.98), 2.3, 0.012, 2.2, TIME, h, g);
	VERTEX.y += h * k;
	wg = g * k;
}
void fragment() {
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float dist = length(VERTEX);
	// дрібна брижа, пливе за течією
	vec2 q = wp.xz - flow * TIME;
	float e = 0.05;
	float r0 = ripple(q, TIME);
	vec2 dg = vec2(ripple(q + vec2(e, 0.0), TIME) - r0, ripple(q + vec2(0.0, e), TIME) - r0) / e;
	dg *= 0.07 * (1.0 - smoothstep(25.0, 120.0, dist));
	vec3 nw = normalize(vec3(-(wg.x + dg.x), 1.0, -(wg.y + dg.y)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// прозорість: що глибше й що навскісніше дивишся — то густіший колір води
	float d = max(dep, 0.0);
	float path = d / max(V.y, 0.2);
	float absorb = 1.0 - exp(-path * 1.4);
	vec3 col = mix(shallow, deep, absorb);
	float alpha = mix(0.08, 0.93, absorb);
	// відблиск неба: збоку вода — як дзеркало, згори — видно дно
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, V), 0.0, 1.0), 5.0);
	col = mix(col, sky, fres * 0.85);
	alpha = mix(alpha, 1.0, fres);
	// піна біля берега
	float shore = smoothstep(0.0, 0.06, dep);
	float fb = 1.0 - smoothstep(0.07, 0.32, dep);
	float foam = fb * smoothstep(0.5, 0.8, nz(wp.xz * 2.2 + vec2(TIME * 0.3, -TIME * 0.2)) + 0.25 * sin(TIME * 1.5 + dep * 20.0));
	col = mix(col, vec3(0.93, 0.95, 0.95), foam * 0.8);
	alpha = max(alpha, foam * 0.8);
	ALBEDO = col;
	ALPHA = clamp(alpha * shore, 0.0, 1.0);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""

const _BED_SH := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_tex = 0.0;
uniform vec2 flow = vec2(0.0);
varying vec3 wp;
varying float dep;
float hh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nz(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hh(i), hh(i + vec2(1, 0)), f.x), mix(hh(i + vec2(0, 1)), hh(i + vec2(1, 1)), f.x), f.y);
}
float caus(vec2 p, float t) {
	vec2 w = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.45;
	float a = abs(sin(w.x * 2.1 + t * 0.6) + sin(w.y * 2.3 - t * 0.5));
	float b = abs(sin((w.x + w.y) * 1.6 - t * 0.8) + sin((w.x - w.y) * 1.9 + t * 0.4));
	return pow(clamp(1.0 - min(a, b) * 0.6, 0.0, 1.0), 5.0);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dep = UV.x;
}
void fragment() {
	vec2 p = wp.xz;
	vec3 sand = vec3(0.78, 0.7, 0.5);
	sand = mix(sand, sand * texture(sand_tex, p / 2.6).rgb / vec3(0.83, 0.70, 0.55), use_tex);
	vec3 mud = vec3(0.3, 0.29, 0.2) * (0.85 + nz(p * 0.9) * 0.3);
	vec3 c = mix(sand, mud, smoothstep(0.15, 1.3, dep));
	c *= 0.82 + nz(p * 6.0) * 0.25;                        // камінчики й мулисті плями
	// сонячні відблиски на дні (каустика), пливуть за течією
	float ca = caus(p * 1.3 - flow * TIME * 0.5, TIME);
	c += vec3(0.85, 0.95, 0.8) * ca * 0.28 * (1.0 - smoothstep(0.2, 2.0, dep));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""


func _water_mat(flow := Vector2.ZERO, amp := 1.0, fixed_depth := -1.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = _WATER_SH
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("amp", amp)
	m.set_shader_parameter("fixed_depth", fixed_depth)
	return m


func _bed_mat(flow := Vector2.ZERO) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = _BED_SH
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("flow", flow)
	if ResourceLoader.exists("res://assets/textures/sand.jpg"):
		m.set_shader_parameter("sand_tex", load("res://assets/textures/sand.jpg"))
		m.set_shader_parameter("use_tex", 1.0)
	return m


func _water_body(x0: float, x1: float, z0: float, z1: float, sx: float, sz: float, depth_of: Callable, flow: Vector2) -> void:
	## Дно (русло, чаша ставка) і вода над ним — дві сітки з однаковими точками.
	## depth_of(p) — глибина під землею (м), від'ємна — уже берег.
	var nx := int(ceil((x1 - x0) / sx))
	var nzc := int(ceil((z1 - z0) / sz))
	var w := nx + 1
	var dep := PackedFloat32Array()
	dep.resize(w * (nzc + 1))
	for j in nzc + 1:
		for i in w:
			dep[j * w + i] = float(depth_of.call(Vector3(x0 + i * sx, 0, z0 + j * sz)))
	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var uv := PackedVector2Array()
	var wuv := PackedVector2Array()
	for j in nzc + 1:
		for i in w:
			var x := x0 + i * sx
			var z := z0 + j * sz
			var d: float = dep[j * w + i]
			var yl := -maxf(dep[j * w + maxi(i - 1, 0)], 0.0)
			var yr := -maxf(dep[j * w + mini(i + 1, nx)], 0.0)
			var yd := -maxf(dep[maxi(j - 1, 0) * w + i], 0.0)
			var yu := -maxf(dep[mini(j + 1, nzc) * w + i], 0.0)
			bv.append(Vector3(x, -maxf(d, 0.0) - 0.015, z))
			bn.append(Vector3(-(yr - yl) / (2.0 * sx), 1.0, -(yu - yd) / (2.0 * sz)).normalized())
			uv.append(Vector2(maxf(d, 0.0), 0))
			wv.append(Vector3(x, 0.05, z))
			wn.append(Vector3.UP)
			wuv.append(Vector2(d + 0.065, 0))
	var idx := PackedInt32Array()
	for j in nzc:
		for i in nx:
			var a := j * w + i
			if maxf(maxf(dep[a], dep[a + 1]), maxf(dep[a + w], dep[a + w + 1])) < -0.6:
				continue
			for k in [a, a + 1, a + w, a + 1, a + w + 1, a + w]:
				idx.append(k)
	for pair in [[bv, bn, uv, _bed_mat(flow)], [wv, wn, wuv, _water_mat(flow)]]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pair[0]
		arr[Mesh.ARRAY_NORMAL] = pair[1]
		arr[Mesh.ARRAY_TEX_UV] = pair[2]
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = pair[3]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _make_river() -> void:
	# русло: біля берега мілко, посередині — RIVER_DEPTH; вода тече вздовж x
	var river_depth := func(p: Vector3) -> float:
		var e := RIVER_W / 2.0 - absf(p.z - RIVER_Z)
		return RIVER_DEPTH * smoothstep(0.0, 3.0, e) if e > 0.0 else e
	_water_body(-LIMIT * 1.2, LIMIT * 1.2, RIVER_Z - RIVER_W / 2.0 - 0.5, RIVER_Z + RIVER_W / 2.0 + 0.5, 2.0, 0.5, river_depth, RIVER_FLOW)
	# дерев'яний місток на дорозі
	var plank: Material = world._planks_mat(Color(0.55, 0.4, 0.26), true)
	var post := Util.mat(Color(0.4, 0.28, 0.18), 0.9)
	var br := Util.box(Vector3(3.4, 0.16, RIVER_W + 4.0), plank, Vector3(0, 0.35, RIVER_Z))
	add_child(br)
	# пологі сходи з берега на настил (Ніка й усі інші йдуть по мосту, а не крізь нього)
	for s in [-1.0, 1.0]:
		add_child(Util.box(Vector3(3.4, 0.08, 1.86), plank, Vector3(0, 0.175, RIVER_Z + s * 6.9), Vector3(s * 0.2345, 0, 0)))
	for side in [-1.0, 1.0]:
		add_child(Util.box(Vector3(0.1, 0.08, RIVER_W + 4.0), post, Vector3(side * 1.6, 1.15, RIVER_Z)))
		for k in 7:
			var z := RIVER_Z - (RIVER_W + 4.0) / 2.0 + k * (RIVER_W + 4.0) / 6.0
			add_child(Util.cyl(0.07, 0.08, 1.2, post, Vector3(side * 1.6, 0.6, z)))
			if absf(z - RIVER_Z) < RIVER_W / 2.0:
				add_child(Util.cyl(0.1, 0.11, 2.0, post, Vector3(side * 1.6, -0.8, z)))    # палі мосту — до самого дна
	# очерет уздовж берегів
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts: Array = []
	for i in 260:
		var x := rng.randf_range(-LIMIT, LIMIT)
		if absf(x) < 4.0:
			continue
		var z := RIVER_Z + (RIVER_W / 2.0 + rng.randf_range(-0.3, 0.8)) * (1.0 if rng.randf() < 0.5 else -1.0)
		pts.append(Vector3(x, 0, z))
	_reeds(pts, rng)


static func pond_sd(p: Vector3) -> float:
	## Відстань від точки до берега ставка (від'ємна — у воді).
	var q := Vector2(absf(p.x - POND.x), absf(p.z - POND.z)) - (POND_HALF - Vector2(POND_CORNER, POND_CORNER))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - POND_CORNER


func water_depth(p: Vector3) -> float:
	## Глибина води в точці (річка або ставок), м; ≤ 0 — суша.
	var e := RIVER_W / 2.0 - absf(p.z - RIVER_Z)
	var d := RIVER_DEPTH * smoothstep(0.0, 3.0, e) if e > 0.0 else e
	var sd := pond_sd(p)
	if sd < 0.0:
		d = maxf(d, POND_DEPTH * smoothstep(0.0, 7.0, -sd))
	return d


func _pond_t(a: float) -> float:
	## Від центру ставка до берега під кутом a (м).
	var d := Vector3(cos(a), 0, sin(a))
	var lo := 0.0
	var hi := POND_HALF.length() + 1.0
	for i in 24:
		var m := (lo + hi) * 0.5
		if pond_sd(POND + d * m) < 0.0:
			lo = m
		else:
			hi = m
	return (lo + hi) * 0.5


func _pond_outline(off := 0.0, seg := 8) -> PackedVector2Array:
	## Обрис берега (x, z) — прямокутник із заокругленими кутами; off — відступ назовні.
	var pts := PackedVector2Array()
	var cr := POND_CORNER + off
	var ix := POND_HALF.x - POND_CORNER
	var iz := POND_HALF.y - POND_CORNER
	for c in [[1.0, 1.0, 0.0], [-1.0, 1.0, PI / 2.0], [-1.0, -1.0, PI], [1.0, -1.0, PI * 1.5]]:
		for k in seg + 1:
			var a: float = c[2] + PI / 2.0 * k / seg
			pts.append(Vector2(POND.x + c[0] * ix + cos(a) * cr, POND.z + c[1] * iz + sin(a) * cr))
	return pts


func _make_pond(rng: RandomNumberGenerator) -> void:
	## Ставок — прямокутний, із заокругленими краями; чаша полого йде вглиб до POND_DEPTH посередині.
	var pond_depth := func(p: Vector3) -> float:
		var sd := pond_sd(p)
		return POND_DEPTH * smoothstep(0.0, 7.0, -sd) if sd < 0.0 else -sd
	_water_body(POND.x - POND_HALF.x - 1.0, POND.x + POND_HALF.x + 1.0, POND.z - POND_HALF.y - 1.0, POND.z + POND_HALF.y + 1.0,
		0.7, 0.7, pond_depth, Vector2(0.08, 0.05))
	var pts: Array = []
	for i in 140:
		var a := rng.randf() * TAU
		if a > 0.3 and a < 0.9:
			continue          # тут місток-причал
		if a > TAU - 0.55 or a < 0.18:
			continue          # тут гуси заходять у воду
		var r := _pond_t(a) + rng.randf_range(-0.6, 0.5)
		pts.append(POND + Vector3(cos(a) * r, 0, sin(a) * r))
	_reeds(pts, rng)
	# причал і човен
	var a2 := 0.6
	var dir := Vector3(cos(a2), 0, sin(a2))
	var edge := _pond_t(a2)
	# причал низький (настил на PIER_DECK над землею) — Ніка заходить на нього з берега й гуляє над водою.
	# Модель pier.glb: довжина вздовж x (1.99), ширина настилу 0.54, настил на 0.45 вище низу опор (усе в одиницях моделі).
	var side := Vector3(-dir.z, 0, dir.x)
	var pier_len := PIER_W / 0.545 * 1.99
	var pier_c := POND + dir * (edge + 0.8 - pier_len / 2.0)       # береговий край — на 0.8 м на суші
	var pm := Models.spawn(self, "pier", PIER_W / 0.545 * 0.75, "x") if Models.exists("pier") else null
	if pm:
		# модель лежить уздовж x — повертаємо так, щоб причал ішов від берега у воду;
		# опори йдуть під землю й під воду, над водою лишається тільки настил і низенькі стовпчики
		pm.position = pier_c + Vector3(0, PIER_DECK - PIER_W / 0.545 * 0.453, 0)
		pm.rotation.y = atan2(dir.x, dir.z) + PI / 2.0
	else:
		var plank: Material = world._planks_mat(Color(0.55, 0.4, 0.26), true)
		var pier := Util.box(Vector3(PIER_W, 0.12, pier_len), plank, pier_c + Vector3(0, PIER_DECK - 0.06, 0))
		pier.rotation.y = atan2(dir.x, dir.z)
		add_child(pier)
	var pa := POND + dir * (edge + 0.8)
	var pb := POND + dir * (edge + 0.8 - pier_len)
	Util.pier = {"a": Vector2(pa.x, pa.z), "b": Vector2(pb.x, pb.z), "hw": PIER_W / 2.0 - 0.05, "y": PIER_DECK}
	# човен — завдовжки ~3.2 м, на воді поруч із причалом (з того боку, де глибше), бортом уздовж нього
	boat = Models.spawn(self, "boat", 3.2, "realx") if Models.exists("boat") else null
	if boat:
		boat.position = POND + dir * (edge - 3.6) - side * 2.0 + Vector3(0, -0.34, 0)
		boat.rotation.y = atan2(dir.x, dir.z) + PI / 2.0 + 0.12
		_boat_y = boat.position.y
		_boat_rot = boat.rotation.y
	# перешкода — уздовж берега (кола по 4.5 м) і посередині
	var ring := _pond_outline(-5.0, 3)
	var prev := ring[ring.size() - 1]
	for q in ring:
		var n := maxi(1, int(ceil(prev.distance_to(q) / 5.0)))
		for k in n:
			var c := prev.lerp(q, float(k + 1) / n)
			_obst.append([c.x, c.y, 4.5, 0.1])
		prev = q
	for x in [-7.0, 0.0, 7.0]:
		_obst.append([POND.x + x, POND.z, POND_HALF.y - 0.5, 0.1])


# ------------------------------------------------------------------ риби у ставку й у річці (fish.gd)
var fish: Node3D


func _make_fish() -> void:
	fish = preload("res://scripts/fish.gd").new()
	fish.name = "Fish"
	add_child(fish)
	fish.setup(self)


# ------------------------------------------------------------------ осока біля озера: росте й розмножується
const SEDGE_START := 7
const SEDGE_MAX := 34
var sedge: Array = []
var _sedge_day := -1
var _sedge_t := 0.0
var _sedge_rng := RandomNumberGenerator.new()


func _sedge_add(grow_from: Node3D = null) -> void:
	## Новий кущ осоки: біля озера, або поруч із батьківським кущем (розмножується).
	if not Models.exists("sedge") or sedge.size() >= SEDGE_MAX:
		return
	var pos := Vector3.ZERO
	for tries in 12:
		var a: float
		var r: float
		if grow_from and is_instance_valid(grow_from):
			var q := grow_from.position + Vector3(_sedge_rng.randf_range(-1.6, 1.6), 0, _sedge_rng.randf_range(-1.6, 1.6))
			var off := q - POND
			a = atan2(off.z, off.x)
			r = off.length()
		else:
			a = _sedge_rng.randf() * TAU
			r = _pond_t(a) + _sedge_rng.randf_range(0.2, 2.2)
		var an := fposmod(a, TAU)
		if (an > 0.25 and an < 0.95) or an > TAU - 0.6 or an < 0.2:
			continue                      # причал і місце, де гуси заходять у воду
		var et := _pond_t(a)
		if r < et - 0.3 or r > et + 3.2:
			continue
		pos = POND + Vector3(cos(a) * r, 0, sin(a) * r)
		var ok := true
		for o in sedge:
			if (o as Node3D).position.distance_to(pos) < 0.7:
				ok = false
				break
		if ok:
			var h := Models.spawn(self, "sedge", _sedge_rng.randf_range(0.7, 1.1))
			h.position = pos
			h.rotation.y = _sedge_rng.randf() * TAU
			h.scale = Vector3.ONE * 0.2          # росте з маленького
			h.set_meta("grow", 0.0)
			sedge.append(h)
			return


func _sedge_step(delta: float) -> void:
	if sedge.is_empty() and _sedge_day == -1:
		_sedge_rng.seed = 77
		for i in SEDGE_START:
			_sedge_add()
		for h in sedge:
			h.scale = Vector3.ONE
			h.set_meta("grow", 1.0)
		_sedge_day = int(Game.state["day"])
	# кожен новий день — одна-дві нові рослини поруч зі старими
	var d := int(Game.state["day"])
	if _sedge_day != -1 and d != _sedge_day:
		_sedge_day = d
		for k in 2:
			if not sedge.is_empty():
				_sedge_add(sedge[_sedge_rng.randi() % sedge.size()])
	# плавно підростають
	_sedge_t += delta
	if _sedge_t > 0.1:
		var dt := _sedge_t
		_sedge_t = 0.0
		for h in sedge:
			var g: float = h.get_meta("grow", 1.0)
			if g < 1.0:
				g = minf(1.0, g + dt / 40.0)
				h.set_meta("grow", g)
				h.scale = Vector3.ONE * lerpf(0.2, 1.0, g)


var boat: Node3D
var _boat_y := 0.0
var _boat_rot := 0.0
var _bt := 0.0
var fountain_jets: Array = []


func _boat_step(delta: float) -> void:
	_bt += delta
	if boat:
		# човен гойдається на воді
		boat.position.y = _boat_y + sin(_bt * 1.3) * 0.04
		boat.rotation.z = sin(_bt * 0.9) * 0.04
		boat.rotation.y = _boat_rot + sin(_bt * 0.25) * 0.06


func _reeds(pts: Array, rng: RandomNumberGenerator) -> void:
	## Очерет: тонкі зелені стебла з коричневими «качалками» — одним MultiMesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := float(k) / 5.0 * TAU
		var off := Vector3(cos(a), 0, sin(a)) * 0.12
		var hgt := 1.1 + 0.25 * sin(k * 2.3)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.02
		st.set_color(Color(0.25, 0.42, 0.15))
		st.add_vertex(off - side)
		st.add_vertex(off + side)
		st.set_color(Color(0.5, 0.62, 0.25))
		st.add_vertex(off + Vector3(0, hgt, 0) + off * 0.3)
		if k % 2 == 0:
			var top := off + Vector3(0, hgt * 0.8, 0) + off * 0.25
			st.set_color(Color(0.4, 0.25, 0.12))
			st.add_vertex(top - side * 1.8)
			st.add_vertex(top + side * 1.8)
			st.add_vertex(top + Vector3(0, 0.2, 0))
	st.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), pts[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = world.grass.material_override
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ копички сіна (колишнє пшеничне поле прибрано)
func _make_wheat(rng: RandomNumberGenerator) -> void:
	## Пшеницю й опудало прибрано — лишилися копички сіна вздовж краю колишнього поля.
	## Випадкові числа «прокручуємо» так само, як і раніше, щоб ліс і луки стояли на тих самих місцях.
	for i in 5200:
		rng.randf()
		rng.randf()
	for i in 5200:
		rng.randf()
		rng.randf_range(0.8, 1.2)
	for k in 4:
		var hs := Models.spawn(self, "haystack", rng.randf_range(1.3, 1.7))
		if hs:
			hs.position = Vector3(WHEAT.position.x + 6 + k * 10.0, 0, WHEAT.end.y + 3.0)
			_obst.append([hs.position.x, hs.position.z, 1.1, 1.5])


# ------------------------------------------------------------------ пшеничне поле (на місці старого грибного лісу)
func _make_wheat_field() -> void:
	var rng := RandomNumberGenerator.new()         # окремий генератор — решта світу не зсувається
	rng.seed = 4242
	var hay := Models.spawn(self, "haystack", 1.9)
	if hay:
		hay.position = HAY_N
		hay.rotation.y = 0.7
		_obst.append([HAY_N.x, HAY_N.z, 1.3, 1.9])
	if Models.exists("wheat"):
		_make_wheat_clumps(rng)
		return
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 1.0, 0.04)
	var mat := Util.mat(Color(0.86, 0.7, 0.3), 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var field := Node3D.new()
	field.name = "WheatField"
	add_child(field)
	var chunk := 18.0
	var buckets := {}
	var x := WHEAT_N.position.x + 0.25
	while x < WHEAT_N.end.x:
		var z := WHEAT_N.position.y + 0.25
		while z < WHEAT_N.end.y:
			var p := Vector3(x + rng.randf_range(-0.18, 0.18), 0, z + rng.randf_range(-0.18, 0.18))
			var h := rng.randf_range(0.85, 1.2)
			var ang := rng.randf() * TAU
			if not _near_forest_road(Vector2(p.x, p.z), 1.8):
				var key := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3(1.0, h, 1.0)), p + Vector3(0, h * 0.5, 0)))
			z += 0.5
		x += 0.5
	var i := 0
	for key in buckets:
		var list: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pm
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mi := MultiMeshInstance3D.new()
		mi.name = "wheat_%d" % i
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 120.0
		field.add_child(mi)
		i += 1


func _make_wheat_clumps(rng: RandomNumberGenerator) -> void:
	## Пшениця з моделі wheat.glb (кущі колосся з Meshy): зблизька — детальна, далі — спрощена wheat_lo.
	var sc: Node = (load(Models.DIR % "wheat") as PackedScene).instantiate()
	var hi_n := sc.find_child("wheat", true, false) as MeshInstance3D
	var lo_n := sc.find_child("wheat_lo", true, false) as MeshInstance3D
	var hi: Mesh = hi_n.mesh if hi_n else null
	var lo: Mesh = lo_n.mesh if lo_n else hi
	sc.free()
	if hi == null:
		return
	var field := Node3D.new()
	field.name = "WheatField"
	add_child(field)
	var chunk := 6.0
	var step := 1.45
	var buckets := {}
	var x := WHEAT_N.position.x + step * 0.5
	while x < WHEAT_N.end.x:
		var z := WHEAT_N.position.y + step * 0.5
		while z < WHEAT_N.end.y:
			var p := Vector3(x + rng.randf_range(-0.4, 0.4), 0, z + rng.randf_range(-0.4, 0.4))
			var s := rng.randf_range(1.05, 1.3)
			var ang := rng.randf() * TAU
			if not _near_forest_road(Vector2(p.x, p.z), 1.8):
				var key := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3(s, s * rng.randf_range(0.95, 1.15), s)), p))
			z += step
		x += step
	var i := 0
	for key in buckets:
		var list: Array = buckets[key]
		var c := Vector3((key.x + 0.5) * chunk, 0, (key.y + 0.5) * chunk)   # вузол у центрі шматка — від нього рахується дальність
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = hi if lod == 0 else lo
			mm.instance_count = list.size()
			for j in list.size():
				var t: Transform3D = list[j]
				mm.set_instance_transform(j, Transform3D(t.basis, t.origin - c))
			var mi := MultiMeshInstance3D.new()
			mi.name = "wheat_%d_%d" % [i, lod]
			mi.position = c
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod == 0:
				mi.visibility_range_end = 22.0
			else:
				mi.visibility_range_begin = 22.0
				mi.visibility_range_end = 140.0
			field.add_child(mi)
		i += 1


# ------------------------------------------------------------------ пагорб з млином, піщана дорога, дерева
func _make_mill() -> void:
	var hill := Util.sphere(1.0, Util.mat(Color(0.45, 0.6, 0.28), 1.0), MILL_HILL + Vector3(0, -MILL_HILL_H * 0.6, 0),
		Vector3(MILL_HILL_R, MILL_HILL_H * 1.6, MILL_HILL_R))
	hill.name = "mill_hill"
	(hill.mesh as SphereMesh).radial_segments = 64        # гладкий схил — дорога лежить рівно
	(hill.mesh as SphereMesh).rings = 32
	hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hill)                                        # по пагорбу ходять і їздять: висота — Util.hill_y
	_make_mill_road()
	_make_mill_trees()


func _hill_y(x: float, z: float) -> float:
	## Висота поверхні пагорба в точці (x, z); 0 — поза пагорбом.
	return Util.hill_y(Vector3(x, 0, z))


func _make_mill_road() -> void:
	## Піщана дорога від кінця польової дороги вгору по схилу до дверей млина.
	var c := Vector2(MILL_HILL.x, MILL_HILL.z)
	var side := Vector2(MILL_DIR.y, -MILL_DIR.x) * (float(MILL_ROAD[2]) / 2.0)
	var steps := 64
	var rows := []
	for i in steps + 1:
		var m: Vector2 = c + MILL_DIR * lerpf(float(MILL_ROAD[0]), float(MILL_ROAD[1]), float(i) / steps)
		var row := []
		for s in [-1.0, 1.0]:
			var q: Vector2 = m + side * s
			row.append(Vector3(q.x, _hill_y(q.x, q.y) + 0.03, q.y))
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0: Vector3 = rows[i][0]
		var a1: Vector3 = rows[i][1]
		var b0: Vector3 = rows[i + 1][0]
		var b1: Vector3 = rows[i + 1][1]
		var n := (b0 - a0).cross(a1 - a0).normalized()
		if n.y < 0.0:
			n = -n
		for v in [a0, b0, a1, a1, b0, b1]:
			st.set_normal(n)
			st.add_vertex(v)
	var sand := Util.road_mat()
	var road := MeshInstance3D.new()
	road.name = "mill_road"
	road.mesh = st.commit()
	road.material_override = sand
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)


func _make_mill_trees() -> void:
	for i in MILL_TREES.size():
		var t: Array = MILL_TREES[i]
		var m := Models.spawn(self, t[0], t[2])
		if m == null:
			continue
		var q: Vector2 = t[1]
		var y := _hill_y(q.x, q.y)
		if y > 0.0:
			y -= 0.15                                      # трохи в схил, щоб не висіло
		m.name = "mill_tree_%d" % (i + 1)
		m.position = Vector3(q.x, y, q.y)
		m.rotation.y = deg_to_rad(t[3])
		trees.append([q.x, q.y])
		_obst.append([q.x, q.y, 0.5, y + 6.0])


func _near_mill(p: Vector3) -> bool:
	## Новий (ширший) пагорб, піщана дорога й дерева біля неї — випадкового лісу тут не ставимо.
	var q := Vector2(p.x, p.z)
	var c := Vector2(MILL_HILL.x, MILL_HILL.z)
	if q.distance_to(c) < MILL_HILL_R + 2.0:
		return true
	var a: Vector2 = c + MILL_DIR * float(MILL_ROAD[0])
	var t := clampf((q - c).dot(a - c) / (a - c).length_squared(), 0.0, 1.0)
	if q.distance_to(c + (a - c) * t) < 3.5:
		return true
	for tr in MILL_TREES:
		if q.distance_to(tr[1]) < 3.0:
			return true
	return false


# ------------------------------------------------------------------ луки: трава й квіти за тином
func _on_road(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	var segs := [[Vector2(0, 5), Vector2(0, 150)], [Vector2(0, 30), Vector2(-46, 22)], [Vector2(-46, 22), Vector2(-72, -30)], [Vector2(0, 36), Vector2(26, 32)], [Vector2(0, 9), Vector2(-14, 12.5)]]
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var ba := b - a
		var t := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		if q.distance_to(a + ba * t) < 1.6:
			return true
	if _near_forest_road(q, 1.6) or _near_east_road(q, 1.6):
		return true
	if _near_air_road(q, AIR_ROAD_W / 2.0 + 0.3):
		return true
	for sg in _yard_road_segs():
		var a2: Vector2 = sg[0]
		var ba2: Vector2 = sg[1] - a2
		if q.distance_to(a2 + ba2 * clampf((q - a2).dot(ba2) / ba2.dot(ba2), 0.0, 1.0)) < YARD_ROAD_W / 2.0 + 0.3:
			return true
	return q.distance_to(Vector2(VILLAGE.x, VILLAGE.z)) < 10.0


func _in_village_garden(p: Vector3, pad := 0.3) -> bool:
	## Точка на городі за хатою старого села (город — bazaar.gd: VILLAGE_GARDEN, 6.4 × 4.6 м).
	for sp in village_huts:
		var q: Vector3 = Basis(Vector3.UP, float(sp[1])).inverse() * (p - (sp[0] as Vector3))
		if absf(q.x) < 3.2 + pad and absf(q.z + 9.4) < 2.3 + pad:
			return true
	return false


func _make_meadow(rng: RandomNumberGenerator) -> void:
	## Пучки трави й квіти по луках — шматками, далекі не малюються.
	var chunk := 50.0
	var buckets := {}
	var tries := 0
	var n := 0
	while n < 7000 and tries < 20000:
		tries += 1
		var p := Vector3(rng.randf_range(-170, 170), 0, rng.randf_range(-150, 200))
		if p.length() > ZONE_LIMIT:
			continue
		if p.x > -22.0 and p.x < 10.0 and p.z > -16.0 and p.z < 6.0:
			continue
		if _on_road(p) or absf(p.z - RIVER_Z) < RIVER_W / 2.0 + 0.5:
			continue
		if BAZAAR_AREA.has_point(Vector2(p.x, p.z)):
			continue
		var al := air_local(p)
		if al.x < 6.0 and al.x > -83.0 and absf(al.y) < 7.0:
			continue                      # аеродром біля річки
		if pond_sd(p) < 0.5:
			continue
		if _near_plow(Vector2(p.x, p.z), 0.3):
			continue                      # без пучків трави на ріллі й на дорозі до поля
		if _in_village_garden(p) or Util.on_pier(p, 0.5):
			continue                      # на грядках за хатами й крізь дошки причалу трава не росте
		if bazaar and bazaar.building_at(p) != null:
			continue                      # усередині хат, стаєнь і корівників — долівка, а не трава
		var key := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(p)
		n += 1
	var gmesh: Mesh = world.grass.multimesh.mesh
	for key in buckets:
		var list: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = gmesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6)), list[i]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = world.grass.material_override
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 110.0
		add_child(mi)


# ------------------------------------------------------------------ піщана дорога до поля під оранку
func _make_field_road() -> void:
	## Ґрунтова піщана дорога від навісу трактора до поля: смуга з колією посередині.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := FIELD_ROAD_W / 2.0
	for i in FIELD_ROAD.size() - 1:
		var a: Vector2 = FIELD_ROAD[i]
		var b: Vector2 = FIELD_ROAD[i + 1]
		var sd := (b - a).normalized()
		var side := Vector2(sd.y, -sd.x) * hw
		var ext := sd * (hw if i > 0 else 0.0)              # перекриття на зламі, щоб не було щілини
		var a0 := a - ext + side
		var a1 := a - ext - side
		var b0 := b + side
		var b1 := b - side
		for v in [a0, b0, a1, a1, b0, b1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, 0.022 + i * 0.003, v.y))
	var sand := Util.road_mat()
	var road := MeshInstance3D.new()
	road.name = "field_road"
	road.mesh = st.commit()
	road.material_override = sand
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	# дві укочені колії посередині дороги (темніший пісок)
	var rut := Util.road_mat(0.82)
	for i in FIELD_ROAD.size() - 1:
		var a: Vector2 = FIELD_ROAD[i]
		var b: Vector2 = FIELD_ROAD[i + 1]
		var d := b - a
		var sd := d.normalized()
		var nrm := Vector2(sd.y, -sd.x)
		for s in [-0.75, 0.75]:
			var c: Vector2 = (a + b) / 2.0 + nrm * float(s)
			var box := Util.box(Vector3(0.45, 0.01, d.length()), rut, Vector3(c.x, 0.028 + i * 0.003, c.y))
			box.rotation.y = atan2(d.x, d.y)
			box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(box)


# ------------------------------------------------------------------ ліс (MultiMesh по шматках)
const FOREST_C := Vector3(-30.0, 0, -388.0)      # грибний ліс далеко на півночі, за пшеничним полем (має збігатися з CENTER у forest_goods.gd)
const FOREST_R := 40.0
# дорога до лісу: від воріт на захід, повз подвір'я на північ і до лісу (так само в шейдері землі, world.gd, і на мапі, hud.gd)
const FOREST_ROAD := [Vector2(0, 9), Vector2(-24, 8.5), Vector2(-24, -50), Vector2(-29, -70), Vector2(-30, -82)]


func _near_forest_road(q: Vector2, w: float) -> bool:
	for i in FOREST_ROAD.size() - 1:
		var a: Vector2 = FOREST_ROAD[i]
		var b: Vector2 = FOREST_ROAD[i + 1]
		var ba := b - a
		var t := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		if q.distance_to(a + ba * t) < w:
			return true
	return false
# грибний ліс на сході (за полем під оранку): густий, з мохом і сосновими голками; дорога від воріт повз навіс трактора
const EAST_FOREST_C := Vector3(122.0, 0, -18.0)          # галявина в лісі, куди веде дорога (так само в forest_goods.gd)
const EAST_ROAD := [Vector2(1.5, 6.2), Vector2(10.5, 6.0), Vector2(22.5, 5.0), Vector2(71.0, 5.0), Vector2(100.0, 5.5),
	Vector2(112.0, 0.0), Vector2(118.0, -10.0), Vector2(121.0, -16.0)]
const EAST_ROAD_W := 3.0


static func in_east_forest(q: Vector2, pad := 0.0) -> bool:
	## Чи точка в грибному лісі на сході (з півночі вужчий, на південь ширшає; поле під оранку — не ліс).
	if q.y < -102.0 + pad or q.y > 72.0 - pad or q.x > 163.0 - pad:
		return false
	if q.x < 103.0 - (q.y + 102.0) * 0.1437 + pad:
		return false
	return not PLOW_FIELD.grow(5.0).has_point(q)


func _near_east_road(q: Vector2, w: float) -> bool:
	for i in range(3, EAST_ROAD.size() - 1):
		var a: Vector2 = EAST_ROAD[i]
		var ba: Vector2 = EAST_ROAD[i + 1] - a
		var t := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		if q.distance_to(a + ba * t) < w:
			return true
	return q.distance_to(Vector2(EAST_FOREST_C.x, EAST_FOREST_C.z)) < 7.0 + w * 0.5


const ORCHARD := Rect2(2.5, 6.5, 17.5, 15.5)
const PLOW_FIELD := Rect2(74.0, -18.0, 22.0, 20.0)      # поле під оранку: на 50 м далі від городу, 22×20 м
const FIELD_ROAD := [Vector2(22.5, 5.0), Vector2(71.0, 5.0), Vector2(75.5, 2.2)]     # піщана дорога від навісу трактора до поля
const FIELD_ROAD_W := 3.0


func _near_plow(q: Vector2, w: float) -> bool:
	## Чи точка на полі під оранку або біля дороги до нього.
	if PLOW_FIELD.grow(w).has_point(q):
		return true
	for i in FIELD_ROAD.size() - 1:
		var a: Vector2 = FIELD_ROAD[i]
		var ba: Vector2 = FIELD_ROAD[i + 1] - a
		var t := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		if q.distance_to(a + ba * t) < FIELD_ROAD_W / 2.0 + w:
			return true
	return false
# навіс для техніки — на фермі під східним забором (x = −128): усе стоїть задом до забору за 2 м, носом на захід
const SHED := Vector3(-132.3, 0, 45.5)                 # трактор із плугом
const SHED_YAW := -PI / 2.0
const SHED_ROOF := Rect2(-141.2, 36.4, 11.8, 17.2)     # стовпи навісу: x, z, ширина, глибина
const TRAILER_PARK := Vector3(-131.5, 0, 50.0)


func _ok_tree(p: Vector3) -> bool:
	if _near_forest_road(Vector2(p.x, p.z), 4.5):
		return false                           # дорога до грибного лісу
	if ORCHARD.grow(1.0).has_point(Vector2(p.x, p.z)):
		return false                           # садок
	if WHEAT_N.grow(4.0).has_point(Vector2(p.x, p.z)):
		return false                           # пшеничне поле
	if Rect2(19.0, -20.0, 25.0, 30.0).has_point(Vector2(p.x, p.z)):
		return false                           # поле під оранку й навіс трактора
	if p.x > -26.0 and p.x < 22.0 and p.z > -20.0 and p.z < 9.0:
		return false                           # подвір'я й город
	if p.x > -22.0 and p.x < 26.0 and p.z > -47.0 and p.z <= -20.0:
		return false                           # стайня, корівник і пасовисько за двором
	if absf(p.x) < 7.0 and p.z > 5.0:
		return false                           # дорога на південь
	if Vector2(p.x - VILLAGE.x, p.z - VILLAGE.z).length() < 34.0:
		return false
	if absf(p.z - RIVER_Z) < RIVER_W:
		return false
	if BAZAAR_AREA.grow(3.0).has_point(Vector2(p.x, p.z)):
		return false                           # базар за річкою
	if pond_sd(p) < 5.0:
		return false
	if p.x > WHEAT.position.x - 4 and p.x < WHEAT.end.x + 4 and p.z > WHEAT.position.y - 4 and p.z < WHEAT.end.y + 6:
		return false
	if Vector2(p.x - MILL_HILL.x, p.z - MILL_HILL.z).length() < 24.0:
		return false                           # старий радіус — щоб решта лісу не перемішалась (новий — у _near_mill)
	if p.x < -26.0 and p.x > -125.0 and absf(p.z + 2.0) < 16.0:
		return false                           # старе місце аеродрому — щоб решта лісу не перемішалась
	if Vector2(p.x + 11.5, p.z - 13.0).length() < 8.0:
		return false                           # хата Тарасика
	if absf(p.x + 23.0) < 4.0 and p.z > 18.0 and p.z < 30.0:
		return false
	if Rect2(28.0, 44.0, 16.0, 14.0).has_point(Vector2(p.x, p.z)):
		return false                           # комбайн біля поля
	return true


func _thicken_far_forest(kinds: Array, heights: Dictionary, chunk: float, buckets: Dictionary) -> void:
	## Грибний ліс за пшеничним полем — густіший. Свій rng, щоб решта лісу стояла як була.
	var rf := RandomNumberGenerator.new()
	rf.seed = 4242
	var cell := 3.0
	var used := {}
	for t in trees:
		if t[1] < -310.0:
			used[Vector2i(floori(t[0] / cell), floori(t[1] / cell))] = true
	var added := 0
	var tries := 0
	while added < 260 and tries < 4000:
		tries += 1
		var p := Vector3(rf.randf_range(-200, 200), 0, rf.randf_range(-470, -320))
		var k: String = kinds[rf.randi() % kinds.size()]
		var hr: Array = heights[k]
		var ang := rf.randf() * TAU
		var th := rf.randf_range(hr[0], hr[1])
		if p.length() > LIMIT + 30.0 or not _ok_tree(p) or not Models.exists(k):
			continue
		var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
		if used.has(c):
			continue
		used[c] = true
		var key := "%d_%d_%s" % [floori(p.x / chunk), floori(p.z / chunk), k]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append([p, ang, th])
		trees.append([p.x, p.z])
		_obst.append([p.x, p.z, 0.5, 6.0])
		added += 1


func _thicken_east_forest(kinds: Array, heights: Dictionary, chunk: float, buckets: Dictionary) -> void:
	## Грибний ліс на сході — густіший (більше сосен). Дорога й галявина — без дерев. Свій rng — решта лісу як була.
	for key in buckets:
		var keep: Array = []
		for it in buckets[key]:
			var p0: Vector3 = it[0]
			if not _near_east_road(Vector2(p0.x, p0.z), 3.5):
				keep.append(it)
		buckets[key] = keep
	trees = trees.filter(func(t): return not _near_east_road(Vector2(t[0], t[1]), 3.5))
	_obst = _obst.filter(func(o): return o[3] != 6.0 or not _near_east_road(Vector2(o[0], o[1]), 3.5))
	var rf := RandomNumberGenerator.new()
	rf.seed = 4343
	var ek := ["pine_lo", "pine_lo", "pine_lo", "birch_a_lo", "birch_b_lo", "pine_lo"]
	var cell := 3.2
	var used := {}
	for t in trees:
		used[Vector2i(floori(t[0] / cell), floori(t[1] / cell))] = true
	var added := 0
	var tries := 0
	while added < 420 and tries < 6000:
		tries += 1
		var p := Vector3(rf.randf_range(78.0, 163.0), 0, rf.randf_range(-102.0, 72.0))
		var k: String = ek[rf.randi() % ek.size()]
		if not kinds.has(k):
			k = kinds[0]
		var hr: Array = heights[k]
		var ang := rf.randf() * TAU
		var th := rf.randf_range(hr[0], hr[1] + 1.5)
		var q := Vector2(p.x, p.z)
		if not in_east_forest(q, 1.0) or _near_east_road(q, 3.5) or not _ok_tree(p) or not Models.exists(k):
			continue
		if _near_plow(q, 4.0):
			continue
		var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
		if used.has(c):
			continue
		used[c] = true
		var key := "%d_%d_%s" % [floori(p.x / chunk), floori(p.z / chunk), k]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append([p, ang, th])
		trees.append([p.x, p.z])
		_obst.append([p.x, p.z, 0.5, 6.0])
		added += 1


func _make_east_road() -> void:
	## Ґрунтова дорога від поля під оранку до галявини в грибному лісі (з колією посередині).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := EAST_ROAD_W / 2.0
	for i in range(3, EAST_ROAD.size() - 1):
		var a: Vector2 = EAST_ROAD[i]
		var b: Vector2 = EAST_ROAD[i + 1]
		var sd := (b - a).normalized()
		var side := Vector2(sd.y, -sd.x) * hw
		var ext := sd * hw
		for v in [a - ext + side, b + side, a - ext - side, a - ext - side, b + side, b - side]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, 0.024 + i * 0.003, v.y))
	var road := MeshInstance3D.new()
	road.name = "east_forest_road"
	road.mesh = st.commit()
	road.material_override = Util.road_mat()
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	var rut := Util.road_mat(0.82)
	for i in range(3, EAST_ROAD.size() - 1):
		var a: Vector2 = EAST_ROAD[i]
		var b: Vector2 = EAST_ROAD[i + 1]
		var d := b - a
		var nrm := Vector2(d.normalized().y, -d.normalized().x)
		for s in [-0.75, 0.75]:
			var c: Vector2 = (a + b) / 2.0 + nrm * float(s)
			var box := Util.box(Vector3(0.45, 0.01, d.length()), rut, Vector3(c.x, 0.03 + i * 0.003, c.y))
			box.rotation.y = atan2(d.x, d.y)
			box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(box)
	# галявина в кінці дороги — витоптана
	var gl := Util.cyl(5.5, 5.5, 0.02, Util.road_mat(0.9), Vector3(EAST_FOREST_C.x, 0.02, EAST_FOREST_C.z))
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gl)


func _make_forest(rng: RandomNumberGenerator) -> void:
	var kinds := ["birch_b_lo", "pine_lo", "birch_a_lo", "pine_lo"]
	var heights := {"birch_b_lo": [7.0, 10.0], "pine_lo": [8.0, 12.0], "birch_a_lo": [6.5, 9.0]}
	var chunk := 40.0
	var buckets := {}               # (шматок, вид) → масив [позиція, кут, висота]
	var n := 0
	var tries := 0
	while n < 700 and tries < 9000:
		tries += 1
		var p: Vector3
		var r := rng.randf()
		var far := false
		if r < 0.16:
			var fa := rng.randf() * TAU
			var fd := sqrt(rng.randf()) * (FOREST_R + 3.0)
			p = FOREST_C + Vector3(cos(fa) * fd, 0, sin(fa) * fd)                      # Ліс (гриби й ягоди)
			far = true
		elif r < 0.5:
			p = Vector3(rng.randf_range(30, 160), 0, rng.randf_range(-90, 70))          # ліс на сході
		elif r < 0.75:
			p = Vector3(rng.randf_range(-170, 170), 0, rng.randf_range(112, 200))       # ліс за річкою
		elif r < 0.9:
			p = Vector3(rng.randf_range(-170, -40), 0, rng.randf_range(-130, -5))       # гай на заході
		else:
			p = Vector3(rng.randf_range(-200, 200), 0, rng.randf_range(-470, -320))     # за пшеничним полем (зміщено на 300 м, ширше) — грибний ліс
			far = true
		if p.length() > (LIMIT + 30.0 if far else ZONE_LIMIT + 30.0) or not _ok_tree(p):
			continue
		var k: String = kinds[rng.randi() % kinds.size()]
		if not Models.exists(k):
			continue
		var hr: Array = heights[k]
		var ang := rng.randf() * TAU
		var th := rng.randf_range(hr[0], hr[1])
		if _near_mill(p):
			continue                               # після rng — решта лісу стоїть як була
		if FARM_AREA.has_point(Vector2(p.x, p.z)) or FARM_FENCE.grow(1.5).has_point(Vector2(p.x, p.z)):
			continue                               # ферма за ставком і її забір (після rng — решта лісу як була)
		if _near_plow(Vector2(p.x, p.z), 4.0):
			continue                               # поле під оранку й дорога до нього (після rng)
		if _in_village_garden(p, 3.0):
			continue                               # город і копиця за хатами села (після rng)
		var key := "%d_%d_%s" % [floori(p.x / chunk), floori(p.z / chunk), k]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append([p, ang, th])
		trees.append([p.x, p.z])
		_obst.append([p.x, p.z, 0.5, 6.0])
		n += 1
	_thicken_far_forest(kinds, heights, chunk, buckets)
	_thicken_east_forest(kinds, heights, chunk, buckets)
	# зразок кожного виду: меш і як він стоїть у моделі
	var proto := {}
	for k in kinds:
		if proto.has(k) or not Models.exists(k):
			continue
		var h := Models.spawn(self, k, 1.0)
		var mi: MeshInstance3D = h.find_children("*", "MeshInstance3D", true, false)[0]
		proto[k] = [mi.mesh, h.global_transform.affine_inverse() * mi.global_transform, mi.get_active_material(0)]
		h.queue_free()
	for key in buckets:
		var ks := String(key)
		var k := ks.substr(ks.find("_", ks.find("_") + 1) + 1)
		var pr: Array = proto[k]
		var list: Array = buckets[key]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pr[0]
		mm.instance_count = list.size()
		for i in list.size():
			var it: Array = list[i]
			var tr := Transform3D(Basis(Vector3.UP, float(it[1])).scaled(Vector3.ONE * float(it[2])), it[0])
			mm.set_instance_transform(i, tr * (pr[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = pr[2]
		mmi.visibility_range_end = 170.0
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mmi)


# ------------------------------------------------------------------ аеродром: ангар і злітна смуга
var hangar_doors: Array = []                  # [лівий, правий]
var _hangar_tw: Tween
var hangar_open := false
var hangar_node: Node3D
var hangar_btns: Array = []                   # кнопки воріт на задній стіні (зсередини й ззовні)
var hangar_lamps: Array = []
const HANGAR_HX := 5.0                        # пів-довжини ангара (від центру до воріт і до задньої стіни)
const HANGAR_HZ := 5.8                        # пів-ширини
const HANGAR_BTN_Z := -4.2                    # де на задній стіні кнопка (збоку, щоб не заважав хвіст літака)


static func air_local(p: Vector3) -> Vector2:
	## Точка світу → система аеродрому (x — від воріт до задньої стіни, y — убік).
	var d := p - HANGAR
	return Vector2(d.dot(AIR_X), d.dot(AIR_Z))


static func air_world(lx: float, lz: float) -> Vector3:
	## Точка в системі аеродрому → світ.
	return HANGAR + AIR_X * lx + AIR_Z * lz


func _make_airfield() -> void:
	var hg := Node3D.new()
	hg.name = "hangar"
	hg.position = HANGAR
	hg.rotation.y = AIR_ROT
	add_child(hg)
	hangar_node = hg
	var metal := Util.mat(Color(0.74, 0.76, 0.72), 0.55)
	var metal2 := Util.mat(Color(0.62, 0.66, 0.62), 0.55)
	var roof_m := Util.mat(Color(0.58, 0.36, 0.28), 0.7)
	var floor_m := Util.mat(Color(0.6, 0.6, 0.58), 0.95)
	const HX := 5.0          # пів-довжини (уздовж x)
	const HZ := 5.8          # пів-ширини
	const WH := 3.6          # висота стін
	hg.add_child(Util.box(Vector3(HX * 2.0, 0.06, HZ * 2.0), floor_m, Vector3(0, 0.03, 0)))
	# стіни: задня й бокові (ребристі — смужками двох відтінків)
	for i in 8:
		var z := -HZ + (i + 0.5) * HZ * 2.0 / 8.0
		hg.add_child(Util.box(Vector3(0.14, WH, HZ * 2.0 / 8.0), metal if i % 2 == 0 else metal2, Vector3(HX, WH / 2.0, z)))
	for sgn in [-1.0, 1.0]:
		for i in 7:
			var x := -HX + (i + 0.5) * HX * 2.0 / 7.0
			hg.add_child(Util.box(Vector3(HX * 2.0 / 7.0, WH, 0.14), metal if i % 2 == 0 else metal2, Vector3(x, WH / 2.0, sgn * HZ)))
		# віконця збоку
		for x in [-2.5, 0.0, 2.5]:
			hg.add_child(Util.box(Vector3(1.2, 0.6, 0.16), Util.mat(Color(0.55, 0.75, 0.9), 0.2), Vector3(x, 2.7, sgn * HZ)))
	# дах-арка (з дощок по дузі) і фронтони спереду й ззаду
	var n := 14
	for i in n:
		var t0 := -PI / 2.0 + PI * i / n
		var t1 := -PI / 2.0 + PI * (i + 1) / n
		var p0 := Vector2(HZ * 1.03 * sin(t0), WH + 2.4 * cos(t0))
		var p1 := Vector2(HZ * 1.03 * sin(t1), WH + 2.4 * cos(t1))
		var mid := (p0 + p1) / 2.0
		var seg := Util.box(Vector3(HX * 2.0 + 0.5, 0.12, p0.distance_to(p1) + 0.05), roof_m, Vector3(0, mid.y, mid.x))
		seg.rotation.x = -atan2(p1.y - p0.y, p1.x - p0.x)
		hg.add_child(seg)
		var gh := mid.y - WH
		if gh > 0.05:
			for sx in [-HX, HX]:
				hg.add_child(Util.box(Vector3(0.12, gh, p0.distance_to(p1) + 0.02), metal2, Vector3(sx, WH + gh / 2.0, mid.x)))
	# над воротами — балка й напис
	hg.add_child(Util.box(Vector3(0.3, 0.3, HZ * 2.0 + 0.2), Util.mat(Color(0.85, 0.7, 0.2), 0.6), Vector3(-HX - 0.05, WH - 0.1, 0)))
	var lb := Label3D.new()
	lb.text = "АНГАР"
	lb.font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	lb.font_size = 160
	lb.pixel_size = 0.006
	lb.modulate = Color(0.85, 0.2, 0.15)
	lb.outline_size = 0
	lb.position = Vector3(-HX - 0.15, WH + 1.0, 0)
	lb.rotation.y = -PI / 2.0
	hg.add_child(lb)
	# розсувні ворота (дві стулки)
	var door_m := Util.mat(Color(0.35, 0.5, 0.62), 0.5)
	for sgn in [-1.0, 1.0]:
		var d := Node3D.new()
		d.position = Vector3(-HX - 0.22, 0, sgn * HZ / 2.0)
		hg.add_child(d)
		d.add_child(Util.box(Vector3(0.1, WH - 0.25, HZ), door_m, Vector3(0, (WH - 0.25) / 2.0, 0)))
		for k in 3:
			d.add_child(Util.box(Vector3(0.12, 0.08, HZ - 0.1), Util.mat(Color(0.9, 0.85, 0.75), 0.6), Vector3(-0.02, 0.6 + k * 1.1, 0)))
		d.set_meta("closed_z", sgn * HZ / 2.0)
		d.set_meta("open_z", sgn * (HZ * 1.5 + 0.3))
		hangar_doors.append(d)
	# кнопка воріт на задній стіні на висоті 1 м — зсередини (side −1) і ззовні (side +1)
	var font: Font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	for side in [-1.0, 1.0]:
		var pn := Node3D.new()
		pn.name = "hangar_btn_in" if side < 0.0 else "hangar_btn_out"
		pn.position = Vector3(HX + side * 0.09, 1.0, HANGAR_BTN_Z)
		hg.add_child(pn)
		pn.add_child(Util.box(Vector3(0.04, 0.34, 0.24), Util.mat(Color(0.95, 0.78, 0.15), 0.5)))
		var bt := Util.cyl(0.055, 0.055, 0.05, Util.mat(Color(0.85, 0.12, 0.1), 0.35), Vector3(side * 0.035, 0, 0), Vector3(0, 0, PI / 2.0))
		bt.set_meta("rest_x", side * 0.035)
		bt.set_meta("side", side)
		pn.add_child(bt)
		hangar_btns.append(bt)
		var lamp := Util.box(Vector3(0.03, 0.05, 0.05), Util.mat(Color(0.9, 0.15, 0.1), 0.4, 0.0, Color(0.9, 0.15, 0.1), 1.5), Vector3(side * 0.03, 0.11, 0))
		pn.add_child(lamp)
		hangar_lamps.append(lamp)
		var bl := Label3D.new()
		bl.text = "ВОРОТА"
		bl.font = font
		bl.font_size = 48
		bl.pixel_size = 0.003
		bl.modulate = Color(0.15, 0.15, 0.15)
		bl.outline_size = 0
		bl.position = Vector3(side * 0.03, 0.24, 0)
		bl.rotation.y = side * PI / 2.0
		pn.add_child(bl)
		var pa := Util.pick_area("hangar_btn", Vector3(0.3, 0.5, 0.5), Vector3.ZERO)
		pa.set_meta("side", side)
		pn.add_child(pa)
	# колесовідбійники-перешкоди для тих, хто ходить
	for i in 7:
		var o := air_world(HX, -HZ + i * HZ * 2.0 / 6.0)
		_obst.append([o.x, o.z, 0.9, 4.0])
	for sgn in [-1.0, 1.0]:
		for i in 6:
			var o := air_world(-HX + i * HX * 2.0 / 5.0, sgn * HZ)
			_obst.append([o.x, o.z, 0.9, 4.0])
	houses.append([HANGAR.x, HANGAR.z])
	# злітна смуга: темна доріжка, біла пунктирна осьова, «зебра» на початку й у кінці
	var strip := Node3D.new()
	strip.name = "runway"
	strip.position = HANGAR
	strip.rotation.y = AIR_ROT
	add_child(strip)
	var ra := Vector3(-11.0 + 4.0, 0, 0)               # у системі аеродрому
	var rb := Vector3(-79.0 - 3.0, 0, 0)
	var len := ra.distance_to(rb)
	var c := (ra + rb) / 2.0
	var asphalt := Util.mat(Color(0.36, 0.37, 0.38), 0.95)
	var white := Util.mat(Color(0.95, 0.95, 0.92), 0.8)
	strip.add_child(Util.box(Vector3(len, 0.04, 8.0), asphalt, Vector3(c.x, 0.02, c.z)))
	strip.add_child(Util.box(Vector3(5.0, 0.04, 4.0), asphalt, Vector3(-7.0, 0.02, 0)))
	var x := ra.x - 10.0
	while x > rb.x + 10.0:
		strip.add_child(Util.box(Vector3(3.0, 0.045, 0.25), white, Vector3(x, 0.025, c.z)))
		x -= 6.0
	for end in [ra.x - 3.0, rb.x + 3.0]:
		for k in 6:
			strip.add_child(Util.box(Vector3(3.5, 0.045, 0.4), white, Vector3(end, 0.025, c.z - 2.8 + k * 1.12)))
	for e in strip.get_children():
		(e as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# вітровказ (смугастий конус на щоглі)
	var ws := Node3D.new()
	ws.position = air_world(-11.0 - 6.0, -7.5)
	ws.rotation.y = AIR_ROT
	add_child(ws)
	ws.add_child(Util.cyl(0.05, 0.07, 4.2, Util.mat(Color(0.9, 0.9, 0.9), 0.6), Vector3(0, 2.1, 0)))
	for k in 3:
		var cone := Util.cyl(0.32 - k * 0.07, 0.25 - k * 0.07, 0.5, Util.mat(Color(0.95, 0.45, 0.1) if k % 2 == 0 else Color(0.95, 0.95, 0.95), 0.7), Vector3(0.3 + k * 0.5, 4.0, 0))
		cone.rotation.z = PI / 2.0
		ws.add_child(cone)
	_obst.append([ws.position.x, ws.position.z, 0.3, 4.0])
	_make_air_road()
	_make_airfield_trees()


const FARM_DRIVE := [Vector2(FARM_GATE_S_X, 83.0), Vector2(FARM_GATE_S_X, 95.0)]    # заїзд на ферму від дороги біля річки


func _near_air_road(q: Vector2, w: float) -> bool:
	var fa: Vector2 = FARM_DRIVE[0]
	var fb: Vector2 = FARM_DRIVE[1] - fa
	if q.distance_to(fa + fb * clampf((q - fa).dot(fb) / fb.dot(fb), 0.0, 1.0)) < w:
		return true
	for i in AIR_ROAD.size() - 1:
		var a: Vector2 = AIR_ROAD[i]
		var ba: Vector2 = AIR_ROAD[i + 1] - a
		var t := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		if q.distance_to(a + ba * t) < w:
			return true
	return false


func _make_air_road() -> void:
	## Піщана дорога від головної дороги села вздовж річки до воріт ангара.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := AIR_ROAD_W / 2.0
	for i in AIR_ROAD.size() - 1:
		var a: Vector2 = AIR_ROAD[i]
		var b: Vector2 = AIR_ROAD[i + 1]
		var sd := (b - a).normalized()
		var side := Vector2(sd.y, -sd.x) * hw
		var ext := sd * (hw if i > 0 else 0.0)              # перекриття на зламі, щоб не було щілини
		for v in [a - ext + side, b + side, a - ext - side, a - ext - side, b + side, b - side]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, 0.02 + i * 0.003, v.y))
	var sand := Util.road_mat()
	var road := MeshInstance3D.new()
	road.name = "airfield_road"
	road.mesh = st.commit()
	road.material_override = sand
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)


func _make_airfield_trees() -> void:
	## Дерева довкола аеродрому: ряди вздовж смуги й за ангаром (західний край — відкритий для зльоту й посадки).
	var rng := RandomNumberGenerator.new()
	rng.seed = 251
	var kinds := ["pine_lo", "birch_b_lo", "birch_a_lo"]
	var heights := {"birch_b_lo": [7.0, 10.0], "pine_lo": [8.0, 12.0], "birch_a_lo": [6.5, 9.0]}
	var pts := []
	var lpts := []                                         # у системі аеродрому
	var x := 14.0
	while x >= -79.0 - 6.0:
		lpts.append(Vector2(x, -15.0))                      # ряд з одного боку смуги
		if absf(x - (-11.0 + 2.5)) > 4.0:
			lpts.append(Vector2(x, 9.0))                    # ряд з другого боку
		x -= 8.0
	var z := -15.0
	while z <= 9.0:
		lpts.append(Vector2(15.0, z))                       # за ангаром (до річки)
		z += 6.0
	for lq in lpts:
		var w := air_world(lq.x, lq.y)
		pts.append(Vector2(w.x, w.z))
	var n := 0
	for q in pts:
		if _near_air_road(q, 3.5):
			continue
		var k: String = kinds[n % kinds.size()]
		var hr: Array = heights[k]
		var m := Models.spawn(self, k, rng.randf_range(hr[0], hr[1]))
		if m == null:
			continue
		n += 1
		m.name = "airfield_tree_%d" % n
		m.position = Vector3(q.x, 0, q.y)
		m.rotation.y = rng.randf() * TAU
		trees.append([q.x, q.y])
		_obst.append([q.x, q.y, 0.5, 6.0])


func set_hangar_door(open: bool) -> void:
	if hangar_open == open and _hangar_tw == null:
		return
	hangar_open = open
	if _hangar_tw:
		_hangar_tw.kill()
	_hangar_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	for d in hangar_doors:
		_hangar_tw.tween_property(d, "position:z", float(d.get_meta("open_z" if open else "closed_z")), 2.2)
	_hangar_tw.chain().tween_callback(func(): _hangar_tw = null)
	var au = get_node_or_null("/root/Main/Audio")
	if au and au.has_method("play_at") and hangar_doors.size() > 0:
		au.play_at("door_open", hangar_doors[0], -4.0, 0.6)
	var lc := Color(0.2, 0.9, 0.25) if open else Color(0.9, 0.15, 0.1)
	for l in hangar_lamps:
		(l as MeshInstance3D).material_override = Util.mat(lc, 0.4, 0.0, lc, 1.5)


func press_hangar_btn(side: float) -> void:
	## Ніка натиснула кнопку на задній стіні: ворота відчиняються (і стоять відчинені) або зачиняються.
	for b in hangar_btns:
		if float(b.get_meta("side")) != side:
			continue
		var rx: float = b.get_meta("rest_x")
		var tw := create_tween()
		tw.tween_property(b, "position:x", rx - side * 0.025, 0.08)
		tw.tween_property(b, "position:x", rx, 0.15)
	var au = get_node_or_null("/root/Main/Audio")
	if au and au.has_method("play_at") and hangar_btns.size() > 0:
		au.play_at("pop", hangar_btns[0], -6.0, 1.6)
	set_hangar_door(not hangar_open)


static func _in_hangar_l(q: Vector2) -> bool:
	return q.x > -HANGAR_HX - 0.25 and q.x < HANGAR_HX and absf(q.y) < HANGAR_HZ


static func in_hangar(p: Vector3) -> bool:
	return _in_hangar_l(air_local(p))


func hangar_keep(old: Vector3, p: Vector3) -> Vector3:
	## У ангар і з ангара — лише крізь відчинені ворота (не крізь зачинені стулки й стіни).
	var a := air_local(old)
	var b := air_local(p)
	if absf(a.x) > 9.0 or absf(a.y) > 9.0:
		return p
	if _in_hangar_l(a) == _in_hangar_l(b):
		return p
	if hangar_open and _hangar_tw == null and minf(a.x, b.x) < -HANGAR_HX + 0.8 and absf(b.y) < HANGAR_HZ - 0.3:
		return p
	return Vector3(old.x, p.y, old.z)


func is_blocked(p: Vector3, r: float) -> bool:
	## Чи заважає щось сісти літаку в точці p (дерева, хати, вода, подвір'я, поле, пагорб вітряка).
	if p.x > -27.0 and p.x < 23.0 and p.z > -35.0 and p.z < 10.0:
		return true
	if Vector2(p.x - VILLAGE.x, p.z - VILLAGE.z).length() < 34.0:
		return true
	if p.x > WHEAT.position.x - 2 and p.x < WHEAT.end.x + 2 and p.z > WHEAT.position.y - 2 and p.z < WHEAT.end.y + 2:
		return true
	if Vector2(p.x - MILL_HILL.x, p.z - MILL_HILL.z).length() < MILL_HILL_R + 3.0:
		return true
	if BAZAAR_AREA.grow(4.0).has_point(Vector2(p.x, p.z)):
		return true
	if WHEAT_N.grow(2.0).has_point(Vector2(p.x, p.z)):
		return true
	for o in _obst:
		if Vector2(p.x - o[0], p.z - o[1]).length() < float(o[2]) + r:
			return true
	return false


# ------------------------------------------------------------------ великий базар за річкою (з Blender)
const BAZAAR_AREA := Rect2(-74.0, 106.0, 141.0, 134.0)
var bazaar: Node3D
var village_huts: Array = []     # [позиція, поворот (рад), зелена?] — хати старого села, ставить bazaar.gd


func _make_bazaar() -> void:
	bazaar = preload("res://scripts/bazaar.gd").new()
	bazaar.name = "Bazaar"
	add_child(bazaar)
	bazaar.village_spots = village_huts
	bazaar.build()
	for h in bazaar.map_houses:
		houses.append(h)


# ------------------------------------------------------------------ старі ларки (більше не ставимо)
const STALLS := [
	["bread", "Хліб", Vector3(-8.0, 0, -9.5), Color(0.85, 0.35, 0.25), "Паляниці, калачі й бублики — ще теплі!"],
	["meat", "М'ясо", Vector3(8.0, 0, -9.5), Color(0.75, 0.2, 0.25), "Ковбаски, сало й шинка — до борщу!"],
	["veg", "Овочі", Vector3(-9.5, 0, 8.5), Color(0.3, 0.6, 0.3), "Морква, буряк, капуста, гарбузи й яблучка."],
	["honey", "Мед", Vector3(4.5, 0, -11.5), Color(0.95, 0.65, 0.15), "Липовий і гречаний мед — солодкий-пресолодкий."],
	["pots", "Глечики", Vector3(11.0, 0, 5.0), Color(0.3, 0.45, 0.8), "Глиняні глечики, макітри й мисочки."],
]


const EXTRA_BUILDINGS := [
	# [модель, висота, позиція, поворот-поправка (куди дивиться фасад моделі), радіус перешкоди, підпис]
	# котедж біля площі прибрано — у селі лишились тільки хати
]


func _make_extra_buildings() -> void:
	## Будиночки й кіоски з моделей (Gemini → 3D): ставимо фасадом до площі.
	for b in EXTRA_BUILDINGS:
		var m := Models.spawn(self, b[0], b[1])
		if m == null:
			continue
		m.position = b[2]
		var to: Vector3 = VILLAGE - (b[2] as Vector3)
		m.rotation.y = atan2(to.x, to.z) + float(b[3])
		_obst.append([m.position.x, m.position.z, b[4], 3.0])
		houses.append([m.position.x, m.position.z])
		if String(b[5]) != "":
			m.set_meta("stall", [String(b[5]).split(":")[0].split(" —")[0], b[5]])
			m.add_child(Util.pick_area("stall", Vector3(4.0, 3.0, 4.0), Vector3(0, 1.5, 0)))


func _make_stalls() -> void:
	var wood := Util.mat(Color(0.55, 0.38, 0.22), 0.9)
	var dark := Util.mat(Color(0.4, 0.27, 0.16), 0.9)
	var white := Util.mat(Color(0.96, 0.94, 0.88), 0.9)
	var font: Font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	for st in STALLS:
		var n := Node3D.new()
		n.name = "stall_" + String(st[0])
		n.position = VILLAGE + (st[2] as Vector3)
		var to: Vector3 = VILLAGE - n.position
		n.rotation.y = atan2(to.x, to.z)          # прилавком до фонтану
		add_child(n)
		var col: Color = st[3]
		var stripe := Util.mat(col, 0.85)
		# прилавок і стовпчики
		n.add_child(Util.box(Vector3(2.4, 0.9, 0.9), wood, Vector3(0, 0.45, 0.35)))
		n.add_child(Util.box(Vector3(2.5, 0.06, 1.0), dark, Vector3(0, 0.93, 0.35)))
		for sx in [-1.15, 1.15]:
			for sz in [-0.15, 0.85]:
				n.add_child(Util.box(Vector3(0.08, 2.3, 0.08), dark, Vector3(sx, 1.15, sz)))
		# смугастий навіс
		for k in 8:
			var a := Util.box(Vector3(0.32, 0.04, 1.5), stripe if k % 2 == 0 else white, Vector3(-1.12 + k * 0.32, 2.35, 0.4))
			a.rotation.x = 0.28
			n.add_child(a)
		for k in 8:
			var fr := Util.box(Vector3(0.32, 0.18, 0.03), stripe if k % 2 == 0 else white, Vector3(-1.12 + k * 0.32, 2.07, 1.12))
			n.add_child(fr)
		# вивіска
		var lb := Label3D.new()
		lb.text = st[1]
		lb.font = font
		lb.font_size = 72
		lb.pixel_size = 0.005
		lb.modulate = Color(0.25, 0.15, 0.08)
		lb.outline_size = 10
		lb.outline_modulate = Color(1, 0.97, 0.85)
		lb.position = Vector3(0, 2.62, 0.55)
		n.add_child(lb)
		_stall_goods(n, String(st[0]))
		n.set_meta("stall", [st[1], st[4]])
		n.add_child(Util.pick_area("stall", Vector3(2.6, 2.6, 1.6), Vector3(0, 1.3, 0.4)))
		_obst.append([n.position.x, n.position.z, 1.4, 2.5])


func _stall_goods(n: Node3D, kind: String) -> void:
	var y := 0.96
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	match kind:
		"bread":
			var crust := Util.mat(Color(0.78, 0.5, 0.22), 0.8)
			var light := Util.mat(Color(0.9, 0.68, 0.36), 0.8)
			for i in 6:
				n.add_child(Util.sphere(0.16, crust if i % 2 == 0 else light, Vector3(-0.9 + i * 0.36, y + 0.08, 0.35 + rng.randf_range(-0.15, 0.15)), Vector3(1.3, 0.6, 1.0)))
			for i in 3:
				var bub := Util.mesh(TorusMesh.new(), light, Vector3(-0.6 + i * 0.6, y + 0.35, 0.05), Vector3(90, 0, 0), Vector3(0.22, 0.22, 0.22))
				n.add_child(bub)
		"meat":
			var red := Util.mat(Color(0.75, 0.3, 0.3), 0.7)
			var pink := Util.mat(Color(0.95, 0.8, 0.75), 0.7)
			var saus := Util.mat(Color(0.55, 0.22, 0.15), 0.6)
			for i in 4:
				n.add_child(Util.box(Vector3(0.36, 0.14, 0.26), red if i % 2 == 0 else pink, Vector3(-0.8 + i * 0.52, y + 0.07, 0.4)))
			for i in 6:
				var c := Util.capsule(0.045, 0.45, saus, Vector3(-0.9 + i * 0.36, 1.75, 0.0))
				n.add_child(c)
		"veg":
			var crate := Util.mat(Color(0.6, 0.45, 0.28), 0.9)
			var cols := [Color(0.95, 0.5, 0.1), Color(0.55, 0.12, 0.25), Color(0.5, 0.75, 0.3), Color(0.85, 0.2, 0.15)]
			for i in 4:
				var cx := -0.85 + i * 0.57
				n.add_child(Util.box(Vector3(0.5, 0.16, 0.5), crate, Vector3(cx, y + 0.08, 0.35)))
				var m := Util.mat(cols[i], 0.7)
				for k in 5:
					n.add_child(Util.sphere(0.07, m, Vector3(cx + rng.randf_range(-0.16, 0.16), y + 0.2, 0.35 + rng.randf_range(-0.16, 0.16))))
			n.add_child(Util.sphere(0.32, Util.mat(Color(0.95, 0.55, 0.15), 0.7), Vector3(1.6, 0.28, 0.6), Vector3(1.0, 0.8, 1.0)))
		"honey":
			var jar := Util.mat(Color(0.95, 0.65, 0.12), 0.25)
			var lid := Util.mat(Color(0.85, 0.2, 0.15), 0.6)
			for i in 7:
				var x := -0.95 + i * 0.32
				var zz := 0.25 + (i % 2) * 0.25
				n.add_child(Util.cyl(0.09, 0.09, 0.22, jar, Vector3(x, y + 0.11, zz)))
				n.add_child(Util.cyl(0.095, 0.095, 0.04, lid, Vector3(x, y + 0.24, zz)))
		"pots":
			var clay := Util.mat(Color(0.72, 0.4, 0.25), 0.8)
			var blue := Util.mat(Color(0.3, 0.45, 0.75), 0.6)
			for i in 5:
				var x := -0.9 + i * 0.45
				var m2: Material = clay if i % 2 == 0 else blue
				n.add_child(Util.sphere(0.15, m2, Vector3(x, y + 0.15, 0.35), Vector3(1.0, 1.1, 1.0)))
				n.add_child(Util.cyl(0.05, 0.07, 0.14, m2, Vector3(x, y + 0.34, 0.35)))
			n.add_child(Util.sphere(0.3, clay, Vector3(-1.55, 0.3, 0.6), Vector3(1.0, 1.0, 1.0)))


# ------------------------------------------------------------------ пташки в небі
var sky_birds: Array = []          # [вузол, ліве крило, праве крило, зграя, фаза]
var _flocks: Array = []            # [центр, радіус, висота, швидкість, кут]


func _make_sky_birds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var dark := Util.mat(Color(0.18, 0.16, 0.15), 0.9)
	var light := Util.mat(Color(0.95, 0.95, 0.95), 0.9)
	var flocks := [[Vector3(-10, 0, 20), 45.0, 42.0, 0.09, dark, 7], [Vector3(30, 0, 60), 35.0, 38.0, -0.12, light, 5],
		[Vector3(-60, 0, -30), 55.0, 50.0, 0.07, dark, 8], [Vector3(0, 0, -5), 22.0, 34.0, 0.15, dark, 3]]
	for fi in flocks.size():
		var f: Array = flocks[fi]
		_flocks.append([f[0], f[1], f[2], f[3], rng.randf() * TAU])
		for k in int(f[5]):
			var b := Node3D.new()
			add_child(b)
			b.scale = Vector3.ONE * 2.2
			b.add_child(Util.sphere(0.12, f[4], Vector3.ZERO, Vector3(0.8, 0.7, 1.8)))
			var wl := Node3D.new()
			var wr := Node3D.new()
			b.add_child(wl)
			b.add_child(wr)
			var bl := Util.box(Vector3(0.6, 0.03, 0.22), f[4], Vector3(-0.3, 0, 0))
			var br := Util.box(Vector3(0.6, 0.03, 0.22), f[4], Vector3(0.3, 0, 0))
			bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			br.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wl.add_child(bl)
			wr.add_child(br)
			var off := Vector3(rng.randf_range(-4, 4), rng.randf_range(-1.5, 1.5), rng.randf_range(-4, 4))
			sky_birds.append([b, wl, wr, fi, rng.randf() * TAU, off])


func _sky_birds_step(delta: float) -> void:
	var night := Game.is_night()
	for f in _flocks:
		f[4] = float(f[4]) + float(f[3]) * delta
	for it in sky_birds:
		var b: Node3D = it[0]
		b.visible = not night
		if night:
			continue
		var f: Array = _flocks[it[3]]
		var a: float = f[4]
		var c: Vector3 = f[0]
		var r: float = f[1]
		var off: Vector3 = it[5]
		var p := c + Vector3(cos(a) * r, float(f[2]) + sin(a * 3.0 + float(it[4])) * 1.2, sin(a) * r) + off
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(float(f[3]))
		b.position = p
		b.rotation.y = atan2(dir.x, dir.z)
		var ph: float = _t * 9.0 + float(it[4])
		var flap := sin(ph) * 0.6 if fmod(_t + float(it[4]), 6.0) < 3.5 else 0.12      # махає й ковзає
		(it[1] as Node3D).rotation.z = flap
		(it[2] as Node3D).rotation.z = -flap



static func apply_view_ranges(root: Node, max_size := 14.0, near := 60.0) -> void:
	## Дрібні речі (хати, ларки, лавки, гриби…) телефон не малює, коли вони далеко від камери.
	## Великі (земля, річка, дороги, гори) — не чіпаємо.
	for g in root.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.visibility_range_end > 0.0 or mi.mesh == null:
			continue
		var sz := mi.mesh.get_aabb().size * mi.global_transform.basis.get_scale()
		var dim := maxf(sz.x, maxf(sz.y, sz.z))
		if dim <= 0.0 or dim > max_size:
			continue
		mi.visibility_range_end = clampf(near + dim * 10.0, near, 170.0)
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


# ------------------------------------------------------------------ бункер для зерна на фермі й засік біля млина
const WHEAT_PLOW := Rect2(-27.0, -104.5, 14.5, 33.5)  # східна частина пшеничного поля (за дорогою) — її оре тракторист після обмолоту
const BUNKER := Vector3(-152.5, 0, 43.2)              # бункер на ніжках (на захід від навісу), жолоб — на південь, до проїзду
const BUNKER_SPOUT := Vector3(-152.5, 3.2, 46.8)      # кінець жолоба над проїздом (z = 46.8): сюди підставляють причіп
const BUNKER_PIT := Vector3(-146.5, 0, 46.8)          # приймальна яма з ґраткою на проїзді: сюди висипають зерно з причепа
const MILL_BIN_SIDE := 5.2                             # засік — збоку млина (від осі дороги вбік), трохи нижче за схилом
const MILL_BIN_ALONG := 1.0
var bunker_stream: CPUParticles3D
var mill_bin_grain: MeshInstance3D


func mill_dirs() -> Array:
	## [центр пагорба, униз уздовж дороги, убік (до засіку)].
	var c := Vector3(MILL_HILL.x, 0, MILL_HILL.z)
	var dv := Vector3(MILL_DIR.x, 0, MILL_DIR.y)
	return [c, dv, Vector3(dv.z, 0, -dv.x)]


func mill_bin_pos() -> Vector3:
	var m := mill_dirs()
	var p: Vector3 = m[0] + m[2] * MILL_BIN_SIDE + m[1] * MILL_BIN_ALONG
	p.y = Util.hill_y(p)
	return p


func _make_grain_bunker() -> void:
	## Металевий бункер на чотирьох ніжках: знизу лійка й похилий жолоб над проїздом (набирати зерно в причіп),
	## збоку — ківшовий підйомник від приймальної ями з ґраткою (висипати зерно з причепа).
	var n := Node3D.new()
	n.name = "GrainBunker"
	add_child(n)
	var metal := Util.mat(Color(0.66, 0.68, 0.7), 0.45, 0.6)
	var dark := Util.mat(Color(0.32, 0.34, 0.36), 0.6, 0.5)
	var rust := Util.mat(Color(0.55, 0.32, 0.2), 0.8)
	var b := BUNKER
	var leg_h := 4.6
	for sx in [-1.2, 1.2]:
		for sz in [-1.2, 1.2]:
			n.add_child(Util.box(Vector3(0.2, leg_h, 0.2), dark, b + Vector3(sx, leg_h * 0.5, sz)))
			Obstacles.add_outer(b.x + sx, b.z + sz, 0.3, leg_h)
	# розпірки між ніжками
	for sz in [-1.2, 1.2]:
		n.add_child(Util.box(Vector3(2.4, 0.12, 0.12), dark, b + Vector3(0, 1.6, sz)))
	for sx in [-1.2, 1.2]:
		n.add_child(Util.box(Vector3(0.12, 0.12, 2.4), dark, b + Vector3(sx, 1.6, 0)))
	n.add_child(Util.cyl(1.45, 0.28, 1.2, metal, b + Vector3(0, 4.4, 0)))           # лійка
	n.add_child(Util.cyl(1.45, 1.45, 3.0, metal, b + Vector3(0, 6.5, 0)))           # корпус
	n.add_child(Util.cyl(0.12, 1.6, 0.9, rust, b + Vector3(0, 8.45, 0)))            # дашок
	for y in [5.2, 6.5, 7.8]:
		n.add_child(Util.cyl(1.48, 1.48, 0.06, dark, b + Vector3(0, y, 0)))         # обручі
	# похилий жолоб від лійки до проїзду, на кінці — коротка труба донизу
	var a := b + Vector3(0, 3.8, 0)
	var e := BUNKER_SPOUT + Vector3(0, 0.25, 0)
	var dz := e.z - a.z
	var dy := a.y - e.y
	var ln := sqrt(dz * dz + dy * dy)
	n.add_child(Util.box(Vector3(0.42, 0.1, ln), dark, (a + e) * 0.5, Vector3(atan2(dy, dz), 0, 0)))
	for sx in [-0.21, 0.21]:
		n.add_child(Util.box(Vector3(0.04, 0.22, ln), dark, (a + e) * 0.5 + Vector3(sx, 0.1, 0), Vector3(atan2(dy, dz), 0, 0)))
	n.add_child(Util.cyl(0.14, 0.14, 0.45, dark, BUNKER_SPOUT + Vector3(0, 0.1, 0)))
	bunker_stream = Util.grain_stream()
	bunker_stream.position = BUNKER_SPOUT - Vector3(0, 0.15, 0)
	n.add_child(bunker_stream)
	# ківшовий підйомник збоку бункера (від ями — під землею) і труба зверху в бункер
	var ex := b + Vector3(1.95, 0, 0)
	n.add_child(Util.box(Vector3(0.5, 9.2, 0.5), metal, ex + Vector3(0, 4.6, 0)))
	n.add_child(Util.box(Vector3(0.7, 0.6, 0.7), dark, ex + Vector3(0, 9.4, 0)))
	n.add_child(Util.box(Vector3(1.9, 0.25, 0.25), dark, b + Vector3(1.0, 8.95, 0), Vector3(0, 0, -0.25)))
	n.add_child(Util.box(Vector3(0.9, 0.8, 0.9), dark, ex + Vector3(0, 0.4, 0)))     # мотор підйомника
	Obstacles.add_outer(ex.x, ex.z, 0.6, 9.0)
	# приймальна яма: бетонна обв'язка й темна ґратка (по ній можна проїхати)
	var conc := Util.mat(Color(0.6, 0.6, 0.57), 0.95)
	var grate := Util.mat(Color(0.18, 0.18, 0.19), 0.7, 0.5)
	var pit := BUNKER_PIT
	for e2 in [[Vector3(0, 0.05, -1.3), Vector3(2.8, 0.1, 0.2)], [Vector3(0, 0.05, 1.3), Vector3(2.8, 0.1, 0.2)],
			[Vector3(-1.3, 0.05, 0), Vector3(0.2, 0.1, 2.4)], [Vector3(1.3, 0.05, 0), Vector3(0.2, 0.1, 2.4)]]:
		var c := Util.box(e2[1], conc, pit + (e2[0] as Vector3))
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(c)
	var g := Util.box(Vector3(2.4, 0.04, 2.4), grate, pit + Vector3(0, 0.03, 0))
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(g)
	for k in 7:
		var bar := Util.box(Vector3(0.06, 0.05, 2.4), conc, pit + Vector3(-1.05 + k * 0.35, 0.06, 0))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(bar)
	houses.append([b.x, b.z])


func _make_mill_bin() -> void:
	## Дерев'яний засік збоку млина: відкритий зверху ящик, куди тракторист висипає зерно з причепа.
	var m := mill_dirs()
	var p := mill_bin_pos()
	var n := Node3D.new()
	n.name = "MillBin"
	add_child(n)
	n.position = p
	n.rotation.y = atan2(m[1].x, m[1].z)
	var wood := Util.mat(Color(0.52, 0.36, 0.22), 0.9)
	var dark := Util.mat(Color(0.38, 0.26, 0.16), 0.9)
	var w := 2.4
	var h := 1.0
	for e in [[Vector3(0, h * 0.5, -w * 0.5), Vector3(w, h, 0.1)], [Vector3(0, h * 0.225, w * 0.5), Vector3(w, h * 0.45, 0.1)],
			[Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.1, h, w)], [Vector3(w * 0.5, h * 0.5, 0), Vector3(0.1, h, w)]]:
		n.add_child(Util.box(e[1], wood, e[0]))
	n.add_child(Util.box(Vector3(w, 0.08, w), dark, Vector3(0, 0.04, 0)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			n.add_child(Util.box(Vector3(0.14, h + 0.25, 0.14), dark, Vector3(sx * w * 0.5, (h + 0.25) * 0.5 - 0.15, sz * w * 0.5)))
	# зерно в засіку (підіймається з кожним привезеним причепом)
	mill_bin_grain = Util.box(Vector3(w - 0.14, 1.0, w - 0.14), Util.mat(Color(0.84, 0.66, 0.3), 0.95), Vector3(0, 0.5, 0))
	n.add_child(mill_bin_grain)
	set_mill_bin(0)
	Obstacles.add_outer(p.x, p.z, 1.5, h)


func set_mill_bin(loads: int) -> void:
	if mill_bin_grain == null:
		return
	var k := clampf(loads / 4.0, 0.0, 1.0)
	mill_bin_grain.visible = loads > 0
	mill_bin_grain.scale.y = maxf(0.05, 0.38 * k)
	mill_bin_grain.position.y = 0.08 + mill_bin_grain.scale.y * 0.5


func set_wheat_ripe(on: bool) -> void:
	## Пшениця на полі: стоїть (on) чи вже скошена комбайном.
	var f := get_node_or_null("WheatField")
	if f:
		f.visible = on


# ------------------------------------------------------------------ комбайн біля пшеничного поля (Комбайн.blend)
const COMBINE_POS := Vector3(-135.2, 0, 40.0)        # під навісом на фермі
var combine_reel: Node3D


func _make_combine() -> void:
	## Комбайн стоїть на краю поля жаткою до колосся; мотовило поволі крутиться.
	if not ResourceLoader.exists("res://assets/models/combine.glb"):
		return
	var c: Node3D = load("res://assets/models/combine.glb").instantiate()
	c.name = "Combine"
	add_child(c)
	c.position = COMBINE_POS
	c.rotation.y = PI
	combine_reel = c.find_child("Мотовило", true, false) as Node3D
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 170.0
	for dz in [-2.6, 0.6, 3.6]:
		_obst.append([COMBINE_POS.x, COMBINE_POS.z + dz, 2.1, 4.0])
