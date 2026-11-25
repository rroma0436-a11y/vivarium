extends SkeletonModifier3D
## Вирівнює голову моделі, яку Meshy зробив із повернутою до глядача головою:
## після кожного кадру анімації довертає шию так, щоб голова дивилась уздовж тіла.

var bone := -1
var yaw := 0.0          # на скільки довернути (радіани, навколо вертикалі скелета)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or bone < 0 or absf(yaw) < 0.001:
		return
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(bone)
	var turned := Basis(Vector3.UP, yaw) * g.basis
	sk.set_bone_pose_rotation(bone, (pg.basis.inverse() * turned).get_rotation_quaternion())
