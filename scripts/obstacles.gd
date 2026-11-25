class_name Obstacles
## Перешкоди на подвір'ї й у хаті (кола на землі), щоб персонажі не проходили крізь хату,
## криницю, стіл, дерева… Кожна перешкода: [центр (x, z), радіус, висота].

static var items: Array = []
static var outer: Array = []          # відкритий світ (для Beep, що літає всюди)
static var all: Array = []            # items + outer


static func clear() -> void:
	items.clear()
	outer.clear()
	all.clear()


static func add_outer(x: float, z: float, r: float, h := 1.0) -> void:
	outer.append([Vector2(x, z), r, h])


static func finish() -> void:
	all = items + outer


static func add(x: float, z: float, r: float, h := 1.0) -> void:
	items.append([Vector2(x, z), r, h])


static func add_line(a: Vector2, b: Vector2, r: float, h := 1.0) -> void:
	## Паркан чи довга річ — ланцюжок кіл.
	var n := maxi(1, int(ceil(a.distance_to(b) / (r * 1.2))))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		add(p.x, p.y, r, h)


static func push_out(p: Vector3, me := 0.25, min_h := 0.0, list: Array = []) -> Vector3:
	## Якщо точка всередині перешкоди — виштовхуємо назовні.
	var q := Vector2(p.x, p.z)
	var src: Array = list if not list.is_empty() else items
	for _pass in 3:                      # кілька проходів: виштовхнуло з одного кола — не лишається в сусідньому (не застрягає)
		var moved := false
		for it in src:
			if float(it[2]) < min_h:
				continue
			var c: Vector2 = it[0]
			var r: float = float(it[1]) + me
			var d := q - c
			var l := d.length()
			if l < r:
				if l < 0.0001:
					d = Vector2(0, 1)
					l = 1.0
				q = c + d / l * (r + 0.005)
				moved = true
		if not moved:
			break
	return Vector3(q.x, p.y, q.y)


static func steer(pos: Vector3, target: Vector3, me := 0.25, min_h := 0.0, list: Array = []) -> Vector3:
	## Куди йти зараз, щоб обійти перешкоди на шляху до target (проміжна точка збоку від перешкоди).
	var p := Vector2(pos.x, pos.z)
	var t := Vector2(target.x, target.z)
	for _iter in 3:
		var d := t - p
		var L := d.length()
		if L < 0.05:
			break
		var u := d / L
		var best := -1
		var best_s := INF
		var best_off := Vector2.ZERO
		var src: Array = list if not list.is_empty() else items
		for i in src.size():
			var it: Array = src[i]
			if float(it[2]) < min_h:
				continue
			var c: Vector2 = it[0]
			var r: float = float(it[1]) + me
			if p.distance_to(c) < r - 0.02:
				continue          # уже всередині (виштовхне push_out)
			var s := (c - p).dot(u)
			if s <= 0.0 or s > L + r:
				continue
			var closest := p + u * clampf(s, 0.0, L)
			var off := closest - c
			if off.length() < r and s < best_s:
				best = i
				best_s = s
				best_off = off
		if best < 0:
			break
		var it2: Array = (list if not list.is_empty() else items)[best]
		var c2: Vector2 = it2[0]
		var r2: float = float(it2[1]) + me
		if best_off.length() < 0.001:
			best_off = Vector2(-u.y, u.x)
		t = c2 + best_off.normalized() * (r2 + minf(0.3, r2 * 0.5))
	return Vector3(t.x, target.y, t.y)
