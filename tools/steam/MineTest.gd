extends Node
## Dev check for the Miner's mine: stepping into its footprint and back out must not set
## it off, and staying in it must. Run headless:
##   godot --headless --path . res://tools/steam/MineTest.tscn

var arena: Node
var miner: Node
var sapper: Node
var fails := 0

func _ready() -> void:
	if name != "MineTest":
		var keeper := Node.new()
		keeper.name = "MineTest"
		keeper.set_script(get_script())
		get_tree().root.add_child.call_deferred(keeper)
		queue_free()
		return
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _player(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("player_id") == id:
			return p
	return null

func _step(p: Node, to: Vector2i) -> void:
	p._scripted_move_to(arena.cell_to_world(to), p.move_duration)
	await _wait(p.move_duration + 0.02)

func _run() -> void:
	Consts.set_map_layout_index(1)
	Consts.set_map_size(2)
	Consts.set_sudden_death_index(Consts.SUDDEN_DEATH_OPTIONS.size() - 1)
	Consts.set_hazard_chance_percent(0)
	GameManager.set_player_slots([
		{"id": 1, "device": 99, "character_id": 6},
		{"id": 2, "device": 98, "character_id": 0},
	] as Array[Dictionary])
	GameManager.reset_match()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
	await _wait(0.2)
	arena = get_tree().current_scene.get("arena")
	miner = _player(1)
	sapper = _player(2)
	for x in range(1, 10):
		arena.destroy_block_at(Vector2i(x, 1))
	# Miner plants a mine on (3,1); the Sapper starts further down the same row.
	miner.position = arena.cell_to_world(Vector2i(3, 1))
	miner.bomb_count_max = 4
	miner.bomb_count_current = 4
	miner._place_ordnance(true)
	await _wait(0.1)
	var mine: Node = arena.get_bomb_at(Vector2i(3, 1))
	_check(mine != null and mine.is_mine, "mine planted at (3,1)")
	sapper.position = arena.cell_to_world(Vector2i(6, 1))
	sapper.shield_charges = 0
	await _wait(1.0) # past the arming delay

	# 1. Clip the edge of the footprint and turn straight back (0.2s countdown).
	await _step(sapper, Vector2i(5, 1))
	await _clip_edge_and_back()
	_check(not mine.has_exploded, "no blast after clipping the edge and turning back")
	await _wait(0.6)
	_check(sapper.alive, "Sapper unharmed")
	_check(mine._mine_trip_left < 0.0, "mine stood down and is waiting again")
	_check(is_instance_valid(arena.get_bomb_at(Vector2i(3, 1))), "mine is still planted")

	# 2. A second bluff, then staying in it.
	await _clip_edge_and_back()
	await _wait(0.5)
	_check(not mine.has_exploded, "second bluff also safe")
	await _step(sapper, Vector2i(4, 1))
	await _step(sapper, Vector2i(3, 1))
	await _step(sapper, Vector2i(2, 1))
	await _wait(0.4)
	_check(not is_instance_valid(mine) or mine.has_exploded, "walking on through sets it off")
	_check(not sapper.alive, "and it hurts (no shield)")
	print("DONE fails=%d" % fails)
	get_tree().quit(fails)

## Just inside the footprint's edge (cell 4), then back out — 0.1s of exposure in all.
func _clip_edge_and_back() -> void:
	var inside: Vector2 = arena.cell_to_world(Vector2i(4, 1)) + Vector2(30, 0)
	sapper.position = inside
	await _wait(0.1)
	sapper.position = arena.cell_to_world(Vector2i(5, 1))
	await _wait(0.05)
