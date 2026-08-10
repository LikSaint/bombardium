extends Node2D

const PlayerScene := preload("res://scenes/Player.tscn")
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
	if overlay.visible:
		_fit_results_block.call_deferred()

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
	# is re-chosen in the lobby anyway) and for bots or a disconnected pad,
	# which have nobody to press the arrows.
	if not match_over and winner_id > 0:
		for corner in hud_corners:
			if corner.player != null and corner.player.player_id == winner_id \
					and corner.player.device_id != Consts.DEVICE_BOT and corner.player.device_id != Consts.DEVICE_NONE:
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
	get_tree().reload_current_scene()

func _has_human_player() -> bool:
	for slot in GameManager.player_slots:
		if slot["device"] != Consts.DEVICE_BOT and slot["device"] != Consts.DEVICE_NONE:
			return true
	return false

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
