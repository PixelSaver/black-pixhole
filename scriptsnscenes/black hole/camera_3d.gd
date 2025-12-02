extends Camera3D

const SENS = 0.0005

var speed = Vector3.ZERO
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.use_accumulated_input = false

func _process(delta):
	var dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	dir = dir.rotated(-rotation.y)
	var dir3 = Vector3(dir.x, float(Input.is_action_pressed("fly_up")) - float(Input.is_action_pressed("fly_down")), dir.y)
	speed = lerp(speed, dir3, 0.05)
	position += speed * delta * 1.65
	look_at(Vector3(0, 0, 0))
