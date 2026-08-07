extends Node2D
## Base bomb: 2s fuse, cross-shaped blast stopped by walls, destroys the
## first soft block hit in each direction (an Engineer temp wall dies too, but
## still blocks the blast from going further). Chains into any other bomb its
## blast reaches, and is always pushed into a slide by the Bomb-Kicker
## walking into it — own or an opponent's bomb alike.
##
## The Sapper's bombs are `remote`: no fuse at all, no Timer running, and they
## never go off on their own — only Player._ability_detonate() (or a chain
## reaction from someone else's blast reaching them) sets them off. They carry
## a blinking antenna instead of a burning fuse, so an untriggered one reads
## as "planted and armed", not "about to go off any second".

const ExplosionScene := preload("res://scenes/Explosion.tscn")
const SLIDE_STEP_DURATION := 0.08

signal exploded

@export var radius: int = 2
@export var is_circle_blast: bool = false # Pyro passive: fills a radius instead of a cross
@export var remote: bool = false # Sapper passive: no fuse, detonated only on demand
var cell: Vector2i
var arena: Node2D
var owner_player: Node2D

var has_exploded: bool = false
var is_sliding: bool = false

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
	if not remote:
		$Timer.start()

func _process(_delta: float) -> void:
	if has_exploded:
		return
	if remote:
		_update_antenna_blink()
	else:
		_update_fuse_cue()

# Fuse cue: burns down (shortens toward the bomb) and pulses/glows redder
# faster the closer it is to going off.
func _update_fuse_cue() -> void:
	var t: float = $Timer.time_left / $Timer.wait_time if $Timer.wait_time > 0.0 else 0.0
	var freq: float = lerp(2.0, 12.0, 1.0 - t)
	var phase: float = Time.get_ticks_msec() / 1000.0 * freq
	var pulse: float = 1.0 + 0.15 * absf(sin(phase * PI))
	$BombBody.scale = Vector2.ONE * 1.4 * pulse
	$BombBody.modulate = Color.WHITE.lerp(Color(1.0, 0.25, 0.2), 1.0 - t)

	var tip: Vector2 = FUSE_BASE.lerp(FUSE_TIP_FULL, t)
	$Fuse.points = PackedVector2Array([FUSE_BASE, tip])
	$Spark.position = tip
	$Spark.scale = Vector2.ONE * pulse

## The only "still armed" cue a remote bomb gives — a plain on/off blink, at a
## constant rate, since there's no countdown to race against and nothing
## should read as urgency here.
func _update_antenna_blink() -> void:
	var phase := fmod(Time.get_ticks_msec() / 1000.0, ANTENNA_BLINK_PERIOD)
	$AntennaTip.modulate.a = 1.0 if phase < ANTENNA_BLINK_PERIOD * 0.5 else 0.15

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
	var next_cell := cell + dir
	if not arena.in_bounds(next_cell) or arena.is_wall(next_cell) or arena.is_block(next_cell) or arena.has_bomb_at(next_cell):
		is_sliding = false
		return
	arena.remove_bomb(cell)
	cell = next_cell
	arena.register_bomb(cell, self)
	var tw := create_tween()
	tw.tween_property(self, "position", arena.cell_to_world(cell), SLIDE_STEP_DURATION)
	tw.finished.connect(func():
		if has_exploded:
			return
		_slide_step(dir)
	)
