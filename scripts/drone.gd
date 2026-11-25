extends Node3D
## Дрон-помічник: облітає маленький город по колу, годує курей зерном
## і поливає соняшники за тином. Уночі відпочиває біля курника.

signal done(what: String)

var center := Vector3.ZERO
var radius := 2.2
var height := 2.6
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


func setup(at: Vector3, sp := {}) -> void:
	center = at
	spots = sp
	position = at + Vector3(radius, height, 0)
	model = Models.spawn(self, "drone", 0.6)
	if model:
		model.position.y -= 0.3
	add_child(Util.pick_area("drone", Vector3(0.8, 0.6, 0.8), Vector3.ZERO))
	drops = _particles(Color(0.55, 0.8, 1.0, 0.8), 0.015, 40)
	grain_fx = _particles(Color(0.95, 0.8, 0.3, 1.0), 0.02, 30)
	bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 40)
	bubble.pixel_size = 0.0032
	bubble.position = Vector3(0, 0.6, 0)
	add_child(bubble)


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
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			bubble.visible = false
	if mode == "task":
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
		var a := _t * 0.35
		var want := center + Vector3(cos(a) * radius, height + sin(_t * 1.7) * 0.12, sin(a) * radius)
		position = position.lerp(want, 1.0 - exp(-delta * 2.0))
		rotation.y = lerp_angle(rotation.y, -a, 1.0 - exp(-delta * 3.0))
		if fmod(_t, 14.0) < delta:
			_hover = 3.0       # зависає й поливає


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
		var step := minf(speed * d, to.length())
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
	say("Смачного, курочки!")
	Game.emit_event("hens_fed")
	done.emit("feed")
	await fly_to(center + Vector3(radius, height, 0))
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
	await fly_to(center + Vector3(radius, height, 0), 3.5)
	mode = "patrol"


func _play(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -8.0)


func _land() -> void:
	## Увечері летить на свій майданчик біля хати й сідає.
	mode = "task"
	drops.emitting = false
	grain_fx.emitting = false
	var pad: Vector3 = spots.get("drone_pad", center)
	say("Біп… лечу спати.", 2.0)
	await fly_to(Vector3(pad.x, 3.0, pad.z), 3.0)
	await fly_to(pad + Vector3(0, 0.32, 0), 0.8)
	rotation.y = 0.0
	mode = "rest"


func _take_off() -> void:
	mode = "task"
	var pad: Vector3 = spots.get("drone_pad", center)
	await fly_to(Vector3(pad.x, 3.0, pad.z), 1.0)
	say("Доброго ранку! Біп!", 2.0)
	await fly_to(center + Vector3(radius, height, 0), 3.0)
	mode = "patrol"
