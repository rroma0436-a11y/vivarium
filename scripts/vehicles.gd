extends RefCounted
class_name Vehicles
## Спільне для трактора й воза: куди можна їхати (не в річку, не на пагорб вітряка,
## не крізь хати й тин подвір'я) і як дістатися назад (через місток, якщо треба).

const LIMIT := 200.0
const YARD := Rect2(-21.5, -15.5, 31.0, 21.0)       # подвір'я з тином (туди транспорт не заїжджає)
const RIVER_Z := 102.0
const RIVER_HALF := 4.0 + 0.6                         # пів ширини річки з берегами
const BRIDGE_HALF := 1.45                              # пів ширини містка (x від −1.45 до 1.45)
const MILL := Vector3(-82, 0, -50)
const MILL_R := 25.0
const POND := Vector3(-70, 0, 31)                     # ставок — прямокутник із заокругленими кутами (як у world_outer.gd)
const POND_HALF := Vector2(21.5, 14.5)
const POND_CORNER := 6.0


static func keep_out(p: Vector3, r: float, from := Vector3.INF) -> Vector3:
	## Виштовхує точку p (центр транспорту радіусом r) з місць, куди їхати не можна.
	p = Obstacles.push_out(p, r, 0.4, Obstacles.all)
	# ставок — прямокутник із заокругленими кутами (на пагорб з млином заїжджати можна)
	var ix := POND_HALF.x - POND_CORNER
	var iz := POND_HALF.y - POND_CORNER
	var cq := Vector2(clampf(p.x, POND.x - ix, POND.x + ix), clampf(p.z, POND.z - iz, POND.z + iz))
	var dq := Vector2(p.x, p.z) - cq
	var rr := POND_CORNER + r
	if dq.length() < rr:
		if dq.length() < 0.001:
			# усередині серцевини — до ближчого берега
			var ex := ix - absf(p.x - POND.x)
			var ez := iz - absf(p.z - POND.z)
			var sx := 1.0 if p.x >= POND.x else -1.0
			var sz := 1.0 if p.z >= POND.z else -1.0
			dq = Vector2(sx, 0) if ex < ez else Vector2(0, sz)
			cq = Vector2(p.x, p.z) + dq * minf(ex, ez)
		dq = dq.normalized() * rr
		p.x = cq.x + dq.x
		p.z = cq.y + dq.y
	# подвір'я з тином
	var y := YARD.grow(r)
	if y.has_point(Vector2(p.x, p.z)):
		var dl := p.x - y.position.x
		var dr := y.end.x - p.x
		var dt := p.z - y.position.y
		var db := y.end.y - p.z
		var m := minf(minf(dl, dr), minf(dt, db))
		if m == dl:
			p.x = y.position.x
		elif m == dr:
			p.x = y.end.x
		elif m == dt:
			p.z = y.position.y
		else:
			p.z = y.end.y
	# річка: тільки містком
	if absf(p.z - RIVER_Z) < RIVER_HALF + r * 0.5 and absf(p.x) > BRIDGE_HALF:
		var side := signf(p.z - RIVER_Z) if from == Vector3.INF else signf(from.z - RIVER_Z)
		if side == 0.0:
			side = -1.0
		p.z = RIVER_Z + side * (RIVER_HALF + r * 0.5)
	p.x = clampf(p.x, -LIMIT, LIMIT)
	p.z = clampf(p.z, -LIMIT, LIMIT)
	p.y = Util.hill_y(p)
	return p


static func route(from: Vector3, to: Vector3) -> Array:
	## Точки дороги від from до to: якщо треба через річку — спершу до містка й по ньому.
	var pts: Array = []
	var a := signf(from.z - RIVER_Z)
	var b := signf(to.z - RIVER_Z)
	if a != b and a != 0.0 and b != 0.0:
		pts.append(Vector3(0, 0, RIVER_Z + a * 9.0))
		pts.append(Vector3(0, 0, RIVER_Z - a * 9.0))
	# з далекого півдня (за селом) — дорогою через село
	if from.z > 40.0 and to.z < 20.0:
		pts.append(Vector3(0.6, 0, 30.0))
		pts.append(Vector3(0.6, 0, 18.0))
	# ставок посередині дороги (до ферми за ставком і назад) — об'їжджаємо з півночі чи з півдня
	var a2 := Vector2(from.x, from.z) if pts.is_empty() else Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)
	var b2 := Vector2(to.x, to.z)
	var box := Rect2(POND.x - POND_HALF.x - 4.0, POND.z - POND_HALF.y - 4.0, POND_HALF.x * 2.0 + 8.0, POND_HALF.y * 2.0 + 8.0)
	var hit := false
	for k in 21:
		if box.has_point(a2.lerp(b2, k / 20.0)):
			hit = true
	if hit and not box.has_point(a2) and not box.has_point(b2):
		var e1 := box.end.x + 2.0 if a2.x > b2.x else box.position.x - 2.0
		var e2 := box.position.x - 2.0 if a2.x > b2.x else box.end.x + 2.0
		var zn := box.position.y - 2.0
		var zs := box.end.y + 2.0
		var ln := a2.distance_to(Vector2(e1, zn)) + b2.distance_to(Vector2(e2, zn))
		var ls := a2.distance_to(Vector2(e1, zs)) + b2.distance_to(Vector2(e2, zs))
		var zz := zn if ln <= ls else zs
		pts.append(Vector3(e1, 0, zz))
		pts.append(Vector3(e2, 0, zz))
	pts.append(to)
	return pts


static func steer_target(pos: Vector3, target: Vector3, r: float) -> Vector3:
	## Проміжна точка в обхід хат, дерев і подвір'я.
	var t := Obstacles.steer(pos, target, r, 0.4, Obstacles.all)
	# подвір'я — обходимо кутом
	var y := YARD.grow(r + 1.5)
	var mid := (pos + t) * 0.5
	if y.has_point(Vector2(mid.x, mid.z)) and not y.has_point(Vector2(pos.x, pos.z)):
		var corners: Array = [Vector2(y.position.x, y.position.y), Vector2(y.end.x, y.position.y), Vector2(y.position.x, y.end.y), Vector2(y.end.x, y.end.y)]
		var best: Vector2 = corners[0]
		var bs := INF
		for c in corners:
			var s: float = c.distance_to(Vector2(pos.x, pos.z)) + c.distance_to(Vector2(target.x, target.z))
			if s < bs:
				bs = s
				best = c
		t = Vector3(best.x, 0, best.y)
	return t
