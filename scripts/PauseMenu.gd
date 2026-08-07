extends CanvasLayer
## Escape (keyboard) or Start (any gamepad) opens this — and only the device
## that opened it can navigate/confirm/close it, so one player pausing mid-
## match can't be overridden by anyone else. The title shows who paused.
## Icons only: resume (play), settings (gear - language), restart match, back to main menu, quit game.
## The settings icon opens a small sub-panel (left/right cycles the UI language); confirm/toggle backs out to the main row.
## `include_restart` is off in the Lobby scene (nothing mid-match to restart there); the main-menu exit is always offered.
##
## If the controller that opened the menu disconnects while it's open, nobody
## else is allowed to touch it (by design) — so without this it would soft-
## lock the game paused forever. Instead it auto-resumes the moment that
## specific device drops.

@export var include_restart: bool = true

const MainMenuScenePath := "res://scenes/MainMenu.tscn"

var options: Array[String] = []
var selected: int = 0
var is_open: bool = false
var in_settings: bool = false

enum SettingsRow { LANGUAGE, SOUND, MUSIC }
const SETTINGS_ROW_COUNT := 3
var settings_selected: int = SettingsRow.LANGUAGE
var pausing_device = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if include_restart:
		options = ["resume", "settings", "restart", "menu", "quit"]
	else:
		options = ["resume", "settings", "menu", "quit"]
	get_node("Panel/Row/Restart").visible = include_restart
	$Title.visible = false
	visible = false
	_refresh_selection()
	_refresh_hint()
	_refresh_settings_texts()
	Loc.language_changed.connect(_refresh_hint)
	Loc.language_changed.connect(_refresh_settings_texts)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _refresh_hint() -> void:
	if not in_settings:
		$HotkeyHint.text = Loc.t("PAUSE_HOTKEY_HINT")

func _refresh_settings_texts() -> void:
	$SettingsPanel/Title.text = Loc.t("SETTINGS_TITLE")
	$SettingsPanel/LanguageRow/LanguageLabel.text = Loc.t("SETTINGS_LANGUAGE") + ":"
	$SettingsPanel/LanguageRow/LanguageValue.text = "%s %s" % [Loc.native_name(), Loc.flag()]
	$SettingsPanel/SoundRow/SoundLabel.text = Loc.t("SETTINGS_SOUND") + ":"
	$SettingsPanel/SoundRow/SoundValue.text = _volume_bbcode(Sfx.volume_percent())
	$SettingsPanel/MusicRow/MusicLabel.text = Loc.t("SETTINGS_MUSIC") + ":"
	$SettingsPanel/MusicRow/MusicValue.text = _volume_bbcode(Music.volume_percent())
	_refresh_settings_selection()
	if in_settings:
		$HotkeyHint.text = Loc.t("SETTINGS_HINT")

# Renders a volume as 5 stepped bars (empty bars = muted), matching the
# Language row's "label left, value right" table layout.
const VOLUME_GRADE_STEPS := 5
const VOLUME_BAR_FILLED := "▮"
const VOLUME_BAR_EMPTY := "▯"

func _volume_bbcode(percent: int) -> String:
	var grade := (percent + 19) / (100 / VOLUME_GRADE_STEPS)
	var bars := ""
	for i in VOLUME_GRADE_STEPS:
		if i < grade:
			bars += "[color=#ffffff]%s[/color]" % VOLUME_BAR_FILLED
		else:
			bars += "[color=#ffffff40]%s[/color]" % VOLUME_BAR_EMPTY
	if grade == 0:
		bars += "  " + Loc.t("SETTINGS_OFF")
	return bars

func _refresh_settings_selection() -> void:
	var rows: Array = [$SettingsPanel/LanguageRow, $SettingsPanel/SoundRow, $SettingsPanel/MusicRow]
	for i in rows.size():
		rows[i].modulate = Color(1, 1, 1, 1) if i == settings_selected else Color(1, 1, 1, 0.45)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	if is_open and device == pausing_device:
		_close()

func _input(event: InputEvent) -> void:
	var device = _device_of(event)
	if device == null:
		return

	if not is_open:
		if _is_toggle(event):
			Sfx.play_menu()
			_open(device)
		return

	if device != pausing_device:
		return # only the player who paused controls this menu

	if in_settings:
		if _is_toggle(event) or _is_confirm(event):
			Sfx.play_menu()
			_close_settings()
		elif _is_row_prev(event):
			settings_selected = (settings_selected - 1 + SETTINGS_ROW_COUNT) % SETTINGS_ROW_COUNT
			_refresh_settings_selection()
			Sfx.play_menu()
		elif _is_row_next(event):
			settings_selected = (settings_selected + 1) % SETTINGS_ROW_COUNT
			_refresh_settings_selection()
			Sfx.play_menu()
		elif _is_value_left(event):
			_adjust_setting(-1)
		elif _is_value_right(event):
			_adjust_setting(1)
		return

	if _is_toggle(event):
		Sfx.play_menu()
		_close()
	elif _is_prev(event):
		selected = (selected - 1 + options.size()) % options.size()
		_refresh_selection()
		Sfx.play_menu()
	elif _is_next(event):
		selected = (selected + 1) % options.size()
		_refresh_selection()
		Sfx.play_menu()
	elif _is_confirm(event):
		Sfx.play_menu()
		_activate(options[selected])

func _adjust_setting(delta: int) -> void:
	match settings_selected:
		SettingsRow.LANGUAGE:
			Loc.toggle_language() # only two languages, so either direction just flips
		SettingsRow.SOUND:
			Sfx.adjust_volume(delta)
		SettingsRow.MUSIC:
			Music.adjust_volume(delta)
	_refresh_settings_texts()
	Sfx.play_menu()

func _device_of(event: InputEvent):
	if event is InputEventKey:
		return -1
	if event is InputEventJoypadButton:
		return event.device
	return null

func _is_toggle(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		return true
	return false

func _is_prev(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_A or event.keycode == KEY_W):
		return true
	if event is InputEventJoypadButton and event.pressed and (event.button_index == JOY_BUTTON_DPAD_LEFT or event.button_index == JOY_BUTTON_DPAD_UP):
		return true
	return false

func _is_next(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_D or event.keycode == KEY_S):
		return true
	if event is InputEventJoypadButton and event.pressed and (event.button_index == JOY_BUTTON_DPAD_RIGHT or event.button_index == JOY_BUTTON_DPAD_DOWN):
		return true
	return false

func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		return true
	return Pad.is_confirm_button(event)

# Settings panel only: W/S (or dpad up/down) moves between the Language, Sound
# and Music rows; A/D (or dpad left/right) adjusts the selected row's value.
# Split out from _is_prev/_is_next above, which deliberately treat both axes
# as one "previous/next" for the single-row option list.
func _is_row_prev(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_W:
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_UP:
		return true
	return false

func _is_row_next(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_DOWN:
		return true
	return false

func _is_value_left(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_A:
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_LEFT:
		return true
	return false

func _is_value_right(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_RIGHT:
		return true
	return false

func _open(device) -> void:
	pausing_device = device
	is_open = true
	visible = true
	get_tree().paused = true
	selected = 0
	_refresh_selection()
	_refresh_title(device)

func _close() -> void:
	is_open = false
	in_settings = false
	$Panel.visible = true
	$Title.visible = true
	$SettingsPanel.visible = false
	pausing_device = null
	visible = false
	get_tree().paused = false
	_refresh_hint()

func _open_settings() -> void:
	in_settings = true
	settings_selected = SettingsRow.LANGUAGE
	$Panel.visible = false
	$Title.visible = false
	$SettingsPanel.visible = true
	_refresh_settings_texts()

func _close_settings() -> void:
	in_settings = false
	$SettingsPanel.visible = false
	$Panel.visible = true
	_refresh_title(pausing_device)
	_refresh_hint()

func _refresh_title(device) -> void:
	var slot := _find_slot_by_device(device)
	if slot.is_empty():
		$Title.visible = false
		return
	$Title.visible = true
	$Title/Portrait.set_character(slot["character_id"], Consts.PLAYER_COLORS[(slot["id"] - 1) % Consts.PLAYER_COLORS.size()])
	$Title/PlayerLabel.text = "P%d" % slot["id"]

func _find_slot_by_device(device) -> Dictionary:
	for slot in GameManager.player_slots:
		if slot["device"] == device:
			return slot
	return {}

func _refresh_selection() -> void:
	for i in options.size():
		var node: Control = get_node("Panel/Row/" + options[i].capitalize())
		node.modulate = Color(1, 1, 1, 1) if i == selected else Color(1, 1, 1, 0.45)
		node.scale = Vector2(1.15, 1.15) if i == selected else Vector2(1, 1)

func _activate(option: String) -> void:
	match option:
		"resume":
			_close()
		"settings":
			_open_settings()
		"restart":
			get_tree().paused = false
			GameManager.reset_match()
			get_tree().reload_current_scene()
		"menu":
			get_tree().paused = false
			GameManager.leave_to_lobby()
			get_tree().change_scene_to_file(MainMenuScenePath)
		"quit":
			get_tree().quit()
