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
##
## The Grenadier's shells are `thrown`: the only bomb that spends its life in
## the air. It is fired from wherever its owner stood, arcs over everything in
## between — walls, crates, water, people — and goes off the instant it lands
## on the cell it was aimed at. See the flight section further down.

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

## The Miner's trap. A mine has no fuse and — unlike every other bomb — is not
## solid: players walk straight over it, which is the whole point of a trap. It
## goes off the moment an opponent steps anywhere its own blast would reach, and
## never for the Miner themselves, who therefore owns the ground they seeded.
##
## A mine is also invisible for all but the two moments that matter: the plant
## and the trip. See MINE_REVEAL_DURATION.
##
## Trigger range is not a number of its own: it *is* the blast footprint, walls
## and crates included (see _blast_cells). A mine on half of a radius-4 bomb
## covers two cells and so fires at two cells — the range you can see from the
## explosion is the range you have to respect, and neither can drift from the
## other as radius powerups come in.
##
## MINE_ARM_DELAY keeps a freshly planted mine from going off in the face of an
## opponent already standing there.
##
## MINE_TRIP_DELAY is the tell between tripping a mine and wearing it. The scale
## to read it against is distance travelled, not seconds: base move_duration is
## 0.3s per cell, and clearing a radius-1 mine means getting two cells from its
## centre. So this buys a little under one cell — walking into a mine is meant
## to be something you pay for, and only somebody already on their way out the
## far side gets to keep the charge they were carrying.
##
## It has been as high as 0.45 (a cell and a half), which let anyone who clipped
## the edge of the footprint stroll clear and made mines read as a suggestion.
## If they now feel unfair rather than punishing, this is the single number to
## move; the strobe below re-times itself to whatever it is set to.
const MINE_ARM_DELAY := 0.6
const MINE_TRIP_DELAY := 0.25

## How long a freshly planted mine stays on show before sinking out of sight for
## good. A mine nobody can see is the trap the character is named for; a mine
## nobody — the Miner included — ever saw is a coin flip, so the plant itself is
## the one honest look anybody gets at where the field is. Anyone watching the
## Miner work can read the field off that; anyone who wandered in late pays for
## it, which is the whole point.
##
## Deliberately shorter than MINE_ARM_DELAY: what is on display is the act of
## planting, not a live mine, and the ground has gone quiet again by the time it
## can hurt anybody. The mine reappears only once tripped — the strobe in
## _draw_mine is then the sole warning, and MINE_TRIP_DELAY is how much of one.
const MINE_REVEAL_DURATION := 0.5
const MINE_FADE_DURATION := 0.2 # tail of that window: it sinks into the floor rather than blinking out

## The Grenadier's shell, in the air.
##
## The time of flight is the entire counterplay to a ranged blast that needs no
## fuse: the shell is visible the whole way, its landing cell is ringed from the
## moment it leaves the tube, and at base move speed (0.3s per cell) even the
## shortest shot is three and a half cells of walking — the floor is deliberately
## generous, because a shell lobbed over the crate you are hiding behind lands
## with the least warning of any of them and is the one that has to be escapable. So a shell aimed where somebody *is*
## misses, and one aimed where they are going does not — which is the skill the
## character is asking for. Shortening this is the fastest way to make the
## Grenadier unfair, since nothing else about the shot can be dodged: the floor
## started at 0.45, which read as a shot you had to have already been running
## from before it was fired.
##
## It is priced by the cell, with a floor, rather than being one flat number: a
## charged shot travels further, so it hangs in the air longer and is that much
## easier to walk out from under. Without that the long shot would be strictly
## better than the short one — same warning, more reach — and there would be no
## reason ever to tap the button. It also feeds the cooldown, which is measured
## from impact (see Player.GRENADE_COOLDOWN), so shooting across the arena costs
## more time than lobbing one over the crate in front of you.
##
## The arc is why it clears walls. Height is drawn, not simulated — nothing in
## this game has a z axis — but it is what tells you a shell is passing over the
## crate rather than into it, and a longer throw visibly goes higher. The base
## height carries the short shot: at the floor above it hangs for over a second,
## and a flat little hop that took that long would read as the game lagging
## rather than as a mortar shell going up and coming down.
const FLIGHT_MIN_DURATION := 1.1
const FLIGHT_PER_CELL := 0.22
const FLIGHT_ARC_HEIGHT := 52.0
const FLIGHT_ARC_PER_CELL := 5.0
const FLIGHT_SPIN := 9.0 # radians/s; a tumbling shell reads as thrown rather than slid

## Seconds a shell aimed `cells` away spends in the air. Player asks for this
## before the shot to price the cooldown off it, and the shell itself uses it to
## fly — one answer, so the two can't disagree.
static func flight_time_for(cells: int) -> float:
	return maxf(FLIGHT_MIN_DURATION, FLIGHT_PER_CELL * cells)

signal exploded

@export var radius: int = 2
@export var is_star_blast: bool = false # Pyro passive: four extra half-length arms on the diagonals, and cover slows the blast instead of stopping it
@export var remote: bool = false # Sapper passive: no fuse, detonated only on demand
@export var magnetic: bool = false # Magnet passive: crawls toward the nearest opponent
@export var is_mine: bool = false # Miner ability: walkable, no fuse, tripped by opponents
@export var thrown: bool = false # Grenadier ability: flies to `cell` over the map, explodes on landing
var cell: Vector2i
var arena: Node2D
var owner_player: Node2D

var has_exploded: bool = false
var is_sliding: bool = false
var _slide_left: int = 0 # cells still owed to the current kick

var _magnet_step_timer: float = 0.0
var _magnet_dir: Vector2i = Vector2i.ZERO
var _magnet_caught: bool = false # the catch bonus is once per bomb, not once per step
var _magnet_dormant: bool = true # nobody in range; drawn asleep rather than merely still
var _fuse_total: float = 0.0
var _mine_age: float = 0.0
var _mine_trip_left: float = -1.0 # >= 0 once tripped: counting down to the blast
var _flight_left: float = 0.0
var _flight_total: float = 0.0 # priced off the distance, see flight_time_for
var _flight_arc: float = 0.0
var _flight_from: Vector2 # the muzzle it left; `cell` is where it comes down

const FUSE_BASE := Vector2(8, -6)
const FUSE_TIP_FULL := Vector2(20, -20)
const ANTENNA_BLINK_PERIOD := 0.8 # seconds per full on/off cycle

func _ready() -> void:
	# A shell in the air is deliberately not on the grid: it doesn't block the
	# cell it is about to land on, can't be kicked or crawled into on the way
	# there, and can't be chained by a blast it happens to fly through. The one
	# thing that *does* see it is the bot danger map, which reads it off its
	# owner's live_bombs (see Player._compute_danger_cells) — it is plainly
	# visible on screen, so pretending otherwise would only make bots blind.
	if not thrown:
		arena.register_bomb(cell, self)
	$BombBody.texture = Consts.BOMB_TEXTURE
	$Fuse.visible = not remote and not is_mine and not thrown
	$Spark.visible = not remote and not is_mine and not thrown
	$Antenna.visible = remote
	$AntennaTip.visible = remote
	if thrown:
		# Lets Player._incoming_shell_cells find every shell in flight by
		# scanning one group instead of walking each player's live_bombs — the
		# only way a turret's shell (owner_player == null, in nobody's
		# live_bombs) gets seen by a bot at all. See that method for the rest.
		add_to_group("thrown_shells")
		# No fuse of any kind — impact is the trigger. It sits a little smaller
		# than a placed bomb because it is meant to read as a shell overhead
		# rather than as something already on the floor.
		_flight_from = position
		var cells := int(round(_flight_from.distance_to(arena.cell_to_world(cell)) / float(Consts.CELL_SIZE)))
		_flight_total = flight_time_for(cells)
		_flight_left = _flight_total
		_flight_arc = FLIGHT_ARC_HEIGHT + FLIGHT_ARC_PER_CELL * cells
		$BombBody.scale = Vector2.ONE * 1.05
		return
	if is_mine:
		# No Timer at all: a mine waits for a footstep, not a clock. It also sits
		# smaller and half-faded compared to a bomb, because something you are
		# meant to walk over should not look like something you are meant to walk
		# around — the transparency is what sells it as set into the floor.
		$BombBody.scale = Vector2.ONE * 0.85
		$BombBody.modulate.a = MINE_BODY_ALPHA
		return
	if remote:
		$Timer.wait_time = REMOTE_FUSE_DURATION
	_fuse_total = $Timer.wait_time
	$Timer.start()

func _process(delta: float) -> void:
	if has_exploded:
		return
	if thrown:
		_update_flight(delta)
		queue_redraw() # the shadow and the landing ring move every frame
		return
	if is_mine:
		_update_mine(delta)
		queue_redraw() # the arm/trip cue in _draw() animates every frame
	elif remote:
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

## A mine's whole life: arm, wait however long it takes, trip, go off.
##
## The owner is skipped, and that is the character rather than a convenience —
## the Miner walks their own field freely, which is what makes seeding ground
## worth doing at all instead of just being a slower way to place a bomb. They
## are still perfectly capable of dying to a mine somebody else tripped next to
## them, so the field is not a safe room.
func _update_mine(delta: float) -> void:
	_mine_age += delta
	$BombBody.modulate.a = MINE_BODY_ALPHA * _mine_reveal_ratio()
	if _mine_trip_left >= 0.0:
		_mine_trip_left -= delta
		if _mine_trip_left <= 0.0:
			explode()
		return
	if _mine_age < MINE_ARM_DELAY:
		return
	var blast := _blast_cells()
	for p in get_tree().get_nodes_in_group("players"):
		if p == owner_player or not p.alive:
			continue
		if blast.has(arena.world_to_cell(p.position)):
			_mine_trip_left = MINE_TRIP_DELAY
			# Surfaces on the same frame it trips rather than on the next one:
			# with MINE_TRIP_DELAY this short, a frame of invisible countdown is
			# a measurable slice of the only warning anybody gets.
			$BombBody.modulate.a = MINE_BODY_ALPHA
			Sfx.play("countdown_tick")
			return

## How visible the mine is right now, 1.0 to 0.0: full while it is being planted,
## fading out over MINE_FADE_DURATION, nothing at all through the long middle of
## its life, and full again from the instant it trips. Drives both the sprite's
## alpha and every stroke in _draw_mine, so there is one answer to "can this be
## seen" rather than two that can drift apart.
func _mine_reveal_ratio() -> float:
	if _mine_trip_left >= 0.0:
		return 1.0
	if _mine_age >= MINE_REVEAL_DURATION:
		return 0.0
	var fade_start := MINE_REVEAL_DURATION - MINE_FADE_DURATION
	if _mine_age <= fade_start:
		return 1.0
	return 1.0 - (_mine_age - fade_start) / MINE_FADE_DURATION

## Whether this mine is on screen at all right now. Bots read it to decide what
## they are allowed to know (Player._bot_remembers_mine): a mine nobody can see is
## a mine everybody is entitled to forget, and a bot that kept perfect track of
## one would be playing with information the player was denied.
func is_mine_visible() -> bool:
	return is_mine and not has_exploded and _mine_reveal_ratio() > 0.0

## One frame of the shell's flight, and the landing that ends it.
##
## The node itself is moved along the arc rather than an inner sprite, so the
## shadow and the landing ring in _draw_flight() are positioned relative to one
## thing. `cell` is the landing cell from the moment it is fired, which is what
## lets explode() work exactly as it does for a bomb that never moved.
func _update_flight(delta: float) -> void:
	_flight_left = maxf(_flight_left - delta, 0.0)
	var t: float = 1.0 - _flight_left / _flight_total
	var ground: Vector2 = _flight_from.lerp(arena.cell_to_world(cell), t)
	position = ground - Vector2(0.0, sin(t * PI) * _flight_arc)
	$BombBody.rotation += delta * FLIGHT_SPIN
	if _flight_left <= 0.0:
		explode()

## Cells this bomb's blast would actually reach, walls and crates accounted for.
## Deliberately the very same call the explosion itself makes, so a mine's
## trigger range and its kill range are one thing by construction rather than
## two that happen to agree — and so an opponent safely round a corner doesn't
## set off a mine that could never have touched them.
func _blast_cells() -> Dictionary:
	return arena.blast_cells(cell, radius, is_star_blast)

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
	# Only ever give up an index entry that is actually ours. A thrown shell was
	# never registered (see _ready) and can perfectly well come down on top of
	# somebody's mine, and erasing that entry would orphan the mine — still
	# drawn, still armed, and no longer known to anything that looks a bomb up
	# by cell.
	if arena.get_bomb_at(cell) == self:
		arena.remove_bomb(cell)
	Sfx.play("bomb_explode")
	_apply_blast()
	exploded.emit()
	queue_free()

## Every cell the blast reached gets the same treatment whatever shape got it
## there: temp walls come down, crates come down, and anything else is checked
## for a bomb to set off. Which cells those are is Arena.blast_cells' business
## alone — cross and star can't drift apart in what they do to what they
## touch, and neither can drift from what _blast_cells tells a mine it covers.
func _apply_blast() -> void:
	var cells := _blast_cells()
	for c in cells:
		_spawn_explosion(c)
		if arena.is_temp_wall(c):
			arena.destroy_temp_wall_at(c)
		elif arena.is_block(c):
			arena.destroy_block_at(c, owner_player)
		else:
			_trigger_chain_at(c)
	# By group, not by cell index: there are only ever a couple of these on the
	# arena at once, and a separate Arena-side index would just be one more
	# thing to keep in sync with their tweens. Shared group, not one per hazard
	# kind, so every future contact hazard (see docs/plan-crate-hazards.md) gets
	# blast damage for free instead of this method growing a new loop each time.
	for mob in get_tree().get_nodes_in_group("hazard_mobs"):
		if cells.has(mob.cell):
			mob.take_hit()

func _trigger_chain_at(target_cell: Vector2i) -> void:
	var other = arena.get_bomb_at(target_cell)
	if other != null and other != self:
		other.explode()

## Every blast cell goes through here whatever the blast's shape, which makes it
## the one place a bridge has to be checked: a crossing goes down to a cross, a
## Pyro's star and a chain reaction alike, without any of them having to know
## bridges exist.
func _spawn_explosion(target_cell: Vector2i) -> void:
	arena.break_bridge_at(target_cell)
	var exp := ExplosionScene.instantiate()
	exp.position = arena.cell_to_world(target_cell)
	arena.add_child(exp)

## A kick carries the bomb `distance` cells, or until something stops it — the
## kicker decides how far (see Player.kick_distance), the arena decides whether
## it gets there. The bomb keeps its own countdown rather than the caller
## driving the steps, because a slide outlives the moment of contact: the
## Hockey Player is free to walk off, or die, mid-slide.
func start_slide(dir: Vector2i, distance: int) -> void:
	if is_sliding or has_exploded or distance <= 0:
		return
	is_sliding = true
	_slide_left = distance
	_slide_step(dir)

func _slide_step(dir: Vector2i) -> void:
	if _slide_left <= 0 or not _can_enter(cell + dir):
		is_sliding = false
		return
	_slide_left -= 1
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
	if arena.is_pit(target_cell):
		return false # kicked or crawling, a bomb stops at the water's edge
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
	var target_cell: Vector2i = arena.world_to_cell(target.position)
	var offset: Vector2i = target_cell - cell
	# Banding is deliberately measured straight-line rather than along the route
	# the bomb will actually walk: how close the thing is on screen is what a
	# player reads and reacts to, and a bomb that went dormant because the way
	# round was long would look asleep while sitting two cells away.
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

	var step := _magnet_step_toward(target_cell)
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

## First step of the shortest route to `target_cell`, or ZERO when there is no
## route at all.
##
## This replaces an axis-greedy step (close the longer axis, fall back to the
## other when blocked), which was chosen so the bomb would stall on geometry
## rather than solve it. In practice, around a corner both axes alternate
## between blocked and open, so the bomb picked a different one every step and
## visibly jittered on the spot with its heading wedge spinning — it read as a
## broken object rather than as a threat that had lost you.
##
## What made stalling look like the safe default was that nothing else held the
## mechanic back. The range bands do that now: the bomb is asleep past 8 cells
## and slower than a player inside them, so it can route properly and still be
## walked away from. Losing it is a matter of distance, not of hoping it trips
## over a wall.
func _magnet_step_toward(target_cell: Vector2i) -> Vector2i:
	var came_from := {cell: cell}
	var queue: Array[Vector2i] = [cell]
	var head := 0
	var reached := false
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == target_cell:
			reached = true
			break
		for dir in Consts.DIRECTIONS:
			var next: Vector2i = current + dir
			if came_from.has(next):
				continue
			# The target's own cell is the goal, so it counts as reachable even
			# though somebody is standing on it; every other occupied cell is a
			# genuine obstacle, which is what lets a player body-block a chase.
			if next != target_cell and not _magnet_can_enter(next):
				continue
			came_from[next] = current
			queue.append(next)
	if not reached:
		return Vector2i.ZERO
	var node := target_cell
	while came_from[node] != cell:
		node = came_from[node]
	return node - cell

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
const MINE_IDLE_COLOR := Color(0.95, 0.72, 0.25)
const MINE_TRIP_COLOR := Color(1.0, 0.25, 0.2)
const MINE_BODY_ALPHA := 0.5

## A mine has to advertise itself just enough — and only when it is advertising
## at all (see _mine_reveal_ratio; most of a mine's life is drawn as bare floor).
## It is drawn flat on the ground rather than as a silhouette standing up off it —
## the shape says "this is floor you may cross", and the colour says crossing it
## is a decision. Once tripped it strobes on the way out, which is the entire
## counterplay: the tell has to be impossible to miss even when it is far too
## short to stroll out of.
##
## The faint diamonds are the mine's own blast cells, walls and crates included,
## so a radius powerup is visible as the field growing rather than as a number in
## the corner — and since the trigger *is* the footprint, what is drawn is
## exactly the ground that sets it off. Anyone watching the plant reads the
## footprint too, which is the right trade: the reach is only on show for the
## half-second the mine itself is, and after that the danger is that you don't
## know where the field is, not that you can't tell how big it is.
func _draw_mine() -> void:
	var reveal := _mine_reveal_ratio()
	if reveal <= 0.0:
		return
	var tripped := _mine_trip_left >= 0.0
	var armed := _mine_age >= MINE_ARM_DELAY
	var tint := MINE_TRIP_COLOR if tripped else MINE_IDLE_COLOR
	# Three on/off cycles across the window whatever MINE_TRIP_DELAY is set to,
	# rather than a fixed 10Hz that would show two blinks at one value and six at
	# another. The count is the part that reads; the rate follows from it.
	var strobe := tripped and fmod(_mine_trip_left, MINE_TRIP_DELAY / 3.0) < MINE_TRIP_DELAY / 6.0

	var footprint_alpha: float = (0.34 if strobe else (0.20 if tripped else (0.15 if armed else 0.06))) * reveal
	for c in _blast_cells():
		if c == cell:
			continue
		var at := Vector2(c - cell) * float(Consts.CELL_SIZE)
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0, -10), at + Vector2(10, 0),
			at + Vector2(0, 10), at + Vector2(-10, 0),
		]), Color(tint, footprint_alpha))

	if tripped:
		draw_circle(Vector2.ZERO, 15.0, Color(tint, 0.45 if strobe else 0.15))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 22, Color(tint, 1.0 if strobe else 0.4), 2.5)
		return
	# Still arming: dim, and no pulse, so it plainly isn't live yet.
	var pulse := 0.35 + 0.25 * absf(sin(Time.get_ticks_msec() / 1000.0 * PI))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 22, Color(tint, (pulse if armed else 0.18) * reveal), 2.0)
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 14, Color(tint, (0.5 if armed else 0.18) * reveal), 1.5)

const FLIGHT_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const FLIGHT_MARKER_COLOR := Color(1.0, 0.55, 0.18)

## A shell in the air, and — more importantly — where it is about to land.
##
## The ring on the landing cell is the whole reason the Grenadier is fair: it
## goes down the instant the shot leaves the tube, so the blast is announced for
## its entire flight rather than arriving out of nowhere, and it closes as the
## shell falls so how long you have left is something you can see rather than
## count. The shadow does the other half of the job — it tracks the ground the
## shell is passing *over*, which is what says the wall between you and the
## Grenadier is not going to help.
func _draw_flight() -> void:
	var t: float = 1.0 - _flight_left / _flight_total
	var landing: Vector2 = arena.cell_to_world(cell) - position
	var ground: Vector2 = _flight_from.lerp(arena.cell_to_world(cell), t) - position
	var height: float = sin(t * PI)

	# Shadow: tight and dark on the ground, wide and faint at the top of the
	# arc, which is the only depth cue a game with no z axis can offer.
	draw_circle(ground, lerpf(7.0, 11.0, height), Color(FLIGHT_SHADOW_COLOR, FLIGHT_SHADOW_COLOR.a * (1.0 - 0.45 * height)))

	draw_arc(landing, lerpf(26.0, 12.0, t), 0.0, TAU, 26, Color(FLIGHT_MARKER_COLOR, 0.35 + 0.5 * t), 2.0)
	draw_circle(landing, 4.0, Color(FLIGHT_MARKER_COLOR, 0.25 + 0.55 * t))

func _draw() -> void:
	if has_exploded:
		return
	if thrown:
		_draw_flight()
		return
	if is_mine:
		_draw_mine()
		return
	if not magnetic:
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
