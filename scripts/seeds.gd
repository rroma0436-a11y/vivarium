extends Node3D
## Золоті насінинки в небі над округою. Їх можна зібрати лише на літаку:
## пролетіти крізь насінинку. Зібрані зберігаються в Game.state["seeds"].

signal collected(left: int)

const SPOTS := [
	Vector3(-4, 14, -4),        # над подвір'ям
	Vector3(0, 24, 80),         # над церквою
	Vector3(0, 9, 102),         # над містком через річку
	Vector3(-56, 8, 18),        # над ставком
	Vector3(48, 10, 29),        # над пшеничним полем
	Vector3(-70, 20, -40),      # біля вітряка
	Vector3(95, 20, -20),       # над лісом на сході
	Vector3(-60, 18, 150),      # над лісом за річкою
	Vector3(-40, 34, -2),       # високо над аеродромом
	Vector3(20, 16, -110),      # за подвір'ям, над гаєм
]
const RADIUS := 4.2

var nodes: Array = []
var _t := 0.0
var dragon: Node3D


func build() -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.82, 0.25)
	gold.metallic = 0.6
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.15)
	gold.emission_energy_multiplier = 1.6
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.45, 0.3, 0.1)
	stripe.emission_enabled = true
	stripe.emission = Color(0.6, 0.4, 0.1)
	stripe.emission_energy_multiplier = 0.6
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_color = Color(1.0, 0.8, 0.3, 0.35)
	halo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.albedo_texture = _glow_tex()
	var got: Array = Game.state.get("seeds", [])
	for i in SPOTS.size():
		var n := Node3D.new()
		n.position = SPOTS[i]
		add_child(n)
		var body := Node3D.new()
		body.scale = Vector3(1.6, 1.6, 1.6)
		n.add_child(body)
		# насінинка соняшника: сплюснута крапля з темними смужками
		body.add_child(Util.sphere(0.35, gold, Vector3.ZERO, Vector3(0.7, 1.15, 0.35)))
		body.add_child(Util.sphere(0.36, stripe, Vector3(0.12, 0, 0), Vector3(0.06, 1.05, 0.36)))
		body.add_child(Util.sphere(0.36, stripe, Vector3(-0.12, 0, 0), Vector3(0.06, 1.05, 0.36)))
		var h := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 3.2)
		h.mesh = q
		h.material_override = halo
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(h)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.35)
		l.light_energy = 1.2
		l.omni_range = 5.0
		n.add_child(l)
		n.visible = not (i in got or float(i) in got)
		nodes.append(n)


func _glow_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func left() -> int:
	var c := 0
	for n in nodes:
		if n.visible:
			c += 1
	return c


func _process(delta: float) -> void:
	_t += delta
	for i in nodes.size():
		var n: Node3D = nodes[i]
		if not n.visible:
			continue
		n.get_child(0).rotation.y = _t * 1.6 + i
		n.position.y = SPOTS[i].y + sin(_t * 1.3 + i) * 0.4
		if dragon and dragon.rider and dragon.state != "rest":
			if n.global_position.distance_to(dragon.global_position + Vector3(0, 1.2, 0)) < RADIUS:
				_collect(i)


func _collect(i: int) -> void:
	var n: Node3D = nodes[i]
	n.visible = false
	var got: Array = Game.state.get("seeds", [])
	if not (i in got or float(i) in got):
		got.append(i)
	Game.state["seeds"] = got
	# іскорки на місці насінинки
	var p := CPUParticles3D.new()
	p.amount = 40
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.2
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -2, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.3
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	p.mesh = m
	p.material_override = Util.mat(Color(1, 0.85, 0.3), 0.3, 0.0, Color(1, 0.75, 0.2), 2.0)
	add_child(p)
	p.global_position = n.global_position
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	Game.emit_event("seed")
	collected.emit(left())
