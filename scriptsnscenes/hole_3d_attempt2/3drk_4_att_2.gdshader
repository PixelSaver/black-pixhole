shader_type canvas_item;

// ---------- User uniforms ----------
uniform vec3 black_hole_position = vec3(0.0, 0.0, 0.0);
uniform float schwarzschild_radius = 1.;
uniform vec3 black_hole_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 background_color : source_color = vec3(0.05, 0.05, 0.08);

uniform int max_steps = 3000;
uniform float step_size = 1.;
uniform float escape_radius = 1e4;

uniform vec3 camera_position = vec3(0.0, 0.0, 100);
uniform vec3 camera_target = vec3(0.0, 0.0, 0.0);
uniform float camera_fov = 60.0;

// ---------- Accretion Disc Params --------
uniform float disc_inner_radius = 2.2;
uniform float disc_outer_radius = 5.2;
uniform vec3 disc_color : source_color = vec3(1.0, 0.5, 0.2);
uniform float disc_thickness = 1.;

// -------- Star params ---------
uniform vec3 star_color : source_color = vec3(1.);
uniform float star_brightness = 1.;
uniform float star_density = 0.005;

uniform vec2 viewport_size = vec2(800.0, 600.0);

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

    vec3 hot_color = vec3(1.0, 0.95, 0.8);
    vec3 cool_color = vec3(1.0, 0.3, 0.1);

    return mix(hot_color, cool_color, r_norm);
}
// Simple hash function to generate pseudo-random values
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 78.233);
    return fract(p.x * p.y);
}

// Get star brightness based on direction
float getStarBrightness(vec3 dir) {
    // Convert spherical coordinates to a 2D hash domain
    float phi = atan(dir.y, dir.x);
    float theta = acos(clamp(dir.z, -1.0, 1.0));
    
    vec2 hashCoord = vec2(phi, theta) * 100.0; // scale up for density
    float h = hash21(hashCoord);
	if (h > 1.-star_density) { // increase chance for stars
	    return (h - (1.-star_density)) / star_density;
	}
}

void fragment() {
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

    vec3 color_out = background_color;
    vec3 prevPos = vec3(ray.x, ray.y, ray.z);

    bool hitBlackHole = false;
    bool hitDisk = false;
    bool escaped = false;

    // Main integration loop
    for (int i = 0; i < max_steps; i++) {
        // Check if ray hit event horizon
        if (ray.r <= schwarzschild_radius * 1.01) { hitBlackHole = true; break; }
        
        float adaptive_step = getAdaptiveStepSize(ray.r);
        rk4Step(ray, adaptive_step);

        vec3 newPos = vec3(ray.x, ray.y, ray.z);

        // Check disk intersection
        vec3 diskIntersection;
        if (!hitDisk && checkDiskIntersection(prevPos, newPos, diskIntersection)) {
            hitDisk = true;
            color_out = getDiskColor(diskIntersection);
            break;
        }

        prevPos = newPos;
        if (ray.r > escape_radius) { escaped = true; break; }
    }

    // Apply colors in priority order
    if (hitDisk) {
        // Disk is opaque
    } else if (hitBlackHole) {
        color_out = black_hole_color;
    } else {
        // Use final ray direction after bending
		vec3 finalDir = normalize(vec3(ray.x, ray.y, ray.z) - black_hole_position);
		float starVal = getStarBrightness(finalDir) * star_brightness;
		if (starVal > 0.985) {
	        color_out = mix(color_out, star_color, starVal);
		}
    }
	

    COLOR = vec4(color_out, 1.0);
}