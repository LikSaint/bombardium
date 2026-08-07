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
## BFS pathing (flee live blasts, else chase the nearest enemy/block, and drop
## a bomb only when a safe escape route from its own blast still exists).

const BombScene := preload("res://scenes/Bomb.tscn")
const ExplosionScript := preload("res://scripts/Explosion.gd")

enum CharacterId { BOMB_MASTER, SCOUT, ENGINEER, PYRO, BOMB_KICKER }

const MOVE_DEADZONE := 0.35

signal died(player_id: int)
signal stats_changed

@export var player_id: int = 1
@export var device_id: int = -1
@export var character_id: int = CharacterId.BOMB_MASTER

var arena: Node2D
var current_cell: Vector2i
var is_moving: bool = false
var alive: bool = true
var facing_dir: Vector2i = Consts.DIR_DOWN

var is_bot: bool = false
const BOT_DECISION_INTERVAL := 0.6 # pause between bot decisions; higher = slower/calmer bots
const BOT_DECISION_JITTER := 0.15 # +/- random spread so bots don't all tick in lockstep
var bot_decision_timer: float = 0.0
var bot_move_dir: Vector2i = Vector2i.ZERO
# While actively escaping a blast, decisions run every frame (no throttle) —
# only casual wandering/bombing-consideration is paced by BOT_DECISION_INTERVAL.
# Escape timing in _bot_should_bomb() assumes this, so don't throttle fleeing.
var is_fleeing: bool = false
const BOMB_FUSE_DURATION := 2.0 # must match Bomb.tscn's Timer wait_time
const BOMB_ESCAPE_SAFETY_MARGIN := 0.4 # buffer so a bomb is never a photo finish

var move_duration: float = 0.3
var bomb_count_max: int = 1
var bomb_count_current: int = 1
var bomb_radius: int = 1
var shield_charges: int = 0

# Upgrade levels shown on the HUD (0 = base, unrelated to the raw stat values above).
var bomb_level: int = 0
var radius_level: int = 0
var speed_level: int = 0

var ability_cooldown: float = 0.2
var ability_on_cooldown: bool = false

# Scout/Runner: jumping a wooden block requires pressing the same direction
# twice within this window (not a dedicated ability button).
const DOUBLE_TAP_WINDOW := 0.35
var _prev_held_dirs: Dictionary = {} # Vector2i -> bool, last frame's raw held state
var _last_dir_press_time: Dictionary = {} # Vector2i -> float (Time.get_ticks_msec()/1000.0)

# Engineer: temp walls this player currently has active, capped by bomb_level.
var active_temp_walls: Array = []

func _ready() -> void:
	is_bot = device_id == Consts.DEVICE_BOT
	add_to_group("players")
	$Portrait.set_character(character_id, Consts.PLAYER_COLORS[(player_id - 1) % Consts.PLAYER_COLORS.size()])
	_apply_character_passives()

func _apply_character_passives() -> void:
	match character_id:
		CharacterId.BOMB_MASTER:
			bomb_radius += 1
			bomb_count_max += 1
			bomb_count_current = bomb_count_max
			bomb_level += 1
			radius_level += 1
			shield_charges += 1
		CharacterId.SCOUT:
			move_duration *= 0.9
			speed_level += 1
		CharacterId.PYRO:
			shield_charges += 1
		CharacterId.BOMB_KICKER:
			move_duration *= 0.9
			speed_level += 1
	stats_changed.emit()

func _input(event: InputEvent) -> void:
	if not alive:
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
	if not alive:
		return
	var dir := _bot_update(delta) if is_bot else _poll_move_dir()
	if dir != Vector2i.ZERO:
		facing_dir = dir
		$Portrait.face(dir)
	if not is_bot and character_id == CharacterId.SCOUT:
		_update_jump_double_tap()
	if is_moving:
		return
	if dir != Vector2i.ZERO:
		_try_move(dir)

func _poll_move_dir() -> Vector2i:
	var x := 0.0
	var y := 0.0
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

## Scout/Runner passive: pressing a direction twice quickly while a wooden
## block or a bomb sits directly ahead hops clean over it. Edge-tracking runs
## every frame (even mid-move) so timing isn't skewed by movement being busy;
## only the jump attempt itself is gated on not already moving.
func _update_jump_double_tap() -> void:
	var held := _held_dirs()
	var now := Time.get_ticks_msec() / 1000.0
	for d in held.keys():
		var is_down: bool = held[d]
		var was_down: bool = _prev_held_dirs.get(d, false)
		if is_down and not was_down:
			var last_t: float = _last_dir_press_time.get(d, -INF)
			if not is_moving and now - last_t <= DOUBLE_TAP_WINDOW:
				_try_jump_over_obstacle(d)
			_last_dir_press_time[d] = now
	_prev_held_dirs = held

func _try_jump_over_obstacle(dir: Vector2i) -> void:
	var mid_cell := current_cell + dir
	var target_cell := current_cell + dir * 2
	# A temp wall only counts as a jumpable obstacle when it's blocking *this*
	# player — the owner already walks through it normally, no jump needed.
	var is_foreign_temp_wall: bool = arena.is_temp_wall(mid_cell) and not arena.is_walkable_for(mid_cell, self)
	if not arena.is_block(mid_cell) and not arena.has_bomb_at(mid_cell) and not is_foreign_temp_wall:
		return
	if not arena.is_walkable_for(target_cell, self):
		return
	facing_dir = dir
	$Portrait.face(dir)
	Sfx.play("jump")
	_move_to_cell(target_cell, move_duration)

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
	if bot_decision_timer <= 0.0 and not is_moving:
		bot_move_dir = Vector2i.ZERO
		_bot_think()
		bot_decision_timer = 0.0 if is_fleeing else BOT_DECISION_INTERVAL + randf_range(-BOT_DECISION_JITTER, BOT_DECISION_JITTER)
		var dir := bot_move_dir
		bot_move_dir = Vector2i.ZERO
		return dir
	return Vector2i.ZERO

func _bot_think() -> void:
	var danger := _compute_danger_cells()
	var hazard := _compute_active_hazard_cells()
	if danger.has(current_cell) or hazard.has(current_cell):
		is_fleeing = true
		_bot_flee(danger, hazard)
		return
	is_fleeing = false
	if bomb_count_current > 0 and not arena.has_bomb_at(current_cell) and _bot_should_bomb(danger, hazard):
		place_bomb()
		is_fleeing = true
		_bot_flee(_compute_danger_cells(), _compute_active_hazard_cells())
		return
	_bot_wander(danger, hazard)

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
		if p.current_cell == cell:
			return p
	return null

func _alive_enemies() -> Array:
	var result: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.alive:
			result.append(p)
	return result

func _bot_should_bomb(danger: Dictionary, hazard: Dictionary) -> bool:
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
func _time_until_forced_detonation() -> float:
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
	var unsafe: Dictionary = danger.duplicate()
	for c in hazard:
		unsafe[c] = true
	var path := _bfs_find(current_cell, func(c): return not unsafe.has(c), hazard)
	if path.size() >= 2:
		bot_move_dir = path[1] - path[0]
	else:
		bot_move_dir = _bot_random_safe_dir(danger, hazard)

func _bot_wander(danger: Dictionary, hazard: Dictionary) -> void:
	# Unlike fleeing, wandering is never forced through danger — there's no
	# urgency, so avoid every currently-ticking blast footprint entirely
	# (not just active hazards), or the hunt for an enemy/block can route the
	# bot right back into its own still-live bomb.
	var unsafe: Dictionary = danger.duplicate()
	for c in hazard:
		unsafe[c] = true
	var targets := {}
	for e in _alive_enemies():
		# An enemy already sharing this cell is not somewhere to walk to. Left in,
		# the chase would "arrive" instantly every tick and the bot would stand
		# still forever — two bots stacked on one cell used to freeze each other
		# that way, and with the last players stuck the round could never end.
		if e.current_cell != current_cell:
			targets[e.current_cell] = true
	var path: Array = []
	if not targets.is_empty():
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

const PORTRAIT_REST_Y := -4.0

var _move_tween: Tween

func _move_to_cell(target_cell: Vector2i, duration: float) -> void:
	# A shove can interrupt a step that's still animating; without killing the
	# old tween the two would fight over `position` and land on the wrong cell.
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	is_moving = true
	$Portrait.set_walking(true, duration)
	var tw := create_tween()
	tw.tween_property(self, "position", arena.cell_to_world(target_cell), duration)
	tw.finished.connect(func():
		current_cell = target_cell
		is_moving = false
		$Portrait.set_walking(false)
		arena.try_collect_powerup(current_cell, self)
	)
	_move_tween = tw

func _try_move(dir: Vector2i) -> void:
	var target_cell := current_cell + dir
	if character_id == CharacterId.BOMB_KICKER:
		# Always pushes whatever bomb is ahead — own or an opponent's — just by
		# walking into it; if the push clears the cell, movement continues into it.
		var bomb = arena.get_bomb_at(target_cell)
		if bomb != null and not bomb.is_sliding:
			bomb.start_slide(dir)
			Sfx.play("bomb_kick")
			_play_kick_anim()
	if not arena.is_walkable_for(target_cell, self):
		return
	Sfx.play("footstep", 1.0, 0.1)
	_move_to_cell(target_cell, move_duration)

func place_bomb() -> void:
	if bomb_count_current <= 0 or arena.has_bomb_at(current_cell):
		return
	var bomb := BombScene.instantiate()
	bomb.cell = current_cell
	bomb.arena = arena
	bomb.owner_player = self
	bomb.radius = bomb_radius
	bomb.is_circle_blast = character_id == CharacterId.PYRO
	bomb.position = arena.cell_to_world(current_cell)
	arena.add_child(bomb)
	bomb.exploded.connect(_on_owned_bomb_exploded)
	bomb_count_current -= 1
	Sfx.play("bomb_place")

func _on_owned_bomb_exploded() -> void:
	bomb_count_current = min(bomb_count_current + 1, bomb_count_max)

func use_ability() -> void:
	if ability_on_cooldown:
		return
	var used := false
	match character_id:
		CharacterId.ENGINEER:
			used = _ability_temp_wall()
	if used:
		ability_on_cooldown = true
		get_tree().create_timer(ability_cooldown).timeout.connect(func(): ability_on_cooldown = false)

## Drops a temp wall on the Engineer's own cell — passable for them (see
## Arena.is_walkable_for), solid for everyone else, bombs, and explosions.
## Capped at 1 + bomb_level, so it scales with bomb-count upgrades collected.
func _ability_temp_wall() -> bool:
	if active_temp_walls.size() >= bomb_level + 1:
		return false
	var wall: Node = arena.place_temp_wall(current_cell, self)
	if wall == null:
		return false
	active_temp_walls.append(wall)
	wall.tree_exited.connect(func(): active_temp_walls.erase(wall))
	Sfx.play("wall_place")
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
	current_cell = from_cell
	var escape: Vector2i = _escape_cell(from_cell, push_dir)
	if escape == INVALID_CELL:
		_kill()
		return
	facing_dir = push_dir
	_move_to_cell(escape, SHOVE_DURATION)

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
