extends Node3D
class_name Walker

signal arrived
## Спільне для персонажів, що ходять землею: модель з Meshy, анімації, ходьба до точки з поворотом,
## бульбашка з текстом, зона торкання.

var model: Node3D
var ap: AnimationPlayer
var anims := {}                    # наша назва → назва анімації в моделі
var bubble: Label3D
var area: Area3D
var shadow: MeshInstance3D
var walk_speed := 0.8
var run_speed := 2.0
var turn_speed := 6.0
var target := Vector3.ZERO
var moving := false
var running := false
var bounds := Rect2(-20.5, -14.5, 29.0, 19.0)
var current := ""
var _then: Callable
var _bubble_left := 0.0
var _face_to := NAN
var pose                           # пози поверх анімації (сидіти, пити, нести) — для людей
var hand: BoneAttachment3D         # права кисть: сюди «беремо» глечик, відро, кошик
var hand_l: BoneAttachment3D       # ліва кисть
var held: Node3D
var thigh := 0.45                  # довжина стегна (щоб правильно сісти)
var _base_y := 0.0
var avoid := true                  # обходити перешкоди (хату, криницю, стіл, дерева…)
var avoid_now := true              # для останнього кроку справи можна вимкнути (сісти на стілець)
var me_r := 0.25                   # «товщина» персонажа
var _best_d := INF
var _stuck_t := 0.0
var _esc_left := 0.0               # вибирається з закутка (застряг між речами)
var _esc_dir := Vector3.ZERO
var _escapes := 0


func setup_model(id: String, height: float, map: Dictionary, loops: Array) -> bool:
	model = Models.spawn(self, id, height)
	if model == null:
		return false
	ap = Models.anim_player(model)
	for k in map:
		anims[k] = Models.find_anim(ap, map[k])
	var lp: Array = []
	for k in loops:
		lp.append(anims.get(k, ""))
	if ap:
		Models.set_loop(ap, lp)
		ap.playback_default_blend_time = 0.25
	_base_y = model.position.y
	return true


func setup_pose() -> void:
	## Для людей: модифікатор поз і «рука», в яку можна щось узяти.
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	pose = preload("res://scripts/humanoid_pose.gd").new()
	pose.axis_node = self
	pose.setup(sk)
	sk.add_child(pose)
	var hb: int = pose.find(sk, "RightHand")
	if hb >= 0:
		hand = BoneAttachment3D.new()
		hand.bone_name = sk.get_bone_name(hb)
		sk.add_child(hand)
	hb = pose.find(sk, "LeftHand")
	if hb >= 0:
		hand_l = BoneAttachment3D.new()
		hand_l.bone_name = sk.get_bone_name(hb)
		sk.add_child(hand_l)
	var up: int = pose.find(sk, "LeftUpLeg")
	var kn: int = pose.find(sk, "LeftLeg")
	if up >= 0 and kn >= 0:
		var a := (sk.global_transform * sk.get_bone_global_rest(up)).origin
		var b := (sk.global_transform * sk.get_bone_global_rest(kn)).origin
		thigh = a.distance_to(b) / maxf(global_transform.basis.get_scale().x, 0.001)


var _sk_cache: Skeleton3D


func hips_world() -> Vector3:
	## Де зараз стегна (кістка Hips) у світі.
	if _sk_cache == null:
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			return global_position + Vector3(0, 0.9, 0)
		_sk_cache = sks[0]
	var hb: int = pose._b.get("Hips", -1) if pose else -1
	if hb < 0:
		return global_position + Vector3(0, 0.9, 0)
	return _sk_cache.global_transform * _sk_cache.get_bone_global_pose(hb).origin


func place_hips(h: Vector3) -> void:
	## Ставимо персонажа так, щоб стегна опинилися в точці h (сидіти на возі, лізти на трактор…).
	global_position += h - hips_world()


func hold(obj: Node3D, offset := Vector3.ZERO, left := false, rot := Basis()) -> void:
	## Взяти річ у праву (або ліву) руку. Річ не переноситься в кістку (на телефонах це
	## спотворювало її розмір) — вона щокадру стає туди, де кисть, зі своїм справжнім розміром.
	var h := hand_l if left else hand
	if h == null or obj == null:
		return
	drop()
	_take(obj)
	_held_mode = "hand"
	_held_left = left
	_held_off = offset
	_held_rot = rot.orthonormalized()
	_update_held()


func hold_upright(obj: Node3D, below := 0.15, left := false, fwd := 0.04) -> void:
	## Узяти річ рівно (як стоїть на столі): кисть тримає її за шийку/дужку, річ висить під кистю.
	var h := hand_l if left else hand
	if h == null or obj == null:
		return
	drop()
	_take(obj)
	_held_mode = "upright"
	_held_left = left
	_held_below = below
	_held_fwd = fwd
	_update_held()


var _held_mode := ""
var _held_left := false
var _held_off := Vector3.ZERO
var _held_rot := Basis()
var _held_below := 0.0
var _held_fwd := 0.0
var _held_scale := Vector3.ONE
var _held_h := 0.25              # висота речі
var _held_base := 0.0            # від низу речі до її початку координат
var _head_bone := -2


func _take(obj: Node3D) -> void:
	if obj.is_inside_tree():
		_held_scale = obj.global_transform.basis.get_scale()
		if obj.get_parent() != get_parent():
			obj.reparent(get_parent(), true)
	else:
		_held_scale = obj.scale
		get_parent().add_child(obj)
	held = obj
	# розміри речі (для того, щоб пити: край глечика — біля рота)
	var bb := AABB()
	var first := true
	var mis: Array = obj.find_children("*", "MeshInstance3D", true, false)
	if obj is MeshInstance3D:
		mis.append(obj)
	for mi in mis:
		var b: AABB = Models.global_aabb(mi)
		bb = b if first else bb.merge(b)
		first = false
	if not first:
		_held_h = bb.size.y
		_held_base = obj.global_position.y - bb.position.y


func _update_held() -> void:
	if held == null or not is_instance_valid(held):
		held = null
		return
	var h := hand_l if _held_left else hand
	if h == null or not h.is_inside_tree():
		return
	if held.get_parent() != get_parent():
		held.reparent(get_parent(), false)     # пішов у хату чи з хати — річ разом із ним
	var sb := Basis.from_scale(_held_scale)
	if _held_mode == "upright":
		var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
		var t0 := Transform3D(Basis(Vector3.UP, rotation.y) * sb, h.global_position - Vector3(0, _held_below, 0) + f * _held_fwd)
		# рука біля рота — нахиляє глечик: край біля губ, дно — вгору й від обличчя
		# до рота нахиляємо лише невеликі речі й (у Ніки) лише коли справді їсть чи п'є — інакше лопата й льодяник крутилися б
		var to_mouth: bool = _held_h < 0.6 and (not ("item_kind" in self) or (pose != null and float(pose.drink) > 0.01))
		var mouth := _mouth_pos() if to_mouth else Vector3.INF
		var k := 0.0
		if mouth != Vector3.INF:
			k = clampf((0.42 - h.global_position.distance_to(mouth)) / 0.2, 0.0, 1.0)
		if k > 0.001:
			var y := -(f * 0.8 + Vector3.UP * 0.55).normalized()        # від дна до шийки — до рота
			var x := y.cross(f).normalized()
			var z := x.cross(y).normalized()
			var bottom := mouth - y * _held_h * 0.95
			var t1 := Transform3D(Basis(x, y, z) * sb, bottom + y * _held_base)
			held.global_transform = t0.interpolate_with(t1, k * k * (3.0 - 2.0 * k))
		else:
			held.global_transform = t0
	else:
		var hb := h.global_transform.basis.orthonormalized()
		held.global_transform = Transform3D(hb * _held_rot * sb, h.global_position + hb * _held_off)


func _mouth_pos() -> Vector3:
	if hand == null or not (hand.get_parent() is Skeleton3D):
		return Vector3.INF
	var sk: Skeleton3D = hand.get_parent()
	if _head_bone == -2:
		_head_bone = -1
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if n == "Head" or n.ends_with("_Head") or n.ends_with(":Head"):
				_head_bone = i
				break
	if _head_bone < 0:
		return Vector3.INF
	var hp := sk.global_transform * sk.get_bone_global_pose(_head_bone).origin
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	return hp + f * 0.1 + Vector3.UP * 0.02


func drop() -> Node3D:
	var o := held
	held = null
	if o and o.get_parent():
		o.get_parent().remove_child(o)
	return o


# дорога до грибного лісу (збігається з FOREST_ROAD у world_outer.gd) — ходять діда й Ніка
const FOREST_WAY := [Vector3(-24.0, 0, 8.5), Vector3(-24.0, 0, -50.0), Vector3(-29.0, 0, -70.0), Vector3(-30.0, 0, -80.0)]


func take_basket() -> Node3D:
	## Бере в праву руку порожній кошик (для яблук, грибів і ягід). Плоди кладемо через Util.basket_add.
	if hand == null:
		return null
	var b := Util.basket()
	hold_upright(b, 0.2, false, 0.08)
	return b


func drop_basket() -> void:
	## Ставить кошик — він зникає з рук.
	var o := drop()
	if o:
		o.queue_free()


func place_held(where: Node3D, at: Vector3) -> void:
	## Поставити річ, яку тримає, у певне місце світу.
	var o := drop()
	if o == null:
		return
	where.add_child(o)
	o.transform = Transform3D(Basis(), at)


# ---------------- «справи» (послідовності дій): кожна має свій номер; нова справа скасовує стару
var job := 0
var doing := ""


func begin_job(name: String) -> int:
	job += 1
	doing = name
	put_back_held()
	return job


func end_job(id: int) -> void:
	if id == job:
		doing = ""


func cancel_job() -> void:
	job += 1
	doing = ""
	stop()
	put_back_held()


func go(p: Vector3, run := false, use_avoid := true) -> void:
	## Для «справ»: await go(точка). Якщо справу перервали — теж повертається.
	walk_to(p, run, Callable(), use_avoid)
	await arrived


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func put_back_held() -> void:
	## Якщо справу перервали з річчю в руці — річ повертається на своє місце.
	if held == null:
		return
	var o := drop()
	var home: Node = o.get_meta("home_parent", null)
	if home and is_instance_valid(home):
		home.add_child(o)
		o.transform = o.get_meta("home_tr", Transform3D())
	else:
		o.queue_free()


static func remember_home(o: Node3D) -> void:
	o.set_meta("home_parent", o.get_parent())
	o.set_meta("home_tr", o.transform)


func sit_down(on: bool, speed := 1.6) -> void:
	## Плавно сісти/встати (пози кодом; модель опускається на довжину стегна).
	if pose == null:
		return
	var from: float = pose.sit
	var to := 1.0 if on else 0.0
	var t := 0.0
	while t < 1.0:
		t = minf(1.0, t + get_process_delta_time() * speed)
		pose.sit = lerpf(from, to, t)
		await get_tree().process_frame


func setup_common(kind: String, pick_size: Vector3, bubble_h: float, shadow_r: float) -> void:
	area = Util.pick_area(kind, pick_size, Vector3(0, pick_size.y / 2.0, 0))
	add_child(area)
	bubble = Util.bubble(load("res://assets/fonts/DejaVuSans-Bold.ttf"), 44)
	bubble.pixel_size = 0.0035
	bubble.position = Vector3(0, bubble_h, 0)
	add_child(bubble)
	shadow = Util.blob_shadow(shadow_r, 0.28)
	add_child(shadow)


func play(kind: String, speed := 1.0) -> void:
	if ap == null:
		return
	var n: String = anims.get(kind, "")
	if n == "" or not ap.has_animation(n):
		return
	if current == kind and ap.is_playing() and ap.current_animation == n:
		ap.speed_scale = speed
		return
	current = kind
	ap.play(n, 0.25)
	ap.speed_scale = speed


func anim_length(kind: String) -> float:
	var n: String = anims.get(kind, "")
	if ap and n != "" and ap.has_animation(n):
		return ap.get_animation(n).length
	return 1.0


func walk_to(p: Vector3, run := false, then := Callable(), use_avoid := true) -> void:
	p.y = 0.0
	p.x = clampf(p.x, bounds.position.x, bounds.end.x)
	p.z = clampf(p.z, bounds.position.y, bounds.end.y)
	avoid_now = avoid and use_avoid
	if avoid_now:
		p = Obstacles.push_out(p, me_r, 0.0, _obs())
	target = p
	moving = true
	running = run
	_best_d = INF
	_stuck_t = 0.0
	_escapes = 0
	_esc_left = 0.0
	_then = then
	_face_to = NAN


func stop() -> void:
	var was := moving
	moving = false
	_then = Callable()
	if was:
		arrived.emit()


func face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_face_to = atan2(d.x, d.z)


func say(text: String, secs := 3.0) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_left = secs


func _physics_step(delta: float) -> void:
	## Викликати з _process нащадка.
	var gp0 := global_position
	if absf(gp0.z - 102.0) < 9.0 and absf(gp0.x) < 2.2 and gp0.y > -0.05 and gp0.y < 0.7:
		global_position.y = Util.bridge_y(gp0)
	elif Util.on_hill(gp0) and gp0.y > -0.05 and gp0.y < Util.hill_y(gp0) + 0.35:
		global_position.y = Util.hill_y(gp0)
	if held:
		_update_held()
	if pose and model and float(pose.sit) > 0.0:
		model.position.y = _base_y - thigh * float(pose.sit)
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			bubble.visible = false
	if moving and pose and float(pose.sit) > 0.0:
		pose.sit = maxf(0.0, float(pose.sit) - delta * 1.8)     # спершу встає, потім іде
		play("idle")
	elif moving and _esc_left > 0.0:
		# вибираємось із закутка: кілька кроків у вільний бік
		_esc_left -= delta
		var want_e := atan2(_esc_dir.x, _esc_dir.z)
		rotation.y = lerp_angle(rotation.y, want_e, 1.0 - exp(-delta * turn_speed * 1.5))
		position += _esc_dir * (run_speed if running else walk_speed) * delta
		position = Obstacles.push_out(position, me_r, 0.0, _obs())
		position.x = clampf(position.x, bounds.position.x, bounds.end.x)
		position.z = clampf(position.z, bounds.position.y, bounds.end.y)
	elif moving:
		var real := target - position
		real.y = 0.0
		var goal := Obstacles.steer(position, target, me_r, 0.0, _obs()) if avoid_now else target
		var to := goal - position
		to.y = 0.0
		var d := real.length()
		var v := (run_speed if running else walk_speed) * delta
		if to.length() < 0.02:
			to = real
		if d > 0.02:
			var want := atan2(to.x, to.z)
			rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-delta * turn_speed))
		# застряг (ціль недосяжна)? — вважаємо, що дійшов
		if d < _best_d - 0.25:
			_best_d = d
			_stuck_t = 0.0
		else:
			_stuck_t += delta
		if _stuck_t > 1.6 and _escapes < 2 and d > v:
			_escapes += 1
			_stuck_t = 0.0
			_best_d = INF
			_esc_dir = _free_dir(real)
			_esc_left = 1.1
			return
		if d <= v or _stuck_t > 4.0:
			if d <= v:
				position = Vector3(target.x, 0, target.z)
			moving = false
			_on_arrived()
			if _then.is_valid():
				var cb := _then
				_then = Callable()
				cb.call()
			arrived.emit()
		else:
			# іде туди, куди дивиться (плавні повороти, без ковзання боком)
			var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
			var step := fwd * v * clampf(fwd.dot(to.normalized()) * 1.3, 0.25, 1.0)
			position += step
			if avoid_now:
				position = Obstacles.push_out(position, me_r, 0.0, _obs())
	elif not is_nan(_face_to):
		rotation.y = lerp_angle(rotation.y, _face_to, 1.0 - exp(-delta * turn_speed))
		if abs(angle_difference(rotation.y, _face_to)) < 0.02:
			_face_to = NAN


var extra_obs: Array = []        # додаткові перешкоди лише для цього персонажа (напр. дракон для дівчинки)


func _obs() -> Array:
	if extra_obs.is_empty():
		return []
	return Obstacles.items + extra_obs


func _free_dir(to_target: Vector3) -> Vector3:
	## Куди найвільніше відійти (далі від перешкод, по можливості — у бік цілі).
	var best := Vector3(sin(rotation.y + PI), 0, cos(rotation.y + PI))
	var best_s := -INF
	var tt := to_target.normalized() if to_target.length() > 0.01 else Vector3.ZERO
	for i in 12:
		var a := TAU * i / 12.0
		var dir := Vector3(sin(a), 0, cos(a))
		var p := position + dir * 1.3
		var inside := bounds.has_point(Vector2(p.x, p.z))
		var pushed := Obstacles.push_out(p, me_r + 0.15, 0.0, _obs())
		var sc := -pushed.distance_to(p) * 3.0 + dir.dot(tt) * 0.6 + (0.0 if inside else -5.0)
		if sc > best_s:
			best_s = sc
			best = dir
	return best


func _on_arrived() -> void:
	pass
