extends Node3D
## Бик Бодя: пасеться на вигоні біля корівника — повільно ходить, нахиляє голову й щипає траву,
## мукає. Торкнешся — підстрибує. Увечері йде в корівник, зранку виходить.

const PASTURE := Rect2(1.5, -22.0, 12.5, 5.0)
var pasture := PASTURE
var voices := ["Му-у-у!", "Мууу! Привіт!", "Му! Трава смачна!"]
var kind := "bull"
var night_from := 20.0
var speed_k := 1.0
var _inside_p := Vector3.ZERO           # де стоїть у сараї (невидимий)
var door := Vector3(7.0, 0, -21.5)
var model: Node3D
var ap: AnimationPlayer
var bpose
var area: Area3D
var _bubble: Label3D
var _bubble_left := 0.0
var _target := Vector3.ZERO
var _pause := 2.0
var _graze := 0.0
var _busy := 0.0
var mode := "free"          # free, to_shed, inside, to_pasture, hitched, milking
var size_h := 1.55          # висота тварини (для вимені)
var _a := {}
const SPEED := 0.55


func setup(at: Vector3, shed_door: Vector3, id := "bull", h := 1.55, past := PASTURE) -> void:
	door = shed_door
	kind = id
	pasture = past
	size_h = h
	position = at
	_target = at
	model = Models.spawn(self, id, h)
	if model == null:
		return
	ap = Models.anim_player(model)
	if ap:
		for k in ["idle", "walk", "run", "jump", "graze", "neigh", "drink", "trot"]:
			_a[k] = Models.find_anim(ap, [k])
		Models.set_loop(ap, [_a["idle"], _a["walk"], _a["run"], _a["trot"]])
		ap.playback_default_blend_time = 0.3
		ap.play(_a["idle"])
		ap.seek(randf() * 3.0, true)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if id.begins_with("horse"):
		_a["graze"] = ""                     # коні пасуться власним рухом шиї (horse_pose.gd) — морда до самої трави
	if sks.size() > 0 and id.begins_with("horse"):
		bpose = preload("res://scripts/horse_pose.gd").new()
		bpose.axis_node = self
		bpose.setup(sks[0])
		sks[0].add_child(bpose)
	elif sks.size() > 0:
		bpose = preload("res://scripts/bird_pose.gd").new()
		bpose.axis_node = self
		bpose.setup(sks[0])
		sks[0].add_child(bpose)
	area = Util.pick_area("bull", Vector3(1.2, h, h * 1.5), Vector3(0, h * 0.5, 0))
	add_child(area)
	add_child(Util.blob_shadow(0.6, 1.1))
	_bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 44)
	_bubble.pixel_size = 0.004
	_bubble.position = Vector3(0, h + 0.5, 0)
	add_child(_bubble)


func say(t: String, secs := 2.0) -> void:
	_bubble.text = t
	_bubble.visible = true
	_bubble_left = secs


func _play(k: String, sp := 1.0) -> void:
	if ap == null or _a.get(k, "") == "":
		return
	if ap.current_animation != _a[k]:
		ap.play(_a[k])
	ap.speed_scale = sp


func poke() -> void:
	## Торкнулися — мукає й підстрибує на місці.
	if mode == "inside" or mode == "hitched":
		return
	if mode == "milking":
		say("Му-у… Мене доять!", 2.0)          # стоїть смирно, не стрибає
		return
	say(voices[randi() % voices.size()], 2.0)
	if _a.get("jump", "") != "":
		_busy = minf(ap.get_animation(_a["jump"]).length, 2.0)
		_target = position
		ap.play(_a["jump"])
		ap.speed_scale = 1.0
	elif _a.get("neigh", "") != "":
		_neigh()


func _neigh() -> void:
	## Кінь для масовки: іржить на місці.
	_busy = ap.get_animation(_a["neigh"]).length
	_target = position
	ap.play(_a["neigh"])
	ap.speed_scale = 1.0


func _process(delta: float) -> void:
	if model == null:
		return
	if _rein_mi and visible:
		_reins_draw()
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.visible = false
	if mode == "hitched":
		return                             # запряжений: рухом керує віз (cart.gd)
	if mode == "parked":
		return                             # Ніка злізла й лишила тут — стоїть, чекає її
	if mode == "milking":
		_milk_step(delta)                  # бабуся доїть: стоїть на місці, ремигає
		return
	var h := Game.hour()
	var night := h >= night_from or h < 6.3
	if mode == "inside":
		if night:
			kept_in = false
		if not night and not kept_in and (not keeper_only or Game.hour() >= 10.0):
			mode = "free"
			visible = true
			position = door
			_target = door + Vector3(randf_range(-2, 2), 0, 2.5)
			say("Му-у! Доброго ранку!", 2.5)
		return
	if night and (mode == "free" or mode == "to_pasture"):
		send_home()
	if _busy > 0.0:
		_busy -= delta
		return
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	if d > 0.08:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 2.5))
		var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
		var sp := SPEED * speed_k * clampf(fwd.dot(to / d) + 0.3, 0.2, 1.0)
		position += fwd * minf(sp * delta, d)
		if speed_k > 1.5 and _a.get("run", "") != "":
			_play("run", 0.9)
		else:
			_play("walk", 0.9 * clampf(speed_k, 1.0, 1.6))
		if bpose:
			bpose.peck = lerpf(bpose.peck, 0.0, 0.1)
		return
	if mode == "to_shed":
		if _path.size() > 0:
			_target = _path.pop_front()
			return
		mode = "inside"
		visible = false
		speed_k = 1.0
		return
	if mode == "to_pasture":
		mode = "free"
		speed_k = 1.0
	if _graze > 0.0 and _a.get("graze", "") != "":
		_graze -= delta                       # є своя анімація пасіння (кінь для масовки)
		_play("graze")
		return
	_play("idle")
	if _graze > 0.0:
		_graze -= delta
		if bpose:
			# голова до трави, жує
			bpose.peck = lerpf(bpose.peck, 0.85 + (0.0 if kind.begins_with("horse") else sin(_graze * 5.0) * 0.08), 1.0 - exp(-delta * 1.4))
		return
	if bpose:
		bpose.peck = lerpf(bpose.peck, 0.0, 1.0 - exp(-delta * 2.0))
	_pause -= delta
	if _pause > 0.0:
		return
	_pause = randf_range(2.0, 6.0)
	var r := randf()
	if r < 0.45:
		_graze = randf_range(4.0, 9.0)
	elif r < 0.85:
		_target = Vector3(randf_range(pasture.position.x, pasture.end.x), 0, randf_range(pasture.position.y, pasture.end.y))
	elif r < 0.95:
		say(voices[randi() % voices.size()], 2.0)
		if _a.get("neigh", "") != "":
			_neigh()



var keeper_only := false                # зранку виходить лише коли конюх/пастух випустить (або по 10-й годині)
var kept_in := false                    # Тарасик загнав у сарай — до ранку не виходить
var _path: Array = []


func send_home(fast := false) -> void:
	## Іти в сарай (корівник/стайню): спершу до дверей ззовні, потім усередину.
	if mode == "inside" or mode == "milking":
		return
	mode = "to_shed"
	_graze = 0.0
	_busy = 0.0
	speed_k = 2.0 if fast else 1.0
	_path = [door + door_in]
	_target = door


var door_in := Vector3.ZERO             # куди «заходить» за двері (напрям усередину)


# ------------------------------------------------------------------ запряжений у віз (cart.gd)
# ------------------------------------------------------------------ упряж (harness.glb): хомут із дугою, вуздечка, віжки
const HARNESS_K := 0.92                                  # упряж робили на трохи більшого коня
const HARNESS_COLLAR := Vector3(0.0, 1.35, 0.70)         # центр хомута в моделі упряжі (уже повернутій: y — вгору, z — вперед)
var harness: Array = []                                  # усі шматки упряжі (показуємо, коли запряжений)
var harness_shift := Vector3(0, -0.16, -0.08)              # підгонка хомута на шиї (м)


func add_harness() -> void:
	## Одягаємо упряж: вуздечка їде з головою, хомут — із шиєю, решта — з тулубом. Оглоблі в упряжі
	## не беремо — у воза свої.
	if not Models.exists("harness") or model == null or not harness.is_empty():
		return
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var src: Node3D = load(Models.DIR % "harness").instantiate()
	# модель упряжі лежить «на боці» (вісь висоти — −z): повертаємо на 90° навколо x
	var rot := Basis(Vector3.RIGHT, PI / 2.0)
	var neck0 := _bone_rest(sk, "neck0")
	var neck1 := _bone_rest(sk, "neck1")
	var want := neck0.lerp(neck1, 0.45) + Vector3(0, 0.1, 0) + harness_shift
	var H := Transform3D(rot.scaled(Vector3.ONE * HARNESS_K), Vector3.ZERO)
	H.origin = want - H.basis * (rot.inverse() * HARNESS_COLLAR)
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.begins_with("Shafts"):
			continue
		var bone := ""
		if nm.begins_with("Bridle"):
			bone = "head0"
		elif nm.begins_with("Collar"):
			bone = "neck0"
		var part := MeshInstance3D.new()
		part.mesh = (mi as MeshInstance3D).mesh
		for si in (mi as MeshInstance3D).get_surface_override_material_count():
			part.set_surface_override_material(si, (mi as MeshInstance3D).get_surface_override_material(si))
		var local := H * (src.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform if src.is_inside_tree() else _rel(src, mi))
		var bi := sk.find_bone(bone) if bone != "" else -1
		if bi < 0:
			for i in sk.get_bone_count():
				if sk.get_bone_name(i).ends_with(bone) and bone != "":
					bi = i
		if bi >= 0:
			var ba := BoneAttachment3D.new()
			ba.bone_idx = bi
			sk.add_child(ba)
			var B := global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_rest(bi)
			part.transform = B.affine_inverse() * local
			ba.add_child(part)
		else:
			part.transform = local
			add_child(part)
		part.visible = mode == "hitched"
		harness.append(part)
	src.free()


func _rel(root: Node3D, n: Node3D) -> Transform3D:
	## Перетворення вузла відносно кореня (сцена ще не в дереві).
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _bone_rest(sk: Skeleton3D, nm: String) -> Vector3:
	var bi := sk.find_bone(nm)
	if bi < 0:
		return Vector3(0, 1.2, 0.6)
	return to_local(sk.global_transform * sk.get_bone_global_rest(bi).origin)


func show_harness(on: bool) -> void:
	if no_harness:
		return
	if on and harness.is_empty():
		add_harness()
	for p in harness:
		(p as Node3D).visible = on


func hitch_begin() -> void:
	## Кінь стає в оглобли: власні справи (пастися, у стайню) припиняються.
	if mode == "inside":
		visible = true
		position = door
	mode = "hitched"
	show_harness(true)
	_busy = 0.0
	_graze = 0.0
	_path = []
	speed_k = 1.0
	kept_in = false
	if bpose:
		bpose.peck = 0.0


func hitch_release() -> void:
	## Відпряжений: знову сам собою (увечері піде в стайню).
	mode = "free"
	show_harness(false)
	_target = position
	_pause = 2.0
	say("Дякую! І-го-го!", 2.5)


func park() -> void:
	## Ніка злізла: кінь лишається там, де стоїть (не йде сам у стайню), поки вона знову не сяде.
	mode = "parked"
	show_harness(false)
	_busy = 0.0
	_path = []
	hitch_move(rotation.y, 0.0, 0.0)
	say("Пфррр… Почекаю тут!", 2.0)


func hitch_move(heading: float, sp: float, dt: float) -> void:
	## Крок під керуванням: повернутися носом до heading й пройти sp·dt метрів уперед.
	rotation.y = heading
	position += Vector3(sin(heading), 0, cos(heading)) * sp * dt
	if sp > 0.15:
		if sp > 2.4 and _a.get("run", "") != "":
			_play("run", clampf(sp / 3.2, 0.7, 1.3))
		else:
			_play("walk", clampf(sp / 1.35, 0.5, 1.8))
	else:
		_play("idle")


func send_out(fast := false) -> void:
	## Вийти на пасовисько.
	if mode == "milking":
		return
	kept_in = false
	if mode == "inside":
		visible = true
		position = door
	mode = "to_pasture"
	speed_k = 2.0 if fast else 1.0
	_target = Vector3(randf_range(pasture.position.x, pasture.end.x), 0, randf_range(pasture.position.y, pasture.end.y))


# ------------------------------------------------------------------ доїння (бабуся Галя з дійницею)
var _milk_walk := false


func milk_begin() -> void:
	## Бабуся йде доїти: корова зупиняється й чекає. Якщо вона в корівнику — виходить до дверей.
	if mode == "hitched":
		return
	if mode == "inside" or mode == "to_shed":
		visible = true
		position = door if mode == "inside" else position
		_target = door + Vector3(2.2, 0, -3.6)
		_milk_walk = true
	else:
		_target = position
		_milk_walk = false
	mode = "milking"
	_path = []
	_busy = 0.0
	_graze = 0.0
	speed_k = 1.0
	say("Му-у! Чекаю бабусю.", 2.5)


func milk_walking() -> bool:
	## Ще йде на місце доїння.
	return mode == "milking" and _milk_walk


func milk_end() -> void:
	## Подоїли: знову пасеться (а якщо вже вечір — сама піде в корівник).
	if mode != "milking":
		return
	mode = "free"
	_milk_walk = false
	_target = position
	_pause = 3.0
	say("Му-у! Дякую!", 2.0)


func _milk_step(delta: float) -> void:
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	if _milk_walk and d > 0.08:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 2.5))
		var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
		position += fwd * minf(SPEED * clampf(fwd.dot(to / d) + 0.3, 0.2, 1.0) * delta, d)
		_play("walk", 0.9)
		return
	_milk_walk = false
	_play("idle")
	if bpose:
		# стоїть смирно й ремигає — голова трохи опущена
		bpose.peck = lerpf(bpose.peck, 0.35 + sin(Time.get_ticks_msec() * 0.004) * 0.05, 1.0 - exp(-delta * 2.0))


func udder_point() -> Vector3:
	## Де вим'я (у світі): між задніми ногами, трохи ближче до живота.
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var p := global_position - fwd * size_h * 0.42 + Vector3(0, size_h * 0.3, 0)
	if model == null:
		return p
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return p
	var sk: Skeleton3D = sks[0]
	var hl := _bone_world(sk, "leg_hind_left_top0")
	var hr := _bone_world(sk, "leg_hind_right_top0")
	var fl := _bone_world(sk, "leg_front_left_top0")
	var fr := _bone_world(sk, "leg_front_right_top0")
	if hl == Vector3.INF or hr == Vector3.INF or fl == Vector3.INF or fr == Vector3.INF:
		return p
	var q := ((hl + hr) * 0.5).lerp((fl + fr) * 0.5, 0.2)
	# вим'я — посередині між боками, трохи попереду задніх ніг
	return Vector3(q.x, p.y, q.z)


func _bone_world(sk: Skeleton3D, nm: String) -> Vector3:
	var bi := sk.find_bone(nm)
	if bi < 0:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).ends_with(nm):
				bi = i
				break
	if bi < 0:
		return Vector3.INF
	return sk.global_transform * sk.get_bone_global_pose(bi).origin


# ------------------------------------------------------------------ сідло й вуздечка (saddle.glb, bridle.glb з Blender) — їздовий кінь
var no_harness := false                                   # їздовий кінь: хомута з упряжжю не вдягаємо
var back_k := 0.0                                         # висота спини (частка висоти моделі) — для посадки Ніки
var tack: Array = []
var _rein_mi: MeshInstance3D
var _rein_pts: Array = []                                 # кільця вудила (Л, П) і точки біля передньої луки (Л, П)
var _rein_mat: StandardMaterial3D


func add_tack(bk: float) -> void:
	## Сідло їде з тулубом, вуздечка — з головою; повід малюємо щокадру від кілець вудила до передньої луки.
	if model == null or not Models.exists("saddle") or not tack.is_empty():
		return
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	back_k = bk
	no_harness = true
	var box := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		var ab := m.get_aabb()
		for i in 8:
			var p := to_local(m.global_transform * ab.get_endpoint(i))
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	var c := box.get_center()
	var H := box.size.y
	var L := box.size.z
	var kz := clampf((box.size.x * 0.5 + 0.03) / 0.31, 0.65, 1.1)
	# сідло: у моделі вперед — +x, точка спини під сідлом — (0, 1, 0)
	var S := Transform3D(Basis(Vector3.UP, -PI / 2.0) * Basis.from_scale(Vector3(0.95, 0.95, kz)), Vector3.ZERO)
	var back := Vector3(c.x, box.position.y + bk * H - 0.01, c.z - 0.09 * L)
	S.origin = back - S.basis * Vector3(0, 1.0, 0)
	var sa: Array = _attach_glb(sk, "saddle", S, "body", [])
	# вуздечка: у моделі тім'я — (-1.3, 1.4, 0), вісь голови до морди — (0.5, -0.42, 0), лоб — (0.42, 0.5, 0)
	var hp := _bone_rest(sk, "head0")
	var he := _bone_rest(sk, "head_end")
	var hl := (he - hp).length()
	if hl < 0.05 or not Models.exists("bridle"):
		return
	var dh := (he - hp).normalized()
	var uh := Vector3(0, -dh.z, dh.y).normalized()
	if uh.y + uh.z < 0.0:
		uh = -uh
	var db := Vector3(0.5, -0.42, 0).normalized()
	var ub := Vector3(0.42, 0.5, 0).normalized()
	var Bm := (Basis(dh, uh, dh.cross(uh)) * Basis(db, ub, db.cross(ub)).inverse()).scaled(Vector3.ONE * (1.15 * hl / 0.653))
	var T := Transform3D(Bm, Vector3.ZERO)
	T.origin = hp + uh * (0.108 * hl) - dh * (0.03 * hl) - Bm * Vector3(-1.3, 1.4, 0)
	var ba: Array = _attach_glb(sk, "bridle", T, "head0", ["Повід"])
	# повід: кільця вудила → передня лука сідла
	for zz in [-0.083, 0.083]:
		_rein_pts.append(_marker(ba, T * Vector3(-1.007, 0.937, zz)))
	for sx in [1.0, -1.0]:
		_rein_pts.append(_marker(sa, Vector3(back.x + sx * 0.09, back.y + 0.1, back.z + 0.22)))
	_rein_mat = StandardMaterial3D.new()
	_rein_mat.albedo_color = Color(0.1, 0.045, 0.03)
	_rein_mat.roughness = 0.45
	_rein_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rein_mi = MeshInstance3D.new()
	_rein_mi.mesh = ImmediateMesh.new()
	_rein_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rein_mi.extra_cull_margin = 2.0
	add_child(_rein_mi)


func _attach_glb(sk: Skeleton3D, id: String, T: Transform3D, bone: String, skip: Array) -> Array:
	## Шматки моделі id чіпляємо до кістки bone (T — куди ставити модель у системі коня). Повертає [вузол, його система].
	var src: Node3D = load(Models.DIR % id).instantiate()
	var bi := sk.find_bone(bone)
	if bi < 0:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).ends_with(bone):
				bi = i
	var holder: Node3D = self
	var B := Transform3D()
	if bi >= 0:
		var ba := BoneAttachment3D.new()
		ba.bone_idx = bi
		sk.add_child(ba)
		holder = ba
		B = global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_rest(bi)
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		var sk_it := false
		for k in skip:
			if nm.begins_with(String(k)):
				sk_it = true
		if sk_it:
			continue
		var part := MeshInstance3D.new()
		part.mesh = (mi as MeshInstance3D).mesh
		part.transform = B.affine_inverse() * T * _rel(src, mi)
		holder.add_child(part)
		tack.append(part)
	src.free()
	return [holder, B]


func _marker(at: Array, p: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = (at[1] as Transform3D).affine_inverse() * p
	(at[0] as Node3D).add_child(m)
	return m


func _reins_draw() -> void:
	var im := _rein_mi.mesh as ImmediateMesh
	im.clear_surfaces()
	if _rein_pts.size() < 4:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _rein_mat)
	for s in 2:
		var a := to_local((_rein_pts[s] as Node3D).global_position)
		var b := to_local((_rein_pts[s + 2] as Node3D).global_position)
		var mid := (a + b) * 0.5 + Vector3(0, -0.12, 0)
		var prev := a
		for i in range(1, 9):
			var t := i / 8.0
			var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
			var side := (p - prev).cross(Vector3.UP)
			side = side.normalized() * 0.009 if side.length() > 0.0001 else Vector3(0.009, 0, 0)
			im.surface_add_vertex(prev - side)
			im.surface_add_vertex(prev + side)
			im.surface_add_vertex(p + side)
			im.surface_add_vertex(prev - side)
			im.surface_add_vertex(p + side)
			im.surface_add_vertex(p - side)
			prev = p
	im.surface_end()
