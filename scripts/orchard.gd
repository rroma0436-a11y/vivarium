extends Node3D
## Садок біля хати — увесь із коду: яблуні, груші, вишні й сливи з пухкими кронами, що гойдаються
## на вітрі; плоди ростуть, наливаються кольором, стиглі падають у траву. Тин, хвіртка, вулики й лавка.
## Плоди — по одному MultiMesh на вид (кілька викликів малювання на весь сад).

const AREA := Rect2(4.0, 8.0, 14.5, 12.5)          # x, z
const KINDS := {
	"apple": {"name": "Яблуня", "fruit": "яблука", "green": Color(0.55, 0.75, 0.25), "ripe": Color(0.86, 0.16, 0.12), "r": 0.15, "shape": Vector3(1.0, 0.92, 1.0), "n": 16},
	"pear": {"name": "Груша", "fruit": "груші", "green": Color(0.5, 0.7, 0.25), "ripe": Color(0.93, 0.8, 0.25), "r": 0.14, "shape": Vector3(0.9, 1.3, 0.9), "n": 12},
	"cherry": {"name": "Вишня", "fruit": "вишні", "green": Color(0.6, 0.72, 0.3), "ripe": Color(0.62, 0.03, 0.08), "r": 0.075, "shape": Vector3(1.0, 1.0, 1.0), "n": 34},
	"plum": {"name": "Слива", "fruit": "сливи", "green": Color(0.55, 0.7, 0.3), "ripe": Color(0.35, 0.18, 0.5), "r": 0.11, "shape": Vector3(0.9, 1.15, 0.9), "n": 18},
}
const LAYOUT := [
	["apple", Vector3(5.8, 0, 10.2)], ["pear", Vector3(9.6, 0, 9.8)], ["apple", Vector3(13.4, 0, 10.3)], ["cherry", Vector3(16.9, 0, 9.9)],
	["plum", Vector3(6.1, 0, 14.2)], ["apple", Vector3(10.0, 0, 14.0)], ["cherry", Vector3(13.8, 0, 14.4)], ["apple", Vector3(17.0, 0, 14.0)],
	["cherry", Vector3(5.7, 0, 18.3)], ["apple", Vector3(9.4, 0, 18.2)], ["pear", Vector3(13.1, 0, 18.5)], ["plum", Vector3(16.8, 0, 18.1)],
]

var trees: Array = []          # {kind, pos, crown_c, crown_r, fruits:[{p, r, state, fall_y, mm_i}]}
var _mm := {}                  # kind → MultiMesh
var _crown_mat: ShaderMaterial
var _t := 0.0
var _last_day := -1
var _last_hour := -1.0


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_crown_mat = _make_crown_mat()
	var bark := Util.mat(Color(0.42, 0.29, 0.2), 0.95)
	var crown_st := SurfaceTool.new()
	crown_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_st := SurfaceTool.new()
	trunk_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 14
	ball.rings = 8
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	for L in LAYOUT:
		var kind: String = L[0]
		var base: Vector3 = L[1] + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var small := kind == "cherry" or kind == "plum"
		var h := rng.randf_range(1.25, 1.5) * (0.9 if small else 1.0)
		var tr := rng.randf_range(0.13, 0.17)
		# стовбур, трохи нахилений
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var tb := Basis.from_euler(Vector3(lean.z, 0, -lean.x)).scaled(Vector3(tr, h, tr))
		trunk_st.append_from(cyl, 0, Transform3D(tb, base + Vector3(0, h * 0.5, 0)))
		var top := base + Basis.from_euler(Vector3(lean.z, 0, -lean.x)) * Vector3(0, h, 0)
		# гілки — у крону
		for k in 3:
			var a := k * TAU / 3.0 + rng.randf() * 0.8
			var d := Vector3(cos(a), 0.9, sin(a)).normalized()
			var bl := rng.randf_range(0.7, 1.0)
			var bb := Basis(Vector3.UP.cross(d).normalized(), Vector3.UP.angle_to(d)).scaled(Vector3(tr * 0.5, bl, tr * 0.5))
			trunk_st.append_from(cyl, 0, Transform3D(bb, top + d * bl * 0.45 - Vector3(0, 0.15, 0)))
		# крона — кілька пухких куль, щільно злитих
		var cr := rng.randf_range(1.15, 1.4) * (0.85 if small else 1.0)
		var cc := top + Vector3(0, cr * 0.75, 0)
		var blobs := [[Vector3.ZERO, 1.0]]
		for k in 5:
			var a := k * TAU / 5.0 + rng.randf() * 0.5
			blobs.append([Vector3(cos(a) * cr * 0.55, rng.randf_range(-0.25, 0.2) * cr, sin(a) * cr * 0.55), rng.randf_range(0.6, 0.75)])
		blobs.append([Vector3(rng.randf_range(-0.2, 0.2), cr * 0.55, rng.randf_range(-0.2, 0.2)), 0.62])
		for bl2 in blobs:
			var r: float = cr * float(bl2[1])
			crown_st.append_from(ball, 0, Transform3D(Basis().scaled(Vector3(r, r * 0.88, r)), cc + bl2[0]))
		var t := {"kind": kind, "pos": base, "crown_c": cc, "crown_r": cr, "fruits": [], "blobs": blobs}
		trees.append(t)
		# торкнутися дерева
		var pa := Util.pick_area("orchard_tree", Vector3(cr * 2.0, h + cr * 2.0, cr * 2.0), base + Vector3(0, (h + cr * 2.0) * 0.5, 0))
		pa.set_meta("tree", trees.size() - 1)
		add_child(pa)
		Obstacles.add_outer(base.x, base.z, 0.4, 2.0)
	var crown_mesh := crown_st.commit()
	var cmi := MeshInstance3D.new()
	cmi.mesh = crown_mesh
	cmi.material_override = _crown_mat
	add_child(cmi)
	var trunk_mesh := trunk_st.commit()
	var tmi := MeshInstance3D.new()
	tmi.mesh = trunk_mesh
	tmi.material_override = bark
	add_child(tmi)
	_make_fruits(rng)
	_make_fence()
	_make_extras(rng)
	_make_leaves()
	Obstacles.finish()


func _make_crown_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 c_top : source_color = vec3(0.5, 0.76, 0.3);
uniform vec3 c_bot : source_color = vec3(0.15, 0.36, 0.13);
varying vec3 wp;
varying float up;
float h21(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn(vec3 p) { vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h21(i), h21(i + vec3(1,0,0)), f.x), mix(h21(i + vec3(0,1,0)), h21(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h21(i + vec3(0,0,1)), h21(i + vec3(1,0,1)), f.x), mix(h21(i + vec3(0,1,1)), h21(i + vec3(1,1,1)), f.x), f.y), f.z); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.4 + wp.x * 0.6 + wp.z * 0.4) * 0.05 + sin(TIME * 3.1 + wp.y * 2.0) * 0.015;
	VERTEX.x += sway * max(wp.y - 1.0, 0.0) * 0.5;
	VERTEX.z += sway * 0.6 * max(wp.y - 1.0, 0.0) * 0.5;
	up = NORMAL.y * 0.5 + 0.5;
}
void fragment() {
	float n = vn(wp * 3.2) * 0.6 + vn(wp * 9.0) * 0.4;
	vec3 c = mix(c_bot, c_top, smoothstep(0.1, 0.95, up * 0.8 + n * 0.35));
	c *= 0.82 + 0.3 * smoothstep(0.35, 0.75, n);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _make_fruits(rng: RandomNumberGenerator) -> void:
	for kind in KINDS:
		var info: Dictionary = KINDS[kind]
		var count := 0
		for t in trees:
			if t["kind"] == kind:
				count += int(info["n"])
		if count == 0:
			continue
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.45
		sm.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = sm
		mm.instance_count = count
		_mm[kind] = mm
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		var idx := 0
		for t in trees:
			if t["kind"] != kind:
				continue
			for k in int(info["n"]):
				var a := rng.randf() * TAU
				var y := rng.randf_range(-0.55, 0.45)
				var d := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
				var p: Vector3 = t["crown_c"] + d * _surface(t, d) * rng.randf_range(0.97, 1.01)
				t["fruits"].append({"p": p, "r": rng.randf_range(0.2, 1.0), "state": "grow", "y": p.y, "v": 0.0, "i": idx, "rot": rng.randf() * TAU})
				idx += 1
		_refresh(kind)


func _surface(t: Dictionary, d: Vector3) -> float:
	## Відстань від центру крони до її поверхні в напрямку d (крона — кілька куль).
	var best := 0.3
	var cr: float = t["crown_r"]
	for b in t["blobs"]:
		var c: Vector3 = b[0]
		var r: float = cr * float(b[1])
		var sc := Vector3(1.0, 0.88, 1.0)
		# сплюснута куля: переходимо в простір, де вона кругла
		var o := -c / sc
		var dd := (d / sc)
		var a := dd.dot(dd)
		var bq := 2.0 * o.dot(dd)
		var cq := o.dot(o) - r * r
		var disc := bq * bq - 4.0 * a * cq
		if disc < 0.0:
			continue
		var tt := (-bq + sqrt(disc)) / (2.0 * a)
		best = maxf(best, tt)
	return best


func _refresh(kind: String) -> void:
	var info: Dictionary = KINDS[kind]
	var mm: MultiMesh = _mm[kind]
	for t in trees:
		if t["kind"] != kind:
			continue
		for f in t["fruits"]:
			var i: int = f["i"]
			if f["state"] == "gone":
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -50, 0)))
				continue
			var r: float = clampf(f["r"], 0.0, 1.0)
			var sz := float(info["r"]) * (0.45 + 0.55 * r)
			var b := Basis(Vector3.UP, float(f["rot"])).scaled(info["shape"] * sz)
			var pos: Vector3 = f["p"]
			if f["state"] != "grow":
				pos.y = float(f["y"])
			mm.set_instance_transform(i, Transform3D(b, pos))
			var c: Color = (info["green"] as Color).lerp(info["ripe"], smoothstep(0.45, 1.0, r))
			if f["state"] == "ground" and float(f["r"]) > 1.6:
				c = c.darkened(0.35)
			mm.set_instance_color(i, c)


func _process(delta: float) -> void:
	_t += delta
	var h := Game.hour()
	var d := int(Game.state.get("day", 1))
	if d != _last_day:
		# новий день: опалі й зірвані плоди — знову зелені зав'язі
		if _last_day != -1:
			for t in trees:
				for f in t["fruits"]:
					if f["state"] != "grow":
						f["state"] = "grow"
						f["r"] = randf_range(0.15, 0.5)
			for k in _mm:
				_refresh(k)
		_last_day = d
	var falling := false
	for t in trees:
		for f in t["fruits"]:
			if f["state"] == "fall":
				falling = true
				f["v"] = float(f["v"]) + 9.8 * delta
				f["y"] = float(f["y"]) - float(f["v"]) * delta
				if float(f["y"]) <= float(KINDS[t["kind"]]["r"]) * 0.8:
					f["y"] = float(KINDS[t["kind"]]["r"]) * 0.8
					f["state"] = "ground"
					f["p"] = Vector3(f["p"].x + randf_range(-0.3, 0.3), 0, f["p"].z + randf_range(-0.3, 0.3))
	if falling:
		for k in _mm:
			_refresh(k)
	# раз на ігрову «чверть години» — ростуть
	if absf(h - _last_hour) < 0.25:
		return
	var dh := h - _last_hour if _last_hour >= 0.0 and h > _last_hour else 0.25
	_last_hour = h
	if h < 6.0 or h > 21.0:
		return
	for t in trees:
		for f in t["fruits"]:
			if f["state"] == "grow":
				f["r"] = float(f["r"]) + dh * 0.07
				if float(f["r"]) > 1.35 and randf() < 0.25:
					f["state"] = "fall"
					f["v"] = 0.0
					f["y"] = f["p"].y
			elif f["state"] == "ground":
				f["r"] = float(f["r"]) + dh * 0.05
	for k in _mm:
		_refresh(k)


# ------------------------------------------------------------------ для дідуся й Beep
func ripe_count(i: int) -> int:
	var n := 0
	for f in trees[i]["fruits"]:
		if f["state"] == "ground" or f["state"] == "grow" and float(f["r"]) >= 0.95:
			n += 1
	return n


func ripe_trees(n: int) -> Array:
	var list: Array = []
	for i in trees.size():
		var c := ripe_count(i)
		if c > 0:
			list.append([c, i])
	list.sort_custom(func(a, b): return a[0] > b[0])
	return list.slice(0, n).map(func(x): return x[1])


func tree_pos(i: int) -> Vector3:
	return trees[i]["pos"]


func pick_spot(i: int, from: Vector3) -> Vector3:
	var p: Vector3 = trees[i]["pos"]
	var d := from - p
	d.y = 0.0
	if d.length() < 0.1:
		d = Vector3(1, 0, 0)
	return p + d.normalized() * 1.1


func pick(i: int, n: int) -> int:
	## Зірвати до n стиглих (спершу підняти опалі). Повертає скільки зірвали.
	var got := 0
	for f in trees[i]["fruits"]:
		if got >= n:
			break
		if f["state"] == "ground" or f["state"] == "grow" and float(f["r"]) >= 0.95:
			f["state"] = "gone"
			got += 1
	if got > 0:
		_refresh(trees[i]["kind"])
	return got


func describe(i: int) -> String:
	var info: Dictionary = KINDS[trees[i]["kind"]]
	var c := ripe_count(i)
	if c == 0:
		return "%s: %s ще зелені — зачекаймо." % [info["name"], info["fruit"]]
	return "%s: стиглих — %d. Зірвемо!" % [info["name"], c]


func fruit_name(i: int) -> String:
	return KINDS[trees[i]["kind"]]["fruit"]


# ------------------------------------------------------------------ тин, вулики, лавка, квіти, листя
func _make_fence() -> void:
	var post := Util.mat(Color(0.42, 0.3, 0.2), 0.9)
	var weave := Util.mat(Color(0.62, 0.47, 0.3), 0.95)
	var r := AREA
	var sides := [[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)],
		[Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)],
		[Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)],
		[Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y)]]
	for si in sides.size():
		var a: Vector2 = sides[si][0]
		var b: Vector2 = sides[si][1]
		var len := a.distance_to(b)
		var n := int(len / 1.2)
		for k in n + 1:
			var q := a.lerp(b, float(k) / n)
			# хвіртка на західному боці (до дороги)
			if si == 3 and absf(q.y - 11.5) < 0.9:
				continue
			add_child(Util.cyl(0.04, 0.05, 0.85, post, Vector3(q.x, 0.42, q.y)))
		var seg_parts := [[0.0, 1.0]]
		if si == 3:
			var g0 := (r.end.y - 12.4) / len
			var g1 := (r.end.y - 10.6) / len
			seg_parts = [[0.0, g0], [g1, 1.0]]
		for sp in seg_parts:
			var p0 := a.lerp(b, sp[0])
			var p1 := a.lerp(b, sp[1])
			var c := (p0 + p1) / 2.0
			var l := p0.distance_to(p1)
			for hh in [0.3, 0.55]:
				var w := Util.box(Vector3(l, 0.12, 0.05), weave, Vector3(c.x, hh, c.y))
				w.rotation.y = -atan2(p1.y - p0.y, p1.x - p0.x)
				add_child(w)
		for k in n:
			var q0 := a.lerp(b, float(k) / n)
			var q1 := a.lerp(b, float(k + 1) / n)
			if si == 3 and absf((q0.y + q1.y) * 0.5 - 11.5) < 1.0:
				continue
			Obstacles.add_outer((q0.x + q1.x) * 0.5, (q0.y + q1.y) * 0.5, 0.55, 0.8)
	# дерев'яна хвіртка (відчинена)
	var gate := Util.box(Vector3(0.05, 0.75, 1.6), Util.mat(Color(0.55, 0.38, 0.22), 0.9), Vector3(r.position.x - 0.7, 0.42, 10.9))
	gate.rotation.y = 1.1
	add_child(gate)


func _make_extras(rng: RandomNumberGenerator) -> void:
	# вулики
	var hive := Util.mat(Color(0.93, 0.85, 0.55), 0.8)
	var roof := Util.mat(Color(0.55, 0.32, 0.2), 0.8)
	for i in 3:
		var p := Vector3(AREA.end.x - 0.9, 0, AREA.position.y + 2.2 + i * 1.3)
		add_child(Util.box(Vector3(0.6, 0.5, 0.55), hive, p + Vector3(0, 0.45, 0)))
		add_child(Util.box(Vector3(0.66, 0.06, 0.6), hive.duplicate(), p + Vector3(0, 0.64, 0)))
		var rf := Util.mesh(PrismMesh.new(), roof, p + Vector3(0, 0.8, 0), Vector3(0, 90, 0), Vector3(0.7, 0.25, 0.68))
		add_child(rf)
		add_child(Util.box(Vector3(0.6, 0.2, 0.5), Util.mat(Color(0.45, 0.33, 0.22), 0.9), p + Vector3(0, 0.1, 0)))
		add_child(Util.box(Vector3(0.02, 0.04, 0.18), Util.mat(Color(0.15, 0.1, 0.05), 1.0), p + Vector3(-0.31, 0.3, 0)))
		Obstacles.add_outer(p.x, p.z, 0.45, 1.0)
	# лавка під деревом
	var wood := Util.mat(Color(0.6, 0.42, 0.25), 0.85)
	var bp := Vector3(8.0, 0, 16.2)
	add_child(Util.box(Vector3(1.6, 0.06, 0.4), wood, bp + Vector3(0, 0.45, 0)))
	add_child(Util.box(Vector3(1.6, 0.35, 0.05), wood, bp + Vector3(0, 0.68, -0.2)))
	for sx in [-0.7, 0.7]:
		add_child(Util.box(Vector3(0.07, 0.45, 0.35), wood, bp + Vector3(sx, 0.22, 0)))
	# квіточки в траві
	var cols := [Color(1, 1, 1), Color(1.0, 0.85, 0.2), Color(0.75, 0.5, 0.95), Color(1.0, 0.5, 0.6)]
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_colors = true
	var fs := SphereMesh.new()
	fs.radius = 0.05
	fs.height = 0.06
	fs.radial_segments = 6
	fs.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fs.material = fmat
	fm.mesh = fs
	fm.instance_count = 140
	for i in 140:
		var p := Vector3(rng.randf_range(AREA.position.x + 0.4, AREA.end.x - 0.4), 0.08, rng.randf_range(AREA.position.y + 0.4, AREA.end.y - 0.4))
		fm.set_instance_transform(i, Transform3D(Basis(), p))
		fm.set_instance_color(i, cols[i % cols.size()])
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fm
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)


func _make_leaves() -> void:
	## Зрідка злітають листочки з крон.
	var p := CPUParticles3D.new()
	p.position = Vector3(AREA.get_center().x, 2.6, AREA.get_center().y)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(AREA.size.x * 0.45, 0.6, AREA.size.y * 0.45)
	p.amount = 10
	p.lifetime = 5.0
	p.gravity = Vector3(0.25, -0.45, 0.1)
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.2
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.1
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.65, 0.25)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	p.particle_flag_align_y = false
	add_child(p)
