shader_type sky;

uniform sampler2D orbit_panorama : source_color, filter_linear, repeat_enable;
uniform sampler2D surface_panorama : source_color, filter_linear, repeat_enable;
uniform float surface_blend : hint_range(0.0, 1.0) = 0.0;
uniform float surface_energy = 1.0;
uniform sampler2D night_panorama : source_color, filter_linear, repeat_enable;
uniform bool solar_enabled = false;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform vec3 moon_direction = vec3(-1.0, 0.0, 0.0);
uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 moon_color : source_color = vec4(0.82, 0.86, 0.95, 1.0);
uniform float sun_radius = 0.00465;
uniform float moon_radius = 0.0045;
uniform float moon_illumination = 0.5;
uniform float sun_elevation = 90.0;
uniform float daylight = 1.0;
uniform float sidereal_angle = 0.0;
uniform float horizon_dip = 0.0;

vec2 panorama_coordinates(vec3 direction) {
	return vec2(atan(direction.x, direction.z) / (2.0 * PI) + 0.5, acos(clamp(direction.y, -1.0, 1.0)) / PI);
}

void sky() {
	vec3 orbital = texture(orbit_panorama, SKY_COORDS).rgb;
	vec3 surface = texture(surface_panorama, SKY_COORDS).rgb;
	COLOR = mix(orbital, surface * surface_energy, surface_blend);
	if (solar_enabled) {
		vec3 direction = normalize(EYEDIR);
		vec3 reference = abs(local_up.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 east = normalize(cross(reference, local_up));
		vec3 north = cross(local_up, east);
		vec3 local_direction = vec3(dot(direction, east), dot(direction, local_up), dot(direction, north));
		vec2 surface_uv = panorama_coordinates(local_direction);
		vec3 inertial = direction;
		inertial.xz = vec2(cos(sidereal_angle) * direction.x + sin(sidereal_angle) * direction.z, -sin(sidereal_angle) * direction.x + cos(sidereal_angle) * direction.z);
		orbital = texture(orbit_panorama, panorama_coordinates(inertial)).rgb;
		float baked_disc = 1.0 - smoothstep(0.65, 1.0, length((surface_uv - vec2(0.91646, 0.22163)) / vec2(0.045, 0.065)));
		vec2 clean_uv = vec2(1.0 - surface_uv.x, surface_uv.y);
		vec3 night = mix(texture(night_panorama, surface_uv).rgb, texture(night_panorama, clean_uv).rgb, baked_disc) * 0.025 + orbital * 0.12;
		surface = mix(texture(surface_panorama, surface_uv).rgb, texture(surface_panorama, clean_uv).rgb, baked_disc) * surface_energy;
		float horizon = pow(1.0 - abs(local_direction.y), 5.0);
		float twilight = (1.0 - smoothstep(0.0, 12.0, abs(sun_elevation))) * smoothstep(-18.0, -6.0, sun_elevation);
		float toward_sun = pow(max(0.0, dot(normalize(direction - local_up * dot(direction, local_up) + vec3(0.00001)), normalize(sun_direction - local_up * dot(sun_direction, local_up) + vec3(0.00001)))), 4.0);
		vec3 atmospheric = mix(night, surface, daylight) + vec3(0.65, 0.15, 0.025) * horizon * twilight * toward_sun;
		COLOR = mix(orbital, atmospheric, surface_blend);
		float refraction = 0.00989 * surface_blend * (1.0 - smoothstep(-1.0, 5.0, sun_elevation));
		vec3 apparent_sun = normalize(sun_direction + local_up * refraction);
		float separation = length(direction - apparent_sun);
		float disc = 1.0 - smoothstep(sun_radius * 0.95, sun_radius * 1.05, separation);
		float visibility = mix(1.0, step(-sin(horizon_dip), dot(direction, local_up)), surface_blend);
		float halo = exp(-separation * separation / (sun_radius * sun_radius * 16.0)) * 0.08;
		COLOR += sun_color.rgb * (disc * 8.0 + halo) * visibility;
		// Lunar disc: reconstruct a sphere normal on the disc and shade by the sun, so the
		// terminator follows illumination. Dim the moon in daylight so it does not compete.
		vec3 apparent_moon = normalize(moon_direction);
		float moon_separation = length(direction - apparent_moon);
		float moon_disc = 1.0 - smoothstep(moon_radius * 0.95, moon_radius * 1.05, moon_separation);
		vec3 moon_offset = direction - apparent_moon * dot(direction, apparent_moon);
		vec3 moon_normal = normalize(apparent_moon + moon_offset / max(moon_radius, 0.0001));
		float lit = smoothstep(-0.08, 0.12, dot(moon_normal, normalize(sun_direction)));
		float phase = mix(0.04, 1.0, clamp(moon_illumination, 0.0, 1.0));
		float moon_glow = exp(-moon_separation * moon_separation / (moon_radius * moon_radius * 36.0)) * 0.035;
		float moon_visibility = visibility * mix(1.0, 0.22, daylight);
		COLOR += moon_color.rgb * (moon_disc * (0.35 + 1.4 * lit * phase) + moon_glow * phase) * moon_visibility;
	}
}