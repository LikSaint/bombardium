extends Node
## Start scene for Capture.gd: hands the work to a node that survives the scene
## changes the capture plan makes, then gets out of the way.

func _ready() -> void:
	var keeper := Node.new()
	keeper.name = "Capture"
	keeper.set_script(load("res://tools/steam/Capture.gd"))
	get_tree().root.add_child.call_deferred(keeper)
	queue_free()
