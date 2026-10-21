shader_type spatial;
render_mode cull_disabled;

// Ground-cover tufts (scripts/grass_cover.gd): blades sway with a travelling wave, strongest at the tip.
// UV.y is 0 at the root and 1 at the tip; the instance colour tints each tuft.
uniform vec3 root_colour : source_color = vec3(0.16, 0.28, 0.08);
uniform vec3 tip_colour : source_color = vec3(0.62, 0.74, 0.30);
uniform float wind_strength = 0.35;
uniform float wind_speed = 1.5;
varying float height_share;

void vertex() {
	height_share = UV.y;
	// Blades are modelled in metres and scaled by the instance basis: sway in the same units.
	vec3 base = MODEL_MATRIX[3].xyz * 1000.0;
	float phase = dot(base.xz, vec2(0.21, 0.16)) + TIME * wind_speed;
	float gust = sin(phase) + 0.5 * sin(phase * 2.3 + base.x * 0.07);
	VERTEX.x += gust * wind_strength * UV.y * UV.y;
	VERTEX.z += cos(phase * 0.9) * wind_strength * 0.5 * UV.y * UV.y;
}

void fragment() {
	ALBEDO = mix(root_colour, tip_colour, height_share) * COLOR.rgb;
	ROUGHNESS = 0.9;
	// Lit like the ground the tuft grows from, not by the blade's own facing.
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(MODEL_MATRIX[1].xyz), 0.0)).xyz);
}
