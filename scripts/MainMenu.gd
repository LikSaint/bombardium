extends Control
## Title screen: Play -> Lobby, Settings -> language sub-panel, Quit -> exit.
## Any connected device (keyboard or any gamepad) can navigate - nobody "owns"
## this screen the way a paused match is owned by whoever hit pause.

const LobbyScenePath := "res://scenes/Lobby.tscn"

var options: Array[String] = ["play", "settings", "quit"]
var selected: int = 0
var in_settings: bool = false

enum SettingsRow { LANGUAGE, SOUND, MUSIC }
const SETTINGS_ROW_COUNT := 3
var settings_selected: int = SettingsRow.LANGUAGE

func _ready() -> void:
	Music.play_track(Music.Track.MENU)
	_refresh_menu_texts()
	_refresh_selection()
	_refresh_hint()
	_refresh_settings_texts()
	Loc.language_changed.connect(_on_language_changed)

func _on_language_changed() -> void:
	_refresh_menu_texts()
	_refresh_hint()
	_refresh_settings_texts()

func _refresh_menu_texts() -> void:
	$MenuRow/Play.text = Loc.t("MENU_PLAY")
	$MenuRow/Settings.text = Loc.t("SETTINGS_TITLE")
	$MenuRow/Quit.text = Loc.t("MENU_QUIT")

func _refresh_hint() -> void:
	if not in_settings:
		$HotkeyHint.text = Loc.t("MAIN_MENU_HOTKEY_HINT")

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

func _input(event: InputEvent) -> void:
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

	if _is_prev(event):
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

func _refresh_selection() -> void:
	for i in options.size():
		var node: Control = get_node("MenuRow/" + options[i].capitalize())
		node.modulate = Color(1, 1, 1, 1) if i == selected else Color(1, 1, 1, 0.45)
		if i == selected:
			node.scale = Vector2(1.1, 1.1)
			node.pivot_offset = node.size / 2
		else:
			node.scale = Vector2(1, 1)

func _activate(option: String) -> void:
	match option:
		"play":
			get_tree().change_scene_to_file(LobbyScenePath)
		"settings":
			_open_settings()
		"quit":
			get_tree().quit()

func _open_settings() -> void:
	in_settings = true
	settings_selected = SettingsRow.LANGUAGE
	$MenuRow.visible = false
	$SettingsPanel.visible = true
	_refresh_settings_texts()

func _close_settings() -> void:
	in_settings = false
	$SettingsPanel.visible = false
	$MenuRow.visible = true
	_refresh_hint()
