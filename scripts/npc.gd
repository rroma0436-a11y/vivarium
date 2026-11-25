extends Walker
## Мешканець ферми з готовими рухами (модель із Meshy): гуляє між точками,
## коли торкнешся — зупиняється, повертається до тебе й щось каже (або танцює).

var kind := ""
var lines: Array = []
var places: Array = []
var busy := false
var idle_left := 3.0
var _act_left := 0.0
var _line := 0
var main                           # головна сцена (світ, Бім, звук…)
var lives_outside := false         # увечері йде додому за ворота, зранку повертається
var at_home := false
var shopkeeper := false            # продавець на площі: уночі крамниця зачинена — його не видно
const YARD_BOUNDS := Rect2(-20.5, -14.5, 29.0, 19.0)
const OUT_BOUNDS := Rect2(-20.5, -14.5, 29.0, 33.0)


func setup(id: String, height: float, map: Dictionary, loops: Array, talk_lines: Array, where: Array, pick_kind: String) -> void:
	kind = pick_kind
	lines = talk_lines
	places = where
	if not setup_model(id, height, map, loops):
		add_child(Util.capsule(0.2, height * 0.8, Util.mat(Color(0.8, 0.8, 0.85)), Vector3(0, height * 0.45, 0)))
	setup_common(kind, Vector3(0.6, height, 0.6), height + 0.45, 0.35)
	play("idle")


func _process(delta: float) -> void:
	if shopkeeper:
		var h := Game.hour()
		var closed := h >= 20.5 or h < 7.0
		if closed == visible:
			visible = not closed
			if closed:
				stop()
				position = places[0]
		if closed:
			return
	_physics_step(delta)
	if pose:
		pose.life = lerpf(pose.life, 0.0 if moving or busy else 1.0, 1.0 - exp(-delta * 3.0))
	if shopkeeper and not moving and not busy and doing == "":
		# стоїть обличчям до покупців (до площі)
		var c: Vector3 = main.world.outer.VILLAGE
		rotation.y = lerp_angle(rotation.y, atan2(c.x - global_position.x, c.z - global_position.z), 1.0 - exp(-delta * 2.0))
	if _act_left > 0.0:
		_act_left -= delta
		if _act_left <= 0.0:
			busy = false
	if moving:
		play("run" if running else "walk")
		return
	if busy:
		return
	play("idle")
	if doing != "":
		return
	idle_left -= delta
	if idle_left > 0.0 or places.is_empty():
		return
	idle_left = randf_range(5.0, 11.0) if not shopkeeper else randf_range(12.0, 25.0)
	var h := Game.hour()
	if lives_outside and main:
		if not at_home and (h >= 19.3 or h < 6.0):
			go_home()
			return
		if at_home:
			if h >= 7.3 and h < 19.0:
				come_back()
			return
	if Game.is_night():
		return
	if choose_job():
		return
	var p: Vector3 = places[randi() % places.size()]
	walk_to(p + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)), randf() < 0.15)


func go_home() -> void:
	## Через ворота — додому (хата за дорогою); там зникає до ранку.
	var id := begin_job("home")
	var w = main.world
	say("Мені додому! Па-па!", 2.5)
	await go(w.spots["inside_gate"] + Vector3(randf_range(-0.3, 0.3), 0, 0))
	if id != job:
		return
	await w.pass_gate(self, true)
	if id != job:
		return
	bounds = OUT_BOUNDS
	await go(w.spots["kid_home"], false, false)
	if id != job:
		return
	at_home = true
	visible = false
	end_job(id)


func come_back() -> void:
	var id := begin_job("back")
	var w = main.world
	visible = true
	at_home = false
	position = w.spots["kid_home"]
	await go(w.spots["outside_gate"] + Vector3(randf_range(-0.3, 0.3), 0, 0), false, false)
	if id != job:
		return
	await w.pass_gate(self, false)
	if id != job:
		return
	bounds = YARD_BOUNDS
	say("Доброго ранку!", 2.0)
	end_job(id)


func choose_job() -> bool:
	## Нащадки (Тарасик, Гвинтик) обирають тут свої справи. true — справу почато.
	return false


func talk(from: Vector3) -> void:
	if doing != "":
		say(lines[_line % lines.size()] if lines.size() > 0 else "", 2.5)
		_line += 1
		return
	stop()
	face(from)
	busy = true
	if lines.size() > 0:
		say(lines[_line % lines.size()], 3.5)
		_line += 1
	var k := "dance" if anims.get("dance", "") != "" and randf() < 0.4 else "talk"
	if anims.get(k, "") == "":
		k = "idle"
	play(k)
	_act_left = clampf(anim_length(k), 2.5, 6.0)


func make_idle_from(src_key: String, at_frac := 0.0, _span := 0.0) -> void:
	## Окремої анімації «стоїть» немає — беремо одну позу з ходьби (момент, коли ноги поруч)
	## і тримаємо її нерухомо; дихання й легкий поворот голови додаємо кодом.
	if ap == null or anims.get(src_key, "") == "":
		return
	var src: Animation = ap.get_animation(anims[src_key])
	# шукаємо кадр, де ступні найближче одна до одної (стоїть рівно)
	var t0 := src.length * at_frac
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0 and pose:
		var sk: Skeleton3D = sks[0]
		var lf: int = pose.find(sk, "LeftFoot")
		var rf: int = pose.find(sk, "RightFoot")
		if lf >= 0 and rf >= 0:
			var best := INF
			for i in 24:
				var t := src.length * i / 24.0
				ap.play(anims[src_key])
				ap.seek(t, true)
				var d := sk.get_bone_global_pose(lf).origin.distance_to(sk.get_bone_global_pose(rf).origin)
				if d < best:
					best = d
					t0 = t
	var a := Animation.new()
	a.length = 2.0
	a.loop_mode = Animation.LOOP_LINEAR
	for tr in src.get_track_count():
		var ty := src.track_get_type(tr)
		var v = null
		match ty:
			Animation.TYPE_POSITION_3D:
				v = src.position_track_interpolate(tr, t0)
			Animation.TYPE_ROTATION_3D:
				v = src.rotation_track_interpolate(tr, t0)
			Animation.TYPE_SCALE_3D:
				v = src.scale_track_interpolate(tr, t0)
		if v == null:
			continue
		var nt := a.add_track(ty)
		a.track_set_path(nt, src.track_get_path(tr))
		a.track_insert_key(nt, 0.0, v)
	var lib := ap.get_animation_library("")
	if lib:
		var nm := name + "_idle"
		lib.add_animation(nm, a)
		anims["idle"] = nm
	ap.play(anims["idle"])
