#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D output_image;
layout(set = 0, binding = 1) uniform sampler2D skybox_sampler; // Skybox Texture
layout(set = 0, binding = 2) uniform sampler2D noise_sampler;

// Params struct remains unchanged
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
    float nebula_radius;
    float nebula_height;
    float nebula_intensity_scale;
    float _nebula_step_size_start; // Optional: If you want to control the initial step size (0.0265)

    // Block 15 (Offset 224)
    vec3 nebula_pos;
    float _pad4;
} params;

const float EPS = 1e-6;
const float THETA_EPS = 1e-6;
const float PI = 3.14159265359;
// Reduced switching radius for stability (only near the pole)
const float CARTESIAN_SWITCH_RADIUS = 0.05;

// --- RK4 STRUCTS ---
struct Ray {
    float x, y, z;
    float r, theta, phi;
    float dr, dtheta, dphi;
    float E, L;
};

// --- RK4 LOGIC ---

// initRay remains UNCHANGED (it correctly sets up initial E and L)
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

    float theta_clamped = clamp(ray.theta, THETA_EPS, PI - THETA_EPS);

    float st = sin(theta_clamped);
    float ct = cos(theta_clamped);
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);

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

// MODIFIED: Geodesic RHS with Polar Stabilization
void geodesicRHS(Ray ray, out vec3 d1, out vec3 d2) {
    float r = ray.r;
    float theta = ray.theta;
    float dr = ray.dr;
    float dtheta = ray.dtheta;
    float dphi = ray.dphi;

    // Use THETA_EPS for clamping for robust trig
    float theta_clamped = clamp(theta, THETA_EPS, PI - THETA_EPS);

    float f = 1.0 - params.schwarzschild_radius / max(r, EPS);
    float dt_dL = ray.E / max(f, EPS);

    float st = sin(theta_clamped);
    float ct = cos(theta_clamped);

    d1 = vec3(dr, dtheta, dphi);

    // d^2r/dL^2 (Radial Acceleration) - Unchanged
    d2.x = -(params.schwarzschild_radius / (2.0 * r * r)) * f * dt_dL * dt_dL
            + (params.schwarzschild_radius / (2.0 * r * r * max(f, EPS))) * dr * dr
            + r * (dtheta * dtheta + st * st * dphi * dphi);

    // d^2theta/dL^2 (Polar Acceleration) - Unchanged in the general case
    d2.y = -2.0 * dr * dtheta / r + st * ct * dphi * dphi;

    // --- POLAR STABILIZATION: The hybrid fix for d^2phi/dL^2 ---

    float R_xy = r * st; // Distance from Z-axis (R_xy = sqrt(x^2 + y^2))

    if (R_xy < CARTESIAN_SWITCH_RADIUS) {
        // When extremely close to the pole, the angular momentum (L) is dominated by
        // the ray's initial angular velocity. Since L is conserved, dL/dL=0.
        // We force d^2phi/dL^2 to zero to prevent the division by zero from st=0.
        d2.z = 0.0;

        // Critically, we must also stabilize d^2theta/dL^2 near the pole:
        // By removing the centrifugal term, we prevent "orbiting" the pole.
        d2.y = -2.0 * dr * dtheta / r; // Removed st * ct * dphi * dphi
    } else {
        // Spherical calculation (standard):
        float gamma_term = ct / max(st, 1e-6);
        d2.z = -2.0 * dr * dphi / r - 2.0 * gamma_term * dtheta * dphi;
    }
}

// rk4Step remains UNCHANGED (it's robust)
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

// NOTE: All CARTESIAN RK logic and rk2Step are REMOVED here.

float getAdaptiveStepSize(float r) {
    float normalized_r = r / params.schwarzschild_radius;
    if (normalized_r < 2.0) return params.step_size * 0.01;
    if (normalized_r < 5.0) return params.step_size * 0.1;
    if (normalized_r < 20.0) return params.step_size * 0.5;
    return params.step_size;
}

// --- DISC (VOLUMETRIC) ---

// accretion_density remains UNCHANGED
float accretion_density(float l, float phi, float y, float R, float R0) {
    float phi_norm = (phi / (2.0 * PI)) + 0.5;

    float noise_base_v = log(max(l, 1.0)) * 1.5;

    float angle_time_coord = phi_norm + params.time * 0.1;
    float radial_offset = texture(noise_sampler, vec2(angle_time_coord, 0.5)).r * 0.2;

    float noise_v_coord = noise_base_v + radial_offset;

    float n = texture(noise_sampler, vec2(angle_time_coord, noise_v_coord * 0.25)).r;

    float fade = (R - R0) * 0.5;
    float d0 = pow(max(1.0 - l / R, 0.0) * clamp((l - R0) / fade + 1.0, 0.0, 1.0), 1.5);

    return d0 * exp(-y * y * (400.0 / (params.disc_thickness * params.disc_thickness))) * 10.0 * (n + max(0.0, n - 0.65) * 1.5) * 1.3;
}

// renderDiscVolume remains UNCHANGED
vec3 renderDiscVolume(Ray r_start, Ray r_end, float ray_t) {
    if (params.enable_disc < 0.5) return vec3(0.0);

    vec3 color_accum = vec3(0.0);
    float alpha_accum = 0.0;

    const int steps = 10;
    float dl_sub = ray_t / float(steps);

    for (int j = 0; j < steps; ++j) {
        float frac = (float(j) + 0.5) / float(steps);
        vec3 p = mix(vec3(r_start.x, r_start.y, r_start.z), vec3(r_end.x, r_end.y, r_end.z), frac);

        float r = length(p.xz);

        if (r < params.disc_inner_radius || r > params.disc_outer_radius) continue;
        if (abs(p.y) > params.disc_thickness) continue;

        // NOTE: atan(p.y, p.x) is incorrect here for the phi angle in the disc plane,
        // it should be atan(p.z, p.x) if disc is in the XZ plane,
        // or p.xz coordinates if the disc is in the XZ plane
        float density = accretion_density(r, atan(p.x, p.z), p.y, params.disc_outer_radius, params.disc_inner_radius);

        // Simplified absorption model (Beer-Lambert law)
        float opacity = 1.0 - exp(-density * dl_sub * params.disc_emission_strength);

        float r_norm = (r - params.disc_inner_radius) / max(params.disc_outer_radius - params.disc_inner_radius, EPS);
        vec3 disc_color = mix(params.disc_inner_color.rgb, params.disc_outer_color.rgb, clamp(r_norm, 0.0, 1.0));

        color_accum += disc_color * opacity * (1.0 - alpha_accum);
        alpha_accum += opacity * (1.0 - alpha_accum);

        if (alpha_accum > 0.99) break;
    }
    return color_accum;
}

// --- GRID ---

// All grid functions remain UNCHANGED
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
    float tFar = length(origin) + params.grid_range;
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
// --- Procedural Simplex Noise (snoise) for 3D Texture Replacement ---
// A common 3D Simplex noise function
// The actual implementation details are long, but here is a placeholder/summary
// You must include the full function code here.

vec4 permute(vec4 x) {
    return mod(((x * 34.0) + 1.0) * x, 289.0);
}

vec4 taylorInvSqrt(vec4 r) {
    return 1.79284291400159 - 0.85373472095314 * r;
}

// [0-1]
float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    // First corner
    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    // Other corners
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    //   x0 = x0 - 0.0 + 0.0 * C.xxx;
    //   x1 = x0 - i1  + 1.0 * C.xxx;
    //   x2 = x0 - i2  + 2.0 * C.xxx;
    //   x3 = x0 - 1.0 + 3.0 * C.xxx;
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
    vec3 x3 = x0 - D.yyy; // 1.0 - 3.0*C.x = 0.5 = D.y

    // Permutations
    i = mod(i, 289.0);
    vec4 p = permute(permute(permute(
                    i.z + vec4(0.0, i1.z, i2.z, 1.0))
                    + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    // Gradients: 7x7 points uniformly over a square, mapped onto an octahedron.
    // The ring size of 17*17 = 289 is passed to *p below.
    vec4 j4 = 4.0 * mod(mod(p, 34.0), 13.0) - 13.0;
    vec4 j = mod(mod(p, 34.0), 13.0) - 6.5;

    vec4 x4 = abs(j4);
    vec4 z = 1.0 - step(x4, j);
    vec4 jz = (j4 + (j4 - x4) / 4.0) * z;

    vec4 gr = p.wzyx * 2.0 + jz.xzxz; // 2 * grad
    vec4 xg = (gr - D.w) + D.yyzz; // grad - 4 * ceil(grad/4)

    // Gradients
    vec3 n0 = vec3(xg.x, xg.y, gr.x);
    vec3 n1 = vec3(xg.z, xg.w, gr.y);
    vec3 n2 = vec3(xg.w, xg.z, gr.z);
    vec3 n3 = vec3(xg.z, xg.w, gr.w);

    // Normalise gradients
    vec4 t = taylorInvSqrt(vec4(dot(n0, n0), dot(n1, n1), dot(n2, n2), dot(n3, n3)));
    n0 *= t.x;
    n1 *= t.y;
    n2 *= t.z;
    n3 *= t.w;

    // The domain expansion makes the maximum value of the polynomial 2.0
    // and the minimum -2.0. So scale and shift to the range [0, 1].
    // Attenuation
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    float noise = 0.5 + 0.5 * dot(m * m, vec4(dot(n0, x0), dot(n1, x1), dot(n2, x2), dot(n3, x3)));
    return 0.5;
}
// New function to calculate emission and transmittance for a single geodesic step
vec4 nebulaStep(vec3 lp, float step_size, float et) {
    float NEBULA_RADIUS = params.nebula_radius;
    float NEBULA_HEIGHT = params.nebula_height;

    float l = length(lp.xz);
    if (l > NEBULA_RADIUS || abs(lp.y) > NEBULA_HEIGHT * 0.5) {
        return vec4(0.0, 0.0, 0.0, 0.0); // Outside bounds
    }

    // --- 1. Noise Sampling (Approximation of Original Textures) ---
    // n: Placeholder for the 2D noise (using snoise on XZ plane)
    // float n = clamp(snoise(lp.xz * 0.35 + et * 0.5), 0.0, 1.0);
    float n = clamp(snoise(vec3(lp.xz * 0.35, 0.0) + et * 0.5), 0.0, 1.0);

    // n3: Time-varying, lower frequency noise (approx. n3 from original)
    vec3 n3_coord = lp * 1.5 + vec3(et, 0.0, 0.0) * 5.0;
    float n3 = snoise(n3_coord);

    // n3o: High-frequency spatial noise (approx. n3o from original)
    float n3o = snoise(lp * 5.0);

    // --- 2. Density Calculations (Lines 34-39) ---
    // We use a simplified version of the spiral distortion for performance/simplicity
    vec3 nlp = lp + 0.12 * (l + 1.0) * (n - 0.5) * 0.5;
    float nl = length(nlp.xz);
    float r = nl * 1.85 - 1.2;
    float t = mod(atan(nlp.z, nlp.x), PI);
    float diff = abs(mod((r - t + 0.5 * PI), (PI)) - 0.5 * PI); // distance from spiral

    // Helper variables
    float l2 = l * l;
    float lpy2 = lp.y * lp.y;
    float factor = (1.0 + tanh(3.0 * r)) * 0.6 * max(0.0, 0.42 - pow(diff, 2.0));

    // Density components (from lines 36-39)
    float spiral_density = (0.5 * max(0.0, 1.15 - pow(diff, 0.15)) + factor) * max(0.0, 1.0 - sqrt(0.045 * l2 + 24.0 * lpy2)) * (1.5 * n + 0.55) * 0.4;
    float core_density = 40.0 * pow(max(0.0, 0.45 - sqrt(0.3 * lp.x * lp.x + lp.z * lp.z + 3.0 * lp.y * lp.y)), 2.0) + 5.0 * pow(max(0.0, 0.65 - sqrt(0.45 * lp.x * lp.x + lp.z * lp.z + 4.0 * lpy2)), 1.5) * (n + 0.5);
    float particle_density = (0.3 * max(0.0, 1.25 - pow(diff, 0.15)) + factor) * max(0.0, 1.0 - pow(0.045 * l2 + 16.0 * lpy2, 4.0)) * (1.0 - abs(4.0 * lp.y)) * 400.0;
    float dust_density = pow(max(0.0, n3 - 0.2), 1.5) * particle_density;
    float gas_density = pow(max(0.0, abs(n3o - 0.55) - 0.12), 2.0) * particle_density * 1.2 * max(0.0, 1.0 - 0.35 * diff - pow(0.2 * l, 0.4)) * (0.5 - abs(2.5 * lp.y));

    // --- 3. Accumulation / Emission (Lines 41-42) ---

    float total_density = spiral_density + core_density + dust_density + gas_density;

    // Use a small constant for proximity since distance(campos, lp) is not easily available here
    // In the compute shader, we are always tracing from a position. We'll use 1.0 as a proxy.
    // float prox = tanh(distance(campos, lp) * 0.4);
    float prox = 1.0;

    // Opacity/Transmittance (T in the original shader)
    float opacity = 1.0 - exp(-(total_density) * prox * step_size * 0.2);

    // Star Color (same mix as original, but using 'l' as radius)
    vec3 star_col = mix(vec3(0.45, 0.6, 1.0), vec3(1.0, 0.5, 0.2), pow(max(0.0, 1.0 - 0.2 * l), 1.8));

    // Calculate transmittance for this step (how much light gets through)
    float step_transmittance = exp(-(total_density) * prox * step_size * 0.2);

    // Calculate emission (light emitted by this volume segment)
    vec3 emission = prox * (star_col * vec3(spiral_density * 12.0 + core_density * 6.0 + vec3(0.7, 0.4, 0.3) * dust_density * 0.02) + vec3(1.0, 0.3, 0.3) * gas_density * 8.0) * step_size * 2.0;

    // Apply intensity scale
    emission *= params.nebula_intensity_scale;

    // Return emission and the transmittance (NOT opacity)
    return vec4(emission, step_transmittance) * 0.5 + 0.5;
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

    // --- New Nebula Accumulators ---
    vec3 total_nebula_color = vec3(0.0);
    float ray_transmittance = 1.0; // T starts at 1.0 (fully transparent)
    float et = params.time * 0.05; // Time coordinate for noise

    bool hitBH = false;
    bool straightHitGrid = false;
    float straightGridStrength = 0.0;

    // --- STRAIGHT RAY GRID CHECK ---
    if (params.show_grid > 0.5) {
        straightHitGrid = checkGridIntersectionStraightRay(params.camera_position, ray_dir, straightGridStrength);
    }

    // --- RAY MARCHING (Geodesic Integration) ---
    for (float i = 0.0; i < params.max_steps; i += 1.0) {
        if (ray.r <= params.schwarzschild_radius * 1.2) {
            hitBH = true;
            break;
        }

        float step_val = getAdaptiveStepSize(ray.r);
        Ray prev_ray = ray;
        rk4Step(ray, step_val); // Switched to rk4Step for better accuracy/stability

        vec3 new_pos_cart = vec3(ray.x, ray.y, ray.z);

        // --- VOLUME RENDERING STEP ---
        vec3 disc_step_color = renderDiscVolume(prev_ray, ray, step_val);

        total_disc_color += disc_step_color;

        // --- VOLUME RENDERING STEP (Nebula) ---
            vec3 mid_pos = mix(prev_pos_cart, new_pos_cart, 0.5);
            vec3 pos_rel_bh = mid_pos - params.black_hole_position;
        
            // Apply nebula position offset to get local galaxy coordinates (lp)
            vec3 lp = pos_rel_bh - params.nebula_pos;
            
            // Use nebula radius/height parameters
            float NEBULA_RADIUS = params.nebula_radius;
            float NEBULA_HEIGHT = params.nebula_height;
        
            float l = length(lp.xz);
            if (l <= NEBULA_RADIUS && abs(lp.y) <= NEBULA_HEIGHT * 0.5) {
                // --- 1. COORDINATE PORTING (Exact Match to Spatial Shader) ---
                float ang = atan(lp.z, lp.x);
                float et = params.time * 0.05;
        
                // 2D polar noise texture sample (Using provided 2D noise sampler)
                float n = clamp(-max(0.0, 0.8 - l) + texture(noise_sampler, vec2(ang / (2.0 * PI) + et * 0.5, l * 0.35)).r, 0.0, 1.0);
        
                // 3D polar noise texture sample (Need to use the Simplex noise since no 3D texture is bound)
                // NOTE: The original shader used texture(noise3D, vec3(..., lp.y, log(l * 5.0))).r;
                // The compute shader must use the snoise placeholder since a 3D texture is not available.
                // We substitute the texture lookup with the snoise(lp * factor) approximation from the compute shader's prelude.
                vec3 n3_coord_polar = vec3(1.5 * ang / PI + et, lp.y, log(max(l * 5.0, 0.01)));
                float n3 = snoise(n3_coord_polar);
                
                // 3D cartesian noise texture sample
                float ct = cos(et * 1.5), st = sin(et * 1.5);
                vec3 n3o_coord_cart = vec3(lp.x * ct - lp.z * st, lp.y, lp.x * st + lp.z * ct) * 0.5;
                float n3o = snoise(n3o_coord_cart); // Using snoise as placeholder for texture3D
        
                // --- 2. DENSITY & COLOR CALCULATION (Exact Match) ---
                vec3 nlp = lp + 0.12 * (l + 1.0) * (n - 0.5) * 0.5;
                float nl = length(nlp.xz);
                float r_density = nl * 1.85 - 1.2; // Renamed 'r' to 'r_density' to avoid collision with Ray.r
                float t = mod(atan(nlp.z, nlp.x), PI);
                float diff = abs(mod((r_density - t + 0.5 * PI), (PI)) - 0.5 * PI); 
        
                float l2 = l * l;
                float lpy2 = lp.y * lp.y;
                float factor = (1.0 + tanh(3.0 * r_density)) * 0.6 * max(0.0, 0.42 - pow(diff, 2.0));
        
                float spiral_density = (0.5 * max(0.0, 1.15 - pow(diff, 0.15)) + factor) * max(0.0, 1.0 - sqrt(0.045 * l2 + 24.0 * lpy2)) * (1.5 * n + 0.55) * 0.4;
                float core_density = 40.0 * pow(max(0.0, 0.45 - sqrt(0.3 * lp.x * lp.x + lp.z * lp.z + 3.0 * lp.y * lp.y)), 2.0) + 5.0 * pow(max(0.0, 0.65 - sqrt(0.45 * lp.x * lp.x + lp.z * lp.z + 4.0 * lpy2)), 1.5) * (n + 0.5);
                float particle_density = (0.3 * max(0.0, 1.25 - pow(diff, 0.15)) + factor) * max(0.0, 1.0 - pow(0.045 * l2 + 16.0 * lpy2, 4.0)) * (1.0 - abs(4.0 * lp.y)) * 400.0;
                float dust_density = pow(max(0.0, n3 - 0.2), 1.5) * particle_density;
                float gas_density = pow(max(0.0, abs(n3o - 0.55) - 0.12), 2.0) * particle_density * 1.2 * max(0.0, 1.0 - 0.35 * diff - pow(0.2 * l, 0.4)) * (0.5 - abs(2.5 * lp.y));
        
                vec3 star_col = mix(vec3(0.45, 0.6, 1.0), vec3(1.0, 0.5, 0.2), pow(max(0.0, 1.0 - 0.2 * l), 1.8));
                float total_density = spiral_density + core_density + dust_density + gas_density;
                float prox = tanh(distance(params.camera_position, mid_pos) * 0.4);
        
                // --- 3. ACCUMULATION (Correct Backwards Raytracing Order) ---
                
                // Luminosity (L): Light *emitted* from this step, attenuated by the volume *behind* it (ray_transmittance)
                vec3 emission = prox * ray_transmittance * (star_col * vec3(spiral_density * 12.0 + core_density * 6.0 + vec3(0.7, 0.4, 0.3) * dust_density * 0.02) + vec3(1.0, 0.3, 0.3) * gas_density * 8.0) * step_val * 2.0;
        
                // Transmittance (T): How much light is blocked by the volume in this step
                // T is updated *after* L is calculated, ensuring L uses the accumulated transmittance from the previous steps.
                ray_transmittance *= exp(-(total_density) * prox * step_val * 0.2);
                
                total_nebula_color += emission * params.nebula_intensity_scale;
            }

        prev_pos_cart = new_pos_cart;
        if (ray.r > params.escape_radius) break;
    }

    // --- COMPOSITING ---

    // Black Hole
    if (hitBH) {
        color_out = params.black_hole_color.rgb;
    } else {
        // Background (Skybox or Stars)
        vec3 final_dir = normalize(vec3(ray.x, ray.y, ray.z) - params.black_hole_position);

        // Convert 3D direction vector to 2D UV coordinates
        float phi = atan(final_dir.z, final_dir.x);
        float theta = acos(final_dir.y);

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

        // 1. Blend the **accumulated nebula light** over the background.
        // We multiply the background by the ray's remaining transmittance (T)
        // to simulate the light being blocked by the nebula in the foreground.

        color_out = total_nebula_color + color_out * ray_transmittance;
    }

    // 4. Accretion Disc (Blended over BH/Sky/Grid) - Additive for emission
    color_out = total_disc_color + color_out;

    imageStore(output_image, pixel_coords, vec4(color_out, 1.0));
}
