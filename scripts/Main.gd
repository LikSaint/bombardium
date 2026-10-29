extends Node2D

const PlayerScene := preload("res://scenes/Player.tscn")
const ArenaScript := preload("res://scripts/Arena.gd")
const LateJoinScript := preload("res://scripts/LateJoin.gd")
const LobbyScenePath := "res://scenes/Lobby.tscn"

@onready var arena: Node2D = $Arena
@onready var camera: Camera2D = $Camera2D
@onready var sudden_death: Node = $SuddenDeath
@onready var overlay: ColorRect = $UI/Overlay
@onready var results_box: VBoxContainer = $UI/Overlay/Results
@onready var results_label: Label = $UI/Overlay/Results/ResultsLabel
@onready var winner_portrait_box: Control = $UI/Overlay/Results/WinnerPortrait
@onready var winner_portrait = $UI/Overlay/Results/WinnerPortrait/Portrait # CharacterPortrait
@onready var winner_name_label: Label = $UI/Overlay/Results/WinnerName
@onready var match_over_menu: HBoxContainer = $UI/Overlay/Results/MatchOverMenu
@onready var match_over_hint: Label = $UI/Overlay/Results/MatchOverHint
@onready var round_timer_label: Label = $UI/Overlay/RoundTimerLabel
@onready var hud_corners: Array = [$UI/HudTopLeft, $UI/HudTopRight, $UI/HudBottomLeft, $UI/HudBottomRight]
@onready var hotkey_hint: Label = $UI/HotkeyHint
@onready var map_name_label: Label = $UI/MapNameLabel

const HOTKEY_HINT_VISIBLE_DURATION := 6.0
const HOTKEY_HINT_FADE_DURATION := 1.0
## The map name only has to be caught, not read twice — it goes away well
## before the control hint does.
const MAP_NAME_VISIBLE_DURATION := 3.0
const ROUND_END_DELAY_SECONDS := 3
## Fallback only, for the match-over screen with nobody there to press a
## button on it (every slot a bot, or every pad gone) — see _on_round_ended.
## Longer than a between-round countdown on its own timer: there's a final
## score to actually read, not just the one line that just changed.
const MATCH_END_DELAY_SECONDS := 6

# --- Match-over menu ---------------------------------------------------
#
# The between-round overlay times out and reloads on its own — there's
# nothing to decide, the same four players are about to play the next round
# regardless. The *match*-over screen is different: restart, back to the
# Lobby, and quit are three genuinely different things to do next, so instead
# of picking one on a timer this becomes a small menu and waits, exactly the
# way MainMenu.gd's title screen does — any connected device may drive it,
# since it's a shared "what's next" screen rather than one player's own pause
# menu.
var _match_over_options: Array[String] = ["restart", "lobby", "quit"]
var _match_over_selected: int = 0
var _match_over_active: bool = false

func _ready() -> void:
	overlay.visible = false
	if GameManager.player_slots.is_empty():
		# Scene opened directly (e.g. in the editor) instead of via the Lobby.
		get_tree().change_scene_to_file.call_deferred(LobbyScenePath)
		return
	Music.play_track(Music.Track.ARENA)
	arena.generate()
	Log.info("ARENA", "generated: layout=%s size=%dx%d random_walls=%s powerups=%d%% hazards=%d%% sudden_death=%s" % [
		Consts.layout_name_for_id(arena.layout_id), Consts.GRID_WIDTH, Consts.GRID_HEIGHT,
		Consts.random_indestructible_walls, Consts.powerup_chance_percent, Consts.hazard_chance_percent,
		Consts.SUDDEN_DEATH_LABELS[Consts.sudden_death_index]])
	GameManager.round_ended.connect(_on_round_ended)
	# Spawning first: it binds the HUD corners, and which of them are on screen
	# decides how much room the arena gets (see _frame_arena).
	_spawn_players()
	_setup_late_join()
	_frame_arena()
	get_viewport().size_changed.connect(_on_viewport_resized)
	# A window carried to a display of another pixel density can keep its logical
	# size, in which case only this fires.
	get_window().dpi_changed.connect(_on_viewport_resized)
	sudden_death.begin(arena)
	_refresh_hotkey_hint()
	Loc.language_changed.connect(_refresh_hotkey_hint)
	_show_hotkey_hint()
	_show_map_name()

func _refresh_hotkey_hint() -> void:
	hotkey_hint.text = Loc.t("MAIN_HOTKEY_HINT")

## Which map this round is being played on. Worth a line on screen mainly
## because the Map setting defaults to Random and re-rolls every round — without
## it the terrain changing under everyone reads as the game being inconsistent
## rather than as the setting doing what it says.
func _show_map_name() -> void:
	map_name_label.text = Consts.layout_name_for_id(arena.layout_id)
	map_name_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(MAP_NAME_VISIBLE_DURATION)
	tw.tween_property(map_name_label, "modulate:a", 0.0, HOTKEY_HINT_FADE_DURATION)

func _show_hotkey_hint() -> void:
	hotkey_hint.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(HOTKEY_HINT_VISIBLE_DURATION)
	tw.tween_property(hotkey_hint, "modulate:a", 0.0, HOTKEY_HINT_FADE_DURATION)

# --- Arena framing and HUD layout -------------------------------------------
#
# The arena is a fixed pixel rectangle whose size comes from the map-size
# setting (9x7 up to 21x17 cells), while the window is whatever the player
# gives us — a resized macOS window, a Steam Deck's 1280x800, a TV, a window
# dragged onto a monitor of another shape. The aim is that the arena takes as
# much of the screen as it can and the HUD takes the rest, so nothing is left
# as dead space: the camera zoom is derived from the viewport every time it
# changes, and the HUD is laid out around the result.
#
# Note that Camera2D.zoom *magnifies* in Godot 4 (2.0 draws the world twice as
# large, 0.5 half as large) — the reverse of Godot 3, where it divided.
#
# The arena must never grow underneath an occupied HUD panel (the spawn cells
# sit in its corners). Two framings are tried — SIDES, the arena in the column
# between the left and right panels, and ROWS, the arena in the row between the
# top and bottom ones — and whichever lets the arena be bigger wins. Panels of
# players who aren't in the match reserve nothing.
#
# Once the arena is placed, whatever is left on either side of it is the HUD's:
# the panels are centred in those bars and scaled up to fill them (never below
# their designed size), and the Backdrop layer paints the bars and the rest of
# the window in the HUD's own colour. A wide screen therefore gets big side
# panels rather than a small arena with empty margins.

## Breathing room between the arena and the screen edge / a HUD panel.
const ARENA_SCREEN_MARGIN := 16.0
## Gap between a HUD panel and the screen edge.
const HUD_EDGE_MARGIN := 12.0
## A panel grows to fill the leftover space, but past this it is just a
## blown-up widget — better to leave the rest to the backdrop.
const HUD_MAX_SCALE := 2.0
## High enough that a tiny map on a big screen still fills it; this is only a
## sanity bound.
const ARENA_MAX_ZOOM := 6.0
## Only reached on a window too small to hold anything; keeps zoom positive.
const ARENA_MIN_ZOOM := 0.05

enum HudLayout { SIDES, ROWS }

@onready var hud_bars: Array = [$Backdrop/HudBarA, $Backdrop/HudBarB]

## Everything below depends on the viewport size alone, so one signal covers a
## window resize, a fullscreen toggle, and a window moved to a display of a
## different size or scale (the stretch factor changes with the window's pixel
## size). Deferred so the viewport has finished updating when it is measured.
func _on_viewport_resized() -> void:
	_frame_arena.call_deferred()
	if overlay.visible:
		_fit_results_block.call_deferred()

func _frame_arena() -> void:
	var arena_size := Consts.arena_pixel_size()
	var viewport_size := get_viewport_rect().size
	var panel_size := _hud_panel_size()
	var layout := HudLayout.SIDES
	var frame := _hud_free_rect(viewport_size, panel_size, HudLayout.SIDES)
	var rows_frame := _hud_free_rect(viewport_size, panel_size, HudLayout.ROWS)
	if _fit_zoom(arena_size, rows_frame.size) > _fit_zoom(arena_size, frame.size):
		layout = HudLayout.ROWS
		frame = rows_frame

	var zoom := _fit_zoom(arena_size, frame.size)
	camera.zoom = Vector2(zoom, zoom)
	# Centre the arena on `frame` rather than on the viewport: with only some of
	# the HUD panels visible the free area is off-centre, and the camera has to
	# shift by the same amount (in world units, hence the division by zoom).
	camera.position = arena_size / 2.0 - (frame.get_center() - viewport_size / 2.0) / zoom

	var arena_rect := Rect2(frame.get_center() - arena_size * zoom / 2.0, arena_size * zoom)
	_layout_hud(layout, viewport_size, panel_size, arena_rect)

func _hud_panel_size() -> Vector2:
	return hud_corners[0].custom_minimum_size

## Corner `i` is slot `i`'s panel: top-left, top-right, bottom-left, bottom-right.
func _hud_column_occupied(column: int) -> bool:
	for i in hud_corners.size():
		if i % 2 == column and hud_corners[i].visible:
			return true
	return false

func _hud_row_occupied(row: int) -> bool:
	for i in hud_corners.size():
		if i / 2 == row and hud_corners[i].visible:
			return true
	return false

## The part of the viewport the arena may occupy: everything except the HUD
## panels it has to stay clear of, at their designed size — the left/right
## column for SIDES, the top/bottom row for ROWS.
func _hud_free_rect(viewport_size: Vector2, panel_size: Vector2, layout: HudLayout) -> Rect2:
	var left := ARENA_SCREEN_MARGIN
	var right := ARENA_SCREEN_MARGIN
	var top := ARENA_SCREEN_MARGIN
	var bottom := ARENA_SCREEN_MARGIN
	var reserve_x := HUD_EDGE_MARGIN + panel_size.x + ARENA_SCREEN_MARGIN
	var reserve_y := HUD_EDGE_MARGIN + panel_size.y + ARENA_SCREEN_MARGIN
	if layout == HudLayout.SIDES:
		if _hud_column_occupied(0):
			left = reserve_x
		if _hud_column_occupied(1):
			right = reserve_x
	else:
		if _hud_row_occupied(0):
			top = reserve_y
		if _hud_row_occupied(1):
			bottom = reserve_y
	return Rect2(left, top, viewport_size.x - left - right, viewport_size.y - top - bottom)

## Largest zoom at which `content` still fits inside `available`, both in
## pixels. Clamped, so a viewport too small to fit anything (`available` can go
## negative once the HUD is reserved) can't produce a zero or negative zoom.
func _fit_zoom(content: Vector2, available: Vector2) -> float:
	if content.x <= 0.0 or content.y <= 0.0:
		return 1.0
	return clampf(minf(available.x / content.x, available.y / content.y), ARENA_MIN_ZOOM, ARENA_MAX_ZOOM)

## Fills what the arena left over with the HUD: the two backdrop bars take the
## exact leftover on either side of the arena, and each panel is scaled to the
## roomiest size that fits its bar, then centred across the bar and pushed to
## the screen edge along it.
func _layout_hud(layout: HudLayout, viewport_size: Vector2, panel_size: Vector2, arena_rect: Rect2) -> void:
	var bars: Array[Rect2] = []
	if layout == HudLayout.SIDES:
		bars.append(Rect2(0.0, 0.0, arena_rect.position.x, viewport_size.y))
		bars.append(Rect2(arena_rect.end.x, 0.0, viewport_size.x - arena_rect.end.x, viewport_size.y))
	else:
		bars.append(Rect2(0.0, 0.0, viewport_size.x, arena_rect.position.y))
		bars.append(Rect2(0.0, arena_rect.end.y, viewport_size.x, viewport_size.y - arena_rect.end.y))
	for i in hud_bars.size():
		hud_bars[i].position = bars[i].position
		hud_bars[i].size = bars[i].size

	# One scale for all panels, so the four corners stay the same size: the
	# tightest bar that actually holds a panel decides it. A panel that can't
	# be enlarged isn't shrunk below its designed size either.
	var hud_scale := HUD_MAX_SCALE
	for i in hud_corners.size():
		if not hud_corners[i].visible:
			continue
		var bar: Rect2 = bars[i % 2] if layout == HudLayout.SIDES else bars[i / 2]
		var room := bar.size - Vector2.ONE * (HUD_EDGE_MARGIN + ARENA_SCREEN_MARGIN)
		var across := room.x / panel_size.x if layout == HudLayout.SIDES else room.y / panel_size.y
		# Along the bar the panels share the screen edge to edge, two to a bar.
		var along_room := viewport_size - Vector2.ONE * HUD_EDGE_MARGIN * 3.0
		var along := along_room.y / 2.0 / panel_size.y if layout == HudLayout.SIDES else along_room.x / 2.0 / panel_size.x
		hud_scale = minf(hud_scale, minf(across, along))
	hud_scale = maxf(hud_scale, 1.0)

	var scaled := panel_size * hud_scale
	for i in hud_corners.size():
		var column := i % 2
		var row := i / 2
		var corner: Control = hud_corners[i]
		corner.scale = Vector2(hud_scale, hud_scale)
		if layout == HudLayout.SIDES:
			var bar: Rect2 = bars[column]
			var y := HUD_EDGE_MARGIN if row == 0 else viewport_size.y - HUD_EDGE_MARGIN - scaled.y
			corner.position = Vector2(bar.position.x + (bar.size.x - scaled.x) / 2.0, y)
		else:
			var bar: Rect2 = bars[row]
			var x := HUD_EDGE_MARGIN if column == 0 else viewport_size.x - HUD_EDGE_MARGIN - scaled.x
			corner.position = Vector2(x, bar.position.y + (bar.size.y - scaled.y) / 2.0)

# --- Joining a match in progress ---------------------------------------------

## How long a match with nobody left in it but bots carries on before it ends, unless
## somebody sits down: the pads that were playing it are all gone, so nobody is watching.
const NO_HUMANS_GRACE := 5.0
var _no_humans_left: float = NO_HUMANS_GRACE
var _no_players_label: Label = null

func _setup_late_join() -> void:
	var late_join := Node.new()
	late_join.set_script(LateJoinScript)
	late_join.main = self
	add_child(late_join)
	refresh_free_slot_placeholder()
	_no_players_label = Label.new()
	_no_players_label.anchor_left = 0.5
	_no_players_label.anchor_right = 0.5
	_no_players_label.offset_left = -300.0
	_no_players_label.offset_right = 300.0
	_no_players_label.offset_top = 84.0
	_no_players_label.offset_bottom = 124.0
	_no_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_players_label.add_theme_font_size_override("font_size", 24)
	_no_players_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_no_players_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_no_players_label.add_theme_constant_override("outline_size", 8)
	_no_players_label.visible = false
	$UI.add_child(_no_players_label)

## A match with only bots left in it (every pad that was playing has gone) ends after
## NO_HUMANS_GRACE seconds, with the count shown, unless a person joins in the meantime
## (see LateJoin). Not counted while paused or over a results screen — those have their
## own timings — and it starts over each time someone is there.
func _process(delta: float) -> void:
	if _no_players_label == null:
		return
	if _has_human_player() or overlay.visible or _match_over_active or get_tree().paused:
		_no_humans_left = NO_HUMANS_GRACE
		_no_players_label.visible = false
		return
	_no_humans_left -= delta
	_no_players_label.visible = true
	_no_players_label.text = Loc.t("NO_PLAYERS_LEFT", [maxi(1, ceili(_no_humans_left))])
	if _no_humans_left <= 0.0:
		set_process(false)
		GameManager.leave_to_lobby()
		get_tree().change_scene_to_file(LobbyScenePath)
#
# The interaction itself — press any button, pick which seat, confirm — is LateJoin.gd;
# this is what it asks of the match. A seat can be taken in two ways: the first free
# slot (the match was started with fewer players than it has slots), which spawns a new
# player, or a bot's, which the newcomer takes over.

## Whether a person may join right now: not while paused, over a results screen or
## the match-over menu, and not once the round has ended.
func late_join_allowed() -> bool:
	return not (get_tree().paused or overlay.visible or _match_over_active or GameManager.round_over)

## The seats a newcomer can pick between, as slot indices in screen order: every bot,
## and the first free slot. Only the first free one, because the slots fill in order and
## a gap in the list would be a player who doesn't exist.
func join_candidates() -> Array[int]:
	var out: Array[int] = []
	var slots := GameManager.player_slots
	for i in slots.size():
		if slots[i]["device"] == Consts.DEVICE_BOT:
			out.append(i)
	var free := _free_slot_index()
	if free >= 0:
		out.append(free)
	return out

## The first slot nobody holds, or -1 if the match is full.
func _free_slot_index() -> int:
	var index := GameManager.player_slots.size()
	if index < mini(Consts.configured_player_slots, hud_corners.size()):
		return index
	return -1

## Shows the "press any button" placeholder on the first free slot's corner, if there
## is one — an empty panel with nothing in it but the invitation.
func refresh_free_slot_placeholder() -> void:
	var free := _free_slot_index()
	for i in range(GameManager.player_slots.size(), hud_corners.size()):
		if i == free:
			hud_corners[i].show_empty_slot()
		else:
			hud_corners[i].hide_empty_slot()
	_frame_arena.call_deferred()

## Where a player joining mid-round enters: their corner's spawn cell, or the nearest
## open cell if that has been built over or blown up since. Returns (-1, -1) if there
## is nowhere within a few cells.
func _late_spawn_cell(slot_index: int) -> Vector2i:
	var home: Vector2i = arena.get_spawn_cells()[slot_index]
	var best := Vector2i(-1, -1)
	var best_dist := 1 << 30
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := home + Vector2i(dx, dy)
			if not arena.in_bounds(c) or arena.get_cell_state(c) != ArenaScript.CellState.EMPTY:
				continue
			if arena.is_block(c) or arena.has_bomb_at(c) or arena.is_pit(c):
				continue
			var d := absi(dx) + absi(dy)
			if d < best_dist:
				best_dist = d
				best = c
	return best

## Seats `device` at `slot_index` (one of join_candidates()). Returns whether it worked.
func join_slot(device: int, slot_index: int) -> bool:
	if not late_join_allowed() or GameManager.device_in_match(device):
		return false
	var slots := GameManager.player_slots
	if slot_index == _free_slot_index():
		return _join_free_slot(device)
	if slot_index >= 0 and slot_index < slots.size() and slots[slot_index]["device"] == Consts.DEVICE_BOT:
		Log.info("JOIN", "device %d takes over the bot at slot %d (%s)" % [device, slot_index, Log.who(slots[slot_index]["id"], slots[slot_index]["character_id"], device)])
		slots[slot_index]["device"] = device
		GameManager.player_reconnected.emit(slots[slot_index]["id"], device)
		return true
	return false

func _join_free_slot(device: int) -> bool:
	var index := GameManager.player_slots.size()
	var cell := _late_spawn_cell(index)
	if cell == Vector2i(-1, -1):
		return false
	var slot := {"id": index + 1, "device": device, "character_id": randi() % Consts.CHARACTER_COUNT}
	if not GameManager.join_round(slot["id"]):
		return false
	Log.info("JOIN", "%s joins the free slot %d at %s" % [Log.who(slot["id"], slot["character_id"], device), index, Log.cell(cell)])
	GameManager.player_slots.append(slot)
	var p := PlayerScene.instantiate()
	p.player_id = slot["id"]
	p.device_id = device
	p.character_id = slot["character_id"]
	p.position = arena.cell_to_world(cell)
	arena.add_child(p)
	p.arena = arena
	hud_corners[index].bind(p)
	# A second of grace: they appear into a fight that is already going on.
	p._start_invulnerability()
	# The next free slot, if any, gets the placeholder now; the arena is refitted.
	refresh_free_slot_placeholder()
	return true

func _spawn_players() -> void:
	var spawn_cells: Array = arena.get_spawn_cells()
	var player_ids: Array[int] = []
	for i in GameManager.player_slots.size():
		var slot: Dictionary = GameManager.player_slots[i]
		var p := PlayerScene.instantiate()
		p.player_id = slot["id"]
		p.device_id = slot["device"]
		p.character_id = slot["character_id"]
		p.position = arena.cell_to_world(spawn_cells[i])
		arena.add_child(p)
		p.arena = arena
		if i < hud_corners.size():
			hud_corners[i].bind(p)
		player_ids.append(slot["id"])
		Log.info("SPAWN", "%s at %s" % [Log.who(slot["id"], slot["character_id"], slot["device"]), Log.cell(spawn_cells[i])])

	GameManager.start_round(player_ids)

# --- Winner portrait -------------------------------------------------------
#
# Who won is a character first and a slot number second. The results text has
# always named the slot ("Player 2"), but a few rounds in nobody remembers which
# corner that was, and everyone re-picks between rounds anyway — so the overlay
# leads with the winner's own sprite, blown up big, in their team color and
# walking on the spot.

const WINNER_PORTRAIT_SCALE := 3.5
## Entrance pop: the portrait springs out to full size rather than just being there.
const WINNER_POP_START_SCALE := 0.55
const WINNER_POP_DURATION := 0.35
## How long one step of the victory walk takes. Deliberately slower than the
## in-arena walk (paced to the character's real move speed) — this is a strut.
const WINNER_WALK_STEP_SECONDS := 0.6

## A `player_id` of -1 (a draw, or an empty score table) leaves the overlay as
## text only.
func _show_winner(player_id: int) -> void:
	var winner := _find_player(player_id)
	winner_portrait_box.visible = winner != null
	winner_name_label.visible = winner != null
	if winner == null:
		return

	var color: Color = Consts.PLAYER_COLORS[(player_id - 1) % Consts.PLAYER_COLORS.size()]
	# The character they actually played this round, taken off the live Player
	# rather than their GameManager slot: a player who died early may already
	# have re-picked, and that pick belongs to the next round, not this result.
	winner_portrait.set_character(winner.character_id, color)
	winner_portrait.set_walking(true, WINNER_WALK_STEP_SECONDS)
	winner_name_label.text = Consts.character_name(winner.character_id)
	winner_name_label.add_theme_color_override("font_color", color)

	var full := Vector2(WINNER_PORTRAIT_SCALE, WINNER_PORTRAIT_SCALE)
	winner_portrait.scale = full * WINNER_POP_START_SCALE
	create_tween().tween_property(winner_portrait, "scale", full, WINNER_POP_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The results block is a fixed pixel stack — a chest-high portrait, the name,
## and up to seven score lines — on a window that can be any size, so it gets
## the same treatment as the arena: measured, and shrunk as one piece when the
## window is too short to hold it. Never enlarged; at rest it is already as big
## as it should be. Deferred one frame by its callers so the labels have
## re-measured against their new text first.
##
## The shrink is anchored at the top of the block rather than its middle: a
## block that doesn't fit sits at the top of its rect (see
## _results_available_height), so scaling about its top edge is what lands it
## back inside.
func _fit_results_block() -> void:
	var content := results_box.get_combined_minimum_size().y
	var fit := 1.0 if content <= 0.0 else minf(1.0, _results_available_height() / content)
	results_box.pivot_offset = Vector2(results_box.size.x / 2.0, 0.0)
	results_box.scale = Vector2(fit, fit)

## The height the block is allowed to use, worked out from its anchors rather
## than read off `size`: a Control clamps its own size up to its minimum size,
## so a block that overflows always reports the height it wants, never the
## height it actually has to fit into.
func _results_available_height() -> float:
	var viewport_height := get_viewport_rect().size.y
	var top := viewport_height * results_box.anchor_top + results_box.offset_top
	var bottom := viewport_height * results_box.anchor_bottom + results_box.offset_bottom
	return bottom - top

## The live Player node behind a slot id, found through the HUD corner it is
## bound to. Dead players stay in the tree (just hidden), so this also resolves
## a match winner who didn't survive the final round.
func _find_player(player_id: int) -> Node:
	if player_id <= 0:
		return null
	for corner in hud_corners:
		if corner.player != null and corner.player.player_id == player_id:
			return corner.player
	return null

func _on_round_ended(winner_id: int) -> void:
	var match_over := GameManager.is_match_over()
	var lines: PackedStringArray = []

	if match_over:
		lines.append(Loc.t("MATCH_OVER"))
		lines.append(Loc.t("MATCH_WINNER", [GameManager.get_match_winner()]))
		Sfx.play("match_win")
		_show_winner(GameManager.get_match_winner())
	elif winner_id == -1:
		lines.append(Loc.t("ROUND_DRAW", [GameManager.round_number, GameManager.rounds_per_match]))
		Sfx.play("round_draw")
		_show_winner(-1)
	else:
		lines.append(Loc.t("ROUND_WINNER", [GameManager.round_number, GameManager.rounds_per_match, winner_id]))
		Sfx.play("round_win")
		_show_winner(winner_id)

	lines.append("")
	lines.append(Loc.t("SCORE_HEADER"))
	var ids: Array = GameManager.scores.keys()
	ids.sort()
	for id in ids:
		lines.append(Loc.t("SCORE_LINE", [id, GameManager.scores[id]]))

	results_label.text = "\n".join(lines)
	overlay.visible = true
	_fit_results_block.call_deferred()

	# The winner gets the countdown to re-pick their character, on their own
	# HUD corner — the same arrows-over-the-portrait UI a dead player gets
	# mid-round (see PlayerHudCorner.begin_winner_repick), not a separate
	# screen-center prompt. Skipped when the match is over (the whole line-up
	# is re-chosen in the lobby anyway). A bot winner re-picks on its own.
	if not match_over and winner_id > 0:
		for corner in hud_corners:
			if corner.player != null and corner.player.player_id == winner_id:
				corner.begin_winner_repick()
				break

	if match_over:
		# A finished match stops here rather than quietly dealing itself
		# another — reset_match() + reload_current_scene() used to do exactly
		# that unconditionally, and with nothing gating it a match "ending"
		# never actually ended: round_number was zeroed and the same four
		# players went straight back into round 1 with no sign anything had
		# happened.
		#
		# With somebody there to press a button, what replaces it is a menu
		# rather than a fixed choice — see _show_match_over_menu. Without
		# anybody (every slot a bot, every pad gone), there's nobody to press
		# it, so that's the one case that still falls back to the old
		# auto-timeout, now landing on the Lobby instead of quietly
		# restarting.
		if _has_human_player():
			_show_match_over_menu()
			return
		for seconds_left in range(MATCH_END_DELAY_SECONDS, 0, -1):
			round_timer_label.text = Loc.t("RETURNING_TO_LOBBY_IN", [seconds_left])
			Sfx.play("countdown_tick")
			await get_tree().create_timer(1.0).timeout
		GameManager.leave_to_lobby()
		get_tree().change_scene_to_file(LobbyScenePath)
		return

	for seconds_left in range(ROUND_END_DELAY_SECONDS, 0, -1):
		round_timer_label.text = Loc.t("NEXT_ROUND_IN", [seconds_left])
		Sfx.play("countdown_tick")
		await get_tree().create_timer(1.0).timeout

	overlay.visible = false
	Log.info("ROUND", "reloading the arena for the next round")
	get_tree().reload_current_scene()

func _has_human_player() -> bool:
	return GameManager.has_human()

## Puts up the Restart/Lobby/Quit row and hands input over to it (_input,
## below) instead of counting down — see the section note above
## _match_over_options for why this one doesn't time out on its own.
func _show_match_over_menu() -> void:
	round_timer_label.visible = false
	match_over_hint.text = Loc.t("MATCH_OVER_HINT")
	match_over_hint.visible = true
	match_over_menu.visible = true
	_match_over_selected = 0
	_match_over_active = true
	_refresh_match_over_selection()
	_fit_results_block.call_deferred()

func _refresh_match_over_selection() -> void:
	for i in _match_over_options.size():
		var node: Control = match_over_menu.get_node(_match_over_options[i].capitalize())
		node.modulate = Color(1, 1, 1, 1) if i == _match_over_selected else Color(1, 1, 1, 0.45)
		node.scale = Vector2(1.15, 1.15) if i == _match_over_selected else Vector2(1, 1)

## Any connected device drives this — it's a shared "what's next" screen, not
## one player's private pause menu, exactly like MainMenu.gd's title screen.
func _input(event: InputEvent) -> void:
	if not _match_over_active:
		return
	if _is_menu_prev(event):
		_match_over_selected = (_match_over_selected - 1 + _match_over_options.size()) % _match_over_options.size()
		_refresh_match_over_selection()
		Sfx.play_menu()
	elif _is_menu_next(event):
		_match_over_selected = (_match_over_selected + 1) % _match_over_options.size()
		_refresh_match_over_selection()
		Sfx.play_menu()
	elif _is_menu_confirm(event):
		Sfx.play_menu()
		_activate_match_over_option(_match_over_options[_match_over_selected])

func _activate_match_over_option(option: String) -> void:
	_match_over_active = false
	match option:
		"restart":
			GameManager.reset_match()
			get_tree().reload_current_scene()
		"lobby":
			GameManager.leave_to_lobby()
			get_tree().change_scene_to_file(LobbyScenePath)
		"quit":
			get_tree().quit()

func _is_menu_prev(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_A or event.keycode == KEY_W):
		return true
	if event is InputEventJoypadButton and event.pressed and (event.button_index == JOY_BUTTON_DPAD_LEFT or event.button_index == JOY_BUTTON_DPAD_UP):
		return true
	return false

func _is_menu_next(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_D or event.keycode == KEY_S):
		return true
	if event is InputEventJoypadButton and event.pressed and (event.button_index == JOY_BUTTON_DPAD_RIGHT or event.button_index == JOY_BUTTON_DPAD_DOWN):
		return true
	return false

func _is_menu_confirm(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		return true
	return Pad.is_confirm_button(event)
