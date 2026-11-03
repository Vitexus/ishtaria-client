shader_type spatial;
render_mode cull_disabled;

// The far-view ribbon of a coarse river (surface_environment.gd `_build_rivers`). Inside the detail disk the disk
// draws the river's real water, so the ribbon gives way there like the planet surface does.
uniform vec3 detail_direction = vec3(0.0);
uniform float detail_discard = 0.00012;
varying vec3 surface_direction;

void vertex() {
	surface_direction = normalize(VERTEX);
}

void fragment() {
	if (length(detail_direction) > 0.5 && length(normalize(surface_direction) - detail_direction) < detail_discard) {
		discard;
	}
	ALBEDO = vec3(0.04, 0.19, 0.25);
	ROUGHNESS = 0.28;
}
