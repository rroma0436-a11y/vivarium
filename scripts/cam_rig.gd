extends Node3D
## Камера, що літає за Beep: тягни пальцем — обертай навколо, щипок двома пальцями — наближай.
## Коротке торкання без руху — це «тап» (сигнал tapped).

signal tapped(screen_pos: Vector2)

var cam: Camera3D
var target := Vector3.ZERO          # куди дивимось (плавно доганяє focus)
var focus := Vector3.ZERO           # куди хочемо дивитись
var yaw := 0.0
var pitch := -22.0
var dist := 7.0
var dist_min := 3.0
var dist_max := 12.0
var yaw_limit := 400.0              # у кімнаті обмежуємо поворот
var yaw_center := 0.0
var blockers: Array = []          # AABB, крізь які камера не пролітає (хата)
var pitch_min := -60.0
var pitch_max := -8.0
var _touches := {}
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _moved := 0.0
var _pinch0 := 0.0
var _dist0 := 0.0
var _want_dist := -1.0              # куди плавно наближаємо/віддаляємо камеру (-1 — не треба)
var _want_pitch := 999.0
var last_drag := -100.0             # коли гравець востаннє крутив камеру пальцем (с) — тоді камера не повертається сама


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)


func setup(pos: Vector3, y: float, p: float, d: float, dmin: float, dmax: float, ylimit := 400.0, pmin := -60.0, pmax := -8.0) -> void:
	pitch_min = pmin
	pitch_max = pmax
	focus = pos
	target = pos
	yaw = y
	yaw_center = y
	pitch = p
	dist = d
	dist_min = dmin
	dist_max = dmax
	yaw_limit = ylimit
	_apply()


var collide_mask := 0               # шари стін, крізь які камера не пролітає (Ніка біля хат)
var inside_box := AABB()           # якщо задано — камера завжди всередині (кімната)


func glide_to(d: float, p := 999.0) -> void:
	## Плавно наблизити/віддалити камеру (і нахилити), як у кіно.
	_want_dist = clampf(d, dist_min, dist_max)
	_want_pitch = p


func _process(delta: float) -> void:
	target = target.lerp(focus, 1.0 - exp(-delta * 3.0))
	if _want_dist > 0.0:
		dist = lerpf(dist, _want_dist, 1.0 - exp(-delta * 2.5))
		if absf(dist - _want_dist) < 0.05:
			_want_dist = -1.0
	if _want_pitch < 900.0:
		pitch = lerpf(pitch, _want_pitch, 1.0 - exp(-delta * 2.5))
		if absf(pitch - _want_pitch) < 0.2:
			_want_pitch = 999.0
	_apply()
	_cut_step(delta)


# ------------------------------------------------------------------ речі між камерою й Нікою ховаються (не закривають екран)
var keep_root: Node3D = null          # Ніка — її ніколи не ховаємо
var _all_meshes: Array = []
var _near_meshes: Array = []
var _hidden := {}                     # MeshInstance3D -> скільки ще лишатися схованим (с)
var _scan_t := 99.0
var _near_t := 99.0
var _cut_t := 0.0
var _node_count := -1


func _cut_step(delta: float) -> void:
	for mi in _hidden.keys():
		_hidden[mi] = float(_hidden[mi]) - delta
	var on := collide_mask != 0 and is_inside_tree()
	if not on:
		if not _hidden.is_empty():
			_unhide_all()
		return
	_scan_t += delta
	_near_t += delta
	_cut_t += delta
	if _scan_t > 4.0 and get_tree().get_node_count() != _node_count:
		_scan_t = 0.0
		_node_count = get_tree().get_node_count()
		_all_meshes.clear()
		for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			if keep_root != null and is_instance_valid(keep_root) and keep_root.is_ancestor_of(mi):
				continue
			var ab := Models.global_aabb(mi)
			if ab.size.x > 12.0 or ab.size.z > 12.0 or ab.size.y > 12.0:
				continue
			_all_meshes.append([mi, ab.get_center()])
		_near_t = 99.0
	if _near_t > 0.6:
		_near_t = 0.0
		_near_meshes.clear()
		for it in _all_meshes:
			var mi = it[0]
			if not is_instance_valid(mi):
				continue
			var c: Vector3 = it[1]
			if c.distance_to(target) < 22.0 or (mi as Node3D).global_position.distance_to(target) < 22.0:
				_near_meshes.append(mi)
	if _cut_t > 0.1:
		_cut_t = 0.0
		var cp := cam.global_position
		var to := target - cp
		var L := to.length()
		if L > 0.4:
			var end := cp + to * ((L - 0.45) / L)
			for mi in _near_meshes:
				if not is_instance_valid(mi) or not mi.is_inside_tree():
					continue
				var m := mi as MeshInstance3D
				if not m.visible and not _hidden.has(m):
					continue
				var ab := Models.global_aabb(m)
				if ab.size.x > 12.0 or ab.size.z > 12.0 or ab.size.y > 12.0:
					continue
				if ab.grow(0.6).has_point(target):
					continue
				if ab.grow(0.05).intersects_segment(cp, end) or ab.has_point(cp):
					if not _hidden.has(m):
						m.visible = false
					_hidden[m] = 0.35
	for mi in _hidden.keys():
		if float(_hidden[mi]) <= 0.0:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = true
			_hidden.erase(mi)


func _unhide_all() -> void:
	for mi in _hidden.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = true
	_hidden.clear()


func _apply() -> void:
	yaw = clampf(yaw, yaw_center - yaw_limit, yaw_center + yaw_limit)
	pitch = clampf(pitch, pitch_min, pitch_max)
	dist = clampf(dist, dist_min, dist_max)
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	var dir := b * Vector3(0, 0, 1)
	var d := dist
	for box in blockers:
		var hit = (box as AABB).intersects_ray(target, dir)
		if hit != null and not (box as AABB).has_point(target):
			d = minf(d, maxf(target.distance_to(hit) - 0.4, 1.2))
	if collide_mask != 0 and is_inside_tree():
		# стіни, піч, перегородки між камерою й Нікою — камера стає перед ними (і в хаті теж),
		# щоб екран не закривала стіна впритул
		var inside := inside_box.size != Vector3.ZERO
		var rq := PhysicsRayQueryParameters3D.create(target, target + dir * (d + 0.3), collide_mask)
		var rh := get_world_3d().direct_space_state.intersect_ray(rq)
		if not rh.is_empty():
			d = minf(d, maxf(target.distance_to(rh["position"]) - (0.32 if inside else 0.25), 0.3 if inside else 0.5))
	if inside_box.size == Vector3.ZERO and dist_max < 60.0:
		# хати, сараї, дерева подвір'я (перешкоди-кола) — камера не залітає в стіну, а стає перед нею
		var s := 0.6
		while s < d:
			var q := target + dir * s
			var hit_o := false
			for it in Obstacles.all:
				if float(it[2]) > 1.8 and q.y < float(it[2]) and Vector2(q.x, q.z).distance_to(it[0]) < float(it[1]) + 0.15 \
						and Vector2(target.x, target.z).distance_to(it[0]) > float(it[1]) + 0.3:
					hit_o = true
					break
			if hit_o:
				d = maxf(s - 0.25, 0.6)
				break
			s += 0.3
		# і не опускається в траву
		var cy := target.y + dir.y * d
		if cy < 0.45 and dir.y < -0.01:
			d = minf(d, maxf((target.y - 0.45) / -dir.y, 0.6))
	if inside_box.size != Vector3.ZERO:
		# у кімнаті камера не виходить за стіни: наближаємо, поки не опиниться всередині
		d = _fit_in_box(dir, d)
		# тісно (стіна за спиною) — замість лізти впритул до голови камера дивиться більше згори
		var pe := pitch
		while d < 1.7 and pe > -72.0:
			pe -= 8.0
			var dir2 := Basis.from_euler(Vector3(deg_to_rad(pe), deg_to_rad(yaw), 0)) * Vector3(0, 0, 1)
			var d2 := _fit_in_box(dir2, dist)
			if collide_mask != 0 and is_inside_tree():
				var rq2 := PhysicsRayQueryParameters3D.create(target, target + dir2 * (d2 + 0.3), collide_mask)
				var rh2 := get_world_3d().direct_space_state.intersect_ray(rq2)
				if not rh2.is_empty():
					d2 = minf(d2, maxf(target.distance_to(rh2["position"]) - 0.32, 0.3))
			if d2 > d + 0.05:
				d = d2
				dir = dir2
	cam.global_position = target + dir * d
	cam.look_at(target, Vector3.UP)


func _fit_in_box(dir: Vector3, d: float) -> float:
	## Найбільша відстань від Ніки вздовж dir, на якій камера ще всередині кімнати (не над дахом).
	if not inside_box.has_point(target):
		var guard := 0
		while d > 0.35 and not inside_box.has_point(target + dir * d) and guard < 200:
			d -= 0.08
			guard += 1
		return d
	var t := d
	for i in 3:
		if absf(dir[i]) > 0.0001:
			var lim: float = inside_box.end[i] if dir[i] > 0.0 else inside_box.position[i]
			t = minf(t, (lim - target[i]) / dir[i] - 0.1)
	return clampf(t, 0.35, d)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_press_pos = e.position
				_press_time = Time.get_ticks_msec() / 1000.0
				_moved = 0.0
			elif _touches.size() == 2:
				var v: Array = _touches.values()
				_pinch0 = (v[0] as Vector2).distance_to(v[1])
				_dist0 = dist
				_moved = 999.0
		else:
			_touches.erase(e.index)
			if _touches.is_empty() and _moved < 14.0 and Time.get_ticks_msec() / 1000.0 - _press_time < 0.45:
				tapped.emit(e.position)
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_moved += e.relative.length()
			if _moved >= 14.0:
				_want_pitch = 999.0
				last_drag = Time.get_ticks_msec() / 1000.0
				yaw -= e.relative.x * 0.25
				pitch -= e.relative.y * 0.18
		elif _touches.size() == 2 and _pinch0 > 0.0:
			var v: Array = _touches.values()
			var d := (v[0] as Vector2).distance_to(v[1])
			_want_dist = -1.0
			dist = _dist0 * _pinch0 / maxf(d, 1.0)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_want_dist = -1.0
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist *= 0.9
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist *= 1.1



func looking() -> bool:
	## Гравець щойно оглядався (крутив камеру) — не перебиваємо.
	return Time.get_ticks_msec() / 1000.0 - last_drag < 4.0
