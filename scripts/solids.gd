class_name Solids
## Тверді будівлі й дерева для Beep, коли він літає: кожна нерухома річ, вища за ~2.4 м
## (хати, особняк, ринок, ангар, церква, дерева на подвір'ї…), отримує опуклу оболонку
## у фізичному світі. Beep перевіряє рух кулькою (cast_motion) і не пролітає крізь дахи й стіни.
## Рухомі речі (трактор, тварини, двері, лопаті вітряка) сюди не потрапляють.

const LAYER := 1 << 19                 # окремий шар — дотики (Area3D) і решта фізики його не бачать
const MIN_TOP := 2.4                   # нижчі речі (соняшники, паркани, копиці) Beep перелітає
const MAX_SPAN := 50.0                 # далекі гори й земля — не перешкоди

static var body: StaticBody3D
static var count := 0


static func build(root: Node3D, skip: Array = []) -> void:
	## Збирає оболонки для всього, що вже стоїть у світі під root.
	if body != null and is_instance_valid(body):
		body.queue_free()
	body = StaticBody3D.new()
	body.name = "Solids"
	body.collision_layer = LAYER
	body.collision_mask = 0
	root.add_child(body)
	body.global_transform = Transform3D.IDENTITY
	count = 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible or mi.has_meta("part_aabb") or mi.skin != null:
			continue
		if not _static_branch(mi, root, skip):
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if ab.end.y < MIN_TOP or ab.size.x > MAX_SPAN or ab.size.z > MAX_SPAN or ab.size.y > 40.0:
			continue
		var faces := mi.mesh.get_faces()
		if faces.size() < 12:
			continue
		var pts: PackedVector3Array = mi.global_transform * faces
		var sh := ConvexPolygonShape3D.new()
		sh.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = sh
		body.add_child(cs)
		count += 1


static func _static_branch(n: Node, root: Node, skip: Array) -> bool:
	## Чи вся гілка від root до n — нерухома декорація (без власних скриптів персонажів).
	var p := n
	while p != null and p != root:
		if skip.has(p):
			return false
		var sc = p.get_script()
		if sc != null:
			var path: String = (sc as Script).resource_path.get_file()
			if path != "world.gd" and path != "world_outer.gd":
				return false
		p = p.get_parent()
	return p == root


static func _params(r: float, at: Vector3) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = LAYER
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return q


static func ready(w: World3D) -> bool:
	return body != null and is_instance_valid(body) and count > 0 and w != null


static func inside(w: World3D, at: Vector3, r: float) -> bool:
	if not ready(w):
		return false
	return not w.direct_space_state.intersect_shape(_params(r, at), 1).is_empty()


static func _normal(space: PhysicsDirectSpaceState3D, at: Vector3, r: float) -> Vector3:
	## Нормаль стіни, якої торкається кулька в точці at (від стіни до кульки); ZERO — не торкається.
	var info := space.get_rest_info(_params(r, at))
	if info.is_empty():
		return Vector3.ZERO
	var nrm: Vector3 = info["normal"]
	var away: Vector3 = at - info["point"]
	if away.length_squared() > 1e-8:
		if nrm.dot(away) < 0.0:
			nrm = -nrm
		if nrm.length_squared() < 0.5:
			nrm = away.normalized()
	return nrm.normalized()


static func move(w: World3D, at: Vector3, motion: Vector3, r: float, slide := true) -> Vector3:
	## Куди насправді можна зрушити кульку радіуса r з точки at: до перешкоди, а далі — ковзає
	## вздовж стіни чи даху. Повертає зсув (може бути коротшим за motion або іншого напряму).
	## Увага: cast_motion не бачить стіну, якої кулька вже торкається, — тому дотик перевіряємо окремо.
	if not ready(w) or motion.length_squared() < 1e-10:
		return motion
	var space := w.direct_space_state
	var done := Vector3.ZERO
	var left := motion
	for _i in 4:
		if left.length_squared() < 1e-10:
			break
		var start := at + done
		var n0 := _normal(space, start, r)
		if n0 != Vector3.ZERO:
			var dn := left.dot(n0)
			if dn < 0.0:
				if not slide:
					return done
				left -= n0 * dn                  # уздовж стіни
				done += n0 * 0.003               # і трішки від неї
				continue
		var q := _params(r, start)
		q.motion = left
		var res := space.cast_motion(q)
		if res.is_empty():
			return done + left
		var safe: float = res[0]
		if safe >= 1.0:
			return done + left
		var n1 := _normal(space, start + left * clampf(float(res[1]), 0.0, 1.0), r)
		done += left * safe
		if not slide or n1 == Vector3.ZERO:
			return done
		left = left * (1.0 - safe)
		left -= n1 * minf(0.0, left.dot(n1))
		done += n1 * 0.003
	return done
