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


func _ready() -> void:
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


func _fade(p: AudioStreamPlayer, target: float, delta: float) -> void:
	if p and p.stream:
		p.volume_db = move_toward(p.volume_db, target, delta * 20.0)
