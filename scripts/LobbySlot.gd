extends Control
## One player slot in the Lobby: a "+" placeholder until a device joins,
## then that device's chosen character portrait (tinted to their team color)
## + blinking left/right arrows (hinting the character can still be cycled)
## + a checkmark once ready, plus the character's name and ability blurb.

func _ready() -> void:
	var blink := create_tween().set_loops()
	blink.tween_property($ArrowLeft, "modulate:a", 0.25, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 0.25, 0.5)
	blink.tween_property($ArrowLeft, "modulate:a", 1.0, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 1.0, 0.5)

func show_empty() -> void:
	$Frame.color = Color(0.18, 0.18, 0.22, 1)
	$Portrait.visible = false
	$PlusV.visible = true
	$PlusH.visible = true
	$Check.visible = false
	$ArrowLeft.visible = false
	$ArrowRight.visible = false
	$BotBadge.visible = false
	$NameLabel.visible = false
	$Stats.visible = false
	$AbilityLabel.visible = false
	$ReadyLabel.visible = false

func show_joined(player_index: int, character_id: int, is_ready: bool, is_bot: bool = false) -> void:
	$Frame.color = Color(0.12, 0.12, 0.15, 1)
	$Portrait.visible = true
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[player_index % Consts.PLAYER_COLORS.size()])
	$PlusV.visible = false
	$PlusH.visible = false
	$Check.visible = is_ready
	$ArrowLeft.visible = not is_ready and not is_bot
	$ArrowRight.visible = not is_ready and not is_bot
	$BotBadge.visible = is_bot
	$NameLabel.visible = true
	$NameLabel.text = Consts.CHARACTER_NAMES[character_id]
	_show_character_stats(character_id)
	$AbilityLabel.visible = true
	$AbilityLabel.text = Consts.CHARACTER_ABILITY_DESC[character_id]
	$ReadyLabel.visible = is_ready

func _show_character_stats(character_id: int) -> void:
	var stats = Consts.get_character_stats(character_id)
	$Stats.visible = true
	$Stats/Bomb/BombIcon.texture = Consts.STAT_ICONS[Consts.PowerupType.BOMB_COUNT]
	$Stats/Bomb/BombCount.text = str(stats["bombs"])
	$Stats/Radius/RadiusIcon.texture = Consts.STAT_ICONS[Consts.PowerupType.RADIUS]
	$Stats/Radius/RadiusCount.text = str(stats["radius"])
	$Stats/Speed/SpeedIcon.texture = Consts.STAT_ICONS[Consts.PowerupType.SPEED]
	$Stats/Speed/SpeedCount.text = str(stats["speed"])
	$Stats/Shield/ShieldIcon.texture = Consts.STAT_ICONS[Consts.PowerupType.SHIELD]
	$Stats/Shield/ShieldCount.text = str(stats["shield"])
