extends Node2D
## "You are out of bombs" — shown over a character who tries to put down something that is
## limited by the bomb bonus and cannot: a bomb or a mine with no charge left, a grenade with
## no shell, a wall past the cap, a turret past its limit. A child of the Player (see
## Player._warn_limit).
##
## It is the bomb-bonus icon itself — the sprite as it appears in the HUD, not a stand-in —
## tinted **red**, **shaking**, **rising** off the character's head and **fading out** as it
## goes: enough movement to catch the eye in the middle of a fight, gone in under a second so it
## never sits on screen being a nag.
##
## The tint is a shader that mixes red into the sprite's own colours rather than painting it
## over. A plain multiply would leave a black bomb black, and a flat red fill would lose the
## sprite, so a share of the way to red is added and the highlights and the spark keep showing.

const DURATION := 0.9
const RISE := 36.0
const START_HEIGHT := -36.0       # just over the head, in the player's space
const SHAKE_AMPLITUDE := 4.5
const SHAKE_RATE := 70.0          # radians per second
const ICON_PIXELS := 26.0         # the longer side, on screen
const RED := Color(1.0, 0.18, 0.12)
## How far toward red the sprite's colours are pulled, 0 = untouched, 1 = a flat red fill.
const TINT_STRENGTH := 0.34

const SHADER_CODE := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.18, 0.12, 1.0);
uniform float strength = 0.34;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Toward red by `strength`, then a lift on the dark parts so the black body reads as dark
	// red rather than still black; the sprite's own light and dark detail is kept underneath.
	vec3 rgb = mix(c.rgb, tint.rgb, strength);
	rgb += tint.rgb * 0.12 * (1.0 - c.r);
	COLOR = vec4(clamp(rgb, 0.0, 1.0), c.a * COLOR.a);
}
"""

var _age: float = 0.0

func _ready() -> void:
	z_index = 30
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", RED)
	mat.set_shader_parameter("strength", TINT_STRENGTH)
	material = mat

## The same warning again: the icon starts over from the head rather than a second one being
## stacked on the first.
func restart() -> void:
	_age = 0.0

func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t := clampf(_age / DURATION, 0.0, 1.0)
	var icon: Texture2D = Consts.STAT_ICONS[Consts.PowerupType.BOMB_COUNT]
	var scale_to := ICON_PIXELS / maxf(icon.get_width(), icon.get_height())
	var size := icon.get_size() * scale_to
	# Rises fast and then eases off; the shake dies away a little as it goes.
	var y := START_HEIGHT - RISE * (1.0 - pow(1.0 - t, 2.0))
	var x := sin(_age * SHAKE_RATE) * SHAKE_AMPLITUDE * (1.0 - 0.5 * t)
	# Fully there for the first half, then gone.
	var alpha := 1.0 - smoothstep(0.5, 1.0, t)
	draw_texture_rect(icon, Rect2(Vector2(x, y) - size / 2.0, size), false, Color(1, 1, 1, alpha))
