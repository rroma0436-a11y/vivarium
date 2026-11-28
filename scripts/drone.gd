extends Node3D
## Дрон-помічник: живе на фермі. Удень літає над усім світом і стежить, щоб не було пожеж —
## побачить вогонь, підлітає й гасить. Зранку годує курей, по обіді поливає город.
## Уночі сидить на зарядці за 2 м від комбайна.

signal done(what: String)

const HOME := Vector3(-135.2, 0, 40.0)        # комбайн на фермі
const PATROL_H := 16.0                         # висота облітання світу
const PATROL_R := 240.0                        # як далеко облітає
const PATROL_SPEED := 9.0
var center := HOME
var model: Node3D
var drops: CPUParticles3D
var grain_fx: CPUParticles3D
var spots := {}
var mode := "patrol"               # patrol, task, rest
var _t := 0.0
var _hover := 0.0
var _fed_day := -1
var _watered_day := -1
var bubble: Label3D
var _bubble_left := 0.0
var foam: CPUParticles3D
var fires: Array = []
var _next_fire := 40.0
var _wp := Vector3.ZERO
var charger: Node3D
var charger_pos := Vector3(-131.2, 0, 34.8)        # збоку від навісу (на північ), не перед комбайном
var _charger_mat: StandardMaterial3D


func setup(_at: Vector3, sp := {}) -> void:
	spots = sp
	position = HOME + Vector3(0, PATROL_H, 0)
	model = Models.spawn(self, "drone", 0.6)
	if model:
		model.position.y -= 0.3
		_split_props()
	add_child(Util.pick_area("drone", Vector3(0.8, 0.6, 0.8), Vector3.ZERO))
	drops = _particles(Color(0.55, 0.8, 1.0, 0.8), 0.015, 40)
	grain_fx = _particles(Color(0.95, 0.8, 0.3, 1.0), 0.02, 30)
	foam = _particles(Color(0.85, 0.95, 1.0, 0.85), 0.035, 140)
	foam.lifetime = 1.4
	foam.spread = 22.0
	bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 40)
	bubble.pixel_size = 0.0032
	bubble.position = Vector3(0, 0.6, 0)
	add_child(bubble)


# ------------------------------------------------------------------ пропелери крутяться
var _props: Array = []
var _spin := 0.0
const HUBS := [Vector2(0.687, 0.679), Vector2(-0.689, 0.678), Vector2(0.688, -0.679), Vector2(-0.686, -0.679)]


func _split_props() -> void:
	## Модель дрона — одна сітка. Вирізаємо з неї чотири пропелери (тонкий шар лопатей над моторами)
	## в окремі сітки, щоб крутити їх навколо осей моторів.
	var m: Node3D = model.get_meta("model") if model.has_meta("model") else null
	if m == null:
		return
	var mis := m.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return
	var mi := mis[0] as MeshInstance3D
	var src := mi.mesh as ArrayMesh
	if src == null or src.get_surface_count() != 1:
		return
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		return
	var T := Models._rel(mi, m)
	var keep := PackedInt32Array()
	var per := [[], [], [], []]
	for i in range(0, idx.size() - 2, 3):
		var a: Vector3 = T * verts[idx[i]]
		var b: Vector3 = T * verts[idx[i + 1]]
		var c: Vector3 = T * verts[idx[i + 2]]
		var which := -1
		if minf(a.y, minf(b.y, c.y)) > 0.12 and maxf(a.y, maxf(b.y, c.y)) < 0.26:
			var cen := (a + b + c) / 3.0
			for h in 4:
				if Vector2(cen.x - HUBS[h].x, cen.z - HUBS[h].y).length() < 0.45:
					which = h
					break
		if which < 0:
			keep.append(idx[i])
			keep.append(idx[i + 1])
			keep.append(idx[i + 2])
		else:
			(per[which] as Array).append_array([idx[i], idx[i + 1], idx[i + 2]])
	if keep.size() == idx.size():
		return
	var mat: Material = mi.get_active_material(0)
	arr[Mesh.ARRAY_INDEX] = keep
	var body := ArrayMesh.new()
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	body.surface_set_material(0, mat)
	mi.mesh = body
	for h in 4:
		if (per[h] as Array).is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array(per[h])
		var pm := ArrayMesh.new()
		pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		pm.surface_set_material(0, mat)
		var hub := Vector3(HUBS[h].x, 0.0, HUBS[h].y)
		var pivot := Node3D.new()
		pivot.position = hub
		m.add_child(pivot)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pm
		pmi.transform = Transform3D(T.basis, T.origin - hub)
		pivot.add_child(pmi)
		_props.append(pivot)


func _particles(col: Color, r: float, n: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = 0.9
	p.direction = Vector3(0, -1, 0)
	p.spread = 14.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -6, 0)
	p.emitting = false
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.5
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	p.mesh = sm
	p.position = Vector3(0, -0.35, 0)
	add_child(p)
	return p


func say(text: String, secs := 2.5) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_left = secs


func _process(delta: float) -> void:
	_t += delta
	rotation.z = sin(_t * 1.3) * 0.05 if mode != "rest" else 0.0
	_spin = lerpf(_spin, 0.0 if mode == "rest" else 28.0, 1.0 - exp(-delta * 1.5))
	for i in _props.size():
		(_props[i] as Node3D).rotation.y += _spin * delta * (1.0 if i == 0 or i == 3 else -1.0)
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			bubble.visible = false
	if charger == null and _t > 1.0:
		_make_charger()
	if _charger_mat:
		_charger_mat.emission_energy_multiplier = (1.6 + sin(_t * 3.0)) if mode == "rest" else 0.4
	_flicker_fires()
	if mode == "task":
		return
	if not Game.is_night():
		_next_fire -= delta
		if _next_fire <= 0.0:
			_next_fire = randf_range(45.0, 100.0)
			_spawn_fire()
	if not fires.is_empty() and mode != "rest":
		put_out(_nearest_fire())
		return
	# розпорядок: зранку годує курей, по обіді поливає город
	var h := Game.hour()
	var day := int(Game.state["day"])
	if not Game.is_night():
		if h >= 7.2 and h < 11.0 and _fed_day != day:
			_fed_day = day
			feed_hens()
			return
		if h >= 13.0 and h < 17.0 and _watered_day != day and float(Game.state["field"]["water"]) < 60.0:
			_watered_day = day
			water_field()
			return
	if Game.is_night():
		if mode != "rest":
			_land()
		return
	if mode == "rest":
		_take_off()
		return
	mode = "patrol"
	if _hover > 0.0:
		_hover -= delta
		drops.emitting = true
	else:
		drops.emitting = false
		# облітає світ від точки до точки
		if _wp == Vector3.ZERO or position.distance_to(_wp) < 3.0:
			_wp = _rand_point(0.0, PATROL_R) + Vector3(0, PATROL_H, 0)
		var to := _wp - position
		position += to.normalized() * minf(PATROL_SPEED * delta, to.length())
		if Vector2(to.x, to.z).length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 2.0))


func poke() -> void:
	if mode == "task":
		say("Біп! Я працюю!")
		return
	_hover = 3.0


func busy() -> bool:
	return mode == "task"


func fly_to(p: Vector3, speed := 3.0) -> void:
	## Летить до точки (await fly_to(...)).
	while position.distance_to(p) > 0.05:
		var d := get_process_delta_time()
		var to := p - position
		var sp := speed if to.length() < 12.0 else maxf(speed, 22.0)   # далеко — летить швидко
		var step := minf(sp * d, to.length())
		position += to.normalized() * step
		var flat := Vector2(to.x, to.z)
		if flat.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-d * 4.0))
		await get_tree().process_frame


func feed_hens() -> void:
	## Летить до курника, сипле зерно — кури збігаються клювати.
	if mode == "task":
		return
	mode = "task"
	say("Біп! Несу зерно!")
	var g: Vector3 = spots.get("grain", Vector3(5.0, 0, -0.6))
	await fly_to(g + Vector3(0, 2.0, 0))
	grain_fx.emitting = true
	_play("pop")
	await get_tree().create_timer(2.5).timeout
	Game.state["hens_fed"] = 100.0
	for b in get_parent().get_children():
		if "rooster" in b:
			b.go_eat(g, "grain")
	await get_tree().create_timer(1.5).timeout
	grain_fx.emitting = false
	Game.emit_event("hens_fed")
	done.emit("feed")
	await fly_to(position + Vector3(0, 4.0, 0), 2.0)
	_wp = Vector3.ZERO
	mode = "patrol"


func water_field() -> void:
	## Летить за тин і поливає грядки з соняшниками — ряд за рядом.
	if mode == "task":
		return
	mode = "task"
	say("Біп! Лечу поливати город!")
	var f: Rect2 = spots.get("field", Rect2(11.1, -9.5, 6.8, 10.0))
	var y := 2.6
	await fly_to(Vector3(f.position.x + 0.4, y, f.end.y - 0.5), 3.5)
	drops.emitting = true
	_play("sparkle")
	var rows := 6
	for r in rows:
		var x := f.position.x + 0.4 + r * 1.2
		var z0 := f.end.y - 0.5 if r % 2 == 0 else f.position.y + 0.5
		var z1 := f.position.y + 0.5 if r % 2 == 0 else f.end.y - 0.5
		await fly_to(Vector3(x, y, z0), 3.0)
		await fly_to(Vector3(x, y, z1), 2.4)
		var w: Dictionary = Game.state["field"]
		w["water"] = minf(100.0, float(w["water"]) + 100.0 / rows)
	drops.emitting = false
	Game.state["field"]["water"] = 100.0
	say("Город полито!")
	Game.emit_event("field_watered")
	done.emit("water")
	await fly_to(position + Vector3(0, 4.0, 0), 2.0)
	_wp = Vector3.ZERO
	mode = "patrol"


func _play(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -8.0)


func _land() -> void:
	## Увечері летить на зарядку біля комбайна й сідає.
	mode = "task"
	drops.emitting = false
	grain_fx.emitting = false
	foam.emitting = false
	if charger == null:
		_make_charger()
	say("Біп… лечу на зарядку.", 2.0)
	await fly_to(Vector3(charger_pos.x, maxf(position.y, 6.0), charger_pos.z), 3.0)
	await fly_to(charger_pos + Vector3(0, 0.44, 0), 0.8)
	rotation.y = 0.0
	mode = "rest"
	say("Заряджаюсь…", 2.0)


func _take_off() -> void:
	mode = "task"
	await fly_to(charger_pos + Vector3(0, 3.0, 0), 1.0)
	say("Доброго ранку! Лечу стежити, щоб не було пожеж!", 3.0)
	await fly_to(Vector3(position.x, PATROL_H, position.z), 3.0)
	_wp = Vector3.ZERO
	mode = "patrol"


# ------------------------------------------------------------------ зарядка біля комбайна
func _make_charger() -> void:
	## Зарядна станція — за навісом з північного боку, біля задньої частини комбайна (не перед ним: там він виїжджає).
	var main = get_node_or_null("/root/Main")
	var c: Node3D = main.combine if main and "combine" in main and main.combine else null
	var par := get_parent() as Node3D
	if c and par:
		var inv := par.global_transform.affine_inverse()
		var box := AABB()
		var first := true
		for n in c.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var bb: AABB = (inv * mi.global_transform) * mi.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		if not first:
			charger_pos = Vector3(box.end.x - 1.2, 0.0, box.position.z - 3.0)
	charger = Node3D.new()
	charger.name = "DroneCharger"
	charger.position = charger_pos
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.27, 0.3)
	metal.metallic = 0.6
	metal.roughness = 0.4
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.6
	cm.height = 0.1
	cm.material = metal
	base.mesh = cm
	base.position.y = 0.05
	charger.add_child(base)
	_charger_mat = StandardMaterial3D.new()
	_charger_mat.albedo_color = Color(0.2, 0.9, 0.4)
	_charger_mat.emission_enabled = true
	_charger_mat.emission = Color(0.2, 1.0, 0.45)
	_charger_mat.emission_energy_multiplier = 0.4
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.44
	tm.material = _charger_mat
	ring.mesh = tm
	ring.position.y = 0.11
	charger.add_child(ring)
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.7, 0.12)
	bm.material = metal
	post.mesh = bm
	post.position = Vector3(-0.72, 0.35, 0)
	charger.add_child(post)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.08
	lm.height = 0.16
	lm.material = _charger_mat
	lamp.mesh = lm
	lamp.position = Vector3(-0.72, 0.76, 0)
	charger.add_child(lamp)
	if par:
		par.add_child(charger)


# ------------------------------------------------------------------ пожежі
func _rand_point(rmin: float, rmax: float) -> Vector3:
	## Випадкова точка у світі (не у воді).
	var p := Vector3.ZERO
	for i in 30:
		var a := randf() * TAU
		var r := sqrt(randf_range(rmin * rmin / (rmax * rmax), 1.0)) * rmax
		p = Vector3(cos(a) * r, 0.0, sin(a) * r)
		if absf(p.z - 102.0) < 9.0:
			continue                                   # річка
		if absf(p.x + 70.0) < 23.0 and absf(p.z - 31.0) < 16.0:
			continue                                   # ставок
		return p
	return p


func _spawn_fire() -> void:
	var par := get_parent() as Node3D
	if par == null:
		return
	var p := _rand_point(25.0, PATROL_R)
	var node := Node3D.new()
	node.name = "Fire"
	node.position = p
	var flames := CPUParticles3D.new()
	flames.amount = 70
	flames.lifetime = 0.9
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.9
	flames.direction = Vector3.UP
	flames.spread = 18.0
	flames.initial_velocity_min = 1.2
	flames.initial_velocity_max = 2.4
	flames.gravity = Vector3(0, 1.5, 0)
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.4, 1.0))
	g.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
	g.add_point(0.45, Color(1.0, 0.45, 0.05, 0.9))
	flames.color_ramp = g
	flames.mesh = _quad(0.55, true)
	flames.position.y = 0.3
	node.add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 30
	smoke.lifetime = 3.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.8
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 2.5
	smoke.gravity = Vector3(0.3, 0.6, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var gs := Gradient.new()
	gs.set_color(0, Color(0.3, 0.3, 0.3, 0.55))
	gs.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	smoke.color_ramp = gs
	smoke.mesh = _quad(1.2, false)
	smoke.position.y = 1.2
	node.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.0
	light.omni_range = 10.0
	light.position.y = 1.2
	node.add_child(light)
	par.add_child(node)
	fires.append({"node": node, "pos": p, "flames": flames, "smoke": smoke, "light": light, "power": 1.0})


func _quad(size: float, glow: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	return q


func _flicker_fires() -> void:
	for fr in fires:
		var l: OmniLight3D = fr["light"]
		if is_instance_valid(l):
			l.light_energy = float(fr["power"]) * randf_range(2.2, 3.6)


func _nearest_fire() -> Dictionary:
	var best: Dictionary = fires[0]
	for fr in fires:
		if position.distance_to(fr["pos"]) < position.distance_to(best["pos"]):
			best = fr
	return best


func _toast(text: String) -> void:
	var m = get_node_or_null("/root/Main")
	if m and "hud" in m and m.hud:
		m.hud.toast(text, 3.0)


func put_out(fr: Dictionary) -> void:
	## Підлітає до пожежі й гасить її водою.
	mode = "task"
	drops.emitting = false
	say("Біп! Бачу пожежу!", 3.0)
	_toast("Дрон помітив пожежу й летить гасити!")
	var p: Vector3 = fr["pos"]
	await fly_to(Vector3(p.x, maxf(position.y, PATROL_H), p.z), 24.0)
	await fly_to(p + Vector3(0, 4.5, 0), 6.0)
	var node: Node3D = fr["node"]
	if is_instance_valid(node):
		foam.emitting = true
		_play("sparkle")
		say("Шшш! Гашу вогонь!", 3.0)
		var k := 0.0
		while k < 5.0:
			var d := get_process_delta_time()
			k += d
			fr["power"] = clampf(1.0 - k / 5.0, 0.0, 1.0)
			node.scale = Vector3.ONE * (0.15 + 0.85 * float(fr["power"]))
			rotation.y += d * 0.6
			await get_tree().process_frame
		foam.emitting = false
		(fr["flames"] as CPUParticles3D).emitting = false
		(fr["light"] as OmniLight3D).visible = false
		(fr["smoke"] as CPUParticles3D).emitting = false
		get_tree().create_timer(4.0).timeout.connect(node.queue_free)
		say("Пожежу загашено! Біп!", 3.0)
		_toast("Дрон загасив пожежу")
	fires.erase(fr)
	await fly_to(Vector3(position.x, PATROL_H, position.z), 4.0)
	_wp = Vector3.ZERO
	mode = "patrol"
