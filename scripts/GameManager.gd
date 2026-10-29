extends Node
## Autoloaded as `GameManager`. Tracks round/match state and scores across scene reloads.

signal round_ended(winner_id: int)
## A pad dropped out mid-match and a bot has taken the slot over.
signal player_disconnected(player_id: int)
## A person has taken a slot over from a bot (see LateJoin), and now drives it.
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

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func set_player_slots(slots: Array[Dictionary]) -> void:
	player_slots = slots

func set_character_id(player_id: int, character_id: int) -> void:
	for slot in player_slots:
		if slot["id"] == player_id:
			slot["character_id"] = character_id
			return

## A pad that drops out mid-match does not leave its character standing there: a bot
## plays the slot from that moment on, and the person can take it back by joining again
## (see LateJoin) — on any button, the same way anybody else joins.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	for slot in player_slots:
		if slot["device"] == device:
			Log.warn("MATCH", "pad %d dropped out mid-match: %s is a bot now" % [device, Log.who(slot["id"], slot["character_id"], device)])
			slot["device"] = Consts.DEVICE_BOT
			player_disconnected.emit(slot["id"])
			return

## Whether this input device is already driving a slot in the current match.
func device_in_match(device: int) -> bool:
	for slot in player_slots:
		if slot["device"] == device:
			return true
	return false

## Whether any slot is driven by a person rather than a bot.
func has_human() -> bool:
	for slot in player_slots:
		if slot["device"] != Consts.DEVICE_BOT:
			return true
	return false

## A player who joins after the round has started (see LateJoin): they are alive from
## now on and on the scoreboard from nothing. Refused once the round is over, since
## there is no round left for them to be in.
func join_round(id: int) -> bool:
	if round_over:
		return false
	if not scores.has(id):
		scores[id] = 0
	if not alive_players.has(id):
		alive_players.append(id)
	Log.info("MATCH", "p%d joined mid-round" % id)
	return true

func start_round(player_ids: Array[int]) -> void:
	round_number += 1
	Log.info("ROUND", "round %d/%d starts with players %s" % [round_number, rounds_per_match, player_ids])
	round_over = false
	alive_players = player_ids.duplicate()
	for id in player_ids:
		if not scores.has(id):
			scores[id] = 0

# Two players can die in the same blast (e.g. a Pyro's star explosion
# catching both survivors at once) — both deaths land in the same frame via
# separate Explosion body_entered signals. Deferring the win check to idle
# time lets all of that frame's deaths land first, so a full wipeout reads as
# a draw instead of the first-processed corpse being declared the winner —
# and round_over then makes sure round_ended only ever fires once per round.
func player_died(id: int) -> void:
	if not alive_players.has(id):
		return
	alive_players.erase(id)
	Log.info("MATCH", "p%d out; alive now %s%s" % [id, alive_players, " (round already over)" if round_over else ""])
	if not round_over:
		_check_round_end.call_deferred()

func _check_round_end() -> void:
	if round_over or alive_players.size() > 1:
		return
	round_over = true
	if alive_players.size() == 1:
		var winner: int = alive_players[0]
		scores[winner] += 1
		Log.info("ROUND", "round %d/%d ended: p%d wins; scores %s" % [round_number, rounds_per_match, winner, scores])
		round_ended.emit(winner)
	else:
		Log.info("ROUND", "round %d/%d ended: draw; scores %s" % [round_number, rounds_per_match, scores])
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
	Log.info("MATCH", "new match: %d rounds" % Consts.rounds_per_match())
	round_number = 0
	scores.clear()
	rounds_per_match = Consts.rounds_per_match()

func leave_to_lobby() -> void:
	Log.info("MATCH", "back to the lobby")
	player_slots = []
	alive_players = []
	scores = {}
	round_number = 0
