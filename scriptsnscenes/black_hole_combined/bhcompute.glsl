#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D output_image;
layout(set = 0, binding = 1) uniform sampler2D skybox_sampler; // Skybox Texture
layout(set = 0, binding = 2) uniform sampler2D noise_sampler;

// We keep the Params struct aligned to std140 (256 bytes total)
layout(set = 0, binding = 3, std140) uniform Params {
    // Block 1 (Offset 0)
    vec3 black_hole_position;
    float schwarzschild_radius;

    // Block 2 (Offset 16)
    vec4 black_hole_color; // Using as vec3 + padding

    // Block 3 (Offset 32)
    vec3 camera_position;
    float camera_fov;

    // Block 4 (Offset 48)
    vec3 camera_target; // Not strictly used in RK4 cam setup, but kept for alignment
    float time;

    // Block 5 (Offset 64)
    vec2 resolution;
    float max_steps;
    float step_size;

    // Block 6 (Offset 80)
    float escape_radius;
    float skybox_brightness; // repurposed as background brightness
    vec2 _pad1;

    // Block 7 (Offset 96)
    float disc_inner_radius;
    float disc_outer_radius;
    float disc_thickness;
    float disc_emission_strength; // Used as mixing factor in your canvas code

    // Block 8 (Offset 112)
    vec4 disc_inner_color;
    // Block 9 (Offset 128)
    vec4 disc_outer_color;

    // Block 10 (Offset 144)
    float enable_disc;
    vec3 _pad2;

    // Block 11 (Offset 160)
    float show_grid;
    float grid_spacing;
    float grid_line_thickness;
    float grid_alpha;

    // Block 12 (Offset 176)
    float grid_range;
    float grid_warp_offset;
    vec2 _pad3;

    // Block 13 (Offset 192)
    vec4 grid_color;

    // Block 14 (Offset 208)
    float star_density;
    float star_brightness;
    vec2 _pad4;

    // Block 15 (Offset 224)
    vec4 star_color;
} params;

const float EPS = 1e-6;
const float THETA_EPS = 1e-6;
const float PI = 3.14159265359;
const float CARTESIAN_SWITCH_RADIUS = 0.2; // Radius around Z-axis (R_xy = sqrt(x^2 + y^2))

// --- RK4 STRUCTS ---
struct Ray {
    float x, y, z;
    float r, theta, phi;
    float dr, dtheta, dphi;
    float E, L;
};

// --- RK4 LOGIC ---
Ray initRay(vec3 pos, vec3 dir) {
    vec3 rel = pos - params.black_hole_position;

    Ray ray;
    ray.x = rel.x;
    ray.y = rel.y;
    ray.z = rel.z;
    ray.r = length(rel);

    ray.theta = acos(clamp(rel.z / max(ray.r, EPS), -1.0, 1.0));
    ray.phi = atan(rel.y, rel.x);

    float dx = dir.x;
    float dy = dir.y;
    float dz = dir.z;

    // --- NEW: Clamp theta for robust trig calculations (THETA_EPS = 1e-6) ---

    float theta_clamped = clamp(ray.theta, THETA_EPS, PI - THETA_EPS);

    float st = sin(theta_clamped); // Use clamped st for safety
    float ct = cos(theta_clamped); // Use clamped ct
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);

    // Old line: st = max(st, 1e-4); // Delete this line

    ray.dr = st * cp * dx + st * sp * dy + ct * dz;
    ray.dtheta = (ct * cp * dx + ct * sp * dy - st * dz) / max(ray.r, EPS);

    // CRITICAL: dphi calculation now uses the safe, non-zero 'st'
    ray.dphi = (-sp * dx + cp * dy) / (max(ray.r, EPS) * st);

    ray.L = ray.r * ray.r * st * ray.dphi; // Use safe 'st' here
    float f = 1.0 - params.schwarzschild_radius / max(ray.r, EPS);
    float dt_dL = sqrt((ray.dr * ray.dr) / max(f, EPS) +
                ray.r * ray.r * (ray.dtheta * ray.dtheta +
                        st * st * ray.dphi * ray.dphi));
    ray.E = f * dt_dL;

    return ray;
}

void geodesicRHS(Ray ray, out vec3 d1, out vec3 d2) {
    float r = ray.r;
    float theta = ray.theta;
    float dr = ray.dr;
    float dtheta = ray.dtheta;
    float dphi = ray.dphi;

    // --- FINAL FIX: Use a larger Epsilon for the singularity guard ---
    float theta_clamped = clamp(theta, THETA_EPS, PI - THETA_EPS);

    float f = 1.0 - params.schwarzschild_radius / max(r, EPS);
    float dt_dL = ray.E / max(f, EPS);

    // Use the clamped angle to derive the trigonometric functions
    float st = sin(theta_clamped); // sin(theta) - ALWAYS > 0
    float ct = cos(theta_clamped); // cos(theta)

    d1 = vec3(dr, dtheta, dphi);

    // d^2r/dL^2 (Radial Acceleration) - Unchanged
    d2.x = -(params.schwarzschild_radius / (2.0 * r * r)) * f * dt_dL * dt_dL
            + (params.schwarzschild_radius / (2.0 * r * r * max(f, EPS))) * dr * dr
            + r * (dtheta * dtheta + st * st * dphi * dphi);

    // d^2theta/dL^2 (Polar Acceleration) - Unchanged
    d2.y = -2.0 * dr * dtheta / r + st * ct * dphi * dphi;

    // d^2phi/dL^2: The singularity is here: -2 * (ct / st) * dtheta * dphi
    // --- POLAR STABILIZATION: The key modification is here ---

    // We explicitly calculate the unstable term (Gamma^phi_theta_phi):
    float gamma_term = ct / max(st, 1e-6); // Use a safety max for sin(theta)

    // Apply a smooth step or clamp to the gamma term near the poles.
    // This is the Theta-Averaging concept: damping the derivative near the pole.
    // If we are extremely close to the pole, force the angular contribution to zero.
    float stability_factor = 1.;
    // if (st < .1) {
    //     // Use a smooth step to ramp down the unstable term as we approach the pole (st=0)
    //     stability_factor = smoothstep(0.0, .1, st);
    // }

    // Final d^2phi/dL^2:
    d2.z = -2.0 * dr * dphi / r - 2.0 * gamma_term * dtheta * dphi * stability_factor;

    // --- ORIGINAL NEW STABILIZATION (Keep this as a final failsafe) ---
    // If the ray is extremely close to the axis, the change in phi is negligible.
    if (st < 1e-3) {
        d2.z = 0.0;
        // Also stabilize dtheta to prevent the ray from "orbiting" the pole
        d2.y = -2.0 * dr * dtheta / r;
    }
}

// --- CARTESIAN RK LOGIC ---
vec3 getCartesianAcceleration(Ray ray, float r_val, vec3 pos_cart) {
    float Rs = params.schwarzschild_radius;
    float f = 1.0 - Rs / max(r_val, EPS);

    // E and L are conserved and are *correctly* calculated during initRay and RK steps.
    // They are defined by the (r, theta, phi) state and must be preserved.

    // Calculate dr/dL, the radial velocity magnitude, from the Cartesian components
    // (This is the dot product of the position vector (pos_cart) and the velocity vector
    //  represented by (ray.dr, ray.dtheta, ray.dphi) transformed to Cartesian velocity,
    //  but since dX/dL is easier to use, we calculate the dot product of pos and dX/dL)

    // Convert current angular derivatives to Cartesian velocity (dX/dL, dY/dL, dZ/dL)
    // To do this properly, we need the initial Cartesian velocity dX/dL, dY/dL, dZ/dL.
    // Since we don't store it, we use the simpler radial acceleration formula:

    // The radial part of the acceleration (d^2r/dL^2) from the spherical geodesic equation:
    // This value is computed inside geodesicRHS in d2.x
    // We will re-calculate it here using *current* spherical state (r, dr, dtheta, dphi)

    float st = sin(ray.theta);
    float dr = ray.dr;
    float dtheta = ray.dtheta;
    float dphi = ray.dphi;
    float dt_dL = ray.E / max(f, EPS);

    float acc_r = -(Rs / (2.0 * r_val * r_val)) * f * dt_dL * dt_dL
            + (Rs / (2.0 * r_val * r_val * max(f, EPS))) * dr * dr
            + r_val * (dtheta * dtheta + st * st * dphi * dphi);

    // The vector acceleration is purely radial: a = acc_r * (pos / r)
    return acc_r * normalize(pos_cart);
}
// --- CARTESIAN RK LOGIC ---
// Helper function to convert spherical derivatives (dr, dtheta, dphi) to Cartesian velocity (dX/dL, dY/dL, dZ/dL)
// The Jacobian transformation J * (dr, dtheta, dphi)
vec3 getCartesianVelocity(Ray ray) {
    float st = sin(ray.theta);
    float ct = cos(ray.theta);
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);
    float r = ray.r;

    // dX/dL
    float dX_dL = st * cp * ray.dr + r * ct * cp * ray.dtheta - r * st * sp * ray.dphi;
    // dY/dL
    float dY_dL = st * sp * ray.dr + r * ct * sp * ray.dtheta + r * st * cp * ray.dphi;
    // dZ/dL
    float dZ_dL = ct * ray.dr - r * st * ray.dtheta;

    return vec3(dX_dL, dY_dL, dZ_dL);
}
void rk4Step(inout Ray ray, float dL) {
    Ray r_temp;
    vec3 k1a, k1b, k2a, k2b, k3a, k3b, k4a, k4b;

    geodesicRHS(ray, k1a, k1b);

    r_temp = ray;
    r_temp.r += 0.5 * dL * k1a.x;
    r_temp.theta += 0.5 * dL * k1a.y;
    r_temp.phi += 0.5 * dL * k1a.z;
    r_temp.dr += 0.5 * dL * k1b.x;
    r_temp.dtheta += 0.5 * dL * k1b.y;
    r_temp.dphi += 0.5 * dL * k1b.z;
    geodesicRHS(r_temp, k2a, k2b);

    r_temp = ray;
    r_temp.r += 0.5 * dL * k2a.x;
    r_temp.theta += 0.5 * dL * k2a.y;
    r_temp.phi += 0.5 * dL * k2a.z;
    r_temp.dr += 0.5 * dL * k2b.x;
    r_temp.dtheta += 0.5 * dL * k2b.y;
    r_temp.dphi += 0.5 * dL * k2b.z;
    geodesicRHS(r_temp, k3a, k3b);

    r_temp = ray;
    r_temp.r += dL * k3a.x;
    r_temp.theta += dL * k3a.y;
    r_temp.phi += dL * k3a.z;
    r_temp.dr += dL * k3b.x;
    r_temp.dtheta += dL * k3b.y;
    r_temp.dphi += dL * k3b.z;
    geodesicRHS(r_temp, k4a, k4b);

    ray.r += dL * (k1a.x + 2.0 * k2a.x + 2.0 * k3a.x + k4a.x) / 6.0;
    ray.theta += dL * (k1a.y + 2.0 * k2a.y + 2.0 * k3a.y + k4a.y) / 6.0;
    ray.phi += dL * (k1a.z + 2.0 * k2a.z + 2.0 * k3a.z + k4a.z) / 6.0;
    ray.dr += dL * (k1b.x + 2.0 * k2b.x + 2.0 * k3b.x + k4b.x) / 6.0;
    ray.dtheta += dL * (k1b.y + 2.0 * k2b.y + 2.0 * k3b.y + k4b.y) / 6.0;
    ray.dphi += dL * (k1b.z + 2.0 * k2b.z + 2.0 * k3b.z + k4b.z) / 6.0;

    ray.theta = clamp(ray.theta, 0.0, PI);
    ray.r = max(ray.r, EPS);

    float st = sin(ray.theta);
    float ct = cos(ray.theta);
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);

    ray.x = ray.r * st * cp;
    ray.y = ray.r * st * sp;
    ray.z = ray.r * ct;
}

// New RK2 (Midpoint Method) Step
void rk2Step(inout Ray ray, float dL) {
    // Current Cartesian state
    vec3 pos_cart = vec3(ray.x, ray.y, ray.z);
    float r_val = ray.r;
    float R_xy = length(pos_cart.xy); // Radial distance from Z-axis

    // If we are near the pole, integrate in Cartesian space
    if (R_xy < CARTESIAN_SWITCH_RADIUS) {

        // 1. K1 (Current State)
        vec3 V_k1 = getCartesianVelocity(ray);
        vec3 A_k1 = getCartesianAcceleration(ray, r_val, pos_cart);

        // 2. Midpoint State (temp)
        Ray r_mid = ray;

        // Propagate the position and velocity to the midpoint (0.5 * dL)
        vec3 P_mid = pos_cart + V_k1 * (0.5 * dL);
        vec3 V_mid = V_k1 + A_k1 * (0.5 * dL); // Velocity at midpoint

        // Update the temporary Ray struct with midpoint Cartesian coordinates
        r_mid.x = P_mid.x;
        r_mid.y = P_mid.y;
        r_mid.z = P_mid.z;

        // Reconstruct midpoint spherical coordinates (needed for acceleration calculation)
        float r_mid_val = length(P_mid);
        r_mid.r = r_mid_val;
        r_mid.theta = acos(clamp(P_mid.z / max(r_mid_val, EPS), -1.0, 1.0));
        r_mid.phi = atan(P_mid.y, P_mid.x);

        // 3. K2 (Midpoint Acceleration)
        vec3 A_k2 = getCartesianAcceleration(r_mid, r_mid_val, P_mid);

        // 4. Final Step (Proper RK2 Update)
        // P_new = P_old + V_mid * dL (using V_mid, which is V_k1 + A_k1 * 0.5 * dL)
        pos_cart = pos_cart + V_mid * dL;

        // V_new = V_old + A_k2 * dL (using A_k2 from the midpoint)
        vec3 V_new = V_k1 + A_k2 * dL; // <<< Declared V_new here!

        // --- UPDATE RAY STATE ---
        ray.x = pos_cart.x;
        ray.y = pos_cart.y;
        ray.z = pos_cart.z;

        // Reconstruct spherical coordinates
        r_val = length(pos_cart);
        ray.r = r_val;
        ray.theta = acos(clamp(pos_cart.z / max(r_val, EPS), -1.0, 1.0));
        ray.phi = atan(pos_cart.y, pos_cart.x);

        // Reconstruct spherical velocities (V_new -> (dr, dtheta, dphi))
        // This projection is critical for a smooth transition back to the spherical solver.
        float st = sin(ray.theta);
        float ct = cos(ray.theta);
        float sp = sin(ray.phi);
        float cp = cos(ray.phi);

        // Spherical basis vectors in Cartesian space:
        vec3 e_r = normalize(pos_cart);
        vec3 e_theta = vec3(ct * cp, ct * sp, -st);
        // Ensure e_phi is orthogonal to the Z-axis (pos_cart.xy) near the pole
        vec3 e_phi = vec3(-sp, cp, 0.0);

        // Projection:
        ray.dr = dot(V_new, e_r);
        // Note: dtheta = (V_new . e_theta) / r
        ray.dtheta = dot(V_new, e_theta) / max(ray.r, EPS);
        // Note: dphi = (V_new . e_phi) / (r * sin(theta)) - Use clamped theta (st)
        // If 'st' is very small, we must stabilize 'dphi'.
        ray.dphi = dot(V_new, e_phi) / (max(ray.r, EPS) * max(st, 1e-4));
    } else {
        // --- SPHERICAL INTEGRATION (Original Code) ---
        // ... (Spherical RK2 step remains unchanged) ...
        Ray r_temp;
        vec3 k1a, k1b, k2a, k2b;

        geodesicRHS(ray, k1a, k1b);

        r_temp = ray;
        r_temp.r += 0.5 * dL * k1a.x;
        r_temp.theta += 0.5 * dL * k1a.y;
        r_temp.phi += 0.5 * dL * k1a.z;
        r_temp.dr += 0.5 * dL * k1b.x;
        r_temp.dtheta += 0.5 * dL * k1b.y;
        r_temp.dphi += 0.5 * dL * k1b.z;
        geodesicRHS(r_temp, k2a, k2b);

        ray.r += dL * k2a.x;
        ray.theta += dL * k2a.y;
        ray.phi += dL * k2a.z;
        ray.dr += dL * k2b.x;
        ray.dtheta += dL * k2b.y;
        ray.dphi += dL * k2b.z;

        // Final Spherical to Cartesian Conversion (with clamping)
        ray.theta = clamp(ray.theta, 0.0, PI);
        ray.r = max(ray.r, EPS);

        float theta_clamped = clamp(ray.theta, THETA_EPS, PI - THETA_EPS);

        float st = sin(theta_clamped);
        float ct = cos(theta_clamped);
        float sp = sin(ray.phi);
        float cp = cos(ray.phi);

        ray.x = ray.r * st * cp;
        ray.y = ray.r * st * sp;
        ray.z = ray.r * ct;
    }
}
float getAdaptiveStepSize(float r) {
    float normalized_r = r / params.schwarzschild_radius;
    if (normalized_r < 2.0) return params.step_size * 0.01;
    if (normalized_r < 5.0) return params.step_size * 0.1;
    if (normalized_r < 20.0) return params.step_size * 0.5;
    return params.step_size;
}

// --- DISC (VOLUMETRIC) ---
// R = disc_outer_radius, R0 = disc_inner_radius, fade is derived from R/R0
float accretion_density(float l, float phi, float y, float R, float R0) {
    // 1. Azimuthal/Angle (U) Coordinate for Noise:
    // phi_norm maps [-PI, PI] to [0, 1] for a continuous wrap-around.
    float phi_norm = (phi / (2.0 * PI)) + 0.5;

    // 2. Radial (V) Coordinate for Noise:
    // Base V-coordinate uses a logarithmic stretch of the radius (l).
    float noise_base_v = log(max(l, 1.0)) * 1.5;

    // **NEW RADIAL VARIATION LOGIC:**
    // Use the base U (angle + time) to slightly offset the V-coordinate.
    // This makes the 'radial' distance sampled from the noise texture vary
    // based on the angle (phi), breaking the perfect radial symmetry.
    float angle_time_coord = phi_norm + params.time * 0.1;
    float radial_offset = texture(noise_sampler, vec2(angle_time_coord, 0.5)).r * 0.2; // Sample U-axis for a shifting offset

    // The final V-coordinate is the stretched radius (noise_base_v)
    // plus a small offset that varies continuously around the disk (radial_offset).
    float noise_v_coord = noise_base_v + radial_offset;

    // 3. Noise Lookup:
    // U is the angle + time. V is the radius + angular offset.
    float n = texture(noise_sampler, vec2(angle_time_coord, noise_v_coord * 0.25)).r; // Scale V down for a softer pattern

    // Original radial falloff (d0):
    // Normalized distance from inner edge (l-R0) and falloff near outer edge (1 - l/R)
    float fade = (R - R0) * 0.5; // Use half the width for the 'fade' parameter
    float d0 = pow(max(1.0 - l / R, 0.0) * clamp((l - R0) / fade + 1.0, 0.0, 1.0), 1.5);

    // Gaussian falloff along the Y-axis (thickness)
    return d0 * exp(-y * y * (400.0 / (params.disc_thickness * params.disc_thickness))) * 10.0 * (n + max(0.0, n - 0.65) * 1.5) * 1.3;
}

// New disc volume rendering function
vec3 renderDiscVolume(Ray r_start, Ray r_end, float ray_t) {
    if (params.enable_disc < 0.5) return vec3(0.0);

    vec3 color_accum = vec3(0.0);
    float alpha_accum = 0.0;

    const int steps = 10; // Sub-steps per geodesic step
    float dl_sub = ray_t / float(steps);

    for (int j = 0; j < steps; ++j) {
        float frac = (float(j) + 0.5) / float(steps);
        // Approximate position between geodesic steps
        vec3 p = mix(vec3(r_start.x, r_start.y, r_start.z), vec3(r_end.x, r_end.y, r_end.z), frac);

        float r = length(p.xz);

        // Skip points outside the disc's bounds
        if (r < params.disc_inner_radius || r > params.disc_outer_radius) continue;
        if (abs(p.y) > params.disc_thickness) continue;

        float density = accretion_density(r, atan(p.y, p.x), p.y, params.disc_outer_radius, params.disc_inner_radius);

        // Simplified absorption model (Beer-Lambert law)
        float opacity = 1.0 - exp(-density * dl_sub * params.disc_emission_strength);

        // Interpolate color based on radius
        float r_norm = (r - params.disc_inner_radius) / max(params.disc_outer_radius - params.disc_inner_radius, EPS);
        vec3 disc_color = mix(params.disc_inner_color.rgb, params.disc_outer_color.rgb, clamp(r_norm, 0.0, 1.0));

        // Compositing: Over operator (alpha blending)
        color_accum += disc_color * opacity * (1.0 - alpha_accum);
        alpha_accum += opacity * (1.0 - alpha_accum);

        if (alpha_accum > 0.99) break; // Optimization
    }
    return color_accum;
}

// --- GRID ---
float calculateWarpedGridY(float x, float z) {
    float dx = x - params.black_hole_position.x;
    float dz = z - params.black_hole_position.z;
    float dist = sqrt(dx * dx + dz * dz);

    if (dist > params.schwarzschild_radius) {
        return 2.0 * sqrt(params.schwarzschild_radius * (dist - params.schwarzschild_radius)) - params.grid_warp_offset;
    }
    return 2.0 * params.schwarzschild_radius - params.grid_warp_offset;
}

bool isOnGridLine(vec2 xz, out float strength) {
    float xMod = mod(xz.x + params.grid_range, params.grid_spacing);
    float yMod = mod(xz.y + params.grid_range, params.grid_spacing);
    float distX = min(xMod, params.grid_spacing - xMod);
    float distY = min(yMod, params.grid_spacing - yMod);
    float minDist = min(distX, distY);

    if (minDist < params.grid_line_thickness) {
        strength = step(minDist, params.grid_line_thickness * 0.99);
        return true;
    }
    return false;
}

bool checkGridIntersectionStraightRay(vec3 origin, vec3 dir, out float gridStrength) {
    if (params.show_grid < 0.5) return false;

    float tNear = 0.0;
    float tFar = length(origin) + params.grid_range; // Simple far plane
    const int samples = 128;

    float prevY = origin.y - calculateWarpedGridY(origin.x, origin.z);

    for (int i = 1; i <= samples; ++i) {
        float tf = float(i) / float(samples);
        float t = mix(tNear, tFar, tf);
        vec3 p = origin + dir * t;

        float distXZ = length(p.xz);
        if (distXZ > params.grid_range || distXZ < params.schwarzschild_radius * 1.01) continue;

        float yNow = p.y - calculateWarpedGridY(p.x, p.z);

        if (prevY * yNow <= 0.0) {
            float frac = abs(prevY) / (abs(prevY) + abs(yNow) + 1e-6);
            vec3 hit = mix(p, origin + dir * (t - (tFar - tNear) / float(samples)), frac);

            float lineStr;
            if (isOnGridLine(hit.xz, lineStr)) {
                float fade = 1.0 - smoothstep(params.grid_range * 0.9, params.grid_range, length(hit.xz));
                gridStrength = params.grid_alpha * lineStr * fade;
                return true;
            }
        }
        prevY = yNow;
    }
    return false;
}

// --- MAIN ---
void main() {
    ivec2 pixel_coords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 res = ivec2(params.resolution);
    if (pixel_coords.x >= res.x || pixel_coords.y >= res.y) return;

    // --- CAMERA LOGIC ---
    vec3 forward = normalize(params.camera_target - params.camera_position);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);

    vec2 uv = (vec2(pixel_coords) + 0.5) / vec2(res);
    uv = uv * 2.0 - 1.0;
    uv.x *= float(res.x) / float(res.y);
    float tan_fov = tan(radians(params.camera_fov) * 0.5);
    uv *= tan_fov;

    vec3 ray_dir = normalize(uv.x * right - uv.y * up + forward);
    Ray ray = initRay(params.camera_position, ray_dir);

    vec3 prev_pos_cart = vec3(ray.x, ray.y, ray.z);
    vec3 total_disc_color = vec3(0.0);
    float total_disc_alpha = 0.0;
    vec3 color_out = vec3(0.05, 0.05, 0.08); // Background color

    bool hitBH = false;
    bool straightHitGrid = false;
    float straightGridStrength = 0.0;

    // --- STRAIGHT RAY GRID CHECK ---
    if (params.show_grid > 0.5) {
        straightHitGrid = checkGridIntersectionStraightRay(params.camera_position, ray_dir, straightGridStrength);
    }

    // --- RAY MARCHING (Geodesic Integration) ---
    for (float i = 0.0; i < params.max_steps; i += 1.0) {
        if (ray.r <= params.schwarzschild_radius * 1.01) {
            hitBH = true;
            break;
        }

        float step_val = getAdaptiveStepSize(ray.r);
        Ray prev_ray = ray;
        rk2Step(ray, step_val); // Use RK2 for performance

        vec3 new_pos_cart = vec3(ray.x, ray.y, ray.z);

        // --- VOLUME RENDERING STEP ---
        vec3 disc_step_color = renderDiscVolume(prev_ray, ray, step_val);

        // Compositing: Assume total_disc_alpha is always small enough to not hit max
        total_disc_color += disc_step_color;

        prev_pos_cart = new_pos_cart;
        if (ray.r > params.escape_radius) break;
    }

    // --- COMPOSITING ---

    // Black Hole
    if (hitBH) {
        color_out = params.black_hole_color.rgb;
    } else {
        // Background (Skybox or Stars)
        // Map the final ray direction to UV coordinates
        vec3 final_dir = normalize(vec3(ray.x, ray.y, ray.z) - params.black_hole_position);

        // Convert 3D direction vector to 2D UV coordinates
        float phi = atan(final_dir.z, final_dir.x); // Longitude (-pi to pi)
        float theta = acos(final_dir.y); // Latitude (0 to pi)

        // Map to UV (0 to 1)
        float u = phi / (2.0 * 3.14159265) + 0.5;
        float v = theta / 3.14159265;

        // Sample the 2D texture
        vec3 sky_color = texture(skybox_sampler, vec2(u, v)).rgb;

        color_out = sky_color;

        // Spacetime Grid (Straight Ray Check)
        if (straightHitGrid) {
            color_out = mix(color_out, params.grid_color.rgb, straightGridStrength);
        }
    }

    // 4. Accretion Disc (Blended over BH/Sky/Grid)
    // The disc is drawn over everything else
    color_out = total_disc_color + color_out; // Additive blending for emission

    imageStore(output_image, pixel_coords, vec4(color_out, 1.0));
}
