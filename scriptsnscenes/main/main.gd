extends CanvasLayer
class_name Main

@export var bh_node : Node

func _ready() -> void:
	await get_tree().process_frame
	while not Global.runtime_inspector:
		await get_tree().process_frame
	Global.runtime_inspector.inspect(bh_node)

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
