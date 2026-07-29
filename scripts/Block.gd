extends Node2D
## Destructible soft block. Purely visual/logical — Arena tracks grid state.

func destroy() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ZERO, 0.15)
	tw.tween_callback(queue_free)
