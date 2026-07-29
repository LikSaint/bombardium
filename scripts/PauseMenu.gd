extends CanvasLayer
## Escape (keyboard) or Start (any gamepad) opens this — and only the device
## that opened it can navigate/confirm/close it, so one player pausing mid-
## match can't be overridden by anyone else. The title shows who paused.
## Icons only: resume (play), restart match, back to lobby, quit game.
## `include_lobby_restart` is off in the Lobby scene (nothing to restart/leave yet).
##
## If the controller that opened the menu disconnects while it's open, nobody
## else is allowed to touch it (by design) — so without this it would soft-
## lock the game paused forever. Instead it auto-resumes the moment that
## specific device drops.

@export var include_lobby_restart: bool = true

const LobbyScenePath := "res://scenes/Lobby.tscn"

var options: Array[String] = []
var selected: int = 0
var is_open: bool = false
var pausing_device = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if include_lobby_restart:
		options = ["resume", "restart", "lobby", "quit"]
	else:
		options = ["resume", "quit"]
	for opt_name in ["Restart", "Lobby"]:
		get_node("Panel/Row/" + opt_name).visible = include_lobby_restart
	$Title.visible = false
	visible = false
	_refresh_selection()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

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
			_open(device)
		return

	if device != pausing_device:
		return # only the player who paused controls this menu

	if _is_toggle(event):
		_close()
	elif _is_prev(event):
		selected = (selected - 1 + options.size()) % options.size()
		_refresh_selection()
	elif _is_next(event):
		selected = (selected + 1) % options.size()
		_refresh_selection()
	elif _is_confirm(event):
		_activate(options[selected])

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
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
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
	pausing_device = null
	visible = false
	get_tree().paused = false

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
		"restart":
			get_tree().paused = false
			GameManager.reset_match()
			get_tree().reload_current_scene()
		"lobby":
			get_tree().paused = false
			GameManager.leave_to_lobby()
			get_tree().change_scene_to_file(LobbyScenePath)
		"quit":
			get_tree().quit()
