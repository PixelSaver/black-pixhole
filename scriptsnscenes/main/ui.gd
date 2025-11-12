extends Control
class_name UI

@export var fps_label : RichTextLabel

func _process(_delta: float) -> void:
	fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
