extends Node2D
## Short-lived blast segment. Damage falloff from center of cell: closer = more likely to hit.

const CELL_HALF_SIZE := 32.0  # Consts.CELL_SIZE / 2
const MAX_DAMAGE_DIST := CELL_HALF_SIZE  # Full cell distance = 0% damage

var hit_players := {}

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	queue_free()

func _physics_process(_delta: float) -> void:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if not player.alive or hit_players.has(player):
			continue
		var dist = position.distance_to(player.position)
		if dist >= MAX_DAMAGE_DIST:
			continue
		# Damage chance: 100% at center, falls off linearly to edges
		var damage_chance = 1.0 - (dist / MAX_DAMAGE_DIST)
		if randf() < damage_chance:
			hit_players[player] = true
			player.die()
