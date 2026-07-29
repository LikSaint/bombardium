extends Node2D
## Base bomb: 2s fuse, cross-shaped blast stopped by walls, destroys the
## first soft block hit in each direction (an Engineer temp wall dies too, but
## still blocks the blast from going further). Chains into any other bomb its
## blast reaches, and is always pushed into a slide by the Bomb-Kicker
## walking into it — own or an opponent's bomb alike.

const ExplosionScene := preload("res://scenes/Explosion.tscn")
const SLIDE_STEP_DURATION := 0.08

signal exploded

@export var radius: int = 2
@export var is_circle_blast: bool = false # Pyro passive: fills a radius instead of a cross
var cell: Vector2i
var arena: Node2D
var owner_player: Node2D

var has_exploded: bool = false
var is_sliding: bool = false

const FUSE_BASE := Vector2(8, -6)
const FUSE_TIP_FULL := Vector2(20, -20)

func _ready() -> void:
	arena.register_bomb(cell, self)
	$BombBody.texture = Consts.BOMB_TEXTURE

# Fuse cue: burns down (shortens toward the bomb) and pulses/glows redder
# faster the closer it is to going off.
func _process(_delta: float) -> void:
	if has_exploded:
		return
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

func _on_timer_timeout() -> void:
	explode()

func explode() -> void:
	if has_exploded:
		return
	has_exploded = true
	arena.remove_bomb(cell)
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
				arena.destroy_block_at(c)
				break

func _explode_circle() -> void:
	# Pyro: diamond blast. Each block/temp wall pierced reduces remaining range by 1.
	_spawn_explosion(cell)
	if arena.is_temp_wall(cell):
		arena.destroy_temp_wall_at(cell)

	# 4 cardinal directions
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for dir in directions:
		var blocks_hit = 0
		for i in range(1, radius + 1):
			var c: Vector2i = cell + dir * i
			if not arena.in_bounds(c):
				break
			if arena.is_wall(c):
				# Permanent wall stops blast
				break

			var is_destructible = arena.is_temp_wall(c) or arena.is_block(c)

			# If position exceeds radius minus blocks hit, only continue if destructible
			if i > radius - blocks_hit:
				if is_destructible:
					_spawn_explosion(c)
					if arena.is_temp_wall(c):
						arena.destroy_temp_wall_at(c)
					elif arena.is_block(c):
						arena.destroy_block_at(c)
					blocks_hit += 1
				break

			if is_destructible:
				_spawn_explosion(c)
				if arena.is_temp_wall(c):
					arena.destroy_temp_wall_at(c)
				elif arena.is_block(c):
					arena.destroy_block_at(c)
				blocks_hit += 1
			else:
				_spawn_explosion(c)
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
