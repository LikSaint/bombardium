extends Node
## Autoloaded as `Sfx`. Playback for the game's short sound effects, with a
## single master volume (0..1) persisted to user://settings.cfg — the same
## file Loc uses for language, under a different key, so both survive a
## save from either side. A small round-robin pool of AudioStreamPlayer
## nodes lets several sounds overlap (e.g. two bombs exploding at once)
## without cutting each other off. Music lives in its own `Music` autoload
## with its own volume/key so the two can be mixed independently.

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := 0.7
const POOL_SIZE := 8
const VOLUME_STEP := 0.1

const SOUNDS := {
	"bomb_place": preload("res://assets/sfx/bomb_place.wav"),
	"bomb_explode": preload("res://assets/sfx/bomb_explode.wav"),
	"player_death": preload("res://assets/sfx/player_death.wav"),
	"shield_block": preload("res://assets/sfx/shield_block.wav"),
	"powerup_pickup": preload("res://assets/sfx/powerup_pickup.wav"),
	"block_destroy": preload("res://assets/sfx/block_destroy.wav"),
	"wall_place": preload("res://assets/sfx/wall_place.wav"),
	"wall_destroy": preload("res://assets/sfx/wall_destroy.wav"),
	"bomb_kick": preload("res://assets/sfx/bomb_kick.wav"),
	"jump": preload("res://assets/sfx/jump.wav"),
	"footstep": preload("res://assets/sfx/footstep.wav"),
	"round_win": preload("res://assets/sfx/round_win.wav"),
	"round_draw": preload("res://assets/sfx/round_draw.wav"),
	"match_win": preload("res://assets/sfx/match_win.wav"),
	"countdown_tick": preload("res://assets/sfx/countdown_tick.wav"),
	"menu": preload("res://assets/sfx/menu.wav"),
}

var volume: float = DEFAULT_VOLUME

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_load_volume()

## Plays `name` (a key of SOUNDS) once, round-robin across the player pool so
## overlapping sounds don't cut each other off. `pitch` scales playback rate
## (>1 = higher/faster); `jitter` adds a small random spread on top so
## repeated plays of the same sound (footsteps, menu moves) don't sound
## identical every time.
func play(name: String, pitch: float = 1.0, jitter: float = 0.05) -> void:
	if volume <= 0.0 or not SOUNDS.has(name):
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = SOUNDS[name]
	p.volume_db = linear_to_db(volume)
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	p.play()

## Every menu/lobby interaction (move, confirm, back, join, ready) uses this
## one soft blip, deliberately unvaried: distinct per-action sounds made
## navigating a menu feel noisy, and the on-screen selection already says what
## happened. Fixed pitch and no jitter so repeats are identical.
func play_menu() -> void:
	play("menu", 1.0, 0.0)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_save_volume()

func adjust_volume(delta_steps: int) -> void:
	set_volume(volume + VOLUME_STEP * delta_steps)

func volume_percent() -> int:
	return int(round(volume * 100.0))

func _load_volume() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampf(cfg.get_value("settings", "sfx_volume", DEFAULT_VOLUME), 0.0, 1.0)
	else:
		volume = DEFAULT_VOLUME

func _save_volume() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # preserve sibling keys (e.g. Loc's language) already in the file
	cfg.set_value("settings", "sfx_volume", volume)
	cfg.save(SETTINGS_PATH)
