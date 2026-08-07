extends Node
## Autoloaded as `Music`. Two looping themes — a calm one for the menus/lobby
## and a bouncier one for matches — with a short crossfade between them, so
## entering or leaving a match doesn't cut the audio off mid-phrase.
##
## Both are mixed to sit well under the sound effects, and volume (0..1) is
## separate from Sfx's, persisted to user://settings.cfg under its own key. At
## volume 0 playback is stopped outright rather than played silently.
##
## Each track has its own AudioStreamPlayer kept alive for the whole session:
## crossfading needs both streams audible at once, and the streams are small
## enough that holding two costs nothing.

enum Track { NONE, MENU, ARENA }

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := 0.3
const VOLUME_STEP := 0.1
const CROSSFADE_SECONDS := 0.8
const SILENT_DB := -60.0

const TRACKS := {
	Track.MENU: preload("res://assets/music/menu_theme.wav"),
	Track.ARENA: preload("res://assets/music/arena_theme.wav"),
}

var volume: float = DEFAULT_VOLUME
var current_track: int = Track.NONE

var _players: Dictionary = {} # Track -> AudioStreamPlayer
var _fades: Dictionary = {} # Track -> Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # music (and its fades) keep running while paused
	for track in TRACKS:
		var p := AudioStreamPlayer.new()
		p.stream = TRACKS[track]
		p.volume_db = SILENT_DB
		add_child(p)
		_players[track] = p
	_load_volume()

## Switches to `track`, crossfading from whatever is playing. Repeat calls with
## the track already playing are ignored, so moving between the main menu and
## the lobby doesn't restart the track from the top.
func play_track(track: int) -> void:
	if track == current_track:
		return
	current_track = track
	_apply(true)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply(false)
	_save_volume()

func adjust_volume(delta_steps: int) -> void:
	set_volume(volume + VOLUME_STEP * delta_steps)

func volume_percent() -> int:
	return int(round(volume * 100.0))

## Speeds the music up (or back down) without changing tracks — sudden death
## nudges this upward as the walls close in. Pitch and tempo move together,
## which is the point: it should read as the round getting more frantic.
func set_pitch(scale: float) -> void:
	for track in _players:
		_players[track].pitch_scale = scale

# `fade` off means snap (used while the player drags the volume, where any
# ramp would just feel laggy); on means crossfade (used when the track changes).
func _apply(fade: bool) -> void:
	for track in _players:
		var p: AudioStreamPlayer = _players[track]
		var wanted: bool = track == current_track and volume > 0.0
		_kill_fade(track)
		if not wanted:
			if fade and p.playing:
				_fade_out(track, p)
			else:
				p.stop()
			continue
		if not p.playing:
			p.volume_db = SILENT_DB if fade else linear_to_db(volume)
			p.play()
		if fade:
			_fades[track] = create_tween()
			_fades[track].tween_property(p, "volume_db", linear_to_db(volume), CROSSFADE_SECONDS)
		else:
			p.volume_db = linear_to_db(volume)

func _fade_out(track: int, p: AudioStreamPlayer) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", SILENT_DB, CROSSFADE_SECONDS)
	tw.tween_callback(p.stop)
	_fades[track] = tw

func _kill_fade(track: int) -> void:
	var tw: Tween = _fades.get(track)
	if tw != null and tw.is_valid():
		tw.kill()
	_fades.erase(track)

func _load_volume() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampf(cfg.get_value("settings", "music_volume", DEFAULT_VOLUME), 0.0, 1.0)
	else:
		volume = DEFAULT_VOLUME

func _save_volume() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # preserve sibling keys (Loc's language, Sfx's volume) already in the file
	cfg.set_value("settings", "music_volume", volume)
	cfg.save(SETTINGS_PATH)
