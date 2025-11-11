shader_type canvas_item;

// ---------- User uniforms ----------
uniform vec3 black_hole_position = vec3(0.0, 0.0, 0.0);
uniform float schwarzschild_radius = 10.0;
uniform vec3 black_hole_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 background_color : source_color = vec3(0.05, 0.05, 0.08);

uniform bool use_geodesics = true;
uniform int max_steps = 2000;
uniform float step_size = 0.05;  // Conservative default
uniform float escape_radius = 500.0;

uniform vec3 camera_position = vec3(0.0, 0.0, -100.0);
uniform vec3 camera_target = vec3(0.0, 0.0, 0.0);
uniform float camera_fov = 60.0;

// ---------- Accretion Disc Params --------
uniform float disc_inner_radius = 15.0;
uniform float disc_outer_radius = 30.0;
uniform vec3 disc_color : source_color = vec3(1.0, 0.5, 0.0);
uniform float disc_thickness = 1.0;

// ---------- Debug ----------
uniform int debug_mode = 0; // 0=off, 1=initial r, 2=min r, 3=steps, 4=show errors

// ---------- Constants ----------
uniform vec2 viewport_size = vec2(144.0, 81.0);
const float EPS = 1e-7;
const float HORIZON_MARGIN = 1.05; // Stay away from coordinate singularity

// Safe math operations
float safe_acos(float x) {
    return acos(clamp(x, -1.0, 1.0));
}

float safe_sqrt(float x) {
    return sqrt(max(x, 0.0));
}

float safe_div(float num, float denom, float fallback) {
    float abs_denom = abs(denom);
    if (abs_denom < EPS) return fallback;
    return num / denom;
}

// Check if value is valid (not NaN, not Inf)
bool is_valid(float x) {
    return (x == x) && (x < 1e10) && (x > -1e10);
}

bool all_valid(float r, float theta, float phi, float dr, float dtheta, float dphi) {
    return is_valid(r) && is_valid(theta) && is_valid(phi) && 
           is_valid(dr) && is_valid(dtheta) && is_valid(dphi);
}

// ---------- Geodesic Integration with Error Checking ----------

bool init_ray_from_camera(vec3 cam_pos, vec3 ray_dir, float rs,
                          out float r, out float theta, out float phi,
                          out float dr, out float dtheta, out float dphi,
                          out float rayE) {
    
    // Position relative to black hole
    vec3 rel_pos = cam_pos - black_hole_position;
    r = length(rel_pos);
    
    // Early validation
    if (r < rs * HORIZON_MARGIN || !is_valid(r)) {
        return false;
    }
    
    // Normalize relative position for spherical conversion
    vec3 rel_pos_norm = rel_pos / r;
    
    // Spherical coordinates: theta from +z axis, phi in xy-plane
    theta = safe_acos(rel_pos_norm.z);
    
    // Clamp theta away from poles to avoid singularity
    float theta_min = 0.01;
    float theta_max = PI - 0.01;
    theta = clamp(theta, theta_min, theta_max);
    
    phi = atan(rel_pos_norm.y, rel_pos_norm.x);
    
    // Precompute trig functions with clamped theta
    float sin_theta = sin(theta);
    float cos_theta = cos(theta);
    float sin_phi = sin(phi);
    float cos_phi = cos(phi);
    
    // sin_theta should now be safe, but double-check
    sin_theta = max(abs(sin_theta), EPS) * sign(sin_theta);
    
    // Spherical basis vectors (normalized by construction)
    vec3 e_r = vec3(sin_theta * cos_phi, sin_theta * sin_phi, cos_theta);
    vec3 e_theta = vec3(cos_theta * cos_phi, cos_theta * sin_phi, -sin_theta);
    vec3 e_phi = vec3(-sin_phi, cos_phi, 0.0);
    
    // Project ray direction onto spherical basis
    dr = dot(ray_dir, e_r);
    dtheta = dot(ray_dir, e_theta) / r;
    dphi = dot(ray_dir, e_phi) / (r * sin_theta);
    
    // Validate initial derivatives
    if (!all_valid(r, theta, phi, dr, dtheta, dphi)) {
        return false;
    }
    
    // Calculate conserved energy for null geodesic
    // Metric factor f = (1 - rs/r)
    float f = 1.0 - rs / r;
    f = max(f, EPS);
    
    // Spatial term from metric: dr²/f + r²(dθ² + sin²θ dφ²)
    float spatial_sq = (dr * dr) / f + 
                       r * r * (dtheta * dtheta + sin_theta * sin_theta * dphi * dphi);
    
    // For null geodesic: (1-rs/r)(dt/dλ)² = spatial_term
    float dt_dlambda = safe_sqrt(spatial_sq);
    
    // Conserved energy E = (1 - rs/r) * dt/dλ
    rayE = f * dt_dlambda;
    
    // Validate energy is reasonable
    if (!is_valid(rayE) || rayE < EPS) {
        return false;
    }
    
    return true;
}

bool geodesic_derivatives(float r, float theta, float phi,
                          float dr, float dtheta, float dphi,
                          float rayE, float rs,
                          out float vr, out float vtheta, out float vphi,
                          out float ar, out float atheta, out float aphi) {
    
    // Check if we're too close to horizon
    if (r < rs * HORIZON_MARGIN) {
        vr = dr; vtheta = dtheta; vphi = dphi;
        ar = -1000.0; atheta = 0.0; aphi = 0.0; // Force infall
        return true;
    }
    
    // Clamp theta away from poles during integration
    theta = clamp(theta, 0.0, PI);
    
    // Validate inputs
    if (!all_valid(r, theta, phi, dr, dtheta, dphi)) {
        vr = vtheta = vphi = ar = atheta = aphi = 0.0;
        return false;
    }
    
    // Velocities
    vr = dr;
    vtheta = dtheta;
    vphi = dphi;
    
    // Metric factor and time derivative
    float f = 1.0 - rs / r;
    f = max(f, EPS); // Prevent division by zero
    float dt_dlambda = rayE / f;
    
    // Trig functions
    float sin_theta = sin(theta);
    float cos_theta = cos(theta);
    
    // Ensure sin_theta is never too small
    sin_theta = max(abs(sin_theta), EPS) * sign(sin_theta);
    float sin_theta_sq = sin_theta * sin_theta;
    
    // Schwarzschild geodesic equations
    // d²r/dλ² = -(rs/2r²)f(dt/dλ)² + (rs/2r²f)(dr/dλ)² + r[(dθ/dλ)² + sin²θ(dφ/dλ)²]
    float term1 = -(rs / (2.0 * r * r)) * f * dt_dlambda * dt_dlambda;
    float term2 = (rs / (2.0 * r * r * f)) * dr * dr;
    float term3 = r * (dtheta * dtheta + sin_theta_sq * dphi * dphi);
    ar = term1 + term2 + term3;
    
    // d²θ/dλ² = -(2/r)(dr/dλ)(dθ/dλ) + sinθ cosθ(dφ/dλ)²
    atheta = -(2.0 / r) * dr * dtheta + sin_theta * cos_theta * dphi * dphi;
    
    // d²φ/dλ² = -(2/r)(dr/dλ)(dφ/dλ) - 2cotθ(dθ/dλ)(dφ/dλ)
    float cot_theta = cos_theta / sin_theta;
    aphi = -(2.0 / r) * dr * dphi - 2.0 * cot_theta * dtheta * dphi;
    
    // Validate outputs
    return is_valid(ar) && is_valid(atheta) && is_valid(aphi);
}

bool rk4_step(inout float r, inout float theta, inout float phi,
              inout float dr, inout float dtheta, inout float dphi,
              float rayE, float rs, float h) {
    
    // Save original state
    float r0 = r, th0 = theta, ph0 = phi;
    float dr0 = dr, dth0 = dtheta, dph0 = dphi;
    
    // k1
    float k1_r, k1_th, k1_ph, k1_dr, k1_dth, k1_dph;
    if (!geodesic_derivatives(r0, th0, ph0, dr0, dth0, dph0, rayE, rs,
                             k1_r, k1_th, k1_ph, k1_dr, k1_dth, k1_dph)) {
        return false;
    }
    
    // k2
    float k2_r, k2_th, k2_ph, k2_dr, k2_dth, k2_dph;
    if (!geodesic_derivatives(r0 + 0.5*h*k1_r, th0 + 0.5*h*k1_th, ph0 + 0.5*h*k1_ph,
                             dr0 + 0.5*h*k1_dr, dth0 + 0.5*h*k1_dth, dph0 + 0.5*h*k1_dph,
                             rayE, rs,
                             k2_r, k2_th, k2_ph, k2_dr, k2_dth, k2_dph)) {
        return false;
    }
    
    // k3
    float k3_r, k3_th, k3_ph, k3_dr, k3_dth, k3_dph;
    if (!geodesic_derivatives(r0 + 0.5*h*k2_r, th0 + 0.5*h*k2_th, ph0 + 0.5*h*k2_ph,
                             dr0 + 0.5*h*k2_dr, dth0 + 0.5*h*k2_dth, dph0 + 0.5*h*k2_dph,
                             rayE, rs,
                             k3_r, k3_th, k3_ph, k3_dr, k3_dth, k3_dph)) {
        return false;
    }
    
    // k4
    float k4_r, k4_th, k4_ph, k4_dr, k4_dth, k4_dph;
    if (!geodesic_derivatives(r0 + h*k3_r, th0 + h*k3_th, ph0 + h*k3_ph,
                             dr0 + h*k3_dr, dth0 + h*k3_dth, dph0 + h*k3_dph,
                             rayE, rs,
                             k4_r, k4_th, k4_ph, k4_dr, k4_dth, k4_dph)) {
        return false;
    }
    
    // Compute updates
    float new_r = r0 + (h/6.0) * (k1_r + 2.0*k2_r + 2.0*k3_r + k4_r);
    float new_theta = th0 + (h/6.0) * (k1_th + 2.0*k2_th + 2.0*k3_th + k4_th);
    float new_phi = ph0 + (h/6.0) * (k1_ph + 2.0*k2_ph + 2.0*k3_ph + k4_ph);
    float new_dr = dr0 + (h/6.0) * (k1_dr + 2.0*k2_dr + 2.0*k3_dr + k4_dr);
    float new_dtheta = dth0 + (h/6.0) * (k1_dth + 2.0*k2_dth + 2.0*k3_dth + k4_dth);
    float new_dphi = dph0 + (h/6.0) * (k1_dph + 2.0*k2_dph + 2.0*k3_dph + k4_dph);
    
    // Validate new state
    if (!all_valid(new_r, new_theta, new_phi, new_dr, new_dtheta, new_dphi)) {
        return false;
    }
    
    // Apply updates
    r = new_r;
    theta = new_theta;
    phi = new_phi;
    dr = new_dr;
    dtheta = new_dtheta;
    dphi = new_dphi;
    
    // Enforce theta bounds strictly - avoid poles
    theta = clamp(theta, 0.01, PI - 0.01);
    
    // Normalize phi to [-π, π] using a more stable method
    // This avoids discontinuities at phi = ±π
    while (phi > PI) phi -= 2.0 * PI;
    while (phi < -PI) phi += 2.0 * PI;
    
    return true;
}

vec3 spherical_to_cartesian(float r, float theta, float phi) {
    float st = sin(theta);
    float ct = cos(theta);
    float sp = sin(phi);
    float cp = cos(phi);
    return vec3(r * st * cp, r * st * sp, r * ct);
}

bool intersect_disc(vec3 local_pos) {
    if (abs(local_pos.z) > disc_thickness) return false;
    float r_sq = local_pos.x * local_pos.x + local_pos.y * local_pos.y;
    float inner_sq = disc_inner_radius * disc_inner_radius;
    float outer_sq = disc_outer_radius * disc_outer_radius;
    return (r_sq >= inner_sq && r_sq <= outer_sq);
}

vec3 trace_geodesic(vec3 cam_pos, vec3 ray_dir, float rs, out float initial_r, out float min_r, out int steps, out bool had_error) {
    float r, theta, phi, dr, dtheta, dphi, rayE;
    
    had_error = false;
    
    // Initialize ray
    if (!init_ray_from_camera(cam_pos, ray_dir, rs, r, theta, phi, dr, dtheta, dphi, rayE)) {
        had_error = true;
        return vec3(1.0, 0.0, 0.0); // Red for initialization error
    }
    
    initial_r = r;
    min_r = r;
    steps = 0;
    
    // Main integration loop
    for (int i = 0; i < max_steps; i++) {
        steps = i;
        
        // Check termination conditions
        if (r <= rs * HORIZON_MARGIN) {
            return black_hole_color;
        }
        
        if (r > escape_radius) {
            return background_color;
        }
        
        // Track minimum approach
        if (r < min_r) min_r = r;
        
        // Check disc intersection
        vec3 local_pos = spherical_to_cartesian(r, theta, phi);
        if (intersect_disc(local_pos)) {
            return disc_color;
        }
        
        // Adaptive step size: smaller near horizon, larger far away
        float adaptive_h = step_size * max(r - rs, rs * 0.1) * 1e-3;
        
        // Clamp step size to reasonable bounds
        adaptive_h = clamp(adaptive_h, 0.01, 10.0);
        
        // Integrate one step
        if (!rk4_step(r, theta, phi, dr, dtheta, dphi, rayE, rs, adaptive_h)) {
            had_error = true;
            return vec3(1.0, 0.0, 1.0); // Magenta for integration error
        }
    }
    
    // Max steps reached
    return background_color;
}

void fragment() {
    // Camera basis
    vec3 forward = normalize(camera_target - camera_position);
    vec3 world_up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(forward, world_up));
    
    // Handle degenerate case
    if (length(right) < 1e-5) {
        world_up = vec3(1.0, 0.0, 0.0);
        right = normalize(cross(forward, world_up));
    }
    vec3 up = normalize(cross(right, forward));
    
    // Screen to NDC
    vec2 uv = (FRAGCOORD.xy / viewport_size) * 2.0 - 1.0;
    float aspect = viewport_size.x / viewport_size.y;
    uv.x *= aspect;
    
    // Apply FOV
    float tan_half_fov = tan(radians(camera_fov) * 0.5);
    uv *= tan_half_fov;
    
    // Ray direction
    vec3 ray_dir = normalize(uv.x * right + uv.y * up + forward);
    
    vec3 color_out;
    
    if (!use_geodesics) {
        // Simple sphere test
        vec3 oc = camera_position - black_hole_position;
        float b = dot(oc, ray_dir);
        float c = dot(oc, oc) - schwarzschild_radius * schwarzschild_radius;
        float discriminant = b * b - c;
        
        if (discriminant >= 0.0) {
            float t = -b - sqrt(discriminant);
            color_out = (t > 0.0) ? black_hole_color : background_color;
        } else {
            color_out = background_color;
        }
    } else {
        float initial_r, min_r;
        int steps;
        bool had_error;
        
        color_out = trace_geodesic(camera_position, ray_dir, schwarzschild_radius, 
                                   initial_r, min_r, steps, had_error);
        
        // Debug visualizations
        if (debug_mode == 1) {
            // Initial distance
            color_out = vec3(initial_r / 200.0, 0.0, 0.0);
        } else if (debug_mode == 2) {
            // Minimum radius (red=close, green=far)
            float norm = clamp((min_r - schwarzschild_radius) / 50.0, 0.0, 1.0);
            color_out = vec3(1.0 - norm, norm, 0.0);
        } else if (debug_mode == 3) {
            // Step count
            float ratio = float(steps) / float(max_steps);
            color_out = vec3(ratio, ratio * 0.5, 1.0 - ratio);
        } else if (debug_mode == 4) {
            // Show errors
            if (had_error) {
                color_out = vec3(1.0, 1.0, 0.0); // Yellow for errors
            }
        }
    }
    
    COLOR = vec4(color_out, 1.0);
}