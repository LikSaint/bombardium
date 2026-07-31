extends Node2D
## Engineer ability: blocks movement for 1 minute, then reverts. A blast
## that reaches it destroys it early (see Bomb._explode_cross/_explode_circle).

var cell: Vector2i
var arena: Node2D

func _on_timer_timeout() -> void:
	destroy()

func destroy() -> void:
	Sfx.play("wall_destroy")
	arena.remove_temp_wall(cell)
	queue_free()
