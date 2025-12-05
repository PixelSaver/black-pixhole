extends CanvasLayer
class_name Main

@export var bh_node : Node

func _ready() -> void:
	Global.runtime_inspector.inspect(bh_node)
