extends TextureRect

@onready var shader_setup : ShaderSetup = $ShaderSetup
@export var min_distance := 10.0
@export var max_distance := 1000.0
@export var zoom_speed := 1.
var camera_pos : Vector3 = Vector3(0,8,10)
var target := Vector3.ZERO
var distance := 60
var target_distance := 60
var yaw := 0.0
var pitch := 0.0
var rotation_speed := 0.01
var fov := 60.0

# Called when the user provides input (e.g., mouse move/scroll)
func _gui_input(event: InputEvent) -> void:
	# Check if the game is paused (assuming you have a way to check if controls should be active)
	# if get_tree().paused: return 

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * rotation_speed 
		pitch = clamp(pitch + event.relative.y * rotation_speed, -PI/2.0 + 0.001, PI/2.0 - 0.001)
		_update_camera_state()
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = clamp(target_distance * 0.95, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = clamp(target_distance * 1.05, min_distance, max_distance)
	
	# After input, call update to reflect changes immediately
	shader_setup._setup_uniforms()
	# Also submit the image for rendering if your draw call isn't in _process
	shader_setup._update_shader()


# Called every frame to smooth the zoom/distance
func _process(delta):
	# Smoothly interpolate distance toward target_distance
	distance = lerp(distance, target_distance, zoom_speed * delta)
	# Check if a significant update is needed
	if abs(distance - target_distance) > 0.001:
		_update_camera_state()
		shader_setup._setup_uniforms()
		shader_setup._update_shader()

# Calculates the spherical coordinates into a cartesian position
func _update_camera_state():
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)
	var v = Vector3(x, y, z)

	# Position is offset from target
	camera_pos = target + v # Note: Your original logic was target - v, but v is the offset
	shader_setup.camera_position = camera_pos
	print("camera pos: %s" % camera_pos)

# This is called by _setup_uniforms() to get the current camera data
#func get_camera_params() -> Array:
	## Returns [position, target, fov] to be packed into the uniform buffer
	#return [camera_position_world, target, fov]
