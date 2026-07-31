extends Control
## Title screen: Play -> Lobby, Settings -> language sub-panel, Quit -> exit.
## Any connected device (keyboard or any gamepad) can navigate - nobody "owns"
## this screen the way a paused match is owned by whoever hit pause.

const LobbyScenePath := "res://scenes/Lobby.tscn"

var options: Array[String] = ["play", "settings", "quit"]
var selected: int = 0
var in_settings: bool = false

func _ready() -> void:
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
	if in_settings:
		$HotkeyHint.text = Loc.t("SETTINGS_HINT")

func _input(event: InputEvent) -> void:
	if in_settings:
		if _is_toggle(event) or _is_confirm(event):
			_close_settings()
		elif _is_prev(event) or _is_next(event):
			Loc.toggle_language()
		return

	if _is_prev(event):
		selected = (selected - 1 + options.size()) % options.size()
		_refresh_selection()
	elif _is_next(event):
		selected = (selected + 1) % options.size()
		_refresh_selection()
	elif _is_confirm(event):
		_activate(options[selected])

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
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		return true
	return false

func _refresh_selection() -> void:
	for i in options.size():
		var node: Control = get_node("MenuRow/" + options[i].capitalize())
		node.modulate = Color(1, 1, 1, 1) if i == selected else Color(1, 1, 1, 0.45)
		node.scale = Vector2(1.1, 1.1) if i == selected else Vector2(1, 1)

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
	$MenuRow.visible = false
	$SettingsPanel.visible = true
	_refresh_settings_texts()

func _close_settings() -> void:
	in_settings = false
	$SettingsPanel.visible = false
	$MenuRow.visible = true
	_refresh_hint()
