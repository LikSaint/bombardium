extends Node2D
## The "a hazard just came out of this crate" marker: a warning triangle hovering
## over the cell with two rings pulsing out of it, for DURATION seconds and gone.
##
## A hazard used to appear with nothing but a dull thud, which for a saw that is
## already moving or a cloud that is already spreading is no warning at all — the
## first anybody knew about it was dying to it. The sign is the same for every kind
## of hazard on purpose: it means "something dangerous just came out of that crate"
## without anybody having to learn a different one per trap — what it is, the thing
## itself shows.
##
## The triangle sits above the cell, not on it, so it never hides the hazard that
## is emerging underneath.

const DURATION := 2.0
const WARNING_COLOR := Color(1.0, 0.82, 0.12)
const WARNING_EDGE_COLOR := Color(0.14, 0.08, 0.04)
const RING_COLOR := Color(1.0, 0.3, 0.1)
## Above players and bombs: it is an overlay, not part of the floor.
const OVERLAY_Z := 20

var _age: float = 0.0

func _ready() -> void:
	z_index = OVERLAY_Z

func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Held at full strength, then fading over the last third.
	var fade := 1.0 - smoothstep(DURATION * 0.65, DURATION, _age)
	if fade <= 0.0:
		return
	var cs := float(Consts.CELL_SIZE)

	# Two rings out of the crate's cell, half a cycle apart.
	for i in 2:
		var phase := fposmod(_age * 1.3 + i * 0.5, 1.0)
		var radius := lerpf(cs * 0.3, cs * 1.1, phase)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(RING_COLOR, (1.0 - phase) * 0.85 * fade), 3.0)

	# The triangle blinks for the first stretch — a flashing sign reads as an
	# alarm where a steady one reads as scenery — and then holds.
	var blink := 1.0 if _age > 1.0 or int(_age * 7.0) % 2 == 0 else 0.35
	var bob := sin(_age * 7.0) * 3.0
	var centre := Vector2(0.0, -cs * 0.78 + bob)
	var tri := PackedVector2Array([
		centre + Vector2(0.0, -22.0),
		centre + Vector2(26.0, 20.0),
		centre + Vector2(-26.0, 20.0),
	])
	draw_colored_polygon(tri, Color(WARNING_COLOR, fade * blink))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(WARNING_EDGE_COLOR, fade * blink), 3.0)
	# The exclamation mark: a bar and a dot, drawn rather than typed, so there is
	# no font in it to be missing a glyph.
	draw_rect(Rect2(centre + Vector2(-3.0, -8.0), Vector2(6.0, 16.0)), Color(WARNING_EDGE_COLOR, fade * blink))
	draw_circle(centre + Vector2(0.0, 13.0), 3.4, Color(WARNING_EDGE_COLOR, fade * blink))
