shader_type spatial;

render_mode unshaded;

uniform float radius;
uniform sampler2D noise : filter_nearest;
uniform samplerCube skybox;

#define rs 0.7 //schwartzchild radius
#define fade 0.15 //distance over which accretion disk fades close to the inner radius
#define H 0.1 //height of the accretion disk
#define R 5.0 //outer radius of the accretion disk
#define R0 1.75 //inner radius of the accretion disk

float accretion_density(float l, float t, float y)
{
	float n = texture(noise, vec2(0.5 * t / PI + TIME * 0.2, log(l) * 1.5)).r;
	float d0 = pow(max(1.0 - l / R, 0.0) * clamp((l - R0) / fade + 1.0, 0.0, 1.0), 1.5);
	return d0 * exp(-y * y * 400.0) * 10.0 * (n + max(0.0, n - 0.65) * 1.5) * 1.3;
}

void fragment() {
	mat4 inv_view_model = inverse(MODEL_MATRIX) * INV_VIEW_MATRIX;
	vec3 campos = (inv_view_model * vec4(0, 0, 0, 1)).xyz;
	vec3 ld = -normalize((inv_view_model * vec4(VIEW, 0)).xyz); //ray direction in local space
	vec3 lp = (inv_view_model * vec4(VERTEX, 1)).xyz; //ray position in local space

	bool in_bounds = false, prev_in_bounds = false;
	float step_size = 0.05;

	float T = 1.0; //transmission
	vec3 L = vec3(0, 0, 0); //luminosity
	float et = TIME * 0.05;
	for (int i = 0; i < 200; i++)
	{
		step_size *= 1.005; //gradually increase step size
		lp += ld * step_size;
		float r = length(lp);
		float l = length(lp.xz);

		//newtonian-like approximation for light bending
		vec3 la = -1.5 * rs * lp * pow(1.0 + dot(normalize(lp), ld), 3.0) * pow(clamp(2.0 - 0.5 * r, 0.0, 1.0), 2.0) / pow(r, 4.0);
		ld = normalize(ld + la * step_size);

		float ang = atan(lp.z, lp.x);

		float d = accretion_density(l, ang, lp.y);
		float bhd = 10.0 * clamp((rs - r) / 0.5 + 1.0, 0.0, 1.0); //density of black hole
		T *= exp(-(d + bhd) * step_size);
		L += T * d * vec3(3.5, 0.85 / r, exp(r * 0.01) - 1.0) * 2.0 * step_size;

		in_bounds = r < radius;
		if (T <= 0.005 || (!in_bounds && prev_in_bounds))
			break;
		prev_in_bounds = in_bounds;
	}

	ALBEDO = L + T * pow(texture(skybox, ld).rgb, vec3(2.2, 2.2, 2.2));
}