extends Node
## Autoloaded as `GameManager`. Tracks round/match state and scores across scene reloads.

signal round_ended(winner_id: int)
signal player_disconnected(player_id: int)
signal player_reconnected(player_id: int, device: int)

# How many rounds a match runs for. Captured from Consts.rounds_per_match()
# when the match starts (reset_match) so it can't shift mid-match even if the
# Lobby's Settings screen is revisited later (e.g. after a "menu" exit).
var rounds_per_match: int = 5

# Set once by the Lobby, then persists across round reloads within a match.
# Each entry: {id: int, device: int, character_id: int}. A dead player can
# change their own "character_id" here mid-round; it takes effect next round.
var player_slots: Array[Dictionary] = []

var alive_players: Array[int] = []
var scores: Dictionary = {}
var round_number: int = 0
var round_over: bool = false # guards against round_ended firing twice (see player_died)

# LIFO: a controller reconnecting reclaims the most recently dropped player
# first (drop P1 then P2 -> next controller to press gets P2, the one after gets P1).
var orphaned_player_stack: Array[int] = []

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func set_player_slots(slots: Array[Dictionary]) -> void:
	player_slots = slots
	orphaned_player_stack.clear()

func set_character_id(player_id: int, character_id: int) -> void:
	for slot in player_slots:
		if slot["id"] == player_id:
			slot["character_id"] = character_id
			return

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	for slot in player_slots:
		if slot["device"] == device:
			slot["device"] = Consts.DEVICE_NONE
			if not orphaned_player_stack.has(slot["id"]):
				orphaned_player_stack.append(slot["id"])
			player_disconnected.emit(slot["id"])
			return

# Any controller press claims the most recently orphaned player's slot,
# taking effect from the next round. Ignored while that controller is
# already bound to a live slot, so it never steals input from an active player.
func _input(event: InputEvent) -> void:
	if orphaned_player_stack.is_empty():
		return
	var device = _reconnect_device_of(event)
	if device == null:
		return
	for slot in player_slots:
		if slot["device"] == device:
			return
	var player_id: int = orphaned_player_stack.pop_back()
	for slot in player_slots:
		if slot["id"] == player_id:
			slot["device"] = device
			player_reconnected.emit(player_id, device)
			return

func _reconnect_device_of(event: InputEvent):
	if Pad.is_confirm_button(event):
		return event.device
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		return -1
	return null

func start_round(player_ids: Array[int]) -> void:
	round_number += 1
	round_over = false
	alive_players = player_ids.duplicate()
	for id in player_ids:
		if not scores.has(id):
			scores[id] = 0

# Two players can die in the same blast (e.g. a Pyro's circle explosion
# catching both survivors at once) — both deaths land in the same frame via
# separate Explosion body_entered signals. Deferring the win check to idle
# time lets all of that frame's deaths land first, so a full wipeout reads as
# a draw instead of the first-processed corpse being declared the winner —
# and round_over then makes sure round_ended only ever fires once per round.
func player_died(id: int) -> void:
	if not alive_players.has(id):
		return
	alive_players.erase(id)
	if not round_over:
		_check_round_end.call_deferred()

func _check_round_end() -> void:
	if round_over or alive_players.size() > 1:
		return
	round_over = true
	if alive_players.size() == 1:
		var winner: int = alive_players[0]
		scores[winner] += 1
		round_ended.emit(winner)
	else:
		round_ended.emit(-1)

func is_match_over() -> bool:
	return round_number >= rounds_per_match

func get_match_winner() -> int:
	var best_id := -1
	var best_score := -1
	for id in scores.keys():
		if scores[id] > best_score:
			best_score = scores[id]
			best_id = id
	return best_id

func reset_match() -> void:
	round_number = 0
	scores.clear()
	rounds_per_match = Consts.rounds_per_match()

func leave_to_lobby() -> void:
	player_slots = []
	alive_players = []
	scores = {}
	round_number = 0
	orphaned_player_stack.clear()
