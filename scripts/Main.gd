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

var _winner_id_for_input: int = 0

func _ready() -> void:
	overlay.visible = false
	if GameManager.player_slots.is_empty():
		# Scene opened directly (e.g. in the editor) instead of via the Lobby.
		get_tree().change_scene_to_file.call_deferred(LobbyScenePath)
		return
	Music.play_track(Music.Track.ARENA)
	arena.generate()
	_fit_camera_to_arena()
	get_viewport().size_changed.connect(_fit_camera_to_arena)
	GameManager.round_ended.connect(_on_round_ended)
	_spawn_players()
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

func _input(event: InputEvent) -> void:
	if _winner_id_for_input <= 0 or not overlay.visible:
		return

	var device_id: int = -1
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT:
			device_id = -1
		elif event.keycode == KEY_RIGHT:
			device_id = -1

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			device_id = event.device
		elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
			device_id = event.device

	if device_id == -1:
		_change_winner_character(event.keycode == KEY_RIGHT if event is InputEventKey else false)
	elif device_id >= 0:
		_change_winner_character(event.button_index == JOY_BUTTON_DPAD_RIGHT, device_id)

func _change_winner_character(is_right: bool, device_id: int = -1) -> void:
	for slot in GameManager.player_slots:
		if slot["id"] == _winner_id_for_input and (device_id == -1 or slot["device"] == device_id):
			var delta = 1 if is_right else -1
			slot["character_id"] = posmod(slot["character_id"] + delta, Consts.CHARACTER_COUNT)
			Sfx.play("menu_confirm")
			return

func _fit_camera_to_arena() -> void:
	var arena_size := Vector2(Consts.GRID_WIDTH * Consts.CELL_SIZE, Consts.GRID_HEIGHT * Consts.CELL_SIZE)
	var viewport_size := get_viewport_rect().size
	var zoom_factor: float = max(arena_size.x / viewport_size.x, arena_size.y / viewport_size.y) * 1.05
	camera.zoom = Vector2(zoom_factor, zoom_factor)
	camera.position = arena_size / 2.0

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

	# Allow winner to change character during countdown
	_winner_id_for_input = winner_id

	for seconds_left in range(ROUND_END_DELAY_SECONDS, 0, -1):
		round_timer_label.text = Loc.t("NEXT_ROUND_IN", [seconds_left])
		Sfx.play("countdown_tick")
		await get_tree().create_timer(1.0).timeout

	if match_over:
		GameManager.reset_match()

	overlay.visible = false
	_winner_id_for_input = 0
	get_tree().reload_current_scene()
