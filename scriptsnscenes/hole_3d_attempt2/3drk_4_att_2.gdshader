shader_type canvas_item;

// ---------- User uniforms ----------
uniform vec3 black_hole_position = vec3(0.0, 0.0, 0.0);
uniform float schwarzschild_radius = 10.0;
uniform vec3 black_hole_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 background_color : source_color = vec3(0.05, 0.05, 0.08);

uniform bool use_geodesics = true;
uniform int max_steps = 500;
uniform float dlambda = 0.5;            // integration step size in affine parameter
uniform float escape_radius = 1e6;

uniform vec3 camera_position = vec3(0.0, 0.0, -100.0);
uniform vec3 camera_target = vec3(0.0, 0.0, 1.0);
uniform float camera_fov = 60.0;        // degrees

// ---------- Constants & helpers ----------
const float EPS = 1e-6;

// Numerically-stable sphere intersection (for fallback)
bool sphere_intersect(vec3 origin, vec3 direction, vec3 center, float radius) {
	vec3 oc = origin - center;
	float b = dot(oc, direction);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	if (disc <= 0.0) return false;
	float t = -b - sqrt(disc);
	if (t > 0.0) return true;
	t = -b + sqrt(disc);
	return t > 0.0;
}

// clamp sin to avoid division by zero, preserve sign for cotangent
float safe_cot(float theta) {
	float s = sin(theta);
	if (abs(s) < EPS) {
		// approximate cotangent for very small sin
		return cos(theta) / (EPS * (s >= 0.0 ? 1.0 : -1.0));
	}
	return cos(theta) / s;
}

// ---------- Geodesic math (Schwarzschild) ----------
// State variables: r, theta, phi, dr, dtheta, dphi
// Conserved energy renamed to rayE to avoid conflicts

void init_ray_from_camera(vec3 cam_pos, vec3 ray_dir, float rs,
                          out float r, out float theta, out float phi,
                          out float dr, out float dtheta, out float dphi,
                          out float rayE) {
	// cartesian -> spherical (camera position)
	r = length(cam_pos);
	if (r < EPS) r = EPS;
	theta = acos(clamp(cam_pos.z / r, -1.0, 1.0));
	phi = atan(cam_pos.y, cam_pos.x);

	// Compute spherical-basis components of direction
	float sin_t = sin(theta);
	float cos_t = cos(theta);
	float sin_p = sin(phi);
	float cos_p = cos(phi);

	// dr/dlambda = dot(direction, e_r)
	dr = sin_t * cos_p * ray_dir.x + sin_t * sin_p * ray_dir.y + cos_t * ray_dir.z;

	// dtheta/dlambda = dot(direction, e_theta) / r
	dtheta = (cos_t * cos_p * ray_dir.x + cos_t * sin_p * ray_dir.y - sin_t * ray_dir.z) / max(r, EPS);

	// dphi/dlambda = dot(direction, e_phi) / (r * sinθ)
	float denom = max(r * sin_t, EPS);
	dphi = (-sin_p * ray_dir.x + cos_p * ray_dir.y) / denom;

	// Conserved energy rayE: compute dt/dlambda first (from spatial part)
	float f = 1.0 - rs / r;
	float arg = max(0.0, (dr*dr) / max(f, EPS) + r*r*(dtheta*dtheta + (sin_t*sin_t) * dphi*dphi));
	float dt_dlambda = sqrt(arg);
	rayE = f * dt_dlambda;
}

void geodesic_derivatives(float r, float theta, float phi,
                          float dr, float dtheta, float dphi,
                          float rayE, float rs,
                          out float vr, out float vtheta, out float vphi,
                          out float ar, out float atheta, out float aphi) {
	// velocities (first derivatives)
	vr = dr;
	vtheta = dtheta;
	vphi = dphi;

	// Accelerations (second derivatives)
	float f = 1.0 - rs / r;
	float dt_dlambda = rayE / max(f, EPS);
	float sin_t = sin(theta);
	float cos_t = cos(theta);
	float sin_t_sq = sin_t * sin_t;

	// Use safe cotangent
	float cot_t = (abs(sin_t) < EPS) ? (cos_t / (EPS * (sin_t >= 0.0 ? 1.0 : -1.0))) : cos_t / sin_t;

	// d2r/dlambda2
	float term1 = -(rs / (2.0 * r * r)) * f * dt_dlambda * dt_dlambda;
	float term2 = (rs / (2.0 * r * r * max(f, EPS))) * dr * dr;
	float term3 = r * (dtheta * dtheta + sin_t_sq * dphi * dphi);
	ar = term1 + term2 + term3;

	// d2theta/dlambda2
	atheta = -(2.0 / r) * dr * dtheta + sin_t * cos_t * dphi * dphi;

	// d2phi/dlambda2
	aphi = -(2.0 / r) * dr * dphi - 2.0 * cot_t * dtheta * dphi;
}

// Single RK4 step: updates state variables by step (dlambda)
void rk4_step_state(inout float r, inout float theta, inout float phi,
                    inout float dr, inout float dtheta, inout float dphi,
                    float rayE, float rs, float step) {
	// Save original
	float r0 = r; float th0 = theta; float ph0 = phi;
	float dr0 = dr; float dth0 = dtheta; float dph0 = dphi;

	// k1
	float k1_vr, k1_vth, k1_vph, k1_ar, k1_ath, k1_aph;
	geodesic_derivatives(r0, th0, ph0, dr0, dth0, dph0, rayE, rs,
	                     k1_vr, k1_vth, k1_vph, k1_ar, k1_ath, k1_aph);

	// k2 state
	float r1 = r0 + 0.5 * step * k1_vr;
	float th1 = th0 + 0.5 * step * k1_vth;
	float ph1 = ph0 + 0.5 * step * k1_vph;
	float dr1 = dr0 + 0.5 * step * k1_ar;
	float dth1 = dth0 + 0.5 * step * k1_ath;
	float dph1 = dph0 + 0.5 * step * k1_aph;

	float k2_vr, k2_vth, k2_vph, k2_ar, k2_ath, k2_aph;
	geodesic_derivatives(r1, th1, ph1, dr1, dth1, dph1, rayE, rs,
	                     k2_vr, k2_vth, k2_vph, k2_ar, k2_ath, k2_aph);

	// k3 state
	float r2 = r0 + 0.5 * step * k2_vr;
	float th2 = th0 + 0.5 * step * k2_vth;
	float ph2 = ph0 + 0.5 * step * k2_vph;
	float dr2 = dr0 + 0.5 * step * k2_ar;
	float dth2 = dth0 + 0.5 * step * k2_ath;
	float dph2 = dph0 + 0.5 * step * k2_aph;

	float k3_vr, k3_vth, k3_vph, k3_ar, k3_ath, k3_aph;
	geodesic_derivatives(r2, th2, ph2, dr2, dth2, dph2, rayE, rs,
	                     k3_vr, k3_vth, k3_vph, k3_ar, k3_ath, k3_aph);

	// k4 state
	float r3 = r0 + step * k3_vr;
	float th3 = th0 + step * k3_vth;
	float ph3 = ph0 + step * k3_vph;
	float dr3 = dr0 + step * k3_ar;
	float dth3 = dth0 + step * k3_ath;
	float dph3 = dph0 + step * k3_aph;

	float k4_vr, k4_vth, k4_vph, k4_ar, k4_ath, k4_aph;
	geodesic_derivatives(r3, th3, ph3, dr3, dth3, dph3, rayE, rs,
	                     k4_vr, k4_vth, k4_vph, k4_ar, k4_ath, k4_aph);

	// Combine to update
	r  = r0  + (step / 6.0) * (k1_vr  + 2.0 * k2_vr  + 2.0 * k3_vr  + k4_vr);
	theta = th0 + (step / 6.0) * (k1_vth + 2.0 * k2_vth + 2.0 * k3_vth + k4_vth);
	phi   = ph0 + (step / 6.0) * (k1_vph + 2.0 * k2_vph + 2.0 * k3_vph + k4_vph);
	dr    = dr0 + (step / 6.0) * (k1_ar  + 2.0 * k2_ar  + 2.0 * k3_ar  + k4_ar);
	dtheta= dth0 + (step / 6.0) * (k1_ath + 2.0 * k2_ath + 2.0 * k3_ath + k4_ath);
	dphi  = dph0 + (step / 6.0) * (k1_aph + 2.0 * k2_aph + 2.0 * k3_aph + k4_aph);

	// keep theta in a reasonable band, wrap phi
	if (theta < 0.0) theta = -theta;
	if (theta > PI) theta = mod(theta, PI);
	phi = mod(phi + PI, 2.0 * PI) - PI;
}

// Convert spherical back to cartesian position for collision testing
vec3 spherical_to_cartesian(float r, float theta, float phi) {
	float st = sin(theta);
	return vec3(r * st * cos(phi), r * st * sin(phi), r * cos(theta));
}

// ---------- Trace loop ----------
vec3 trace_geodesic(vec3 cam_pos, vec3 ray_dir, float rs) {
	// Initialize spherical state & conserved rayE
	float r, theta, phi, dr, dtheta, dphi, rayE;
	init_ray_from_camera(cam_pos, ray_dir, rs, r, theta, phi, dr, dtheta, dphi, rayE);

	// Sanity guards
	if (!(r > 0.0)) return background_color;
	if (r <= rs) return black_hole_color;

	// Integration loop
	for (int i = 0; i < max_steps; i++) {
		// Check capture
		if (r <= rs) {
			return black_hole_color;
		}

		// Step forward
		rk4_step_state(r, theta, phi, dr, dtheta, dphi, rayE, rs, dlambda);

		// Recompute cartesian pos for intersection test
		vec3 pos = spherical_to_cartesian(r, theta, phi) + black_hole_position;

		// Check escape far away
		if (r > escape_radius) break;
	}
	return background_color;
}

// ---------- Fragment entry ----------
void fragment() {
	// Build camera basis
	vec3 forward = normalize(camera_target - camera_position);
	vec3 world_up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(forward, world_up));
	if (length(right) < 1e-5) {
		world_up = vec3(1.0, 0.0, 0.0);
		right = normalize(cross(forward, world_up));
	}
	vec3 up = cross(right, forward);

	// Map screen uv to ray direction
	vec2 uv = SCREEN_UV * 2.0 - 1.0;
	float aspect = UV.x / UV.y;
	float tan_half_fov = tan(radians(camera_fov) * 0.5);
	uv.x *= aspect * tan_half_fov;
	uv.y *= tan_half_fov;
	vec3 ray_dir = normalize(uv.x * right + uv.y * up + forward);

	vec3 color_out;
	if (!use_geodesics) {
		// Simple sphere intersection fallback
		if (sphere_intersect(camera_position, ray_dir, black_hole_position, schwarzschild_radius)) {
			color_out = black_hole_color;
		} else {
			color_out = background_color;
		}
	} else {
		color_out = trace_geodesic(camera_position, ray_dir, schwarzschild_radius);
	}

	COLOR = vec4(color_out, 1.0);
}
