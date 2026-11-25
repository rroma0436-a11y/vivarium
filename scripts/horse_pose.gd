extends SkeletonModifier3D
## Коням: пасеться — шия плавно опускається аж до трави (морда торкається землі), голова жує.
## peck — та сама ручка, що й у bird_pose.gd (0 — голова вгорі, ≈0.85 — пасеться).

var peck := 0.0
var axis_node: Node3D
var _chain: Array = []          # кістки шиї від тулуба до голови
var _w: Array = []              # частка нахилу кожної
var _head := -1
var _tip := -1
var _t := 0.0


func setup(sk: Skeleton3D) -> void:
	for n in ["neck0", "neck1", "neck2"]:
		var b := sk.find_bone(n)
		if b >= 0:
			_chain.append(b)
	_head = sk.find_bone("head0")
	_tip = sk.find_bone("head_end")
	if _chain.size() == 1:
		_w = [1.0]
	elif _chain.size() == 2:
		_w = [0.62, 0.38]
	else:
		_w = [0.5, 0.3, 0.2]


func _turn(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or absf(angle) < 0.0005:
		return
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(axis.normalized(), angle) * g.basis)).get_rotation_quaternion())


func _tip_y(sk: Skeleton3D) -> float:
	if _tip >= 0:
		return (sk.global_transform * sk.get_bone_global_pose(_tip).origin).y
	if _head >= 0:
		var hg := sk.get_bone_global_pose(_head)
		return (sk.global_transform * (hg.origin + hg.basis.y * 0.35)).y
	return 0.0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or axis_node == null or peck < 0.001 or _chain.is_empty():
		return
	_t += get_process_delta_time() if is_inside_tree() else 0.016
	var side := (sk.global_transform.basis.inverse() * axis_node.global_transform.basis.x).normalized()
	var bones: Array = _chain.duplicate()
	if _head >= 0:
		bones.append(_head)
	var orig: Array = []
	for b in bones:
		orig.append(sk.get_bone_pose_rotation(b))
	var ground := axis_node.global_position.y + (0.06 if _tip >= 0 else 0.12)
	var apply := func(x: float) -> void:
		for i in bones.size():
			sk.set_bone_pose_rotation(bones[i], orig[i])
		for i in _chain.size():
			_turn(sk, _chain[i], side, x * float(_w[i]))
		if _head >= 0:
			_turn(sk, _head, side, x * 0.3)
	# на скільки нахилити шию, щоб морда дісталася трави (пошук половинним діленням)
	var lo := 0.0
	var hi := 1.7
	for k in 7:
		var mid := (lo + hi) * 0.5
		apply.call(mid)
		if _tip_y(sk) > ground:
			lo = mid
		else:
			hi = mid
	var reach := clampf(peck / 0.85, 0.0, 1.0)
	var ang := lo * reach
	apply.call(ang)
	if _head >= 0 and reach > 0.6:
		_turn(sk, _head, side, sin(_t * 7.0) * 0.06 * reach)          # жує
