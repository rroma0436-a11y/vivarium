extends Node3D
## Птахи в небі: лелеки повільно кружляють високо, зрідка змахуючи крилами, а ластівки шугають нижче.
## Зграйка тримається над тим місцем, де зараз камера, — задереш погляд у небо й побачиш їх.
## Уночі сховані (world.gd вимикає visible).

var _birds: Array = []          # [вузол, ліве крило, праве крило, дані]
var _center := Vector3.INF
var _t := 0.0


func _ready() -> void:
	var white := _mat(Color(0.95, 0.95, 0.93))
	var black := _mat(Color(0.08, 0.08, 0.09))
	var red := _mat(Color(0.85, 0.25, 0.15))
	var dark := _mat(Color(0.1, 0.12, 0.22))
	var belly := _mat(Color(0.92, 0.86, 0.8))
	for i in 4:
		_add(_stork(white, black, red), {"kind": "stork", "r": 20.0 + i * 5.0, "h": 28.0 + i * 3.5, "s": 6.0 + i * 0.6,
			"a": i * 1.7, "ph": i * 2.3, "dir": 1.0})
	for i in 7:
		_add(_swallow(dark, belly), {"kind": "swallow", "r": 8.0 + i * 2.2, "h": 12.0 + (i % 3) * 2.5, "s": 9.0 + i * 0.7,
			"a": i * 0.9, "ph": i * 1.3, "dir": -1.0 if i % 2 == 1 else 1.0})


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _part(parent: Node3D, mesh: Mesh, m: Material, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c


func _stork(white: Material, black: Material, red: Material) -> Array:
	## Лелека: біле тіло, крила білі з чорними кінцями, червоний дзьоб і ноги позаду.
	var b := Node3D.new()
	_part(b, _capsule(0.12, 0.75), white, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	_part(b, _capsule(0.05, 0.4), white, Vector3(0, 0.02, 0.45), Vector3(PI / 2.0, 0, 0))
	var head := SphereMesh.new()
	head.radius = 0.07
	head.height = 0.14
	head.radial_segments = 8
	head.rings = 4
	_part(b, head, white, Vector3(0, 0.03, 0.66))
	_part(b, _box(0.03, 0.03, 0.3), red, Vector3(0, 0.02, 0.85))
	_part(b, _box(0.025, 0.025, 0.45), red, Vector3(0.05, -0.03, -0.55))
	_part(b, _box(0.025, 0.025, 0.45), red, Vector3(-0.05, -0.03, -0.55))
	_part(b, _box(0.22, 0.02, 0.16), black, Vector3(0, 0, -0.38))
	var wl := Node3D.new()
	wl.position = Vector3(0.09, 0.04, 0.02)
	b.add_child(wl)
	_part(wl, _box(0.6, 0.025, 0.34), white, Vector3(0.3, 0, 0))
	_part(wl, _box(0.5, 0.02, 0.28), black, Vector3(0.84, 0, -0.03))
	var wr := Node3D.new()
	wr.position = Vector3(-0.09, 0.04, 0.02)
	b.add_child(wr)
	_part(wr, _box(0.6, 0.025, 0.34), white, Vector3(-0.3, 0, 0))
	_part(wr, _box(0.5, 0.02, 0.28), black, Vector3(-0.84, 0, -0.03))
	b.scale = Vector3.ONE * 1.3
	return [b, wl, wr]


func _swallow(dark: Material, belly: Material) -> Array:
	## Ластівка: темна спинка, світле черевце, гострі крила назад і хвіст-вилочка.
	var b := Node3D.new()
	_part(b, _capsule(0.05, 0.24), dark, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	_part(b, _capsule(0.035, 0.16), belly, Vector3(0, -0.02, 0.02), Vector3(PI / 2.0, 0, 0))
	_part(b, _box(0.015, 0.01, 0.16), dark, Vector3(0.03, 0, -0.18), Vector3(0, -0.25, 0))
	_part(b, _box(0.015, 0.01, 0.16), dark, Vector3(-0.03, 0, -0.18), Vector3(0, 0.25, 0))
	var wl := Node3D.new()
	wl.position = Vector3(0.04, 0.01, 0.02)
	b.add_child(wl)
	_part(wl, _box(0.24, 0.01, 0.07), dark, Vector3(0.12, 0, -0.04), Vector3(0, 0.35, 0))
	var wr := Node3D.new()
	wr.position = Vector3(-0.04, 0.01, 0.02)
	b.add_child(wr)
	_part(wr, _box(0.24, 0.01, 0.07), dark, Vector3(-0.12, 0, -0.04), Vector3(0, -0.35, 0))
	b.scale = Vector3.ONE * 1.6
	return [b, wl, wr]


func _add(parts: Array, data: Dictionary) -> void:
	add_child(parts[0])
	_birds.append([parts[0], parts[1], parts[2], data])


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	c.y = 0.0
	if _center == Vector3.INF or _center.distance_to(c) > 90.0:
		_center = c
	else:
		_center = _center.lerp(c, 1.0 - exp(-delta * 0.25))
	for it in _birds:
		var b: Node3D = it[0]
		var wl: Node3D = it[1]
		var wr: Node3D = it[2]
		var d: Dictionary = it[3]
		var stork: bool = d["kind"] == "stork"
		var ph: float = d["ph"]
		var dir: float = d["dir"]
		var r: float = float(d["r"]) + sin(_t * (0.13 if stork else 0.5) + ph) * (4.0 if stork else 3.0)
		d["a"] = float(d["a"]) + dir * float(d["s"]) / maxf(r, 1.0) * delta
		var a: float = d["a"]
		var h: float = float(d["h"]) + sin(_t * (0.2 if stork else 0.9) + ph) * (2.0 if stork else 3.0)
		var p := _center + Vector3(cos(a) * r, h, sin(a) * r)
		var tang := Vector3(-sin(a), 0, cos(a)) * dir
		b.global_position = p
		b.look_at(p - tang, Vector3.UP)
		b.rotate_object_local(Vector3(0, 0, 1), dir * (0.3 if stork else 0.5))
		# крила: лелека здебільшого ширяє й зрідка змахує, ластівка махає часто з короткими ковзаннями
		var w := 0.06
		if stork:
			if fmod(_t + ph * 3.0, 9.0) < 2.2:
				w = sin(_t * 2.6 + ph) * 0.45
		else:
			if fmod(_t + ph, 2.5) < 1.8:
				w = sin(_t * 13.0 + ph) * 0.6
		wl.rotation.z = w
		wr.rotation.z = -w
