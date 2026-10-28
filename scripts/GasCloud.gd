extends Node2D
## Crate hazard: a patch of fire that doesn't chase and doesn't block movement —
## it just makes a stretch of the arena unsafe to stand in for a while. The one
## hazard that reads as a zone to route around rather than a point to dodge or
## an object to outrun.
##
## (It was a green poison cloud, and nobody could tell what it was: a faint
## green wash over a green floor. It is orange flames now. The class, the scene
## and the "gas_clouds" group keep their old names — the arena and the bots find
## it by those — so only the way it looks and how it is introduced changed.)
##
## It does not go live the instant it appears. For WARMUP_DURATION the cells it is
## about to take are outlined in a pulsing dashed orange and nothing hurts yet, so
## whoever is standing next to the crate that just broke has a moment to step out
## of the footprint instead of learning about it by dying in it.
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
## Seconds since it appeared, *including* the warm-up. Everything that paces the
## fire itself (growth, lifetime, fade) reads _live_time() instead.
var _elapsed: float = 0.0
var _hit_cooldowns: Dictionary = {} # Player node -> float, seconds left before it can hurt that player again

const GAS_MAX_RADIUS := 2
## Outline-only stretch before it can hurt anyone — see the top of the file.
const WARMUP_DURATION := 0.6
const GROWTH_STEP_DURATION := 0.4   # ring by ring; full radius live by 0.8s
const LIFETIME := 6.0
const FADE_DURATION := LIFETIME * 0.2 # tail of LIFETIME: fades out rather than vanishing on the last frame
## How often the same player can be hurt again while still standing in it —
## not a one-shot: leaving and coming back, or simply staying, both cost more
## than once.
const TICK_COOLDOWN := 0.6

const GLOW_COLOR := Color(1.0, 0.36, 0.04)    # the scorched ground under the flames
const FLAME_OUTER_COLOR := Color(1.0, 0.42, 0.08)
const FLAME_INNER_COLOR := Color(1.0, 0.86, 0.3)
const WARNING_COLOR := Color(1.0, 0.5, 0.12)   # the outline of cells that are about to ignite
const FLAMES_PER_CELL := 4

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
	if _elapsed < WARMUP_DURATION:
		return out
	var live := _live_time()
	for c in _footprint:
		if live >= _footprint[c] * GROWTH_STEP_DURATION:
			out[c] = true
	return out

## Seconds the fire has actually been burning: the clock behind its growth, its
## lifetime and its fade, which starts once the warm-up is over.
func _live_time() -> float:
	return maxf(0.0, _elapsed - WARMUP_DURATION)

func _process(delta: float) -> void:
	_elapsed += delta
	if _live_time() >= LIFETIME:
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
	var cs := float(Consts.CELL_SIZE)
	if _elapsed < WARMUP_DURATION:
		_draw_warmup(cs)
		return
	var live := _live_time()
	var fade_start := LIFETIME - FADE_DURATION
	var fade: float = 1.0 if live <= fade_start else clampf(1.0 - (live - fade_start) / FADE_DURATION, 0.0, 1.0)
	if fade <= 0.0:
		return
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.4)
	for c in active_cells():
		var at: Vector2 = Vector2(c - origin_cell) * cs
		_draw_burning_cell(c, at, cs, fade, pulse)

## Not yet burning: each cell of the footprint is outlined, pulsing faster as the
## fire comes up, so the shape it is about to take is on the ground before it is
## lethal.
func _draw_warmup(cs: float) -> void:
	var progress := _elapsed / WARMUP_DURATION
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * (2.0 + 4.0 * progress))
	for c in _footprint:
		var at: Vector2 = Vector2(c - origin_cell) * cs
		var rect := Rect2(at - Vector2(cs, cs) / 2.0, Vector2(cs, cs)).grow(-3.0)
		draw_rect(rect, Color(GLOW_COLOR, 0.10 + 0.12 * pulse), true)
		draw_rect(rect, Color(WARNING_COLOR, 0.55 + 0.4 * pulse), false, 2.5)

## One cell on fire: a warm glow on the floor and a few flame tongues licking up
## out of it. Each tongue has its own phase, derived from where it is rather than
## rolled, so the flicker is stable from frame to frame and differs from cell to
## cell without the fire needing any state of its own.
func _draw_burning_cell(c: Vector2i, at: Vector2, cs: float, fade: float, pulse: float) -> void:
	var rect := Rect2(at - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
	draw_rect(rect, Color(GLOW_COLOR, 0.46 * fade * pulse), true)
	var t := Time.get_ticks_msec() / 1000.0
	for i in FLAMES_PER_CELL:
		var seed := float((c.x * 7 + c.y * 13 + i * 5) % 11) / 11.0 * TAU
		var x := (float(i) - (FLAMES_PER_CELL - 1) / 2.0) * cs * 0.23 + sin(seed) * cs * 0.04
		var base := at + Vector2(x, cs * 0.34)
		var height := cs * (0.62 + 0.16 * sin(t * 9.0 + seed)) * fade
		var sway := sin(t * 5.0 + seed * 1.7) * cs * 0.05
		_draw_flame(base, cs * 0.25, height, sway, Color(FLAME_OUTER_COLOR, 0.92 * fade))
		_draw_flame(base, cs * 0.13, height * 0.62, sway * 0.6, Color(FLAME_INNER_COLOR, 0.95 * fade))

## A single flame tongue: a teardrop that is widest near the bottom and comes to a
## point at the top, leaning by `sway`.
func _draw_flame(base: Vector2, width: float, height: float, sway: float, colour: Color) -> void:
	var half := width / 2.0
	var pts := PackedVector2Array([
		base + Vector2(-half, 0.0),
		base + Vector2(-half * 0.95, -height * 0.35),
		base + Vector2(-half * 0.45 + sway * 0.5, -height * 0.75),
		base + Vector2(sway, -height),
		base + Vector2(half * 0.45 + sway * 0.5, -height * 0.75),
		base + Vector2(half * 0.95, -height * 0.35),
		base + Vector2(half, 0.0),
	])
	draw_colored_polygon(pts, colour)
