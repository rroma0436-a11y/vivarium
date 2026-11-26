extends Node3D
## Базар за річкою (зроблено в Blender, файл Базар.blend): два ряди ларьків із продавцями й товаром,
## дві вулиці хат із меблями, дерев'яна церква в кінці проходу, криниці, лавки, ліхтарі.
## Усе стоїть так само, як у Blender; головний прохід — продовження дороги від мосту (x = 0).
## Двері хат, ларьків, церкви й ворота дворів відчиняються, коли поруч Ніка.
## Стіни, ларьки й паркани тверді для Ніки (шар WALLS), підлога хат і ганки — шар FLOOR.

const DIR := "res://assets/models/bazaar/%s.glb"
# точка Blender (0, 0) у світі гри; вісь X Blender (прохід між ларьками) дивиться на північ, до мосту
const ORIGIN := Vector3(-3.06, 0, 197.0)
const AREA := Rect2(-74.0, 106.0, 141.0, 134.0)          # x, z — уся територія базару
const WALLS := 1 << 17
const FLOOR := 1 << 16

var root: Node3D
var walls: StaticBody3D
var floors: StaticBody3D
var buildings: Array = []        # {node, box (AABB у системі вузла), roofs: [MeshInstance3D], kind}
var doors: Array = []            # {node, base, open_to, angle, open, pos}
var sellers: Array = []          # [вузол, AnimationPlayer]
var map_houses: Array = []       # [x, z] для мапи
var map_road_pts: Array = []     # точки доріг базару для мапи [x, z]
var inside = null                # будівля, в якій зараз Ніка (або null)
var village_spots: Array = []    # хати старого села: [позиція у світі, поворот (рад), зелена?]
static var extra_areas: Array = []   # Rect2 довкола хат старого села (там теж діють стіни й підлога)
var _acc := 0.0
var mill_parts: Array = []      # млин: [вузол, вісь, швидкість]

# продавці: файл, позиція в Blender (x, y), поворот (рад, навколо Z Blender), слова
const SELLERS := [
	["bz_seller_bread", Vector2(5.0, -0.2), "Ковбаска домашня, сальце — пробуй!", "sausage"],
	["bz_seller_m1", Vector2(9.5, -0.2), "Сокири, молотки, граблі, а ще сідла й вуздечки — на все господарство!", "tools"],
	["bz_seller_w2", Vector2(14.0, -0.2), "Льодяники, пряники, цукерочки!", "sweets"],
	["bz_seller_bread", Vector2(18.5, -0.2), "Свіжий хліб, тільки з печі!", "bread"],
	["bz_seller_girl", Vector2(9.5, -6.12), "Яблучка, груші, сливи — солоденькі!", "fruit"],
]
# товар кожного продавця: [назва, ціна, що це (Util.thing)]
const GOODS := {
	"sausage": [["Ковбаса домашня", 10, "sausage"], ["Сало", 8, "salo"], ["Шинка", 12, "ham"]],
	"tools": [["Сокира", 15, "axe"], ["Молоток", 8, "hammer"], ["Граблі", 10, "rake"], ["Лопата", 10, "shovel"], ["Вила", 10, "fork"]],
	"sweets": [["Льодяник", 2, "candy"], ["Пряник", 3, "gingerbread"], ["Цукерки", 4, "sweets"]],
	"bread": [["Паляниця", 4, "bread"], ["Батон", 3, "baton"], ["Булочка", 2, "bun"]],
	"fruit": [["Яблука", 3, "apple"], ["Груші", 3, "pear"], ["Сливи", 2, "plum"]],
}
const SHOP_ASK := {
	"sausage": "Добрий день, Ніко! Ковбаски, сальця чи шинки?",
	"tools": "Що шукаєш, господине? Сокиру, граблі, лопату?",
	"sweets": "Солоденького хочеш? Льодяники, пряники!",
	"bread": "Свіжий хліб! Паляницю чи булочку?",
	"fruit": "Яблучка, груші, сливи — вибирай!",
}
const SELLER_FILE_POS := {"bz_seller_bread": Vector2(18.5, -0.2), "bz_seller_m1": Vector2(9.5, -0.2),
	"bz_seller_w2": Vector2(14.0, -0.2), "bz_seller_girl": Vector2(9.5, -6.12)}
# хлопець-продавець: рухи з Blender (Idle — стоїть, Talk — говорить руками, Wave — махає, Give — подає товар)
const STUDENT_LINES := ["Хліба? Цукерок? Підходь ближче!", "Я після школи тут торгую!", "Гарного дня, Ніко!", "Кажуть, над селом літає дракон!"]


static func to_world(bx: float, by: float) -> Vector3:
	## Точка з Blender (x, y) → світ гри.
	return ORIGIN + Vector3(-by, 0, -bx)


static func in_area(p: Vector3) -> bool:
	if AREA.has_point(Vector2(p.x, p.z)):
		return true
	for r in extra_areas:
		if (r as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


func build() -> void:
	root = Node3D.new()
	root.name = "BazaarRoot"
	root.position = ORIGIN
	root.rotation.y = PI / 2.0
	add_child(root)
	walls = _body("BazaarWalls", WALLS)
	floors = _body("BazaarFloors", FLOOR)
	for f in ["bz_misc", "bz_fence", "bz_stalls", "bz_houses", "bz_goods", "bz_mill"]:
		if not ResourceLoader.exists(DIR % f):
			continue
		var n: Node3D = load(DIR % f).instantiate()
		n.name = f
		root.add_child(n)
		if f == "bz_misc":
			# лавки з Blender вгрузли в землю й лежали в траві, як дошки — прибрано (лавочки тепер біля хат)
			for c in n.find_children("Лавка*", "", true, false):
				c.get_parent().remove_child(c)
				c.free()
		if f == "bz_stalls":
			var fs := n.find_child("Продавець_Риба", true, false)
			if fs:
				fs.get_parent().remove_child(fs)
				fs.free()
		if f == "bz_mill":
			var mn := n.get_node_or_null("Млин") as Node3D
			if mn:     # на вершині пагорба (замість вітряка), входом до дороги
				var hw := Vector3(Util.HILL_C.x, Util.HILL_H - 0.1, Util.HILL_C.y)
				mn.position = Vector3(-(hw.z - ORIGIN.z), hw.y, hw.x - ORIGIN.x)
				mn.rotation = Vector3(0, atan2(0.4472136, 0.8944272) - PI / 2.0, 0)
	_remove_old_goods()
	for s in SELLERS:
		_add_seller(s[0], s[1], s[2])
		if not sellers.is_empty():
			var sd: Dictionary = sellers[sellers.size() - 1]
			sd["shop"] = s[3]
			var at: Vector2 = s[1]
			sd["front"] = to_world(at.x, at.y + (-1.75 if at.y > -3.0 else 1.75))     # де стати покупцеві (у проході)
			sd["greet_t"] = 0.0
	_tack_stall()
	_make_village_huts()
	_village_props()
	_stall_trees()
	_setup_meshes()
	_setup_buildings()
	_collect_roads()
	_add_sheds()


func _add_sheds() -> void:
	## Сарай діда, стайня й корівник — теж «будівлі»: Ніка заходить, камера — зсередини, світло вмикається.
	var wo = get_parent()
	var lists: Array = []
	if wo and "walk_in" in wo:
		lists.append(wo.walk_in)
	if wo and "world" in wo and wo.world and "walk_in" in wo.world:
		lists.append(wo.world.walk_in)
	for l in lists:
		for e in l:
			var n: Node3D = e[0]
			var box: AABB = e[1]
			buildings.append({"node": n, "kind": "shed", "roofs": [], "box": box, "name": String(n.name), "furn": []})
			var wb := AABB(n.global_transform * box.position, Vector3.ZERO)
			for i in 8:
				wb = wb.expand(n.global_transform * box.get_endpoint(i))
			extra_areas.append(Rect2(wb.position.x - 0.8, wb.position.z - 0.8, wb.size.x + 1.6, wb.size.z + 1.6))


func _make_village_huts() -> void:
	## Хати старого села: копії базарних хат (стіни, піч, стіл, лава, ліжко, двері), без воріт двору.
	## Хата обернена ганком до вулиці й відсунута на 1 м назад від центру садиби.
	extra_areas.clear()
	var hs: Node3D = root.get_node_or_null("bz_houses")
	if hs == null:
		return
	var parent_t: Transform3D = root.transform * hs.transform
	var k := 0
	for sp in village_spots:
		var src := hs.get_node_or_null("Хата_Зелена" if sp[2] else "Хата") as Node3D
		if src == null:
			continue
		var h := src.duplicate() as Node3D
		for c in h.get_children():
			var cn := String(c.name)
			if cn.contains("Ворота") or cn.contains("Калітка"):
				h.remove_child(c)
				c.free()
		k += 1
		h.name = "Село_Хата_%d" % k
		var bs := Basis(Vector3.UP, float(sp[1]))
		var pos: Vector3 = sp[0]
		var w := Transform3D(bs * Basis(Vector3.UP, PI / 2.0), pos + bs * Vector3(0, 0, -1.0))
		h.transform = parent_t.affine_inverse() * w
		hs.add_child(h)
		village_nodes.append([h, sp])
		# зона, де діють стіни й підлога хати (замість кіл-перешкод відкритого світу)
		var a := pos + bs * Vector3(-6.9, 0, -6.9)
		var b := pos + bs * Vector3(6.9, 0, 7.7)
		extra_areas.append(Rect2(minf(a.x, b.x), minf(a.z, b.z), absf(a.x - b.x), absf(a.z - b.z)))


func _collect_roads() -> void:
	var rd := root.find_child("Дороги", true, false) as MeshInstance3D
	if rd == null or rd.mesh == null:
		return
	var seen := {}
	for f in rd.mesh.get_faces():
		var w: Vector3 = rd.global_transform * f
		var key := Vector2i(int(w.x / 2.0), int(w.z / 2.0))
		if not seen.has(key):
			seen[key] = true
			map_road_pts.append([w.x, w.z])


func _body(nm: String, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = nm
	b.collision_layer = layer
	b.collision_mask = 0
	add_child(b)
	return b


func _add_seller(file: String, at: Vector2, words: String) -> void:
	if not ResourceLoader.exists(DIR % file):
		return
	var holder := Node3D.new()
	holder.name = "Seller_%d" % sellers.size()
	root.add_child(holder)
	var m: Node3D = load(DIR % file).instantiate()
	holder.add_child(m)
	# файл уже стоїть на своєму місці з Blender — зсуваємо, якщо цей продавець в іншому ларьку
	var fp: Vector2 = SELLER_FILE_POS[file]
	holder.position = Vector3(at.x - fp.x, 0, -(at.y - fp.y))
	var ap := Models.anim_player(m)
	if ap and ap.has_animation("Idle"):
		ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")
	elif ap and ap.get_animation_list().size() > 0:
		var an: String = ap.get_animation_list()[0]
		ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		ap.play(an)
		ap.seek(randf() * ap.get_animation(an).length, true)
	Models.give_nika_anims(ap)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pos := to_world(at.x, at.y)
	var pick := Util.pick_area("bz_seller", Vector3(0.9, 1.8, 0.9), Vector3(0, 0.9, 0))
	pick.set_meta("words", words)
	var here := Vector3(fp.x, 0, -fp.y)          # де стоїть продавець у системі holder
	pick.position = here
	holder.add_child(pick)
	var lb := Label3D.new()
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 44
	lb.outline_size = 10
	lb.modulate = Color(1, 0.98, 0.9)
	lb.outline_modulate = Color(0.25, 0.12, 0.3)
	lb.width = 520.0
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.pixel_size = 0.004
	lb.position = here + Vector3(0, 2.15, 0)
	lb.visible = false
	lb.no_depth_test = true
	holder.add_child(lb)
	var cyl := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.22
	cs.height = 1.6
	cyl.shape = cs
	walls.add_child(cyl)
	cyl.global_position = pos + Vector3(0, 0.8, 0)
	sellers.append({"node": holder, "ap": ap, "model": m, "pos": pos, "label": lb, "left": 0.0, "words": words,
		"rich": ap != null and ap.has_animation("Give"), "next": randf_range(4.0, 8.0)})


func seller_say(holder: Node, text := "") -> void:
	for s in sellers:
		if s["node"] == holder:
			var lb: Label3D = s["label"]
			lb.text = text if text != "" else String(s["words"])
			lb.visible = true
			s["left"] = 3.5
			if s["rich"]:
				var ap: AnimationPlayer = s["ap"]
				ap.play("Give" if randf() < 0.6 else "Wave", 0.25)
				s["next"] = randf_range(6.0, 10.0)


# ------------------------------------------------------------------ сітки: видимість, тіні
const INTERIOR := ["Інтер'єр", "Піч", "Стіл", "Стілець", "Лава", "Ліжко", "Постіль", "Табурет"]
const ROOF := ["_Дах", "Димар", "Мансарда", "Дахи", "Бані"]


func _setup_meshes() -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		var file := _file_of(mi)
		var far := 150.0
		var shadow := true
		if file == "bz_goods":
			far = 40.0                   # новий товар на прилавках (Базар_Село_Деталі.blend)
			shadow = false
		elif file == "bz_village_props":
			far = 90.0
			shadow = nm.contains("Криниця") or nm.contains("Журавель") or nm.begins_with("Копиця")
			if nm.begins_with("Копиця"):
				_hay_look(mi)
			if nm.begins_with("Стежка"):
				mi.material_override = Util.road_mat()
				shadow = false
		elif file == "bz_stalls" and not nm.begins_with("Ларьок") and nm != "Продавець_Риба":
			far = 45.0                   # товар на прилавках
			shadow = false
		elif file == "bz_fence":
			far = 90.0
			shadow = false
		elif _has_any(nm, INTERIOR):
			far = 28.0
			shadow = false
		elif nm.begins_with("Лавка") or nm.begins_with("Ліхтар") or nm.begins_with("Криниця") or nm.contains("Калітка") or nm.contains("Ворота"):
			far = 70.0
			shadow = false
		elif nm == "Дороги":
			far = 0.0
			shadow = false
			mi.material_override = Util.road_mat()
		elif file == "bz_houses":
			# дрібніші частини хат — лише зблизька (телефону легше)
			if nm.ends_with("Розпис"):
				far = 35.0
				shadow = false
			elif nm.ends_with("Двері"):
				far = 50.0
				shadow = false
			elif nm.ends_with("Вікна") or nm.ends_with("Ганок") and not nm.ends_with("Дах_Ганок"):
				far = 70.0
				shadow = false
			elif nm.ends_with("Димар") or nm.ends_with("Дах_Ганок") or nm.ends_with("Мансарда"):
				far = 95.0
				shadow = false
		elif file == "bz_misc" and nm.begins_with("Церква") and not (nm.ends_with("Дахи") or nm.ends_with("Колоди") or nm.ends_with("Бані") or nm.ends_with("Стіни")):
			# стіни церкви теж кидають тінь — інакше сонце світить між колодами смугами на підлогу, і вона мерехтить
			far = 80.0
			shadow = false
		mi.visibility_range_end = far
		mi.visibility_range_end_margin = 8.0 if far > 0.0 else 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shadow and (file == "bz_houses" or file == "bz_misc" or file == "bz_stalls"):
			# стіни й дахи — тінь з обох боків, щоб сонце не світило крізь стіну на підлогу
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


var _hay_mat: StandardMaterial3D


func _hay_look(mi: MeshInstance3D) -> void:
	## Копиця — золотисте сіно з соломинками (у моделі колір майже білий, на сонці копиця була схожа на яйце).
	if mi.mesh == null:
		return
	if _hay_mat == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.09
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.52, 0.38, 0.14))
		ramp.set_color(1, Color(0.93, 0.78, 0.40))
		ramp.add_point(0.55, Color(0.80, 0.62, 0.26))
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		tex.color_ramp = ramp
		_hay_mat = StandardMaterial3D.new()
		_hay_mat.albedo_texture = tex
		_hay_mat.roughness = 1.0
		_hay_mat.uv1_triplanar = true
		_hay_mat.uv1_scale = Vector3(1.6, 0.35, 1.6)       # витягнуто вздовж висоти — схоже на соломинки, що звисають
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m == null or not String(m.resource_name).begins_with("Дерево"):
			mi.set_surface_override_material(i, _hay_mat)


func _file_of(n: Node) -> String:
	var p := n
	while p != null and p.get_parent() != root:
		p = p.get_parent()
	return String(p.name) if p else ""


static func _has_any(s: String, keys: Array) -> bool:
	for k in keys:
		if s.contains(k):
			return true
	return false


# ------------------------------------------------------------------ будівлі, двері, тверді стіни
func _setup_buildings() -> void:
	var hs: Node = root.get_node_or_null("bz_houses")
	if hs:
		for h in hs.get_children():
			if not (h is Node3D) or h is MeshInstance3D:
				continue
			_add_building(h, "house")
	var misc: Node = root.get_node_or_null("bz_misc")
	if misc:
		var ch: Node = misc.get_node_or_null("Церква")
		if ch:
			_add_building(ch, "church")
			_church_extras(ch, buildings[buildings.size() - 1])
		for n in misc.get_children():
			var nm := String(n.name)
			if nm.begins_with("Криниця"):
				_solid(n as MeshInstance3D, true)
			elif nm.begins_with("Дерево"):
				var tr := n.find_child("*Стовбур", false, false) as MeshInstance3D
				if tr:
					_solid(tr, true)
	var ml: Node = root.get_node_or_null("bz_mill/Млин")
	if ml:
		_add_building(ml, "mill")
		for p in [["МлинРотор", Vector3.FORWARD, 1.2], ["МлинВал", Vector3.UP, -2.4], ["МлинЖорна_1", Vector3.UP, 7.2], ["МлинЖорна_2", Vector3.UP, 7.2]]:
			var mp := ml.get_node_or_null(String(p[0]))
			if mp:
				mill_parts.append([mp, p[1], p[2]])
	var st: Node = root.get_node_or_null("bz_stalls")
	if st:
		for n in st.get_children():
			var nm := String(n.name)
			if nm.begins_with("Ларьок") and not nm.contains("_Двері") and not nm.contains("Табурет"):
				_add_stall(n as MeshInstance3D)
	var fc: Node = root.get_node_or_null("bz_fence")
	if fc:
		for n in fc.get_children():
			_solid(n as MeshInstance3D, false)
	for b in buildings:
		if b["kind"] == "house":
			_hut_props(b)
	if _props_lib:
		_props_lib.free()
		_props_lib = null


func _add_building(h: Node3D, kind: String) -> void:
	var nm := String(h.name)
	var b := {"node": h, "kind": kind, "roofs": [], "box": AABB(), "name": nm, "furn": []}
	var wall_box := AABB()
	var first := true
	for c in h.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var cn := String(mi.name).trim_prefix(nm)
		if _has_any(cn, ROOF):
			b["roofs"].append(mi)
		elif cn.ends_with("Стіни"):
			_strip_up_faces(mi, 0.75, 0)      # «підлога» стін збігалася з підлогою інтер'єру — мерехтіла
			_solid(mi, false)
			var ab: AABB = mi.transform * mi.get_aabb()
			wall_box = ab if first else wall_box.merge(ab)
			first = false
		elif cn.ends_with("Інтер'єр") or cn.ends_with("Ганок") or cn.ends_with("Фундамент"):
			if kind == "church" and cn.ends_with("Інтер'єр"):
				# у церкві дві однакові підлоги одна в одній (світла й темна) — мерехтіли смугами;
				# лишаємо одну й робимо її темнішою
				_strip_up_faces(mi, 0.75, 1, 0.012)
			_floor(mi)
			if cn.ends_with("Інтер'єр"):
				var ceil := _split_ceiling(mi)
				if ceil:
					b["roofs"].append(ceil)
				if kind == "church":
					mi.set_surface_override_material(0, Util.mat(Color(0.4, 0.26, 0.15), 0.85))   # дошки темніші (після заміни сітки)
		elif cn.ends_with("Піч") or cn.ends_with("Стіл") or cn.ends_with("Ліжко"):
			_solid(mi, true)
		# меблі, до яких можна торкнутися: Ніка сяде, ляже чи поп'є
		if cn.contains("Стілець") or cn.ends_with("Лава") or cn.contains("Табурет"):
			_furn(mi, "sit", b)
			_solid_box(mi)                    # Ніка обходить стільці й лави, а не проходить крізь них
		elif cn.ends_with("Ліжко"):
			_furn(mi, "lie", b)
		elif cn.ends_with("Стіл"):
			_furn(mi, "drink", b)
		if kind == "church" and (cn.ends_with("Колоди") or cn.ends_with("Стіни") or cn.ends_with("Вікна")):
			# церква висока: коли Ніка всередині, стіни вище 3 м ховаємо (видно згори)
			var up := _split_ceiling(mi, 3.2, false)
			if up:
				b["roofs"].append(up)
		if cn.contains("Двері") or cn.contains("Калітка") or cn.contains("Ворота"):
			_add_door(mi, h, cn.contains("Калітка") or cn.contains("Ворота"))
	b["box"] = wall_box
	buildings.append(b)
	var c3 := h.global_position
	map_houses.append([c3.x, c3.z])


func _add_stall(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	_solid(mi, false)
	_floor(mi)
	var box := mi.get_aabb()
	var b := {"node": mi, "kind": "stall", "roofs": [], "box": box, "name": String(mi.name), "furn": []}
	var top := _split_ceiling(mi, 2.1, false)            # дах ларька — окремо, щоб ховати
	if top:
		b["roofs"].append(top)
	for sign_name in ["Вивіска_ковбаса", "Вивіска_льодяник"]:
		var sg := mi.get_parent().get_node_or_null(sign_name) as Node3D
		if sg and sg.global_position.distance_to(mi.global_position) < 2.0:
			b["roofs"].append(sg)
	buildings.append(b)
	var d := mi.get_parent().get_node_or_null(String(mi.name) + "_Двері") as MeshInstance3D
	if d:
		_add_door(d, mi, false)
	var stool := mi.get_parent().get_node_or_null(String(mi.name) + "_Табурет") as MeshInstance3D
	if stool:
		_furn(stool, "sit", b)
	map_houses.append([mi.global_position.x, mi.global_position.z])
	# торкнувся ларька — продавець цього ларька пропонує товар
	var c := mi.global_transform * box.get_center()
	for sd in sellers:
		if Vector2((sd["pos"] as Vector3).x - c.x, (sd["pos"] as Vector3).z - c.z).length() < 3.2 and sd.has("shop"):
			var a := Util.pick_area("bz_shop", box.size * Vector3(1.0, 0.6, 1.0), box.get_center() - Vector3(0, box.size.y * 0.2, 0))
			a.set_meta("seller", sd["node"])
			mi.add_child(a)
			break


func seller_of(n: Node) -> Dictionary:
	for sd in sellers:
		if sd["node"] == n:
			return sd
	return {}


func seller_near(p: Vector3, r: float) -> Dictionary:
	## Продавець, біля чийого ларька (у проході) стоїть Ніка.
	for sd in sellers:
		if sd.has("front") and Vector2((sd["front"] as Vector3).x - p.x, (sd["front"] as Vector3).z - p.z).length() < r:
			return sd
	return {}


func seller_give(sd: Dictionary) -> void:
	## Продавець подає товар (є свій рух — «Give»; немає — нахиляється вперед).
	if sd.is_empty():
		return
	var ap: AnimationPlayer = sd["ap"]
	if sd["rich"] and ap:
		ap.play("Give", 0.2)
		sd["next"] = randf_range(6.0, 10.0)
		return
	var h: Node3D = sd["node"]
	var to: Vector3 = (sd["front"] as Vector3) - (sd["pos"] as Vector3)
	to.y = 0.0
	var d := root.global_transform.basis.inverse() * to.normalized() * 0.18
	var p0 := h.position
	var tw := create_tween()
	tw.tween_property(h, "position", p0 + d, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(h, "position", p0, 0.45).set_trans(Tween.TRANS_SINE)


func _furn(mi: MeshInstance3D, act: String, b: Dictionary) -> void:
	## Невидима зона торкання на меблях; працює лише тоді, коли Ніка в цій будівлі.
	var ab := mi.get_aabb()
	var a := Util.pick_area("bz_furn", ab.size + Vector3(0.12, 0.12, 0.12), ab.get_center())
	a.set_meta("act", act)
	a.set_meta("box", ab)
	a.input_ray_pickable = false
	mi.add_child(a)
	b["furn"].append(a)


func world_box(b: Dictionary) -> AABB:
	## Коробка будівлі у світі (для камери всередині).
	var n: Node3D = b["node"]
	var box: AABB = b["box"]
	var out := AABB(n.global_transform * box.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(n.global_transform * box.get_endpoint(i))
	return out


func building_center(b: Dictionary) -> Vector3:
	var n: Node3D = b["node"]
	return n.global_transform * (b["box"] as AABB).get_center()


func table_of(b: Dictionary) -> Node3D:
	var n: Node3D = b["node"]
	for c in n.get_children():
		if String(c.name).ends_with("Стіл"):
			return c
	return null


var _ceil_cache := {}            # спільна сітка інтер'єру → [без стелі, стеля]


func _split_ceiling(mi: MeshInstance3D, min_y := 2.0, flat_only := true) -> MeshInstance3D:
	## Стеля входить у сітку інтер'єру разом із підлогою. Розрізаємо: стелю (горизонтальні
	## трикутники вище 2 м) — в окрему сітку, щоб ховати її разом із дахом, коли Ніка в хаті.
	var src: Mesh = mi.mesh
	if not _ceil_cache.has(src):
		var rest := ArrayMesh.new()
		var top := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for i in verts.size():
					idx.append(i)
			var keep := PackedInt32Array()
			var up := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				var a := verts[idx[t]]
				var b2 := verts[idx[t + 1]]
				var c := verts[idx[t + 2]]
				var n := (b2 - a).cross(c - a)
				var flat := not flat_only or (n.length() > 0.0 and absf(n.normalized().y) > 0.9)
				var hy := minf(a.y, minf(b2.y, c.y)) if flat_only else (a.y + b2.y + c.y) / 3.0
				if flat and hy > min_y:
					up.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			var mat := src.surface_get_material(si)
			for pair in [[rest, keep], [top, up]]:
				if (pair[1] as PackedInt32Array).is_empty():
					continue
				var a2 := arr.duplicate()
				a2[Mesh.ARRAY_INDEX] = pair[1]
				var m2: ArrayMesh = pair[0]
				m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
				m2.surface_set_material(m2.get_surface_count() - 1, mat)
		_ceil_cache[src] = [rest, top if top.get_surface_count() > 0 else null]
	var pair2: Array = _ceil_cache[src]
	if pair2[1] == null:
		return null
	mi.mesh = pair2[0]
	var cm := MeshInstance3D.new()
	cm.name = String(mi.name) + "_Верх"
	cm.mesh = pair2[1]
	cm.transform = mi.transform
	cm.visibility_range_end = 150.0
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.get_parent().add_child(cm)
	return cm


func _solid(mi: MeshInstance3D, convex: bool) -> void:
	if mi == null or mi.mesh == null:
		return
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_convex_shape(true, true) if convex else mi.mesh.create_trimesh_shape()
	walls.add_child(cs)
	cs.global_transform = mi.global_transform


func _solid_box(mi: MeshInstance3D) -> void:
	## Низькі меблі: тверда коробка 0.72 м заввишки (капсула Ніки починається на 0.55 м — низьку лаву інакше не «відчуває»).
	if mi == null or mi.mesh == null:
		return
	var ab := mi.get_aabb()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(ab.size.x, 0.72, ab.size.z)          # нижче за погляд камери (0.8 м) — камера крізь них бачить
	cs.shape = bx
	walls.add_child(cs)
	cs.global_transform = mi.global_transform * Transform3D(Basis(), Vector3(ab.get_center().x, ab.position.y + bx.size.y * 0.5, ab.get_center().z))


func _floor(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	floors.add_child(cs)
	cs.global_transform = mi.global_transform


func _add_door(d: MeshInstance3D, owner_node: Node3D, inward: bool) -> void:
	## Двері обертаються навколо свого початку координат (завіси). Відчиняються назовні,
	## ворота дворів — у двір.
	var center := owner_node.global_position
	var base := d.rotation.y
	var best := 0.0
	var best_d := -INF
	var ab := d.get_aabb()
	var mid := ab.get_center()
	for sgn in [-1.0, 1.0]:
		var t := d.global_transform
		var rot := Basis(Vector3.UP, deg_to_rad(95.0) * sgn)
		var pworld: Vector3 = t.origin + rot * (t.basis * mid)
		var dist := Vector2(pworld.x - center.x, pworld.z - center.z).length()
		var score := -dist if inward else dist
		if score > best_d:
			best_d = score
			best = sgn
	# «відкрито» в системі батька: той самий поворот навколо вертикалі світу
	var up_local: Vector3 = (d.get_parent() as Node3D).global_transform.basis.inverse() * Vector3.UP
	doors.append({"node": d, "base": d.transform, "axis": up_local.normalized(), "sign": best, "k": 0.0, "want": 0.0,
		"pos": d.global_transform * mid})


# ------------------------------------------------------------------ щокадру
func step(delta: float, who: Array, cam: Vector3, me := Vector3.INF) -> void:
	## who — хто ходить (позиції); cam — де камера.
	for m in mill_parts:
		(m[0] as Node3D).rotate_object_local(m[1], float(m[2]) * delta)
	_acc += delta
	if _acc > 0.2:
		_acc = 0.0
		for d in doors:
			var p: Vector3 = d["pos"]
			var near := false
			for q in who:
				var v: Vector3 = q
				if absf(v.x - p.x) < 2.2 and absf(v.z - p.z) < 2.2:
					near = true
					break
			if not near and d.get("held", false):
				# ці двері Ніка відчинила сама — тримаємо, поки вона поруч
				if me != Vector3.INF and absf(me.x - p.x) < 2.6 and absf(me.z - p.z) < 2.6:
					near = true
				else:
					d["held"] = false
			d["want"] = 1.0 if near or int(d.get("npc", 0)) > 0 else 0.0
		for s in sellers:
			var far: bool = (s["pos"] as Vector3).distance_to(cam) > 60.0
			(s["model"] as Node3D).visible = not far
			if s["ap"]:
				(s["ap"] as AnimationPlayer).active = not far
	for d in doors:
		var k: float = d["k"]
		var w: float = d["want"]
		if absf(k - w) < 0.001:
			continue
		k = move_toward(k, w, delta * 1.8)
		d["k"] = k
		var e := k * k * (3.0 - 2.0 * k)
		var tr: Transform3D = d["base"]
		var r := Basis(d["axis"], deg_to_rad(95.0) * float(d["sign"]) * e)
		(d["node"] as Node3D).transform = Transform3D(r * tr.basis, tr.origin)
	for s in sellers:
		if s["rich"] and (s["model"] as Node3D).visible:
			_seller_life(s, delta)
		if s["left"] > 0.0:
			s["left"] = float(s["left"]) - delta
			if s["left"] <= 0.0:
				(s["label"] as Label3D).visible = false


func _seller_life(s: Dictionary, delta: float) -> void:
	## Продавець із кількома рухами: стоїть, час від часу говорить руками чи махає; потім знову стоїть.
	var ap: AnimationPlayer = s["ap"]
	if ap.current_animation != "Idle" and not ap.is_playing():
		ap.play("Idle", 0.3)
	s["next"] = float(s["next"]) - delta
	if s["next"] <= 0.0:
		s["next"] = randf_range(7.0, 14.0)
		if ap.current_animation == "Idle":
			ap.play("Talk" if randf() < 0.65 else "Wave", 0.3)
			if randf() < 0.35:
				var lb: Label3D = s["label"]
				lb.text = STUDENT_LINES[randi() % STUDENT_LINES.size()]
				lb.visible = true
				s["left"] = 3.0


func building_at(p: Vector3):
	## Будівля, всередині якої точка p (або null).
	if not in_area(p):
		return null
	for b in buildings:
		var n: Node3D = b["node"]
		var box: AABB = b["box"]
		if box.size == Vector3.ZERO:
			continue
		var q: Vector3 = (n.global_transform.affine_inverse() * (p + Vector3(0, 0.5, 0)))
		if box.grow(-0.05).has_point(q):
			return b
	return null


var lamp: OmniLight3D            # світло в будівлі, де зараз Ніка (дах лишається — дивимось зсередини)
var ceil_mi: MeshInstance3D      # стеля над стінами (щоб зсередини не було видно неба крізь дах)


func set_inside(b) -> void:
	## Ніка зайшла в будівлю: вмикаємо світло всередині й торкання меблів.
	if b == inside:
		return
	if inside:
		for a in inside["furn"]:
			(a as Area3D).input_ray_pickable = false
	inside = b
	if lamp == null:
		lamp = OmniLight3D.new()
		lamp.name = "RoomLamp"
		lamp.light_color = Color(1.0, 0.93, 0.8)
		lamp.shadow_enabled = false
		add_child(lamp)
	lamp.visible = inside != null
	if ceil_mi == null:
		ceil_mi = MeshInstance3D.new()
		ceil_mi.name = "RoomCeiling"
		ceil_mi.mesh = BoxMesh.new()
		ceil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ceil_mi.material_override = Util.mat(Color(0.93, 0.89, 0.8), 0.9)
		add_child(ceil_mi)
	ceil_mi.visible = inside != null and not (inside["kind"] in ["stall", "shed"])
	if inside:
		var lb: AABB = inside["box"]
		(ceil_mi.mesh as BoxMesh).size = Vector3(lb.size.x - 0.05, 0.05, lb.size.z - 0.05)
		ceil_mi.global_transform = (inside["node"] as Node3D).global_transform * Transform3D(Basis(), Vector3(lb.get_center().x, lb.end.y - 0.03, lb.get_center().z))
		for a in inside["furn"]:
			(a as Area3D).input_ray_pickable = true
		var wb := world_box(inside)
		lamp.global_position = wb.get_center() + Vector3(0, minf(wb.size.y * 0.25, 1.0), 0)
		lamp.omni_range = maxf(wb.size.x, wb.size.z) * 0.85 + 1.0
		lamp.light_energy = 1.4 if inside["kind"] != "church" else 2.0


func floor_y(p: Vector3, cur_y: float) -> float:
	## Висота підлоги під ногами (хата, ганок, ларьок), інакше — земля.
	if not in_area(p):
		return 0.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, cur_y + 0.62, p.z), Vector3(p.x, -0.5, p.z), FLOOR)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	return maxf(0.0, float((hit["position"] as Vector3).y))


# ------------------------------------------------------------------ Ніка сама відчиняє двері й хвіртки
func door_ahead(p: Vector3, dir: Vector3):
	## Зачинені двері (чи ворітця) просто перед Нікою — ті, що вона зараз відчинить рукою.
	if dir.length() < 0.1:
		return null
	for d in doors:
		if float(d["want"]) > 0.5 or float(d["k"]) > 0.3:
			continue
		var q: Vector3 = d["pos"]
		var to := Vector3(q.x - p.x, 0, q.z - p.z)
		var dist := to.length()
		if dist < 1.15 and dist > 0.05 and absf(q.y - p.y) < 2.2 and to.normalized().dot(dir) > 0.35:
			return d
	return null


func open_by_hand(d: Dictionary, from := Vector3.INF) -> void:
	if from != Vector3.INF and float(d["k"]) < 0.05:
		_swing_away(d, from)
	d["want"] = 1.0
	d["held"] = true


func _swing_away(d: Dictionary, from: Vector3) -> void:
	## Стулка відчиняється від того, хто відчиняє, а не крізь нього.
	var n := d["node"] as Node3D
	var hinge: Vector3 = (n.get_parent() as Node3D).global_transform * (d["base"] as Transform3D).origin
	var v: Vector3 = (d["pos"] as Vector3) - hinge
	v.y = 0.0
	var best := float(d["sign"])
	var best_d := -INF
	for sgn in [-1.0, 1.0]:
		var q: Vector3 = hinge + Basis(Vector3.UP, deg_to_rad(95.0) * sgn) * v
		var dd := Vector2(q.x - from.x, q.z - from.z).length()
		if dd > best_d:
			best_d = dd
			best = sgn
	d["sign"] = best


# ------------------------------------------------------------------ товар: старий простий прибираємо (новий — у bz_goods)
const OLD_GOODS := ["Риба_Ящик_1", "Риба_Ящик_2", "Тараня_в'язка", "Овочі_Картопля", "Овочі_Морква", "Овочі_Капуста", "Овочі_Цибуля",
	"Овочі_Буряк", "Глечик_молоко_1", "Глечик_молоко_2", "Глечик_молоко_3", "Сир_круг_1", "Сир_круг_2", "Бринза_дошка", "Кошик_яйця",
	"Глечик_зелений_1", "Глечик_коричневий", "Глечик_зелений_2", "Горщик_1", "Горщик_2", "Макітра", "Миски_1", "Миски_2", "Тарілка_1",
	"Тарілка_2", "Тарілка_3", "Рушники_стос_1", "Рушники_стос_2", "Рушники_стос_3", "Вишиванки_стос_1", "Вишиванки_стос_2", "Рушники_висять"]


func _remove_old_goods() -> void:
	var stl: Node = root.get_node_or_null("bz_stalls")
	if stl == null or root.get_node_or_null("bz_goods") == null:
		return
	for nm in OLD_GOODS:
		var o := stl.find_child(nm, true, false)
		if o:
			o.get_parent().remove_child(o)
			o.free()


# ------------------------------------------------------------------ старе село: тин, ворітця, лавки, город, копиці, криниця з журавлем
var village_nodes: Array = []                    # [вузол хати, [позиція, поворот, зелена?]]
var village_info: Array = []                     # для працівників ферми: точки від хати крізь двері й хвіртку на вулицю


func _village_way(pos: Vector3, bs: Basis, dmi: Node, gleaf: Node, dl: Vector3, side: float, gx: float, gz: float, hx: float, zf: float) -> void:
	## Шлях із хати: усередині → за дверима → перед хвірткою (у дворі) → за хвірткою → вулиця; де стоїть велосипед.
	var w := func(v: Vector3) -> Vector3:
		return pos + bs * v
	var e := {"pos": pos, "door": dmi, "gate": gleaf, "door_at": w.call(Vector3(dl.x, 0, dl.z))}
	var bike_p: Vector3
	var bike_f: Vector3
	if side == 0.0:
		e["inside"] = w.call(Vector3(dl.x, 0, dl.z - 1.0))
		e["door_out"] = w.call(Vector3(dl.x, 0, dl.z + 1.0))
		e["gate_at"] = w.call(Vector3(gx, 0, zf))
		e["gate_in"] = w.call(Vector3(gx, 0, zf - 1.1))
		e["gate_out"] = w.call(Vector3(gx, 0, zf + 1.1))
		e["street"] = w.call(Vector3(gx, 0, zf + 2.2))
		var sb := 1.0 if gx <= 0.0 else -1.0            # лавочка — з цього боку від хвіртки, велосипед — з іншого
		bike_p = Vector3(clampf(gx - sb * 2.3, -hx + 0.8, hx - 0.8), 0, zf + 0.8)
		bike_f = Vector3(-1, 0, 0)
	else:
		e["inside"] = w.call(Vector3(dl.x - side * 1.0, 0, dl.z))
		e["door_out"] = w.call(Vector3(dl.x + side * 1.0, 0, dl.z))
		e["gate_at"] = w.call(Vector3(side * hx, 0, gz))
		e["gate_in"] = w.call(Vector3(side * (hx - 1.1), 0, gz))
		e["gate_out"] = w.call(Vector3(side * (hx + 1.1), 0, gz))
		e["street"] = w.call(Vector3(side * (hx + 0.8), 0, zf + 1.5))
		bike_p = Vector3(side * (hx + 2.0), 0, zf - 2.0)
		bike_f = Vector3(0, 0, -side)
	var fw: Vector3 = bs * bike_f
	e["bike"] = Transform3D(Basis(Vector3.UP, atan2(fw.x, fw.z)), w.call(bike_p))
	village_info.append(e)


func hut_info(p: Vector3) -> Dictionary:
	## Точки хати старого села, найближчої до p.
	var best := {}
	var bd := INF
	for e in village_info:
		var d: float = (e["pos"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best if bd < 8.0 else {}


func npc_door(n: Node, open: bool, from := Vector3.INF) -> void:
	## Працівник ферми сам відчиняє (і тримає) або зачиняє двері чи хвіртку.
	if n == null:
		return
	for d in doors:
		if d["node"] != n:
			continue
		if open:
			if from != Vector3.INF and float(d["k"]) < 0.05:
				_swing_away(d, from)
			d["npc"] = int(d.get("npc", 0)) + 1
			d["want"] = 1.0
		else:
			d["npc"] = maxi(0, int(d.get("npc", 0)) - 1)
		return
const VILLAGE_WELL := Vector3(13.0, 0, 58.0)
const VILLAGE_GARDEN := Vector3(0, 0, -9.4)      # центр городу (6.4 × 4.6 м) у системі садиби: за заднім тином (z = -6.4)


func _vput(lib: Node, holder: Node3D, inv: Transform3D, src: String, w: Transform3D) -> Node3D:
	var s := lib.find_child(src, true, false) as Node3D
	if s == null:
		s = lib.find_child(src + "_0*", true, false) as Node3D          # Blender міг дописати .001
	if s == null:
		return null
	var n := s.duplicate() as Node3D
	holder.add_child(n)
	n.transform = inv * w
	return n


func _path_piece(lib: Node, holder: Node3D, inv: Transform3D, pos: Vector3, bs: Basis, p0: Vector3, p1: Vector3) -> void:
	## Шматок стежки від p0 до p1 (у системі садиби). «Стежка_10м» лежить від z = -10 до 0 (початок — на кінці),
	## тож ставимо її кінцем у p1; з обох боків трохи довша — на зламах без щілин.
	var L2 := p0.distance_to(p1)
	if L2 < 0.4:
		return
	const PW := 0.6                                   # пів ширини стежки
	const PY := 0.025
	var a := pos + bs * p0
	var b := pos + bs * p1
	var d2 := Vector2(b.x - a.x, b.z - a.z).normalized()
	var sd := Vector3(-d2.y, 0, d2.x) * PW
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = [a + sd, b + sd, a - sd, a - sd, b + sd, b - sd]
	# круглі кінці — шматки зливаються на зламах і перехрестях без щілин і кутів
	for c in [a, b]:
		for k in 20:
			var a0 := TAU * k / 20.0
			var a1 := TAU * (k + 1) / 20.0
			pts.append(c)
			pts.append(c + Vector3(cos(a1), 0, sin(a1)) * PW)
			pts.append(c + Vector3(cos(a0), 0, sin(a0)) * PW)
	pts.reverse()                                     # лицем угору (інакше видно зворот — темна смуга)
	for v in pts:
		st.set_normal(Vector3.UP)
		st.add_vertex(inv * Vector3((v as Vector3).x, PY, (v as Vector3).z))
	var mi := MeshInstance3D.new()
	mi.name = "Стежка"
	mi.mesh = st.commit()
	mi.material_override = Util.road_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi, true)


func _road_grid() -> Dictionary:
	## Трикутники доріг базару (x, z), розкладені по клітинках 4 м — щоб швидко знайти, де вулиця.
	var out := {}
	var rd := root.find_child("Дороги", true, false) as MeshInstance3D
	if rd == null or rd.mesh == null:
		return out
	var f := rd.mesh.get_faces()
	var xf := rd.global_transform
	for i in range(0, f.size() - 2, 3):
		var a := xf * f[i]
		var b := xf * f[i + 1]
		var c := xf * f[i + 2]
		var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
		var x0 := int(floor(minf(a.x, minf(b.x, c.x)) / 4.0))
		var x1 := int(floor(maxf(a.x, maxf(b.x, c.x)) / 4.0))
		var z0 := int(floor(minf(a.z, minf(b.z, c.z)) / 4.0))
		var z1 := int(floor(maxf(a.z, maxf(b.z, c.z)) / 4.0))
		for gx in range(x0, x1 + 1):
			for gz in range(z0, z1 + 1):
				var key := Vector2i(gx, gz)
				if not out.has(key):
					out[key] = []
				out[key].append(tri)
	return out


func _on_bz_road(grid: Dictionary, p: Vector3) -> bool:
	var key := Vector2i(int(floor(p.x / 4.0)), int(floor(p.z / 4.0)))
	if not grid.has(key):
		return false
	var q := Vector2(p.x, p.z)
	for tri in grid[key]:
		var t: PackedVector2Array = tri
		if Geometry2D.point_is_inside_triangle(q, t[0], t[1], t[2]):
			return true
	return false


func _house_paths(lib: Node, holder: Node3D, inv: Transform3D) -> void:
	## Стежки до хвірток хат базару: з вулиці — до калітки, від калітки — до ґанку.
	var hs: Node3D = root.get_node_or_null("bz_houses")
	if hs == null:
		return
	var grid := _road_grid()
	var nb := 0
	for h in hs.get_children():
		var hn := String(h.name)
		if not (h is Node3D) or h is MeshInstance3D or not hn.begins_with("Хата") or hn.begins_with("Село_"):
			continue
		var kal := (h as Node3D).find_child("*Калітка", false, false) as MeshInstance3D
		if kal == null:
			continue
		var ht := (h as Node3D).global_transform
		var pos := ht.origin
		var bs := ht.basis.orthonormalized()
		var green := hn.begins_with("Хата_Зелена")
		# калітка (центр) і куди від неї «назовні» — у системі хати
		var kc: Vector3 = bs.inverse() * (kal.global_transform * kal.get_aabb().get_center() - pos)
		kc.y = 0.0
		var out_dir: Vector3 = Vector3(0, 0, 1) if green else Vector3(-1, 0, 0)
		var inner := kc - out_dir * 1.2
		var porch: Vector3 = Vector3(-2.6, 0, 5.0) if green else Vector3(-6.9, 0, 0.0)
		var corner: Vector3 = Vector3(porch.x, 0, inner.z) if green else Vector3(inner.x, 0, porch.z)
		# з вулиці: шукаємо найближчу дорогу назовні (до 14 м), інакше — коротка стежка 2 м
		var reach := 2.0
		var s := 1.0
		while s <= 14.0:
			if _on_bz_road(grid, pos + bs * (kc + out_dir * s)):
				reach = s + 0.5
				break
			s += 0.5
		_path_piece(lib, holder, inv, pos, bs, kc + out_dir * reach, kc)
		_path_piece(lib, holder, inv, pos, bs, kc, inner)
		_path_piece(lib, holder, inv, pos, bs, inner, corner)
		_path_piece(lib, holder, inv, pos, bs, corner, porch)
		# лавочка біля хати: за тином обабіч хвіртки (з того боку, де немає воріт), сидінням до вулиці
		var lat := Vector3(out_dir.z, 0, -out_dir.x)
		if kc.dot(lat) > 0.0:
			lat = -lat
		var bbs := bs * Basis(Vector3.UP, atan2(out_dir.x, out_dir.z))
		nb += 1
		var bench := _vput(lib, holder, inv, "Лавка_спинка" if nb % 2 == 0 else "Лавка", Transform3D(bbs, pos + bs * (kc + out_dir * 0.55 + lat * 2.4)))
		if bench is MeshInstance3D:
			var bab := (bench as MeshInstance3D).get_aabb()
			var ba := Util.pick_area("bz_furn", bab.size + Vector3(0.12, 0.12, 0.12), bab.get_center())
			ba.set_meta("act", "sit")
			ba.set_meta("box", bab)
			ba.set_meta("edge", true)                  # Ніка сідає на край лавочки
			ba.set_meta("face", bbs * Vector3(0, 0, 1))
			bench.add_child(ba)


func _stall_trees() -> void:
	## Дерева за ларьками: за кожним рядом ларьків, за 7 м від їхніх задніх стінок.
	var mn := root.get_node_or_null("bz_misc") as Node3D
	if mn == null:
		return
	var src := mn.find_child("Дерево", false, false) as Node3D
	if src == null:
		return
	var grid := _road_grid()
	var wo = get_parent()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7707
	# ряди ларьків у файлі: z = 0 (задні стінки на z = -1.02) і z = 6.32 (задні стінки на z = 7.34), уздовж x від 3.4 до 24.6
	var k := 0
	for zr in [-1.02 - 7.0, 6.32 + 1.02 + 7.0]:
		for x in [4.0, 10.5, 17.0, 23.5]:
			k += 1
			var t := src.duplicate() as Node3D
			t.name = "Дерево_ларьки_%d" % k
			mn.add_child(t)
			t.position = Vector3(x + rng.randf_range(-0.6, 0.6), 0, zr)
			t.rotation = Vector3(0, rng.randf() * TAU, 0)
			t.scale = Vector3.ONE * rng.randf_range(0.85, 1.05)
			var gp := t.global_position
			if _on_bz_road(grid, gp):
				mn.remove_child(t)
				t.free()
				continue
			if wo and "trees" in wo:                  # стовбур твердий — як і в інших дерев базару (_setup_buildings)
				wo.trees.append([gp.x, gp.z])


func _wall_box(center: Vector3, yaw: float, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	walls.add_child(cs)
	cs.global_transform = Transform3D(Basis(Vector3.UP, yaw), center)


func _village_props() -> void:
	if not ResourceLoader.exists(DIR % "bz_village"):
		return
	var lib: Node3D = load(DIR % "bz_village").instantiate()
	var holder := Node3D.new()
	holder.name = "bz_village_props"
	root.add_child(holder)
	var inv := root.transform.affine_inverse()
	var wo = get_parent()
	var k := 0
	for vn in village_nodes:
		var h: Node3D = vn[0]
		var sp: Array = vn[1]
		var pos: Vector3 = sp[0]
		var bs := Basis(Vector3.UP, float(sp[1]))
		k += 1
		# двері хати: калітку ставимо просто навпроти них, стежка — від вулиці до калітки й далі до ґанку
		var hx := 6.0
		var zf := 7.2
		var zb := -6.4
		var dl := Vector3(0, 0, 2.5)
		var dmi := h.find_child("*Двері*", false, false) as MeshInstance3D
		if dmi:
			var dw := dmi.global_transform * dmi.get_aabb().get_center()
			var dd := bs.inverse() * (dw - pos)
			dl = Vector3(dd.x, 0, dd.z)
		var rel := dl - Vector3(0, 0, -1.0)
		var side := 0.0                                     # 0 — двері дивляться на вулицю, ±1 — убік
		if absf(rel.x) > absf(rel.z) * 1.2:
			side = signf(rel.x)
		var gx := clampf(dl.x, -hx + 1.2, hx - 1.2)
		var gz := clampf(dl.z, zb + 1.2, zf - 1.2)
		var sides := [[Vector3(-hx, 0, zf), Vector3(hx, 0, zf), side == 0.0, gx], [Vector3(hx, 0, zf), Vector3(hx, 0, zb), side > 0.0, gz],
			[Vector3(hx, 0, zb), Vector3(-hx, 0, zb), false, 0.0], [Vector3(-hx, 0, zb), Vector3(-hx, 0, zf), side < 0.0, gz]]
		var segs: Array = []
		for sd in sides:
			var p0: Vector3 = sd[0]
			var p1: Vector3 = sd[1]
			if not sd[2]:
				segs.append([p0, p1])
				continue
			var along := (p1 - p0).normalized()
			var g: float = sd[3]
			var gc := Vector3(g, 0, p0.z) if absf(along.x) > 0.5 else Vector3(p0.x, 0, g)
			segs.append([p0, gc - along * 0.75])
			segs.append([gc + along * 0.75, p1])
		var si := 0
		for sg in segs:
			var a: Vector3 = pos + bs * (sg[0] as Vector3)
			var b: Vector3 = pos + bs * (sg[1] as Vector3)
			var L := a.distance_to(b)
			if L < 0.3:
				continue
			var n := maxi(1, roundi(L / 3.0))
			var yaw := atan2(-(b.z - a.z), b.x - a.x)
			for i in n:
				var c := a.lerp(b, (i + 0.5) / float(n))
				si += 1
				var src := "Тин_глечики_3м" if si % 4 == 2 else "Тин_3м"
				_vput(lib, holder, inv, src, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(L / n / 3.0, 1.0, 1.0)), c))
			_wall_box((a + b) / 2.0 + Vector3(0, 0.65, 0), yaw, Vector3(L, 1.3, 0.14))
		var gate_xf := Transform3D(bs, pos + bs * Vector3(gx, 0, zf))
		if side != 0.0:
			gate_xf = Transform3D(bs * Basis(Vector3.UP, PI / 2.0), pos + bs * Vector3(side * hx, 0, gz))
		var gate := _vput(lib, holder, inv, "Ворітця", gate_xf)
		var gleaf: MeshInstance3D = null
		if gate:
			var leaf := gate.find_child("Ворітця_стулка*", true, false) as MeshInstance3D
			if leaf:
				_add_door(leaf, h, true)
				gleaf = leaf
		_village_way(pos, bs, dmi, gleaf, dl, side, gx, gz, hx, zf)
		var bxl := gx + (2.6 if gx <= 0.0 else -2.6)
		var bench := _vput(lib, holder, inv, "Лавка_спинка" if k % 2 == 0 else "Лавка", Transform3D(bs, pos + bs * Vector3(bxl, 0, zf + 0.55)))
		if bench is MeshInstance3D:
			var bab := (bench as MeshInstance3D).get_aabb()
			var ba := Util.pick_area("bz_furn", bab.size + Vector3(0.12, 0.12, 0.12), bab.get_center())
			ba.set_meta("act", "sit")
			ba.set_meta("box", bab)
			ba.set_meta("edge", true)
			ba.set_meta("face", bs * Vector3(0, 0, 1))
			bench.add_child(ba)
		# стежки (шматок «Стежка_10м» — 10 м уздовж своєї осі z)
		var path := func(p0: Vector3, p1: Vector3) -> void:
			_path_piece(lib, holder, inv, pos, bs, p0, p1)
		if side == 0.0:
			path.call(Vector3(gx, 0, zf + 9.6), Vector3(gx, 0, zf))                   # з вулиці — до калітки
			path.call(Vector3(gx, 0, zf), Vector3(gx, 0, maxf(dl.z + 0.5, zb + 1.0)))  # від калітки — до дверей
		else:
			var ox := side * (hx + 0.8)
			path.call(Vector3(ox, 0, zf + 9.6), Vector3(ox, 0, gz))                    # уздовж тину — до бічної калітки
			path.call(Vector3(ox, 0, gz), Vector3(side * hx, 0, gz))
			path.call(Vector3(side * hx, 0, gz), Vector3(dl.x + side * 0.5, 0, gz))     # від калітки — до дверей
		# город і копиця — за тином позаду хати (раніше стояли між садибами, і тин сусіда йшов крізь грядки й копицю)
		_vput(lib, holder, inv, "Город", Transform3D(bs, pos + bs * VILLAGE_GARDEN))
		var hp := pos + bs * Vector3(4.8 if k % 2 == 1 else -4.8, 0, -8.6)
		var hay := _vput(lib, holder, inv, "Копиця" if k % 2 == 1 else "Копиця_мала", Transform3D(bs, hp))
		if hay is MeshInstance3D:
			_solid(hay as MeshInstance3D, true)
		if wo and "_obst" in wo:
			wo._obst.append([hp.x, hp.z, 1.1, 2.0])
	var well: Node3D = null      # криниця з журавлем стирчала з кута хати старого села — прибрано
	if well:
		for nm in ["Криниця_зруб", "Журавель_стовп"]:
			var m := well.find_child(nm + "*", true, false) as MeshInstance3D
			if m:
				_solid(m, true)
		if wo and "_obst" in wo:
			wo._obst.append([VILLAGE_WELL.x, VILLAGE_WELL.z, 1.0, 2.0])
			var post: Vector3 = VILLAGE_WELL + Basis(Vector3.UP, 0.4) * Vector3(-2.4, 0, 0)
			wo._obst.append([post.x, post.z, 0.35, 3.3])
	_house_paths(lib, holder, inv)
	lib.free()


# ------------------------------------------------------------------ у хатах: хліб і посуд на столі, подушки й ковдра, ікона, рушник, відро
var _props_lib: Node3D = null


func _prop(h: Node3D, src: String, at: Vector3, yaw: float, scl: Vector3) -> void:
	var s := _props_lib.find_child(src, true, false) as Node3D
	if s == null:
		s = _props_lib.find_child(src + "_0*", true, false) as Node3D
	if s == null:
		return
	var n := s.duplicate() as Node3D
	n.name = "Prop_" + src
	h.add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scl), at)
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for mi in list:
		(mi as MeshInstance3D).visibility_range_end = 24.0
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi != n:
			Util.make_takeable(mi as MeshInstance3D, "prop", 0.6)     # миски, глечики, горщики — можна взяти в руки


func _hut_props(b: Dictionary) -> void:
	if _props_lib == null:
		if not ResourceLoader.exists(DIR % "bz_hutprops"):
			return
		_props_lib = load(DIR % "bz_hutprops").instantiate()
	var h: Node3D = b["node"]
	var box: AABB = b["box"]
	if box.size == Vector3.ZERO:
		return
	var part := {}
	var pmi := {}
	for c in h.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		for key in ["Стіл", "Ліжко", "Постіль", "Піч"]:
			if String(mi.name).ends_with(key) and not part.has(key):
				part[key] = mi.transform * mi.get_aabb()
				pmi[key] = mi
	var mid := box.get_center()
	var floor_y: float = (part["Стіл"] as AABB).position.y if part.has("Стіл") else box.position.y
	if part.has("Стіл"):
		var t: AABB = part["Стіл"]
		var span := maxf(t.size.x, t.size.z)
		var depth := minf(t.size.x, t.size.z)
		var s := clampf(minf((span - 0.1) / 0.9, (depth - 0.06) / 0.45), 0.5, 1.0)
		# стільниця — справжня верхня площина сітки над серединою столу (а не верх коробки: продукти висіли в повітрі)
		var ty := _top_local([pmi["Стіл"]], t.get_center(), t.end.y + 0.01)
		if ty == -INF:
			ty = t.end.y
		var yaw_t := 0.0 if t.size.x >= t.size.z else PI / 2.0
		_prop(h, "Набір_стіл", Vector3(t.get_center().x, ty, t.get_center().z), yaw_t, Vector3.ONE * s)
		_table_food(h, Vector3(t.get_center().x, ty, t.get_center().z), yaw_t, s, span, depth)
	if part.has("Ліжко"):
		var bd: AABB = part["Ліжко"]
		var top: float = (part["Постіль"] as AABB).end.y if part.has("Постіль") else bd.end.y
		var bed_mis: Array = [pmi["Ліжко"]]
		if pmi.has("Постіль"):
			bed_mis.append(pmi["Постіль"])
		var lx := bd.size.x >= bd.size.z
		var ax := Vector3(1, 0, 0) if lx else Vector3(0, 0, 1)
		var blen := bd.size.x if lx else bd.size.z
		var bw := bd.size.z if lx else bd.size.x
		var bc := bd.get_center()
		var e1 := bc + ax * blen * 0.5
		var e2 := bc - ax * blen * 0.5
		var head := ax if Vector2(e1.x - mid.x, e1.z - mid.z).length() > Vector2(e2.x - mid.x, e2.z - mid.z).length() else -ax
		var yaw := PI / 2.0 if lx else 0.0
		# подушки й ковдра лягають на матрац (найвища площина постелі під ними, а не верх спинки ліжка)
		var pil := Vector3(bc.x, 0, bc.z) + head * (blen * 0.5 - 0.3)
		var bl := Vector3(bc.x, 0, bc.z) - head * 0.28
		var tp := _top_local(bed_mis, pil, top - 0.02)
		var tb := -INF
		for q in [bl, bl + head * 0.45, bl - head * 0.45]:
			tb = maxf(tb, _top_local(bed_mis, q, top - 0.02))
		if tp == -INF:
			tp = top
		if tb == -INF:
			tb = top
		_prop(h, "Набір_подушки", Vector3(pil.x, tp, pil.z), yaw, Vector3.ONE * clampf(bw / 0.95, 0.6, 1.0))
		_prop(h, "Набір_ковдра", Vector3(bl.x, tb + 0.005, bl.z), yaw, Vector3(bw * 0.95 / 1.6, 1.0, maxf(blen - 0.6, 0.6) / 1.9))
		# рушник — на найближчій до ліжка стіні
		var opts := [[bc.x - box.position.x, Vector3(box.position.x + 0.22, floor_y, bc.z), PI / 2.0],
			[box.end.x - bc.x, Vector3(box.end.x - 0.22, floor_y, bc.z), -PI / 2.0],
			[bc.z - box.position.z, Vector3(bc.x, floor_y, box.position.z + 0.22), 0.0],
			[box.end.z - bc.z, Vector3(bc.x, floor_y, box.end.z - 0.22), PI]]
		var best: Array = opts[0]
		for o in opts:
			if float(o[0]) < float(best[0]):
				best = o
		_prop(h, "Набір_рушник", best[1], float(best[2]), Vector3.ONE)
	# ікона — у кутку навскоси від печі (покуть)
	var stove: Vector3 = (part["Піч"] as AABB).get_center() if part.has("Піч") else mid + Vector3(1, 0, 1)
	var corner := Vector3.ZERO
	var far := -1.0
	for cx in [box.position.x + 0.35, box.end.x - 0.35]:
		for cz in [box.position.z + 0.35, box.end.z - 0.35]:
			var dd := Vector2(float(cx) - stove.x, float(cz) - stove.z).length()
			if dd > far:
				far = dd
				corner = Vector3(cx, 0, cz)
	var to_mid := Vector3(mid.x - corner.x, 0, mid.z - corner.z).normalized()
	_prop(h, "Набір_ікона", Vector3(corner.x, floor_y + 1.5, corner.z), atan2(to_mid.x, to_mid.z), Vector3.ONE)
	# відро з водою на ослоні — біля печі, з боку хати
	if part.has("Піч"):
		var pc: AABB = part["Піч"]
		var c := pc.get_center()
		var d := Vector3(mid.x - c.x, 0, mid.z - c.z)
		var dir := Vector3(signf(d.x), 0, 0) if absf(d.x) * pc.size.z > absf(d.z) * pc.size.x else Vector3(0, 0, signf(d.z))
		if dir == Vector3.ZERO:
			dir = Vector3(0, 0, 1)
		var perp := Vector3(-dir.z, 0, dir.x)
		var ext := pc.size.x * 0.5 if dir.x != 0.0 else pc.size.z * 0.5
		var ext2 := pc.size.z * 0.5 if dir.x != 0.0 else pc.size.x * 0.5
		var at := c + dir * (ext + 0.3) + perp * maxf(ext2 - 0.25, 0.0)
		_prop(h, "Набір_відро", Vector3(at.x, floor_y, at.z), atan2(dir.x, dir.z), Vector3.ONE)


func _top_local(mis: Array, p: Vector3, ymax: float) -> float:
	## Найвища горизонтальна поверхня сітки (у системі хати) просто над точкою p, нижча за ymax.
	var best := -INF
	for m in mis:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := mi.transform
		var tris: PackedVector3Array = mi.mesh.get_faces()
		for i in range(0, tris.size() - 2, 3):
			var a: Vector3 = xf * tris[i]
			var b: Vector3 = xf * tris[i + 1]
			var c: Vector3 = xf * tris[i + 2]
			var d := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
			if absf(d) < 1e-7:
				continue
			var l1 := ((b.x - p.x) * (c.z - p.z) - (c.x - p.x) * (b.z - p.z)) / d
			var l2 := ((c.x - p.x) * (a.z - p.z) - (a.x - p.x) * (c.z - p.z)) / d
			var l3 := 1.0 - l1 - l2
			if l1 < -0.001 or l2 < -0.001 or l3 < -0.001:
				continue
			var y := a.y * l1 + b.y * l2 + c.y * l3
			if y < ymax and y > best:
				best = y
	return best


# ------------------------------------------------------------------ їжа на столі: торкнешся — Ніка візьме й з'їсть (вип'є)
var table_items: Array = []           # {"parent", "xf", "kind", "node"}
var _food_t := 0.0


func _table_food(h: Node3D, top: Vector3, yaw: float, s: float, span: float, depth: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var ax := b * Vector3(1, 0, 0)
	var az := b * Vector3(0, 0, 1)
	var half_l := maxf(span * 0.5 - 0.12, 0.15)
	var half_w := maxf(depth * 0.5 - 0.1, 0.1)
	var spots := [["cup", ax * minf(half_l, 0.42) + az * minf(half_w, 0.18)], ["apple", -ax * minf(half_l, 0.42) + az * minf(half_w, 0.2)],
		["bun", -ax * minf(half_l, 0.3) - az * minf(half_w, 0.18)], ["pie", ax * minf(half_l, 0.28) - az * minf(half_w, 0.2)]]
	for sp in spots:
		var xf := Transform3D(b, top + (sp[1] as Vector3) + Vector3(0, 0.002, 0))
		var e := {"parent": h, "xf": xf, "kind": sp[0], "node": null}
		table_items.append(e)
		_food_spawn(e)


func _food_spawn(e: Dictionary) -> void:
	var n := Util.thing(String(e["kind"]))
	if n == null:
		return
	(e["parent"] as Node3D).add_child(n)
	n.transform = e["xf"]
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 26.0
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e["node"] = n


func food_refill(delta: float, nika: Vector3) -> void:
	## З'їдене з часом з'являється знову (коли Ніка далеко від тієї хати).
	_food_t += delta
	if _food_t < 5.0:
		return
	_food_t = 0.0
	for e in table_items:
		var n = e["node"]
		if n != null and is_instance_valid(n) and (n as Node3D).get_parent() == e["parent"]:
			e["t"] = 0.0
			continue
		e["t"] = float(e.get("t", 0.0)) + 5.0
		var hp: Vector3 = (e["parent"] as Node3D).global_position
		if float(e["t"]) > 180.0 and Vector2(hp.x - nika.x, hp.z - nika.z).length() > 25.0:
			e["t"] = 0.0
			_food_spawn(e)


# ------------------------------------------------------------------ мерехтіння підлоги
var _strip_cache := {}


func _strip_up_faces(mi: MeshInstance3D, y_max: float, from_surface: int, lower := 0.0) -> void:
	## Прибирає з сітки горизонтальні грані «обличчям угору» нижче y_max (у системі сітки),
	## у поверхнях, починаючи з from_surface. Вони лежали в одній площині з підлогою інтер'єру,
	## і телефон малював то одну, то другу — підлога мерехтіла смугами.
	## lower > 0 — не прибирати, а опустити ці грані на стільки метрів (темна основа під дошками).
	var src := mi.mesh
	if src == null:
		return
	var k := "%d_%.2f_%d_%.3f" % [src.get_rid().get_id(), y_max, from_surface, lower]
	if _strip_cache.has(k):
		mi.mesh = _strip_cache[k]
		return
	var out := ArrayMesh.new()
	var changed := false
	for s in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(s)
		if s >= from_surface and arr[Mesh.ARRAY_INDEX] != null and arr[Mesh.ARRAY_NORMAL] != null:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			var low := {}
			for i in range(0, idx.size() - 2, 3):
				var a := idx[i]
				var b := idx[i + 1]
				var c := idx[i + 2]
				if v[a].y < y_max and absf(v[a].y - v[b].y) < 0.003 and absf(v[a].y - v[c].y) < 0.003 \
						and (nr[a] + nr[b] + nr[c]).y > 2.85:
					changed = true
					if lower <= 0.0:
						continue
					low[a] = true
					low[b] = true
					low[c] = true
				keep.append(a)
				keep.append(b)
				keep.append(c)
			if keep.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = keep
			if not low.is_empty():
				var v2 := v.duplicate()
				for q in low:
					v2[q] = v2[q] - Vector3(0, lower, 0)
				arr[Mesh.ARRAY_VERTEX] = v2
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	var res: Mesh = out if changed else src
	_strip_cache[k] = res
	mi.mesh = res


# ------------------------------------------------------------------ церква: убранство, огорожа, дерева
const CHURCH_FLOOR := 0.58                         # висота підлоги церкви (у системі вузла «Церква»)
const CHURCH_YARD := Rect2(-13.5, -11.0, 27.0, 23.5)   # огорожа навколо церкви (x, z у системі церкви; двері — до +z)


func _church_extras(ch: Node3D, b: Dictionary) -> void:
	## Іконостас, ікони, престол, свічники й лави з Церква.blend (файл bz_church_in.glb),
	## огорожа як біля хат і дерева з грибного лісу довкола.
	if ResourceLoader.exists(DIR % "bz_church_in"):
		var inn: Node3D = load(DIR % "bz_church_in").instantiate()
		inn.name = "Убранство"
		ch.add_child(inn)
		inn.position = Vector3(0, CHURCH_FLOOR, 0)
		for n in inn.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var nm := String(mi.name)
			mi.visibility_range_end = 30.0
			mi.visibility_range_end_margin = 6.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if nm.begins_with("Лава"):
				_solid(mi, true)
				_furn(mi, "sit", b)                 # на лаві можна посидіти
			elif nm.begins_with("ЦІконостас") or nm.begins_with("ЦПрестол"):
				_solid(mi, true)
	_church_fence(ch)
	_church_trees(ch)


func _fence_mats() -> Dictionary:
	## Матеріали паркану біля хат (bz_fence.glb): стовп, брус, штахетина.
	var out := {}
	var fc: Node = root.get_node_or_null("bz_fence")
	if fc:
		for n in fc.find_children("*", "MeshInstance3D", true, false):
			var m := (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var mt := m.surface_get_material(s)
				if mt:
					out[String(mt.resource_name)] = mt
			break
	if not out.has("Паркан_Стовп"):
		out["Паркан_Стовп"] = Util.mat(Color(0.71, 0.43, 0.21), 0.9)
	if not out.has("Паркан_Брус"):
		out["Паркан_Брус"] = Util.mat(Color(0.86, 0.63, 0.37), 0.9)
	if not out.has("Паркан_Штахет"):
		out["Паркан_Штахет"] = Util.mat(Color(0.8, 0.52, 0.27), 0.9)
	if not out.has("Паркан_Штахет_темний"):
		out["Паркан_Штахет_темний"] = out["Паркан_Штахет"]
	return out


func _church_fence(ch: Node3D) -> void:
	## Штахетний паркан довкола церкви (такий самий, як біля хат) з хвірткою навпроти дверей.
	var mats := _fence_mats()
	var holder := Node3D.new()
	holder.name = "Огорожа"
	ch.add_child(holder)
	var r := CHURCH_YARD
	var gate_w := 1.2
	# сторони: [початок, кінець] у системі церкви; передня сторона — з проходом для хвіртки
	var sides := [
		[Vector3(r.position.x, 0, r.end.y), Vector3(-gate_w * 0.5, 0, r.end.y)],
		[Vector3(gate_w * 0.5, 0, r.end.y), Vector3(r.end.x, 0, r.end.y)],
		[Vector3(r.end.x, 0, r.end.y), Vector3(r.end.x, 0, r.position.y)],
		[Vector3(r.end.x, 0, r.position.y), Vector3(r.position.x, 0, r.position.y)],
		[Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y)],
	]
	var pickets: Array = []
	var posts: Array = []
	for sd in sides:
		var a: Vector3 = sd[0]
		var e: Vector3 = sd[1]
		var L := a.distance_to(e)
		var dir := (e - a) / L
		var yaw := atan2(dir.x, dir.z) + PI / 2.0       # уздовж сторони — вісь x коробки
		var mid := (a + e) * 0.5
		var bs := Basis(Vector3.UP, yaw)
		for h in [0.32, 1.02]:
			holder.add_child(Util.box(Vector3(L, 0.07, 0.05), mats["Паркан_Брус"], mid + Vector3(0, h, 0), Vector3(0, rad_to_deg(yaw), 0)))
		var np := maxi(1, int(ceil(L / 2.6)))
		for i in np + 1:
			posts.append(Transform3D(bs, a + dir * (L * float(i) / float(np)) + Vector3(0, 0.72, 0)))
		var nk := int(L / 0.16)
		for i in nk:
			var p := a + dir * (0.08 + float(i) * 0.16)
			pickets.append(Transform3D(bs, p + Vector3(0, 0.66, 0) + bs * Vector3(0, 0, 0.035)))
		# тверда стінка для Ніки, коня й велосипеда
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(L, 1.4, 0.16)
		cs.shape = bx
		walls.add_child(cs)
		cs.global_transform = ch.global_transform * Transform3D(bs, mid + Vector3(0, 0.7, 0))
	holder.add_child(_mm(BoxMesh.new(), Vector3(0.12, 1.44, 0.12), mats["Паркан_Стовп"], posts))
	holder.add_child(_mm(BoxMesh.new(), Vector3(0.085, 1.28, 0.022), mats["Паркан_Штахет"], pickets))
	for c in holder.get_children():
		(c as GeometryInstance3D).visibility_range_end = 90.0
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_church_gate(ch, Vector3(0, 0, r.end.y), gate_w)


func _mm(mesh: BoxMesh, size: Vector3, mat: Material, xf: Array) -> MultiMeshInstance3D:
	mesh.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


func _church_gate(ch: Node3D, at: Vector3, w: float) -> void:
	## Хвіртка — копія хвіртки з подвір'я хати; відчиняється, коли підходить Ніка.
	var src: MeshInstance3D = null
	var hs: Node = root.get_node_or_null("bz_houses")
	if hs:
		for n in hs.find_children("*Калітка", "MeshInstance3D", true, false):
			src = n
			break
	if src == null:
		return
	var g := MeshInstance3D.new()
	g.name = "Церква_Калітка"
	g.mesh = src.mesh
	for s in src.get_surface_override_material_count():
		g.set_surface_override_material(s, src.get_surface_override_material(s))
	ch.add_child(g)
	var ab := src.get_aabb()
	# довгий бік хвіртки — уздовж x системи церкви, завіса — на лівому краю проходу
	var bs := Basis() if ab.size.x >= ab.size.z else Basis(Vector3.UP, -PI / 2.0)
	var lb := AABB(bs * ab.position, Vector3.ZERO)
	for i in 8:
		lb = lb.expand(bs * ab.get_endpoint(i))
	g.transform = Transform3D(bs, Vector3(at.x - w * 0.5 - lb.position.x, 0, at.z - lb.get_center().z))
	g.visibility_range_end = 70.0
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_door(g, ch, true)


const CHURCH_TREES := [
	[-17.5, -14.0], [-9.0, -15.5], [0.5, -16.0], [9.5, -15.0], [18.0, -13.5],
	[-18.5, -4.0], [-18.0, 6.0], [18.5, -3.5], [17.5, 7.0],
	[-11.5, -8.5], [11.5, -8.5], [-11.0, 9.0], [11.0, 9.5],
]


func _church_trees(ch: Node3D) -> void:
	## Берізки й сосни з грибного лісу — довкола церкви й у кутках церковного двору.
	var kinds := ["birch_b_lo", "pine_lo", "birch_a_lo", "pine_lo"]
	var heights := {"birch_b_lo": [7.0, 9.5], "pine_lo": [8.0, 11.0], "birch_a_lo": [6.5, 8.5]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var holder := Node3D.new()
	holder.name = "Дерева"
	ch.add_child(holder)
	for t in CHURCH_TREES:
		var k: String = kinds[rng.randi() % kinds.size()]
		if not Models.exists(k):
			continue
		var hr: Array = heights[k]
		var tr := Models.spawn(holder, k, rng.randf_range(hr[0], hr[1]))
		if tr == null:
			continue
		tr.position = Vector3(float(t[0]), 0, float(t[1]))
		tr.rotation.y = rng.randf() * TAU
		for mi in tr.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = 170.0
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.3
		cy.height = 3.0
		cs.shape = cy
		walls.add_child(cs)
		cs.global_position = tr.global_position + Vector3(0, 1.5, 0)


# ------------------------------------------------------------------ сідло й вуздечка на продаж (біля ларька з інструментами)
const TACK_AT := Vector3(11.75, 0, 0.5)          # у системі базару: між ларьком інструментів і ларьком солодощів
var tack_holder: Node3D = null
var tack_goods: Array = []
var tack_sold := false


func _tack_stall() -> void:
	if not Models.exists("saddle"):
		return
	var h := Node3D.new()
	h.name = "TackStall"
	h.position = TACK_AT
	root.add_child(h)
	var wood := Util.mat(Color(0.45, 0.3, 0.18), 0.9)
	h.add_child(Util.mesh(PrismMesh.new(), wood, Vector3(0, 0.85, 0), Vector3(0, 90, 0), Vector3(0.5, 0.3, 0.7)))
	for sx in [-0.3, 0.3]:
		for sz in [-0.12, 0.12]:
			h.add_child(Util.box(Vector3(0.05, 0.72, 0.05), wood, Vector3(sx, 0.36, sz)))
	h.add_child(Util.box(Vector3(0.08, 2.1, 0.08), wood, Vector3(0, 1.05, 1.0)))
	var sd: Node3D = load(Models.DIR % "saddle").instantiate()
	h.add_child(sd)
	tack_goods.append(sd)
	if Models.exists("bridle"):
		var peg := Vector3(0, 1.95, 1.08)
		h.add_child(Util.box(Vector3(0.04, 0.04, 0.14), wood, peg))
		var br: Node3D = load(Models.DIR % "bridle").instantiate()
		br.basis = Basis(Vector3.UP, -PI / 2.0)
		br.position = peg - br.basis * Vector3(-1.3, 1.4, 0)
		h.add_child(br)
		tack_goods.append(br)
	var lb := Label3D.new()
	lb.text = "Сідло й вуздечка — 30 монет"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 40
	lb.outline_size = 8
	lb.pixel_size = 0.003
	lb.modulate = Color(1, 0.95, 0.75)
	lb.outline_modulate = Color(0.25, 0.12, 0.05)
	lb.position = Vector3(0, 1.4, 0.1)
	h.add_child(lb)
	tack_goods.append(lb)
	h.add_child(Util.pick_area("bz_tack", Vector3(0.9, 1.6, 1.3), Vector3(0, 0.8, 0.3)))
	tack_holder = h


func sell_tack() -> void:
	tack_sold = true
	for g in tack_goods:
		(g as Node3D).visible = false
