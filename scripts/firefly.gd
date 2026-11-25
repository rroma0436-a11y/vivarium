extends Node3D
## Світлячок (або падаюча зірка): плаває туди-сюди й ледь мерехтить.
var drift := 0.6
var _t := randf() * 10.0
var _base := Vector3.ZERO


func _ready() -> void:
	_base = position


func _process(delta: float) -> void:
	_t += delta
	if _base == Vector3.ZERO:
		_base = position
	position = _base + Vector3(sin(_t * 0.7) * drift, sin(_t * 1.3) * 0.25 * maxf(drift / 2.0, 1.0), cos(_t * 0.5) * drift)
	var l := get_node_or_null("OmniLight3D")
	for c in get_children():
		if c is OmniLight3D:
			c.light_energy = (1.0 + sin(_t * 6.0) * 0.4) * (3.0 if drift > 1.0 else 1.4)
