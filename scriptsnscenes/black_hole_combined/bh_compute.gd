extends TextureRect

@onready var shader_setup : ShaderSetup = $ShaderSetup
@export var min_distance := 10.0
@export var max_distance := 1000.0
@export var zoom_speed := 1.
var camera_pos : Vector3 = Vector3(0,8,10)
var target := Vector3.ZERO
var distance := 60
var target_distance := 60
var yaw := PI/2
var pitch := 0.0
var rotation_speed := 0.01
var fov := 60.0
var needs_update := false
var frames_to_wait : int = 0

func _ready() -> void:
	shader_setup.shader_process_frame.connect(_on_shader_process)

func _on_shader_process(_delta:float, frame_time:float):
	var fps = Engine.get_frames_per_second()
	var shader_fps = 1/frame_time
	
	if shader_fps < 10:
		print("Shader fps: %s\nEngine fps: %s", [shader_fps, fps])
	if shader_fps > fps*.9:
		frames_to_wait += int(shader_fps/fps) + 1


# Called when the user provides input (e.g., mouse move/scroll)
func _gui_input(event: InputEvent) -> void:
	# Check if the game is paused (assuming you have a way to check if controls should be active)
	# if get_tree().paused: return 

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * rotation_speed 
		pitch = clamp(pitch + event.relative.y * rotation_speed, -PI/2.0 + 0.001, PI/2.0 - 0.001)
		_update_camera_state()
		needs_update = true
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = clamp(target_distance * 0.95, min_distance, max_distance)
			needs_update = true
			
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = clamp(target_distance * 1.1, min_distance, max_distance)
			needs_update = true
	_update_camera_state()

func _process(_delta: float) -> void:
	if frames_to_wait > 0:
		frames_to_wait -= 1
		return
	shader_setup._update_shader()

# Calculates the spherical coordinates into a cartesian position
func _update_camera_state():
	distance = target_distance
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)
	var v = Vector3(x, y, z)

	# Position is offset from target
	camera_pos = target + v # Note: Your original logic was target - v, but v is the offset
	shader_setup.camera_position = camera_pos
	#print("camera pos: %s" % camera_pos)

# This is called by _setup_uniforms() to get the current camera data
#func get_camera_params() -> Array:
	## Returns [position, target, fov] to be packed into the uniform buffer
	#return [camera_position_world, target, fov]
