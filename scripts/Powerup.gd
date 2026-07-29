extends Node2D
## Sits on the ground where a destroyed block was, until a player walks over it
## (Arena.try_collect_powerup). Never destroyed by explosions.

const TARGET_SIZE := 40.0 # icons are different native pixel sizes; normalize the on-screen size

var type: int = Consts.PowerupType.BOMB_COUNT

func _ready() -> void:
	var texture: Texture2D = Consts.STAT_ICONS[type]
	$Icon.texture = texture
	var native_size: float = max(texture.get_width(), texture.get_height())
	var s: float = TARGET_SIZE / native_size
	$Icon.scale = Vector2(s, s)
	var base_y := position.y
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", base_y - 5, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "position:y", base_y, 0.5).set_trans(Tween.TRANS_SINE)
