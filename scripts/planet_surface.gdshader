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
// 1 on the ground of the detail disk within 300 m of water, falling to 0 at 500 m (vertex colour, surface_environment.gd).
varying float lush;
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
// Further Poly Haven ground layers (assets/terrain). Together with the five above and the five of the dry silt plain
// they are the catalogue a biome picks from: `biome_layers[biome]` holds the catalogue numbers of its base ground,
// its alternate and its accent (scripts/ground_layers.gd lists the numbers and sets the table, from the default
// ground or from the `ground_layers` of a datadisk's manifest).
uniform sampler2D tex_alluvial_steppe : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_silt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_alluvial_cracked : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_mud_leaves : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_leaves : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dry : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_laterite : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rocky : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_coast : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Per biome (3 lowland .. 7 polar) the catalogue numbers of base, alternate and accent ground (x, y, z).
uniform vec4 biome_layers[8];
// The catalogue numbers of the beach sand and of the scree below cliffs.
uniform int sand_layer = 2;
uniform int scree_layer = 3;

// One layer of the catalogue. textureGrad with derivatives taken in uniform control flow, since the callers branch.
vec3 layer_color(int index, vec2 uv, vec2 dx, vec2 dy) {
	switch (index) {
		case 0: return textureGrad(tex_grass, uv, dx, dy).rgb;
		case 1: return textureGrad(tex_soil, uv, dx, dy).rgb;
		case 2: return textureGrad(tex_sand, uv, dx, dy).rgb;
		case 3: return textureGrad(tex_gravel, uv, dx, dy).rgb;
		case 4: return textureGrad(tex_rock, uv, dx, dy).rgb;
		case 5: return textureGrad(tex_alluvial_steppe, uv, dx, dy).rgb;
		case 6: return textureGrad(tex_alluvial_silt, uv, dx, dy).rgb;
		case 7: return textureGrad(tex_alluvial_sand, uv, dx, dy).rgb;
		case 8: return textureGrad(tex_alluvial_dirt, uv, dx, dy).rgb;
		case 9: return textureGrad(tex_alluvial_cracked, uv, dx, dy).rgb;
		case 10: return textureGrad(tex_mud_leaves, uv, dx, dy).rgb;
		case 11: return textureGrad(tex_leaves, uv, dx, dy).rgb;
		case 12: return textureGrad(tex_dry, uv, dx, dy).rgb;
		case 13: return textureGrad(tex_laterite, uv, dx, dy).rgb;
		case 14: return textureGrad(tex_snow, uv, dx, dy).rgb;
		case 15: return textureGrad(tex_rocky, uv, dx, dy).rgb;
		case 16: return textureGrad(tex_coast, uv, dx, dy).rgb;
		default: return textureGrad(tex_grass_b, uv, dx, dy).rgb;
	}
}

// A layer read at two very different scales (4 m and 32 m, powers of two so the picture repeats with the anchor), the
// far one only modulating the brightness, so that the 1k pictures do not show their tiling.
vec3 tile_color(int index, vec2 uv, vec2 dx, vec2 dy) {
	vec3 near = layer_color(index, uv / 4.0, dx / 4.0, dy / 4.0);
	vec3 far = layer_color(index, uv / 32.0, dx / 32.0, dy / 32.0);
	return near * (0.6 + 0.8 * dot(far, vec3(0.3333)));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise in 0..1 with a feature size in metres (a power of two up to 1024), repeating every 1024 m like the
// pictures, so the patches do not jump when the render origin moves. `seed` is a whole number shifting the pattern.
float ground_noise(vec2 uv, float scale, float seed) {
	float period = 1024.0 / scale;
	vec2 p = uv / scale + vec2(seed, seed * 0.5 + 3.0);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 c0 = mod(cell, period);
	vec2 c1 = mod(cell + 1.0, period);
	float a = hash12(c0);
	float b = hash12(vec2(c1.x, c0.y));
	float c = hash12(vec2(c0.x, c1.y));
	float d = hash12(c1);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

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
	lush = is_detail ? COLOR.r : 0.0;
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
			// GLSL ES 3.0 (the web build's GL Compatibility renderer) only allows a literal index into
			// a sampler array. A loop bounded by the `patch_count` uniform made the whole scene shader
			// fail to compile in the browser, so nothing of the planet was drawn: keep the bound
			// constant and read each mask by its own index.
			for (int index = 0; index < 4; index++) {
				if (index >= patch_count) {
					break;
				}
				vec4 rect = patch_rect[index];
				vec2 local = vec2(dot(direction, patch_axis_x[index]), dot(direction, patch_axis_z[index])) * planet_radius * 1000.0 - rect.xy;
				vec2 uv = local / rect.zw + vec2(0.5);
				if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
					continue;
				}
				float wet = 0.0;
				if (index == 0) {
					wet = texture(patch_water[0], uv).r;
				} else if (index == 1) {
					wet = texture(patch_water[1], uv).r;
				} else if (index == 2) {
					wet = texture(patch_water[2], uv).r;
				} else {
					wet = texture(patch_water[3], uv).r;
				}
				if (wet > 0.5) {
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
			vec2 uv_dx = dFdx(flat_uv);
			vec2 uv_dy = dFdy(flat_uv);
			// Biome weights of the four nearest environment cells, bilinear with a ragged edge, so that two biomes meet
			// in a soft, uneven border and not along the straight line of a cell.
			float biome_weight[8];
			for (int k = 0; k < 8; k++) {
				biome_weight[k] = 0.0;
			}
			if (has_environment) {
				ivec2 env_size = textureSize(environment_map, 0);
				float env_face = float(env_size.y);
				vec2 env_uv = map_coordinates(direction, env_face);
				vec2 env_point = env_uv * vec2(env_size) - 0.5;
				vec2 env_cell = floor(env_point);
				vec2 env_frac = clamp(fract(env_point) + (ground_noise(flat_uv, 128.0, 0.0) - 0.5) * 0.7, 0.0, 1.0);
				float face_start = floor(env_uv.x * 6.0) * env_face;
				for (int k = 0; k < 4; k++) {
					vec2 offset = vec2(float(k & 1), float(k >> 1));
					vec2 cell = env_cell + offset;
					cell.x = clamp(cell.x, face_start, face_start + env_face - 1.0);
					cell.y = clamp(cell.y, 0.0, env_face - 1.0);
					int cell_biome = int(round(texelFetch(environment_map, ivec2(cell), 0).g * 7.0));
					float w = (k % 2 == 0 ? 1.0 - env_frac.x : env_frac.x) * (k < 2 ? 1.0 - env_frac.y : env_frac.y);
					biome_weight[clamp(cell_biome, 3, 7)] += w;
				}
			} else {
				biome_weight[3] = 1.0;
			}
			// Base, alternate and accent ground of each biome present, patched by noise at three scales.
			vec3 ground = vec3(0.0);
			float weight_sum = 0.0;
			for (int b = 3; b < 8; b++) {
				if (biome_weight[b] < 0.01) {
					continue;
				}
				ivec3 set = ivec3(biome_layers[b].xyz + vec3(0.5));
				float seed = float(b) * 37.0;
				vec3 base = tile_color(set.x, flat_uv, uv_dx, uv_dy);
				vec3 alternate = tile_color(set.y, flat_uv, uv_dx, uv_dy);
				vec3 accent = tile_color(set.z, flat_uv, uv_dx, uv_dy);
				float wide = ground_noise(flat_uv, 64.0, seed) * 0.65 + ground_noise(flat_uv, 16.0, seed + 5.0) * 0.35;
				float fine = ground_noise(flat_uv, 32.0, seed + 9.0) * 0.6 + ground_noise(flat_uv, 8.0, seed + 2.0) * 0.4;
				float broad = ground_noise(flat_uv, 256.0, seed + 4.0);
				vec3 mixed = mix(base, alternate, smoothstep(0.42, 0.58, wide * 0.7 + broad * 0.3) * 0.95);
				mixed = mix(mixed, accent, smoothstep(0.62, 0.78, fine * 0.6 + broad * 0.4) * 0.9);
				ground += mixed * biome_weight[b];
				weight_sum += biome_weight[b];
			}
			ground /= max(weight_sum, 0.001);
			// Green cover within 500 m of water, wherever the biome is dry: grass ground in two tones, ragged at its edge.
			// Beach sand, scree and bare rock below still cover it, so a stony shore stays stony.
			float green_weight = clamp(lush * (0.8 + 0.4 * ground_noise(flat_uv, 16.0, 61.0)), 0.0, 1.0);
			if (green_weight > 0.001) {
				vec3 green = mix(tile_color(0, flat_uv, uv_dx, uv_dy), tile_color(17, flat_uv, uv_dx, uv_dy), smoothstep(0.4, 0.6, ground_noise(flat_uv, 32.0, 53.0)));
				ground = mix(ground, green, green_weight);
			}
			vec3 sand = tile_color(sand_layer, flat_uv, uv_dx, uv_dy);
			vec3 gravel = tile_color(scree_layer, flat_uv, uv_dx, uv_dy);
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
			ground = mix(ground, sand, beach);
			float rock_weight = max(smoothstep(0.07, 0.22, slope), smoothstep(2.0, 3.5, elevation));
			// Loose scree gathers on the steep ground just below the bare cliffs.
			float scree = smoothstep(0.04, 0.09, slope) * (1.0 - smoothstep(0.16, 0.26, slope));
			ground = mix(ground, gravel * 0.9, scree * 0.8);
			// Sedimentary banding: rock colour steps with absolute height (4 m period repeats with the anchor).
			float strata = texture(tex_rock, vec2(0.5, detail_elevation * 1000.0 / 4.0)).g;
			rock *= mix(0.8, 1.15, smoothstep(0.35, 0.65, strata));
			vec3 textured = mix(ground, rock, rock_weight);
			// Macro variation: a 256 m view of the grass picture lightens or darkens large areas, hiding the tiling.
			float macro = ground_noise(flat_uv, 256.0, 71.0);
			textured *= mix(0.84, 1.14, macro);
			// A slow change of hue over hundreds of metres (cooler and damper, warmer and drier), visible from far and from the air.
			float tint = ground_noise(flat_uv, 512.0, 29.0) * 0.6 + ground_noise(flat_uv, 128.0, 31.0) * 0.4;
			textured *= mix(vec3(0.84, 0.88, 0.94), vec3(1.14, 1.08, 0.94), smoothstep(0.3, 0.7, tint));
			// Far away the pictures only alias: fade to the plain biome colour.
			// Every layer is read at two large scales and does not alias, so the ground stays to the edge of the
			// detail disk; a very wide macro variation breaks the tiling of the far plain.
			float near_detail = 1.0 - smoothstep(1500.0, 3500.0, view_distance_m);
			textured *= mix(0.9, 1.1, ground_noise(flat_uv, 1024.0, 13.0));
			// The plain colour under the pictures is green too near water, so the 20 % of it that shows is not dry brown.
			land = mix(land, vec3(0.30, 0.46, 0.20), lush * 0.7);
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