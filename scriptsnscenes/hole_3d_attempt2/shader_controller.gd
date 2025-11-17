extends Node
class_name ShaderController
## Master controller for black hole shader parameters using array-based approach

@export_group("Target")
@export var target: CanvasItem ## Node with the black hole shader material

@export_group("Black Hole")
@export var black_hole_position: Vector3 = Vector3.ZERO:
	set(v): black_hole_position = v; _update_param("black_hole_position", v)
@export_range(0.1, 100.0) var schwarzschild_radius: float = 0.0:
	set(v): schwarzschild_radius = v; _update_param("schwarzschild_radius", v)
@export var black_hole_color: Color = Color.WHITE:
	set(v): black_hole_color = v; _update_param("black_hole_color", _color_to_vec3(v))

@export_group("Rendering")
@export var background_color: Color = Color.WHITE:
	set(v): background_color = v; _update_param("background_color", _color_to_vec3(v))
@export_range(100, 5000, 100) var max_steps: int = 0:
	set(v): max_steps = v; _update_param("max_steps", v)
@export_range(0.1, 10.0) var step_size: float = 0.0:
	set(v): step_size = v; _update_param("step_size", v)
@export_range(1e3, 1e5) var escape_radius: float = 0.0:
	set(v): escape_radius = v; _update_param("escape_radius", v)

@export_group("Camera")
@export_range(30.0, 120.0) var camera_fov: float = 0.0:
	set(v): camera_fov = v; _update_param("camera_fov", v)

@export_group("Accretion Disc")
@export_range(0.1, 100.0) var disc_inner_radius: float = 0.0:
	set(v): disc_inner_radius = v; _update_param("disc_inner_radius", v)
@export_range(0.1, 100.0) var disc_outer_radius: float = 0.0:
	set(v): disc_outer_radius = v; _update_param("disc_outer_radius", v)
@export var disc_inner_color: Color = Color.WHITE:
	set(v): disc_inner_color = v; _update_param("disc_inner_color", _color_to_vec3(v))
@export var disc_outer_color: Color = Color.WHITE:
	set(v): disc_outer_color = v; _update_param("disc_outer_color", _color_to_vec3(v))
@export_range(0.1, 10.0) var disc_thickness: float = 0.0:
	set(v): disc_thickness = v; _update_param("disc_thickness", v)

@export_group("Stars")
@export var star_color: Color = Color.WHITE:
	set(v): star_color = v; _update_param("star_color", _color_to_vec3(v))
@export_range(0.0, 10.0) var star_brightness: float = 0.0:
	set(v): star_brightness = v; _update_param("star_brightness", v)
@export_range(0.0, 0.02) var star_density: float = 0.0:
	set(v): star_density = v; _update_param("star_density", v)
@export_range(0.001, 0.05) var star_size_scale: float = 0.0:
	set(v): star_size_scale = v; _update_param("star_size_scale", v)

@export_group("Grid")
@export var show_grid: bool = false:
	set(v): show_grid = v; _update_param("show_grid", v)
@export var grid_color: Color = Color.WHITE:
	set(v): grid_color = v; _update_param("grid_color", _color_to_vec3(v))
@export_range(1, 1e3) var grid_spacing: float = 0.0:
	set(v): grid_spacing = v; _update_param("grid_spacing", v)
@export_range(0.1, 10.0) var grid_line_thickness: float = 0.0:
	set(v): grid_line_thickness = v; _update_param("grid_line_thickness", v)
@export_range(0.0, 1.0) var grid_alpha: float = 0.0:
	set(v): grid_alpha = v; _update_param("grid_alpha", v)
@export_range(10, 1e3) var grid_range: float = 0.0:
	set(v): grid_range = v; _update_param("grid_range", v)
@export_range(0.0, 100.0) var grid_warp_offset: float = 0.0:
	set(v): grid_warp_offset = v; _update_param("grid_warp_offset", v)

@export_group("Big Star")
@export var bigstar_center: Vector3 = Vector3.ZERO:
	set(v): bigstar_center = v; _update_param("bigstar_center", v)
@export_range(0.1, 100.0) var bigstar_radius: float = 0.0:
	set(v): bigstar_radius = v; _update_param("bigstar_radius", v)
@export var bigstar_emission: Color = Color.WHITE:
	set(v): bigstar_emission = v; _update_param("bigstar_emission", _color_to_vec3(v))
@export_range(0.0, 10.0) var bigstar_surface_brightness: float = 0.0:
	set(v): bigstar_surface_brightness = v; _update_param("bigstar_surface_brightness", v)
@export_range(0.0, 100.0) var bigstar_halo: float = 0.0:
	set(v): bigstar_halo = v; _update_param("bigstar_halo", v)

@export_group("Other")
@export var viewport_size: Vector2 = Vector2.ZERO:
	set(v): viewport_size = v; _update_param("viewport_size", v)

var _material: ShaderMaterial
var _initialized := false

# Define parameter mappings: [shader_param_name, property_name, is_color]
const PARAM_MAP = [
	["black_hole_position", "black_hole_position", false],
	["schwarzschild_radius", "schwarzschild_radius", false],
	["black_hole_color", "black_hole_color", true],
	["background_color", "background_color", true],
	["max_steps", "max_steps", false],
	["step_size", "step_size", false],
	["escape_radius", "escape_radius", false],
	["camera_position", "camera_position", false],
	["camera_target", "camera_target", false],
	["camera_fov", "camera_fov", false],
	["disc_inner_radius", "disc_inner_radius", false],
	["disc_outer_radius", "disc_outer_radius", false],
	["disc_inner_color", "disc_inner_color", true],
	["disc_outer_color", "disc_outer_color", true],
	["disc_thickness", "disc_thickness", false],
	["star_color", "star_color", true],
	["star_brightness", "star_brightness", false],
	["star_density", "star_density", false],
	["star_size_scale", "star_size_scale", false],
	["show_grid", "show_grid", false],
	["grid_color", "grid_color", true],
	["grid_spacing", "grid_spacing", false],
	["grid_line_thickness", "grid_line_thickness", false],
	["grid_alpha", "grid_alpha", false],
	["grid_range", "grid_range", false],
	["grid_warp_offset", "grid_warp_offset", false],
	["bigstar_center", "bigstar_center", false],
	["bigstar_radius", "bigstar_radius", false],
	["bigstar_emission", "bigstar_emission", true],
	["bigstar_surface_brightness", "bigstar_surface_brightness", false],
	["bigstar_halo", "bigstar_halo", false],
	["viewport_size", "viewport_size", false],
]

func _ready():
	if not target:
		target = get_parent() as CanvasItem

	if target and target.material is ShaderMaterial:
		_material = target.material
		_read_existing_parameters()
		_update_viewport_size()
		_initialized = true
	else:
		push_error("BlackHoleShaderController: No valid ShaderMaterial found")

## Read current shader parameters into exported properties
func _read_existing_parameters():
	if not _material:
		return

	for param_info in PARAM_MAP:
		var shader_name = param_info[0]
		var property_name = param_info[1]
		var is_color = param_info[2]

		var value = _material.get_shader_parameter(shader_name)
		print("Reading %s: %s (type: %s)" % [shader_name, value, type_string(typeof(value))])

		if value != null:
			if is_color:
				if value is Vector3:
					set(property_name, Color(value.x, value.y, value.z))
				elif value is Color:
					set(property_name, value)
			else:
				set(property_name, value)
		else:
			print_debug("Value is null, %s" % property_name)

## Update a single shader parameter
func _update_param(param_name: String, value):
	if not _material or not _initialized:
		return
	_material.set_shader_parameter(param_name, value)

func _color_to_vec3(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)

func _update_viewport_size():
	if target:
		var size = target.get_viewport_rect().size
		_material.set_shader_parameter("viewport_size", size)

func _process(_delta):
	# Auto-update viewport size if it changes
	if Engine.is_editor_hint():
		_update_viewport_size()
