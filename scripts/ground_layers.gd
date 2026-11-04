extends RefCounted
## The ground layers of the detail disk (Poly Haven, CC0, assets/terrain/) and which of them each biome is drawn with.
## The numbers are the cases of `layer_color` in planet_surface.gdshader; the names are the folders, and the server's
## `GROUND_LAYERS` (story/disk.rs) lists the same names in the same order for the `ground_layers` of a datadisk manifest.

const LAYERS: Array[String] = [
	"grass_ground", "forest_ground_06", "gravelly_sand", "gravel_ground_01", "gray_rocks",
	"grass_path_2", "dry_mud_field_001", "aerial_sand", "dirt_aerial_03", "mud_cracked_dry_03",
	"brown_mud_leaves_01", "forest_leaves_02", "dry_ground_01", "red_laterite_soil_stones", "snow_02",
	"rocky_terrain_02", "coast_sand_rocks_02", "grass_path_3",
]
## The shader uniform of each layer, in the order of LAYERS.
const UNIFORMS: Array[String] = [
	"tex_grass", "tex_soil", "tex_sand", "tex_gravel", "tex_rock",
	"tex_alluvial_steppe", "tex_alluvial_silt", "tex_alluvial_sand", "tex_alluvial_dirt", "tex_alluvial_cracked",
	"tex_mud_leaves", "tex_leaves", "tex_dry", "tex_laterite", "tex_snow",
	"tex_rocky", "tex_coast", "tex_grass_b",
]
## Land biomes by the number the environment grid gives them (3 lowland ... 7 polar).
const BIOME_KEYS: Array[String] = ["lowland", "grassland", "temperate_forest", "mountain", "polar"]

## Base, alternate and accent ground per biome, then the beach sand and the scree, as layer names.
const DEFAULT := {
	"lowland": ["grass_ground", "grass_path_3", "forest_ground_06"],
	"grassland": ["grass_path_2", "grass_path_3", "dry_ground_01"],
	"temperate_forest": ["forest_ground_06", "brown_mud_leaves_01", "forest_leaves_02"],
	"mountain": ["gravel_ground_01", "rocky_terrain_02", "dirt_aerial_03"],
	"polar": ["snow_02", "gravelly_sand", "gravel_ground_01"],
	"beach": ["gravelly_sand"],
	"scree": ["gravel_ground_01"],
}
## The dry silt plain between two rivers (a datadisk's `ground: alluvial`).
const ALLUVIAL := {
	"lowland": ["dry_mud_field_001", "grass_path_2", "mud_cracked_dry_03"],
	"grassland": ["grass_path_2", "dry_ground_01", "dry_mud_field_001"],
	"temperate_forest": ["forest_ground_06", "brown_mud_leaves_01", "grass_path_2"],
	"mountain": ["dirt_aerial_03", "red_laterite_soil_stones", "rocky_terrain_02"],
	"polar": ["snow_02", "gravelly_sand", "gravel_ground_01"],
	"beach": ["aerial_sand"],
	"scree": ["dirt_aerial_03"],
}

static func index_of(layer_name: String) -> int:
	return LAYERS.find(layer_name)

## Loads every layer's picture into the material (once, with the world's first material).
static func load_textures(material: ShaderMaterial) -> void:
	for index in LAYERS.size():
		var layer: String = LAYERS[index]
		material.set_shader_parameter(UNIFORMS[index], load("res://assets/terrain/%s/%s_diff_1k.jpg" % [layer, layer]))

## The table a world draws with: the set named by the datadisk (`ground`), then the datadisk's own `ground_layers`
## laid over it. Unknown names are ignored, so an older client keeps what it can draw.
static func table_for(ground: String, overrides: Variant) -> Dictionary:
	var table: Dictionary = (ALLUVIAL if ground == "alluvial" else DEFAULT).duplicate(true)
	if overrides is Dictionary:
		for key: Variant in overrides:
			if not table.has(key) or not overrides[key] is Array:
				continue
			var names: Array = []
			for layer: Variant in overrides[key]:
				if layer is String and index_of(layer) >= 0:
					names.append(layer)
			if not names.is_empty():
				table[key] = names
	return table

## Hands the table to the shader: per biome the numbers of base, alternate and accent ground (a missing one repeats
## the previous), and the beach and scree layers.
static func apply(material: ShaderMaterial, table: Dictionary) -> void:
	var rows := PackedVector4Array()
	rows.resize(8)
	for slot in BIOME_KEYS.size():
		var names: Array = table[BIOME_KEYS[slot]]
		var numbers: Array[float] = []
		for position in 3:
			numbers.append(float(index_of(names[mini(position, names.size() - 1)])))
		rows[3 + slot] = Vector4(numbers[0], numbers[1], numbers[2], 0.0)
	material.set_shader_parameter("biome_layers", rows)
	material.set_shader_parameter("sand_layer", index_of(table["beach"][0]))
	material.set_shader_parameter("scree_layer", index_of(table["scree"][0]))
