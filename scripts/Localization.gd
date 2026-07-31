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
		"CHAR_NAME_SCOUT": "Бегун",
		"CHAR_NAME_ENGINEER": "Инженер",
		"CHAR_NAME_PYRO": "Пиро",
		"CHAR_NAME_BOMB_KICKER": "Хокеист",

		"CHAR_DESC_BOMB_MASTER": "Разбирается в бомбах",
		"CHAR_DESC_SCOUT": "Двойное нажатие в сторону ящика или бомбы - перепрыгивает через неё",
		"CHAR_DESC_ENGINEER": "%s: Поставить стену, через которую проходит только сам",
		"CHAR_DESC_PYRO": "Бомбы взрываются кругом и немного пробивают ящики",
		"CHAR_DESC_BOMB_KICKER": "Толкает бомбы движением — свои и чужие",

		"MAP_SIZE_TINY": "Крошечная",
		"MAP_SIZE_SMALL": "Маленькая",
		"MAP_SIZE_MEDIUM": "Средняя",
		"MAP_SIZE_LARGE": "Большая",
		"MAP_SIZE_HUGE": "Огромная",

		"READY": "ГОТОВ",
		"BOT_BADGE": "ИИ",
		"OFFLINE_BADGE": "ОТКЛЮЧЕН",
		"DISCONNECTED_HINT": "Отключено…",
		"CYCLE_HINT": "%s — сменить",

		"LOBBY_LEGEND": "%s — присоединиться, ещё раз — готов\n%s или %s — сменить персонажа   •   ↑/↓ — размер карты\nB — добавить бота   •   N — убрать бота",
		"MAIN_HOTKEY_HINT": "Движение — WASD / стик   •   Бомба — Space / A   •   Способность — E / B\nПауза — Esc / Start",
		"PAUSE_HOTKEY_HINT": "A/D или ◄► / стик — навигация   •   Space/A — выбрать   •   Esc/Start — закрыть",

		"MATCH_OVER": "Матч завершён!",
		"MATCH_WINNER": "Победитель матча: Player %d",
		"ROUND_DRAW": "Раунд %d/%d: ничья",
		"ROUND_WINNER": "Раунд %d/%d: победил Player %d",
		"SCORE_HEADER": "Счёт:",
		"SCORE_LINE": "Player %d — %d",
		"NEXT_ROUND_IN": "Следующий раунд через: %d",

		"SETTINGS_TITLE": "Настройки",
		"SETTINGS_LANGUAGE": "Язык",
		"SETTINGS_SOUND": "Звук",
		"SETTINGS_OFF": "Выкл",
		"SETTINGS_HINT": "W/S или ▲▼ — раздел   •   A/D или ◄► — изменить   •   Space/Esc — назад",

		"MENU_PLAY": "Играть",
		"MENU_QUIT": "Выход",
		"MAIN_MENU_HOTKEY_HINT": "W/S или ↑/↓ / стик — навигация   •   Space/A — выбрать",
	},
	"en": {
		"CHAR_NAME_BOMB_MASTER": "Sapper",
		"CHAR_NAME_SCOUT": "Runner",
		"CHAR_NAME_ENGINEER": "Engineer",
		"CHAR_NAME_PYRO": "Pyro",
		"CHAR_NAME_BOMB_KICKER": "Hockey Player",

		"CHAR_DESC_BOMB_MASTER": "Knows their way around bombs",
		"CHAR_DESC_SCOUT": "Double-tap a direction toward a crate or bomb to hop over it",
		"CHAR_DESC_ENGINEER": "%s: Place a wall only they can pass through",
		"CHAR_DESC_PYRO": "Bombs explode in a circle and punch through crates a bit",
		"CHAR_DESC_BOMB_KICKER": "Pushes bombs by walking into them — theirs or anyone's",

		"MAP_SIZE_TINY": "Tiny",
		"MAP_SIZE_SMALL": "Small",
		"MAP_SIZE_MEDIUM": "Medium",
		"MAP_SIZE_LARGE": "Large",
		"MAP_SIZE_HUGE": "Huge",

		"READY": "READY",
		"BOT_BADGE": "BOT",
		"OFFLINE_BADGE": "OFFLINE",
		"DISCONNECTED_HINT": "Disconnected…",
		"CYCLE_HINT": "%s — change",

		"LOBBY_LEGEND": "%s — join, press again — ready\n%s or %s — change character   •   Up/Down — map size\nB — add a bot   •   N — remove a bot",
		"MAIN_HOTKEY_HINT": "Move — WASD / stick   •   Bomb — Space / A   •   Ability — E / B\nPause — Esc / Start",
		"PAUSE_HOTKEY_HINT": "A/D or ◄► / stick — navigate   •   Space/A — select   •   Esc/Start — close",

		"MATCH_OVER": "Match over!",
		"MATCH_WINNER": "Match winner: Player %d",
		"ROUND_DRAW": "Round %d/%d: draw",
		"ROUND_WINNER": "Round %d/%d: Player %d wins",
		"SCORE_HEADER": "Score:",
		"SCORE_LINE": "Player %d — %d",
		"NEXT_ROUND_IN": "Next round in: %d",

		"SETTINGS_TITLE": "Settings",
		"SETTINGS_LANGUAGE": "Language",
		"SETTINGS_SOUND": "Sound",
		"SETTINGS_OFF": "Off",
		"SETTINGS_HINT": "W/S or ▲▼ — section   •   A/D or ◄► — adjust   •   Space/Esc — back",

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
	if cfg.load(SETTINGS_PATH) == OK:
		lang = cfg.get_value("settings", "language", DEFAULT_LANG)
	else:
		lang = DEFAULT_LANG

func _save_language() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # preserve sibling keys (e.g. Sfx's volume) already in the file
	cfg.set_value("settings", "language", lang)
	cfg.save(SETTINGS_PATH)
