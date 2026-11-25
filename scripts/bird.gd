extends Node3D
## Курочка або півник (моделі без готових рухів): дріботять подвір'ям, дзьобають зерно,
## трусять головою; півник іноді кукурікає.

var model: Node3D
var area: Area3D
var home := Vector3.ZERO
var radius := 2.5
var speed := 0.45
var rooster := false
var _target := Vector3.ZERO
var _pause := 1.0
var _peck := 0.0
var _t := 0.0
var _bubble: Label3D
var _bubble_left := 0.0
var base_home := Vector3.ZERO      # звичне місце біля курника
var base_radius := 2.5
var mode := "free"                 # free — гуляє; grain — клює зерно; trough — п'є; to_coop — іде в курник; inside — у курнику
var coop_door := Vector3.ZERO
var coop_hole := Vector3(7.05, 0.62, -1.6)   # круглий лаз у курнику (над драбинкою)
static var ramp_user = null                   # по драбинці — по одній


func setup(id: String, height: float, at: Vector3, is_rooster := false) -> void:
	rooster = is_rooster
	home = at
	base_home = at
	position = at
	_target = at
	model = Models.spawn(self, id, height)
	_setup_anims()
	area = Util.pick_area("bird", Vector3(0.4, height, 0.5), Vector3(0, height / 2.0, 0))
	add_child(area)
	add_child(Util.blob_shadow(0.18, 0.25))
	_bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 40)
	_bubble.pixel_size = 0.003
	_bubble.position = Vector3(0, height + 0.35, 0)
	add_child(_bubble)
	_t = randf() * 10.0


var ap: AnimationPlayer
var _a_idle := ""
var _a_walk := ""
var bpose
var goose := false
var voice := "Га-га-га!"


func _setup_anims() -> void:
	## Моделі з рухами (Animate Anything): стоїть / іде; клювання — нахилом шиї кодом.
	if model == null:
		return
	ap = Models.anim_player(model)
	if ap == null:
		return
	_a_idle = Models.find_anim(ap, ["idle"])
	_a_walk = Models.find_anim(ap, ["walk"])
	Models.set_loop(ap, [_a_idle, _a_walk])
	ap.playback_default_blend_time = 0.2
	ap.play(_a_idle)
	ap.seek(randf() * 2.0, true)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		bpose = preload("res://scripts/bird_pose.gd").new()
		bpose.axis_node = self
		bpose.setup(sks[0])
		sks[0].add_child(bpose)


func _anim(walking: bool, fast := false) -> void:
	if ap == null:
		return
	var want := _a_walk if walking else _a_idle
	if ap.current_animation != want:
		ap.play(want)
	ap.speed_scale = (1.8 if fast else 1.0) if walking else 1.0


func say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_left = 2.0


func _process(delta: float) -> void:
	_t += delta
	if model == null:
		return
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.visible = false
	if mode == "inside" or mode == "entering":
		return
	if mode == "trek":
		_trek_step(delta)
		return
	if mode == "swim":
		_swim_step(delta)
		return
	if mode == "ramp" or mode == "ramp_down":
		_ramp(delta)
		return
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	if mode == "to_coop" and d <= 0.08:
		# біля драбинки: чекає своєї черги
		if ramp_user == null or not is_instance_valid(ramp_user):
			ramp_user = self
			mode = "ramp"
			_ramp_t = 0.0
		else:
			model.position.y = 0.0
		return
	if d > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
		var sp := speed * (2.6 if mode == "to_coop" or mode == "grain" and d > 0.8 else 1.0)
		position += to / d * minf(sp * delta, d)
		if mode != "to_coop":
			position = Obstacles.push_out(position, 0.12)
		if ap:
			_anim(true, sp > speed * 1.5)
			if bpose:
				bpose.peck = 0.0
		else:
			# дріботіння: маленькі підскоки й погойдування
			model.position.y = abs(sin(_t * 14.0)) * 0.03
			model.rotation.z = sin(_t * 14.0) * 0.06
			model.rotation.x = 0.0
		return
	_anim(false)
	model.position.y = 0.0
	model.rotation.z = 0.0
	if _peck > 0.0:
		_peck -= delta
		var k := maxf(0.0, sin(_peck * 9.0))     # дзьобає зерно
		if bpose:
			bpose.peck = k
		else:
			model.rotation.x = k * 0.55
		return
	if bpose:
		bpose.peck = 0.0
	model.rotation.x = lerpf(model.rotation.x, 0.0, 0.2)
	_pause -= delta
	if _pause > 0.0:
		return
	_pause = randf_range(0.8, 3.0)
	if mode == "grain" or mode == "trough":
		# біля зерна чи корита — переважно клює, іноді переступає
		if float(Game.state.get("hens_fed" if mode == "grain" else "trough", 0.0)) < 30.0:
			roam()
		elif randf() < 0.7:
			_peck = randf_range(1.2, 2.5)
		else:
			var a2 := randf() * TAU
			_target = home + Vector3(cos(a2), 0, sin(a2)) * randf_range(0.1, radius)
		return
	var r := randf()
	if r < 0.45:
		var a := randf() * TAU
		_target = Obstacles.push_out(home + Vector3(cos(a), 0, sin(a)) * randf_range(0.3, radius), 0.15)
	elif r < 0.85:
		_peck = randf_range(1.0, 2.2)
	elif rooster and Game.hour() < 10.0 and randf() < 0.5:
		say("Ку-ку-рі-ку!")
	elif goose and randf() < 0.3:
		say(voice)
	elif not rooster and not goose and randf() < 0.3:
		say("Ко-ко-ко!")


var _ramp_t := 0.0


func _ramp(delta: float) -> void:
	## Піднімається драбинкою до лазу й пірнає всередину (або виходить і спускається).
	_ramp_t += delta
	var up := mode == "ramp"
	var a := coop_door
	var b := coop_hole - Vector3(0.12, 0.0, 0.0)
	var u := clampf(_ramp_t / 1.1, 0.0, 1.0)
	if not up:
		u = 1.0 - u
	position = a.lerp(b, u)
	rotation.y = atan2(b.x - a.x, b.z - a.z) + (0.0 if up else PI)
	if ap:
		_anim(true)
	else:
		model.position.y = abs(sin(_t * 16.0)) * 0.03
	model.rotation.x = (-0.25 if up else 0.25) if not goose else 0.0
	if _ramp_t >= 1.1:
		if up:
			# стрибок у лаз
			var tw := create_tween()
			tw.tween_property(self, "position", coop_hole + Vector3(0.15, -0.05, 0), 0.25)
			tw.parallel().tween_property(self, "scale", Vector3.ONE * 0.2, 0.25)
			tw.tween_callback(func():
				visible = false
				scale = Vector3.ONE
				mode = "inside"
				if ramp_user == self:
					ramp_user = null)
			mode = "entering"
		else:
			position.y = 0.0
			model.rotation.x = 0.0
			roam()
			var a2 := randf() * TAU
			_target = coop_door + Vector3(cos(a2) - 0.8, 0, sin(a2)) * 0.9


func poke() -> void:
	## Торкнулися — злякано відбігає.
	if mode == "trek" or mode == "swim":
		say(voice)
		return
	var a := randf() * TAU
	_target = position + Vector3(cos(a), 0, sin(a)) * 1.2
	_target = home + (_target - home).limit_length(radius)
	say("Ку-ку-рі-ку!" if rooster else "Ко-ко!")


func go_eat(p: Vector3, what := "grain") -> void:
	## Біжить до зерна (або до корита з водою) і клює.
	if mode in ["inside", "to_coop", "ramp", "ramp_down", "entering", "trek", "swim"]:
		return
	mode = what
	home = p
	radius = 0.7 if what == "grain" else 0.35
	var a := randf() * TAU
	_target = p + Vector3(cos(a), 0, sin(a)) * randf_range(0.15, radius)
	_pause = 0.2
	if randf() < 0.5:
		say("Ко-ко-ко!")


func roam() -> void:
	mode = "free"
	home = base_home
	radius = base_radius


func go_coop(door: Vector3) -> void:
	## Заганяють у курник: біжить до дверцят і зникає всередині.
	coop_door = door
	mode = "to_coop"
	_target = door
	_peck = 0.0
	say("Ко-ко!")


func come_out(door: Vector3) -> void:
	## Зранку виходить з курника.
	if mode != "inside":
		return
	visible = true
	position = door
	roam()
	var a := randf() * TAU
	_target = door + Vector3(cos(a) - 0.6, 0, sin(a)) * 0.9
	if rooster:
		say("Ку-ку-рі-ку!")



# ------------------------------------------------------------------ гуси: похід на ставок і плавання
var path: Array = []               # точки шляху (trek)
var after_trek := "free"           # що робити, коли дійде: swim / free
var pond_c := Vector3.ZERO
var pond_r := 7.0
var _swim_y := 0.0
var trek_offset := Vector3.ZERO    # кожна гуска трохи збоку — йдуть табунцем, а не по одній лінії
var trek_delay := 0.0


func start_trek(pts: Array, then: String, delay := 0.0) -> void:
	if mode in ["inside", "to_coop", "ramp", "ramp_down", "entering"]:
		return
	path = pts.duplicate()
	after_trek = then
	trek_delay = delay
	mode = "trek"
	_peck = 0.0


func trekking() -> bool:
	return mode == "trek"


func _trek_step(delta: float) -> void:
	if trek_delay > 0.0:
		trek_delay -= delta
		_anim(false)
		return
	if path.is_empty():
		if after_trek == "swim":
			mode = "swim"
			_target = _swim_point()
			if randf() < 0.5:
				say(voice)
		else:
			roam()
			_target = position
		return
	var tgt: Vector3 = path[0] + (trek_offset if path.size() > 1 else Vector3.ZERO)
	var to := tgt - position
	to.y = 0.0
	var d := to.length()
	if d < 0.25:
		path.pop_front()
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
	var sp := speed * 3.0
	position += to / d * minf(sp * delta, d)
	position.y = lerpf(position.y, 0.0, 1.0 - exp(-delta * 4.0))
	model.position.y = lerpf(model.position.y, 0.0, 0.2)
	if ap:
		_anim(true, true)
		if bpose:
			bpose.peck = 0.0
	else:
		model.position.y = abs(sin(_t * 14.0)) * 0.03


func _swim_point() -> Vector3:
	var a := randf() * TAU
	return pond_c + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, pond_r)


func _swim_step(delta: float) -> void:
	## Пливе ставком: сидить у воді, трохи погойдується, повільно ковзає до нової точки.
	_swim_y = lerpf(_swim_y, -0.16 * scale.y, 1.0 - exp(-delta * 2.0))
	position.y = _swim_y + sin(_t * 1.7) * 0.015
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	if d > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 2.0))
		position += to / d * minf(speed * 0.8 * delta, d)
	_anim(false)
	if bpose:
		bpose.peck = 0.0
	_pause -= delta
	if _pause <= 0.0:
		_pause = randf_range(3.0, 8.0)
		if randf() < 0.6:
			_target = _swim_point()
		elif randf() < 0.3:
			say(voice)
