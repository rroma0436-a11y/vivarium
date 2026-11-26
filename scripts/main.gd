extends Node
## Головна сцена 3D-версії: світ, камера за Beep, персонажі, торкання, квести дідуся.

var world
var audio
var _bark_t := 6.0
var _hen_t := 4.0
var rig
var hud
var puppy
var grandpa
var beep
var terrarium
var kid
var gvintyk
var drone
var birds: Array = []
var geese: Array = []
var dragon
var plane
var tractor
var trailer                             # причіп-самоскид до трактора (trailer.gd)
var orchard
var forest
var hit_area: Node
var _ctl_beep := false                  # гравець сам керує Beep (джойстик)
var _ctl_veh: Node3D = null             # гравець сам кермує трактором чи конем із возом (джойстик)
var _veh_kind := ""                     # "tractor" / "horse"
var _ctl_girl := false                  # гравець сам водить Ніку (джойстик або торкання землі)
var _girl_goal := Vector3.INF
var _house_go := false               # Ніка йде до дверей дідової хати, щоб зайти
var _girl_stuck := 0.0
var _furn = null                        # меблі, до яких іде Ніка: {act, area, spot}
var _meet = null                        # до кого (чого) йде Ніка: {kind, node, area, r}
var _goal_route: Array = []             # решта точок шляху (хвіртка, міст…) до місця, куди торкнулися
var _gesture_t := 0.0                   # Ніка вітається / збирає — поки не рушиш джойстиком
var _acting := ""                       # Ніка сидить / лежить / п'є (джойстик — встає)
var _cam_b = null                       # будівля, в якій зараз камера
var _cam_act := ""                 # сіла/лягла — камера один раз підлітає, далі її можна крутити й віддаляти
var _dmin_out := 3.0
var _dmax_out := 26.0
var girl
var seeds
var riding := false                    # дівчинка на драконі, керує гравець
var gold_flower: Node3D
var _geese_day := -1
var ball: Node3D
var _herd_day := -1
var _out_day := -1
var bowl: Node3D
var kibble: Node3D
var _shot := ""
var _demo := ""
var hero := "girl"
const HEROES := [["girl", "Ніка", "girl"], ["granny", "Бабуся Галя", "granny"], ["grandpa", "Дідусь Петро", "grandpa"],
	["shepherd", "Пастух Іван", "shepherd"], ["groom", "Конюх Семен", "groom"], ["kid", "Тарасик", "kid"], ["robot_kid", "Гвинтик", "gvintyk"]]
var _frames := 0
var _greeted := false
var _track: Node3D
var _last_tap := Vector2.ZERO


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--demo="):
			_demo = a.substr(7)
		elif a.begins_with("--time="):
			Game.state["time"] = float(a.substr(7))
	if _shot == "" and _demo == "":
		var fl := [is_processing(), is_physics_processing(), is_processing_input(), is_processing_unhandled_input()]
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		await _pick_hero()
		set_process(fl[0])
		set_physics_process(fl[1])
		set_process_input(fl[2])
		set_process_unhandled_input(fl[3])
	world = preload("res://scripts/world.gd").new()
	add_child(world)
	audio = preload("res://scripts/audio.gd").new()
	audio.name = "Audio"
	add_child(audio)
	rig = preload("res://scripts/cam_rig.gd").new()
	add_child(rig)
	rig.tapped.connect(tap)
	_spawn_characters()
	hud = preload("res://scripts/hud.gd").new()
	var ui := CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	ui.add_child(hud)
	hud.action.connect(_on_action)
	hud.place_provider = func(): return world.outer.place_name(_player_pos())
	hud.flight.home_pressed.connect(func():
		if _ctl_girl and _mount_state == "ride":
			_show_vehicle_menu()
		elif _ctl_girl:
			_show_nika_menu()
		elif _ctl_veh:
			_ctl_veh = null                  # «Готово» — дідусь сам ставить транспорт на місце
		elif _ctl_beep:
			stop_beep_control()
		elif plane and riding:
			plane.go_home())
	hud.flight.land_pressed.connect(func():
		if _ctl_girl and _mount_state == "ride":
			dismount()
		elif _ctl_veh and _veh_kind == "tractor":
			_show_hitch_menu()
		elif _ctl_beep:
			beep._lift_want = 0.0
		elif plane and riding:
			plane.land_here())
	hud.build_minimap(world.outer, world.YARD)
	hud.marker_provider = _map_markers
	hud.seed_provider = func() -> Array:
		var a: Array = []
		if seeds:
			for i in seeds.nodes.size():
				if seeds.nodes[i].visible:
					a.append(seeds.SPOTS[i])
		return a
	hud.map_tapped.connect(func(p: Vector3):
		if _ctl_girl:
			_girl_goal = p
			return
		if Game.state["location"] == "yard":
			audio.play("click", -6.0)
			beep.fly_to(p))
	Game.quest_started.connect(_on_quest_started)
	Game.quest_done.connect(_on_quest_done)
	Game.night_started.connect(_on_night_started)
	go_to(Game.state["location"], true)
	await get_tree().process_frame
	Solids.build(world, [world.room_root])       # хати й дерева тверді для Beep
	Game.start_quest()
	if _demo != "":
		_run_demo()
	elif _shot == "" and girl:
		start_girl_control(true)              # Ніка — головна героїня: граємо нею одразу


func _pick_hero() -> void:
	var list := []
	for h in HEROES:
		if Models.exists(h[0]):
			list.append(h)
	if list.size() < 2:
		return
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.22, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	bg.add_child(box)
	var t := Label.new()
	t.text = "Ким будеш грати?"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 52)
	box.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)
	var picked := [""]
	_preload_models()
	for h in list:
		var b := Button.new()
		b.text = h[1]
		b.custom_minimum_size = Vector2(230, 230)
		b.add_theme_font_size_override("font_size", 28)
		var ic := "res://assets/ui/%s.png" % h[2]
		if h[2] != "" and ResourceLoader.exists(ic):
			b.icon = load(ic)
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var id: String = h[0]
		b.pressed.connect(func(): picked[0] = id)
		grid.add_child(b)
	while picked[0] == "":
		await get_tree().process_frame
	hero = picked[0]
	grid.hide()
	t.text = "Завантаження…"
	await get_tree().process_frame
	await get_tree().process_frame
	for p in _preload_paths:
		var r = ResourceLoader.load_threaded_get(p)
		if r:
			_preloaded.append(r)
	cl.queue_free()


var _preload_paths: Array = []
var _preloaded: Array = []


func _preload_models() -> void:
	## Поки гравець обирає героя — моделі вже вантажаться у фонових потоках.
	var d := DirAccess.open("res://assets/models")
	if d == null:
		return
	for f in d.get_files():
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if not n.ends_with(".glb"):
			continue
		var p := "res://assets/models/" + n
		if p in _preload_paths:
			continue
		if ResourceLoader.load_threaded_request(p, "", true) == OK:
			_preload_paths.append(p)


func _spawn_characters() -> void:
	var sp: Dictionary = world.spots
	# миска з кормом (корм — купка гранул, яка зменшується, поки Бім їсть)
	bowl = Node3D.new()
	bowl.position = sp["bowl"] + Vector3(0, world.BOWL_STAND_H, 0)
	world.yard_root.add_child(bowl)
	var bm := Models.spawn(bowl, "bowl", 0.13)
	if bm == null:
		bowl.add_child(Util.cyl(0.14, 0.11, 0.1, Util.mat(Color(0.85, 0.2, 0.2), 0.35), Vector3(0, 0.05, 0)))
	kibble = Node3D.new()
	bowl.add_child(kibble)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cols := [Color(0.62, 0.38, 0.18), Color(0.78, 0.52, 0.25), Color(0.9, 0.7, 0.35)]
	for i in 34:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.1
		var y := 0.075 + (0.1 - r) * 0.35 + rng.randf() * 0.015
		var k := Util.sphere(0.017, Util.mat(cols[i % 3], 0.8), Vector3(cos(a) * r, y, sin(a) * r), Vector3(1.3, 0.8, 1))
		k.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		kibble.add_child(k)
	bowl.add_child(Util.pick_area("bowl", Vector3(0.5, 0.3, 0.5), Vector3(0, 0.1, 0)))
	puppy = preload("res://scripts/puppy.gd").new()
	puppy.position = sp["doghouse"] + Vector3(1.2, 0, 1.6)
	world.yard_root.add_child(puppy)
	puppy.bowl_pos = sp["bowl"]
	puppy.home_pos = sp["doghouse"]
	grandpa = preload("res://scripts/grandpa.gd").new()
	grandpa.spots = sp
	grandpa.world = world
	grandpa.position = sp["porch"] + Vector3(1.2, 0, 0.4)
	world.yard_root.add_child(grandpa)
	grandpa.setup_seats()
	beep = preload("res://scripts/beep.gd").new()
	add_child(beep)
	puppy.follow = beep
	# курочки й півник біля курника
	for i in 5:
		var b := preload("res://scripts/bird.gd").new()
		world.yard_root.add_child(b)
		var at: Vector3 = sp.get("coop", Vector3(6.6, 0, -1.6)) + Vector3(randf_range(-1.5, 0.2), 0, randf_range(-1.2, 1.2))
		if i == 0:
			b.setup("rooster", 0.6, at, true)
		else:
			b.setup("hen", 0.48, at)
	# сусідський хлопчик Тарасик і маленький робот Гвинтик
	if Models.exists("kid"):
		kid = preload("res://scripts/kid.gd").new()
		kid.main = self
		world.yard_root.add_child(kid)
		kid.position = Vector3(-2.5, 0, 2.0)
		kid.setup("kid", 1.15, {"idle": ["idle_022", "idle_02"], "walk": ["walk"], "run": ["run"], "talk": ["listening"]},
			["idle", "walk", "run"],
			["Привіт! Я Тарасик, живу в селі.", "Я працюю на фермі — годую корів і коней!", "У корівнику треба прибирати щодня.", "Сіно з копиці — коникам найсмачніше!", "Я ношу воду з криниці — я сильний!"],
			[], "npc")
		Models.give_nika_anims(kid.ap, kid.anims)
		kid.setup_pose()
		kid.make_bucket()
	if Models.exists("robot_kid"):
		gvintyk = preload("res://scripts/gvintyk.gd").new()
		gvintyk.main = self
		world.yard_root.add_child(gvintyk)
		gvintyk.position = Vector3(5.6, 0, -2.6)
		gvintyk.setup("robot_kid", 0.9, {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "dance": ["dance"]},
			["idle", "walk", "run", "dance"],
			["Біп! Я Гвинтик — механік ферми.", "Зарядився на 100%!", "Трактор полагоджено — тепер випробуємо! Біп!", "Гайки підкручені, мастило є!"],
			[], "npc")
		Models.give_nika_anims(gvintyk.ap, gvintyk.anims)
		gvintyk.setup_pose()
		gvintyk.make_props()
	if Models.exists("drone"):
		drone = preload("res://scripts/drone.gd").new()
		world.yard_root.add_child(drone)
		drone.setup(Vector3(-5.6, 0, 2.4), sp)
	for b in world.yard_root.get_children():
		if "rooster" in b:
			birds.append(b)
	# гуси гуляють у лівій частині двору, на ніч ідуть у сарай
	if Models.exists("goose"):
		for i in 3:
			var g := preload("res://scripts/bird.gd").new()
			g.goose = true
			world.yard_root.add_child(g)
			g.setup("goose", 0.62 if i > 0 else 0.7, Vector3(-12.0 + i * 0.9, 0, 1.0 + i * 0.6))
			g.base_radius = 3.5
			g.radius = 3.5
			g.speed *= 0.8
			g.coop_hole = world.spots["barn"] + Vector3(0, 0, -0.75)
			geese.append(g)
	# індик гуляє з гусьми, на ніч теж іде в сарай
	if Models.exists("turkey"):
		var tk := preload("res://scripts/bird.gd").new()
		tk.goose = true
		tk.voice = "Бал-бал-бал!"
		world.yard_root.add_child(tk)
		tk.setup("turkey", 0.85, Vector3(-10.0, 0, -4.5))
		tk.base_radius = 3.0
		tk.radius = 3.0
		tk.speed *= 0.7
		tk.coop_hole = world.spots["barn"] + Vector3(0.6, 0, -0.75)
		geese.append(tk)
	_spawn_shopkeepers()
	_check_models()
	_spawn_cattle()
	_spawn_workers()
	if Models.exists("plane_y"):
		plane = preload("res://scripts/plane.gd").new()
		world.yard_root.add_child(plane)
		plane.setup(world.outer.HANGAR, world.outer.RUNWAY_A, world.outer.RUNWAY_B)
		plane.hangar_door = world.outer.set_hangar_door
		plane.landed.connect(_on_plane_landed)
	_spawn_farm_extras()
	if Models.exists("girl"):
		girl = preload("res://scripts/girl.gd").new()
		girl.main = self
		world.yard_root.add_child(girl)
		girl.position = girl.HOME_YARD
		girl.setup_girl()
		var twin = {"granny": granny, "grandpa": grandpa, "groom": groom, "shepherd": shepherd,
			"kid": kid, "robot_kid": gvintyk}.get(hero)
		if twin:
			twin.hide()
			twin.process_mode = Node.PROCESS_MODE_DISABLED
	_spawn_forest_hares()
	seeds = preload("res://scripts/seeds.gd").new()
	world.yard_root.add_child(seeds)
	seeds.build()
	seeds.dragon = plane
	seeds.collected.connect(_on_seed)
	if Game.state["seeds"].size() >= seeds.SPOTS.size():
		_make_gold_flower(false)
	puppy.water_pos = sp["water_bowl"]
	var bl: Vector3 = sp["water_bowl"] - sp["bowl"]
	puppy.bowl_front = Vector3(-bl.z, 0, bl.x).normalized()
	puppy.main = self
	terrarium = preload("res://scripts/terrarium.gd").new()
	terrarium.position = sp["terrarium"]
	terrarium.rotation.y = deg_to_rad(18)
	world.room_root.add_child(terrarium)
	terrarium.position = sp["terrarium"] - world.ROOM
	terrarium.scale = Vector3.ONE * 1.35                   # більший тераріум — більше місця Лимончикові
	terrarium.gecko.scale = Vector3.ONE / 1.35


func go_to(loc: String, instant := false, keep_beep := false) -> void:
	Game.state["location"] = loc
	beep.outdoors = loc == "yard"
	if loc != "yard":
		beep.lift = 0.0
		beep._lift_want = 0.0
		beep._cruise = false
	cam_follow = null
	_cam_up = 0.8
	if hud:
		hud.show_overview_button(false)
	var sp: Dictionary = world.spots
	rig.blockers = [AABB(world.HOUSE_POS + Vector3(-3.2, 0, -3.7), Vector3(6.4, 6.0, 7.1)) if world.big_house else AABB(world.HOUSE_POS + Vector3(-3.0, 0, -2.4), Vector3(6.0, 4.6, 4.8))] if loc == "yard" else []
	if loc == "yard":
		if not keep_beep:
			beep.position = sp["porch"] + Vector3(2.4, 0, 2.2) if instant or beep.position.z < -500 else sp["porch"] + Vector3(0.4, 0, 1.2)
		rig.setup(sp["door"] + Vector3(0, 0.9, 1.0) if keep_beep else beep.position + Vector3(0, 0.9, 0), 0.0, -20.0, 6.8, 3.0, 26.0)
	else:
		beep.position = world.ROOM + Vector3(-0.3, 0, -1.6)
		rig.setup(world.ROOM + Vector3(0, 1.25, 0.2), 20.0, -14.0, 2.2, 0.3, 2.4, 400.0, -45.0, 8.0)
	rig.inside_box = AABB(world.ROOM + Vector3(-3.3, 0.25, -2.55), Vector3(6.6, 2.55, 5.1)) if loc == "room" else AABB()
	if not keep_beep:
		beep.moving = false
	if hud:
		hud.refresh()


func _ambient_voices(delta: float) -> void:
	## Бім іноді гавкає, кури кудкудакають, зранку кукурікає півень, уночі ухкає сова.
	if Game.state["location"] != "yard":
		return
	_bark_t -= delta
	if _bark_t <= 0.0:
		_bark_t = randf_range(10.0, 25.0)
		if not Game.is_night():
			audio.play_at("puppy_bark" if randf() < 0.6 else "small_dog", puppy, -6.0)
	_hen_t -= delta
	if _hen_t <= 0.0:
		_hen_t = randf_range(7.0, 16.0)
		for b in world.yard_root.get_children():
			if "rooster" in b:
				if Game.is_night():
					if randf() < 0.3:
						audio.play_at("owl", world.yard_root, -10.0)
				elif b.rooster and Game.hour() < 9.5 and randf() < 0.5:
					audio.play_at("rooster", b, -4.0)
				else:
					audio.play_at("hens" if randf() < 0.7 else "chicks", b, -10.0)
				break


var _door_acc := 0.0
var _lod_acc := 0.0


func _lod_characters(dt: float) -> void:
	## Далекі персонажі: не малюємо й не рахуємо скелет/анімацію (логіка — ходьба, справи — працює далі).
	_lod_acc += dt
	if _lod_acc < 0.3:
		return
	_lod_acc = 0.0
	if rig == null or rig.cam == null:
		return
	var cp: Vector3 = rig.cam.global_position
	var list: Array = [girl, tea_boy, market_bot, kid, gvintyk, puppy, grandpa, horse]
	list.append(granny)
	list.append_array(cows)
	list.append_array(extra_horses)
	list.append_array(geese)
	list.append_array(birds)
	for w in list:
		if w == null or not is_instance_valid(w):
			continue
		var n: Node3D = w
		var far := n.global_position.distance_to(cp) > 75.0
		var m = n.get("model")
		if m is Node3D:
			(m as Node3D).visible = not far
		var a = n.get("ap")
		if a is AnimationPlayer:
			(a as AnimationPlayer).active = not far


func _watch_doors(dt: float) -> void:
	## Двері будинків і ворота відчиняються, коли хтось підходить.
	_door_acc += dt
	if _door_acc < 0.25:
		return
	var mv: Array = []
	if Game.state["location"] == "yard" and not beep.piloting and beep.lift < 3.0:
		mv.append(beep.global_position)
	for w in [grandpa, girl if not _ctl_girl else null, kid, gvintyk, puppy, groom, shepherd]:
		if w and is_instance_valid(w) and w.visible and (w as Node3D).global_position.z > -500.0:
			mv.append((w as Node3D).global_position)
	for g in geese:
		if g.visible:
			mv.append(g.global_position)
	for c in cows:
		if c.visible:
			mv.append(c.global_position)
	if horse and horse.visible:
		mv.append(horse.global_position)
	if garden_horse and garden_horse.visible:
		mv.append(garden_horse.global_position)
	for eh in extra_horses:
		if eh.visible:
			mv.append(eh.global_position)
	if _ctl_girl and girl:
		# двері й ворота, які Ніка відчинила сама, — відчинені, поки вона поруч
		var gp: Vector3 = girl.global_position
		for g in _hand_open.keys():
			var ad: Dictionary = world.auto_doors[g]
			var p: Vector3 = ad["pos"]
			if Vector2(gp.x - p.x, gp.z - p.z).length() < float(ad["r"]) + 0.8:
				mv.append(gp)
			else:
				_hand_open.erase(g)
		if _mount and _mount_state == "ride":
			mv.append(_mount.global_position)
	world.door_watch(mv, _door_acc)
	_door_acc = 0.0


var _resume_t := 0.0


func _nika_resume(delta: float) -> void:
	## Ніка — головна героїня: щойно закінчився політ, керування Beep чи трактором — знову граємо нею.
	if _ctl_girl or girl == null or _demo != "" or _shot != "" or _girl_starting:
		_resume_t = 0.0
		return
	if riding or girl.on_plane or _ctl_beep or _ctl_veh != null or _veh_kind != "" or Game.state["location"] != "yard":
		_resume_t = 0.0
		return
	_resume_t += delta
	if _resume_t > 1.2:
		_resume_t = 0.0
		start_girl_control(true)


func _process(_delta: float) -> void:
	_nika_resume(_delta)
	_watch_doors(_delta)
	_lod_characters(_delta)
	var loc: String = Game.state["location"]
	if world.outer.bazaar:
		var who: Array = []
		if girl and girl.visible and not _ctl_girl:
			who.append(girl.global_position)          # Ніка, якою керує гравець, відчиняє двері сама (рукою)
		if _mount and _mount_state == "ride":
			who.append(_mount.global_position)
		world.outer.bazaar.step(_delta, who, rig.cam.global_position, girl.global_position if _ctl_girl and girl else Vector3.INF)
	if riding and plane and plane.state != "rest":
		_ride_cam(_delta)
	elif _ctl_girl:
		_girl_cam(_delta)
	elif _ctl_veh:
		_veh_cam(_delta)
	elif _ctl_beep:
		_beep_cam(_delta)
	elif _track:
		rig.focus = _track.global_position + Vector3(0, 0.3, 0)
	elif loc == "yard":
		if cam_follow and (not is_instance_valid(cam_follow) or not cam_follow.is_visible_in_tree()):
			overview()
		if cam_follow:
			rig.focus = cam_follow.global_position + Vector3(0, _cam_up, 0)
		else:
			rig.focus = beep.global_position + Vector3(0, _cam_up + beep.lift, 0)
	kibble.visible = Game.state["puppy"]["bowl"] > 0.0
	if hud and loc == "yard":
		hud.update_map_dot(_player_pos())
	if _frames % 60 == 5 and seeds and hud:
		var flags: Array = []
		for n in seeds.nodes:
			flags.append(n.visible)
		hud.set_seed_dots(seeds.SPOTS, flags)
	_frames += 1
	if _frames % 30 == 0 and hud:
		hud.refresh()
	if _frames % 60 == 0:
		_farm_tick()
	if _frames % 15 == 7:
		_night_step()
	_ambient_voices(_delta)
	if _shot != "" and _frames == 60:
		get_viewport().get_texture().get_image().save_png(_shot)
		print("SHOT ", _shot)
		if _demo == "":
			get_tree().quit()


# ------------------------------------------------------------------ торкання
func tap(pos: Vector2) -> void:
	_last_tap = pos
	if hud.dialog_open() or riding or _ctl_veh:
		return
	if _ctl_girl and _mount_state != "":
		return
	var cam: Camera3D = rig.cam
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 80.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"].is_visible_in_tree() and hit["collider"].input_ray_pickable:
		var kind := String(hit["collider"].get_meta("kind"))
		if Game.state["location"] == "yard" and not _ctl_girl:
			focus_on(hit["collider"].get_parent(), kind)
		hit_node = hit["collider"].get_parent()
		hit_area = hit["collider"]
		if _ctl_girl and _meet_begin(kind, hit_node, hit_area):
			return
		_tap_object(kind)
		return
	if dir.y < -0.01:
		var t := -from.y / dir.y
		var p := from + dir * t
		if _ctl_girl:
			_meet = null
			_goal_route = _girl_route_to(Vector3(p.x, 0, p.z))
			_girl_goal = _goal_route.pop_front()
			_girl_stuck = 0.0
			return
		if Game.state["location"] == "yard":
			p.x = clampf(p.x, -world.outer.LIMIT, world.outer.LIMIT)
			p.z = clampf(p.z, -world.outer.LIMIT, world.outer.LIMIT)
			overview()
			beep.fly_to(p)
			if randf() < 0.35:
				puppy.walk_to(p + Vector3(randf_range(-1, 1), 0, 1.0), true)
		else:
			var r: Vector3 = world.ROOM
			p.x = clampf(p.x, r.x - 3.0, r.x + 3.0)
			p.z = clampf(p.z, r.z - 1.8, r.z + 2.0)
			beep.fly_to(p)
			rig.focus = world.ROOM + Vector3(0, 1.25, 0.2)
			rig.dist = 2.2


func _tap_object(kind: String) -> void:
	match kind:
		"beep":
			audio.play_at("robot_beep", beep, 0.0)
			beep.outdoors = Game.state["location"] == "yard"
			beep.hop()
			if beep.outdoors:
				rig.glide_to(9.0, -24.0)
			beep.say(_beep_hint(), 3.5)
			Game.emit_event("tap_beep")
		"puppy":
			if Game.hour() >= 18.5 and _hens_outside() and puppy.doing != "herd":
				herd_hens()
				return
			beep.fly_to(puppy.global_position + Vector3(0.6, 0, 0.8))
			puppy.pet(rig.cam.global_position)
			audio.play_at("puppy_bark", puppy, -2.0, 1.1)
		"grandpa":
			var nt := Game.night_task() if Game.night_active() else {}
			if not nt.is_empty() and nt["goal"] == "blanket":
				if grandpa.doing == "sleep" and (grandpa.lying or grandpa.seated == "armchair"):
					beep.fly_to(grandpa.global_position + (Vector3(-1.0, 0, 0.4) if grandpa.lying else grandpa.global_transform.basis.z * 1.0))
					grandpa.cover(true)
					audio.play("pop", -10.0, 0.8)
					Game.emit_event("blanket")
				else:
					beep.say("Дідусь ще не ліг — зачекаймо трішки.", 3.0)
				return
			if grandpa.doing == "sleep":
				beep.say("Тсс… дідусь спить.", 2.0)
				return
			if grandpa.at_home and grandpa.seated == "armchair" and (Game.day_done() or Game.hour() >= 19.0):
				grandpa.say("Ох, зачитався… Піду вже спати. Добраніч!", 3.0)
				grandpa.command_bed()
				return
			grandpa.wave_at(rig.cam.global_position)
			# дідусеві справи — у його власному меню
			hud.show_grandpa_menu(grandpa.at_home, grandpa.doing in ["plow", "orchard", "forest", "tractor", "cart", "garden"])
		"bowl":
			_on_action("feed")
		"house":
			if _ctl_girl:
				_nika_house_go()
			else:
				enter_house()
		"room_exit":
			if _ctl_girl:
				_nika_house_leave()
			else:
				leave_house()
		"hangar_btn":
			if _ctl_girl:
				_nika_btn_go(hit_area)
			else:
				hud.toast("Кнопка воріт ангара. Керуй Нікою — і вона її натисне!", 3.0)
		"plane":
			if plane and _ctl_girl and not riding:
				_nika_plane_go()
			elif plane:
				if riding:
					plane.say("Летимо!", 1.5)
				elif plane.state == "rest":
					start_ride()
				else:
					plane.poke()
		"firefly":
			var ff: Node3D = hit_node if hit_node else null
			if ff:
				beep.fly_to(ff.global_position)
		"saddle_horse":
			if _ctl_girl:
				start_mount("horse", hit_node)
			elif hit_node and hit_node.has_method("poke"):
				hit_node.poke()
				audio.play_at("pop", hit_node, -6.0, 0.6)
		"bike":
			if _ctl_girl:
				start_mount("bike", bike)
			else:
				hud.toast("Велосипед Ніки. Керуй Нікою — і вона на ньому поїде!", 3.0)
		"bull":
			if hit_node and hit_node.has_method("poke"):
				hit_node.poke()
				audio.play_at("pop", hit_node, -6.0, 0.6)
		"horse":
			if horse:
				horse.poke()
		"hare":
			if hit_node and hit_node.has_method("poke"):
				hit_node.poke()
				audio.play_at("pop", hit_node, -6.0, 1.4)
		"cart":
			hud.toast("Щоб поїхати на возі, торкнись дідуся → «Запрягти коня з возом»", 4.0)
		"garden_cart":
			hud.toast("Віз із конем біля садка. Торкнись дідуся → «Поїхати возом від садка», «Покласти чи зняти плуг з воза» або «Зорати поле конем»", 5.0)
		"gold_flower":
			audio.play("magic_bells", -6.0)
			hud.toast("Чарівний соняшник із золотих насінинок", 3.0)
		"combine":
			if _ctl_girl and combine:
				start_mount("combine", combine)
			else:
				hud.toast("Комбайн. Керуй Нікою — і вона залізе в кабіну й поїде!", 3.0)
		"tractor":
			if _ctl_girl and tractor and tractor.state == "parked" and grandpa.doing not in ["plow", "tractor"]:
				start_mount("tractor", tractor)
				return
			if tractor:
				tractor.poke()
				if _ctl_veh == tractor:
					hud.toast("Кермуй джойстиком; «Готово» — дідусь поставить трактор під навіс", 3.5)
				elif tractor.state == "parked" and grandpa.doing not in ["plow", "tractor"]:
					hud.show_tractor_menu()
		"orchard_tree":
			if orchard and hit_area and hit_area.has_meta("tree"):
				var ti: int = hit_area.get_meta("tree")
				var got: int = orchard.pick(ti, 3)
				if got > 0:
					beep.fly_to(orchard.pick_spot(ti, beep.global_position))
					beep.say("Зірвав %d — %s!" % [got, orchard.fruit_name(ti)], 2.5)
					audio.play("pop", -8.0, 1.2)
					Game.add_coins(got)
				else:
					hud.toast(orchard.describe(ti), 3.0)
		"forest_item":
			if forest and hit_area and hit_area.has_meta("item"):
				var gi: int = hit_area.get_meta("item")
				if forest.can_take(gi):
					beep.fly_to(forest.goods_pos(gi) + Vector3(0.8, 0, 0.8))
					forest.take(gi)
					beep.say("%s — у кошик!" % forest.label(gi), 2.5)
					audio.play("pop", -8.0, 1.1)
					Game.add_coins(1)
					Game.emit_event("forest")
				else:
					beep.say(forest.label(gi), 2.5)
		"stall":
			if hit_node and hit_node.has_meta("stall"):
				var info: Array = hit_node.get_meta("stall")
				hud.toast("Ларок «%s»: %s" % [info[0], info[1]], 3.5)
				audio.play("coins", -10.0)
				beep.say("Смакота!" if info[0] in ["Хліб", "Мед"] else "Гарний ларок!", 1.8)
		"granny":
			if granny:
				audio.play_at("question", granny, -4.0, 1.1)
				Game.emit_event("granny_met")
				if granny.doing == "" and not granny.moving and not granny.busy:
					granny.face(rig.cam.global_position)
				# власне меню бабусі Галі: подоїти корову, кури, город, борщ, пиріжки
				hud.show_granny_menu(Game.is_night() or not granny.on_time(), granny.doing == "milk")
		"pies":
			if granny and granny.plate and hit_node == granny.plate:
				beep.fly_to(granny.plate.global_position + Vector3(0.6, 0, 0.6))
				if granny.eat_pie():
					beep.say("Ням! Пиріжок із вишнями!" if granny.pies_left > 0 else "Останній пиріжок — найсмачніший!", 2.5)
					audio.play("pop", -8.0, 1.3)
					Game.add_coins(1)
		"bz_furn":
			if _ctl_girl and hit_area:
				_furn_go(hit_area)
		"bz_tack":
			_buy_tack()
		"trailer":
			if tractor and tractor.trailer == trailer:
				hud.toast("Причіп на тракторі: ▲ / ▼ або «Причепи» — підняти чи опустити кузов", 4.0)
			else:
				hud.toast("Причіп. Сядь у трактор, під'їдь задом до дишла й натисни «Меню» (або «Причепи») → «Причепити причіп»", 5.0)
		"bz_seller", "bz_shop":
			if world.outer.bazaar and hit_node:
				var sd := _seller_dict(hit_node, hit_area)
				if _ctl_girl and not sd.is_empty() and girl.global_position.distance_to(sd["front"]) < 2.5:
					_shop_open(sd)
				elif not sd.is_empty():
					world.outer.bazaar.seller_say(sd["node"])
					audio.play("coins", -12.0)
		"item":
			if _ctl_girl and hit_node and _acting == "sit":
				var hp: Vector3 = girl.hips_world()
				if Vector2(hit_node.global_position.x - hp.x, hit_node.global_position.z - hp.z).length() < 1.0:
					_nika_take(hit_node)               # сидить за столом — бере просто звідси
				else:
					girl.say("Не дотягнуся… Встану й візьму.", 2.0)
		"nk_basket":
			pass
		"girl":
			if girl and _ctl_girl:
				_show_nika_menu()
				return
			if girl:
				audio.play_at("question", girl, -4.0, 1.25)
				if _ctl_beep:
					stop_beep_control()
				start_girl_control()                 # Ніка — героїня: торкнувся її — знову граєш нею
		"bird":
			_poke_nearest_bird()
			audio.play("hens", -6.0)
		"npc":
			var best: Node3D = null
			var bd := INF
			for n in world.yard_root.get_children():
				if n.has_method("talk"):
					var d: float = rig.cam.unproject_position(n.global_position + Vector3(0, 0.6, 0)).distance_to(_last_tap)
					if d < bd:
						bd = d
						best = n
			var qid: String = Game.current_quest().get("id", "")
			if best and best == kid:
				# власне меню Тарасика (його справи — не в меню Beep)
				audio.play_at("question", kid, -4.0)
				if kid.doing == "" and not kid.moving:
					kid.face(rig.cam.global_position)
				hud.show_kid_menu(false)      # будь-яку нову справу можна замовити й під час іншої
			elif best and best == gvintyk and qid == "eggs" and gvintyk.doing == "":
				gvintyk.command("eggs")
			elif best and best in [gvintyk, shepherd, groom]:
				audio.play_at("robot_beep" if best == gvintyk else "question", best, -4.0)
				if best.doing == "" and not best.moving and best.get("riding") == null:
					best.face(rig.cam.global_position)
				hud.show_worker_menu("gvintyk" if best == gvintyk else ("shepherd" if best == shepherd else "groom"))
			elif best:
				best.talk(rig.cam.global_position)
				audio.play_at("robot_beep" if "robot" in str(best.model) else "question", best, -4.0)
		"drone":
			for n in world.yard_root.get_children():
				if n.has_method("poke") and n.has_method("setup") and "drops" in n:
					n.poke()
			audio.play("robot_beep", -6.0, 1.4)
		"well":
			audio.play("metal_drop", -8.0)
			beep.say("Вода в криниці холодна й смачна!", 2.5)
		"terrarium":
			# наближаємось до тераріуму; ще раз торкнутися — показати температуру
			var c: Vector3 = terrarium.global_position + Vector3(0, 1.0, 0)
			if rig.focus.distance_to(c) > 0.1:
				rig.focus = c
				rig.dist = 1.5
				rig.pitch = -14.0
				rig.yaw = rad_to_deg(terrarium.rotation.y)
			hud.toast("%s · %.1f °C" % [Game.gecko_mood(), Game.state["gecko"]["temp"]], 3.0)


func _poke_nearest_bird() -> void:
	var best: Node3D = null
	var bd := INF
	var cam_pos: Vector3 = rig.cam.global_position
	for b in world.yard_root.get_children():
		if "rooster" in b:
			var d: float = (b as Node3D).global_position.distance_to(cam_pos)
			if d < bd:
				bd = d
				best = b
	if best:
		best.poke()


func _grandpa_dialog(text: String) -> void:
	grandpa.start_talk(rig.cam.global_position)
	audio.play("page", -8.0)
	hud.show_dialog("Дідусь Петро", text, null, func(): grandpa.end_talk())


func _beep_hint() -> String:
	var q := Game.current_quest()
	if q.is_empty():
		return "Біп! Усе зроблено!"
	if q["where"] != "" and q["where"] != Game.state["location"]:
		return "Біп-буп! Нам треба в %s." % ("подвір'я" if q["where"] == "yard" else "хату — торкнись її")
	match q["id"]:
		"meet_beep":
			return "Біп-буп! Привіт! Я Beep."
		"feed_puppy":
			return "Натисни «Корм» — я насиплю!"
		"pet_puppy":
			return "Торкнись Біма, щоб погладити."
		"warm_gecko":
			return "Увімкни лампу й стеж за термометром."
		"feed_gecko":
			return "Коли тепло — натисни «Цвіркуни»."
		"meet_granny":
			return "Бабуся Галя — у червоній хустці. Торкнись її!"
		"granny_milk":
			return "Торкнись бабусі → «Подоїти корову»."
		"granny_garden":
			return "Торкнись бабусі → «Прополоти город»."
		"granny_pies":
			return "Торкнись бабусі → «Спекти пиріжки»."
	return "Біп!"


# ------------------------------------------------------------------ дії з кнопок
func _on_action(name: String) -> void:
	if name.begins_with("th_"):
		_hitch_do(name)
		return
	if name.begins_with("vm_"):
		_vehicle_do(name)
		return
	if name.begins_with("sh_"):
		_shop_buy(name)
		return
	if name in ["nk_basket_take", "nk_basket_put", "nk_put", "nk_eat"]:
		_nika_do(name)
		return
	match name:
		"feed":
			if Game.state["puppy"]["bowl"] > 0.0:
				hud.toast("Мисочка вже повна")
				return
			beep.say("Насипаю корм!", 2.0)
			beep.fly_to(bowl.global_position + Vector3(0.3, 0, 0.5), func():
				Game.fill_bowl()
				audio.play_at("plate", bowl, -4.0)
				beep.happy()
				puppy.say("Гав! Їжа!", 2.0)
				puppy.go_eat())
		"lamp":
			var on: bool = Game.toggle_lamp()
			audio.play("click", 0.0, 0.8)
			beep.say("Лампу ввімкнено. Стеж за термометром!" if on else "Лампу вимкнено.", 2.5)
		"crickets":
			beep.fly_to(terrarium.global_position + Vector3(1.0, 0, 0.1))
			var msg: String = Game.feed_gecko()
			if msg.begins_with("Ням"):
				terrarium.tongue()
				audio.play("pop", -4.0)
			beep.say(msg, 3.5)
		"help":
			hud.show_beep_menu(Game.state["location"] == "yard", Game.is_night(), beep.lamp.visible, grandpa.at_home)
		"hint":
			beep.say(_beep_hint(), 3.5)
			beep.happy()
			audio.play_at("robot_beep", beep, -2.0)
		"drone_feed":
			if drone == null:
				return
			if drone.busy():
				hud.toast("Дрон зараз зайнятий")
				return
			beep.say("Біп! Дроне, нагодуй курей!", 2.5)
			drone.feed_hens()
		"drone_water":
			if drone == null:
				return
			if drone.busy():
				hud.toast("Дрон зараз зайнятий")
				return
			beep.say("Біп! Дроне, полий город!", 2.5)
			drone.water_field()
		"ball":
			throw_ball()
		"light":
			var on: bool = beep.toggle_lamp()
			audio.play("click", -2.0, 1.3)
			beep.say("Ліхтарик увімкнено!" if on else "Ліхтарик вимкнено.", 2.0)
		"scan":
			beep.happy()
			audio.play_at("magic_bells", beep, -6.0)
			hud.show_dialog("Beep · сканер", _scan_text(), load("res://assets/ui/beep.png") if ResourceLoader.exists("res://assets/ui/beep.png") else null)
		"herd":
			if _hens_outside():
				herd_hens()
			else:
				hud.toast("Усі кури вже в курнику")
		"overview":
			overview()
		"goodnight":
			_goodnight()
		"sleep":
			_sleep_to_morning()
		"to_plane", "to_dragon":
			if plane == null:
				hud.toast("Немає моделі літака — завантаж на GitHub файл models_10.zip", 5.0)
				return
			if riding:
				return
			start_ride()
		"beep_ctl":
			start_beep_control()
		"girl_ctl":
			start_girl_control()
		"nk_forest", "nk_home", "nk_bazaar", "nk_grandpa", "nk_granny", "nk_bike", "nk_horse", "nk_combine", "nk_tractor", "nk_jump", "nk_beep":
			_nika_do(name)
		"home":
			beep.say("Летимо додому!", 2.0)
			beep.fly_to(world.spots["door"] + Vector3(1.5, 0, 2.0))
			overview()
		"go_yard":
			leave_house()
		"go_room":
			enter_house()
		"grandpa_in", "gp_in":
			grandpa.command_in()
		"grandpa_out", "gp_out":
			grandpa.command_out()
		"grandpa_bed", "gp_bed":
			grandpa.say("Добре, онучку, лягаю спати…", 2.5)
			grandpa.command_bed()
		"gp_talk":
			_grandpa_talk()
		"gp_plow":
			if tractor == null:
				hud.toast("Немає моделі трактора — завантаж на GitHub файл models_10.zip", 5.0)
				return
			if not tractor.plow_on or tractor.trailer:
				hud.toast("Щоб орати, причепи до трактора плуг (а причіп відчепи)", 4.0)
				return
			grandpa.cancel_job()
			grandpa.plow_job()
			_follow_later(grandpa)
		"kid_talk":
			if kid:
				kid.talk(rig.cam.global_position)
				audio.play_at("question", kid, -4.0)
		"kid_water", "water":
			if kid:
				kid.say("Зараз принесу води!", 2.0)
				kid.command("water")
				_follow_later(kid)
		"kid_feed", "kid_clean":
			if kid:
				kid.command("feed" if name == "kid_feed" else "clean")
				_follow_later(kid)
		"sh_out", "sh_in":
			if shepherd:
				shepherd.command("out" if name == "sh_out" else "in")
				_follow_later(shepherd)
		"gm_out", "gm_in", "gm_hay":
			if groom:
				groom.command({"gm_out": "out", "gm_in": "in", "gm_hay": "hay"}[name])
				_follow_later(groom)
		"gv_repair", "gv_test", "gv_eggs":
			if gvintyk:
				gvintyk.command({"gv_repair": "repair", "gv_test": "test", "gv_eggs": "eggs"}[name])
				_follow_later(gvintyk)
		"sh_talk", "gm_talk", "gv_talk":
			var who = {"sh_talk": shepherd, "gm_talk": groom, "gv_talk": gvintyk}[name]
			if who:
				who.talk(rig.cam.global_position)
				audio.play_at("robot_beep" if who == gvintyk else "question", who, -4.0)
		"girl_talk":
			if girl:
				girl.talk(rig.cam.global_position)
		"girl_forest":
			if girl:
				girl.cancel_job()
				girl.forest_job()
				_follow_later(girl)
		"girl_visit":
			if girl:
				girl.cancel_job()
				girl.visit_grandpa()
				_follow_later(girl)
		"girl_home":
			if girl:
				girl.cancel_job()
				girl.back_to_village()
				_follow_later(girl)
		"tr_drive", "tr_plow":
			if tractor == null:
				return
			if name == "tr_plow" and (not tractor.plow_on or tractor.trailer):
				hud.toast("Щоб орати, причепи до трактора плуг (а причіп відчепи)", 4.0)
				return
			if grandpa.doing == "sleep" or grandpa.lying:
				hud.toast("Дідусь спить — трактор почекає до ранку", 3.0)
				return
			grandpa.cancel_job()
			if name == "tr_drive":
				grandpa.tractor_drive_job()
			else:
				grandpa.plow_job()
			_follow_later(grandpa)
		"gp_tractor":
			if tractor == null:
				hud.toast("Немає моделі трактора — завантаж на GitHub файл models_10.zip", 5.0)
				return
			grandpa.cancel_job()
			grandpa.tractor_drive_job()
			_follow_later(grandpa)
		"gp_horse":
			if horse == null or horse_cart == null:
				hud.toast("Немає моделі коня чи воза — завантаж на GitHub файл models_11.zip", 5.0)
				return
			grandpa.cancel_job()
			grandpa.horse_job()
			_follow_later(grandpa)
		"gp_gcart", "gp_gplow", "gp_gfield":
			if garden_cart == null:
				hud.toast("Немає моделі коня чи воза — завантаж на GitHub файл models_11.zip", 5.0)
				return
			if name != "gp_gcart" and garden_plow == null:
				hud.toast("Немає моделі плуга (assets/models/plow.glb)", 4.0)
				return
			if grandpa.doing == "sleep" or grandpa.lying:
				hud.toast("Дідусь спить — кінь почекає до ранку", 3.0)
				return
			grandpa.cancel_job()
			match name:
				"gp_gcart":
					grandpa.garden_cart_job()
				"gp_gplow":
					grandpa.garden_plow_job()
				"gp_gfield":
					grandpa.garden_field_job()
			_follow_later(grandpa)
		"gp_orchard":
			grandpa.cancel_job()
			grandpa.orchard_job()
			_follow_later(grandpa)
		"gp_forest":
			grandpa.cancel_job()
			grandpa.forest_job()
			_follow_later(grandpa)
		"gp_read":
			grandpa.read_job()
		"gp_mush", "gp_market", "gp_fish", "gp_mill", "gp_sow", "gp_farm":
			if garden_cart == null or garden_horse == null:
				hud.toast("Немає моделі коня чи воза — завантаж на GitHub файл models_11.zip", 5.0)
				return
			if grandpa.doing == "sleep" or grandpa.lying:
				hud.toast("Дідусь спить — кінь почекає до ранку", 3.0)
				return
			grandpa.cancel_job()
			grandpa.trip_job(name.substr(3))
			_follow_later(grandpa)
		"gr_talk":
			_granny_talk()
		"gr_milk", "gr_hens", "gr_garden", "gr_borscht", "gr_pies":
			if granny == null:
				hud.toast("Немає моделі бабусі — завантаж на GitHub файл models_13.zip", 5.0)
				return
			if Game.is_night() or not granny.on_time():
				granny.say("Ніч надворі, онучку. Завтра зранку!", 2.5)
				return
			granny.cancel_job()
			match name:
				"gr_milk":
					granny.milk_job()
				"gr_hens":
					granny.hens_job()
				"gr_garden":
					granny.garden_job()
				"gr_borscht":
					granny.borscht_job()
				"gr_pies":
					granny.pies_job()
			_follow_later(granny)
		"sound":
			audio.set_muted(not audio.is_muted())
			hud.buttons["sound"].text = "♪" if not audio.is_muted() else "✕"


# ------------------------------------------------------------------ камера: зосередитись на тому, кого торкнулись, або загальний огляд
var cam_follow: Node3D                 # за ким стежить камера (null — загальний огляд за Beep)
var _cam_up := 0.8
const FOCUS := {
	# вид: [відстань, нахил, висота точки, на яку дивимось]
	"beep": [3.2, -14.0, 0.9], "puppy": [2.4, -14.0, 0.35], "grandpa": [3.4, -10.0, 1.1], "npc": [3.0, -10.0, 0.75],
	"bird": [2.0, -16.0, 0.3], "bowl": [2.6, -30.0, 0.3], "well": [5.5, -16.0, 1.3], "house": [11.0, -14.0, 2.2],
	"drone": [4.5, -14.0, 0.0], "plane": [12.0, -14.0, 1.2], "dragon": [9.5, -12.0, 1.4], "barn": [12.0, -16.0, 2.5], "workshop": [9.0, -14.0, 1.4],
	"girl": [2.8, -10.0, 0.65], "bull": [5.5, -14.0, 1.0], "gold_flower": [5.0, -12.0, 1.8],
	"granny": [3.2, -10.0, 1.0], "pies": [2.2, -28.0, 0.8],
}


var tea_boy
var market_bot
var bull


func _spawn_shopkeepers() -> void:
	## Хлопець-школяр біля площі в селі (чайну прибрано; згодом стане продавцем на базарі).
	var o = world.outer
	if false and Models.exists("student"):   # хлопець тепер продавець у ларьку на базарі (bazaar.gd)
		tea_boy = preload("res://scripts/npc.gd").new()
		tea_boy.name = "TeaBoy"
		tea_boy.main = self
		world.yard_root.add_child(tea_boy)
		var tp: Vector3 = o.TEA_POS
		var to_c: Vector3 = (o.VILLAGE - tp).normalized()
		var side := Vector3(-to_c.z, 0, to_c.x)
		var spots := [tp + to_c * 0.2, tp + to_c * 0.2 + side * 0.9, tp + to_c * 0.2 - side * 0.9, tp + to_c * 2.6]
		tea_boy.position = spots[0]
		tea_boy.setup("student", 1.6, {"idle": ["walking"], "walk": ["walking"], "run": ["running"], "dance": ["all_night"]},
			["walk", "run", "dance"],
			["Привіт! За річкою тепер великий базар — ти вже була?", "Я після школи хочу торгувати на базарі!",
			 "Скоро в мене буде свій ларьок!", "Сідай на лавку біля фонтану — відпочинь!", "Кажуть, над селом літає дракон!"], spots, "npc")
		tea_boy.bounds = Rect2(tp.x - 4.0, tp.z - 4.0, 8.0, 8.0)
		tea_boy.avoid = false
		tea_boy.setup_pose()
		tea_boy.make_idle_from("walk")
		tea_boy.shopkeeper = true
		tea_boy.idle_left = 20.0
		tea_boy.play("idle")
		tea_boy.face(o.VILLAGE)
		tea_boy.set_meta("view_from", to_c)
	# робота EngineBot і старий ринок на площі прибрано — тепер базар за річкою


func _map_markers() -> Array:
	## Для великої мапи: хто де.
	var m: Array = []
	if plane:
		m.append(["Літак" + (" (летить)" if plane.flying() else (" (в ангарі)" if plane.in_hangar else "")), plane.global_position, Color(0.95, 0.75, 0.1)])
	if girl and girl.visible:
		m.append(["Ніка", girl.global_position, Color(0.9, 0.15, 0.15)])
	if grandpa:
		if grandpa.at_home:
			m.append(["Дідусь (у хаті)", world.HOUSE_POS, Color(0.45, 0.35, 0.25)])
		else:
			m.append(["Дідусь", grandpa.global_position, Color(0.45, 0.35, 0.25)])
	m.append(["Бім", puppy.global_position, Color(0.9, 0.55, 0.15)])
	if granny:
		if granny.visible:
			m.append(["Бабуся Галя" + (" (доїть корову)" if granny.doing == "milk" else ""), granny.global_position, Color(0.85, 0.2, 0.2)])
		elif granny.in_house:
			m.append(["Бабуся (у хаті)", world.HOUSE_POS, Color(0.85, 0.2, 0.2)])
	for n in [kid, gvintyk]:
		if n and n.visible:
			m.append(["Тарасик" if n == kid else "Гвинтик", n.global_position, Color(0.2, 0.55, 0.85) if n == kid else Color(0.4, 0.5, 0.55)])
	if drone:
		m.append(["Дрон", drone.global_position, Color(0.3, 0.6, 0.3)])
	if bull and bull.visible:
		m.append(["Бичок", bull.global_position, Color(0.4, 0.25, 0.15)])
	var nc := 0
	var cp := Vector3.ZERO
	for c in cows:
		if c != bull and c.visible:
			nc += 1
			cp = c.global_position
	if nc > 0:
		m.append(["Корови (%d)" % nc, cp, Color(0.25, 0.25, 0.25)])
	if horse and horse.visible:
		m.append(["Кінь", horse.global_position, Color(0.6, 0.45, 0.3)])
	if tea_boy:
		m.append(["Хлопець біля площі", tea_boy.global_position, Color(0.25, 0.35, 0.7)])
	m.append(["Beep (ти)", beep.global_position if Game.state["location"] == "yard" else world.HOUSE_POS, Color(0.1, 0.7, 0.75)])
	for e in m:
		var pn: String = world.outer.place_name(e[1])
		if String(e[0]).ends_with("(у хаті)"):
			pn = "у хаті"
		e.append(pn)
	return m


# ------------------------------------------------------------------ трактор, садок, грибний ліс
# ферма за ставком (world_outer.gd: COWSHED_POS, STABLE_POS) — двері дивляться на схід (+X)
const COW_DOORS := [Vector3(-166.9, 0, 39.0), Vector3(-166.9, 0, 55.0), Vector3(-166.9, 0, 71.0)]     # біля дверей трьох корівників (зовні)
const COW_DOOR := Vector3(-166.9, 0, 55.0)            # середній корівник (пастух виганяє звідси)
const COW_PASTURE := Rect2(-153.0, 57.0, 22.0, 18.0)    # пасовисько перед корівниками (на південь від навісу для техніки)
const COW_BACK := Vector3(10.5, 0, 0)                  # від передніх дверей корівника до задніх воріт (з боку пасовиська)
const HORSE_DOORS := [Vector3(-187.0, 0, 39.7), Vector3(-187.0, 0, 55.7), Vector3(-187.0, 0, 71.7)]  # біля дверей трьох стаєнь
const HORSE_DOOR := Vector3(-187.0, 0, 39.7)           # перша стайня (кінь для воза)
const HORSE_PADDOCK := Rect2(-182.0, 36.0, 14.0, 36.0)   # левада перед стайнями
const CART_PARK := Vector3(-162.0, 0, 50.0)            # де стоїть віз (східніше левади)
const FARM_WAY := [Vector3(-24, 0, 8.5), Vector3(-45, 0, 9.0), Vector3(-120, 0, 9.0), Vector3(-166, 0, 9.0)]  # від воріт до ферми (північніше ставка, повз аеродром)
var cows: Array = []                                  # корови + бичок
var home_cow                                          # корова біля хати Тарасика (її доїть бабуся)
const HOME_COW_AT := Vector3(-27.0, 0, 14.0)
const HOME_COW_PASTURE := Rect2(-32.0, 11.0, 9.0, 7.0)
var horse
var horse_cart
var extra_horses: Array = []                          # коні для масовки (horse2.glb)


# віз із конем у упряжі біля дідового садка (східніше тину садка, оглоблями на північ) і кінний плуг поруч
const GARDEN_CART_PARK := Vector3(23.3, 0, 15.5)
const GARDEN_PLOW_AT := Vector3(21.5, 0, 16.0)
const GARDEN_PADDOCK := Rect2(22.6, 19.0, 2.4, 3.6)      # де пасеться розпряжений кінь
var garden_horse
var garden_cart
var garden_plow


func _spawn_garden_cart(field: Rect2) -> void:
	if not Models.exists("horse") or not Models.exists("cart"):
		return
	garden_cart = preload("res://scripts/cart.gd").new()
	world.yard_root.add_child(garden_cart)
	garden_cart.setup(GARDEN_CART_PARK, PI)
	# розпряжений кінь пасеться біля воза (на південь від нього), упряж лежить на возі
	garden_horse = preload("res://scripts/bull.gd").new()
	world.yard_root.add_child(garden_horse)
	var pc := Vector3(GARDEN_PADDOCK.get_center().x, 0, GARDEN_PADDOCK.get_center().y)
	garden_horse.setup(pc, pc, "horse", 1.75, GARDEN_PADDOCK)
	garden_horse.voices = ["І-го-го!", "Пфррр! Поїдемо орати?"]
	garden_horse.stay_out = true
	if garden_horse.area:
		garden_horse.area.set_meta("kind", "garden_cart")
	if garden_cart.area:
		garden_cart.area.set_meta("kind", "garden_cart")
	if Models.exists("plow"):
		garden_plow = preload("res://scripts/plow.gd").new()
		world.yard_root.add_child(garden_plow)
		garden_plow.setup(GARDEN_PLOW_AT, PI, field, tractor)


func _cow_way(d: Vector3) -> Array:
	## Від передніх дверей корівника (дивляться на захід) — обходом між корівниками на пасовисько за ними.
	var gz := d.z + 8.0
	return [Vector3(-168.5, 0, gz), Vector3(-155.0, 0, gz)]


func _spawn_cattle() -> void:
	## Бичок і п'ять корів (пасуться за корівником, на ніч — у корівник), кінь — у стайні.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	if Models.exists("bull"):
		bull = preload("res://scripts/bull.gd").new()
		world.yard_root.add_child(bull)
		bull.setup(Vector3(-145.0, 0, 65.0), COW_DOORS[0], "bull", 1.55, COW_PASTURE)
		bull.door_in = Vector3(3.0, 0, 0)
		bull.yard_way = _cow_way(COW_DOORS[0])
		cows.append(bull)
	if Models.exists("cow"):
		var names := ["Зірка", "Ласка", "Квітка", "Красуля", "Мілка"]
		for i in 5:
			var c = preload("res://scripts/bull.gd").new()
			world.yard_root.add_child(c)
			c.setup(Vector3(rng.randf_range(-151.0, -133.0), 0, rng.randf_range(58.0, 73.0)), COW_DOORS[(i + 1) % COW_DOORS.size()], "cow", rng.randf_range(1.35, 1.5), COW_PASTURE)
			c.door_in = Vector3(3.0, 0, rng.randf_range(-0.6, 0.6))
			c.yard_way = _cow_way(COW_DOORS[(i + 1) % COW_DOORS.size()])
			c.voices = ["Му-у-у! Я — %s." % names[i], "Мууу!", "Му-у! Молочко буде!"]
			c.night_from = 19.8 + i * 0.08
			c.set_meta("name", names[i])
			cows.append(c)
		# копія корови — пасеться біля хати Тарасика, ночує надворі
		home_cow = preload("res://scripts/bull.gd").new()
		world.yard_root.add_child(home_cow)
		home_cow.setup(HOME_COW_AT, HOME_COW_AT, "cow", 1.42, HOME_COW_PASTURE)
		home_cow.stay_out = true
		home_cow.voices = ["Му-у-у! Я — Зорька.", "Мууу!", "Му-у! Молочко буде!"]
		home_cow.set_meta("name", "Зорька")
	if Models.exists("horse"):
		horse = preload("res://scripts/bull.gd").new()
		world.yard_root.add_child(horse)
		horse.setup(Vector3(-176.0, 0, 42.0), HORSE_DOORS[0], "horse", 1.75, HORSE_PADDOCK)
		horse.door_in = Vector3(-3.0, 0, 0)
		horse.voices = ["І-го-го!", "Пфррр!", "І-го-го! Поїдемо кудись?"]
		horse.area.set_meta("kind", "horse")
		horse.night_from = 20.3
		if Models.exists("cart"):
			# віз стоїть біля стайні, оглоблями на північ (кінь стає перед ним)
			horse_cart = preload("res://scripts/cart.gd").new()
			world.yard_root.add_child(horse_cart)
			horse_cart.setup(CART_PARK, PI)
	# коні для масовки: рудий (horse2), гнідий (horse3 — тепер їздовий, із сідлом і вуздечкою з Blender), рудий осідланий (horse4)
	var mass := [["horse2", 1.55, Vector3(-178.0, 0, 52.0)], ["horse3", 1.52, Vector3(-174.0, 0, 60.0)], ["horse4", 1.68, Vector3(-172.0, 0, 46.0)]]
	for i in mass.size():
		var id: String = mass[i][0]
		if not Models.exists(id):
			continue
		var eh = preload("res://scripts/bull.gd").new()
		world.yard_root.add_child(eh)
		eh.setup(mass[i][2], HORSE_DOORS[(i + 1) % HORSE_DOORS.size()], id, mass[i][1], HORSE_PADDOCK)
		eh.door_in = Vector3(-3.0, 0, 0)
		eh.voices = ["І-го-го!", "Пфррр!"]
		eh.night_from = 20.5 + i * 0.12
		eh.speed_k = 0.9 + i * 0.1
		extra_horses.append(eh)
		if id == "horse4" and eh.area:
			# рудий осідланий — на ньому Ніка їздить верхи
			eh.area.set_meta("kind", "saddle_horse")
			eh.no_harness = true
			eh.voices = ["І-го-го! Сідай, Ніко!", "Пфррр!"]
			saddle_horse = eh
			riding_horses.append(eh)
		elif id == "horse3" and eh.area and Models.exists("saddle"):
			# гнідий: вдягаємо сідло й вуздечку (saddle.glb, bridle.glb) — теж їздовий
			eh.add_tack(0.745)
			eh.area.set_meta("kind", "saddle_horse")
			eh.voices = ["І-го-го! У мене нове сідло!", "Пфррр! Поїдемо, Ніко?"]
			riding_horses.append(eh)
			if saddle_horse == null:
				saddle_horse = eh
	_spawn_ride_things()


var hares: Array = []
var granny
var groom
var shepherd


func _spawn_workers() -> void:
	## Бабуся (живе з дідом). Тарасик, Гвинтик, пастух Іван і конюх Семен живуть у хатах села
	## (по дві з кожного боку дороги біля фонтану) і щоранку ходять на ферму за ставком працювати.
	_make_farm_hay()
	if Models.exists("granny"):
		granny = preload("res://scripts/granny.gd").new()
		granny.name = "Granny"
		granny.main = self
		world.yard_root.add_child(granny)
		granny.setup_granny(world.spots)
	var in_farm := [Vector3(-171.5, 0, 20.0)]
	if Models.exists("groom") and horse:
		groom = preload("res://scripts/groom.gd").new()
		groom.name = "Groom"
		groom.main = self
		world.yard_root.add_child(groom)
		groom.setup_groom(_home_door(1.0, 1), _home_way(1.0, 1) + in_farm + [Vector3(-174, 0, 36.0)])
	if Models.exists("shepherd") and not cows.is_empty():
		shepherd = preload("res://scripts/shepherd.gd").new()
		shepherd.name = "Shepherd"
		shepherd.main = self
		world.yard_root.add_child(shepherd)
		shepherd.setup_shepherd(COW_DOOR, COW_PASTURE, _home_door(-1.0, 1),
			_home_way(-1.0, 1) + in_farm + [Vector3(-171.5, 0, 31.0), Vector3(-152.0, 0, 32.0)])
	if kid:
		kid.start_farm(_home_door(1.0, 0), _home_way(1.0, 0) + in_farm + [Vector3(-172.0, 0, 33.0)], 7.0, 19.0, 4)
	if gvintyk:
		gvintyk.start_farm(_home_door(-1.0, 0), _home_way(-1.0, 0) + in_farm + [Vector3(-171.5, 0, 31.0), Vector3(-152.0, 0, 32.0), Vector3(-143.0, 0, 46.0)], 7.2, 19.2, 4)
	var k := 0
	for e in [[kid, 1.0, 0], [gvintyk, -1.0, 0], [groom, 1.0, 1], [shepherd, -1.0, 1]]:
		if e[0]:
			_give_bike(e[0], e[1], e[2], k, in_farm[0])
		k += 1


# ------------------------------------------------------------------ велосипеди працівників (на роботу й з роботи)
const WORKER_BIKE := 1.25                       # трохи більші за Ніччин
const FARM_BIKES := [Vector3(-174.5, 0, 79.5), Vector3(-176.0, 0, 79.5), Vector3(-177.5, 0, 79.5), Vector3(-179.0, 0, 79.5)]   # на фермі біля південних воріт
var worker_bikes: Array = []


func _give_bike(w, sx: float, row: int, k: int, in_farm: Vector3) -> void:
	var bz = world.outer.bazaar
	if bz == null or not ResourceLoader.exists("res://assets/models/bicycle.glb"):
		return
	var o = world.outer
	var info: Dictionary = bz.hut_info(Vector3(sx * o.HUT_X, 0, o.HUT_Z0 + o.HUT_STEP * row))
	if info.is_empty():
		return
	var b := preload("res://scripts/bike.gd").new()
	b.name = "WorkerBike_%d" % k
	b.size = WORKER_BIKE
	b.pickable = false
	world.yard_root.add_child(b)
	if not b.setup():
		b.queue_free()
		return
	worker_bikes.append(b)
	var park := Transform3D(Basis(Vector3.UP, PI), FARM_BIKES[k])
	var at := (w.way as Array).find(in_farm)
	var tail: Array = (w.way as Array).slice(at + 1) if at >= 0 else []
	var walk: Array = [Vector3(-171.5, 0, 77.0), Vector3(-171.5, 0, 34.0)] + tail
	w.give_bike(b, info, _bike_way(sx, row), park, walk)


func _bike_way(sx: float, row: int) -> Array:
	## Велосипедом: з під'їзду на головну дорогу, повз фонтан на південь до річки,
	## дорогою понад річкою на захід — і крізь південні ворота на ферму.
	var o = world.outer
	var z: float = o.HUT_Z0 + o.HUT_STEP * row
	var pts: Array = []
	if z < o.VILLAGE.z:
		pts = [Vector3(sx * 7.5, 0, o.VILLAGE.z), Vector3(sx * 6.0, 0, o.VILLAGE.z + 5.0), Vector3(sx * 2.0, 0, o.VILLAGE.z + 9.0)]
	else:
		pts = [Vector3(sx * 2.0, 0, z + 2.5)]
	pts += [Vector3(sx * 2.0, 0, 89.5), Vector3(-5.0, 0, 94.8), Vector3(-60.0, 0, 95.0), Vector3(-120.0, 0, 95.0),
		Vector3(-165.0, 0, 95.0), Vector3(-171.5, 0, 90.5), Vector3(-171.5, 0, 85.0), Vector3(-171.5, 0, 81.0)]
	return pts


func _home_door(sx: float, row: int) -> Vector3:
	## Перед ґанком хати села (sx: −1 — захід дороги, 1 — схід; row: 0 — ближча до фонтану з півночі, 1 — південніша).
	var o = world.outer
	return Vector3(sx * (o.HUT_X - 4.2), 0, o.HUT_Z0 + o.HUT_STEP * row)


func _home_way(sx: float, row: int) -> Array:
	## Від хати: крізь хвіртку на дорогу, повз фонтан на північ, до воріт подвір'я (точка 4) і далі до ферми.
	var o = world.outer
	var z: float = o.HUT_Z0 + o.HUT_STEP * row
	var gx: float = o.HUT_X - o.YARD_GATE
	return [Vector3(sx * gx, 0, z), Vector3(sx * 7.0, 0, z), Vector3(sx * 7.0, 0, 47.0), Vector3(sx * 1.5, 0, 40.0),
		Vector3(0, 0, 12)] + FARM_WAY


# ------------------------------------------------------------------ копиця сіна на фермі (конюх привозить, Тарасик годує)
const FARM_HAY := Vector3(-179.0, 0, 31.0)
var farm_hay: Node3D
var _hay_k := 0.8


func _make_farm_hay() -> void:
	farm_hay = Node3D.new()
	farm_hay.name = "FarmHay"
	world.yard_root.add_child(farm_hay)
	farm_hay.position = FARM_HAY
	var m := Models.spawn(farm_hay, "haystack", 1.7)
	if m == null:
		farm_hay.add_child(Util.sphere(1.0, Util.mat(Color(0.86, 0.74, 0.38), 0.95), Vector3(0, 0.6, 0), Vector3(1.2, 0.9, 1.2)))
	add_farm_hay(0.0)


func add_farm_hay(d: float) -> void:
	## Скільки сіна в копиці на фермі (0.35…1.0) — видно за розміром.
	_hay_k = clampf(_hay_k + d, 0.35, 1.0)
	if farm_hay:
		farm_hay.scale = Vector3(1.0, _hay_k, 1.0) * (0.7 + 0.3 * _hay_k)


func _spawn_forest_hares() -> void:
	## Зайці живуть у грибному лісі.
	if not Models.exists("hare"):
		return
	var fc: Vector3 = world.outer.FOREST_C
	for i in 2:
		var hz = preload("res://scripts/hare.gd").new()
		world.outer.add_child(hz)
		hz.setup(fc + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)), 10.0)
		hz.who = girl
		hares.append(hz)


func _check_models() -> void:
	## Якщо якогось архіву з моделями не завантажили на GitHub — кажемо, якого саме.
	var need := {"girl": "models_3.zip", "turkey": "models_4.zip", "market": "models_5.zip", "bull": "models_6.zip", "cow": "models_11.zip", "horse": "models_11.zip", "cart": "models_11.zip", "horse2": "models_14.zip", "horse3": "models_14.zip", "horse4": "models_14.zip",
		"hare": "models_13.zip", "granny": "models_13.zip", "groom": "models_13.zip", "shepherd": "models_13.zip", "sedge": "models_13.zip", "harness": "models_13.zip",
		"bed": "models_7.zip", "kiosks": "models_9.zip", "plane_y": "models_10.zip", "tractor": "models_10.zip", "grandpa_house": "models_10.zip"}
	var miss: Array = []
	for id in need:
		if not Models.exists(id) and not (need[id] in miss):
			miss.append(need[id])
	if not miss.is_empty():
		await get_tree().create_timer(2.0).timeout
		hud.toast("Не вистачає моделей — завантаж на GitHub: " + ", ".join(miss), 8.0)


func _grandpa_talk() -> void:
	var q := Game.current_quest()
	var txt: String = "Відпочинь, онучку. Завтра буде новий день!"
	if not q.is_empty() and q.get("giver", "Дідусь Петро") == "Дідусь Петро":
		txt = q["text"]
	elif not q.is_empty():
		txt = "%s просить тебе: %s" % [q["giver"], q["short"]]
	_grandpa_dialog(txt)


func _granny_talk() -> void:
	## Розмова з бабусею: її завдання (якщо зараз воно від неї) або щось про господарство.
	if granny == null:
		return
	var q := Game.current_quest()
	var txt: String
	if not q.is_empty() and q.get("giver", "") == "Бабуся Галя":
		txt = q["text"]
	else:
		var talk := ["Сідай, онучку, поїж пиріжка. Дідусь сьогодні знову з самого ранку на ногах.",
			"Корівки в нас добрі: Зірка, Ласка, Квітка, Красуля й Мілка. Зранку доїмо — буде парне молочко.",
			"Курочки несуться, город росте, борщ на плиті — що ще треба для щастя?",
			"Як попросиш — і корову подою, і пиріжків спечу. Тільки торкнись мене."]
		txt = talk[randi() % talk.size()]
		var milk := int(Game.state.get("milk", 0))
		if milk > 0:
			txt += " А молока ми вже надоїли %d %s!" % [milk, "дійницю" if milk % 10 == 1 and milk % 100 != 11 else ("дійниці" if milk % 10 in [2, 3, 4] and not (milk % 100 in [12, 13, 14]) else "дійниць")]
	if granny.doing == "" and not granny.moving:
		granny.face(rig.cam.global_position)
	audio.play("page", -8.0)
	hud.show_dialog("Бабуся Галя", txt, _portrait("Бабуся Галя"))


func _follow_later(who: Node3D) -> void:
	## Камера йде за дідусем, поки він працює за двором.
	await get_tree().create_timer(0.3).timeout
	if Game.state["location"] != "yard":
		leave_house()
		await get_tree().create_timer(0.8).timeout
	cam_follow = who


func _spawn_farm_extras() -> void:
	var o = world.outer
	if Models.exists("tractor"):
		tractor = preload("res://scripts/tractor.gd").new()
		world.yard_root.add_child(tractor)
		tractor.setup(o.SHED, o.SHED_YAW, o.PLOW_FIELD)
		tractor.make_field(world.yard_root)
		if Models.exists("trailer"):
			trailer = preload("res://scripts/trailer.gd").new()
			world.yard_root.add_child(trailer)
			trailer.setup(o.TRAILER_PARK, o.SHED_YAW)
		_make_tractor_shed(o.SHED_ROOF)
		grandpa.tractor = tractor
	orchard = preload("res://scripts/orchard.gd").new()
	world.yard_root.add_child(orchard)
	orchard.build()
	grandpa.orchard = orchard
	_spawn_garden_cart(o.PLOW_FIELD)
	forest = preload("res://scripts/forest_goods.gd").new()
	world.yard_root.add_child(forest)
	forest.build(o.trees)
	grandpa.forest = forest
	o.apply_view_ranges(forest, 3.0, 45.0)


func _make_tractor_shed(r: Rect2) -> void:
	## Навіс для комбайна, трактора з плугом і причепа: стовпи по краях і похилий дощаний дах (нижчий ззаду, до забору).
	var n := Node3D.new()
	world.yard_root.add_child(n)
	var wood := Util.mat(Color(0.5, 0.35, 0.22), 0.9)
	var roof := Util.mat(Color(0.45, 0.4, 0.36), 0.8)
	var x0 := r.position.x                   # перед (захід, виїзд)
	var x1 := r.end.x                        # зад (схід, до забору)
	var z0 := r.position.y
	var z1 := r.end.y
	var h0 := 5.6
	var h1 := 5.0
	var hx := func(x: float) -> float: return lerpf(h0, h1, (x - x0) / (x1 - x0))
	var posts: Array = [Vector2(x0, z0), Vector2(x0, z1)]
	for k in 5:
		posts.append(Vector2(x1, lerpf(z0, z1, k / 4.0)))
	for k in range(1, 3):
		var x := lerpf(x0, x1, k / 3.0)
		posts.append(Vector2(x, z0))
		posts.append(Vector2(x, z1))
	for q in posts:
		var h: float = hx.call(q.x)
		n.add_child(Util.box(Vector3(0.24, h, 0.24), wood, Vector3(q.x, h * 0.5, q.y)))
		Obstacles.add_outer(q.x, q.y, 0.3, 2.5)
	var lz := z1 - z0
	var lx := x1 - x0
	n.add_child(Util.box(Vector3(0.24, 0.34, lz + 0.24), wood, Vector3(x0, h0 - 0.05, (z0 + z1) * 0.5)))
	n.add_child(Util.box(Vector3(0.2, 0.24, lz + 0.2), wood, Vector3(x1, h1, (z0 + z1) * 0.5)))
	var tilt := -atan((h0 - h1) / lx)
	for z in [z0, z1]:
		var bm := Util.box(Vector3(lx + 0.2, 0.2, 0.2), wood, Vector3((x0 + x1) * 0.5, (h0 + h1) * 0.5, z))
		bm.rotation.z = tilt
		n.add_child(bm)
	var cnt := int(ceil((lz + 0.8) / 0.6))
	for k in cnt:
		var pl := Util.box(Vector3(lx + 0.9, 0.06, 0.62), roof if k % 2 == 0 else wood, Vector3((x0 + x1) * 0.5, (h0 + h1) * 0.5 + 0.16, z0 - 0.4 + 0.3 + k * 0.6))
		pl.rotation.z = tilt
		n.add_child(pl)
	Obstacles.finish()


# ------------------------------------------------------------------ політ на літаку
func start_ride() -> void:
	## Beep летить на аеродром, літак виїжджає з ангара, Beep сідає в кабіну — і злітаємо.
	if riding or plane == null:
		return
	if _ctl_beep:
		stop_beep_control()
	if _ctl_girl:
		stop_girl_control(true)
	if Game.state["location"] != "yard":
		leave_house()
		await get_tree().create_timer(0.8).timeout
	riding = true
	cam_follow = null
	plane.auto_door = true
	beep.outdoors = true
	beep.say("Летимо до літака!", 2.5)
	var side: Vector3 = plane.global_position + Vector3(0, 0, 5.5)
	if plane.in_hangar:
		side = world.outer.RUNWAY_A + world.outer.AIR_X * 2.0 + world.outer.AIR_Z * 6.0
		plane.roll_out()
	var arrived := [false]
	beep.fly_to(side, func(): arrived[0] = true)
	_track = beep
	rig.glide_to(14.0, -20.0)
	var t := 0.0
	while not arrived[0] and t < 90.0:
		t += get_process_delta_time()
		await get_tree().process_frame
	while plane.state != "rest" and t < 120.0:
		t += get_process_delta_time()
		await get_tree().process_frame
	if not riding:
		return
	# у кабіну сідає Ніка (якщо її нема — Beep)
	_track = plane
	plane.say("Р-р-р-р! Мотор працює!", 2.0)
	if girl and girl.has_method("board_plane"):
		if girl.global_position.distance_to(plane.global_position) > 14.0:
			hud.fade(true)
			await get_tree().create_timer(0.45).timeout
			girl.cancel_job()
			girl.visible = true
			girl.global_position = plane.to_global(Vector3(-3.2, 0, 1.0))
			hud.fade(false)
		beep.say("Ніко, сідай за штурвал!", 2.5)
		girl.say("Лечу-у-у!", 2.0)
		await girl.board_plane(plane)
		plane.rider = girl
		beep.moving = false
		beep.fly_to(world.outer.RUNWAY_A + world.outer.AIR_X * 3.0 + world.outer.AIR_Z * 7.0)
	else:
		var from: Vector3 = beep.global_position + Vector3(0, beep.HOVER, 0)
		var k := 0.0
		beep.moving = false
		beep.piloting = true
		while k < 1.0:
			k = minf(1.0, k + get_process_delta_time() / 1.2)
			var to: Vector3 = plane.seat_global()
			var p: Vector3 = from.lerp(to, k)
			p.y += sin(k * PI) * 1.2
			beep.global_position = p
			await get_tree().process_frame
		plane.pilot = beep
		plane.rider = beep
		beep.say("Пристебнувся!", 1.5)
	_track = null
	hud.show_flight(true)
	hud.flight.home_text = "В ангар"
	hud.flight.land_text = "Сісти"
	hud.toast("Джойстик — кермо, ▲▼ — висота", 4.0)
	rig.glide_to(12.0, -12.0)
	await plane.take_off(true)


var _dbg_cam := Vector3.ZERO          # лише для перевірки: близько до літака


func _ride_cam(delta: float) -> void:
	## Камера позаду літака, трохи згори.
	plane.joy = hud.flight.joy
	plane.climb = hud.flight.climb
	rig.focus = plane.global_position + Vector3(0, 1.6, 0)
	rig.target = rig.focus
	var want := rad_to_deg(plane.rotation.y) + 180.0 + _dbg_cam.y
	if _dbg_cam.x > 0.0:
		rig.dist = _dbg_cam.x
		rig.pitch = _dbg_cam.z
		rig.yaw = want
		return
	rig.yaw += wrapf(want - rig.yaw, -180.0, 180.0) * (1.0 - exp(-delta * 2.5))
	rig.yaw = wrapf(rig.yaw, rig.yaw_center - 180.0, rig.yaw_center + 180.0)
	if rig._want_dist < 0.0:
		rig.dist = lerpf(rig.dist, 13.0, 1.0 - exp(-delta * 1.0))


func _on_plane_landed() -> void:
	if not riding:
		return
	hud.show_flight(false)
	Game.emit_event("plane_flight")
	Game.emit_event("dragon_flight")
	var was: Node3D = plane.rider
	plane.pilot = null
	plane.rider = null
	if was == girl and girl:
		await girl.leave_plane(plane)
		girl.say("Приземлились! Ох і гарно було!", 2.5)
	else:
		beep.piloting = false
		# Beep вистрибує з кабіни поруч
		var to: Vector3 = plane.global_position + plane.global_transform.basis.x * 3.0
		to.y = 0.0
		var from: Vector3 = beep.global_position
		var k := 0.0
		while k < 1.0:
			k = minf(1.0, k + get_process_delta_time() / 0.8)
			var p: Vector3 = from.lerp(to, k)
			p.y = lerpf(from.y, 0.0, k) + sin(k * PI) * 0.8
			beep.global_position = p
			await get_tree().process_frame
		beep.global_position = to
		beep.rotation = Vector3(0, beep.rotation.y, 0)
	riding = false
	beep.say("Приземлились!" if not plane.in_hangar else "Літак в ангарі!", 2.0)
	overview()


# ------------------------------------------------------------------ ручне керування трактором і возом
func vehicle_control_start(kind: String, veh: Node3D) -> void:
	## Дідусь уже сидить — гравець бере кермо: джойстик їде й повертає, «Готово» віддає кермо.
	if _ctl_girl:
		stop_girl_control(true)
	_ctl_veh = veh
	_veh_kind = kind
	cam_follow = null
	hud.show_flight(true)
	hud.flight.home_text = "Готово"
	hud.flight.land_text = ""
	if kind == "tractor":
		hud.flight.land_text = "Причепи"
		hud.toast("Джойстик — їхати й повертати, ▲ / ▼ — підняти чи опустити плуг (або кузов причепа). «Причепи» — причепити чи відчепити плуг і причіп. «Готово» — поставити трактор додому", 7.0)
	elif kind == "garden_cart":
		hud.toast("Джойстик — вести коня з возом. «Готово» — віз повернеться під садок, дідусь розпряже коня", 5.0)
	else:
		hud.toast("Джойстик — вести коня з возом. «Готово» — повернути коня в стайню", 5.0)


func vehicle_control_stop() -> void:
	if _ctl_veh == null and _veh_kind == "":
		return
	_ctl_veh = null
	_veh_kind = ""
	hud.show_flight(false)
	hud.flight.home_text = "В ангар"
	hud.flight.land_text = "Сісти"
	overview()


func _veh_cam(delta: float) -> void:
	## Керування й камера: позаду транспорту, трохи згори.
	var j: Vector2 = hud.flight.joy
	var v: Node3D = _ctl_veh
	if _veh_kind == "tractor":
		tractor.manual_step(j, hud.flight.climb, delta)
	elif v and v.has_method("manual_step"):
		v.manual_step(j, delta)
	rig.focus = v.global_position + Vector3(0, 1.2, 0)
	rig.target = rig.focus
	var moving_fast: bool = absf(float(v.get("speed"))) > 0.4
	if moving_fast:
		var want := rad_to_deg(v.rotation.y) + 180.0
		rig.yaw += wrapf(want - rig.yaw, -180.0, 180.0) * (1.0 - exp(-delta * 1.2))
		rig.yaw = wrapf(rig.yaw, rig.yaw_center - 180.0, rig.yaw_center + 180.0)
	if rig._want_dist < 0.0:
		rig.dist = lerpf(rig.dist, 9.0, 1.0 - exp(-delta * 1.0))


# ------------------------------------------------------------------ гравець водить Ніку
func _player_pos() -> Vector3:
	if riding and plane:
		return plane.global_position
	if _ctl_girl and girl:
		return girl.global_position
	return beep.global_position


var _girl_starting := false


func start_girl_control(quiet := false) -> void:
	if _ctl_girl or _girl_starting:
		return
	if girl == null:
		hud.toast("Ніки ще немає в грі (потрібен файл models_3.zip)", 4.0)
		return
	if riding or girl.on_plane:
		hud.toast("Ніка зараз у літаку", 2.5)
		return
	if _ctl_veh:
		hud.toast("Спершу натисни «Готово» — дідусь поставить транспорт", 3.0)
		return
	if _ctl_beep:
		stop_beep_control()
	if Game.state["location"] != "yard":
		_girl_starting = true
		leave_house()
		await get_tree().create_timer(0.8).timeout
		_girl_starting = false
		if _ctl_girl or riding or _ctl_beep or _ctl_veh:
			return
	if not girl.visible:
		# спала вдома — виходить на подвір'я перед хатою
		girl.position = girl.HOME_YARD
	_ctl_girl = true
	_girl_goal = Vector3.INF
	cam_follow = null
	_make_world_basket()
	_track = null
	girl.player_begin()
	rig.collide_mask = 1 << 17
	rig.keep_root = girl
	_hand_open.clear()
	Game.emit_event("girl_met")
	if not quiet:
		girl.say("Гайда гуляти!", 2.0)
	hud.nika_mode = true
	hud.show_flight(true)
	hud.flight.home_text = "Меню"
	hud.flight.land_text = ""
	hud.flight.show_down = false
	hud.flight.up_small = "бігти"
	hud.flight.up_big = "»"
	hud.show_overview_button(false)
	rig.yaw = rad_to_deg(girl.rotation.y) + 180.0
	rig.glide_to(6.0, -18.0)
	if quiet and _nika_hint_shown:
		return
	_nika_hint_shown = true
	hud.toast("Джойстик — іти (до краю — бігти). Торкнись землі чи мапи — Ніка піде туди. Торкнись коня, велосипеда, трактора чи комбайна — сяде й поїде (у кожного своє «Меню»). Торкнись їжі, кухля, лопати — візьме. По гриби — спершу візьми кошик («Меню»). Пальцем по екрану — оглядатися", 7.0)


var _nika_hint_shown := false


func _show_nika_menu() -> void:
	## Власне меню Ніки (кнопка «Меню» або торкнутися самої Ніки).
	if _mount_state != "":
		hud.toast("Спершу злізь — кнопка «Злізти»", 2.5)
		return
	if _acting != "":
		hud.toast("Рушиш джойстиком — і Ніка встане", 2.5)
		return
	# у Ніки — лише власні справи; куди піти — джойстиком чи торкнувшись землі, на чому поїхати — торкнись того
	var holding: bool = girl.held != null
	var flags := {
		"nk_basket_take": not girl.has_basket(), "nk_basket_put": girl.has_basket(),
		"nk_put": holding, "nk_eat": holding and String(girl.item_kind) in Util.FOOD,
		"nk_horse": _near_saddle_horse() != null,
		"nk_jump": hero == "girl",
	}
	hud.show_nika_menu(flags)


func _nika_walk(route: Array, say_text: String) -> void:
	_meet = null
	_furn = null
	_girl_stuck = 0.0
	_goal_route = route
	_girl_goal = _goal_route.pop_front()
	girl.say(say_text, 2.0)


func _nika_do(what: String) -> void:
	if girl == null or not _ctl_girl or _mount_state != "" or _acting != "":
		return
	match what:
		"nk_basket_take":
			_make_world_basket()
			if _basket_world == null or not is_instance_valid(_basket_world):
				return
			if girl.global_position.distance_to(_basket_world.global_position) > 160.0:
				girl.say("Кошик далеко — лишився біля хати.", 2.5)
				return
			_meet_begin("nk_basket", _basket_world, _basket_world.get_node_or_null("Pick") as Area3D)
			girl.say("Іду по кошик!", 1.8)
		"nk_basket_put":
			_basket_world = girl.put_basket()
			girl.say("Поставлю кошик тут.", 1.8)
		"nk_put":
			girl.put_item()
		"nk_eat":
			girl.eat_held()
		"nk_forest":
			var r := _girl_route_to(Vector3(0, 0, 9.0))
			for q in world.outer.EAST_ROAD:
				r.append(Vector3(q.x, 0, q.y))
			_nika_walk(r, "Іду в ліс по гриби та ягоди!")
		"nk_home":
			_nika_walk(_girl_route_to(girl.HOME_GATE) + [girl.HOME_YARD], "Іду додому!")
		"nk_bazaar":
			var r2 := _girl_route_to(Vector3(-5.0, 0, 70.0))
			for q in girl.BAZAAR_WAY.slice(1):
				r2.append(q)
			r2.append(girl.BAZAAR_SPOTS[4])
			_nika_walk(r2, "Іду на базар!")
		"nk_grandpa":
			if grandpa:
				_meet_begin("grandpa", grandpa, grandpa.area)
				girl.say("Іду до дідуся!", 2.0)
		"nk_granny":
			if granny:
				_meet_begin("granny", granny, granny.area)
				girl.say("Іду до бабусі!", 2.0)
		"nk_bike":
			start_mount("bike", bike)
		"nk_horse":
			var hh = _near_saddle_horse()
			if hh == null:
				girl.say("Немає осідланого коника…", 2.0)
			elif girl.held != null:
				girl.put_item()
				start_mount("horse", hh)
			else:
				start_mount("horse", hh)
		"nk_combine":
			start_mount("combine", combine)
		"nk_tractor":
			start_mount("tractor", tractor)
		"nk_jump":
			_girl_goal = Vector3.INF
			_goal_route = []
			girl.play("jump")
			_gesture_t = girl.anim_length("jump")
			girl.say(["Гоп-гоп!", "Ура-а!", "Я стрибаю!"][randi() % 3], 1.6)
		"nk_beep":
			beep.fly_to(girl.global_position + Vector3(1.0, 0, 1.0))
			hud.show_beep_menu(true, Game.is_night(), beep.lamp.visible, grandpa.at_home)


func stop_girl_control(quiet := false) -> void:
	if not _ctl_girl:
		return
	hud.nika_mode = false
	rig.pitch_max = -8.0
	_mount_force_off()
	_door_left = 0.0
	_ctl_girl = false
	rig.collide_mask = 0
	_hand_open.clear()
	_girl_goal = Vector3.INF
	_goal_route = []
	_meet = null
	_gesture_t = 0.0
	if girl.has_basket():
		_basket_world = girl.put_basket()             # кошик лишається там, де Ніка стояла
	if girl.held:
		girl.put_item()
	_furn = null
	_acting = ""
	girl.player_end()
	if _cam_b != null:
		_cam_b = null
		rig.dist_min = _dmin_out
		rig.dist_max = _dmax_out
	if world.outer.bazaar:
		world.outer.bazaar.set_inside(null)
	world.in_building = false
	rig.inside_box = AABB()
	hud.show_flight(false)
	hud.flight.home_text = "В ангар"
	hud.flight.land_text = "Сісти"
	hud.flight.show_down = true
	hud.flight.up_small = "вгору"
	hud.flight.up_big = "▲"
	if quiet:
		return
	beep.fly_to(girl.global_position + Vector3(1.2, 0, 1.2))
	overview()


func _girl_cam(delta: float) -> void:
	## Керування Нікою: джойстик — відносно камери; камера — позаду, у будівлі — зсередини.
	if _mount_state != "":
		_mount_cam(delta)
		return
	if _threshold:
		_girl_follow(delta, null, false)          # переступає поріг дідової хати сама
		return
	var j: Vector2 = hud.flight.joy
	var run: bool = hud.flight.climb > 0.0
	var yr := deg_to_rad(rig.yaw)
	var fwd := -Vector3(sin(yr), 0, cos(yr))
	var right := Vector3(cos(yr), 0, -sin(yr))
	var mv := right * j.x + fwd * j.y
	var bz = world.outer.bazaar
	if _acting != "":
		# сидить / лежить / п'є — рушиш джойстиком, і Ніка встає
		girl.act_step(delta)
		if _acting != "ending" and (mv.length() > 0.3 or run):
			_act_stop()
		_girl_follow(delta, bz.building_at(girl.global_position) if bz else null, false)
		return
	if _gesture_t > 0.0:
		_gesture_t -= delta
		if mv.length() < 0.1 and not run:
			_girl_follow(delta, bz.building_at(girl.global_position) if bz else null, false)
			return
		_gesture_t = 0.0
		if _pressing:
			girl._keys_abort = true
	if mv.length() > 0.1:
		_girl_goal = Vector3.INF
		_goal_route = []
		_furn = null
		_meet = null
		_house_go = false
		if j.length() > 0.93:
			run = true                       # джойстик до краю — Ніка біжить сама (без кнопки)
	elif _girl_goal != Vector3.INF:
		var to: Vector3 = _girl_goal - girl.global_position
		to.y = 0.0
		var near_r := 0.35
		if _meet != null and _goal_route.is_empty():
			near_r = float(_meet["r"]) + 0.15
		if to.length() < near_r:
			_girl_goal = Vector3.INF
			mv = Vector3.ZERO
			if not _goal_route.is_empty():
				_girl_goal = _goal_route.pop_front()       # далі — наступна точка шляху (хвіртка, міст…)
			elif _house_go:
				_house_go = false
				_nika_enter_house()
				return
			elif _meet != null:
				_meet_arrive()
			elif _furn != null:
				_act_start()
				return
		else:
			mv = _detour(to.normalized()) * clampf(to.length(), 0.45, 1.0)
			run = to.length() > 14.0
	if _hand_door_busy(delta, mv.normalized() if mv.length() > 0.2 else Vector3.ZERO):
		_girl_follow(delta, bz.building_at(girl.global_position) if bz else null, false)
		return
	var gp0: Vector3 = girl.global_position
	var moved: float = girl.player_step(mv, run, delta)
	if Game.state["location"] == "yard":
		var gk: Vector3 = world.outer.hangar_keep(gp0, girl.global_position)
		if gk != girl.global_position:
			girl.global_position = gk                 # зачинені ворота ангара (і стіни) — не крізь них
			moved = 0.0
	if Game.state["location"] == "room":
		_room_keep_in()
	elif not _door_busy and mv.length() > 0.3 and _girl_goal == Vector3.INF and world.portal_shift != Vector3.ZERO:
		# дійшла до відчинених дверей дідової хати й іде далі — заходить сама, як у хати на базарі
		var dsp: Vector3 = world.spots["door"]
		var gq: Vector3 = girl.global_position
		if absf(gq.x - dsp.x) < 0.6 and gq.z < dsp.z + 0.5 and gq.z > dsp.z - 1.0 and mv.normalized().z < -0.6 \
				and world.door_open_k("house") > 0.6:
			_nika_enter_house()
			return
	if _girl_goal != Vector3.INF:
		_detour_update(moved, delta)
		if moved < 0.25 * delta:
			_girl_stuck += delta
			if _girl_stuck > (1.2 if _furn != null else 4.0):
				_girl_goal = Vector3.INF          # уперлася в стіну — зупиняється
				_girl_stuck = 0.0
				_goal_route = []
				if _meet != null:
					_meet_arrive()            # не дійшла впритул (паркан, стіл) — вітається звідси
				if _furn != null:
					var sp: Vector3 = _furn["spot"]
					if Vector2(sp.x - girl.global_position.x, sp.z - girl.global_position.z).length() < 1.4:
						_act_start()          # майже дійшла (стіл заважає) — сідає звідси
						return
					_furn = null
		else:
			_girl_stuck = 0.0
	var b = bz.building_at(girl.global_position) if bz else null
	_girl_follow(delta, b, mv.length() > 0.3 and j.y > 0.25 or _girl_goal != Vector3.INF)
	if bz:
		_shop_check(delta, mv.length() > 0.1 or _girl_goal != Vector3.INF)
		bz.food_refill(delta, girl.global_position)


func _girl_follow(delta: float, b, turning: bool) -> void:
	## Камера за Нікою. Надворі — позаду й трохи згори; у хаті, ларьку чи церкві — зсередини,
	## низько за плечем (дах і стеля лишаються, камера не виходить за стіни).
	var bz = world.outer.bazaar
	if bz:
		bz.set_inside(b)
	world.in_building = b != null
	var lying: bool = _acting == "lie" or girl.rotation.x < -0.3
	var inside_any: bool = b != null or Game.state["location"] == "room"
	rig.focus = girl.to_global(Vector3(0, 0.4, 0)) + Vector3(0, 0.6, 0) if lying else girl.global_position + Vector3(0, 0.8 if inside_any else 1.1, 0)
	rig.target = rig.target.lerp(rig.focus, 1.0 - exp(-delta * 10.0))
	var k := 1.0 - exp(-delta * 2.5)
	if b != _cam_b:
		if _cam_b == null:
			_dmin_out = rig.dist_min
			_dmax_out = rig.dist_max
		_cam_b = b
		if b != null:
			rig.dist_min = 1.6                 # не впритул — щоб було видно всю Ніку, а не саму голову
			rig.dist_max = 6.0 if b["kind"] == "church" else 4.0
			rig.dist = minf(rig.dist, rig.dist_max)
			var wb: AABB = bz.world_box(b)
			wb = wb.grow(-0.3)
			var top := maxf(wb.end.y - 0.6, wb.position.y + 1.9)    # нижче сволоків і стелі
			wb.position.y = -2.0
			wb.size.y = top + 2.0
			rig.inside_box = wb
		else:
			rig.dist_min = _dmin_out
			rig.dist_max = _dmax_out
			rig.inside_box = AABB()
	# оглядатися: у хаті, сараї чи надворі — потягни пальцем, і камера лишиться там, куди повернув
	var look: bool = rig.looking()
	rig.pitch_max = 25.0 if inside_any or _acting != "" else -8.0
	if _acting != _cam_act:
		_cam_act = _acting
		if _acting != "" and not look:
			rig.glide_to(1.7 if lying else 2.6, -38.0 if lying else -16.0)
	if inside_any and not look and _acting == "":
		# у хаті камера трохи далі й вище — видно всю Ніку й кімнату, а не саму спину впритул
		rig.pitch = lerpf(rig.pitch, -38.0 if lying else -26.0, k)
		rig.dist = lerpf(rig.dist, 1.7 if lying else ({"church": 4.5, "stall": 2.2, "shed": 3.8}.get(b["kind"], 3.2) if b != null else 2.4), k)
	elif not inside_any and not look and (rig.pitch < -40.0 or rig.dist < 3.0) and _acting == "":
		rig.pitch = lerpf(rig.pitch, -20.0, k)
		rig.dist = lerpf(rig.dist, 6.0, k)
	if turning and not look:
		var want := rad_to_deg(girl.rotation.y) + 180.0
		rig.yaw += wrapf(want - rig.yaw, -180.0, 180.0) * (1.0 - exp(-delta * (2.2 if b != null else 1.3)))
	rig.yaw = wrapf(rig.yaw, rig.yaw_center - 180.0, rig.yaw_center + 180.0)


func _furn_go(area: Area3D) -> void:
	## Торкнулась стільця, лави, ліжка чи столу — Ніка йде туди.
	var mi := area.get_parent() as Node3D
	var ab: AABB = area.get_meta("box")
	var c: Vector3 = mi.global_transform * ab.get_center()
	var gp: Vector3 = girl.global_position
	var away := Vector3(gp.x - c.x, 0, gp.z - c.z)
	if away.length() < 0.05:
		away = Vector3(0, 0, 1)
	var half := maxf(ab.size.x, ab.size.z) * 0.5 if String(area.get_meta("act")) != "sit" else 0.25
	var spot := c + away.normalized() * (half + 0.4)
	spot.y = 0.0
	if String(area.get_meta("act")) == "sit":
		var bz = world.outer.bazaar
		spot = _seat_plan(area, gp, bz.building_at(c) if bz else null)["spot"]
	_furn = {"act": String(area.get_meta("act")), "area": area, "spot": spot, "c": c}
	_girl_goal = spot
	_girl_stuck = 0.0


func _sit_snack() -> void:
	## Сіла до столу — бере зі столу щось поїсти чи попити (кухоль, яблуко, булочку, пиріжок) і їсть.
	await get_tree().create_timer(1.8).timeout
	if _acting != "sit" or girl == null or girl.held != null:
		return
	var bz = world.outer.bazaar
	if bz == null or not ("table_items" in bz):
		return
	var gp: Vector3 = girl.global_position
	var best: Node3D = null
	var bd := 1.1
	for e in bz.table_items:
		var n = e["node"]
		if n == null or not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
			continue
		var d := Vector2((n as Node3D).global_position.x - gp.x, (n as Node3D).global_position.z - gp.z).length()
		if d < bd:
			bd = d
			best = n
	if best == null:
		return
	await girl.take_item(best, String(best.get_meta("item_kind", "")))
	if _acting != "sit" or girl.held == null:
		return
	await girl.eat_held()


func _seat_plan(area: Area3D, from: Vector3, b) -> Dictionary:
	## Де й як сісти: на край сидіння ближче до столу (чи від спинки), обличчям до столу; і звідки підійти — збоку, не крізь стіл.
	var bz = world.outer.bazaar
	var mi := area.get_parent() as Node3D
	var ab: AABB = area.get_meta("box")
	var xf := mi.global_transform
	var c: Vector3 = xf * ab.get_center()
	var lc := xf.affine_inverse() * from
	var sp := ab.get_center()
	if ab.size.x > 0.8:
		sp.x = clampf(lc.x, ab.position.x + 0.25, ab.end.x - 0.25)
	if ab.size.z > 0.8:
		sp.z = clampf(lc.z, ab.position.z + 0.25, ab.end.z - 0.25)
	var floor_y: float = (xf * ab.position).y
	# довга лава зі спинкою (як у церкві): поперек лави шукаємо сидіння й спинку
	var pew_face := Vector3.ZERO
	var long_x := ab.size.x >= ab.size.z
	if maxf(ab.size.x, ab.size.z) > 1.2 and minf(ab.size.x, ab.size.z) <= 1.0:
		if long_x:
			sp.x = clampf(lc.x, ab.position.x + 0.45, ab.end.x - 0.45)     # не на бокову стінку лави
		else:
			sp.z = clampf(lc.z, ab.position.z + 0.45, ab.end.z - 0.45)
		var seat_t := 0.0
		var seat_n := 0
		var back_t := 0.0
		var back_n := 0
		for i in 13:
			var t := float(i) / 12.0
			var lp := sp
			if long_x:
				lp.z = lerpf(ab.position.z + 0.02, ab.end.z - 0.02, t)
			else:
				lp.x = lerpf(ab.position.x + 0.02, ab.end.x - 0.02, t)
			var h := _mesh_top_at([mi], xf * lp, floor_y + 2.0) - floor_y
			if h > 0.25 and h < 0.7:
				seat_t += t
				seat_n += 1
			elif h >= 0.7 and h < 2.0:
				back_t += t
				back_n += 1
		if seat_n > 0 and back_n > 0:
			seat_t /= seat_n
			back_t /= back_n
			var ax := Vector3(0, 0, 1) if long_x else Vector3(1, 0, 0)
			if long_x:
				sp.z = lerpf(ab.position.z, ab.end.z, seat_t)
			else:
				sp.x = lerpf(ab.position.x, ab.end.x, seat_t)
			pew_face = xf.basis * (ax * signf(seat_t - back_t))       # спиною до спинки
	if area.has_meta("edge"):
		var cc := ab.get_center()
		if long_x:
			sp.x = ab.position.x + 0.4 if lc.x < cc.x else ab.end.x - 0.4
		else:
			sp.z = ab.position.z + 0.4 if lc.z < cc.z else ab.end.z - 0.4
	if area.has_meta("seat"):
		sp = area.get_meta("seat")
	var seat_c: Vector3 = xf * sp
	var seat_y := -INF
	for o in [Vector3.ZERO, Vector3(0.09, 0, 0), Vector3(-0.09, 0, 0), Vector3(0, 0, 0.09), Vector3(0, 0, -0.09)]:
		seat_y = maxf(seat_y, _mesh_top_at([mi], seat_c + o, floor_y + 0.75))      # між дощечками лави — не провалюється
	if seat_y == -INF:
		seat_y = floor_y + minf(ab.size.y, 0.46)
	var backrest := _mesh_centroid_above(mi, seat_y + 0.18)
	var tb: Node3D = bz.table_of(b) if bz and b else null
	var near_t: bool = tb != null and tb.global_position.distance_to(c) < 1.6
	var look: Vector3 = tb.global_position if near_t else (bz.building_center(b) if bz and b else from)
	var face := look - seat_c
	if backrest != Vector3.INF and Vector2(backrest.x - seat_c.x, backrest.z - seat_c.z).length() > 0.05:
		face = seat_c - backrest                          # спинкою стільця — до спини
	elif near_t:
		# лава без спинки біля столу — обличчям до столу (уздовж короткої осі лави)
		var ax := xf.basis.x.normalized() if ab.size.x <= ab.size.z else xf.basis.z.normalized()
		face = ax * signf(ax.dot(look - seat_c) + 0.0001)
	if b and b["kind"] == "church" and backrest == Vector3.INF:
		face = (b["node"] as Node3D).global_transform.basis * Vector3(0, 0, -1)    # на лаві в церкві — обличчям до іконостасу
	if area.has_meta("face"):
		face = area.get_meta("face")
	if pew_face != Vector3.ZERO:
		face = pew_face
	var f := Vector3(face.x, 0, face.z)
	f = f.normalized() if f.length() > 0.001 else Vector3(0, 0, 1)
	# глибина сидіння вздовж погляду — сідає на передній край (ближче до столу), а не вглиб, у спинку
	var lf := xf.basis.orthonormalized().inverse() * f
	var depth := absf(lf.x) * ab.size.x * xf.basis.x.length() + absf(lf.z) * ab.size.z * xf.basis.z.length()
	depth = minf(depth, 0.6) if ab.size.x <= 0.8 or ab.size.z <= 0.8 else 0.4
	if pew_face == Vector3.ZERO and not area.has_meta("seat"):
		seat_c += f * maxf(depth * 0.5 - 0.1, 0.03)
	# звідки підійти: перед сидінням, а коли попереду стіл — збоку, з того боку, де Ніка
	var side := Vector3(f.z, 0, -f.x)
	if side.dot(from - seat_c) < 0.0:
		side = -side
	var half_w := 0.25 if ab.size.x > 0.8 or ab.size.z > 0.8 else maxf(ab.size.x, ab.size.z) * 0.5
	var spot := seat_c + side * (half_w + 0.35) if near_t else seat_c + f * 0.5
	spot.y = 0.0
	return {"seat": seat_c, "y": seat_y, "face": face, "spot": spot}


func _act_start() -> void:
	var f: Dictionary = _furn
	_furn = null
	var bz = world.outer.bazaar
	var b = bz.building_at(girl.global_position) if bz else null
	if b == null:
		b = bz.building_at(f["c"]) if bz else null
	var area: Area3D = f["area"]
	var mi := area.get_parent() as Node3D
	var ab: AABB = area.get_meta("box")
	var c: Vector3 = f["c"]
	var back: Vector3 = girl.global_position
	var at := Vector3(c.x, back.y, c.z)
	var face := Vector3.ZERO
	var extra := {}
	var xf := mi.global_transform
	match String(f["act"]):
		"sit":
			var sp: Dictionary = _seat_plan(area, back, b)
			face = sp["face"]
			at = Vector3((sp["seat"] as Vector3).x, back.y, (sp["seat"] as Vector3).z)
			extra["seat_y"] = sp["y"]
		"drink":
			at = back
			face = c - back
		"lie":
			# ліжко: довга вісь, де подушка (вищий кінець постелі), висота матраца
			var long_ax := Vector3(0, 0, 1) if ab.size.z >= ab.size.x else Vector3(1, 0, 0)
			var short_ax := Vector3(1, 0, 0) if ab.size.z >= ab.size.x else Vector3(0, 0, 1)
			var half := (ab.size.z if ab.size.z >= ab.size.x else ab.size.x) * 0.5
			var halfw := (ab.size.x if ab.size.z >= ab.size.x else ab.size.z) * 0.5
			# усе, що лежить на ліжку: постіль, подушки, складені ковдри
			var mis: Array = [mi]
			var bed_box: AABB = (xf * ab).grow(0.05)
			for sib in mi.get_parent().get_children():
				var sm := sib as MeshInstance3D
				if sm == null or sm == mi or sm.mesh == null or not sm.visible:
					continue
				var sn := String(sm.name)
				if sn.contains("Інтер'єр") or sn.contains("Дах") or sn.contains("Стін") or sn.contains("Підлог") \
						or sn.contains("Піч") or sn.contains("Стел") or sn.contains("Вікн") or sn.contains("Двер") or sn.contains("Черепиц"):
					continue
				var sb: AABB = sm.global_transform * sm.get_aabb()
				if sb.size.x < 3.0 and sb.size.z < 3.0 and sb.intersects(bed_box):
					mis.append(sm)
			var cc: Vector3 = xf * ab.get_center()
			var e1: Vector3 = xf * (ab.get_center() + long_ax * (half - 0.32))
			var e2: Vector3 = xf * (ab.get_center() - long_ax * (half - 0.32))
			var ymax: float = (xf * ab.position).y + 1.3
			var top := _mesh_top_at(mis, cc, ymax)
			var t1 := _mesh_top_at(mis, e1, ymax)
			var t2 := _mesh_top_at(mis, e2, ymax)
			if top == -INF:
				top = (xf * Vector3(0, ab.end.y, 0)).y - 0.35
			var head := e1
			if absf(t1 - t2) > 0.03 and t1 != -INF and t2 != -INF:
				head = e1 if t1 > t2 else e2                   # подушка вища за ковдру
			else:
				var mid: Vector3 = bz.building_center(b) if b else back
				head = e1 if e1.distance_to(mid) > e2.distance_to(mid) else e2
			var u := cc - head
			u.y = 0.0
			u = u.normalized()
			var w := (xf.basis * short_ax)
			w.y = 0.0
			w = w.normalized()
			if w.dot(back - cc) < 0.0:
				w = -w                                        # сідає на той край, з якого підійшла
			var wlen := halfw * xf.basis.get_scale().x
			var side := cc + w * maxf(0.12, wlen - 0.16) - u * 0.1
			var root := head + u * 0.98                       # голова — на краю подушки, а не в ній
			for i in 4:
				var q := head.lerp(root, 0.55 + 0.15 * i)    # тулуб і ноги — без подушок, щоб не висіла над ліжком
				top = maxf(top, _mesh_top_at(mis, q, ymax))   # лягає поверх ковдри, а не в неї
			top = minf(top, (xf * ab.position).y + float(area.get_meta("top_max", 0.72)))    # не вище матраца (піч чи стеля поруч — не «постіль»)
			root.y = top + 0.1
			var pil := _mesh_top_at(mis, head.lerp(root, 0.12), ymax)
			var hl := clampf(atan2(pil - top - 0.04, 0.45), 0.0, 0.6) if pil != -INF else 0.0   # голова й плечі — на подушці
			extra = {"top_y": top, "side": side, "out_yaw": atan2(w.x, w.z), "lie_yaw": atan2(u.x, u.z), "root": root, "head_lean": hl}
			face = w
	face.y = 0.0
	_acting = String(f["act"])
	girl.act_begin(_acting, at, face, back, extra)
	if _acting == "sit":
		_sit_snack()


func _mesh_top_at(mis: Array, p: Vector3, ymax: float) -> float:
	## Найвища поверхня меблів (сидіння, матрац) просто над точкою p, нижча за ymax.
	var best := -INF
	for m in mis:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var tris: PackedVector3Array = mi.mesh.get_faces()
		var xf := mi.global_transform
		for i in range(0, tris.size() - 2, 3):
			var a: Vector3 = xf * tris[i]
			var bb: Vector3 = xf * tris[i + 1]
			var cc: Vector3 = xf * tris[i + 2]
			var d := (bb.x - a.x) * (cc.z - a.z) - (cc.x - a.x) * (bb.z - a.z)
			if absf(d) < 1e-6:
				continue
			var l1 := ((bb.x - p.x) * (cc.z - p.z) - (cc.x - p.x) * (bb.z - p.z)) / d
			var l2 := ((cc.x - p.x) * (a.z - p.z) - (a.x - p.x) * (cc.z - p.z)) / d
			var l3 := 1.0 - l1 - l2
			if l1 < -0.001 or l2 < -0.001 or l3 < -0.001:
				continue
			var y := a.y * l1 + bb.y * l2 + cc.y * l3
			if y < ymax and y > best:
				best = y
	return best


func _mesh_centroid_above(mi: MeshInstance3D, y0: float) -> Vector3:
	## Середина всього, що вище y0 (спинка стільця). INF — нема.
	var tris: PackedVector3Array = mi.mesh.get_faces()
	var xf := mi.global_transform
	var sum := Vector3.ZERO
	var n := 0
	for v in tris:
		var g: Vector3 = xf * v
		if g.y > y0:
			sum += g
			n += 1
	return sum / n if n > 0 else Vector3.INF


func _act_stop() -> void:
	_acting = "ending"
	await girl.act_end()
	_acting = ""


# ------------------------------------------------------------------ ручне керування Beep
func start_beep_control() -> void:
	if riding:
		return
	if _ctl_girl:
		stop_girl_control(true)
	if Game.state["location"] != "yard":
		leave_house()
		await get_tree().create_timer(0.6).timeout
	_ctl_beep = true
	beep.moving = false
	cam_follow = null
	hud.show_flight(true)
	hud.flight.home_text = "Готово"
	hud.flight.land_text = "На землю"
	hud.toast("Джойстик — куди летіти, ▲▼ — вище й нижче. «Готово» — Beep знову сам", 4.5)


func stop_beep_control() -> void:
	_ctl_beep = false
	hud.show_flight(false)
	beep.drive(Vector2.ZERO, 0.0, 0.0)
	beep._lift_want = 0.0
	overview()


func _beep_cam(delta: float) -> void:
	var j: Vector2 = hud.flight.joy
	beep.drive(j, hud.flight.climb, delta, rig.yaw)
	rig.focus = beep.global_position + Vector3(0, 0.6 + beep.lift, 0)
	rig.target = rig.focus
	if j.length() > 0.2:
		var want := rad_to_deg(beep.rotation.y) + 180.0
		rig.yaw += wrapf(want - rig.yaw, -180.0, 180.0) * (1.0 - exp(-delta * 0.8))
		rig.yaw = wrapf(rig.yaw, rig.yaw_center - 180.0, rig.yaw_center + 180.0)


func _on_seed(left: int) -> void:
	audio.play("magic_bells", -2.0, 1.2)
	audio.play("coins", -8.0)
	if left > 0:
		hud.toast("Золота насінинка!  Залишилось: %d" % left, 2.5)
		beep.say(["Є!", "Ура, ще одна!", "Ловимо!", "Яка блискуча!"][randi() % 4], 1.5)
	else:
		hud.toast("Усі золоті насінинки зібрано!", 4.0)
		beep.say("Усі! Летимо до дідуся!", 3.0)
		_make_gold_flower(true)


func _make_gold_flower(grow: bool) -> void:
	## Чарівний соняшник біля хати — нагорода за всі насінинки.
	if gold_flower:
		return
	gold_flower = Node3D.new()
	gold_flower.position = GOLD_FLOWER_POS
	world.yard_root.add_child(gold_flower)
	var stem := Util.mat(Color(0.35, 0.6, 0.2), 0.7)
	gold_flower.add_child(Util.cyl(0.05, 0.07, 2.4, stem, Vector3(0, 1.2, 0)))
	for k in 4:
		var leaf := Util.sphere(0.25, stem, Vector3(0.22 if k % 2 == 0 else -0.22, 0.6 + k * 0.4, 0), Vector3(1.3, 0.12, 0.6))
		leaf.rotation.z = 0.5 if k % 2 == 0 else -0.5
		gold_flower.add_child(leaf)
	var head := Node3D.new()
	head.position = Vector3(0, 2.45, 0.08)
	head.rotation.x = deg_to_rad(-18)
	gold_flower.add_child(head)
	var petal := Util.mat(Color(1.0, 0.8, 0.15), 0.35, 0.3, Color(1.0, 0.7, 0.1), 1.2)
	for k in 20:
		var a := TAU * k / 20.0
		var pt := Util.sphere(0.2, petal, Vector3(cos(a) * 0.42, sin(a) * 0.42, 0), Vector3(0.45, 1.0, 0.12))
		pt.rotation.z = a - PI / 2.0
		head.add_child(pt)
	head.add_child(Util.cyl(0.32, 0.32, 0.12, Util.mat(Color(0.4, 0.25, 0.08), 0.8, 0.0, Color(0.5, 0.3, 0.05), 0.4), Vector3(0, 0, 0.03), Vector3(PI / 2, 0, 0)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.4)
	l.light_energy = 1.4
	l.omni_range = 6.0
	l.position = Vector3(0, 2.5, 0.6)
	gold_flower.add_child(l)
	gold_flower.add_child(Util.pick_area("gold_flower", Vector3(1.2, 3.0, 1.2), Vector3(0, 1.5, 0)))
	if grow:
		gold_flower.scale = Vector3(0.05, 0.05, 0.05)
		create_tween().tween_property(gold_flower, "scale", Vector3.ONE, 6.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(2.0)


func focus_on(n: Node3D, kind: String) -> void:
	## Торкнулися персонажа чи предмета — камера підлітає й стежить за ним.
	if n == null or not FOCUS.has(kind):
		return
	if kind == "beep":
		cam_follow = null
	else:
		cam_follow = n
	var f: Array = FOCUS[kind]
	_cam_up = float(f[2])
	rig.glide_to(float(f[0]), float(f[1]))
	if n.has_meta("view_from"):
		# продавці стоять за прилавком — дивимося з боку покупця
		var vf: Vector3 = n.get_meta("view_from")
		rig.yaw = rad_to_deg(atan2(vf.x, vf.z))
	if hud:
		hud.show_overview_button(cam_follow != null)


func overview() -> void:
	## Загальний огляд: камера відлітає вгору й показує все довкола Beep (у хаті — усю кімнату).
	cam_follow = null
	if Game.state["location"] == "room":
		rig.focus = world.ROOM + Vector3(0, 1.25, 0.2)
		rig.yaw = 20.0
		rig.glide_to(2.3, -16.0)
		if hud:
			hud.show_overview_button(false)
		return
	_cam_up = 0.8
	rig.glide_to(15.0, -34.0)
	if hud:
		hud.show_overview_button(false)


# ------------------------------------------------------------------ Beep заходить у хату й виходить через двері
var _door_busy := false


func _nika_house_go() -> void:
	## Ніка йде до дверей дідової хати й заходить (як у всі інші будівлі).
	if Game.state["location"] == "room" or _door_busy:
		return
	_furn = null
	_meet = null
	_goal_route = []
	_girl_goal = (world.spots["door"] as Vector3) + Vector3(0, 0, 0.75)
	_girl_stuck = 0.0
	_house_go = true


func _nika_put(p: Vector3, yaw: float) -> void:
	girl.global_position = p
	girl.rotation = Vector3(0, yaw, 0)
	girl._pl_y = p.y
	if girl._pl_body:
		girl._pl_body.global_position = Vector3(p.x, 0, p.z)
	rig.focus = p + Vector3(0, 0.8, 0)
	rig.target = rig.focus
	rig.yaw = rad_to_deg(yaw) + 180.0
	rig.yaw_center = rig.yaw


var _threshold := false            # Ніка саме переступає поріг дідової хати (іде сама, без джойстика)


func _nika_stride(to: Vector3, secs: float) -> void:
	## Ніка рівно йде до точки (крізь двері хати).
	girl.play("walk")
	var tw := create_tween()
	tw.tween_property(girl, "global_position", to, maxf(secs, girl.global_position.distance_to(to) / 1.6))
	await tw.finished
	girl.play("idle")


func _nika_enter_house() -> void:
	if _door_busy or Game.state["location"] == "room":
		return
	_door_busy = true
	var sp: Dictionary = world.spots
	girl.rotation.y = PI                            # обличчям до дверей
	if world.door_open_k("house") < 0.6:
		_door_fire = -1.0
		_door_left = girl.open_door_hand(sp["door"])     # сама тягне за ручку
		world.set_door("house", true)
		await get_tree().create_timer(0.6).timeout
	if world.portal_shift != Vector3.ZERO:
		# крізь відчинені двері видно кімнату — Ніка заходить, і з того боку вона вже в кімнаті
		var pd: Vector3 = world.portal_door
		_threshold = true
		girl.rotation.y = PI
		await _nika_stride(Vector3(pd.x, girl.global_position.y, pd.z - 0.3), 0.6)
		go_to("room", false, true)
		world.set_door("room", true, 0.05)
		world.set_door("house", false, 0.3)
		_nika_put(girl.global_position + world.portal_shift, PI)
		rig.setup(girl.global_position + Vector3(0, 0.8, 0), rig.yaw, -20.0, 2.0, 1.1, 2.6, 400.0, -70.0, 25.0)
		await _nika_stride(girl.global_position + Vector3(0, 0, -1.1), 0.9)
		_threshold = false
		world.set_door("room", false)
		_door_busy = false
		return
	go_to("room", false, true)
	world.set_door("house", false, 0.3)
	var rd: Vector3 = sp["room_door"]
	var inward: Vector3 = world.ROOM - rd
	inward.y = 0.0
	inward = inward.normalized()
	world.set_door("room", true, 0.05)
	_nika_put(rd + inward * 0.75, atan2(inward.x, inward.z))
	rig.setup(girl.global_position + Vector3(0, 0.8, 0), rig.yaw, -20.0, 2.0, 1.1, 2.6, 400.0, -70.0, 25.0)
	await get_tree().create_timer(0.7).timeout
	world.set_door("room", false)
	_door_busy = false


func _nika_house_leave() -> void:
	if _door_busy or Game.state["location"] != "room":
		return
	_door_busy = true
	var sp: Dictionary = world.spots
	world.set_door("room", true)
	await get_tree().create_timer(0.5).timeout
	if world.portal_shift != Vector3.ZERO:
		# крізь відчинені двері видно подвір'я — Ніка виходить, і з того боку вона вже надворі
		var rp: Vector3 = world.portal_door + world.portal_shift
		_threshold = true
		girl.rotation.y = 0.0
		await _nika_stride(Vector3(rp.x, girl.global_position.y, rp.z + 0.3), 0.6)
		go_to("yard", false, true)
		world.set_door("house", true, 0.05)
		world.set_door("room", false, 0.3)
		_nika_put(girl.global_position - world.portal_shift, 0.0)
		rig.setup(girl.global_position + Vector3(0, 1.1, 0), 180.0, -20.0, 5.0, 3.0, 26.0)
		var dout: Vector3 = sp["door"]
		await _nika_stride(Vector3(dout.x, girl.global_position.y, dout.z + 0.9), 0.9)
		_threshold = false
		world.set_door("house", false)
		_door_busy = false
		return
	go_to("yard", false, true)
	world.set_door("room", false, 0.3)
	var door: Vector3 = sp["door"]
	world.set_door("house", true, 0.05)
	_nika_put(door + Vector3(0, 0, 0.9), 0.0)
	rig.setup(girl.global_position + Vector3(0, 1.1, 0), 180.0, -20.0, 5.0, 3.0, 26.0)
	await get_tree().create_timer(0.7).timeout
	world.set_door("house", false)
	_door_busy = false


func _room_keep_in() -> void:
	## У дідовій хаті стіни не тверді — Ніка не виходить за них; біля дверей — виходить надвір.
	var R: Vector3 = world.ROOM
	var gp: Vector3 = girl.global_position
	var cl := Vector3(clampf(gp.x, R.x - 2.9, R.x + 2.9), gp.y, clampf(gp.z, R.z - 2.2, R.z + 2.2))
	if cl != gp:
		girl.global_position = cl
		if girl._pl_body:
			girl._pl_body.global_position = Vector3(cl.x, girl._pl_body.global_position.y, cl.z)
	var rd: Vector3 = world.spots["room_door"]
	if not _door_busy and Vector2(cl.x - rd.x, cl.z - rd.z).length() < 0.45:
		_nika_house_leave()


func enter_house() -> void:
	if _door_busy or Game.state["location"] == "room":
		return
	_door_busy = true
	var sp: Dictionary = world.spots
	var door: Vector3 = sp["door"]
	await _beep_fly_and_wait(door + Vector3(0, 0, 0.3))
	world.set_door("house", true)
	await get_tree().create_timer(0.5).timeout
	await _beep_fly_and_wait(door + Vector3(0, 0, -0.9))
	world.set_door("house", false, 0.3)
	go_to("room")
	# у кімнаті: залітає з-за дверей
	var rd: Vector3 = sp["room_door"]
	beep.position = rd + Vector3(0, 0, 1.0)
	world.set_door("room", true, 0.35)
	await get_tree().create_timer(0.35).timeout
	await _beep_fly_and_wait(rd + Vector3(1.3, 0, -2.2))
	world.set_door("room", false)
	_door_busy = false


func leave_house() -> void:
	if _door_busy or Game.state["location"] != "room":
		return
	_door_busy = true
	var sp: Dictionary = world.spots
	var rd: Vector3 = sp["room_door"]
	await _beep_fly_and_wait(rd + Vector3(0, 0, -0.2))
	world.set_door("room", true)
	await get_tree().create_timer(0.5).timeout
	await _beep_fly_and_wait(rd + Vector3(0, 0, 1.0))
	world.set_door("room", false, 0.3)
	go_to("yard", false, true)
	var door: Vector3 = sp["door"]
	beep.position = door + Vector3(0, 0, -0.9)
	world.set_door("house", true, 0.35)
	await get_tree().create_timer(0.35).timeout
	await _beep_fly_and_wait(door + Vector3(0.4, 0, 1.4))
	world.set_door("house", false)
	_door_busy = false


func _beep_fly_and_wait(p: Vector3) -> void:
	var done := [false]
	beep.fly_to_raw(p, func(): done[0] = true)
	var t := 0.0
	while not done[0] and t < 6.0:
		t += get_process_delta_time()
		await get_tree().process_frame


# ------------------------------------------------------------------ життя на фермі
func _lives_outside(n) -> void:
	n.lives_outside = true
	var h := Game.hour()
	if h >= 19.3 or h < 7.3:
		n.at_home = true
		n.visible = false
		n.bounds = n.OUT_BOUNDS
		n.position = world.spots["kid_home"]

func _hens_outside() -> bool:
	for b in birds:
		if b.mode != "inside":
			return true
	return false


func herd_hens() -> void:
	if puppy.doing == "herd":
		return
	beep.say("Біме, жени курочок додому!", 2.5)
	audio.play_at("puppy_bark", puppy, -2.0)
	puppy.herd_hens(birds, world.spots["coop_door"])


func throw_ball() -> void:
	## Beep кидає м'ячик, Бім біжить і приносить.
	if Game.state["location"] != "yard":
		return
	if puppy.doing == "fetch":
		hud.toast("Бім уже біжить за м'ячиком!")
		return
	if ball == null:
		ball = Node3D.new()
		ball.add_child(Util.sphere(0.07, Util.mat(Color(0.9, 0.2, 0.2), 0.4), Vector3.ZERO))
		ball.add_child(Util.sphere(0.071, Util.mat(Color(1, 0.95, 0.4), 0.4), Vector3.ZERO, Vector3(1, 0.25, 1)))
		world.yard_root.add_child(ball)
	if ball.get_parent() != world.yard_root:
		ball.reparent(world.yard_root)
	var from: Vector3 = beep.global_position + Vector3(0, 1.0, 0)
	var a := randf() * TAU
	var to := Vector3(clampf(from.x + cos(a) * randf_range(3.0, 5.5), -20.0, 8.0), 0.07, clampf(from.z + sin(a) * randf_range(3.0, 5.5), -14.0, 4.2))
	to = Obstacles.push_out(to, 0.25)
	ball.global_position = from
	beep.say("Апорт!", 1.5)
	beep.happy()
	audio.play_at("pop", beep, -4.0)
	puppy.say("Гав!", 1.0)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p: Vector3 = from.lerp(to, t)
		p.y = lerpf(from.y, 0.07, t) + sin(t * PI) * 1.6
		ball.global_position = p, 0.0, 1.0, 0.9)
	await tw.finished
	puppy.fetch(ball, beep)


func _scan_text() -> String:
	var s := Game.state
	var p: Dictionary = s["puppy"]
	var lines: Array = []
	lines.append("Бім: ситість %d%%, радість %d%%%s" % [100 - int(p["hunger"]), int(p["joy"]), "" if float(s["water_bowl"]) > 1.0 else ", мисочка з водою порожня"])
	lines.append("Кури: %s, %s" % ["нагодовані" if float(s["hens_fed"]) > 30.0 else "голодні", "корито з водою" if float(s["trough"]) > 1.0 else "корито порожнє"])
	var f: Dictionary = s["field"]
	lines.append("Город: вологість %d%%, соняшники виросли на %d%%" % [int(f["water"]), int(float(f["growth"]) * 100.0)])
	lines.append("Яєць у кошику: %d" % int(s.get("eggs", 0)))
	lines.append("Молоко: бабуся надоїла дійниць — %d" % int(s.get("milk", 0)))
	lines.append("Лимончик: %.1f °C — %s" % [float(s["gecko"]["temp"]), Game.gecko_mood()])
	return "\n".join(lines)


var _pond_day := -1
var _back_day := -1
const GEESE_WAY := [Vector3(-3.0, 0, 2.6), Vector3(0, 0, 3.6), Vector3(0, 0, 7.5), Vector3(0.5, 0, 19.0), Vector3(0, 0, 28.5),
	Vector3(-23.0, 0, 26.0), Vector3(-45.0, 0, 23.5), Vector3(-50.0, 0, 27.5)]


func _swimmers() -> Array:
	## Плавають лише гуси (індик лишається на подвір'ї).
	return geese.filter(func(g): return g.voice == "Га-га-га!")


func _geese_home() -> bool:
	for g in _swimmers():
		if not g.mode in ["free", "grain", "trough"]:
			return false
	return not geese.is_empty()


func _geese_at_pond() -> bool:
	for g in geese:
		if g.mode == "swim" or g.mode == "trek":
			return true
	return false


func geese_to_pond() -> void:
	var c: Vector3 = world.outer.POND
	var flock := _swimmers()
	puppy.herd_geese(flock, true, GEESE_WAY, func():
		var i := 0
		for g in flock:
			g.pond_c = c
			g.pond_r = 7.0
			g.trek_offset = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
			g.start_trek(GEESE_WAY, "swim", i * 0.7)
			i += 1)


func geese_from_pond() -> void:
	var back := GEESE_WAY.duplicate()
	back.reverse()
	back.append(Vector3(-8.0, 0, 1.0))
	puppy.herd_geese(_swimmers(), false, GEESE_WAY, func():
		var i := 0
		for g in geese:
			if g.mode == "swim":
				var pts: Array = [g.global_position + (back[0] - g.global_position).normalized() * 0.0]
				pts.append_array(back)
				g.start_trek(pts, "free", i * 0.6)
			i += 1)


func _farm_tick() -> void:
	## Раз на секунду: увечері Бім заганяє курей (якщо гравець не встиг), зранку кури виходять.
	var h := Game.hour()
	var d := int(Game.state["day"])
	var waiting_for_player: bool = Game.current_quest().get("id", "") == "hens_home"
	if (h >= (21.5 if waiting_for_player else 20.3) or h < 5.0) and _hens_outside() and _herd_day != d and puppy.doing != "herd":
		_herd_day = d
		herd_hens()
	if h >= 6.5 and h < 11.0 and _out_day != d:
		_out_day = d
		for b in birds:
			b.come_out(world.spots["coop_door"])
		for g in geese:
			g.come_out(world.spots["barn"])
	# удень Бім жене гусей (й індика) на ставок, по обіді — назад
	if h >= 10.0 and h < 13.0 and _pond_day != d and _geese_home() and puppy.doing == "" and not puppy.in_house and Game.state["location"] == "yard":
		_pond_day = d
		geese_to_pond()
	if (h >= 16.0 and h < 20.0 or h >= 20.0 and _geese_at_pond()) and _geese_at_pond() and _back_day != d and puppy.doing in ["", "doghouse"]:
		_back_day = d
		geese_from_pond()
	# гуси самі йдуть ночувати в сарай
	if (h >= 20.0 or h < 5.0) and _geese_day != d and not _geese_at_pond():
		_geese_day = d
		for g in geese:
			if g.mode != "inside":
				g.go_coop(world.spots["barn"])
	if waiting_for_player and h >= 18.5 and h < 18.6:
		hud.toast("Вечоріє! Торкнись Біма — він зажене курей", 3.0)


# ------------------------------------------------------------------ квести
const PORTRAITS := {"Дідусь Петро": "grandpa", "Тарасик": "kid", "Гвинтик": "gvintyk", "Beep": "beep", "Ніка": "girl", "Бабуся Галя": "granny"}
const GOLD_FLOWER_POS := Vector3(2.6, 0, -5.4)


func _portrait(giver: String) -> Texture2D:
	var f := "res://assets/ui/%s.png" % PORTRAITS.get(giver, "grandpa")
	return load(f) if ResourceLoader.exists(f) else null


func _on_quest_started(q: Dictionary) -> void:
	var giver: String = q.get("giver", "Дідусь Петро")
	if q["goal"] == "seed" and seeds and seeds.left() == 0:
		Game.complete_quest.call_deferred()
	if giver != "Дідусь Петро":
		audio.play("page", -8.0)
		hud.show_dialog(giver, q["text"], _portrait(giver))
		return
	if not _greeted and Game.state["location"] == "yard":
		_greeted = true
		grandpa.wave_at(rig.cam.global_position)
		await get_tree().create_timer(1.2).timeout
	_grandpa_dialog(q["text"])


# ------------------------------------------------------------------ день і ніч
var fireflies: Array = []
var falling_star: Node3D
var _night_busy := false
var hit_node: Node3D                   # чого торкнулися останнім (для світлячків)


func _sleep_mode() -> String:
	if _night_busy or riding:
		return ""
	if Game.night_active():
		return "sleep" if Game.night_done() else ""
	if Game.is_night():
		return "sleep"                     # денні справи не зроблено, а вже ніч (стара гра) — можна спати
	if Game.day_done():
		if Game.current_quest().is_empty() and Game.hour() < 15.0:
			return ""
		return "goodnight"
	return ""


func _goodnight() -> void:
	## «На добраніч»: сонце швидко сідає, усі розходяться по домівках.
	if _night_busy:
		return
	_night_busy = true
	hud.toast("На добраніч! Усі розходяться по домівках…", 3.5)
	overview()
	var h0 := Game.hour()
	var tw := create_tween()
	tw.tween_method(func(v: float): Game.state["time"] = v, h0, 21.3, 5.0).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_night_busy = false


func _sleep_to_morning() -> void:
	if _night_busy:
		return
	_night_busy = true
	if beep.lamp.visible:
		beep.toggle_lamp()
	await hud.fade(true, 1.2)
	Game.sleep_to_morning()
	grandpa.bed_now = false
	_clear_night_things()
	grandpa.cover(false)
	await get_tree().create_timer(0.6).timeout
	await hud.fade(false, 1.2)
	hud.toast("Доброго ранку! День %d" % int(Game.state["day"]), 3.0)
	_night_busy = false


func _on_night_started(t: Dictionary) -> void:
	audio.play("page", -8.0)
	var giver: String = t.get("giver", "Beep")
	hud.show_dialog(giver, t["text"], _portrait(giver))


func _night_step() -> void:
	## Раз на чверть секунди: кнопка сну, нічні справи (світлячки, зірка, обхід курника).
	if hud:
		hud.update_sleep_button(_sleep_mode())
	var t := Game.night_task() if Game.night_active() else {}
	var goal: String = t.get("goal", "")
	# світлячки
	if goal == "firefly":
		if fireflies.is_empty():
			_spawn_fireflies(int(t["count"]) - int(Game.state["night"].get("progress", 0)))
		for f in fireflies.duplicate():
			if not is_instance_valid(f):
				fireflies.erase(f)
				continue
			var d := Vector2(f.global_position.x - beep.global_position.x, f.global_position.z - beep.global_position.z).length()
			if d < 1.3 and Game.state["location"] == "yard":
				fireflies.erase(f)
				_pop_sparkles(f.global_position, Color(0.8, 1.0, 0.4))
				f.queue_free()
				audio.play("magic_bells", -10.0, 1.4)
				Game.emit_event("firefly")
	elif not fireflies.is_empty():
		for f in fireflies:
			if is_instance_valid(f):
				f.queue_free()
		fireflies.clear()
	# падаюча зірка
	if goal == "star":
		if falling_star == null:
			_spawn_star()
		elif plane and riding and falling_star.global_position.distance_to(plane.global_position) < 7.0:
			_pop_sparkles(falling_star.global_position, Color(1.0, 0.9, 0.5))
			falling_star.queue_free()
			falling_star = null
			audio.play("magic_bells", -2.0, 1.1)
			beep.say("Спіймали зірочку!", 2.5)
			Game.emit_event("star")
	elif falling_star:
		falling_star.queue_free()
		falling_star = null
	# обхід курника з ліхтариком
	if goal == "coop_checked" and beep.lamp.visible and Game.state["location"] == "yard":
		var cp: Vector3 = world.spots["coop"]
		if Vector2(beep.global_position.x - cp.x, beep.global_position.z - cp.z).length() < 3.0:
			beep.say("Раз, два, три… усі вдома!", 2.5)
			Game.emit_event("coop_checked")


func _clear_night_things() -> void:
	for f in fireflies:
		if is_instance_valid(f):
			f.queue_free()
	fireflies.clear()
	if falling_star:
		falling_star.queue_free()
		falling_star = null


const FIREFLY_SPOTS := [Vector3(12.0, 0, -6.0), Vector3(15.5, 0, -2.0), Vector3(18.0, 0, -9.0), Vector3(13.0, 0, 1.5),
	Vector3(-4.0, 0, 3.0), Vector3(-9.5, 0, -3.0), Vector3(2.0, 0, 3.6), Vector3(-12.0, 0, -6.0)]


func _spawn_fireflies(n: int) -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.85, 1.0, 0.45)
	var spots := FIREFLY_SPOTS.duplicate()
	spots.shuffle()
	for i in mini(n, spots.size()):
		var f := Node3D.new()
		f.set_script(preload("res://scripts/firefly.gd"))
		world.yard_root.add_child(f)
		f.position = spots[i] + Vector3(0, 1.1, 0)
		f.add_child(Util.sphere(0.07, glow, Vector3.ZERO))
		var l := OmniLight3D.new()
		l.light_color = Color(0.8, 1.0, 0.45)
		l.light_energy = 1.4
		l.omni_range = 2.2
		f.add_child(l)
		f.add_child(Util.pick_area("firefly", Vector3(1.0, 1.0, 1.0), Vector3.ZERO))
		fireflies.append(f)


func _spawn_star() -> void:
	## Падаюча зірка повільно пливе над селом — її ловлять верхи на драконі.
	falling_star = Node3D.new()
	falling_star.set_script(preload("res://scripts/firefly.gd"))
	falling_star.set("drift", 3.0)
	world.yard_root.add_child(falling_star)
	falling_star.position = Vector3(-8.0, 24.0, 40.0)
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color(1.0, 0.92, 0.55)
	var st := Node3D.new()
	falling_star.add_child(st)
	for k in 5:
		var a := TAU * k / 5.0
		var ray := Util.sphere(0.35, gold, Vector3(sin(a), cos(a), 0) * 0.6, Vector3(0.45, 1.3, 0.3))
		ray.rotation.z = -a
		st.add_child(ray)
	st.add_child(Util.sphere(0.55, gold, Vector3.ZERO))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.6)
	l.light_energy = 3.0
	l.omni_range = 12.0
	falling_star.add_child(l)
	var tail := CPUParticles3D.new()
	tail.amount = 60
	tail.lifetime = 1.6
	tail.gravity = Vector3(0, -0.6, 0)
	tail.initial_velocity_min = 0.2
	tail.initial_velocity_max = 0.6
	tail.spread = 180.0
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	m.radial_segments = 6
	m.rings = 3
	tail.mesh = m
	tail.material_override = gold
	falling_star.add_child(tail)


func _pop_sparkles(at: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -1.5, 0)
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.radial_segments = 6
	m.rings = 3
	p.mesh = m
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = col
	p.material_override = mt
	world.yard_root.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _on_quest_done(q: Dictionary) -> void:
	audio.play("win", -2.0)
	audio.play("coins", -6.0)
	if q.get("done", "") != "":
		hud.toast("+%d ●   %s" % [q["reward"], q["done"]], 3.5)
	await get_tree().create_timer(1.6).timeout
	Game.start_quest()


# ------------------------------------------------------------------ перевірка (лише для розробки)
func _run_demo() -> void:
	var steps: PackedStringArray = _demo.split(",")
	for s in steps:
		await get_tree().create_timer(0.6).timeout
		if hud.dialog_open() and not s.begins_with("shot"):
			hud._close_dialog()
			await get_tree().create_timer(0.3).timeout
		print("DEMO ", s)
		if s.begins_with("wait"):
			await get_tree().create_timer(float(s.substr(4))).timeout
		elif s.begins_with("shot:"):
			get_viewport().get_texture().get_image().save_png(s.substr(5))
			print("SHOT ", s.substr(5))
		elif s.begins_with("time:"):
			Game.state["time"] = float(s.substr(5))
		elif s.begins_with("lookat:"):
			var xz := s.substr(7).split(";")
			_track = Node3D.new()
			add_child(_track)
			_track.position = Vector3(float(xz[0]), float(xz[2]) if xz.size() > 2 else 0.5, float(xz[1]))
		elif s.begins_with("yaw:"):
			rig.yaw = float(s.substr(4))
		elif s.begins_with("dist:"):
			rig.dist = float(s.substr(5))
		elif s.begins_with("pitch:"):
			rig.pitch = float(s.substr(6))
		elif s.begins_with("call:"):
			# call:хто:метод[:аргумент] — для перевірки справ персонажів
			var c := s.substr(5).split(":")
			var who = get(c[0])
			if who:
				var args: Array = []
				if c.size() > 2:
					args.append(c[2])
				who.callv(c[1], args)
		elif s.begins_with("ortho:"):
			# ortho:x;z;розмір — вигляд згори (для розстановки перешкод)
			var c := s.substr(6).split(";")
			rig.set_process(false)
			set_process(false)
			hud.visible = false
			rig.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			rig.cam.size = float(c[2])
			rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), Vector3(float(c[0]), 40, float(c[1])))
			rig.cam.far = 100.0
		elif s.begins_with("camat:"):
			# camat:звідки x;y;z;куди x;y;z — нерухома камера (перевірка зблизька)
			var c := s.substr(6).split(";")
			rig.set_process(false)
			set_process(false)
			hud.visible = false
			rig.cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			rig.cam.fov = 40.0
			rig.cam.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
			rig.cam.look_at(Vector3(float(c[3]), float(c[4]), float(c[5])))
		elif s.begins_with("bones:"):
			# bones:хто — де кістки (у системі вузла персонажа)
			var who: Node3D = get(s.substr(6))
			for sk in who.find_children("*", "Skeleton3D", true, false):
				for b in (sk as Skeleton3D).get_bone_count():
					var gp: Vector3 = who.to_local((sk as Skeleton3D).global_transform * (sk as Skeleton3D).get_bone_global_pose(b).origin)
					print("BONE ", (sk as Skeleton3D).get_bone_name(b), " ", gp)
		elif s == "girl_ctl":
			start_girl_control()
		elif s.begins_with("mount:"):
			var k := s.substr(6)
			start_mount(k, {"combine": combine, "tractor": tractor, "bike": bike, "horse": _near_saddle_horse()}.get(k))
		elif s == "dismount":
			dismount()
		elif s.begins_with("meet:"):
			var k := s.substr(5)
			_meet_begin(k, get(k), null)
		elif s == "info":
			print("INFO girl=", girl.global_position.snapped(Vector3.ONE * 0.01), " ms=", _mount_state, " mk=", _mount_kind,
				" m=", (_mount.global_position.snapped(Vector3.ONE * 0.01) if _mount else Vector3.ZERO), " cmb=", combine.global_position.snapped(Vector3.ONE * 0.01) if combine else Vector3.ZERO,
				" goal=", _girl_goal, " meet=", _meet != null, " gest=", _gesture_t, " anim=", girl.current, " bk=", girl.has_basket(), " cam=", rig.cam.global_position.snapped(Vector3.ONE * 0.01))
		elif s.begins_with("girlat:"):
			var c := s.substr(7).split(";")
			girl.global_position = Vector3(float(c[0]), 0, float(c[1]))
			if girl._pl_body:
				girl._pl_body.global_position = girl.global_position
			if c.size() > 2:
				girl.rotation.y = deg_to_rad(float(c[2]))
				rig.yaw = float(c[2]) + 180.0
		elif s.begins_with("goal:"):
			var c := s.substr(5).split(";")
			_girl_goal = Vector3(float(c[0]), 0, float(c[1]))
		elif s.begins_with("joy:"):
			# joy:x;y;секунд — ніби тримаємо джойстик
			var c := s.substr(4).split(";")
			hud.flight.joy = Vector2(float(c[0]), float(c[1]))
			await get_tree().create_timer(float(c[2])).timeout
			hud.flight.joy = Vector2.ZERO
		elif s == "bzinfo":
			for d in world.outer.bazaar.doors:
				print("DOOR ", d["node"].name, " ", d["pos"], " sign=", d["sign"])
		elif s.begins_with("ray:"):
			var c := s.substr(4).split(";")
			var a := Vector3(float(c[0]), float(c[4]), float(c[1]))
			var b := Vector3(float(c[2]), float(c[4]), float(c[3]))
			var q := PhysicsRayQueryParameters3D.create(a, b, 1 << 17)
			var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
			print("RAY ", a, "->", b, " hit=", hit.get("position", "none"), " n=", hit.get("normal", ""), " shape=", hit.get("shape", -1))
		elif s.begins_with("speed:"):
			Engine.time_scale = float(s.substr(6))
		elif s == "perf":
			print("PERF draw=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " obj=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " fps=", Engine.get_frames_per_second())
		elif s == "where":
			print("GIRL ", girl.global_position, " place=", world.outer.place_name(girl.global_position))
			for d in world.outer.bazaar.doors:
				if float(d["k"]) > 0.0 or float(d["want"]) > 0.0:
					print("  OPEN ", d["node"].name, " k=", d["k"], " rotY=", d["node"].rotation_degrees)
		elif s == "hitch":
			# перевірка воза: кінь одразу в оглоблях
			horse_cart.horse = horse
			horse.hitch_begin()
			horse.global_position = horse_cart.hitch_pos()
			horse.rotation.y = horse_cart.park_yaw
			horse_cart.hitched = true
		elif s == "done":
			hud.flight.home_pressed.emit()
		elif s == "persp":
			rig.cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			rig.cam.far = 400.0
			rig.set_process(true)
			set_process(true)
			hud.visible = true
		elif s.begins_with("orthof:"):
			# orthof:x;y;z;розмір;кут — вигляд збоку без перспективи (камера дивиться в точку з боку кута)
			var c := s.substr(7).split(";")
			rig.set_process(false)
			set_process(false)
			hud.visible = false
			var yw := deg_to_rad(float(c[4]))
			var at := Vector3(float(c[0]), float(c[1]), float(c[2]))
			rig.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			rig.cam.size = float(c[3])
			rig.cam.global_transform = Transform3D(Basis(Vector3.UP, yw), at + Basis(Vector3.UP, yw) * Vector3(0, 0, float(c[5]) if c.size() > 5 else 20.0))
			rig.cam.far = 60.0
		elif s.begins_with("follow:"):
			var c := s.substr(7).split(":")
			focus_on(get(c[0]), c[1])
		elif s.begins_with("joy:"):
			var c := s.substr(4).split(";")
			hud.flight.joy = Vector2(float(c[0]), float(c[1]))
			hud.flight.climb = float(c[2]) if c.size() > 2 else 0.0
		elif s.begins_with("ridecam:"):
			var c := s.substr(8).split(";")
			_dbg_cam = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif s.begins_with("girlpos:"):
			var c := s.substr(8).split(";")
			girl.stop()
			girl.position = Vector3(float(c[0]), 0, float(c[1]))
			girl.rotation.y = deg_to_rad(float(c[2]))
		elif s.begins_with("nightstep:"):
			Game.state["night"] = {"day": Game.night_owner_day(), "step": int(s.substr(10)), "progress": 0}
		elif s == "tapgp":
			_tap_object("grandpa")
		elif s == "gp":
			print("GP ", grandpa.global_position, " lying=", grandpa.lying, " doing=", grandpa.doing, " cur=", grandpa.current, " vis=", grandpa.is_visible_in_tree(), " home=", grandpa.at_home, " model_y=", grandpa.model.position.y, " anim=", grandpa.ap.current_animation)
		elif s == "pp":
			print("PUP ", puppy.global_position, " moving=", puppy.moving, " cur=", puppy.current)
		elif s == "bigmap":
			hud.open_big_map()
		elif s.begins_with("door:"):
			var c := s.substr(5).split(":")
			print("DBG door ", c[0], " exists=", world.doors.has(c[0]))
			world.set_door(c[0], c[1] == "1", 0.3)
		elif s.begins_with("tapk:"):
			_tap_object(s.substr(5))
		elif s == "dbg_girl":
			print("PROG ", Game.state["progress"], " seeds=", Game.state["seeds"])
			print("GIRL cur=", girl.current, " pos=", girl.global_position, " doing=", girl.doing, " moving=", girl.moving, " vis=", girl.visible, " mvis=", girl.model.visible, " onp=", girl.on_plane != null, " anim=", girl.ap.current_animation if girl.ap else "")
		elif s == "geese_out":
			_pond_day = int(Game.state["day"])
			geese_to_pond()
		elif s == "geese_swim":
			for g in _swimmers():
				g.pond_c = world.outer.POND
				g.global_position = world.outer.POND + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
				g.mode = "swim"
				g._target = g._swim_point()
		elif s == "geese_back":
			geese_from_pond()
		elif s == "gdbg":
			for g in geese:
				print("DBG goose ", g.mode, " ", g.global_position)
			print("DBG pup ", puppy.global_position, " ", puppy.doing, " vis=", puppy.visible, " in_house=", puppy.in_house, " cur=", puppy.current)
		elif s.begins_with("camon:"):
			# camon:хто;відстань;висота — нерухома камера дивиться на персонажа (hare, sedge — перший у списку)
			var c := s.substr(6).split(";")
			var n: Node3D = extra_horses[int(String(c[0]).substr(5)) - 2] if String(c[0]).begins_with("horse") and String(c[0]).length() == 6 else hares[0] if c[0] == "hare" else (world.outer.sedge[0] if c[0] == "sedge" else get(c[0]))
			var d := float(c[1])
			rig.set_process(false)
			set_process(false)
			hud.visible = false
			rig.cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			rig.cam.fov = 40.0
			var fw := Vector3(sin(n.global_rotation.y), 0, cos(n.global_rotation.y))
			rig.cam.global_position = n.global_position + fw * d + Vector3(0, float(c[2]), 0) + Vector3(fw.z, 0, -fw.x) * d * 0.4
			rig.cam.look_at(n.global_position + Vector3(0, float(c[2]) * 0.55, 0))
		elif s == "wk":
			for w in [granny, groom, shepherd]:
				if w:
					print("WK ", w.name, " t=", snapped(Game.hour(), 0.01), " pos=", w.global_position, " vis=", w.visible, " doing=", w.doing, " duty=", w.on_duty)
			print("WK horse ", horse.mode, " ", horse.global_position, " cart_h=", horse_cart.hitched, " cows0=", cows[0].mode, " ", cows[0].global_position)
			for hz in hares:
				print("WK hare ", hz.global_position, " ", hz._cur)
			print("WK sedge ", world.outer.sedge.size())
			if groom:
				print("WK cart ", horse_cart.global_position, " horse ", horse.global_position, " groom_riding=", groom.riding != null, " gpos=", groom.global_position)
		elif s.begins_with("speed:"):
			Engine.time_scale = float(s.substr(6))
		elif s == "plane_dbg":
			print("PLANE ", plane.global_position, " st=", plane.state, " rot=", plane.rotation, " pilot=", plane.pilot, " seat=", plane.pilot_seat, " tg=", plane.to_global(plane.pilot_seat), " girl=", girl.global_position if girl else Vector3.ZERO, " gpar=", girl.get_parent().name if girl else "")
		elif s == "ride":
			start_ride()
		elif s == "ride_home":
			plane.go_home()
		elif s == "land":
			plane.land_here()
		elif s == "beepctl":
			start_beep_control()
		elif s.begins_with("overview"):
			overview()
		elif s.begins_with("fly:"):
			var c := s.substr(4).split(";")
			beep.fly_to(Vector3(float(c[0]), 0, float(c[1])))
		elif s.begins_with("quest:"):
			Game.state["quest"] = int(s.substr(6))
			Game.state["progress"] = 0
			Game.start_quest()
		elif s.begins_with("set:"):
			var c := s.substr(4).split(":")
			Game.state[c[0]] = float(c[1])
		elif s.begins_with("track:"):
			_track = get(s.substr(6))
		elif s == "warm":
			Game.state["gecko"]["temp"] = 30.0
			Game.state["gecko"]["lamp"] = true
		elif s == "tap_beep":
			tap(rig.cam.unproject_position(beep.global_position + Vector3(0, 1.05, 0)))
		elif s == "tap_puppy":
			tap(rig.cam.unproject_position(puppy.global_position + Vector3(0, 0.25, 0)))
		elif s == "tap_grandpa":
			tap(rig.cam.unproject_position(grandpa.global_position + Vector3(0, 1.0, 0)))
		elif s == "tap_house":
			tap(rig.cam.unproject_position(world.HOUSE_POS + Vector3(0, 2.0, 0)))
		elif s.begins_with("focus_puppy"):
			rig.focus = puppy.global_position + Vector3(0, 0.3, 0)
			rig.dist = 2.4
			set_process(false)
		elif s.begins_with("focus_grandpa"):
			rig.focus = grandpa.global_position + Vector3(0, 1.0, 0)
			rig.dist = 3.5
			set_process(false)
		elif s.begins_with("focus_terr"):
			_tap_object("terrarium")
			rig.pitch = -14.0
		elif s.begins_with("portrait:"):
			hud.visible = false
			grandpa.stop()
			grandpa.set_process(false)
			grandpa.play("idle")
			grandpa.ap.speed_scale = 0.0
			set_process(false)
			var head: Vector3 = grandpa.global_position + Vector3(0, 1.36, 0)
			rig.setup(head, rad_to_deg(grandpa.rotation.y) + 18.0, -4.0, 1.5, 0.5, 5.0)
			rig.cam.fov = 30.0
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png(s.substr(9))
			hud.visible = true
		elif s.begins_with("face:"):
			# face:хто:висота_голови:файл — портрет для діалогу
			var c := s.substr(5).split(":")
			var who: Node3D = get(c[0])
			hud.visible = false
			who.set_process(false)
			if who.has_method("play"):
				who.play("idle")
			if "ap" in who and who.ap:
				who.ap.speed_scale = 0.0
			set_process(false)
			var head: Vector3 = who.global_position + Vector3(0, float(c[1]), 0)
			rig.setup(head, rad_to_deg(who.rotation.y) + 15.0, -4.0, float(c[3]) if c.size() > 3 else 1.2, 0.3, 5.0)
			rig.cam.fov = 30.0
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png(c[2])
			hud.visible = true
			set_process(true)
			who.set_process(true)
		elif s.begins_with("pupwalk"):
			puppy.position = Vector3(-2, 0, 0)
			puppy.rotation.y = 0.0
			puppy.walk_to(Vector3(-2, 0, 3.5))
			puppy.set_process(true)
		elif s.begins_with("camside"):
			_track = puppy
			rig.setup(puppy.global_position + Vector3(0, 0.3, 0), 90.0, -18.0, 2.6, 1.0, 9.0)
		elif s.begins_with("camfront"):
			_track = puppy
			rig.setup(puppy.global_position + Vector3(0, 0.3, 0), 0.0, -18.0, 2.6, 1.0, 9.0)
		elif s == "dbg2":
			for n in world.yard_root.get_children():
				if n.has_method("talk") or "drops" in n:
					print("NODE ", n.get_script().resource_path.get_file(), " ", n.global_position, " vis=", n.visible, " model=", n.get("model"))
		elif s == "dbg":
			var g: Node3D = terrarium.gecko
			for mi in g.find_children("*", "MeshInstance3D", true, false):
				print("GECKO mesh aabb ", (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb())
			print("GECKO pos ", g.global_position, " terr ", terrarium.global_position)
			var tm: Node3D = terrarium.get_child(0)
			for mi in tm.find_children("*", "MeshInstance3D", true, false):
				print("TERR aabb ", (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb())
		elif s == "fast":
			Game.state["gecko"]["temp"] = 27.98
			Game.state["gecko"]["lamp"] = true
			Game._tick(1.0)
		else:
			_on_action(s)
	print("DEMO END quest=", Game.state["quest"], " coins=", Game.state["coins"])
	get_tree().quit()


# ------------------------------------------------------------------ Ніка сама відчиняє двері, ворота й хвіртки
var _hand_open := {}                     # групи дверей подвір'я, відчинені Нікою
var _door_left := 0.0
var _door_fire := -1.0
var _door_what = null


func _hand_door_busy(delta: float, dir: Vector3) -> bool:
	if _door_left > 0.0:
		_door_left -= delta
		girl.door_hand_step(delta)
		if _door_fire >= 0.0 and _door_left <= _door_fire:
			_door_fire = -1.0
			_fire_door()
		return true
	if dir.length() > 0.1 and _try_hand_door(dir):
		return true
	return false


func _try_hand_door(dir: Vector3) -> bool:
	var gp: Vector3 = girl.global_position
	var at = null
	var bz = world.outer.bazaar
	if bz:
		var d = bz.door_ahead(gp, dir)
		if d != null:
			_door_what = ["bz", d]
			at = d["pos"]
	if at == null and Game.state["location"] == "yard":
		for g in world.auto_doors:
			var ad: Dictionary = world.auto_doors[g]
			if ad["open"] or _hand_open.has(g):
				continue
			var p: Vector3 = ad["pos"]
			var to := Vector3(p.x - gp.x, 0, p.z - gp.z)
			var dl := to.length()
			if dl < minf(float(ad["r"]), 1.7) and dl > 0.05 and to.normalized().dot(dir) > 0.3:
				_door_what = ["world", g]
				at = p
				break
	if at == null:
		return false
	var dur: float = girl.open_door_hand(at)
	_door_left = dur
	_door_fire = dur * 0.55
	return true


func _fire_door() -> void:
	if _door_what == null:
		return
	if _door_what[0] == "bz":
		world.outer.bazaar.open_by_hand(_door_what[1], girl.global_position)
	else:
		var g: String = _door_what[1]
		_hand_open[g] = true
		var ad: Dictionary = world.auto_doors[g]
		ad["open"] = true
		ad["idle"] = 0.0
		for n in ad["names"]:
			world.set_door(n, true, 0.6)
	_door_what = null


# ------------------------------------------------------------------ Ніка верхи на коні з сідлом і на велосипеді
const HORSE_BLOCK := Vector3(4.6, 0, 9.0)       # дерев'яна приступка біля воріт ферми — з неї Ніка сідає на коня
const BIKE_PARK := Vector3(-11.0, 0, 48.95)      # велосипед стоїть біля Ніччиного тину в селі — поруч, уздовж тину (тин — z = 49.5)
var saddle_horse = null
var riding_horses: Array = []                       # усі їздові коні (з сідлом)


func _near_saddle_horse():
	## Найближчий до Ніки їздовий кінь.
	var best = saddle_horse
	var bd := INF
	for h in riding_horses:
		if is_instance_valid(h) and girl:
			var d: float = (h as Node3D).global_position.distance_to(girl.global_position)
			if d < bd:
				bd = d
				best = h
	return best
var bike: Node3D = null
var combine: Node3D = null
var _mount: Node3D = null
var _mount_block := Vector3.INF                 # приступка, з якої Ніка сідає на коня (INF — сідає з землі)
var _mount_kind := ""
var _mount_state := ""                          # come / mount / ride / dismount
var _mount_v := 0.0
var _mount_body: CharacterBody3D
var _h_route: Array = []
var _g_route: Array = []


func _spawn_ride_things() -> void:
	var wood := Util.mat(Color(0.5, 0.34, 0.2), 0.9)
	var blk := Node3D.new()
	blk.name = "HorseBlock"
	world.yard_root.add_child(blk)
	blk.position = HORSE_BLOCK
	blk.add_child(Util.box(Vector3(0.36, 0.55, 0.62), wood, Vector3(-0.1, 0.275, 0)))
	blk.add_child(Util.box(Vector3(0.3, 0.28, 0.62), wood, Vector3(0.22, 0.14, 0)))
	if ResourceLoader.exists("res://assets/models/bicycle.glb"):
		bike = preload("res://scripts/bike.gd").new()
		bike.name = "Bike"
		world.yard_root.add_child(bike)
		bike.position = BIKE_PARK
		bike.rotation.y = PI / 2.0              # колесами вздовж тину, а не крізь нього
		if not bike.setup():
			bike.queue_free()
			bike = null
	if ResourceLoader.exists("res://assets/models/combine.glb"):
		combine = preload("res://scripts/combine.gd").new()
		combine.name = "Combine"
		world.yard_root.add_child(combine)
		combine.position = world.outer.COMBINE_POS
		combine.rotation.y = world.outer.SHED_YAW
		if not combine.setup():
			combine.queue_free()
			combine = null


func _girl_route_to(p: Vector3) -> Array:
	var gp: Vector3 = girl.global_position
	var rz: float = world.outer.RIVER_Z
	var r: Array = []
	if gp.z > rz + 4.0 and p.z < rz:
		r.append_array([Vector3(0, 0, rz + 9.0), Vector3(0, 0, rz - 9.0)])          # з-за річки — мостом
	if girl.YARD_R.has_point(Vector2(gp.x, gp.z)) and not girl.YARD_R.has_point(Vector2(p.x, p.z)):
		r.append_array([world.spots["inside_gate"], world.spots["outside_gate"]])  # з подвір'я — через ворота
	r.append(Vector3(p.x, 0, p.z))
	return r


func start_mount(kind: String, n: Node3D) -> void:
	if n == null or girl == null or _mount_state != "" or _acting != "" or girl.mounting:
		return
	if girl.global_position.distance_to(n.global_position) > (160.0 if kind == "horse" else 70.0):
		girl.say("Це далеко… Підійду ближче.", 2.0)
		return
	_mount = n
	_mount_kind = kind
	girl.solid_skip = [n]
	_girl_goal = Vector3.INF
	_furn = null
	_girl_stuck = 0.0
	_h_route = []
	if kind == "horse":
		# кінь сам підбігає до Ніки й стає лівим боком до неї; вона сідає просто з землі, будь-де
		n.hitch_begin()
		var f: Dictionary = girl.horse_frame(n)
		var seat: Vector3 = f["seat"]
		_mount_block = Vector3.INF
		var gp: Vector3 = girl.global_position
		var d := Vector3(gp.x - n.global_position.x, 0, gp.z - n.global_position.z)
		if d.length() < 0.5:
			d = Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
		_h_yaw = atan2(d.x, d.z) - PI / 2.0
		var hb := Basis(Vector3.UP, _h_yaw)
		var stand := gp - hb * Vector3(float(f["side"]) + 0.42, 0, seat.z)
		stand.y = 0.0
		_h_route = []
		var hp: Vector3 = n.global_position
		var rz: float = world.outer.RIVER_Z
		if (hp.z - rz) * (gp.z - rz) < 0.0 and absf(hp.z - rz) > 3.0:
			var sg := signf(hp.z - rz)
			_h_route.append_array([Vector3(0, 0, rz + sg * 9.0), Vector3(0, 0, rz - sg * 9.0)])     # через річку — мостом
		var yr: Rect2 = girl.YARD_R
		if yr.has_point(Vector2(gp.x, gp.z)) != yr.has_point(Vector2(hp.x, hp.z)):
			if yr.has_point(Vector2(gp.x, gp.z)):
				_h_route.append_array([world.spots["outside_gate"], world.spots["inside_gate"]])
			else:
				_h_route.append_array([world.spots["inside_gate"], world.spots["outside_gate"]])
		if n.global_position.distance_to(stand) > 3.0:
			_h_route.append(stand - hb * Vector3(0, 0, 2.6))
		_h_route.append(stand)
		_g_route = []
		_girl_face(n.global_position)
		girl.say(["Конику, біжи до мене!", "Іди-но сюди, коником покатаюсь!"][randi() % 2], 2.2)
		if n.has_method("say"):
			n.say("І-го-го!", 1.5)
	elif kind == "combine" or kind == "tractor":
		var c: Dictionary = n.cab_points()
		_g_route = _girl_route_to(n.to_global(c["climb"]))
		girl.say("Залізу в кабіну!" if kind == "combine" else "Покатаюсь на тракторі!", 2.0)
	else:
		_g_route = _girl_route_to(n.to_global(Vector3(0.42, 0, -0.05)))
		girl.say("Покатаюсь на велосипеді!", 2.0)
	_mount_state = "come"


func _mount_cam(delta: float) -> void:
	match _mount_state:
		"come":
			if hud.flight.joy.length() > 0.35:
				_mount_cancel()
				return
			var h_ok := true
			if _mount_kind == "horse" and _mount_block != Vector3.INF:
				h_ok = _horse_come(delta)
			var g_ok := _girl_come(delta)
			if _mount_state == "come" and h_ok and g_ok:
				_mount_state = "mount"
				_do_mount()
			_girl_follow(delta, null, false)
		"mount", "dismount":
			_mount_follow(delta, false)
		"ride":
			_mount_drive(delta)


func _girl_come(delta: float) -> bool:
	if _g_route.is_empty():
		girl.player_step(Vector3.ZERO, false, delta)
		return true
	var to: Vector3 = (_g_route[0] as Vector3) - girl.global_position
	to.y = 0.0
	if to.length() < 0.3:
		_g_route.pop_front()
		_girl_stuck = 0.0
		return false
	var dir := to.normalized()
	if _hand_door_busy(delta, dir):
		return false
	var moved: float = girl.player_step(_detour(dir) * clampf(to.length(), 0.5, 1.0), to.length() > 10.0, delta)
	_detour_update(moved, delta)
	if moved < 0.2 * delta:
		_girl_stuck += delta
		if _girl_stuck > 5.0:
			girl.say("Ой, тут не пройти…", 2.0)
			_mount_cancel()
	else:
		_girl_stuck = 0.0
	return false


func _horse_come(delta: float) -> bool:
	var h = _mount
	if _h_route.is_empty():
		var turn := wrapf(_h_yaw - h.rotation.y, -PI, PI)
		h.hitch_move(h.rotation.y + clampf(turn, -1.6 * delta, 1.6 * delta), 0.0, delta)
		return absf(turn) < 0.04
	var to: Vector3 = (_h_route[0] as Vector3) - h.global_position
	to.y = 0.0
	if to.length() < 0.15:
		if _h_route.size() == 1:
			h.global_position = Vector3((_h_route[0] as Vector3).x, 0, (_h_route[0] as Vector3).z)
		_h_route.pop_front()
		return false
	var want := atan2(to.x, to.z)
	var hd: float = h.rotation.y + clampf(wrapf(want - h.rotation.y, -PI, PI), -2.2 * delta, 2.2 * delta)
	h.hitch_move(hd, minf(4.6, to.length() * 1.5 + 0.25), delta)        # підбігає риссю
	return false


func _do_mount() -> void:
	if _mount_kind == "horse":
		if _mount_block != Vector3.INF:
			await girl.mount_horse(_mount, _mount_block)
		else:
			await girl.mount_horse(_mount, girl.global_position, 0.0)
	elif _mount_kind == "combine" or _mount_kind == "tractor":
		_mount.solid(false)
		if _mount_kind == "tractor":
			_mount.nika_begin()
		await girl.mount_cab(_mount, _mount_kind)
	else:
		await girl.mount_bike(_mount)
	if _mount_state != "mount":
		return
	_mount_state = "ride"
	_mount_v = 0.0
	_cab_steer = 0.0
	_gait = "walk" if _mount_kind == "horse" else ""
	hud.flight.land_text = "Злізти"
	hud.toast("Джойстик — їхати, «»» — швидше, «Меню» — керування саме цим транспортом, «Злізти» — на землю", 4.0)


func dismount() -> void:
	if _mount_state != "ride":
		return
	_auto_ride = []
	_mount_state = "dismount"
	_mount_v = 0.0
	hud.flight.land_text = ""
	if _mount_kind == "horse":
		_mount.hitch_move(_mount.rotation.y, 0.0, 0.0)
		await girl.dismount_horse()
	elif _mount_kind == "combine" or _mount_kind == "tractor":
		_mount.ride_anim(0.0, 0.0, 0.016)
		await girl.dismount_cab()
	else:
		_mount.ride_anim(0.0, 0.0, 0.016)
		await girl.dismount_bike()
	if _mount_state != "dismount":
		return
	_leave_mount(_mount, _mount_kind)
	_mount_state = ""
	_mount = null
	_mount_kind = ""
	girl.solid_skip = []


func _mount_cancel() -> void:
	if _mount_kind == "horse" and _mount and _mount_state == "come":
		if _mount.get_meta("left_by_nika", false):
			_mount.park()
		else:
			_mount.hitch_release()
	_mount_state = ""
	_mount = null
	_mount_kind = ""
	_g_route = []
	_h_route = []
	if girl:
		girl.solid_skip = []


func _mount_force_off() -> void:
	if _mount_state == "":
		return
	if _mount_state == "come":
		_mount_cancel()
		return
	var m := _mount
	var kind := _mount_kind
	var st := _mount_state
	_mount_state = ""
	_mount = null
	_mount_kind = ""
	hud.flight.land_text = ""
	if m and girl and (kind == "combine" or kind == "tractor") and st != "mount":
		_cab_off_alone(m, kind, st == "dismount")      # злазить драбинкою сама, а не опиняється одразу на землі
		return
	if m and girl:
		var off := Vector3(0.9 if kind == "horse" else 0.45, 0, 0)
		if kind == "combine" or kind == "tractor":
			off = m.cab_points()["climb"]
		girl.mount_off_now(m.to_global(off))
		girl.solid_skip = []
		_leave_mount(m, kind)


func _cab_off_alone(m: Node3D, kind: String, going: bool) -> void:
	## Керування Нікою закінчили, коли вона в кабіні: вона сама злазить (виходить, зачиняє двері, драбинкою вниз).
	if going:
		while girl.mounting and girl.mount == m:
			await get_tree().process_frame
	else:
		m.ride_anim(0.0, 0.0, 0.016)
		await girl.dismount_cab()
	girl.solid_skip = []
	_leave_mount(m, kind)


func _leave_mount(m: Node3D, kind: String) -> void:
	## Ніка злізла — кінь, велосипед, трактор чи комбайн лишаються там, де вона злізла.
	if m == null or not is_instance_valid(m):
		return
	match kind:
		"horse":
			m.set_meta("left_by_nika", true)
			m.park()
		"combine":
			m.ride_anim(0.0, 0.0, 0.016)
			m.solid(true)
		"tractor":
			m.nika_end()


func _mount_move(old: Vector3, step: Vector3, r: float, delta: float) -> Vector3:
	## Кінь чи велосипед не проходить крізь стіни базару, хати, дерева й тини; річку — лише мостом.
	if _mount_body == null:
		_mount_body = CharacterBody3D.new()
		_mount_body.name = "MountBody"
		_mount_body.collision_layer = 0
		_mount_body.collision_mask = 1 << 17
		_mount_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		_mount_body.wall_min_slide_angle = 0.0
		var cs := CollisionShape3D.new()
		cs.shape = SphereShape3D.new()
		cs.position = Vector3(0, 0.9, 0)
		_mount_body.add_child(cs)
		add_child(_mount_body)
	((_mount_body.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius = r
	_mount_body.global_position = Vector3(old.x, 0, old.z)
	_mount_body.velocity = step / maxf(delta, 0.0001)
	_mount_body.move_and_slide()
	var p := _mount_body.global_position
	var bz = world.outer.bazaar
	if bz == null or not bz.in_area(p):
		p = Obstacles.push_out(p, r, 0.0, girl._obs())
	var rz: float = world.outer.RIVER_Z
	if absf(p.z - rz) < 5.5 and absf(p.x) > 1.25:
		if absf(old.z - rz) >= 5.5:
			p.z = old.z
		else:
			p.x = clampf(p.x, -1.25, 1.25)
	var yr: Rect2 = girl.YARD_R
	if yr.has_point(Vector2(old.x, old.z)) != yr.has_point(Vector2(p.x, p.z)) and absf(p.x) > 1.0:
		p = old
	if bz and bz.building_at(p) != null:
		p = old
	# люди й тварини — тверді: кінь, велосипед і машини їх не переїжджають
	if _mount:
		var sk := [_mount, girl]
		p = Util.push_solids(p, minf(r, 1.3), sk)
		if _mount_kind == "combine":
			var fw := Vector3(sin(_mount.rotation.y), 0, cos(_mount.rotation.y))
			for off in [2.6, -3.6]:
				var e: Vector3 = p + fw * off
				if Util.push_solids(e, 1.9, sk).distance_to(e) > 0.01 and (p - old).dot(fw * off) > 0.0:
					p = old                      # жатка чи корма впирається в когось — стоїмо
	var lim: float = world.outer.LIMIT
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	p.y = 0.0
	return p


func _mount_drive(delta: float) -> void:
	var m := _mount
	if m == null or not is_instance_valid(m):
		_mount_state = ""
		return
	var j: Vector2 = hud.flight.joy
	var fast: bool = hud.flight.climb > 0.0
	var yr := deg_to_rad(rig.yaw)
	var fwd := -Vector3(sin(yr), 0, cos(yr))
	var right := Vector3(cos(yr), 0, -sin(yr))
	var mv := right * j.x + fwd * j.y
	if not _auto_ride.is_empty() and _mount_kind in ["bike", "horse"]:
		if j.length() > 0.2:
			_auto_ride = []                      # джойстик — далі кермуєш сам
		else:
			var tg: Vector3 = _auto_ride[0]
			if Vector2(tg.x - m.global_position.x, tg.z - m.global_position.z).length() < 2.5:
				_auto_ride.pop_front()
				if _auto_ride.is_empty():
					girl.say("Приїхали в грибний ліс! Злізаю — і по гриби.", 3.0)
			if not _auto_ride.is_empty():
				var tg2: Vector3 = _auto_ride[0]
				mv = Vector3(tg2.x - m.global_position.x, 0, tg2.z - m.global_position.z).normalized()
				fast = true
	var is_bike := _mount_kind == "bike"
	var cabv := _mount_kind == "combine" or _mount_kind == "tractor"
	var vmax := (5.2 if fast else 3.0) if is_bike else (5.5 if fast else 1.8)
	if _mount_kind == "combine":
		vmax = 4.2 if fast else 2.4
	elif _mount_kind == "tractor":
		vmax = 5.0 if fast else 2.8
	elif _mount_kind == "horse" and _gait != "":
		vmax = {"walk": 3.0 if fast else 1.6, "trot": 5.0 if fast else 3.4, "gallop": 6.2}.get(_gait, vmax)
	elif is_bike and _gait == "slow":
		vmax *= 0.6
	if _mount_kind == "horse":
		vmax *= 2.0                               # верхи кінь іде й біжить удвічі швидше
	var want := 0.0
	var steer := 0.0
	if cabv:
		# комбайн і трактор — як справжня машина: джойстик уперед/назад — газ, вліво/вправо — кермо;
		# кермо крутиться плавно, а повертає машина лише на ходу (тим сильніше, чим швидше їде)
		var thr := j.y
		if absf(thr) < 0.15 and absf(j.x) > 0.3:
			thr = 0.35                               # лише кермо — повільно їде вперед і повертає
		want = vmax * clampf(thr, 0.0, 1.0) if thr > 0.0 else -1.0 * clampf(-thr, 0.0, 1.0)
		if absf(thr) < 0.12:
			want = 0.0
		var st_want := -clampf(j.x, -1.0, 1.0) * (0.42 if _mount_kind == "combine" else 0.5)
		_cab_steer = move_toward(_cab_steer, st_want, delta * 0.9)
		steer = _cab_steer
		var base := 3.6 if _mount_kind == "combine" else 2.4
		_old_yaw = m.rotation.y
		m.rotation.y = wrapf(m.rotation.y + _mount_v * tan(_cab_steer) / base * delta, -PI, PI)
	elif mv.length() > 0.12:
		want = vmax * clampf(mv.length(), 0.0, 1.0)
		var turn := wrapf(atan2(mv.x, mv.z) - m.rotation.y, -PI, PI)
		var rate := 2.0 if is_bike else 1.7
		if cabv:
			rate = 0.75 if _mount_kind == "combine" else 1.0
		if cabv and _mount_v < 0.3:
			rate *= 0.3 + _mount_v      # машина повертає лише на ходу
		if _mount_kind == "horse":
			# кінь повертає плавно: кутова швидкість наростає й спадає поступово
			_horse_turn_v = lerpf(_horse_turn_v, clampf(turn * 2.0, -rate, rate), 1.0 - exp(-delta * 3.0))
			m.rotation.y = wrapf(m.rotation.y + _horse_turn_v * delta, -PI, PI)
		else:
			m.rotation.y = wrapf(m.rotation.y + clampf(turn, -rate * delta, rate * delta), -PI, PI)
		steer = clampf(turn, -0.5, 0.5)
		if absf(turn) > 1.6:
			want *= 0.35
	if _mount_kind == "horse" and not (mv.length() > 0.12):
		_horse_turn_v = lerpf(_horse_turn_v, 0.0, 1.0 - exp(-delta * 4.0))
		m.rotation.y = wrapf(m.rotation.y + _horse_turn_v * delta, -PI, PI)
	var acc := (1.2 if cabv else (5.0 if _mount_kind == "horse" else 2.5)) if want > _mount_v else (2.0 if cabv else (6.0 if _mount_kind == "horse" else 4.0))
	_mount_v = move_toward(_mount_v, want, delta * acc)
	var old: Vector3 = m.global_position
	var step := Vector3(sin(m.rotation.y), 0, cos(m.rotation.y)) * _mount_v * delta
	var rad := 0.4 if is_bike else 0.7
	if _mount_kind == "combine":
		rad = 2.1
	elif _mount_kind == "tractor":
		rad = 1.2
	var p := _mount_move(old, step, rad, delta)
	if _mount_kind == "tractor" and m.trailer_blocked(p, m.rotation.y):
		# причіп упирається в хату, паркан чи дерево — стоїмо (не протягуємо його крізь них)
		m.rotation.y = _old_yaw
		p = old
		_mount_v = 0.0
	if cabv and p.distance_to(old) < step.length() * 0.3:
		_mount_v = move_toward(_mount_v, 0.0, delta * 6.0)          # уперлися — гальмуємо
	m.global_position = Vector3(p.x, Util.bridge_y(p), p.z)
	if is_bike or cabv:
		m.ride_anim(_mount_v, steer, delta)
	else:
		m.hitch_move(m.rotation.y, _mount_v, 0.0)
	girl.ride_step(delta, _mount_v)
	_mount_follow(delta, (absf(_mount_v) > 0.2) if cabv else (mv.length() > 0.3 and (j.y > 0.25 or not _auto_ride.is_empty())))


var _auto_ride: Array = []              # велосипед чи коник сам везе Ніку цими точками (у грибний ліс)


func _forest_ride_route(from: Vector3) -> Array:
	## Дорога в грибний ліс для велосипеда й коня: з дороги на південь повз садок (в обхід причепа), далі — дорогою до лісу.
	var road: Array = world.outer.EAST_ROAD
	var pts: Array = [Vector3(0.6, 0, 25.0), Vector3(23.0, 0, 25.0), Vector3(23.0, 0, 12.5), Vector3(29.0, 0, 12.5), Vector3(29.0, 0, 5.0)]
	for i in range(3, road.size()):
		pts.append(Vector3(road[i].x, 0, road[i].y))
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := Vector2(pts[i].x - from.x, pts[i].z - from.z).length()
		if d < bd:
			bd = d
			best = i
	var r: Array = Vehicles.route(from, pts[best])
	for i in range(best + 1, pts.size()):
		r.append(pts[i])
	return r


var _cab_steer := 0.0
var _old_yaw := 0.0
var _h_yaw := 0.0                       # як стане кінь, коли підбіжить до Ніки
var _gait := ""                         # кінь: walk / trot / gallop; велосипед: slow / ""
var _horse_turn_v := 0.0                 # кінь верхи: кутова швидкість повороту (рад/с)


func _mount_follow(delta: float, turning: bool) -> void:
	var bz = world.outer.bazaar
	if bz:
		bz.set_inside(null)
	world.in_building = false
	if _cam_b != null:
		_cam_b = null
		rig.dist_min = _dmin_out
		rig.dist_max = _dmax_out
		rig.inside_box = AABB()
	var m := _mount
	var base: Vector3 = m.global_position if m and is_instance_valid(m) else girl.global_position
	var fy: float = {"horse": 1.75, "combine": 3.0, "tractor": 1.7}.get(_mount_kind, 1.0)
	var dd: float = {"horse": 6.5, "combine": 11.5, "tractor": 7.5}.get(_mount_kind, 4.2)
	rig.focus = base + Vector3(0, fy, 0)
	rig.target = rig.target.lerp(rig.focus, 1.0 - exp(-delta * 8.0))
	var k := 1.0 - exp(-delta * 2.0)
	rig.dist = lerpf(rig.dist, dd, k)
	rig.pitch = lerpf(rig.pitch, -16.0, k)
	if turning and m:
		var w := rad_to_deg(m.rotation.y) + 180.0
		rig.yaw += wrapf(w - rig.yaw, -180.0, 180.0) * (1.0 - exp(-delta * 1.3))
	rig.yaw = wrapf(rig.yaw, rig.yaw_center - 180.0, rig.yaw_center + 180.0)


# ------------------------------------------------------------------ Ніка підходить і взаємодіє з усіма
# Торкнувся будь-кого (людей, тварин, Beep, продавців — і тих, кого додамо потім), коли керуєш Нікою:
# вона йде до нього, вітається, той відповідає, далі — звичайні справи цього персонажа (меню).
# Гриби, ягоди й яблука Ніка збирає сама у свій кошик.
const NOT_CHARACTERS := ["bike", "saddle_horse", "bz_tack", "trailer", "combine", "tractor", "bz_furn", "girl", "house", "room_exit", "bench",
	"plane", "bowl", "cart", "garden_cart", "gold_flower", "stall", "pies", "well", "terrarium", "drone", "firefly"]
const BIG_ANIMALS := ["horse", "bull", "cow", "dragon"]
const SMALL_ANIMALS := ["puppy", "hare", "bird", "gecko", "cat"]
const NIKA_HI := {
	"grandpa": ["Дідусю, привіт!", "Дідусю, а що ти робиш?", "Дідусю, я прийшла!"],
	"granny": ["Бабусю, привіт!", "Бабусю, а що в нас на обід?", "Бабусю, давай я допоможу!"],
	"puppy": ["Біме, хороший песик!", "Хто тут мій пухнастик?"],
	"beep": ["Beep, привіт!", "Біп-біп, друже!"],
	"horse": ["Конику, привіт!", "Який ти гарний, конику!"],
	"bull": ["Привіт, бичку! Тільки не бодайся!"],
	"hare": ["Зайчику, не бійся!"],
	"bird": ["Ціп-ціп-ціп!"],
	"bz_seller": ["Добрий день!", "А що у вас смачненьке?"],
}
const NIKA_REPLY := {
	"grandpa": ["Привіт, онучко!", "О, Ніка прийшла!"],
	"granny": ["Ой, Ніколько моя!", "Привіт, сонечко!"],
}


func _meet_begin(kind: String, node: Node3D, area: Area3D) -> bool:
	if _mount_state != "" or _acting != "":
		return false
	var target := Vector3.INF
	var r := 1.0
	if kind == "forest_item":
		if forest == null or area == null or not area.has_meta("item"):
			return false
		target = forest.goods_pos(int(area.get_meta("item")))
		r = 0.55
	elif kind == "orchard_tree":
		if orchard == null or area == null or not area.has_meta("tree"):
			return false
		target = orchard.pick_spot(int(area.get_meta("tree")), girl.global_position)
		r = 0.35
	elif kind == "nk_basket" or kind == "item":
		if node == null or not is_instance_valid(node) or node == girl.held:
			return false
		target = node.global_position
		r = 0.8 if node.global_position.y > girl.global_position.y + 0.3 else 0.45
	elif kind == "bz_seller" or kind == "bz_shop":
		var sd := _seller_dict(node, area)
		if sd.is_empty():
			return false
		target = sd["front"]
		r = 0.35
	else:
		if kind in NOT_CHARACTERS or node == null or not is_instance_valid(node) or node == girl:
			return false
		if not (node.has_method("say") or node.has_method("poke") or node.has_method("pet") or node.has_method("talk")):
			return false
		target = node.global_position
		r = 2.3 if kind in BIG_ANIMALS or kind.contains("horse") else (0.8 if kind in SMALL_ANIMALS else 1.05)
	target.y = 0.0
	_meet = {"kind": kind, "node": node, "area": area, "r": r}
	_furn = null
	_girl_stuck = 0.0
	if Vector2(girl.global_position.x - target.x, girl.global_position.z - target.z).length() < r + 0.3:
		_girl_goal = Vector3.INF
		_goal_route = []
		_meet_arrive()
		return true
	_goal_route = _girl_route_to(target)
	_girl_goal = _goal_route.pop_front()
	return true


func _meet_arrive() -> void:
	var m: Dictionary = _meet
	_meet = null
	_girl_goal = Vector3.INF
	_goal_route = []
	var kind: String = m["kind"]
	var node = m["node"]
	var area = m["area"]
	match kind:
		"forest_item":
			_nika_pick_forest(area)
		"orchard_tree":
			_nika_pick_tree(area)
		"nk_basket":
			if node and is_instance_valid(node):
				_girl_face(node.global_position)
				girl.pick_basket(node)
				_basket_world = null
				_gesture_t = 0.7
		"item":
			_nika_take(node)
		"bz_seller", "bz_shop":
			var sd := _seller_dict(node, area)
			if not sd.is_empty():
				_shop_open(sd)
		"hangar_btn":
			_nika_press_btn()
		"plane_board":
			_nika_board_plane()
		_:
			if node == null or not is_instance_valid(node):
				return
			_nika_greet(kind, node)


# ------------------------------------------------------------------ ангар: кнопка воріт і Ніка сама сідає в літак
var _pressing := false


func _nika_meet_route(kind: String, node: Node3D, area, wp: Array, r := 0.3) -> void:
	_meet = {"kind": kind, "node": node, "area": area, "r": r}
	_furn = null
	_girl_stuck = 0.0
	_goal_route = _girl_route_to(wp[0]) + wp.slice(1)
	_girl_goal = _goal_route.pop_front()


func _hangar_around(a: Vector2) -> Array:
	## Ніка надворі біля ангара — обходить його збоку до воріт.
	var o = world.outer
	var HX: float = o.HANGAR_HX
	var cz: float = -o.HANGAR_HZ - 1.7 if a.y < 0.0 else o.HANGAR_HZ + 1.7
	var wp: Array = []
	if a.x > -HX - 0.5 and absf(a.y) < 12.0:
		wp.append(o.air_world(maxf(a.x, -HX), cz))
		wp.append(o.air_world(-HX - 2.0, cz))
	return wp


func _nika_btn_go(area) -> void:
	## Ніка йде до кнопки на задній стіні ангара (зсередини чи ззовні — з того боку, де вона є).
	var o = world.outer
	var side := float(area.get_meta("side")) if area and area.has_meta("side") else -1.0
	var inside: bool = o.in_hangar(girl.global_position)
	if not o.hangar_open:
		side = -1.0 if inside else 1.0
	var HX: float = o.HANGAR_HX
	var HZ: float = o.HANGAR_HZ
	var BZ: float = o.HANGAR_BTN_Z
	var a: Vector2 = o.air_local(girl.global_position)
	var wp: Array = []
	if side < 0.0:
		if not inside:
			wp.append_array(_hangar_around(a))
			wp.append(o.air_world(-HX - 2.5, BZ))
			wp.append(o.air_world(-HX + 1.0, BZ))
		wp.append(o.air_world(HX - 1.15, BZ))
	else:
		if inside:
			wp.append(o.air_world(-HX + 1.0, BZ))
			wp.append(o.air_world(-HX - 2.5, BZ))
			a = Vector2(-HX - 2.5, BZ)
		if a.x < HX + 0.5:
			if a.y > HZ:
				wp.append(o.air_world(HX + 2.0, HZ + 1.7))
			else:
				if a.x < -HX:
					wp.append(o.air_world(-HX - 2.0, -HZ - 1.7))
				wp.append(o.air_world(HX + 2.0, -HZ - 1.7))
		wp.append(o.air_world(HX + 1.15, BZ))
	girl.say("Натисну кнопку воріт!", 1.8)
	_nika_meet_route("hangar_btn", area.get_parent() if area else null, area, wp)


func _nika_press_btn() -> void:
	var o = world.outer
	var gp: Vector3 = girl.global_position
	var a: Vector2 = o.air_local(gp)
	var side := -1.0 if o.in_hangar(gp) else 1.0
	if absf(a.y - o.HANGAR_BTN_Z) > 1.3 or absf(a.x - (o.HANGAR_HX + side * 1.15)) > 1.3:
		girl.say("Не дотягнуся до кнопки…", 2.0)
		return
	if plane and (riding or plane.state == "taxi"):
		return
	_pressing = true
	_gesture_t = 4.0
	var b := Vector3(o.HANGAR_HX + side * 0.09, 1.0, o.HANGAR_BTN_Z)
	await girl.press_button(o.hangar_node, b, side, func(): o.press_hangar_btn(side))
	var aborted: bool = girl._keys_abort
	_pressing = false
	if aborted:
		return
	_gesture_t = 0.0
	if _ctl_girl:
		girl.say("Ворота відчиняються!" if o.hangar_open else "Ворота зачиняються!", 2.0)


func _nika_plane_go() -> void:
	## Торкнулась літака — Ніка йде до нього (в ангарі — крізь відчинені ворота) і сама залазить у кабіну.
	if plane.state != "rest":
		plane.poke()
		return
	var o = world.outer
	if plane.in_hangar and not o.hangar_open:
		girl.say("Ворота ангара зачинені! Натисну кнопку на задній стіні.", 3.0)
		return
	var b: Vector3 = plane.to_global(plane.climb_frame()["ground"])
	b.y = 0.0
	var wp: Array = []
	if plane.in_hangar and not o.in_hangar(girl.global_position):
		wp.append_array(_hangar_around(o.air_local(girl.global_position)))
		wp.append(o.air_world(-o.HANGAR_HX - 2.5, o.HANGAR_BTN_Z))
		wp.append(o.air_world(-o.HANGAR_HX + 1.0, o.HANGAR_BTN_Z))
	wp.append(b)
	girl.say("Іду до літака!", 1.8)
	_nika_meet_route("plane_board", plane, null, wp)


func _nika_board_plane() -> void:
	if plane == null or riding or plane.state != "rest" or not _ctl_girl:
		return
	if plane.in_hangar and not world.outer.hangar_open:
		girl.say("Ворота зачинені — спершу кнопка на задній стіні!", 2.5)
		return
	var b: Vector3 = plane.to_global(plane.climb_frame()["ground"])
	if Vector2(girl.global_position.x - b.x, girl.global_position.z - b.z).length() > 2.5:
		girl.say("Не можу підійти до літака…", 2.0)
		return
	stop_girl_control(true)
	riding = true
	cam_follow = null
	plane.auto_door = false
	_track = girl
	rig.glide_to(6.5, -14.0)
	girl.say("Сідаю за штурвал!", 2.0)
	await girl.board_plane(plane)
	if not riding:
		return
	plane.rider = girl
	_track = plane
	plane.say("Р-р-р-р! Мотор працює!", 2.0)
	girl.say("Лечу-у-у!", 2.0)
	await get_tree().create_timer(0.8).timeout
	if not riding:
		return
	_track = null
	hud.show_flight(true)
	hud.flight.home_text = "В ангар"
	hud.flight.land_text = "Сісти"
	hud.toast("Джойстик — кермо, ▲▼ — висота", 4.0)
	rig.glide_to(12.0, -12.0)
	await plane.take_off(true)


func _girl_face(p: Vector3) -> void:
	var d: Vector3 = p - girl.global_position
	if Vector2(d.x, d.z).length() > 0.05:
		girl.rotation.y = atan2(d.x, d.z)


func _nika_gesture(anim: String, max_t := 2.2) -> void:
	if girl.anims.get(anim, "") == "":
		anim = "talk" if girl.anims.get("talk", "") != "" else "idle"
	girl.play(anim)
	_gesture_t = clampf(girl.anim_length(anim), 0.8, max_t)


func _nika_greet(kind: String, node: Node3D) -> void:
	_girl_face(node.global_position)
	var hi: Array = NIKA_HI.get(kind, ["Привіт!", "Добрий день!", "Як справи?"])
	girl.say(hi[randi() % hi.size()], 2.2)
	if kind in SMALL_ANIMALS:
		_nika_gesture("crouch_pick", 1.8)        # присідає погладити
	else:
		_nika_gesture("talk", 2.0)
	# співрозмовник повертається до Ніки (якщо зараз нічим не зайнятий)
	var idle_now := str(node.get("doing")) in ["", "<null>"] and not bool(node.get("moving") if node.get("moving") != null else false)
	if node.has_method("face") and idle_now:
		node.face(girl.global_position)
	await get_tree().create_timer(1.1).timeout
	if not is_instance_valid(node) or not _ctl_girl:
		return
	match kind:
		"puppy":
			puppy.pet(girl.global_position)
			audio.play_at("puppy_bark", puppy, -2.0, 1.1)
		"beep":
			beep.hop()
			beep.say("Біп-буп! Привіт, Ніко!", 2.5)
			audio.play_at("robot_beep", beep, 0.0)
		"bull", "horse", "hare", "bird":
			if node.has_method("poke"):
				node.poke()
				audio.play_at("pop", node, -6.0, 1.0)
		_:
			if NIKA_REPLY.has(kind) and node.has_method("say") and idle_now:
				var rp: Array = NIKA_REPLY[kind]
				node.say(rp[randi() % rp.size()], 2.2)
				await get_tree().create_timer(1.0).timeout
				if not is_instance_valid(node) or not _ctl_girl:
					return
			# далі — звичайні справи персонажа (меню дідуся, бабусі, Тарасика, продавця…)
			hit_node = node
			_last_tap = rig.cam.unproject_position(node.global_position + Vector3(0, 0.6, 0))
			if kind in ["grandpa", "granny", "npc", "bz_seller", "kid"] or not NIKA_REPLY.has(kind):
				_tap_object(kind)


func _nika_pick_forest(area) -> void:
	if forest == null or area == null or not is_instance_valid(area):
		return
	var gi: int = area.get_meta("item")
	_girl_face(forest.goods_pos(gi))
	if not forest.can_take(gi):
		girl.say(forest.label(gi), 2.0)
		return
	if not girl.has_basket():
		girl.say("Спершу треба взяти кошик! Він біля хати («Меню» → «Взяти кошик»).", 3.0)
		return
	_nika_gesture("crouch_pick" if randf() < 0.6 else "pick", 2.4)
	var col: Color = forest.kind_color(gi)
	await get_tree().create_timer(0.9).timeout
	if forest.take(gi) > 0:
		Util.basket_add(girl._bk, col, 0.05)
		girl.say("%s — у кошик!" % forest.label(gi), 2.0)
		audio.play("pop", -8.0, 1.1)
		Game.add_coins(1)
		Game.emit_event("forest")


func _nika_pick_tree(area) -> void:
	if orchard == null or area == null or not is_instance_valid(area):
		return
	var ti: int = area.get_meta("tree")
	_girl_face(orchard.tree_pos(ti))
	if not girl.has_basket():
		girl.say("Візьму кошик — тоді назбираю!", 2.5)
		return
	_nika_gesture("tree_pick", 2.6)
	await get_tree().create_timer(1.0).timeout
	var got: int = orchard.pick(ti, 3)
	if got > 0:
		for i in got:
			Util.basket_add(girl._bk, Color(0.85, 0.22, 0.15), 0.045)
		girl.say("Зірвала %d — %s!" % [got, orchard.fruit_name(ti)], 2.2)
		audio.play("pop", -8.0, 1.2)
		Game.add_coins(got)
	else:
		girl.say(orchard.describe(ti), 2.5)


# ------------------------------------------------------------------ обхід перешкод, коли Ніка йде сама (торкнулися землі чи когось)
var _detour_t := 0.0
var _detour_sign := 1.0


func _detour(dir: Vector3) -> Vector3:
	## Уперлася (паркан, віз, комбайн) — якийсь час іде навскіс, щоб обійти.
	if _detour_t > 0.0:
		return dir.rotated(Vector3.UP, _detour_sign * 1.15)
	return dir


func _detour_update(moved: float, delta: float) -> void:
	if _detour_t > 0.0:
		_detour_t -= delta
		return
	if moved < 0.3 * delta and _girl_stuck > 0.3:
		_detour_sign = -_detour_sign
		_detour_t = 0.9 + randf() * 0.5


const TACK_PRICE := 30


func _buy_tack() -> void:
	## Сідло й вуздечка в ларьку з інструментами: Ніка купує за монети, і комплект зникає з прилавка.
	var bz = world.outer.bazaar if world.outer else null
	if bz == null or bz.tack_holder == null:
		return
	var coins := int(Game.state["coins"])
	if bz.tack_sold:
		hud.toast("Сідло з вуздечкою вже купили!", 3.0)
	elif girl == null or not _ctl_girl or girl.global_position.distance_to(bz.tack_holder.global_position) > 6.0:
		hud.toast("Сідло й вуздечка — %d монет. Підійди Нікою до ларька, щоб купити" % TACK_PRICE, 3.5)
	elif coins < TACK_PRICE:
		girl.say("Ой, у мене лише %d монет… Треба %d." % [coins, TACK_PRICE], 2.5)
	else:
		Game.add_coins(-TACK_PRICE)
		bz.sell_tack()
		girl.say("Купила сідло й вуздечку! Віднесу дідусеві в сарай.", 3.0)
		audio.play("coins", -8.0)


# ------------------------------------------------------------------ причепи трактора: плуг і причіп
func _show_hitch_menu() -> void:
	if tractor == null:
		return
	var tr_on: bool = tractor.trailer != null
	hud.show_hitch_menu({
		"th_plow_up": tractor.plow_on, "th_plow_down": tractor.plow_on,
		"th_plow_off": tractor.plow_on, "th_plow_on": not tractor.plow_on and not tr_on,
		"th_up": tr_on, "th_down": tr_on,
		"th_trl_on": trailer != null and not tr_on, "th_trl_off": tr_on,
	})


func _hitch_do(name: String) -> void:
	if tractor == null:
		return
	match name:
		"th_plow_up":
			tractor.plow_down = false
		"th_plow_down":
			tractor.plow_down = true
		"th_plow_off":
			if tractor.detach_plow():
				hud.toast("Плуг відчеплено — лишився на землі. Причепиш, коли під'їдеш до нього задом", 4.0)
				audio.play("pop", -6.0, 0.8)
		"th_plow_on":
			match tractor.attach_plow():
				"ok":
					hud.toast("Плуг причеплено!", 2.5)
					audio.play("pop", -6.0, 1.0)
				"trailer":
					hud.toast("Спершу відчепи причіп", 3.0)
				"far":
					hud.toast("Плуг далеко — під'їдь до нього задом впритул", 3.5)
		"th_trl_on":
			match tractor.attach_trailer(trailer):
				"ok":
					hud.toast("Причіп причеплено! ▲ / ▼ — кузов угору й униз", 3.5)
					audio.play("pop", -6.0, 1.0)
				"plow":
					hud.toast("Спершу відчепи плуг", 3.0)
				"far":
					hud.toast("Причіп далеко — під'їдь задом до його дишла", 3.5)
		"th_trl_off":
			if tractor.trailer and tractor.trailer.tip_k > 0.05:
				tractor.trailer.tip_want = 0.0
			tractor.detach_trailer()
			hud.toast("Причіп відчеплено", 2.5)
		"th_up":
			if tractor.trailer:
				tractor.trailer.tip_want = 1.0
		"th_down":
			if tractor.trailer:
				tractor.trailer.tip_want = 0.0


# ------------------------------------------------------------------ кошик Ніки: стоїть біля хати, вона бере його сама
var _basket_world: Node3D = null


func _make_world_basket() -> void:
	if girl == null or girl.has_basket():
		return
	if _basket_world != null and is_instance_valid(_basket_world):
		return
	var b := Util.basket()
	girl.get_parent().add_child(b)
	b.global_transform = Transform3D(Basis().scaled(Vector3.ONE * girl.BK_SCALE), girl.HOME_YARD + Vector3(0.9, 0, 0.6))
	var a := Util.pick_area("nk_basket", Vector3(0.5, 0.5, 0.5), Vector3(0, 0.2, 0))
	a.name = "Pick"
	b.add_child(a)
	_basket_world = b


# ------------------------------------------------------------------ речі: взяти в руки, з'їсти, випити
func _nika_take(n: Node3D) -> void:
	if n == null or not is_instance_valid(n) or girl == null:
		return
	var k := String(n.get_meta("item_kind", ""))
	var gp: Vector3 = girl.global_position
	if Vector2(n.global_position.x - gp.x, n.global_position.z - gp.z).length() > 1.4:
		girl.say("Не дістану…", 1.6)
		return
	_gesture_t = 0.8
	await girl.take_item(n, k)
	if girl.held != n:
		return
	if k in Util.FOOD:
		await girl.eat_held()
	else:
		girl.say("Беру %s!" % Util.THING_NAMES.get(k, "це"), 1.8)


# ------------------------------------------------------------------ базар: продавці питають, пропонують і подають товар
var _shop := {}
var _shop_t := 0.0


func _seller_dict(node, area) -> Dictionary:
	var bz = world.outer.bazaar if world and world.outer else null
	if bz == null:
		return {}
	var hn = node
	if area != null and is_instance_valid(area) and area.has_meta("seller"):
		hn = area.get_meta("seller")
	return bz.seller_of(hn)


func _shop_open(sd: Dictionary) -> void:
	var bz = world.outer.bazaar
	if bz == null or sd.is_empty() or not sd.has("shop"):
		return
	_shop = sd
	sd["greet_t"] = Time.get_ticks_msec() / 1000.0
	_girl_face(sd["pos"])
	var cat: String = sd["shop"]
	bz.seller_say(sd["node"], String(bz.SHOP_ASK.get(cat, "Що бажаєш?")))
	audio.play("question", -8.0, 1.1)
	var items: Array = []
	var goods: Array = bz.GOODS.get(cat, [])
	var cols := [Color(0.85, 0.5, 0.2), Color(0.7, 0.4, 0.3), Color(0.55, 0.6, 0.3), Color(0.4, 0.55, 0.75), Color(0.6, 0.45, 0.7)]
	for i in goods.size():
		items.append(["sh_%d" % i, "%s — %d мон." % [goods[i][0], goods[i][1]], cols[i % cols.size()]])
	if cat == "tools" and bz.tack_holder != null and not bz.tack_sold:
		items.append(["sh_tack", "Сідло й вуздечка — %d мон." % TACK_PRICE, Color(0.55, 0.4, 0.25)])
	var title: String = {"sausage": "Ковбаси й сало", "tools": "Інструменти", "sweets": "Солодощі", "bread": "Хліб", "fruit": "Фрукти"}.get(cat, "Ларьок")
	hud.show_choice("%s — у тебе %d мон." % [title, int(Game.state["coins"])], items, Color(0.85, 0.55, 0.2))


const GOODS_COLOR := {"sausage": Color(0.55, 0.18, 0.12), "salo": Color(0.96, 0.88, 0.82), "ham": Color(0.82, 0.45, 0.42),
	"candy": Color(0.95, 0.2, 0.25), "gingerbread": Color(0.6, 0.35, 0.15), "sweets": Color(0.9, 0.6, 0.2), "bread": Color(0.7, 0.42, 0.18),
	"baton": Color(0.8, 0.52, 0.22), "bun": Color(0.82, 0.55, 0.25), "apple": Color(0.85, 0.18, 0.12), "pear": Color(0.8, 0.78, 0.25),
	"plum": Color(0.35, 0.15, 0.45)}


func _shop_buy(id: String) -> void:
	var sd := _shop
	var bz = world.outer.bazaar
	if sd.is_empty() or bz == null or girl == null or not _ctl_girl:
		return
	if id == "sh_tack":
		_buy_tack()
		return
	var i := int(id.trim_prefix("sh_"))
	var goods: Array = bz.GOODS.get(String(sd["shop"]), [])
	if i < 0 or i >= goods.size():
		return
	var g: Array = goods[i]
	var price := int(g[1])
	var k := String(g[2])
	if girl.global_position.distance_to(sd["front"]) > 3.5:
		hud.toast("Підійди ближче до ларька", 2.5)
		return
	if int(Game.state["coins"]) < price:
		girl.say("Ой, у мене лише %d монет…" % int(Game.state["coins"]), 2.2)
		bz.seller_say(sd["node"], "Приходь, як назбираєш %d монет!" % price)
		return
	Game.add_coins(-price)
	audio.play("coins", -8.0)
	bz.seller_say(sd["node"], ["Тримай, Ніко!", "Будь ласка! Смачного!", "На здоров'я!", "Дякую за покупку!"][randi() % 4])
	bz.seller_give(sd)
	# продавець подає — річ із його рук пливе до Ніки
	var it := Util.thing(k)
	if it == null:
		return
	girl.get_parent().add_child(it)
	it.global_position = (sd["pos"] as Vector3) + Vector3(0, 1.0, 0)
	var to: Vector3 = girl.global_position + Vector3(0, 0.5, 0) + girl.global_transform.basis.z.normalized() * 0.22
	var tw := create_tween()
	tw.tween_property(it, "global_position", to, 0.8).set_trans(Tween.TRANS_SINE)
	await tw.finished
	if not is_instance_valid(it):
		return
	if k in Util.FOOD and girl.has_basket():
		await girl.take_item(it, k)
		var o: Node3D = girl.drop()
		if o:
			o.queue_free()
		girl.item_kind = ""
		Util.basket_add(girl._bk, GOODS_COLOR.get(k, Color(0.8, 0.6, 0.3)), 0.045)
		girl.say("Дякую! Кладу %s в кошик." % Util.THING_NAMES.get(k, "покупку"), 2.2)
		audio.play("pop", -8.0, 1.1)
	else:
		await girl.take_item(it, k)
		girl.say("Дякую! Купила %s." % Util.THING_NAMES.get(k, "покупку"), 2.2)


func _shop_check(delta: float, moving: bool) -> void:
	## Ніка підійшла до ларька й зупинилась — продавець сам питає й пропонує товар.
	_shop_t += delta
	if _shop_t < 0.4:
		return
	_shop_t = 0.0
	var bz = world.outer.bazaar
	if bz == null or moving or _acting != "" or _mount_state != "" or not bz.in_area(girl.global_position):
		return
	var sd: Dictionary = bz.seller_near(girl.global_position, 1.4)
	if sd.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(sd.get("greet_t", -100.0)) < 30.0:
		return
	_shop_open(sd)


# ------------------------------------------------------------------ у кожного транспорту — своє меню
func _show_vehicle_menu() -> void:
	match _mount_kind:
		"tractor":
			_show_hitch_menu()
		"horse":
			hud.show_choice("Коник", [
				["vm_walk", "Кроком", Color(0.55, 0.45, 0.3)],
				["vm_trot", "Риссю", Color(0.65, 0.45, 0.25)],
				["vm_gallop", "Галопом!", Color(0.75, 0.35, 0.2)],
				["vm_pat", "Погладити коника", Color(0.45, 0.6, 0.4)],
				["vm_forest", "У грибний ліс", Color(0.35, 0.55, 0.3)],
				["vm_off", "Злізти", Color(0.45, 0.45, 0.6)]], Color(0.6, 0.42, 0.25))
		"bike":
			hud.show_choice("Велосипед", [
				["vm_bell", "Дзвоник: дзінь-дзінь!", Color(0.3, 0.6, 0.85)],
				["vm_slow", "Їхати повільно", Color(0.4, 0.6, 0.45)],
				["vm_fast", "Їхати швидко", Color(0.8, 0.45, 0.25)],
				["vm_forest", "У грибний ліс", Color(0.35, 0.55, 0.3)],
				["vm_off", "Злізти", Color(0.45, 0.45, 0.6)]], Color(0.3, 0.6, 0.85))
		"combine":
			hud.show_choice("Комбайн", [
				["vm_reel", "Мотовило: " + ("зупинити" if combine and combine.reel_on else "запустити"), Color(0.8, 0.5, 0.2)],
				["vm_horn", "Посигналити", Color(0.8, 0.28, 0.2)],
				["vm_off", "Злізти", Color(0.45, 0.45, 0.6)]], Color(0.8, 0.28, 0.2))


func _vehicle_do(name: String) -> void:
	if _mount_state != "ride" or girl == null:
		return
	match name:
		"vm_walk", "vm_trot", "vm_gallop":
			_gait = name.trim_prefix("vm_")
			girl.say({"walk": "Кроком, коником…", "trot": "Риссю, но-о!", "gallop": "Галопом! Ура-а!"}[_gait], 1.8)
			if _mount and _mount.has_method("say"):
				_mount.say("І-го-го!", 1.2)
		"vm_pat":
			girl.say("Хороший коник, розумничок!", 2.0)
			if _mount and _mount.has_method("say"):
				_mount.say("Пфррр!", 1.5)
		"vm_bell":
			girl.say("Дзінь-дзінь!", 1.4)
			audio.play("magic_bells", -10.0, 1.6)
		"vm_slow":
			_gait = "slow"
		"vm_fast":
			_gait = ""
		"vm_reel":
			if combine:
				combine.reel_on = not combine.reel_on
		"vm_horn":
			girl.say("Біп-біп!", 1.4)
			audio.play("robot_beep", -4.0, 0.5)
		"vm_forest":
			if _mount:
				_auto_ride = _forest_ride_route(_mount.global_position)
				girl.say("Їду в ліс по гриби та ягоди!", 2.0)
		"vm_off":
			dismount()
