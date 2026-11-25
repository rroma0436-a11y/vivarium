extends RefCounted
class_name Util
## Дрібні помічники для побудови сцени кодом.


static func blob_shadow(radius: float, alpha := 0.35) -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.07, 0.12, alpha))
	g.set_color(1, Color(0.1, 0.07, 0.12, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = gt
	m.render_priority = -1
	var q := PlaneMesh.new()
	q.size = Vector2(radius * 2.0, radius * 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position.y = 0.003
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func mat(color: Color, rough := 0.6, metal := 0.0, emit := Color(0, 0, 0), emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static var _road_mats := {}


static func road_mat(k := 1.0) -> StandardMaterial3D:
	## Коричнева ґрунтова дорога — така сама, як стежки в шейдері землі (world.gd): пісок × «dirt».
	if _road_mats.has(k):
		return _road_mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.63 * k, 0.53 * k, 0.4 * k)
	if ResourceLoader.exists("res://assets/textures/sand.jpg"):
		m.albedo_texture = load("res://assets/textures/sand.jpg")
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 2.6
	else:
		m.albedo_color = Color(0.58 * k, 0.45 * k, 0.3 * k)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_road_mats[k] = m
	return m


static func mesh(m: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	return mi


static func sphere(r: float, material: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	return mesh(s, material, pos, Vector3.ZERO, scl)


static func box(size: Vector3, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(b, material, pos, rot)


static func cyl(r_top: float, r_bot: float, h: float, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 20
	return mesh(c, material, pos, rot)


static func capsule(r: float, h: float, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	return mesh(c, material, pos, rot)


# ------------------------------------------------------------------ тверді персонажі, тварини й речі для Ніки
# Зони торкання людей, тварин, возів, машин, криниць… — це й «тіло», крізь яке Ніка не проходить.
const NOT_SOLID := ["bz_furn", "girl", "house", "room_exit", "gold_flower", "stall", "pies", "forest_item",
	"orchard_tree", "firefly", "drone", "barn", "workshop", "bird", "bowl", "hare", "fountain", "seed", "item", "nk_basket", "bz_shop", "bench"]
static var pick_areas: Array = []


static func push_solids(p: Vector3, me: float, skip: Array = []) -> Vector3:
	## Виштовхує точку p (ноги Ніки чи центр її коня/велосипеда) з «тіл» усіх персонажів і речей.
	var i := 0
	while i < pick_areas.size():
		var a = pick_areas[i]
		if not is_instance_valid(a):
			pick_areas.remove_at(i)
			continue
		i += 1
		var ar := a as Area3D
		if not ar.is_inside_tree() or ar.get_child_count() == 0:
			continue
		var own := ar.get_parent()
		if own == null or skip.has(own) or not (own as Node3D).is_visible_in_tree():
			continue
		var cs := ar.get_child(0) as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var xf := cs.global_transform
		if absf(xf.origin.x - p.x) > 7.0 or absf(xf.origin.z - p.z) > 7.0:
			continue
		var sc := xf.basis.get_scale()
		var hs: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var y0 := xf.origin.y - hs.y * sc.y
		if y0 > p.y + 1.0 or xf.origin.y + hs.y * sc.y < p.y + 0.1:
			continue                              # літає вгорі (Beep, птахи) або нижче ніг
		var l := xf.affine_inverse() * Vector3(p.x, xf.origin.y, p.z)
		var ex := hs.x * 0.8 + me / maxf(sc.x, 0.001)
		var ez := hs.z * 0.8 + me / maxf(sc.z, 0.001)
		if absf(l.x) >= ex or absf(l.z) >= ez:
			continue
		if (ex - absf(l.x)) * sc.x < (ez - absf(l.z)) * sc.z:
			l.x = ex if l.x >= 0.0 else -ex
		else:
			l.z = ez if l.z >= 0.0 else -ez
		var g := xf * l
		p = Vector3(g.x, p.y, g.z)
	return p


static func pick_area(kind: String, size: Vector3, center: Vector3) -> Area3D:
	## Невидима «зона торкання» для об'єкта.
	var a := Area3D.new()
	a.set_meta("kind", kind)
	a.input_ray_pickable = true
	if not NOT_SOLID.has(kind):
		pick_areas.append(a)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	a.add_child(cs)
	return a


static func bubble(font: Font, size := 48) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = size
	l.outline_size = 14
	l.modulate = Color(0.16, 0.12, 0.3)
	l.outline_modulate = Color(1, 1, 1, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.0022
	l.width = 520.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.render_priority = 10
	l.outline_render_priority = 9
	l.visible = false
	return l


# ------------------------------------------------------------------ кошик для грибів, ягід і яблук
static func basket() -> Node3D:
	## Плетений кошик із дужкою. У вузол «fill» складаються зібрані плоди (див. basket_add).
	var n := Node3D.new()
	var wick := mat(Color(0.72, 0.52, 0.28), 0.95)
	n.add_child(cyl(0.17, 0.13, 0.15, wick, Vector3(0, 0.075, 0)))
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
	var fill := Node3D.new()
	fill.name = "fill"
	n.add_child(fill)
	return n


static func basket_add(b, color: Color, r := 0.04) -> void:
	## Кладе ще один плід у кошик (до 16 штук — далі кошик просто «повний»).
	## b без типу: кошик могли вже прибрати (справу скасували).
	if b == null or not is_instance_valid(b):
		return
	var fill: Node3D = b.get_node_or_null("fill")
	if fill == null or fill.get_child_count() >= 16:
		return
	var i := fill.get_child_count()
	var a := float(i) * 2.4
	var ring := 0.02 + 0.09 * fmod(float(i) * 0.37, 1.0)
	var layer := floorf(float(i) / 8.0)
	fill.add_child(sphere(r, mat(color, 0.5), Vector3(cos(a) * ring, 0.15 + layer * 0.04, sin(a) * ring)))


const HILL_C := Vector2(-82, -50)       # пагорб з млином (має збігатися з MILL_HILL* у world_outer.gd)
const HILL_R := 30.0
const HILL_H := 4.0
const MILL_FLOOR := 4.21                 # цоколь і підлога млина на вершині


static func hill_y(p: Vector3) -> float:
	## Висота пагорба з млином у точці p (у млині — підлога); поза пагорбом — 0.
	var dd := Vector2(p.x - HILL_C.x, p.z - HILL_C.y).length()
	if dd < 2.9:
		return MILL_FLOOR
	var d := dd / HILL_R
	if d >= 1.0:
		return 0.0
	return maxf(0.0, HILL_H * (1.6 * sqrt(1.0 - d * d) - 0.6))


static func on_hill(p: Vector3) -> bool:
	return Vector2(p.x - HILL_C.x, p.z - HILL_C.y).length() < HILL_R + 1.5


# ------------------------------------------------------------------ причал на ставку: по ньому можна ходити
# a — край на березі, b — край над водою (x, z), hw — пів ширини настилу, y — висота настилу (заповнює world_outer.gd)
static var pier := {}


static func _pier_st(p: Vector3) -> Vector3:
	## (відстань від берегового краю вздовж причалу, зсув убік, довжина причалу)
	var a: Vector2 = pier["a"]
	var ab: Vector2 = (pier["b"] as Vector2) - a
	var L := ab.length()
	var u := ab / maxf(L, 0.001)
	var q := Vector2(p.x, p.z) - a
	return Vector3(q.dot(u), q.dot(Vector2(-u.y, u.x)), L)


static func on_pier(p: Vector3, grow := 0.0) -> bool:
	if pier.is_empty():
		return false
	var st := _pier_st(p)
	return st.x >= -grow and st.x <= st.z + grow and absf(st.y) <= float(pier["hw"]) + grow


static func pier_clamp(p: Vector3, me := 0.2) -> Vector3:
	## Ніка на причалі не ступає з настилу у воду: тримаємо її в межах дощок (на березі — вільно).
	if pier.is_empty():
		return p
	var st := _pier_st(p)
	if st.x < 0.0:
		return p
	var hw := float(pier["hw"]) - me
	var s := minf(st.x, st.z - me - 0.15)
	var t := clampf(st.y, -hw, hw)
	var a: Vector2 = pier["a"]
	var u := ((pier["b"] as Vector2) - a) / st.z
	var q := a + u * s + Vector2(-u.y, u.x) * t
	return Vector3(q.x, p.y, q.y)


static func pier_y(p: Vector3) -> float:
	## Висота настилу причалу під ногами (на березі — плавний приступок), поза причалом — 0.
	if not on_pier(p, 0.35):
		return 0.0
	var st := _pier_st(p)
	if absf(st.y) > float(pier["hw"]) + 0.05:
		return 0.0
	return float(pier["y"]) * clampf((st.x + 0.35) / 0.6, 0.0, 1.0)


static func bridge_y(p: Vector3) -> float:
	## Висота настилу мосту через річку (z = 102) з пологими сходами на кінцях; на пагорбі — його висота;
	## на причалі ставка — висота його настилу; деінде — 0.
	var hy := hill_y(p)
	if hy > 0.0:
		return hy
	var py := pier_y(p)
	if py > 0.0:
		return py
	if absf(p.x) > 1.75:
		return 0.0
	var dz := absf(p.z - 102.0)
	if dz <= 6.0:
		return 0.43
	if dz < 7.8:
		return 0.43 * (7.8 - dz) / 1.8
	return 0.0



# ------------------------------------------------------------------ дрібні речі, які Ніка бере в руки (їжа, посуд, інструмент)
const THING_NAMES := {"cup": "кухоль узвару", "apple": "яблучко", "pear": "грушу", "plum": "сливи", "bun": "булочку", "pie": "пиріжок",
	"bread": "паляницю", "baton": "батон", "sausage": "ковбаску", "salo": "сальце", "ham": "шинку", "candy": "льодяник",
	"gingerbread": "пряник", "sweets": "цукерки", "milk": "молоко", "axe": "сокиру", "hammer": "молоток", "rake": "граблі",
	"shovel": "лопату", "fork": "вила", "hoe": "сапу", "broom": "мітлу", "jug": "глечик"}
const FOOD := ["cup", "apple", "pear", "plum", "bun", "pie", "bread", "baton", "sausage", "salo", "ham", "candy", "gingerbread", "sweets", "milk"]


static func make_takeable(n: Node3D, kind := "prop", max_size := 0.9) -> bool:
	## Будь-яку дрібну річ (глечик, горщик, миску, ящик…) Ніка може взяти в руки.
	if n == null or n.has_meta("item_kind"):
		return false
	var inv := n.global_transform.affine_inverse() if n.is_inside_tree() else Transform3D()
	var bb := AABB()
	var first := true
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for m in list:
		var mi := m as MeshInstance3D
		var ab: AABB = (inv * mi.global_transform if n.is_inside_tree() else Transform3D()) * mi.get_aabb()
		bb = ab if first else bb.merge(ab)
		first = false
	if first:
		return false
	var gs := n.global_transform.basis.get_scale() if n.is_inside_tree() else n.scale
	if maxf(bb.size.x * gs.x, maxf(bb.size.y * gs.y, bb.size.z * gs.z)) > max_size:
		return false
	var bot := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	if n is MeshInstance3D and n.is_inside_tree() and bot.length() > 0.03:
		# початок координат сітки далеко (уся «полиця» мала спільний центр) — ставимо річ на свій «низ»
		var hold := Node3D.new()
		hold.name = String(n.name) + "_Item"
		n.get_parent().add_child(hold)
		hold.global_transform = Transform3D(n.global_transform.basis.orthonormalized(), n.global_transform * bot)
		n.reparent(hold, true)
		var sc := n.global_transform.basis.get_scale()
		var a2 := pick_area("item", bb.size * sc + Vector3(0.06, 0.06, 0.06), Vector3(0, bb.size.y * sc.y * 0.5, 0))
		a2.set_meta("item_kind", kind)
		hold.add_child(a2)
		hold.set_meta("item_kind", kind)
		n.set_meta("item_kind", kind)
		return true
	var a := pick_area("item", bb.size + Vector3(0.06, 0.06, 0.06), bb.get_center())
	a.set_meta("item_kind", kind)
	n.add_child(a)
	n.set_meta("item_kind", kind)
	return true


static func thing(kind: String) -> Node3D:
	## Річ із початком координат унизу (стоїть на столі чи на землі). Має зону торкання «item».
	var n := Node3D.new()
	n.name = "Thing_" + kind
	var wood := mat(Color(0.55, 0.38, 0.22), 0.85)
	var iron := mat(Color(0.45, 0.47, 0.5), 0.4, 0.6)
	var sz := Vector3(0.14, 0.14, 0.14)
	match kind:
		"cup":
			if Models.exists("cup"):
				var c := Models.spawn(n, "cup", 0.11)
				if c == null:
					n.add_child(cyl(0.045, 0.04, 0.1, mat(Color(0.75, 0.45, 0.25), 0.6), Vector3(0, 0.05, 0)))
			else:
				n.add_child(cyl(0.045, 0.04, 0.1, mat(Color(0.75, 0.45, 0.25), 0.6), Vector3(0, 0.05, 0)))
		"milk":
			n.add_child(cyl(0.05, 0.06, 0.18, mat(Color(0.95, 0.95, 0.92), 0.5), Vector3(0, 0.09, 0)))
		"apple", "pear", "plum":
			var col: Color = {"apple": Color(0.85, 0.18, 0.12), "pear": Color(0.8, 0.78, 0.25), "plum": Color(0.35, 0.15, 0.45)}[kind]
			var k := 3 if kind != "apple" else 2
			for i in k:
				var a := TAU * i / k
				n.add_child(sphere(0.04, mat(col, 0.45), Vector3(cos(a) * 0.035, 0.04, sin(a) * 0.035), Vector3(1, 1.15 if kind == "pear" else 1.0, 1)))
		"bun":
			n.add_child(sphere(0.05, mat(Color(0.82, 0.55, 0.25), 0.7), Vector3(0, 0.035, 0), Vector3(1, 0.7, 1)))
		"pie":
			n.add_child(sphere(0.06, mat(Color(0.85, 0.6, 0.3), 0.7), Vector3(0, 0.025, 0), Vector3(1.4, 0.5, 0.8)))
		"bread":
			n.add_child(sphere(0.11, mat(Color(0.7, 0.42, 0.18), 0.75), Vector3(0, 0.05, 0), Vector3(1, 0.5, 1)))
			sz = Vector3(0.24, 0.12, 0.24)
		"baton":
			n.add_child(sphere(0.05, mat(Color(0.8, 0.52, 0.22), 0.75), Vector3(0, 0.04, 0), Vector3(1, 0.8, 3.2)))
			sz = Vector3(0.12, 0.1, 0.3)
		"sausage":
			n.add_child(cyl(0.025, 0.025, 0.22, mat(Color(0.55, 0.18, 0.12), 0.5), Vector3(0, 0.025, 0), Vector3(90, 0, 0)))
			sz = Vector3(0.08, 0.08, 0.24)
		"salo":
			n.add_child(box(Vector3(0.1, 0.05, 0.08), mat(Color(0.96, 0.88, 0.82), 0.6), Vector3(0, 0.025, 0)))
		"ham":
			n.add_child(sphere(0.07, mat(Color(0.82, 0.45, 0.42), 0.6), Vector3(0, 0.05, 0), Vector3(1, 0.8, 1.2)))
		"candy":
			n.add_child(cyl(0.006, 0.006, 0.12, mat(Color(0.95, 0.95, 0.9)), Vector3(0, 0.06, 0)))
			n.add_child(sphere(0.035, mat(Color(0.95, 0.2, 0.25), 0.2), Vector3(0, 0.13, 0), Vector3(1, 1, 0.4)))
		"gingerbread":
			n.add_child(cyl(0.06, 0.06, 0.015, mat(Color(0.6, 0.35, 0.15), 0.8), Vector3(0, 0.008, 0)))
		"sweets":
			for i in 4:
				n.add_child(sphere(0.018, mat(Color.from_hsv(i * 0.25, 0.7, 0.95), 0.3), Vector3((i % 2) * 0.04 - 0.02, 0.018, (i / 2) * 0.04 - 0.02), Vector3(1.6, 1, 1)))
		"axe":
			n.add_child(cyl(0.015, 0.018, 0.45, wood, Vector3(0, 0.225, 0)))
			n.add_child(box(Vector3(0.03, 0.08, 0.14), iron, Vector3(0, 0.42, 0.04)))
			sz = Vector3(0.12, 0.5, 0.2)
		"hammer":
			n.add_child(cyl(0.012, 0.014, 0.3, wood, Vector3(0, 0.15, 0)))
			n.add_child(box(Vector3(0.04, 0.04, 0.12), iron, Vector3(0, 0.3, 0)))
			sz = Vector3(0.1, 0.34, 0.14)
		"rake", "shovel", "fork", "hoe", "broom":
			n.add_child(cyl(0.016, 0.018, 1.3, wood, Vector3(0, 0.65 + 0.05, 0)))
			match kind:
				"rake":
					n.add_child(box(Vector3(0.36, 0.03, 0.03), wood, Vector3(0, 0.06, 0)))
					for i in 8:
						n.add_child(box(Vector3(0.01, 0.06, 0.01), iron, Vector3(-0.16 + i * 0.045, 0.03, 0.01)))
				"shovel":
					n.add_child(box(Vector3(0.2, 0.26, 0.015), iron, Vector3(0, 0.0, 0) + Vector3(0, -0.06, 0)))
				"fork":
					n.add_child(box(Vector3(0.16, 0.02, 0.02), iron, Vector3(0, 0.05, 0)))
					for i in 4:
						n.add_child(box(Vector3(0.008, 0.2, 0.008), iron, Vector3(-0.06 + i * 0.04, -0.05, 0)))
				"hoe":
					n.add_child(box(Vector3(0.14, 0.1, 0.012), iron, Vector3(0, 0.0, 0.03), Vector3(70, 0, 0)))
				"broom":
					n.add_child(cyl(0.02, 0.07, 0.28, mat(Color(0.8, 0.68, 0.35), 0.95), Vector3(0, -0.06, 0)))
			for c in n.get_children():
				(c as Node3D).position.y += 0.12                     # усе — над землею
			sz = Vector3(0.3, 1.5, 0.3)
		_:
			return null
	var a := pick_area("item", sz + Vector3(0.06, 0.06, 0.06), Vector3(0, sz.y * 0.5, 0))
	a.set_meta("item_kind", kind)
	n.add_child(a)
	n.set_meta("item_kind", kind)
	return n
