extends Control
## Shown at the bottom of the screen for a dead player: their character
## portrait. Left/Right (A/D on keyboard, D-pad on gamepad) cycles the pick
## live in GameManager; it takes effect when the next round spawns players.
##
## `device_id` is captured once at spawn, but the underlying controller can
## drop and get reclaimed by a *different* physical pad (GameManager's LIFO
## reconnect) while this dock is still on screen — so it stays synced via
## GameManager's disconnect/reconnect signals instead of trusting a stale copy.

var player_id: int
var device_id: int
var character_id: int
var is_disconnected: bool = false

func _ready() -> void:
	_refresh()
	_refresh_hint()
	var blink := create_tween().set_loops()
	blink.tween_property($ArrowLeft, "modulate:a", 0.25, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 0.25, 0.5)
	blink.tween_property($ArrowLeft, "modulate:a", 1.0, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 1.0, 0.5)
	GameManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.player_reconnected.connect(_on_player_reconnected)

func _on_player_disconnected(p_id: int) -> void:
	if p_id != player_id:
		return
	is_disconnected = true
	_refresh_hint()

func _on_player_reconnected(p_id: int, device: int) -> void:
	if p_id != player_id:
		return
	device_id = device
	is_disconnected = false
	_refresh_hint()

func _input(event: InputEvent) -> void:
	if is_disconnected:
		return
	var dir := 0
	if device_id == -1:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_A:
				dir = -1
			elif event.keycode == KEY_D:
				dir = 1
	else:
		if event is InputEventJoypadButton and event.device == device_id and event.pressed:
			if event.button_index == JOY_BUTTON_DPAD_LEFT:
				dir = -1
			elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
				dir = 1
	if dir == 0:
		return
	character_id = posmod(character_id + dir, Consts.CHARACTER_NAMES.size())
	GameManager.set_character_id(player_id, character_id)
	_refresh()

func _refresh() -> void:
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[(player_id - 1) % Consts.PLAYER_COLORS.size()])

func _refresh_hint() -> void:
	if is_disconnected:
		$HotkeyHint.text = "Отключено…"
	else:
		$HotkeyHint.text = "A/D — сменить" if device_id == -1 else "◄► — сменить"
