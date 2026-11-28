extends Node
## Звук гри: фон дня й ночі (пташки, ферма, цвіркуни), спокійна музика вдень,
## звуки «з місця» (Бім гавкає там, де він стоїть) і звуки інтерфейсу.
## Звуки — з Мультстудії (Kenney, OpenGameArt, freesound; див. CREDITS.md).

const DIR := "res://assets/sounds/%s.ogg"

var _cache := {}
var _amb_day: AudioStreamPlayer
var _amb_farm: AudioStreamPlayer
var _amb_night: AudioStreamPlayer
var _music: AudioStreamPlayer
var _ui: Array = []
var _pos: Array = []
var _t := 0.0
var _next_owl := 20.0
static var inst: Node = null
var _voice: AudioStreamPlayer
var _voice_q: Array = []
# звуки природи «з місця»: річка, ставок, ліс (вдень), дощ; уночі в лісі — нічні голоси, вдень — дятел
var _amb_river: AudioStreamPlayer
var _amb_lake: AudioStreamPlayer
var _amb_forest: AudioStreamPlayer
var _amb_rain: AudioStreamPlayer
var _next_wood := 15.0
var _next_fnight := 12.0
# погода: час від часу дощ, інколи з грозою (блискавка й грім)
var raining := false
var storm := false
var _rain_left := 0.0
var _next_rain := randf_range(240.0, 480.0)
var _next_thunder := 8.0
var _rain_fx: CPUParticles3D
var _flash: ColorRect

const RIVER_Z := 102.0                          # як у world_outer.gd
const POND := Vector3(-70, 0, 31)
const POND_HALF := Vector2(21.0, 14.0)
const POND_CORNER := 6.0
const FOREST_C := Vector3(-30.0, 0, -388.0)
const FOREST_R := 40.0
const PLOW_FIELD := Rect2(74.0, -18.0, 22.0, 20.0)


func _ready() -> void:
	inst = self
	_voice = AudioStreamPlayer.new()
	_voice.bus = "SFX"
	add_child(_voice)
	_voice.finished.connect(_voice_next)
	for b in ["Music", "Amb", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -14.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Amb"), -8.0)
	_amb_day = _loop("amb_birds", "Amb")
	_amb_farm = _loop("amb_farm", "Amb")
	_amb_night = _loop("amb_night", "Amb")
	_music = _loop("music_flower", "Music")
	_amb_river = _loop("amb_river", "Amb")
	_amb_lake = _loop("amb_lake", "Amb")
	_amb_forest = _loop("amb_forest", "Amb")
	_amb_rain = _loop("amb_rain", "Amb")
	_make_weather_fx()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_ui.append(p)
	set_muted(bool(Game.state.get("muted", false)))


func _stream(id: String) -> AudioStream:
	if not _cache.has(id):
		var path := DIR % id
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]


func _loop(id: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	var s := _stream(id)
	if s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	p.volume_db = -80.0
	add_child(p)
	if s:
		p.play()
	return p


func play(id: String, vol_db := 0.0, pitch := 1.0) -> void:
	## Звук без місця (кнопки, монетки, завдання).
	var s := _stream(id)
	if s == null:
		return
	for p in _ui:
		if not (p as AudioStreamPlayer).playing:
			p.stream = s
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return
	(_ui[0] as AudioStreamPlayer).stream = s
	(_ui[0] as AudioStreamPlayer).play()


func play_at(id: String, where: Node3D, vol_db := 0.0, pitch := 1.0) -> void:
	## Звук «з місця»: чим ближче камера, тим голосніше.
	var s := _stream(id)
	if s == null or where == null or not where.is_inside_tree():
		return
	var p: AudioStreamPlayer3D = null
	for q in _pos:
		if not (q as AudioStreamPlayer3D).playing:
			p = q
			break
	if p == null:
		if _pos.size() >= 8:
			p = _pos[0]
		else:
			p = AudioStreamPlayer3D.new()
			p.bus = "SFX"
			p.unit_size = 4.0
			p.max_distance = 40.0
			add_child(p)
			_pos.append(p)
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.global_position = where.global_position + Vector3(0, 0.4, 0)
	p.play()


func voice(ids: Array) -> void:
	## Репліка записаним голосом (кілька частин — одна за одною); нова перериває попередню.
	_voice_q = ids.duplicate()
	_voice.stop()
	_voice_next()


func _voice_next() -> void:
	while not _voice_q.is_empty():
		var s := _stream(String(_voice_q.pop_front()))
		if s != null:
			_voice.stream = s
			_voice.play()
			return


func set_muted(m: bool) -> void:
	Game.state["muted"] = m
	AudioServer.set_bus_mute(0, m)


func is_muted() -> bool:
	return AudioServer.is_bus_mute(0)


func _process(delta: float) -> void:
	_t += delta
	var n := Game.night_amount()
	var indoor: bool = Game.state["location"] == "room"
	var muffle := -12.0 if indoor else 0.0
	_fade(_amb_day, lerpf(-4.0, -60.0, n) + muffle, delta)
	_fade(_amb_farm, lerpf(-12.0, -60.0, n) + muffle, delta)
	_fade(_amb_night, lerpf(-60.0, -2.0, n) + muffle, delta)
	_fade(_music, lerpf(0.0, -60.0, smoothstep(0.2, 0.7, n)), delta)
	_nature(delta, n, indoor, muffle)
	_weather(delta, indoor, muffle)


func _listener() -> Vector3:
	var c: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	return c.global_position if c else Vector3.ZERO


static func _pond_sd(p: Vector3) -> float:
	var q := Vector2(absf(p.x - POND.x), absf(p.z - POND.z)) - (POND_HALF - Vector2(POND_CORNER, POND_CORNER))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - POND_CORNER


static func forest_k(p: Vector3) -> float:
	## 0 — не ліс, 1 — глибоко в лісі (північний грибний ліс або ліс на сході).
	var kn := 1.0 - smoothstep(FOREST_R, FOREST_R + 25.0, Vector2(p.x - FOREST_C.x, p.z - FOREST_C.z).length())
	var ke := 0.0
	if p.z > -110.0 and p.z < 80.0 and p.x < 170.0 and not PLOW_FIELD.grow(5.0).has_point(Vector2(p.x, p.z)):
		var edge := 103.0 - (p.z + 102.0) * 0.1437
		ke = smoothstep(edge - 20.0, edge + 6.0, p.x)
	return maxf(kn, ke)


func _near(d: float, full: float, gone: float) -> float:
	## 1 — поруч (ближче full м), 0 — далі gone м.
	return 1.0 - smoothstep(full, gone, d)


func _db(k: float, top: float) -> float:
	return lerpf(-60.0, top, k) if k > 0.001 else -80.0


func _nature(delta: float, n: float, indoor: bool, muffle: float) -> void:
	var p := _listener()
	var kr := 0.0 if indoor else _near(absf(p.z - RIVER_Z), 8.0, 45.0)
	var kl := 0.0 if indoor else _near(maxf(_pond_sd(p), 0.0), 6.0, 40.0)
	var kf := 0.0 if indoor else forest_k(p)
	_fade(_amb_river, _db(kr, -3.0) + muffle, delta)
	_fade(_amb_lake, _db(kl, -4.0) + muffle, delta)
	_fade(_amb_forest, _db(kf * (1.0 - n), -2.0) + muffle, delta)
	if kf > 0.5:
		_next_wood -= delta
		_next_fnight -= delta
		if n < 0.4 and _next_wood <= 0.0 and not raining:
			_next_wood = randf_range(18.0, 45.0)
			play("woodpecker", lerpf(-14.0, -6.0, kf), randf_range(0.92, 1.08))
		if n > 0.6 and _next_fnight <= 0.0:
			_next_fnight = randf_range(20.0, 50.0)
			play("forest_night", lerpf(-14.0, -5.0, kf), randf_range(0.9, 1.05))


# ------------------------------------------------------------------ погода: дощ і гроза
func _make_weather_fx() -> void:
	_rain_fx = CPUParticles3D.new()
	_rain_fx.name = "Rain"
	_rain_fx.amount = 700
	_rain_fx.lifetime = 1.1
	_rain_fx.emitting = false
	_rain_fx.local_coords = false
	_rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain_fx.emission_box_extents = Vector3(14.0, 0.5, 14.0)
	_rain_fx.direction = Vector3(0.08, -1.0, 0.0)
	_rain_fx.spread = 2.0
	_rain_fx.initial_velocity_min = 14.0
	_rain_fx.initial_velocity_max = 17.0
	_rain_fx.gravity = Vector3(0, -9.8, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.45)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	_rain_fx.mesh = q
	add_child(_rain_fx)
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	_flash = ColorRect.new()
	_flash.color = Color(0.92, 0.95, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_flash)


func start_rain(with_storm := false, secs := 0.0) -> void:
	raining = true
	storm = with_storm
	_rain_left = secs if secs > 0.0 else randf_range(90.0, 200.0)
	_next_thunder = randf_range(4.0, 10.0)


func _weather(delta: float, indoor: bool, muffle: float) -> void:
	if raining:
		_rain_left -= delta
		if _rain_left <= 0.0:
			raining = false
			storm = false
			_next_rain = randf_range(300.0, 720.0)
	else:
		_next_rain -= delta
		if _next_rain <= 0.0:
			if randf() < 0.45:
				start_rain(randf() < 0.35)
			else:
				_next_rain = randf_range(200.0, 500.0)
	_fade(_amb_rain, (-2.0 if raining else -80.0) + (muffle * 0.6 if indoor else 0.0), delta * 0.5)
	if _rain_fx:
		var show := raining and not indoor
		if _rain_fx.emitting != show:
			_rain_fx.emitting = show
		if show:
			_rain_fx.global_position = _listener() + Vector3(0, 9.0, 0)
	if storm:
		_next_thunder -= delta
		if _next_thunder <= 0.0:
			_next_thunder = randf_range(12.0, 30.0)
			_lightning(indoor)


func _lightning(indoor: bool) -> void:
	## Спалах блискавки, а за мить — грім (що далі блискавка, то пізніше й тихіше).
	var far := randf()
	if _flash and not indoor:
		var t := create_tween()
		t.tween_property(_flash, "color:a", 0.55, 0.05)
		t.tween_property(_flash, "color:a", 0.05, 0.08)
		t.tween_property(_flash, "color:a", 0.4, 0.05)
		t.tween_property(_flash, "color:a", 0.0, 0.35)
	await get_tree().create_timer(0.4 + far * 2.5).timeout
	play("thunder", lerpf(-2.0, -12.0, far) + (-8.0 if indoor else 0.0), randf_range(0.85, 1.05))


func _fade(p: AudioStreamPlayer, target: float, delta: float) -> void:
	if p and p.stream:
		p.volume_db = move_toward(p.volume_db, target, delta * 20.0)
