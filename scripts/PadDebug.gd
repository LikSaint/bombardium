extends Control
## Dev-only controller inspector, not reachable from the game — run
## scenes/PadDebug.tscn directly (select it in the editor and press F6).
##
## Exists because "which physical button is JOY_BUTTON_A" is not answerable
## from the code: pads without an SDL mapping (and pads carrying a wrong one,
## or sitting in a DirectInput mode it wasn't written for) report their face
## buttons under whatever indices the firmware uses. This prints what a given
## pad actually sends, so a mapping can be written for it instead of guessed
## at — press each face button in turn and read off the index.

const FACE_LABELS := {
	JOY_BUTTON_A: "A (bottom)",
	JOY_BUTTON_B: "B (right)",
	JOY_BUTTON_X: "X (left)",
	JOY_BUTTON_Y: "Y (top)",
	JOY_BUTTON_DPAD_UP: "DPAD_UP",
	JOY_BUTTON_DPAD_DOWN: "DPAD_DOWN",
	JOY_BUTTON_DPAD_LEFT: "DPAD_LEFT",
	JOY_BUTTON_DPAD_RIGHT: "DPAD_RIGHT",
	JOY_BUTTON_START: "START",
	JOY_BUTTON_BACK: "BACK",
}

var _log: Array[String] = []

@onready var info: Label = $Info
@onready var press_log: Label = $PressLog

func _ready() -> void:
	Input.joy_connection_changed.connect(func(_d, _c): _refresh_info())
	_refresh_info()

func _process(_delta: float) -> void:
	_refresh_info()

func _refresh_info() -> void:
	var lines: Array[String] = []
	var pads := Input.get_connected_joypads()
	lines.append("Connected joypads: %s" % str(pads))
	for device in pads:
		var joy_info := Input.get_joy_info(device)
		lines.append("")
		lines.append("[%d] %s" % [device, Input.get_joy_name(device)])
		lines.append("    guid      : %s" % Input.get_joy_guid(device))
		lines.append("    known     : %s" % Input.is_joy_known(device))
		lines.append("    info      : %s" % str(joy_info))
		lines.append("    held      : %s" % str(_held_buttons(device)))
		lines.append("    axes 0..5 : %s" % str(_axes(device)))
		lines.append("    Pad sees  -> bomb=%s ability=%s pickup=%s" % [
			_name_of(Pad.primary_button(device)),
			_name_of(Pad.ability_button(device)),
			_name_of(Pad.pickup_button(device)),
		])
	if pads.is_empty():
		lines.append("")
		lines.append("Nothing connected. On macOS, run this OUTSIDE the editor's embedded")
		lines.append("game window — joypad input does not reach an embedded game (Godot #110490).")
	info.text = "\n".join(lines)

func _held_buttons(device: int) -> Array:
	var held: Array = []
	for button in range(JOY_BUTTON_MAX):
		if Input.is_joy_button_pressed(device, button):
			held.append(_name_of(button))
	return held

func _axes(device: int) -> Array:
	var values: Array = []
	for axis in range(6):
		values.append("%d:%.2f" % [axis, Input.get_joy_axis(device, axis)])
	return values

func _name_of(button: int) -> String:
	return "%d (%s)" % [button, FACE_LABELS.get(button, "?")]

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_log.push_front("device %d  button %s" % [event.device, _name_of(event.button_index)])
		_log.resize(mini(_log.size(), 12))
		press_log.text = "Last presses (newest first):\n" + "\n".join(_log)
