extends Node2D
## Short-lived blast segment. Damage falloff from center of cell: closer = more likely to hit.

## Half a cell away from the blast centre = 0% damage.
@onready var max_damage_dist: float = Consts.CELL_SIZE / 2.0

var hit_players := {}
## Whose bomb this blast came from (null for a turret's shell). Read so a character
## that is immune to its own bombs — see Player.is_immune_to_own_blast — can walk
## through the fire it set itself.
var owner_player: Node = null

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	queue_free()

func _physics_process(_delta: float) -> void:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if not player.alive or hit_players.has(player):
			continue
		if player == owner_player and player.is_immune_to_own_blast():
			continue
		var dist = position.distance_to(player.position)
		if dist >= max_damage_dist:
			continue
		# Damage chance: 100% at center, falls off linearly to edges
		var damage_chance = 1.0 - (dist / max_damage_dist)
		if randf() < damage_chance:
			hit_players[player] = true
			player.die()
