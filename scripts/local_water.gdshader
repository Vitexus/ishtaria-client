shader_type spatial;
render_mode cull_back, depth_draw_always;

// Water of the local detail disk (surface_environment.gd): clear and shallow at the shore, deep and dark
// toward the middle, with ripples that bend the normal, a foam line along the bank and sky reflection
// from the PBR specular. UV2.x is the ground height and UV2.y the water surface of the vertex (km;
// -100 on dry ground, which is discarded); NORMAL carries the unit direction of the vertex.
uniform vec2 wave_phase = vec2(0.0);
uniform vec3 deep_colour : source_color = vec3(0.02, 0.15, 0.22);
uniform vec3 shallow_colour : source_color = vec3(0.12, 0.40, 0.38);
uniform float clarity_per_metre = 0.55;
varying vec3 surface_point;
varying float ground_km;
varying float level_km;
varying vec3 local_point;

void vertex() {
	surface_point = normalize(NORMAL);
	ground_km = UV2.x;
	level_km = UV2.y;
	local_point = VERTEX;
}

void fragment() {
	if (ground_km > level_km) {
		discard;
	}
	float depth_m = (level_km - ground_km) * 1000.0;
	float clarity = exp(-depth_m * clarity_per_metre);
	// Two crossing wave trains (positions in km: the frequencies are per kilometre).
	vec3 point = local_point;
	float phase_a = dot(point, vec3(1.0, 0.7, 0.3)) * 650.0 + wave_phase.x + TIME * 0.8;
	float phase_b = dot(point, vec3(0.2, 0.5, 1.0)) * 700.0 + wave_phase.y + TIME * 0.6;
	float waves = sin(phase_a) * cos(phase_b);
	// The slope of the ripples tilts the surface normal in the plane of the water.
	vec3 up = surface_point;
	vec3 side = normalize(cross(up, abs(up.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 along = cross(up, side);
	float slope_a = cos(phase_a) * cos(phase_b) * 0.05;
	float slope_b = -sin(phase_a) * sin(phase_b) * 0.05;
	vec3 tilted = normalize(up + side * slope_a + along * slope_b);
	NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * tilted));
	float foam = smoothstep(0.35, 0.0, depth_m) * (0.6 + 0.4 * waves);
	vec3 colour = mix(deep_colour, shallow_colour, clarity);
	ALBEDO = mix(colour, vec3(0.92, 0.96, 0.95), clamp(foam, 0.0, 1.0));
	// Shallows show a little of the bed; from about a metre the pond reads as filled, not a floating film.
	ALPHA = clamp(mix(0.97, 0.55, clarity) + foam * 0.5, 0.0, 1.0);
	ROUGHNESS = mix(0.06, 0.5, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.6;
}
