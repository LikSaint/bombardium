extends CharacterBody2D
## Grid-based player. Movement is polled every physics frame; bomb/ability/
## pickup are edge-triggered via _input so each press fires exactly once.
##
## device_id == -1 means keyboard (WASD + Space/E/Q). device_id >= 0 reads
## that joypad's left stick + face buttons directly (no InputMap), which is
## how a single project supports up to 4 local gamepads by device index.
## device_id == Consts.DEVICE_BOT means AI-controlled: _bot_think() replaces
## both _poll_move_dir() and the bomb button, deciding a move direction and
## bombing decision every BOT_DECISION_INTERVAL via simple danger-avoidance +
## BFS pathing (flee live blasts, else grab a nearby powerup, else chase the
## nearest enemy/block, and drop a bomb only when a safe escape route from its
## own blast still exists).

const BombScene := preload("res://scenes/Bomb.tscn")
const ExplosionScript := preload("res://scripts/Explosion.gd")

enum CharacterId { BOMB_MASTER, SCOUT, ENGINEER, PYRO, BOMB_KICKER, MAGNET, MINER }

const MOVE_DEADZONE := 0.35

signal died(player_id: int)
signal stats_changed

@export var player_id: int = 1
@export var device_id: int = -1
@export var character_id: int = CharacterId.BOMB_MASTER

var arena: Node2D
var alive: bool = true
var facing_dir: Vector2i = Consts.DIR_DOWN

# Movement is free-form, not cell-to-cell: `position` is continuous and the
# grid only supplies collision. A direction change therefore takes effect the
# same frame it is pressed, even halfway between two cells — turning back
# without ever reaching the cell ahead is the normal case, not a special one.
# `move_speed` stays derived from move_duration so every existing speed
# upgrade (which scales move_duration) keeps working unchanged.
var move_speed: float = 0.0 # px/s, = CELL_SIZE / move_duration

# Hockey-Player passive: skating. Holding one direction without turning builds
# a charge that scales `move_speed` up to SPRINT_MAX_FACTOR, and any break in
# the run — turning, releasing, or hitting a wall — drops it back to zero at
# once. The payoff is deliberately gated behind a long straight line: it makes
# the character fast at crossing open corridors (running a kicked bomb down,
# escaping a blast lane) without touching the tight, cell-by-cell weaving
# where the rest of the roster is balanced.
const SPRINT_CHARGE_TIME := 0.8 # seconds of unbroken straight running to reach top speed
const SPRINT_MAX_FACTOR := 1.6
var _sprint_charge: float = 0.0
var _sprint_dir: Vector2i = Vector2i.ZERO

# Half-extent of the box tested against the grid. Smaller than the cell so a
# player lined up in a corridor never clips the walls flanking it.
const PLAYER_HALF_EXTENT := 20.0
const WALL_EPSILON := 0.01

# Bombs this player is currently standing on top of. A bomb is impassable to
# everyone, including whoever dropped it — but you have to be able to walk off
# the one under your feet, so it stays passable until you clear the cell.
var _bomb_grace: Dictionary = {} # Vector2i -> true
# Set while a tween owns `position` (Parkour hop, sudden-death shove); normal
# input-driven movement stands down so the two never fight over the transform.
var _scripted_move: bool = false

var is_bot: bool = false
const BOT_DECISION_INTERVAL := 0.6 # pause between bot decisions; higher = slower/calmer bots
const BOT_DECISION_JITTER := 0.15 # +/- random spread so bots don't all tick in lockstep
var bot_decision_timer: float = 0.0
var bot_move_dir: Vector2i = Vector2i.ZERO
var bot_target_cell: Vector2i = Vector2i.ZERO
var bot_hold_time: float = 0.0
const BOT_HOLD_TIMEOUT_FACTOR := 2.5 # give up on an unreachable target after this many step-times
# While actively escaping a blast, decisions run every frame (no throttle) —
# only casual wandering/bombing-consideration is paced by BOT_DECISION_INTERVAL.
# Escape timing in _bot_should_bomb() assumes this, so don't throttle fleeing.
var is_fleeing: bool = false
const BOT_POWERUP_CHASE_MAX_STEPS := 8 # further than this, a pickup isn't worth abandoning the hunt for
const BOMB_FUSE_DURATION := 2.0 # must match Bomb.tscn's Timer wait_time
const BOMB_ESCAPE_SAFETY_MARGIN := 0.4 # buffer so a bomb is never a photo finish

# --- Bot character play ----------------------------------------------------
# Everything above is character-blind: it walks, it bombs, it runs away. These
# tune the parts that are specific to one character's kit, because a bot that
# never presses its own ability button is a bot playing a stat block rather
# than a character — and with the Sapper's trigger and the Engineer's walls
# doing most of their work, that gap now decides matches.
const BOT_WALL_ENEMY_RANGE := 5 # steps to the nearest enemy; further and a wall is just litter
const BOT_WALL_MAX_OPEN_NEIGHBOURS := 2 # only wall a chokepoint — on open ground a wall is walked around
const BOT_KICK_MAX_LANE := 10 # cells of slide worth scanning for a target
const BOT_KICK_MIN_LANE := 2 # a shove that moves the bomb one cell hasn't got it off us
const BOT_KICK_MIN_FUSE := 0.6 # seconds; below this the bomb goes off mid-shove

var move_duration: float = 0.3
var bomb_count_max: int = 1
var bomb_count_current: int = 1
var bomb_radius: int = 1
var shield_charges: int = 0

func get_current_cell() -> Vector2i:
	return arena.world_to_cell(position)

func _update_move_speed() -> void:
	if move_duration > 0.0:
		move_speed = Consts.CELL_SIZE / move_duration

# Upgrade levels shown on the HUD (0 = base, unrelated to the raw stat values above).
var bomb_level: int = 0
var radius_level: int = 0
var speed_level: int = 0

var ability_cooldown: float = 0.2
var ability_on_cooldown: bool = false

# Powerup weight distribution: [BOMB_COUNT, RADIUS, SPEED, SHIELD]
# Default [1,1,1,1], modified by character type
var powerup_weights: Array[int] = [1, 1, 1, 1]
# Multiplier for total powerup spawn chance
var powerup_chance_multiplier: float = 1.0

# Parkour: jumping a wooden block requires pressing the same direction
# twice within this window (not a dedicated ability button).
const DOUBLE_TAP_WINDOW := 0.35
var _prev_held_dirs: Dictionary = {} # Vector2i -> bool, last frame's raw held state
var _last_dir_press_time: Dictionary = {} # Vector2i -> float (Time.get_ticks_msec()/1000.0)

# Engineer: temp walls this player currently has active, capped by bomb_count_max.
var active_temp_walls: Array = []

# Bombs this player has out and still ticking. Everyone maintains it (it's how
# a bomb charge is handed back), but only the Sapper's trigger reads it.
var live_bombs: Array = []

func _ready() -> void:
	is_bot = device_id == Consts.DEVICE_BOT
	add_to_group("players")
	GameManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.player_reconnected.connect(_on_player_reconnected)
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[(player_id - 1) % Consts.PLAYER_COLORS.size()])
	_apply_character_passives()
	_update_move_speed()

## Every character biases the powerups dropped by the blocks *they* destroy
## toward the stat their kit actually scales on (see Arena._pick_powerup_by_weights).
## The weights only redistribute a fixed drop chance between the four types —
## the total stays the map setting — so a bias costs nothing to hand out and
## gives each character a direction to grow in rather than a random walk.
## Pyro's `powerup_chance_multiplier` is the one exception: it raises the total,
## and it stays Pyro's alone.
func _apply_character_passives() -> void:
	match character_id:
		CharacterId.BOMB_MASTER:
			bomb_radius += 1
			bomb_count_max += 1
			bomb_count_current = bomb_count_max
			bomb_level += 1
			radius_level += 1
			shield_charges += 1
			# BOMB_COUNT: the trigger sets off every bomb at once, so bombs are
			# what scales the Sapper — three at a time is a shaped minefield,
			# one is just a bomb with better timing.
			powerup_weights = [3, 1, 1, 1]
		CharacterId.SCOUT:
			# 0.8 rather than 0.9: at one 10% step the Parkour Runner was simply a worse
			# Hockey Player (same speed, no shield, no kick), and the hop alone
			# didn't cover the gap. Speed is the whole identity, so it's the
			# thing to lean into.
			move_duration *= 0.8
			speed_level += 2
			shield_charges += 1
			powerup_weights = [1, 1, 3, 1]  # SPEED
		CharacterId.ENGINEER:
			# The wall cap is the bomb count (see _ability_temp_wall), so the
			# extra bomb is also an extra wall — and it's what makes the
			# Engineer's actual combo (bomb an opponent, wall off their escape)
			# possible at all, which a single bomb never was.
			bomb_count_max += 1
			bomb_count_current = bomb_count_max
			bomb_level += 1
			powerup_weights = [3, 1, 1, 1]  # BOMB_COUNT — every bomb is another wall
		CharacterId.PYRO:
			shield_charges += 1
			# RADIUS: the diamond blast grows as an area, not as four arms, so a
			# radius step is worth several times what it is to anyone else —
			# radius is the Pyro's power stat and the weights should say so.
			powerup_weights = [1, 3, 1, 1]
			powerup_chance_multiplier = 1.5  # 50% more total powerup chance
		CharacterId.BOMB_KICKER:
			move_duration *= 0.9
			speed_level += 1
			shield_charges += 1
			powerup_weights = [3, 1, 1, 1]  # BOMB_COUNT — more bombs, more pucks
		CharacterId.MAGNET:
			# No radius bonus: a blast that walks itself onto the target doesn't
			# need to be big. The second bomb is what the kit actually runs on —
			# one crawling bomb is a threat to walk around, two closing from
			# different sides are what takes a cell away from someone. The shield
			# is the concession to the Magnet living inside their own minefield:
			# their bombs move, so unlike everyone else they can be caught out by
			# ammunition they placed somewhere that was safe at the time.
			bomb_count_max += 1
			bomb_count_current = bomb_count_max
			bomb_level += 1
			shield_charges += 1
			powerup_weights = [3, 1, 1, 1]  # BOMB_COUNT — every bomb is another hunter
		CharacterId.MINER:
			# The extra charge is what makes the character playable at all: mines
			# and bombs share one pool, so at a single charge every mine planted
			# is a round spent unable to break a crate or answer anyone.
			bomb_count_max += 1
			bomb_count_current = bomb_count_max
			bomb_level += 1
			# RADIUS, where everyone else with a trap-shaped kit takes BOMB_COUNT.
			# Mines explode at half radius rounded down, so a radius step is the
			# only thing that lifts them out of covering barely their own cell —
			# and it is worth double to the Miner, whose ordinary bombs grow too.
			powerup_weights = [1, 3, 1, 1]
	stats_changed.emit()

## GameManager owns the slot->device bookkeeping, but the live character in the
## arena has its own copy of device_id from spawn time, and nothing used to
## update it. A pad that came back under a *different* device index (SDL hands
## out a fresh one on re-plug more often than not) therefore reconnected on
## paper — slot updated, "ОТКЛЮЧЕН" badge cleared — while the character kept
## listening to the index that no longer existed, and stayed dead to input
## until the next round respawned it. It only ever appeared to work when the
## pad happened to be handed back the same index.
func _on_player_reconnected(p_id: int, device: int) -> void:
	if p_id != player_id:
		return
	device_id = device

## Also drop the old index on disconnect, rather than keeping it: another pad
## plugged in afterwards can be handed that very index, and would then drive
## this orphaned character without ever claiming it.
func _on_player_disconnected(p_id: int) -> void:
	if p_id != player_id:
		return
	device_id = Consts.DEVICE_NONE

func _is_disconnected() -> bool:
	return device_id == Consts.DEVICE_NONE

func _input(event: InputEvent) -> void:
	if not alive or _is_disconnected():
		return
	if device_id == -1:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_SPACE:
					place_bomb()
				KEY_E:
					use_ability()
				KEY_Q:
					pickup_weapon()
	else:
		# Which physical button each of these is depends on the pad — see the
		# face-button notes in PadInput.gd. A pad that reports its bottom button
		# as JOY_BUTTON_B still gets the bomb on the button the player actually
		# presses, because Pad learned it from their confirm press in the menus.
		if event is InputEventJoypadButton and event.device == device_id and event.pressed:
			var button: int = event.button_index
			if button == Pad.primary_button(device_id):
				place_bomb()
			elif button == Pad.ability_button(device_id):
				use_ability()
			elif button == Pad.pickup_button(device_id):
				pickup_weapon()

func _physics_process(delta: float) -> void:
	if not alive or arena == null:
		return
	if _scripted_move:
		return

	var dir := _bot_update(delta) if is_bot else _poll_move_dir()

	if dir != Vector2i.ZERO:
		facing_dir = dir
		$Portrait.face(dir)

	if not is_bot and character_id == CharacterId.SCOUT:
		_update_jump_double_tap()

	_release_cleared_bombs()

	# Something solid arrived on top of the player rather than the other way
	# round. Nothing they press can help until they're back on open ground, so
	# that takes priority over input for as long as it lasts.
	if not _can_stand_at(position):
		_unstick(delta)
		return

	_update_sprint(dir, delta)

	if dir != Vector2i.ZERO:
		_move_free(dir, delta)
		# Paced by the *effective* duration, so a sprint reads on the sprite
		# (legs cycling faster) and not just on the distance covered.
		$Portrait.set_walking(true, move_duration / _sprint_factor())
	else:
		$Portrait.set_walking(false)

	# Pickup is driven by where the player's centre is, so it fires as soon as
	# they're properly on the cell rather than on a step boundary that no
	# longer exists.
	arena.try_collect_powerup(get_current_cell(), self)

## Straight-line charge, for whoever has the skating passive. Standing still or
## turning is a full reset rather than a decay: the mechanic is meant to be read
## off the screen ("they've been running that lane for a while, they're fast
## now"), and a hidden lingering charge would make the same input produce
## different speeds for no visible reason.
func _update_sprint(dir: Vector2i, delta: float) -> void:
	if character_id != CharacterId.BOMB_KICKER:
		return
	if dir == Vector2i.ZERO or dir != _sprint_dir:
		_sprint_dir = dir
		_sprint_charge = 0.0
		return
	_sprint_charge = minf(_sprint_charge + delta, SPRINT_CHARGE_TIME)

func _sprint_factor() -> float:
	if _sprint_charge <= 0.0:
		return 1.0
	return lerpf(1.0, SPRINT_MAX_FACTOR, _sprint_charge / SPRINT_CHARGE_TIME)

func _poll_move_dir() -> Vector2i:
	var x := 0.0
	var y := 0.0
	if _is_disconnected():
		return Vector2i.ZERO
	if device_id == -1:
		if Input.is_key_pressed(KEY_A):
			x -= 1
		if Input.is_key_pressed(KEY_D):
			x += 1
		if Input.is_key_pressed(KEY_W):
			y -= 1
		if Input.is_key_pressed(KEY_S):
			y += 1
	else:
		var stick := _joy_vector()
		x = stick.x
		y = stick.y

	if abs(x) > abs(y):
		if x > MOVE_DEADZONE:
			return Consts.DIR_RIGHT
		elif x < -MOVE_DEADZONE:
			return Consts.DIR_LEFT
	else:
		if y > MOVE_DEADZONE:
			return Consts.DIR_DOWN
		elif y < -MOVE_DEADZONE:
			return Consts.DIR_UP
	return Vector2i.ZERO

# Raw held state per cardinal direction, independent of the single resolved
# move direction above — needed so double-tap detection sees every direction
# key/axis edge, not just whichever axis currently wins the diagonal tie-break.
func _held_dirs() -> Dictionary:
	var held := {}
	if _is_disconnected():
		return held
	if device_id == -1:
		held[Consts.DIR_LEFT] = Input.is_key_pressed(KEY_A)
		held[Consts.DIR_RIGHT] = Input.is_key_pressed(KEY_D)
		held[Consts.DIR_UP] = Input.is_key_pressed(KEY_W)
		held[Consts.DIR_DOWN] = Input.is_key_pressed(KEY_S)
	else:
		var stick := _joy_vector()
		held[Consts.DIR_LEFT] = stick.x < -MOVE_DEADZONE
		held[Consts.DIR_RIGHT] = stick.x > MOVE_DEADZONE
		held[Consts.DIR_UP] = stick.y < -MOVE_DEADZONE
		held[Consts.DIR_DOWN] = stick.y > MOVE_DEADZONE
	return held

## Left stick plus D-pad, folded into one deflection vector. The D-pad counts
## because plenty of pads are usable only that way — a stick Godot has no
## mapping for can land on axis indices JOY_AXIS_LEFT_X/Y don't cover, and some
## pads have no usable stick at all. Pad's synthetic D-pad events (stick ->
## D-pad, for menus) push in the same direction the stick already reports here,
## so the two never fight.
func _joy_vector() -> Vector2:
	var v := Vector2(
		Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
	)
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_LEFT):
		v.x -= 1.0
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_RIGHT):
		v.x += 1.0
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_UP):
		v.y -= 1.0
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_DOWN):
		v.y += 1.0
	return v

## Parkour passive: pressing a direction twice quickly while a crate, a bomb,
## or a solid wall — indestructible stone included — sits directly ahead hops
## clean over it. Edge-tracking runs every frame (even mid-move) so timing
## isn't skewed by movement being busy; only the jump attempt itself is gated
## on not already moving.
func _update_jump_double_tap() -> void:
	var held := _held_dirs()
	var now := Time.get_ticks_msec() / 1000.0
	for d in held.keys():
		var is_down: bool = held[d]
		var was_down: bool = _prev_held_dirs.get(d, false)
		if is_down and not was_down:
			var last_t: float = _last_dir_press_time.get(d, -INF)
			if not _scripted_move and now - last_t <= DOUBLE_TAP_WINDOW:
				_try_jump_over_obstacle(d)
			_last_dir_press_time[d] = now
	_prev_held_dirs = held

func _try_jump_over_obstacle(dir: Vector2i) -> void:
	if _scripted_move or arena == null:
		return
	var current_cell := get_current_cell()
	var mid_cell := current_cell + dir
	var target_cell := current_cell + dir * 2
	# A temp wall only counts as a jumpable obstacle when it's blocking *this*
	# player — the owner already walks through it normally, no jump needed.
	var is_foreign_temp_wall: bool = arena.is_temp_wall(mid_cell) and not arena.is_walkable_for(mid_cell, self)
	# Permanent stone — the checkerboard/random indestructible walls, never
	# removable by any blast — is a jumpable obstacle too. This is what makes
	# the hop parkour rather than a crate-specific trick: it can cut through
	# the map's fixed layout, not just the destructible clutter on top of it.
	# The one thing it can never do is clear a *double*-thick wall or the
	# arena's outer ring, because those still fail the landing check below —
	# no separate case needed, the same two-cell hop that lands past a single
	# wall simply lands on more wall.
	var is_permanent_wall: bool = arena.is_wall(mid_cell) and not arena.is_temp_wall(mid_cell)
	if not arena.is_block(mid_cell) and not arena.has_bomb_at(mid_cell) and not is_foreign_temp_wall and not is_permanent_wall:
		return
	if not arena.is_walkable_for(target_cell, self):
		return
	facing_dir = dir
	$Portrait.face(dir)
	Sfx.play("jump")
	_scripted_move_to(arena.cell_to_world(target_cell), move_duration)

## Only actually moves once per decision (returns the chosen dir exactly the
## frame it's decided, Vector2i.ZERO every other frame) so the bot visibly
## stands still between steps instead of running in a straight line for the
## whole interval — that's what makes BOT_DECISION_INTERVAL read as "slower"
## rather than just "re-routes less often". Exception: while is_fleeing, the
## next decision is scheduled immediately (no throttle, no jitter) so the bot
## actually moves at full speed while escaping its own bomb — see the timing
## note on is_fleeing above.
func _bot_update(delta: float) -> Vector2i:
	bot_decision_timer -= delta

	# Checked every frame rather than on the decision tick, unlike everything
	# else the bot does: the window for a detonation is open only while an
	# enemy is actually standing in the blast, and someone walking through at
	# full tilt clears a cell in well under one BOT_DECISION_INTERVAL.
	if character_id == CharacterId.BOMB_MASTER:
		_bot_try_detonate()

	# A decision is a *cell* to walk to, but movement is now continuous, so the
	# heading has to be held until the bot actually arrives — returning it for
	# one frame like the old step-based version did would leave it twitching in
	# place. Arrival is "at or past the centre", so an overshoot still counts.
	if bot_move_dir != Vector2i.ZERO:
		bot_hold_time += delta
		var centre: Vector2 = arena.cell_to_world(bot_target_cell)
		var reached: bool = (centre - position).dot(Vector2(bot_move_dir)) <= 0.0
		# Safety valve: something blocked the way (a bomb slid in, a wall
		# dropped) and the target is unreachable — re-decide instead of
		# pushing into it forever.
		if reached or bot_hold_time > move_duration * BOT_HOLD_TIMEOUT_FACTOR:
			bot_move_dir = Vector2i.ZERO
			bot_hold_time = 0.0
		else:
			return bot_move_dir

	if bot_decision_timer <= 0.0:
		_bot_think()
		bot_decision_timer = 0.0 if is_fleeing else BOT_DECISION_INTERVAL + randf_range(-BOT_DECISION_JITTER, BOT_DECISION_JITTER)
		if bot_move_dir != Vector2i.ZERO:
			bot_target_cell = get_current_cell() + bot_move_dir
			bot_hold_time = 0.0
		return bot_move_dir
	return Vector2i.ZERO

func _bot_think() -> void:
	if arena == null:
		return
	var current_cell := get_current_cell()
	var danger := _compute_danger_cells()
	var hazard := _compute_active_hazard_cells()
	if danger.has(current_cell) or hazard.has(current_cell):
		is_fleeing = true
		# Two characters have a better answer to a live blast than running,
		# and both are only available *here* — by the time the generic flee
		# has picked a direction, the chance to use them is gone.
		if _bot_try_character_escape(danger, hazard):
			return
		_bot_flee(danger, hazard)
		return
	is_fleeing = false
	# Terrain first: a wall costs the Engineer nothing to place (they walk
	# through their own), so it's never worth giving up a turn for, and it
	# leaves the bot free to bomb or wander in the same decision.
	if character_id == CharacterId.ENGINEER:
		_bot_try_wall(danger)
	if bomb_count_current > 0 and not arena.has_bomb_at(current_cell) and _bot_should_bomb(danger, hazard):
		place_bomb()
		is_fleeing = true
		_bot_flee(_compute_danger_cells(), _compute_active_hazard_cells())
		return
	_bot_wander(danger, hazard)

## Character-specific ways out of a blast, tried before the generic flee.
## Returns true when one was taken (and has set the bot's heading itself).
func _bot_try_character_escape(danger: Dictionary, hazard: Dictionary) -> bool:
	match character_id:
		CharacterId.SCOUT:
			# The hop clears two cells in one move and goes over the crate
			# that's penning the Parkour Runner in, which is regularly the only way
			# out of a dead end and always the quickest one.
			return _bot_try_escape_jump(danger, hazard)
		CharacterId.BOMB_KICKER:
			# Push the threat away instead of outrunning it — and aim it at
			# someone on the way out if a lane happens to point at them.
			#
			# This is the *only* point in the decision where a bot can ever
			# kick, and not by preference: a bomb on the neighbouring cell
			# always covers this one (nothing can block a blast one cell from
			# its source), so being next to a kickable bomb and being in
			# danger are the same state. Checking for kicks anywhere below
			# this branch would be checking a condition that is never true.
			var kick := _bot_kick_dir()
			if kick != Vector2i.ZERO:
				bot_move_dir = kick
				return true
	return false

func _blast_cells_for(cell: Vector2i, radius: int, is_circle: bool) -> Dictionary:
	var cells := {cell: true}
	if is_circle:
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) + abs(dy) > radius:
					continue
				var c: Vector2i = cell + Vector2i(dx, dy)
				if arena.in_bounds(c) and not arena.is_wall(c):
					cells[c] = true
	else:
		for dir in Consts.DIRECTIONS:
			for i in range(1, radius + 1):
				var c: Vector2i = cell + dir * i
				if not arena.in_bounds(c) or arena.is_wall(c):
					break
				cells[c] = true
				if arena.is_block(c):
					break
	return cells

## Cells inside a live (not yet exploded) bomb's blast footprint. These are
## a *future* threat — the multi-second fuse means walking through one while
## fleeing is fine, only ending up standing there when it goes off is not.
func _compute_danger_cells() -> Dictionary:
	var danger := {}
	for bomb_cell in arena.bombs_by_cell.keys():
		var bomb = arena.bombs_by_cell[bomb_cell]
		for c in _blast_cells_for(bomb_cell, bomb.radius, bomb.is_circle_blast):
			danger[c] = true
	return danger

## Cells covered by a currently-live Explosion node — lethal *right now*, on
## contact, not a future threat. A bomb's entry disappears from
## bombs_by_cell the instant it detonates, but the Explosion hazard it
## spawns lingers for ~0.3s after (see Explosion.gd); without tracking these
## separately, a bot would consider a just-detonated cell safe again
## immediately and could path straight back through the still-active blast
## as if it were a harmless future bomb (this was the actual cause of bots
## "blowing themselves up": fleeing bomb A successfully, then routing a
## second bomb's escape back through A's blast the instant A's
## bombs_by_cell entry vanished, while the killing explosion was still live).
## Unlike _compute_danger_cells(), these must never be a *transit* cell
## either — see the `avoid` param on _bfs_find().
func _compute_active_hazard_cells() -> Dictionary:
	var hazard := {}
	for child in arena.get_children():
		if child.get_script() == ExplosionScript:
			hazard[arena.world_to_cell(child.position)] = true
	return hazard

func _enemy_at(cell: Vector2i) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not p.alive:
			continue
		if p.get_current_cell() == cell:
			return p
	return null

func _alive_enemies() -> Array:
	var result: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.alive:
			result.append(p)
	return result

func _bot_should_bomb(danger: Dictionary, hazard: Dictionary) -> bool:
	var current_cell := get_current_cell()
	var own_blast := _blast_cells_for(current_cell, bomb_radius, character_id == CharacterId.PYRO)
	var targets_enemy := false
	var targets_block := false
	# Nothing stops two players sharing a cell (walkability ignores players), so
	# current_cell has to be scanned for enemies like any other blast cell — an
	# enemy standing right on top of the bot is its best shot, not a blind spot.
	# A block there is impossible, since blocks aren't walkable.
	for c in own_blast:
		if _enemy_at(c) != null:
			targets_enemy = true
		elif arena.is_block(c):
			targets_block = true
	if not targets_enemy and not targets_block:
		return false
	var combined_danger: Dictionary = danger.duplicate()
	for c in own_blast:
		combined_danger[c] = true
	for c in hazard:
		combined_danger[c] = true
	# Transit through the not-yet-detonated blast footprint is fine (the fuse
	# gives ~2s to walk clear) — only the final resting cell has to be safe,
	# so traversal isn't restricted to combined_danger, just the target check.
	# Active hazard cells are the exception: those are hard-blocked even in
	# transit via the `avoid` param, since they're lethal immediately.
	var escape := _bfs_find(current_cell, func(c): return not combined_danger.has(c), hazard)
	if escape.is_empty():
		return false
	# A path existing isn't enough — it has to be walkable before the fuse
	# goes off. Once fleeing starts it's one step per move_duration with no
	# pause (is_fleeing above), so that's the true per-step cost to budget.
	var steps := escape.size() - 1
	var time_needed := steps * move_duration
	# The goal is winning, not just surviving — a kill opportunity is worth
	# more risk than farming a block for an upgrade, so it gets a smaller
	# safety margin (more willing to cut it close when an enemy is in blast).
	var margin := BOMB_ESCAPE_SAFETY_MARGIN * 0.5 if targets_enemy else BOMB_ESCAPE_SAFETY_MARGIN
	return time_needed <= _time_until_forced_detonation() - margin

# Bombs chain-detonate (Bomb.gd's _trigger_chain_at): if a bomb that's
# already ticking has a blast that reaches the cell we're about to bomb, it
# will set our new bomb off the instant *it* goes off — possibly much sooner
# than our own full fuse. Budget against whichever live bomb would reach us
# soonest, not just BOMB_FUSE_DURATION, or a chain reaction can strand a bot
# mid-escape with far less time than it planned for.
#
# Remote (Sapper) bombs used to be skipped here, because they carried no running
# Timer and reading time_left would have reported 0 — making every cell near an
# unexploded mine look like an imminent detonation. They now run a long fuse of
# their own (Bomb.REMOTE_FUSE_DURATION), so they belong in this scan like any
# other bomb: while a mine has most of its fuse left it is simply never the
# soonest threat and changes nothing, and once it is genuinely about to go off
# it should tighten the budget exactly as a short fuse does.
func _time_until_forced_detonation() -> float:
	var current_cell := get_current_cell()
	var soonest := BOMB_FUSE_DURATION
	for bomb_cell in arena.bombs_by_cell.keys():
		var bomb = arena.bombs_by_cell[bomb_cell]
		if not _blast_cells_for(bomb_cell, bomb.radius, bomb.is_circle_blast).has(current_cell):
			continue
		soonest = min(soonest, bomb.get_node("Timer").time_left)
	return soonest

# BFS over walkable cells starting at `start`; returns the path (inclusive of
# start) to the nearest cell satisfying `is_target`, or [] if none is
# reachable. Traversal respects arena walkability and `avoid` (hard-blocked
# cells, e.g. active explosions) but NOT bomb blast footprints in general —
# bombs have a multi-second fuse, so passing through a cell that's merely in
# a future blast radius (but not yet exploded) is safe; only `is_target`
# needs to check that.
func _bfs_find(start: Vector2i, is_target: Callable, avoid: Dictionary = {}, max_steps: int = 400) -> Array:
	if is_target.call(start):
		return [start]
	var visited := {start: true}
	var queue: Array = [start]
	var parent := {}
	var steps := 0
	while not queue.is_empty() and steps < max_steps:
		steps += 1
		var cur: Vector2i = queue.pop_front()
		for dir in Consts.DIRECTIONS:
			var next: Vector2i = cur + dir
			if visited.has(next):
				continue
			if not arena.is_walkable_for(next, self):
				continue
			if avoid.has(next):
				continue
			visited[next] = true
			parent[next] = cur
			if is_target.call(next):
				var path: Array = [next]
				var c: Vector2i = next
				while c != start:
					c = parent[c]
					path.append(c)
				path.reverse()
				return path
			queue.append(next)
	return []

func _bot_random_safe_dir(danger: Dictionary, hazard: Dictionary) -> Vector2i:
	var current_cell := get_current_cell()
	var options: Array = []
	for dir in Consts.DIRECTIONS:
		var c: Vector2i = current_cell + dir
		if arena.is_walkable_for(c, self) and not danger.has(c) and not hazard.has(c):
			options.append(dir)
	if options.is_empty():
		# No fully-safe neighbor — still never step into an active explosion
		# even if every option sits inside some bomb's future blast radius.
		for dir in Consts.DIRECTIONS:
			var c: Vector2i = current_cell + dir
			if arena.is_walkable_for(c, self) and not hazard.has(c):
				options.append(dir)
	if options.is_empty():
		for dir in Consts.DIRECTIONS:
			if arena.is_walkable_for(current_cell + dir, self):
				options.append(dir)
	if options.is_empty():
		return Vector2i.ZERO
	return options[randi() % options.size()]

func _bot_flee(danger: Dictionary, hazard: Dictionary) -> void:
	var current_cell := get_current_cell()
	var unsafe: Dictionary = danger.duplicate()
	for c in hazard:
		unsafe[c] = true
	var path := _bfs_find(current_cell, func(c): return not unsafe.has(c), hazard)
	if path.size() >= 2:
		bot_move_dir = path[1] - path[0]
	else:
		bot_move_dir = _bot_random_safe_dir(danger, hazard)

func _bot_wander(danger: Dictionary, hazard: Dictionary) -> void:
	var current_cell := get_current_cell()
	# Unlike fleeing, wandering is never forced through danger — there's no
	# urgency, so avoid every currently-ticking blast footprint entirely
	# (not just active hazards), or the hunt for an enemy/block can route the
	# bot right back into its own still-live bomb.
	var unsafe: Dictionary = danger.duplicate()
	for c in hazard:
		unsafe[c] = true
	# Powerups outrank both hunting and block-farming: they're a permanent stat
	# gain, they're on a first-come basis (a rival will take them otherwise),
	# and walking onto the cell is all it takes (Arena.try_collect_powerup fires
	# on arrival). Only worth it while it's a short detour, though — chasing one
	# across the whole arena would leave the bot passive, so anything further
	# than BOT_POWERUP_CHASE_MAX_STEPS is ignored in favour of the usual hunt.
	var path: Array = []
	if not arena.powerups_by_cell.is_empty():
		var pickup := _bfs_find(current_cell, func(c): return arena.has_powerup_at(c), unsafe)
		# size() == 1 would mean "already standing on it" (impossible — pickup is
		# automatic), so require a real step rather than freezing on the spot.
		if pickup.size() >= 2 and pickup.size() - 1 <= BOT_POWERUP_CHASE_MAX_STEPS:
			path = pickup
	var targets := {}
	for e in _alive_enemies():
		# An enemy already sharing this cell is not somewhere to walk to. Left in,
		# the chase would "arrive" instantly every tick and the bot would stand
		# still forever — two bots stacked on one cell used to freeze each other
		# that way, and with the last players stuck the round could never end.
		if e.get_current_cell() != current_cell:
			targets[e.get_current_cell()] = true
	if path.is_empty() and not targets.is_empty():
		path = _bfs_find(current_cell, func(c): return targets.has(c), unsafe)
	if path.is_empty():
		path = _bfs_find(current_cell, func(c):
			for dir in Consts.DIRECTIONS:
				if arena.is_block(c + dir):
					return true
			return false
		, unsafe)
	if path.size() >= 2:
		bot_move_dir = path[1] - path[0]
	elif path.size() == 1:
		bot_move_dir = Vector2i.ZERO
	else:
		bot_move_dir = _bot_random_safe_dir(danger, hazard)

## Sapper trigger, bot side. Fires when an enemy is standing in the blast of a
## bomb this bot has out, or — once it's safely clear — when there's nothing
## left to wait for but a block. Their bombs do run a long fuse of their own
## (Bomb.REMOTE_FUSE_DURATION), so this is no longer the only thing standing
## between the bot and running dry at `bomb_count_max` — but waiting out eight
## seconds per charge is not playing the character, it's surviving it.
##
## The trigger is all-or-nothing (it sets off every bomb the bot owns, and
## chains from there), so the bot has to be clear of *all* of them, not just of
## the one with the target in it. A shield buys an exception for an enemy
## target: trading a charge for a kill is a good trade, and it's the one the
## character is built to make. A block-only trigger never spends the shield —
## there's no reason to eat a hit for a wall that isn't going anywhere.
func _bot_try_detonate() -> void:
	if ability_on_cooldown or live_bombs.is_empty():
		return
	var current_cell := get_current_cell()
	var targets_enemy := false
	var targets_block := false
	var self_in_blast := false
	for bomb in live_bombs:
		if not is_instance_valid(bomb) or bomb.has_exploded:
			continue
		var blast := _blast_cells_for(bomb.cell, bomb.radius, bomb.is_circle_blast)
		if blast.has(current_cell):
			self_in_blast = true
		for c in blast:
			if _enemy_at(c) != null:
				targets_enemy = true
			elif arena.is_block(c):
				targets_block = true
	if not targets_enemy and not targets_block:
		return
	if self_in_blast and (not targets_enemy or shield_charges <= 0):
		return
	use_ability()

## Engineer walls, bot side. A wall is only worth spending when it costs
## someone something, so this asks for three things at once: an enemy close
## enough to be affected, a cell narrow enough that they can't simply walk
## around it, and no live blast about to demolish the wall for free.
##
## Spacing them out matters as much as placing them — the budget is small, and
## a bot that dumps its whole allowance into two neighbouring cells of the same
## corridor has blocked exactly one route twice.
func _bot_try_wall(danger: Dictionary) -> void:
	if ability_on_cooldown or active_temp_walls.size() >= bomb_count_max:
		return
	var current_cell := get_current_cell()
	if danger.has(current_cell) or arena.has_bomb_at(current_cell):
		return
	if _open_neighbour_count(current_cell) > BOT_WALL_MAX_OPEN_NEIGHBOURS:
		return
	if _has_own_wall_adjacent(current_cell):
		return
	var to_enemy := _bfs_find(current_cell, func(c): return _enemy_at(c) != null)
	# size() < 2 means the enemy is on this very cell — they're already past
	# whatever this wall would have blocked.
	if to_enemy.size() < 2 or to_enemy.size() - 1 > BOT_WALL_ENEMY_RANGE:
		return
	use_ability()

func _open_neighbour_count(cell: Vector2i) -> int:
	var count := 0
	for dir in Consts.DIRECTIONS:
		if arena.is_walkable_for(cell + dir, self):
			count += 1
	return count

func _has_own_wall_adjacent(cell: Vector2i) -> bool:
	for dir in Consts.DIRECTIONS:
		if arena.temp_wall_cells.get(cell + dir) == self:
			return true
	return false

## Parkour's hop, bot side. Humans trigger it with a double tap
## (_update_jump_double_tap, which is human-only because a bot has no taps to
## read); a bot picks the direction outright.
##
## Escapes only. Two cells for the price of one clears a blast lane a plain
## step cannot, but the landing cell has to be somewhere the bot actually wants
## to be — hopping out of one blast into another is how this would otherwise
## get the Parkour Runner killed faster than not having it. The cell being jumped over
## is checked too: the hop is a tween through real space, and Explosion damages
## on proximity every frame, so passing over a live blast is not free.
func _bot_try_escape_jump(danger: Dictionary, hazard: Dictionary) -> bool:
	if _scripted_move:
		return false
	var current_cell := get_current_cell()
	for dir in Consts.DIRECTIONS:
		var mid: Vector2i = current_cell + dir
		var landing: Vector2i = current_cell + dir * 2
		if hazard.has(mid) or danger.has(landing) or hazard.has(landing):
			continue
		# Permanent stone is jumpable too (see _try_jump_over_obstacle) — a
		# bot boxed in by indestructible walls on three sides used to have no
		# escape at all, since the generic flee/wander pathing treats stone as
		# equally solid whichever kind it is.
		var mid_is_wall: bool = arena.is_wall(mid) and not arena.is_temp_wall(mid)
		if not arena.is_block(mid) and not arena.has_bomb_at(mid) and not mid_is_wall:
			continue
		if not arena.is_walkable_for(landing, self):
			continue
		_try_jump_over_obstacle(dir)
		if _scripted_move:
			# The hop owns `position` until it lands, so the walk order that
			# was in flight has to be dropped — it aims at a cell the bot is
			# about to be two cells past.
			bot_move_dir = Vector2i.ZERO
			bot_hold_time = 0.0
			return true
	return false

## Hockey Player's kick, bot side. The kick itself fires on contact from
## _move_free, and the pathfinder never routes into a bomb cell, so without
## this a bot would go a whole match without kicking anything.
##
## Returns a direction to walk into, or ZERO. Only called while the bot is in
## a blast (see _bot_try_character_escape), so every candidate here is a bomb
## that is currently threatening it: the kick is an escape that happens to
## double as an attack, and directions that also send the bomb at an enemy are
## preferred over ones that merely get it away.
func _bot_kick_dir() -> Vector2i:
	var current_cell := get_current_cell()
	if _time_until_forced_detonation() < BOT_KICK_MIN_FUSE:
		return Vector2i.ZERO
	var fallback := Vector2i.ZERO
	for dir in Consts.DIRECTIONS:
		var bomb_cell: Vector2i = current_cell + dir
		var bomb = arena.get_bomb_at(bomb_cell)
		if bomb == null or bomb.is_sliding or bomb.has_exploded:
			continue
		var lane := _slide_lane(bomb_cell, dir)
		if lane.size() < BOT_KICK_MIN_LANE:
			continue
		# Where it comes to rest still has to be somewhere that isn't pointed
		# back at the bot — a bomb shoved down a short lane can end up with
		# this cell inside its blast all over again.
		var resting: Vector2i = lane[lane.size() - 1]
		var resting_blast := _blast_cells_for(resting, bomb.radius, bomb.is_circle_blast)
		if resting_blast.has(current_cell):
			continue
		for c in lane:
			if _enemy_at(c) != null:
				return dir
		for c in resting_blast:
			if _enemy_at(c) != null:
				return dir
		if fallback == Vector2i.ZERO:
			fallback = dir
	return fallback

## Cells a kicked bomb would travel through, stopping where Bomb._slide_step
## does. The last entry is where it comes to rest.
func _slide_lane(from: Vector2i, dir: Vector2i) -> Array:
	var lane: Array = []
	var c: Vector2i = from + dir
	while lane.size() < BOT_KICK_MAX_LANE:
		if not arena.in_bounds(c) or arena.is_wall(c) or arena.is_block(c) or arena.has_bomb_at(c):
			break
		lane.append(c)
		c += dir
	return lane

const PORTRAIT_REST_Y := -4.0

## One frame of free movement along `dir`.
##
## The player goes exactly where they asked whenever that's possible — no
## automatic re-centring. Pressing up from a spot straddling two columns moves
## straight up and keeps the horizontal offset; it does not slide to the middle
## of a cell, which would read as unrequested diagonal movement.
##
## Corridor alignment is a *fallback*, applied only when the straight step is
## blocked: with a box narrower than a cell, a few pixels of misalignment can
## catch the corner of an obstacle in the neighbouring lane, and refusing the
## move there would leave the player stuck for no visible reason. The nudge
## lasts only until they line up, then movement is purely axial again.
func _move_free(dir: Vector2i, delta: float) -> void:
	var step := move_speed * _sprint_factor() * delta
	var straight := position + Vector2(dir) * step

	if _can_stand_at(straight):
		_apply_move(straight)
		return

	# From here the straight step is blocked by something. Running into a wall
	# (or a bomb) ends the run, so a sprint can't be held up against an obstacle
	# and then spent the instant it clears.
	_sprint_charge = 0.0
	_try_kick_ahead(dir)

	# Lining up is only worth doing when there is somewhere to line up *for*:
	# the cell ahead of the player's own is open, so what stopped them is a
	# corner clipped in the neighbouring lane rather than a wall in their way.
	# Against a dead end there is nothing to round, and sliding them to the
	# middle of a corridor they cannot leave is movement they never asked for —
	# they stop flush and keep whatever offset they had.
	var current_cell := get_current_cell()
	var way_through: bool = _is_open(current_cell + dir)

	var centre: Vector2 = arena.cell_to_world(current_cell)
	var aligned := position
	if dir.x != 0:
		aligned.y = move_toward(position.y, centre.y, step)
	else:
		aligned.x = move_toward(position.x, centre.x, step)
	# `aligned == position` means already lined up, so the obstacle is genuinely
	# dead ahead rather than a corner being clipped — nothing to correct.
	if way_through and not aligned.is_equal_approx(position):
		# Corner cut: carry on forward *and* line up in the same frame.
		var assisted := aligned
		if dir.x != 0:
			assisted.x = straight.x
		else:
			assisted.y = straight.y
		if _can_stand_at(assisted):
			_apply_move(assisted)
			return
		# Too far out of line to cut the corner in one frame: give up the
		# forward step and just slide into alignment. Repeated over a few
		# frames this walks the player around the corner instead of leaving
		# them stuck against it, which is what a pure corner cut does when the
		# misalignment exceeds a single frame's travel.
		if _can_stand_at(aligned):
			_apply_move(aligned)
			return

	# Genuinely walled off in that direction: come to rest flush against it.
	var clamped := _clamp_to_boundary(straight, dir)
	if not clamped.is_equal_approx(position) and _can_stand_at(clamped):
		_apply_move(clamped)

## Walks the player out of a position that is no longer legal.
##
## Sudden death seals cells regardless of who is standing near them, and with
## free movement a box can be left overlapping the new wall while its centre
## sits safely outside it — not enough to be crushed, but enough that every
## candidate move fails the collision test. That used to wedge the player in
## place for the rest of the round with no way out.
##
## The way out is the centre of their own cell when that is still open, and
## otherwise the nearest open neighbour. This deliberately skips the usual
## validity check: nothing is valid right now, and refusing to move is what
## caused the deadlock.
func _unstick(delta: float) -> void:
	var cell := get_current_cell()
	if not _is_open(cell):
		cell = _nearest_open_cell(cell)
		if cell == INVALID_CELL:
			return
	_sprint_charge = 0.0
	position = position.move_toward(arena.cell_to_world(cell), move_speed * delta)

func _nearest_open_cell(from: Vector2i) -> Vector2i:
	var best := INVALID_CELL
	var best_dist := INF
	for dir in Consts.DIRECTIONS:
		var c: Vector2i = from + dir
		if not _is_open(c):
			continue
		var d: float = position.distance_squared_to(arena.cell_to_world(c))
		if d < best_dist:
			best_dist = d
			best = c
	return best

func _apply_move(target: Vector2) -> void:
	position = target
	if not _footstep_playing:
		_footstep_playing = true
		Sfx.play("footstep", 1.0, 0.1)
		get_tree().create_timer(move_duration / _sprint_factor()).timeout.connect(func(): _footstep_playing = false)

var _footstep_playing: bool = false

## Bomb-Kicker only shoves a bomb once actually pressed up against it, which is
## now a collision outcome rather than "the next cell holds a bomb".
func _try_kick_ahead(dir: Vector2i) -> void:
	if character_id != CharacterId.BOMB_KICKER:
		return
	var ahead: Vector2i = arena.world_to_cell(position + Vector2(dir) * (PLAYER_HALF_EXTENT + 2.0))
	var bomb = arena.get_bomb_at(ahead)
	if bomb != null and not bomb.is_sliding:
		bomb.start_slide(dir)
		Sfx.play("bomb_kick")
		_play_kick_anim()

## Pushes `target` back so the leading edge rests flush against the boundary of
## whatever it ran into, instead of the move being refused outright.
func _clamp_to_boundary(target: Vector2, dir: Vector2i) -> Vector2:
	var clamped := target
	var cs := float(Consts.CELL_SIZE)
	if dir.x > 0:
		var col: int = arena.world_to_cell(Vector2(clamped.x + PLAYER_HALF_EXTENT, clamped.y)).x
		clamped.x = col * cs - PLAYER_HALF_EXTENT - WALL_EPSILON
	elif dir.x < 0:
		var col: int = arena.world_to_cell(Vector2(clamped.x - PLAYER_HALF_EXTENT, clamped.y)).x
		clamped.x = (col + 1) * cs + PLAYER_HALF_EXTENT + WALL_EPSILON
	elif dir.y > 0:
		var row: int = arena.world_to_cell(Vector2(clamped.x, clamped.y + PLAYER_HALF_EXTENT)).y
		clamped.y = row * cs - PLAYER_HALF_EXTENT - WALL_EPSILON
	elif dir.y < 0:
		var row: int = arena.world_to_cell(Vector2(clamped.x, clamped.y - PLAYER_HALF_EXTENT)).y
		clamped.y = (row + 1) * cs + PLAYER_HALF_EXTENT + WALL_EPSILON
	return clamped

func _can_stand_at(pos: Vector2) -> bool:
	for ox in [-PLAYER_HALF_EXTENT, PLAYER_HALF_EXTENT]:
		for oy in [-PLAYER_HALF_EXTENT, PLAYER_HALF_EXTENT]:
			if not _is_open(arena.world_to_cell(pos + Vector2(ox, oy))):
				return false
	return true

func _is_open(cell: Vector2i) -> bool:
	if _bomb_grace.has(cell) and arena.has_bomb_at(cell):
		return true
	return arena.is_walkable_for(cell, self)

## Cells the player's box currently touches.
func _occupied_cells() -> Dictionary:
	var cells := {}
	for ox in [-PLAYER_HALF_EXTENT, PLAYER_HALF_EXTENT]:
		for oy in [-PLAYER_HALF_EXTENT, PLAYER_HALF_EXTENT]:
			cells[arena.world_to_cell(position + Vector2(ox, oy))] = true
	return cells

## Once the player is clear of a bomb they were standing on, it turns solid for
## them like it already is for everyone else.
func _release_cleared_bombs() -> void:
	if _bomb_grace.is_empty():
		return
	var occupied := _occupied_cells()
	for cell in _bomb_grace.keys():
		if not occupied.has(cell) or not arena.has_bomb_at(cell):
			_bomb_grace.erase(cell)

## Tween-driven hop/shove: takes `position` away from input handling for its
## duration so the two can't fight over the transform.
func _scripted_move_to(target_pos: Vector2, duration: float) -> void:
	_scripted_move = true
	var tw := create_tween()
	tw.tween_property(self, "position", target_pos, duration)
	tw.finished.connect(func():
		_scripted_move = false
		$Portrait.set_walking(false)
	)

func place_bomb() -> void:
	_place_ordnance(false)

## Bombs and the Miner's mines come out of one pool, not two, so seeding ground
## is always paid for in firepower they no longer have and a bomb-count powerup
## reads the same to them as to anyone.
##
## The last charge is never allowed to be a mine — a mine costs two, so at three
## charges the Miner can have at most two mines out, and at one charge none at
## all. A mine only pays off if somebody walks into it, which is not something
## its owner controls; without this rule the Miner could spend their entire
## arsenal on ground nobody happened to cross and stand there with no way to
## break a crate, defend themselves, or do anything but wait.
func _place_ordnance(as_mine: bool) -> bool:
	if arena == null:
		return false
	var current_cell := get_current_cell()
	if bomb_count_current < (2 if as_mine else 1) or arena.has_bomb_at(current_cell):
		return false
	var bomb := BombScene.instantiate()
	bomb.cell = current_cell
	bomb.arena = arena
	bomb.owner_player = self
	bomb.is_mine = as_mine
	# Half radius, rounded down but never to nothing: a mine that only covered
	# the cell it sits on could not chain, and a minefield that can't chain is a
	# collection of unrelated single squares rather than a field.
	bomb.radius = maxi(1, bomb_radius / 2) if as_mine else bomb_radius
	# A mine is its own kind of ordnance — it never also inherits the character
	# passive that shapes that player's ordinary bombs.
	bomb.is_circle_blast = not as_mine and character_id == CharacterId.PYRO
	bomb.remote = not as_mine and character_id == CharacterId.BOMB_MASTER
	bomb.magnetic = not as_mine and character_id == CharacterId.MAGNET
	bomb.position = arena.cell_to_world(current_cell)
	arena.add_child(bomb)
	bomb.exploded.connect(_on_owned_bomb_exploded.bind(bomb))
	live_bombs.append(bomb)
	bomb_count_current -= 1
	# The bomb lands under the player's feet — it only becomes solid for them
	# once they've walked clear of it (see _release_cleared_bombs).
	_bomb_grace[current_cell] = true
	Sfx.play("wall_place" if as_mine else "bomb_place")
	return true

func _on_owned_bomb_exploded(bomb: Node) -> void:
	live_bombs.erase(bomb)
	bomb_count_current = min(bomb_count_current + 1, bomb_count_max)

func use_ability() -> void:
	if ability_on_cooldown:
		return
	var used := false
	match character_id:
		CharacterId.ENGINEER:
			used = _ability_temp_wall()
		CharacterId.BOMB_MASTER:
			used = _ability_detonate()
		CharacterId.MINER:
			used = _place_ordnance(true)
	if used:
		ability_on_cooldown = true
		get_tree().create_timer(ability_cooldown).timeout.connect(func(): ability_on_cooldown = false)

## Drops a temp wall on the Engineer's own cell — passable for them (see
## Arena.is_walkable_for), solid for everyone else, bombs, and explosions.
##
## Capped at the player's bomb count, not at a separate budget: walls are the
## Engineer's half of the same resource bombs come out of, so a bomb-count
## powerup reads as "+1 wall" as plainly as it reads "+1 bomb", and the HUD's
## bomb counter doubles as the wall counter. This used to be `bomb_level + 1`,
## which is the count of *collected upgrades* — it happened to give the same
## number only because the Engineer had no starting bomb bonus to be out of
## step with, and it silently ignored any bombs granted by a passive.
func _ability_temp_wall() -> bool:
	if active_temp_walls.size() >= bomb_count_max:
		return false
	var wall: Node = arena.place_temp_wall(get_current_cell(), self)
	if wall == null:
		return false
	active_temp_walls.append(wall)
	wall.tree_exited.connect(func(): active_temp_walls.erase(wall))
	Sfx.play("wall_place")
	return true

## Sapper trigger: sets off every bomb they currently have out, at once.
##
## The Sapper's bombs (Bomb.gd's `remote` flag, set in place_bomb() below) run
## a fuse four times the normal length, with a blinking antenna instead of a
## burning one. In practice this is what sets them off: eight seconds is long
## enough that a planted bomb is a trap paying off the moment someone walks into
## it, rather than a warning anyone can watch burn down and step around — which
## was the one thing the Sapper's kit was missing; they were pure front-loaded
## stats that the rest of the roster caught up to on powerups alone.
##
## The fuse exists so the trap is not free. A mine left in a bad spot eventually
## answers for itself, a minefield can't be banked for a whole round, and the
## charges come back without the Sapper having to spend a trigger on a corner of
## the map nobody visited. It cuts both ways either way — the Sapper stands in
## their own blast as often as anyone else, so the timing is still on them.
##
## Iterates over a copy: explode() chains into neighbouring bombs and feeds
## back into _on_owned_bomb_exploded, which mutates live_bombs mid-loop.
func _ability_detonate() -> bool:
	if live_bombs.is_empty():
		return false
	for bomb in live_bombs.duplicate():
		if is_instance_valid(bomb):
			bomb.explode()
	return true

const KICK_LUNGE_DISTANCE := 16.0
const KICK_DURATION := 0.18

func _play_kick_anim() -> void:
	var rest := Vector2(0, PORTRAIT_REST_Y)
	var lunge := rest + Vector2(facing_dir) * KICK_LUNGE_DISTANCE
	var tw := create_tween()
	tw.tween_property($Portrait, "position", lunge, KICK_DURATION * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property($Portrait, "position", rest, KICK_DURATION * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func pickup_weapon() -> void:
	pass # TODO: weapon pickup (MVP phase 5)

func apply_powerup(type: int) -> void:
	match type:
		Consts.PowerupType.BOMB_COUNT:
			bomb_count_max += 1
			bomb_count_current += 1
			bomb_level += 1
		Consts.PowerupType.RADIUS:
			bomb_radius += 1
			radius_level += 1
		Consts.PowerupType.SPEED:
			move_duration *= 0.9
			_update_move_speed()
			speed_level += 1
		Consts.PowerupType.SHIELD:
			shield_charges += 1
	stats_changed.emit()

const INVULN_DURATION := 1.0
const INVULN_BLINK_INTERVAL := 0.1

var is_invulnerable: bool = false

func die() -> void:
	if not alive or is_invulnerable:
		return
	if shield_charges > 0:
		shield_charges -= 1
		stats_changed.emit()
		Sfx.play("shield_block")
		_start_invulnerability()
		return
	_kill()

func _kill() -> void:
	alive = false
	visible = false
	Sfx.play("player_death")
	GameManager.player_died(player_id)
	died.emit(player_id)

const SHOVE_DURATION := 0.12

## A sudden-death wall landed on this player's cell: they take a hit (a shield
## absorbs it like any other damage) and, if they live, get shoved out along
## `push_dir` — the direction the wall front is travelling.
##
## The shove happens even while invulnerable, because the alternative is a
## player left standing inside solid stone. Only when there is no free cell at
## all in any direction is the crush unsurvivable.
func crush(from_cell: Vector2i, push_dir: Vector2i) -> void:
	if not alive:
		return
	die()
	if not alive:
		return
	# `from_cell` is the walled cell, which is not necessarily current_cell:
	# a player caught mid-step is counted by where they're drawn, and that's
	# also where the shove has to start from.
	position = arena.cell_to_world(from_cell)
	var escape: Vector2i = _escape_cell(from_cell, push_dir)
	if escape == INVALID_CELL:
		_kill()
		return
	facing_dir = push_dir
	_scripted_move_to(arena.cell_to_world(escape), SHOVE_DURATION)

const INVALID_CELL := Vector2i(-1, -1)

# Prefers the push direction, then falls back to whichever remaining direction
# leads further from the closing wall (i.e. nearer the middle of the arena).
func _escape_cell(from_cell: Vector2i, push_dir: Vector2i) -> Vector2i:
	var centre := Vector2(Consts.GRID_WIDTH, Consts.GRID_HEIGHT) / 2.0
	var candidates: Array[Vector2i] = []
	for dir in Consts.DIRECTIONS:
		if dir != push_dir:
			candidates.append(dir)
	candidates.sort_custom(func(a, b):
		return Vector2(from_cell + a).distance_to(centre) < Vector2(from_cell + b).distance_to(centre)
	)
	candidates.push_front(push_dir)
	for dir in candidates:
		var cell: Vector2i = from_cell + dir
		if arena.is_walkable_for(cell, self):
			return cell
	return INVALID_CELL

func _start_invulnerability() -> void:
	is_invulnerable = true
	var tw := create_tween()
	tw.set_loops(int(INVULN_DURATION / (INVULN_BLINK_INTERVAL * 2)))
	tw.tween_property($Portrait, "modulate:a", 0.15, INVULN_BLINK_INTERVAL)
	tw.tween_property($Portrait, "modulate:a", 1.0, INVULN_BLINK_INTERVAL)
	get_tree().create_timer(INVULN_DURATION).timeout.connect(_end_invulnerability)

func _end_invulnerability() -> void:
	is_invulnerable = false
	$Portrait.modulate.a = 1.0
