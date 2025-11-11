extends Node3D

# Constants
const C: float = 299792458.0
const G: float = 6.67430e-11

@export_category("Black hole parameters")
@export var black_hole_mass: float = 8.54e36  # Sagittarius A* mass
@export var schwarzschild_radius: float
@export var black_hole_position: Vector3 = Vector3.ZERO

@export_category("Rendering")
@export var use_geodesics: bool = false
var render_texture: ImageTexture
var pixel_data: PackedByteArray
@export var screen_width: int = 800
@export var screen_height: int = 600

@export_category("Camera orbit controls")
@export var camera_azimuth: float = 0.0
var camera_elevation: float = PI / 2.0
var camera_radius: float = 6.34194e10
var camera_target: Vector3 = Vector3.ZERO
@export var camera_fov: float = 60.0

var min_radius: float = 1e12
var max_radius: float = 1e20
@export var orbit_speed: float = 0.008
@export var pan_speed: float = 0.001
@export var zoom_speed: float = 1.08

# Input state
var is_dragging: bool = false
var is_panning: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

# Ray tracing parameters
const MAX_STEPS: int = 10000
const D_LAMBDA: float = 1e7
const ESCAPE_R: float = 1e14

# Performance
var frame_count: int = 0
var last_fps_time: float = 0.0

# References
@onready var camera_3d: Camera3D = $Camera3D
@onready var viewport_quad: TextureRect = $TextureRect
@onready var fps_label: RichTextLabel = $FPSLabel

func _ready() -> void:
	schwarzschild_radius = 2.0 * G * black_hole_mass / (C * C)
	
	# Initialize render texture
	var image := Image.create(screen_width, screen_height, false, Image.FORMAT_RGB8)
	render_texture = ImageTexture.create_from_image(image)
	pixel_data.resize(screen_width * screen_height * 3)
	
	# Setup viewport quad material
	var material := StandardMaterial3D.new()
	material.albedo_texture = render_texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	viewport_quad.material = material
	
	# Setup camera
	update_camera_position()

func _process(_delta: float) -> void:
	# Update FPS counter
	frame_count += 1
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_fps_time >= 1.0:
		var fps = frame_count / (current_time - last_fps_time)
		fps_label.text = "FPS: %.1f | Mode: %s" % [fps, "Geodesic" if use_geodesics else "Simple"]
		frame_count = 0
		last_fps_time = current_time
	
	# Perform ray tracing (CPU for now)
	raytrace()
	
	# Update texture
	var image = Image.create_from_data(screen_width, screen_height, false, Image.FORMAT_RGB8, pixel_data)
	render_texture.update(image)

func _input(event: InputEvent) -> void:
	# Toggle geodesic mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		use_geodesics = !use_geodesics
		print("Geodesics: ", "ON" if use_geodesics else "OFF")
	
	# Mouse button handling
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				is_panning = event.shift_pressed
				last_mouse_pos = event.position
			else:
				is_dragging = false
				is_panning = false
		
		# Scroll for zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_radius /= pow(zoom_speed, 1.0)
			camera_radius = clamp(camera_radius, min_radius, max_radius)
			update_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_radius *= pow(zoom_speed, 1.0)
			camera_radius = clamp(camera_radius, min_radius, max_radius)
			update_camera_position()
	
	# Mouse motion handling
	if event is InputEventMouseMotion and is_dragging:
		var delta_pos = event.position - last_mouse_pos
		
		if is_panning:
			# Pan camera target
			var forward = (camera_target - camera_3d.global_position).normalized()
			var right = forward.cross(Vector3.UP).normalized()
			var up = right.cross(forward)
			camera_target += -right * delta_pos.x * pan_speed * camera_radius
			camera_target += up * delta_pos.y * pan_speed * camera_radius
		else:
			# Orbit camera
			camera_azimuth -= delta_pos.x * orbit_speed
			camera_elevation -= delta_pos.y * orbit_speed
			camera_elevation = clamp(camera_elevation, 0.01, PI - 0.01)
		
		update_camera_position()
		last_mouse_pos = event.position

func update_camera_position() -> void:
	var pos: Vector3
	pos.x = camera_target.x + camera_radius * sin(camera_elevation) * cos(camera_azimuth)
	pos.y = camera_target.y + camera_radius * cos(camera_elevation)
	pos.z = camera_target.z + camera_radius * sin(camera_elevation) * sin(camera_azimuth)
	
	camera_3d.global_position = pos
	camera_3d.look_at(camera_target, Vector3.UP)
	camera_3d.fov = camera_fov

func raytrace() -> void:
	# Build camera basis
	var cam_pos = camera_3d.global_position
	var forward = (camera_target - cam_pos).normalized()
	var right = forward.cross(Vector3.UP).normalized()
	var up = right.cross(forward)
	
	var aspect = float(screen_width) / float(screen_height)
	var tan_half_fov = tan(deg_to_rad(camera_fov) * 0.5)
	
	# Ray trace each pixel
	for y in range(screen_height):
		for x in range(screen_width):
			# NDC to screen space
			var u = (2.0 * (x + 0.5) / screen_width - 1.0) * aspect * tan_half_fov
			var v = (1.0 - 2.0 * (y + 0.5) / screen_height) * tan_half_fov
			var dir = (u * right + v * up + forward).normalized()
			
			var color := Vector3.ZERO
			
			if !use_geodesics:
				# Simple sphere intersection test
				if sphere_intersect(cam_pos, dir):
					color = Vector3(1.0, 0.0, 0.0)
			else:
				# Full geodesic ray tracing
				var ray = create_ray(cam_pos, dir)
				color = trace_geodesic(ray)
			
			# Write pixel
			var idx = (y * screen_width + x) * 3
			pixel_data[idx + 0] = int(color.x * 255)
			pixel_data[idx + 1] = int(color.y * 255)
			pixel_data[idx + 2] = int(color.z * 255)

func sphere_intersect(origin: Vector3, direction: Vector3) -> bool:
	var oc = origin - black_hole_position
	var b = 2.0 * oc.dot(direction)
	var c = oc.dot(oc) - schwarzschild_radius * schwarzschild_radius
	var discriminant = b * b - 4.0 * c
	
	if discriminant > 0.0:
		var t1 = (-b - sqrt(discriminant)) * 0.5
		var t2 = (-b + sqrt(discriminant)) * 0.5
		return t1 > 0.0 or t2 > 0.0
	return false

func create_ray(pos: Vector3, dir: Vector3) -> Dictionary:
	var ray = {
		"x": pos.x, "y": pos.y, "z": pos.z,
		"r": 0.0, "theta": 0.0, "phi": 0.0,
		"dr": 0.0, "dtheta": 0.0, "dphi": 0.0,
		"E": 0.0, "L": 0.0
	}
	
	# Convert to spherical coordinates
	ray.r = sqrt(pos.x * pos.x + pos.y * pos.y + pos.z * pos.z)
	ray.theta = acos(pos.z / ray.r)
	ray.phi = atan2(pos.y, pos.x)
	
	# Convert direction to spherical basis
	var sin_theta = sin(ray.theta)
	var cos_theta = cos(ray.theta)
	var sin_phi = sin(ray.phi)
	var cos_phi = cos(ray.phi)
	
	ray.dr = sin_theta * cos_phi * dir.x + sin_theta * sin_phi * dir.y + cos_theta * dir.z
	ray.dtheta = (cos_theta * cos_phi * dir.x + cos_theta * sin_phi * dir.y - sin_theta * dir.z) / ray.r
	ray.dphi = (-sin_phi * dir.x + cos_phi * dir.y) / (ray.r * sin_theta)
	
	# Store conserved quantities
	ray.L = ray.r * ray.r * sin_theta * ray.dphi
	var f = 1.0 - schwarzschild_radius / ray.r
	var dt_dlambda = sqrt(ray.dr * ray.dr / f + ray.r * ray.r * ray.dtheta * ray.dtheta + 
						  ray.r * ray.r * sin_theta * sin_theta * ray.dphi * ray.dphi)
	ray.E = f * dt_dlambda
	
	return ray

func trace_geodesic(ray: Dictionary) -> Vector3:
	for i in range(MAX_STEPS):
		# Check if ray hit black hole
		var dx = ray.x - black_hole_position.x
		var dy = ray.y - black_hole_position.y
		var dz = ray.z - black_hole_position.z
		var dist_sq = dx * dx + dy * dy + dz * dz
		
		if dist_sq < schwarzschild_radius * schwarzschild_radius:
			return Vector3(1.0, 0.0, 0.0)  # Red for black hole hit
		
		# Step ray forward
		rk4_step(ray, D_LAMBDA)
		
		# Check escape condition
		if ray.r > ESCAPE_R:
			break
	
	return Vector3.ZERO  # Black for escaped/missed

func rk4_step(ray: Dictionary, dlambda: float) -> void:
	if ray.r <= schwarzschild_radius:
		return
	
	var y0 = [ray.r, ray.theta, ray.phi, ray.dr, ray.dtheta, ray.dphi]
	var k1 = geodesic_rhs(ray)
	
	var temp_ray = ray.duplicate(true)
	for i in range(6):
		var keys = ["r", "theta", "phi", "dr", "dtheta", "dphi"]
		temp_ray[keys[i]] = y0[i] + k1[i] * dlambda / 2.0
	var k2 = geodesic_rhs(temp_ray)
	
	temp_ray = ray.duplicate(true)
	for i in range(6):
		var keys = ["r", "theta", "phi", "dr", "dtheta", "dphi"]
		temp_ray[keys[i]] = y0[i] + k2[i] * dlambda / 2.0
	var k3 = geodesic_rhs(temp_ray)
	
	temp_ray = ray.duplicate(true)
	for i in range(6):
		var keys = ["r", "theta", "phi", "dr", "dtheta", "dphi"]
		temp_ray[keys[i]] = y0[i] + k3[i] * dlambda
	var k4 = geodesic_rhs(temp_ray)
	
	# Update ray state
	var keys = ["r", "theta", "phi", "dr", "dtheta", "dphi"]
	for i in range(6):
		ray[keys[i]] += (dlambda / 6.0) * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	
	# Convert back to Cartesian
	ray.x = ray.r * sin(ray.theta) * cos(ray.phi)
	ray.y = ray.r * sin(ray.theta) * sin(ray.phi)
	ray.z = ray.r * cos(ray.theta)

func geodesic_rhs(ray: Dictionary) -> Array:
	var r = ray.r
	var theta = ray.theta
	var dr = ray.dr
	var dtheta = ray.dtheta
	var dphi = ray.dphi
	var E = ray.E
	
	var f = 1.0 - schwarzschild_radius / r
	var dt_dlambda = E / f
	var sin_theta = sin(theta)
	var cos_theta = cos(theta)
	
	var rhs = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	
	# First derivatives
	rhs[0] = dr
	rhs[1] = dtheta
	rhs[2] = dphi
	
	# Second derivatives (Schwarzschild geodesics)
	rhs[3] = (
		-(schwarzschild_radius / (2.0 * r * r)) * f * dt_dlambda * dt_dlambda +
		(schwarzschild_radius / (2.0 * r * r * f)) * dr * dr +
		r * (dtheta * dtheta + sin_theta * sin_theta * dphi * dphi)
	)
	
	rhs[4] = (
		-(2.0 / r) * dr * dtheta +
		sin_theta * cos_theta * dphi * dphi
	)
	
	rhs[5] = (
		-(2.0 / r) * dr * dphi -
		2.0 * cos_theta / sin_theta * dtheta * dphi
	)
	
	return rhs
