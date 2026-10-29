extends Control
## A little pictogram of what is driving a seat: a robot head for a bot, a gamepad for a
## pad, a keyboard for the keyboard. Drawn with shapes rather than a texture so it
## stays crisp at whatever scale the HUD corner is given, and needs no art. Used on the
## lobby slots and on the in-match HUD corners (see LobbySlot, PlayerHudCorner).

const SIZE := Vector2(34, 22)
const BOT_COLOR := Color(1.0, 0.85, 0.2)
const PAD_COLOR := Color(0.55, 0.85, 1.0)
const KEYBOARD_COLOR := Color(0.85, 0.88, 0.95)
const OUTLINE := Color(0, 0, 0, 0.55)

var _device: int = Consts.DEVICE_BOT

func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_device(device_id: int) -> void:
	_device = device_id
	queue_redraw()

func _draw() -> void:
	# A dark plate behind it so the icon reads on any frame colour.
	draw_rect(Rect2(Vector2.ZERO, SIZE), OUTLINE, true)
	if _device == Consts.DEVICE_BOT:
		_draw_bot()
	elif _device == -1:
		_draw_keyboard()
	else:
		_draw_pad()

func _draw_bot() -> void:
	var c := BOT_COLOR
	draw_line(Vector2(17, 2), Vector2(17, 5), c, 2.0) # antenna
	draw_circle(Vector2(17, 2.5), 1.8, c)
	draw_rect(Rect2(8, 5, 18, 13), c, true) # head
	draw_rect(Rect2(5, 9, 3, 5), c, true) # ears
	draw_rect(Rect2(26, 9, 3, 5), c, true)
	draw_rect(Rect2(11, 8, 4, 4), OUTLINE, true) # eyes
	draw_rect(Rect2(19, 8, 4, 4), OUTLINE, true)
	draw_rect(Rect2(12, 14, 10, 2), OUTLINE, true) # mouth

func _draw_pad() -> void:
	var c := PAD_COLOR
	var body := PackedVector2Array([
		Vector2(8, 5), Vector2(26, 5), Vector2(31, 10), Vector2(32, 17),
		Vector2(29, 19), Vector2(25, 15), Vector2(9, 15), Vector2(5, 19),
		Vector2(2, 17), Vector2(3, 10),
	])
	draw_colored_polygon(body, c)
	draw_rect(Rect2(8, 8, 6, 2), OUTLINE, true) # d-pad
	draw_rect(Rect2(10, 6, 2, 6), OUTLINE, true)
	draw_circle(Vector2(23, 8), 1.5, OUTLINE) # face buttons
	draw_circle(Vector2(27, 10), 1.5, OUTLINE)
	draw_circle(Vector2(23, 12), 1.5, OUTLINE)

func _draw_keyboard() -> void:
	var c := KEYBOARD_COLOR
	draw_rect(Rect2(2, 4, 30, 15), c, true)
	for row in 2:
		for col in 7:
			draw_rect(Rect2(4 + col * 4, 6 + row * 4, 3, 3), OUTLINE, true)
	draw_rect(Rect2(8, 14, 18, 3), OUTLINE, true) # space bar
