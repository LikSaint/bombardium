extends Node
## Dev-only camera operator for the Steam page: drives bot-only matches, moves the
## camera and saves screenshots, so a trailer can be recorded with Godot's Movie
## Maker without anyone holding a controller. Not part of the game (tools/* is
## excluded from exports).
##
## godot --path . res://tools/steam/Capture.tscn --resolution 1920x1080 \
##       --write-movie out.avi --fixed-fps 60 -- plan=trailer shots=/dir lang=en

const MAIN := "res://scenes/Main.tscn"
const LOBBY := "res://scenes/Lobby.tscn"
const MENU := "res://scenes/MainMenu.tscn"
const BombScene := preload("res://scenes/Bomb.tscn")

## Zoom 1.0 shows 20x11 cells at 1080p; the close shots show about 11x6.
const CLOSE_ZOOM := 1.8
const FOLLOW_SMOOTHING := 3.0
const SHOT_EVERY := 3.0

## Character ids: 0 Bomb-Master 1 Parkour 2 Engineer 3 Pyro 4 Kicker 5 Magnet 6 Miner 7 Grenadier
## Layout index into Consts.MAP_LAYOUTS: 1 Classic 2 Bridges 3 Crater 4 Quarters 5 Plaza.
## Size index: 0 Tiny .. 4 Huge (21x17).
## A camera step is ["full", seconds] (whole arena, HUD) or ["follow", player index, seconds]
## (close on one character, no HUD).
const PLANS := {
	"trailer": [
		{"layout": 1, "size": 4, "chars": [0, 3, 4, 7],
		 "cam": [["full", 5.0], ["follow", 0, 9.0], ["follow", 1, 9.0], ["follow", 2, 9.0], ["full", 4.0]]},
		{"layout": 2, "size": 4, "chars": [1, 0, 4, 5],
		 "cam": [["full", 5.0], ["follow", 0, 9.0], ["follow", 1, 9.0], ["follow", 3, 9.0], ["full", 4.0]]},
		{"layout": 3, "size": 4, "chars": [3, 0, 4, 1],
		 "cam": [["full", 5.0], ["follow", 1, 9.0], ["follow", 2, 9.0], ["follow", 0, 9.0], ["full", 4.0]]},
		{"layout": 5, "size": 4, "chars": [4, 0, 3, 1],
		 "cam": [["full", 5.0], ["follow", 2, 9.0], ["follow", 0, 9.0], ["follow", 3, 9.0], ["full", 4.0]]},
		{"layout": 4, "size": 3, "chars": [0, 3, 4, 1],
		 "cam": [["full", 5.0], ["follow", 3, 9.0], ["follow", 1, 9.0], ["full", 6.0]]},
	],
}

var shots_dir := "/tmp"
var plan := "test"
var lang := "en"
var segment := 0
var close_mode := false
var follow_index := 0
## Camera target while a story runs: "player" (follow_index), "eng", "pack" (the three
## foes' centre) or "point" (cam_point).
var cam_mode := "player"
var cam_point := Vector2.ZERO
var cam_zoom := CLOSE_ZOOM
var cam_min_x := 0.0 # px: the camera's left edge stays east of this (0: no limit)
var eng: Node = null
var foes: Array = []
var arena: Node = null
var _cam_pos := Vector2.ZERO
var _snap_camera := true

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	shots_dir = args.get("shots", shots_dir)
	plan = args.get("plan", plan)
	lang = args.get("lang", "en")
	_run.call_deferred()

func _process(delta: float) -> void:
	_clock += delta
	# After a shield soaks a hit the game gives a full second of invulnerability, which would
	# swallow the next two mines of the run; the run cuts it short so each blast lands.
	if grace_cut_for != null and is_instance_valid(grace_cut_for) and grace_cut_for.is_invulnerable:
		_grace_seen += delta
		if _grace_seen >= 0.12:
			grace_cut_for._end_invulnerability()
			_grace_seen = 0.0
	else:
		_grace_seen = 0.0
	for f in foes:
		if is_instance_valid(f):
			f.bomb_radius = mini(f.bomb_radius, 2) # a pickup must not give them a blast that reaches the walls
			if shield_floor > 0 and not _foes_in_shot and f.shield_charges < shield_floor:
				f.shield_charges = shield_floor # a fight this long would otherwise finish one of them
	if hold_fire and is_instance_valid(arena):
		for t in _battery():
			t._fire_clock = -600.0
	# While the fighters are out of the shot, so are their bombs and blasts (they would come out of nowhere).
	if is_instance_valid(arena) and not foes.is_empty():
		for c in arena.get_children():
			_hide_if_foes_unseen(c)
	var main := get_tree().current_scene
	if main == null or not main.has_method("late_join_allowed"):
		return
	var backdrop: CanvasLayer = main.get_node("Backdrop")
	var ui: CanvasLayer = main.get_node("UI")
	backdrop.visible = not close_mode
	ui.visible = not close_mode
	if not close_mode:
		_snap_camera = true
		return
	var camera: Camera2D = main.get("camera")
	var target := _follow_target()
	var z := lerpf(camera.zoom.x, cam_zoom, clampf(delta * 3.0, 0.0, 1.0)) if not _snap_camera else cam_zoom
	var view := get_viewport().get_visible_rect().size / z
	var arena_px := Consts.arena_pixel_size()
	camera.zoom = Vector2(z, z)
	# The outer wall ring and the void behind it stay out of close-ups: the camera stops one
	# cell short of the edge (and centres when the view is wider than what is left).
	var inset := float(Consts.CELL_SIZE)
	var lo := Vector2(inset, inset) + view / 2.0
	var hi := arena_px - Vector2(inset, inset) - view / 2.0
	# Shots of the fighters keep the camera east of cam_min_x: the battery is never in them.
	var left := maxf(cam_min_x, inset)
	var right := arena_px.x - inset
	var want := Vector2(
		(left + right) / 2.0 if view.x >= right - left else clampf(target.x, left + view.x / 2.0, right - view.x / 2.0),
		arena_px.y / 2.0 if lo.y > hi.y else clampf(target.y, lo.y, hi.y))
	if _snap_camera:
		_cam_pos = want
		_snap_camera = false
	else:
		_cam_pos = _cam_pos.lerp(want, clampf(delta * FOLLOW_SMOOTHING, 0.0, 1.0))
	camera.position = _cam_pos

## The character being followed, or whoever is nearest to them once they are out.
func _follow_target() -> Vector2:
	match cam_mode:
		"eng":
			return eng.global_position
		"point":
			return cam_point
		"pack":
			var sum := Vector2.ZERO
			var n := 0
			for f in foes:
				if is_instance_valid(f) and f.get("alive"):
					sum += f.global_position
					n += 1
			return sum / n if n > 0 else _cam_pos
	var players := get_tree().get_nodes_in_group("players")
	var wanted: Node2D = null
	for p in players:
		if p.get("player_id") == follow_index + 1:
			wanted = p
	if wanted != null and wanted.get("alive"):
		return wanted.global_position
	var anchor: Vector2 = wanted.global_position if wanted != null else _cam_pos
	var best: Node2D = null
	for p in players:
		if p.get("alive") and (best == null or p.global_position.distance_to(anchor) < best.global_position.distance_to(anchor)):
			best = p
	return best.global_position if best != null else anchor

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("shot ", name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _slots(chars: Array, devices: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in chars.size():
		var dev: int = devices[i] if i < devices.size() else Consts.DEVICE_BOT
		out.append({"id": i + 1, "device": dev, "character_id": chars[i]})
	return out

func _run() -> void:
	var orig_lang: String = Loc.lang
	Loc.set_language(lang)
	if plan == "trailer" or plan == "menus":
		get_tree().change_scene_to_file(MENU)
		await _wait(2.5)
		await _shot("00_menu")
		await _wait(1.5)
		await _lobby_scene()
	if plan == "sapper":
		await _sapper_scene()
	elif plan == "engineer":
		await _engineer_scene()
	elif plan != "menus":
		for m in PLANS[plan]:
			await _play_match(m)
	Loc.set_language(orig_lang)
	get_tree().quit()

func _lobby_scene() -> void:
	close_mode = false
	get_tree().change_scene_to_file(LOBBY)
	await _wait(0.6)
	var lobby := get_tree().current_scene
	lobby.set("slots", [
		{"device": 0, "player_id": 1, "character_id": 3, "ready": true},
		{"device": 1, "player_id": 2, "character_id": 7, "ready": true},
		{"device": 2, "player_id": 3, "character_id": 2, "ready": false},
		{"device": Consts.DEVICE_BOT, "player_id": 4, "character_id": 6, "ready": true},
	])
	lobby.call("_show_view", "room")
	lobby.call("_refresh_slots_ui")
	await _wait(1.5)
	await _shot("01_lobby")
	await _wait(1.0)

func _play_match(m: Dictionary) -> void:
	segment += 1
	Consts.set_map_layout_index(m["layout"])
	Consts.set_map_size(m["size"])
	GameManager.set_player_slots(_slots(m["chars"]))
	GameManager.reset_match()
	close_mode = false
	get_tree().change_scene_to_file(MAIN)
	await _wait(0.1)
	# An all-bot match closes itself after a few seconds (nobody left to play it).
	get_tree().current_scene.set("_no_players_label", null)
	var clock := 0.0
	var step_no := 0
	for step in m["cam"]:
		step_no += 1
		close_mode = step[0] == "follow"
		_snap_camera = true
		var length: float = step[-1]
		if close_mode:
			follow_index = step[1]
		var spent := 0.0
		while spent < length:
			var slice := minf(SHOT_EVERY, length - spent)
			await _wait(slice)
			spent += slice
			clock += slice
			var who := "p%d" % follow_index if close_mode else "full"
			await _shot("s%d_%02d_%s_t%03d" % [segment, step_no, who, int(clock)])
	close_mode = false


# --- Shared staging helpers -----------------------------------------------------------
#
# The two story scenes are staged rather than played: the heroes are driven by this script
# through the game's own code (bombs, walls, turrets, mines), everyone else is a bot or a
# prop, and the camera cuts where the storyboard says so.

var _moves := {}
var _foes_in_shot := false # while the fighters are on screen their shields only go down, as in a real fight
var shield_floor := 0 # the foes are topped back up to this many shields every frame (0: off)
var grace_cut_for: Node = null # whose post-hit invulnerability is cut short (the Sapper's run)
var _grace_seen := 0.0
var _clock := 0.0 # game seconds (it follows Engine.time_scale), for the scripted run paths

func _begin_match(layout: int, size: int, chars: Array, devices: Array) -> void:
	segment += 1
	Consts.set_map_layout_index(layout)
	Consts.set_map_size(size)
	Consts.set_sudden_death_index(Consts.SUDDEN_DEATH_OPTIONS.size() - 1)
	Consts.set_hazard_chance_percent(0)
	GameManager.set_player_slots(_slots(chars, devices))
	GameManager.reset_match()
	cam_mode = "player"
	close_mode = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MAIN)
	await _wait(0.2)
	get_tree().current_scene.set("_no_players_label", null)
	arena = get_tree().current_scene.get("arena")

func _cut(mode: String, zoom: float = CLOSE_ZOOM, index: int = 0) -> void:
	if mode == "wide":
		close_mode = false
		return
	close_mode = true
	cam_mode = mode
	cam_zoom = zoom
	cam_min_x = TRIO_LEFT if mode == "pack" else 0.0
	follow_index = index
	_snap_camera = true

func _player(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("player_id") == id:
			return p
	return null

func _cell_pos(c: Vector2i) -> Vector2:
	return arena.cell_to_world(c)

func _wait_real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _halt(p: Node) -> void:
	if _moves.has(p) and _moves[p] != null and _moves[p].is_valid():
		_moves[p].kill()
	_moves.erase(p)
	p.get_node("Portrait").set_walking(false)

## Starts a walk to `to` over `dur` seconds and returns at once, so the caller can watch
## for something (a mine tripping) and turn the character round mid-stride.
func _go(p: Node, to: Vector2, dur: float) -> Tween:
	_halt(p)
	var d: Vector2 = to - p.position
	var dir := Vector2i.ZERO
	if absf(d.x) >= absf(d.y):
		dir = Vector2i(1 if d.x > 0.0 else -1, 0)
	else:
		dir = Vector2i(0, 1 if d.y > 0.0 else -1)
	p.facing_dir = dir
	p.get_node("Portrait").face(dir)
	p._scripted_move = true
	p.get_node("Portrait").set_walking(true, dur)
	var tw := create_tween()
	tw.tween_property(p, "position", to, dur)
	tw.finished.connect(func():
		p.get_node("Portrait").set_walking(false)
		p._scripted_move = false)
	_moves[p] = tw
	return tw

func _face(p: Node, dir: Vector2i) -> void:
	p.facing_dir = dir
	p.get_node("Portrait").face(dir)

func _step_to(p: Node, c: Vector2i, dur: float = -1.0) -> void:
	var d: float = p.move_duration if dur < 0.0 else dur
	_go(p, _cell_pos(c), d)
	await _wait(d + 0.03)

func _say(who: Node, text: String, color: Color, secs: float, size: int, lift: float = 0.0) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(160, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.z_index = 100
	l.position = Vector2(-80, -78 - lift)
	who.add_child(l)
	await _wait(secs)
	if is_instance_valid(l):
		l.queue_free()

# --- Scene 1: the minefield -----------------------------------------------------------------

var sap: Node = null
var miner: Node = null
var mines := {}

## Everything off the floor: crates, stone pillars. The outer ring stays.
func _empty_arena() -> void:
	for cell in arena.cells.keys():
		var st = arena.cells[cell]
		if st == arena.CellState.BLOCK:
			arena.destroy_block_at(cell)
		elif st == arena.CellState.WALL and not arena._is_border(cell) and not arena.temp_wall_cells.has(cell):
			arena.cells[cell] = arena.CellState.EMPTY
	arena.queue_redraw()

## The Miner plants a mine, for real, with nobody watching: silent, and already past the
## few moments when a fresh mine is shown, so it simply "is there".
func _plant(c: Vector2i) -> void:
	var vol: float = Sfx.volume
	Sfx.volume = 0.0
	miner.position = _cell_pos(c)
	miner._place_ordnance(true)
	Sfx.volume = vol
	var m: Node = arena.get_bomb_at(c)
	if m != null:
		m._mine_age = 10.0
		m.get_node("BombBody").modulate.a = 0.0
		mines[c] = m
	miner.position = _cell_pos(Vector2i(1, Consts.GRID_HEIGHT - 2))

func _until_tripped(m: Node, timeout: float) -> bool:
	var t := 0.0
	while t < timeout and is_instance_valid(m) and m._mine_trip_left < 0.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	return is_instance_valid(m) and m._mine_trip_left >= 0.0

## Walk towards `to` until `m` trips, turn round at once and back off to `back`, and watch the
## mine stand down. The trip itself plays in slow motion, which is just a slower look at what
## the game really does in a third of a second.
func _probe(m: Node, to: Vector2, speed: float, back: Vector2, slow: float, tag: String) -> void:
	var dist: float = (to - sap.position).length() / float(Consts.CELL_SIZE)
	_go(sap, to, dist * speed)
	var tripped := await _until_tripped(m, dist * speed + 0.5)
	if not tripped:
		push_warning("mine never tripped: " + tag)
		return
	Engine.time_scale = slow
	await _shot("sapper_%s_trip" % tag)
	await _wait(0.05)
	_go(sap, back, 0.14)
	var guard := 0.0
	while is_instance_valid(m) and m._mine_trip_left >= 0.0 and guard < 2.0:
		await get_tree().process_frame
		guard += get_process_delta_time()
	await _wait_real(0.5)
	Engine.time_scale = 1.0
	await _wait(0.2)

func _sapper_scene() -> void:
	await _begin_match(1, 4, [0, 6], [99, 98])
	_empty_arena()
	Music.play_track(Music.Track.MENU)
	sap = _player(1)
	miner = _player(2)
	sap.shield_charges += 30 # the probes may clip a blast; the run below counts the shields out
	sap.stats_changed.emit()
	miner.bomb_count_max = 80
	miner.bomb_count_current = 80
	var row := Consts.GRID_HEIGHT / 2
	var hub := Vector2i(11, row)
	sap.position = _cell_pos(Vector2i(17, row))
	miner.position = _cell_pos(Vector2i(1, Consts.GRID_HEIGHT - 2))
	# Mines to the left, above and below the hub, and two more further left: three in a line for the run.
	for c in [Vector2i(9, row), Vector2i(hub.x, row - 2), Vector2i(hub.x, row + 2),
			Vector2i(6, row), Vector2i(3, row)]:
		_plant(c)
	_cut("player", 1.8, 0)
	await _wait(1.0)

	# 1. A calm walk, right to left, straight into the first mine, and back out.
	await _probe(mines[Vector2i(9, row)], _cell_pos(Vector2i(7, row)), 0.3, _cell_pos(hub), 0.5, "left")
	# 1b. Did he imagine it? Back in, a half-step at a time, to make sure — and out again.
	await _wait(0.5)
	await _probe(mines[Vector2i(9, row)], _cell_pos(Vector2i(10, row)), 0.8, _cell_pos(hub), 0.5, "left2")
	# 2. Thinking about it.
	await _wait(0.4)
	_face(sap, Consts.DIR_UP)
	await _wait(0.45)
	_face(sap, Consts.DIR_DOWN)
	await _wait(0.45)
	_face(sap, Consts.DIR_RIGHT)
	# 3. Back to the right, carefully — and a mine has turned up there.
	_plant(Vector2i(13, row))
	await _wait(0.3)
	await _probe(mines[Vector2i(13, row)], _cell_pos(Vector2i(16, row)), 0.5, _cell_pos(hub), 0.5, "right")
	await _wait(0.3)
	# 4. Up, then down, quickly.
	await _probe(mines[Vector2i(hub.x, row - 2)], _cell_pos(Vector2i(hub.x, row - 4)), 0.2, _cell_pos(hub), 0.6, "up")
	await _probe(mines[Vector2i(hub.x, row + 2)], _cell_pos(Vector2i(hub.x, row + 4)), 0.2, _cell_pos(hub), 0.6, "down")
	await _wait(0.5)
	# 5. Enough: straight through, ignoring the blasts.
	_face(sap, Consts.DIR_LEFT)
	await _wait(0.6)
	var run_to := Vector2i(2, row)
	# Two shields: the first two blasts are shrugged off, the third mine is the end of him. All
	# three sit on his row, so each one has him in its footprint for the whole countdown.
	sap.shield_charges = 2
	sap.stats_changed.emit()
	await _shot("sapper_run_start")
	grace_cut_for = sap
	_go(sap, _cell_pos(run_to), (hub.x - run_to.x) * 0.18)
	await _wait(0.9)
	await _shot("sapper_run_mid")
	var guard := 0.0
	while sap.alive and guard < 4.0:
		await get_tree().process_frame
		guard += get_process_delta_time()
	if sap.alive:
		push_warning("the Sapper survived the run")
	grace_cut_for = null
	_halt(sap)
	cam_mode = "point" # stay on the spot, not on whoever is left alive
	cam_point = sap.position
	await _wait(0.4)
	await _shot("sapper_death")
	await _wait(2.4)
	await _shot("sapper_end")
	close_mode = false

# --- Scene 2: the Engineer's turrets ------------------------------------------------------------
#
# A 17x13 map. The Engineer works in the west, the three fighters start in the east, and the
# story cuts between the two. The fight is the real bot AI (the foes are held still while the
# camera is on the Engineer); the Engineer is driven through the game's own build code.
# The ending is staged: the turrets lob a barrage from their own muzzles, aimed by this script
# (more of them, and further, than a turret ever shoots), because the point of the shot is the
# bombardment. Everything is a real shell and a real blast.

const TRIO_LEFT := 7.05 * Consts.CELL_SIZE  # right edge of the battery's east column is x=7: shots of the fighters start east of it
const E_PATCH := Rect2i(2, 4, 5, 5)                 # the cleared ground: x 2..6, y 4..8
const E_WEST := [Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7)]   # west column of the battery
const E_EAST := [Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7)]   # east column, hard against it
const E_CRATES := [Vector2i(3, 4), Vector2i(2, 5), Vector2i(3, 6),    # round the first bomb (3,5)
		Vector2i(5, 6), Vector2i(6, 7), Vector2i(5, 8)]               # round the second (5,7)
var _runs := {}
var _marks := {}       # milestones the Engineer's job has reached, by name
var _barrier_x := -1   # column of stone that keeps the fight (and its blasts) east of the Engineer
var hold_fire := false # every turret's fire clock is pinned: nothing leaves a muzzle until the shout

func _patch_pos() -> Vector2:
	return _cell_pos(Vector2i(4, 6))

func _clear_powerups(rect: Rect2i) -> void:
	for c in arena.powerups_by_cell.keys():
		if rect.has_point(c):
			arena.powerups_by_cell[c].queue_free()
			arena.powerups_by_cell.erase(c)

## Open ground for the story: no pillars in the patch, six crates round two bomb cells.
func _eng_prepare_patch() -> void:
	for y in range(E_PATCH.position.y, E_PATCH.end.y):
		for x in range(E_PATCH.position.x, E_PATCH.end.x):
			var c := Vector2i(x, y)
			if arena.blocks_by_cell.has(c):
				arena.blocks_by_cell[c].queue_free()
				arena.blocks_by_cell.erase(c)
			arena.cells[c] = arena.CellState.EMPTY
	_clear_powerups(E_PATCH)
	for c in E_CRATES:
		arena._place_block(c)
	arena.queue_redraw()

func _eng_clear() -> void:
	await _step_to(eng, Vector2i(4, 5))
	await _step_to(eng, Vector2i(3, 5))
	eng.place_bomb()
	await _step_to(eng, Vector2i(4, 5))
	await _step_to(eng, Vector2i(4, 6))
	await _step_to(eng, Vector2i(4, 7))
	await _step_to(eng, Vector2i(5, 7))
	eng.place_bomb()
	await _step_to(eng, Vector2i(4, 7))
	await _step_to(eng, Vector2i(4, 6))
	var guard := 0.0
	while eng.bomb_count_current < eng.bomb_count_max and guard < 6.0:
		await get_tree().process_frame
		guard += get_process_delta_time()

func _hold_build(dir: Vector2i, seconds: float) -> void:
	_face(eng, dir)
	eng._scripted_move = false
	eng._begin_build()
	await _wait(seconds)
	eng._end_build()

## The Engineer's whole job in one go: the story cuts away from him and back, but he never
## stops, so every time the camera returns he has walked on and built on from where he was.
func _eng_job() -> void:
	hold_fire = true # nothing leaves a muzzle until the shout
	await _eng_clear()
	_mark("cleared")
	_clear_powerups(E_PATCH)
	# Five of the six walls: the west column from the west side, round the south, then the east column.
	for y in [5, 6, 7]:
		await _step_to(eng, Vector2i(3, y))
		await _hold_build(Consts.DIR_RIGHT, 1.75)
		await _wait(0.15)
		if y == 7:
			_mark("walls3")
	for c in [Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)]:
		await _step_to(eng, c)
	for y in [7, 6, 5]:
		await _step_to(eng, Vector2i(6, y))
		await _hold_build(Consts.DIR_LEFT, 1.75)
		await _wait(0.15)
		if y == 6:
			_mark("walls5")
	_mark("walls6")
	# Turrets (a 3.3 s hold each): the east column from where he stands, then round the south end
	# to the west column.
	for y in [5, 6, 7]:
		await _step_to(eng, Vector2i(6, y))
		await _hold_build(Consts.DIR_LEFT, 3.3)
		await _wait(0.1)
		_mark("t%d" % (y - 4))
	for c in [Vector2i(6, 8), Vector2i(5, 8), Vector2i(4, 8)]:
		await _step_to(eng, c)
	await _hold_build(Consts.DIR_UP, 3.3)
	await _wait(0.1)
	_mark("t4")
	for c in [Vector2i(3, 8), Vector2i(3, 7), Vector2i(3, 6)]:
		await _step_to(eng, c)
	await _hold_build(Consts.DIR_RIGHT, 3.3)
	await _wait(0.1)
	_mark("t5")
	await _step_to(eng, Vector2i(3, 5))
	await _hold_build(Consts.DIR_RIGHT, 3.3)
	await _wait(0.1)
	_mark("t6")
	# Then to the north end of the battery, where he stands for the face-off and the shout.
	for c in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)]:
		await _step_to(eng, c)
	_face(eng, Consts.DIR_RIGHT)
	_mark("done")

func _mark(name: String) -> void:
	_marks[name] = true

func _until_mark(name: String, timeout: float = 40.0) -> void:
	var t := 0.0
	while not _marks.has(name) and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	if not _marks.has(name):
		push_warning("the Engineer never reached: " + name)

func _hide_if_foes_unseen(c: Node) -> void:
	var sp: Script = c.get_script()
	if sp != null and (sp.resource_path.ends_with("/Bomb.gd") or sp.resource_path.ends_with("/Explosion.gd")):
		c.visible = _foes_in_shot or c.position.x < 7.5 * Consts.CELL_SIZE

## A solid column across the whole height of the arena, with the fight on its east side. It is
## invisible (floor is painted over it), so on screen it is just open ground that nobody walks
## on: the fighters are real bots with real bombs, and this is what keeps their blasts off the
## walls (a wall stops a blast) and the bots from walking up to the Engineer, so nothing has to be
## pinned in place. Moved west a column or two at a time between shots, it lets the fight creep
## closer. -1 takes it away.
var _barrier_cover: Node2D = null

func _barrier_cells(col: int) -> Array:
	var out: Array = []
	for x in [col, col - 1]: # two columns thick: the Parkour Runner's hop clears one stone, not two
		for y in range(1, Consts.GRID_HEIGHT - 1):
			if not (x % 2 == 0 and y % 2 == 0): # the layout's own pillars stay what they are
				out.append(Vector2i(x, y))
	return out

func _set_barrier(x: int) -> void:
	if _barrier_x >= 0:
		for c in _barrier_cells(_barrier_x):
			arena.cells[c] = arena.CellState.EMPTY
	_barrier_x = x
	if x >= 0:
		for c in _barrier_cells(x):
			if arena.blocks_by_cell.has(c):
				arena.destroy_block_at(c)
			arena.cells[c] = arena.CellState.WALL
	if _barrier_cover == null or not is_instance_valid(_barrier_cover):
		_barrier_cover = Node2D.new()
		arena.add_child(_barrier_cover)
		arena.move_child(_barrier_cover, 0) # drawn straight over the arena's own floor, under everything on it
		_barrier_cover.draw.connect(_paint_barrier)
	_barrier_cover.queue_redraw()
	arena.queue_redraw()

func _paint_barrier() -> void:
	if _barrier_x < 0:
		return
	for c in _barrier_cells(_barrier_x):
		var rect := Rect2(c.x * Consts.CELL_SIZE, c.y * Consts.CELL_SIZE, Consts.CELL_SIZE, Consts.CELL_SIZE)
		_barrier_cover.draw_rect(rect, arena.FLOOR_COLOR, true)
		_barrier_cover.draw_rect(rect, Color(0, 0, 0, 0.15), false, 1.0)

func _battery() -> Array:
	var out: Array = []
	for c in E_WEST + E_EAST:
		var w = arena.get_temp_wall(c)
		if w != null and w.is_turret:
			out.append(w)
	return out

func _walls_built() -> int:
	var n := 0
	for c in E_WEST + E_EAST:
		var w = arena.get_temp_wall(c)
		if w != null and w.level >= 3:
			n += 1
	return n

## The fighters are bots for the whole story (behind the barrier, see _set_barrier). The Engineer
## is taken out of the "players" group meanwhile, which is where the bots look for somebody to
## hunt: left in, all three of them would go for him instead of fighting each other. Off, they
## stop thinking and stand where they are (the face-off walks them by script).
func _foes_live(on: bool) -> void:
	if on:
		eng.remove_from_group("players")
	else:
		eng.add_to_group("players")
	for f in foes:
		if not is_instance_valid(f):
			continue
		f.is_bot = on
		f.device_id = Consts.DEVICE_BOT if on else 99
		if not on:
			f.bot_move_dir = Vector2i.ZERO

## Bombs the frozen foes left lit would go off while the camera is on the Engineer (and on
## them, once their shields are gone). The cut hides it when they simply never go off.
func _defuse() -> void:
	for c in arena.bombs_by_cell.keys():
		var b = arena.bombs_by_cell[c]
		arena.bombs_by_cell.erase(c)
		if is_instance_valid(b):
			b.queue_free()
	for f in foes:
		if is_instance_valid(f):
			f.bomb_count_current = f.bomb_count_max # the defused ones are given back

## Whoever is not in the shot is not on the map: the storyboard never shows the Engineer and the
## three fighters together before the face-off, and the camera views are wide enough to catch both.
func _show_foes(on: bool) -> void:
	for f in foes:
		if is_instance_valid(f):
			f.visible = on
	_foes_in_shot = on

## From wherever a fighter stands to (tx, ty), along the open lanes only (odd rows and columns carry
## no pillars): sideways to the column first from an odd row, up or down first from an odd column.
func _lane_path(f: Node, tx: int, ty: int) -> Array:
	var c: Vector2i = arena.world_to_cell(f.position)
	if c.y % 2 == 1:
		return [Vector2i(tx, c.y), Vector2i(tx, ty)]
	return [Vector2i(c.x, ty), Vector2i(tx, ty)]

## A run that goes everywhere and nowhere: a random walk over the open crossings of the whole
## battlefield, a hop of one to three crossings at a time, never straight back the way it came, and
## never through the battery or its keeper. Each runner keeps to a stretch of the map of their own
## (west, middle, east), so the three do not end up in one heap for one shell to take.
func _scatter_path(from: Vector2i, first: Vector2i, xmin: int, xmax: int) -> Array:
	var cells: Array = [from + first]
	var here: Vector2i = from + first
	var last := first
	var total := absi(first.x) + absi(first.y)
	while total < 90:
		var options: Array = []
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
				Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4),
				Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6)]:
			var n: Vector2i = here + d
			if n.x < xmin or n.x > xmax or n.y < 3 or n.y > 9:
				continue
			if d.x * last.x + d.y * last.y < 0:
				continue
			if _run_blocked(here, n):
				continue
			options.append(d)
		if options.is_empty():
			options.append(-last)
		var step: Vector2i = options.pick_random()
		here += step
		cells.append(here)
		last = step
		total += absi(step.x) + absi(step.y)
	return cells

func _run_blocked(a: Vector2i, b: Vector2i) -> bool:
	var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var c := a
	while c != b:
		c += d
		if c in E_WEST or c in E_EAST or c == Vector2i(5, 4):
			return true
	return false

func _free_cell_near(c: Vector2i) -> Vector2i:
	for r in range(0, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if arena.in_bounds(n) and arena.get_cell_state(n) == arena.CellState.EMPTY \
						and not arena.bombs_by_cell.has(n):
					return n
	return c

## While the camera is elsewhere the fight has moved: the three are set down round column `cx`
## (the story has them creep west, a couple of cells per scene, without ever meaning to).
func _pack_at(cx: int) -> void:
	var spots := [Vector2i(cx, 4), Vector2i(cx + 1, 8), Vector2i(cx - 1, 7)]
	for i in foes.size():
		var f: Node = foes[i]
		if is_instance_valid(f) and f.alive:
			f.position = _cell_pos(_free_cell_near(spots[i]))

## A walk along cell waypoints, which the barrage can then aim at (_foe_at).
func _run_along(f: Node, cells: Array, secs_per_cell: float, total_secs: float = -1.0) -> void:
	_halt(f)
	var pts: Array[Vector2] = [f.position]
	for c in cells:
		pts.append(_cell_pos(c))
	if total_secs > 0.0: # all the walkers must arrive together, whatever their distances
		var length := 0.0
		for i in range(1, pts.size()):
			length += pts[i - 1].distance_to(pts[i]) / float(Consts.CELL_SIZE)
		secs_per_cell = total_secs / maxf(length, 0.5)
	f._scripted_move = true
	f.get_node("Portrait").set_walking(true, secs_per_cell)
	var tw := create_tween()
	for i in range(1, pts.size()):
		var dir := Vector2i(signi(int(pts[i].x - pts[i - 1].x)), signi(int(pts[i].y - pts[i - 1].y)))
		tw.tween_callback(_face.bind(f, dir))
		tw.tween_property(f, "position", pts[i], pts[i - 1].distance_to(pts[i]) / float(Consts.CELL_SIZE) * secs_per_cell)
	tw.finished.connect(func():
		if is_instance_valid(f):
			f.get_node("Portrait").set_walking(false))
	_moves[f] = tw
	_runs[f] = {"t0": _clock, "pts": pts, "spc": secs_per_cell}

func _foe_at(f: Node, t: float) -> Vector2:
	if not _runs.has(f):
		return f.position
	var r: Dictionary = _runs[f]
	var left: float = t - r["t0"]
	var pts: Array = r["pts"]
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i]) / float(Consts.CELL_SIZE) * r["spc"]
		if left <= seg:
			return pts[i - 1].lerp(pts[i], left / seg if seg > 0.0 else 1.0)
		left -= seg
	return pts[pts.size() - 1]

# The falling-bomb whistle: a sine sliding down, a little wobble and breath, swelling as it nears.
var _whistle: AudioStreamWAV = null

func _whistle_stream() -> AudioStreamWAV:
	if _whistle != null:
		return _whistle
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(2300.0, 700.0, t) + 30.0 * sin(t * 55.0)
		phase += TAU * f / float(rate)
		var env := minf(t * 14.0, 1.0) * (0.45 + 0.55 * t)
		var v := (sin(phase) * 0.8 + sin(phase * 2.0) * 0.1 + randf_range(-1.0, 1.0) * 0.07) * env * 0.4
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	_whistle = AudioStreamWAV.new()
	_whistle.format = AudioStreamWAV.FORMAT_16_BITS
	_whistle.mix_rate = rate
	_whistle.data = data
	return _whistle

func _whistle_after(delay: float) -> void:
	if delay > 0.0:
		await _wait(delay)
	var pl := AudioStreamPlayer.new()
	pl.stream = _whistle_stream()
	pl.pitch_scale = randf_range(0.85, 1.25)
	pl.volume_db = -5.0
	add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()

## One barrage shell from `turret` to `cell`. Returns its flight time.
func _lob(turret: Node, cell: Vector2i) -> float:
	var shell: Node = BombScene.instantiate()
	shell.thrown = true
	shell.cell = cell
	shell.arena = arena
	shell.owner_player = eng
	shell.radius = 1
	shell.position = turret.position + Vector2.from_angle((_cell_pos(cell) - turret.position).angle()) * 22.0
	arena.add_child(shell)
	turret._aim_angle = (_cell_pos(cell) - turret.position).angle()
	turret._recoil = 1.0
	Sfx.play("bomb_place", randf_range(0.85, 1.0))
	var flight: float = shell._flight_total
	_whistle_after(maxf(flight - 1.0, 0.0))
	return flight

func _flight_for(from: Vector2, to: Vector2) -> float:
	# The game's own pricing of a throw (Bomb.flight_time_for), as the barrage needs it before it fires.
	return maxf(0.9, 0.18 * round(from.distance_to(to) / float(Consts.CELL_SIZE)))

func _alive_foes() -> Array:
	var out: Array = []
	for f in foes:
		if is_instance_valid(f) and f.alive:
			out.append(f)
	return out

## The barrage: three shells every third of a second, from random turrets, most of them
## dropping round the runners, and one per wave pitched exactly where a given runner will be
## when it lands. Anyone still standing at the end is simply caught where they stand.
func _barrage(turrets: Array, hits: Dictionary) -> void:
	var order := foes.duplicate()
	for wave in 18:
		var alive := _alive_foes()
		if alive.is_empty():
			break
		for k in 3:
			if _alive_foes().is_empty():
				break # the last one has fallen: nothing more is fired (what is in the air still lands)
			var turret: Node = turrets.pick_random()
			var cell := Vector2i.ZERO
			if k == 0 and hits.has(wave):
				var victim: Node = order[hits[wave]]
				if not (is_instance_valid(victim) and victim.alive):
					victim = alive[0]
				var aim: Vector2 = _foe_at(victim, _clock + 1.2)
				for _i in 2:
					aim = _foe_at(victim, _clock + _flight_for(turret.position, aim))
				cell = arena.world_to_cell(aim)
				# Each of them has to fall on his own: with another runner near the spot, wait a wave.
				var crowded := false
				var landing := _clock + _flight_for(turret.position, aim)
				for other in alive:
					if other != victim:
						var there: Vector2i = arena.world_to_cell(_foe_at(other, landing))
						if absi(there.x - cell.x) + absi(there.y - cell.y) <= 3:
							crowded = true
				if crowded:
					hits[wave + 1] = hits[wave]
					cell = _decoy_cell(alive, turret)
			else:
				cell = _decoy_cell(alive, turret)
			_lob(turret, cell)
			await _wait(0.07)
		await _wait(0.2)
	# Anyone who is somehow still up: stop them, and put one on their cell.
	var guard := 0
	while not _alive_foes().is_empty() and guard < 6:
		guard += 1
		for f in _alive_foes():
			_halt(f)
			_lob(turrets.pick_random(), arena.world_to_cell(f.position))
		await _wait(1.6)

## A cell for a shell that is only there for the noise: anywhere on the fighters' side of the map,
## evenly (the battery's side is never shelled by its own turrets), and never close to a runner (where they will be
## when this shell, flying from `turret`, lands).
func _decoy_cell(alive: Array, turret: Node) -> Vector2i:
	var best := Vector2i(12, 6)
	for _try in 60:
		var c := Vector2i(randi_range(9, Consts.GRID_WIDTH - 2), randi_range(2, Consts.GRID_HEIGHT - 3))
		if arena.get_cell_state(c) != arena.CellState.EMPTY or arena.bombs_by_cell.has(c):
			continue
		best = c
		var flight := _flight_for(turret.position, _cell_pos(c))
		var clear := true
		for f in alive:
			for dt in [-0.3, 0.0, 0.3]:
				var there: Vector2i = arena.world_to_cell(_foe_at(f, _clock + flight + dt))
				if absi(there.x - c.x) + absi(there.y - c.y) <= 2:
					clear = false
		if clear:
			return c
	return best

func _confetti(at: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.35),
			Color(0.35, 0.85, 1.0), Color(0.5, 1.0, 0.45), Color(1.0, 0.55, 0.9)])
	var fx := CPUParticles2D.new()
	fx.position = at + Vector2(0, -20)
	fx.z_index = 200
	fx.amount = 90
	fx.one_shot = true
	fx.explosiveness = 0.95
	fx.lifetime = 1.8
	fx.direction = Vector2(0, -1)
	fx.spread = 65.0
	fx.initial_velocity_min = 260.0
	fx.initial_velocity_max = 480.0
	fx.gravity = Vector2(0, 520)
	fx.scale_amount_min = 4.0
	fx.scale_amount_max = 8.0
	fx.angular_velocity_min = -360.0
	fx.angular_velocity_max = 360.0
	fx.color_initial_ramp = gradient
	arena.add_child(fx)
	fx.emitting = true

## The Engineer's victory: hops, spins to face the camera and every other way, confetti, "\o/".
## (The game has no cheering pose for him, so this is a dance made of the sprites it has.)
func _celebrate() -> void:
	_halt(eng)
	eng._scripted_move = true
	_cut("eng", 2.4)
	_face(eng, Consts.DIR_DOWN)
	_confetti(eng.position)
	_say(eng, "\\o/", Color(1.0, 0.9, 0.3), 3.2, 56, 46.0)
	var portrait: Node2D = eng.get_node("Portrait")
	var base_y := portrait.position.y
	var dirs := [Consts.DIR_RIGHT, Consts.DIR_UP, Consts.DIR_LEFT, Consts.DIR_DOWN]
	for i in 6:
		var tw := create_tween()
		tw.tween_property(portrait, "position:y", base_y - 24.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(portrait, "position:y", base_y, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_face(eng, dirs[i % 4] if i < 5 else Consts.DIR_DOWN)
		if i == 2:
			_confetti(eng.position)
		await tw.finished
		await _wait(0.04)

func _engineer_scene() -> void:
	await _begin_match(1, 3, [2, 3, 4, 1], [99])
	eng = _player(1)
	eng.bomb_count_max = 14
	eng.bomb_count_current = 14
	eng.bomb_radius = 2
	eng.stats_changed.emit()
	arena.child_entered_tree.connect(_hide_if_foes_unseen) # a new blast must not show for even one frame
	foes.clear()
	var starts := [Vector2i(12, 4), Vector2i(14, 8), Vector2i(12, 8)]
	for i in 3:
		var f := _player(i + 2)
		f.position = _cell_pos(_free_cell_near(starts[i]))
		f.shield_charges += 10
		f.bomb_count_max = 3
		f.bomb_count_current = 3
		f.bomb_radius = 2
		f.stats_changed.emit()
		foes.append(f)
	# The east is open ground with a few crates left standing: a fighter boxed in by crates has
	# nowhere to go and nothing to do, which is how a whole fight once turned into three statues.
	Consts.set_powerup_chance_percent(0)
	for c in arena.blocks_by_cell.keys():
		if c.x >= 8 and randf() < 0.75:
			arena.destroy_block_at(c)
	eng.position = _cell_pos(Vector2i(1, 1))
	_halt(eng)
	eng.visible = false # the Engineer is only ever on screen in his own shots, until the face-off
	Music.play_track(Music.Track.ARENA)

	# Pre-roll, cut from the video: the match is already well under way when the story starts.
	eng.remove_from_group("players") # the bots leave him alone
	_set_barrier(9)
	shield_floor = 5
	await _wait(26.6)
	_foes_in_shot = true
	print("STORY_START frame=", Engine.get_frames_drawn())
	await _shot("engineer_00_midgame")

	# 1. Mid-game, the whole map with the HUD, then in on the three of them going at it.
	_cut("wide")
	await _wait(2.0)
	_cut("pack", 2.3)
	await _wait(2.5)
	await _shot("engineer_01_fight")

	# 2. The Engineer clears ground: six crates, two bombs. (calm) His job starts here and carries
	# straight on across every cut that follows; the three fight on, live, the whole time.
	Music.play_track(Music.Track.MENU)
	_show_foes(false)
	eng.visible = true
	_eng_prepare_patch()
	eng.position = _patch_pos()
	_face(eng, Consts.DIR_RIGHT)
	cam_point = _patch_pos()
	_cut("point", 1.7)
	_eng_job()
	await _wait(0.8)
	await _until_mark("cleared")
	await _wait(0.9) # the picture changes while he is already on his way to the first wall
	await _shot("engineer_02_cleared")

	# 3. The fight, a little nearer without meaning to be.
	Music.play_track(Music.Track.ARENA)
	eng.visible = false
	_show_foes(true)
	_set_barrier(8)
	_cut("pack", 2.3)
	await _wait(3.0)
	await _shot("engineer_03_fight")

	# 4. Walls at the top level: the shot opens with the first ones up and runs to five; the clock
	# runs double. (calm)
	Music.play_track(Music.Track.MENU)
	_show_foes(false)
	eng.visible = true
	_cut("point", 1.7)
	Engine.time_scale = 2.0
	await _until_mark("walls5")
	await _wait(0.5) # cut off while he is walking on to the sixth
	Engine.time_scale = 1.0
	await _shot("engineer_04_walls")

	# 5. The fight again, nearer still; the sixth wall goes up meanwhile and he starts on the turrets.
	Music.play_track(Music.Track.ARENA)
	eng.visible = false
	_show_foes(true)
	_set_barrier(8)
	_cut("pack", 2.3)
	await _wait(3.0)
	await _shot("engineer_05_fight")
	if not _marks.has("walls6"):
		push_warning("the sixth wall was not up when the shot came back to him")

	# 6. The shot opens on six walls and the first turret going up; four of them. (calm, double speed)
	Music.play_track(Music.Track.MENU)
	_show_foes(false)
	eng.visible = true
	_cut("point", 1.7)
	Engine.time_scale = 2.0
	await _until_mark("t4")
	await _wait(0.6) # again cut off mid-stride, on his way to the fifth
	Engine.time_scale = 1.0
	await _shot("engineer_06_turrets")

	# 7. Out of sight he finishes the last two while the three fight on and then walk up to the line:
	# six turrets on one side, three fighters on the other.
	eng.visible = false
	for y in range(1, Consts.GRID_HEIGHT - 1):
		for x in range(8, Consts.GRID_WIDTH - 1):
			if arena.blocks_by_cell.has(Vector2i(x, y)):
				arena.destroy_block_at(Vector2i(x, y))
	_clear_powerups(Rect2i(8, 1, 8, 12))
	Music.play_track(Music.Track.ARENA)
	Engine.time_scale = 1.25
	_show_foes(true)
	_cut("pack", 2.3) # the battery is out of frame: the last turrets are built behind the camera
	await _until_mark("t6") # the fight goes on until the last turret is up
	await _shot("engineer_065_march")
	_foes_live(false)
	var line := [Vector2i(11, 5), Vector2i(11, 7), Vector2i(11, 9)]  # open lanes: odd rows and columns carry no pillars
	for i in 3:
		_run_along(foes[i], _lane_path(foes[i], 11, line[i].y), 0.5, 3.0)
	await _wait(3.05)
	for f in foes:
		_halt(f)
		_face(f, Consts.DIR_LEFT)
	await _until_mark("done")
	Engine.time_scale = 1.0
	_set_barrier(-1)
	# The whole map is open for the run: every crate goes, so nobody is walked through one.
	for y in range(1, Consts.GRID_HEIGHT - 1):
		for x in range(1, Consts.GRID_WIDTH - 1):
			if arena.blocks_by_cell.has(Vector2i(x, y)):
				arena.destroy_block_at(Vector2i(x, y))
	_clear_powerups(Rect2i(1, 1, Consts.GRID_WIDTH - 2, Consts.GRID_HEIGHT - 2))
	_defuse()
	var turrets := _battery()
	if turrets.size() != 6:
		push_warning("turrets built: %d of 6" % turrets.size())
	shield_floor = 0
	for f in foes:
		f.shield_charges = 0 # from here on, one blast is the end of any of them
		f.stats_changed.emit()
	for i in 3:
		foes[i].position = _cell_pos(line[i]) # (they are within a step of it already)
	eng.visible = true
	cam_point = _cell_pos(Vector2i(8, 6))
	_cut("point", 1.35)
	await _wait(0.4)
	await _shot("engineer_07_faceoff")
	if _alive_foes().size() != 3:
		push_warning("only %d foes at the face-off" % _alive_foes().size())
	# They see the battery.
	# The round would end (results overlay, countdown, reload three seconds later) the moment the
	# last one falls; the video needs the quiet and the dance after it, so the game is told nothing.
	GameManager.round_ended.disconnect(get_tree().current_scene._on_round_ended)
	Sfx.play("hazard_alarm", 1.0, 0.0)
	for f in foes:
		_say(f, "!", Color(1.0, 0.85, 0.15), 1.1, 70)
	await _wait(1.2)
	# 8. "FIRE!"
	_cut("eng", 2.4)
	_say(eng, "FIRE!", Color(1.0, 0.85, 0.2), 1.3, 52)
	await _wait(0.9)
	await _shot("engineer_08_fire")

	# 9. The barrage; the three run for it, along the open lanes.
	cam_point = _cell_pos(Vector2i(8, 6))
	_cut("point", 1.2) # the whole width of the map: the shells fall everywhere and the three run all over it
	var firsts := [Vector2i(2, 0), Vector2i(0, -2), Vector2i(4, 0)]
	var stretches := [Vector2i(9, 15), Vector2i(9, 15), Vector2i(9, 15)]  # the fighters' side of the map only
	var paces := [0.24, 0.27, 0.30]
	for i in 3:
		_run_along(foes[i], _scatter_path(line[i], firsts[i], stretches[i].x, stretches[i].y), paces[i])
	var shots := get_tree().create_timer(2.0, true, false, true)
	shots.timeout.connect(func(): _shot("engineer_09_barrage"))
	await _barrage(turrets, {6: 0, 10: 1, 14: 2})
	# The last one is down: the shells already in flight come in, his fall plays out, and the
	# field goes quiet before anyone cheers.
	var landing := 0.0
	while landing < 6.0:
		var busy := false
		for c in arena.get_children():
			var sp: Script = c.get_script()
			if sp == null:
				continue
			if sp.resource_path.ends_with("/Explosion.gd") or (sp.resource_path.ends_with("/Bomb.gd") and c.thrown and not c.has_exploded):
				busy = true
		if not busy and landing > 0.3:
			break
		await get_tree().process_frame
		landing += get_process_delta_time()
	await _wait(1.8) # the field is quiet: nothing in the air, nothing burning

	# 10. Victory.
	await _celebrate()
	await _shot("engineer_11_victory")
	await _wait(0.6)
	close_mode = false
