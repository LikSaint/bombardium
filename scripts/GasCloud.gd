extends Node2D
## Crate hazard: a poison cloud that doesn't chase and doesn't block movement —
## it just makes a patch of the arena unsafe to linger in for a while. The one
## hazard that reads as a zone to route around rather than a point to dodge or
## an object to outrun.
##
## Not built from Arena.blast_cells — this isn't an explosion, it doesn't stop
## dead at the first thing it hits, and it spreads through open ground rather
## than along rays from a centre. Its own short BFS floods out from the spawn
## cell instead, and the flood distance to each cell is also what paces the
## reveal: a cell goes live once _elapsed clears distance * GROWTH_STEP_DURATION,
## which is what reads on screen as the cloud crawling outward ring by ring
## instead of appearing all at once.

const ArenaScript := preload("res://scripts/Arena.gd")

var arena: Node2D
var origin_cell: Vector2i

var _footprint: Dictionary = {}     # Vector2i -> int, BFS distance from origin_cell
var _elapsed: float = 0.0
var _hit_cooldowns: Dictionary = {} # Player node -> float, seconds left before it can hurt that player again

const GAS_MAX_RADIUS := 2
const GROWTH_STEP_DURATION := 0.4   # ring by ring; full radius live by 0.8s
const LIFETIME := 6.0
const FADE_DURATION := LIFETIME * 0.2 # tail of LIFETIME: fades out rather than vanishing on the last frame
## How often the same player can be hurt again while still standing in it —
## not a one-shot: leaving and coming back, or simply staying, both cost more
## than once.
const TICK_COOLDOWN := 0.6

const CLOUD_COLOR := Color(0.42, 0.72, 0.32)

func _ready() -> void:
	add_to_group("gas_clouds")
	_footprint = _flood_fill(origin_cell)

## Cells reachable from `start` through open floor only (walls, crates and
## chasms all stop it, same as they'd stop a footstep) within GAS_MAX_RADIUS
## steps. A bomb sitting on a cell does not block the spread — this is bad air,
## not a body in the way.
func _flood_fill(start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if dist[cur] >= GAS_MAX_RADIUS:
			continue
		for dir in Consts.DIRECTIONS:
			var next: Vector2i = cur + dir
			if dist.has(next):
				continue
			if arena.get_cell_state(next) != ArenaScript.CellState.EMPTY:
				continue
			dist[next] = dist[cur] + 1
			queue.append(next)
	return dist

## Cells that currently hurt to stand in — read by Player._compute_active_hazard_cells
## for bot awareness, and by _process below for the actual damage tick.
func active_cells() -> Dictionary:
	var out := {}
	for c in _footprint:
		if _elapsed >= _footprint[c] * GROWTH_STEP_DURATION:
			out[c] = true
	return out

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return
	for p in _hit_cooldowns.keys():
		_hit_cooldowns[p] = maxf(0.0, _hit_cooldowns[p] - delta)
	var active := active_cells()
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive or _hit_cooldowns.get(p, 0.0) > 0.0:
			continue
		if active.has(arena.world_to_cell(p.position)):
			_hit_cooldowns[p] = TICK_COOLDOWN
			p.die()
	queue_redraw()

func _draw() -> void:
	var fade_start := LIFETIME - FADE_DURATION
	var fade: float = 1.0 if _elapsed <= fade_start else clampf(1.0 - (_elapsed - fade_start) / FADE_DURATION, 0.0, 1.0)
	if fade <= 0.0:
		return
	var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.6)
	var cs := float(Consts.CELL_SIZE)
	for c in active_cells():
		var at: Vector2 = Vector2(c - origin_cell) * cs
		var rect := Rect2(at - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
		draw_rect(rect, Color(CLOUD_COLOR, 0.28 * fade * pulse), true)
