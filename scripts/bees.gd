extends Node3D
## Бджоли: 20 бджілок по черзі вилітають з вуликів, летять на соняшники (на подвір'ї й на городі),
## збирають нектар, повертаються у вулик, трохи відпочивають — і знову. Увечері всі летять додому.
## Усі бджоли малюються через MultiMesh (5 викликів на всіх) — легко для телефона.

const COUNT := 20
const SPEED := 1.6

var hives: Array = []              # точки льотків вуликів
var flowers: Callable              # повертає масив точок (голівки соняшників)
var _bees: Array = []
var _mm: Array = []                # [MultiMesh, локальна трансформація]
var _t := 0.0


func setup(hive_points: Array, flower_fn: Callable) -> void:
	hives = hive_points
	flowers = flower_fn
	_build_meshes()
	for i in COUNT:
		var b := {
			"hive": hives[i % hives.size()],
			"state": "inside",
			"wait": 1.5 + i * 2.2,          # вилітають по черзі
			"pos": hives[i % hives.size()],
			"from": Vector3.ZERO, "to": Vector3.ZERO, "u": 0.0, "dur": 1.0,
			"phase": randf() * TAU,
			"yaw": 0.0,
		}
		_bees.append(b)


func _build_meshes() -> void:
	var body := SphereMesh.new()
	body.radius = 0.022
	body.height = 0.07
	body.radial_segments = 8
	body.rings = 4
	var band := CylinderMesh.new()
	band.top_radius = 0.0225
	band.bottom_radius = 0.0225
	band.height = 0.012
	band.radial_segments = 8
	band.rings = 1
	var head := SphereMesh.new()
	head.radius = 0.014
	head.height = 0.028
	head.radial_segments = 6
	head.rings = 3
	var wing := QuadMesh.new()
	wing.size = Vector2(0.03, 0.045)
	var yellow := Util.mat(Color(1.0, 0.78, 0.15), 0.6)
	var black := Util.mat(Color(0.12, 0.09, 0.06), 0.7)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.9, 0.97, 1.0, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# тільце лежить уздовж осі Z (вперед)
	var along := Basis.from_euler(Vector3(PI / 2, 0, 0))
	var parts := [
		[body, yellow, Transform3D(along, Vector3.ZERO)],
		[band, black, Transform3D(along, Vector3(0, 0, -0.008))],
		[band, black, Transform3D(along.scaled(Vector3(0.85, 1, 0.85)), Vector3(0, 0, -0.024))],
		[head, black, Transform3D(Basis(), Vector3(0, 0.004, 0.036))],
		[wing, wm, Transform3D()],     # ліве крильце (трансформація — щокадру)
		[wing, wm, Transform3D()],     # праве
	]
	for p in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = p[0]
		mm.instance_count = COUNT
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = p[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# межі, щоб бджоли не зникали з кадру (MultiMesh сам їх не рахує)
		mi.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 10, 60))
		add_child(mi)
		_mm.append([mm, p[2]])


func _process(delta: float) -> void:
	_t += delta
	var day := not Game.is_night() and Game.hour() >= 6.8 and Game.hour() < 19.5
	for i in COUNT:
		var b: Dictionary = _bees[i]
		match b["state"]:
			"inside":
				b["wait"] = float(b["wait"]) - delta
				if day and float(b["wait"]) <= 0.0:
					_fly(b, _pick_flower(), "out")
			"out", "back":
				b["u"] = float(b["u"]) + delta / float(b["dur"])
				var u := minf(float(b["u"]), 1.0)
				var a: Vector3 = b["from"]
				var c: Vector3 = b["to"]
				var mid := (a + c) * 0.5 + Vector3(0, 0.9 + a.distance_to(c) * 0.08, 0)
				var p := a.lerp(mid, u).lerp(mid.lerp(c, u), u)       # дуга
				# бджолине «петляння»
				var ph: float = b["phase"]
				p += Vector3(sin(_t * 5.0 + ph), sin(_t * 7.0 + ph * 2.0) * 0.5, cos(_t * 4.3 + ph)) * 0.06 * sin(u * PI)
				_move(b, p, delta)
				if u >= 1.0:
					if b["state"] == "out":
						b["state"] = "collect"
						b["wait"] = randf_range(4.0, 8.0)
						b["flower"] = c
					else:
						b["state"] = "inside"
						b["wait"] = randf_range(6.0, 14.0)
				elif b["state"] == "out" and not day:
					_fly(b, b["hive"], "back")
			"collect":
				# кружляє над голівкою соняшника, часом присідає
				var f: Vector3 = b["flower"]
				var ph2: float = b["phase"]
				var r := 0.12 + 0.05 * sin(_t * 1.3 + ph2)
				var p2 := f + Vector3(cos(_t * 1.7 + ph2) * r, 0.06 + absf(sin(_t * 0.9 + ph2)) * 0.08, sin(_t * 1.7 + ph2) * r)
				_move(b, p2, delta)
				b["wait"] = float(b["wait"]) - delta
				if float(b["wait"]) <= 0.0 or not day:
					# інколи летить ще на одну квітку, а потім — додому
					if day and randf() < 0.35:
						_fly(b, _pick_flower(), "out")
					else:
						_fly(b, b["hive"], "back")
	_draw()


func _fly(b: Dictionary, to: Vector3, state: String) -> void:
	b["from"] = b["pos"]
	b["to"] = to
	b["u"] = 0.0
	b["dur"] = maxf(1.0, (b["pos"] as Vector3).distance_to(to) / SPEED)
	b["state"] = state


func _pick_flower() -> Vector3:
	var fl: Array = flowers.call()
	if fl.is_empty():
		return Vector3(0, 1.5, 0)
	return fl[randi() % fl.size()]


func _move(b: Dictionary, p: Vector3, delta: float) -> void:
	var old: Vector3 = b["pos"]
	var d := p - old
	if Vector2(d.x, d.z).length() > 0.002:
		b["yaw"] = lerp_angle(float(b["yaw"]), atan2(d.x, d.z), 1.0 - exp(-delta * 10.0))
	b["pos"] = p


func _draw() -> void:
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	var flap := sin(_t * 70.0) * 0.9
	for i in COUNT:
		var b: Dictionary = _bees[i]
		if b["state"] == "inside":
			for m in _mm:
				(m[0] as MultiMesh).set_instance_transform(i, hidden)
			continue
		var tr := Transform3D(Basis(Vector3.UP, float(b["yaw"])).scaled(Vector3.ONE * 1.5), b["pos"])
		for k in 4:
			(_mm[k][0] as MultiMesh).set_instance_transform(i, tr * (_mm[k][1] as Transform3D))
		# крильця махають (кожна бджола — у своєму ритмі)
		var fl := flap * (1.0 if i % 2 == 0 else -1.0)
		var flat := Basis(Vector3.RIGHT, PI / 2)
		for side in [1.0, -1.0]:
			var hinge := Transform3D(Basis(Vector3.BACK, side * (0.35 + fl)), Vector3(side * 0.01, 0.022, 0.004))
			var w := hinge * Transform3D(flat, Vector3(side * 0.016, 0, -0.006))
			(_mm[4 if side > 0 else 5][0] as MultiMesh).set_instance_transform(i, tr * w)
