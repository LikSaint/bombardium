extends Node2D
## Owns grid state and renders the arena. Blocking is resolved logically
## (dictionary lookups), not via physics — movement is grid-based, not free.

const BlockScene := preload("res://scenes/Block.tscn")
const TempWallScene := preload("res://scenes/TempWall.tscn")
const PowerupScene := preload("res://scenes/Powerup.tscn")
const WALL_TEXTURE := preload("res://assets/props/wall.png")
const PlayerScript := preload("res://scripts/Player.gd")

## A chasm is a hole in the map, not a wall: nobody crosses it, but blasts fly
## straight over it. That difference is the whole reason it isn't just another
## WALL value — a river that also stopped explosions would turn the Bridges
## layout into two arenas that never touch until somebody walks across, which
## is exactly the standoff the bridges are supposed to create tension around
## rather than enforce.
enum CellState { EMPTY, WALL, BLOCK, CHASM }

const BLOCK_DENSITY := 0.6
const FLOOR_COLOR := Color(0.22, 0.24, 0.2)
# Roughly matches the fixed checkerboard pattern's interior wall ratio
# (every even x, even y cell -> ~1/4 of interior cells) when scattering
# indestructible walls randomly instead.
const RANDOM_WALL_DENSITY := 0.22
# Temp walls reuse the destructible block sprite, lightly tinted with the
# placing player's color so it reads as "theirs" without a dedicated asset.
const TEMP_WALL_OWNER_TINT_STRENGTH := 0.35

## What it costs the Pyro's blast to punch through something, on top of the step
## onto the cell itself. Nothing is proof against it and nothing is free: cover
## buys range off the fire rather than stopping it dead, and how much it buys is
## the whole difference between the two kinds of cover.
##
## A crate is a delay — at 1 the piercing first shows at radius 3 and grows a
## cell at a time from there, so a crate wall is worth ducking behind early and
## stops being worth much later, which is the "punches through crates a bit" the
## character's description promises.
##
## Stone is a wall in every sense but absolute — at 3 nothing gets through one
## below radius 5, and even a maxed Pyro only gets a cell or two out the far
## side. That is the number to move if permanent cover feels wrong: 4 makes
## stone very nearly the hard stop it used to be, 2 makes it barely thicker than
## a crate.
const CRATE_PIERCE_COST := 1
const WALL_PIERCE_COST := 3

var cells: Dictionary = {} # Vector2i -> CellState
var blocks_by_cell: Dictionary = {} # Vector2i -> Block node
var bombs_by_cell: Dictionary = {} # Vector2i -> Bomb node
var powerups_by_cell: Dictionary = {} # Vector2i -> Powerup node
var temp_wall_cells: Dictionary = {} # Vector2i -> owner Player node; WALL cells that are a temp wall (not permanent stone), passable only for their owner
var temp_wall_nodes: Dictionary = {} # Vector2i -> TempWall node; lets an explosion free the node early instead of waiting out its timer
## Vector2i -> {"axis": Vector2i, "repair": float, "timer": float}. See the
## bridge section further down.
var bridges: Dictionary = {}

## Which terrain the current round is being played on, resolved once per round
## in generate() so the Random setting rolls per round. Main reads it to name
## the map on screen.
var layout_id: String = Consts.LAYOUT_CLASSIC
## Block density for this layout — Plaza raises it, everything else leaves it
## at the default.
var _block_density: float = BLOCK_DENSITY

func generate() -> void:
	for child in get_children():
		child.queue_free()
	cells.clear()
	blocks_by_cell.clear()
	bombs_by_cell.clear()
	powerups_by_cell.clear()
	temp_wall_cells.clear()
	temp_wall_nodes.clear()
	bridges.clear()
	_block_density = BLOCK_DENSITY

	for x in Consts.GRID_WIDTH:
		for y in Consts.GRID_HEIGHT:
			var cell := Vector2i(x, y)
			if x == 0 or y == 0 or x == Consts.GRID_WIDTH - 1 or y == Consts.GRID_HEIGHT - 1:
				cells[cell] = CellState.WALL
			elif not Consts.random_indestructible_walls and x % 2 == 0 and y % 2 == 0:
				cells[cell] = CellState.WALL
			else:
				cells[cell] = CellState.EMPTY

	# Terrain is carved before anything is scattered on top of it, so the
	# connectivity guard on random walls and the block pass both see the
	# finished shape of the map rather than the bare checkerboard.
	var protected_cells := _get_protected_cells()
	layout_id = Consts.resolve_map_layout()
	_apply_layout(protected_cells)

	if Consts.random_indestructible_walls:
		_scatter_random_walls(protected_cells)

	for cell in cells.keys():
		if cells[cell] != CellState.EMPTY:
			continue
		if protected_cells.has(cell):
			continue
		if randf() < _block_density:
			_place_block(cell)

	queue_redraw()

# --- Terrain layouts -------------------------------------------------------
#
# Each carver works on the already-built base pattern and may add to
# `protected`, which is the set of cells the later passes must leave alone. A
# carver protecting a cell is how it says "this one is load-bearing" — the far
# side of a doorway, the banks a bridge lands on, the open floor a plaza is
# made of — and it is what keeps a layout from being quietly undone by a
# random wall or a crate dropped in the one gap that mattered.

func _apply_layout(protected: Dictionary) -> void:
	match layout_id:
		Consts.LAYOUT_BRIDGES:
			_carve_bridges(protected)
		Consts.LAYOUT_CRATER:
			_carve_crater(protected)
		Consts.LAYOUT_QUARTERS:
			_carve_quarters(protected)
		Consts.LAYOUT_PLAZA:
			_carve_plaza(protected)

## Bridges: a chasm splits the arena down the middle and two crossings are the
## only way over. Spawns sit two to a side, so the opening minutes are a
## two-versus-two across a gap that either pair can close by blowing a bridge.
func _carve_bridges(protected: Dictionary) -> void:
	var x: int = Consts.GRID_WIDTH / 2
	for y in range(1, Consts.GRID_HEIGHT - 1):
		cells[Vector2i(x, y)] = CellState.CHASM
	# A quarter and three quarters down: far enough apart that holding both is
	# a real commitment, and neither is on the row a spawn camps.
	for y in [Consts.GRID_HEIGHT / 4, Consts.GRID_HEIGHT - 1 - Consts.GRID_HEIGHT / 4]:
		_add_bridge(Vector2i(x, y), Consts.DIR_RIGHT, protected)

## Crater: a ring of chasm around a small central plateau, four ways in. The
## middle is the safest ground on the map right up until somebody drops the
## bridge behind you.
func _carve_crater(protected: Dictionary) -> void:
	var centre := Vector2i(Consts.GRID_WIDTH / 2, Consts.GRID_HEIGHT / 2)
	const RING := 2
	for dx in range(-RING, RING + 1):
		for dy in range(-RING, RING + 1):
			var cell: Vector2i = centre + Vector2i(dx, dy)
			if maxi(absi(dx), absi(dy)) == RING:
				cells[cell] = CellState.CHASM
			else:
				cells[cell] = CellState.EMPTY
				protected[cell] = true
	for dir in Consts.DIRECTIONS:
		_add_bridge(centre + dir * RING, dir, protected)

## Quarters: a solid wall cross cuts the arena into four rooms joined by four
## doorways. No chasms at all — this one is about corners and choke points
## rather than about crossings that can be taken away.
func _carve_quarters(protected: Dictionary) -> void:
	var cx: int = Consts.GRID_WIDTH / 2
	var cy: int = Consts.GRID_HEIGHT / 2
	var door_ys := [Consts.GRID_HEIGHT / 4, Consts.GRID_HEIGHT - 1 - Consts.GRID_HEIGHT / 4]
	var door_xs := [Consts.GRID_WIDTH / 4, Consts.GRID_WIDTH - 1 - Consts.GRID_WIDTH / 4]
	for y in range(1, Consts.GRID_HEIGHT - 1):
		cells[Vector2i(cx, y)] = CellState.WALL
	for x in range(1, Consts.GRID_WIDTH - 1):
		cells[Vector2i(x, cy)] = CellState.WALL
	for y in door_ys:
		_open_doorway(Vector2i(cx, y), Consts.DIR_RIGHT, protected)
	for x in door_xs:
		_open_doorway(Vector2i(x, cy), Consts.DIR_DOWN, protected)

## Plaza: the middle is swept clear of everything and the crates pile up around
## it. Nowhere to hide in the centre, nowhere to move at the edges — the
## opposite trade to every other layout here.
func _carve_plaza(protected: Dictionary) -> void:
	var centre := Vector2i(Consts.GRID_WIDTH / 2, Consts.GRID_HEIGHT / 2)
	var half := Vector2i(Consts.GRID_WIDTH / 4, Consts.GRID_HEIGHT / 4)
	for dx in range(-half.x, half.x + 1):
		for dy in range(-half.y, half.y + 1):
			var cell: Vector2i = centre + Vector2i(dx, dy)
			if not in_bounds(cell) or _is_border(cell):
				continue
			cells[cell] = CellState.EMPTY
			protected[cell] = true
	_block_density = 0.85

## A gap in a layout's wall, plus the cell on either side of it. Clearing the
## approaches is not cosmetic: on the checkerboard pattern a doorway can easily
## open onto a fixed pillar, which would leave a door nobody can walk through.
func _open_doorway(cell: Vector2i, axis: Vector2i, protected: Dictionary) -> void:
	for step in [Vector2i.ZERO, axis, -axis]:
		var c: Vector2i = cell + step
		if not in_bounds(c) or _is_border(c):
			continue
		cells[c] = CellState.EMPTY
		protected[c] = true

func _is_border(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == Consts.GRID_WIDTH - 1 or cell.y == Consts.GRID_HEIGHT - 1

# --- Bridges ---------------------------------------------------------------
#
# A bridge is one chasm cell with a crossing over it. Intact it is ordinary
# floor (EMPTY) and reads as such to everything — players walk it, bombs slide
# over it, the bots' pathfinder routes through it — and blown it reverts to the
# CHASM underneath, which is what makes taking one out a real change to the
# map rather than a decoration.
#
# It then rebuilds itself, a quarter at a time, and is only walkable again at
# the last quarter: a bridge is either there or it isn't. Repair is deliberately
# slow enough (four ticks, twenty seconds) that dropping a crossing buys real
# time, and a fresh blast resets the progress outright — holding a bridge down
# is something you have to keep spending bombs on.

const BRIDGE_REPAIR_INTERVAL := 5.0
const BRIDGE_REPAIR_STEP := 0.25

func _add_bridge(cell: Vector2i, axis: Vector2i, protected: Dictionary) -> void:
	if not in_bounds(cell) or _is_border(cell):
		return
	cells[cell] = CellState.EMPTY
	bridges[cell] = {"axis": axis, "repair": 1.0, "timer": BRIDGE_REPAIR_INTERVAL}
	# The crossing and both banks: a bridge that opened onto a crate or a
	# random wall would be a crossing in name only.
	_open_doorway(cell, axis, protected)

func is_bridge(cell: Vector2i) -> bool:
	return bridges.has(cell)

## Called for every cell a blast touches (see Bomb._spawn_explosion), so a
## crossing goes down to any explosion that reaches it whatever its shape —
## and re-blowing one that is part way rebuilt puts it back to nothing.
func break_bridge_at(cell: Vector2i) -> void:
	var bridge = bridges.get(cell)
	if bridge == null:
		return
	var was_intact: bool = bridge["repair"] >= 1.0
	bridge["repair"] = 0.0
	bridge["timer"] = BRIDGE_REPAIR_INTERVAL
	if was_intact:
		cells[cell] = CellState.CHASM
		Sfx.play("wall_destroy")
		# Whatever was standing on the planks goes into the water with them. A
		# bomb is set off rather than deleted so its owner gets the charge back
		# (the same call seal_cell makes, for the same reason); players are not
		# handled here at all — Player._unstick walks them back off a cell that
		# has stopped being legal, which is a shove to the nearest bank rather
		# than a drowning.
		if powerups_by_cell.has(cell):
			powerups_by_cell[cell].queue_free()
			powerups_by_cell.erase(cell)
		if bombs_by_cell.has(cell):
			bombs_by_cell[cell].explode()
	queue_redraw()

func _process(delta: float) -> void:
	var changed := false
	for cell in bridges:
		var bridge: Dictionary = bridges[cell]
		if bridge["repair"] >= 1.0:
			continue
		bridge["timer"] -= delta
		if bridge["timer"] > 0.0:
			continue
		bridge["timer"] = BRIDGE_REPAIR_INTERVAL
		bridge["repair"] = minf(1.0, bridge["repair"] + BRIDGE_REPAIR_STEP)
		if bridge["repair"] >= 1.0 and cells.get(cell) == CellState.CHASM:
			cells[cell] = CellState.EMPTY
			Sfx.play("wall_place")
		changed = true
	if changed:
		queue_redraw()

# Alternate "map mode": scatter indestructible walls randomly across the
# interior instead of the fixed checkerboard pattern above.
#
# Unlike the checkerboard, random placement can seal the arena into regions
# with no route between them. Survivors stranded in different regions can
# never reach each other, so the last-one-standing check never fires and the
# round runs forever — hence every wall that would break connectivity is
# rejected. Blocks aren't placed yet here, so "not a wall" is exactly "open".
func _scatter_random_walls(protected_cells: Dictionary) -> void:
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

## Only EMPTY counts as open here. Blocks aren't placed yet at the point this
## runs, so the arena is walls, chasms and floor — and a chasm is unreachable
## floor as far as connectivity goes, which is exactly what it must not be
## mistaken for. (An intact bridge is EMPTY and so counts as the crossing it
## is; a round can and does temporarily split when one is blown, which is the
## layout working rather than a generation failure.)
func _all_open_cells_connected() -> bool:
	var open_count := 0
	for cell in cells:
		if cells[cell] == CellState.EMPTY:
			open_count += 1
	var start: Vector2i = get_spawn_cells()[0]
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for dir in Consts.DIRECTIONS:
			var next: Vector2i = cur + dir
			if seen.has(next) or cells.get(next, CellState.WALL) != CellState.EMPTY:
				continue
			seen[next] = true
			queue.append(next)
	return seen.size() == open_count

func _get_protected_cells() -> Dictionary:
	var protected: Dictionary = {}
	for spawn in get_spawn_cells():
		protected[spawn] = true
		for dir in Consts.DIRECTIONS:
			protected[spawn + dir] = true
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
	var base_chance = Consts.powerup_chance_percent / 100.0

	if owner_player != null:
		# Whoever broke the block biases what falls out of it, per character
		# (see Player._apply_character_passives).
		powerup_type = _pick_powerup_by_weights(owner_player.powerup_weights,
			base_chance * owner_player.powerup_chance_multiplier)
	elif randf() < base_chance:
		# Ownerless destruction (nothing does this today): map setting chance,
		# then an even roll between the four types.
		powerup_type = randi() % 4

	if powerup_type >= 0:
		_spawn_powerup(cell, powerup_type)

func _pick_powerup_by_weights(weights: Array[int], effective_chance: float) -> int:
	# Calculate total weight
	var total_weight = 0
	for w in weights:
		total_weight += w

	if total_weight == 0:
		return -1

	# Roll based on effective chance and weights
	var roll = randf()
	var accumulated = 0.0

	for powerup_type in range(4):
		var probability = effective_chance * float(weights[powerup_type]) / float(total_weight)
		accumulated += probability
		if roll < accumulated:
			return powerup_type

	return -1

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

# Lets an explosion kill a temp wall immediately (see Bomb._apply_blast)
# instead of leaving its sprite up until its own timer fires.
func destroy_temp_wall_at(cell: Vector2i) -> void:
	if temp_wall_nodes.has(cell):
		temp_wall_nodes[cell].destroy()

# Turns `cell` into permanent stone, clearing whatever was standing on it —
# used by sudden death, which drops walls on the arena regardless of what's in
# the way. A block is removed without its usual powerup roll (the wall would
# just bury it anyway) and a bomb is set off rather than deleted, so its owner
# gets the charge back instead of losing a bomb for the rest of the round.
func seal_cell(cell: Vector2i) -> void:
	# Rubble on a crossing ends it: stop rebuilding a bridge the closing ring
	# has just filled in, or the repair tick would carve the wall back open.
	bridges.erase(cell)
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

## Open air with nothing under it. Impassable to everyone and to bombs, but
## deliberately not a wall — blasts cross it (see the CellState note above), and
## so does the Parkour Runner's hop.
func is_pit(cell: Vector2i) -> bool:
	return get_cell_state(cell) == CellState.CHASM

## The one authority on which cells a blast touches, for every shape of bomb.
##
## Explosions, mine trigger ranges and the bots' danger map all read the
## footprint from here instead of each walking the grid their own way: a bot
## whose idea of a blast disagrees with the blast is a bot that strolls into
## fire, and a mine whose trigger range disagrees with its own explosion goes
## off at people it could never have reached.
func blast_cells(origin: Vector2i, radius: int, is_star: bool) -> Dictionary:
	return _star_blast_cells(origin, radius) if is_star else _cross_blast_cells(origin, radius)

## Four arms, each ending at the first solid thing. A temp wall is reached and
## burns; permanent stone is not reached at all. Either way the arm stops there.
func _cross_blast_cells(origin: Vector2i, radius: int) -> Dictionary:
	var hit := {origin: true}
	for dir in Consts.DIRECTIONS:
		for i in range(1, radius + 1):
			var c: Vector2i = origin + dir * i
			if not in_bounds(c):
				break
			if is_wall(c):
				if is_temp_wall(c):
					hit[c] = true
				break
			hit[c] = true
			if is_block(c):
				break
	return hit

## The Pyro's blast: an eight-pointed star, not a filled diamond.
##
## The four straight arms are exactly everyone else's, same length for the same
## radius. What the Pyro gets on top is four short arms out of the corners, at
## half the range. So a radius powerup is worth the same *kind* of thing it is
## worth to anybody — four cells of reach, plus two on the diagonals — and the
## footprint grows as 6r+1 against a normal bomb's 4r+1: half again as much
## blast, at every radius, forever.
##
## It used to be a filled diamond, 2r²+2r+1 cells. That is quadratic against
## everyone else's linear, so the third radius powerup was worth four times what
## the first one was and a mid-round Pyro covered a third of a large map from one
## bomb. Same character, same fantasy, an arithmetic that stops running away.
##
## Rounded *up* on the diagonals, because rounded down a radius-1 Pyro — which is
## every Pyro at the start of a round — would be an ordinary bomb with no star at
## all.
func _star_blast_cells(origin: Vector2i, radius: int) -> Dictionary:
	var hit := {origin: true}
	for dir in Consts.DIRECTIONS:
		_pierce_ray(hit, origin, dir, radius)
	for dir in Consts.DIAGONALS:
		_pierce_ray(hit, origin, dir, (radius + 1) / 2)
	return hit

## One arm of a Pyro blast. Unlike an ordinary arm it isn't stopped by what it
## hits, it is *slowed* by it: cover charges the fire extra range to get through
## (CRATE_PIERCE_COST, WALL_PIERCE_COST) and the arm runs until it can't pay.
## Crates are a speed bump, stone very nearly a wall, and neither is a guarantee
## — which is the piercing the character is built on, minus the version of it
## that ignored walls outright.
func _pierce_ray(hit: Dictionary, origin: Vector2i, dir: Vector2i, range_cells: int) -> void:
	var left := range_cells
	var c := origin
	while left > 0:
		c += dir
		if not in_bounds(c):
			return
		left -= 1 # the step onto this cell
		if is_wall(c):
			left -= WALL_PIERCE_COST
			# A temp wall burns the moment the fire reaches its face, whether or
			# not anything gets out the far side — it is the Engineer's cover and
			# it is spent either way. Permanent stone lights up only when the
			# blast actually came through, so a dark wall always means the cover
			# held, and nothing on screen ever suggests stone is breaking.
			if is_temp_wall(c) or left > 0:
				hit[c] = true
			if left < 0:
				return
		else:
			hit[c] = true
			if is_block(c):
				left -= CRATE_PIERCE_COST

func is_walkable(cell: Vector2i) -> bool:
	if get_cell_state(cell) != CellState.EMPTY:
		return false
	if has_blocking_bomb_at(cell):
		return false
	return true

## A bomb blocks the cell it sits on — except a Miner's mine, which is meant to
## be walked over and would be a wall rather than a trap otherwise.
##
## Note this is about *people*. Bombs still treat a mine's cell as occupied
## (see Bomb._can_enter, which asks has_bomb_at): bombs_by_cell holds one bomb
## per cell, so letting a sliding or crawling bomb move onto a mine would
## overwrite the mine's entry in the index and orphan it.
func has_blocking_bomb_at(cell: Vector2i) -> bool:
	var bomb = bombs_by_cell.get(cell)
	return bomb != null and not bomb.is_mine

# Same as is_walkable(), except a temp wall is passable for the player who
# placed it (everyone else, bombs, and explosions still treat it as solid).
# Pyro can also walk through their own bombs.
func is_walkable_for(cell: Vector2i, player: Node) -> bool:
	if get_cell_state(cell) == CellState.WALL and temp_wall_cells.get(cell) == player:
		return not has_blocking_bomb_at(cell)
	# Pyro, Magnet and Sapper can pass through their own bombs. For the latter two
	# this is a requirement of the kit rather than a convenience: the Magnet's
	# bombs move, so one can come and park itself in a doorway its owner is
	# standing in, and the Sapper's sit armed for eight seconds at a stretch.
	# Either character could otherwise wall themselves in with their own
	# ammunition and spend the round fighting it instead of anybody else.
	if bombs_by_cell.has(cell) and player.character_id in [
		PlayerScript.CharacterId.PYRO,
		PlayerScript.CharacterId.MAGNET,
		PlayerScript.CharacterId.BOMB_MASTER,
	]:
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

const WATER_COLOR := Color(0.10, 0.20, 0.30)
const WATER_DEEP_COLOR := Color(0.06, 0.13, 0.22)
const PLANK_COLOR := Color(0.42, 0.30, 0.17)
const PLANK_EDGE_COLOR := Color(0.26, 0.18, 0.10)

func _draw() -> void:
	for x in Consts.GRID_WIDTH:
		for y in Consts.GRID_HEIGHT:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * Consts.CELL_SIZE, y * Consts.CELL_SIZE, Consts.CELL_SIZE, Consts.CELL_SIZE)
			var state = cells.get(cell, CellState.EMPTY)
			if state == CellState.WALL and not temp_wall_cells.has(cell):
				draw_texture_rect(WALL_TEXTURE, rect, false)
				continue
			if state == CellState.CHASM:
				_draw_water(rect, cell)
			else:
				draw_rect(rect, FLOOR_COLOR, true)
				draw_rect(rect, Color(0, 0, 0, 0.15), false, 1.0)
			if bridges.has(cell):
				_draw_bridge(rect, cell)

## Water is drawn rather than textured because there is no asset for it, and a
## flat dark rectangle would read as a shadow. The ripple is a fixed pattern
## keyed off the cell coordinates instead of a running animation: it only has
## to say "this is not floor" at a glance, and a still arena is one that never
## costs a redraw.
func _draw_water(rect: Rect2, cell: Vector2i) -> void:
	draw_rect(rect, WATER_DEEP_COLOR, true)
	draw_rect(rect.grow(-5.0), WATER_COLOR, true)
	var phase: float = float(posmod(cell.x * 3 + cell.y * 7, 5)) / 5.0
	for i in 2:
		var y: float = rect.position.y + rect.size.y * (0.30 + 0.34 * i + 0.08 * phase)
		draw_line(
			Vector2(rect.position.x + 12.0, y),
			Vector2(rect.end.x - 12.0, y),
			Color(0.55, 0.75, 0.9, 0.22), 2.0)

## The crossing itself, drawn on top of whatever the cell currently is: planks
## over floor while it stands, and over water while it doesn't.
##
## A broken bridge rebuilds from both banks inward, so how much is left to close
## is legible from across the arena — the gap in the middle *is* the repair
## meter. Nothing separate has to be read, and the moment the two halves meet is
## the moment it becomes walkable again.
func _draw_bridge(rect: Rect2, cell: Vector2i) -> void:
	var bridge: Dictionary = bridges[cell]
	var repair: float = bridge["repair"]
	if repair <= 0.0:
		return
	var centre := rect.get_center()
	# `along` runs the way the crossing spans, `across` is the deck's width.
	var along := Vector2(absi(bridge["axis"].x), absi(bridge["axis"].y))
	var across := Vector2(along.y, along.x)
	var half: float = rect.size.x * 0.5
	var reach: float = half * repair # how far the deck comes out from each bank
	var deck_half: float = half * 0.34

	for side in [-1.0, 1.0]:
		var bank: Vector2 = centre + along * half * side
		var inner: Vector2 = centre + along * (half - reach) * side
		var deck := Rect2(bank, Vector2.ZERO).expand(inner)
		deck = Rect2(deck.position - across * deck_half, deck.size + across * deck_half * 2.0)
		draw_rect(deck, PLANK_COLOR, true)
		draw_rect(deck, PLANK_EDGE_COLOR, false, 1.5)

	# Plank seams, so the deck reads as boards rather than as a brown bar. The
	# deck occupies |offset| in [half - reach, half], measured out from the
	# centre — anything nearer the middle than that is over the gap.
	const SEAMS := 4
	for i in range(1, SEAMS):
		var offset: float = (float(i) / float(SEAMS) - 0.5) * 2.0 * half
		if absf(offset) < half - reach:
			continue
		var at: Vector2 = centre + along * offset
		draw_line(at - across * deck_half, at + across * deck_half, PLANK_EDGE_COLOR, 1.0)
