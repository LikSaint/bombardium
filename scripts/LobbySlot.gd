extends Control
## One player slot in the Lobby: a "+" placeholder until a device joins,
## then that device's chosen character portrait (tinted to their team color)
## + blinking left/right arrows (hinting the character can still be cycled)
## + a checkmark once ready, plus the character's name and ability blurb.

var _is_empty: bool = true
var _player_index: int
var _character_id: int
var _is_ready: bool
var _is_bot: bool
var _device_id: int

func _ready() -> void:
	var blink := create_tween().set_loops()
	blink.tween_property($ArrowLeft, "modulate:a", 0.25, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 0.25, 0.5)
	blink.tween_property($ArrowLeft, "modulate:a", 1.0, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 1.0, 0.5)
	var ready_blink := create_tween().set_loops()
	ready_blink.tween_property($ReadyHint, "modulate:a", 0.2, 0.5)
	ready_blink.tween_property($ReadyHint, "modulate:a", 1.0, 0.5)
	Loc.language_changed.connect(_on_language_changed)

func _on_language_changed() -> void:
	if not _is_empty:
		show_joined(_player_index, _character_id, _is_ready, _is_bot, _device_id)

func show_empty() -> void:
	_is_empty = true
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
	$ReadyHint.visible = false

func show_joined(player_index: int, character_id: int, is_ready: bool, is_bot: bool = false, device_id: int = -1) -> void:
	_is_empty = false
	_player_index = player_index
	_character_id = character_id
	_is_ready = is_ready
	_is_bot = is_bot
	_device_id = device_id
	$Frame.color = Color(0.12, 0.12, 0.15, 1)
	$Portrait.visible = true
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[player_index % Consts.PLAYER_COLORS.size()])
	$PlusV.visible = false
	$PlusH.visible = false
	$Check.visible = is_ready
	$ArrowLeft.visible = not is_ready and not is_bot
	$ArrowRight.visible = not is_ready and not is_bot
	$BotBadge.visible = is_bot
	$BotBadge.text = Loc.t("BOT_BADGE")
	$NameLabel.visible = true
	$NameLabel.text = Consts.character_name(character_id)
	_show_character_stats(character_id)
	$AbilityLabel.visible = true
	$AbilityLabel.text = Consts.character_ability_desc(character_id, device_id)
	$ReadyLabel.visible = is_ready
	$ReadyLabel.text = Loc.t("READY")
	$ReadyHint.visible = not is_ready and not is_bot
	$ReadyHint.text = Loc.t("SLOT_READY_HINT", [Hints.label(device_id, Hints.Action.JOIN)])

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
