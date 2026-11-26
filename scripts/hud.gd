extends Control
## Інтерфейс: завдання, монетки, стан тварин, кнопки дій, діалог дідуся, підказки.

signal action(name: String)            # кнопка дії: feed, lamp, crickets, go_yard, go_room, help

var title_font: Font
var bold: Font
var quest_label: Label
var coins_label: Label
var place_label: Label
var place_provider: Callable          # назва місця, де Beep (подвір'я, село, річка…)
var minimap: Control
var status_label: Label
var actions_box: HBoxContainer
var dialog: Control
var dialog_name: Label
var dialog_text: Label
var dialog_portrait: TextureRect
var dialog_ok: Button
var toast_label: Label
var toast_panel: PanelContainer
var _toast_left := 0.0
var _dialog_queue: Array = []
var _on_dialog_close: Callable
var buttons := {}
var bottom_bar: Control
var flight                            # керування польотом на драконі


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_font = load("res://assets/fonts/RuslanDisplay-Regular.ttf")
	var fb: Font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	if title_font is FontFile:
		(title_font as FontFile).fallbacks = [fb]
	bold = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	theme = _make_theme()
	_build_top()
	_build_bottom()
	_build_dialog()
	_build_toast()
	_build_beep_menu()
	flight = preload("res://scripts/flight_pad.gd").new()
	add_child(flight)
	Game.changed.connect(refresh)
	refresh()
	# виріз камери й заокруглені кути телефону не мають закривати кнопки й написи
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area.call_deferred()


func _apply_safe_area() -> void:
	## Увесь інтерфейс — у «безпечній» зоні екрана (без вирізу камери й заокруглених кутів) і трохи далі від країв.
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var vr := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var kx := vr.x / float(win.x)
	var ky := vr.y / float(win.y)
	var edge := 10.0 if OS.has_feature("mobile") else 0.0          # запас від країв на телефоні
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if safe.size.x > 0 and safe.size.y > 0:
		l = maxf(0.0, float(safe.position.x)) * kx
		t = maxf(0.0, float(safe.position.y)) * ky
		r = maxf(0.0, float(win.x - safe.end.x)) * kx
		b = maxf(0.0, float(win.y - safe.end.y)) * ky
	offset_left = minf(l + edge, vr.x * 0.12)
	offset_top = minf(t + edge, vr.y * 0.12)
	offset_right = -minf(r + edge, vr.x * 0.12)
	offset_bottom = -minf(b + edge, vr.y * 0.12)


# ------------------------------------------------------------------ тема
func _box(col: Color, radius := 22, border := Color(0, 0, 0, 0), bw := 0, shadow := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow > 0:
		s.shadow_color = Color(0.1, 0.05, 0.2, 0.25)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 3)
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = load("res://assets/fonts/DejaVuSans.ttf")
	t.default_font_size = 22
	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.96)))
	t.set_stylebox("hover", "Button", _box(Color(1, 0.97, 0.9)))
	t.set_stylebox("pressed", "Button", _box(Color(0.93, 0.88, 1.0), 22, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _box(Color(0.9, 0.9, 0.92, 0.8)))
	t.set_color("font_color", "Button", Color(0.2, 0.15, 0.35))
	t.set_color("font_hover_color", "Button", Color(0.2, 0.15, 0.35))
	t.set_color("font_pressed_color", "Button", Color(0.35, 0.2, 0.6))
	t.set_font("font", "Button", bold)
	t.set_stylebox("panel", "PanelContainer", _box(Color(1, 1, 1, 0.9), 24))
	t.set_color("font_color", "Label", Color(0.2, 0.15, 0.35))
	return t


func _btn(text: String, key: String, color := Color(1, 1, 1, 0.96)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 72)
	b.add_theme_font_size_override("font_size", 24)
	if color != Color(1, 1, 1, 0.96):
		b.add_theme_stylebox_override("normal", _box(color))
		b.add_theme_stylebox_override("hover", _box(color.lightened(0.08)))
		b.add_theme_stylebox_override("pressed", _box(color.darkened(0.1), 22, Color(0, 0, 0, 0), 0, 2))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
	b.pressed.connect(func():
		var au = get_node_or_null("/root/Main/Audio")
		if au:
			au.play("click", -6.0)
		action.emit(key))
	buttons[key] = b
	return b


# ------------------------------------------------------------------ верх: місце, завдання, монетки
func _build_top() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var place := PanelContainer.new()
	place_label = Label.new()
	place_label.add_theme_font_override("font", title_font)
	place_label.add_theme_font_size_override("font_size", 26)
	place_label.add_theme_color_override("font_color", Color(0.45, 0.25, 0.6))
	place.add_child(place_label)
	top.add_child(place)
	var q := PanelContainer.new()
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var qv := VBoxContainer.new()
	var qt := Label.new()
	qt.text = "Завдання"
	qt.add_theme_font_size_override("font_size", 15)
	qt.add_theme_color_override("font_color", Color(0.55, 0.45, 0.7))
	qv.add_child(qt)
	quest_label = Label.new()
	quest_label.add_theme_font_override("font", bold)
	quest_label.add_theme_font_size_override("font_size", 21)
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qv.add_child(quest_label)
	q.add_child(qv)
	top.add_child(q)
	var c := PanelContainer.new()
	coins_label = Label.new()
	coins_label.add_theme_font_override("font", bold)
	coins_label.add_theme_font_size_override("font_size", 24)
	coins_label.add_theme_color_override("font_color", Color(0.75, 0.5, 0.05))
	c.add_child(coins_label)
	top.add_child(c)
	var snd := Button.new()
	snd.text = "♪"
	snd.custom_minimum_size = Vector2(64, 0)
	snd.add_theme_font_override("font", bold)
	snd.add_theme_font_size_override("font_size", 28)
	snd.focus_mode = Control.FOCUS_NONE
	snd.pressed.connect(func(): action.emit("sound"))
	top.add_child(snd)
	buttons["sound"] = snd
	# стан тварин — під верхньою смугою, ліворуч
	var sp := PanelContainer.new()
	sp.position = Vector2(16, 104)
	sp.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.78), 18, Color(0, 0, 0, 0), 0, 0))
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	sp.add_child(status_label)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sp)


# ------------------------------------------------------------------ низ: дії й переходи
func _build_bottom() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = -90
	bar.offset_bottom = -12
	bar.add_theme_constant_override("separation", 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	bottom_bar = bar
	actions_box = HBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 12)
	actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(actions_box)
	actions_box.add_child(_btn("Корм", "feed", Color(0.95, 0.6, 0.25)))
	actions_box.add_child(_btn("Лампа", "lamp", Color(0.95, 0.45, 0.35)))
	actions_box.add_child(_btn("Цвіркуни", "crickets", Color(0.45, 0.7, 0.35)))
	bar.add_child(_btn("Beep, допоможи", "help", Color(0.3, 0.72, 0.7)))
	bar.add_child(_btn("Ніка", "girl_ctl", Color(0.85, 0.3, 0.4)))
	bar.add_child(_btn("На подвір'я", "go_yard", Color(0.55, 0.45, 0.85)))
	bar.add_child(_btn("У хату", "go_room", Color(0.55, 0.45, 0.85)))


# ------------------------------------------------------------------ діалог
func _build_dialog() -> void:
	dialog = Control.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.visible = false
	add_child(dialog)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.05, 0.2, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -300
	panel.offset_bottom = -24
	panel.add_theme_stylebox_override("panel", _box(Color(1, 0.98, 0.93, 0.98), 30, Color(0.85, 0.7, 0.45), 4, 10))
	dialog.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	panel.add_child(h)
	dialog_portrait = TextureRect.new()
	dialog_portrait.texture = load("res://assets/ui/grandpa.png")
	dialog_portrait.custom_minimum_size = Vector2(200, 200)
	dialog_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dialog_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(dialog_portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	h.add_child(v)
	dialog_name = Label.new()
	dialog_name.add_theme_font_override("font", title_font)
	dialog_name.add_theme_font_size_override("font_size", 28)
	dialog_name.add_theme_color_override("font_color", Color(0.5, 0.3, 0.15))
	v.add_child(dialog_name)
	dialog_text = Label.new()
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_text.add_theme_font_size_override("font_size", 23)
	v.add_child(dialog_text)
	dialog_ok = Button.new()
	dialog_ok.text = "Добре!"
	dialog_ok.custom_minimum_size = Vector2(220, 64)
	dialog_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	dialog_ok.add_theme_stylebox_override("normal", _box(Color(0.45, 0.72, 0.4)))
	dialog_ok.add_theme_stylebox_override("hover", _box(Color(0.5, 0.78, 0.45)))
	dialog_ok.add_theme_stylebox_override("pressed", _box(Color(0.38, 0.62, 0.34)))
	dialog_ok.add_theme_color_override("font_color", Color.WHITE)
	dialog_ok.add_theme_color_override("font_hover_color", Color.WHITE)
	dialog_ok.pressed.connect(_close_dialog)
	v.add_child(dialog_ok)


func show_dialog(who: String, text: String, portrait: Texture2D = null, then := Callable()) -> void:
	if dialog.visible:
		_dialog_queue.append([who, text, portrait, then])
		return
	dialog_name.text = who
	dialog_text.text = text
	dialog_portrait.texture = portrait if portrait != null else load("res://assets/ui/grandpa.png")
	dialog_portrait.visible = dialog_portrait.texture != null
	_on_dialog_close = then
	dialog.visible = true
	dialog.modulate.a = 0.0
	create_tween().tween_property(dialog, "modulate:a", 1.0, 0.25)


func _close_dialog() -> void:
	dialog.visible = false
	if _on_dialog_close.is_valid():
		var cb := _on_dialog_close
		_on_dialog_close = Callable()
		cb.call()
	if not _dialog_queue.is_empty():
		var d: Array = _dialog_queue.pop_front()
		show_dialog(d[0], d[1], d[2], d[3])


func dialog_open() -> bool:
	for m in [beep_menu, grandpa_menu, kid_menu, girl_menu, tractor_menu, granny_menu, hitch_menu, choice_menu]:
		if m != null and is_instance_valid(m) and m.visible:
			return true
	return dialog.visible


# ------------------------------------------------------------------ меню Beep
var beep_menu: Control
var _menu_box: GridContainer
var _menu_items := {}

const BEEP_ITEMS := [
	["hint", "Підказка", Color(0.3, 0.72, 0.7)],
	["scan", "Сканер ферми", Color(0.4, 0.55, 0.85)],
	["ball", "М'ячик для Біма", Color(0.9, 0.45, 0.35)],
	["drone_feed", "Дрон: нагодуй курей", Color(0.85, 0.65, 0.25)],
	["drone_water", "Дрон: полий город", Color(0.3, 0.6, 0.9)],
	["herd", "Біме, жени курей додому", Color(0.6, 0.5, 0.35)],
	["light", "Ліхтарик", Color(0.45, 0.4, 0.7)],
	["to_plane", "Летимо на літаку", Color(0.85, 0.6, 0.15)],
	["beep_ctl", "Керувати Beep самому", Color(0.3, 0.55, 0.8)],
	["home", "Додому, на подвір'я", Color(0.45, 0.6, 0.35)],
]


func _build_beep_menu() -> void:
	beep_menu = _make_menu("Beep, допоможи!", BEEP_ITEMS, Color(0.3, 0.72, 0.7), _menu_items)
	grandpa_menu = _make_menu("Дідусю, а що ти робитимеш?", GRANDPA_ITEMS, Color(0.75, 0.5, 0.32), _gp_items)
	kid_menu = _make_menu("Тарасику, чим займемось?", KID_ITEMS, Color(0.25, 0.55, 0.85), _kid_items)
	girl_menu = _make_menu("Ніка", GIRL_ITEMS, Color(0.85, 0.3, 0.4), _girl_items, 2)
	tractor_menu = _make_menu("Трактор Червоненький", TRACTOR_ITEMS, Color(0.8, 0.28, 0.2), _tr_items)
	hitch_menu = _make_menu("Причепи трактора", HITCH_ITEMS, Color(0.3, 0.45, 0.7), _th_items)
	granny_menu = _make_menu("Бабусю Галю, що робитимемо?", GRANNY_ITEMS, Color(0.82, 0.25, 0.25), _granny_items)


func _make_menu(title: String, items: Array, accent: Color, store: Dictionary, cols := 2) -> Control:
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.05, 0.2, 0.3)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			menu.visible = false)
	menu.add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.11
	panel.anchor_bottom = 0.9
	panel.add_theme_stylebox_override("panel", _box(Color(0.97, 0.99, 1.0, 0.97), 30, accent, 4, 10))
	menu.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", title_font)
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", accent.darkened(0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var box := GridContainer.new()
	box.columns = cols
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("h_separation", 14)
	box.add_theme_constant_override("v_separation", 14)
	v.add_child(box)
	if store == _menu_items:
		_menu_box = box
	for it in items:
		var b := Button.new()
		b.text = it[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 22)
		var col: Color = it[2]
		b.add_theme_stylebox_override("normal", _box(col))
		b.add_theme_stylebox_override("hover", _box(col.lightened(0.08)))
		b.add_theme_stylebox_override("pressed", _box(col.darkened(0.1), 22, Color(0, 0, 0, 0), 0, 2))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
		var key: String = it[0]
		b.pressed.connect(func():
			menu.visible = false
			var au = get_node_or_null("/root/Main/Audio")
			if au:
				au.play("click", -6.0)
			action.emit(key))
		box.add_child(b)
		store[key] = b
	var close := Button.new()
	close.text = "Закрити"
	close.custom_minimum_size = Vector2(220, 56)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): menu.visible = false)
	v.add_child(close)
	return menu


var grandpa_menu: Control
var _gp_items := {}
const GRANDPA_ITEMS := [
	["gp_talk", "Поговорити", Color(0.45, 0.6, 0.75)],
	["gp_plow", "Зорати поле на тракторі", Color(0.8, 0.3, 0.22)],
	["gp_tractor", "Керувати трактором і плугом самому", Color(0.7, 0.25, 0.2)],
	["gp_horse", "Запрягти коня з возом", Color(0.6, 0.42, 0.25)],
	["gp_orchard", "Зібрати фрукти в садку", Color(0.85, 0.5, 0.2)],
	["gp_forest", "Піти в ліс по гриби та ягоди", Color(0.35, 0.55, 0.3)],
	["gp_in", "Іти в хату почитати", Color(0.6, 0.45, 0.35)],
	["gp_out", "Вийти на подвір'я", Color(0.55, 0.6, 0.35)],
	["gp_bed", "Лягти спати", Color(0.45, 0.4, 0.7)],
]


func show_grandpa_menu(at_home: bool, busy_outside: bool) -> void:
	_gp_items["gp_in"].visible = not at_home
	_gp_items["gp_out"].visible = at_home
	for k in ["gp_plow", "gp_orchard", "gp_forest", "gp_tractor", "gp_horse"]:
		_gp_items[k].visible = not busy_outside
	move_child(grandpa_menu, get_child_count() - 1)
	grandpa_menu.visible = true
	grandpa_menu.modulate.a = 0.0
	create_tween().tween_property(grandpa_menu, "modulate:a", 1.0, 0.2)


var kid_menu: Control
var _kid_items := {}
const KID_ITEMS := [
	["kid_water", "Принести води", Color(0.3, 0.62, 0.8)],
	["kid_play", "Погратися з Бімом", Color(0.9, 0.5, 0.3)],
	["kid_field", "Подивитися на соняшники", Color(0.9, 0.7, 0.2)],
	["kid_talk", "Поговорити", Color(0.45, 0.6, 0.75)],
]

var girl_menu: Control
var _girl_items := {}
const GIRL_ITEMS := [
	["nk_basket_take", "Взяти кошик", Color(0.72, 0.52, 0.28)],
	["nk_basket_put", "Поставити кошик", Color(0.6, 0.45, 0.3)],
	["nk_eat", "З'їсти", Color(0.85, 0.5, 0.2)],
	["nk_put", "Покласти з рук", Color(0.55, 0.5, 0.45)],
	["nk_forest", "У грибний ліс", Color(0.35, 0.55, 0.3)],
	["nk_horse", "Покликати коня", Color(0.55, 0.38, 0.22)],
	["nk_jump", "Пострибати", Color(0.85, 0.3, 0.4)],
	["nk_beep", "Покликати Beep", Color(0.3, 0.72, 0.7)],
]


var granny_menu: Control
var _granny_items := {}
const GRANNY_ITEMS := [
	["gr_talk", "Поговорити", Color(0.45, 0.6, 0.75)],
	["gr_milk", "Подоїти корову", Color(0.55, 0.62, 0.7)],
	["gr_hens", "Нагодувати курей", Color(0.85, 0.65, 0.25)],
	["gr_garden", "Прополоти город", Color(0.35, 0.6, 0.3)],
	["gr_borscht", "Зварити борщ", Color(0.75, 0.25, 0.3)],
	["gr_pies", "Спекти пиріжки", Color(0.85, 0.5, 0.2)],
]


func show_granny_menu(night: bool, milking: bool) -> void:
	## Меню бабусі: удень — усі справи (нова справа замінює ту, що бабуся робить зараз), уночі — лише розмова.
	for k in ["gr_milk", "gr_hens", "gr_garden", "gr_borscht", "gr_pies"]:
		_granny_items[k].visible = not night
	_granny_items["gr_milk"].text = "Подоїти корову" if not milking else "Вже доїть корову…"
	_granny_items["gr_milk"].disabled = milking
	_open_menu(granny_menu)


var tractor_menu: Control
var _tr_items := {}
const TRACTOR_ITEMS := [
	["tr_drive", "Сісти за кермо самому (дідусь — поруч)", Color(0.75, 0.25, 0.2)],
	["tr_plow", "Хай дідусь сам зоре поле", Color(0.55, 0.4, 0.25)],
]


var hitch_menu: Control
var _th_items := {}
const HITCH_ITEMS := [
	["th_plow_up", "Підняти плуг", Color(0.55, 0.4, 0.25)],
	["th_plow_down", "Опустити плуг", Color(0.45, 0.32, 0.2)],
	["th_plow_off", "Відчепити плуг", Color(0.7, 0.3, 0.22)],
	["th_plow_on", "Причепити плуг", Color(0.6, 0.42, 0.25)],
	["th_up", "Підняти кузов причепа", Color(0.3, 0.5, 0.75)],
	["th_down", "Опустити кузов причепа", Color(0.25, 0.4, 0.62)],
	["th_trl_on", "Причепити причіп", Color(0.3, 0.55, 0.45)],
	["th_trl_off", "Відчепити причіп", Color(0.55, 0.45, 0.3)],
]


func show_hitch_menu(flags: Dictionary) -> void:
	for k in flags:
		if _th_items.has(k):
			(_th_items[k] as Control).visible = flags[k]
	_open_menu(hitch_menu)


func show_tractor_menu() -> void:
	_open_menu(tractor_menu)


func _open_menu(m: Control) -> void:
	move_child(m, get_child_count() - 1)
	m.visible = true
	m.modulate.a = 0.0
	create_tween().tween_property(m, "modulate:a", 1.0, 0.2)


func show_kid_menu(busy: bool) -> void:
	## Меню Тарасика: води принести, погратися з Бімом, подивитися на соняшники.
	for k in ["kid_water", "kid_play", "kid_field"]:
		_kid_items[k].visible = not busy
	_open_menu(kid_menu)


var nika_mode := false                  # граємо Нікою (джойстик видно, а кнопка «Спати» — теж)


func show_nika_menu(flags: Dictionary) -> void:
	## Меню Ніки-героїні: куди піти, на чому поїхати, покликати Beep.
	for k in _girl_items:
		(_girl_items[k] as Button).visible = bool(flags.get(k, true))
	_open_menu(girl_menu)


var choice_menu: Control = null


func show_choice(title: String, items: Array, accent := Color(0.85, 0.55, 0.2)) -> void:
	## Меню на льоту: власне меню транспорту, товар продавця…
	if choice_menu and is_instance_valid(choice_menu):
		choice_menu.queue_free()
	var store := {}
	choice_menu = _make_menu(title, items, accent, store, 2 if items.size() > 3 else 1)
	_open_menu(choice_menu)


func show_beep_menu(in_yard: bool, night: bool, lamp_on: bool, grandpa_home := false) -> void:
	for k in _menu_items:
		var b: Button = _menu_items[k]
		b.visible = k in ["hint", "scan"] or in_yard
	_menu_items["light"].text = "Ліхтарик: " + ("вимкнути" if lamp_on else "увімкнути")
	_menu_items["herd"].visible = in_yard and Game.hour() >= 17.0
	move_child(beep_menu, get_child_count() - 1)
	beep_menu.visible = true
	beep_menu.modulate.a = 0.0
	create_tween().tween_property(beep_menu, "modulate:a", 1.0, 0.2)


# ------------------------------------------------------------------ підказка
func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_panel.offset_top = 112
	toast_panel.add_theme_stylebox_override("panel", _box(Color(0.25, 0.18, 0.4, 0.92), 22))
	toast_label = Label.new()
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	toast_label.add_theme_font_size_override("font_size", 21)
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_panel)


func toast(text: String, secs := 2.5) -> void:
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.reset_size()
	toast_panel.position.x = (size.x - toast_panel.size.x) / 2.0
	_toast_left = secs


func _process(delta: float) -> void:
	if _big and _big.visible:
		_big_redraw -= delta
		if _big_redraw <= 0.0:
			_big_redraw = 0.3
			_big_tex.queue_redraw()
			_update_legend()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			toast_panel.visible = false


# ------------------------------------------------------------------ оновлення
func refresh() -> void:
	var s: Dictionary = Game.state
	var loc: String = s["location"]
	var pname := "Хата"
	if loc == "yard":
		pname = place_provider.call() if place_provider.is_valid() else "Подвір'я"
	place_label.text = pname + "  " + Game.clock_text() + ("  ☾" if Game.is_night() else "  ☀")
	if minimap:
		minimap.visible = loc == "yard" and not big_map_open()
	coins_label.text = "● %d" % s["coins"]
	var q := Game.current_quest()
	var qt := Game.quest_progress_text()
	if not q.is_empty() and q["where"] != "" and q["where"] != loc:
		qt += "   →  " + ("Подвір'я" if q["where"] == "yard" else "Хата")
	quest_label.text = qt
	var p: Dictionary = s["puppy"]
	var g: Dictionary = s["gecko"]
	if loc == "yard":
		status_label.text = "Бім:  ситість %d%%   радість %d%%\n%s" % [100 - int(p["hunger"]), int(p["joy"]), Game.puppy_mood()]
	else:
		status_label.text = "Лимончик:  %.1f °C  (треба 28–32)\n%s" % [g["temp"], Game.gecko_mood()]
	buttons["feed"].visible = loc == "yard"
	buttons["lamp"].visible = loc == "room"
	buttons["crickets"].visible = loc == "room"
	buttons["lamp"].text = "Лампа: увімк." if g["lamp"] else "Лампа: вимк."
	buttons["go_yard"].visible = loc != "yard"
	buttons["go_room"].visible = loc != "room"


# ------------------------------------------------------------------ мапа в кутку
const MAP_RECT := Rect2(-200, -150, 400, 400)     # x, z світу, які показує мапа (з базаром за річкою)
var _map_tex: TextureRect
var _map_dot: Control
var _map_big := false
signal map_tapped(world_pos: Vector3)


var _outer
var marker_provider: Callable          # [[підпис, позиція, колір], ...] — хто де (для великої мапи)
var seed_provider: Callable            # позиції ще не зібраних насінинок
var _big: Control
var _big_tex: TextureRect
var _big_redraw := 0.0
var _yard: Rect2
var _tex_far: Texture2D
var _tex_near: Texture2D
var _big_rect := Rect2(-55, -33, 75, 75)
var _big_toggle: Button
var _legend: VBoxContainer
const NEAR_RECT := Rect2(-55, -33, 75, 75)       # подвір'я, ангар, хата Тарасика
const NEAR_LABELS := [["Хата", Vector3(0, 0, -10.3)], ["Сарай", Vector3(-15.5, 0, -11.2)], ["Майстерня", Vector3(-16.5, 0, -2.0)],
	["Курник", Vector3(7.6, 0, -1.6)], ["Криниця", Vector3(4.95, 0, -4.1)], ["Город", Vector3(14.5, 0, -4.5)],
	["Хата Тарасика", Vector3(-14.0, 0, 15.5)], ["Ангар", Vector3(-33.0, 0, -9.5)], ["Ворота", Vector3(0, 0, 5.0)]]


func build_minimap(outer, yard: Rect2) -> void:
	_outer = outer
	## Маленька мапа: подвір'я, дорога, село, річка, ставок, поле, вітряк, ліс; точка — Beep.
	## Торкнешся мапи — Beep летить туди.
	_yard = yard
	var img := _paint_map(MAP_RECT, 512, false)
	_tex_far = ImageTexture.create_from_image(img)
	_tex_near = ImageTexture.create_from_image(_paint_map(NEAR_RECT, 512, true))
	# рамка
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.9), 18, Color(0.45, 0.25, 0.6), 3, 4))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.offset_left = -196
	panel.offset_right = -14
	panel.offset_top = 96
	panel.offset_bottom = 278
	add_child(panel)
	minimap = panel
	_map_tex = TextureRect.new()
	_map_tex.texture = _tex_far
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_map_tex.custom_minimum_size = Vector2(170, 170)
	_map_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(_map_tex)
	_map_dot = ColorRect.new()
	_map_dot.color = Color(0.2, 0.85, 0.85)
	_map_dot.size = Vector2(10, 10)
	_map_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_tex.add_child(_map_dot)
	_map_tex.gui_input.connect(func(e: InputEvent):
		var pos := Vector2(-1, -1)
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pos = e.position
		elif e is InputEventScreenTouch and e.pressed:
			pos = e.position
		if pos.x < 0:
			return
		_map_tex.accept_event()
		var au = get_node_or_null("/root/Main/Audio")
		if au:
			au.play("click", -6.0)
		open_big_map())


func open_big_map() -> void:
	## Велика мапа на весь екран: хто де (з підписами), місця, насінинки.
	## Торкнешся мапи — Beep полетить туди; «Закрити» — повернутися до гри.
	if _big == null:
		_big = Control.new()
		_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_big.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_big)
		var dim := ColorRect.new()
		dim.color = Color(0.1, 0.06, 0.18, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		dim.gui_input.connect(func(e: InputEvent):
			if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
				close_big_map())
		_big.add_child(dim)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _box(Color(1, 0.98, 0.93, 0.98), 26, Color(0.45, 0.25, 0.6), 4, 8))
		_big.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		panel.add_child(v)
		var top := HBoxContainer.new()
		var t := Label.new()
		t.text = "Мапа округи"
		t.add_theme_font_override("font", title_font)
		t.add_theme_font_size_override("font_size", 28)
		t.add_theme_color_override("font_color", Color(0.45, 0.25, 0.6))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		var hint := Label.new()
		hint.text = "торкнись — Beep полетить туди  "
		hint.add_theme_font_size_override("font_size", 17)
		hint.add_theme_color_override("font_color", Color(0.5, 0.42, 0.6))
		top.add_child(hint)
		_big_toggle = Button.new()
		_big_toggle.add_theme_font_size_override("font_size", 20)
		_big_toggle.custom_minimum_size = Vector2(190, 54)
		_big_toggle.pressed.connect(func():
			_set_big_view(_big_rect != NEAR_RECT))
		top.add_child(_big_toggle)
		var x := Button.new()
		x.text = "✕ Закрити"
		x.add_theme_font_size_override("font_size", 22)
		x.custom_minimum_size = Vector2(150, 54)
		x.pressed.connect(close_big_map)
		top.add_child(x)
		v.add_child(top)
		_big_tex = TextureRect.new()
		_big_tex.texture = _tex_near
		_big_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_big_tex.stretch_mode = TextureRect.STRETCH_SCALE
		_big_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_big_tex.mouse_filter = Control.MOUSE_FILTER_STOP
		_big_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		v.add_child(row)
		row.add_child(_big_tex)
		_legend = VBoxContainer.new()
		_legend.custom_minimum_size = Vector2(270, 0)
		_legend.add_theme_constant_override("separation", 4)
		row.add_child(_legend)
		_big_tex.draw.connect(_draw_big_marks)
		_big_tex.gui_input.connect(func(e: InputEvent):
			var pos := Vector2(-1, -1)
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				pos = e.position
			elif e is InputEventScreenTouch and e.pressed:
				pos = e.position
			if pos.x < 0:
				return
			_big_tex.accept_event()
			var sz := _big_tex.size
			var wx := _big_rect.position.x + pos.x / sz.x * _big_rect.size.x
			var wz := _big_rect.position.y + pos.y / sz.y * _big_rect.size.y
			map_tapped.emit(Vector3(wx, 0, wz))
			close_big_map())
		_big.set_meta("panel", panel)
	_set_big_view(true)
	var S := minf(size.y - 150.0, size.x - 420.0)
	_big_tex.custom_minimum_size = Vector2(S, S)
	var pnl: PanelContainer = _big.get_meta("panel")
	pnl.reset_size()
	await get_tree().process_frame
	pnl.position = (size - pnl.size) / 2.0
	_big.visible = true
	minimap.visible = false
	_big_tex.queue_redraw()
	_update_legend()


func _set_big_view(near: bool) -> void:
	_big_rect = NEAR_RECT if near else MAP_RECT
	_big_tex.texture = _tex_near if near else _tex_far
	_big_toggle.text = "Уся округа" if near else "Подвір'я зблизька"
	_big_tex.queue_redraw()


func _update_legend() -> void:
	## Список праворуч від мапи: хто де.
	if _legend == null or not marker_provider.is_valid():
		return
	var ms: Array = marker_provider.call()
	while _legend.get_child_count() < ms.size() + 1:
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_font_size_override("normal_font_size", 18)
		l.add_theme_font_override("bold_font", bold)
		l.add_theme_font_size_override("bold_font_size", 18)
		l.add_theme_color_override("default_color", Color(0.3, 0.25, 0.35))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_legend.add_child(l)
	var head: RichTextLabel = _legend.get_child(0)
	head.text = "[b]Хто де[/b]"
	for i in range(1, _legend.get_child_count()):
		var l: RichTextLabel = _legend.get_child(i)
		if i - 1 >= ms.size():
			l.visible = false
			continue
		var m: Array = ms[i - 1]
		var col: Color = m[2]
		var where: String = m[3] if m.size() > 3 else ""
		l.visible = true
		l.text = "[color=#%s]●[/color] [b]%s[/b]%s" % [col.to_html(false), m[0], ("\n    [color=#8a7a95]%s[/color]" % where) if where != "" else ""]


func close_big_map() -> void:
	if _big:
		_big.visible = false
	if minimap:
		minimap.visible = Game.state["location"] == "yard"


func big_map_open() -> bool:
	return _big != null and _big.visible


func _to_map(p: Vector3, sz: Vector2) -> Vector2:
	return Vector2((p.x - _big_rect.position.x) / _big_rect.size.x * sz.x, (p.z - _big_rect.position.y) / _big_rect.size.y * sz.y)


func _draw_big_marks() -> void:
	var sz := _big_tex.size
	var c := _big_tex
	# назви місць
	var used: Array = []
	var near := _big_rect == NEAR_RECT
	if near:
		for pl in NEAR_LABELS:
			var q := _to_map(pl[1], sz)
			var w := bold.get_string_size(pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			used.append(Rect2(q + Vector2(-w / 2.0, -10), Vector2(w, 18)))
			c.draw_string_outline(bold, q + Vector2(-w / 2.0, 5), pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(1, 1, 1, 0.8))
			c.draw_string(bold, q + Vector2(-w / 2.0, 5), pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.3, 0.25))
	elif _outer:
		for pl in _outer.places:
			if String(pl[0]) == "Подвір'я" or String(pl[0]) == "Город":
				continue
			var q := _to_map(pl[1], sz)
			if String(pl[0]) == "Річка":
				q = _to_map(Vector3(60, 0, pl[1].z), sz)
			elif String(pl[0]) == "Ліс":
				q = _to_map(Vector3(95, 0, -45), sz)
			var w := bold.get_string_size(pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			used.append(Rect2(q + Vector2(-w / 2.0, 12), Vector2(w, 20)))
			c.draw_string_outline(bold, q + Vector2(-w / 2.0, 28), pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(1, 1, 1, 0.75))
			c.draw_string(bold, q + Vector2(-w / 2.0, 28), pl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.35, 0.3, 0.25))
	# насінинки
	if seed_provider.is_valid():
		for p in seed_provider.call():
			var q := _to_map(p, sz)
			if q.x < 8 or q.y < 8 or q.x > sz.x - 8 or q.y > sz.y - 8:
				continue
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -8), q + Vector2(7, 0), q + Vector2(0, 8), q + Vector2(-7, 0)]), Color(1.0, 0.8, 0.1))
			c.draw_polyline(PackedVector2Array([q + Vector2(0, -8), q + Vector2(7, 0), q + Vector2(0, 8), q + Vector2(-7, 0), q + Vector2(0, -8)]), Color(0.55, 0.35, 0.0), 1.5)
	# хто де: кружечок і підпис; підписи, що налазять, зсуваємо вниз
	if not marker_provider.is_valid():
		return
	var ms: Array = marker_provider.call()
	for m in ms:
		var q0 := _to_map(m[1], sz)
		used.append(Rect2(q0 - Vector2(9, 9), Vector2(18, 18)))
	for m in ms:
		var q := _to_map(m[1], sz)
		if q.x < 0 or q.y < 0 or q.x > sz.x or q.y > sz.y:
			continue
		var col: Color = m[2]
		c.draw_circle(q, 9.0, Color.WHITE)
		c.draw_circle(q, 7.0, col)
		var txt: String = m[0]
		var fs := 17
		var w := bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := q + Vector2(12, 6)
		for off in [Vector2(12, 6), Vector2(-12 - w, 6), Vector2(-w / 2.0, -14), Vector2(-w / 2.0, 26), Vector2(12, 24), Vector2(-12 - w, -12), Vector2(12, -12), Vector2(-12 - w, 24)]:
			var cand: Vector2 = q + off
			var r := Rect2(cand - Vector2(0, 16), Vector2(w, 20))
			var hit := false
			for u in used:
				if (u as Rect2).intersects(r):
					hit = true
					break
			if not hit:
				at = cand
				break
			at = Vector2(-9999, 0)
		if at.x < -999:
			continue                      # місця для підпису немає — він є у списку праворуч
		used.append(Rect2(at - Vector2(0, 16), Vector2(w, 20)))
		c.draw_string_outline(bold, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.WHITE)
		c.draw_string(bold, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.darkened(0.35))


func _paint_map(R: Rect2, S: int, near: bool) -> Image:
	## Малює мапу ділянки R світу (x, z) у картинку S×S.
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.72, 0.38))
	var to_px := func(x: float, z: float) -> Vector2i:
		return Vector2i(int((x - R.position.x) / R.size.x * S), int((z - R.position.y) / R.size.y * S))
	var disc := func(x: float, z: float, r_m: float, c: Color):
		var p: Vector2i = to_px.call(x, z)
		var r := maxi(1, int(r_m / R.size.x * S))
		if p.x < -r or p.y < -r or p.x > S + r or p.y > S + r:
			return
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r:
					var q := p + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < S and q.y < S:
						img.set_pixelv(q, c)
	var line := func(a: Vector2, b: Vector2, w_m: float, c: Color):
		var n := int(a.distance_to(b) / 1.0) + 1
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			disc.call(p.x, p.y, w_m, c)
	# ліс
	var outer = _outer
	var yard: Rect2 = _yard
	var rectm := func(x0: float, z0: float, x1: float, z1: float, c: Color):
		var a: Vector2i = to_px.call(x0, z0)
		var b: Vector2i = to_px.call(x1, z1)
		for y in range(maxi(0, mini(a.y, b.y)), mini(S, maxi(a.y, b.y) + 1)):
			for x in range(maxi(0, mini(a.x, b.x)), mini(S, maxi(a.x, b.x) + 1)):
				img.set_pixel(x, y, c)
	for t in outer.trees:
		disc.call(t[0], t[1], 2.2, Color(0.3, 0.5, 0.25))
	# річка, ставок, пагорб
	line.call(Vector2(R.position.x, outer.RIVER_Z), Vector2(R.end.x, outer.RIVER_Z), outer.RIVER_W / 2.0, Color(0.3, 0.55, 0.85))
	# ставок — прямокутник із заокругленими кутами
	var pc: Vector3 = outer.POND
	var ph: Vector2 = outer.POND_HALF
	var pr: float = outer.POND_CORNER
	var pw := Color(0.3, 0.55, 0.85)
	rectm.call(pc.x - ph.x + pr, pc.z - ph.y, pc.x + ph.x - pr, pc.z + ph.y, pw)
	rectm.call(pc.x - ph.x, pc.z - ph.y + pr, pc.x + ph.x, pc.z + ph.y - pr, pw)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			disc.call(pc.x + sx * (ph.x - pr), pc.z + sz * (ph.y - pr), pr, pw)
	disc.call(outer.MILL_HILL.x, outer.MILL_HILL.z, outer.MILL_HILL_R, Color(0.48, 0.66, 0.32))
	# дороги
	var dirt := Color(0.82, 0.68, 0.48)
	line.call(Vector2(0, 5), Vector2(0, 150), 1.6, dirt)
	line.call(Vector2(0, 30), Vector2(-46, 22), 1.2, dirt)
	line.call(Vector2(-46, 22), Vector2(-72, -30), 1.2, dirt)
	line.call(Vector2(0, 36), Vector2(26, 32), 1.2, dirt)
	for fi in outer.FOREST_ROAD.size() - 1:
		line.call(outer.FOREST_ROAD[fi], outer.FOREST_ROAD[fi + 1], 1.2, dirt)
	for fi in range(2, outer.EAST_ROAD.size() - 1):
		line.call(outer.EAST_ROAD[fi], outer.EAST_ROAD[fi + 1], 1.2, dirt)
	disc.call(outer.EAST_FOREST_C.x, outer.EAST_FOREST_C.z, 4.0, dirt)
	disc.call(outer.VILLAGE.x, outer.VILLAGE.z, 9.0, dirt)
	if outer.bazaar:
		for rp in outer.bazaar.map_road_pts:
			disc.call(rp[0], rp[1], 1.4, dirt)
	# аеродром: смуга й ангар
	for ar in [[-79.0, -4.0, -7.0, 4.0, Color(0.45, 0.46, 0.48)], [-5.0, -5.8, 5.0, 5.8, Color(0.6, 0.38, 0.3)]]:
		var c0: Vector3 = outer.air_world(ar[0], ar[1])
		var c1: Vector3 = outer.air_world(ar[2], ar[3])
		rectm.call(minf(c0.x, c1.x), minf(c0.z, c1.z), maxf(c0.x, c1.x), maxf(c0.z, c1.z), ar[4])
	# подвір'я й город
	for x in range(int(yard.position.x), int(yard.end.x)):
		line.call(Vector2(x, yard.position.y), Vector2(x, yard.end.y), 0.6, Color(0.66, 0.8, 0.45))
	line.call(Vector2(yard.position.x, yard.position.y), Vector2(yard.end.x, yard.position.y), 0.6, Color(0.5, 0.35, 0.2))
	line.call(Vector2(yard.position.x, yard.end.y), Vector2(yard.end.x, yard.end.y), 0.6, Color(0.5, 0.35, 0.2))
	line.call(Vector2(yard.position.x, yard.position.y), Vector2(yard.position.x, yard.end.y), 0.6, Color(0.5, 0.35, 0.2))
	line.call(Vector2(yard.end.x, yard.position.y), Vector2(yard.end.x, yard.end.y), 0.6, Color(0.5, 0.35, 0.2))
	for x in range(11, 18):
		line.call(Vector2(x, -9.5), Vector2(x, 0.5), 0.5, Color(0.95, 0.8, 0.2))
	# хати
	disc.call(0, -10.3, 3.3, Color(0.98, 0.95, 0.85))
	for h in outer.houses:
		disc.call(h[0], h[1], 3.0, Color(0.85, 0.45, 0.35))
	disc.call(-14, 15.5, 3.0, Color(0.85, 0.45, 0.35))
	if near:
		# будівлі подвір'я
		rectm.call(-3.0, -11.8, 3.0, -7.4, Color(0.95, 0.78, 0.35))          # хата (стріха)
		rectm.call(-19.1, -14.0, -11.9, -8.4, Color(0.75, 0.3, 0.25))        # сарай
		rectm.call(-19.0, -4.2, -14.0, 0.2, Color(0.6, 0.42, 0.28))          # майстерня
		rectm.call(6.8, -2.6, 8.4, -0.6, Color(0.85, 0.6, 0.3))              # курник
		disc.call(4.95, -4.1, 0.9, Color(0.6, 0.6, 0.65))                    # криниця
		disc.call(3.8, -8.4, 1.2, Color(0.95, 0.85, 0.4))                    # майданчик дрона
		rectm.call(-16.5, 13.3, -11.5, 17.7, Color(0.85, 0.45, 0.35))        # хата Тарасика
	return img


func update_map_dot(p: Vector3) -> void:
	if _map_tex == null:
		return
	var sz := _map_tex.size
	var u := (p.x - MAP_RECT.position.x) / MAP_RECT.size.x
	var v := (p.z - MAP_RECT.position.y) / MAP_RECT.size.y
	_map_dot.position = Vector2(u * sz.x, v * sz.y) - _map_dot.size / 2.0


var _overview_btn: Button


func show_overview_button(on: bool) -> void:
	## Кнопка «↩ Огляд» — повернути камеру до загального вигляду.
	if _overview_btn == null:
		_overview_btn = Button.new()
		_overview_btn.text = "Огляд"
		_overview_btn.add_theme_font_size_override("font_size", 24)
		var col := Color(0.4, 0.4, 0.75)
		_overview_btn.add_theme_stylebox_override("normal", _box(col))
		_overview_btn.add_theme_stylebox_override("hover", _box(col.lightened(0.08)))
		_overview_btn.add_theme_stylebox_override("pressed", _box(col.darkened(0.1)))
		_overview_btn.add_theme_color_override("font_color", Color.WHITE)
		_overview_btn.anchor_left = 0.5
		_overview_btn.anchor_right = 0.5
		_overview_btn.anchor_top = 1.0
		_overview_btn.anchor_bottom = 1.0
		_overview_btn.offset_left = -90
		_overview_btn.offset_right = 90
		_overview_btn.offset_top = -86
		_overview_btn.offset_bottom = -24
		_overview_btn.pressed.connect(func():
			var au = get_node_or_null("/root/Main/Audio")
			if au:
				au.play("click", -6.0)
			action.emit("overview"))
		add_child(_overview_btn)
		move_child(_overview_btn, bottom_bar.get_index() + 1)
	_overview_btn.visible = on


func show_flight(on: bool) -> void:
	## Політ на драконі: ховаємо звичайні кнопки, показуємо джойстик.
	flight.reset()
	flight.visible = on
	bottom_bar.visible = not on
	if on and _overview_btn:
		_overview_btn.visible = false
	if on:
		move_child(flight, get_child_count() - 1)


var _seed_dots: Array = []


func set_seed_dots(spots: Array, visible_flags: Array) -> void:
	## Золоті цятки на мапі — де ще лишилися насінинки.
	if _map_tex == null:
		return
	if _seed_dots.is_empty():
		for i in spots.size():
			var d := ColorRect.new()
			d.color = Color(1.0, 0.8, 0.1)
			d.size = Vector2(8, 8)
			d.rotation = PI / 4.0
			d.pivot_offset = Vector2(4, 4)
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_map_tex.add_child(d)
			_seed_dots.append(d)
	var sz := _map_tex.size
	for i in spots.size():
		var p: Vector3 = spots[i]
		var u := (p.x - MAP_RECT.position.x) / MAP_RECT.size.x
		var v := (p.z - MAP_RECT.position.y) / MAP_RECT.size.y
		_seed_dots[i].position = Vector2(u * sz.x, v * sz.y) - Vector2(4, 4)
		_seed_dots[i].visible = visible_flags[i]
	_map_tex.move_child(_map_dot, _map_tex.get_child_count() - 1)



# ------------------------------------------------------------------ «На добраніч» / «Спати до ранку»
var _sleep_btn: Button
var _fade: ColorRect


func update_sleep_button(mode: String) -> void:
	## mode: "" — сховати, "goodnight" — «На добраніч», "sleep" — «Спати до ранку».
	if _sleep_btn == null:
		_sleep_btn = Button.new()
		_sleep_btn.add_theme_font_size_override("font_size", 24)
		var col := Color(0.32, 0.3, 0.62)
		_sleep_btn.add_theme_stylebox_override("normal", _box(col))
		_sleep_btn.add_theme_stylebox_override("hover", _box(col.lightened(0.08)))
		_sleep_btn.add_theme_stylebox_override("pressed", _box(col.darkened(0.1)))
		_sleep_btn.add_theme_color_override("font_color", Color.WHITE)
		_sleep_btn.anchor_left = 0.5
		_sleep_btn.anchor_right = 0.5
		_sleep_btn.anchor_top = 1.0
		_sleep_btn.anchor_bottom = 1.0
		_sleep_btn.offset_left = -130
		_sleep_btn.offset_right = 130
		_sleep_btn.offset_top = -160
		_sleep_btn.offset_bottom = -100
		_sleep_btn.pressed.connect(func():
			var au = get_node_or_null("/root/Main/Audio")
			if au:
				au.play("click", -6.0)
			action.emit(String(_sleep_btn.get_meta("mode", ""))))
		add_child(_sleep_btn)
	_sleep_btn.visible = mode != "" and not big_map_open() and (nika_mode or not (flight and flight.visible))
	_sleep_btn.set_meta("mode", mode)
	_sleep_btn.text = "☾  На добраніч" if mode == "goodnight" else "☾  Спати до ранку"


func fade(to_black: bool, secs := 1.0) -> void:
	if _fade == null:
		_fade = ColorRect.new()
		_fade.color = Color(0.03, 0.02, 0.08, 0.0)
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fade)
	move_child(_fade, get_child_count() - 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if to_black else Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0 if to_black else 0.0, secs)
	await tw.finished
