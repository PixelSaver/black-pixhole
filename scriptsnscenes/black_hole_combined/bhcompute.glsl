#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
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
const float PI = 3.14159265359;

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
    ray.x = rel.x; ray.y = rel.y; ray.z = rel.z;
    ray.r = length(rel);

    ray.theta = acos(clamp(rel.z / max(ray.r, EPS), -1.0, 1.0));
    ray.phi = atan(rel.y, rel.x);

    float dx = dir.x; float dy = dir.y; float dz = dir.z;

    float st = sin(ray.theta);
    float ct = cos(ray.theta);
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);

    st = max(st, 1e-2); // Clamp to reduce noise at poles

    ray.dr = st * cp * dx + st * sp * dy + ct * dz;
    ray.dtheta = (ct * cp * dx + ct * sp * dy - st * dz) / max(ray.r, EPS);
    ray.dphi = (-sp * dx + cp * dy) / (max(ray.r, EPS) * max(st, EPS));

    ray.L = ray.r * ray.r * max(st, EPS) * ray.dphi;
    float f = 1.0 - params.schwarzschild_radius / max(ray.r, EPS);
    float dt_dL = sqrt((ray.dr * ray.dr) / max(f, EPS) +
                       ray.r * ray.r * (ray.dtheta * ray.dtheta +
                       st * st * ray.dphi * ray.dphi));
    ray.E = f * dt_dL;

    return ray;
}

void geodesicRHS(Ray ray, out vec3 d1, out vec3 d2) {
    float r = ray.r; float theta = ray.theta;
    float dr = ray.dr; float dtheta = ray.dtheta; float dphi = ray.dphi;

    float f = 1.0 - params.schwarzschild_radius / max(r, EPS);
    float dt_dL = ray.E / max(f, EPS);
    float st = sin(theta); float ct = cos(theta);

    d1 = vec3(dr, dtheta, dphi);
    d2.x = -(params.schwarzschild_radius / (2.0 * r*r)) * f * dt_dL * dt_dL
         + (params.schwarzschild_radius / (2.0 * r*r * max(f, EPS))) * dr * dr
         + r * (dtheta*dtheta + st*st*dphi*dphi);
    d2.y = -2.0*dr*dtheta/r + st*ct*dphi*dphi;
    d2.z = -2.0*dr*dphi/r - 2.0*ct/max(st, EPS) * dtheta * dphi;
}

void rk4Step(inout Ray ray, float dL) {
    Ray r_temp;
    vec3 k1a, k1b, k2a, k2b, k3a, k3b, k4a, k4b;

    geodesicRHS(ray, k1a, k1b);

    r_temp = ray;
    r_temp.r += 0.5 * dL * k1a.x; r_temp.theta += 0.5 * dL * k1a.y; r_temp.phi += 0.5 * dL * k1a.z;
    r_temp.dr += 0.5 * dL * k1b.x; r_temp.dtheta += 0.5 * dL * k1b.y; r_temp.dphi += 0.5 * dL * k1b.z;
    geodesicRHS(r_temp, k2a, k2b);

    r_temp = ray;
    r_temp.r += 0.5 * dL * k2a.x; r_temp.theta += 0.5 * dL * k2a.y; r_temp.phi += 0.5 * dL * k2a.z;
    r_temp.dr += 0.5 * dL * k2b.x; r_temp.dtheta += 0.5 * dL * k2b.y; r_temp.dphi += 0.5 * dL * k2b.z;
    geodesicRHS(r_temp, k3a, k3b);

    r_temp = ray;
    r_temp.r += dL * k3a.x; r_temp.theta += dL * k3a.y; r_temp.phi += dL * k3a.z;
    r_temp.dr += dL * k3b.x; r_temp.dtheta += dL * k3b.y; r_temp.dphi += dL * k3b.z;
    geodesicRHS(r_temp, k4a, k4b);

    ray.r += dL * (k1a.x + 2.0*k2a.x + 2.0*k3a.x + k4a.x) / 6.0;
    ray.theta += dL * (k1a.y + 2.0*k2a.y + 2.0*k3a.y + k4a.y) / 6.0;
    ray.phi += dL * (k1a.z + 2.0*k2a.z + 2.0*k3a.z + k4a.z) / 6.0;
    ray.dr += dL * (k1b.x + 2.0*k2b.x + 2.0*k3b.x + k4b.x) / 6.0;
    ray.dtheta += dL * (k1b.y + 2.0*k2b.y + 2.0*k3b.y + k4b.y) / 6.0;
    ray.dphi += dL * (k1b.z + 2.0*k2b.z + 2.0*k3b.z + k4b.z) / 6.0;

    ray.theta = clamp(ray.theta, 0.0, PI);
    ray.r = max(ray.r, EPS);

    float st = sin(ray.theta); float ct = cos(ray.theta);
    float sp = sin(ray.phi); float cp = cos(ray.phi);

    ray.x = ray.r * st * cp;
    ray.y = ray.r * st * sp;
    ray.z = ray.r * ct;
}

// New RK2 (Midpoint Method) Step
void rk2Step(inout Ray ray, float dL) {
    Ray r_temp;
    vec3 k1a, k1b, k2a, k2b;

    // K1: Evaluate RHS at the current position (ray)
    geodesicRHS(ray, k1a, k1b);

    // Midpoint: Estimate state at t + dL/2 using K1
    r_temp = ray;
    r_temp.r += 0.5 * dL * k1a.x; r_temp.theta += 0.5 * dL * k1a.y; r_temp.phi += 0.5 * dL * k1a.z;
    r_temp.dr += 0.5 * dL * k1b.x; r_temp.dtheta += 0.5 * dL * k1b.y; r_temp.dphi += 0.5 * dL * k1b.z;

    // K2: Evaluate RHS at the midpoint (r_temp)
    geodesicRHS(r_temp, k2a, k2b);

    // Final Step: Use K2 to step from the original position
    ray.r += dL * k2a.x;
    ray.theta += dL * k2a.y;
    ray.phi += dL * k2a.z;
    ray.dr += dL * k2b.x;
    ray.dtheta += dL * k2b.y;
    ray.dphi += dL * k2b.z;

    // Update Spherical <-> Cartesian
    ray.theta = clamp(ray.theta, 0.0, PI);
    ray.r = max(ray.r, EPS);

    float st = sin(ray.theta); float ct = cos(ray.theta);
    float sp = sin(ray.phi); float cp = cos(ray.phi);

    ray.x = ray.r * st * cp;
    ray.y = ray.r * st * sp;
    ray.z = ray.r * ct;
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
float accretion_density(float l, float t, float y, float R, float R0) {
    // Simplified log(l) * 1.5 to map radius to a noise UV
    float noise_r_coord = log(max(l, 1.0)) * 1.5;
    float n = texture(noise_sampler, vec2(0.5 * t / PI + params.time * 0.2, noise_r_coord)).r;

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
            vec3 hit = mix(p, origin + dir * (t - (tFar-tNear)/float(samples)), frac);

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

// --- STARS ---
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 78.233);
    return fract(p.x * p.y);
}

float getStarBrightness(vec3 dir) {
    float phi = atan(dir.y, dir.x);
    float theta = acos(clamp(dir.z, -1.0, 1.0));
    vec2 hashCoord = vec2((phi + PI) / (2.0 * PI), theta / PI) * 50.0;
    float h = hash21(hashCoord);
    float brightness = smoothstep(0.0, params.star_density, h);
    vec2 fracPos = fract(hashCoord);
    float dist = length(fracPos - 0.5);
    return exp(-pow(dist / 0.05, 2.0) * 8.0) * brightness;
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
            float theta = acos(final_dir.y);         // Latitude (0 to pi)
            
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
