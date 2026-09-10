extends Node2D
## Crate hazard: rolls in a straight line until it hits something, then turns
## toward whichever perpendicular is open (a real bounce, not a U-turn, unless
## both are blocked) or turns back if boxed in on three sides. Rolling into
## water or a chasm is a one-way trip — the only way to be rid of it without
## spending a bomb on it. Kills on contact; dies to a single blast, unlike a
## slower, tougher hazard would — a fast, readable threat shouldn't also need
## the same punishment to put down.
##
## Joins the "hazard_mobs" group — the shared contract for any contact hazard
## on the arena: Bomb._apply_blast's damage loop, Arena.seal_cell /
## break_bridge_at's cleanup, and Player._compute_active_hazard_cells' bot
## awareness all read this group rather than a node type. Every member must
## expose `cell`, `next_cell` (== cell while not moving) and `take_hit()`.

var cell: Vector2i
var arena: Node2D
var dir: Vector2i = Vector2i.ZERO
var next_cell: Vector2i

## Same radius Explosion uses for its own contact check — one physical
## language for "close enough to touch" across every hazard in the game.
const CONTACT_RADIUS := 26.0

const BODY_RADIUS := 16.0
const TOOTH_COUNT := 8
const SPIN_SPEED := 4.5 # radians/sec — fast enough to read as a blade, not a coin
const SAW_COLOR := Color(0.78, 0.80, 0.84)
const SAW_EDGE_COLOR := Color(0.32, 0.34, 0.38)

var _emerged: bool = false

func _ready() -> void:
	add_to_group("hazard_mobs")
	add_to_group("saws") # own kind, only for the MAX_SAWS cap in Arena
	next_cell = cell
	if dir == Vector2i.ZERO:
		dir = _pick_initial_dir()

## Any direction open from the spawn cell, chosen at random rather than always
## the same order — a pit counts as open too, since rolling into one is a
## valid (if short) life for this hazard. If nothing is open at all, the first
## step's own bounce logic sorts it out.
func _pick_initial_dir() -> Vector2i:
	var options: Array[Vector2i] = []
	for d in Consts.DIRECTIONS:
		if arena.is_walkable(cell + d) or arena.is_pit(cell + d):
			options.append(d)
	if options.is_empty():
		return Consts.DIRECTIONS[randi() % Consts.DIRECTIONS.size()]
	return options[randi() % options.size()]

func _on_emerge_timeout() -> void:
	_emerged = true
	$StepTimer.start()

func _process(_delta: float) -> void:
	queue_redraw() # the spin and the emerge grow are both continuous, not tick-based

func _physics_process(_delta: float) -> void:
	if not _emerged:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.alive and position.distance_to(p.position) < CONTACT_RADIUS:
			p.die()

func take_hit() -> void:
	destroy() # one blast is all it takes — no armor, unlike the turret

func destroy() -> void:
	Sfx.play("block_destroy", 1.3)
	queue_free()

func _on_step_timer_timeout() -> void:
	if not is_instance_valid(arena):
		return
	if arena.is_pit(cell + dir):
		Sfx.play("wall_destroy", 0.4) # sinks — duller than a blast, because it isn't one
		queue_free()
		return
	if arena.is_walkable(cell + dir):
		next_cell = cell + dir
		_move()
		return
	dir = _bounce_dir()
	if dir == Vector2i.ZERO:
		return # boxed in on every side this tick — sits still until the next one
	next_cell = cell + dir
	_move()

## The perpendiculars to the current heading, tried before a straight U-turn —
## a real bounce rather than always doubling back. A pit in a perpendicular
## counts as open too: the saw rolls into it and sinks the same way it would
## rolling forward into one.
func _bounce_dir() -> Vector2i:
	# Built with an if/else rather than a ternary: a conditional expression
	# choosing between two array literals doesn't come out typed as
	# Array[Vector2i], and assigning it to one throws at runtime.
	var perp: Array[Vector2i] = []
	if dir.x != 0:
		perp = [Consts.DIR_UP, Consts.DIR_DOWN]
	else:
		perp = [Consts.DIR_LEFT, Consts.DIR_RIGHT]
	perp.shuffle()
	for d in perp:
		if arena.is_walkable(cell + d) or arena.is_pit(cell + d):
			return d
	if arena.is_walkable(cell - dir) or arena.is_pit(cell - dir):
		return -dir
	return Vector2i.ZERO

func _move() -> void:
	cell = next_cell
	create_tween().tween_property(self, "position", arena.cell_to_world(cell), $StepTimer.wait_time)

func _draw() -> void:
	var emerge_t: float = 1.0 if _emerged else clampf(1.0 - $EmergeTimer.time_left / $EmergeTimer.wait_time, 0.0, 1.0)
	if emerge_t <= 0.0:
		return
	var r := BODY_RADIUS * emerge_t
	var spin := Time.get_ticks_msec() / 1000.0 * SPIN_SPEED
	var pts := PackedVector2Array()
	for i in TOOTH_COUNT * 2:
		var a: float = spin + TAU * float(i) / float(TOOTH_COUNT * 2)
		var rad: float = r * (1.0 if i % 2 == 0 else 0.68)
		pts.append(Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, Color(SAW_COLOR, emerge_t))
	draw_circle(Vector2.ZERO, r * 0.3, Color(SAW_EDGE_COLOR, emerge_t))
