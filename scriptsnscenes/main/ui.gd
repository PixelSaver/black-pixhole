extends Control
class_name UI

@export var fps_label : RichTextLabel
@export var controls_toggle : Button

func _ready():
	controls_toggle.connect("toggled", _on_controls_toggle)

#func _process(_delta: float) -> void:
	#fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("controls"):
		if fps_label.visible:
			_on_controls_toggle(true)
			controls_toggle.hide()
		else:
			_on_controls_toggle(false)
			controls_toggle.show()

func _on_controls_toggle(toggled_on:bool):
	if toggled_on:
		Global.runtime_inspector.hide()
		fps_label.hide()
	else:
		Global.runtime_inspector.show()
		fps_label.show()
