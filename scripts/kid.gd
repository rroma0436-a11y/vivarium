extends "res://scripts/npc.gd"
## Тарасик, сусідський хлопчик. Носить воду з криниці відром — наливає Бімові в мисочку
## й курям у корито; грається з Бімом у доганялки; ходить дивитися на соняшники.

var bucket: Node3D
var bucket_water: MeshInstance3D
var _water_day := -1


func make_bucket() -> void:
	## Відро стоїть біля криниці, коли ним не користуються.
	bucket = Node3D.new()
	var tin := Util.mat(Color(0.62, 0.66, 0.7), 0.35, 0.6)
	bucket.add_child(Util.cyl(0.13, 0.1, 0.24, tin, Vector3(0, 0.12, 0)))
	bucket_water = Util.cyl(0.12, 0.12, 0.01, Util.mat(Color(0.5, 0.75, 1.0), 0.05, 0.0, Color(0.3, 0.6, 0.9), 0.2), Vector3(0, 0.21, 0))
	bucket.add_child(bucket_water)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.12
	tm.outer_radius = 0.13
	tm.rings = 12
	tm.ring_segments = 4
	handle.mesh = tm
	handle.material_override = tin
	handle.rotation_degrees = Vector3(90, 0, 0)
	handle.position = Vector3(0, 0.24, 0)
	handle.scale = Vector3(1, 1, 1.0)
	bucket.add_child(handle)
	bucket_water.visible = false
	main.world.yard_root.add_child(bucket)
	bucket.position = main.world.spots["well_front"] + Vector3(-0.3, 0, -0.5)
	Walker.remember_home(bucket)


func choose_job() -> bool:
	var s := Game.state
	var h := Game.hour()
	if h > 8.0 and h < 19.0 and _water_day != int(s["day"]) and (float(s["water_bowl"]) < 25.0 or float(s["trough"]) < 25.0) and randf() < 0.5:
		water_job()
		return true
	var r := randf()
	if r < 0.15:
		play_with_bim()
		return true
	if r < 0.25:
		look_at_field()
		return true
	return false


func water_job() -> void:
	## Двічі по воду: Бімові в мисочку, потім курочкам у корито.
	if doing == "water":
		return
	var id := begin_job("water")
	_water_day = int(Game.state["day"])
	say("Піду наберу води!", 2.5)
	var sp: Dictionary = main.world.spots
	for target in ["water_bowl", "trough"]:
		await go(bucket.global_position + Vector3(0.0, 0, 0.45))
		if id != job:
			return
		face(sp["well"])
		await wait(0.4)
		# бере відро й набирає воду з криниці
		hold(bucket, Vector3(0, 0.3, 0.0), false, Basis(Vector3.RIGHT, PI))
		bucket_water.visible = false
		face(sp["well"])
		_sound("metal_drop")
		await main.world.well_draw()     # відро криниці опускається й піднімається, коловорот крутиться
		if id != job:
			return
		bucket_water.visible = true
		_sound("well_done" if false else "pop")
		var tp: Vector3 = sp[target]
		var wf: Vector3 = sp["well_front"]
		var stand: Vector3 = tp + (wf - tp).normalized() * 0.55
		await go(stand)
		if id != job:
			return
		face(tp)
		await wait(0.4)
		await _pour(id)
		if id != job:
			return
		Game.state[target] = 100.0
		Game.emit_event("water_carried")
		if target == "water_bowl":
			say("Пий, Біме!", 2.0)
			if main.puppy and not main.puppy.in_house:
				main.puppy.go_drink()
		else:
			say("Курочки, водичка!", 2.0)
			for b in main.world.yard_root.get_children():
				if "rooster" in b and b.mode == "free":
					b.go_eat(tp, "trough")
		# назад до криниці з порожнім відром
		await go(main.world.spots["well_front"] + Vector3(0.5, 0, 0.35))
		if id != job:
			return
		put_back_held()
	bucket_water.visible = false
	end_job(id)


func _pour(id: int) -> void:
	## Нахиляє відро — ллється вода.
	if bucket == null:
		return
	var fx := CPUParticles3D.new()
	fx.amount = 30
	fx.lifetime = 0.5
	fx.direction = Vector3(0, -1, 0)
	fx.spread = 18.0
	fx.initial_velocity_min = 0.5
	fx.initial_velocity_max = 1.0
	fx.gravity = Vector3(0, -6, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.03
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.8, 1.0, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	fx.mesh = sm
	main.world.yard_root.add_child(fx)
	fx.global_position = global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 0.35 + Vector3(0, 0.35, 0)
	_sound("sparkle")
	var b0 := bucket.rotation
	var t := 0.0
	while t < 1.8 and id == job:
		t += get_process_delta_time()
		bucket.rotation.x = b0.x + deg_to_rad(70.0) * clampf(t / 0.5, 0.0, 1.0)
		if t > 1.3:
			bucket_water.visible = false
		await get_tree().process_frame
	bucket.rotation = b0
	fx.emitting = false
	await wait(0.6)
	fx.queue_free()


func play_with_bim() -> void:
	## Доганялки: Тарасик бігає, Бім — за ним.
	if main.puppy == null or main.puppy.doing != "" or main.puppy.in_house:
		return
	var id := begin_job("play")
	say("Біме, наздоганяй!", 2.5)
	var pup = main.puppy
	var old = pup.follow
	pup.follow = self
	for i in 4:
		var p := Vector3(randf_range(-6.0, 3.0), 0, randf_range(-3.5, 3.5))
		walk_to(p, true)
		pup.walk_to(p + Vector3(randf_range(-0.6, 0.6), 0, 0.8), true)
		await arrived
		if id != job:
			break
		await wait(0.5)
	pup.follow = old
	if id == job:
		say("Ха-ха! Ти швидкий!", 2.0)
		pup.act("wag", 2.0)
	end_job(id)


func look_at_field() -> void:
	var id := begin_job("field")
	await go(Vector3(8.2, 0, randf_range(-5.0, -1.0)))
	if id != job:
		return
	face(Vector3(14, 0, -4))
	await wait(0.8)
	var h: float = float(Game.state["field"]["growth"])
	say("Ого, які соняшники!" if h > 0.6 else ("Соняшники хочуть пити…" if float(Game.state["field"]["water"]) < 25.0 else "Ростуть, ростуть!"), 3.0)
	await wait(3.0)
	end_job(id)


func _sound(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -10.0)
