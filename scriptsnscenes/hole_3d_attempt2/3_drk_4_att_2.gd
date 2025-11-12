extends Control
class_name RK4Attempt2

@onready var shader_mat := $SubViewportContainer/SubViewport/ShaderRect.material as ShaderMaterial
@export var pause : Control 
var target := Vector3.ZERO
var distance := 60
var yaw := 0.0
var pitch := 0.0
var rotation_speed := 0.01
var fov := 60.0

func _ready():
	Global.rk4_att2 = self
	pause.process_mode = Node.PROCESS_MODE_PAUSABLE
	yaw = .5
	pitch = -.3
	_update_shader_camera()

func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * rotation_speed 
		pitch = clamp(pitch - event.relative.y * rotation_speed, -PI/2.+.01, PI/2.+.01)
		_update_shader_camera()
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(distance * 0.95, 10.)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(distance * 1.05, 1.0e3)
		_update_shader_camera()
	
	if Input.is_action_just_pressed("pause"):
		if pause.process_mode == Node.PROCESS_MODE_DISABLED:
			pause.process_mode = Node.PROCESS_MODE_PAUSABLE
			print("unpaused")
		else:
			print("paused")
			pause.process_mode = Node.PROCESS_MODE_DISABLED

func _update_shader_camera():
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)
	var v = Vector3(x, y, z)

	var camera_position = target - v

	shader_mat.set_shader_parameter("camera_position", camera_position)
	shader_mat.set_shader_parameter("camera_target", target)
	shader_mat.set_shader_parameter("camera_fov", fov)
