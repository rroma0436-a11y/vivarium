extends Node
## Стан гри «Диво-Світ»: потреби тварин, тераріум, квести дідуся й бабусі, монетки. Зберігається в user://save.json.

signal changed                                   # щось у стані змінилося (оновити інтерфейс)
signal quest_started(quest: Dictionary)          # новий квест — показати діалог
signal quest_done(quest: Dictionary)             # квест виконано
signal said(who: String, text: String)           # репліка (Beep чи тварина) — показати бульбашку

const SAVE_PATH := "user://save.json"
const VERSION := "0.5"
const DAY_SECONDS := 2160.0         # одна ігрова доба = 36 хвилин
const START_HOUR := 8.0

# Нічні справи: після денних завдань дня d — ніч d. Далі ночі повторюються по колу.
const NIGHTS := [
	[
		{"id": "n_blanket", "giver": "Beep", "goal": "blanket", "count": 1, "reward": 5,
		 "text": "Дідусь ліг спати. Уночі прохолодно — зайди в хату, торкнись дідуся, і я тихенько вкрию його ковдрою. А потім — «Спати до ранку».",
		 "short": "Вкрий дідуся ковдрою", "done": "Дідусь усміхається уві сні."},
	],
	[
		{"id": "n_fireflies", "giver": "Beep", "goal": "firefly", "count": 5, "reward": 10,
		 "text": "Подивись — над городом світяться світлячки! Торкнись світлячка, я підлечу й зберу його в баночку. Треба п'ять — буде нічник.",
		 "short": "Збери світлячків", "done": "Баночка-нічник світиться в хаті!"},
	],
	[
		{"id": "n_star", "giver": "Beep", "goal": "star", "count": 1, "reward": 15,
		 "text": "Ой, над селом падає зірка! Летімо на літаку й зловимо її! Торкнись мене → «Летимо на літаку».",
		 "short": "Злови падаючу зірку на літаку", "done": "Зірочка тепер світить над хатою!"},
	],
]
const NIGHTS_AGAIN := [
	[{"id": "r_blanket", "giver": "Beep", "goal": "blanket", "count": 1, "reward": 5,
	  "text": "Дідусь спить — вкрий його ковдрою.", "short": "Вкрий дідуся ковдрою", "done": "Добраніч, дідусю!"}],
	[{"id": "r_fireflies", "giver": "Beep", "goal": "firefly", "count": 5, "reward": 5,
	  "text": "Світлячки знову прилетіли! Збери п'ять.", "short": "Збери світлячків", "done": "Гарно світять!"}],
]
const EVENING_HOLD := 18.5           # поки денні справи не зроблено, сонце не сідає нижче

# Тераріум леопардового гекона: тепла зона 28–32 °C
const GECKO_MIN := 28.0
const GECKO_MAX := 32.0
const ROOM_TEMP := 22.0
const LAMP_TEMP := 35.0

const QUESTS := [
	{"id": "meet_beep", "giver": "Дідусь Петро", "goal": "tap_beep", "count": 1, "reward": 5,
	 "where": "yard",
	 "text": "Привіт, онучку! Ласкаво просимо на нашу ферму. Я — дідусь Петро. А це наш робот-помічник Beep. Торкнись його — привітайся!",
	 "short": "Торкнись робота Beep",
	 "done": "Біп-буп! Радий знайомству! Я допомагатиму тобі на фермі."},
	{"id": "feed_puppy", "giver": "Дідусь Петро", "goal": "puppy_fed", "count": 1, "reward": 10,
	 "where": "yard",
	 "text": "Наше цуценя Бім уже з самого ранку зголодніло. Насип йому корму в мисочку — натисни «Корм».",
	 "short": "Нагодуй цуценя Біма",
	 "done": "Бім наївся й аж хвостиком метляє!"},
	{"id": "pet_puppy", "giver": "Дідусь Петро", "goal": "puppy_petted", "count": 3, "reward": 10,
	 "where": "yard",
	 "text": "Цуценятам потрібна ласка. Погладь Біма — торкнись його тричі.",
	 "short": "Погладь Біма",
	 "done": "Бачиш, як він радіє? Тварини все відчувають."},
	{"id": "warm_gecko", "giver": "Дідусь Петро", "goal": "gecko_warm", "count": 1, "reward": 15,
	 "where": "room",
	 "text": "У хаті живе леопардовий гекон Лимончик — торкнись хати, щоб зайти. Він любить тепло: увімкни лампу в тераріумі й зігрій його до 28–32 градусів. Тільки не перегрій!",
	 "short": "Зігрій тераріум до 28–32 °C",
	 "done": "Тепло й затишно — Лимончик вибрався погрітися."},
	{"id": "feed_gecko", "giver": "Дідусь Петро", "goal": "gecko_fed", "count": 1, "reward": 15,
	 "where": "room",
	 "text": "Тепер можна й пообідати. Нагодуй Лимончика цвіркунами. Гекони їдять, лише коли їм тепло.",
	 "short": "Нагодуй гекона цвіркунами",
	 "done": "Ням! Лимончик спіймав аж трьох цвіркунів."},
	{"id": "day_end", "giver": "Дідусь Петро", "goal": "morning", "count": 1, "reward": 20,
	 "where": "",
	 "text": "Молодець! Перший день на фермі вдався: усі ситі й задоволені. Відпочинь — а завтра зранку на тебе чекають нові справи.",
	 "short": "Перший день завершено! Чекаємо ранку",
	 "done": "Доброго ранку! Півень уже прокукурікав."},
	# ---------------- день другий
	{"id": "hens_feed", "giver": "Дідусь Петро", "goal": "hens_fed", "count": 1, "reward": 10,
	 "where": "yard",
	 "text": "Кури зранку голодні. Натисни «Beep» і вибери «Дрон: нагодуй курей» — дрон насипле їм зерна.",
	 "short": "Нагодуй курей (через дрон)",
	 "done": "Ко-ко-ко! Кури клюють зерно."},
	{"id": "kid_water", "giver": "Тарасик", "goal": "water_carried", "count": 2, "reward": 15,
	 "where": "yard",
	 "text": "Привіт! Я Тарасик. Допоможеш? Торкнись мене й вибери «Принести води» — я наберу води з криниці й наллю Бімові та курочкам.",
	 "short": "Допоможи Тарасикові напоїти тварин",
	 "done": "Дякую! Тепер усі напоєні."},
	{"id": "field_water", "giver": "Дідусь Петро", "goal": "field_watered", "count": 1, "reward": 15,
	 "where": "yard",
	 "text": "За тином наш город із соняшниками. Сонце пече — попроси дрон полити город: «Beep» → «Дрон: полий город».",
	 "short": "Полий соняшники за тином",
	 "done": "Соняшники напилися й тягнуться до сонця!"},
	{"id": "ball", "giver": "Beep", "goal": "ball_fetched", "count": 3, "reward": 10,
	 "where": "yard",
	 "text": "Біп! Бім нудьгує. Натисни «Beep» → «М'ячик для Біма» — я кину, а він принесе. Тричі!",
	 "short": "Пограй з Бімом у м'ячик",
	 "done": "Гав-гав! Бім щасливий і трішки втомлений."},
	{"id": "eggs", "giver": "Гвинтик", "goal": "eggs_collected", "count": 1, "reward": 10,
	 "where": "yard",
	 "text": "Біп-біп! Я Гвинтик. Кури знесли яйця! Торкнись мене — я зберу їх і віднесу дідусеві.",
	 "short": "Зберіть яйця з Гвинтиком",
	 "done": "Кошик повний! Дідусь спече млинці."},
	{"id": "hens_home", "giver": "Дідусь Петро", "goal": "hens_home", "count": 1, "reward": 15,
	 "where": "yard",
	 "text": "Як смеркне, кури мають бути в курнику. Коли настане вечір — торкнись Біма, і він їх зажене.",
	 "short": "Увечері — Бім заганяє курей",
	 "done": "Усі кури вдома, а Бім пішов у будку. На добраніч!"},
	{"id": "day2_end", "giver": "Дідусь Петро", "goal": "morning", "count": 1, "reward": 25,
	 "where": "",
	 "text": "Оце так день! Тепер ти справжній господар ферми. Далі — роби що хочеш: грайся з Бімом, доглядай тварин і город.",
	 "short": "Другий день завершено!",
	 "done": "Новий день на фермі!"},
	# ---------------- день третій: Ніка й жовтий літак
	{"id": "meet_girl", "giver": "Дідусь Петро", "goal": "girl_met", "count": 1, "reward": 10,
	 "where": "yard",
	 "text": "Онучку, у селі, у білій хатці біля площі, живе дівчинка Ніка в червоному каптурику. Зранку вона ходить на базар, а по обіді — до мене в гості. Знайди її (на великій мапі видно, хто де) і привітайся — торкнись її.",
	 "short": "Познайомся з Нікою",
	 "done": "Привіт-привіт! Як добре, що ти прийшов!"},
	{"id": "plane_ride", "giver": "Ніка", "goal": "plane_flight", "count": 1, "reward": 15,
	 "where": "yard",
	 "text": "А ти знаєш, що за фермою є аеродром? В ангарі стоїть жовтий літак, і Beep уміє ним керувати! Торкнись Beep → «Летимо на літаку». У небі: джойстик — повороти й швидкість, ▲▼ — висота. «Сісти» — посадка просто тут, «В ангар» — літак сам повернеться.",
	 "short": "Політай на літаку",
	 "done": "Ух! Оце так політ! Пропелер аж дзижчить."},
	{"id": "seeds", "giver": "Ніка", "goal": "seed", "count": 10, "reward": 30,
	 "where": "yard",
	 "text": "Дивись! У небі над округою світяться золоті насінинки чарівного соняшника — аж десять! На мапі вони жовтими ромбиками. Полетіть із Beep на літаку й зберіть їх — треба пролетіти просто крізь насінинку.",
	 "short": "Збери золоті насінинки",
	 "done": "Усі десять! Дідусь посадив їх біля хати — і виріс чарівний соняшник!"},
	{"id": "day3_end", "giver": "Дідусь Петро", "goal": "morning", "count": 1, "reward": 25,
	 "where": "",
	 "text": "Оце пригода! Чарівний соняшник світиться біля хати. Відпочинь, а завтра — нові справи на фермі.",
	 "short": "Третій день завершено!",
	 "done": "Доброго ранку! Чарівний соняшник сяє на сонці."},
	# ---------------- день четвертий: бабуся Галя
	{"id": "meet_granny", "giver": "Бабуся Галя", "goal": "granny_met", "count": 1, "reward": 10,
	 "where": "yard",
	 "text": "Здрастуй, онучку! Я — бабуся Галя, дідусева дружина. На мені й корівки, і курочки, і город, і борщ. Торкнись мене — побачиш, у чому можна мені допомогти.",
	 "short": "Торкнись бабусі Галі",
	 "done": "Ой, яке ж ти гарне онуча! Ходи, обійму."},
	{"id": "granny_milk", "giver": "Бабуся Галя", "goal": "milked", "count": 1, "reward": 20,
	 "where": "yard",
	 "text": "Корівки вже на пасовиську й чекають. Торкнись мене й вибери «Піду подою корову» — візьму дійницю й стільчик і піду доїти. Подивись, як дійниця наповнюється молоком!",
	 "short": "Подоїть із бабусею корову",
	 "done": "Повна дійниця парного молока!"},
	{"id": "granny_garden", "giver": "Бабуся Галя", "goal": "weeded", "count": 1, "reward": 10,
	 "where": "yard",
	 "text": "На городі знову бур'яни повилазили. Торкнись мене → «Прополоти город».",
	 "short": "Прополіть із бабусею город",
	 "done": "Гарбузи дякують — тепер їм просторо!"},
	{"id": "granny_pies", "giver": "Бабуся Галя", "goal": "pies", "count": 1, "reward": 15,
	 "where": "yard",
	 "text": "А тепер — найсмачніше! Торкнись мене → «Приготую їсти». Я винесу тацю на стіл, а ти торкайся пиріжків — Beep пригоститься.",
	 "short": "Спечіть із бабусею пиріжки",
	 "done": "Пиріжки з вишнями — гарячі й рум'яні!"},
	{"id": "day4_end", "giver": "Бабуся Галя", "goal": "morning", "count": 1, "reward": 25,
	 "where": "",
	 "text": "Дякую, онучку, за поміч! Тепер ти знаєш усі мої справи — проси мене, коли захочеш: і корову подою, і борщу зварю. А зараз — відпочивай.",
	 "short": "Четвертий день завершено!",
	 "done": "Доброго ранку! Бабуся вже несе дійницю."},
]

var state: Dictionary = {}
var _save_left := 0.0


func _ready() -> void:
	load_game()
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	add_child(t)
	t.timeout.connect(_tick.bind(0.5))
	get_tree().node_added.connect(_on_node_added)


const LIGHT_NEAR := 22.0             # м: ліхтарі (хати, Beep, світлячки…) світять лише поблизу, далі — вимкнені
const LIGHT_FADE := 6.0


func _on_node_added(n: Node) -> void:
	## Кожен ліхтар у Compatibility — ще один прохід малювання: далекі вимикаються самі (рушій їх не рахує).
	if n is OmniLight3D or n is SpotLight3D:
		var l := n as Light3D
		if not l.distance_fade_enabled:
			l.distance_fade_enabled = true
			l.distance_fade_begin = LIGHT_NEAR
			l.distance_fade_length = LIGHT_FADE
			l.distance_fade_shadow = LIGHT_NEAR


func default_state() -> Dictionary:
	return {
		"version": VERSION, "day": 1, "time": START_HOUR, "coins": 0, "quest": 0, "progress": 0, "location": "yard",
		"puppy": {"hunger": 65.0, "joy": 55.0, "bowl": 0.0},
		"gecko": {"temp": 23.0, "lamp": false, "hunger": 70.0},
		"water_bowl": 0.0, "trough": 0.0, "hens_fed": 0.0, "eggs": 0, "milk": 0,
		"field": {"water": 30.0, "growth": 0.45},
		"seeds": [],
		"night": {},
		"quest_shown": -1,
	}


# ------------------------------------------------------------------ збереження
func load_game() -> void:
	state = default_state()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			_merge(state, data)


func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if dst.has(k) and typeof(dst[k]) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state, "\t"))


func reset_game() -> void:
	state = default_state()
	save_game()
	changed.emit()
	start_quest()


# ------------------------------------------------------------------ потреби й тераріум
func _tick(dt: float) -> void:
	# час доби (поки денні справи не зроблено — вечір «чекає»)
	var t0 := float(state["time"])
	state["time"] = t0 + dt * 24.0 / DAY_SECONDS
	if not day_done() and t0 < EVENING_HOLD and float(state["time"]) >= EVENING_HOLD and t0 > 6.0:
		state["time"] = EVENING_HOLD
	if state["time"] >= 24.0:
		state["time"] -= 24.0
		state["day"] = int(state["day"]) + 1
	_night_tick()
	# ранок: квести «чекаємо ранку» завершуються
	var cq := current_quest()
	if not cq.is_empty() and cq["goal"] == "morning" and int(state["day"]) >= _quest_day() + 1 and hour() >= 6.5 and hour() < 12.0:
		emit_event("morning")
	# вода в мисці й кориті потроху випаровується, город сохне й росте, коли є вода
	state["water_bowl"] = maxf(0.0, float(state["water_bowl"]) - dt * 0.05)
	state["trough"] = maxf(0.0, float(state["trough"]) - dt * 0.05)
	state["hens_fed"] = maxf(0.0, float(state["hens_fed"]) - dt * 0.25)
	var f: Dictionary = state["field"]
	f["water"] = maxf(0.0, float(f["water"]) - dt * 0.04)
	if float(f["water"]) > 20.0:
		f["growth"] = minf(1.0, float(f["growth"]) + dt * 0.0006)
	var p: Dictionary = state["puppy"]
	var g: Dictionary = state["gecko"]
	# цуценя потроху голодніє й сумує без уваги — повільніше, ніж раніше (за 2–3 хв ситість падала до 0%),
	# і не нижче 10%: Бім голодний чи сумний, але не «нуль»
	p["hunger"] = clampf(p["hunger"] + dt * 0.1, 0.0, 90.0)
	p["joy"] = clampf(p["joy"] - dt * 0.035, 10.0, 100.0)
	# температура тераріуму тягнеться до лампи або до кімнатної
	var target := LAMP_TEMP if g["lamp"] else ROOM_TEMP
	var was_warm := gecko_warm()
	g["temp"] = g["temp"] + (target - g["temp"]) * (1.0 - exp(-dt * 0.035))
	g["hunger"] = clampf(g["hunger"] + dt * 0.08, 0.0, 100.0)
	if gecko_warm() and not was_warm:
		emit_event("gecko_warm")
	_save_left -= dt
	if _save_left <= 0.0:
		_save_left = 5.0
		save_game()
	changed.emit()


func gecko_warm() -> bool:
	var t: float = state["gecko"]["temp"]
	return t >= GECKO_MIN and t <= GECKO_MAX


func gecko_mood() -> String:
	var t: float = state["gecko"]["temp"]
	if t < GECKO_MIN - 3.0:
		return "Холодно — Лимончик сховався й дрімає"
	if t < GECKO_MIN:
		return "Прохолодно — ще трохи тепла"
	if t <= GECKO_MAX:
		return "Тепло й затишно"
	return "Гаряче! Вимкни лампу"


func puppy_mood() -> String:
	var p: Dictionary = state["puppy"]
	if p["hunger"] > 70.0:
		return "Бім голодний"
	if p["joy"] < 30.0:
		return "Бімові нудно — погладь його"
	return "Бім щасливий"


# ------------------------------------------------------------------ дії гравця
func fill_bowl() -> bool:
	if state["puppy"]["bowl"] > 0.0:
		return false
	state["puppy"]["bowl"] = 100.0
	changed.emit()
	return true


func puppy_ate() -> void:
	state["puppy"]["bowl"] = 0.0
	state["puppy"]["hunger"] = 0.0
	state["puppy"]["joy"] = minf(100.0, state["puppy"]["joy"] + 15.0)
	emit_event("puppy_fed")


func puppy_petted() -> void:
	state["puppy"]["joy"] = minf(100.0, state["puppy"]["joy"] + 12.0)
	emit_event("puppy_petted")


func toggle_lamp() -> bool:
	state["gecko"]["lamp"] = not state["gecko"]["lamp"]
	changed.emit()
	return state["gecko"]["lamp"]


func feed_gecko() -> String:
	## Повертає репліку: гекон їсть лише в теплі.
	var g: Dictionary = state["gecko"]
	if g["temp"] < GECKO_MIN:
		return "Лимончику холодно — він не хоче їсти. Спершу зігрій тераріум."
	if g["temp"] > GECKO_MAX:
		return "Занадто гаряче! Вимкни лампу, хай трохи охолоне."
	if g["hunger"] < 20.0:
		return "Лимончик ще ситий."
	g["hunger"] = 0.0
	emit_event("gecko_fed")
	return "Ням-ням! Лимончик спритно ловить цвіркунів."


# ------------------------------------------------------------------ квести
func current_quest() -> Dictionary:
	var i: int = state["quest"]
	return QUESTS[i] if i < QUESTS.size() else {}


func start_quest() -> void:
	var q := current_quest()
	if q.is_empty():
		return
	if state["quest_shown"] != state["quest"]:
		state["quest_shown"] = state["quest"]
		state["quest_day"] = int(state["day"])
		if q["goal"] == "seed":
			state["progress"] = mini(state["seeds"].size(), int(q["count"]) - 1)
		quest_started.emit(q)
	changed.emit()


func emit_event(name: String) -> void:
	_night_event(name)
	var q := current_quest()
	if q.is_empty() or q["goal"] != name:
		changed.emit()
		return
	if name == "seed":
		state["progress"] = state["seeds"].size() - 1
	state["progress"] += 1
	if state["progress"] >= q["count"]:
		complete_quest()
	else:
		changed.emit()


func _quest_day() -> int:
	## День, у який почався поточний квест «чекаємо ранку».
	return int(state.get("quest_day", int(state["day"]) - 1))


func add_coins(n: int) -> void:
	state["coins"] += n
	changed.emit()


func complete_quest() -> void:
	var q := current_quest()
	state["coins"] += int(q.get("reward", 0))
	state["quest"] += 1
	state["progress"] = 0
	save_game()
	quest_done.emit(q)
	changed.emit()


func quest_progress_text() -> String:
	var q := current_quest()
	if day_done():
		if night_active():
			var t := night_task()
			if t.is_empty():
				return "Нічні справи зроблено — «Спати до ранку»"
			var pr: int = int(state["night"].get("progress", 0))
			return "Ніч · %s" % t["short"] + (" (%d/%d)" % [pr, t["count"]] if int(t["count"]) > 1 else "")
		if q.is_empty():
			return "Вільний день — гуляй, літай, грайся!"
		return "Справи на сьогодні зроблено! Можна «На добраніч»"
	if is_night():
		return "Ніч — «%s» продовжимо зранку" % q["short"]
	if q.is_empty():
		return ""
	if q["count"] > 1:
		return "%s (%d/%d)" % [q["short"], state["progress"], q["count"]]
	return q["short"]


# ------------------------------------------------------------------ час доби
func hour() -> float:
	return float(state["time"])


func clock_text() -> String:
	var h := hour()
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


func night_amount() -> float:
	## 0 — день, 1 — глибока ніч; плавно на світанку (5–7) і смерканні (19:30–21:30).
	var h := hour()
	var morning := 1.0 - smoothstep(5.0, 7.0, h)
	var evening := smoothstep(19.5, 21.5, h)
	return clampf(maxf(morning, evening), 0.0, 1.0)


func is_night() -> bool:
	return night_amount() > 0.6



# ------------------------------------------------------------------ день і ніч (варіант Б)
signal night_started(task: Dictionary)


func day_done() -> bool:
	## Денні завдання на сьогодні виконано (лишилося «чекаємо ранку» або квестів уже немає).
	var q := current_quest()
	return q.is_empty() or q["goal"] == "morning"


func night_active() -> bool:
	return is_night() and day_done()


func night_owner_day() -> int:
	return int(state["day"]) if hour() >= 12.0 else int(state["day"]) - 1


func night_tasks(d: int) -> Array:
	if d >= 1 and d - 1 < NIGHTS.size():
		return NIGHTS[d - 1]
	return NIGHTS_AGAIN[d % NIGHTS_AGAIN.size()]


func night_task() -> Dictionary:
	var n: Dictionary = state.get("night", {})
	if int(n.get("day", -99)) != night_owner_day():
		return {}
	var ts := night_tasks(int(n["day"]))
	var i: int = int(n.get("step", 0))
	return ts[i] if i < ts.size() else {}


func night_done() -> bool:
	var n: Dictionary = state.get("night", {})
	return int(n.get("day", -99)) == night_owner_day() and night_task().is_empty()


func _night_tick() -> void:
	if not night_active():
		return
	var n: Dictionary = state.get("night", {})
	if int(n.get("day", -99)) != night_owner_day():
		state["night"] = {"day": night_owner_day(), "step": 0, "progress": 0}
		var t := night_task()
		if not t.is_empty():
			night_started.emit(t)


func _night_event(name: String) -> void:
	if not night_active():
		return
	var t := night_task()
	if t.is_empty() or t["goal"] != name:
		return
	var n: Dictionary = state["night"]
	n["progress"] = int(n.get("progress", 0)) + 1
	if int(n["progress"]) >= int(t["count"]):
		n["step"] = int(n.get("step", 0)) + 1
		n["progress"] = 0
		state["coins"] += int(t.get("reward", 0))
		save_game()
		quest_done.emit(t)
		var nt := night_task()
		if not nt.is_empty():
			night_started.emit(nt)
	changed.emit()


func sleep_to_morning() -> void:
	## «Спати до ранку»: одразу ранок наступного дня.
	if hour() >= 12.0:
		state["day"] = int(state["day"]) + 1
	state["time"] = 6.5
	state["night"] = {}
	save_game()
	changed.emit()
