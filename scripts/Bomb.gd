extends Node2D
## Base bomb: 2s fuse, cross-shaped blast stopped by walls, destroys the
## first soft block hit in each direction (an Engineer temp wall dies too, but
## still blocks the blast from going further). Chains into any other bomb its
## blast reaches, and is always pushed into a slide by the Bomb-Kicker
## walking into it — own or an opponent's bomb alike.
##
## The Sapper's bombs are `remote`: they run REMOTE_FUSE_DURATION instead of the
## normal one and are normally set off early, by Player._ability_detonate() or by
## a chain reaction from someone else's blast. The long fuse is a backstop rather
## than a clock to play against — it exists so a minefield eventually expires and
## so careless planting costs the Sapper something too, not so anyone waits it
## out. They carry a blinking antenna instead of a burning fuse; the blink speeds
## up as the fuse runs down.
##
## The Magnet's bombs are `magnetic`: they crawl a cell at a time toward
## whichever living opponent is nearest, on a normal fuse. That makes them the
## opposite threat to a kicked bomb — a kick is fast, straight, and over in a
## moment, while a magnet bomb is slow, steerable only by where you stand, and
## still coming when you have stopped thinking about it.

const ExplosionScene := preload("res://scenes/Explosion.tscn")
const SLIDE_STEP_DURATION := 0.08

## Magnet crawl pace, by how far off the nearest opponent is (in cells, walked
## rather than as the crow flies). The bomb is dead still until someone comes
## within range, stirs slowly when they are merely somewhere nearby, hunts at a
## pace a player can still outrun, and only really commits on the last step in.
##
## The banding is the mechanic, not a tuning detail. A bomb that crawled at one
## fixed speed wandered off after whoever happened to be marginally nearest
## halfway across the arena, which read as aimless twitching rather than as
## being hunted — the threat has to be legible, and "it woke up because you got
## close" is legible in a way that constant motion is not.
const MAGNET_RANGE_DORMANT := 9 # this far off (or further), the bomb never stirs
const MAGNET_STEP_FAR := 0.90   # 6-8 cells: stirring, easily walked away from
const MAGNET_STEP_NEAR := 0.55  # 3-5 cells: hunting, still slower than a player
const MAGNET_STEP_LUNGE := 0.22 # 2 cells: the last step in, faster than you are

## Fuse a magnet bomb earns for pulling up alongside its target (see
## _grant_catch_bonus). Half again as long as a normal 2s fuse, so the arrival
## is a real standoff rather than a formality.
const MAGNET_CATCH_FUSE_BONUS := 1.0

## Fuse for a remote bomb, four times the normal one. Long enough that the
## Sapper still picks the moment — the whole point of the character — and short
## enough that a minefield can't be banked for a whole round, and that a mine
## planted somewhere thoughtless comes back around to its owner.
const REMOTE_FUSE_DURATION := 8.0

signal exploded

@export var radius: int = 2
@export var is_circle_blast: bool = false # Pyro passive: fills a radius instead of a cross
@export var remote: bool = false # Sapper passive: no fuse, detonated only on demand
@export var magnetic: bool = false # Magnet passive: crawls toward the nearest opponent
var cell: Vector2i
var arena: Node2D
var owner_player: Node2D

var has_exploded: bool = false
var is_sliding: bool = false

var _magnet_step_timer: float = 0.0
var _magnet_dir: Vector2i = Vector2i.ZERO
var _magnet_caught: bool = false # the catch bonus is once per bomb, not once per step
var _magnet_dormant: bool = true # nobody in range; drawn asleep rather than merely still
var _fuse_total: float = 0.0

const FUSE_BASE := Vector2(8, -6)
const FUSE_TIP_FULL := Vector2(20, -20)
const ANTENNA_BLINK_PERIOD := 0.8 # seconds per full on/off cycle

func _ready() -> void:
	arena.register_bomb(cell, self)
	$BombBody.texture = Consts.BOMB_TEXTURE
	$Fuse.visible = not remote
	$Spark.visible = not remote
	$Antenna.visible = remote
	$AntennaTip.visible = remote
	if remote:
		$Timer.wait_time = REMOTE_FUSE_DURATION
	_fuse_total = $Timer.wait_time
	$Timer.start()

func _process(delta: float) -> void:
	if has_exploded:
		return
	if remote:
		_update_antenna_blink()
	else:
		_update_fuse_cue()
	if magnetic:
		_update_magnet(delta)
		queue_redraw() # the field halo in _draw() animates every frame

# Fuse cue: burns down (shortens toward the bomb) and pulses/glows redder
# faster the closer it is to going off.
func _update_fuse_cue() -> void:
	var t: float = _fuse_ratio()
	var freq: float = lerp(2.0, 12.0, 1.0 - t)
	var phase: float = Time.get_ticks_msec() / 1000.0 * freq
	var pulse: float = 1.0 + 0.15 * absf(sin(phase * PI))
	$BombBody.scale = Vector2.ONE * 1.4 * pulse
	$BombBody.modulate = Color.WHITE.lerp(Color(1.0, 0.25, 0.2), 1.0 - t)

	var tip: Vector2 = FUSE_BASE.lerp(FUSE_TIP_FULL, t)
	$Fuse.points = PackedVector2Array([FUSE_BASE, tip])
	$Spark.position = tip
	$Spark.scale = Vector2.ONE * pulse

## A remote bomb's "still armed" cue: a plain on/off blink that starts lazy and
## winds up as the long fuse burns down. Deliberately still not the burning-fuse
## cue — the body neither pulses nor reddens, because the honest reading of a
## mine is "sitting there, on its own schedule", not "about to go off any
## second" the way a thrown bomb is. The rate carries all of it: at a full fuse
## this is the same unhurried blink it always was, and only the last seconds get
## frantic.
func _update_antenna_blink() -> void:
	var freq: float = lerp(1.0 / ANTENNA_BLINK_PERIOD, 9.0, 1.0 - _fuse_ratio())
	var phase := fmod(Time.get_ticks_msec() / 1000.0 * freq, 1.0)
	$AntennaTip.modulate.a = 1.0 if phase < 0.5 else 0.15

## How much fuse is left, 1.0 to 0.0. Measured against the fuse the bomb was
## planted with rather than against Timer.wait_time, because a magnet bomb that
## catches someone restarts its Timer with extra seconds (see _update_magnet) —
## reading wait_time there would snap the cue back to "freshly planted" at the
## exact moment the bomb became most dangerous.
func _fuse_ratio() -> float:
	if _fuse_total <= 0.0:
		return 0.0
	return clampf($Timer.time_left / _fuse_total, 0.0, 1.0)

func _on_timer_timeout() -> void:
	explode()

func explode() -> void:
	if has_exploded:
		return
	has_exploded = true
	arena.remove_bomb(cell)
	Sfx.play("bomb_explode")
	if is_circle_blast:
		_explode_circle()
	else:
		_explode_cross()
	exploded.emit()
	queue_free()

func _explode_cross() -> void:
	_spawn_explosion(cell)
	if arena.is_temp_wall(cell):
		arena.destroy_temp_wall_at(cell)
	for dir in Consts.DIRECTIONS:
		for i in range(1, radius + 1):
			var c: Vector2i = cell + dir * i
			if not arena.in_bounds(c):
				break
			if arena.is_wall(c):
				if arena.is_temp_wall(c):
					_spawn_explosion(c)
					arena.destroy_temp_wall_at(c)
				break
			_spawn_explosion(c)
			_trigger_chain_at(c)
			if arena.is_block(c):
				arena.destroy_block_at(c, owner_player)
				break

func _explode_circle() -> void:
	# Pyro: diamond blast (manhattan distance <= radius). Pierces blocks until range runs out.
	_spawn_explosion(cell)
	if arena.is_temp_wall(cell):
		arena.destroy_temp_wall_at(cell)

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) > radius:
				continue
			if dx == 0 and dy == 0:
				continue
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not arena.in_bounds(c):
				continue
			if arena.is_wall(c):
				continue
			_spawn_explosion(c)
			if arena.is_temp_wall(c):
				arena.destroy_temp_wall_at(c)
			elif arena.is_block(c):
				arena.destroy_block_at(c, owner_player)
			else:
				_trigger_chain_at(c)

func _trigger_chain_at(target_cell: Vector2i) -> void:
	var other = arena.get_bomb_at(target_cell)
	if other != null and other != self:
		other.explode()

func _spawn_explosion(target_cell: Vector2i) -> void:
	var exp := ExplosionScene.instantiate()
	exp.position = arena.cell_to_world(target_cell)
	arena.add_child(exp)

func start_slide(dir: Vector2i) -> void:
	if is_sliding or has_exploded:
		return
	is_sliding = true
	_slide_step(dir)

func _slide_step(dir: Vector2i) -> void:
	if not _can_enter(cell + dir):
		is_sliding = false
		return
	var tw := _move_to_cell(cell + dir, SLIDE_STEP_DURATION)
	tw.finished.connect(func():
		if has_exploded:
			return
		_slide_step(dir)
	)

## Whether the bomb may occupy `target_cell` — the same test for a kicked slide
## and a magnet crawl. Players are deliberately not in it: a bomb passes under
## everyone, and the magnet stops short of its target for its own reasons (see
## _update_magnet) rather than because a body is in the way.
func _can_enter(target_cell: Vector2i) -> bool:
	if not arena.in_bounds(target_cell):
		return false
	return not arena.is_wall(target_cell) and not arena.is_block(target_cell) and not arena.has_bomb_at(target_cell)

## Hands `cell` over to `target_cell` in the arena's index and glides the sprite
## across to match. Returns the tween so the caller can chain onto it.
func _move_to_cell(target_cell: Vector2i, duration: float) -> Tween:
	arena.remove_bomb(cell)
	cell = target_cell
	arena.register_bomb(cell, self)
	var tw := create_tween()
	tw.tween_property(self, "position", arena.cell_to_world(cell), duration)
	return tw

## One crawl step per MAGNET_STEP_DURATION, toward whichever opponent is nearest
## *right now* — the target is re-picked every step rather than locked in when
## the bomb was planted, so the bomb transfers to whoever strays closest and two
## players can pull the same bomb back and forth between them.
##
## A kick takes priority: while the Hockey Player has this bomb sliding, the
## magnet stands down entirely rather than fight the slide tween over
## `position`, and resumes the chase from wherever the slide leaves it.
func _update_magnet(delta: float) -> void:
	if is_sliding:
		_magnet_step_timer = 0.0
		return

	var target := _nearest_target()
	if target == null:
		_go_dormant()
		return

	# Close enough: stop rather than step onto them. A bomb arriving underneath
	# a player leaves them unable to stand where they are and hands them to
	# Player._unstick(), which shoves them clear of the cell — the chase would
	# spend its last second pushing its own target out of the blast.
	var offset: Vector2i = arena.world_to_cell(target.position) - cell
	var distance: int = absi(offset.x) + absi(offset.y)
	if distance <= 1:
		_magnet_dir = Vector2i.ZERO
		_magnet_dormant = false
		_grant_catch_bonus()
		return

	var step_duration := _magnet_step_duration(distance)
	if step_duration <= 0.0:
		_go_dormant()
		return

	_magnet_dormant = false
	_magnet_step_timer += delta
	if _magnet_step_timer < step_duration:
		return
	_magnet_step_timer = 0.0

	var step := _magnet_step_toward(offset)
	_magnet_dir = step # ZERO when stalled, which also clears the leading-edge wedge
	if step == Vector2i.ZERO:
		return
	_move_to_cell(cell + step, step_duration)

## Seconds per cell at this range, or -1 when nobody is close enough to be worth
## stirring for. The step timer is reset on the way into dormancy rather than
## left running, so a bomb that has sat idle for a while doesn't fire off a
## banked step the instant someone steps into range.
func _magnet_step_duration(distance: int) -> float:
	if distance >= MAGNET_RANGE_DORMANT:
		return -1.0
	if distance >= 6:
		return MAGNET_STEP_FAR
	if distance >= 3:
		return MAGNET_STEP_NEAR
	return MAGNET_STEP_LUNGE

func _go_dormant() -> void:
	_magnet_dir = Vector2i.ZERO
	_magnet_step_timer = 0.0
	_magnet_dormant = true

## Catching someone buys the bomb another second of fuse — once per bomb, not
## once per step, or a bomb that pinned anyone would simply never go off.
##
## It pays for the chase. A normal fuse is 2s, which at MAGNET_STEP_DURATION is
## barely three cells of travel, so a bomb that spent its whole life closing the
## distance used to arrive with nothing left to threaten anyone with. Now the
## arrival is the point: the bomb pulls up alongside and *waits*, which is both
## the moment the victim gets to run and the moment they have to be somewhere
## else by.
func _grant_catch_bonus() -> void:
	if _magnet_caught or has_exploded:
		return
	_magnet_caught = true
	$Timer.start($Timer.time_left + MAGNET_CATCH_FUSE_BONUS)

## Greedy, not a path search: close the longer axis first and fall back to the
## other one when that cell is blocked. It will sit stalled against the outside
## of a dead end instead of walking around, and that is the point — a bomb that
## solved the maze would be unavoidable, so the arena's own geometry is the
## counterplay to being hunted.
func _magnet_step_toward(offset: Vector2i) -> Vector2i:
	var primary := Vector2i(signi(offset.x), 0)
	var secondary := Vector2i(0, signi(offset.y))
	if absi(offset.y) > absi(offset.x):
		var longer := secondary
		secondary = primary
		primary = longer
	if primary != Vector2i.ZERO and _magnet_can_enter(cell + primary):
		return primary
	if secondary != Vector2i.ZERO and _magnet_can_enter(cell + secondary):
		return secondary
	return Vector2i.ZERO

## Same as _can_enter(), plus: a crawling bomb never climbs onto a living player
## — anyone's, very much including the owner's.
##
## Stopping short of the *target* (see _update_magnet) is not enough on its own,
## because the bomb walks over whoever is standing between it and that target,
## and the one standing there is usually the Magnet who just planted it. A bomb
## arriving under someone's feet leaves them unable to stand where they are and
## hands them to Player._unstick(), which shoves them off the cell — so from
## that player's seat the bomb did not pass by, it homed in and stuck to them.
##
## Routing around bodies rather than stopping dead at them also means a player
## can deliberately body-block a magnet bomb in a corridor and hold it there
## until the fuse runs out, which is a fair trade for standing next to it.
func _magnet_can_enter(target_cell: Vector2i) -> bool:
	if not _can_enter(target_cell):
		return false
	for p in get_tree().get_nodes_in_group("players"):
		if p.alive and arena.world_to_cell(p.position) == target_cell:
			return false
	return true

## Nearest living player other than whoever planted it, straight-line rather
## than along a route: this is a magnet, not a hunter, and "pulled toward"
## honestly means toward whoever is physically closest even through a wall.
func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == owner_player or not p.alive:
			continue
		var d: float = position.distance_squared_to(p.position)
		if d < best_dist:
			best_dist = d
			best = p
	return best

const MAGNET_HALO_COLOR := Color(0.45, 0.75, 1.0)
const MAGNET_HALO_PERIOD := 0.9

## The one thing that has to read across the arena is "that bomb is coming for
## me". The expanding field ring says the bomb is magnetic at all; the wedge on
## its leading edge says which way it is crawling, and therefore whose problem
## it currently is. Drawn on the Bomb node itself, so it sits under the bomb
## body rather than over it.
func _draw() -> void:
	if not magnetic or has_exploded:
		return
	# Asleep: the core ring only, dimmed. No outgoing pulse and no wedge, so a
	# bomb nobody is close enough to wake reads as inert at a glance instead of
	# looking like it is about to set off after someone.
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(MAGNET_HALO_COLOR, 0.22 if _magnet_dormant else 0.5), 1.5)
	if _magnet_dormant:
		return
	var phase := fmod(Time.get_ticks_msec() / 1000.0, MAGNET_HALO_PERIOD) / MAGNET_HALO_PERIOD
	draw_arc(Vector2.ZERO, lerpf(14.0, 27.0, phase), 0.0, TAU, 24, Color(MAGNET_HALO_COLOR, 0.55 * (1.0 - phase)), 2.0)
	if _magnet_dir == Vector2i.ZERO:
		return
	var forward := Vector2(_magnet_dir)
	var side := Vector2(-forward.y, forward.x) * 6.0
	var tip: Vector2 = forward * 23.0
	var back: Vector2 = tip - forward * 9.0
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(MAGNET_HALO_COLOR, 0.85))
