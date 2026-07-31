extends Control
## Join screen shown before a match. Space/A joins a device and then toggles
## ready; A/D or D-pad left/right cycles that device's character while not
## ready. The keyboard (host) also picks the map size with Up/Down. Starts
## the match once at least one device has joined and everyone is ready.
## Symbols only: "+" = open slot, portrait = your character, check = ready,
## bar height = map size.
## Keyboard-only, like map size: B fills the next open slot with an
## AI-controlled bot (instantly ready); N removes the most recently added bot.

const MainScenePath := "res://scenes/Main.tscn"

const BAR_DIM_COLOR := Color(0.3, 0.3, 0.36, 1)
const BAR_SELECTED_COLOR := Color(1.0, 0.65, 0.2, 1)

var slots: Array[Dictionary] = [] # {device, player_id, character_id, ready}

@onready var slot_nodes: Array = [$Slots/Slot1, $Slots/Slot2, $Slots/Slot3, $Slots/Slot4]
@onready var bar_nodes: Array = [
	$MapSizeRow/Bar0, $MapSizeRow/Bar1, $MapSizeRow/Bar2, $MapSizeRow/Bar3, $MapSizeRow/Bar4
]
@onready var hotkey_legend: Label = $HotkeyLegend

func _ready() -> void:
	Consts.set_map_size(Consts.DEFAULT_MAP_SIZE_INDEX)
	_refresh_map_size_bars()
	_refresh_slots_ui()
	_refresh_legend()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	Loc.language_changed.connect(_on_language_changed)

func _on_language_changed() -> void:
	_refresh_legend()
	_refresh_slots_ui()

func _refresh_legend() -> void:
	var join_combo := "%s / %s" % [Hints.KEYBOARD_LABELS[Hints.Action.JOIN], Hints.XBOX_STYLE_LABELS[Hints.Action.JOIN]]
	hotkey_legend.text = Loc.t("LOBBY_LEGEND", [join_combo, Hints.KEYBOARD_LABELS[Hints.Action.CYCLE], Hints.XBOX_STYLE_LABELS[Hints.Action.CYCLE]])

# Nothing persists pre-match, so a dropped controller's slot just closes
# outright (freeing it for anyone to re-join) instead of trying to hold a
# "waiting to reconnect" state — otherwise an unplugged pad could permanently
# block the match from starting on a ready check that can never be satisfied.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	for i in slots.size():
		if slots[i]["device"] == device:
			slots.remove_at(i)
			_reindex_player_ids()
			_refresh_slots_ui()
			return

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP:
			Consts.set_map_size(Consts.map_size_index - 1)
			_refresh_map_size_bars()
			return
		elif event.keycode == KEY_DOWN:
			Consts.set_map_size(Consts.map_size_index + 1)
			_refresh_map_size_bars()
			return
		elif event.keycode == KEY_B:
			_add_bot()
			return
		elif event.keycode == KEY_N:
			_remove_last_bot()
			return

	var device = _device_of_event(event)
	if device == null:
		return

	if _is_join_press(event, device):
		_toggle_join_or_ready(device)
	elif _is_left(event, device):
		_cycle_character(device, -1)
	elif _is_right(event, device):
		_cycle_character(device, 1)

func _device_of_event(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		return -1
	if event is InputEventJoypadButton and event.pressed:
		return event.device
	return null

func _is_join_press(event: InputEvent, device: int) -> bool:
	if device == -1:
		return event.keycode == KEY_SPACE
	return event.button_index == JOY_BUTTON_A

func _is_left(event: InputEvent, device: int) -> bool:
	if device == -1:
		return event.keycode == KEY_A
	return event.button_index == JOY_BUTTON_DPAD_LEFT

func _is_right(event: InputEvent, device: int) -> bool:
	if device == -1:
		return event.keycode == KEY_D
	return event.button_index == JOY_BUTTON_DPAD_RIGHT

func _find_slot_by_device(device: int) -> Dictionary:
	for s in slots:
		if s["device"] == device:
			return s
	return {}

func _toggle_join_or_ready(device: int) -> void:
	var slot := _find_slot_by_device(device)
	if slot.is_empty():
		if slots.size() >= Consts.MAX_PLAYERS:
			return
		slots.append({"device": device, "player_id": slots.size() + 1, "character_id": 0, "ready": false})
	else:
		slot["ready"] = not slot["ready"]
	_refresh_slots_ui()
	_maybe_start()

func _add_bot() -> void:
	if slots.size() >= Consts.MAX_PLAYERS:
		return
	_append_bot_slot()
	_refresh_slots_ui()
	_maybe_start()

func _append_bot_slot() -> void:
	slots.append({
		"device": Consts.DEVICE_BOT,
		"player_id": slots.size() + 1,
		"character_id": randi() % Consts.CHARACTER_COUNT,
		"ready": true,
	})

func _remove_last_bot() -> void:
	for i in range(slots.size() - 1, -1, -1):
		if slots[i]["device"] == Consts.DEVICE_BOT:
			slots.remove_at(i)
			_reindex_player_ids()
			_refresh_slots_ui()
			return

func _reindex_player_ids() -> void:
	for i in slots.size():
		slots[i]["player_id"] = i + 1

func _cycle_character(device: int, delta: int) -> void:
	var slot := _find_slot_by_device(device)
	if slot.is_empty() or slot["ready"]:
		return
	slot["character_id"] = posmod(slot["character_id"] + delta, Consts.CHARACTER_COUNT)
	_refresh_slots_ui()

func _maybe_start() -> void:
	if slots.is_empty():
		return
	for slot in slots:
		if not slot["ready"]:
			return

	# A single player alone can never become "the last survivor" (round_ended
	# only fires once someone else has died) — auto-fill a bot opponent so a
	# solo match is actually playable instead of running forever.
	if slots.size() == 1:
		_append_bot_slot()
		_refresh_slots_ui()
		_maybe_start()
		return

	var player_slots: Array[Dictionary] = []
	for slot in slots:
		player_slots.append({
			"id": slot["player_id"],
			"device": slot["device"],
			"character_id": slot["character_id"],
		})
	GameManager.set_player_slots(player_slots)
	GameManager.reset_match()
	get_tree().change_scene_to_file(MainScenePath)

func _refresh_map_size_bars() -> void:
	for i in bar_nodes.size():
		bar_nodes[i].color = BAR_SELECTED_COLOR if i == Consts.map_size_index else BAR_DIM_COLOR

func _refresh_slots_ui() -> void:
	for i in slot_nodes.size():
		var node: Control = slot_nodes[i]
		if i < slots.size():
			var slot: Dictionary = slots[i]
			node.show_joined(i, slot["character_id"], slot["ready"], slot["device"] == Consts.DEVICE_BOT, slot["device"])
		else:
			node.show_empty()
