extends Node
## Joining a match that is already running. A child of Main.
##
## Any device that is not playing — a pad, or the keyboard — can sit down:
##
##   1. Press any button. That does not join yet; it only says "I'm here", and the seats
##      somebody could take light up on the HUD ("press any button" on each, pulsing).
##   2. Pick which seat: left/right (or up/down) moves between them, and the one you are
##      on is framed on the HUD. A seat is a bot's, or the first free slot.
##   3. Press A (Space on the keyboard) to take it. B (Esc) backs out, and so does
##      waiting too long.
##
## Two presses rather than one, because a button pressed by accident — a pad picked up
## off the sofa, a stray key — must not put a character into somebody's game; and a
## choice, because which bot you replace is the point of joining mid-fight.
##
## Several devices can be choosing at once; if two want the same seat the first to
## confirm gets it and the other's pick moves on to the next one.
##
## What a seat *is* and how it is filled belongs to Main (join_candidates, join_slot);
## this is only the interaction and what it draws on the HUD.

## How long a half-finished join waits for the next press before giving up.
const IDLE_TIMEOUT := 8.0

var main: Node = null
## device -> {"slot": index into the match's slots, "idle": seconds since its last press}
var _pending: Dictionary = {}

func _process(delta: float) -> void:
	if main == null:
		return
	if not main.late_join_allowed():
		_pending.clear()
	else:
		_tidy_pending(delta)
	_refresh_hud()

## Drops devices that went idle or got seated by other means, and moves any pick whose
## seat has been taken since onto a seat that is still free.
func _tidy_pending(delta: float) -> void:
	var candidates: Array[int] = main.join_candidates()
	for device in _pending.keys():
		var entry: Dictionary = _pending[device]
		entry["idle"] += delta
		if entry["idle"] >= IDLE_TIMEOUT or GameManager.device_in_match(device) or candidates.is_empty():
			_pending.erase(device)
			continue
		if not candidates.has(entry["slot"]):
			entry["slot"] = candidates[0]

func _input(event: InputEvent) -> void:
	if main == null or not main.late_join_allowed():
		return
	var device = _device_of(event)
	if device == null or GameManager.device_in_match(device):
		return
	if not _pending.has(device):
		if not _is_any_button(event):
			return
		var candidates: Array[int] = main.join_candidates()
		if candidates.is_empty():
			return # nothing to take, so nothing happens
		_pending[device] = {"slot": _first_choice(candidates), "idle": 0.0}
		get_viewport().set_input_as_handled()
		return
	# Choosing: everything this device presses belongs to the join until it is done.
	if not _is_press(event):
		return
	get_viewport().set_input_as_handled()
	var entry: Dictionary = _pending[device]
	entry["idle"] = 0.0
	if _is_cancel(event):
		_pending.erase(device)
	elif _is_confirm(event):
		var slot: int = entry["slot"]
		_pending.erase(device)
		main.join_slot(device, slot)
	elif _is_prev(event):
		_step(entry, -1)
	elif _is_next(event):
		_step(entry, 1)

## A free slot if there is one — somewhere to arrive as a new player — otherwise the
## first bot.
func _first_choice(candidates: Array[int]) -> int:
	var free: int = candidates.back()
	if free >= GameManager.player_slots.size():
		return free
	return candidates[0]

func _step(entry: Dictionary, direction: int) -> void:
	var candidates: Array[int] = main.join_candidates()
	if candidates.is_empty():
		return
	var at := candidates.find(entry["slot"])
	entry["slot"] = candidates[posmod(at + direction, candidates.size())]
	Sfx.play_menu()

# --- What this draws on the HUD --------------------------------------------

func _refresh_hud() -> void:
	var enabled: bool = main != null and main.late_join_allowed()
	var candidates: Array[int] = main.join_candidates() if enabled else []
	var corners: Array = main.hud_corners
	for i in corners.size():
		var corner = corners[i]
		var state: int = corner.JoinState.NONE
		var confirm_text := ""
		if candidates.has(i):
			state = corner.JoinState.PROMPT
			for device in _pending:
				if _pending[device]["slot"] == i:
					state = corner.JoinState.SELECTED
					confirm_text = Hints.label(device, Hints.Action.JOIN)
					break
		corner.set_join_state(state, confirm_text)

# --- Reading input ----------------------------------------------------------

## -1 for the keyboard, the pad's index for a joypad, null for anything else (mouse,
## stick motion — a drifting stick is not somebody pressing a button).
func _device_of(event: InputEvent):
	if event is InputEventKey:
		return -1
	if event is InputEventJoypadButton:
		return event.device
	return null

func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and not _is_arrow_key(event)
	return event is InputEventJoypadButton and event.pressed

## The arrow keys are left out entirely: Pad republishes each one as its WASD twin
## (see PadInput._mirror_arrow_key), and counting both would move a choice twice per
## press, or turn the first press of an arrow into "any button" and its twin into a
## move.
func _is_arrow_key(event: InputEventKey) -> bool:
	return event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

## Any button at all starts a join — except Esc, which is the pause key for those playing
## and has no business seating anybody.
func _is_any_button(event: InputEvent) -> bool:
	if not _is_press(event):
		return false
	return not (event is InputEventKey and event.keycode == KEY_ESCAPE)

func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.keycode == KEY_SPACE or event.keycode == KEY_ENTER
	# JOY_BUTTON_A is positional — the bottom face button — whatever the pad prints on it.
	return event.button_index == JOY_BUTTON_A

func _is_cancel(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.keycode == KEY_ESCAPE
	return event.button_index == JOY_BUTTON_B

func _is_prev(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.keycode == KEY_A or event.keycode == KEY_W
	return event.button_index == JOY_BUTTON_DPAD_LEFT or event.button_index == JOY_BUTTON_DPAD_UP

func _is_next(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.keycode == KEY_D or event.keycode == KEY_S
	return event.button_index == JOY_BUTTON_DPAD_RIGHT or event.button_index == JOY_BUTTON_DPAD_DOWN
