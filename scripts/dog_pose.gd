extends SkeletonModifier3D
## Пози песика кодом (у моделі є тільки ходьба, біг, їжа, хвостик):
## sit — сідає, lie — лягає, paw — дає лапу (сидячи), eat_low — нижче опускає голову до миски.
## Кістки «наводяться» в потрібний бік у системі координат песика (вперед / вгору).

var sit := 0.0
var lie := 0.0
var paw := 0.0
var eat_low := 0.0
var axis_node: Node3D          # вузол песика (його осі: +Z вперед, +Y вгору)
var _b := {}


func setup(sk: Skeleton3D) -> void:
	for s in ["L", "R"]:
		for n in ["rearUpr", "rearLwr", "rearHorselink", "rearFoot", "clavicle", "frontLwr", "frontHorselink", "frontFoot"]:
			_b[n + "_" + s] = sk.find_bone(n + "_" + s)
		# інший пес (Meshy): передня лапа — frontUpr → frontLeg_X_03 → frontHorselink → frontToe
		if _b["frontLwr_" + s] < 0 and sk.find_bone("frontUpr_" + s) >= 0:
			_b["clavicle_" + s] = sk.find_bone("frontUpr_" + s)
			_b["frontLwr_" + s] = sk.find_bone("frontLeg_%s_03" % s)
			_b["frontFoot_" + s] = sk.find_bone("frontToe_" + s)
	for n in ["neck_01", "neck1", "head", "chest", "hips"]:
		_b[n] = sk.find_bone(n)
	if _b["neck_01"] < 0:
		_b["neck_01"] = _b["neck1"]


func _aim(sk: Skeleton3D, bone: String, child: String, want: Vector3, w: float) -> void:
	var b: int = _b.get(bone, -1)
	var c: int = _b.get(child, -1)
	if b < 0 or c < 0 or w < 0.001:
		return
	var g := sk.get_bone_global_pose(b)
	var cur := sk.get_bone_global_pose(c).origin - g.origin
	if cur.length() < 0.00001:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	q = Quaternion.IDENTITY.slerp(q, clampf(w, 0.0, 1.0))
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(q) * g.basis)).get_rotation_quaternion())


func _turn(sk: Skeleton3D, bone: String, axis: Vector3, angle: float) -> void:
	var b: int = _b.get(bone, -1)
	if b < 0 or absf(angle) < 0.0005:
		return
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(axis.normalized(), angle) * g.basis)).get_rotation_quaternion())


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or axis_node == null:
		return
	if sit < 0.001 and lie < 0.001 and paw < 0.001 and eat_low < 0.001:
		return
	var inv := sk.global_transform.basis.inverse()
	var f := (inv * axis_node.global_transform.basis.z).normalized()
	var u := (inv * axis_node.global_transform.basis.y).normalized()
	var side := (inv * axis_node.global_transform.basis.x).normalized()
	# голова нижче до миски
	if eat_low > 0.001:
		_turn(sk, "neck_01", side, deg_to_rad(28.0) * eat_low)
	# задні лапки складені (і для «сидіти», і для «лежати»)
	var fold := maxf(sit, lie)
	if fold > 0.001:
		for s in ["L", "R"]:
			_aim(sk, "rearUpr_" + s, "rearLwr_" + s, f * 0.85 - u * 0.35, fold)
			_aim(sk, "rearLwr_" + s, "rearHorselink_" + s, -f * 0.8 - u * 0.45, fold)
			_aim(sk, "rearHorselink_" + s, "rearFoot_" + s, f * 1.0 - u * 0.12, fold)
	# передні лапки: сидячи — рівно вниз, лежачи — витягнуті вперед
	for s in ["L", "R"]:
		var wsit := sit * (1.0 - lie)
		if wsit > 0.001:
			var pw := paw if s == "R" else 0.0
			var down := -u + f * 0.08
			var up_fwd := f * 0.9 + u * 0.35
			_aim(sk, "clavicle_" + s, "frontLwr_" + s, down.lerp(up_fwd, pw), wsit)
			_aim(sk, "frontLwr_" + s, "frontHorselink_" + s, down.lerp(f + u * 0.1, pw), wsit)
			_aim(sk, "frontHorselink_" + s, "frontFoot_" + s, down.lerp(f - u * 0.3, pw), wsit)
		if lie > 0.001:
			_aim(sk, "clavicle_" + s, "frontLwr_" + s, f * 0.5 - u * 0.85, lie)
			_aim(sk, "frontLwr_" + s, "frontHorselink_" + s, f * 1.0 - u * 0.05, lie)
			_aim(sk, "frontHorselink_" + s, "frontFoot_" + s, f, lie)
