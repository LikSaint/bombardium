extends Node
## Autoloaded as `Hints`. Maps a slot's device_id to a human-readable control
## label (keyboard letters vs. gamepad glyphs) so per-character text like
## "E: place a wall" can show whichever button is actually bound for that
## specific player instead of a hardcoded keyboard key.

enum Action { MOVE, BOMB, ABILITY, PICKUP, CYCLE, JOIN, PAUSE }

const KEYBOARD_LABELS := {
	Action.MOVE: "WASD",
	Action.BOMB: "Space",
	Action.ABILITY: "E",
	Action.PICKUP: "Q",
	Action.CYCLE: "A/D",
	Action.JOIN: "Space",
	Action.PAUSE: "Esc",
}

# Godot's JOY_BUTTON_* indices already follow Xbox-style face-button layout
# (A=bottom, B=right, X=left, Y=top) regardless of the physical pad, so this
# is the correct label set for Xbox/generic/Switch controllers. PlayStation
# pads get their own glyphs since players know those buttons as symbols.
const XBOX_STYLE_LABELS := {
	Action.MOVE: "◄►",
	Action.BOMB: "A",
	Action.ABILITY: "X",
	Action.PICKUP: "B",
	Action.CYCLE: "◄►",
	Action.JOIN: "A",
	Action.PAUSE: "Start",
}

const PLAYSTATION_LABELS := {
	Action.MOVE: "◄►",
	Action.BOMB: "✕",
	Action.ABILITY: "□",
	Action.PICKUP: "○",
	Action.CYCLE: "◄►",
	Action.JOIN: "✕",
	Action.PAUSE: "Start",
}

# Nintendo prints its face buttons in mirrored positions: the bottom button is
# B (not A) and the left one is Y (not X). Godot's JOY_BUTTON_* names are
# positional, so the *bindings* need no change here — only the printed glyphs
# do, or a Switch player is told to press a button that sits on the far side
# of the pad from the one that actually fires.
const NINTENDO_LABELS := {
	Action.MOVE: "◄►",
	Action.BOMB: "B",
	Action.ABILITY: "Y",
	Action.PICKUP: "A",
	Action.CYCLE: "◄►",
	Action.JOIN: "B",
	Action.PAUSE: "+",
}

## Empty string for a bot or a currently-disconnected slot — neither has a
## real input device to describe.
func label(device_id: int, action: int) -> String:
	if device_id == Consts.DEVICE_BOT or device_id == Consts.DEVICE_NONE:
		return ""
	if device_id == -1:
		return KEYBOARD_LABELS.get(action, "")
	return _gamepad_labels(device_id).get(action, "")

func is_keyboard(device_id: int) -> bool:
	return device_id == -1

func _gamepad_labels(device_id: int) -> Dictionary:
	match Pad.family(device_id):
		Pad.Family.PLAYSTATION:
			return PLAYSTATION_LABELS
		Pad.Family.NINTENDO:
			return NINTENDO_LABELS
		_:
			return XBOX_STYLE_LABELS
