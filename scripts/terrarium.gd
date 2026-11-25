extends Node3D
## Тераріум леопардового гекона Лимончика (моделі з Meshy).
## Гекон бігає по піску, залазить на камінь і колоду, гріється під лампою, ловить цвіркунів;
## коли холодно — ховається в схованку. Висоту поверхні беремо з карти terrarium_floor.json.

const HEIGHT := 1.25
const GECKO_LEN := 0.42
const INNER := Rect2(-0.55, -0.26, 1.1, 0.52)
# перешкоди на дні (центр x,z; радіус): схованка-колода, мисочка з водою, рослинки
const CAVE := [Vector2(-0.29, 0.02), 0.19, 1.0]
const STUFF := [[Vector2(0.415, 0.125), 0.1, 1.0], [Vector2(-0.54, -0.05), 0.06, 1.0], [Vector2(0.52, -0.2), 0.07, 1.0]]   # де можна бігати (x, z)
const HIDE_IN := Vector3(-0.36, 0.0, 0.03)       # у колоді: голова визирає з отвору (праворуч)
const HIDE_DOOR := Vector3(-0.14, 0.0, 0.0)      # вхід у схованку (отвір колоди дивиться вправо)
const BASK := Vector3(0.09, 0.0, -0.1)           # камінь під лампою
const LAMP_P := Vector3(0.15, 1.2, -0.05)
const SAND := 0.625
const GLASS := Rect2(-0.6, -0.29, 1.2, 0.58)     # голова й хвіст гекона не виходять за скло

var lamp_light: OmniLight3D
var gecko: Node3D
var anim
var thermo: Label3D
var area: Area3D
var crickets: Array = []
var _floor := {}
var _t := 0.0
var _target := Vector3.ZERO
var _speed := 0.0
var _pause := 1.0
var _mode := "rest"          # rest, walk, hide, hunt
var _lick := 0.0
var _stall := 0.0
var _last_d := INF
var _hidden := 0.0           # 1 — повністю в схованці
var _prey: Node3D            # за яким цвіркуном біжить
var _prey_best := INF
var _prey_t := 0.0


func _ready() -> void:
	var m := Models.spawn(self, "terrarium", HEIGHT)
	if m == null:
		add_child(Util.box(Vector3(1.2, 0.6, 0.6), Util.mat(Color(0.55, 0.3, 0.2)), Vector3(0, 0.3, 0)))
	var f := FileAccess.open("res://assets/models/terrarium_floor.json", FileAccess.READ)
	if f:
		_floor = JSON.parse_string(f.get_as_text())
	lamp_light = OmniLight3D.new()
	lamp_light.light_color = Color(1, 0.65, 0.35)
	lamp_light.omni_range = 1.4
	lamp_light.light_energy = 0.0
	lamp_light.position = LAMP_P + Vector3(0, -0.15, 0)
	add_child(lamp_light)
	gecko = Node3D.new()
	add_child(gecko)
	var g := Models.spawn(gecko, "gecko", GECKO_LEN, "z")
	if g == null:
		gecko.add_child(Util.capsule(0.03, 0.22, Util.mat(Color(0.98, 0.82, 0.32)), Vector3(0, 0.03, 0), Vector3(90, 0, 0)))
	else:
		var sks := g.find_children("*", "Skeleton3D", true, false)
		if sks.size() > 0:
			anim = preload("res://scripts/gecko_anim.gd").new()
			anim.setup(sks[0])
			sks[0].add_child(anim)
	gecko.position = Vector3(HIDE_IN.x, SAND, HIDE_IN.z)
	gecko.rotation.y = PI * 0.5
	_mode = "hide"
	_target = gecko.position
	thermo = Label3D.new()
	thermo.font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	thermo.font_size = 40
	thermo.pixel_size = 0.0013
	thermo.outline_size = 12
	thermo.outline_modulate = Color(1, 1, 1, 0.95)
	thermo.position = Vector3(-0.47, 0.95, 0.345)
	add_child(thermo)
	area = Util.pick_area("terrarium", Vector3(1.4, 1.35, 0.8), Vector3(0, 0.67, 0))
	add_child(area)


func floor_y(x: float, z: float) -> float:
	## Висота поверхні (пісок, камінь, колода) у точці; беремо найвищу з 4 сусідніх клітинок.
	if _floor.is_empty():
		return SAND
	var nx: int = _floor["nx"]
	var nz: int = _floor["nz"]
	var fx := (x - float(_floor["x0"])) / (float(_floor["x1"]) - float(_floor["x0"])) * (nx - 1)
	var fz := (z - float(_floor["z0"])) / (float(_floor["z1"]) - float(_floor["z0"])) * (nz - 1)
	var ix := clampi(int(fx), 0, nx - 2)
	var iz := clampi(int(fz), 0, nz - 2)
	var h: Array = _floor["h"]
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var a: float = lerpf(h[iz * nx + ix], h[iz * nx + ix + 1], tx)
	var b: float = lerpf(h[(iz + 1) * nx + ix], h[(iz + 1) * nx + ix + 1], tx)
	return maxf(lerpf(a, b, tz), SAND - 0.02)


func _process(delta: float) -> void:
	_t += delta
	var gs: Dictionary = Game.state["gecko"]
	var on: bool = gs["lamp"]
	lamp_light.light_energy = lerpf(lamp_light.light_energy, 2.2 if on else 0.0, 0.1)
	var temp: float = gs["temp"]
	thermo.text = "%d°C" % roundi(temp)
	if temp < Game.GECKO_MIN:
		thermo.modulate = Color(0.2, 0.45, 0.95)
	elif temp <= Game.GECKO_MAX:
		thermo.modulate = Color(0.15, 0.6, 0.25)
	else:
		thermo.modulate = Color(0.9, 0.25, 0.2)
	_think(delta, temp)
	_move(delta)
	_crickets(delta)
	if anim:
		anim.breathe = _t
		if _lick > 0.0:
			_lick -= delta
			anim.nod = -sin(_lick * 18.0) * 0.35
		else:
			anim.nod = 0.0


func _think(delta: float, temp: float) -> void:
	var cold := temp < Game.GECKO_MIN - 1.0
	if cold:
		if _mode not in ["hide", "hiding"]:
			if gecko.position.distance_to(Vector3(HIDE_IN.x, gecko.position.y, HIDE_IN.z)) < 0.12:
				_mode = "hide"
				_speed = 0.0
			else:
				_mode = "to_hide"
				_go(HIDE_DOOR, 0.16)
		return
	if _mode in ["hide", "hiding", "to_hide"]:
		# зігрілося — виходить зі схованки
		_mode = "exit"
		_go(HIDE_DOOR, 0.12)
		_pause = 0.5
		return
	if _mode == "exit":
		if _speed == 0.0:
			_mode = "rest"
		return
	if not crickets.is_empty() and _mode != "hunt":
		_mode = "hunt"
	if _mode == "hunt":
		if crickets.is_empty():
			_mode = "rest"
			_pause = 1.5
			return
		var c := nearest_cricket()
		if c == null:
			_speed = 0.0
			return
		# не наближається до цвіркуна (уперся в скло чи колоду) — цвіркун відстрибує, шукаємо іншого
		var dd := Vector2(c.position.x - gecko.position.x, c.position.z - gecko.position.z).length()
		if c != _prey:
			_prey = c
			_prey_best = dd
			_prey_t = 0.0
		elif dd < _prey_best - 0.01:
			_prey_best = dd
			_prey_t = 0.0
		else:
			_prey_t += delta
			if _prey_t > 2.0:
				_scare(c)
				_prey = null
				_speed = 0.0
				return
		_target = c.position
		_speed = 0.34
		return
	if _speed > 0.0:
		return
	_pause -= delta
	if _pause > 0.0:
		if anim:
			anim.look = sin(_t * 0.5) * 0.35
		return
	var r := randf()
	if r < 0.3 and temp < Game.GECKO_MAX:
		_go(BASK + Vector3(randf_range(-0.04, 0.04), 0, randf_range(-0.03, 0.03)), 0.14)
		_pause = randf_range(5.0, 9.0)   # гріється довше
	elif r < 0.85:
		var p := Obstacles.push_out(Vector3(randf_range(INNER.position.x, INNER.end.x), 0, randf_range(INNER.position.y, INNER.end.y)), 0.04, 0.0, _obstacles())
		_go(p, 0.12 if randf() < 0.7 else 0.32)
		_pause = randf_range(1.5, 4.0)
	else:
		_pause = randf_range(2.0, 4.0)


func _go(p: Vector3, speed: float) -> void:
	_target = Vector3(clampf(p.x, INNER.position.x, INNER.end.x), 0, clampf(p.z, INNER.position.y, INNER.end.y))
	_speed = speed


func _obstacles() -> Array:
	## Схованку обходить, якщо не лізе в неї (тоді — тільки через вхід).
	var list: Array = STUFF.duplicate()
	if not (_mode in ["to_hide", "hiding", "hide", "exit"]):
		list.append(CAVE)
	elif _mode == "to_hide":
		list.append([CAVE[0], 0.09, 1.0])      # до входу — збоку, не через дах колоди
	return list


func _move(delta: float) -> void:
	var pos := gecko.position
	var goal := Obstacles.steer(pos, _target, 0.05, 0.0, _obstacles())
	var to := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
	var real := Vector3(_target.x - pos.x, 0, _target.z - pos.z)
	var d := real.length()
	var moving := _speed > 0.0 and d > 0.02
	if _mode == "hide" and not moving:
		# сидить у схованці головою до виходу — визирає
		gecko.rotation.y = lerp_angle(gecko.rotation.y, PI * 0.5, 1.0 - exp(-delta * 5.0))
	if moving:
		var want := atan2(to.x, to.z)
		gecko.rotation.y = lerp_angle(gecko.rotation.y, want, 1.0 - exp(-delta * 7.0))
		var fwd := Vector3(sin(gecko.rotation.y), 0, cos(gecko.rotation.y))
		var step := minf(_speed * delta * clampf(fwd.dot(to.normalized()) + 0.2, 0.15, 1.0), d)
		pos += fwd * step
		pos = Obstacles.push_out(pos, 0.05, 0.0, _obstacles())
		pos.x = clampf(pos.x, INNER.position.x, INNER.end.x)
		pos.z = clampf(pos.z, INNER.position.y, INNER.end.y)
		pos = _inside_glass(pos, gecko.rotation.y)
		# уперся в скло і не наближається до цілі — вважаємо, що дійшов
		if d > _last_d - 0.002:
			_stall += delta
		else:
			_stall = 0.0
		_last_d = d
		if _stall > 1.2:
			_stall = 0.0
			_last_d = INF
			_target = Vector3(pos.x, 0, pos.z)
	elif _speed > 0.0:
		_speed = 0.0
		if _mode == "to_hide":
			_target = HIDE_IN
			_speed = 0.06
			_mode = "hiding"
		elif _mode == "hiding":
			_mode = "hide"
	if not moving:
		pos = _inside_glass(pos, gecko.rotation.y)
	# у схованці (і поки залазить/вилазить) — на піску під колодою, інакше — на поверхні
	var inside := absf(pos.x - HIDE_IN.x) < 0.2 and absf(pos.z - HIDE_IN.z) < 0.12 and _mode in ["hide", "hiding", "exit", "to_hide"]
	var y := SAND if inside else floor_y(pos.x, pos.z)
	pos.y = lerpf(pos.y, y, 1.0 - exp(-delta * 14.0))
	gecko.position = pos
	# нахил по схилу (камінь, колода)
	var fwd2 := Vector3(sin(gecko.rotation.y), 0, cos(gecko.rotation.y)) * 0.12
	var slope := floor_y(pos.x + fwd2.x, pos.z + fwd2.z) - floor_y(pos.x - fwd2.x, pos.z - fwd2.z)
	if inside:
		slope = 0.0
	gecko.rotation.x = lerpf(gecko.rotation.x, -atan2(slope, 0.24), 0.15)
	if anim:
		var speed_k := clampf(_speed / 0.3, 0.0, 1.0) if moving else 0.0
		anim.stride = lerpf(anim.stride, speed_k * 0.9 + (0.25 if moving else 0.0), 0.2)
		anim.phase += delta * (6.0 + 14.0 * speed_k) * (1.0 if moving else 0.0)


func _inside_glass(pos: Vector3, yaw: float) -> Vector3:
	## Зсуває гекона так, щоб і голова, і кінчик хвоста були всередині тераріуму.
	var f := Vector3(sin(yaw), 0, cos(yaw))
	for k in [0.2, -0.22]:
		var p: Vector3 = pos + f * k
		if p.x < GLASS.position.x:
			pos.x += GLASS.position.x - p.x
		elif p.x > GLASS.end.x:
			pos.x += GLASS.end.x - p.x
		if p.z < GLASS.position.y:
			pos.z += GLASS.position.y - p.z
		elif p.z > GLASS.end.y:
			pos.z += GLASS.end.y - p.z
	return pos


# ------------------------------------------------------------------ цвіркуни
const LID_Y := 0.92
var _cmat: StandardMaterial3D
var _cmat2: StandardMaterial3D


func _cricket() -> Node3D:
	## Цвіркун: тільце, голівка, вусики, лапки (лапки ворушаться, коли повзе).
	if _cmat == null:
		_cmat = Util.mat(Color(0.32, 0.2, 0.1), 0.55)
		_cmat2 = Util.mat(Color(0.55, 0.38, 0.18), 0.6)
	var c := Node3D.new()
	var body := Util.capsule(0.011, 0.048, _cmat2, Vector3(0, 0.014, -0.004), Vector3(90, 0, 0))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(body)
	c.add_child(Util.sphere(0.009, _cmat, Vector3(0, 0.016, 0.024)))
	for k in [-1, 1]:
		var ant := Util.box(Vector3(0.0012, 0.0012, 0.045), _cmat, Vector3(0.004 * k, 0.026, 0.045), Vector3(-25, 18 * k, 0))
		c.add_child(ant)
	var legs := Node3D.new()
	legs.name = "legs"
	c.add_child(legs)
	for k in [-1, 1]:
		for n in 3:
			var z := 0.012 - n * 0.013
			var lg := Util.box(Vector3(0.022 if n < 2 else 0.03, 0.0018, 0.0018), _cmat, Vector3(0.011 * k, 0.008, z), Vector3(0, 0, -30 * k))
			lg.set_meta("k", k)
			lg.set_meta("n", n)
			legs.add_child(lg)
		# великі задні лапки для стрибків
		c.add_child(Util.box(Vector3(0.0025, 0.0025, 0.034), _cmat2, Vector3(0.011 * k, 0.019, -0.022), Vector3(30, 0, 0)))
	return c


func _blocked(x: float, z: float, pad := 0.03) -> bool:
	## Колода-схованка, мисочка, рослини: цвіркуни туди не лізуть (гекон би їх не дістав).
	for o in STUFF:
		if Vector2(x, z).distance_to(o[0]) < float(o[1]) + pad:
			return true
	# закуток ліворуч за колодою — геконові туди не дістатися
	if x < CAVE[0].x - 0.05:
		return true
	# біля колоди — ширше: щілини між колодою і склом геконові не пролізти
	return Vector2(x, z).distance_to(CAVE[0]) < float(CAVE[1]) + maxf(pad, 0.11)


func _scare(c: Node3D) -> void:
	## Цвіркун відстрибує на вільне місце й деякий час гекон його не чіпає.
	c.set_meta("skip", 3.0)
	c.set_meta("hop", 0.35)
	var away := Vector2(c.position.x - gecko.position.x, c.position.z - gecko.position.z)
	c.rotation.y = atan2(away.x, away.y) + randf_range(-0.6, 0.6)


func add_crickets(n := 10) -> void:
	## Цвіркуни сиплються згори з кришки й розповзаються по піску.
	n = mini(n, 16 - crickets.size())
	for i in n:
		var c := _cricket()
		var x := randf_range(INNER.position.x + 0.08, INNER.end.x - 0.02)
		var z := randf_range(INNER.position.y + 0.01, INNER.end.y - 0.01)
		for _k in 20:
			if not _blocked(x, z, 0.05):
				break
			x = randf_range(INNER.position.x + 0.08, INNER.end.x - 0.02)
			z = randf_range(INNER.position.y + 0.01, INNER.end.y - 0.01)
		c.position = Vector3(x, LID_Y + randf_range(0.0, 0.03), z)
		c.rotation.y = randf() * TAU
		c.set_meta("vy", -randf_range(0.0, 0.3))
		c.set_meta("state", "fall")
		c.set_meta("delay", i * 0.07)
		c.set_meta("turn", randf_range(0.3, 1.2))
		c.set_meta("hop", 0.0)
		c.set_meta("skip", 0.0)
		c.visible = false
		add_child(c)
		crickets.append(c)


func _crickets(delta: float) -> void:
	var head := gecko.position + Vector3(sin(gecko.rotation.y), 0, cos(gecko.rotation.y)) * GECKO_LEN * 0.42
	for c in crickets.duplicate():
		var st: String = c.get_meta("state")
		var dl: float = c.get_meta("delay")
		if dl > 0.0:
			c.set_meta("delay", dl - delta)
			continue
		c.visible = true
		var fy := floor_y(c.position.x, c.position.z)
		if st == "fall":
			var vy: float = float(c.get_meta("vy")) - 3.2 * delta
			c.position.y += vy * delta
			c.rotation.x += delta * 6.0       # кувиркається в польоті
			if c.position.y <= fy:
				c.position.y = fy
				c.rotation.x = 0.0
				if vy < -0.6:
					c.set_meta("vy", -vy * 0.25)   # трішки підскакує
				else:
					c.set_meta("state", "crawl")
					c.set_meta("vy", 0.0)
			else:
				c.set_meta("vy", vy)
			continue
		# повзе: міняє напрям, іноді стрибає; від стінок відвертає
		var turn: float = float(c.get_meta("turn")) - delta
		if turn <= 0.0:
			turn = randf_range(0.4, 1.4)
			c.rotation.y += randf_range(-1.1, 1.1)
			# тікає від гекона, якщо він близько
			var away := Vector2(c.position.x - head.x, c.position.z - head.z)
			if away.length() < 0.12:
				c.rotation.y = atan2(away.x, away.y) + randf_range(-0.5, 0.5)
			if randf() < 0.18:
				c.set_meta("hop", 0.35)
		c.set_meta("turn", turn)
		var hop: float = c.get_meta("hop")
		var sp := 0.045
		if hop > 0.0:
			hop -= delta
			c.set_meta("hop", hop)
			sp = 0.38
		var fwd := Vector3(sin(c.rotation.y), 0, cos(c.rotation.y))
		var np: Vector3 = c.position + fwd * sp * delta
		var sk: float = c.get_meta("skip", 0.0)
		if sk > 0.0:
			c.set_meta("skip", sk - delta)
		if np.x < INNER.position.x + 0.03 or np.x > INNER.end.x or np.z < INNER.position.y or np.z > INNER.end.y \
				or (_blocked(np.x, np.z) and not _blocked(c.position.x, c.position.z)):
			c.rotation.y += PI * 0.7
			np = c.position
		c.position.x = np.x
		c.position.z = np.z
		var lift := sin(clampf(hop / 0.35, 0.0, 1.0) * PI) * 0.035 if hop > 0.0 else 0.0
		c.position.y = floor_y(c.position.x, c.position.z) + lift
		# лапки
		var legs: Node3D = c.get_node("legs")
		var ph: float = _t * 28.0 + float(c.get_instance_id() % 7)
		for lg in legs.get_children():
			var k: int = lg.get_meta("k")
			var n2: int = lg.get_meta("n")
			lg.rotation.y = sin(ph + n2 * 2.1 + (PI if k > 0 else 0.0)) * 0.5
		# гекон спіймав
		var under := Vector2(gecko.position.x - c.position.x, gecko.position.z - c.position.z).length() < 0.07
		if (Vector2(head.x - c.position.x, head.z - c.position.z).length() < 0.045 or under) and absf(head.y - c.position.y) < 0.12:
			crickets.erase(c)
			c.queue_free()
			_lick = 0.8


func nearest_cricket() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for c in crickets:
		if c.get_meta("state") != "crawl" or float(c.get_meta("skip", 0.0)) > 0.0:
			continue
		var d: float = (c as Node3D).position.distance_to(gecko.position)
		if d < bd:
			bd = d
			best = c
	return best


func tongue() -> void:
	## Покормили: у тераріум стрибають цвіркуни, гекон за ними полює.
	if Game.state["gecko"]["temp"] >= Game.GECKO_MIN - 1.0:
		add_crickets(10)
	else:
		_lick = 0.8
