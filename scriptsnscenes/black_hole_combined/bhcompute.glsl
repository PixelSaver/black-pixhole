#[compute]
#version 450

// Workgroup size - each thread handles one pixel
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Output texture
layout(rgba16f, set = 0, binding = 0) uniform image2D output_image;

// Skybox cubemap
layout(set = 0, binding = 1) uniform samplerCube skybox;

// Disc noise texture
layout(set = 0, binding = 2) uniform sampler2D disc_noise;

// Parameters uniform buffer
layout(set = 0, binding = 3, std140) uniform Params {
    // Black hole
    vec3 black_hole_position;
    float schwarzschild_radius;
    vec4 black_hole_color;
    
    // Camera
    vec3 camera_position;
    float camera_fov;
    vec3 camera_target;
    float time;
    
    // Rendering
    ivec2 resolution;
    int max_steps;
    float step_size;
    float escape_radius;
    float skybox_brightness;
    
    // Disc
    float disc_inner_radius;
    float disc_outer_radius;
    float disc_thickness;
    float disc_emission_strength;
    vec4 disc_inner_color;
    vec4 disc_outer_color;
    int enable_disc;
    
    // Grid
    int show_grid;
    float grid_spacing;
    float grid_line_thickness;
    float grid_alpha;
    float grid_range;
    float grid_warp_offset;
    vec4 grid_color;
    
    // Stars
    float star_density;
    float star_brightness;
    vec4 star_color;
} params;

const float EPS = 1e-6;
const float PI = 3.14159265359;

// ========== LIGHT BENDING ==========
vec3 bendRay(vec3 pos, vec3 dir, float step) {
    vec3 rel_pos = pos - params.black_hole_position;
    float r = length(rel_pos);
    
    if (r < params.schwarzschild_radius * 1.5) return dir;
    
    float r3 = r * r * r;
    float strength = 1.2 * params.schwarzschild_radius / r3;
    vec3 accel = -rel_pos * strength;
    
    return normalize(dir + accel * step);
}

// ========== DISC FUNCTIONS ==========
bool checkDiscIntersection(vec3 p0, vec3 p1, out vec3 hit_pos) {
    if (params.enable_disc == 0) return false;
    if (p0.y * p1.y >= 0.0) return false;
    
    float t = p0.y / (p0.y - p1.y);
    hit_pos = mix(p0, p1, t);
    
    float r = length(hit_pos.xz);
    return (r >= params.disc_inner_radius && 
            r <= params.disc_outer_radius && 
            abs(hit_pos.y) <= params.disc_thickness);
}

vec3 getDiscColor(vec3 pos) {
    float r = length(pos.xz);
    float t = (r - params.disc_inner_radius) / 
              max(params.disc_outer_radius - params.disc_inner_radius, 0.01);
    t = clamp(t, 0.0, 1.0);
    
    float angle = atan(pos.z, pos.x);
    vec2 noise_uv = vec2(angle / (2.0 * PI) + params.time * 0.1, 
                         log(r + 1.0) * 0.3);
    float noise_val = texture(disc_noise, noise_uv).r;
    
    vec3 base_color = mix(params.disc_inner_color.rgb, 
                          params.disc_outer_color.rgb, t);
    
    float intensity = params.disc_emission_strength * (1.5 - t * 0.5);
    intensity *= (0.8 + noise_val * 0.4);
    
    return base_color * intensity;
}

// ========== GRID FUNCTIONS ==========
float calculateWarpedGridY(float x, float z) {
    if (params.show_grid == 0) return 0.0;
    
    float dx = x - params.black_hole_position.x;
    float dz = z - params.black_hole_position.z;
    float dist = sqrt(dx * dx + dz * dz);
    
    if (dist > params.schwarzschild_radius) {
        return 2.0 * sqrt(params.schwarzschild_radius * 
               (dist - params.schwarzschild_radius)) - params.grid_warp_offset;
    }
    return 2.0 * params.schwarzschild_radius - params.grid_warp_offset;
}

bool isOnGridLine(vec2 xz, out float strength) {
    float xMod = mod(xz.x + params.grid_range, params.grid_spacing);
    float zMod = mod(xz.y + params.grid_range, params.grid_spacing);
    
    float distX = min(xMod, params.grid_spacing - xMod);
    float distZ = min(zMod, params.grid_spacing - zMod);
    float minDist = min(distX, distZ);
    
    if (minDist < params.grid_line_thickness) {
        strength = smoothstep(params.grid_line_thickness, 
                            params.grid_line_thickness * 0.5, minDist);
        return true;
    }
    return false;
}

bool checkGridIntersection(vec3 p0, vec3 p1, out float strength) {
    if (params.show_grid == 0) return false;
    
    float dist2D = length(p0.xz);
    if (dist2D > params.grid_range) return false;
    
    const int samples = 8;
    for (int i = 0; i <= samples; i++) {
        float t = float(i) / float(samples);
        vec3 p = mix(p0, p1, t);
        
        float expected_y = calculateWarpedGridY(p.x, p.z);
        float dist_to_surface = abs(p.y - expected_y);
        
        if (dist_to_surface < 0.5) {
            float line_str;
            if (isOnGridLine(p.xz, line_str)) {
                float fade = 1.0 - smoothstep(params.grid_range * 0.8, 
                                             params.grid_range, length(p.xz));
                strength = params.grid_alpha * line_str * fade;
                return true;
            }
        }
    }
    return false;
}

// ========== STAR FIELD ==========
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 78.233);
    return fract(p.x * p.y);
}

float getStarBrightness(vec3 dir) {
    float phi = atan(dir.y, dir.x);
    float theta = acos(clamp(dir.z, -1.0, 1.0));
    
    vec2 coord = vec2((phi + PI) / (2.0 * PI), theta / PI) * 50.0;
    float h = hash21(coord);
    
    if (h < params.star_density) {
        vec2 frac_pos = fract(coord);
        float dist = length(frac_pos - 0.5);
        return exp(-dist * dist * 300.0) * (h / params.star_density);
    }
    return 0.0;
}

// ========== MAIN COMPUTE ==========
void main() {
    ivec2 pixel_coords = ivec2(gl_GlobalInvocationID.xy);
    
    // Bounds check
    if (pixel_coords.x >= params.resolution.x || 
        pixel_coords.y >= params.resolution.y) {
        return;
    }
    
    // Setup camera
    vec3 forward = normalize(params.camera_target - params.camera_position);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);
    
    // Calculate ray direction
    vec2 uv = (vec2(pixel_coords) + 0.5) / vec2(params.resolution);
    uv = uv * 2.0 - 1.0;
    uv.x *= float(params.resolution.x) / float(params.resolution.y);
    
    float tan_fov = tan(radians(params.camera_fov) * 0.5);
    uv *= tan_fov;
    
    vec3 ray_dir = normalize(uv.x * right - uv.y * up + forward);
    vec3 ray_pos = params.camera_position;
    
    // Raymarching state
    vec3 color = vec3(0.0);
    float transmission = 1.0;
    bool hit_something = false;
    
    vec3 prev_pos = ray_pos;
    float current_step = params.step_size;
    
    // Main raymarching loop
    for (int i = 0; i < params.max_steps; i++) {
        // Bend ray
        ray_dir = bendRay(ray_pos, ray_dir, current_step);
        
        // Advance ray
        prev_pos = ray_pos;
        ray_pos += ray_dir * current_step;
        
        float r = length(ray_pos - params.black_hole_position);
        
        // Hit event horizon
        if (r <= params.schwarzschild_radius * 1.05) {
            color += params.black_hole_color.rgb * transmission;
            hit_something = true;
            transmission = 0.0;
            break;
        }
        
        // Adaptive step size
        float normalized_r = r / params.schwarzschild_radius;
        if (normalized_r < 3.0) {
            current_step = params.step_size * 0.2;
        } else if (normalized_r < 10.0) {
            current_step = params.step_size * 0.5;
        } else {
            current_step = params.step_size * 1.5;
        }
        
        // Check disc intersection
        vec3 disc_hit;
        if (checkDiscIntersection(prev_pos, ray_pos, disc_hit)) {
            vec3 disc_color = getDiscColor(disc_hit);
            color += disc_color * transmission;
            hit_something = true;
            transmission = 0.0;
            break;
        }
        
        // Check grid intersection
        float grid_strength;
        if (checkGridIntersection(prev_pos, ray_pos, grid_strength)) {
            color += params.grid_color.rgb * grid_strength * transmission;
            transmission *= (1.0 - grid_strength);
        }
        
        // Escape check
        if (r > params.escape_radius) {
            break;
        }
        
        // Early exit
        if (transmission < 0.01) {
            hit_something = true;
            break;
        }
    }
    
    // Background: skybox + stars
    if (transmission > 0.01) {
        vec3 final_dir = normalize(ray_pos - params.camera_position);
        
        // Sample skybox
        vec3 sky = texture(skybox, final_dir).rgb;
        sky = pow(sky, vec3(2.2)) * params.skybox_brightness;
        
        // Add stars
        float star_val = getStarBrightness(final_dir) * params.star_brightness;
        sky += params.star_color.rgb * star_val;
        
        color += sky * transmission;
    }
    
    // Simple tone mapping
    color = color / (color + 3.0);
        
    // Write output
    imageStore(output_image, pixel_coords, vec4(color, 1.0));
}
