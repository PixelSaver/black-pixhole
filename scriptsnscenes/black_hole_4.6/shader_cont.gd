extends ColorRect
class_name ShaderContainer

@export_group("Rendering")
@export var resolution := Vector2i(432, 243)
@export_range(10, 10000) var max_steps := 3000
@export_range(0.0001, 10.0) var step_size := 1.0
@export_range(50.0, 50000.0) var escape_radius := 10000.0
@export var background_color := Color(0.05, 0.05, 0.08, 1.0)

@export_group("Black Hole")
@export var black_hole_position := Vector3.ZERO
@export_range(0.5, 10.0) var schwarzschild_radius := 2.0
@export var black_hole_color := Color(0.0, 0.0, 0.0, 1.0)

@export_group("Camera")
@export_range(30.0, 120.0) var camera_fov := 60.0
@export var camera_position := Vector3(0, 0, 100)
@export var camera_target := Vector3.ZERO

@export_group("Accretion Disc")
@export var show_disc := true
@export var disc_noise : Texture2D
@export_range(1.0, 50.0) var disc_inner_radius := 2.2
@export_range(1.0, 100.0) var disc_outer_radius := 5.2
@export_range(0.1, 50.0) var disc_thickness := 1.0
@export_range(0.1, 100.0) var disc_emission_strength := 1.0
@export var disc_inner_color := Color(1.0, 0.95, 0.0, 1.0)
@export var disc_outer_color := Color(1.0, 0.3, 0.0, 1.0)

@export_group("Stars")
@export var star_color := Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 10.0) var star_brightness := 1.0
@export_range(0.0, 0.05) var star_density := 0.005
@export_range(0.001, 0.1) var star_size_scale := 0.012

@export_group("Spacetime Grid")
@export var show_grid := true
@export var grid_color := Color(0.5, 0.7, 1.0, 1.0)
@export_range(0.5, 50.0) var grid_spacing := 10.0
@export_range(0.01, 10.0) var grid_line_thickness := 0.8
@export_range(0.0, 10.0) var grid_alpha := 1.0
@export_range(1.0, 200.0) var grid_range := 60.0
@export_range(-200.0, 200.0) var grid_warp_offset := 50.0

@export_group("Big Star")
@export var enable_bigstar := false
@export var bigstar_center := Vector3(0.0, 50.0, -200.0)
@export_range(1.0, 200.0) var bigstar_radius := 20.0
@export var bigstar_emission := Color(1.0, 0.9, 0.7, 1.0)
@export_range(0.0, 20.0) var bigstar_surface_brightness := 6.0
@export_range(0.0, 5.0) var bigstar_halo := 0.6

@onready var subvp : SubViewport = $".."
@onready var subvp_cont : SubViewportContainer = $"../.."
var shader_mat : ShaderMaterial

# Camera
var is_dragging := false
var camera_pos : Vector3 
var target := Vector3.ZERO
var distance := 60.
var target_distance := 60.
var yaw := PI/2
var pitch := 0.0
var rotation_speed := 0.01
var fov := 60.0
var first_person_pitch := 0.
var first_person_yaw := 0.

# Shader uniforms
var _shader_uniform_names := {}


func _ready() -> void:
	shader_mat = self.material as ShaderMaterial
	
	while not Global.runtime_inspector:
		await get_tree().process_frame
	await Global.runtime_inspector.inspection_finished
	
	camera_pos = Global.runtime_inspector.get_target_prop("camera_position")
	target = Global.runtime_inspector.get_target_prop("camera_target")
	
	Global.runtime_inspector.property_changed.connect(_on_runtime_prop_changed)
	
	_set_camera_pos_reverse()
	_apply_camera()

func _push_all_shader_params():
	if not shader_mat:
		return

	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR:
			var prop_name = property.name
			if _shader_uniform_names.has(prop_name):
				Global.runtime_inspector.set_target_prop(prop_name, get(prop_name))

func _on_runtime_prop_changed(prop_name:String, new_val):
	match prop_name:
		"camera_position":
			camera_pos = new_val
			_set_camera_pos_reverse()
			_apply_camera()
		"camera_target":
			target = new_val
			_set_camera_pos_reverse()
			_apply_camera()
		_:
			return

func _gui_input(event: InputEvent) -> void:
	print("GUI EVENT:", event)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				is_dragging = event.pressed
				print("Dragging")

			MOUSE_BUTTON_WHEEL_UP:
				distance *= 0.9
				_update_camera_from_angles()

			MOUSE_BUTTON_WHEEL_DOWN:
				distance *= 1.1
				_update_camera_from_angles()

	elif event is InputEventMouseMotion:
		if is_dragging:

			yaw -= event.relative.x * rotation_speed
			pitch = clamp(
				pitch + event.relative.y * rotation_speed,
				-PI/2 + 0.1,
				PI/2 - 0.1
			)

			_update_camera_from_angles()
		
func _set_camera_pos_reverse() -> void:
	var relative: Vector3 = camera_pos - target
	distance = relative.length()
	target_distance = distance

	if distance < 0.0001:
		return

	var dir := relative / distance

	pitch = asin(clamp(dir.y, -1.0, 1.0))

	yaw = atan2(dir.x, dir.z)

func _update_camera_from_angles():
	var x = distance * cos(pitch) * sin(yaw)
	var y = distance * sin(pitch)
	var z = distance * cos(pitch) * cos(yaw)

	camera_pos = target + Vector3(x, y, z)
	
	if shader_mat:
		shader_mat.set_shader_parameter("camera_position", camera_pos)
		
	Global.runtime_inspector.set_target_prop("camera_position", camera_pos)

func _apply_camera():
	if shader_mat:
		shader_mat.set_shader_parameter("camera_position", camera_pos)
