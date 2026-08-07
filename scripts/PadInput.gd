extends Node
## Autoloaded as `Pad`. Smooths over the differences between controller
## families so the rest of the game can keep speaking one dialect.
##
## Two jobs:
##
## 1. Left stick -> synthetic D-pad. Every menu, the Lobby and the dead-player
##    character dock navigate on JOY_BUTTON_DPAD_* alone. A lot of common pads
##    can't drive that: unbranded clones with no entry in Godot's SDL mapping
##    database report their D-pad as a raw hat/axis that never becomes a
##    JOY_BUTTON_DPAD_* event, and some pads have no D-pad worth using at all.
##    So this node watches each device's left stick and injects real D-pad
##    press/release events for the same device index. Everything downstream
##    stays plain D-pad code with no per-pad special-casing, and the
##    "stick — navigate" hints already on screen stop being a lie.
##
## 2. Arrow keys -> WASD, by the same trick, so the keyboard player can steer
##    with either cluster everywhere (menus and the arena alike) without WASD
##    checks having to be written twice in every screen.
##
## 3. Face-button and glyph normalization for pads Godot has no mapping for
##    (see is_confirm_button) and for the Nintendo/PlayStation button naming
##    that ControlHints renders.

const NAV_DEADZONE := 0.5 # higher than Player's MOVE_DEADZONE: a menu should not skip a row on a resting thumb

enum Family { XBOX, PLAYSTATION, NINTENDO }

const PLAYSTATION_VENDOR_ID := 0x054C
const NINTENDO_VENDOR_ID := 0x057E

# device -> the cardinal direction its stick is currently held in (ZERO = centered).
var _stick_dir: Dictionary = {}

func _ready() -> void:
	# The pause menu runs with the tree paused, and it is navigated with the
	# very events this node synthesizes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

# A pad unplugged mid-deflection would otherwise leave its synthetic D-pad
# button stuck down forever, and the next pad to take that device index would
# inherit it.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	var held: Vector2i = _stick_dir.get(device, Vector2i.ZERO)
	if held != Vector2i.ZERO:
		_emit_dpad(device, held, false)
	_stick_dir.erase(device)
	# The next pad to take this device index gets to teach its own layout.
	_primary_button.erase(device)

# Movement/navigation is written against WASD throughout — polled in
# Player._poll_move_dir, matched by keycode in every menu. Rather than spell
# out both clusters in a dozen places, an arrow press is republished as its
# WASD twin, which also lands in Input's key state so the polling side picks it
# up unchanged. `echo` is carried over so the "not event.echo" guards menus use
# to ignore OS key-repeat keep working.
const _ARROW_TO_WASD := {
	KEY_LEFT: KEY_A,
	KEY_RIGHT: KEY_D,
	KEY_UP: KEY_W,
	KEY_DOWN: KEY_S,
}

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_mirror_arrow_key(event)
		return
	if not (event is InputEventJoypadMotion):
		return
	if event.axis != JOY_AXIS_LEFT_X and event.axis != JOY_AXIS_LEFT_Y:
		return
	var device: int = event.device
	var dir := _stick_direction(device)
	var prev: Vector2i = _stick_dir.get(device, Vector2i.ZERO)
	if dir == prev:
		return
	_stick_dir[device] = dir
	# Release first, so a roll straight from left to right reads as two clean
	# presses instead of leaving both directions held at once.
	if prev != Vector2i.ZERO:
		_emit_dpad(device, prev, false)
	if dir != Vector2i.ZERO:
		_emit_dpad(device, dir, true)

## Both axes are read from Input rather than off the event, because a diagonal
## push arrives as two separate single-axis events and only the pair decides
## which direction actually wins.
func _stick_direction(device: int) -> Vector2i:
	var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	if absf(x) > absf(y):
		if x > NAV_DEADZONE:
			return Consts.DIR_RIGHT
		if x < -NAV_DEADZONE:
			return Consts.DIR_LEFT
	else:
		if y > NAV_DEADZONE:
			return Consts.DIR_DOWN
		if y < -NAV_DEADZONE:
			return Consts.DIR_UP
	return Vector2i.ZERO

func _mirror_arrow_key(event: InputEventKey) -> void:
	if not _ARROW_TO_WASD.has(event.keycode):
		return
	var twin := InputEventKey.new()
	twin.keycode = _ARROW_TO_WASD[event.keycode]
	twin.physical_keycode = twin.keycode
	twin.pressed = event.pressed
	twin.echo = event.echo
	Input.parse_input_event(twin)

func _emit_dpad(device: int, dir: Vector2i, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = _button_for_dir(dir)
	event.pressed = pressed
	Input.parse_input_event(event)

func _button_for_dir(dir: Vector2i) -> int:
	match dir:
		Consts.DIR_LEFT:
			return JOY_BUTTON_DPAD_LEFT
		Consts.DIR_RIGHT:
			return JOY_BUTTON_DPAD_RIGHT
		Consts.DIR_UP:
			return JOY_BUTTON_DPAD_UP
		_:
			return JOY_BUTTON_DPAD_DOWN

# --- Face buttons ---------------------------------------------------------
#
# JOY_BUTTON_A/B/X/Y are positional names Godot derives from the pad's SDL
# mapping: on a correctly mapped pad JOY_BUTTON_A is the bottom button whatever
# the vendor prints on it (Cross on PlayStation, B on Nintendo). Cheap PC pads
# break that assumption in both directions — some have no mapping at all and
# report raw firmware indices, others carry a mapping that is simply wrong for
# the hardware, or sit in a DirectInput mode the mapping wasn't written for. On
# those, the bottom button can arrive as JOY_BUTTON_B, and hardcoding
# JOY_BUTTON_A puts every primary action on a button nobody is pressing.
#
# So the primary button is *learned* instead of assumed: whichever face button
# a device first confirms with (title screen, Lobby join, reconnect claim) is
# that device's primary from then on, and the other two in-match actions are
# placed relative to it around the four-button cluster.

const FACE_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]

# Offsets around the face cluster, measured from the primary. On a standard pad
# the primary is A, which puts ability on X and pickup on B — the layout these
# were bound to before any of this existed.
const _ABILITY_OFFSET := 2
const _PICKUP_OFFSET := 1

var _primary_button: Dictionary = {} # device -> face button index it confirms with

## True for any face button press. Also records that button as the device's
## primary the first time — deliberate, and the reason this is not a pure
## predicate: it is only ever called from confirm/join/reclaim paths, which is
## exactly the moment a player demonstrates which button they consider "A".
func is_confirm_button(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return false
	if not (event.button_index in FACE_BUTTONS):
		return false
	if not _primary_button.has(event.device):
		_primary_button[event.device] = event.button_index
	return true

func primary_button(device: int) -> int:
	return _primary_button.get(device, JOY_BUTTON_A)

func ability_button(device: int) -> int:
	return _offset_from_primary(device, _ABILITY_OFFSET)

func pickup_button(device: int) -> int:
	return _offset_from_primary(device, _PICKUP_OFFSET)

# Wraps around the cluster so the three in-match actions can never collide on
# one button, whatever index the primary turned out to be.
func _offset_from_primary(device: int, offset: int) -> int:
	var base := FACE_BUTTONS.find(primary_button(device))
	return FACE_BUTTONS[(base + offset) % FACE_BUTTONS.size()]

## Which vendor's button names to print for `device`. get_joy_info() comes back
## empty on some platforms (notably macOS with the editor's embedded game
## window), so the name check is a real fallback, not just belt-and-braces.
func family(device: int) -> int:
	var info := Input.get_joy_info(device)
	match info.get("vendor_id", 0):
		PLAYSTATION_VENDOR_ID:
			return Family.PLAYSTATION
		NINTENDO_VENDOR_ID:
			return Family.NINTENDO
	var joy_name := Input.get_joy_name(device).to_lower()
	for token in ["sony", "playstation", "dualshock", "dualsense"]:
		if token in joy_name:
			return Family.PLAYSTATION
	for token in ["nintendo", "switch", "joy-con", "joycon", "pro controller"]:
		if token in joy_name:
			return Family.NINTENDO
	return Family.XBOX
