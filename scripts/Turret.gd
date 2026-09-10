extends Node2D
## Crate hazard: stationary. Doesn't chase and doesn't kill on contact —
## instead fires a shell at the nearest living player on an interval, reusing
## the Grenadier's own thrown-shell flight (Bomb.thrown) with the same
## telegraph: the ring on the landing cell, visible for the whole flight. Two
## armor — dies to a second blast, not the first — because it can't run, so
## putting it down should be a real commitment, not a coincidence of a nearby
## explosion clipping it.
##
## In "hazard_mobs" (see the group note on Bomb._apply_blast) for blast damage
## and sudden-death/bridge cleanup, and in its own "turrets" for the
## one-per-arena cap. next_cell == cell always, since it never moves — the
## hazard_mobs contract every member has to satisfy (see Player's bot-hazard
## reader).

const BombScene := preload("res://scenes/Bomb.tscn")

var cell: Vector2i
var arena: Node2D
var next_cell: Vector2i
var hits_left: int = 2 # toughest contact hazard in the game — matches that it can't flee

const SHOT_RADIUS := 2
## Visible "aiming" tell shown for this long before a shot actually leaves —
## read straight off $FireTimer.time_left in _draw(), the same trick
## Bomb._fuse_ratio uses for its own countdown cue, rather than a second timer
## to keep in step with the first.
const WINDUP_DURATION := 0.4

var _emerged: bool = false

func _ready() -> void:
	add_to_group("hazard_mobs")
	add_to_group("turrets")
	next_cell = cell

func _on_emerge_timeout() -> void:
	_emerged = true
	$FireTimer.start()

func _process(_delta: float) -> void:
	queue_redraw() # the aim tell and the armor ring both animate continuously

func take_hit() -> void:
	hits_left -= 1
	if hits_left > 0:
		Sfx.play("shield_block") # first blast strips the armor, doesn't kill
		return
	destroy()

func destroy() -> void:
	Sfx.play("block_destroy", 0.8)
	queue_free()

func _on_fire_timer_timeout() -> void:
	if not _emerged or not is_instance_valid(arena):
		return
	var target := _nearest_player()
	if target == null:
		return
	var shell := BombScene.instantiate()
	shell.thrown = true
	shell.cell = arena.world_to_cell(target.position)
	shell.arena = arena
	shell.owner_player = null
	shell.radius = SHOT_RADIUS
	shell.position = position # leaves from the turret itself, not from the target's cell
	arena.add_child(shell)
	Sfx.play("bomb_place", 0.8)

func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive:
			continue
		var d: float = position.distance_squared_to(p.position)
		if d < best_dist:
			best_dist = d
			best = p
	return best

const BODY_RADIUS := 15.0
const ARMOR_RING_COLOR := Color(0.5, 0.75, 1.0)
const AIM_COLOR := Color(1.0, 0.35, 0.2)
const BODY_COLOR := Color(0.4, 0.42, 0.46)

func _draw() -> void:
	var emerge_t: float = 1.0 if _emerged else clampf(1.0 - $EmergeTimer.time_left / $EmergeTimer.wait_time, 0.0, 1.0)
	if emerge_t <= 0.0:
		return
	var r := BODY_RADIUS * emerge_t
	draw_circle(Vector2.ZERO, r, Color(BODY_COLOR, emerge_t))
	# The armor ring is the only way to see a hit already landed and didn't
	# kill it — same idea as the mine/creep-style tell everything else in this
	# family uses: a stat you can't see any other way has to be drawn.
	if hits_left > 1:
		draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 20, Color(ARMOR_RING_COLOR, 0.8 * emerge_t), 2.5)
	if _emerged and $FireTimer.time_left <= WINDUP_DURATION:
		var t: float = 1.0 - $FireTimer.time_left / WINDUP_DURATION
		draw_circle(Vector2.ZERO, r * 0.5, Color(AIM_COLOR, t))
