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

## It is drawn as what it is — a grenade launcher on a mount, its tube swinging to
## follow the nearest player — rather than as an abstract disc with a dot on it,
## which is what it used to be and what nobody could identify as a turret.

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
## Where the tube is pointing, in radians. Eased toward the nearest player rather
## than snapped, so it visibly *tracks* them — and so the tube is already lined up
## on someone by the time the windup starts.
var _aim_angle: float = PI / 2.0
## 1.0 the instant a shell leaves, draining to 0: the tube kicks back and the
## muzzle flashes while it is above zero.
var _recoil: float = 0.0
const AIM_TURN_RATE := 7.0
const RECOIL_DRAIN := 4.5

func _ready() -> void:
	add_to_group("hazard_mobs")
	add_to_group("turrets")
	next_cell = cell

func _on_emerge_timeout() -> void:
	_emerged = true
	$FireTimer.start()

func _process(delta: float) -> void:
	if _emerged:
		var target := _nearest_player()
		if target != null:
			var want: float = (target.position - position).angle()
			_aim_angle = lerp_angle(_aim_angle, want, clampf(delta * AIM_TURN_RATE, 0.0, 1.0))
	_recoil = maxf(0.0, _recoil - delta * RECOIL_DRAIN)
	queue_redraw() # the tube, the windup glow and the armor ring all animate continuously

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
	# Leaves from the muzzle of the tube, which is pointing at the target, rather than
	# from the middle of the mount — otherwise the shell sprite sits on top of the very
	# launcher it is supposed to be coming out of.
	shell.position = position + Vector2.from_angle(_aim_angle) * TUBE_FRONT
	arena.add_child(shell)
	_recoil = 1.0
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

const BASE_RADIUS := 19.0
const ARMOR_RING_COLOR := Color(0.5, 0.75, 1.0)
const AIM_COLOR := Color(1.0, 0.35, 0.2)
const BASE_COLOR := Color(0.30, 0.32, 0.36)
const BASE_EDGE_COLOR := Color(0.12, 0.13, 0.15)
const TUBE_COLOR := Color(0.33, 0.38, 0.27)      # olive drab, like the Grenadier's own launcher
const TUBE_SHADE_COLOR := Color(0.2, 0.24, 0.16)
const TUBE_BAND_COLOR := Color(0.62, 0.64, 0.6)
const MUZZLE_COLOR := Color(0.5, 0.52, 0.5)
const FLASH_COLOR := Color(1.0, 0.8, 0.3)
## Tube geometry in its own space, pointing along +x from the pivot.
const TUBE_BACK := -9.0
const TUBE_FRONT := 29.0
const TUBE_HALF_WIDTH := 8.0
const RECOIL_KICK := 7.0

func _draw() -> void:
	var emerge_t: float = 1.0 if _emerged else clampf(1.0 - $EmergeTimer.time_left / $EmergeTimer.wait_time, 0.0, 1.0)
	if emerge_t <= 0.0:
		return
	var windup := 0.0
	if _emerged and $FireTimer.time_left <= WINDUP_DURATION:
		windup = 1.0 - $FireTimer.time_left / WINDUP_DURATION

	# The mount: a squat round plate with bolts, so the tube has something to sit on.
	var r := BASE_RADIUS * emerge_t
	draw_circle(Vector2.ZERO, r + 2.0, Color(BASE_EDGE_COLOR, emerge_t))
	draw_circle(Vector2.ZERO, r, Color(BASE_COLOR, emerge_t))
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		draw_circle(Vector2(cos(a), sin(a)) * r * 0.72, 1.8 * emerge_t, Color(BASE_EDGE_COLOR, emerge_t))
	# The armor ring is the only way to see a hit already landed and didn't
	# kill it — a stat you can't see any other way has to be drawn.
	if hits_left > 1:
		draw_arc(Vector2.ZERO, r + 5.0, 0.0, TAU, 24, Color(ARMOR_RING_COLOR, 0.85 * emerge_t), 2.5)

	# The launcher: drawn along +x and rotated onto the target, scaled in as it emerges.
	draw_set_transform(Vector2.ZERO, _aim_angle, Vector2.ONE * emerge_t)
	var kick := -_recoil * RECOIL_KICK
	var back := TUBE_BACK + kick
	var front := TUBE_FRONT + kick
	var w := TUBE_HALF_WIDTH
	# breech block behind the tube
	draw_rect(Rect2(Vector2(back - 4.0, -w - 2.0), Vector2(6.0, (w + 2.0) * 2.0)), BASE_EDGE_COLOR)
	# the tube, with a darker lower half so it reads as round rather than flat
	draw_rect(Rect2(Vector2(back, -w), Vector2(front - back, w * 2.0)), TUBE_COLOR)
	draw_rect(Rect2(Vector2(back, 1.0), Vector2(front - back, w - 1.0)), TUBE_SHADE_COLOR)
	# reinforcing bands
	for bx in [back + 7.0, back + 19.0]:
		draw_rect(Rect2(Vector2(bx, -w - 1.0), Vector2(3.0, w * 2.0 + 2.0)), TUBE_BAND_COLOR)
	# flared muzzle, and the mouth of the tube in it
	draw_rect(Rect2(Vector2(front - 2.0, -w - 3.0), Vector2(6.0, w * 2.0 + 6.0)), MUZZLE_COLOR)
	draw_rect(Rect2(Vector2(front - 2.0, -w - 3.0), Vector2(6.0, 2.0)), TUBE_BAND_COLOR)
	var mouth := Vector2(front + 3.0, 0.0)
	draw_circle(mouth, 5.0, BASE_EDGE_COLOR)
	if windup > 0.0:
		# A shell is chambered and the mouth is heating up: it grows and brightens
		# until the shot leaves, which is the tell for "this is about to fire".
		draw_circle(mouth, 5.0, Color(AIM_COLOR, 0.35 + 0.55 * windup))
		draw_circle(mouth, 2.0 + 2.5 * windup, Color(0.08, 0.08, 0.08))
	if _recoil > 0.0:
		draw_circle(mouth + Vector2(4.0, 0.0), 9.0 * _recoil + 3.0, Color(FLASH_COLOR, 0.85 * _recoil))
	# pivot cap over the join between tube and mount
	draw_circle(Vector2.ZERO, 6.0, Color(BASE_EDGE_COLOR, 1.0))
	draw_circle(Vector2.ZERO, 4.0, Color(BASE_COLOR.lightened(0.15), 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
