extends SkeletonModifier3D
## Процедурна анімація гекона (модель зі Smart Rig без готових рухів):
## лапки переступають «по діагоналі», хвіст і тіло вигинаються, голова повертається й киває.

var legs_front_l := -1
var legs_front_r := -1
var legs_rear_l := -1
var legs_rear_r := -1
var tail: Array = []
var spine := -1
var head := -1
var phase := 0.0          # фаза кроку (крутить скрипт тераріуму)
var stride := 0.0         # 0 — стоїть, 1 — біжить
var look := 0.0           # поворот голови
var nod := 0.0            # кивок (коли ловить цвіркуна)
var breathe := 0.0


func setup(sk: Skeleton3D) -> void:
	legs_front_l = sk.find_bone("joint_21")
	legs_front_r = sk.find_bone("joint_25")
	legs_rear_l = sk.find_bone("joint_08")
	legs_rear_r = sk.find_bone("joint_12")
	spine = sk.find_bone("joint_02")
	head = sk.find_bone("joint_28")
	for n in ["joint_17", "joint_16", "joint_15", "joint_14"]:
		var b := sk.find_bone(n)
		if b >= 0:
			tail.append(b)


func _turn(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 0.0005:
		return
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(bone)
	var turned := Basis(axis, angle) * g.basis
	sk.set_bone_pose_rotation(bone, (pg.basis.inverse() * turned).get_rotation_quaternion())


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var s := sin(phase)
	var w := stride
	# тіло вигинається хвилею, як у справжньої ящірки
	_turn(sk, spine, Vector3.UP, s * 0.22 * w)
	# лапки: ліва передня з правою задньою, і навпаки
	# (однаковий кут для лівої й правої лапи дає протилежний рух, бо вони дивляться в різні боки)
	_turn(sk, legs_front_l, Vector3.UP, s * 0.6 * w)
	_turn(sk, legs_front_r, Vector3.UP, s * 0.6 * w)
	_turn(sk, legs_rear_l, Vector3.UP, -s * 0.6 * w)
	_turn(sk, legs_rear_r, Vector3.UP, -s * 0.6 * w)
	# хвіст: хвиля з запізненням + легке погойдування, коли стоїть
	for i in tail.size():
		var a := sin(phase - 0.9 * (i + 1)) * 0.28 * w + sin(breathe * 0.7 + i * 0.6) * 0.06 * (1.0 - w)
		_turn(sk, tail[i], Vector3.UP, a)
	# голова: дивиться навколо й киває
	_turn(sk, head, Vector3.UP, look - s * 0.15 * w)
	_turn(sk, head, Vector3.RIGHT, nod)
