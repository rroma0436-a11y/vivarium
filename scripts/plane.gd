extends Node3D
## Жовтий літак. Пілот — робот Beep. Стоїть в ангарі на аеродромі (колишня Галявина дракона).
## Злітає з будь-якого місця, де стоїть (розбіг уперед), у польоті керує гравець:
## джойстик — повороти й швидкість, ▲▼ — висота, «Сісти» — сідає просто під собою (якщо там рівно й сухо),
## «В ангар» — сам летить на аеродром, сідає на смугу й заїжджає в ангар.
## Пропелер крутиться, коли працює мотор.

signal landed

const LENGTH := 6.5
const SEAT := Vector3(0, 1.95, 0.2)          # кабіна (у системі літака; літак дивиться вздовж +Z)
const MIN_Y := 8.0
const MAX_Y := 55.0
const LIMIT := 215.0

var home := Vector3.ZERO                       # місце в ангарі
var runway_a := Vector3.ZERO                   # початок смуги (біля ангара)
var runway_b := Vector3.ZERO                   # кінець смуги
var state := "rest"                            # rest, taxi, roll, ride, land, home, approach
var pilot: Node3D                              # Beep, коли сидить у кабіні
var rider: Node3D                              # = pilot (для сумісності)
var hold := false
var joy := Vector2.ZERO
var climb := 0.0
var speed := 0.0
var in_hangar := true
var hangar_door: Callable                      # (open: bool) — ворота ангара

var model: Node3D
var prop: Node3D
var _prop_speed := 0.0
var _prop_axis := Vector3.RIGHT
var _vy := 0.0
var _roll := 0.0
var _t := 0.0
var _bubble: Label3D
var _bubble_left := 0.0
var _wall_said := false
var _engine: AudioStreamPlayer3D
var _approach := 0                             # етап заходу на посадку в ангар
var area: Area3D
var _idle_engine := false
var pilot_seat := Vector3.ZERO                 # де сидить пілот (Ніка — нижче, ніж Beep)                      # мотор працює на холостих (чекаємо пілота)
var _gen: AudioStreamGeneratorPlayback
var _phase := 0.0


func setup(hangar_spot: Vector3, ra: Vector3, rb: Vector3) -> void:
	home = hangar_spot
	runway_a = ra
	runway_b = rb
	position = home
	rotation.y = atan2(rb.x - ra.x, rb.z - ra.z)        # носом до смуги
	model = Models.spawn(self, "plane_y", LENGTH, "realx")
	if model == null:
		return
	model.rotation.y = PI / 2.0                           # ніс моделі (−X) → уперед (+Z)
	_cut_propeller()
	area = Util.pick_area("plane", Vector3(6.0, 2.2, 6.5), Vector3(0, 1.1, 0))
	add_child(area)
	_bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 52)
	_bubble.pixel_size = 0.006
	_bubble.position = Vector3(0, 3.2, 0)
	add_child(_bubble)
	_make_engine_sound()


func _make_engine_sound() -> void:
	## Гул мотора — синтезуємо на льоту (тон залежить від обертів пропелера).
	var g := AudioStreamGenerator.new()
	g.mix_rate = 22050.0
	g.buffer_length = 0.25
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = g
	_engine.bus = "SFX"
	_engine.unit_size = 10.0
	_engine.max_distance = 90.0
	_engine.volume_db = -14.0
	add_child(_engine)


func _engine_step() -> void:
	if _engine == null:
		return
	var on := _prop_speed > 1.0
	if on and not _engine.playing:
		_engine.play()
		_gen = _engine.get_stream_playback()
	elif not on and _engine.playing:
		_engine.stop()
		_gen = null
	if _gen == null:
		return
	var n := _gen.get_frames_available()
	var f := 38.0 + _prop_speed * 2.2
	var amp := clampf(_prop_speed / 40.0, 0.15, 0.55)
	var inc := f / 22050.0
	for i in n:
		_phase = fmod(_phase + inc, 1.0)
		var s := (_phase * 2.0 - 1.0) * 0.6 + sin(_phase * TAU * 2.0) * 0.4
		s *= amp * (0.85 + 0.15 * sin(_phase * TAU * 0.5))
		_gen.push_frame(Vector2(s, s))


func _cut_propeller() -> void:
	var mis := model.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return
	var mi: MeshInstance3D = mis[0]
	var part := Models.cut(model, AABB(Vector3(-1.96, 0.3, -0.8), Vector3(0.35, 1.5, 1.6)), 100.0, mi)
	if part == null:
		return
	prop = Models.hinge(part, mi.to_global(Vector3(-1.75, 1.05, 0.0)))
	_prop_axis = (prop.global_transform.basis.inverse() * mi.global_transform.basis.x).normalized()
	# у моделі за першим пропелером є ще один (нерухомий) — прибираємо його лопаті
	for sg in [1.0, -1.0]:
		var extra := Models.cut(model, AABB(Vector3(-1.48, 0.85, 0.36 if sg > 0.0 else -0.9), Vector3(0.27, 0.4, 0.54)), 100.0, mi)
		if extra:
			extra.queue_free()


func say(t: String, secs := 2.0) -> void:
	if _bubble == null:
		return
	_bubble.text = t
	_bubble.visible = true
	_bubble_left = secs


func seat_local() -> Vector3:
	return SEAT


func seat_global() -> Vector3:
	return to_global(SEAT)


func flying() -> bool:
	return state in ["ride", "home", "approach", "land", "roll"]


func poke() -> void:
	if state == "rest":
		say("Сідай у кабіну — полетимо!", 2.0)


# ------------------------------------------------------------------ злітання
func roll_out() -> void:
	## Мотор, ворота ангара, виїзд на початок смуги (носом уздовж смуги). await roll_out()
	if state != "rest" or not in_hangar:
		return
	state = "taxi"
	if hangar_door.is_valid():
		hangar_door.call(true)
	await get_tree().create_timer(2.0).timeout
	await _taxi_to(runway_a, 3.5)
	await _turn_to((runway_b - runway_a).normalized())
	in_hangar = false
	if hangar_door.is_valid():
		hangar_door.call(false)
	state = "rest"
	_idle_engine = true


func _turn_to(dir: Vector3) -> void:
	var want := atan2(dir.x, dir.z)
	while absf(angle_difference(rotation.y, want)) > 0.02:
		rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-get_process_delta_time() * 3.0))
		await get_tree().process_frame
	rotation.y = want


func take_off(_free := true) -> void:
	## Розбіг уперед і зліт (з ангара спершу виїжджає на смугу).
	if state != "rest":
		return
	if in_hangar:
		await roll_out()
	_idle_engine = false
	state = "roll"
	speed = 0.0
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var t := 0.0
	while t < 4.0:
		var dt := get_process_delta_time()
		t += dt
		speed = minf(speed + 6.0 * dt, 22.0)
		var p := global_position + f * speed * dt
		if t > 2.4:
			p.y += (t - 2.4) * 3.5 * dt * 2.0
			rotation.x = lerpf(rotation.x, -0.18, dt * 2.0)
		global_position = p
		await get_tree().process_frame
	speed = 16.0
	_vy = 3.0
	state = "ride"
	if _want_home:
		_want_home = false
		go_home()


func _taxi_to(p: Vector3, v: float) -> void:
	## Їде по землі до точки (повертається носом і котиться).
	while true:
		var to := p - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.2:
			break
		var dt := get_process_delta_time()
		var want := atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-dt * 2.5))
		var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
		global_position += f * minf(v * dt, d) * clampf(f.dot(to / d), 0.2, 1.0)
		await get_tree().process_frame


# ------------------------------------------------------------------ польот
func _process(delta: float) -> void:
	_t += delta
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.visible = false
	var want_prop := 0.0
	if state != "rest":
		want_prop = 14.0 + speed * 1.4
	if state == "taxi" or state == "rest" and _idle_engine:
		want_prop = 9.0
	_engine_step()
	_prop_speed = lerpf(_prop_speed, want_prop, 1.0 - exp(-delta * 1.5))
	if prop:
		prop.rotate_object_local(_prop_axis, _prop_speed * delta)
	match state:
		"ride":
			_ride(delta)
		"home":
			_autopilot(delta)
	if pilot and is_instance_valid(pilot):
		pilot.global_position = to_global(pilot_seat if pilot_seat != Vector3.ZERO else SEAT)
		pilot.rotation = rotation


func _ride(delta: float) -> void:
	var want_speed := 15.0 + joy.y * (8.0 if joy.y > 0.0 else 6.0)
	speed = lerpf(speed, want_speed, 1.0 - exp(-delta * 1.2))
	var turn := -joy.x * 1.1
	var flat := Vector2(global_position.x, global_position.z)
	var lim := LIMIT + 50.0 * clampf(-flat.x / maxf(flat.length(), 0.001), 0.0, 1.0)     # на захід (за злітну смугу) — на 50 м далі
	if flat.length() > lim:
		var back := atan2(-global_position.x, -global_position.z)
		turn = clampf(angle_difference(rotation.y, back) * 1.5, -1.1, 1.1)
		if not _wall_said:
			_wall_said = true
			say("Далі туман — повертаємо!", 2.5)
	elif flat.length() < lim - 30.0:
		_wall_said = false
	rotation.y += turn * delta
	_vy = lerpf(_vy, climb * 7.0, 1.0 - exp(-delta * 2.5))
	_move(delta, turn)


func _move(delta: float, turn: float) -> void:
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var p := global_position + f * speed * delta
	p.y += _vy * delta
	var low := min_y(p)
	if p.y < low:
		p.y = lerpf(p.y, low, 1.0 - exp(-delta * 3.0))
		_vy = maxf(_vy, 0.0)
	p.y = minf(p.y, MAX_Y)
	global_position = p
	_roll = lerpf(_roll, clampf(-turn * 0.6, -0.7, 0.7), 1.0 - exp(-delta * 3.0))
	rotation.z = _roll
	rotation.x = lerpf(rotation.x, clampf(-_vy / 16.0, -0.35, 0.35), 1.0 - exp(-delta * 3.0))


static func min_y(p: Vector3) -> float:
	## Не нижче дерев, вітряка, церкви й пагорбів.
	var low := MIN_Y
	if Vector2(p.x + 82.0, p.z + 50.0).length() < 30.0:
		low = 18.0
	if Vector2(p.x, p.z - 80.0).length() < 10.0:
		low = 16.0
	if Vector2(p.x, p.z).length() > 230.0:
		low = 22.0
	return low


# ------------------------------------------------------------------ посадка будь-де
func can_land_here() -> String:
	## Порожній рядок — можна сідати; інакше — чому ні.
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var main = get_node_or_null("/root/Main")
	for k in 7:
		var p := global_position + f * (12.0 + k * 5.0)
		if Vector2(p.x, p.z).length() > 200.0:
			return "Тут уже пагорби — далі не сісти."
		if absf(p.z - 102.0) < 7.0:
			return "Під нами річка!"
		if main and main.world.outer.pond_sd(p) < 3.0:
			return "Під нами ставок!"
		if main and main.world.outer.is_blocked(p, 5.0):
			return "Тут дерева чи хати — шукаймо рівну галявину."
	return ""


func land_here() -> void:
	if state != "ride":
		return
	var why := can_land_here()
	if why != "":
		say(why, 2.5)
		return
	state = "land"
	say("Сідаємо!", 1.5)
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	# плавне зниження вперед
	while global_position.y > 0.05:
		var dt := get_process_delta_time()
		speed = lerpf(speed, 15.0, 1.0 - exp(-dt * 1.0))
		_vy = lerpf(_vy, -maxf(3.0, global_position.y * 0.45), 1.0 - exp(-dt * 2.0))
		var p := global_position + f * speed * dt
		p.y = maxf(0.0, p.y + _vy * dt)
		global_position = p
		_roll = lerpf(_roll, 0.0, 1.0 - exp(-dt * 3.0))
		rotation.z = _roll
		rotation.x = lerpf(rotation.x, -0.06 if p.y > 1.0 else 0.0, 1.0 - exp(-dt * 3.0))
		await get_tree().process_frame
	await _rollout(f)
	in_hangar = false
	state = "rest"
	landed.emit()


func _rollout(f: Vector3) -> void:
	while speed > 0.3:
		var dt := get_process_delta_time()
		speed = maxf(0.0, speed - 6.0 * dt)
		global_position += f * speed * dt
		global_position.y = 0.0
		rotation.x = lerpf(rotation.x, 0.0, 1.0 - exp(-dt * 4.0))
		rotation.z = lerpf(rotation.z, 0.0, 1.0 - exp(-dt * 4.0))
		await get_tree().process_frame
	speed = 0.0
	rotation.x = 0.0
	rotation.z = 0.0


# ------------------------------------------------------------------ в ангар (автопілот)
var _want_home := false


func go_home() -> void:
	if state in ["roll", "taxi"]:
		_want_home = true
		return
	if state == "ride":
		state = "home"
		_approach = 0
		say("Летимо на аеродром!", 2.0)


func _autopilot(delta: float) -> void:
	## Етап 0: летимо до точки далеко за кінцем смуги; етап 1: вирівнюємось і знижуємось уздовж смуги.
	var dir := (runway_a - runway_b).normalized()           # сідаємо в бік ангара
	var entry := runway_b - dir * 55.0 + Vector3(0, 14.0, 0)
	var target := entry
	if _approach == 1:
		target = runway_b + Vector3(0, 0, 0)
	var to := target - global_position
	var flat := Vector2(to.x, to.z)
	var want := atan2(to.x, to.z)
	var turn := clampf(angle_difference(rotation.y, want) * 1.6, -1.1, 1.1)
	rotation.y += turn * delta
	speed = lerpf(speed, 16.0 if _approach == 0 else 13.0, 1.0 - exp(-delta))
	if _approach == 0:
		_vy = lerpf(_vy, clampf((target.y - global_position.y) * 0.5, -5.0, 5.0), 1.0 - exp(-delta * 2.0))
		_move(delta, turn)
		if flat.length() < 10.0:
			_approach = 1
	else:
		# ковзаємо вниз до початку смуги
		var dist := flat.length()
		var want_y := clampf(dist * 0.25, 0.0, 14.0)
		_vy = lerpf(_vy, clampf((want_y - global_position.y) * 1.2, -6.0, 3.0), 1.0 - exp(-delta * 3.0))
		var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
		var p := global_position + f * speed * delta
		p.y = maxf(0.0, p.y + _vy * delta)
		global_position = p
		_roll = lerpf(_roll, clampf(-turn * 0.6, -0.7, 0.7), 1.0 - exp(-delta * 3.0))
		rotation.z = _roll
		rotation.x = lerpf(rotation.x, 0.0, 1.0 - exp(-delta * 3.0))
		if dist < 3.0 or global_position.y < 0.1 and dist < 20.0:
			state = "approach"
			_finish_home()


func _finish_home() -> void:
	global_position.y = 0.0
	var dir := (runway_a - runway_b).normalized()
	rotation.y = atan2(dir.x, dir.z)
	# котимося смугою до ангара
	while global_position.distance_to(runway_a) > 6.0:
		var dt := get_process_delta_time()
		speed = maxf(4.0, speed - 4.0 * dt)
		var to := runway_a - global_position
		to.y = 0.0
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-dt * 2.0))
		global_position += Vector3(sin(rotation.y), 0, cos(rotation.y)) * speed * dt
		global_position.y = 0.0
		_roll = lerpf(_roll, 0.0, 1.0 - exp(-dt * 4.0))
		rotation.z = _roll
		await get_tree().process_frame
	speed = 3.0
	if hangar_door.is_valid():
		hangar_door.call(true)
	# заїжджаємо в ангар (носом уперед), там розвертаємось носом до виходу
	state = "taxi"
	await _taxi_to(home, 3.0)
	await _turn_to((runway_b - runway_a).normalized())
	speed = 0.0
	in_hangar = true
	state = "rest"
	if hangar_door.is_valid():
		hangar_door.call(false)
	landed.emit()
