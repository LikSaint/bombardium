extends Node
## Autoloaded as `Loc`. Tiny in-house i18n: a key->text table per language
## (no Godot .translation/csv import step needed) plus persistence to
## user://settings.cfg. UI scripts call Loc.t("KEY", [args]) and listen to
## `language_changed` to refresh already-visible text.

signal language_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LANG := "en"

# Language names are never translated - each is always shown in itself.
const LANG_NATIVE_NAMES := {"ru": "Русский", "en": "English"}
const LANG_FLAGS := {"ru": "🇷🇺", "en": "🇬🇧"}
const AVAILABLE_LANGS: Array[String] = ["ru", "en"]

var lang: String = DEFAULT_LANG

const STRINGS := {
	"ru": {
		"CHAR_NAME_BOMB_MASTER": "Сапёр",
		"CHAR_NAME_SCOUT": "Паркурщик",
		"CHAR_NAME_ENGINEER": "Инженер",
		"CHAR_NAME_PYRO": "Пиро",
		"CHAR_NAME_BOMB_KICKER": "Хокеист",
		"CHAR_NAME_MAGNET": "Магнетто",
		"CHAR_NAME_MINER": "Минёр",
		"CHAR_NAME_GRENADIER": "Гранатомётчик",

		"CHAR_DESC_BOMB_MASTER": "Очень длинный фитиль — можно подорвать в любой момент кнопкой (%s)",
		"CHAR_DESC_SCOUT": "Самый быстрый; двойное нажатие в сторону — перепрыгивает через ящик, бомбу или даже стену",
		"CHAR_DESC_ENGINEER": "%s: Поставить стену, через которую проходит только сам. Стен — сколько бомб",
		"CHAR_DESC_PYRO": "Взрыв бьёт ещё и по диагонали, и продавливает ящики — а с разгоном радиуса и камень",
		"CHAR_DESC_BOMB_KICKER": "Толкает бомбы движением — свои и чужие — на 2 клетки, +1 за каждый бонус скорости",
		"CHAR_DESC_MAGNET": "Его бомбы сами ползут к ближайшему сопернику — медленно, но неотвязно",
		"CHAR_DESC_MINER": "%s: Часть бомб ставит невидимыми минами — они рвутся у врага под ногами",
		"CHAR_DESC_GRENADIER": "Вместо бомб — гранатомёт. Зажми кнопку бомбы, стоя на месте, чтобы бросить дальше; бонусы бомб добавляют дальность",

		"MAP_SIZE_TINY": "Крошечная",
		"MAP_SIZE_SMALL": "Маленькая",
		"MAP_SIZE_MEDIUM": "Средняя",
		"MAP_SIZE_LARGE": "Большая",
		"MAP_SIZE_HUGE": "Огромная",

		"MAP_LAYOUT_RANDOM": "Случайно",
		"MAP_LAYOUT_CLASSIC": "Классика",
		"MAP_LAYOUT_BRIDGES": "Мосты",
		"MAP_LAYOUT_CRATER": "Кратер",
		"MAP_LAYOUT_QUARTERS": "Кварталы",
		"MAP_LAYOUT_PLAZA": "Площадь",

		"READY": "ГОТОВ",
		"BOT_BADGE": "ИИ",
		"OFFLINE_BADGE": "ОТКЛЮЧЕН",
		"DISCONNECTED_HINT": "Отключено…",
		"CYCLE_HINT": "%s — сменить",

		"LOBBY_LEGEND": "%s — присоединиться, ещё раз — готов\n%s или %s — сменить персонажа",
		"MAIN_HOTKEY_HINT": "Движение — WASD / стик   •   Бомба — Space / A   •   Способность — E / X\nПауза — Esc / Start",
		"PAUSE_HOTKEY_HINT": "A/D или ◄► / стик — навигация   •   Space/A — выбрать   •   Esc/Start — закрыть",

		"MAP_SETTINGS_TITLE": "Настройки матча",
		"ROOM_ITEM": "Комната",
		"SETTINGS_MAP_SIZE": "Размер карты",
		"SETTINGS_MAP_LAYOUT": "Карта",
		"SETTINGS_PLAYER_SLOTS": "Слоты игроков",
		"SETTINGS_BOTS": "Боты",
		"SETTINGS_RANDOM_WALLS": "Случайные стены",
		"SETTINGS_POWERUP_CHANCE": "Шанс бонусов",
		"SETTINGS_SUDDEN_DEATH": "Закрытие раунда",
		"SETTINGS_ROUNDS": "Раундов в матче",
		"SETTINGS_ON": "Вкл",
		"MAP_SETTINGS_HINT": "▲▼ — раздел   •   ◄► — изменить   •   Space/A — подтвердить/войти в комнату   •   Esc/Start — назад",
		"LOBBY_JOIN_HINT": "Чтобы подключиться, нажмите %s",
		"SLOT_READY_HINT": "%s — чтобы стать готовым",
		"MATCH_STARTING_IN": "Старт через: %d",

		"MATCH_OVER": "Матч завершён!",
		"MATCH_WINNER": "Победитель матча: Player %d",
		"ROUND_DRAW": "Раунд %d/%d: ничья",
		"ROUND_WINNER": "Раунд %d/%d: победил Player %d",
		"SCORE_HEADER": "Счёт:",
		"SCORE_LINE": "Player %d — %d",
		"NEXT_ROUND_IN": "Следующий раунд через: %d",
		"RETURNING_TO_LOBBY_IN": "Возврат в лобби через: %d",
		"MATCH_OVER_HINT": "A/D или ◄► / стик — выбор   •   Space/A — подтвердить",

		"SETTINGS_TITLE": "Настройки",
		"SETTINGS_LANGUAGE": "Язык",
		"SETTINGS_SOUND": "Звук",
		"SETTINGS_MUSIC": "Музыка",
		"SETTINGS_OFF": "Выкл",
		"SETTINGS_HINT": "W/S или ▲▼ — раздел   •   A/D или ◄► — изменить   •   Space/A или Esc/Start — назад",

		"MENU_PLAY": "Играть",
		"MENU_QUIT": "Выход",
		"MAIN_MENU_HOTKEY_HINT": "W/S или ↑/↓ / стик — навигация   •   Space/A — выбрать",
	},
	"en": {
		"CHAR_NAME_BOMB_MASTER": "Sapper",
		"CHAR_NAME_SCOUT": "Parkour Runner",
		"CHAR_NAME_ENGINEER": "Engineer",
		"CHAR_NAME_PYRO": "Pyro",
		"CHAR_NAME_BOMB_KICKER": "Hockey Player",
		"CHAR_NAME_MAGNET": "Magnetto",
		"CHAR_NAME_MINER": "Miner",
		"CHAR_NAME_GRENADIER": "Grenadier",

		"CHAR_DESC_BOMB_MASTER": "Very long fuse — set them off whenever you like with the button (%s)",
		"CHAR_DESC_SCOUT": "Fastest on their feet; double-tap a direction to hop over a crate, a bomb, or even a wall",
		"CHAR_DESC_ENGINEER": "%s: Place a wall only they can pass through. One wall per bomb",
		"CHAR_DESC_PYRO": "Blast throws extra arms on the diagonals and pushes through crates — through stone too, with enough radius",
		"CHAR_DESC_BOMB_KICKER": "Pushes bombs by walking into them — theirs or anyone's — 2 cells, +1 per speed powerup",
		"CHAR_DESC_MAGNET": "Their bombs crawl toward the nearest opponent on their own — slowly, but they don't let go",
		"CHAR_DESC_MINER": "%s: Spends some bombs as invisible mines — they go off under an opponent's feet",
		"CHAR_DESC_GRENADIER": "No bombs — a launcher instead. Hold the bomb button, standing still, to throw further; bomb powerups add reach",

		"MAP_SIZE_TINY": "Tiny",
		"MAP_SIZE_SMALL": "Small",
		"MAP_SIZE_MEDIUM": "Medium",
		"MAP_SIZE_LARGE": "Large",
		"MAP_SIZE_HUGE": "Huge",

		"MAP_LAYOUT_RANDOM": "Random",
		"MAP_LAYOUT_CLASSIC": "Classic",
		"MAP_LAYOUT_BRIDGES": "Bridges",
		"MAP_LAYOUT_CRATER": "Crater",
		"MAP_LAYOUT_QUARTERS": "Quarters",
		"MAP_LAYOUT_PLAZA": "Plaza",

		"READY": "READY",
		"BOT_BADGE": "BOT",
		"OFFLINE_BADGE": "OFFLINE",
		"DISCONNECTED_HINT": "Disconnected…",
		"CYCLE_HINT": "%s — change",

		"LOBBY_LEGEND": "%s — join, press again — ready\n%s or %s — change character",
		"MAIN_HOTKEY_HINT": "Move — WASD / stick   •   Bomb — Space / A   •   Ability — E / X\nPause — Esc / Start",
		"PAUSE_HOTKEY_HINT": "A/D or ◄► / stick — navigate   •   Space/A — select   •   Esc/Start — close",

		"MAP_SETTINGS_TITLE": "Match Settings",
		"ROOM_ITEM": "Room",
		"SETTINGS_MAP_SIZE": "Map size",
		"SETTINGS_MAP_LAYOUT": "Map",
		"SETTINGS_PLAYER_SLOTS": "Player slots",
		"SETTINGS_BOTS": "Bots",
		"SETTINGS_RANDOM_WALLS": "Random walls",
		"SETTINGS_POWERUP_CHANCE": "Powerup chance",
		"SETTINGS_SUDDEN_DEATH": "Round end",
		"SETTINGS_ROUNDS": "Rounds per match",
		"SETTINGS_ON": "On",
		"MAP_SETTINGS_HINT": "▲▼ — section   •   ◄► — change   •   Space/A — confirm / enter room   •   Esc/Start — back",
		"LOBBY_JOIN_HINT": "Press %s to join",
		"SLOT_READY_HINT": "%s — to ready up",
		"MATCH_STARTING_IN": "Starting in: %d",

		"MATCH_OVER": "Match over!",
		"MATCH_WINNER": "Match winner: Player %d",
		"ROUND_DRAW": "Round %d/%d: draw",
		"ROUND_WINNER": "Round %d/%d: Player %d wins",
		"SCORE_HEADER": "Score:",
		"SCORE_LINE": "Player %d — %d",
		"NEXT_ROUND_IN": "Next round in: %d",
		"RETURNING_TO_LOBBY_IN": "Returning to lobby in: %d",
		"MATCH_OVER_HINT": "A/D or ◄► / stick — select   •   Space/A — confirm",

		"SETTINGS_TITLE": "Settings",
		"SETTINGS_LANGUAGE": "Language",
		"SETTINGS_SOUND": "Sound",
		"SETTINGS_MUSIC": "Music",
		"SETTINGS_OFF": "Off",
		"SETTINGS_HINT": "W/S or ▲▼ — section   •   A/D or ◄► — adjust   •   Space/A or Esc/Start — back",

		"MENU_PLAY": "Play",
		"MENU_QUIT": "Quit",
		"MAIN_MENU_HOTKEY_HINT": "W/S or Up/Down / stick — navigate   •   Space/A — select",
	},
}

func _ready() -> void:
	_load_saved_language()

func t(key: String, args: Array = []) -> String:
	var table: Dictionary = STRINGS.get(lang, {})
	var text: String = table.get(key, STRINGS.get(DEFAULT_LANG, {}).get(key, key))
	if args.is_empty():
		return text
	return text % args

func set_language(new_lang: String) -> void:
	if new_lang == lang or not STRINGS.has(new_lang):
		return
	lang = new_lang
	_save_language()
	language_changed.emit()

func toggle_language() -> void:
	var idx := AVAILABLE_LANGS.find(lang)
	set_language(AVAILABLE_LANGS[(idx + 1) % AVAILABLE_LANGS.size()])

func native_name(for_lang: String = "") -> String:
	var l := for_lang if for_lang != "" else lang
	return LANG_NATIVE_NAMES.get(l, l)

func flag(for_lang: String = "") -> String:
	var l := for_lang if for_lang != "" else lang
	return LANG_FLAGS.get(l, "")

func _load_saved_language() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("settings", "language"):
		lang = cfg.get_value("settings", "language", DEFAULT_LANG)
	else:
		lang = _detect_system_language()

# No explicit choice saved yet (first launch, or a settings.cfg written only
# by Sfx before the player ever touched Language) - fall back to the OS
# locale instead of always booting in English.
func _detect_system_language() -> String:
	var system_lang := OS.get_locale_language()
	return system_lang if AVAILABLE_LANGS.has(system_lang) else DEFAULT_LANG

func _save_language() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # preserve sibling keys (e.g. Sfx's volume) already in the file
	cfg.set_value("settings", "language", lang)
	cfg.save(SETTINGS_PATH)
