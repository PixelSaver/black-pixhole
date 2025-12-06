extends TextureRect

@onready var shader_setup : ShaderSetup = $ShaderSetup
@export var min_distance := 10.0
@export var max_distance := 1000.0
@export var zoom_speed := 1.
@export var fps_label : RichTextLabel
@export var pause_panel: Panel
const SMOOTHING_FACTOR = 0.01
var avg_sfps := 0.0
var camera_pos : Vector3 
var target := Vector3.ZERO
var distance := 60.
var target_distance := 60.
var yaw := PI/2
var pitch := 0.0
var rotation_speed := 0.01
var fov := 60.0
var needs_update := false
var frames_to_wait : int = 0

func _ready() -> void:
	shader_setup.shader_process_frame.connect(_on_shader_process)
	while not Global.runtime_inspector:
		await get_tree().process_frame
	await Global.runtime_inspector.inspection_finished
	camera_pos = Global.runtime_inspector.get_target_prop("camera_position")
	target = Global.runtime_inspector.get_target_prop("camera_target")
	Global.runtime_inspector.property_changed.connect(_on_runtime_prop_changed)
	_set_camera_pos_reverse()

func _on_runtime_prop_changed(prop_name:String, new_val):
	match prop_name:
		"camera_position":
			camera_pos = new_val
			_set_camera_pos_reverse()
		"camera_target":
			target = new_val
			_set_camera_pos_reverse()
		_:
			return

func _set_camera_pos_reverse():
	# 1. Get the relative vector from the target to the camera
	var relative_pos: Vector3 = camera_pos - target

	# 2. Calculate Distance (r)
	distance = relative_pos.length()
	target_distance = distance 

	if distance < 0.001:
		# Avoid division by zero/near-zero, maintain current pitch/yaw
		return

	# 3. Calculate Pitch (Polar Angle)
	pitch = asin(relative_pos.y / distance)

	# 4. Calculate Yaw (Azimuthal Angle)
	yaw = atan2(relative_pos.x, relative_pos.z)

func _on_shader_process(_delta:float, frame_time:float, frame_delay:float):
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	var current_sfps = 1/frame_time
	
	if avg_sfps == 0.0:
		avg_sfps = current_sfps
	else:
		avg_sfps = (current_sfps * SMOOTHING_FACTOR) + (avg_sfps * (1.0 - SMOOTHING_FACTOR))
	
	if current_sfps > fps*.9:
		frames_to_wait += int(current_sfps/fps) + 1
	
	fps_label.text = "[font_size=30]Engine FPS: %s\nShader FPS: %s[/font_size]" % [fps, snappedf(avg_sfps, .01)]
	fps_label.text += "\nFrame Delay: %d" % frame_delay
	fps_label.text += "\nRAM Free: %.2f MB" % (OS.get_memory_info().physical / 1024.0 / 1024.0)
	fps_label.text += "\nStatic Memory: %.2f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0)
	fps_label.text += "\nDraw Calls: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	fps_label.text += "\nVideo Memory Used: %.2f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0 )
	
	
	if current_sfps < 5:
		fps_label.text = "[color=red][shake]" + fps_label.text + "[/shake][/color]"
	elif current_sfps < 10:
		fps_label.text = "[color=yellow]" + fps_label.text + "[/color]"


# Called when the user provides input (e.g., mouse move/scroll)
func _gui_input(event: InputEvent) -> void:
	# Check if the game is paused (assuming you have a way to check if controls should be active)
	# if get_tree().paused: return 

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * rotation_speed 
		pitch = clamp(pitch + event.relative.y * rotation_speed, -PI/2.0 + 0.1, PI/2.0 - 0.1)
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
func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("pause"):
		if shader_setup._paused:
			print("Unpaused")
			pause_panel.hide()
			shader_setup._paused = false
			shader_setup._update_shader()
		else:
			print("Paused")
			pause_panel.show()
			shader_setup._paused = true

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
	Global.runtime_inspector.set_target_prop("camera_position", camera_pos)
	#shader_setup.camera_position = camera_pos
	#print("camera pos: %s" % camera_pos)
