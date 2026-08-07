extends Node2D
## Owns grid state and renders the arena. Blocking is resolved logically
## (dictionary lookups), not via physics — movement is grid-based, not free.

const BlockScene := preload("res://scenes/Block.tscn")
const TempWallScene := preload("res://scenes/TempWall.tscn")
const PowerupScene := preload("res://scenes/Powerup.tscn")
const WALL_TEXTURE := preload("res://assets/props/wall.png")
const PlayerScript := preload("res://scripts/Player.gd")

enum CellState { EMPTY, WALL, BLOCK }

const BLOCK_DENSITY := 0.6
const FLOOR_COLOR := Color(0.22, 0.24, 0.2)
# Roughly matches the fixed checkerboard pattern's interior wall ratio
# (every even x, even y cell -> ~1/4 of interior cells) when scattering
# indestructible walls randomly instead.
const RANDOM_WALL_DENSITY := 0.22
# Temp walls reuse the destructible block sprite, lightly tinted with the
# placing player's color so it reads as "theirs" without a dedicated asset.
const TEMP_WALL_OWNER_TINT_STRENGTH := 0.35

var cells: Dictionary = {} # Vector2i -> CellState
var blocks_by_cell: Dictionary = {} # Vector2i -> Block node
var bombs_by_cell: Dictionary = {} # Vector2i -> Bomb node
var powerups_by_cell: Dictionary = {} # Vector2i -> Powerup node
var temp_wall_cells: Dictionary = {} # Vector2i -> owner Player node; WALL cells that are a temp wall (not permanent stone), passable only for their owner
var temp_wall_nodes: Dictionary = {} # Vector2i -> TempWall node; lets an explosion free the node early instead of waiting out its timer

func generate() -> void:
	for child in get_children():
		child.queue_free()
	cells.clear()
	blocks_by_cell.clear()
	bombs_by_cell.clear()
	powerups_by_cell.clear()
	temp_wall_cells.clear()
	temp_wall_nodes.clear()

	for x in Consts.GRID_WIDTH:
		for y in Consts.GRID_HEIGHT:
			var cell := Vector2i(x, y)
			if x == 0 or y == 0 or x == Consts.GRID_WIDTH - 1 or y == Consts.GRID_HEIGHT - 1:
				cells[cell] = CellState.WALL
			elif not Consts.random_indestructible_walls and x % 2 == 0 and y % 2 == 0:
				cells[cell] = CellState.WALL
			else:
				cells[cell] = CellState.EMPTY

	var protected_cells := _get_protected_cells()
	if Consts.random_indestructible_walls:
		_scatter_random_walls(protected_cells)

	for cell in cells.keys():
		if cells[cell] != CellState.EMPTY:
			continue
		if protected_cells.has(cell):
			continue
		if randf() < BLOCK_DENSITY:
			_place_block(cell)

	queue_redraw()

# Alternate "map mode": scatter indestructible walls randomly across the
# interior instead of the fixed checkerboard pattern above.
#
# Unlike the checkerboard, random placement can seal the arena into regions
# with no route between them. Survivors stranded in different regions can
# never reach each other, so the last-one-standing check never fires and the
# round runs forever — hence every wall that would break connectivity is
# rejected. Blocks aren't placed yet here, so "not a wall" is exactly "open".
func _scatter_random_walls(protected_cells: Array) -> void:
	for x in range(1, Consts.GRID_WIDTH - 1):
		for y in range(1, Consts.GRID_HEIGHT - 1):
			var cell := Vector2i(x, y)
			if cells[cell] != CellState.EMPTY:
				continue
			if protected_cells.has(cell):
				continue
			if randf() >= RANDOM_WALL_DENSITY:
				continue
			cells[cell] = CellState.WALL
			if not _all_open_cells_connected():
				cells[cell] = CellState.EMPTY

func _all_open_cells_connected() -> bool:
	var open_count := 0
	for cell in cells:
		if cells[cell] != CellState.WALL:
			open_count += 1
	var start: Vector2i = get_spawn_cells()[0]
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for dir in Consts.DIRECTIONS:
			var next: Vector2i = cur + dir
			if seen.has(next) or not cells.has(next) or cells[next] == CellState.WALL:
				continue
			seen[next] = true
			queue.append(next)
	return seen.size() == open_count

func _get_protected_cells() -> Array:
	var protected: Array = []
	for spawn in get_spawn_cells():
		protected.append(spawn)
		for dir in Consts.DIRECTIONS:
			protected.append(spawn + dir)
	return protected

func get_spawn_cells() -> Array:
	return [
		Vector2i(1, 1),
		Vector2i(Consts.GRID_WIDTH - 2, 1),
		Vector2i(1, Consts.GRID_HEIGHT - 2),
		Vector2i(Consts.GRID_WIDTH - 2, Consts.GRID_HEIGHT - 2),
	]

func _place_block(cell: Vector2i) -> void:
	var block := BlockScene.instantiate()
	block.position = cell_to_world(cell)
	add_child(block)
	blocks_by_cell[cell] = block
	cells[cell] = CellState.BLOCK

func destroy_block_at(cell: Vector2i, owner_player: Node = null) -> void:
	if not blocks_by_cell.has(cell):
		return
	blocks_by_cell[cell].destroy()
	blocks_by_cell.erase(cell)
	cells[cell] = CellState.EMPTY

	var powerup_type: int = -1

	if owner_player != null and owner_player.character_id == PlayerScript.CharacterId.PYRO:
		# Pyro: 5% each for RADIUS/SPEED/SHIELD + 15% for BOMB_COUNT = 30% total
		var roll = randf() * 100.0
		if roll < 5.0:
			powerup_type = Consts.PowerupType.RADIUS
		elif roll < 10.0:
			powerup_type = Consts.PowerupType.SPEED
		elif roll < 15.0:
			powerup_type = Consts.PowerupType.SHIELD
		elif roll < 30.0:
			powerup_type = Consts.PowerupType.BOMB_COUNT
	else:
		# Normal: map setting chance, then random type
		if randf() < Consts.powerup_chance_percent / 100.0:
			powerup_type = randi() % 4

	if powerup_type >= 0:
		_spawn_powerup(cell, powerup_type)

func _spawn_powerup(cell: Vector2i, powerup_type: int) -> void:
	var powerup := PowerupScene.instantiate()
	powerup.type = powerup_type
	powerup.position = cell_to_world(cell)
	add_child(powerup)
	powerups_by_cell[cell] = powerup

func has_powerup_at(cell: Vector2i) -> bool:
	return powerups_by_cell.has(cell)

# Explosions never destroy powerups lying on the ground — only players collect them.
func try_collect_powerup(cell: Vector2i, player: Node) -> void:
	if not powerups_by_cell.has(cell):
		return
	var type: int = powerups_by_cell[cell].type
	powerups_by_cell[cell].queue_free()
	powerups_by_cell.erase(cell)
	Sfx.play("powerup_pickup")
	player.apply_powerup(type)

func place_temp_wall(cell: Vector2i, owner: Node = null) -> Node:
	if get_cell_state(cell) != CellState.EMPTY or bombs_by_cell.has(cell):
		return null
	var wall := TempWallScene.instantiate()
	wall.position = cell_to_world(cell)
	wall.cell = cell
	wall.arena = self
	add_child(wall)
	cells[cell] = CellState.WALL
	temp_wall_cells[cell] = owner
	temp_wall_nodes[cell] = wall
	if owner != null:
		wall.modulate = Color.WHITE.lerp(Consts.PLAYER_COLORS[(owner.player_id - 1) % Consts.PLAYER_COLORS.size()], TEMP_WALL_OWNER_TINT_STRENGTH)
	queue_redraw()
	return wall

func remove_temp_wall(cell: Vector2i) -> void:
	if cells.get(cell) == CellState.WALL:
		cells[cell] = CellState.EMPTY
		temp_wall_cells.erase(cell)
		temp_wall_nodes.erase(cell)
		queue_redraw()

func is_temp_wall(cell: Vector2i) -> bool:
	return temp_wall_cells.has(cell)

# Lets an explosion kill a temp wall immediately (see Bomb._explode_cross/
# _explode_circle) instead of leaving its sprite up until its own timer fires.
func destroy_temp_wall_at(cell: Vector2i) -> void:
	if temp_wall_nodes.has(cell):
		temp_wall_nodes[cell].destroy()

# Turns `cell` into permanent stone, clearing whatever was standing on it —
# used by sudden death, which drops walls on the arena regardless of what's in
# the way. A block is removed without its usual powerup roll (the wall would
# just bury it anyway) and a bomb is set off rather than deleted, so its owner
# gets the charge back instead of losing a bomb for the rest of the round.
func seal_cell(cell: Vector2i) -> void:
	if temp_wall_nodes.has(cell):
		temp_wall_nodes[cell].destroy()
	if blocks_by_cell.has(cell):
		blocks_by_cell[cell].destroy()
		blocks_by_cell.erase(cell)
	if powerups_by_cell.has(cell):
		powerups_by_cell[cell].queue_free()
		powerups_by_cell.erase(cell)
	if bombs_by_cell.has(cell):
		bombs_by_cell[cell].explode()
	cells[cell] = CellState.WALL
	queue_redraw()

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < Consts.GRID_WIDTH and cell.y >= 0 and cell.y < Consts.GRID_HEIGHT

func get_cell_state(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return CellState.WALL
	return cells.get(cell, CellState.EMPTY)

func is_wall(cell: Vector2i) -> bool:
	return get_cell_state(cell) == CellState.WALL

func is_block(cell: Vector2i) -> bool:
	return get_cell_state(cell) == CellState.BLOCK

func is_walkable(cell: Vector2i) -> bool:
	if get_cell_state(cell) != CellState.EMPTY:
		return false
	if bombs_by_cell.has(cell):
		return false
	return true

# Same as is_walkable(), except a temp wall is passable for the player who
# placed it (everyone else, bombs, and explosions still treat it as solid).
# Pyro can also walk through their own bombs.
func is_walkable_for(cell: Vector2i, player: Node) -> bool:
	if get_cell_state(cell) == CellState.WALL and temp_wall_cells.get(cell) == player:
		return not bombs_by_cell.has(cell)
	# Pyro can pass through their own bombs
	if player.character_id == PlayerScript.CharacterId.PYRO and bombs_by_cell.has(cell):
		var bomb = bombs_by_cell[cell]
		if bomb.owner_player == player:
			return true
	return is_walkable(cell)

func register_bomb(cell: Vector2i, bomb: Node) -> void:
	bombs_by_cell[cell] = bomb

func remove_bomb(cell: Vector2i) -> void:
	bombs_by_cell.erase(cell)

func has_bomb_at(cell: Vector2i) -> bool:
	return bombs_by_cell.has(cell)

func get_bomb_at(cell: Vector2i) -> Node:
	return bombs_by_cell.get(cell)

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * Consts.CELL_SIZE + Consts.CELL_SIZE / 2.0,
		cell.y * Consts.CELL_SIZE + Consts.CELL_SIZE / 2.0
	)

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / Consts.CELL_SIZE), int(pos.y / Consts.CELL_SIZE))

func _draw() -> void:
	for x in Consts.GRID_WIDTH:
		for y in Consts.GRID_HEIGHT:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * Consts.CELL_SIZE, y * Consts.CELL_SIZE, Consts.CELL_SIZE, Consts.CELL_SIZE)
			var state = cells.get(cell, CellState.EMPTY)
			if state == CellState.WALL and not temp_wall_cells.has(cell):
				draw_texture_rect(WALL_TEXTURE, rect, false)
			else:
				draw_rect(rect, FLOOR_COLOR, true)
				draw_rect(rect, Color(0, 0, 0, 0.15), false, 1.0)
