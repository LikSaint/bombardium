extends Control
## Always-visible per-player corner widget: character portrait + a row of
## stat icons with upgrade-level numbers. Dims when its player dies.
##
## Also shows a small "reconnect" badge over the portrait when this player's
## controller drops mid-round — otherwise a disconnected player's character
## just silently stops responding with no on-screen explanation.
##
## When a player dies, shows left/right arrows to cycle character selection
## (takes effect next round), as well as a hotkey hint.

## When true, mirrors the internal layout so the portrait sits at the outer
## edge of the widget and the stats sit toward the screen center — used for
## HUD corners anchored to the right side of the screen.
@export var mirrored: bool = false

var player: Node = null
var offline_label: Label
var character_id: int
var device_id: int
var is_disconnected: bool = false
var can_change_character: bool = false
const CHARACTER_CHANGE_DELAY := 0.5

func _ready() -> void:
	if mirrored:
		_apply_mirror()
	_setup_arrow_animations()
	Loc.language_changed.connect(_on_language_changed)

func _on_language_changed() -> void:
	if offline_label != null:
		offline_label.text = Loc.t("OFFLINE_BADGE")
	_refresh_hint()

func _apply_mirror() -> void:
	var w: float = custom_minimum_size.x
	$Portrait.position.x = w - $Portrait.position.x
	var stats: Control = $Stats
	var new_left: float = w - stats.offset_right
	var new_right: float = w - stats.offset_left
	stats.offset_left = new_left
	stats.offset_right = new_right
	var left_arrow: Polygon2D = $ArrowLeft
	var right_arrow: Polygon2D = $ArrowRight
	left_arrow.position.x = w - left_arrow.position.x
	right_arrow.position.x = w - right_arrow.position.x

func _setup_arrow_animations() -> void:
	pass

func bind(p: Node) -> void:
	player = p
	visible = true
	modulate.a = 1.0
	character_id = p.character_id
	device_id = p.device_id
	$ArrowLeft.visible = false
	$ArrowRight.visible = false
	$HotkeyHint.visible = false
	$Portrait.set_character(p.character_id, Consts.PLAYER_COLORS[(p.player_id - 1) % Consts.PLAYER_COLORS.size()])
	$Stats/Bomb/Icon.texture = Consts.STAT_ICONS[Consts.PowerupType.BOMB_COUNT]
	$Stats/Radius/Icon.texture = Consts.STAT_ICONS[Consts.PowerupType.RADIUS]
	$Stats/Speed/Icon.texture = Consts.STAT_ICONS[Consts.PowerupType.SPEED]
	$Stats/Shield/Icon.texture = Consts.STAT_ICONS[Consts.PowerupType.SHIELD]
	p.stats_changed.connect(_refresh)
	p.died.connect(_on_player_died)
	_ensure_offline_label()
	GameManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.player_reconnected.connect(_on_player_reconnected)
	_refresh()

func _ensure_offline_label() -> void:
	if offline_label != null:
		return
	offline_label = Label.new()
	offline_label.text = Loc.t("OFFLINE_BADGE")
	offline_label.add_theme_font_size_override("font_size", 12)
	offline_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	var badge_x: float = (custom_minimum_size.x - 72.0) if mirrored else 0.0
	offline_label.position = Vector2(badge_x, 46)
	offline_label.size = Vector2(72, 20)
	offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offline_label.visible = false
	add_child(offline_label)

func _on_player_disconnected(player_id: int) -> void:
	if player == null or player_id != player.player_id:
		return
	offline_label.visible = true
	is_disconnected = true
	_refresh_hint()

func _on_player_reconnected(player_id: int, device: int) -> void:
	if player == null or player_id != player.player_id:
		return
	offline_label.visible = false
	device_id = device
	is_disconnected = false
	_refresh_hint()

func _refresh() -> void:
	if player == null:
		return
	$Stats/Bomb/Count.text = str(player.bomb_level)
	$Stats/Radius/Count.text = str(player.radius_level)
	$Stats/Speed/Count.text = str(player.speed_level)
	$Stats/Shield/Count.text = str(player.shield_charges)

func _on_player_died(_id: int) -> void:
	modulate.a = 0.4
	if player == null or player.device_id == Consts.DEVICE_BOT:
		return
	_show_character_selection()

func _show_character_selection() -> void:
	$ArrowLeft.visible = true
	$ArrowRight.visible = true
	$HotkeyHint.visible = true
	_refresh_hint()
	_start_arrow_blink()
	can_change_character = false
	get_tree().create_timer(CHARACTER_CHANGE_DELAY).timeout.connect(func(): can_change_character = true)

func _start_arrow_blink() -> void:
	var blink := create_tween().set_loops()
	blink.tween_property($ArrowLeft, "modulate:a", 0.25, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 0.25, 0.5)
	blink.tween_property($ArrowLeft, "modulate:a", 1.0, 0.5)
	blink.parallel().tween_property($ArrowRight, "modulate:a", 1.0, 0.5)

const BOUNCE_DISTANCE := 8.0
const BOUNCE_DURATION := 0.25

func _play_bounce_animation() -> void:
	var rest: Vector2 = $Portrait.position
	var up: Vector2 = rest - Vector2(0, BOUNCE_DISTANCE)
	var tw := create_tween()
	tw.tween_property($Portrait, "position", up, BOUNCE_DURATION * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property($Portrait, "position", rest, BOUNCE_DURATION * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _refresh_hint() -> void:
	if is_disconnected:
		$HotkeyHint.text = Loc.t("DISCONNECTED_HINT")
	else:
		$HotkeyHint.text = Loc.t("CYCLE_HINT", [Hints.label(device_id, Hints.Action.CYCLE)])

func _input(event: InputEvent) -> void:
	if player == null or player.alive:
		return
	var dir := 0
	if device_id == -1:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_A:
				dir = -1
			elif event.keycode == KEY_D:
				dir = 1
	else:
		if event is InputEventJoypadButton and event.device == device_id and event.pressed:
			if event.button_index == JOY_BUTTON_DPAD_LEFT:
				dir = -1
			elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
				dir = 1
	if dir == 0 or is_disconnected or not can_change_character:
		return
	character_id = posmod(character_id + dir, Consts.CHARACTER_COUNT)
	GameManager.set_character_id(player.player_id, character_id)
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[(player.player_id - 1) % Consts.PLAYER_COLORS.size()])
	_play_bounce_animation()
