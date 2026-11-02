extends Control
## A little pictogram of what is driving a seat: a robot head for a bot, a gamepad for a
## pad, a keyboard for the keyboard. Baked once per device into a 34x22 pixel sprite in
## the same style as the HUD icons (dark ink outline, lit top edge, shaded underside), so
## it stays crisp at whatever scale the HUD corner is given, and needs no art files. Used
## on the lobby slots and on the in-match HUD corners (see LobbySlot, PlayerHudCorner).

const W := 34
const H := 22
const SIZE := Vector2(W, H)

const INK := Color(0.09, 0.07, 0.13)
const SCREEN := Color(0.07, 0.09, 0.17)

## Per device: [body, lit edge, shaded edge].
const BOT_TONES := [Color(1.0, 0.8, 0.22), Color(1.0, 0.95, 0.6), Color(0.86, 0.5, 0.12)]
const PAD_TONES := [Color(0.42, 0.74, 1.0), Color(0.8, 0.94, 1.0), Color(0.2, 0.44, 0.82)]
const KEYBOARD_TONES := [Color(0.55, 0.58, 0.74), Color(0.82, 0.85, 0.95), Color(0.36, 0.38, 0.54)]

static var _textures: Dictionary = {}

var _device: int = Consts.DEVICE_BOT

func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_device(device_id: int) -> void:
	_device = device_id
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(_texture_for(_device), Rect2(Vector2.ZERO, size), false)

static func _texture_for(device_id: int) -> Texture2D:
	var key := _kind(device_id)
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(make_image(device_id))
	return _textures[key]

## -3 bot, -1 keyboard, anything else a pad.
static func _kind(device_id: int) -> int:
	if device_id == Consts.DEVICE_BOT:
		return Consts.DEVICE_BOT
	return -1 if device_id == -1 else 0

static func make_image(device_id: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	match _kind(device_id):
		Consts.DEVICE_BOT:
			_bake_bot(img)
		-1:
			_bake_keyboard(img)
		_:
			_bake_pad(img)
	return img

# --- sprites -----------------------------------------------------------------

static func _bake_bot(img: Image) -> void:
	var mask := _new_mask()
	_span(mask, 2, 16, 17) # antenna ball
	_span(mask, 3, 15, 18)
	_span(mask, 4, 16, 17) # stem
	_span(mask, 5, 8, 25) # head, corners cut
	for y in range(6, 18):
		_span(mask, y, 7, 26)
	_span(mask, 18, 8, 25)
	for y in range(9, 15): # ears
		_span(mask, y, 4, 6)
		_span(mask, y, 27, 29)
	_paint(img, mask, BOT_TONES)
	_rect(img, 10, 8, 14, 6, SCREEN) # visor
	for eye_x in [12, 18]:
		_rect(img, eye_x, 9, 4, 4, Color(0.3, 0.95, 1.0))
		_rect(img, eye_x, 11, 4, 2, Color(0.1, 0.65, 0.85))
		_rect(img, eye_x, 9, 1, 1, Color.WHITE) # glint
	for grill_x in [11, 13, 15, 17, 19, 21]: # mouth grill
		_rect(img, grill_x, 15, 1, 2, BOT_TONES[2])
	_rect(img, 9, 6, 1, 1, BOT_TONES[1]) # rivets
	_rect(img, 24, 6, 1, 1, BOT_TONES[1])
	_rect(img, 16, 2, 1, 1, Color.WHITE) # antenna glint

static func _bake_pad(img: Image) -> void:
	var mask := _new_mask()
	var rows := [
		[3, 8, 25], [4, 6, 27], [5, 5, 28], [6, 4, 29], [7, 3, 30], [8, 3, 30],
		[9, 2, 31], [10, 2, 31], [11, 2, 31], [12, 2, 31], [13, 2, 31], [14, 3, 30],
	]
	for r in rows:
		_span(mask, r[0], r[1], r[2])
	_span(mask, 15, 3, 11) # grips
	_span(mask, 15, 22, 30)
	_span(mask, 16, 3, 10)
	_span(mask, 16, 23, 30)
	_span(mask, 17, 3, 9)
	_span(mask, 17, 24, 30)
	_span(mask, 18, 4, 8)
	_span(mask, 18, 25, 29)
	_paint(img, mask, PAD_TONES)
	_rect(img, 8, 6, 3, 7, SCREEN) # d-pad
	_rect(img, 6, 8, 7, 3, SCREEN)
	_rect(img, 9, 9, 1, 1, Color(0.3, 0.34, 0.5))
	_rect(img, 23, 6, 2, 2, Color(1.0, 0.85, 0.3)) # face buttons
	_rect(img, 26, 9, 2, 2, Color(1.0, 0.38, 0.38))
	_rect(img, 23, 12, 2, 2, Color(0.4, 0.9, 0.45))
	_rect(img, 20, 9, 2, 2, Color.WHITE)
	_rect(img, 16, 8, 2, 2, PAD_TONES[1]) # home button
	_rect(img, 6, 4, 6, 1, PAD_TONES[1]) # bumper glints
	_rect(img, 22, 4, 6, 1, PAD_TONES[1])

static func _bake_keyboard(img: Image) -> void:
	var mask := _new_mask()
	_span(mask, 4, 2, 31)
	for y in range(5, 18):
		_span(mask, y, 1, 32)
	_span(mask, 18, 2, 31)
	_paint(img, mask, KEYBOARD_TONES)
	var cap := Color(0.97, 0.98, 1.0)
	var cap_shade := Color(0.66, 0.68, 0.84)
	for row_y in [6, 10]:
		for col in 6:
			_key(img, 3 + col * 5, row_y, 3, cap, cap_shade)
	_key(img, 3, 14, 4, cap, cap_shade)
	_key(img, 9, 14, 16, cap, cap_shade) # space bar
	_key(img, 27, 14, 4, cap, cap_shade)

# --- helpers -----------------------------------------------------------------

static func _new_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(W * H)
	return mask

static func _span(mask: PackedByteArray, y: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		mask[y * W + x] = 1

static func _filled(mask: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and mask[y * W + x] == 1

## Fills the silhouette with the body tone, lights its upper edge, shades its lower and
## right edges and wraps it in the ink outline.
static func _paint(img: Image, mask: PackedByteArray, tones: Array) -> void:
	for y in H:
		for x in W:
			if _filled(mask, x, y):
				var c: Color = tones[0]
				if not _filled(mask, x, y - 1) or not _filled(mask, x - 1, y):
					c = tones[1]
				if not _filled(mask, x, y + 1) or not _filled(mask, x + 1, y):
					c = tones[2]
				img.set_pixel(x, y, c)
			elif _filled(mask, x - 1, y) or _filled(mask, x + 1, y) \
					or _filled(mask, x, y - 1) or _filled(mask, x, y + 1):
				img.set_pixel(x, y, INK)

static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)

static func _key(img: Image, x: int, y: int, w: int, cap: Color, shade: Color) -> void:
	_rect(img, x, y, w, 3, cap)
	_rect(img, x, y + 2, w, 1, shade)
