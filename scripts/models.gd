extends RefCounted
class_name Models
## Завантаження 3D-моделей з Meshy (assets/models/*.glb): підгонка розміру, постановка на землю,
## пошук анімацій. Якщо файлу ще немає — повертає null, і персонаж будує просту заміну сам.

const DIR := "res://assets/models/%s.glb"


static func exists(id: String) -> bool:
	return ResourceLoader.exists(DIR % id)


static func spawn(parent: Node3D, id: String, size: float, axis := "y") -> Node3D:
	## Додає модель у parent, масштабує так, щоб її висота (axis="y") або довжина ("z") дорівнювала size,
	## і ставить низом на y=0, по центру. Повертає вузол-обгортку (його можна повертати й рухати).
	if not exists(id):
		return null
	var holder := Node3D.new()
	holder.name = id
	parent.add_child(holder)
	var m: Node3D = load(DIR % id).instantiate()
	holder.add_child(m)
	var b := measure(m)
	var span: float = b.size.y if axis == "y" else (b.size.x if axis == "realx" else b.size.z)
	var s := size / maxf(span, 0.0001)
	m.scale = Vector3.ONE * s
	var c := b.get_center()
	m.position = -Vector3(c.x, b.position.y, c.z) * s
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.set_meta("model", m)
	return holder


static func measure(m: Node3D) -> AABB:
	## Межі моделі в її власних координатах. Для моделей зі скелетом рахуємо по кістках
	## (сітка зі скінінгом має «сирі» межі, що не збігаються з видимим тілом).
	var sks := m.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		var sk: Skeleton3D = sks[0]
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for b in sk.get_bone_count():
			var p := (_rel(sk, m) * sk.get_bone_global_pose(b)).origin
			lo = lo.min(p)
			hi = hi.max(p)
		var sz := hi - lo
		# кістки не доходять до краю тіла: голова, вуха, кінчик хвоста трохи далі
		lo -= Vector3(sz.x * 0.06, 0.0, sz.z * 0.06)
		hi += Vector3(sz.x * 0.06, sz.y * 0.08, sz.z * 0.06)
		return AABB(lo, hi - lo)
	var out := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = _rel(mi, m) * (mi as MeshInstance3D).get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out


static func _rel(n: Node3D, m: Node3D) -> Transform3D:
	## Положення n у системі m (працює й тоді, коли модель ще не в дереві сцени).
	var t := Transform3D()
	var c: Node = n
	while c != null and c != m:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func anim_player(holder: Node) -> AnimationPlayer:
	if holder == null:
		return null
	return holder.find_child("AnimationPlayer", true, false) as AnimationPlayer


static func find_anim(ap: AnimationPlayer, keys: Array) -> String:
	## Перша анімація, назва якої містить один із ключів (без урахування регістру).
	if ap == null:
		return ""
	for k in keys:
		for n in ap.get_animation_list():
			if String(k) in String(n).to_lower():
				return n
	return ""


static func set_loop(ap: AnimationPlayer, names: Array) -> void:
	for n in names:
		if n != "" and ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR


static func glow(holder: Node, energy := 0.0) -> void:
	## Легке власне світіння моделі (щоб уночі не була зовсім темна, а очі Beep сяяли).
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.get_surface_override_material_count():
			var mat := m3.get_active_material(si)
			if mat is StandardMaterial3D:
				var d: StandardMaterial3D = mat.duplicate()
				d.emission_enabled = energy > 0.0
				d.emission_texture = d.albedo_texture
				d.emission = Color(1, 1, 1)
				d.emission_energy_multiplier = energy
				m3.set_surface_override_material(si, d)


static func cut(holder: Node3D, box: AABB, max_edge := 100.0, ref: Node3D = null, cyl_r := 0.0, cyl_axis := 2, y_max := INF) -> MeshInstance3D:
	## Вирізає з моделі шматок (трикутники, центр яких у box — у просторі батька holder):
	## двері хати, хвіртку, коловорот криниці… Повертає окремий MeshInstance3D на тому ж місці.
	if holder == null:
		return null
	var mis := holder.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return null
	var mi: MeshInstance3D = mis[0]
	var parent := holder.get_parent() as Node3D
	var space: Node3D = ref if ref != null else parent
	var T := space.global_transform.affine_inverse() * mi.global_transform
	var mesh: Mesh = mi.mesh
	var keep := ArrayMesh.new()
	var part := ArrayMesh.new()
	var part_box := AABB()
	var has_box := false
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var a_idx := PackedInt32Array()
		var b_idx := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			var p0: Vector3 = T * verts[idx[t]]
			var p1: Vector3 = T * verts[idx[t + 1]]
			var p2: Vector3 = T * verts[idx[t + 2]]
			var c := (p0 + p1 + p2) / 3.0
			var e := maxf(p0.distance_to(p1), maxf(p1.distance_to(p2), p2.distance_to(p0)))
			var inside := box.has_point(c) and e < max_edge
			if inside and cyl_r > 0.0:
				# колесо: лише те, що в колі навколо осі Z через центр box (без крил-бризковиків)
				var bc := box.get_center()
				for pk in [p0, p1, p2]:
					var dd := Vector2(pk.y - bc.y, pk.z - bc.z) if cyl_axis == 0 else Vector2(pk.x - bc.x, pk.y - bc.y)
					if dd.length() > cyl_r or pk.y > y_max:
						inside = false
			if inside:
				b_idx.append(idx[t]); b_idx.append(idx[t + 1]); b_idx.append(idx[t + 2])
				for k in 3:
					var v: Vector3 = verts[idx[t + k]]
					if has_box:
						part_box = part_box.expand(v)
					else:
						part_box = AABB(v, Vector3.ZERO)
						has_box = true
			else:
				a_idx.append(idx[t]); a_idx.append(idx[t + 1]); a_idx.append(idx[t + 2])
		var mat := mi.get_active_material(s)
		for pair in [[keep, a_idx], [part, b_idx]]:
			var ix: PackedInt32Array = pair[1]
			if ix.is_empty():
				continue
			var arr2 := arr.duplicate()
			arr2[Mesh.ARRAY_INDEX] = ix
			var am: ArrayMesh = pair[0]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
			am.surface_set_material(am.get_surface_count() - 1, mat)
	if part.get_surface_count() == 0:
		return null
	mi.mesh = keep
	var pm := MeshInstance3D.new()
	pm.mesh = part
	parent.add_child(pm)
	pm.global_transform = mi.global_transform
	pm.set_meta("part_aabb", part_box)          # межі лише вирізаного шматка (у вершинах — уся модель)
	return pm


static func hinge(part: Node3D, pivot_global: Vector3) -> Node3D:
	## Вузол-петля: обертаючи його, обертаємо вирізаний шматок навколо цієї точки.
	var p := Node3D.new()
	part.get_parent().add_child(p)
	p.global_position = pivot_global
	part.reparent(p, true)
	return p


static func global_aabb(mi: MeshInstance3D) -> AABB:
	if mi.has_meta("part_aabb"):
		return mi.global_transform * (mi.get_meta("part_aabb") as AABB)
	return mi.global_transform * mi.get_aabb()


static func smooth_normals(holder: Node) -> void:
	## Згладжує освітлення моделі (прибирає «гранчастість»): нормалі усереднюються
	## для всіх вершин, що стоять в одній точці. Форма не змінюється.
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		var out := ArrayMesh.new()
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(v.size())
				for i in v.size():
					idx[i] = i
			var key := {}
			var acc: Array[Vector3] = []
			var vk := PackedInt32Array()
			vk.resize(v.size())
			for i in v.size():
				var k := Vector3i(roundi(v[i].x * 2000.0), roundi(v[i].y * 2000.0), roundi(v[i].z * 2000.0))
				if not key.has(k):
					key[k] = acc.size()
					acc.append(Vector3.ZERO)
				vk[i] = key[k]
			for t in range(0, idx.size() - 2, 3):
				var a := v[idx[t]]
				var b := v[idx[t + 1]]
				var c := v[idx[t + 2]]
				var fn := (b - a).cross(c - a)       # з вагою площі
				for j in 3:
					acc[vk[idx[t + j]]] += fn
			var nrm := PackedVector3Array()
			nrm.resize(v.size())
			var old: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			for i in v.size():
				var n := acc[vk[i]]
				if n.length_squared() < 1e-20:
					n = old[i] if i < old.size() else Vector3.UP
				# напрям — як у старої нормалі (щоб не вивернути)
				if i < old.size() and n.dot(old[i]) < 0.0:
					n = -n
				nrm[i] = n.normalized()
			arr[Mesh.ARRAY_NORMAL] = nrm
			arr[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(s, mi.get_active_material(s))
		mi.mesh = out
