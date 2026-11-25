extends Node3D
## Робот-помічник Beep (модель з Meshy): ширяє, погойдується, літає за дотиком,
## підказує, радісно крутиться. Очі світяться бірюзовим (особливо вночі).

const SPEED := 2.6
const HOVER := 1.05
const SIZE := 0.62

var body: Node3D
var bubble: Label3D
var area: Area3D
var shadow: MeshInstance3D
var eye_light: OmniLight3D
var target := Vector3.ZERO
var moving := false
var hover_t := 0.0
var bubble_left := 0.0
var _then: Callable
var _spin := 0.0
var lamp: SpotLight3D              # ліхтарик (вночі)
var _raw := false                  # летіти напряму, без обходу
var lamp_cone: MeshInstance3D
var lift := 0.0                    # на якій висоті над звичайною (злітає вгору)
var _lift_want := 0.0
var _hop_left := 0.0               # скільки ще висіти вгорі після дотику
var _cruise := false               # далекий переліт: злітає вгору, летить швидко, опускається біля цілі
var outdoors := true               # у хаті вгору не злітає
var _best_d := INF
var _stuck_t := 0.0
var piloting := false              # сидить у кабіні літака (позицію задає літак)
var _over := false                 # застряг біля сараю чи паркану — перелітає згори
var _bump := 0.0                   # в автопольоті вперся в будівлю — набирає висоту, щоб перелетіти
var _bump_t := 0.0
const R := 0.35                    # радіус «кульки» Beep для зіткнень із будівлями


func _center() -> Vector3:
	return global_position + Vector3(0, HOVER + lift, 0)


func _solid_ok() -> bool:
	## Зіткнення з хатами й деревами — лише надворі й коли Beep не всередині оболонки
	## (якщо раптом опинився всередині — вільно вибирається).
	return outdoors and not piloting and not Solids.inside(get_world_3d(), _center(), R * 0.5)


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var m := Models.spawn(body, "beep", SIZE)
	if m == null:
		body.add_child(Util.sphere(0.2, Util.mat(Color(0.95, 0.96, 0.98), 0.35), Vector3(0, 0.22, 0)))
		body.add_child(Util.sphere(0.15, Util.mat(Color(0.12, 0.14, 0.2), 0.25), Vector3(0, 0.24, 0.1), Vector3(1, 0.72, 0.55)))
	else:
		m.position.y -= SIZE * 0.5
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(0.4, 0.95, 1.0)
	eye_light.omni_range = 1.6
	eye_light.position = Vector3(0, 0.0, 0.35)
	body.add_child(eye_light)
	shadow = Util.blob_shadow(0.3, 0.25)
	add_child(shadow)
	area = Util.pick_area("beep", Vector3(0.6, 0.7, 0.6), Vector3(0, HOVER, 0))
	add_child(area)
	lamp = SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.8)
	lamp.light_energy = 3.0
	lamp.spot_range = 9.0
	lamp.spot_angle = 32.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, 0.05, 0.25)
	lamp.rotation_degrees = Vector3(-28, 180, 0)
	lamp.visible = false
	body.add_child(lamp)
	bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 44)
	bubble.pixel_size = 0.0035
	bubble.position = Vector3(0, HOVER + 0.55, 0)
	add_child(bubble)


func _process(delta: float) -> void:
	hover_t += delta
	if piloting:
		body.position = Vector3(0, 0.0, 0)
		body.rotation = Vector3.ZERO
		area.position.y = 0.0
		bubble.position.y = 0.9
		shadow.visible = false
		eye_light.light_energy = lerpf(0.15, 1.2, Game.night_amount())
		if bubble_left > 0.0:
			bubble_left -= delta
			if bubble_left <= 0.0:
				bubble.visible = false
		return
	shadow.visible = true
	if _hop_left > 0.0:
		_hop_left -= delta
		if _hop_left <= 0.0 and not _cruise:
			_lift_want = 0.0
	if _bump > 0.0:
		_bump_t -= delta
		if _bump_t <= 0.0:
			_bump = 0.0
	var want := maxf(_lift_want, _bump)
	var new_lift := lerpf(lift, want, 1.0 - exp(-delta * (1.2 if want > lift else 1.6)))
	# угору-вниз — не крізь дах чи крону (біля цілі в автопольоті — вільно, щоб сісти куди треба)
	var near_goal := moving and Vector2(target.x - position.x, target.z - position.z).length() < 2.5
	if absf(new_lift - lift) > 0.00001 and not near_goal and _solid_ok():
		var mv := Solids.move(get_world_3d(), _center(), Vector3(0, new_lift - lift, 0), R, false)
		new_lift = lift + mv.y
	lift = new_lift
	body.position = Vector3(0, HOVER + lift + sin(hover_t * 2.2) * 0.06, 0)
	area.position.y = lift
	bubble.position.y = HOVER + 0.55 + lift
	body.rotation.z = sin(hover_t * 1.3) * 0.06
	shadow.scale = Vector3.ONE * (1.0 - sin(hover_t * 2.2) * 0.08)
	eye_light.light_energy = lerpf(0.15, 1.2, Game.night_amount())
	if _spin > 0.0:
		_spin -= delta
		body.rotation.y += delta * TAU / 0.6
		if _spin <= 0.0:
			body.rotation.y = 0.0
	if bubble_left > 0.0:
		bubble_left -= delta
		if bubble_left <= 0.0:
			bubble.visible = false
	if moving:
		var real := target - position
		real.y = 0.0
		# облітає високі речі (хату, криницю, дерева, піч, шафу); низькі — перелітає
		var high := lift > 3.0
		var goal := target if (_raw or high) else Obstacles.steer(position, target, 0.35, 0.9, Obstacles.all)
		var to := goal - position
		to.y = 0.0
		if to.length() < 0.05:
			to = real
		var d := real.length()
		if _cruise:
			# далеко — вгору на 10 м і швидко; близько до цілі — вниз
			_lift_want = 10.0 if d > 16.0 else 0.0
		# не наближається до цілі — уперся в стіну: піднімається й перелітає
		if d < _best_d - 0.05:
			_best_d = d
			_stuck_t = 0.0
		else:
			_stuck_t += delta
		if _stuck_t > 0.8 and outdoors and not _raw and not _over:
			_over = true
			_stuck_t = 0.0
		if _over:
			_lift_want = 5.0 if d > 2.5 else 0.0
		var top := 11.0 + clampf(lift / 10.0, 0.0, 1.0) * 11.0       # угорі — до 22 м/с
		var v := maxf(SPEED, minf(d * 0.8, top)) * delta * clampf(d, 0.35, 1.0)
		if _cruise and lift < 6.0 and d > 16.0:
			v = minf(v, (SPEED + lift) * delta)          # спершу набирає висоту, потім летить
		if d > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 5.0))
			body.rotation.x = lerpf(body.rotation.x, 0.18, 0.1)
		if d <= v:
			position = Vector3(target.x, 0, target.z)
			moving = false
			_cruise = false
			_over = false
			_lift_want = 0.0
			body.rotation.x = 0.0
			if _then.is_valid():
				var cb := _then
				_then = Callable()
				cb.call()
		else:
			var step := to.normalized() * v
			# на висоті (де кола-перешкоди вже не діють) — не крізь дахи: уперся — набирає висоту
			if lift > 2.5 and not _raw and d > 2.5 and _solid_ok():
				var mv := Solids.move(get_world_3d(), _center(), step, R, false)
				if mv.length() < step.length() * 0.6:
					_bump = minf(maxf(_bump, lift + 2.5), 30.0)
					_bump_t = 1.5
				step = Vector3(mv.x, 0, mv.z)
			position += step
			if not _raw and not high:
				position = Obstacles.push_out(position, 0.35, 0.9, Obstacles.all)
	else:
		body.rotation.x = lerpf(body.rotation.x, 0.0, 0.1)


func fly_to(p: Vector3, then := Callable()) -> void:
	_raw = false
	target = Obstacles.push_out(Vector3(p.x, 0, p.z), 0.35, 0.9, Obstacles.all)
	moving = true
	_then = then
	_cruise = outdoors and Vector2(target.x - position.x, target.z - position.z).length() > 25.0
	_best_d = INF
	_stuck_t = 0.0
	_over = false


func face(p: Vector3) -> void:
	var d := p - global_position
	rotation.y = atan2(d.x, d.z)


func say(text: String, secs := 3.0) -> void:
	bubble.text = text
	bubble.visible = true
	bubble_left = secs


func happy() -> void:
	_spin = 0.6


func hop(h := 10.0) -> void:
	## Торкнулися: злітає вгору (на подвір'ї — на 10 м, роздивитися довкола), трохи висить і опускається.
	_lift_want = h if outdoors else 0.6
	_hop_left = 4.0 if outdoors else 1.2
	_spin = 0.6


func toggle_lamp() -> bool:
	lamp.visible = not lamp.visible
	return lamp.visible


func fly_to_raw(p: Vector3, then := Callable()) -> void:
	## Без обходу перешкод (крізь двері).
	_cruise = false
	_lift_want = 0.0
	target = Vector3(p.x, 0, p.z)
	moving = true
	_raw = true
	_then = then


func drive(j: Vector2, climb: float, delta: float, _cam_yaw := 0.0) -> void:
	## Ручне керування: джойстик уліво-вправо — поворот, уперед-назад — летіти; ▲▼ — висота.
	moving = false
	_hop_left = 0.0
	if delta <= 0.0:
		return
	rotation.y -= j.x * 2.2 * delta
	var top := 5.0 + clampf(lift / 10.0, 0.0, 1.0) * 9.0
	var v := j.y * (top if j.y > 0.0 else 2.5)
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var p := position + f * v * delta
	if lift < 3.0:
		p = Obstacles.push_out(p, 0.35, 0.9, Obstacles.all)
	var flat := Vector2(p.x, p.z)
	var lim := 215.0 + 50.0 * clampf(-flat.x / maxf(flat.length(), 0.001), 0.0, 1.0)     # на захід (за злітну смугу) — на 50 м далі
	if flat.length() > lim:
		flat = flat.normalized() * lim
		p = Vector3(flat.x, 0, flat.y)
	# стіни й дахи будівель, крони дерев: ковзає вздовж, на схил даху — вилітає вгору
	if _solid_ok():
		var mv := Solids.move(get_world_3d(), _center(), Vector3(p.x - position.x, 0, p.z - position.z), R, true)
		p = position + Vector3(mv.x, 0, mv.z)
		if mv.y > 0.0:
			lift += mv.y
			_lift_want = maxf(_lift_want, lift)
	position = Vector3(p.x, 0, p.z)
	if absf(climb) > 0.1:
		_lift_want = clampf(lift + climb * 4.0, 0.0, 25.0)
	body.rotation.x = lerpf(body.rotation.x, clampf(j.y, -0.5, 1.0) * 0.2, 0.1)
