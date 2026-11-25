extends "res://scripts/npc.gd"
## Гвинтик — маленький робот-помічник. Збирає яйця в курнику й несе кошик дідусеві на ґанок,
## носить дрова до хати, а коли все зроблено — танцює.

var basket: Node3D
var porch_basket: Node3D
var woodpile: Node3D
var _eggs_day := -1
var _wood_day := -1


func make_props() -> void:
	var wp: Dictionary = main.world.spots
	# кошик, з яким ходить по яйця (стоїть біля курника)
	basket = _basket(false)
	main.world.yard_root.add_child(basket)
	basket.position = wp["coop_door"] + Vector3(-0.5, 0, 0.7)
	Walker.remember_home(basket)
	# кошик з яйцями на ґанку (з'являється, коли Гвинтик їх приніс)
	porch_basket = _basket(true)
	main.world.yard_root.add_child(porch_basket)
	porch_basket.position = wp["porch"] + Vector3(1.0, 0, -0.5)
	porch_basket.visible = int(Game.state.get("eggs", 0)) > 0
	# купка дров біля дверей, яка росте
	woodpile = Node3D.new()
	main.world.yard_root.add_child(woodpile)
	woodpile.position = wp["porch"] + Vector3(-1.5, 0, -0.6)


func _basket(with_eggs: bool) -> Node3D:
	var n := Node3D.new()
	var wick := Util.mat(Color(0.72, 0.52, 0.28), 0.95)
	n.add_child(Util.cyl(0.17, 0.13, 0.15, wick, Vector3(0, 0.075, 0)))
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.14
	tm.outer_radius = 0.16
	tm.rings = 14
	tm.ring_segments = 4
	handle.mesh = tm
	handle.material_override = wick
	handle.rotation_degrees = Vector3(90, 0, 0)
	handle.position = Vector3(0, 0.15, 0)
	n.add_child(handle)
	var eggs := Node3D.new()
	eggs.name = "eggs"
	var em := Util.mat(Color(0.98, 0.95, 0.88), 0.5)
	var em2 := Util.mat(Color(0.88, 0.72, 0.55), 0.5)
	for i in 5:
		var a := i * TAU / 5.0
		eggs.add_child(Util.sphere(0.035, em if i % 2 == 0 else em2, Vector3(cos(a) * 0.07, 0.15, sin(a) * 0.07), Vector3(1, 1.3, 1)))
	eggs.visible = with_eggs
	n.add_child(eggs)
	return n


func choose_job() -> bool:
	var h := Game.hour()
	var d := int(Game.state["day"])
	if h > 8.0 and h < 18.0 and _eggs_day != d and randf() < 0.35 and Game.current_quest().get("id", "") != "eggs":
		eggs_job()
		return true
	if h > 9.0 and h < 19.0 and _wood_day != d and randf() < 0.35:
		firewood_job()
		return true
	if randf() < 0.2:
		dance()
		return true
	return false


func eggs_job() -> void:
	if doing == "eggs":
		return
	var id := begin_job("eggs")
	_eggs_day = int(Game.state["day"])
	var sp: Dictionary = main.world.spots
	say("Біп! Іду по яйця!", 2.5)
	await go(basket.global_position + Vector3(0, 0, 0.4))
	if id != job:
		return
	hold(basket, Vector3(0, 0.22, 0.0), false, Basis(Vector3.RIGHT, PI))
	await go(sp["coop_door"] + Vector3(-0.45, 0, 0))
	if id != job:
		return
	face(sp["coop"])
	say("Раз… два… три яйця!", 2.5)
	_sound("pop")
	await wait(1.0)
	basket.get_node("eggs").visible = true
	await wait(1.4)
	if id != job:
		return
	await go(porch_basket.global_position + Vector3(0.4, 0, 0.5))
	if id != job:
		return
	face(porch_basket.global_position)
	await wait(0.5)
	basket.get_node("eggs").visible = false
	put_back_held()
	porch_basket.visible = true
	Game.state["eggs"] = int(Game.state.get("eggs", 0)) + 3
	Game.emit_event("eggs_collected")
	say("Кошик яєць для дідуся! Біп!", 3.0)
	_sound("coin")
	end_job(id)


func firewood_job() -> void:
	## Три ходки від дровітні до хати — по одному поліну.
	if doing == "wood":
		return
	var id := begin_job("wood")
	_wood_day = int(Game.state["day"])
	var sp: Dictionary = main.world.spots
	say("Принесу дров для печі!", 2.5)
	for i in 3:
		await go(sp["firewood_front"])
		if id != job:
			return
		await wait(0.6)
		var lg := Util.cyl(0.06, 0.06, 0.42, Util.mat(Color(0.55, 0.38, 0.22), 0.9), Vector3.ZERO, Vector3(0, 0, 90))
		hold(lg, Vector3(0, 0.1, 0.05))
		_sound("chop")
		await go(woodpile.global_position + Vector3(0.45, 0, 0.35))
		if id != job:
			var l := drop()
			if l:
				l.queue_free()
			return
		face(woodpile.global_position)
		await wait(0.4)
		var l2 := drop()
		if l2:
			l2.queue_free()
		_add_log()
	say("Дідусю, дрова є!", 2.5)
	end_job(id)


func _add_log() -> void:
	var n := woodpile.get_child_count()
	if n >= 9:
		return
	var row := n / 3
	var col := n % 3
	var l := Util.cyl(0.06, 0.06, 0.42, Util.mat(Color(0.55, 0.38, 0.22).darkened(randf() * 0.15), 0.9),
		Vector3(0, 0.06 + row * 0.11, (col - 1) * 0.13 + (0.06 if row % 2 == 1 else 0.0)), Vector3(0, 0, 90))
	woodpile.add_child(l)


func dance() -> void:
	if anims.get("dance", "") == "":
		return
	var id := begin_job("dance")
	say("Біп-біп! Танцюю!", 2.0)
	busy = true
	play("dance")
	await wait(clampf(anim_length("dance"), 3.0, 7.0))
	busy = false
	end_job(id)


func _sound(id: String) -> void:
	var au = get_node_or_null("/root/Main/Audio")
	if au and Game.state["location"] == "yard":
		au.play_at(id, self, -10.0)
