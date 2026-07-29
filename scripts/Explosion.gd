extends Area2D
## Short-lived blast segment. Kills any player body overlapping it.

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(0.3).timeout
	queue_free()

func _on_body_entered(body: Node) -> void:
	if body.has_method("die"):
		body.die()
