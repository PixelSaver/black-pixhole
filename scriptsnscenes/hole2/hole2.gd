extends Node2D

const C := 299_792_458.0
const G := 6.67430e-11

## scale meters to pixels
var pixels_per_meter: float = 5e-9     
#$ integration step (affine parameter)
var dlambda: float = 1.0               
var max_trail_points: int = 400

# Black Hole params
var BH_mass: float = 8.54e36
var r_s: float = 2.0 * G * BH_mass / (C * C)

var rays: Array = []

## Create a new ray dictionary
func _new_ray(pos: Vector2, dir: Vector2) -> Dictionary:
	var ray: Dictionary = {
		"x": pos.x,
		"y": pos.y,
		"r": 0.0,
		"phi": 0.0,
		"dr": 0.0,
		"dphi": 0.0,
		"E": 0.0,
		"L": 0.0,
		"trail": []
	}

	ray.r = sqrt(pos.x * pos.x + pos.y * pos.y)
	ray.phi = atan2(pos.y, pos.x)

	var vx: float = dir.x
	var vy: float = dir.y

	ray.dr = vx * cos(ray.phi) + vy * sin(ray.phi)
	ray.dphi = (-vx * sin(ray.phi) + vy * cos(ray.phi)) / ray.r
	ray.L = ray.r * ray.r * ray.dphi

	var f: float = 1.0 - r_s / ray.r
	var dt_dlambda: float = sqrt((ray.dr * ray.dr) / (f * f) + (ray.r * ray.r * ray.dphi * ray.dphi) / f)
	ray.E = f * dt_dlambda

	ray.trail.append(Vector2(ray.x, ray.y))
	return ray

## RHS of the null geodesic ODEs
func geodesic_rhs(ray: Dictionary) -> PackedFloat32Array:
	var r: float = ray.r
	var dr: float = ray.dr
	var dphi: float = ray.dphi
	var E: float = ray.E
	var f: float = 1.0 - r_s / r
	var rhs := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

	rhs[0] = dr
	rhs[1] = dphi

	var dt_dlambda: float = E / f
	rhs[2] = - (r_s / (2.0 * r * r)) * f * (dt_dlambda * dt_dlambda) \
		+ (r_s / (2.0 * r * r * f)) * (dr * dr) \
		+ (r - r_s) * (dphi * dphi)
	rhs[3] = -2.0 * dr * dphi / r
	return rhs

func add_state(a: Array, b: PackedFloat32Array, factor: float) -> Array:
	var out := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		out[i] = a[i] + b[i] * factor
	return out

## RK4 integration step
func rk4_step(ray: Dictionary, dl: float) -> void:
	var y0 := [ray.r, ray.phi, ray.dr, ray.dphi]
	var k1 := geodesic_rhs(ray)



	var temp := add_state(y0, k1, dl * 0.5)
	var r2 := ray.duplicate()
	r2.r = temp[0]; r2.phi = temp[1]; r2.dr = temp[2]; r2.dphi = temp[3]
	var k2 := geodesic_rhs(r2)

	temp = add_state(y0, k2, dl * 0.5)
	var r3 := ray.duplicate()
	r3.r = temp[0]; r3.phi = temp[1]; r3.dr = temp[2]; r3.dphi = temp[3]
	var k3 := geodesic_rhs(r3)

	temp = add_state(y0, k3, dl)
	var r4 := ray.duplicate()
	r4.r = temp[0]; r4.phi = temp[1]; r4.dr = temp[2]; r4.dphi = temp[3]
	var k4 := geodesic_rhs(r4)

	ray.r    += (dl / 6.0) * (k1[0] + 2.0 * k2[0] + 2.0 * k3[0] + k4[0])
	ray.phi  += (dl / 6.0) * (k1[1] + 2.0 * k2[1] + 2.0 * k3[1] + k4[1])
	ray.dr   += (dl / 6.0) * (k1[2] + 2.0 * k2[2] + 2.0 * k3[2] + k4[2])
	ray.dphi += (dl / 6.0) * (k1[3] + 2.0 * k2[3] + 2.0 * k3[3] + k4[3])

	ray.x = ray.r * cos(ray.phi)
	ray.y = ray.r * sin(ray.phi)
	ray.trail.append(Vector2(ray.x, ray.y))
	if ray.trail.size() > max_trail_points:
		ray.trail.pop_front()


# Godot Sim stuff
func _ready() -> void:
	for y in range(-10, 10):
		rays.append(_new_ray(Vector2(-1e11, y * 5e9), Vector2(C, 0)))

	queue_redraw()


func _physics_process(_delta: float) -> void:
	for ray in rays:
		if ray.r <= r_s:
			continue
		rk4_step(ray, dlambda)
	queue_redraw()

func world_to_screen_pos(world_pos: Vector2) -> Vector2:
	var px: float = world_pos.x * pixels_per_meter
	var py: float = -world_pos.y * pixels_per_meter
	return Vector2(px, py) + get_viewport_rect().size * 0.5


func _draw() -> void:
	# Draw event horizon
	var center := world_to_screen_pos(Vector2.ZERO)
	var r_pixels := r_s * pixels_per_meter
	draw_circle(center, r_pixels, Color.BLACK)

	# Draw rays
	for ray in rays:
		var pts: Array[Vector2] = []
		for p in ray.trail:
			pts.append(world_to_screen_pos(p))
		for i in pts.size() - 1:
			var alpha := float(i) / float(max(1, pts.size() - 1))
			draw_line(pts[i], pts[i + 1], Color(1, 1, 1, max(alpha, 0.05)), 1.0)
		var p := world_to_screen_pos(Vector2(ray.x, ray.y))
		draw_circle(p, 2.0, Color.RED)
