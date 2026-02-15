shader_type canvas_item;

// User uniforms
uniform vec3 black_hole_position = vec3(0.0, 0.0, 0.0);
uniform float schwarzschild_radius = 1.;
uniform vec3 black_hole_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 background_color : source_color = vec3(0.05, 0.05, 0.08);

// Rendering
uniform int max_steps = 3000;
uniform float step_size = 1.;
uniform float escape_radius = 1e4;

// Camera
uniform vec3 camera_position = vec3(0.0, 0.0, 100);
uniform vec3 camera_target = vec3(0.0, 0.0, 0.0);
uniform float camera_fov = 60.1;
uniform vec2 viewport_size = vec2(800.0, 600.0);

// Accretion Disc 
uniform bool show_disc = true;
uniform float disc_inner_radius = 2.2;
uniform float disc_outer_radius = 5.2;
uniform vec3 disc_inner_color : source_color = vec3(1.0, 0.95, 0.0);
uniform vec3 disc_outer_color : source_color = vec3(1.0, 0.3, 0.0);
uniform float disc_thickness = 1.;
uniform float disc_emission_strength = 1.0;

// Star background params
uniform vec3 star_color : source_color = vec3(1.);
uniform float star_brightness = 1.;
uniform float star_density = 0.005;
uniform float star_size_scale = 0.012;

// Grid Params
uniform bool show_grid = true;
uniform vec3 grid_color : source_color = vec3(0.5, 0.7, 1.0);
uniform float grid_spacing = 10; // Spacing between grid lines (matches C++)
uniform float grid_line_thickness = 0.8; // Width of grid lines
uniform float grid_alpha = 1;
uniform float grid_range = 60.; // How far grid extends
uniform float grid_warp_offset = 50.; // Offset from C++ code

// Spherical star (option A: finite sphere)
uniform bool enable_bigstar = false;
uniform vec3 bigstar_center = vec3(0.0, 50.0, -200.0); // world position of star
uniform float bigstar_radius = 20.0;                 // physical radius (world units)
uniform vec3 bigstar_emission : source_color = vec3(1.0, 0.9, 0.7);
uniform float bigstar_surface_brightness = 6.0;      // brightness at surface (tweak)
uniform float bigstar_halo = 0.6;                    // additive halo factor

uniform float time = 1.0;

const float EPS = 1e-7;
const float G_CONST = 6.67430e-11;
const float C_CONST = 299792458.0;

// Ray structure matching C++ implementation
struct Ray {
    float x, y, z;
    float r, theta, phi;
    float dr, dtheta, dphi;
    float E, L;
};

Ray initRay(vec3 pos, vec3 dir) {
    vec3 rel = pos - black_hole_position;

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

    float st = sin(ray.theta);
    float ct = cos(ray.theta);
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);

	// clamp to reduce noise
	st = max(st, 1e-2);

    ray.dr = st * cp * dx + st * sp * dy + ct * dz;
    ray.dtheta = (ct * cp * dx + ct * sp * dy - st * dz) / max(ray.r, EPS);
    ray.dphi = (-sp * dx + cp * dy) / (max(ray.r, EPS) * max(st, EPS));

    ray.L = ray.r * ray.r * max(st, EPS) * ray.dphi;
    float f = 1.0 - schwarzschild_radius / max(ray.r, EPS);
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

    float f = 1.0 - schwarzschild_radius / max(r, EPS);
    float dt_dL = ray.E / max(f, EPS);
    float st = sin(theta);
    float ct = cos(theta);

    d1 = vec3(dr, dtheta, dphi);

    d2.x = -(schwarzschild_radius / (2.0 * r*r)) * f * dt_dL * dt_dL
         + (schwarzschild_radius / (2.0 * r*r * max(f, EPS))) * dr * dr
         + r * (dtheta*dtheta + st*st*dphi*dphi);

    d2.y = -2.0*dr*dtheta/r + st*ct*dphi*dphi;

    d2.z = -2.0*dr*dphi/r - 2.0*ct/max(st, EPS) * dtheta * dphi;
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

    ray.r += dL * (k1a.x + 2.0*k2a.x + 2.0*k3a.x + k4a.x) / 6.0;
    ray.theta += dL * (k1a.y + 2.0*k2a.y + 2.0*k3a.y + k4a.y) / 6.0;
    ray.phi += dL * (k1a.z + 2.0*k2a.z + 2.0*k3a.z + k4a.z) / 6.0;
    ray.dr += dL * (k1b.x + 2.0*k2b.x + 2.0*k3b.x + k4b.x) / 6.0;
    ray.dtheta += dL * (k1b.y + 2.0*k2b.y + 2.0*k3b.y + k4b.y) / 6.0;
    ray.dphi += dL * (k1b.z + 2.0*k2b.z + 2.0*k3b.z + k4b.z) / 6.0;

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
void rk2Step(inout Ray ray, float dL) {
    Ray r_temp;
    vec3 k1a, k1b, k2a, k2b;

    // K1: Evaluate RHS at the current position (ray)
    geodesicRHS(ray, k1a, k1b);

    // Midpoint: Estimate state at t + dL/2 using K1
    r_temp = ray;
    r_temp.r += 0.5 * dL * k1a.x;
    r_temp.theta += 0.5 * dL * k1a.y;
    r_temp.phi += 0.5 * dL * k1a.z;
    r_temp.dr += 0.5 * dL * k1b.x;
    r_temp.dtheta += 0.5 * dL * k1b.y;
    r_temp.dphi += 0.5 * dL * k1b.z;

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

    float st = sin(ray.theta);
    float ct = cos(ray.theta);
    float sp = sin(ray.phi);
    float cp = cos(ray.phi);

    ray.x = ray.r * st * cp;
    ray.y = ray.r * st * sp;
    ray.z = ray.r * ct;
}

float getAdaptiveStepSize(float r) {
    float normalized_r = r / schwarzschild_radius;

    if (normalized_r < 2.0) {
        return step_size * 0.01;
    } else if (normalized_r < 5.0) {
        return step_size * 0.1;
    } else if (normalized_r < 20.0) {
        return step_size * 0.5;
    } else {
        return step_size;
    }
}

bool checkDiskIntersection(vec3 oldPos, vec3 newPos, out vec3 intersectionPoint) {
    if (oldPos.y * newPos.y >= 0.0) {
        return false;
    }

    float t = oldPos.y / (oldPos.y - newPos.y);
    intersectionPoint = oldPos + t * (newPos - oldPos);

    float r = length(vec2(intersectionPoint.x, intersectionPoint.z));
    if (r < disc_inner_radius || r > disc_outer_radius) {
        return false;
    }

    if (abs(intersectionPoint.y) > disc_thickness) {
        return false;
    }

    return true;
}

vec3 getDiskColor(vec3 intersectionPoint) {
    float r = length(vec2(intersectionPoint.x, intersectionPoint.z));
    float r_norm = (r - disc_inner_radius) / max(disc_outer_radius - disc_inner_radius, EPS);
    r_norm = clamp(r_norm, 0.0, 1.0);

    return mix(disc_inner_color, disc_outer_color, r_norm);
}
float accretion_density(float l, float phi, float y, float R, float R0) {
    float phi_norm = (phi / (2.0 * PI)) + 0.5;

    float noise_base_v = log(max(l, 1.0)) * 1.5;

    float angle_time_coord = phi_norm + time * 0.1;
    float radial_offset = texture(noise_sampler, vec2(angle_time_coord, 0.5)).r * 0.2;

    float noise_v_coord = noise_base_v + radial_offset;

    float n = texture(noise_sampler, vec2(angle_time_coord, noise_v_coord * 0.25)).r;
	float n = 1.0;

    float fade = (R - R0) * 0.5;
    float d0 = pow(max(1.0 - l / R, 0.0) * clamp((l - R0) / fade + 1.0, 0.0, 1.0), 1.5);

    return d0 * exp(-y * y * (400.0 / (disc_thickness * disc_thickness))) * 10.0 * (n + max(0.0, n - 0.65) * 1.5) * 1.3;
}
vec3 renderDiscVolume(Ray r_start, Ray r_end, float ray_t) {
    if (!show_disc) return vec3(0.0);

    vec3 color_accum = vec3(0.0);
    float alpha_accum = 0.0;

    const int steps = 10;
    float dl_sub = ray_t / float(steps);

    for (int j = 0; j < steps; ++j) {
        float frac = (float(j) + 0.5) / float(steps);
        vec3 p = mix(vec3(r_start.x, r_start.y, r_start.z), vec3(r_end.x, r_end.y, r_end.z), frac);

        float r = length(p.xz);

        if (r < disc_inner_radius || r > disc_outer_radius) continue;
        if (abs(p.y) > disc_thickness) continue;

        // NOTE: atan(p.y, p.x) is incorrect here for the phi angle in the disc plane,
        // it should be atan(p.z, p.x) if disc is in the XZ plane,
        // or p.xz coordinates if the disc is in the XZ plane
        float density = accretion_density(r, atan(p.x, p.z), p.y, disc_outer_radius, disc_inner_radius);

        // Simplified absorption model (Beer-Lambert law)
        float opacity = 1.0 - exp(-density * dl_sub * disc_emission_strength);

        float r_norm = (r - disc_inner_radius) / max(disc_outer_radius - disc_inner_radius, EPS);
        vec3 disc_color = mix(disc_inner_color.rgb, disc_outer_color.rgb, clamp(r_norm, 0.0, 1.0));

        color_accum += disc_color * opacity * (1.0 - alpha_accum);
        alpha_accum += opacity * (1.0 - alpha_accum);

        if (alpha_accum > 0.99) break;
    }
    return color_accum;
}

// Simple hash function to generate pseudo-random values
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 78.233);
    return fract(p.x * p.y);
}

// Get star brightness based on direction
// Procedural star brightness (returns 0 if no star here)
float getStarBrightness(vec3 dir) {
    // Spherical coords from direction
    float phi = atan(dir.y, dir.x);               // -PI..PI
    float theta = acos(clamp(dir.z, -1.0, 1.0));  // 0..PI

    // Map to 0..1 for hashing
    vec2 hashCoord = vec2((phi + PI) / (2.0 * PI), theta / PI) * 50.0;
    float h = hash21(hashCoord);

    // Map hash to brightness
    float brightness = smoothstep(0.0, star_density, h); // small probability per cell

    // local fractional position within hash cell
    vec2 fracPos = fract(hashCoord);
    vec2 center = vec2(0.5);
    float dist = length(fracPos - center);

    float angular_size = 0.01; // tweak as needed
    float profile = exp(-pow(dist / angular_size, 2.0) * 8.0);
    float halo = exp(-pow(dist / (angular_size*3.0), 2.0) * 4.0) * 0.6;

    return clamp((profile + 0.5*halo) * brightness, 0.0, 1.0);
}
vec3 getStableStarDir(vec3 rayDir) {
    // Project rayDir onto a unit sphere and quantize for hash
    float phi = atan(rayDir.y, rayDir.x);
    float theta = acos(clamp(rayDir.z, -1.0, 1.0));

    // Quantize into hash grid
    float N = 100.0; // number of cells around sphere
    float qphi = floor((phi + PI)/(2.0*PI) * N);
    float qtheta = floor(theta / PI * N);

    return vec3(qphi, qtheta, 0.0); // return as 2D coord for hashing
}

// Calculate warped Y coordinate for the grid surface (matching C++ exactly)
// This replicates the C++ generateGrid() function
float calculateWarpedGridY(float worldX, float worldZ) {
    float y = 0.0;

    float dx = worldX - black_hole_position.x;
    float dz = worldZ - black_hole_position.z;
    float dist = sqrt(dx * dx + dz * dz);
    
    if (dist > schwarzschild_radius) {
        return 2.0 * sqrt(schwarzschild_radius * 
               (dist - schwarzschild_radius)) - grid_warp_offset;
    }
    return 2.0 * schwarzschild_radius - grid_warp_offset;

    return y;
}

// Returns fade factor (1.0 = fully visible, 0.0 = invisible) near grid_range
float getGridEdgeFade(vec2 xz) {
    float dist = length(xz);
    // 0.8–1.0 range controls where the fade starts and ends
    return 1.0 - smoothstep(grid_range * .9, grid_range, dist);
}

vec2 calculateGridGradient(float x, float z) {
    float r_s = schwarzschild_radius;
    vec2 pos_bh_xz = black_hole_position.xz;
    float r = length(vec2(x, z) - pos_bh_xz); // Radial distance 'r'

    float R_MIN = r_s * 0.1; // Match the R_MIN from WarpedY

    // --- Termination Region: r < R_MIN ---
    if (r < R_MIN) {
        // The surface is an extremely deep, flat plane here. Gradient is 0.
        return vec2(0.0);
    }

    // --- Inner & Outer Regions: r >= R_MIN ---
    float h = 0.001; // Tiny step size for approximation
    float y_r_plus_h = calculateWarpedGridY(x + h, z);
    float y_r = calculateWarpedGridY(x, z);

    // Simple Forward Difference
    float df_dx_approx = (y_r_plus_h - y_r) / h;

    // Repeat for Z
    float y_z_plus_h = calculateWarpedGridY(x, z + h);
    float df_dz_approx = (y_z_plus_h - y_r) / h;

    // This numerically calculates the gradient of the surface Y(x, z).
    return vec2(df_dx_approx, df_dz_approx);
}
// Check if point is near a grid line (in XZ plane)
// This matches how the C++ code generates grid lines in a regular pattern
bool isOnGridLine(float worldX, float worldZ, out float lineStrength) {
    // Calculate distance to nearest grid lines
    float xMod = mod(worldX + grid_range, grid_spacing);
    float zMod = mod(worldZ + grid_range, grid_spacing);

    float distToLineX = min(xMod, grid_spacing - xMod);
    float distToLineZ = min(zMod, grid_spacing - zMod);

    float minDist = min(distToLineX, distToLineZ);

    // Sharp falloff with minimal smoothing for crisp lines
    if (minDist < grid_line_thickness) {
        lineStrength = smoothstep(grid_line_thickness, 
                            grid_line_thickness * 0.5, minDist);
        return true;
    }

    return false;
}
// Check if ray intersects the warped grid surface
// This raytraces against the implicit surface defined by calculateWarpedGridY()
bool checkGridIntersection(vec3 oldPos, vec3 newPos, out float gridStrength) {
    if (!show_grid) return false;

    // Check if within grid range (XZ distance)
    float oldDist2D = length(vec2(oldPos.x, oldPos.z));
    float newDist2D = length(vec2(newPos.x, newPos.z));

    if (oldDist2D > grid_range && newDist2D > grid_range) return false;

    // Sample densely along the ray segment to find intersection with warped surface
    const int numSamples = 32; // Increased samples for better detection
    float bestStrength = 0.0;

    for (int i = 0; i <= numSamples; i++) {
        float t = float(i) / float(numSamples);
        vec3 samplePos = mix(oldPos, newPos, t);

        // Skip if outside grid range
        float dist2D = length(vec2(samplePos.x, samplePos.z));
        if (dist2D > grid_range) continue;

        // Calculate where the warped grid surface should be at this XZ position
        // This is the key: the grid is a 2D mesh in XZ, warped in Y direction
        float expectedY = calculateWarpedGridY(samplePos.x, samplePos.z);

        const float GRID_SURFACE_THICKNESS = 0.001;
        float distToSurface = abs(samplePos.y - expectedY);
        if (distToSurface < GRID_SURFACE_THICKNESS) {
            float lineStr;
            if (isOnGridLine(samplePos.x, samplePos.z, lineStr)) {
                gridStrength = grid_alpha * lineStr;
                return true;
                // float surfaceFade = 1.0 - smoothstep(0.0, GRID_SURFACE_THICKNESS, distToSurface);
                // float strength = grid_alpha * lineStr * pow(surfaceFade, 4.0);

                // if (strength > bestStrength) {
                //     bestStrength = strength;
                // }
            }
        }
    }

    if (bestStrength > 0.01) {
        gridStrength = bestStrength;
        return true;
    }

    return false;
}
// Finds the first exact intersection along the straight ray (origin + t * dir)
// Returns true if found. Outputs gridStrength (0..1) and hitPos (world-space point).
bool checkGridIntersectionStraightRay(vec3 origin, vec3 dir, out float gridStrength) {
    if (!show_grid) return false;
    
    const int MAX_STEPS = 2048;
    const float HIT_EPSILON = 0.001;
    

    float t = 0.0;
    float tNear = 0.0;
    float tFar = length(camera_position) + grid_range * escape_radius;
    const float SINGULARITY_RADIUS = 0.001;

    for (int i = 1; i <= MAX_STEPS; ++i) {
        // float tf = float(i) / float(samples);
        // float t = mix(tNear, tFar, tf);
        vec3 p = origin + dir * t;
        
        if (t > tFar) return false;
        
        float distXZ = length(p.xz);
        
        if (distXZ > grid_range*1.05 && distXZ < schwarzschild_radius * 1.001 && dot(p.xz, dir.xz) > 0.0) continue;

        float yNow = p.y - calculateWarpedGridY(p.x, p.z);
        float dist = p.y - yNow;

        // Detect a sign change (surface crossing)
        if (abs(dist) < HIT_EPSILON) {
          // if grid line is close to center, ignore
          if (distXZ < schwarzschild_radius * .1) {
            t += HIT_EPSILON * 2.0;
            continue;
            // Skip logic and continue loop
          }
          float lineStr;
            if (isOnGridLine(p.x, p.z, lineStr)) {
                // Fade near edge
                float fade = 1.0 - smoothstep(grid_range * 0.9, grid_range, distXZ);;
                gridStrength = grid_alpha * lineStr * fade;
                return true;
            }
        }
        
        vec2 gradXZ = calculateGridGradient(p.x, p.z);
        float gradientMagnitude = length(gradXZ);
        
        float invGradient = 1.0 / sqrt(1.0 + gradientMagnitude * gradientMagnitude + 1e-6);
        t += invGradient * abs(dist);
    }

    return false;
}
// segment from p0 -> p1, returns true when intersects; out t is [0..1] param along segment
bool intersectSegmentSphere(vec3 p0, vec3 p1, vec3 center, float radius, out float t_hit, out vec3 hitPos) {
    vec3 d = p1 - p0;
    vec3 oc = p0 - center;
    float a = dot(d, d);
    float b = 2.0 * dot(oc, d);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - 4.0 * a * c;
    if (disc < 0.0) return false;
    float sqrtD = sqrt(disc);
    float t0 = (-b - sqrtD) / (2.0 * a);
    float t1 = (-b + sqrtD) / (2.0 * a);

    // choose smallest positive t in [0,1]
    float t = 1e9;
    if (t0 >= 0.0 && t0 <= 1.0) t = min(t, t0);
    if (t1 >= 0.0 && t1 <= 1.0) t = min(t, t1);
    if (t > 1e8) return false;

    t_hit = t;
    hitPos = p0 + d * t;
    return true;
}
void fragment() {
    float alpha = 1.0;

    // Camera basis
    vec3 forward = normalize(camera_target - camera_position);
    vec3 world_up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(forward, world_up));

    if (length(right) < 1e-5) {
        world_up = vec3(1.0, 0.0, 0.0);
        right = normalize(cross(forward, world_up));
    }
    vec3 up = cross(right, forward);

    // Screen to NDC
    vec2 uv = (FRAGCOORD.xy / viewport_size);
    uv = uv * 2.0 - 1.0;
    float aspect = viewport_size.x / viewport_size.y;
    uv.x *= aspect;

    // Apply FOV
    float tan_half_fov = tan(radians(camera_fov) * 0.5);
    uv *= tan_half_fov;

    // Ray direction
    vec3 ray_dir = normalize(uv.x * right - uv.y * up + forward);
    Ray ray = initRay(camera_position, ray_dir);
    
    float transmission = 1.0;
    bool hitSomething = false;
    
    vec3 prev_world_pos = vec3(ray.x, ray.y, ray.z);
    
    float curr_step = step_size;

    // Accumulations
    vec3 total_disc_color = vec3(0.0);
    // vec3 total_nebula_color = vec3(0.0);
    float et = time * 0.05;
    
    bool hitPixHole = false;
    
    bool straightHitGrid = false;
    float straightGridStrength = 0.0;
    if (show_grid) {
        straightHitGrid = checkGridIntersectionStraightRay(camera_position, ray_dir, straightGridStrength);
    }

    // Main integration loop
    for (int i = 0; i < max_steps; i++) {
      // Hit event horizon
      if (ray.r <= schwarzschild_radius * 1.01) { 
        hitPixHole = true;
        break; 
      }
        float adaptive_step = getAdaptiveStepSize(ray.r);
        Ray prev_ray = ray;
        
        if (ray.r < schwarzschild_radius * 2.0) {
          rk2Step(ray, adaptive_step);
        } else {
          rk4Step(ray, adaptive_step);
        }
        
        vec3 curr_world_pos = vec3(ray.x, ray.y, ray.z);
        vec3 mid_pos = mix(prev_world_pos, curr_world_pos, 0.5);
        
        // Accretion disk
        vec3 diskIntersection;
        if (show_disc) {
          vec3 disc_step_color = renderDiscVolume(prev_ray, ray, adaptive_step);
          total_disc_color += disc_step_color;
        }
        
        // nebula
        // if (show_nebula) {
        
        // }

        prev_world_pos = curr_world_pos;
        
        if (ray.r > escape_radius) { break; }
        // Early exit
        if (transmission < 0.01) {
            break;
        }
    }
    
    vec3 color_out;
    
    if (hitPixHole) {
      color_out = black_hole_color;
    } else {
      // Add skybox image here
      // // Stars (procedural)
      vec3 starDir = getStableStarDir(ray_dir);
      vec2 hashCoord = vec2(starDir.x, starDir.y);
      float h = hash21(hashCoord);
      float starVal = getStarBrightness(ray_dir) * star_brightness;
      if (starVal > 1.-star_density) {
          // additive contribution so very bright stars "bleed" a bit
          // color_out = mix(color_out, star_color, starVal);
          color_out += star_color * starVal;
      }
      // Grid
      if (straightHitGrid) {
      color_out = mix(color_out, grid_color, straightGridStrength);
      }
      // Blend nebula here
    }
    // Blend disc volume
    color_out = total_disc_color + color_out;
    
    color_out = clamp(color_out, 0.0, 4.0);

    COLOR = vec4(color_out, alpha);
}