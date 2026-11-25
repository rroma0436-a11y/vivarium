extends SkeletonModifier3D
## Птахам (курка, півень, гуска): нахил шиї — клювання зерна та пиття.

var peck := 0.0
var axis_node: Node3D
var _neck := -1
var _head := -1


func setup(sk: Skeleton3D) -> void:
	_neck = sk.find_bone("neck0")
	_head = sk.find_bone("neck3")
	if _head < 0:
		_head = sk.find_bone("head0")        # бик: голова одразу після шиї


func _turn(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or absf(angle) < 0.0005:
		return
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(axis.normalized(), angle) * g.basis)).get_rotation_quaternion())


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or axis_node == null or peck < 0.001:
		return
	var side := (sk.global_transform.basis.inverse() * axis_node.global_transform.basis.x).normalized()
	_turn(sk, _neck, side, deg_to_rad(55.0) * peck)
	_turn(sk, _head, side, deg_to_rad(30.0) * peck)
