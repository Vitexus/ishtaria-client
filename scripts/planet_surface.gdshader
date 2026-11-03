shader_type spatial;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform bool has_heightmap = false;
uniform float planet_radius = 6371.0;
uniform float elevation_scale = 8.0;
uniform sampler2D environment_map : filter_nearest, repeat_disable;
uniform bool has_environment = false;
uniform bool water_pass = false;
uniform bool is_detail = false;
uniform vec3 detail_direction = vec3(0.0);
uniform float detail_discard = 0.00012;
uniform vec2 wave_phase = vec2(0.0);
// Rivers and ponds of the landscape patches (surface_environment.gd `_update_patch_water`): painted on the planet so
// they show from the air and beyond the detail disk, which draws the real water near the player. Per patch the R8 mask
// (wet > 0.5), the axes of its local frame and its rectangle (offset x/z, extent x/z, metres).
uniform int patch_count = 0;
uniform sampler2D patch_water[4] : filter_nearest, repeat_disable;
uniform vec3 patch_axis_x[4];
uniform vec3 patch_axis_z[4];
uniform vec4 patch_rect[4];
varying vec3 surface_point;
varying float detail_elevation;
varying float detail_water;
varying vec3 local_point;
varying float view_distance_m;

// Local ground detail (detail disk only): CC0 Poly Haven layers, blended by slope, height and biome.
// Positions are metres on planet-fixed axes: render-origin local km * 1000 + texture_anchor, where the
// anchor is the origin reduced modulo 1024 m so every tile size below (powers of two) repeats seamlessly.
uniform bool use_textures = false;
uniform vec3 texture_anchor = vec3(0.0);
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Optional 0 A.D. Persia albedos (CC BY-SA), blended into dry / rocky ground.
uniform bool use_persia_textures = false;
uniform float persia_blend = 0.35;
uniform sampler2D tex_sand_persia : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_soil_persia : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock_persia : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Ground set "alluvial" of a datadisk world (the manifest's `ground`, announced in /world `datadisks`): the dry silt
// plain between two rivers. The five Poly Haven layers replace the grass, soil, sand and gravel of the default set.
uniform bool use_alluvial = false;
uniform sampler2D tex_alluvial_steppe : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_silt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_cracked : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

vec2 map_coordinates(vec3 direction, float size) {
		vec3 magnitude = abs(direction);
		float face;
		vec2 point;
		if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z) {
			face = direction.x >= 0.0 ? 0.0 : 1.0;
			point = vec2(direction.x >= 0.0 ? -direction.z : direction.z, direction.y);
		} else if (magnitude.y >= magnitude.z) {
			face = direction.y >= 0.0 ? 2.0 : 3.0;
			point = vec2(direction.x, direction.y >= 0.0 ? -direction.z : direction.z);
		} else {
			face = direction.z >= 0.0 ? 4.0 : 5.0;
			point = vec2(direction.z >= 0.0 ? direction.x : -direction.x, direction.y);
		}
		vec2 squared = point * point;
		vec2 difference = 2.0 * (squared - squared.yx);
		vec2 coefficient = vec2(3.0) + difference;
		vec2 cube = sign(point) * sqrt(max(0.5 * (coefficient - sqrt(max(coefficient * coefficient - 24.0 * squared, vec2(0.0)))), vec2(0.0)));
		vec2 pixel = vec2((cube.x + 1.0) * 0.5, (1.0 - cube.y) * 0.5);
		pixel = clamp(pixel * size, vec2(0.5), vec2(size - 0.5));
		return vec2((face * size + pixel.x) / (6.0 * size), pixel.y / size);
	}

float sample_height(vec3 direction) {
	return texture(heightmap, map_coordinates(direction, float(textureSize(heightmap, 0).y))).r;
}

vec2 sample_environment(vec3 direction) {
	return texture(environment_map, map_coordinates(direction, float(textureSize(environment_map, 0).y))).rg;
}

void vertex() {
	surface_point = normalize(is_detail ? NORMAL : VERTEX);
	detail_elevation = UV2.x;
	detail_water = UV2.y;
	local_point = VERTEX;
	view_distance_m = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz) * 1000.0;
	if (has_heightmap && !is_detail) {
		float elevation = (sample_height(surface_point) * 2.0 - 1.0) * elevation_scale;
		if (water_pass) {
			elevation = has_environment ? (sample_environment(surface_point).r * 2.0 - 1.0) * elevation_scale : 0.0;
			elevation += 0.001;
		}
		VERTEX = surface_point * (planet_radius + elevation);
	}
}

void fragment() {
	ALBEDO = vec3(0.22, 0.45, 0.28);
	ROUGHNESS = 1.0;
	if (has_heightmap) {
		vec3 direction = normalize(surface_point);
		if (!is_detail && length(detail_direction) > 0.5 && length(direction - detail_direction) < detail_discard) {
			discard;
		}
		float height = sample_height(direction);
		float elevation = is_detail ? detail_elevation : (height * 2.0 - 1.0) * elevation_scale;
		float snow = smoothstep(0.68, 0.85, abs(direction.y) + max(elevation, 0.0) / 6.0);
		vec3 land = mix(vec3(0.12, 0.30, 0.13), vec3(0.36, 0.39, 0.32), smoothstep(1.0, 3.5, elevation));
		land = mix(vec3(0.64, 0.65, 0.42), land, smoothstep(0.0, 0.15, elevation));
		if (has_environment) {
			int biome = int(round(sample_environment(direction).g * 7.0));
			if (biome == 4) { land = vec3(0.33, 0.49, 0.23); }
			if (biome == 5) { land = vec3(0.10, 0.27, 0.12); }
			if (biome == 6) { land = vec3(0.36, 0.39, 0.32); }
			if (biome == 7) { snow = 1.0; }
		}
		ALBEDO = mix(land, vec3(0.88, 0.94, 0.96), snow);
		vec3 slope_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(slope_normal, NORMAL) < 0.0 ? -slope_normal : slope_normal;
		if (!is_detail && !water_pass) {
			for (int index = 0; index < min(patch_count, 4); index++) {
				vec4 rect = patch_rect[index];
				vec2 local = vec2(dot(direction, patch_axis_x[index]), dot(direction, patch_axis_z[index])) * planet_radius * 1000.0 - rect.xy;
				vec2 uv = local / rect.zw + vec2(0.5);
				if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
					continue;
				}
				if (texture(patch_water[index], uv).r > 0.5) {
					// The deep colour of the detail disk's water (local_water.gdshader), so the river does not change hue at the disk's edge.
					ALBEDO = vec3(0.04, 0.19, 0.25);
					ROUGHNESS = 0.28;
				}
			}
		}
		if (is_detail && use_textures && !water_pass) {
			vec3 up = direction;
			vec3 geometric = normalize(cross(dFdx(local_point), dFdy(local_point)));
			geometric = dot(geometric, up) < 0.0 ? -geometric : geometric;
			float slope = 1.0 - dot(geometric, up);
			vec3 world = local_point * 1000.0 + texture_anchor;
			// Flat layers use the plane facing the local up axis, rock is projected from all three sides.
			vec3 axis = abs(up);
			vec2 flat_uv = axis.y >= axis.x && axis.y >= axis.z ? world.xz : (axis.x >= axis.z ? world.yz : world.xy);
			vec3 grass = texture(tex_grass, flat_uv / 4.0).rgb;
			vec3 soil = texture(tex_soil, flat_uv / 4.0).rgb;
			vec3 sand = texture(tex_sand, flat_uv / 4.0).rgb;
			vec3 gravel = texture(tex_gravel, flat_uv / 4.0).rgb;
			if (use_persia_textures) {
				float w = clamp(persia_blend, 0.0, 1.0);
				soil = mix(soil, texture(tex_soil_persia, flat_uv / 4.0).rgb, w * 0.7);
				sand = mix(sand, texture(tex_sand_persia, flat_uv / 4.0).rgb, w);
			}
			if (use_alluvial) {
				// Every layer is read at two very different scales so that the 1k pictures do not show their tiling.
				vec3 steppe = texture(tex_alluvial_steppe, flat_uv / 5.0).rgb * texture(tex_alluvial_steppe, flat_uv / 37.0).rgb * 1.9;
				vec3 silt = texture(tex_alluvial_silt, flat_uv / 5.0).rgb * texture(tex_alluvial_silt, flat_uv / 41.0).rgb * 1.9;
				vec3 cracked = texture(tex_alluvial_cracked, flat_uv / 6.0).rgb;
				float dryness = texture(tex_alluvial_silt, flat_uv / 97.0).g;
				grass = steppe;
				soil = mix(silt, cracked, smoothstep(0.45, 0.7, dryness) * 0.8);
				sand = texture(tex_alluvial_sand, flat_uv / 6.0).rgb * texture(tex_alluvial_sand, flat_uv / 43.0).rgb * 1.9;
				gravel = texture(tex_alluvial_dirt, flat_uv / 5.0).rgb * texture(tex_alluvial_dirt, flat_uv / 47.0).rgb * 1.9;
			}
			// Patches of bare soil and gravel, cheaply, from the grass picture seen at a very different scale.
			float patches = texture(tex_grass, flat_uv / 64.0).g;
			vec3 blend = pow(abs(geometric), vec3(4.0));
			blend /= blend.x + blend.y + blend.z;
			vec3 rock_x = texture(tex_rock, world.yz / 8.0).rgb;
			vec3 rock_y = texture(tex_rock, world.xz / 8.0).rgb;
			vec3 rock_z = texture(tex_rock, world.xy / 8.0).rgb;
			vec3 rock = rock_x * blend.x + rock_y * blend.y + rock_z * blend.z;
			if (use_persia_textures) {
				float w = clamp(persia_blend, 0.0, 1.0);
				vec3 persia_rock = (
					texture(tex_rock_persia, world.yz / 8.0).rgb * blend.x
					+ texture(tex_rock_persia, world.xz / 8.0).rgb * blend.y
					+ texture(tex_rock_persia, world.xy / 8.0).rgb * blend.z
				);
				rock = mix(rock, persia_rock, w);
			}
			// Land colour class: the biome tint above decides which flat layer dominates.
			float beach = 1.0 - smoothstep(0.0, 0.004, elevation);
			float dry = smoothstep(0.55, 0.62, land.r + land.g * 0.4 - land.b);
			vec3 ground = mix(mix(grass, soil, smoothstep(0.45, 0.75, patches) * 0.85), gravel, dry * 0.7);
			ground = mix(ground, sand, max(beach, dry * 0.5));
			float rock_weight = max(smoothstep(0.07, 0.22, slope), smoothstep(2.0, 3.5, elevation));
			// Loose scree gathers on the steep ground just below the bare cliffs.
			float scree = smoothstep(0.04, 0.09, slope) * (1.0 - smoothstep(0.16, 0.26, slope));
			ground = mix(ground, gravel * 0.9, scree * 0.8);
			// Sedimentary banding: rock colour steps with absolute height (4 m period repeats with the anchor).
			float strata = texture(tex_rock, vec2(0.5, detail_elevation * 1000.0 / 4.0)).g;
			rock *= mix(0.8, 1.15, smoothstep(0.35, 0.65, strata));
			vec3 textured = mix(ground, rock, rock_weight);
			// Macro variation: a 256 m view of the grass picture lightens or darkens large areas, hiding the tiling.
			float macro = texture(tex_grass, flat_uv / 256.0).g;
			textured *= mix(0.85, 1.12, macro);
			// Far away the pictures only alias: fade to the plain biome colour.
			// The alluvial set is read at several large scales and does not alias, so it stays to the edge of the
			// detail disk; a very wide macro variation breaks the tiling of the far plain.
			float near_detail = use_alluvial ? 1.0 - smoothstep(1500.0, 3500.0, view_distance_m) : 1.0 - smoothstep(120.0, 600.0, view_distance_m);
			if (use_alluvial) {
				textured *= mix(0.9, 1.1, texture(tex_alluvial_silt, flat_uv / 900.0).g);
			}
			vec3 surface = mix(land, mix(land, textured, 0.8), near_detail);
			// Snow does not stay on steep rock.
			ALBEDO = mix(surface, vec3(0.88, 0.94, 0.96), snow * (1.0 - smoothstep(0.12, 0.3, slope)));
			ROUGHNESS = mix(0.95, 0.8, rock_weight);
			// Wet bank: ground within half a metre above the water of its vertex is darker and smoother.
			float above_water_m = (detail_elevation - detail_water) * 1000.0;
			float wet = detail_water > -50.0 ? 1.0 - smoothstep(0.0, 0.5, above_water_m) : 0.0;
			ALBEDO *= mix(1.0, 0.6, wet);
			ROUGHNESS = mix(ROUGHNESS, 0.45, wet);
			// Rock relief from its normal map, whiteout-blended in model space and turned into view space.
			vec3 normal_x = texture(tex_rock_normal, world.yz / 8.0).xyz * 2.0 - 1.0;
			vec3 normal_y = texture(tex_rock_normal, world.xz / 8.0).xyz * 2.0 - 1.0;
			vec3 normal_z = texture(tex_rock_normal, world.xy / 8.0).xyz * 2.0 - 1.0;
			vec3 detailed = normalize(geometric + (vec3(0.0, normal_x.y, normal_x.x) * blend.x + vec3(normal_y.x, 0.0, normal_y.y) * blend.y + vec3(normal_z.x, normal_z.y, 0.0) * blend.z) * rock_weight * near_detail * 0.6);
			NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * detailed));
		}
		if (water_pass) {
			float level = 0.0;
			if (is_detail) {
				// The local patch carries its own water level per vertex (-100 on dry ground): rivers of a
				// landscape patch show even where the coarse cell is a river, not a lake or the sea.
				level = detail_water;
			} else if (has_environment) {
				vec2 environment = sample_environment(direction);
				int biome = int(round(environment.g * 7.0));
				if (biome != 0 && biome != 1) { discard; }
				level = (environment.r * 2.0 - 1.0) * elevation_scale;
			}
			if (elevation > level) { discard; }
			ALBEDO = mix(vec3(0.035, 0.25, 0.38), vec3(0.08, 0.43, 0.48), exp(-max(level - elevation, 0.0) * 8.0));
			vec3 wave_point = is_detail ? local_point : direction * planet_radius;
			float waves = sin(dot(wave_point, vec3(1.0, 0.7, 0.3)) * 650.0 + wave_phase.x + TIME * 0.8) * cos(dot(wave_point, vec3(0.2, 0.5, 1.0)) * 700.0 + wave_phase.y + TIME * 0.6);
			ALBEDO *= 1.0 + waves * 0.08;
			ROUGHNESS = 0.28;
		}
	}
}