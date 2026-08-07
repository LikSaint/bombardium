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

var map_size_index: int = DEFAULT_MAP_SIZE_INDEX
var GRID_WIDTH: int = MAP_SIZES[DEFAULT_MAP_SIZE_INDEX]["width"]
var GRID_HEIGHT: int = MAP_SIZES[DEFAULT_MAP_SIZE_INDEX]["height"]

func set_map_size(index: int) -> void:
	map_size_index = clampi(index, 0, MAP_SIZES.size() - 1)
	GRID_WIDTH = MAP_SIZES[map_size_index]["width"]
	GRID_HEIGHT = MAP_SIZES[map_size_index]["height"]

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

const SUDDEN_DEATH_OPTIONS := [60, 180, 300, 480, 720, 1200, 0] # last 0 means "off"
const SUDDEN_DEATH_LABELS := ["1", "3", "5", "8", "12", "20", "OFF"]
const DEFAULT_SUDDEN_DEATH_INDEX := 2 # 300 seconds (5 minutes)
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
const CHARACTER_COUNT := 5

const CHARACTER_NAME_KEYS := [
	"CHAR_NAME_BOMB_MASTER",
	"CHAR_NAME_SCOUT",
	"CHAR_NAME_ENGINEER",
	"CHAR_NAME_PYRO",
	"CHAR_NAME_BOMB_KICKER",
]

func character_name(character_id: int) -> String:
	return Loc.t(CHARACTER_NAME_KEYS[character_id])

# Player.CharacterId.ENGINEER — the only ability blurb that names a button.
const ENGINEER_ID := 2

# Short ability/passive blurb shown on character select. Index matches
# CHARACTER_NAME_KEYS / Player.CharacterId order.
const CHARACTER_ABILITY_DESC_KEYS := [
	"CHAR_DESC_BOMB_MASTER",
	"CHAR_DESC_SCOUT",
	"CHAR_DESC_ENGINEER",
	"CHAR_DESC_PYRO",
	"CHAR_DESC_BOMB_KICKER",
]

## `device_id` selects which button label gets substituted into the
## Engineer's blurb (keyboard letter vs. that player's actual gamepad glyph);
## every other character's blurb ignores it.
func character_ability_desc(character_id: int, device_id: int = -1) -> String:
	var text := Loc.t(CHARACTER_ABILITY_DESC_KEYS[character_id])
	if character_id == ENGINEER_ID:
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
]

# Get starting stats for a character (before any upgrades)
func get_character_stats(character_id: int) -> Dictionary:
	var stats = {"bombs": 1, "radius": 1, "speed": 0, "shield": 0}
	match character_id:
		0:  # Sapper
			stats["bombs"] = 2
			stats["radius"] = 2
			stats["shield"] = 1
		1:  # Scout
			stats["speed"] = 1
		2:  # Engineer
			pass
		3:  # Pyro
			stats["shield"] = 1
		4:  # Hockey player
			stats["speed"] = 1
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
