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
	var want := target.clamp(view / 2.0, arena_px - view / 2.0)
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

func _slots(chars: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in chars.size():
		out.append({"id": i + 1, "device": Consts.DEVICE_BOT, "character_id": chars[i]})
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
	if plan == "story":
		await _story()
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


# --- The Engineer story -----------------------------------------------------------
#
# Staged rather than played: the Engineer (player 1, top-left corner) is driven by this
# script, the three foes are bots shoved into the opposite corner so they fight each
# other, and the camera cuts between the two. Everything the Engineer does goes through
# the game's own build / bomb / turret code, so the shots show real mechanics.

const ENG_CELL := Vector2i(1, 1)
const BOMB_CELL := Vector2i(3, 1)
## Character ids of the foes: Pyro, Bomb-Kicker, Bomb-Master.
const FOE_CHARS := [3, 4, 0]

func _story() -> void:
	segment += 1
	Consts.set_map_layout_index(1)
	Consts.set_map_size(4)
	Consts.set_sudden_death_index(Consts.SUDDEN_DEATH_OPTIONS.size() - 1)
	Consts.set_hazard_chance_percent(0)
	GameManager.set_player_slots(_slots([2] + FOE_CHARS))
	GameManager.reset_match()
	cam_mode = "player"
	close_mode = false
	get_tree().change_scene_to_file(MAIN)
	await _wait(0.1)
	var main := get_tree().current_scene
	main.set("_no_players_label", null)
	arena = main.get("arena")
	_stage()
	await _wait(0.1)
	# Establishing shot: the whole huge map, HUD and all.
	await _shot("story_00_wide")
	await _wait(2.5)
	await _shot("story_01_wide")
	_cut("eng", 2.0)
	_eng_clear()
	await _wait(8.0)
	_cut("pack", 1.7)
	await _wait(4.0)
	await _shot("story_02_fight")
	_cut("eng", 2.0)
	_eng_walls()
	await _wait(9.0)
	_cut("pack", 1.7)
	await _wait(3.0)
	await _shot("story_03_fight")
	_cut("eng", 2.0)
	await _eng_turrets()
	await _shot("story_04_turrets")
	_cut("pack", 1.7)
	await _foes_approach()
	await _wait(8.0)
	_cut("wide", 1.0)
	await _wait(3.0)
	await _shot("story_99_end")

func _cut(mode: String, zoom: float) -> void:
	if mode == "wide":
		close_mode = false
		return
	close_mode = true
	cam_mode = mode
	cam_zoom = zoom
	_snap_camera = true

func _player(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("player_id") == id:
			return p
	return null

## Players 2-4 go into the top-right pocket with extra shields so the fight lasts; the
## Engineer is taken off the controls; a lane along the top row is cleared so the foes
## have a way to the turrets.
func _stage() -> void:
	eng = _player(1)
	eng.is_bot = false
	eng.device_id = 99
	eng.bomb_count_max = 8
	eng.bomb_count_current = 8
	eng.stats_changed.emit()
	var pocket := [Vector2i(Consts.GRID_WIDTH - 2, 1), Vector2i(Consts.GRID_WIDTH - 3, 1), Vector2i(Consts.GRID_WIDTH - 2, 2)]
	foes.clear()
	for i in 3:
		var f := _player(i + 2)
		f.position = arena.cell_to_world(pocket[i])
		f.shield_charges += 8
		f.bomb_count_max = 3
		f.bomb_count_current = 3
		f.bomb_radius = 2
		f.stats_changed.emit()
		foes.append(f)
	for x in range(2, Consts.GRID_WIDTH - 1):
		if x == 4:
			continue # left for the Engineer's bomb
		arena.destroy_block_at(Vector2i(x, 1))
	arena.destroy_block_at(Vector2i(3, 2))
	arena.destroy_block_at(Vector2i(2, 1))

func _face(p: Node, dir: Vector2i) -> void:
	p.facing_dir = dir
	p.get_node("Portrait").face(dir)

## One step on the grid, at the character's own pace.
func _step(p: Node, to: Vector2i) -> void:
	var from: Vector2i = p.get_current_cell()
	_face(p, to - from)
	var dur: float = p.move_duration
	p.get_node("Portrait").set_walking(true, dur)
	p._scripted_move_to(arena.cell_to_world(to), dur)
	await _wait(dur + 0.03)

func _walk(p: Node, cells: Array) -> void:
	for c in cells:
		await _step(p, c)
	p.get_node("Portrait").set_walking(false)

## Hold the build button on the cell in front, for `seconds`.
func _hold_build(dir: Vector2i, seconds: float) -> void:
	_face(eng, dir)
	eng._begin_build()
	await _wait(seconds)
	eng._end_build()

func _eng_clear() -> void:
	await _walk(eng, [Vector2i(2, 1), BOMB_CELL])
	eng.place_bomb()
	await _wait(0.3)
	await _walk(eng, [Vector2i(2, 1), Vector2i(1, 1)])

func _eng_walls() -> void:
	await _wait(0.5)
	await _walk(eng, [Vector2i(2, 1), BOMB_CELL])
	await _hold_build(Vector2i(0, 1), 1.75)   # wall south of the bomb cell
	await _wait(0.3)
	await _hold_build(Vector2i(1, 0), 1.75)   # wall east of it
	await _wait(0.3)
	await _step(eng, Vector2i(2, 1))
	await _hold_build(Vector2i(1, 0), 1.75)   # wall on the bomb cell itself

func _eng_turrets() -> void:
	await _hold_build(Vector2i(1, 0), 3.3)
	await _step(eng, BOMB_CELL)
	await _hold_build(Vector2i(0, 1), 3.3)
	await _hold_build(Vector2i(1, 0), 3.3)

func _foes_approach() -> void:
	pass
