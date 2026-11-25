extends Node3D
## Заєць живе в грибному лісі: принюхується, лежить, стрибає між кущами,
## а коли хтось підходить близько чи торкнешся його — тікає галопом.

const SIZE := 0.45
const FLEE_DIST := 4.0

var center := Vector3.ZERO
var radius := 9.0
var model: Node3D
var ap: AnimationPlayer
var area: Area3D
var anims := {}
var target := Vector3.ZERO
var moving := false
var fleeing := false
var _wait := 2.0
var _cur := ""
var who: Node3D = null            # за ким стежимо (гравець / дідусь)


func setup(c: Vector3, r: float) -> void:
	center = c
	radius = r
	model = Models.spawn(self, "hare", SIZE)
	if model == null:
		return
	ap = Models.anim_player(model)
	anims = {
		"idle": Models.find_anim(ap, ["idlealertbreathe", "rabbit_idle"]),
		"sniff": Models.find_anim(ap, ["sniffle"]),
		"look": Models.find_anim(ap, ["lookaround"]),
		"lie": Models.find_anim(ap, ["lie"]),
		"hop": Models.find_anim(ap, ["1hop"]),
		"walk": Models.find_anim(ap, ["rabbit_walk"]),
		"run": Models.find_anim(ap, ["gallop"]),
	}
	Models.set_loop(ap, [anims["idle"], anims["sniff"], anims["look"], anims["lie"], anims["hop"], anims["walk"], anims["run"]])
	if ap:
		ap.playback_default_blend_time = 0.2
	area = Util.pick_area("hare", Vector3(0.7, 0.6, 0.9), Vector3(0, 0.3, 0))
	add_child(area)
	position = c + Vector3(randf_range(-radius, radius) * 0.5, 0, randf_range(-radius, radius) * 0.5)
	_play("sniff")


func _play(k: String, sp := 1.0) -> void:
	if ap == null:
		return
	var n: String = anims.get(k, "")
	if n == "" or not ap.has_animation(n):
		return
	if _cur == k and ap.is_playing():
		ap.speed_scale = sp
		return
	_cur = k
	ap.play(n, 0.2)
	ap.speed_scale = sp


func poke() -> void:
	## Торкнулися — тікає.
	_flee_from(get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else position + Vector3(0, 0, 3))


func _flee_from(p: Vector3) -> void:
	var away := global_position - p
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var t := global_position + away * randf_range(6.0, 9.0)
	var off := Vector2(t.x - center.x, t.z - center.z)
	if off.length() > radius:
		off = off.normalized() * radius * 0.9
		t = Vector3(center.x + off.x, 0, center.z + off.y)
	target = t
	moving = true
	fleeing = true


func _process(delta: float) -> void:
	if model == null:
		return
	# хто поруч?
	if who and is_instance_valid(who) and not fleeing:
		var d: Vector3 = who.global_position - global_position
		d.y = 0.0
		if d.length() < FLEE_DIST:
			_flee_from(who.global_position)
	if moving:
		var to := target - position
		to.y = 0.0
		var d := to.length()
		var sp := 4.2 if fleeing else 0.9
		if d < 0.2:
			moving = false
			fleeing = false
			_wait = randf_range(2.0, 5.0)
			_play("look")
			return
		var hd := atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, hd, 1.0 - exp(-delta * 8.0))
		position += Vector3(sin(rotation.y), 0, cos(rotation.y)) * minf(sp * delta, d)
		_play("run" if fleeing else "hop", 1.0)
		return
	_wait -= delta
	if _wait > 0.0:
		return
	var r := randf()
	if r < 0.4:
		_play("sniff")
		_wait = randf_range(3.0, 6.0)
	elif r < 0.55:
		_play("lie")
		_wait = randf_range(5.0, 9.0)
	elif r < 0.7:
		_play("idle")
		_wait = randf_range(2.0, 4.0)
	else:
		var a := randf() * TAU
		var rr := sqrt(randf()) * radius
		target = center + Vector3(cos(a) * rr, 0, sin(a) * rr)
		moving = true
