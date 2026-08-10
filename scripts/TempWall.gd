extends Node2D
## Engineer ability: blocks movement for 12s, then reverts. A blast that
## reaches it destroys it early (see Bomb._apply_blast).
##
## The old lifetime was a full minute, which was fine only while the Engineer
## could have exactly one wall out: now that the cap scales with their bomb
## count, minute-long walls would let one player quietly re-lay the whole map
## over the course of a round. 12s is long enough to seal an escape route or
## hold a corridor and short enough that the arena is still the arena.

var cell: Vector2i
var arena: Node2D

func _on_timer_timeout() -> void:
	destroy()

func destroy() -> void:
	Sfx.play("wall_destroy")
	arena.remove_temp_wall(cell)
	queue_free()
