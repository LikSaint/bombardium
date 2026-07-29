extends Node2D
## PixelLab-generated character art: one real sprite per direction
## (south/north/east/west), no mirroring or fake poses needed. Team color is
## applied by assets/shaders/team_tint.gdshader, which recolors only the
## low-saturation jumpsuit fabric to a vivid team color (hue+saturation
## replaced, original brightness kept) — skin/hair/colored accessories
## already have their own saturation and are left alone.
## Used by the in-game Player, HUD corners, the post-death picker, the
## Lobby, and PauseMenu's title.
##
## While moving, cycles the 6-frame PixelLab "walk" animation for the current
## direction (Consts.CHARACTER_WALK_FRAMES); standing still shows the static
## idle sprite (Consts.CHARACTER_SPRITES). Only Player calls set_walking() —
## HUD/Lobby/etc. portraits just sit on the idle frame.

const WALK_FRAME_COUNT := 6

var character_id: int = 0
var current_dir: String = "south"
var is_walking: bool = false
var walk_frame_index: int = 0
var walk_frame_duration: float = 0.1
var walk_elapsed: float = 0.0

func _ready() -> void:
	$Sprite.material = $Sprite.material.duplicate() # each portrait needs its own team color

func set_character(char_id: int, team_color: Color) -> void:
	character_id = char_id
	$Sprite.material.set_shader_parameter("team_color", team_color)
	_apply_frame()

## dir is a 4-directional Vector2i (one axis non-zero, or zero to leave as-is).
func face(dir: Vector2i) -> void:
	var new_dir: String = current_dir
	if dir.x > 0:
		new_dir = "east"
	elif dir.x < 0:
		new_dir = "west"
	elif dir.y < 0:
		new_dir = "north"
	elif dir.y > 0:
		new_dir = "south"
	if new_dir != current_dir:
		current_dir = new_dir
		_apply_frame()

## duration is how long ONE full move (one grid cell) takes — the walk cycle
## is paced to match it, so faster characters visibly step faster.
func set_walking(walking: bool, duration: float = 0.5) -> void:
	is_walking = walking
	if walking:
		walk_frame_duration = duration / WALK_FRAME_COUNT
		walk_elapsed = 0.0
		walk_frame_index = 0
	_apply_frame()

func _process(delta: float) -> void:
	if not is_walking:
		return
	walk_elapsed += delta
	if walk_elapsed >= walk_frame_duration:
		walk_elapsed = 0.0
		walk_frame_index = (walk_frame_index + 1) % WALK_FRAME_COUNT
		_apply_frame()

func _apply_frame() -> void:
	if is_walking:
		$Sprite.texture = Consts.CHARACTER_WALK_FRAMES[character_id][current_dir][walk_frame_index]
	else:
		$Sprite.texture = Consts.CHARACTER_SPRITES[character_id][current_dir]
