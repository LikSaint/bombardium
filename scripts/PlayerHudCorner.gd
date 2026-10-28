extends Control
## Always-visible per-player corner widget: character portrait + a row of
## stat icons with upgrade-level numbers. Dims when its player dies.
##
## It is also where a seat that somebody could take is advertised (see LateJoin): a
## free slot shows an empty panel, a bot's panel carries the same line, and both say
## "press any button" in a slow pulse. A person who has pressed a button and is
## choosing a seat lights up the one they are on.
##
## When a player dies, shows left/right arrows to cycle character selection
## (takes effect next round), as well as a hotkey hint. The round winner gets
## the same arrows on their own portrait during the post-round overlay (see
## begin_winner_repick, called from Main.gd) — one re-pick UI for both cases
## instead of a second one built out of a screen-center label.
##
## A bot re-picks too, through the same arrows and the same change path, so the
## portrait flicks through characters on screen the way a person's does: it waits a
## moment, chooses a character at random, and steps to it the short way round (see
## _bot_repick).

## When true, mirrors the internal layout so the portrait sits at the outer
## edge of the widget and the stats sit toward the screen center — used for
## HUD corners anchored to the right side of the screen.
@export var mirrored: bool = false

var player: Node = null
var character_id: int
var device_id: int
var can_change_character: bool = false
const CHARACTER_CHANGE_DELAY := 0.5
## A bot takes a beat before touching the arrows, then presses one every
## BOT_PICK_STEP seconds — about as fast as a person flicking through them.
const BOT_PICK_DELAY_MIN := 0.6
const BOT_PICK_DELAY_MAX := 1.6
const BOT_PICK_STEP := 0.18

var _bot_pick_timer: Timer = null
var _bot_pick_steps: int = 0
var _bot_pick_dir: int = 1

## True only for the round winner, only during the post-round overlay. Lets
## _input's arrow handling fire for a player who is still alive() — the death
## path below never sets this, since a dead player's own alive flag already
## takes care of it.
var repick_active: bool = false

var _portrait_rest_pos: Vector2
var _bounce_tween: Tween

func _ready() -> void:
	if mirrored:
		_apply_mirror()
	_setup_arrow_animations()
	_portrait_rest_pos = $Portrait.position
	Loc.language_changed.connect(_on_language_changed)

func _on_language_changed() -> void:
	_refresh_hint()
	_refresh_join_label()

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
	$Portrait.visible = true
	$Stats.visible = true
	set_join_state(JoinState.NONE)
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
	GameManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.player_reconnected.connect(_on_player_reconnected)
	_refresh()

## The pad is gone and a bot has the seat (see GameManager): the arrows and key hint a
## person had no longer apply, and a dead one starts picking a character for itself.
func _on_player_disconnected(player_id: int) -> void:
	if player == null or player_id != player.player_id:
		return
	device_id = Consts.DEVICE_BOT
	$ArrowLeft.visible = false
	$ArrowRight.visible = false
	$HotkeyHint.visible = false
	repick_active = false
	if not player.alive:
		_bot_repick()

func _on_player_reconnected(player_id: int, device: int) -> void:
	if player == null or player_id != player.player_id:
		return
	device_id = device
	# A person has just taken this seat over from a bot: the bot's own re-pick stops, and
	# a seat that was already dead hands them the arrows to pick a character with.
	_bot_pick_steps = 0
	if _bot_pick_timer != null:
		_bot_pick_timer.stop()
	set_join_state(JoinState.NONE)
	if not player.alive:
		_show_character_selection()
	_refresh_hint()

# --- Joining (see LateJoin) --------------------------------------------------

enum JoinState { NONE, PROMPT, SELECTED }
const JOIN_BLINK_RATE := 0.7 # cycles per second: slow enough to read as breathing
const JOIN_FRAME_COLOR := Color(1.0, 0.85, 0.3)
var _join_state: int = JoinState.NONE
var _join_confirm_text: String = ""
var _join_label: Label = null

## An empty seat: the panel with its portrait and numbers hidden, and nothing on it but
## the invitation to take it.
func show_empty_slot() -> void:
	if player != null:
		return
	visible = true
	modulate.a = 1.0
	$Portrait.visible = false
	$Stats.visible = false
	$ArrowLeft.visible = false
	$ArrowRight.visible = false
	$HotkeyHint.visible = false
	if _join_state == JoinState.NONE:
		set_join_state(JoinState.PROMPT)

## Takes the placeholder away again — when somebody else has filled the slot ahead of it.
func hide_empty_slot() -> void:
	if player != null:
		return
	set_join_state(JoinState.NONE)
	visible = false

## NONE: nothing to say. PROMPT: this seat can be taken. SELECTED: somebody is choosing
## it, and `confirm_text` is the button that seats them (a pad's A, a keyboard's Space).
func set_join_state(state: int, confirm_text: String = "") -> void:
	if state == _join_state and confirm_text == _join_confirm_text:
		return
	_join_state = state
	_join_confirm_text = confirm_text
	_refresh_join_label()
	queue_redraw()

func _refresh_join_label() -> void:
	if _join_state == JoinState.NONE:
		if _join_label != null:
			_join_label.visible = false
		return
	if _join_label == null:
		_join_label = Label.new()
		_join_label.add_theme_font_size_override("font_size", 13)
		_join_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_join_label.add_theme_constant_override("outline_size", 4)
		_join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_join_label.size = Vector2(custom_minimum_size.x, 20)
		add_child(_join_label)
	_join_label.visible = true
	# On an empty panel it sits in the middle; under a bot's numbers, along the bottom.
	_join_label.position = Vector2(0, 38 if player == null else 70)
	if _join_state == JoinState.SELECTED:
		_join_label.text = Loc.t("JOIN_CONFIRM", [_join_confirm_text])
		_join_label.add_theme_color_override("font_color", JOIN_FRAME_COLOR)
	else:
		_join_label.text = Loc.t("JOIN_PROMPT")
		_join_label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))

func _process(_delta: float) -> void:
	if _join_state == JoinState.NONE:
		return
	# Smooth, not blinking: a sine rather than an on/off, between "faint" and "full".
	var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * JOIN_BLINK_RATE)
	if _join_label != null:
		_join_label.modulate.a = 0.3 + 0.7 * breath
	if _join_state == JoinState.SELECTED:
		queue_redraw()

func _draw() -> void:
	if _join_state != JoinState.SELECTED:
		return
	var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * JOIN_BLINK_RATE)
	var rect := Rect2(Vector2(2, 2), custom_minimum_size - Vector2(4, 4))
	draw_rect(rect, Color(JOIN_FRAME_COLOR, 0.10 + 0.08 * breath), true)
	draw_rect(rect, Color(JOIN_FRAME_COLOR, 0.7 + 0.3 * breath), false, 3.0)

func _refresh() -> void:
	if player == null:
		return
	$Stats/Bomb/Count.text = str(player.bomb_level)
	$Stats/Radius/Count.text = str(player.radius_level)
	$Stats/Speed/Count.text = str(player.speed_level)
	$Stats/Shield/Count.text = str(player.shield_charges)

func _on_player_died(_id: int) -> void:
	modulate.a = 0.4
	if player == null:
		return
	if player.device_id == Consts.DEVICE_BOT:
		_bot_repick()
		return
	_show_character_selection()

## Called by Main.gd on the winning slot's corner once a round ends. Skipped
## by Main.gd itself for a disconnected pad (nobody to press the arrows), so this
## doesn't need to re-check that the way _on_player_died does for a human; a bot
## is handled here since its re-pick is its own thing.
func begin_winner_repick() -> void:
	repick_active = true
	if player != null and player.device_id == Consts.DEVICE_BOT:
		_bot_repick()
		return
	_show_character_selection()

## A bot's re-pick: the arrows appear (no key hint — a bot has no keys), and after
## a short pause it steps to a randomly chosen character one press at a time, the
## short way round the roster. Driven by a Timer child rather than awaits, so
## nothing is left running when the round reloads and frees this widget.
func _bot_repick() -> void:
	$ArrowLeft.visible = true
	$ArrowRight.visible = true
	_start_arrow_blink()
	var count := Consts.CHARACTER_COUNT
	var target := randi() % count
	var forward := posmod(target - character_id, count)
	_bot_pick_dir = 1 if forward <= count / 2 else -1
	_bot_pick_steps = forward if _bot_pick_dir == 1 else count - forward
	if _bot_pick_steps == 0:
		return # it rolled the character it already is
	if _bot_pick_timer == null:
		_bot_pick_timer = Timer.new()
		_bot_pick_timer.one_shot = true
		_bot_pick_timer.timeout.connect(_on_bot_pick_tick)
		add_child(_bot_pick_timer)
	_bot_pick_timer.start(randf_range(BOT_PICK_DELAY_MIN, BOT_PICK_DELAY_MAX))

func _on_bot_pick_tick() -> void:
	if _bot_pick_steps <= 0:
		return
	_change_character(_bot_pick_dir)
	_bot_pick_steps -= 1
	if _bot_pick_steps > 0:
		_bot_pick_timer.start(BOT_PICK_STEP)

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

## Always bounces relative to the fixed rest position captured at _ready(),
## never the portrait's current (possibly still mid-tween) position - reading
## the live position here let repeated quick presses re-anchor "rest" higher
## and higher each time, walking the portrait off-screen.
func _play_bounce_animation() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	var up: Vector2 = _portrait_rest_pos - Vector2(0, BOUNCE_DISTANCE)
	_bounce_tween = create_tween()
	_bounce_tween.tween_property($Portrait, "position", up, BOUNCE_DURATION * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property($Portrait, "position", _portrait_rest_pos, BOUNCE_DURATION * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _refresh_hint() -> void:
	$HotkeyHint.text = Loc.t("CYCLE_HINT", [Hints.label(device_id, Hints.Action.CYCLE)])

func _input(event: InputEvent) -> void:
	if player == null:
		return
	if player.alive and not repick_active:
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
	if dir == 0 or not can_change_character:
		return
	_change_character(dir)

## One press of an arrow, from a person or a bot: step the selection, record it for
## next round, and show it on the portrait.
func _change_character(dir: int) -> void:
	character_id = posmod(character_id + dir, Consts.CHARACTER_COUNT)
	GameManager.set_character_id(player.player_id, character_id)
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[(player.player_id - 1) % Consts.PLAYER_COLORS.size()])
	_play_bounce_animation()
