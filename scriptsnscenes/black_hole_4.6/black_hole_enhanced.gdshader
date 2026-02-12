shader_type canvas_item;

// ============================================================================
// BLACK HOLE PARAMETERS
// ============================================================================
uniform vec3 black_hole_position = vec3(0.0, 0.0, 0.0);
uniform float schwarzschild_radius = 1.0;
uniform vec3 black_hole_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 background_color : source_color = vec3(0.05, 0.05, 0.08);

// ============================================================================
// RAYMARCHING PARAMETERS
// ============================================================================
uniform int max_steps = 3000;
uniform float step_size = 1.0;
uniform float escape_radius = 1e4;

// ============================================================================
// CAMERA PARAMETERS
// ============================================================================
uniform vec3 camera_position = vec3(0.0, 0.0, 100.0);
uniform vec3 camera_target = vec3(0.0, 0.0, 0.0);
uniform float camera_fov = 60.0;
uniform vec2 viewport_size = vec2(800.0, 600.0);

// ============================================================================
// ACCRETION DISC PARAMETERS
// ============================================================================
uniform bool enable_disc = true;
uniform float disc_inner_radius = 2.2;
uniform float disc_outer_radius = 5.2;
uniform vec3 disc_inner_color : source_color = vec3(1.0, 0.95, 0.0);
uniform vec3 disc_outer_color : source_color = vec3(1.0, 0.3, 0.0);
uniform float disc_thickness = 1.0;
uniform float disc_emission_strength = 1.5;

// ============================================================================
// STAR FIELD PARAMETERS
// ============================================================================
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float star_brightness = 1.0;
uniform float star_density = 0.005;
uniform float star_size_scale = 0.012;

// ============================================================================
// GRID PARAMETERS
// ============================================================================
uniform bool show_grid = true;
uniform vec3 grid_color : source_color = vec3(0.5, 0.7, 1.0);
uniform float grid_spacing = 10.0;
uniform float grid_line_thickness = 0.8;
uniform float grid_alpha = 1.0;
uniform float grid_range = 60.0;
uniform float grid_warp_offset = 50.0;

// ============================================================================
// SPHERICAL STAR PARAMETERS
// ============================================================================
uniform bool enable_bigstar = false;
uniform vec3 bigstar_center = vec3(0.0, 50.0, -200.0);
uniform float bigstar_radius = 20.0;
uniform vec3 bigstar_emission : source_color = vec3(1.0, 0.9, 0.7);
uniform float bigstar_surface_brightness = 6.0;
uniform float bigstar_halo = 0.6;

// ============================================================================
// CONSTANTS
// ============================================================================
const float EPS = 1e-7;

// ============================================================================
// RAY STRUCTURE (GEODESIC INTEGRATION)
// ============================================================================
struct Ray {
    float x, y, z;
    float r, theta, phi;
    float dr, dtheta, dphi;
    float E, L;
};

// ============================================================================
// RAY INITIALIZATION
// ============================================================================
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
    
    // Clamp to reduce noise
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

// ============================================================================
// GEODESIC EQUATIONS (RHS OF DIFFERENTIAL EQUATIONS)
// ============================================================================
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
    
    d2.x = -(schwarzschild_radius / (2.0 * r * r)) * f * dt_dL * dt_dL
         + (schwarzschild_radius / (2.0 * r * r * max(f, EPS))) * dr * dr
         + r * (dtheta * dtheta + st * st * dphi * dphi);
    
    d2.y = -2.0 * dr * dtheta / r + st * ct * dphi * dphi;
    
    d2.z = -2.0 * dr * dphi / r - 2.0 * ct / max(st, EPS) * dtheta * dphi;
}

// ============================================================================
// RK4 INTEGRATION STEP
// ============================================================================
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

// ============================================================================
// ADAPTIVE STEP SIZE
// ============================================================================
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

// ============================================================================
// DISC INTERSECTION
// ============================================================================
bool checkDiscIntersection(vec3 oldPos, vec3 newPos, out vec3 intersectionPoint) {
    if (!enable_disc) return false;
    if (oldPos.y * newPos.y >= 0.0) return false;
    
    float t = oldPos.y / (oldPos.y - newPos.y);
    intersectionPoint = oldPos + t * (newPos - oldPos);
    
    float r = length(vec2(intersectionPoint.x, intersectionPoint.z));
    if (r < disc_inner_radius || r > disc_outer_radius) return false;
    if (abs(intersectionPoint.y) > disc_thickness) return false;
    
    return true;
}

vec3 getDiscColor(vec3 intersectionPoint) {
    float r = length(vec2(intersectionPoint.x, intersectionPoint.z));
    float r_norm = (r - disc_inner_radius) / max(disc_outer_radius - disc_inner_radius, EPS);
    r_norm = clamp(r_norm, 0.0, 1.0);
    
    vec3 base_color = mix(disc_inner_color, disc_outer_color, r_norm);
    float intensity = disc_emission_strength * (1.5 - r_norm * 0.5);
    
    return base_color * intensity;
}

// ============================================================================
// STAR FIELD FUNCTIONS
// ============================================================================
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
    
    float brightness = smoothstep(0.0, star_density, h);
    
    vec2 fracPos = fract(hashCoord);
    vec2 center = vec2(0.5);
    float dist = length(fracPos - center);
    
    float angular_size = star_size_scale;
    float profile = exp(-pow(dist / angular_size, 2.0) * 8.0);
    float halo = exp(-pow(dist / (angular_size * 3.0), 2.0) * 4.0) * 0.6;
    
    return clamp((profile + 0.5 * halo) * brightness, 0.0, 1.0);
}

// ============================================================================
// GRID FUNCTIONS
// ============================================================================
float calculateWarpedGridY(float worldX, float worldZ) {
    float dx = worldX - black_hole_position.x;
    float dz = worldZ - black_hole_position.z;
    float dist = sqrt(dx * dx + dz * dz);
    
    if (dist > schwarzschild_radius) {
        float deltaY = 2.0 * sqrt(schwarzschild_radius * (dist - schwarzschild_radius));
        return deltaY - grid_warp_offset;
    } else {
        return 2.0 * schwarzschild_radius - grid_warp_offset;
    }
}

float getGridEdgeFade(vec2 xz) {
    float dist = length(xz);
    return 1.0 - smoothstep(grid_range * 0.9, grid_range, dist);
}

bool isOnGridLine(float worldX, float worldZ, out float lineStrength) {
    float xMod = mod(worldX + grid_range, grid_spacing);
    float zMod = mod(worldZ + grid_range, grid_spacing);
    
    float distToLineX = min(xMod, grid_spacing - xMod);
    float distToLineZ = min(zMod, grid_spacing - zMod);
    float minDist = min(distToLineX, distToLineZ);
    
    if (minDist < grid_line_thickness) {
        lineStrength = smoothstep(grid_line_thickness, grid_line_thickness * 0.5, minDist);
        return true;
    }
    
    return false;
}

bool checkGridIntersectionStraightRay(vec3 origin, vec3 dir, out float gridStrength, out vec3 hitPos) {
    gridStrength = 0.0;
    hitPos = vec3(0.0);
    
    if (!show_grid) return false;
    
    float tNear = 0.0;
    float tFar = length(camera_position) + grid_range;
    const int samples = 128;
    
    float prevY = origin.y - calculateWarpedGridY(origin.x, origin.z);
    float prevT = tNear;
    
    for (int i = 1; i <= samples; ++i) {
        float tf = float(i) / float(samples);
        float t = mix(tNear, tFar, tf);
        vec3 p = origin + dir * t;
        
        float distXZ = length(p.xz);
        if (distXZ > grid_range || distXZ < schwarzschild_radius * 1.001) continue;
        
        float yNow = p.y - calculateWarpedGridY(p.x, p.z);
        
        if (prevY * yNow <= 0.0) {
            float frac = abs(prevY) / (abs(prevY) + abs(yNow) + 1e-6);
            vec3 hit = mix(p, origin + dir * prevT, frac);
            
            float lineStr;
            if (isOnGridLine(hit.x, hit.z, lineStr)) {
                float fade = getGridEdgeFade(hit.xz);
                gridStrength = grid_alpha * lineStr * fade;
                hitPos = hit;
                return true;
            }
        }
        
        prevY = yNow;
        prevT = t;
    }
    
    return false;
}

// ============================================================================
// SPHERICAL STAR INTERSECTION
// ============================================================================
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
    
    float t = 1e9;
    if (t0 >= 0.0 && t0 <= 1.0) t = min(t, t0);
    if (t1 >= 0.0 && t1 <= 1.0) t = min(t, t1);
    if (t > 1e8) return false;
    
    t_hit = t;
    hitPos = p0 + d * t;
    return true;
}

// ============================================================================
// FRAGMENT SHADER (MAIN)
// ============================================================================
void fragment() {
    // Setup camera basis
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
    
    vec3 color_out = background_color;
    vec3 prevPos = vec3(ray.x, ray.y, ray.z);
    
    bool hitBlackHole = false;
    bool hitDisk = false;
    bool hitStar = false;
    bool escaped = false;
    
    // Check straight (unbent) ray grid intersection
    float straightGridStrength = 0.0;
    bool straightHitGrid = false;
    vec3 straightHitPos = vec3(0.0);
    
    if (show_grid) {
        straightHitGrid = checkGridIntersectionStraightRay(camera_position, ray_dir, straightGridStrength, straightHitPos);
    }
    
    // Main geodesic integration loop
    for (int i = 0; i < max_steps; i++) {
        // Event horizon check
        if (ray.r <= schwarzschild_radius * 1.01) {
            hitBlackHole = true;
            break;
        }
        
        float adaptive_step = getAdaptiveStepSize(ray.r);
        rk4Step(ray, adaptive_step);
        
        vec3 newPos = vec3(ray.x, ray.y, ray.z);
        
        // Check spherical star intersection
        if (enable_bigstar) {
            float t_hit;
            vec3 hitPos;
            if (intersectSegmentSphere(prevPos, newPos, bigstar_center, bigstar_radius, t_hit, hitPos)) {
                vec3 N = normalize(hitPos - bigstar_center);
                vec3 V = normalize(camera_position - hitPos);
                float cosTheta = clamp(dot(N, V), 0.0, 1.0);
                float surface = pow(cosTheta, 0.5);
                
                vec3 surfColor = bigstar_emission * bigstar_surface_brightness * surface;
                
                vec3 dirToStarFromCamera = normalize(bigstar_center - camera_position);
                vec3 currentRayDir = normalize(hitPos - camera_position);
                float ang = max(0.0, dot(dirToStarFromCamera, currentRayDir));
                float halo = pow(ang, 16.0);
                vec3 haloColor = bigstar_emission * (bigstar_halo * halo);
                
                color_out = surfColor + haloColor;
                hitStar = true;
                break;
            }
        }
        
        // Check disc intersection
        vec3 diskIntersection;
        if (!hitDisk && checkDiscIntersection(prevPos, newPos, diskIntersection)) {
            hitDisk = true;
            color_out = getDiscColor(diskIntersection);
            break;
        }
        
        prevPos = newPos;
        
        // Escape check
        if (ray.r > escape_radius) {
            escaped = true;
            break;
        }
    }
    
    // Apply colors in priority order
    if (hitDisk || hitStar) {
        // Opaque surfaces
    } else if (hitBlackHole) {
        color_out = black_hole_color;
    } else {
        // Background rendering
        if (straightHitGrid) {
            color_out = mix(background_color, grid_color, straightGridStrength);
        } else {
            color_out = background_color;
        }
        
        // Add procedural stars
        float starVal = getStarBrightness(ray_dir) * star_brightness;
        if (starVal > 1.0 - star_density) {
            color_out += star_color * starVal;
        }
    }
    
    COLOR = vec4(color_out, 1.0);
}
