extends Control
class_name UI

@export var fps_label : RichTextLabel
@export var controls_toggle : Button

func _ready():
	controls_toggle.connect("toggled", _on_controls_toggle)

#func _process(_delta: float) -> void:
	#fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

func _on_controls_toggle(toggled_on:bool):
	if toggled_on:
		Global.runtime_inspector.hide()
		fps_label.hide()
	else:
		Global.runtime_inspector.show()
		fps_label.show()
