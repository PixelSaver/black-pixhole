extends Control
class_name RK4Attempt2

@onready var shader_mat := $SubViewportContainer/SubViewport/ShaderRect.material as ShaderMaterial
@export var pause : Control 
@export var min_distance := 10.0
@export var max_distance := 1000.0
@export var zoom_speed := 0.1
var target := Vector3.ZERO
var distance := 60
var target_distance := 60
var yaw := 0.0
var pitch := 0.0
var rotation_speed := 0.01
var fov := 60.0
var cam_t : Tween

func _ready():
	Global.rk4_att2 = self
	pause.process_mode = Node.PROCESS_MODE_PAUSABLE
	yaw = .5
	pitch = -.3
	cam_t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	_update_shader_camera()

func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * rotation_speed 
		pitch = clamp(pitch - event.relative.y * rotation_speed, -PI/2.+.001, PI/2.-.001)
		_update_shader_camera()
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = clamp(target_distance * 0.95 - 10., min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = clamp(target_distance * 1.05 + 10., min_distance, max_distance)
	
	if Input.is_action_just_pressed("pause"):
		if pause.process_mode == Node.PROCESS_MODE_DISABLED:
			pause.process_mode = Node.PROCESS_MODE_PAUSABLE
			print("unpaused")
		else:
			print("paused")
			pause.process_mode = Node.PROCESS_MODE_DISABLED

func _process(delta):
	# Smoothly interpolate distance toward target_distance
	distance = clamp(lerp(distance, target_distance, log(zoom_speed*delta*distance)), min_distance, max_distance)
	_update_shader_camera()

func _update_shader_camera():
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)
	var v = Vector3(x, y, z)

	var camera_position = target - v

	shader_mat.set_shader_parameter("camera_position", camera_position)
	shader_mat.set_shader_parameter("camera_target", target)
	shader_mat.set_shader_parameter("camera_fov", fov)
