extends SkeletonModifier3D
## Пози людини поверх анімації (коли в моделі немає готових рухів):
## sit — сидить (стегна вперед, гомілки вниз); drink — права рука з кухлем біля рота;
## carry — права рука витягнута вперед (тягнеться до речі або несе відро/кошик).
## Кістки «наводяться» в потрібному напрямку — не залежить від того, як модель зібрана.

var sit := 0.0
var drink := 0.0
var carry := 0.0
var carry_l := 0.0      # те саме лівою рукою (річ у лівій, коли в правій кошик)
var ride := 0.0          # верхи на драконі: ноги по боках спини, руки тримаються попереду
var life := 0.0         # стоїть на місці: дихає, ледь гойдається, роззирається
var lean := 0.0         # нахил тулуба вперед (радіани; трактор: тягнеться до керма, лізе вгору)
var swim := 0.0         # пливе (вага пози 0..1)
var swim_move := 0.0    # 0 — тримається на воді (ноги «велосипед», долоні гребуть туди-сюди), 1 — пливе брасом
var swim_ph := 0.0      # фаза гребка 0..1
var body_node: Node3D   # тіло, що лежить на воді: його «вгору» — до голови, «вперед» — груди
## Кисті й ступні в задані точки (IK на дві кістки): "LeftHand"/"RightHand"/"LeftFoot"/"RightFoot" →
## [точка у світі (Vector3), вага 0..1]. Лікті йдуть донизу й убік, коліна — вперед.
var ik := {}
var axis_node: Node3D
var _b := {}
var _lt := 0.0


func setup(sk: Skeleton3D) -> void:
	for key in ["LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
			"RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand", "Head", "Neck", "Spine", "Spine1", "Spine2",
			"LeftToeBase", "RightToeBase", "Hips"]:
		_b[key] = find(sk, key)


static func find(sk: Skeleton3D, key: String) -> int:
	## Кістка за назвою без префікса («mixamorig_LeftLeg», «mixamorig:LeftLeg» або просто «LeftLeg»).
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n == key or n.ends_with("_" + key) or n.ends_with(":" + key):
			return i
	return -1


func _aim(sk: Skeleton3D, bone: String, child: String, want: Vector3, w: float) -> void:
	## Повернути кістку так, щоб вона дивилася в напрямку want (у просторі скелета), з вагою w.
	var b: int = _b[bone]
	var c: int = _b[child]
	if b < 0 or c < 0 or w < 0.001:
		return
	var g := sk.get_bone_global_pose(b)
	var cur := sk.get_bone_global_pose(c).origin - g.origin
	if cur.length() < 0.0001:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	q = Quaternion.IDENTITY.slerp(q, clampf(w, 0.0, 1.0))
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var turned := Basis(q) * g.basis
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * turned).get_rotation_quaternion())


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or axis_node == null:
		return
	if life > 0.001 and swim < 0.5:
		_alive(sk)
	if absf(lean) > 0.001 or not ik.is_empty():
		_reach(sk)
	if swim > 0.001:
		_swim(sk)
		return
	if sit < 0.001 and drink < 0.001 and carry < 0.001 and carry_l < 0.001 and ride < 0.001:
		return
	var inv := sk.global_transform.basis.inverse()
	var fwd := (inv * axis_node.global_transform.basis.z).normalized()
	var up := (inv * axis_node.global_transform.basis.y).normalized()
	var side := (inv * axis_node.global_transform.basis.x).normalized()   # вліво для персонажа
	if sit > 0.001:
		for s in ["Left", "Right"]:
			var spread := side * (0.12 if s == "Left" else -0.12)
			_aim(sk, s + "UpLeg", s + "Leg", fwd + spread - up * 0.08, sit)
			_aim(sk, s + "Leg", s + "Foot", -up + fwd * 0.12, sit)
	if ride > 0.001:
		for s in ["Left", "Right"]:
			var sd := side if s == "Left" else -side
			_aim(sk, s + "UpLeg", s + "Leg", fwd * 0.7 + sd * 0.55 - up * 0.4, ride)
			_aim(sk, s + "Leg", s + "Foot", -up * 0.9 + fwd * 0.12 + sd * 0.2, ride)
			_aim(sk, s + "Arm", s + "ForeArm", fwd * 0.55 - up * 0.7 + sd * 0.12, ride)
			_aim(sk, s + "ForeArm", s + "Hand", fwd * 0.9 - up * 0.35 - sd * 0.15, ride)
	if carry > 0.001:
		_aim(sk, "RightArm", "RightForeArm", fwd * 0.55 - up * 0.8 - side * 0.12, carry)
		_aim(sk, "RightForeArm", "RightHand", fwd * 0.95 - up * 0.2 + side * 0.1, carry)
	if carry_l > 0.001:
		_aim(sk, "LeftArm", "LeftForeArm", fwd * 0.55 - up * 0.8 + side * 0.12, carry_l)
		_aim(sk, "LeftForeArm", "LeftHand", fwd * 0.95 - up * 0.2 - side * 0.1, carry_l)
	if drink > 0.001:
		_aim(sk, "RightArm", "RightForeArm", fwd * 0.55 - up * 0.75 - side * 0.05, drink)
		var hb: int = _b["Head"]
		var eb: int = _b["RightForeArm"]
		if hb >= 0 and eb >= 0:
			var mouth := sk.get_bone_global_pose(hb).origin + fwd * 0.14 * _scale(sk) - up * 0.02 * _scale(sk)
			var elbow := sk.get_bone_global_pose(eb).origin
			_aim(sk, "RightForeArm", "RightHand", mouth - elbow, drink)


func _scale(sk: Skeleton3D) -> float:
	## Розмір кісток у «скелетних» одиницях (моделі з Meshy бувають у сантиметрах).
	var a: int = _b["RightArm"]
	var b: int = _b["RightForeArm"]
	if a < 0 or b < 0:
		return 1.0
	return (sk.get_bone_global_pose(b).origin - sk.get_bone_global_pose(a).origin).length() / 0.28


func _rot(sk: Skeleton3D, key: String, axis: Vector3, angle: float) -> void:
	var b: int = _b.get(key, -1)
	if b < 0:
		return
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(axis.normalized(), angle) * g.basis)).get_rotation_quaternion())


func _alive(sk: Skeleton3D) -> void:
	## Живе стояння: груди підіймаються від дихання, тіло ледь гойдається, голова повільно роззирається.
	_lt += get_process_delta_time() if is_inside_tree() else 0.016
	var inv := sk.global_transform.basis.inverse()
	var side := (inv * axis_node.global_transform.basis.x).normalized()
	var up := (inv * axis_node.global_transform.basis.y).normalized()
	var fwd := (inv * axis_node.global_transform.basis.z).normalized()
	var br := sin(_lt * 1.7) * 0.025 * life
	_rot(sk, "Spine1" if _b.get("Spine1", -1) >= 0 else "Spine", side, -br)
	_rot(sk, "Spine", fwd, sin(_lt * 0.45) * 0.03 * life)
	var look := (sin(_lt * 0.31) * 0.6 + sin(_lt * 0.83 + 1.0) * 0.4) * 0.35 * life
	_rot(sk, "Neck", up, look * 0.4)
	_rot(sk, "Head", up, look * 0.6)
	_rot(sk, "Head", side, sin(_lt * 0.5 + 2.0) * 0.06 * life)
	# руки вільно звисають, ледь рухаються з диханням
	_rot(sk, "LeftArm", fwd, br * 0.8)
	_rot(sk, "RightArm", fwd, -br * 0.8)


# ------------------------------------------------------------------ IK: кисті й ступні в точку
const CHAINS := {
	"LeftHand": ["LeftArm", "LeftForeArm", "LeftHand"],
	"RightHand": ["RightArm", "RightForeArm", "RightHand"],
	"LeftFoot": ["LeftUpLeg", "LeftLeg", "LeftFoot"],
	"RightFoot": ["RightUpLeg", "RightLeg", "RightFoot"],
}


func _reach(sk: Skeleton3D) -> void:
	var inv := sk.global_transform.affine_inverse()
	var fwd := (inv.basis * axis_node.global_transform.basis.z).normalized()
	var up := (inv.basis * axis_node.global_transform.basis.y).normalized()
	var side := (inv.basis * axis_node.global_transform.basis.x).normalized()   # уліво
	if absf(lean) > 0.001:
		# нахил ділимо між трьома хребцями — спина гнеться плавно
		for b in ["Spine", "Spine1", "Spine2"]:
			_rot(sk, b, side, lean / 3.0)
	for key in ["LeftFoot", "RightFoot", "LeftHand", "RightHand"]:
		if not ik.has(key):
			continue
		var e: Array = ik[key]
		var w := clampf(float(e[1]), 0.0, 1.0)
		if w < 0.001:
			continue
		var out := side if key.begins_with("Left") else -side
		var pole: Vector3
		if key.ends_with("Hand"):
			pole = -up * 1.0 + out * 0.7 - fwd * 0.4         # лікоть донизу, трохи вбік і назад
		else:
			pole = fwd + out * 0.12                           # коліно вперед
		var c: Array = CHAINS[key]
		_ik2(sk, c[0], c[1], c[2], inv * (e[0] as Vector3), pole, w)
		if key.ends_with("Foot"):
			# ступня — носком уперед, ледь донизу (а не туди, куди дивиться гомілка)
			_aim(sk, key, key.replace("Foot", "ToeBase"), fwd - up * 0.25, w)


func _ik2(sk: Skeleton3D, upper: String, lower: String, end: String, t: Vector3, pole: Vector3, w: float) -> void:
	var bu: int = _b.get(upper, -1)
	var bl: int = _b.get(lower, -1)
	var be: int = _b.get(end, -1)
	if bu < 0 or bl < 0 or be < 0:
		return
	var a := sk.get_bone_global_pose(bu).origin
	var b := sk.get_bone_global_pose(bl).origin
	var c := sk.get_bone_global_pose(be).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to := t - a
	if to.length() < 0.0001 or l1 < 0.0001 or l2 < 0.0001:
		return
	var dir := to.normalized()
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.999)
	var pp := pole - dir * pole.dot(dir)
	if pp.length() < 0.0001:
		return
	pp = pp.normalized()
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var elbow := a + dir * (l1 * ca) + pp * (l1 * sqrt(1.0 - ca * ca))
	_aim(sk, upper, lower, elbow - a, w)
	var b2 := sk.get_bone_global_pose(bl).origin
	_aim(sk, lower, end, a + dir * d - b2, w)


# ------------------------------------------------------------------ плавання
# брас: [фаза, плече, передпліччя, стегно, гомілка]; вектор — (до голови, у бік грудей, убік назовні)
const BRASS := [
	[0.0, Vector3(1.0, 0.18, 0.1), Vector3(1.0, 0.12, -0.02), Vector3(-1.0, 0.05, 0.07), Vector3(-1.0, -0.06, 0.05)],     # ковзає, руки витягнуті
	[0.3, Vector3(1.0, 0.18, 0.1), Vector3(1.0, 0.12, -0.02), Vector3(-1.0, 0.05, 0.07), Vector3(-1.0, -0.06, 0.05)],
	[0.55, Vector3(0.45, 0.4, 0.85), Vector3(0.2, 0.9, 0.3), Vector3(-1.0, 0.08, 0.08), Vector3(-1.0, -0.06, 0.05)],     # руки розводить і гребе
	[0.72, Vector3(-0.05, 0.65, 0.6), Vector3(0.55, 0.3, -0.8), Vector3(-0.7, 0.5, 0.45), Vector3(0.55, -0.75, 0.35)],   # долоні під підборіддям, п'яти — до себе
	[0.86, Vector3(0.75, 0.4, 0.2), Vector3(0.95, 0.25, -0.1), Vector3(-0.85, 0.12, 0.6), Vector3(-0.6, -0.25, 0.65)],   # руки вперед, ноги штовхають
	[1.0, Vector3(1.0, 0.18, 0.1), Vector3(1.0, 0.12, -0.02), Vector3(-1.0, 0.05, 0.07), Vector3(-1.0, -0.06, 0.05)],
]


func _brass(t: float) -> Array:
	for i in BRASS.size() - 1:
		var a: Array = BRASS[i]
		var b: Array = BRASS[i + 1]
		if t <= float(b[0]):
			var u := smoothstep(0.0, 1.0, (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
			return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u), (a[3] as Vector3).lerp(b[3], u), (a[4] as Vector3).lerp(b[4], u)]
	var l: Array = BRASS[BRASS.size() - 1]
	return [l[1], l[2], l[3], l[4]]


func _swim(sk: Skeleton3D) -> void:
	var bn: Node3D = body_node if body_node else axis_node
	var inv := sk.global_transform.basis.inverse()
	var U := (inv * bn.global_transform.basis.y).normalized()     # до голови
	var F := (inv * bn.global_transform.basis.z).normalized()     # груди (у воді — донизу)
	var S := (inv * bn.global_transform.basis.x).normalized()     # уліво
	var k := _brass(swim_ph)
	var a := swim_ph * TAU
	var m := swim_move
	var w := swim
	for s in ["Left", "Right"]:
		var sd := S if s == "Left" else -S
		var off := 0.0 if s == "Left" else PI
		# тримається на воді: долоні гребуть туди-сюди перед грудьми, ноги по черзі крутять «велосипед»
		var t_au := Vector3(-0.25, 0.7, 0.6 + 0.1 * sin(a))
		var t_af := Vector3(-0.1, 0.8, 0.1 + 0.55 * sin(a + 0.6))
		var t_lt := Vector3(-0.85, 0.3 + 0.3 * sin(a * 2.0 + off), 0.18)
		var t_ls := Vector3(-0.9, -0.2 - 0.35 * sin(a * 2.0 + off + 1.2), 0.12)
		var segs := [[s + "Arm", s + "ForeArm", t_au.lerp(k[0], m)], [s + "ForeArm", s + "Hand", t_af.lerp(k[1], m)],
			[s + "UpLeg", s + "Leg", t_lt.lerp(k[2], m)], [s + "Leg", s + "Foot", t_ls.lerp(k[3], m)]]
		for sg in segs:
			var c: Vector3 = sg[2]
			_aim(sk, sg[0], sg[1], U * c.x + F * c.y + sd * c.z, w)
		_aim(sk, s + "Foot", s + "ToeBase", -U * 0.9 - F * 0.3 + sd * 0.1, w * 0.8)     # носки витягнуті
	# спина ледь прогинається, коли гребе руками; голова над водою дивиться вперед, на вдиху — трохи вище
	var pull := maxf(0.0, sin((swim_ph - 0.4) * TAU)) * m
	_rot(sk, "Spine1" if _b.get("Spine1", -1) >= 0 else "Spine", S, -0.12 * pull * w)
	var bend := w * lerpf(0.2, 0.7, m)
	_rot(sk, "Neck", S, -bend * 0.5)
	_rot(sk, "Head", S, -bend * 0.45 - 0.15 * pull * w)
