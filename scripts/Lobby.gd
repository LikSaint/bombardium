extends Control
## Two views sharing one scene (so joined players survive switching between
## them):
## - "settings": the screen shown right after Main Menu -> Play. Up/Down (or
##   dpad up/down) moves between rows, Left/Right (or dpad left/right) edits
##   the selected row's value, confirm on the "Room" row enters the Room view.
##   Any connected device can drive it, like the Main Menu.
## - "room": the join/ready screen (formerly the whole Lobby). Space/A joins a
##   device and then toggles ready; A/D or dpad left/right cycles that
##   device's character while not ready.
## Esc/Start in the Room view goes back to Settings without discarding joined
## slots; re-entering the Room only reshuffles slots (trimmed/rebalanced
## right-to-left) if Player Slots or Bots were actually changed in Settings.
## Once everyone is ready, a 3-2-1 countdown starts the match (cancelled if
## anyone un-readies or leaves).

const MainScenePath := "res://scenes/Main.tscn"
const MainMenuScenePath := "res://scenes/MainMenu.tscn"

const BAR_DIM_COLOR := Color(0.3, 0.3, 0.36, 1)
const BAR_SELECTED_COLOR := Color(1.0, 0.65, 0.2, 1)

const COUNTDOWN_SECONDS := 3

enum SettingsRow { ROOM, MAP_SIZE, PLAYER_SLOTS, BOTS, RANDOM_WALLS, POWERUP_CHANCE, SUDDEN_DEATH, ROUNDS }
const SETTINGS_ROW_COUNT := 8

var view: String = "settings" # "settings" or "room"
var settings_selected: int = SettingsRow.ROOM
# True once Player Slots or Bots has been changed in Settings since the last
# time the Room was entered — gates the right-to-left slot reshuffle so
# leaving via Esc and coming straight back never disturbs anyone who already
# joined.
var settings_touched: bool = false

var slots: Array[Dictionary] = [] # {device, player_id, character_id, ready}
var countdown_active: bool = false

@onready var slot_nodes: Array = [
	$RoomView/Slots/Slot1, $RoomView/Slots/Slot2, $RoomView/Slots/Slot3, $RoomView/Slots/Slot4
]
@onready var bar_nodes: Array = [
	$SettingsPanel/Rows/MapSizeRow/Bars/Bar0, $SettingsPanel/Rows/MapSizeRow/Bars/Bar1,
	$SettingsPanel/Rows/MapSizeRow/Bars/Bar2, $SettingsPanel/Rows/MapSizeRow/Bars/Bar3,
	$SettingsPanel/Rows/MapSizeRow/Bars/Bar4,
]
@onready var settings_row_nodes: Array = [
	$SettingsPanel/Rows/RoomRow, $SettingsPanel/Rows/MapSizeRow, $SettingsPanel/Rows/PlayerSlotsRow,
	$SettingsPanel/Rows/BotsRow, $SettingsPanel/Rows/RandomWallsRow,
	$SettingsPanel/Rows/PowerupChanceRow, $SettingsPanel/Rows/SuddenDeathRow, $SettingsPanel/Rows/RoundsRow,
]
@onready var hotkey_legend: Label = $RoomView/HotkeyLegend
@onready var join_hint: Label = $RoomView/JoinHint
@onready var countdown_label: Label = $RoomView/CountdownLabel

func _ready() -> void:
	Music.play_track(Music.Track.MENU)
	Consts.set_map_size(Consts.map_size_index)
	_refresh_map_size_bars()
	_refresh_settings_texts()
	_refresh_settings_selection()
	_show_view("settings")
	var join_blink := create_tween().set_loops()
	join_blink.tween_property(join_hint, "modulate:a", 0.25, 0.6)
	join_blink.tween_property(join_hint, "modulate:a", 1.0, 0.6)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	Loc.language_changed.connect(_on_language_changed)

func _on_language_changed() -> void:
	_refresh_legend()
	_refresh_slots_ui()
	_refresh_settings_texts()

func _show_view(v: String) -> void:
	view = v
	$SettingsPanel.visible = (v == "settings")
	$RoomView.visible = (v == "room")
	if v == "room":
		_refresh_legend()
		_refresh_slots_ui()

# --- Settings view -----------------------------------------------------

func _refresh_settings_texts() -> void:
	$SettingsPanel/Subtitle.text = Loc.t("MAP_SETTINGS_TITLE")
	$SettingsPanel/Rows/RoomRow/Label.text = "▶  %s" % Loc.t("ROOM_ITEM")
	$SettingsPanel/Rows/MapSizeRow/Label.text = Loc.t("SETTINGS_MAP_SIZE")
	$SettingsPanel/Rows/PlayerSlotsRow/Label.text = Loc.t("SETTINGS_PLAYER_SLOTS")
	$SettingsPanel/Rows/PlayerSlotsRow/Value.text = str(Consts.configured_player_slots)
	$SettingsPanel/Rows/BotsRow/Label.text = Loc.t("SETTINGS_BOTS")
	$SettingsPanel/Rows/BotsRow/Value.text = str(Consts.configured_bots)
	$SettingsPanel/Rows/RandomWallsRow/Label.text = Loc.t("SETTINGS_RANDOM_WALLS")
	$SettingsPanel/Rows/RandomWallsRow/Value.text = Loc.t("SETTINGS_ON") if Consts.random_indestructible_walls else Loc.t("SETTINGS_OFF")
	$SettingsPanel/Rows/PowerupChanceRow/Label.text = Loc.t("SETTINGS_POWERUP_CHANCE")
	$SettingsPanel/Rows/PowerupChanceRow/Value.text = "%d%%" % Consts.powerup_chance_percent
	$SettingsPanel/Rows/SuddenDeathRow/Label.text = Loc.t("SETTINGS_SUDDEN_DEATH")
	var sd_label := Consts.SUDDEN_DEATH_LABELS[Consts.sudden_death_index]
	if sd_label == "OFF":
		$SettingsPanel/Rows/SuddenDeathRow/Value.text = sd_label
	else:
		var sd_suffix := " мин" if Loc.lang == "ru" else " min"
		$SettingsPanel/Rows/SuddenDeathRow/Value.text = sd_label + sd_suffix
	$SettingsPanel/Rows/RoundsRow/Label.text = Loc.t("SETTINGS_ROUNDS")
	$SettingsPanel/Rows/RoundsRow/Value.text = str(Consts.rounds_per_match())
	$SettingsPanel/Hint.text = Loc.t("MAP_SETTINGS_HINT")

func _refresh_settings_selection() -> void:
	for i in settings_row_nodes.size():
		settings_row_nodes[i].modulate = Color(1, 1, 1, 1) if i == settings_selected else Color(1, 1, 1, 0.45)

func _refresh_map_size_bars() -> void:
	for i in bar_nodes.size():
		bar_nodes[i].color = BAR_SELECTED_COLOR if i == Consts.map_size_index else BAR_DIM_COLOR

func _input_settings(event: InputEvent) -> void:
	if _is_back(event):
		Sfx.play_menu()
		get_tree().change_scene_to_file(MainMenuScenePath)
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
	elif _is_confirm(event) and settings_selected == SettingsRow.ROOM:
		Sfx.play_menu()
		_enter_room()

func _adjust_setting(delta: int) -> void:
	match settings_selected:
		SettingsRow.ROOM:
			return
		SettingsRow.MAP_SIZE:
			Consts.set_map_size(Consts.map_size_index + delta)
			_refresh_map_size_bars()
		SettingsRow.PLAYER_SLOTS:
			Consts.set_configured_player_slots(Consts.configured_player_slots + delta)
			settings_touched = true
		SettingsRow.BOTS:
			Consts.set_configured_bots(Consts.configured_bots + delta)
			settings_touched = true
		SettingsRow.RANDOM_WALLS:
			Consts.set_random_indestructible_walls(not Consts.random_indestructible_walls)
		SettingsRow.POWERUP_CHANCE:
			Consts.set_powerup_chance_percent(Consts.powerup_chance_percent + delta * Consts.POWERUP_CHANCE_STEP)
		SettingsRow.SUDDEN_DEATH:
			Consts.set_sudden_death_index(Consts.sudden_death_index + delta)
		SettingsRow.ROUNDS:
			Consts.set_rounds_index(Consts.rounds_index + delta)
	_refresh_settings_texts()
	Sfx.play_menu()

# Reconciles the live `slots` array against the configured player-slot cap
# and bot count. Only called when those two settings actually changed (or on
# the very first Room visit) so a plain Esc-then-Room round trip never
# disturbs anyone already joined.
func _apply_slot_settings() -> void:
	while slots.size() > Consts.configured_player_slots:
		slots.remove_at(slots.size() - 1)

	var bot_count := 0
	for s in slots:
		if s["device"] == Consts.DEVICE_BOT:
			bot_count += 1

	while bot_count > Consts.configured_bots:
		for i in range(slots.size() - 1, -1, -1):
			if slots[i]["device"] == Consts.DEVICE_BOT:
				slots.remove_at(i)
				bot_count -= 1
				break

	while bot_count < Consts.configured_bots and slots.size() < Consts.configured_player_slots:
		_append_bot_slot()
		bot_count += 1

	_reindex_player_ids()

func _enter_room() -> void:
	if settings_touched or slots.is_empty():
		_apply_slot_settings()
		settings_touched = false
	_show_view("room")

# --- Room view -----------------------------------------------------

func _refresh_legend() -> void:
	var join_combo := "%s / %s" % [Hints.KEYBOARD_LABELS[Hints.Action.JOIN], Hints.XBOX_STYLE_LABELS[Hints.Action.JOIN]]
	hotkey_legend.text = Loc.t("LOBBY_LEGEND", [join_combo, Hints.KEYBOARD_LABELS[Hints.Action.CYCLE], Hints.XBOX_STYLE_LABELS[Hints.Action.CYCLE]])
	join_hint.text = Loc.t("LOBBY_JOIN_HINT", [join_combo])

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
			_cancel_countdown()
			_refresh_slots_ui()
			return

func _input(event: InputEvent) -> void:
	if view == "settings":
		_input_settings(event)
	else:
		_input_room(event)

func _input_room(event: InputEvent) -> void:
	if _is_back(event):
		Sfx.play_menu()
		_cancel_countdown()
		_show_view("settings")
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

func _is_back(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		return true
	return false

# Arrow keys are not listed here (or in any other predicate): Pad republishes
# them as their WASD twin, so matching both would move the selection twice per
# press.
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

func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		return true
	return Pad.is_confirm_button(event)

func _device_of_event(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		return -1
	if event is InputEventJoypadButton and event.pressed:
		return event.device
	return null

func _is_join_press(event: InputEvent, device: int) -> bool:
	if device == -1:
		return event.keycode == KEY_SPACE
	return Pad.is_confirm_button(event)

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
		if slots.size() >= Consts.configured_player_slots:
			return
		slots.append({"device": device, "player_id": slots.size() + 1, "character_id": 0, "ready": false})
	else:
		slot["ready"] = not slot["ready"]
		if not slot["ready"]:
			_cancel_countdown()
	Sfx.play_menu()
	_refresh_slots_ui()
	_maybe_start()

func _append_bot_slot() -> void:
	slots.append({
		"device": Consts.DEVICE_BOT,
		"player_id": slots.size() + 1,
		"character_id": randi() % Consts.CHARACTER_COUNT,
		"ready": true,
	})

func _reindex_player_ids() -> void:
	for i in slots.size():
		slots[i]["player_id"] = i + 1

func _cycle_character(device: int, delta: int) -> void:
	var slot := _find_slot_by_device(device)
	if slot.is_empty() or slot["ready"]:
		return
	slot["character_id"] = posmod(slot["character_id"] + delta, Consts.CHARACTER_COUNT)
	Sfx.play_menu()
	_refresh_slots_ui()

func _all_ready() -> bool:
	if slots.is_empty():
		return false
	for slot in slots:
		if not slot["ready"]:
			return false
	return true

func _maybe_start() -> void:
	if countdown_active or not _all_ready():
		return
	_start_countdown()

func _start_countdown() -> void:
	countdown_active = true
	for seconds_left in range(COUNTDOWN_SECONDS, 0, -1):
		if not countdown_active or not _all_ready():
			_cancel_countdown()
			return
		countdown_label.visible = true
		countdown_label.text = Loc.t("MATCH_STARTING_IN", [seconds_left])
		Sfx.play("countdown_tick")
		await get_tree().create_timer(1.0).timeout
	if not countdown_active or not _all_ready() or view != "room":
		_cancel_countdown()
		return
	_begin_match()

func _cancel_countdown() -> void:
	countdown_active = false
	countdown_label.visible = false

func _begin_match() -> void:
	countdown_active = false
	countdown_label.visible = false
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

func _refresh_slots_ui() -> void:
	for i in slot_nodes.size():
		var node: Control = slot_nodes[i]
		if i >= Consts.configured_player_slots:
			node.visible = false
			continue
		node.visible = true
		if i < slots.size():
			var slot: Dictionary = slots[i]
			node.show_joined(i, slot["character_id"], slot["ready"], slot["device"] == Consts.DEVICE_BOT, slot["device"])
		else:
			node.show_empty()
	join_hint.visible = slots.size() < Consts.configured_player_slots
