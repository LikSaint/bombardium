extends Node2D
## Fireworks over the match-over screen. It is the one thing a finished match has that a
## finished round doesn't: both put the winner's portrait up, and the only difference
## used to be the heading. Rockets go up from the bottom edge and burst in the upper
## half of the screen, for as long as the screen is up.
##
## Lives inside the results overlay, under the text, so the scores stay readable. The
## burst is one-shot square particles — no textures, the same blocky look as the rest.

const ROCKET_RISE_TIME := 0.5
const LAUNCH_GAP_MIN := 0.18
const LAUNCH_GAP_MAX := 0.55
const BURST_PARTICLES := 90
const BURST_LIFETIME := 1.4

## Where bursts go, as fractions of the screen: wide, and kept off the bottom where the
## winner's score lines are.
const BURST_X_RANGE := Vector2(0.08, 0.92)
const BURST_Y_RANGE := Vector2(0.1, 0.55)

const PALETTE: Array[Color] = [
	Color(1.0, 0.85, 0.2), Color(1.0, 0.35, 0.3), Color(0.35, 0.8, 1.0),
	Color(0.45, 1.0, 0.5), Color(1.0, 0.5, 0.85), Color(1.0, 1.0, 1.0),
]

var _area := Vector2(960.0, 720.0)
var _accent := Color.WHITE
var _next_launch := 0.0

## `area` is the size of the screen the fireworks fill; `accent` is the winner's colour,
## which about every other burst wears.
func start(area: Vector2, accent: Color) -> void:
	_area = area
	_accent = accent

func _process(delta: float) -> void:
	_next_launch -= delta
	if _next_launch > 0.0:
		return
	_next_launch = randf_range(LAUNCH_GAP_MIN, LAUNCH_GAP_MAX)
	var target := Vector2(
		_area.x * randf_range(BURST_X_RANGE.x, BURST_X_RANGE.y),
		_area.y * randf_range(BURST_Y_RANGE.x, BURST_Y_RANGE.y))
	var color: Color = _accent if randf() < 0.5 else PALETTE[randi() % PALETTE.size()]
	_launch(Vector2(target.x + randf_range(-40.0, 40.0), _area.y), target, color)

func _launch(from: Vector2, target: Vector2, color: Color) -> void:
	var rocket := ColorRect.new()
	rocket.size = Vector2(4.0, 10.0)
	rocket.color = color.lerp(Color.WHITE, 0.5)
	rocket.position = from
	add_child(rocket)
	var tw := create_tween()
	tw.tween_property(rocket, "position", target, ROCKET_RISE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		rocket.queue_free()
		_burst(target, color))

func _burst(at: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.emitting = true
	p.amount = BURST_PARTICLES
	p.lifetime = BURST_LIFETIME
	p.explosiveness = 1.0
	p.spread = 180.0
	# Speeds close together make a ring rather than a cloud; damping pulls it in
	# and gravity lets it sag, which is what a burst does.
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 190.0
	p.damping_min = 70.0
	p.damping_max = 90.0
	p.gravity = Vector2(0.0, 110.0)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.0
	p.color = color
	# Holds its colour for most of its life, then fades out.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	p.color_ramp = fade
	p.finished.connect(p.queue_free)
	add_child(p)
