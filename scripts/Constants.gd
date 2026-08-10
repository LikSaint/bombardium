extends Node
## Autoloaded as `Consts`. Shared grid/gameplay constants and current match settings.

const CELL_SIZE := 64
const MAX_PLAYERS := 4
const DEVICE_NONE := -2 # sentinel: slot's controller disconnected, nobody bound yet
const DEVICE_BOT := -3 # sentinel: slot is AI-controlled, no physical device

const MAP_SIZES := [
	{"name_key": "MAP_SIZE_TINY", "width": 9, "height": 7},
	{"name_key": "MAP_SIZE_SMALL", "width": 11, "height": 9},
	{"name_key": "MAP_SIZE_MEDIUM", "width": 13, "height": 11},
	{"name_key": "MAP_SIZE_LARGE", "width": 17, "height": 13},
	{"name_key": "MAP_SIZE_HUGE", "width": 21, "height": 17},
]
const DEFAULT_MAP_SIZE_INDEX := 2

func map_size_name(index: int) -> String:
	return Loc.t(MAP_SIZES[index]["name_key"])

# --- Map layouts -----------------------------------------------------------
#
# A layout is the arena's *terrain* — the chasms and fixed structures carved
# into it — and it composes with the base wall pattern rather than replacing
# it: Classic on top of the checkerboard is exactly the map this game has
# always had, and every layout still honours the Random walls setting.
#
# Layouts are gated on grid size rather than being offered everywhere and
# quietly degrading. A chasm splitting a 9x7 arena leaves two rooms of a dozen
# cells each, which is not a smaller version of the same map — it's a different
# and much worse one. Anything that doesn't fit falls back to Classic (see
# resolve_map_layout).
const LAYOUT_CLASSIC := "classic"
const LAYOUT_BRIDGES := "bridges"
const LAYOUT_CRATER := "crater"
const LAYOUT_QUARTERS := "quarters"
const LAYOUT_PLAZA := "plaza"

## Index 0 is the "roll a fresh one every round" entry rather than a map, and
## is the default: a match should walk through the set instead of settling on
## whichever one happened to be selected in the lobby.
const MAP_LAYOUTS := [
	{"id": "", "name_key": "MAP_LAYOUT_RANDOM", "min_width": 0, "min_height": 0},
	{"id": LAYOUT_CLASSIC, "name_key": "MAP_LAYOUT_CLASSIC", "min_width": 0, "min_height": 0},
	{"id": LAYOUT_BRIDGES, "name_key": "MAP_LAYOUT_BRIDGES", "min_width": 11, "min_height": 9},
	{"id": LAYOUT_CRATER, "name_key": "MAP_LAYOUT_CRATER", "min_width": 13, "min_height": 11},
	{"id": LAYOUT_QUARTERS, "name_key": "MAP_LAYOUT_QUARTERS", "min_width": 11, "min_height": 9},
	{"id": LAYOUT_PLAZA, "name_key": "MAP_LAYOUT_PLAZA", "min_width": 13, "min_height": 9},
]
const MAP_LAYOUT_RANDOM_INDEX := 0
const DEFAULT_MAP_LAYOUT_INDEX := MAP_LAYOUT_RANDOM_INDEX
var map_layout_index: int = DEFAULT_MAP_LAYOUT_INDEX

func set_map_layout_index(index: int) -> void:
	map_layout_index = clampi(index, 0, MAP_LAYOUTS.size() - 1)

func map_layout_name(index: int) -> String:
	return Loc.t(MAP_LAYOUTS[index]["name_key"])

func layout_name_for_id(id: String) -> String:
	for entry in MAP_LAYOUTS:
		if entry["id"] == id:
			return Loc.t(entry["name_key"])
	return Loc.t(MAP_LAYOUTS[1]["name_key"])

func _layout_fits(entry: Dictionary) -> bool:
	return GRID_WIDTH >= entry["min_width"] and GRID_HEIGHT >= entry["min_height"]

## Layouts still due to be played this pass, drawn from the end. See
## _refill_layout_bag.
var _layout_bag: Array[String] = []
## Whatever generate() last resolved, so the bag can avoid opening on it.
var _last_layout_id: String = ""

## The layout the round about to start actually gets. Called once per round (by
## Arena.generate), which is what makes the Random entry re-roll per round
## rather than per match.
func resolve_map_layout() -> String:
	if map_layout_index != MAP_LAYOUT_RANDOM_INDEX:
		var chosen: Dictionary = MAP_LAYOUTS[map_layout_index]
		_last_layout_id = chosen["id"] if _layout_fits(chosen) else LAYOUT_CLASSIC
		return _last_layout_id
	if _layout_bag.is_empty():
		_refill_layout_bag()
	_last_layout_id = _layout_bag.pop_back()
	return _last_layout_id

## Random deals the whole set out before repeating any of it, rather than
## rolling independently every round: an honest roll gives the same layout twice
## in a row about one round in five, and a five-round match that plays Crater
## three times reads as the setting not working. Refilled once the bag runs dry.
##
## A fresh bag never opens on the layout that just played, so the seam between
## two bags can't repeat one either. That's done by swapping the offending first
## draw with another entry rather than by reshuffling until it lands well — a
## reshuffle loop isn't guaranteed to end.
func _refill_layout_bag() -> void:
	_layout_bag.clear()
	for i in range(1, MAP_LAYOUTS.size()):
		if _layout_fits(MAP_LAYOUTS[i]):
			_layout_bag.append(MAP_LAYOUTS[i]["id"])
	_layout_bag.shuffle()
	if _layout_bag.size() > 1 and _layout_bag[-1] == _last_layout_id:
		var other := randi() % (_layout_bag.size() - 1)
		_layout_bag[-1] = _layout_bag[other]
		_layout_bag[other] = _last_layout_id

var map_size_index: int = DEFAULT_MAP_SIZE_INDEX
var GRID_WIDTH: int = MAP_SIZES[DEFAULT_MAP_SIZE_INDEX]["width"]
var GRID_HEIGHT: int = MAP_SIZES[DEFAULT_MAP_SIZE_INDEX]["height"]

func set_map_size(index: int) -> void:
	map_size_index = clampi(index, 0, MAP_SIZES.size() - 1)
	GRID_WIDTH = MAP_SIZES[map_size_index]["width"]
	GRID_HEIGHT = MAP_SIZES[map_size_index]["height"]
	# Which layouts fit is a function of the grid, so a half-dealt bag from the
	# old size can hold layouts this one can't take (and miss ones it can).
	_layout_bag.clear()

## The arena's footprint in world pixels. The single place that turns the grid
## into a size — everything that has to frame the arena on screen (Main's
## camera fit) works from this rather than re-multiplying the grid itself.
func arena_pixel_size() -> Vector2:
	return Vector2(GRID_WIDTH, GRID_HEIGHT) * CELL_SIZE

# --- Pre-match settings, configured on the Lobby's Settings screen ---------

const PLAYER_SLOTS_MIN := 1
const PLAYER_SLOTS_MAX := MAX_PLAYERS
var configured_player_slots: int = MAX_PLAYERS

const BOTS_MIN := 0
var configured_bots: int = 0

func set_configured_player_slots(value: int) -> void:
	configured_player_slots = clampi(value, PLAYER_SLOTS_MIN, PLAYER_SLOTS_MAX)
	configured_bots = clampi(configured_bots, BOTS_MIN, configured_player_slots)

# Bots can never exceed the player-slot count: adding a bot fills one of the
# match's slots exactly like a joining human would.
func set_configured_bots(value: int) -> void:
	configured_bots = clampi(value, BOTS_MIN, configured_player_slots)

var random_indestructible_walls: bool = false

func set_random_indestructible_walls(value: bool) -> void:
	random_indestructible_walls = value

const POWERUP_CHANCE_MIN := 0
const POWERUP_CHANCE_MAX := 100
const POWERUP_CHANCE_STEP := 5
const DEFAULT_POWERUP_CHANCE_PERCENT := 20
var powerup_chance_percent: int = DEFAULT_POWERUP_CHANCE_PERCENT

func set_powerup_chance_percent(value: int) -> void:
	powerup_chance_percent = clampi(value, POWERUP_CHANCE_MIN, POWERUP_CHANCE_MAX)

const ROUNDS_OPTIONS := [3, 5, 7, 9]
const DEFAULT_ROUNDS_INDEX := 1 # ROUNDS_OPTIONS[1] == 5, matches the old fixed value
var rounds_index: int = DEFAULT_ROUNDS_INDEX

func rounds_per_match() -> int:
	return ROUNDS_OPTIONS[rounds_index]

func set_rounds_index(index: int) -> void:
	rounds_index = clampi(index, 0, ROUNDS_OPTIONS.size() - 1)

const SUDDEN_DEATH_OPTIONS := [60, 120, 180, 300, 480, 720, 1200, 0] # last 0 means "off"
const SUDDEN_DEATH_LABELS := ["1", "2", "3", "5", "8", "12", "20", "OFF"]
const DEFAULT_SUDDEN_DEATH_INDEX := 1 # 120 seconds (2 minutes)
var sudden_death_index: int = DEFAULT_SUDDEN_DEATH_INDEX

func sudden_death_timer() -> float:
	return float(SUDDEN_DEATH_OPTIONS[sudden_death_index])

func is_sudden_death_enabled() -> bool:
	return SUDDEN_DEATH_OPTIONS[sudden_death_index] > 0

func set_sudden_death_index(index: int) -> void:
	sudden_death_index = clampi(index, 0, SUDDEN_DEATH_OPTIONS.size() - 1)

const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)
const DIRECTIONS: Array[Vector2i] = [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]

## Nothing in the game *moves* diagonally — these exist for the Pyro's blast,
## which throws four short arms out of the corners on top of the usual four
## (see Arena._star_blast_cells).
const DIAGONALS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

const PLAYER_COLORS := [
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.3, 0.3),
	Color(0.3, 1.0, 0.4),
	Color(1.0, 0.85, 0.2),
]

# Index must match Player.CharacterId enum order. Each character is a proper
# 4-directional PixelLab sprite (single flat image per direction, not a
# tintable-layer setup) — team color is applied as a soft whole-sprite
# modulate blend in CharacterPortrait.gd rather than a clothes-only tint.
const CHARACTER_COUNT := 8

const CHARACTER_NAME_KEYS := [
	"CHAR_NAME_BOMB_MASTER",
	"CHAR_NAME_SCOUT",
	"CHAR_NAME_ENGINEER",
	"CHAR_NAME_PYRO",
	"CHAR_NAME_BOMB_KICKER",
	"CHAR_NAME_MAGNET",
	"CHAR_NAME_MINER",
	"CHAR_NAME_GRENADIER",
]

func character_name(character_id: int) -> String:
	return Loc.t(CHARACTER_NAME_KEYS[character_id])

# Short ability/passive blurb shown on character select. Index matches
# CHARACTER_NAME_KEYS / Player.CharacterId order.
const CHARACTER_ABILITY_DESC_KEYS := [
	"CHAR_DESC_BOMB_MASTER",
	"CHAR_DESC_SCOUT",
	"CHAR_DESC_ENGINEER",
	"CHAR_DESC_PYRO",
	"CHAR_DESC_BOMB_KICKER",
	"CHAR_DESC_MAGNET",
	"CHAR_DESC_MINER",
	"CHAR_DESC_GRENADIER",
]

## A blurb for a character with a button-press ability carries a single `%s`;
## `device_id` selects what gets substituted for it (keyboard letter vs. that
## player's actual gamepad glyph). Blurbs without one ignore device_id, so
## which characters have an ability lives in the strings rather than in a list
## of ids here that has to be kept in step with them.
func character_ability_desc(character_id: int, device_id: int = -1) -> String:
	var text := Loc.t(CHARACTER_ABILITY_DESC_KEYS[character_id])
	if text.contains("%s"):
		var button := Hints.label(device_id, Hints.Action.ABILITY)
		text = text % [button if button != "" else "—"]
	return text
const CHARACTER_SPRITES := [
	{
		"south": preload("res://assets/characters/bomb_master_south.png"),
		"north": preload("res://assets/characters/bomb_master_north.png"),
		"east": preload("res://assets/characters/bomb_master_east.png"),
		"west": preload("res://assets/characters/bomb_master_west.png"),
	},
	{
		"south": preload("res://assets/characters/scout_south.png"),
		"north": preload("res://assets/characters/scout_north.png"),
		"east": preload("res://assets/characters/scout_east.png"),
		"west": preload("res://assets/characters/scout_west.png"),
	},
	{
		"south": preload("res://assets/characters/engineer_south.png"),
		"north": preload("res://assets/characters/engineer_north.png"),
		"east": preload("res://assets/characters/engineer_east.png"),
		"west": preload("res://assets/characters/engineer_west.png"),
	},
	{
		"south": preload("res://assets/characters/pyro_south.png"),
		"north": preload("res://assets/characters/pyro_north.png"),
		"east": preload("res://assets/characters/pyro_east.png"),
		"west": preload("res://assets/characters/pyro_west.png"),
	},
	{
		"south": preload("res://assets/characters/bomb_kicker_south.png"),
		"north": preload("res://assets/characters/bomb_kicker_north.png"),
		"east": preload("res://assets/characters/bomb_kicker_east.png"),
		"west": preload("res://assets/characters/bomb_kicker_west.png"),
	},
	# Re-skin, not a generated character: these are the Engineer's frames with the
	# hard hat restyled into a horseshoe magnet (blue/red dome, pale poles). The
	# body, and the wrench in its hand, are still the Engineer's — the Magnet is
	# waiting on a PixelLab sheet of its own, which needs 5 generations (1 for the
	# 4 directions + 1 per direction of walk) against a trial that has 3 left.
	{
		"south": preload("res://assets/characters/magnet_south.png"),
		"north": preload("res://assets/characters/magnet_north.png"),
		"east": preload("res://assets/characters/magnet_east.png"),
		"west": preload("res://assets/characters/magnet_west.png"),
	},
	# Re-skin: the Parkour Runner's frames with the near-white kit recoloured to
	# dark khaki. Same standing offer as the Magnet — a sheet of the Miner's own
	# costs 5 PixelLab generations against a trial with 3 left.
	{
		"south": preload("res://assets/characters/miner_south.png"),
		"north": preload("res://assets/characters/miner_north.png"),
		"east": preload("res://assets/characters/miner_east.png"),
		"west": preload("res://assets/characters/miner_west.png"),
	},
	# Re-skin, and the one that carries its own kit: the Miner's frames in olive
	# drab with a plain gunmetal helmet, plus a shouldered launcher drawn on
	# every frame. The weapon is deliberately oversized — it is the only thing
	# separating two soldiers built on the same body at lobby size, and it is
	# also the whole character. Built by a Pillow script rather than PixelLab,
	# for the same reason as the entries above.
	{
		"south": preload("res://assets/characters/grenadier_south.png"),
		"north": preload("res://assets/characters/grenadier_north.png"),
		"east": preload("res://assets/characters/grenadier_east.png"),
		"west": preload("res://assets/characters/grenadier_west.png"),
	},
]

# Same character/direction keys as CHARACTER_SPRITES, but each entry is an
# Array of 6 walk-cycle frame textures (PixelLab "walk" template animation).
# CHARACTER_SPRITES itself is used as the idle/standing frame when not moving.
const CHARACTER_WALK_FRAMES := [
	{
		"south": [preload("res://assets/characters/walk/bomb_master_south_0.png"), preload("res://assets/characters/walk/bomb_master_south_1.png"), preload("res://assets/characters/walk/bomb_master_south_2.png"), preload("res://assets/characters/walk/bomb_master_south_3.png"), preload("res://assets/characters/walk/bomb_master_south_4.png"), preload("res://assets/characters/walk/bomb_master_south_5.png")],
		"north": [preload("res://assets/characters/walk/bomb_master_north_0.png"), preload("res://assets/characters/walk/bomb_master_north_1.png"), preload("res://assets/characters/walk/bomb_master_north_2.png"), preload("res://assets/characters/walk/bomb_master_north_3.png"), preload("res://assets/characters/walk/bomb_master_north_4.png"), preload("res://assets/characters/walk/bomb_master_north_5.png")],
		"east": [preload("res://assets/characters/walk/bomb_master_east_0.png"), preload("res://assets/characters/walk/bomb_master_east_1.png"), preload("res://assets/characters/walk/bomb_master_east_2.png"), preload("res://assets/characters/walk/bomb_master_east_3.png"), preload("res://assets/characters/walk/bomb_master_east_4.png"), preload("res://assets/characters/walk/bomb_master_east_5.png")],
		"west": [preload("res://assets/characters/walk/bomb_master_west_0.png"), preload("res://assets/characters/walk/bomb_master_west_1.png"), preload("res://assets/characters/walk/bomb_master_west_2.png"), preload("res://assets/characters/walk/bomb_master_west_3.png"), preload("res://assets/characters/walk/bomb_master_west_4.png"), preload("res://assets/characters/walk/bomb_master_west_5.png")],
	},
	{
		"south": [preload("res://assets/characters/walk/scout_south_0.png"), preload("res://assets/characters/walk/scout_south_1.png"), preload("res://assets/characters/walk/scout_south_2.png"), preload("res://assets/characters/walk/scout_south_3.png"), preload("res://assets/characters/walk/scout_south_4.png"), preload("res://assets/characters/walk/scout_south_5.png")],
		"north": [preload("res://assets/characters/walk/scout_north_0.png"), preload("res://assets/characters/walk/scout_north_1.png"), preload("res://assets/characters/walk/scout_north_2.png"), preload("res://assets/characters/walk/scout_north_3.png"), preload("res://assets/characters/walk/scout_north_4.png"), preload("res://assets/characters/walk/scout_north_5.png")],
		"east": [preload("res://assets/characters/walk/scout_east_0.png"), preload("res://assets/characters/walk/scout_east_1.png"), preload("res://assets/characters/walk/scout_east_2.png"), preload("res://assets/characters/walk/scout_east_3.png"), preload("res://assets/characters/walk/scout_east_4.png"), preload("res://assets/characters/walk/scout_east_5.png")],
		"west": [preload("res://assets/characters/walk/scout_west_0.png"), preload("res://assets/characters/walk/scout_west_1.png"), preload("res://assets/characters/walk/scout_west_2.png"), preload("res://assets/characters/walk/scout_west_3.png"), preload("res://assets/characters/walk/scout_west_4.png"), preload("res://assets/characters/walk/scout_west_5.png")],
	},
	{
		"south": [preload("res://assets/characters/walk/engineer_south_0.png"), preload("res://assets/characters/walk/engineer_south_1.png"), preload("res://assets/characters/walk/engineer_south_2.png"), preload("res://assets/characters/walk/engineer_south_3.png"), preload("res://assets/characters/walk/engineer_south_4.png"), preload("res://assets/characters/walk/engineer_south_5.png")],
		"north": [preload("res://assets/characters/walk/engineer_north_0.png"), preload("res://assets/characters/walk/engineer_north_1.png"), preload("res://assets/characters/walk/engineer_north_2.png"), preload("res://assets/characters/walk/engineer_north_3.png"), preload("res://assets/characters/walk/engineer_north_4.png"), preload("res://assets/characters/walk/engineer_north_5.png")],
		"east": [preload("res://assets/characters/walk/engineer_east_0.png"), preload("res://assets/characters/walk/engineer_east_1.png"), preload("res://assets/characters/walk/engineer_east_2.png"), preload("res://assets/characters/walk/engineer_east_3.png"), preload("res://assets/characters/walk/engineer_east_4.png"), preload("res://assets/characters/walk/engineer_east_5.png")],
		"west": [preload("res://assets/characters/walk/engineer_west_0.png"), preload("res://assets/characters/walk/engineer_west_1.png"), preload("res://assets/characters/walk/engineer_west_2.png"), preload("res://assets/characters/walk/engineer_west_3.png"), preload("res://assets/characters/walk/engineer_west_4.png"), preload("res://assets/characters/walk/engineer_west_5.png")],
	},
	{
		"south": [preload("res://assets/characters/walk/pyro_south_0.png"), preload("res://assets/characters/walk/pyro_south_1.png"), preload("res://assets/characters/walk/pyro_south_2.png"), preload("res://assets/characters/walk/pyro_south_3.png"), preload("res://assets/characters/walk/pyro_south_4.png"), preload("res://assets/characters/walk/pyro_south_5.png")],
		"north": [preload("res://assets/characters/walk/pyro_north_0.png"), preload("res://assets/characters/walk/pyro_north_1.png"), preload("res://assets/characters/walk/pyro_north_2.png"), preload("res://assets/characters/walk/pyro_north_3.png"), preload("res://assets/characters/walk/pyro_north_4.png"), preload("res://assets/characters/walk/pyro_north_5.png")],
		"east": [preload("res://assets/characters/walk/pyro_east_0.png"), preload("res://assets/characters/walk/pyro_east_1.png"), preload("res://assets/characters/walk/pyro_east_2.png"), preload("res://assets/characters/walk/pyro_east_3.png"), preload("res://assets/characters/walk/pyro_east_4.png"), preload("res://assets/characters/walk/pyro_east_5.png")],
		"west": [preload("res://assets/characters/walk/pyro_west_0.png"), preload("res://assets/characters/walk/pyro_west_1.png"), preload("res://assets/characters/walk/pyro_west_2.png"), preload("res://assets/characters/walk/pyro_west_3.png"), preload("res://assets/characters/walk/pyro_west_4.png"), preload("res://assets/characters/walk/pyro_west_5.png")],
	},
	{
		"south": [preload("res://assets/characters/walk/bomb_kicker_south_0.png"), preload("res://assets/characters/walk/bomb_kicker_south_1.png"), preload("res://assets/characters/walk/bomb_kicker_south_2.png"), preload("res://assets/characters/walk/bomb_kicker_south_3.png"), preload("res://assets/characters/walk/bomb_kicker_south_4.png"), preload("res://assets/characters/walk/bomb_kicker_south_5.png")],
		"north": [preload("res://assets/characters/walk/bomb_kicker_north_0.png"), preload("res://assets/characters/walk/bomb_kicker_north_1.png"), preload("res://assets/characters/walk/bomb_kicker_north_2.png"), preload("res://assets/characters/walk/bomb_kicker_north_3.png"), preload("res://assets/characters/walk/bomb_kicker_north_4.png"), preload("res://assets/characters/walk/bomb_kicker_north_5.png")],
		"east": [preload("res://assets/characters/walk/bomb_kicker_east_0.png"), preload("res://assets/characters/walk/bomb_kicker_east_1.png"), preload("res://assets/characters/walk/bomb_kicker_east_2.png"), preload("res://assets/characters/walk/bomb_kicker_east_3.png"), preload("res://assets/characters/walk/bomb_kicker_east_4.png"), preload("res://assets/characters/walk/bomb_kicker_east_5.png")],
		"west": [preload("res://assets/characters/walk/bomb_kicker_west_0.png"), preload("res://assets/characters/walk/bomb_kicker_west_1.png"), preload("res://assets/characters/walk/bomb_kicker_west_2.png"), preload("res://assets/characters/walk/bomb_kicker_west_3.png"), preload("res://assets/characters/walk/bomb_kicker_west_4.png"), preload("res://assets/characters/walk/bomb_kicker_west_5.png")],
	},
	# Re-skin — see the note on the Magnet's entry in CHARACTER_SPRITES.
	{
		"south": [preload("res://assets/characters/walk/magnet_south_0.png"), preload("res://assets/characters/walk/magnet_south_1.png"), preload("res://assets/characters/walk/magnet_south_2.png"), preload("res://assets/characters/walk/magnet_south_3.png"), preload("res://assets/characters/walk/magnet_south_4.png"), preload("res://assets/characters/walk/magnet_south_5.png")],
		"north": [preload("res://assets/characters/walk/magnet_north_0.png"), preload("res://assets/characters/walk/magnet_north_1.png"), preload("res://assets/characters/walk/magnet_north_2.png"), preload("res://assets/characters/walk/magnet_north_3.png"), preload("res://assets/characters/walk/magnet_north_4.png"), preload("res://assets/characters/walk/magnet_north_5.png")],
		"east": [preload("res://assets/characters/walk/magnet_east_0.png"), preload("res://assets/characters/walk/magnet_east_1.png"), preload("res://assets/characters/walk/magnet_east_2.png"), preload("res://assets/characters/walk/magnet_east_3.png"), preload("res://assets/characters/walk/magnet_east_4.png"), preload("res://assets/characters/walk/magnet_east_5.png")],
		"west": [preload("res://assets/characters/walk/magnet_west_0.png"), preload("res://assets/characters/walk/magnet_west_1.png"), preload("res://assets/characters/walk/magnet_west_2.png"), preload("res://assets/characters/walk/magnet_west_3.png"), preload("res://assets/characters/walk/magnet_west_4.png"), preload("res://assets/characters/walk/magnet_west_5.png")],
	},
	# Re-skin — see the note on the Miner's entry in CHARACTER_SPRITES.
	{
		"south": [preload("res://assets/characters/walk/miner_south_0.png"), preload("res://assets/characters/walk/miner_south_1.png"), preload("res://assets/characters/walk/miner_south_2.png"), preload("res://assets/characters/walk/miner_south_3.png"), preload("res://assets/characters/walk/miner_south_4.png"), preload("res://assets/characters/walk/miner_south_5.png")],
		"north": [preload("res://assets/characters/walk/miner_north_0.png"), preload("res://assets/characters/walk/miner_north_1.png"), preload("res://assets/characters/walk/miner_north_2.png"), preload("res://assets/characters/walk/miner_north_3.png"), preload("res://assets/characters/walk/miner_north_4.png"), preload("res://assets/characters/walk/miner_north_5.png")],
		"east": [preload("res://assets/characters/walk/miner_east_0.png"), preload("res://assets/characters/walk/miner_east_1.png"), preload("res://assets/characters/walk/miner_east_2.png"), preload("res://assets/characters/walk/miner_east_3.png"), preload("res://assets/characters/walk/miner_east_4.png"), preload("res://assets/characters/walk/miner_east_5.png")],
		"west": [preload("res://assets/characters/walk/miner_west_0.png"), preload("res://assets/characters/walk/miner_west_1.png"), preload("res://assets/characters/walk/miner_west_2.png"), preload("res://assets/characters/walk/miner_west_3.png"), preload("res://assets/characters/walk/miner_west_4.png"), preload("res://assets/characters/walk/miner_west_5.png")],
	},
	# Re-skin — see the note on the Grenadier's entry in CHARACTER_SPRITES.
	{
		"south": [preload("res://assets/characters/walk/grenadier_south_0.png"), preload("res://assets/characters/walk/grenadier_south_1.png"), preload("res://assets/characters/walk/grenadier_south_2.png"), preload("res://assets/characters/walk/grenadier_south_3.png"), preload("res://assets/characters/walk/grenadier_south_4.png"), preload("res://assets/characters/walk/grenadier_south_5.png")],
		"north": [preload("res://assets/characters/walk/grenadier_north_0.png"), preload("res://assets/characters/walk/grenadier_north_1.png"), preload("res://assets/characters/walk/grenadier_north_2.png"), preload("res://assets/characters/walk/grenadier_north_3.png"), preload("res://assets/characters/walk/grenadier_north_4.png"), preload("res://assets/characters/walk/grenadier_north_5.png")],
		"east": [preload("res://assets/characters/walk/grenadier_east_0.png"), preload("res://assets/characters/walk/grenadier_east_1.png"), preload("res://assets/characters/walk/grenadier_east_2.png"), preload("res://assets/characters/walk/grenadier_east_3.png"), preload("res://assets/characters/walk/grenadier_east_4.png"), preload("res://assets/characters/walk/grenadier_east_5.png")],
		"west": [preload("res://assets/characters/walk/grenadier_west_0.png"), preload("res://assets/characters/walk/grenadier_west_1.png"), preload("res://assets/characters/walk/grenadier_west_2.png"), preload("res://assets/characters/walk/grenadier_west_3.png"), preload("res://assets/characters/walk/grenadier_west_4.png"), preload("res://assets/characters/walk/grenadier_west_5.png")],
	},
]

# Starting stats for a character (before any upgrades), for the lobby's stat
# pips. Must stay in step with Player._apply_character_passives(), which is
# what actually applies them in the arena.
func get_character_stats(character_id: int) -> Dictionary:
	var stats = {"bombs": 1, "radius": 1, "speed": 0, "shield": 0}
	match character_id:
		0:  # Sapper
			stats["bombs"] = 2
			stats["shield"] = 1
		1:  # Runner
			stats["speed"] = 2
			stats["shield"] = 1
		2:  # Engineer
			stats["bombs"] = 2
		3:  # Pyro
			stats["shield"] = 1
		4:  # Hockey player
			stats["speed"] = 1
			stats["shield"] = 1
		5:  # Magnet
			stats["bombs"] = 2
			stats["shield"] = 1
		6:  # Miner
			stats["bombs"] = 2
			stats["shield"] = 1
		7:  # Grenadier
			# One charge and no way to spend it on the floor — the launcher is
			# this character's bombs (Player._can_place_bombs), and bomb pickups
			# buy it reach rather than a second shell.
			stats["shield"] = 1
	return stats

enum PowerupType { BOMB_COUNT, RADIUS, SPEED, SHIELD }

# Index must match PowerupType enum order.
const STAT_ICONS := [
	preload("res://assets/icons/bomb.png"),
	preload("res://assets/icons/radius.png"),
	preload("res://assets/icons/speed.png"),
	preload("res://assets/icons/shield.png"),
]

const BOMB_TEXTURE := preload("res://assets/icons/bomb_round.png")
