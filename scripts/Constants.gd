extends Node
## Autoloaded as `Consts`. Shared grid/gameplay constants and current match settings.

const CELL_SIZE := 64
const MAX_PLAYERS := 4
const DEVICE_NONE := -2 # sentinel: slot's controller disconnected, nobody bound yet
const DEVICE_BOT := -3 # sentinel: slot is AI-controlled, no physical device

const MAP_SIZES := [
	{"name": "Крошечная", "width": 9, "height": 7},
	{"name": "Маленькая", "width": 11, "height": 9},
	{"name": "Средняя", "width": 13, "height": 11},
	{"name": "Большая", "width": 17, "height": 13},
	{"name": "Огромная", "width": 21, "height": 17},
]
const DEFAULT_MAP_SIZE_INDEX := 2

var map_size_index: int = DEFAULT_MAP_SIZE_INDEX
var GRID_WIDTH: int = MAP_SIZES[DEFAULT_MAP_SIZE_INDEX]["width"]
var GRID_HEIGHT: int = MAP_SIZES[DEFAULT_MAP_SIZE_INDEX]["height"]

func set_map_size(index: int) -> void:
	map_size_index = clampi(index, 0, MAP_SIZES.size() - 1)
	GRID_WIDTH = MAP_SIZES[map_size_index]["width"]
	GRID_HEIGHT = MAP_SIZES[map_size_index]["height"]

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
const CHARACTER_NAMES := ["Сапёр", "Бегун", "Инженер", "Пиро", "Хокеист"]

# Short ability/passive blurb shown on character select. Index matches
# CHARACTER_NAMES / Player.CharacterId order.
const CHARACTER_ABILITY_DESC := [
	"Разбирается в бомбах",
	"Двойное нажатие в сторону ящика или бомбы - перепрыгивает через неё",
	"E: Поставить стену, через которую проходит только сам",
	"Бомбы взрываются кругом и немного пробивают ящики",
	"Толкает бомбы движением — свои и чужие",
]
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
