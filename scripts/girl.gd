extends "res://scripts/npc.gd"
## Ніка — живе в селі, у хаті на заході площі. Зранку гуляє біля хати й фонтану,
## перед обідом ходить на базар, по обіді — у гості до дідуся Петра (через ворота ферми),
## увечері повертається додому й до ранку її не видно (спить).

var riding := false                    # (сумісність: на літаку не літає)
var _met := false
var _visit_day := -1
var _market_day := -1
var plane: Node3D

const OUT := Rect2(-62.0, -70.0, 110.0, 160.0)
const FAR := Rect2(-62.0, -135.0, 110.0, 225.0)      # з дорогою до грибного лісу
const HOME_YARD := Vector3(-20.2, 0, 47.5)      # подвір'ячко перед хатою в селі
const HOME_GATE := Vector3(-17.6, 0, 47.0)      # хвіртка в тину
const ROAD_IN := Vector3(-5.0, 0, 46.0)          # з хвіртки — на дорогу
const MARKET := [Vector3(-6.6, 0, 52.4), Vector3(6.6, 0, 52.4), Vector3(-8.0, 0, 66.8), Vector3(3.9, 0, 50.6), Vector3(9.4, 0, 64.4), Vector3(-9.2, 0, 59.0)]
# базар за річкою (bazaar.gd): дорога через міст і місця біля ларьків (уздовж проходу, x = 0)
const BAZAAR_WAY := [Vector3(-5.0, 0, 70.0), Vector3(-5.0, 0, 90.0), Vector3(0.0, 0, 96.5), Vector3(0.0, 0, 110.0), Vector3(0.0, 0, 160.0)]
const BAZAAR_SPOTS := [Vector3(-0.9, 0, 191.5), Vector3(0.9, 0, 187.0), Vector3(-0.9, 0, 182.5), Vector3(0.9, 0, 178.0), Vector3(-0.9, 0, 173.5)]
const SQUARE := [Vector3(-4.5, 0, 55.5), Vector3(4.5, 0, 55.0), Vector3(-5.0, 0, 64.5), Vector3(4.0, 0, 65.0)]


func setup_girl(_unused = null) -> void:
	setup("girl", 1.0, {"idle": ["idle_15", "idle"], "walk": ["walking"], "run": ["running"], "skip": ["skip"],
			"talk": ["talk"], "jump": ["happy_jump", "jump"], "sit": ["sit_cross"], "stand": ["sit_to_stand"],
			"pick": ["female_bend_over_pick_up", "pick_up"], "crouch_pick": ["crouch_pick"], "tree_pick": ["stand_pick_fruit"],
			"pocket": ["put_in_pocket"], "wag": ["finger_wag"], "drink": ["stand_and_drink"], "turn": ["idle_turn"],
			"sleep": ["toss_and_turn"], "open_door": ["open_door"]},
		["idle", "walk", "run", "skip", "sit"],
		["Привіт! Я — Ніка. Живу в селі, у білій хатці біля площі!",
		 "Зранку я ходжу на базар — там пахне хлібом і медом!",
		 "А по обіді біжу в гості до дідуся Петра.",
		 "За фермою є аеродром, а в ангарі — жовтий літак! Beep уміє ним керувати.",
		 "У небі світяться золоті насінинки. Збери їх на літаку!"],
		[], "girl")
	bounds = OUT
	extra_obs = Obstacles.outer
	walk_speed = 0.95
	run_speed = 2.2
	_make_idle()
	setup_pose()


func _make_idle() -> void:
	## Якщо окремої анімації «стоїть» у моделі немає — беремо спокійний початок розмови й гойдаємо туди-сюди.
	if ap == null or anims.get("talk", "") == "" or (anims.get("idle", "") != "" and anims["idle"] != anims["talk"]):
		return
	var lib := ap.get_animation_library("")
	var src: Animation = ap.get_animation(anims["talk"])
	var a: Animation = src.duplicate(true)
	a.length = minf(1.1, src.length)
	a.loop_mode = Animation.LOOP_PINGPONG
	if lib:
		lib.add_animation("girl_idle", a)
		anims["idle"] = "girl_idle"


func in_yard() -> bool:
	return position.z < 5.0 and position.x > -21.0 and position.x < 9.0


var on_plane: Node3D = null
const PLANE_SEAT := Vector3(0, 1.32, 0.12)


func board_plane(p: Node3D) -> void:
	## Підбігає до літака й залазить у кабіну.
	cancel_job()
	busy = false
	var side: Vector3 = p.to_global(Vector3(-2.6, 0, 0.4))
	var id := begin_job("plane")
	await go(side, true)
	var from := global_position
	var k := 0.0
	play("sit")
	while k < 1.0:
		k = minf(1.0, k + get_process_delta_time() / 0.9)
		var to: Vector3 = p.to_global(PLANE_SEAT)
		var q := from.lerp(to, k)
		q.y += sin(k * PI) * 0.6
		global_position = q
		rotation.y = lerp_angle(rotation.y, p.rotation.y, k)
		await get_tree().process_frame
	on_plane = p
	p.pilot = self
	p.pilot_seat = PLANE_SEAT
	end_job(id)


func leave_plane(p: Node3D) -> void:
	on_plane = null
	p.pilot = null
	p.pilot_seat = Vector3.ZERO
	var from := global_position
	var to: Vector3 = p.to_global(Vector3(-2.6, 0, 0.4))
	to.y = 0.0
	var k := 0.0
	while k < 1.0:
		k = minf(1.0, k + get_process_delta_time() / 0.8)
		var q := from.lerp(to, k)
		q.y = lerpf(from.y, 0.0, k) + sin(k * PI) * 0.5
		global_position = q
		await get_tree().process_frame
	global_position = to
	rotation = Vector3(0, rotation.y, 0)
	current = ""
	play("idle")
	idle_left = 4.0


# ------------------------------------------------------------------ гравець сам керує Нікою
var solid_skip: Array = []             # крізь кого можна (транспорт, до якого Ніка зараз іде)
var player := false                    # джойстиком (або торканням землі) керує гравець
var _pl_body: CharacterBody3D          # невидима «капсула» — щоб не проходити крізь стіни базару
var _pl_y := 0.0
const PL_WALK := 1.55
const PL_RUN := 3.6
const YARD_R := Rect2(-21.0, -15.0, 30.0, 20.0)


func player_begin() -> void:
	cancel_job()
	busy = false
	moving = false
	_esc_left = 0.0
	player = true
	at_home = false
	visible = true
	bounds = Rect2(-250.0, -250.0, 500.0, 500.0)
	if pose:
		pose.sit = 0.0
	if held:
		drop()
	if _pl_body == null:
		_pl_body = CharacterBody3D.new()
		_pl_body.name = "NikaBody"
		_pl_body.collision_layer = 0
		_pl_body.collision_mask = 1 << 17           # стіни, ларьки, паркани базару (bazaar.gd: WALLS)
		_pl_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		_pl_body.wall_min_slide_angle = 0.0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.2
		cap.height = 1.1
		cs.shape = cap
		cs.position = Vector3(0, 1.1, 0)               # низ капсули на 0.55 м — сходинки, ґанок і поріг не заважають
		_pl_body.add_child(cs)
		get_parent().add_child(_pl_body)
	_pl_body.global_position = Vector3(global_position.x, 0, global_position.z)
	_pl_y = global_position.y
	current = ""
	play("idle")


# ------------------------------------------------------------------ у хаті: сісти, попити, лягти (керує гравець)
var acting := ""                       # sit / drink / lie (поки гравець не рушить джойстиком)
var _act_back := Vector3.ZERO           # куди стати, коли встане
var _act_cup: Node3D


var _sit_on := false                    # сидить чи встає: стегна — на сидінні (а не провалюються в нього)
var _sit_from := Vector3.ZERO
var _sit_at := Vector3.ZERO
var _sit_root_y := 0.0
var _lie := {}                         # як лягає на ліжко (точки ліжка) і _lie_t — де вона в цьому русі
var _lie_t := 0.0
const LIE_SIT := 0.7                   # сідає на край ліжка
const LIE_END := 2.9                   # … закидає ноги на ліжко й лягає на спину, голова — на подушці


var _hips_rest := -1.0


func _hips_up() -> float:
	## Висота стегон стоячи (з пози спокою скелета, щоб не залежало від поточного руху).
	if _hips_rest < 0.0:
		_hips_rest = 0.43
		var sks := model.find_children("*", "Skeleton3D", true, false) if model else []
		var hb: int = pose._b.get("Hips", -1) if pose else -1
		if not sks.is_empty() and hb >= 0:
			var sk: Skeleton3D = sks[0]
			var g: Vector3 = sk.global_transform * sk.get_bone_global_rest(hb).origin
			var y := (global_transform.affine_inverse() * g).y - (model.position.y - _base_y)
			if y > 0.25 and y < 0.7:
				_hips_rest = y
	return _hips_rest


func act_begin(act: String, at: Vector3, face_dir: Vector3, back: Vector3, extra: Dictionary = {}) -> void:
	acting = act
	_act_back = back
	moving = false
	if pose:
		pose.life = 0.0
	match act:
		"sit":
			var h0 := _hips_up()
			_sit_from = global_position
			_sit_at = at
			var seat_y: float = extra.get("seat_y", at.y + h0 - thigh)
			_sit_root_y = maxf(at.y, seat_y + 0.11 - h0 + thigh)
			_sit_on = true
			if face_dir.length() > 0.01:
				rotation.y = atan2(face_dir.x, face_dir.z)
			play("idle")
			sit_down(true, 1.8)
			say(["Посиджу трошки.", "Як тут затишно!", "Ох, і добре!"][randi() % 3], 2.0)
		"lie":
			_lie = extra.duplicate()
			_lie["from"] = global_position
			_lie["from_yaw"] = rotation.y
			_lie["h0"] = _hips_up()
			_lie_t = 0.0
			play("idle")
			say("Трошки полежу… z-z-z", 2.5)
		"drink":
			global_position = at
			_pl_y = at.y
			if face_dir.length() > 0.01:
				rotation.y = atan2(face_dir.x, face_dir.z)
			play("idle")
			if Models.exists("cup"):
				_act_cup = Models.spawn(get_parent(), "cup", 0.11)
			if _act_cup == null:
				_act_cup = Util.cyl(0.045, 0.04, 0.1, Util.mat(Color(0.75, 0.45, 0.25), 0.6))
				get_parent().add_child(_act_cup)
			hold_upright(_act_cup, 0.06, false)
			say("Ммм, смачний узвар!", 2.5)


func _sit_apply() -> void:
	var k: float = pose.sit if pose else 1.0
	var kx := clampf(k * 1.5, 0.0, 1.0)
	kx = kx * kx * (3.0 - 2.0 * kx)
	var xz := _sit_from.lerp(_sit_at, kx)
	global_position = Vector3(xz.x, lerpf(_sit_at.y, _sit_root_y, k), xz.z)


func _lie_apply(T: float) -> void:
	## T: 0 — стоїть біля ліжка, LIE_SIT — сидить на краю, LIE_END — лежить на спині.
	var L := _lie
	var h0: float = L["h0"]
	var top: float = L["top_y"]
	var side: Vector3 = L["side"]
	var out_yaw: float = L["out_yaw"]
	var lie_yaw: float = L["lie_yaw"]
	var root_sit := Vector3(side.x, top + 0.02 - h0 + thigh, side.z)
	var root_lie: Vector3 = L["root"]
	if T <= LIE_SIT:
		var k := clampf(T / LIE_SIT, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var f: Vector3 = L["from"]
		var p := f.lerp(root_sit, e)
		p.y = lerpf(f.y, root_sit.y, e)
		rotation = Vector3(0, lerp_angle(float(L["from_yaw"]), out_yaw, minf(1.0, e * 1.6)), 0)
		if pose:
			pose.sit = e
			pose.ik = {}
			pose.lean = 0.0
		global_position = p
	else:
		# залазить: руки впираються в постіль, сідає глибше, закидає ноги на ліжко й лягає на спину
		# (повертається навколо стегон, а не «злітає» всім тілом)
		var k2 := clampf((T - LIE_SIT) / (LIE_END - LIE_SIT), 0.0, 1.0)
		var ky := clampf(k2 / 0.55, 0.0, 1.0)
		ky = ky * ky * (3.0 - 2.0 * ky)
		var kt := clampf((k2 - 0.3) / 0.7, 0.0, 1.0)
		kt = kt * kt * (3.0 - 2.0 * kt)
		if not L.has("hs"):
			L["hs"] = hips_world()
		var u := Vector3(sin(lie_yaw), 0, cos(lie_yaw))
		var h_lie: Vector3 = root_lie - u * h0
		var hp: Vector3 = (L["hs"] as Vector3).lerp(h_lie, ky)
		hp.y = lerpf((L["hs"] as Vector3).y, h_lie.y, kt) + sin(ky * PI) * 0.05
		rotation = Vector3(-PI / 2.0 * kt, lerp_angle(out_yaw, lie_yaw, ky), 0)
		if pose:
			pose.sit = 1.0 - kt
			pose.lean = -0.15 * sin(kt * PI)
			var hw := 1.0 - kt
			var bk := Vector3(sin(rotation.y), 0, cos(rotation.y))
			var sd := bk.cross(Vector3.UP)
			pose.ik = {"LeftHand": [hp - bk * 0.12 + sd * 0.2 + Vector3(0, top - hp.y + 0.03, 0), hw],
				"RightHand": [hp - bk * 0.12 - sd * 0.2 + Vector3(0, top - hp.y + 0.03, 0), hw]} if hw > 0.02 else {}
			if pose.sit <= 0.0 and model:
				model.position.y = _base_y
		place_hips(hp)
	_pl_y = global_position.y


func act_step(delta: float) -> void:
	_physics_step(delta)
	if acting == "drink" and pose:
		pose.drink = lerpf(pose.drink, 1.0, 1.0 - exp(-delta * 2.5))
	if _sit_on:
		_sit_apply()
	if acting == "lie" and not _lie.is_empty():
		_lie_t = minf(LIE_END, _lie_t + delta)
		_lie_apply(_lie_t)
		if _lie_t >= LIE_END and ap:
			ap.speed_scale = 0.3                 # лежить тихо, ледь дихає


func act_end(instant := false) -> void:
	if acting == "":
		return
	var was := acting
	acting = ""
	if pose:
		pose.drink = 0.0
	if was == "drink":
		var m := drop()
		if m:
			m.queue_free()
		elif _act_cup and is_instance_valid(_act_cup):
			_act_cup.queue_free()
		_act_cup = null
	if was == "sit" and pose:
		_sit_from = _act_back
		if instant:
			pose.sit = 0.0
		else:
			await sit_down(false, 2.2)
		_sit_on = false
	if was == "lie" and not _lie.is_empty():
		if ap:
			ap.speed_scale = 1.0
		_lie["from"] = _act_back
		if not instant:
			var T := _lie_t
			while T > 0.0:
				T = maxf(0.0, T - get_process_delta_time() * 1.25)
				_lie_apply(T)
				await get_tree().process_frame
		rotation = Vector3(0, rotation.y, 0)
		if pose:
			pose.sit = 0.0
			pose.ik = {}
			pose.lean = 0.0
		if model:
			model.position.y = _base_y
		_lie = {}
	_sit_on = false
	global_position = _act_back
	_pl_y = _act_back.y
	if _pl_body:
		_pl_body.global_position = Vector3(_act_back.x, _pl_y, _act_back.z)
	play("idle")


func player_end() -> void:
	if acting != "":
		act_end(true)
	player = false
	var bz0 = main.world.outer.bazaar if main else null
	if bz0 == null or bz0.building_at(global_position) == null:
		global_position.y = Util.hill_y(global_position)
	moving = false
	idle_left = 3.0
	bounds = OUT if not (main and main.world.outer.bazaar and main.world.outer.bazaar.in_area(global_position)) else FAR_ALL
	play("idle")


const FAR_ALL := Rect2(-80.0, -135.0, 150.0, 380.0)


func player_step(mv: Vector3, run: bool, delta: float) -> float:
	## mv — куди йти (довжина 0…1). Повертає, скільки пройшла (для перевірки, чи не застрягла).
	if climbing:
		return 1.0
	_physics_step(delta)
	var amt := clampf(mv.length(), 0.0, 1.0)
	var old := global_position
	var bz = main.world.outer.bazaar if main else null
	if amt > 0.08:
		var dir := mv / mv.length()
		var spd := (PL_RUN if run else PL_WALK) * (amt if not run else 1.0)
		_pl_body.global_position = Vector3(old.x, _pl_y, old.z)
		_pl_body.velocity = dir * spd
		_pl_body.move_and_slide()
		var p := _pl_body.global_position
		var in_room: bool = Game.state.get("location", "yard") == "room"     # у дідовій хаті (стоїть окремо, далеко від світу)
		if in_room:
			p = Util.push_solids(p, 0.17, solid_skip + [self])     # дід, Beep — не крізь них
			global_position = Vector3(p.x, global_position.y, p.z)
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-delta * 12.0))
			play("run" if run else "walk", 1.05 if run else clampf(spd / 1.05, 0.7, 1.7))
			return Vector2(p.x - old.x, p.z - old.z).length()
		# причал на ставку: з берега — на настил, а з настилу у воду не ступає
		var on_pier := Util.on_pier(p) or Util.on_pier(old)
		if on_pier:
			p = Util.pier_clamp(p)
		# у відкритому світі — ті самі перешкоди, що й для всіх (хати, дерева, криниця…)
		if (bz == null or not bz.in_area(p)) and not (on_pier and Util.on_pier(p)):
			p = Obstacles.push_out(p, me_r, 0.0, _obs())
		# річка: перейти можна лише мостом
		var rz: float = main.world.outer.RIVER_Z
		if absf(p.z - rz) < 5.0 and absf(p.x) > 2.0:
			p.z = old.z if absf(old.z - rz) >= 5.0 else p.z
			p.x = clampf(p.x, -2.0, 2.0) if absf(old.z - rz) < 5.0 else p.x
		# тин подвір'я: у двір і з двору — тільки через ворота
		var was_in := YARD_R.has_point(Vector2(old.x, old.z))
		var now_in := YARD_R.has_point(Vector2(p.x, p.z))
		var TY := YARD_R.grow(0.5)
		if (was_in != now_in or (not TY.has_point(Vector2(old.x, old.z)) and TY.has_point(Vector2(p.x, p.z)))) and absf(p.x) > 1.3:
			p = Vector3(old.x, p.y, old.z)       # тин — зовні теж не крізь нього
		# люди, тварини, вози, машини — тверді: обходить, а не проходить крізь них
		var ps := Util.push_solids(p, 0.17, solid_skip + [self])
		if bz == null or bz.building_at(ps) == bz.building_at(p):
			p = ps
		var lim: float = main.world.outer.LIMIT
		p.x = clampf(p.x, -lim, lim)
		p.z = clampf(p.z, -lim, lim)
		global_position = Vector3(p.x, global_position.y, p.z)
		# уперлася в паркан чи тин і далі тисне джойстиком — перелазить
		var mv_now := Vector2(p.x - old.x, p.z - old.z).length()
		if amt > 0.6 and mv_now < spd * delta * 0.3:
			_push_t += delta
			if _push_t > 0.35:
				_push_t = 0.0
				if _try_climb(dir):
					return 1.0
		else:
			_push_t = 0.0
		var want := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-delta * 12.0))
		if run:
			play("run", 1.05)
		else:
			play("walk", clampf(spd / 1.05, 0.7, 1.7))
	else:
		play("idle")
		# хтось підійшов упритул (корова, дідусь) — Ніка трішки відступає, а не стоїть у ньому
		var q := Util.push_solids(global_position, 0.17, solid_skip + [self])
		if q.distance_to(global_position) > 0.001 and (bz == null or bz.building_at(q) == bz.building_at(global_position)):
			global_position = global_position.lerp(q, 1.0 - exp(-delta * 6.0))
	# підлога: ганок, хата, ларьок — трохи вище за землю
	var fy := 0.0
	if bz and bz.in_area(global_position):
		fy = bz.floor_y(global_position, _pl_y)
	fy = maxf(fy, Util.bridge_y(global_position) + 0.04)    # міст, пагорб; дороги й стежки трохи над землею — ноги не вгрузають
	_pl_y = lerpf(_pl_y, fy, 1.0 - exp(-delta * 14.0)) if absf(_pl_y - fy) < 0.6 else fy
	global_position.y = _pl_y
	if pose:
		pose.life = lerpf(pose.life, 0.0 if amt > 0.08 else 1.0, 1.0 - exp(-delta * 3.0))
	var moved := Vector2(global_position.x - old.x, global_position.z - old.z).length()
	return moved


# ------------------------------------------------------------------ перелазить через паркан чи тин
var climbing := false
var _push_t := 0.0
const CLIMB_MAX := 1.45                # вищі стіни — не перелазить


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 << 17)
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(q)


func _try_climb(dir: Vector3) -> bool:
	## Що попереду: низький паркан (стіни базару), тин подвір'я чи паркан-перешкода. Якщо за ним вільно — перелазить.
	if acting != "" or mount != null or climbing or _pl_body == null:
		return false
	dir = Vector3(dir.x, 0, dir.z).normalized()
	var gp := global_position
	var g := _pl_y
	var fd := -1.0                     # відстань до паркану
	var top := 0.0                     # висота верху паркану над землею
	var tin := false
	var low := _ray(Vector3(gp.x, g + 0.45, gp.z), Vector3(gp.x, g + 0.45, gp.z) + dir * 0.9)
	if not low.is_empty():
		if not _ray(Vector3(gp.x, g + CLIMB_MAX + 0.1, gp.z), Vector3(gp.x, g + CLIMB_MAX + 0.1, gp.z) + dir * 1.0).is_empty():
			return false               # стіна хати чи ларька — висока
		var hp: Vector3 = low["position"]
		fd = Vector2(hp.x - gp.x, hp.z - gp.z).length()
		var dn := _ray(hp + dir * 0.04 + Vector3(0, CLIMB_MAX + 0.2, 0), hp + dir * 0.04 + Vector3(0, -0.3, 0))
		top = ((dn["position"] as Vector3).y - g) if not dn.is_empty() else 1.0
		var dn2 := _ray(hp + dir * 0.12 + Vector3(0, CLIMB_MAX + 0.2, 0), hp + dir * 0.12 + Vector3(0, -0.3, 0))
		if not dn2.is_empty():
			top = maxf(top, (dn2["position"] as Vector3).y - g)
	else:
		var T := YARD_R.grow(0.5)
		var ins := T.has_point(Vector2(gp.x, gp.z))
		var s := 0.0
		while s <= 1.2 and fd < 0.0:
			var q := gp + dir * s
			if T.has_point(Vector2(q.x, q.z)) != ins and absf(q.x) > 1.3:
				fd = s
				top = 1.15
				tin = true
			s += 0.05
		if fd < 0.0:
			var list: Array = _obs()
			if list.is_empty():
				list = Obstacles.items
			s = 0.1
			while s <= 1.0 and fd < 0.0:
				var q2 := gp + dir * s
				for it in list:
					var h := float(it[2])
					var r := float(it[1])
					if h < 0.3 or h > CLIMB_MAX or r > 0.36:
						continue
					if Vector2(q2.x, q2.z).distance_to(it[0]) < r + 0.05:
						fd = s
						top = h
						break
				s += 0.05
	if fd < 0.0 or top < 0.3 or top > CLIMB_MAX:
		return false
	var F := gp + dir * fd
	var bz = main.world.outer.bazaar if main else null
	var rz: float = main.world.outer.RIVER_Z if main else 99999.0
	var land := Vector3.INF
	for ex in [0.45, 0.6, 0.8, 1.0]:
		var L: Vector3 = F + dir * ex
		L.y = g
		if absf(L.z - rz) < 5.0 and absf(L.x) > 2.0:
			continue
		if bz and bz.building_at(L) != bz.building_at(gp):
			continue
		if tin and YARD_R.has_point(Vector2(L.x, L.z)) == YARD_R.has_point(Vector2(gp.x, gp.z)):
			continue
		var lst := _obs()
		if Obstacles.push_out(L, me_r, 0.0, lst if not lst.is_empty() else Obstacles.items).distance_to(L) > 0.03:
			continue
		if _pl_body.test_move(Transform3D(Basis(), L), Vector3(0, 0.02, 0)):
			continue
		if Util.push_solids(L, 0.17, solid_skip + [self]).distance_to(L) > 0.03:
			continue
		land = L
		break
	if land == Vector3.INF:
		return false
	_climb(F, dir, top, Vector2(land.x - F.x, land.z - F.z).length(), fd)
	return true


func _cl_feet(z: float) -> Dictionary:
	return {"LeftFoot": [Vector3(0.08, ANK, z), 1.0], "RightFoot": [Vector3(-0.08, ANK, z), 1.0]}


func _climb(F: Vector3, dir: Vector3, H: float, ld: float, fd: float) -> void:
	## Підходить упритул, хапається руками за верх, ставить ногу, підтягується, перекидає ноги й зістрибує.
	climbing = true
	moving = false
	if held and item_kind in LONG_TOOLS:
		put_item()
	var fr := Node3D.new()
	get_parent().add_child(fr)
	fr.global_position = Vector3(F.x, _pl_y, F.z)
	fr.rotation.y = atan2(dir.x, dir.z)
	var hs := _hips_up()
	var a := maxf(fd, 0.28)
	var hl := has_basket() or held != null           # одна рука зайнята
	var k: Array = []
	var k0 := {"t": 0.0, "hips": Vector3(0, hs, -a), "yaw": 0.0, "anim": "idle", "ik": _cl_feet(-a)}
	k.append(k0)
	var k1 := {"t": 0.35, "hips": Vector3(0, hs, -0.28), "yaw": 0.0, "lean": 0.2, "ik": _cl_feet(-0.28)}
	k1["ik"]["LeftHand"] = [Vector3(0.17, H + 0.03, -0.05), 1.0]
	if not hl:
		k1["ik"]["RightHand"] = [Vector3(-0.17, H + 0.03, -0.05), 1.0]
	k.append(k1)
	var k2 := {"t": 0.8, "hips": Vector3(0, hs + H * 0.32, -0.24), "yaw": 0.0, "lean": 0.35,
		"ik": {"LeftFoot": [Vector3(0.08, ANK, -0.28), 1.0], "RightFoot": [Vector3(-0.08, H * 0.5, -0.12), 1.0],
			"LeftHand": [Vector3(0.17, H + 0.02, -0.03), 1.0]}}
	if not hl:
		k2["ik"]["RightHand"] = [Vector3(-0.17, H + 0.02, -0.03), 1.0]
	k.append(k2)
	var k3 := {"t": 1.3, "hips": Vector3(0, H + 0.14, -0.06), "yaw": 0.0, "lean": 0.3,
		"ik": {"LeftFoot": [Vector3(0.1, H * 0.55, -0.15), 1.0], "RightFoot": [Vector3(-0.08, H + 0.03, -0.04), 1.0],
			"LeftHand": [Vector3(0.19, H + 0.02, 0.0), 1.0]}}
	if not hl:
		k3["ik"]["RightHand"] = [Vector3(-0.19, H + 0.02, 0.0), 1.0]
	k.append(k3)
	var k4 := {"t": 1.75, "hips": Vector3(0, H + 0.12, 0.1), "yaw": 0.0, "lean": 0.12,
		"ik": {"LeftFoot": [Vector3(0.1, H * 0.5, 0.16), 1.0], "RightFoot": [Vector3(-0.08, H + 0.02, 0.03), 1.0],
			"LeftHand": [Vector3(0.19, H + 0.02, -0.02), 1.0]}}
	if not hl:
		k4["ik"]["RightHand"] = [Vector3(-0.19, H + 0.02, -0.02), 1.0]
	k.append(k4)
	# на тому боці — розвертається обличчям до паркану, тримається руками за верх і злазить, тоді обертається
	var top_h := func(w: float) -> Dictionary:
		var d := {"LeftHand": [Vector3(-0.17, H + 0.02, 0.02), w]}
		if not hl:
			d["RightHand"] = [Vector3(0.17, H + 0.02, 0.02), w]
		return d
	var k5 := {"t": 2.25, "hips": Vector3(0, H + 0.04, 0.1), "yaw": 1.6, "lean": 0.1,
		"ik": {"LeftFoot": [Vector3(0.1, H * 0.5, -0.15), 1.0], "RightFoot": [Vector3(-0.08, H * 0.5, 0.17), 1.0]}.merged(top_h.call(1.0))}
	k.append(k5)
	k.append({"t": 2.75, "hips": Vector3(0, H * 0.5 + hs * 0.6, 0.24), "yaw": PI, "lean": 0.2,
		"ik": {"LeftFoot": [Vector3(-0.08, H * 0.45, 0.14), 1.0], "RightFoot": [Vector3(0.08, H * 0.3, 0.16), 1.0]}.merged(top_h.call(1.0))})
	k.append({"t": 3.2, "hips": Vector3(0, hs + H * 0.12, 0.3), "yaw": PI, "lean": 0.15,
		"ik": {"LeftFoot": [Vector3(-0.08, H * 0.2, 0.18), 1.0], "RightFoot": [Vector3(0.08, ANK, 0.32), 1.0]}.merged(top_h.call(1.0))})
	k.append({"t": 3.55, "hips": Vector3(0, hs, 0.34), "yaw": PI, "lean": 0.05,
		"ik": {"LeftFoot": [Vector3(-0.08, ANK, 0.34), 1.0], "RightFoot": [Vector3(0.08, ANK, 0.34), 1.0]}.merged(top_h.call(0.0))})
	k.append({"t": 4.0, "hips": Vector3(0, hs, maxf(ld, 0.5)), "yaw": TAU, "lean": 0.0, "anim": "idle", "ik": _cl_feet(maxf(ld, 0.5))})
	k.append({"t": 4.1, "hips": Vector3(0, hs, maxf(ld, 0.5)), "yaw": TAU, "lean": 0.0, "ik": _cl_feet(maxf(ld, 0.5))})
	ld = maxf(ld, 0.5)
	say(["Гоп — і я там!", "Перелізу!", "Тримаюсь міцно!"][randi() % 3], 1.6)
	await _play_keys(fr, k)
	var L: Vector3 = fr.to_global(Vector3(0, 0, ld))
	fr.queue_free()
	if pose:
		pose.ik = {}
		pose.lean = 0.0
	var y := Util.bridge_y(L)
	var bz = main.world.outer.bazaar if main else null
	if bz and bz.in_area(L):
		y = maxf(y, bz.floor_y(L, _pl_y))
	global_position = Vector3(L.x, y, L.z)
	_pl_y = y
	if _pl_body:
		_pl_body.global_position = global_position
	climbing = false
	play("idle")


func _process(delta: float) -> void:
	_basket_step(delta)
	_held_arm_step(delta)
	if player:
		return                                # керує гравець (main.gd → player_step)
	if mounting:
		return                                # саме залазить чи злазить (рух за ключами)
	if on_plane:
		if current != "sit":
			play("sit")
		return
	if not visible:
		# спить удома — зранку виходить
		var hh := Game.hour()
		if hh >= 7.3 and hh < 20.0:
			visible = true
			position = HOME_YARD
			at_home = false
			say("Доброго ранку!", 2.0)
		return
	_physics_step(delta)
	if pose:
		pose.life = lerpf(pose.life, 0.0 if moving or busy else 1.0, 1.0 - exp(-delta * 3.0))
	if moving:
		play("run" if running else "walk", 1.0)
		return
	if doing != "" or busy:
		if busy:
			_act_left -= delta
			if _act_left <= 0.0:
				busy = false
		return
	if current == "sit":
		busy = true
		play("stand")
		_act_left = clampf(anim_length("stand"), 1.0, 4.0)
		return
	play("idle")
	idle_left -= delta
	if idle_left > 0.0:
		return
	idle_left = randf_range(4.0, 9.0)
	_choose()


func _choose() -> void:
	var h := Game.hour()
	var d := int(Game.state["day"])
	if position.z > 95.0:
		from_bazaar()                         # опинилася за річкою — повертається мостом у село
		return
	if h >= 20.0 or h < 7.0:
		go_home_village()
		return
	if in_yard():
		if h >= 15.0 or randf() < 0.12:
			back_to_village()
			return
		_wander_yard()
		return
	if h >= 12.0 and h < 15.0 and _visit_day != d:
		_visit_day = d
		visit_grandpa()
		return
	if _market_day != d and h >= 9.0 and h < 12.0:
		_market_day = d
		market_job()
		return
	var r := randf()
	if r < 0.15:
		busy = true
		play("jump")
		_act_left = minf(anim_length("jump"), 4.0)
	elif r < 0.22 and anims.get("drink", "") != "":
		busy = true
		play("drink")
		_act_left = minf(anim_length("drink"), 8.0)
	elif r < 0.27 and anims.get("pocket", "") != "":
		busy = true
		play("pocket")
		say(["О, яка гарна квіточка!", "Знайшла камінчик!", "Це я сховаю в кишеньку."][randi() % 3], 2.5)
		_act_left = minf(anim_length("pocket"), 8.0)
	elif r < 0.55:
		var q: Vector3 = SQUARE[randi() % SQUARE.size()]
		walk_to(q + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)), randf() < 0.2)
	else:
		walk_to(HOME_YARD + Vector3(randf_range(-1.5, 1.0), 0, randf_range(-2.0, 2.0)))


func _wander_yard() -> void:
	var gp: Node3D = main.grandpa if main else null
	if gp and gp.visible and gp.global_position.z < 4.0 and randf() < 0.6:
		var p: Vector3 = gp.global_position
		var dir := (global_position - p)
		dir.y = 0.0
		if dir.length() < 0.1:
			dir = Vector3(1, 0, 0)
		walk_to(p + dir.normalized() * 1.4)
		if randf() < 0.5:
			say(["Дідусю, а розкажи казку!", "Я принесла пиріжків!", "Дідусю, а що ти робиш?"][randi() % 3], 2.5)
		return
	walk_to(Vector3(randf_range(-10.0, 4.0), 0, randf_range(-4.0, 2.5)))


func market_job() -> void:
	## Зранку — на базар за річку: через міст, уздовж ларьків, купує щось і вертається додому.
	var id := begin_job("market")
	say("Піду на базар за річку!", 2.5)
	bounds = FAR_ALL
	if position.distance_to(HOME_YARD) < 6.0:
		await go(HOME_GATE)
		if id != job:
			return
	await go(ROAD_IN)
	if id != job:
		return
	for wp in BAZAAR_WAY:
		await go(wp)
		if id != job:
			return
	var spots: Array = BAZAAR_SPOTS.duplicate()
	spots.shuffle()
	for k in 2:
		var sp: Vector3 = spots[k]
		await go(sp + Vector3(0, 0, randf_range(-0.4, 0.4)))
		if id != job:
			return
		face(sp + Vector3(-3.0 if sp.x < 0.0 else 3.0, 0, 0))
		say(["Мені хлібину, будь ласка!", "Скільки коштують яблучка?", "Ой, які льодяники!", "Мені кільце ковбаски!"][randi() % 4], 2.5)
		await wait(3.5)
		if id != job:
			return
	say("Усе купила! Тепер додому.", 2.0)
	await _bazaar_to_village(id)
	if id != job:
		return
	await go(HOME_GATE)
	if id != job:
		return
	bounds = OUT
	end_job(id)
	idle_left = 1.0


func from_bazaar() -> void:
	var id := begin_job("from_bazaar")
	bounds = FAR_ALL
	await _bazaar_to_village(id)
	if id != job:
		return
	bounds = OUT
	end_job(id)
	idle_left = 1.0


func _bazaar_to_village(id: int) -> void:
	## З базару — назад мостом через річку до села.
	if position.z > 112.0 and absf(position.x) > 3.0:
		await go(Vector3(0.0, 0, clampf(position.z, 112.0, 200.0)))
		if id != job:
			return
	for k in range(BAZAAR_WAY.size() - 1, -1, -1):
		if (BAZAAR_WAY[k] as Vector3).z > position.z + 1.0:
			continue
		await go(BAZAAR_WAY[k])
		if id != job:
			return
	await go(ROAD_IN)


func visit_grandpa() -> void:
	## Із села — дорогою до ферми, через ворота — на подвір'я.
	var id := begin_job("visit")
	say("Піду до дідуся Петра!", 2.5)
	bounds = OUT
	if position.distance_to(HOME_YARD) < 6.0:
		await go(HOME_GATE)
		if id != job:
			return
	await go(ROAD_IN)
	if id != job:
		return
	await go(Vector3(0.6, 0, 20.0))
	if id != job:
		return
	await go(main.world.spots["outside_gate"] + Vector3(0.4, 0, 0))
	if id != job:
		return
	await main.world.pass_gate(self, false)
	bounds = OUT
	if id != job:
		return
	await go(Vector3(-2.0, 0, 0.5))
	if id != job:
		return
	say("Добридень, дідусю!", 2.5)
	end_job(id)
	idle_left = 2.0


func back_to_village() -> void:
	var id := begin_job("back")
	say("Па-па! Піду додому.", 2.0)
	await go(main.world.spots["inside_gate"] + Vector3(-0.3, 0, 0))
	if id != job:
		return
	await main.world.pass_gate(self, true)
	bounds = OUT
	if id != job:
		return
	await go(Vector3(0.6, 0, 20.0))
	if id != job:
		return
	await go(ROAD_IN)
	if id != job:
		return
	await go(HOME_GATE)
	if id != job:
		return
	end_job(id)
	idle_left = 1.0


func forest_job() -> void:
	## Іде дорогою в грибний ліс із кошиком, збирає гриби й ягоди й повертається додому в село.
	var forest = main.forest if main else null
	if forest == null:
		return
	var id := begin_job("forest")
	say("Піду в ліс по гриби та ягоди!", 2.5)
	bounds = OUT
	if in_yard():
		await go(main.world.spots["inside_gate"] + Vector3(-0.3, 0, 0))
		if id != job:
			return
		await main.world.pass_gate(self, true)
	elif position.distance_to(HOME_YARD) < 6.0:
		await go(HOME_GATE)
		if id != job:
			return
		await go(ROAD_IN)
		if id != job:
			return
		await go(Vector3(0.6, 0, 20.0), true)
		if id != job:
			return
	bounds = FAR
	var basket := take_basket()
	await go(main.world.spots["outside_gate"] + Vector3(0.4, 0, 1.2), true)
	if id != job:
		return
	for wp in FOREST_WAY:
		await go(wp, true)
		if id != job:
			return
	var got := 0
	for it in forest.nearest_goods(FOREST_WAY[FOREST_WAY.size() - 1], 4):
		await go(forest.goods_pos(it) + Vector3(0.5, 0, 0.5))
		if id != job:
			return
		face(forest.goods_pos(it))
		var pk := "crouch_pick" if anims.get("crouch_pick", "") != "" and randf() < 0.5 else "pick"
		if anims.get(pk, "") != "":
			busy = true
			play(pk)
			await wait(minf(anim_length(pk), 4.5))
			busy = false
			play("idle")
		else:
			await wait(1.0)
		if id != job:
			return
		var col: Color = forest.kind_color(it)
		var n: int = forest.take(it)
		got += n
		if n > 0:
			Util.basket_add(basket, col, 0.05)
	say("Повний кошик — %d! Бабуся зрадіє." % got if got > 0 else "Сьогодні тут уже все зібрали…", 3.0)
	if got > 0:
		Game.emit_event("forest")
	await wait(1.2)
	if id != job:
		return
	for k in range(FOREST_WAY.size() - 1, -1, -1):
		await go(FOREST_WAY[k], true)
		if id != job:
			return
	await go(Vector3(0.6, 0, 20.0), true)
	if id != job:
		return
	await go(ROAD_IN, true)
	if id != job:
		return
	bounds = OUT
	await go(HOME_GATE)
	if id != job:
		return
	drop_basket()
	end_job(id)
	idle_left = 1.0


func go_home_village() -> void:
	## Увечері — додому: заходить у хвіртку, підходить до хати й зникає до ранку.
	if in_yard():
		await back_to_village()
	if position.z > 95.0:
		await from_bazaar()
	var id := begin_job("home")
	if position.distance_to(HOME_YARD) > 5.0:
		await go(HOME_GATE)
		if id != job:
			return
	await go(HOME_YARD + Vector3(-1.2, 0, 0))
	if id != job:
		return
	say("На добраніч!", 1.5)
	await wait(1.2)
	if id != job:
		return
	at_home = true
	visible = false
	end_job(id)


func talk(from: Vector3) -> void:
	super.talk(from)


func can_ride() -> bool:
	return false


# ------------------------------------------------------------------ сама відчиняє двері й хвіртки
var _door_t := 9.0
var _door_len := 0.7


func open_door_hand(at: Vector3) -> float:
	## Повертається до дверей і тягне за ручку (рух «відчинити двері» з моделі). Повертає, скільки це триває.
	var to := at - global_position
	to.y = 0.0
	if to.length() > 0.01:
		rotation.y = atan2(to.x, to.z)
	_door_t = 0.0
	var n: String = anims.get("open_door", "")
	if n != "" and ap and ap.has_animation(n):
		current = ""
		play("open_door", 1.25)
		_door_len = clampf(anim_length("open_door") / 1.25, 0.6, 1.3)
	else:
		_door_len = 0.7
	return _door_len


func door_hand_step(delta: float) -> void:
	_door_t += delta
	_physics_step(delta)
	if pose and anims.get("open_door", "") == "":
		pose.carry = sin(clampf(_door_t / _door_len, 0.0, 1.0) * PI)
	if _door_t >= _door_len:
		if pose:
			pose.carry = 0.0
		play("idle")


# ------------------------------------------------------------------ верхи на коні з сідлом і на велосипеді
var mount: Node3D = null              # на кому/чому зараз їде
var mount_kind := ""                  # "horse" / "bike"
var horse_f := {}                     # точки сідла (у системі коня)
var mounting := false
var _ride_t := 0.0
var _keys_abort := false


static func horse_frame(h: Node3D) -> Dictionary:
	## Точки сідла (у системі коня: вперед — +z, лівий бік — +x), з розмірів самої моделі коня.
	var box := AABB()
	var first := true
	var mdl = h.get("model")
	if mdl is Node3D:
		for n in (mdl as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			var ab := m.get_aabb()
			for i in 8:
				var p := h.to_local(m.global_transform * ab.get_endpoint(i))
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	if first or box.size.y < 1.0 or box.size.y > 2.6 or box.size.z < 1.2 or box.size.z > 3.5:
		box = AABB(Vector3(-0.25, 0, -1.02), Vector3(0.5, 1.68, 2.04))      # заміри horse4 у Blender
	var c := box.get_center()
	var H := box.size.y
	var L := box.size.z
	var y0 := box.position.y
	var bk = h.get("back_k")
	if bk != null and float(bk) > 0.0:
		y0 += float(bk) * H + 0.057 - 0.792 * H              # своє сідло (saddle.glb): сидіння на 5–6 см над спиною
	var side := c.x + minf(box.size.x * 0.5, 0.32)
	var seat := Vector3(c.x, y0 + 0.792 * H + 0.09, c.z - 0.11 * L)
	return {
		"seat": seat,
		"hand_l": Vector3(c.x + 0.08, seat.y + 0.03, seat.z + 0.16),          # повід перед сідлом (руки в Ніки короткі)
		"hand_r": Vector3(c.x - 0.08, seat.y + 0.03, seat.z + 0.16),
		"foot_l": Vector3(side + 0.05, y0 + 0.59 * H, c.z - 0.08 * L),
		"foot_r": Vector3(2.0 * c.x - side - 0.05, y0 + 0.59 * H, c.z - 0.08 * L),
		"pommel": Vector3(c.x + 0.04, y0 + 0.85 * H, c.z + 0.01 * L),
		"cantle": Vector3(c.x + 0.05, y0 + 0.82 * H, c.z - 0.23 * L),
		"croup": Vector3(c.x, y0 + 0.85 * H, c.z - 0.3 * L),
		"side": side,
	}


func _kpt(t: Node3D, v) -> Variant:
	if v is Vector3:
		return v
	if v is String:
		var s := String(v)
		if s.begins_with("grip"):
			return t.to_local(t.grip_global(s == "grip_l"))
		if s.begins_with("wheel"):
			return t.to_local(t.grip_global(s == "wheel_l"))
		if s.begins_with("pedal"):
			return t.to_local(t.pedal_global(s == "pedal_l"))
		if s == "door_h" and t.has_method("door_handle_global"):
			return t.to_local(t.door_handle_global())
	return null


func _play_keys(t: Node3D, keys: Array) -> void:
	## Рух за «ключами» (як дідусь лізе на трактор): стегна, поворот, нахил і точки для кистей і ступнів —
	## усе в системі коня чи велосипеда.
	_keys_abort = false
	var T := 0.0
	var total: float = keys[keys.size() - 1]["t"]
	var fired := {}
	while T < total and not _keys_abort:
		T = minf(total, T + get_process_delta_time())
		for ki in keys.size():
			var kk: Dictionary = keys[ki]
			if kk.has("door") and not fired.has(ki) and T >= float(kk["t"]):
				fired[ki] = true                       # тут рука тягне чи штовхає двері
				if t.has_method("open_door"):
					t.open_door(bool(kk["door"]), float(kk.get("door_spd", 1.6)))
		var i := 0
		while i < keys.size() - 2 and T > float(keys[i + 1]["t"]):
			i += 1
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var u := clampf((T - float(a["t"])) / maxf(0.001, float(b["t"]) - float(a["t"])), 0.0, 1.0)
		var sm := u * u * (3.0 - 2.0 * u)
		var an: String = a.get("anim", "")
		if an != "" and current != an:
			play(an, float(a.get("anim_speed", 1.0)))
		var p0: Vector3 = keys[maxi(i - 1, 0)]["hips"]
		var p3: Vector3 = keys[mini(i + 2, keys.size() - 1)]["hips"]
		var hp: Vector3 = (a["hips"] as Vector3).cubic_interpolate(b["hips"], p0, p3, sm)
		rotation.y = t.global_rotation.y + lerp_angle(float(a["yaw"]), float(b["yaw"]), sm)
		if pose:
			pose.lean = lerpf(float(a.get("lean", 0.0)), float(b.get("lean", 0.0)), sm)
			var ik := {}
			var ia: Dictionary = a.get("ik", {})
			var ib: Dictionary = b.get("ik", {})
			for k in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				var ea: Array = ia.get(k, [null, 0.0])
				var eb: Array = ib.get(k, [null, 0.0])
				var pa = _kpt(t, ea[0])
				var pb = _kpt(t, eb[0])
				if pa == null:
					pa = pb
				if pb == null:
					pb = pa
				if pa == null:
					continue
				ik[k] = [t.to_global((pa as Vector3).lerp(pb, sm)), lerpf(float(ea[1]), float(eb[1]), sm)]
			pose.ik = ik
		place_hips(t.to_global(hp))
		await get_tree().process_frame


func _ride_prep(t: Node3D, kind: String) -> void:
	mounting = true
	mount = t
	mount_kind = kind
	busy = false
	moving = false
	acting = ""
	if held:
		drop()
	if pose:
		pose.sit = 0.0
		pose.life = 0.0
		pose.drink = 0.0
		pose.carry = 0.0
	if model:
		model.position = Vector3(0, _base_y, 0)
	current = ""
	play("idle")


func _horse_ik(f: Dictionary) -> Dictionary:
	return {"LeftFoot": [f["foot_l"], 1.0], "RightFoot": [f["foot_r"], 1.0], "LeftHand": [f["hand_l"], 1.0], "RightHand": [f["hand_r"], 1.0]}


func mount_horse(h: Node3D, block: Vector3, top := 0.55) -> void:
	## Сідає на коня: стає біля лівого боку, підіймає руку й береться за луку сідла, другою — за задню луку,
	## присідає, ставить ногу в стремено, підтягується, перекидає праву ногу через круп і сідає.
	## З приступки (top > 0) — спершу стає на сходинки.
	_ride_prep(h, "horse")
	horse_f = horse_frame(h)
	var f := horse_f
	var S: Vector3 = f["seat"]
	var B := h.to_local(block)
	var G := h.to_local(global_position)
	var ank := ANK
	var hs := _hips_up()
	var yi := -PI / 2.0
	var z := S.z
	var sx: float = f["side"]
	var P: Vector3 = f["pommel"]
	var Cn: Vector3 = f["cantle"]
	var X := sx + 0.42                      # де стоїть біля коня
	var y0 := 0.0
	var keys: Array = [{"t": 0.0, "hips": Vector3(G.x, hs, G.z), "yaw": yi,
		"ik": {"LeftFoot": [Vector3(G.x, ank, G.z + 0.08), 1.0], "RightFoot": [Vector3(G.x, ank, G.z - 0.08), 1.0]}}]
	var t := 0.5
	if top > 0.0:
		X = B.x - 0.06
		y0 = top
		keys.append({"t": t, "hips": Vector3(B.x + 0.34, top * 0.51 + hs - 0.05, z), "yaw": yi, "lean": 0.1,
			"ik": {"LeftFoot": [Vector3(B.x + 0.36, ank, z + 0.08), 1.0], "RightFoot": [Vector3(B.x + 0.22, top * 0.51 + ank, z - 0.08), 1.0]}})
		t += 0.5
	var feet := {"LeftFoot": [Vector3(X, y0 + ank, z + 0.08), 1.0], "RightFoot": [Vector3(X, y0 + ank, z - 0.08), 1.0]}
	keys.append({"t": t, "hips": Vector3(X, y0 + hs, z), "yaw": yi, "ik": feet})
	# ліва рука — угору, на луку сідла
	t += 0.55
	keys.append({"t": t, "hips": Vector3(X - 0.04, y0 + hs, z), "yaw": yi, "lean": 0.05,
		"ik": feet.merged({"LeftHand": [P, 1.0]})})
	# права — на задню луку: тримається обома
	t += 0.45
	var grip := feet.merged({"LeftHand": [P, 1.0], "RightHand": [Cn, 1.0]})
	keys.append({"t": t, "hips": Vector3(X - 0.06, y0 + hs, z), "yaw": yi, "lean": 0.1, "ik": grip})
	# присідає, щоб відштовхнутися
	t += 0.45
	keys.append({"t": t, "hips": Vector3(X - 0.04, y0 + hs - 0.12, z), "yaw": yi, "lean": 0.25, "ik": grip})
	# підтягується на руках, ліва нога — у стремені
	t += 0.6
	keys.append({"t": t, "hips": Vector3(sx + 0.14, S.y - 0.06, z), "yaw": yi, "lean": 0.55,
		"ik": {"LeftFoot": [f["foot_l"], 1.0], "RightFoot": [Vector3(sx + 0.12, S.y - 0.55, z - 0.06), 0.7],
			"LeftHand": [P, 1.0], "RightHand": [Cn, 1.0]}})
	# перекидає праву ногу через круп
	t += 0.6
	keys.append({"t": t, "hips": Vector3(S.x + 0.18, S.y + 0.12, z), "yaw": -0.9, "lean": 0.45,
		"ik": {"LeftFoot": [f["foot_l"], 1.0], "RightFoot": [(f["croup"] as Vector3) + Vector3(0, 0.18, 0), 1.0],
			"LeftHand": [P, 1.0], "RightHand": [P - Vector3(0.08, 0, 0), 0.8]}})
	t += 0.6
	keys.append({"t": t, "hips": S + Vector3(0, 0.03, 0), "yaw": 0.0, "lean": 0.2, "ik": _horse_ik(f)})
	t += 0.4
	keys.append({"t": t, "hips": S, "yaw": 0.0, "lean": 0.15, "ik": _horse_ik(f)})
	await _play_keys(h, keys)
	if _keys_abort:
		return
	mounting = false
	say(["Но-о, коником!", "Їдемо!", "Ого, як високо!"][randi() % 3], 2.0)


func dismount_horse() -> void:
	## Злазить будь-де: обома руками за сідло, перекидає праву ногу через круп, стає в ліве стремено
	## й сповзає вздовж боку на землю — руки відпускає, лише коли ноги вже на землі.
	var h := mount
	mounting = true
	var f := horse_f
	var S: Vector3 = f["seat"]
	var z := S.z
	var sx: float = f["side"]
	var P: Vector3 = f["pommel"]
	var Cn: Vector3 = f["cantle"]
	var hs := _hips_up()
	var X := sx + 0.36
	var hold := {"LeftHand": [P, 1.0], "RightHand": [Cn, 1.0]}
	var keys := [
		{"t": 0.0, "hips": S, "yaw": 0.0, "lean": 0.15, "ik": _horse_ik(f)},
		{"t": 0.5, "hips": S + Vector3(0, 0.06, 0), "yaw": 0.0, "lean": 0.45,
			"ik": {"LeftFoot": [f["foot_l"], 1.0], "RightFoot": [f["foot_r"], 1.0], "LeftHand": [P, 1.0], "RightHand": [P - Vector3(0.08, 0, 0), 1.0]}},
		{"t": 1.1, "hips": Vector3(S.x + 0.18, S.y + 0.12, z), "yaw": -0.8, "lean": 0.5,
			"ik": {"LeftFoot": [f["foot_l"], 1.0], "RightFoot": [(f["croup"] as Vector3) + Vector3(0, 0.18, 0), 1.0], "LeftHand": [P, 1.0], "RightHand": [Cn, 0.8]}},
		{"t": 1.7, "hips": Vector3(sx + 0.15, S.y - 0.08, z), "yaw": -PI / 2.0, "lean": 0.5,
			"ik": {"LeftFoot": [f["foot_l"], 1.0], "RightFoot": [Vector3(sx + 0.14, S.y - 0.62, z - 0.08), 0.8]}.merged(hold)},
		{"t": 2.4, "hips": Vector3(X, hs - 0.04, z), "yaw": -PI / 2.0, "lean": 0.15,
			"ik": {"LeftFoot": [Vector3(X, ANK, z + 0.08), 1.0], "RightFoot": [Vector3(X, ANK, z - 0.08), 1.0]}.merged(hold)},
		{"t": 2.9, "hips": Vector3(X + 0.08, hs, z), "yaw": -PI / 2.0, "lean": 0.0,
			"ik": {"LeftFoot": [Vector3(X + 0.08, ANK, z + 0.08), 1.0], "RightFoot": [Vector3(X + 0.08, ANK, z - 0.08), 1.0],
				"LeftHand": [P, 0.0], "RightHand": [Cn, 0.0]}},
	]
	await _play_keys(h, keys)
	if _keys_abort:
		return
	_mount_done()


func _bike_ik() -> Dictionary:
	return {"LeftFoot": ["pedal_l", 1.0], "RightFoot": ["pedal_r", 1.0], "LeftHand": ["grip_l", 1.0], "RightHand": ["grip_r", 1.0]}


func mount_bike(b: Node3D) -> void:
	## Сідає на велосипед: стає зліва, бере кермо, переносить праву ногу через багажник,
	## стає над рамою, сідає на сідло й ставить ноги на педалі.
	_ride_prep(b, "bike")
	var G := b.to_local(global_position)
	var hs := 0.69
	var ank := 0.1
	var hands := {"LeftHand": ["grip_l", 1.0], "RightHand": ["grip_r", 1.0]}
	var keys := [
		{"t": 0.0, "hips": Vector3(G.x, hs, G.z), "yaw": 0.0,
			"ik": {"LeftFoot": [Vector3(G.x + 0.06, ank, G.z), 1.0], "RightFoot": [Vector3(G.x - 0.06, ank, G.z), 1.0]}},
		{"t": 0.35, "hips": Vector3(0.42, hs, -0.05), "yaw": 0.0,
			"ik": {"LeftFoot": [Vector3(0.48, ank, -0.03), 1.0], "RightFoot": [Vector3(0.36, ank, -0.07), 1.0]}},
		{"t": 0.8, "hips": Vector3(0.38, hs - 0.03, -0.07), "yaw": 0.0, "lean": 0.35,
			"ik": {"LeftFoot": [Vector3(0.48, ank, -0.03), 1.0], "RightFoot": [Vector3(0.36, ank, -0.07), 1.0]}.merged(hands)},
		{"t": 1.4, "hips": Vector3(0.22, hs + 0.07, -0.12), "yaw": 0.0, "lean": 0.45,
			"ik": {"LeftFoot": [Vector3(0.46, ank, -0.03), 1.0], "RightFoot": [Vector3(0.08, 0.62, -0.42), 1.0]}.merged(hands)},
		{"t": 1.9, "hips": Vector3(0.0, hs, -0.1), "yaw": 0.0, "lean": 0.4,
			"ik": {"LeftFoot": [Vector3(0.15, ank, -0.06), 1.0], "RightFoot": [Vector3(-0.15, ank, -0.06), 1.0]}.merged(hands)},
		{"t": 2.5, "hips": b.SEAT_HIPS, "yaw": 0.0, "lean": 0.6, "ik": _bike_ik()},
	]
	await _play_keys(b, keys)
	if _keys_abort:
		return
	mounting = false
	say(["Дзінь-дзінь!", "Поїхали!", "Тримаюсь за кермо!"][randi() % 3], 2.0)


func dismount_bike() -> void:
	var b := mount
	mounting = true
	var hs := 0.69
	var ank := 0.1
	var hands := {"LeftHand": ["grip_l", 1.0], "RightHand": ["grip_r", 1.0]}
	var keys := [
		{"t": 0.0, "hips": b.SEAT_HIPS, "yaw": 0.0, "lean": 0.6, "ik": _bike_ik()},
		{"t": 0.5, "hips": Vector3(0.0, hs, -0.1), "yaw": 0.0, "lean": 0.4,
			"ik": {"LeftFoot": [Vector3(0.15, ank, -0.06), 1.0], "RightFoot": [Vector3(-0.15, ank, -0.06), 1.0]}.merged(hands)},
		{"t": 1.1, "hips": Vector3(0.22, hs + 0.07, -0.12), "yaw": 0.0, "lean": 0.45,
			"ik": {"LeftFoot": [Vector3(0.3, ank, -0.03), 1.0], "RightFoot": [Vector3(0.08, 0.62, -0.42), 1.0]}.merged(hands)},
		{"t": 1.7, "hips": Vector3(0.42, hs, -0.05), "yaw": 0.0, "lean": 0.0,
			"ik": {"LeftFoot": [Vector3(0.48, ank, -0.03), 1.0], "RightFoot": [Vector3(0.36, ank, -0.07), 1.0],
				"LeftHand": ["grip_l", 0.0], "RightHand": ["grip_r", 0.0]}},
	]
	await _play_keys(b, keys)
	if _keys_abort:
		return
	_mount_done()


# ------------------------------------------------------------------ кабіна: трактор і комбайн
var cab := {}                         # точки кабіни (у системі машини)


func _cab_ik(v: Node3D, c: Dictionary) -> Dictionary:
	var f: Array = c["feet"]
	return {"LeftHand": ["wheel_l", 1.0], "RightHand": ["wheel_r", 1.0], "LeftFoot": [f[0], 1.0], "RightFoot": [f[1], 1.0]}


func mount_cab(v: Node3D, kind: String) -> void:
	## Залазить у кабіну: стає біля драбинки (приступки), хапається руками, лізе сходинками вгору,
	## переступає поріг, сідає на сидіння, ставить ноги на педалі й бере кермо.
	_ride_prep(v, kind)
	cab = v.cab_points()
	var c := cab
	var G := v.to_local(global_position)
	if c.get("ladder", false):
		await _play_keys(v, _ladder_keys(c, G, true))
		if _keys_abort:
			v.open_door(false)
			return
		mounting = false
		say(["Заводжу мотор!", "Поїхали!", "Я — комбайнерка!"][randi() % 3], 2.0)
		return
	v.open_door(true)
	var C: Vector3 = c["climb"]
	var D: Vector3 = c["sill"]
	var S: Vector3 = c["seat"]
	var hs := _hips_up()                   # справжня висота стегон Ніки — ноги дістають приступки, а не висить у повітрі
	var ank := 0.1
	var yi := PI / 2.0                     # обличчям до машини (драбинка — з правого боку, −x)
	var keys := [
		{"t": 0.0, "hips": Vector3(G.x, hs, G.z), "yaw": yi,
			"ik": {"LeftFoot": [Vector3(G.x, ank, G.z + 0.08), 1.0], "RightFoot": [Vector3(G.x, ank, G.z - 0.08), 1.0]}},
		{"t": 0.45, "hips": Vector3(C.x, hs, C.z), "yaw": yi,
			"ik": {"LeftFoot": [Vector3(C.x, ank, C.z + 0.08), 1.0], "RightFoot": [Vector3(C.x, ank, C.z - 0.08), 1.0]}},
	]
	# як дідусь: спершу хапається руками за крило/поручень, тоді ставить ногу на приступку й підтягується
	var grab: Vector3 = c.get("hold", C + Vector3(0.45, 1.0, 0.0))
	keys.append({"t": 0.95, "hips": Vector3(C.x + 0.05, hs, C.z), "yaw": yi, "lean": 0.15,
		"ik": {"LeftFoot": [Vector3(C.x, ank, C.z + 0.08), 1.0], "RightFoot": [Vector3(C.x, ank, C.z - 0.08), 1.0],
			"LeftHand": [grab + Vector3(0, 0, 0.16), 1.0], "RightHand": [grab + Vector3(0, 0.1, -0.16), 1.0]}})
	var t := 0.95
	var prev_foot := Vector3(C.x, ank, C.z)
	for st in c["steps"]:
		var P: Vector3 = st
		t += 0.6
		var hand: Vector3 = c.get("hold", P + Vector3(0.25, 0.85, 0.0))
		if not c.has("hold"):
			hand = Vector3(P.x + 0.2, P.y + 0.95, P.z)
		keys.append({"t": t, "hips": Vector3(P.x - 0.22, P.y + hs - 0.05, P.z), "yaw": yi, "lean": 0.25,
			"ik": {"LeftFoot": [P + Vector3(0, ank, 0.09), 1.0], "RightFoot": [prev_foot + Vector3(0, 0.15, -0.09), 1.0],
				"LeftHand": [hand + Vector3(0, 0, 0.16), 1.0], "RightHand": [hand + Vector3(0, 0.1, -0.16), 1.0]}})
		prev_foot = P + Vector3(0, ank, 0)
	t += 0.6
	keys.append({"t": t, "hips": Vector3(D.x - 0.05, D.y + hs, D.z), "yaw": yi, "lean": 0.1,
		"ik": {"LeftFoot": [D + Vector3(0.05, ank, 0.08), 1.0], "RightFoot": [D + Vector3(-0.05, ank, -0.08), 1.0]}})
	t += 0.5
	keys.append({"t": t, "hips": Vector3(S.x - 0.1, D.y + hs, S.z + 0.1), "yaw": 0.6,
		"ik": {"LeftFoot": [Vector3(S.x - 0.0, D.y + ank, S.z + 0.15), 1.0], "RightFoot": [Vector3(S.x - 0.2, D.y + ank, S.z + 0.05), 1.0]}})
	t += 0.6
	keys.append({"t": t, "hips": S, "yaw": 0.0, "lean": 0.15, "ik": _cab_ik(v, c)})
	await _play_keys(v, keys)
	if _keys_abort:
		return
	v.open_door(false)
	mounting = false
	say(["Заводжу мотор!", "Поїхали!", "Я — комбайнерка!" if kind == "combine" else "Тр-р-р, поїхали!"][randi() % 3], 2.0)


func dismount_cab() -> void:
	var v := mount
	mounting = true
	var c := cab
	if pose:
		# поки їхала, ноги були в позі «сидить» — вона перекривала IK, і Ніка злазила з зігнутими ногами,
		# не ставлячи їх на сходинки; плавно знімаємо її, щоб спуск був як підйом, тільки навпаки
		create_tween().tween_property(pose, "sit", 0.0, 0.4)
	if c.get("ladder", false):
		await _play_keys(v, _ladder_keys(c, Vector3.ZERO, false))
		v.open_door(false)
		if _keys_abort:
			return
		play("idle")
		_mount_done()
		return
	v.open_door(true)
	var C: Vector3 = c["climb"]
	var D: Vector3 = c["sill"]
	var S: Vector3 = c["seat"]
	var hs := _hips_up()                   # справжня висота стегон Ніки — ноги дістають приступки, а не висить у повітрі
	var ank := 0.1
	var yi := PI / 2.0
	var keys := [
		{"t": 0.0, "hips": S, "yaw": 0.0, "lean": 0.15, "ik": _cab_ik(v, c)},
		{"t": 0.6, "hips": Vector3(S.x - 0.1, D.y + hs, S.z + 0.1), "yaw": -1.2,
			"ik": {"LeftFoot": [Vector3(S.x, D.y + ank, S.z + 0.15), 1.0], "RightFoot": [Vector3(S.x - 0.2, D.y + ank, S.z + 0.05), 1.0]}},
		{"t": 1.1, "hips": Vector3(D.x - 0.05, D.y + hs, D.z), "yaw": yi, "lean": 0.1,
			"ik": {"LeftFoot": [D + Vector3(0.05, ank, 0.08), 1.0], "RightFoot": [D + Vector3(-0.05, ank, -0.08), 1.0]}},
	]
	var t := 1.1
	var steps: Array = (c["steps"] as Array).duplicate()
	steps.reverse()
	for st in steps:
		var P: Vector3 = st
		t += 0.55
		var hand := Vector3(P.x + 0.2, P.y + 0.95, P.z)
		if c.has("hold"):
			hand = c["hold"]
		keys.append({"t": t, "hips": Vector3(P.x - 0.22, P.y + hs - 0.05, P.z), "yaw": yi, "lean": 0.25,
			"ik": {"LeftFoot": [P + Vector3(0, ank, 0.09), 1.0], "RightFoot": [P + Vector3(0, ank, -0.09), 1.0],
				"LeftHand": [hand + Vector3(0, 0, 0.16), 1.0], "RightHand": [hand + Vector3(0, 0.1, -0.16), 1.0]}})
	# стає на землю, ще тримаючись (як дідусь), тоді відпускає й відступає
	var grab: Vector3 = c.get("hold", C + Vector3(0.45, 1.0, 0.0))
	t += 0.6
	keys.append({"t": t, "hips": Vector3(C.x + 0.05, hs, C.z), "yaw": yi, "lean": 0.15,
		"ik": {"LeftFoot": [Vector3(C.x, ank, C.z + 0.08), 1.0], "RightFoot": [Vector3(C.x, ank, C.z - 0.08), 1.0],
			"LeftHand": [grab + Vector3(0, 0, 0.16), 1.0], "RightHand": [grab + Vector3(0, 0.1, -0.16), 1.0]}})
	t += 0.45
	keys.append({"t": t, "hips": Vector3(C.x - 0.15, hs, C.z), "yaw": yi,
		"ik": {"LeftFoot": [Vector3(C.x - 0.15, ank, C.z + 0.08), 1.0], "RightFoot": [Vector3(C.x - 0.15, ank, C.z - 0.08), 1.0],
			"LeftHand": [grab + Vector3(0, 0, 0.16), 0.0], "RightHand": [grab + Vector3(0, 0.1, -0.16), 0.0]}})
	await _play_keys(v, keys)
	v.open_door(false)
	if _keys_abort:
		return
	_mount_done()


const HIPS_UP := 0.41                  # стегна Ніки над ступнями, коли стоїть (коліна трохи зігнуті)
const ANK := 0.075                     # кісточка над підошвою (ступні — на землі, а не в траві)


func _ladder_keys(c: Dictionary, G: Vector3, up: bool) -> Array:
	## Комбайн: підходить до драбинки, лізе по поперечинах (руки — на поручнях, ноги — по черзі),
	## виходить на площадку, іде до дверей, сама відчиняє їх рукою, заходить, зачиняє за собою й сідає.
	## Злазить: відчиняє двері, виходить, зачиняє, іде площадкою до драбинки й спускається.
	var C: Vector3 = c["climb"]
	var lz: float = c["ladder_z"]
	var dy: float = c["deck_y"]
	var dx: float = c["deck_x"]
	var dz: float = c["door_z"]
	var D: Vector3 = c["sill"]
	var S: Vector3 = c["seat"]
	var steps: Array = c["steps"]
	var hs := _hips_up()
	var yi := PI / 2.0                    # обличчям до комбайна (драбинка ліворуч від нього, вісь −x)
	var zs := dz - 0.62                   # тут стоїть, поки відчиняє (стулка відходить уперед)
	var IN := Vector3(D.x + 0.25, D.y, D.z - 0.05)      # у кабіні біля дверей
	var ground := {"LeftFoot": [Vector3(C.x, ANK, lz - 0.07), 1.0], "RightFoot": [Vector3(C.x, ANK, lz + 0.07), 1.0]}
	var deck_ik := func(z: float) -> Dictionary:
		return {"LeftFoot": [Vector3(dx, dy + ANK, z - 0.07), 1.0], "RightFoot": [Vector3(dx, dy + ANK, z + 0.07), 1.0]}
	var in_ik := {"LeftFoot": [IN + Vector3(0, ANK, 0.07), 1.0], "RightFoot": [IN + Vector3(0, ANK, -0.07), 1.0]}
	var hand := func(base: Dictionary, w: float) -> Dictionary:
		var o := base.duplicate()
		o["RightHand"] = ["door_h", w]
		return o
	var rail := func(y: float, left: bool) -> Vector3:
		if y > 2.4:
			return Vector3(-1.42, dy + 0.03, lz + (-0.17 if left else 0.17))      # край площадки
		return Vector3(c.get("rail_dx", 0.0) + (-1.72 + 0.23 * (clampf(y, 0.35, 2.45) - 0.35) / 2.1) - 0.03, y, lz + (-0.17 if left else 0.17))
	# --- по драбинці (знизу вгору)
	var ladder: Array = []
	var prev_l := Vector3(C.x + 0.25, ANK, lz - 0.07)
	var prev_r := Vector3(C.x + 0.25, ANK, lz + 0.07)
	for i in steps.size():
		var P: Vector3 = steps[i]
		var lf := prev_l
		var rf := prev_r
		if i % 2 == 0:
			lf = P + Vector3(0, ANK, -0.07)
			prev_l = lf
		else:
			rf = P + Vector3(0, ANK, 0.07)
			prev_r = rf
		var low := minf(lf.y, rf.y)
		var hy := minf(P.y + 0.62, 2.5)
		ladder.append({"hips": Vector3(P.x - 0.27, low + hs - 0.06, lz), "yaw": yi, "lean": 0.22,
			"ik": {"LeftFoot": [lf, 1.0], "RightFoot": [rf, 1.0],
				"LeftHand": [rail.call(hy, true), 1.0], "RightHand": [rail.call(hy + 0.15, false), 1.0]}})
	var top := {"hips": Vector3(dx, dy + hs, lz), "yaw": yi, "lean": 0.1, "ik": deck_ik.call(lz)}
	var keys: Array = []
	var t := 0.0
	var walk := func(z: float, yaw: float) -> Dictionary:
		return {"hips": Vector3(dx, dy + hs, z), "yaw": yaw, "anim": "walk", "anim_speed": 0.9}
	if up:
		keys.append({"t": t, "hips": Vector3(G.x, hs, G.z), "yaw": yi, "ik": {"LeftFoot": [Vector3(G.x, ANK, G.z - 0.07), 1.0], "RightFoot": [Vector3(G.x, ANK, G.z + 0.07), 1.0]}})
		t += 0.5
		var k1 := {"t": t, "hips": Vector3(C.x, hs, C.z), "yaw": yi, "ik": ground.duplicate()}
		k1["ik"]["LeftHand"] = [rail.call(0.95, true), 1.0]
		k1["ik"]["RightHand"] = [rail.call(1.1, false), 1.0]
		keys.append(k1)
		for k in ladder:
			t += 0.5
			k["t"] = t
			keys.append(k)
		t += 0.7
		top["t"] = t
		keys.append(top)
		t += 0.4
		keys.append({"t": t, "hips": Vector3(dx, dy + hs, lz), "yaw": 0.0, "ik": deck_ik.call(lz)})
		t += 0.15
		keys.append((walk.call(lz + 0.05, 0.0) as Dictionary).merged({"t": t}))
		t += absf(zs - lz) / 0.75
		keys.append((walk.call(zs, 0.0) as Dictionary).merged({"t": t}))
		# двері: бере рукою за ручку, тягне на себе (відступає), відпускає — стулка відходить сама
		t += 0.35
		keys.append({"t": t, "hips": Vector3(dx, dy + hs, zs), "yaw": yi - 0.35, "anim": "idle", "ik": deck_ik.call(zs)})
		t += 0.45
		keys.append({"t": t, "hips": Vector3(dx + 0.04, dy + hs, zs + 0.03), "yaw": yi - 0.35, "lean": 0.15, "ik": hand.call(deck_ik.call(zs), 1.0)})
		t += 0.2
		keys.append({"t": t, "hips": Vector3(dx + 0.04, dy + hs, zs + 0.03), "yaw": yi - 0.35, "lean": 0.15, "door": true, "door_spd": 0.9, "ik": hand.call(deck_ik.call(zs), 1.0)})
		t += 0.5
		keys.append({"t": t, "hips": Vector3(dx - 0.06, dy + hs, zs - 0.08), "yaw": yi - 0.6, "lean": 0.0, "ik": hand.call(deck_ik.call(zs - 0.08), 1.0)})
		t += 0.35
		keys.append({"t": t, "hips": Vector3(dx - 0.06, dy + hs, zs - 0.08), "yaw": yi - 0.6, "ik": hand.call(deck_ik.call(zs - 0.08), 0.0)})
		t += 0.35
		keys.append((walk.call(zs + 0.05, 0.0) as Dictionary).merged({"t": t}))
		t += absf(dz - zs) / 0.75
		keys.append((walk.call(dz, 0.0) as Dictionary).merged({"t": t}))
		t += 0.35
		keys.append({"t": t, "hips": Vector3(dx, dy + hs, dz), "yaw": yi, "anim": "idle", "ik": deck_ik.call(dz)})
		t += 0.55
		keys.append({"t": t, "hips": Vector3(D.x, D.y + hs, D.z), "yaw": yi, "lean": 0.1,
			"ik": {"LeftFoot": [D + Vector3(0, ANK, -0.07), 1.0], "RightFoot": [D + Vector3(0, ANK, 0.07), 1.0]}})
		t += 0.45
		keys.append({"t": t, "hips": IN + Vector3(0, hs, 0), "yaw": yi, "ik": in_ik})
		# у кабіні: повертається до відчинених дверей, бере за ручку й зачиняє за собою
		t += 0.4
		keys.append({"t": t, "hips": IN + Vector3(-0.08, hs, 0.04), "yaw": -1.25, "lean": 0.3, "ik": hand.call(in_ik, 1.0)})
		t += 0.2
		keys.append({"t": t, "hips": IN + Vector3(-0.08, hs, 0.04), "yaw": -1.25, "lean": 0.3, "door": false, "door_spd": 0.9, "ik": hand.call(in_ik, 1.0)})
		t += 0.6
		keys.append({"t": t, "hips": IN + Vector3(-0.02, hs, 0.0), "yaw": -1.9, "lean": 0.2, "ik": hand.call(in_ik, 1.0)})
		t += 0.55
		keys.append({"t": t, "hips": IN + Vector3(0, hs, -0.02), "yaw": -2.4, "lean": 0.1, "ik": hand.call(in_ik, 1.0)})
		t += 0.3
		keys.append({"t": t, "hips": IN + Vector3(0, hs, -0.02), "yaw": -2.4, "ik": hand.call(in_ik, 0.0)})
		t += 0.5
		keys.append({"t": t, "hips": Vector3(S.x - 0.12, D.y + hs, S.z + 0.12), "yaw": 0.5,
			"ik": {"LeftFoot": [Vector3(S.x - 0.05, D.y + ANK, S.z + 0.1), 1.0], "RightFoot": [Vector3(S.x - 0.22, D.y + ANK, S.z + 0.02), 1.0]}})
		t += 0.6
		keys.append({"t": t, "hips": S, "yaw": 0.0, "lean": 0.15, "ik": _cab_ik(mount, c)})
		return keys
	# --- униз: устає, відчиняє двері, виходить, зачиняє їх, іде площадкою до драбинки, спускається
	keys.append({"t": t, "hips": S, "yaw": 0.0, "lean": 0.15, "ik": _cab_ik(mount, c)})
	t += 0.6
	keys.append({"t": t, "hips": Vector3(S.x - 0.12, D.y + hs, S.z + 0.12), "yaw": -1.3,
		"ik": {"LeftFoot": [Vector3(S.x - 0.05, D.y + ANK, S.z + 0.1), 1.0], "RightFoot": [Vector3(S.x - 0.22, D.y + ANK, S.z + 0.02), 1.0]}})
	t += 0.5
	keys.append({"t": t, "hips": IN + Vector3(0, hs, -0.02), "yaw": -2.4, "ik": in_ik})
	t += 0.4
	keys.append({"t": t, "hips": IN + Vector3(-0.04, hs, -0.02), "yaw": -2.4, "lean": 0.15, "ik": hand.call(in_ik, 1.0)})
	t += 0.2
	keys.append({"t": t, "hips": IN + Vector3(-0.04, hs, -0.02), "yaw": -2.4, "lean": 0.15, "door": true, "door_spd": 0.9, "ik": hand.call(in_ik, 1.0)})
	t += 0.5
	keys.append({"t": t, "hips": IN + Vector3(-0.1, hs, 0.04), "yaw": -1.8, "lean": 0.3, "ik": hand.call(in_ik, 1.0)})
	t += 0.3
	keys.append({"t": t, "hips": IN + Vector3(-0.08, hs, 0.04), "yaw": -1.6, "lean": 0.2, "ik": hand.call(in_ik, 0.0)})
	t += 0.5
	keys.append({"t": t, "hips": Vector3(D.x, D.y + hs, D.z), "yaw": -yi,
		"ik": {"LeftFoot": [D + Vector3(0, ANK, 0.07), 1.0], "RightFoot": [D + Vector3(0, ANK, -0.07), 1.0]}})
	t += 0.55
	keys.append({"t": t, "hips": Vector3(dx, dy + hs, dz), "yaw": -yi, "ik": deck_ik.call(dz)})
	t += 0.4
	keys.append({"t": t, "hips": Vector3(dx, dy + hs, dz), "yaw": PI, "ik": deck_ik.call(dz)})
	t += 0.15
	keys.append((walk.call(dz - 0.05, PI) as Dictionary).merged({"t": t}))
	t += absf(dz - zs) / 0.75
	keys.append((walk.call(zs, PI) as Dictionary).merged({"t": t}))
	# озирається на відчинені двері, бере за ручку й зачиняє
	t += 0.45
	keys.append({"t": t, "hips": Vector3(dx, dy + hs, zs), "yaw": -0.5, "anim": "idle", "ik": deck_ik.call(zs)})
	t += 0.4
	keys.append({"t": t, "hips": Vector3(dx - 0.05, dy + hs, zs + 0.04), "yaw": -0.5, "lean": 0.3, "ik": hand.call(deck_ik.call(zs), 1.0)})
	t += 0.2
	keys.append({"t": t, "hips": Vector3(dx - 0.05, dy + hs, zs + 0.04), "yaw": -0.5, "lean": 0.3, "door": false, "door_spd": 0.9, "ik": hand.call(deck_ik.call(zs), 1.0)})
	t += 0.6
	keys.append({"t": t, "hips": Vector3(dx, dy + hs, zs), "yaw": 0.0, "lean": 0.2, "ik": hand.call(deck_ik.call(zs), 1.0)})
	t += 0.5
	keys.append({"t": t, "hips": Vector3(dx + 0.03, dy + hs, zs), "yaw": 0.45, "lean": 0.1, "ik": hand.call(deck_ik.call(zs), 1.0)})
	t += 0.3
	keys.append({"t": t, "hips": Vector3(dx + 0.03, dy + hs, zs), "yaw": 0.45, "ik": hand.call(deck_ik.call(zs), 0.0)})
	t += 0.4
	keys.append({"t": t, "hips": Vector3(dx, dy + hs, zs), "yaw": PI, "ik": deck_ik.call(zs)})
	t += 0.15
	keys.append((walk.call(zs - 0.05, PI) as Dictionary).merged({"t": t}))
	t += absf(zs - lz) / 0.75
	keys.append((walk.call(lz, PI) as Dictionary).merged({"t": t}))
	t += 0.4
	keys.append({"t": t, "hips": Vector3(dx, dy + hs, lz), "yaw": PI, "anim": "idle", "ik": deck_ik.call(lz)})
	t += 0.45
	top["t"] = t
	keys.append(top)
	ladder.reverse()
	for k in ladder:
		t += 0.5
		k["t"] = t
		keys.append(k)
	# як заходила, тільки навпаки: стає на землю, ще тримаючись за поручні, відпускає їх і відходить від драбинки
	t += 0.6
	var kg := {"t": t, "hips": Vector3(C.x, hs, C.z), "yaw": yi, "ik": ground.duplicate()}
	kg["ik"]["LeftHand"] = [rail.call(0.95, true), 1.0]
	kg["ik"]["RightHand"] = [rail.call(1.1, false), 1.0]
	keys.append(kg)
	t += 0.35
	var kr := {"t": t, "hips": Vector3(C.x, hs, C.z), "yaw": yi, "ik": ground.duplicate()}
	kr["ik"]["LeftHand"] = [rail.call(0.95, true), 0.0]
	kr["ik"]["RightHand"] = [rail.call(1.1, false), 0.0]
	keys.append(kr)
	var Gx := C.x - 0.55
	t += 0.45
	keys.append({"t": t, "hips": Vector3(C.x, hs, C.z), "yaw": -yi, "anim": "walk", "anim_speed": 0.9})
	t += 0.6
	keys.append({"t": t, "hips": Vector3(Gx, hs, C.z), "yaw": -yi, "anim": "idle"})
	t += 0.2
	keys.append({"t": t, "hips": Vector3(Gx, hs, C.z), "yaw": -yi})
	return keys


func ride_step(delta: float, v: float) -> void:
	## Щокадру, поки їде: сидить у сідлі, руки на кермі/поводі, ноги на педалях (крутяться разом із ними).
	if mount == null or mounting:
		return
	_physics_step(delta)
	_ride_t += delta
	rotation.y = mount.global_rotation.y
	if mount_kind in ["combine", "tractor"]:
		if pose:
			pose.life = 0.0
			pose.lean = 0.12
			pose.sit = minf(1.0, pose.sit + delta * 2.5)      # сідає плавно, як і встає при злазанні
			var f: Array = cab["feet"]
			pose.ik = {"LeftHand": [mount.grip_global(true), 1.0], "RightHand": [mount.grip_global(false), 1.0],
				"LeftFoot": [mount.to_global(f[0]), 1.0], "RightFoot": [mount.to_global(f[1]), 1.0]}
		place_hips(mount.to_global(cab["seat"]))
	elif mount_kind == "bike":
		if pose:
			pose.life = 0.0
			pose.lean = 0.6
			var bb := mount.global_transform.basis
			pose.ik = {"LeftHand": [mount.grip_global(true) + bb * Vector3(0, 0.02, -0.035), 1.0],
				"RightHand": [mount.grip_global(false) + bb * Vector3(0, 0.02, -0.035), 1.0],
				"LeftFoot": [mount.pedal_global(true) + bb * Vector3(0, 0.06, -0.03), 1.0],
				"RightFoot": [mount.pedal_global(false) + bb * Vector3(0, 0.06, -0.03), 1.0]}
		place_hips(mount.to_global(mount.SEAT_HIPS))
	else:
		var f := horse_f
		var k := clampf(v / 2.0, 0.0, 1.0)
		var bob := absf(sin(_ride_t * (4.5 + v * 1.5))) * 0.045 * k
		if pose:
			pose.life = 0.0
			pose.lean = 0.25 + 0.1 * clampf(v / 5.5, 0.0, 1.0)
			pose.ik = {"LeftFoot": [mount.to_global(f["foot_l"]), 1.0], "RightFoot": [mount.to_global(f["foot_r"]), 1.0],
				"LeftHand": [mount.to_global(f["hand_l"]), 1.0], "RightHand": [mount.to_global(f["hand_r"]), 1.0]}
		place_hips(mount.to_global((f["seat"] as Vector3) + Vector3(0, bob, 0)))


func _mount_done() -> void:
	if pose:
		pose.ik = {}
		pose.lean = 0.0
		pose.sit = 0.0
	if model:
		model.position = Vector3(0, _base_y, 0)     # після сідла модель лишалась опущеною — ноги в землі
	mount = null
	mount_kind = ""
	mounting = false
	var p := global_position
	var y := Util.bridge_y(p)
	global_position = Vector3(p.x, y, p.z)
	rotation = Vector3(0, rotation.y, 0)
	_pl_y = y
	if _pl_body:
		_pl_body.global_position = Vector3(p.x, y, p.z)
	current = ""
	play("idle")


func mount_off_now(at: Vector3) -> void:
	## Негайно на землю поруч (натиснули «Готово» посеред руху).
	_keys_abort = true
	global_position = at
	_mount_done()


# ------------------------------------------------------------------ кошик: несе збоку в опущеній руці
var _bk: Node3D = null
var _bk_sw := 0.0
var _bk_last := Vector3.ZERO
const BK_SCALE := 0.75


func take_basket() -> Node3D:
	## Кошик висить у правій опущеній руці збоку (а не перед обличчям), трохи гойдається в такт крокам.
	if _bk and is_instance_valid(_bk):
		return _bk
	var b := Util.basket()
	get_parent().add_child(b)
	_bk = b
	_bk_last = global_position
	_basket_step(0.0)
	return b


func drop_basket() -> void:
	if _bk and is_instance_valid(_bk):
		_bk.queue_free()
	_bk = null
	if pose and mount == null and pose.ik.has("RightHand"):
		var ik: Dictionary = pose.ik.duplicate()
		ik.erase("RightHand")
		pose.ik = ik


func has_basket() -> bool:
	return _bk != null and is_instance_valid(_bk)


func _held_arm_step(delta: float) -> void:
	## Річ у руці (льодяник, лопата…): рука зігнута й тримає її перед собою, а не розмахує нею.
	if pose == null or not ("carry_l" in pose):
		return
	if _door_t < _door_len and anims.get("open_door", "") == "":
		return
	var want: bool = held != null and is_instance_valid(held) and pose.drink < 0.001 and pose.ride < 0.001 and not climbing
	var r: bool = want and not _held_left and not pose.ik.has("RightHand")
	var l: bool = want and _held_left and not pose.ik.has("LeftHand")
	var k := clampf(delta * 6.0, 0.0, 1.0)
	pose.carry = lerpf(pose.carry, 0.85 if r else 0.0, k)
	pose.carry_l = lerpf(pose.carry_l, 0.85 if l else 0.0, k)
	if pose.carry < 0.002:
		pose.carry = 0.0
	if pose.carry_l < 0.002:
		pose.carry_l = 0.0


func _basket_step(delta: float) -> void:
	if _bk == null:
		return
	if not is_instance_valid(_bk):
		_bk = null
		return
	if _bk.get_parent() != get_parent():
		_bk.reparent(get_parent(), false)       # зайшла в хату чи вийшла — кошик разом із нею
	var free_hands := mount == null and not mounting and acting == ""
	_bk.visible = visible and free_hands
	if not free_hands:
		return
	var v := 0.0
	if delta > 0.0:
		v = Vector2(global_position.x - _bk_last.x, global_position.z - _bk_last.z).length() / delta
	_bk_last = global_position
	_bk_sw += delta * (2.0 + minf(v, 3.0) * 2.4)
	var swing := sin(_bk_sw) * clampf(v * 0.05, 0.0, 0.12)
	var hp := hips_world()
	var right := -global_transform.basis.x.normalized()
	var fwd := global_transform.basis.z.normalized()
	var top := Vector3(global_position.x, hp.y - 0.1, global_position.z) + right * 0.2 + fwd * (0.03 + swing * 0.4)
	var below := (0.15 + 0.16) * BK_SCALE
	var b := (Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, swing)).scaled(Vector3.ONE * BK_SCALE)
	_bk.global_transform = Transform3D(b, top - b.y.normalized() * below)
	if pose:
		var ik: Dictionary = pose.ik.duplicate()
		ik["RightHand"] = [top + Vector3(0, 0.02, 0), 1.0]
		pose.ik = ik


# ------------------------------------------------------------------ речі в руках: хліб, кухоль, яблуко, лопата, граблі, сокира…
const LONG_TOOLS := ["rake", "shovel", "fork", "hoe", "broom"]
var item_kind := ""


func take_item(obj: Node3D, kind := "") -> void:
	## Бере річ: коли та внизу — нахиляється (присідає), на столі чи на полиці — тягнеться рукою.
	if obj == null or not is_instance_valid(obj):
		return
	if held:
		put_item()
	var to := obj.global_position - global_position
	if Vector2(to.x, to.z).length() > 0.05 and acting == "":
		rotation.y = atan2(to.x, to.z)
	var left := has_basket()                     # права рука — з кошиком
	var hk := "LeftHand" if left else "RightHand"
	var low := obj.global_position.y < global_position.y + 0.4
	if low and acting == "":
		var an := "crouch_pick" if anims.get("crouch_pick", "") != "" else "pick"
		if anims.get(an, "") != "":
			play(an)
		await get_tree().create_timer(0.6).timeout
	elif pose:
		var t := 0.0
		while t < 0.5 and is_instance_valid(obj):
			t += get_process_delta_time()
			var ik: Dictionary = pose.ik.duplicate()
			ik[hk] = [obj.global_position + Vector3(0, 0.05, 0), clampf(t / 0.4, 0.0, 1.0)]
			pose.ik = ik
			await get_tree().process_frame
		var ik2: Dictionary = pose.ik.duplicate()
		ik2.erase(hk)
		pose.ik = ik2
	if not is_instance_valid(obj):
		return
	for a in obj.find_children("*", "Area3D", false, false):
		(a as Area3D).input_ray_pickable = false
	item_kind = kind
	if kind in LONG_TOOLS or kind == "axe":
		hold_upright(obj, 0.42 if kind != "axe" else 0.12, left, 0.1)
	else:
		hold_upright(obj, 0.03, left, 0.06)
	if acting == "":
		play("idle")


func put_item() -> Node3D:
	## Кладе те, що в руках, перед собою (довге — на землю плазом).
	var o := drop()
	if o == null:
		item_kind = ""
		return null
	get_parent().add_child(o)
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var b := Basis(Vector3.UP, rotation.y)
	var at := global_position + f * 0.4
	if item_kind in LONG_TOOLS:
		b = b * Basis(Vector3.RIGHT, PI / 2.0)
		at.y += 0.03
	o.global_transform = Transform3D(b.scaled(_held_scale), at)
	for a in o.find_children("*", "Area3D", false, false):
		(a as Area3D).input_ray_pickable = true
	item_kind = ""
	return o


func eat_held() -> void:
	## Їсть чи п'є те, що в руці: підносить до рота кілька разів, і воно зникає.
	if held == null:
		return
	var k := item_kind
	var drink := k in ["cup", "jug", "milk"]
	say((["Ммм, смачний узвар!", "Яке смачне молочко!"] if drink else ["Ням-ням!", "Смакота!", "Ммм, як смачно!"])[randi() % (2 if drink else 3)], 2.2)
	var t := 0.0
	var dur := 2.8
	while t < dur and held != null:
		t += get_process_delta_time()
		if pose:
			var w := clampf(t / 0.4, 0.0, 1.0) * clampf((dur - t) / 0.4, 0.0, 1.0)
			pose.drink = w * (1.0 if drink else 0.85 + 0.15 * sin(t * 9.0))
		await get_tree().process_frame
	if pose:
		pose.drink = 0.0
	var o := drop()
	if o:
		o.queue_free()
	item_kind = ""


func put_basket() -> Node3D:
	## Ставить кошик на землю поруч (потім можна знову взяти, торкнувшись його).
	if _bk == null or not is_instance_valid(_bk):
		_bk = null
		return null
	var b := _bk
	_bk = null
	if pose and pose.ik.has("RightHand"):
		var ik: Dictionary = pose.ik.duplicate()
		ik.erase("RightHand")
		pose.ik = ik
	var f := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var r := -global_transform.basis.x.normalized()
	b.global_transform = Transform3D(Basis(Vector3.UP, rotation.y).scaled(Vector3.ONE * BK_SCALE), Vector3(global_position.x, global_position.y, global_position.z) + r * 0.3 + f * 0.25)
	b.visible = true
	if b.get_node_or_null("Pick") == null:
		var a := Util.pick_area("nk_basket", Vector3(0.5, 0.5, 0.5), Vector3(0, 0.2, 0))
		a.name = "Pick"
		b.add_child(a)
	(b.get_node("Pick") as Area3D).input_ray_pickable = true
	return b


func pick_basket(b: Node3D) -> void:
	## Бере кошик, що стоїть на землі: нахиляється, і кошик — у правій руці.
	if b == null or not is_instance_valid(b):
		return
	if _bk and is_instance_valid(_bk) and _bk != b:
		put_basket()
	var an := "crouch_pick" if anims.get("crouch_pick", "") != "" else "pick"
	if anims.get(an, "") != "":
		play(an)
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(b):
		return
	var a := b.get_node_or_null("Pick") as Area3D
	if a:
		a.input_ray_pickable = false
	if b.get_parent() != get_parent():
		b.reparent(get_parent(), true)
	_bk = b
	_bk_last = global_position
	play("idle")
	say("Беру кошик!", 1.6)
