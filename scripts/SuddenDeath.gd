extends Node
## Sudden death. Once a round has run for START_AFTER_SECONDS, permanent walls
## start dropping in one at a time — clockwise from the top centre of the arena
## and spiralling inward — so a stalemate between cautious survivors can't drag
## on forever. The playable area just keeps shrinking until someone is left.
##
## Each wall telegraphs before it lands: a ghost sprite fades up on its cell for
## exactly as long as the current interval, then snaps to a solid wall. Early on
## that interval is several seconds, so the ghost is a barely-visible hint that
## creeps in; by the end it's a fraction of a second and the wall may as well
## appear instantly. The interval shrinks geometrically (not linearly) between
## START_INTERVAL and END_INTERVAL, which is what makes the ring feel like it's
## closing slowly and then rushing.
##
## Lives on Main rather than Arena because it's round pacing, not grid state —
## Arena only exposes seal_cell() for it. The scene reloads between rounds, so
## the 5-minute clock resets by itself.

const START_AFTER_SECONDS := 300.0
const START_INTERVAL := 3.0
const END_INTERVAL := 0.28
# The ghost never gets more than half-opaque; the jump to a real wall is the
# whole point of the telegraph, so it has to stay clearly unfinished until then.
const GHOST_MAX_ALPHA := 0.5
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
		_elapsed += delta
		if _elapsed >= START_AFTER_SECONDS:
			_start()
		return

	_timer += delta
	if _ghost != null:
		# Quadratic ease-in: the ghost lingers near-invisible for most of the
		# wait and only becomes obvious right before it turns solid.
		var progress: float = clampf(_timer / _interval, 0.0, 1.0)
		_ghost.modulate.a = GHOST_MAX_ALPHA * progress * progress
	if _timer >= _interval:
		_land()

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
	_ghost.z_index = -1 # under the players, so nobody is hidden by the warning
	arena.add_child(_ghost)

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
		# Mid-step players count as being wherever they're drawn, not just where
		# their move started, so a wall landing on them still connects.
		if node.current_cell == cell or arena.world_to_cell(node.position) == cell:
			found.append(node)
	return found

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
