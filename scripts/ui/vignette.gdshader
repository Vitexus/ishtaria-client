shader_type canvas_item;
// The veil behind menus: a tinted darkening that is lighter at the centre of the screen and
// close to opaque at its edges, so the world stays faintly visible behind the panel.

uniform vec4 tint : source_color = vec4(0.12, 0.07, 0.05, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	vec2 centred = UV - vec2(0.5);
	float distance_from_centre = length(centred * vec2(1.25, 1.0));
	float alpha = mix(strength * 0.72, min(1.0, strength * 1.18), smoothstep(0.15, 0.75, distance_from_centre));
	COLOR = vec4(tint.rgb, alpha);
}
