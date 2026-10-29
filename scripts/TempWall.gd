extends Node2D
## The Engineer's wall. It blocks movement until it times out or is blown up, and it
## comes in three levels (see Player._build_tick): the level is how many blasts it
## takes to bring down, and the picture changes with it — wood, then stone and iron,
## then steel and gold — so how tough one is can be read from across the arena. A
## wall that has taken a hit and survived shows cracks.
##
## A level-3 wall can be turned into a mini-turret (see Player._finish_turret_upgrade): the
## Engineer holds the build button aimed at it, and while they do a ghost of the turret
## comes up on the wall, getting more solid until it is real. A bomb charge stays spent for as
## long as the turret stands, and from then on it lobs a small shell at the nearest enemy
## every few seconds.
##
## Walls and turrets both live for a minute (LIFETIME). Building a wall up a level gives it a
## fresh minute, and so does turning it into a turret: a turret has a full minute of its own from
## the moment it is made, which is a minute a bomb charge is spent. What keeps an Engineer from
## laying the whole map over a round is the cap — one wall per bomb they have — and the minute:
## the walls go on expiring, so the budget comes back.

## How long a wall, or a turret, stands before it comes down by itself.
const LIFETIME := 60.0

const BombScene := preload("res://scenes/Bomb.tscn")
const MAX_LEVEL := 3
const TEXTURES: Array[Texture2D] = [
	preload("res://assets/props/temp_wall_1.png"),
	preload("res://assets/props/temp_wall_2.png"),
	preload("res://assets/props/temp_wall_3.png"),
]

var cell: Vector2i
var arena: Node2D
## How tough it was built, 1..MAX_LEVEL. Picks the sprite.
var level: int = 1
## Blasts left in it. Starts equal to level.
var hp: int = 1

# --- Turret mode --------------------------------------------------------------
const TURRET_INTERVAL := 3.0       # seconds between shells
const TURRET_WINDUP := 0.5         # the muzzle glows for this long before one leaves
const TURRET_RANGE := 7.0          # cells; further than that nobody is worth a shell
const TURRET_MIN_RANGE := 2.0
const TURRET_RADIUS := 1           # a small blast: it is a bomb's worth of turret, not a mortar
## What a turret can take: it is a launcher bolted to the wall, not the wall, so it drops
## from the three blasts a level-3 wall stands to the one shield it carries — the first
## blast breaks the shield and leaves it standing, the second brings it down.
const TURRET_SHIELDS := 1

## The turret takes after whoever built it, in two ways, both of them half of what they
## would be for the Engineer themselves:
##
##   * Its blast is TURRET_RADIUS plus half of the radius bonus the Engineer has collected
##     (rounded down) — the same halving the Grenadier's shell gets, for the same reason: a
##     blast powerup is worth half as much to a launcher as to a bomb on the floor.
##   * Their speed shortens the time between shells, by half the proportion it shortens
##     their own step: each speed powerup the Engineer has taken makes it about 5% quicker.
const TURRET_SPEED_SHARE := 0.5

## Blast radius of the shell, in cells.
func _turret_radius() -> int:
	if not is_instance_valid(turret_owner):
		return TURRET_RADIUS
	return TURRET_RADIUS + (turret_owner.bomb_radius - 1) / 2

## Seconds between shells right now.
func _turret_interval() -> float:
	if not is_instance_valid(turret_owner):
		return TURRET_INTERVAL
	var pace: float = clampf(turret_owner.move_duration / turret_owner.BASE_MOVE_DURATION, 0.25, 1.0)
	return TURRET_INTERVAL * (1.0 - TURRET_SPEED_SHARE * (1.0 - pace))
var is_turret: bool = false
var turret_owner: Node = null
## 0..1 while the builder is holding the button to turn this wall into a turret — how far
## along they are, which is how solid the ghost of the turret drawn on it is — and -1
## otherwise. Set by the Engineer every frame of the hold (see Player), not by the wall: the
## wall's own picture covers anything the Engineer could draw from their side.
var upgrade_progress: float = -1.0
var _ghost_angle: float = 0.0
var _fire_clock: float = 0.0
var _aim_angle: float = 0.0
var _recoil: float = 0.0

func _ready() -> void:
	# The sprite is a child, and a child draws over its parent's own _draw — which
	# would bury the cracks and the turret under the wall. Behind the parent instead.
	$Sprite.show_behind_parent = true
	_refresh_sprite()
	$Timer.start(LIFETIME)

func _refresh_sprite() -> void:
	$Sprite.texture = TEXTURES[clampi(level, 1, MAX_LEVEL) - 1]
	queue_redraw()

## Builds the wall up to `new_level`, repairs it fully and gives it a fresh minute. Returns
## false if it is already at least that.
func raise_to(new_level: int) -> bool:
	new_level = clampi(new_level, 1, MAX_LEVEL)
	if new_level <= level:
		return false
	level = new_level
	hp = level
	$Timer.start(LIFETIME)
	_refresh_sprite()
	return true

## How long its builder is untouchable after the wall they were standing in comes down:
## the blast that did it lingers on the cell for a moment, and they have just lost the
## wall that was taking it for them.
const BREAK_GRACE := 0.6

## A blast reached it. It takes one hit and stands, or — on its last — comes down. Anyone
## sheltering inside takes nothing either way (see Player.is_sheltered): the wall is what
## is hit, and when it falls its builder is given BREAK_GRACE to step clear.
func hit(_breaker: Node) -> void:
	hp -= 1
	if hp > 0:
		Sfx.play("shield_block", 0.9)
		queue_redraw()
		return
	var occupant: Node = arena.temp_wall_cells.get(cell)
	var was_inside: bool = occupant != null and is_instance_valid(occupant) and occupant.alive and occupant.get_current_cell() == cell
	destroy()
	if was_inside:
		occupant.grant_silent_grace(BREAK_GRACE)

func _on_timer_timeout() -> void:
	destroy()

func destroy() -> void:
	Sfx.play("wall_destroy")
	# A turret holds one of its owner's bomb charges for as long as it stands; the
	# charge comes back with it, however it went.
	if is_turret and is_instance_valid(turret_owner):
		turret_owner.bomb_count_current = mini(turret_owner.bomb_count_current + 1, turret_owner.bomb_count_max)
		turret_owner.stats_changed.emit()
	arena.remove_temp_wall(cell)
	queue_free()

## Turns this wall into a turret for the owner. Only a level-3 wall is one, and only
## once; the caller pays the bomb charge (see Player._finish_turret_upgrade).
func make_turret(owner_player: Node) -> void:
	is_turret = true
	hp = 1 + TURRET_SHIELDS
	turret_owner = owner_player
	_fire_clock = 0.0
	$Timer.start(LIFETIME) # its own minute, from now
	Sfx.play("wall_place", 1.3)
	queue_redraw()

func set_upgrade_progress(progress: float, angle: float) -> void:
	upgrade_progress = progress
	_ghost_angle = angle
	queue_redraw()

func clear_upgrade_progress() -> void:
	if upgrade_progress < 0.0:
		return
	upgrade_progress = -1.0
	queue_redraw()

func _process(delta: float) -> void:
	if not is_turret:
		return
	_recoil = maxf(0.0, _recoil - delta * 4.5)
	var target := _nearest_enemy()
	if target != null:
		var want: float = (target.position - position).angle()
		_aim_angle = lerp_angle(_aim_angle, want, clampf(delta * 7.0, 0.0, 1.0))
	var interval := _turret_interval()
	_fire_clock = minf(_fire_clock + delta, interval)
	if _fire_clock >= interval and target != null:
		if _fire_at(target):
			_fire_clock = 0.0
	queue_redraw()

## The nearest living player that is not the owner, within range, and not so close
## that the shell would come down on the owner as well.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not p.alive or p == turret_owner:
			continue
		var d: float = position.distance_to(p.position) / float(Consts.CELL_SIZE)
		if d > TURRET_RANGE or d < TURRET_MIN_RANGE or d >= best_dist:
			continue
		best_dist = d
		best = p
	return best

func _fire_at(target: Node2D) -> bool:
	var landing: Vector2i = arena.world_to_cell(target.position)
	# Never a shell that would catch the person who built the turret.
	if is_instance_valid(turret_owner) and arena.blast_cells(landing, _turret_radius(), false).has(turret_owner.get_current_cell()):
		return false
	var shell := BombScene.instantiate()
	shell.thrown = true
	shell.cell = landing
	shell.arena = arena
	shell.owner_player = turret_owner
	shell.radius = _turret_radius()
	shell.position = position + Vector2.from_angle(_aim_angle) * 22.0
	arena.add_child(shell)
	_recoil = 1.0
	Sfx.play("bomb_place", 0.9)
	return true

const CRACK_COLOR := Color(0.07, 0.05, 0.05, 0.9)
const TUBE_COLOR := Color(0.33, 0.38, 0.27)
const TUBE_SHADE_COLOR := Color(0.2, 0.24, 0.16)
const TUBE_BAND_COLOR := Color(0.62, 0.64, 0.6)
const MUZZLE_COLOR := Color(0.5, 0.52, 0.5)
const MOUNT_COLOR := Color(0.12, 0.13, 0.15)
const AIM_COLOR := Color(1.0, 0.35, 0.2)
const FLASH_COLOR := Color(1.0, 0.8, 0.3)
const SHIELD_COLOR := Color(0.5, 0.75, 1.0)

func _draw() -> void:
	if is_turret:
		_draw_launcher(1.0, _aim_angle, true)
		_draw_shield()
		return
	# Damage: one crack per hit taken, so a level-3 wall that has survived two blasts
	# is visibly on its last. (A turret has no cracks: its shield going is the tell.)
	var taken := level - hp
	if taken >= 1:
		draw_polyline(PackedVector2Array([Vector2(-22, -26), Vector2(-14, -12), Vector2(-20, -2), Vector2(-8, 12)]), CRACK_COLOR, 3.0)
	if taken >= 2:
		draw_polyline(PackedVector2Array([Vector2(24, -22), Vector2(14, -8), Vector2(22, 4), Vector2(10, 20)]), CRACK_COLOR, 3.0)
	# Being turned into a turret: the turret, as a ghost that fills in as the hold goes on.
	# No progress ring on it — the dial at the builder's feet is the timer.
	if upgrade_progress >= 0.0:
		_draw_launcher(_ghost_alpha(), _ghost_angle, false)

## How solid the ghost turret is right now. It starts faint and **blinks**, and the blinking
## never stops, but the floor it blinks down to and the peak it blinks up to both rise with
## the hold, so the turret becomes less and less transparent until it is the real one.
const GHOST_BLINK_RATE := 3.0 # cycles per second
func _ghost_alpha() -> float:
	var solid := 0.2 + 0.6 * upgrade_progress # how solid it is, before the blink
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * GHOST_BLINK_RATE)
	return solid * (0.35 + 0.65 * blink)

## A small launcher mounted on top of the wall: a round base and a tube that turns to
## follow the nearest enemy, glows before a shot and kicks back after it. `alpha` fades the
## whole thing, which is how the ghost of one is drawn; `live` is whether it is a working
## turret, with a windup and recoil, rather than a picture of one.
func _draw_launcher(alpha: float, angle: float, live: bool) -> void:
	draw_circle(Vector2.ZERO, 13.0, _fade(MOUNT_COLOR, alpha))
	draw_circle(Vector2.ZERO, 11.0, _fade(Color(0.34, 0.36, 0.4), alpha))
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	var kick := -_recoil * 5.0 if live else 0.0
	draw_rect(Rect2(Vector2(-4.0 + kick, -5.0), Vector2(26.0, 10.0)), _fade(TUBE_COLOR, alpha))
	draw_rect(Rect2(Vector2(-4.0 + kick, 1.0), Vector2(26.0, 4.0)), _fade(TUBE_SHADE_COLOR, alpha))
	draw_rect(Rect2(Vector2(6.0 + kick, -6.0), Vector2(3.0, 12.0)), _fade(TUBE_BAND_COLOR, alpha))
	draw_rect(Rect2(Vector2(20.0 + kick, -7.0), Vector2(5.0, 14.0)), _fade(MUZZLE_COLOR, alpha))
	var mouth := Vector2(26.0 + kick, 0.0)
	draw_circle(mouth, 4.0, _fade(MOUNT_COLOR, alpha))
	if live:
		var windup := clampf((_fire_clock - (_turret_interval() - TURRET_WINDUP)) / TURRET_WINDUP, 0.0, 1.0)
		if windup > 0.0:
			draw_circle(mouth, 4.0, Color(AIM_COLOR, 0.35 + 0.55 * windup))
		if _recoil > 0.0:
			draw_circle(mouth + Vector2(4.0, 0.0), 7.0 * _recoil + 2.0, Color(FLASH_COLOR, 0.85 * _recoil))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, 4.0, _fade(MOUNT_COLOR, alpha))

func _fade(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * alpha)

## The turret's shield, while it holds: a ring round the mount and the shield icon on the
## corner of the wall. When a blast breaks it both go, and the next one is the last.
func _draw_shield() -> void:
	if hp > 1:
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(SHIELD_COLOR, 0.9), 2.5)
		var icon: Texture2D = Consts.STAT_ICONS[Consts.PowerupType.SHIELD]
		var size := icon.get_size() * 0.26
		draw_texture_rect(icon, Rect2(Vector2(-27.0, -27.0), size), false)
