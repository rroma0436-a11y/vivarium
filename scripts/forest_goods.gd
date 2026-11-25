extends Node3D
## Грибний ліс далеко на півночі (дорога веде до нього від дому): гриби (білі, лисички, мухомори — їх не беремо!)
## і кущики ягід (суниці, малина, чорниці). Зібране щоранку виростає знову. Все — з коду, легке для телефона.
## Увесь дальній ліс за пшеничним полем — грибний: підберезники, опеньки, сироїжки, ожина, брусниці, трави.
## Центр лісу має збігатися з FOREST_C у world_outer.gd.

const CENTER := Vector3(-30.0, 0, -388.0)
const R := 40.0
const FAR := Rect2(-200.0, -468.0, 400.0, 146.0)     # увесь дальній ліс за пшеничним полем: x, z, ширина, глибина
const FAR_LIMIT := 432.0                              # не далі межі, куди можна зайти

var goods: Array = []          # {node, kind, pos, taken}
var _last_day := -1

const KINDS := {
	"borovyk": ["Білий гриб", true], "lysychky": ["Лисички", true], "mukhomor": ["Мухомор — отруйний, не чіпаємо!", false],
	"sunytsi": ["Суниці", true], "malyna": ["Малина", true], "chornytsi": ["Чорниці", true],
	"pidberezovyk": ["Підберезник", true], "openky": ["Опеньки", true], "syroizhky": ["Сироїжки", true],
	"ozhyna": ["Ожина", true], "brusnytsi": ["Брусниці", true], "vovchi": ["Вовчі ягоди — отруйні, не чіпаємо!", false],
	"romashka": ["Ромашка", true], "zvirobii": ["Звіробій", true], "chebrets": ["Чебрець", true], "myata": ["М'ята", true],
}

var _mats := {}
var _balls := {}


func build(tree_spots: Array) -> void:
	## tree_spots — де стоять дерева (щоб гриби не росли просто в стовбурі).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var plan := ["borovyk", "borovyk", "borovyk", "borovyk", "lysychky", "lysychky", "lysychky", "lysychky", "mukhomor", "mukhomor", "mukhomor",
		"sunytsi", "sunytsi", "malyna", "malyna", "chornytsi", "chornytsi", "chornytsi", "borovyk", "lysychky"]
	for kind in plan + plan + plan:
		var p := Vector3.ZERO
		for tries in 30:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * R
			p = CENTER + Vector3(cos(a) * d, 0, sin(a) * d)
			var ok := true
			for t in tree_spots:
				if Vector2(p.x - t[0], p.z - t[1]).length() < 1.3:
					ok = false
					break
			for g in goods:
				if (g["pos"] as Vector3).distance_to(p) < 2.0:
					ok = false
			if ok:
				break
		var n := Node3D.new()
		n.position = p
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		_make(n, kind, rng)
		var pa := Util.pick_area("forest_item", Vector3(1.0, 0.8, 1.0), Vector3(0, 0.35, 0))
		pa.set_meta("item", goods.size())
		n.add_child(pa)
		goods.append({"node": n, "kind": kind, "pos": p, "taken": false})
	_far_goods(tree_spots)
	# м'який мох і опале листя під деревами — плями на землі
	var moss := Util.mat(Color(0.25, 0.4, 0.18), 1.0)
	var leaves := Util.mat(Color(0.5, 0.38, 0.2), 1.0)
	for i in 120:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * R
		var q := CENTER + Vector3(cos(a) * d, 0.03, sin(a) * d)
		var cy := Util.cyl(rng.randf_range(0.8, 1.8), rng.randf_range(0.8, 1.8), 0.02, moss if i % 3 else leaves, q)
		cy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cy)
	# пеньки й повалене дерево
	var bark := Util.mat(Color(0.4, 0.28, 0.18), 0.95)
	var cut := Util.mat(Color(0.8, 0.66, 0.45), 0.9)
	for i in 12:
		var a := rng.randf() * TAU
		var q := CENTER + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.0, R - 2.0)
		add_child(Util.cyl(0.28, 0.34, 0.45, bark, q + Vector3(0, 0.22, 0)))
		add_child(Util.cyl(0.28, 0.28, 0.02, cut, q + Vector3(0, 0.46, 0)))
		Obstacles.add_outer(q.x, q.z, 0.4, 0.5)
	var log := Util.cyl(0.25, 0.28, 4.5, bark, CENTER + Vector3(4.0, 0.25, 3.0))
	log.rotation = Vector3(0, 0.6, PI / 2.0)
	add_child(log)
	Obstacles.add_outer(CENTER.x + 4.0, CENTER.z + 3.0, 1.6, 0.6)
	for i in 110:
		var q := Vector3(rng.randf_range(FAR.position.x, FAR.end.x), 0.03, rng.randf_range(FAR.position.y, FAR.end.y))
		if Vector2(q.x, q.z).length() > FAR_LIMIT:
			continue
		var cy := Util.cyl(rng.randf_range(0.8, 1.8), rng.randf_range(0.8, 1.8), 0.02, moss if i % 3 else leaves, q)
		cy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cy)
	Obstacles.finish()


func _far_goods(tree_spots: Array) -> void:
	## Гриби, ягоди й трави по всьому дальньому лісу (свій rng — ближній грибний ліс лишається як був).
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var cell := 2.0
	var grid := {}
	for t in tree_spots:
		if t[1] < FAR.position.y - 5.0 or t[1] > FAR.end.y + 5.0:
			continue
		var k := Vector2i(floori(t[0] / cell), floori(t[1] / cell))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(Vector2(t[0], t[1]))
	for g in goods:
		var gp: Vector3 = g["pos"]
		var k := Vector2i(floori(gp.x / cell), floori(gp.z / cell))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(Vector2(gp.x, gp.z))
	var plan := ["borovyk", "pidberezovyk", "pidberezovyk", "openky", "openky", "syroizhky", "syroizhky", "lysychky", "mukhomor",
		"ozhyna", "ozhyna", "brusnytsi", "brusnytsi", "chornytsi", "sunytsi", "malyna", "vovchi",
		"romashka", "zvirobii", "chebrets", "myata"]
	var placed := 0
	var tries := 0
	while placed < 170 and tries < 2500:
		tries += 1
		var p := Vector3(rng.randf_range(FAR.position.x, FAR.end.x), 0, rng.randf_range(FAR.position.y, FAR.end.y))
		if Vector2(p.x, p.z).length() > FAR_LIMIT or Vector2(p.x - CENTER.x, p.z - CENTER.z).length() < R:
			continue
		var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
		var ok := true
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for q in grid.get(c + Vector2i(dx, dz), []):
					if (q as Vector2).distance_to(Vector2(p.x, p.z)) < 1.6:
						ok = false
		if not ok:
			continue
		if not grid.has(c):
			grid[c] = []
		grid[c].append(Vector2(p.x, p.z))
		var kind: String = plan[placed % plan.size()]
		var n := Node3D.new()
		n.position = p
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		_make(n, kind, rng)
		var pa := Util.pick_area("forest_item", Vector3(1.0, 0.8, 1.0), Vector3(0, 0.35, 0))
		pa.set_meta("item", goods.size())
		n.add_child(pa)
		goods.append({"node": n, "kind": kind, "pos": p, "taken": false})
		placed += 1


func _make(n: Node3D, kind: String, rng: RandomNumberGenerator) -> void:
	match kind:
		"borovyk":
			_mushroom(n, Color(0.5, 0.3, 0.15), Color(0.95, 0.92, 0.82), 0.16, 0.2, rng, 1)
		"lysychky":
			for k in 4:
				var c := Node3D.new()
				c.position = Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.18, 0.18))
				n.add_child(c)
				_mushroom(c, Color(0.98, 0.65, 0.12), Color(0.98, 0.72, 0.25), 0.06, 0.08, rng, 0)
		"mukhomor":
			_mushroom(n, Color(0.85, 0.08, 0.06), Color(0.97, 0.95, 0.9), 0.15, 0.24, rng, 2)
		"sunytsi":
			_bush(n, Color(0.3, 0.55, 0.2), Color(0.9, 0.1, 0.12), 0.35, 0.03, 14, rng)
		"malyna":
			_bush(n, Color(0.26, 0.5, 0.2), Color(0.85, 0.15, 0.35), 0.55, 0.035, 16, rng)
		"chornytsi":
			_bush(n, Color(0.22, 0.42, 0.2), Color(0.2, 0.22, 0.55), 0.32, 0.03, 18, rng)
		"pidberezovyk":
			_mushroom(n, Color(0.45, 0.33, 0.22), Color(0.9, 0.88, 0.84), 0.13, 0.26, rng, 3)
		"openky":
			for k in 6:
				var c := Node3D.new()
				c.position = Vector3(rng.randf_range(-0.16, 0.16), 0, rng.randf_range(-0.16, 0.16))
				n.add_child(c)
				_mushroom(c, Color(0.78, 0.55, 0.28), Color(0.9, 0.82, 0.62), 0.05, rng.randf_range(0.08, 0.13), rng, 0)
		"syroizhky":
			var sc: Color = [Color(0.85, 0.2, 0.25), Color(0.85, 0.45, 0.55), Color(0.45, 0.6, 0.3), Color(0.8, 0.65, 0.3)][rng.randi() % 4]
			for k in 2:
				var c := Node3D.new()
				c.position = Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
				n.add_child(c)
				_mushroom(c, sc, Color(0.97, 0.96, 0.93), 0.11, 0.12, rng, 0)
		"ozhyna":
			_bush(n, Color(0.22, 0.4, 0.18), Color(0.12, 0.07, 0.16), 0.6, 0.04, 16, rng)
		"brusnytsi":
			_bush(n, Color(0.16, 0.36, 0.16), Color(0.82, 0.08, 0.14), 0.28, 0.025, 18, rng)
		"vovchi":
			_bush(n, Color(0.3, 0.48, 0.24), Color(1.0, 0.12, 0.05), 0.45, 0.035, 12, rng)
		"romashka":
			_herb(n, Color(0.35, 0.58, 0.25), Color(0.98, 0.98, 0.95), Color(0.98, 0.8, 0.15), 7, 0.35, rng)
		"zvirobii":
			_herb(n, Color(0.3, 0.5, 0.2), Color(0.98, 0.82, 0.1), Color(0.95, 0.65, 0.05), 6, 0.5, rng)
		"chebrets":
			_herb(n, Color(0.32, 0.45, 0.25), Color(0.7, 0.45, 0.8), Color(0.6, 0.35, 0.7), 9, 0.18, rng)
		"myata":
			_herb(n, Color(0.3, 0.62, 0.32), Color(0.4, 0.72, 0.4), Color(0.75, 0.65, 0.88), 8, 0.28, rng)


func _herb(n: Node3D, stem_c: Color, petal_c: Color, mid_c: Color, count: int, h: float, rng: RandomNumberGenerator) -> void:
	## Пучок трави: тонкі стебельця з квіточками.
	var sm := _mat(stem_c, 0.85)
	var pm := _mat(petal_c, 0.6)
	var cm := _mat(mid_c, 0.5)
	for k in count:
		var hh := h * rng.randf_range(0.7, 1.15)
		var o := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var st := Util.cyl(0.008, 0.012, hh, sm, o + Vector3(0, hh * 0.5, 0))
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(st)
		n.add_child(_ball(0.035, pm, o + Vector3(0, hh, 0), Vector3(1, 0.45, 1)))
		n.add_child(_ball(0.014, cm, o + Vector3(0, hh + 0.012, 0)))
	n.add_child(_ball(0.12, sm, Vector3(0, 0.05, 0), Vector3(1.3, 0.5, 1.3)))


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), rough]
	if not _mats.has(key):
		_mats[key] = Util.mat(c, rough)
	return _mats[key]


func _ball(r: float, m: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	## Кулька зі спільним мешем — дрібні ягідки й квіточки легші для телефона.
	if not _balls.has(r):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 8 if r < 0.06 else 14
		sm.rings = 4 if r < 0.06 else 7
		_balls[r] = sm
	return Util.mesh(_balls[r], m, pos, Vector3.ZERO, scl)


func _mushroom(n: Node3D, cap_c: Color, stem_c: Color, cap_r: float, stem_h: float, rng: RandomNumberGenerator, dots: int) -> void:
	var stem := Util.cyl(cap_r * 0.35, cap_r * 0.45, stem_h, Util.mat(stem_c, 0.8), Vector3(0, stem_h * 0.5, 0))
	n.add_child(stem)
	var cap := Util.sphere(cap_r, Util.mat(cap_c, 0.55), Vector3(0, stem_h, 0), Vector3(1.0, 0.6, 1.0))
	cap.rotation.z = rng.randf_range(-0.15, 0.15)
	n.add_child(cap)
	if dots == 3:
		var dm := _mat(Color(0.15, 0.13, 0.12), 0.9)
		for k in 6:
			var a := rng.randf() * TAU
			n.add_child(_ball(cap_r * 0.07, dm, Vector3(cos(a) * cap_r * 0.4, rng.randf_range(0.2, 0.85) * stem_h, sin(a) * cap_r * 0.4)))
	if dots == 2:
		var wm := Util.mat(Color(1, 1, 1), 0.7)
		for k in 7:
			var a := rng.randf() * TAU
			var y := rng.randf_range(0.35, 0.9)
			var d := Vector3(cos(a) * sqrt(1.0 - y * y), y * 0.6, sin(a) * sqrt(1.0 - y * y))
			n.add_child(Util.sphere(cap_r * 0.14, wm, Vector3(0, stem_h, 0) + d * cap_r, Vector3(1, 0.5, 1)))


func _bush(n: Node3D, leaf_c: Color, berry_c: Color, size: float, br: float, count: int, rng: RandomNumberGenerator) -> void:
	var lm := Util.mat(leaf_c, 0.85)
	for k in 4:
		var o := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) * size * 2.0
		n.add_child(Util.sphere(size * rng.randf_range(0.55, 0.8), lm, o + Vector3(0, size * 0.55, 0), Vector3(1, 0.75, 1)))
	var bm := Util.mat(berry_c, 0.35)
	var berries := Node3D.new()
	berries.name = "berries"
	n.add_child(berries)
	for k in count:
		var a := rng.randf() * TAU
		var y := rng.randf_range(-0.1, 0.8)
		var d := Vector3(cos(a) * sqrt(1.0 - y * y), y * 0.75, sin(a) * sqrt(1.0 - y * y))
		berries.add_child(Util.sphere(br, bm, Vector3(0, size * 0.55, 0) + d * size * 0.78))


func _process(_d: float) -> void:
	var d := int(Game.state.get("day", 1))
	if d != _last_day:
		if _last_day != -1:
			for g in goods:
				_set_taken(g, false)
		_last_day = d


func _set_taken(g: Dictionary, on: bool) -> void:
	g["taken"] = on
	var n: Node3D = g["node"]
	var b := n.get_node_or_null("berries")
	if b:
		b.visible = not on               # кущик лишається, ягоди зникають
	else:
		n.visible = not on


func can_take(i: int) -> bool:
	var g: Dictionary = goods[i]
	return not g["taken"] and KINDS[g["kind"]][1]


func take(i: int) -> int:
	if not can_take(i):
		return 0
	_set_taken(goods[i], true)
	return 1


func label(i: int) -> String:
	return KINDS[goods[i]["kind"]][0]


func kind_color(i: int) -> Color:
	## Колір плоду — щоб у кошику лежали саме ті гриби чи ягоди, які зібрали.
	match String(goods[i]["kind"]):
		"borovyk":
			return Color(0.55, 0.35, 0.18)
		"lysychky":
			return Color(0.98, 0.65, 0.12)
		"sunytsi":
			return Color(0.9, 0.1, 0.12)
		"malyna":
			return Color(0.85, 0.15, 0.35)
		"chornytsi":
			return Color(0.2, 0.22, 0.55)
		"pidberezovyk":
			return Color(0.45, 0.33, 0.22)
		"openky":
			return Color(0.78, 0.55, 0.28)
		"syroizhky":
			return Color(0.85, 0.35, 0.35)
		"ozhyna":
			return Color(0.12, 0.07, 0.16)
		"brusnytsi":
			return Color(0.82, 0.08, 0.14)
		"romashka":
			return Color(0.98, 0.98, 0.95)
		"zvirobii":
			return Color(0.98, 0.82, 0.1)
		"chebrets":
			return Color(0.7, 0.45, 0.8)
		"myata":
			return Color(0.4, 0.72, 0.4)
	return Color(0.6, 0.5, 0.3)


func goods_pos(i: int) -> Vector3:
	return goods[i]["pos"]


func nearest_goods(from: Vector3, n: int) -> Array:
	var list: Array = []
	for i in goods.size():
		if can_take(i):
			list.append(i)
	list.sort_custom(func(a, b): return (goods[a]["pos"] as Vector3).distance_to(from) < (goods[b]["pos"] as Vector3).distance_to(from))
	return list.slice(0, n)
