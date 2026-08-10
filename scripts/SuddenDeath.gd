extends Node
## Sudden death. Once a round has run past the Round end setting, permanent walls
## start dropping in one at a time — clockwise from the top centre of the arena
## and spiralling inward — so a stalemate between cautious survivors can't drag
## on forever. The playable area just keeps shrinking until someone is left.
##
## Each wall telegraphs before it lands: a ghost sprite pulses on its cell for
## exactly as long as the current interval — faint, out, stronger, out, stronger
## still — and then snaps to a solid wall. Early on that interval is several
## seconds, so the pulses are a slow, easily-missed hint; by the end it's a
## fraction of a second and the same three pulses read as an alarm going off.
## The interval shrinks geometrically (not linearly) between
## START_INTERVAL and END_INTERVAL, which is what makes the ring feel like it's
## closing slowly and then rushing.
##
## Lives on Main rather than Arena because it's round pacing, not grid state —
## Arena only exposes seal_cell() for it. The scene reloads between rounds, so
## the clock resets by itself.

const START_INTERVAL := 3.0
const END_INTERVAL := 0.28
# The ghost never gets more than half-opaque; the jump to a real wall is the
# whole point of the telegraph, so it has to stay clearly unfinished until then.
const GHOST_MAX_ALPHA := 0.5
# Pulses per telegraph. Three reads as a rhythm you can count on ("that's two,
# it lands on the next one") without turning into a strobe at the end, where the
# whole interval is barely a quarter of a second.
const GHOST_PULSES := 3
# Music creeps up as the walls speed up — a nudge, not a chipmunk.
const MUSIC_MAX_PITCH := 1.12

const WALL_TEXTURE := preload("res://assets/props/wall.png")

var arena: Node2D

var _elapsed: float = 0.0
var _running: bool = false
var _cells: Array[Vector2i] = []
var _dirs: Array[Vector2i] = [] # travel direction at each cell; players get shoved this way
var _index: int = 0
var _interval: float = START_INTERVAL
var _timer: float = 0.0
var _ghost: Sprite2D

func begin(arena_node: Node2D) -> void:
	arena = arena_node
	Music.set_pitch(1.0) # a previous round may have left it sped up
	if not GameManager.round_ended.is_connected(_on_round_ended):
		GameManager.round_ended.connect(_on_round_ended) # GameManager outlives the scene

# The round is decided but the scene lives on for a few seconds of results
# overlay — stop dropping walls, so the winner isn't crushed after winning.
func _on_round_ended(_winner_id: int) -> void:
	_running = false
	_clear_ghost()
	set_process(false)

func _process(delta: float) -> void:
	if arena == null:
		return
	if not _running:
		if not Consts.is_sudden_death_enabled():
			return
		_elapsed += delta
		if _elapsed >= Consts.sudden_death_timer():
			_start()
		return

	_timer += delta
	if _ghost != null:
		_ghost.modulate.a = _ghost_alpha(_timer / _interval)
	if _timer >= _interval:
		_land()

## The telegraph, as a series of pulses rather than one fade: the cell shows
## itself faintly, blinks back out, returns a little more solid, blinks out
## again, and the last pulse holds at its brightest until the wall lands.
##
## A single smooth ramp was the obvious thing and the wrong one. It is hardest
## to see exactly when it matters most — early, at a three-second interval,
## where a slowly brightening square is indistinguishable from the floor not
## changing. Something that appears and disappears is caught by peripheral
## vision even when it is barely there, and each pulse arriving stronger than
## the last is what says the wall is coming *here*, soon. The final pulse holds
## rather than blinking out so the wall never lands out of a gap.
func _ghost_alpha(progress: float) -> float:
	var phase: float = clampf(progress, 0.0, 1.0) * GHOST_PULSES
	var index: int = mini(int(phase), GHOST_PULSES - 1)
	var local: float = phase - float(index)
	var peak: float = GHOST_MAX_ALPHA * float(index + 1) / float(GHOST_PULSES)
	if index == GHOST_PULSES - 1:
		return peak * minf(1.0, local * 2.0)
	return peak * sin(local * PI)

func _start() -> void:
	_cells = _build_spiral()
	_running = true
	_advance()

# Walls in the order they'll drop: outermost playable ring first, each ring
# starting at its top centre and running clockwise, then inward one ring.
# Cells that are already permanent wall (the border, and the checkerboard
# pillars on non-random maps) are skipped so they don't waste a turn.
func _build_spiral() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dirs: Array[Vector2i] = []
	var ring := 1
	while true:
		var x0 := ring
		var y0 := ring
		var x1 := Consts.GRID_WIDTH - 1 - ring
		var y1 := Consts.GRID_HEIGHT - 1 - ring
		if x0 > x1 or y0 > y1:
			break
		var ring_cells: Array[Vector2i] = []
		var ring_dirs: Array[Vector2i] = []
		var seen := {}
		# Clockwise: top row left->right, right column down, bottom row
		# right->left, left column up. `seen` collapses the degenerate rings
		# (a single row, column or cell at the centre) into one pass.
		var walk := func(from: Vector2i, to: Vector2i, step: Vector2i) -> void:
			var cur := from
			while true:
				if not seen.has(cur):
					seen[cur] = true
					ring_cells.append(cur)
					ring_dirs.append(step)
				if cur == to:
					break
				cur += step
		walk.call(Vector2i(x0, y0), Vector2i(x1, y0), Consts.DIR_RIGHT)
		walk.call(Vector2i(x1, y0), Vector2i(x1, y1), Consts.DIR_DOWN)
		walk.call(Vector2i(x1, y1), Vector2i(x0, y1), Consts.DIR_LEFT)
		walk.call(Vector2i(x0, y1), Vector2i(x0, y0), Consts.DIR_UP)

		# Rotate the ring so it opens at the top centre instead of the corner.
		var start_at := _index_of_top_centre(ring_cells, (x0 + x1) / 2, y0)
		for i in ring_cells.size():
			var j: int = (start_at + i) % ring_cells.size()
			cells.append(ring_cells[j])
			dirs.append(ring_dirs[j])
		ring += 1

	# Drop cells that are already solid, keeping cells and dirs in step.
	var out_cells: Array[Vector2i] = []
	_dirs = []
	for i in cells.size():
		if arena.is_wall(cells[i]) and not arena.is_temp_wall(cells[i]):
			continue
		# Open water is impassable already, so filling it in would spend a turn
		# of the ring without taking a cell of ground off anyone. Bridges are
		# the exception whatever state they happen to be in when the spiral is
		# built: a blown one is ground that comes back, and the ring has to be
		# able to take it away for good (seal_cell retires the crossing).
		if arena.is_pit(cells[i]) and not arena.is_bridge(cells[i]):
			continue
		out_cells.append(cells[i])
		_dirs.append(dirs[i])
	return out_cells

func _index_of_top_centre(ring_cells: Array[Vector2i], centre_x: int, top_y: int) -> int:
	var target := Vector2i(centre_x, top_y)
	var found := ring_cells.find(target)
	return found if found != -1 else 0

# Puts the next ghost up, or ends sudden death when the spiral is exhausted.
func _advance() -> void:
	_timer = 0.0
	if _index >= _cells.size():
		_running = false
		_clear_ghost()
		return
	var p: float = float(_index) / maxf(1.0, float(_cells.size() - 1))
	_interval = START_INTERVAL * pow(END_INTERVAL / START_INTERVAL, p)
	Music.set_pitch(lerpf(1.0, MUSIC_MAX_PITCH, p))
	_clear_ghost()
	_ghost = Sprite2D.new()
	_ghost.texture = WALL_TEXTURE
	_ghost.position = arena.cell_to_world(_cells[_index])
	_ghost.modulate.a = 0.0
	arena.add_child(_ghost)
	# The warning has to sit above the floor and below everything standing on it.
	# It used to ask for that with z_index = -1, which is a level *below* the
	# arena's own _draw() — and since that paints every cell with an opaque
	# FLOOR_COLOR, the telegraph was covered by the floor and never visible at
	# all. Ordinary z with the node first among the children is the actual
	# answer: a parent draws before its children, so this lands on top of the
	# floor, while being first keeps it under the blocks, bombs and players.
	arena.move_child(_ghost, 0)

func _land() -> void:
	var cell: Vector2i = _cells[_index]
	var dir: Vector2i = _dirs[_index]
	_clear_ghost()
	arena.seal_cell(cell)
	Sfx.play("wall_place")
	for player in _players_on(cell):
		player.crush(cell, dir)
	_index += 1
	_advance()

func _players_on(cell: Vector2i) -> Array:
	var found: Array = []
	for node in get_tree().get_nodes_in_group("players"):
		if not node.alive:
			continue
		# Where the player *is* is where their centre is. Movement is free-form,
		# so a box merely clipping the sealed cell is not being buried by it —
		# that player is pushed back out by Player's own unstick handling
		# instead of being crushed.
		if node.get_current_cell() == cell:
			found.append(node)
	return found

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
