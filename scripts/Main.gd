extends Node2D

const PlayerScene := preload("res://scenes/Player.tscn")
const LobbyScenePath := "res://scenes/Lobby.tscn"

@onready var arena: Node2D = $Arena
@onready var camera: Camera2D = $Camera2D
@onready var sudden_death: Node = $SuddenDeath
@onready var overlay: ColorRect = $UI/Overlay
@onready var results_label: Label = $UI/Overlay/ResultsLabel
@onready var round_timer_label: Label = $UI/Overlay/RoundTimerLabel
@onready var hud_corners: Array = [$UI/HudTopLeft, $UI/HudTopRight, $UI/HudBottomLeft, $UI/HudBottomRight]
@onready var hotkey_hint: Label = $UI/HotkeyHint

const HOTKEY_HINT_VISIBLE_DURATION := 6.0
const HOTKEY_HINT_FADE_DURATION := 1.0
const ROUND_END_DELAY_SECONDS := 3

func _ready() -> void:
	overlay.visible = false
	if GameManager.player_slots.is_empty():
		# Scene opened directly (e.g. in the editor) instead of via the Lobby.
		get_tree().change_scene_to_file.call_deferred(LobbyScenePath)
		return
	Music.play_track(Music.Track.ARENA)
	arena.generate()
	GameManager.round_ended.connect(_on_round_ended)
	# Spawning first: it binds the HUD corners, and which of them are on screen
	# decides how much room the arena gets (see _frame_arena).
	_spawn_players()
	_frame_arena()
	get_viewport().size_changed.connect(_on_viewport_resized)
	sudden_death.begin(arena)
	_refresh_hotkey_hint()
	Loc.language_changed.connect(_refresh_hotkey_hint)
	_show_hotkey_hint()

func _refresh_hotkey_hint() -> void:
	hotkey_hint.text = Loc.t("MAIN_HOTKEY_HINT")

func _show_hotkey_hint() -> void:
	hotkey_hint.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(HOTKEY_HINT_VISIBLE_DURATION)
	tw.tween_property(hotkey_hint, "modulate:a", 0.0, HOTKEY_HINT_FADE_DURATION)

# --- Arena framing ---------------------------------------------------------
#
# The arena is a fixed pixel rectangle whose size comes from the map-size
# setting (9x7 up to 21x17 cells), while the window is whatever the player
# gives us — a resized macOS window, a Steam Deck's 1280x800, a TV. So the
# camera zoom is derived from the viewport every time either one changes, and
# the whole arena always ends up on screen: scaled down when it is too big,
# scaled up when it would otherwise sit as a small island in the middle.
#
# Note that Camera2D.zoom *magnifies* in Godot 4 (2.0 draws the world twice as
# large, 0.5 half as large) — the reverse of Godot 3, where it divided.
#
# The four HUD corner panels live on a CanvasLayer at fixed viewport
# coordinates and the spawn cells sit in the arena's own corners, so the arena
# must never grow underneath an occupied panel. Two framings are tried — the
# arena in the column between the side panels, and the arena in the row between
# the top and bottom ones — and whichever leaves the arena bigger wins. Panels
# of players who aren't in the match reserve nothing, so a two-player round
# gets the entire bottom of the screen to itself.

## Breathing room between the arena and the screen edge / a HUD panel.
const ARENA_SCREEN_MARGIN := 16.0
## Tiny maps on a big screen would otherwise be blown up to a comic scale.
const ARENA_MAX_ZOOM := 2.0
## Only reached on a window too small to hold anything; keeps zoom positive.
const ARENA_MIN_ZOOM := 0.05

func _on_viewport_resized() -> void:
	# Deferred so the HUD panels have re-anchored to the new viewport before
	# their rects are measured below.
	_frame_arena.call_deferred()

func _frame_arena() -> void:
	var arena_size := Consts.arena_pixel_size()
	var viewport_size := get_viewport_rect().size
	var between_columns := _hud_free_rect(viewport_size, true)
	var between_rows := _hud_free_rect(viewport_size, false)
	var frame := between_columns
	if _fit_zoom(arena_size, between_rows.size) > _fit_zoom(arena_size, between_columns.size):
		frame = between_rows

	var zoom := _fit_zoom(arena_size, frame.size)
	camera.zoom = Vector2(zoom, zoom)
	# Centre the arena on `frame` rather than on the viewport: with only some of
	# the HUD panels visible the free area is off-centre, and the camera has to
	# shift by the same amount (in world units, hence the division by zoom).
	camera.position = arena_size / 2.0 - (frame.get_center() - viewport_size / 2.0) / zoom

## The part of the viewport the arena may occupy: everything except the HUD
## panels it has to stay clear of — the left/right ones when `reserve_sides` is
## true, the top/bottom ones otherwise. Panels are measured rather than
## hard-coded so moving one in Main.tscn keeps the framing honest.
func _hud_free_rect(viewport_size: Vector2, reserve_sides: bool) -> Rect2:
	var left := ARENA_SCREEN_MARGIN
	var right := ARENA_SCREEN_MARGIN
	var top := ARENA_SCREEN_MARGIN
	var bottom := ARENA_SCREEN_MARGIN
	for corner in hud_corners:
		if not corner.visible:
			continue
		var rect: Rect2 = corner.get_global_rect()
		if reserve_sides:
			if rect.get_center().x < viewport_size.x / 2.0:
				left = maxf(left, rect.end.x + ARENA_SCREEN_MARGIN)
			else:
				right = maxf(right, viewport_size.x - rect.position.x + ARENA_SCREEN_MARGIN)
		elif rect.get_center().y < viewport_size.y / 2.0:
			top = maxf(top, rect.end.y + ARENA_SCREEN_MARGIN)
		else:
			bottom = maxf(bottom, viewport_size.y - rect.position.y + ARENA_SCREEN_MARGIN)
	return Rect2(left, top, viewport_size.x - left - right, viewport_size.y - top - bottom)

## Largest zoom at which `content` still fits inside `available`, both in
## pixels. Clamped, so a viewport too small to fit anything (`available` can go
## negative once the HUD is reserved) can't produce a zero or negative zoom.
func _fit_zoom(content: Vector2, available: Vector2) -> float:
	if content.x <= 0.0 or content.y <= 0.0:
		return 1.0
	return clampf(minf(available.x / content.x, available.y / content.y), ARENA_MIN_ZOOM, ARENA_MAX_ZOOM)

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

	GameManager.start_round(player_ids)

func _on_round_ended(winner_id: int) -> void:
	var match_over := GameManager.is_match_over()
	var lines: PackedStringArray = []

	if match_over:
		lines.append(Loc.t("MATCH_OVER"))
		lines.append(Loc.t("MATCH_WINNER", [GameManager.get_match_winner()]))
		Sfx.play("match_win")
	elif winner_id == -1:
		lines.append(Loc.t("ROUND_DRAW", [GameManager.round_number, GameManager.rounds_per_match]))
		Sfx.play("round_draw")
	else:
		lines.append(Loc.t("ROUND_WINNER", [GameManager.round_number, GameManager.rounds_per_match, winner_id]))
		Sfx.play("round_win")

	lines.append("")
	lines.append(Loc.t("SCORE_HEADER"))
	var ids: Array = GameManager.scores.keys()
	ids.sort()
	for id in ids:
		lines.append(Loc.t("SCORE_LINE", [id, GameManager.scores[id]]))

	results_label.text = "\n".join(lines)
	overlay.visible = true

	# The winner gets the countdown to re-pick their character, on their own
	# HUD corner — the same arrows-over-the-portrait UI a dead player gets
	# mid-round (see PlayerHudCorner.begin_winner_repick), not a separate
	# screen-center prompt. Skipped when the match is over (the whole line-up
	# is re-chosen in the lobby anyway) and for bots or a disconnected pad,
	# which have nobody to press the arrows.
	if not match_over and winner_id > 0:
		for corner in hud_corners:
			if corner.player != null and corner.player.player_id == winner_id \
					and corner.player.device_id != Consts.DEVICE_BOT and corner.player.device_id != Consts.DEVICE_NONE:
				corner.begin_winner_repick()
				break

	for seconds_left in range(ROUND_END_DELAY_SECONDS, 0, -1):
		round_timer_label.text = Loc.t("NEXT_ROUND_IN", [seconds_left])
		Sfx.play("countdown_tick")
		await get_tree().create_timer(1.0).timeout

	if match_over:
		GameManager.reset_match()

	overlay.visible = false
	get_tree().reload_current_scene()
