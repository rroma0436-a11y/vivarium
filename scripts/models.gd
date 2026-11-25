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



const NIKA_SHARE := {"walk": "walking", "run": "running", "talk": "talk_with_left", "pick": "female_bend_over_pick_up",
	"crouch_pick": "crouch_pick", "tree_pick": "stand_pick_fruit", "pocket": "put_in_pocket", "drink": "stand_and_drink",
	"stand": "sit_to_stand", "sit_down": "stand_to_sit", "sleep": "toss_and_turn", "open_door": "open_door"}


static func give_nika_anims(ap: AnimationPlayer, anims = null) -> void:
	## Рухи Ніки (крім її власних) — персонажу, у якого їх немає. anims: роль → назва (якщо є).
	if ap == null:
		return
	var need := {}
	for role in NIKA_SHARE:
		var own := find_anim(ap, [NIKA_SHARE[role]])
		if anims != null and own != "" and String(anims.get(role, "")) == "":
			anims[role] = own
		if own == "":
			need[role] = NIKA_SHARE[role]
	var got := share_anims(ap, "girl", need)
	if anims == null:
		return
	for role in got:
		var r: String = role if String(anims.get(role, "")) == "" else role + "2"
		anims[r] = got[role]


static func _bkey(n: String) -> String:
	var k := n.to_lower()
	if ":" in k:
		k = k.get_slice(":", k.get_slice_count(":") - 1)
	if k.begins_with("mixamorig"):
		k = k.substr(9)
	return k.lstrip("_")


static func _hips(sk: Skeleton3D) -> int:
	for i in sk.get_bone_count():
		if _bkey(sk.get_bone_name(i)) == "hips":
			return i
	return -1


static func _xf_to(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != top:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _grest(sk: Skeleton3D, b: int) -> Transform3D:
	var xf := sk.get_bone_rest(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		xf = sk.get_bone_rest(p) * xf
		p = sk.get_bone_parent(p)
	return xf


static var _src := {}
static var _done := {}


static func share_anims(ap: AnimationPlayer, from_id: String, map: Dictionary) -> Dictionary:
	## Анімації іншої моделі-людини → у ap під назвою "nika_…" (перенос через позу спокою). map: роль → ключ назви.
	var out := {}
	if ap == null or map.is_empty() or not exists(from_id) or not ap.has_animation_library(""):
		return out
	var root := ap.get_node_or_null(ap.root_node)
	if root == null:
		return out
	var sks := root.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return out
	var sk: Skeleton3D = sks[0]
	if not _src.has(from_id):
		_src[from_id] = load(DIR % from_id).instantiate()
	var src: Node = _src[from_id]
	var sap := anim_player(src)
	var ssks := src.find_children("*", "Skeleton3D", true, false)
	if sap == null or ssks.is_empty():
		return out
	var ssk: Skeleton3D = ssks[0]
	var tk := _xf_to(sk, root)
	var skx := _xf_to(ssk, src)
	var by_key := {}
	for i in sk.get_bone_count():
		by_key[_bkey(sk.get_bone_name(i))] = i
	var hb := _hips(sk)
	var shb := _hips(ssk)
	var k := 1.0
	if hb >= 0 and shb >= 0:
		var hs := (skx * _grest(ssk, shb)).origin.y
		if absf(hs) > 1e-5:
			k = (tk * _grest(sk, hb)).origin.y / hs
	var path := String(root.get_path_to(sk))
	var lib: AnimationLibrary = ap.get_animation_library("nika") if ap.has_animation_library("nika") else AnimationLibrary.new()
	for role in map:
		var an := find_anim(sap, [String(map[role])])
		if an == "":
			continue
		var nn := an
		var ck := root.scene_file_path + "|" + nn
		if not lib.has_animation(nn) and _done.has(ck) and root.scene_file_path != "":
			lib.add_animation(nn, _done[ck])
		if not lib.has_animation(nn):
			var a := sap.get_animation(an).duplicate(true) as Animation
			for t in range(a.get_track_count() - 1, -1, -1):
				var sb := String(a.track_get_path(t).get_concatenated_subnames())
				var ty := a.track_get_type(t)
				var si := ssk.find_bone(sb) if sb != "" else -1
				var ti: int = by_key.get(_bkey(sb), -1) if si >= 0 else -1
				if ti < 0 or not (ty == Animation.TYPE_ROTATION_3D or (ty == Animation.TYPE_POSITION_3D and si == shb)):
					a.remove_track(t)
					continue
				a.track_set_path(t, NodePath(path + ":" + sk.get_bone_name(ti)))
				if ty == Animation.TYPE_ROTATION_3D:
					var qa := (skx.basis * _grest(ssk, si).basis).orthonormalized().get_rotation_quaternion()
					var qb := (tk.basis * _grest(sk, ti).basis).orthonormalized().get_rotation_quaternion()
					var ls := sk.get_bone_rest(ti).basis.orthonormalized().get_rotation_quaternion()
					var lss := ssk.get_bone_rest(si).basis.orthonormalized().get_rotation_quaternion()
					var m := qb.inverse() * qa
					for i in a.track_get_key_count(t):
						var q: Quaternion = a.track_get_key_value(t, i)
						a.track_set_key_value(t, i, (ls * m * (lss.inverse() * q) * m.inverse()).normalized())
				else:
					var sp := ssk.get_bone_parent(si)
					var tp := sk.get_bone_parent(ti)
					var fs := skx.basis * (_grest(ssk, sp).basis if sp >= 0 else Basis.IDENTITY)
					var ft := tk.basis * (_grest(sk, tp).basis if tp >= 0 else Basis.IDENTITY)
					var r0 := ssk.get_bone_rest(si).origin
					var t0 := sk.get_bone_rest(ti).origin
					for i in a.track_get_key_count(t):
						var v: Vector3 = a.track_get_key_value(t, i)
						a.track_set_key_value(t, i, t0 + ft.inverse() * (fs * (v - r0) * k))
			lib.add_animation(nn, a)
			_done[ck] = a
		out[role] = "nika/" + nn
	if not ap.has_animation_library("nika") and not out.is_empty():
		var cur := ap.current_animation
		var at := ap.current_animation_position if cur != "" else 0.0
		ap.stop()
		ap.add_animation_library("nika", lib)
		if cur != "":
			ap.play(cur)
			ap.seek(at, true)
	return out
