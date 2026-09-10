extends Node2D
## Sits on the ground where a destroyed block was, until a player walks over it
## (Arena.try_collect_powerup). Never destroyed by explosions.

const TARGET_SIZE := 40.0 # icons are different native pixel sizes; normalize the on-screen size

## Plain white and faint by default (see Powerup.tscn) — reads as ambient
## glow, not a signal. A cursed pickup is the same icon and the same bob, with
## no other tell: this is on purpose, not a placeholder. It's easy to miss
## mid-fight or from across the arena, which is the whole risk of it — an
## attentive player can skip a pickup that looks off; an inattentive one pays
## for grabbing it (see Player.apply_curse).
const CURSED_GLOW_COLOR := Color(1.0, 0.15, 0.15, 0.4)

var type: int = Consts.PowerupType.BOMB_COUNT
var is_cursed: bool = false

func _ready() -> void:
	var texture: Texture2D = Consts.STAT_ICONS[type]
	$Icon.texture = texture
	var native_size: float = max(texture.get_width(), texture.get_height())
	var s: float = TARGET_SIZE / native_size
	$Icon.scale = Vector2(s, s)
	if is_cursed:
		$Glow.color = CURSED_GLOW_COLOR
	var base_y := position.y
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", base_y - 5, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "position:y", base_y, 0.5).set_trans(Tween.TRANS_SINE)
