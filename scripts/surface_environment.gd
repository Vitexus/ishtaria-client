extends Node3D

signal objects_failed(message: String)
## The characters were replaced (loaded or cleared); the minimap lists them again.
signal npcs_changed
## The props of the region changed (loaded, cleared or a datadisk model arrived); the minimap
## draws their roads and buildings again.
signal props_changed
## The baked water picture changed (a new region was shown or the world was cleared).
signal water_changed

const RADIUS := 6371.0
const BIOMES := ["ocean", "lake", "river", "beach", "grassland", "forest", "mountain", "snow"]
const MAX_OBJECTS := 512
## How often the routes of walking animals are asked for again; a route covers a minute at least.
const ANIMAL_REFRESH_S := 30.0
const MAX_WAYPOINTS := 40
const PORTAL_MODEL := "res://assets/kenney/survival-kit/Models/GLB format/structure-metal-doorway.glb"
const PORTAL_STATES := ["building", "open", "closed"]
## Scale of the gate model: the model is half a metre tall, so the portal is four metres tall.
const PORTAL_SCALE_M := 8.0
## Default detail disk (km) without a datadisk landscape patch. Large enough to walk and to
## hide the coarse globe underfoot; small enough that the mesh stays fine (~5.5 m cells).
const DETAIL_RADIUS := 0.7
## Cap when a landscape patch (Uruk's 6 km floodplain) would otherwise demand a huge disk.
const DETAIL_RADIUS_MAX := 2.4
## Outer band (km) where the detail mesh eases toward the unpatched planet so its rim does not
## stand as a floating plateau with a hard shadow over the coarse globe.
const DETAIL_EDGE_FEATHER := 0.08
const DETAIL_SEGMENTS := 128
## Upper bound when the disk grows with a patch (keeps rebuild cost bounded).
const DETAIL_SEGMENTS_MAX := 192
const MEMORIALS := preload("res://scripts/survival_panel.gd")
const CHARACTERS := preload("res://scripts/character_catalog.gd")
const FACE := preload("res://scripts/character_face.gd")
const MAX_NPCS := 64
const MAX_PROPS := 3000
## Kenney kits whose models the server's generated places are built from.
## Models with a light: where the lamp hangs (model units, scaled like the model).
const LAMP_MODELS := {"graveyard.lightpost-single": [0.0, 1.1, 0.25]}
## Gas lamps: a dim, warm, slightly flickering flame; halogen-strong lights blow out the pale gravestones.
const LAMP_RANGE_M := 7.0
## The scene is in kilometres and Godot's omni falloff is pow(distance, -attenuation) in scene units, so the
## energy is tiny: 3e-6 = intensity 3.0 at one metre (0.75 at two, 0.08 at six) with attenuation 2.
const LAMP_ENERGY := 3.0e-6
const LAMP_FLICKER := 0.07
const PROP_KITS := {"graveyard": "graveyard-kit", "town": "fantasy-town-kit", "castle": "castle-kit", "retro": "retro-fantasy-kit", "pirate": "pirate-kit", "survival": "survival-kit/Models/GLB format", "food": "food-kit/Models/GLB format", "quaternius": "", "zeroad": ""}
## What the minimap draws of the generated places: the road modules of the towns and the
## structural props (walls, roofs, stalls, fountains, towers, crypts, fences, quaternius
## buildings). Trees, graves and other small scenery stay off the map. Mirrors the models
## that `ishtaria-server/src/scenery.rs` generates.
const ROAD_MODELS := ["town.road"]
const BUILDING_KEYWORDS := ["wall", "roof", "chimney", "stall", "fountain", "tower", "crypt", "fence", "structure", "house", "barracks", "castle", "fortress", "temple"]
## The baked region picture covers this many metres around the centre when no landscape patch
## is loaded; with a patch (Uruk) it grows to the patch so the minimap can show the city and river.
const WATER_MAP_PIXELS := 256
const WATER_MAP_EXTENT_M := 420.0
const WATER_MAP_EXTENT_MAX_M := 3500.0
## Water on the minimap: the same colour the map legend shows.
const WATER_MAP_COLOR := Color(0.18, 0.45, 0.65, 0.92)
## Built / tilled ground from a datadisk clear mask (streets, houses, fields).
const SETTLEMENT_MAP_COLOR := Color(0.55, 0.52, 0.42, 0.75)

var heightmap: Image:
	set(value):
		_stop_detail_work()
		heightmap = value
var environment: Dictionary = {}
var catalog: Array[Dictionary] = []
var placements: Array[Dictionary] = []
## Fish circling around their place: {"node", "radius", "speed", "phase"} with the radius in model units.
var _swimmers: Array[Dictionary] = []
## Land animals walking along the waypoints the server sent: {"id", "node", "placement", "player", "route", "walking"}
## with the route as [unix milliseconds, x, y, z] in metres.
var _walkers: Array[Dictionary] = []
## Server clock minus the local clock, in milliseconds.
var _clock_offset_ms := 0.0
var _animals_request: HTTPRequest
var _animals_elapsed := 0.0
var land_material: ShaderMaterial
var water_material: ShaderMaterial
var detail: Node3D
## Decorative grass tufts around the region centre (see grass_cover.gd).
var grass: Node3D
var grass_cover := preload("res://scripts/grass_cover.gd").new(self)
var objects: Node3D
var memorials: Node3D
## Characters of story datadisks, standing near the player.
var npcs: Node3D
## Buildings, fences, ships and other props of towns, graveyards and harbours.
var props: Node3D
## Lamps of the generated places: warm lights (and glowing bulbs) that burn at night.
var lamps: Node3D
## Things that characters built or planted: {"node", "entry"} for each.
var placed: Node3D
var _placed_entries: Array[Dictionary] = []
## Items dropped on the ground nearby (server `loot` list).
var loot: Node3D
var _loot_entries: Array[Dictionary] = []
var _prop_entries: Array = []
var _lamp_positions: Array = []
var _night := 0.0
var _lit_materials := {}
var _lamp_time := 0.0
var _prop_scenes: Dictionary = {}
## Model footprints in model units, by scene path or datadisk media URL: the x and z extents of
## the meshes, so the minimap can draw a rectangle of the real size.
var _prop_footprints: Dictionary = {}
## Buildings that datadisks bring (`disk:<disk>:<path>`): the models fetched so far, and the
## placements waiting for a model that is still being downloaded.
var _structure_models: Dictionary = {}
var _structure_waiting: Dictionary = {}
## Footprints (model units) of the fetched datadisk buildings, by their media URL.
var _structure_footprints: Dictionary = {}
## The minimap's baked water: the picture of streams, lakes and the sea around the region's
## centre, with the tangent frame it was drawn in. Empty when the world has no region yet.
## Keys: texture (ImageTexture), centre (Vector3, world metres), tangent, forward (Vector3),
## metres_per_pixel (float).
var water_map: Dictionary = {}
## Turns a translation key into text (set by the game once the story is loaded).
var npc_text := Callable()
## Asks the story client for a media file (a character model); answered through `media_ready`.
var fetch_media := Callable()
var _npc_entries: Array = []
## Characters of the story that walk along the waypoints the server sent: {"id", "index" (of _npc_entries and the
## children of `npcs`), "route", "walking", "player" (the animation player of its model, or null)}.
var _npc_walkers: Array[Dictionary] = []
## Characters the player talks to: id -> {"released_at": 0 while the conversation is on, otherwise when it ended (msec), "home": the
## orientation before it}. They stand still and face the player; afterwards they go on to where they were going (see `hold_npc`).
var _held_npcs: Dictionary = {}
## A released character waits for the server's next route (it goes on from where it stood), but no longer than this.
const HOLD_RELEASE_MS := 4000
var portals: Node3D
var target := Vector3.ZERO
var server_url := ""
## Bearer token for `/world/objects` so the server can unlock Easter-egg clips; empty for guests.
var auth_token := ""
var objects_loaded := false
## Soft ambient one-shots while an NPC stands (not gated by the server).
const COMMON_GESTURES := ["Point", "Sad", "Happy", "Salute"]
var _origin_metres: Array = []
var _models: Dictionary = {}
var _objects_request: HTTPRequest
## Landscape patches of datadisk places (ADR 0013): their metadata arrives with the region,
## their 16-bit height and water grids are downloaded directly (Godot would load them as half
## floats and lose the decimetre step) and replace the base terrain inside their rectangle.
var _terrain_patches: Array = []
var _terrain_requests: Dictionary = {}
var _region_generation := 0
var _scenes: Dictionary = {}
var _detail_vertices := PackedVector3Array()
## Radius (km) and segment count of the detail disk last built; grow with landscape patches.
var _detail_radius := DETAIL_RADIUS
var _detail_segments := DETAIL_SEGMENTS
## Computes the detail disk on a worker thread (the game); the tests leave it off and get the mesh at once.
var async_detail := false
var _detail_generation := 0
var _detail_pending := false
var _detail_tasks: Array = []
var _detail_anchor: Array = []
var _memorial_entries: Array = []
var _portal_entries: Array = []
var _portal_request: HTTPRequest
var _memorial_request: HTTPRequest
var _memorial_elapsed := 0.0

func _exit_tree() -> void:
	_stop_detail_work()

## Drops any detail disk still being computed and waits for its worker: the workers read the heightmap,
## environment and landscape patches, so those may only change while none runs.
func _stop_detail_work() -> void:
	_detail_generation += 1
	_detail_pending = false
	for id: int in _detail_tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_detail_tasks.clear()

func _ready() -> void:
	load_catalog("res://assets/world_objects.json")
	detail = Node3D.new()
	add_child(detail)
	detail.top_level = true
	grass = Node3D.new()
	grass.name = "Grass"
	add_child(grass)
	grass.top_level = true
	objects = Node3D.new()
	add_child(objects)
	objects.top_level = true
	memorials = Node3D.new()
	add_child(memorials)
	memorials.top_level = true
	npcs = Node3D.new()
	add_child(npcs)
	npcs.top_level = true
	props = Node3D.new()
	add_child(props)
	props.top_level = true
	lamps = Node3D.new()
	add_child(lamps)
	lamps.top_level = true
	portals = Node3D.new()
	add_child(portals)
	portals.top_level = true
	placed = Node3D.new()
	add_child(placed)
	placed.top_level = true
	loot = Node3D.new()
	loot.name = "Loot"
	add_child(loot)
	loot.top_level = true

func _process(delta: float) -> void:
	_swim()
	_wander(delta)
	_walk_npcs(delta)
	_face_held(delta)
	_animals_elapsed += delta
	if _animals_elapsed >= ANIMAL_REFRESH_S:
		_animals_elapsed = 0.0
		_request_animals()
	_flicker_lamps(delta)
	_memorial_elapsed += delta
	if _memorial_elapsed >= 5.0:
		_memorial_elapsed = 0.0
		_request_memorials()
		refresh_portals()

func load_catalog(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("objects") is Array:
		return false
	var validated: Array[Dictionary] = []
	var identifiers := {}
	for entry: Variant in parsed.objects:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("scene") is String or not entry.get("biomes") is Array:
			return false
		if entry.id.is_empty() or identifiers.has(entry.id) or not entry.scene.begins_with("res://") or not ResourceLoader.exists(entry.scene, "PackedScene"):
			return false
		for biome: Variant in entry.biomes:
			if not biome is String or not biome in BIOMES:
				return false
		for key in ["weight", "scale_m", "max_slope"]:
			var value: Variant = entry.get(key)
			if not (value is float or value is int) or not is_finite(float(value)) or value <= 0 or value > 1000:
				return false
		identifiers[entry.id] = entry
		if entry.has("animation") and (not entry.animation is String or entry.animation.is_empty() or entry.animation.length() > 40):
			return false
		if entry.has("swim_radius_m"):
			var radius: Variant = entry.swim_radius_m
			if not (radius is float or radius is int) or not is_finite(float(radius)) or radius <= 0 or radius > 50:
				return false
		if entry.has("metallic"):
			var metallic: Variant = entry.metallic
			if not (metallic is float or metallic is int) or not is_finite(float(metallic)) or metallic < 0 or metallic > 1:
				return false
		validated.append(entry)
	if validated.is_empty() or validated.size() > 512:
		return false
	catalog = validated
	_models = identifiers
	_scenes.clear()
	return true

func apply_environment(data: Variant, expected_sha256: String, expected_seed: String) -> bool:
	_stop_detail_work()
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2) or data.get("heightmap_sha256") != expected_sha256 or data.get("seed") != expected_seed:
		return false
	var size: Variant = data.get("face_size")
	if not (size is float or size is int) or size < 1 or size > 64 or float(size) != floorf(float(size)):
		return false
	var count := int(size) * int(size) * 6
	for key in ["elevation_m", "water_m", "downstream", "flow", "biomes"]:
		if not data.get(key) is Array or data[key].size() != count:
			return false
		for value: Variant in data[key]:
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) != floorf(float(value)):
				return false
	for index in count:
		if data.biomes[index] < 0 or data.biomes[index] > 7 or data.elevation_m[index] < -8000 or data.elevation_m[index] > 8000 or data.water_m[index] < -8001 or data.water_m[index] > 8000 or data.downstream[index] < -1 or data.downstream[index] >= count or data.downstream[index] == index or data.flow[index] < 1 or data.flow[index] > count:
			return false
	environment = data.duplicate(true)
	_clear_objects()
	var atlas := Image.create(int(size) * 6, int(size), false, Image.FORMAT_RGBAF)
	for face in 6:
		for row in int(size):
			for column in int(size):
				var index := face * int(size) * int(size) + row * int(size) + column
				atlas.set_pixel(face * int(size) + column, row, Color((data.water_m[index] + 8000.0) / 16000.0, data.biomes[index] / 7.0, 0, 1))
	var texture := ImageTexture.create_from_image(atlas)
	for material in [land_material, water_material]:
		material.set_shader_parameter("environment_map", texture)
		material.set_shader_parameter("has_environment", true)
	_build_rivers()
	show_region(target)
	return true

func clear_world() -> void:
	_stop_detail_work()
	environment.clear()
	heightmap = null
	target = Vector3.ZERO
	server_url = ""
	_origin_metres.clear()
	placements.clear()
	_clear_placed()
	_clear_loot()
	for child in get_children():
		# Nodes of the owner that live under the environment (such as the other players) stay.
		if child != detail and child != grass and child != objects and child != memorials and child != portals and child != npcs and child != props and child != lamps and child != placed and child != loot and not child.has_meta("persistent"):
			remove_child(child)
			child.queue_free()
	_clear_region()
	for material in [land_material, water_material]:
		material.set_shader_parameter("has_environment", false)
		material.set_shader_parameter("detail_direction", Vector3.ZERO)

func cube_point(face: int, horizontal: float, vertical: float) -> Vector3:
	var point: Vector3
	match face:
		0: point = Vector3(1, vertical, -horizontal)
		1: point = Vector3(-1, vertical, horizontal)
		2: point = Vector3(horizontal, 1, -vertical)
		3: point = Vector3(horizontal, -1, vertical)
		4: point = Vector3(horizontal, vertical, 1)
		_: point = Vector3(-horizontal, vertical, -1)
	return Vector3(
		point.x * sqrt(1.0 - point.y * point.y / 2.0 - point.z * point.z / 2.0 + point.y * point.y * point.z * point.z / 3.0),
		point.y * sqrt(1.0 - point.x * point.x / 2.0 - point.z * point.z / 2.0 + point.x * point.x * point.z * point.z / 3.0),
		point.z * sqrt(1.0 - point.x * point.x / 2.0 - point.y * point.y / 2.0 + point.x * point.x * point.y * point.y / 3.0))

func coordinates(direction: Vector3) -> Vector3:
	var mapped := _coordinates64([direction.x, direction.y, direction.z])
	return Vector3(mapped[0], mapped[1], mapped[2])

func _coordinates64(direction: Array) -> Array:
	var radius := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
	var point: Array = [float(direction[0]) / radius, float(direction[1]) / radius, float(direction[2]) / radius]
	var magnitude: Array = [absf(point[0]), absf(point[1]), absf(point[2])]
	var face: int
	var pair: Array
	if magnitude[0] >= magnitude[1] and magnitude[0] >= magnitude[2]:
		face = 0 if point[0] >= 0 else 1
		pair = [-point[2] if face == 0 else point[2], point[1]]
	elif magnitude[1] >= magnitude[2]:
		face = 2 if point[1] >= 0 else 3
		pair = [point[0], -point[2] if face == 2 else point[2]]
	else:
		face = 4 if point[2] >= 0 else 5
		pair = [point[0] if face == 4 else -point[0], point[1]]
	var squared: Array = [float(pair[0]) * pair[0], float(pair[1]) * pair[1]]
	var result: Array = [0.0, 0.0]
	for axis in 2:
		var coefficient: float = 3.0 + 2.0 * (squared[axis] - squared[1 - axis])
		result[axis] = signf(pair[axis]) * sqrt(maxf(0.5 * (coefficient - sqrt(maxf(coefficient * coefficient - 24.0 * squared[axis], 0.0))), 0.0))
	return [face, clampf((result[0] + 1.0) * 0.5, 0, 1), clampf((1.0 - result[1]) * 0.5, 0, 1)]

func elevation(direction: Vector3) -> float:
	return elevation64([direction.x, direction.y, direction.z])

func relief64(direction: Array, base_metres: float, seed: String) -> float:
	var radius := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
	var point: Array = [float(direction[0]) / radius * 6371000.0, float(direction[1]) / radius * 6371000.0, float(direction[2]) / radius * 6371000.0]
	var hash := 0
	for byte in seed.to_utf8_buffer():
		hash = (hash * 31 + byte) % 997
	var phase := float(hash) * TAU / 997.0
	var coast := clampf(base_metres / 150.0, 0.0, 1.0)
	var fade := coast * coast * (3.0 - 2.0 * coast)
	return fade * (9.0 * sin((point[0] * 0.73 + point[1] * 0.41 + point[2] * 0.55) / 93.0 + phase) * sin((point[0] * -0.38 + point[1] * 0.87 + point[2] * 0.31) / 127.0 - phase) + 3.0 * sin((point[0] * 0.21 + point[1] * -0.52 + point[2] * 0.83) / 37.0 + phase))

## Base elevation in kilometres from the planet heightmap (and shared relief), without landscape patches.
func elevation64_base(direction: Array) -> float:
	if heightmap == null:
		return 0.0
	var mapped := _coordinates64(direction)
	var size := heightmap.get_height()
	var horizontal := clampf(mapped[1] * size - 0.5, 0, size - 1)
	var vertical := clampf(mapped[2] * size - 0.5, 0, size - 1)
	var column := int(horizontal)
	var row := int(vertical)
	var offset := int(mapped[0]) * size
	var upper := lerpf(roundf(heightmap.get_pixel(offset + column, row).r * 255.0), roundf(heightmap.get_pixel(offset + mini(column + 1, size - 1), row).r * 255.0), horizontal - column)
	var lower := lerpf(roundf(heightmap.get_pixel(offset + column, mini(row + 1, size - 1)).r * 255.0), roundf(heightmap.get_pixel(offset + mini(column + 1, size - 1), mini(row + 1, size - 1)).r * 255.0), horizontal - column)
	var base := lerpf(upper, lower, vertical - row) * 16000.0 / 255.0 - 8000.0
	var metres := base + (relief64(direction, base, environment.seed) if environment.get("version") == 2 else 0.0)
	return metres / 1000.0

func elevation64(direction: Array) -> float:
	# The landscape patches look the ground up by a unit direction. A point in metres (the camera's) must be reduced to one, or the
	# patch is missed and the ground comes out as the coarse base map: the camera is then lifted by the difference (17 m in Uruk) and
	# cannot look level until it is moved far away.
	var metres := elevation64_base(direction) * 1000.0
	var length := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
	if length <= 0.0:
		return metres / 1000.0
	var unit: Array = [float(direction[0]) / length, float(direction[1]) / length, float(direction[2]) / length]
	return (metres + _terrain_offset_m(unit, metres)) / 1000.0

func environment_index(direction: Vector3) -> int:
	var mapped := coordinates(direction)
	var size := int(environment.face_size)
	return int(mapped.x) * size * size + mini(int(mapped.z * size), size - 1) * size + mini(int(mapped.y * size), size - 1)

func _cell_direction(index: int) -> Vector3:
	var size := int(environment.face_size)
	return cube_point(index / (size * size), (index % size + 0.5) * 2.0 / size - 1.0, 1.0 - (int(index / size) % size + 0.5) * 2.0 / size)

func _build_rivers() -> void:
	for child in get_children():
		if child.name == "Rivers":
			remove_child(child)
			child.queue_free()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := 0
	for index in environment.biomes.size():
		var destination := int(environment.downstream[index])
		if int(environment.biomes[index]) != 2 or destination < 0:
			continue
		var start := _cell_direction(index)
		var end := _cell_direction(destination)
		var sideways := start.cross(end).normalized()
		var width := minf(0.00015, 0.00002 * sqrt(float(environment.flow[index])))
		for step in 16:
			var first := start.slerp(end, step / 16.0).normalized()
			var second := start.slerp(end, (step + 1.0) / 16.0).normalized()
			var corners: Array[Vector3] = []
			for direction in [first - sideways * width, first + sideways * width, second - sideways * width, second + sideways * width]:
				var unit: Vector3 = direction.normalized()
				var water := maxf(elevation(unit), 0.0)
				var sample_index := environment_index(unit)
				if int(environment.biomes[sample_index]) == 1:
					water = maxf(water, environment.water_m[sample_index] / 1000.0)
				corners.append(unit * (RADIUS + water + 0.003))
			for corner in [0, 2, 1, 1, 2, 3]:
				tool.set_normal(corners[corner].normalized())
				tool.add_vertex(corners[corner])
				vertices += 1
	if vertices == 0:
		return
	var rivers := MeshInstance3D.new()
	rivers.name = "Rivers"
	rivers.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.25, 0.38)
	material.roughness = 0.28
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rivers.material_override = material
	add_child(rivers)

func _cancel_objects() -> void:
	_region_generation += 1
	if is_instance_valid(_objects_request):
		_objects_request.cancel_request()
		_objects_request.queue_free()
	_objects_request = null
	if is_instance_valid(_memorial_request):
		_memorial_request.cancel_request()
		_memorial_request.queue_free()
	_memorial_request = null
	if is_instance_valid(_portal_request):
		_portal_request.cancel_request()
		_portal_request.queue_free()
	_portal_request = null

## Portals stay while the objects are replaced; they are cleared with the region.
func _clear_portals() -> void:
	_portal_entries.clear()
	for child in portals.get_children():
		portals.remove_child(child)
		child.queue_free()

func _clear_objects() -> void:
	placements.clear()
	_swimmers.clear()
	_walkers.clear()
	objects_loaded = false
	_memorial_entries.clear()
	_clear_npcs()
	_clear_props()
	_clear_loot()
	for child in memorials.get_children():
		memorials.remove_child(child)
		child.queue_free()
	for child in objects.get_children():
		objects.remove_child(child)
		child.queue_free()

func _clear_region(clear_objects: bool = true) -> void:
	_cancel_objects()
	_detail_vertices.clear()
	if clear_objects:
		_clear_objects()
		_clear_portals()
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	for child in grass.get_children():
		grass.remove_child(child)
		child.queue_free()
	land_material.set_shader_parameter("detail_direction", Vector3.ZERO)
	water_material.set_shader_parameter("detail_direction", Vector3.ZERO)
	water_map = {}
	water_changed.emit()

func show_region(direction: Vector3) -> void:
	target = direction
	_clear_region(direction == Vector3.ZERO or heightmap == null or environment.is_empty())
	if direction == Vector3.ZERO or heightmap == null or environment.is_empty():
		return
	_build_detail()
	_request_objects(direction.normalized())

## How far the patched detail disk reaches (km). Grows with the largest landscape patch so a
## city like Uruk is not cut by a 700 m circle, but stays capped for mesh cost.
func _compute_detail_radius() -> float:
	var radius := DETAIL_RADIUS
	for patch: Dictionary in _terrain_patches:
		var half_km := maxf(float(patch.extent[0]), float(patch.extent[1])) * 0.5 / 1000.0
		# About 70 % of the half-extent covers the walled city without dragging in the whole floodplain.
		radius = maxf(radius, minf(DETAIL_RADIUS_MAX, half_km * 0.7))
	return radius

func _compute_detail_segments(radius_km: float) -> int:
	var segments := int(round(float(DETAIL_SEGMENTS) * radius_km / DETAIL_RADIUS / 8.0) * 8.0)
	return clampi(segments, DETAIL_SEGMENTS, DETAIL_SEGMENTS_MAX)

## Rebuilds the local detail disk. With `async_detail` the vertices are computed on a worker thread and
## swapped in when ready (the old disk stays, shifted to the new render origin, meanwhile); otherwise the
## mesh is ready when this returns, which is what the headless tests rely on.
func _build_detail() -> void:
	_detail_generation += 1
	if target == Vector3.ZERO or heightmap == null or environment.is_empty():
		_detail_pending = false
		_detail_vertices.clear()
		for child in detail.get_children():
			detail.remove_child(child)
			child.queue_free()
		detail.position = Vector3.ZERO
		for child in grass.get_children():
			grass.remove_child(child)
			child.queue_free()
		return
	_detail_radius = _compute_detail_radius()
	_detail_segments = _compute_detail_segments(_detail_radius)
	var unit := target.normalized()
	var reference := Vector3.UP if absf(unit.y) < 0.9 else Vector3.RIGHT
	var tangent := reference.cross(unit).normalized()
	var job := {
		"generation": _detail_generation,
		"unit": unit,
		"tangent": tangent,
		"forward": unit.cross(tangent).normalized(),
		"radius": _detail_radius,
		"segments": _detail_segments,
		"feather": maxf(DETAIL_EDGE_FEATHER, _detail_radius * 0.06),
		"anchor": (_origin_metres.duplicate() if _origin_metres.size() == 3 else [0.0, 0.0, 0.0]),
		"map_extent": _map_extent_m(),
	}
	if not async_detail:
		_detail_pending = false
		_finish_detail(_compute_detail(job))
		return
	_detail_pending = true
	# A task must be waited for once to release it, so finished ones are collected here, not just forgotten.
	var running: Array = []
	for id: int in _detail_tasks:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			running.append(id)
	_detail_tasks = running
	_detail_tasks.append(WorkerThreadPool.add_task(func() -> void: _finish_detail.call_deferred(_compute_detail(job))))

## Worker-safe: reads the heightmap, environment and landscape patches, writes nothing shared.
func _compute_detail(job: Dictionary) -> Dictionary:
	var unit: Vector3 = job.unit
	var tangent: Vector3 = job.tangent
	var forward: Vector3 = job.forward
	var radius_km: float = job.radius
	var segments: int = job.segments
	var feather: float = job.feather
	var anchor: Array = job.anchor
	var count := (segments + 1) * (segments + 1)
	var land := PackedVector3Array()
	var land_normals := PackedVector3Array()
	var land_uv2 := PackedVector2Array()
	var water_vertices := PackedVector3Array()
	var water_uv2 := PackedVector2Array()
	land.resize(count)
	land_normals.resize(count)
	water_vertices.resize(count)
	land_uv2.resize(count)
	water_uv2.resize(count)
	for row in segments + 1:
		for column in segments + 1:
			var horizontal: float = (float(column) / segments * 2.0 - 1.0) * radius_km
			var vertical: float = (float(row) / segments * 2.0 - 1.0) * radius_km
			var direction: Array = []
			for axis in 3:
				direction.append(float(unit[axis]) * RADIUS + float(tangent[axis]) * horizontal + float(forward[axis]) * vertical)
			var length64 := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
			for axis in 3:
				direction[axis] /= length64
			var point := Vector3(direction[0], direction[1], direction[2])
			var height := elevation64(direction)
			# Ease the rim toward the unpatched globe so a landscape patch does not read as a floating card.
			var radial := Vector2(horizontal, vertical).length()
			var edge := 1.0
			if feather > 0.0 and radial > radius_km - feather:
				edge = clampf((radius_km - radial) / feather, 0.0, 1.0)
				edge = edge * edge * (3.0 - 2.0 * edge)
				height = lerpf(elevation64_base(direction), height, edge)
			var water_level := _detail_water_km(direction, point, height)
			if edge < 1.0 and is_finite(water_level):
				var base_water := float(environment.water_m[environment_index(point)]) / 1000.0
				water_level = lerpf(base_water, water_level, edge)
			# Dry ground carries no water: the vertex sinks under the land and the shader discards it.
			var water := (water_level if is_finite(water_level) else height - 0.01) + 0.001
			var index := row * (segments + 1) + column
			land_normals[index] = point
			land_uv2[index] = Vector2(height, water_level if is_finite(water_level) else -100.0)
			land[index] = _position_from(anchor, [direction[0] * (RADIUS + height) * 1000.0, direction[1] * (RADIUS + height) * 1000.0, direction[2] * (RADIUS + height) * 1000.0])
			water_uv2[index] = Vector2(height, water_level if is_finite(water_level) else -100.0)
			water_vertices[index] = _position_from(anchor, [direction[0] * (RADIUS + water) * 1000.0, direction[1] * (RADIUS + water) * 1000.0, direction[2] * (RADIUS + water) * 1000.0])
	# A disk, not a square: the old axis-aligned patch looked like a huge floating tile from above.
	var indices := PackedInt32Array()
	for row in segments:
		for column in segments:
			var mid_h: float = ((float(column) + 0.5) / segments * 2.0 - 1.0) * radius_km
			var mid_v: float = ((float(row) + 0.5) / segments * 2.0 - 1.0) * radius_km
			if Vector2(mid_h, mid_v).length() > radius_km:
				continue
			var first := row * (segments + 1) + column
			indices.append_array(PackedInt32Array([first, first + segments + 1, first + 1, first + 1, first + segments + 1, first + segments + 2]))
	var tufts: Dictionary = grass_cover.compute(unit, anchor)
	var water_image := _bake_water_image(unit, tangent, forward, float(job.map_extent))
	return {"job": job, "grass": tufts, "water_image": water_image, "land": land, "normals": land_normals, "uv2": land_uv2, "water": water_vertices, "water_uv2": water_uv2, "indices": indices}

func _build_detail_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uv2: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Main thread: takes a computed disk, unless a newer build has been asked for since.
func _finish_detail(result: Dictionary) -> void:
	var job: Dictionary = result.job
	if int(job.generation) != _detail_generation or not is_inside_tree():
		return
	_detail_pending = false
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	detail.position = Vector3.ZERO
	grass.position = Vector3.ZERO
	grass_cover.apply(grass, result.grass)
	_detail_anchor = job.anchor
	var unit: Vector3 = job.unit
	var mesh := _build_detail_mesh(result.land, result.normals, result.uv2, result.indices)
	_detail_vertices = result.land
	var local_land := MeshInstance3D.new()
	local_land.mesh = mesh
	var material := land_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("is_detail", true)
	# Texture coordinates are planet-fixed metres, so the (changing) render origin is added back, modulo the tile period.
	material.set_shader_parameter("texture_anchor", Vector3(fposmod(float(job.anchor[0]), 1024.0), fposmod(float(job.anchor[1]), 1024.0), fposmod(float(job.anchor[2]), 1024.0)))
	local_land.material_override = material
	detail.add_child(local_land)
	var local_water := MeshInstance3D.new()
	local_water.mesh = _build_detail_mesh(result.water, result.normals, result.water_uv2, result.indices)
	var water_detail := ShaderMaterial.new()
	water_detail.shader = preload("res://scripts/local_water.gdshader")
	var anchor: Array = job.anchor
	water_detail.set_shader_parameter("wave_phase", Vector2(fposmod((anchor[0] + anchor[1] * 0.7 + anchor[2] * 0.3) * 0.65, TAU), fposmod((anchor[0] * 0.2 + anchor[1] * 0.5 + anchor[2]) * 0.7, TAU)))
	local_water.material_override = water_detail
	detail.add_child(local_water)
	var discard_radius: float = float(job.radius) * 1.05 / RADIUS
	land_material.set_shader_parameter("detail_direction", unit)
	land_material.set_shader_parameter("detail_discard", discard_radius)
	water_material.set_shader_parameter("detail_direction", unit)
	water_material.set_shader_parameter("detail_discard", discard_radius)
	_apply_water_map(result.water_image, unit, job.tangent, job.forward, float(job.map_extent))

## The water surface (km above the planet's radius) under a point given in metres from the planet's centre, or NAN on
## dry ground: the same rule the water mesh and the server use, so what swims is what is drawn as water.
func water_surface_km(coordinates_metres: Array) -> float:
	var radius := sqrt(float(coordinates_metres[0]) * coordinates_metres[0] + float(coordinates_metres[1]) * coordinates_metres[1] + float(coordinates_metres[2]) * coordinates_metres[2])
	if radius <= 0.0 or heightmap == null or environment.is_empty():
		return NAN
	var direction: Array = [float(coordinates_metres[0]) / radius, float(coordinates_metres[1]) / radius, float(coordinates_metres[2]) / radius]
	var height := elevation64(direction)
	var level := _detail_water_km(direction, Vector3(direction[0], direction[1], direction[2]), height)
	return level if is_finite(level) and level > height else NAN

func ground_position64(coordinates_metres: Array) -> Vector3:
	var radius := sqrt(float(coordinates_metres[0]) * coordinates_metres[0] + float(coordinates_metres[1]) * coordinates_metres[1] + float(coordinates_metres[2]) * coordinates_metres[2])
	var direction: Array = [float(coordinates_metres[0]) / radius, float(coordinates_metres[1]) / radius, float(coordinates_metres[2]) / radius]
	var height := elevation64(direction)
	var projected: Array = []
	for axis in 3:
		projected.append(direction[axis] * (RADIUS + height) * 1000.0)
	var point := _render_position(projected)
	# While a new disk is computed the old vertices sit in the previous origin's frame: the exact height will do.
	if _detail_vertices.is_empty() or target == Vector3.ZERO or _detail_pending:
		return point
	var up := Vector3(direction[0], direction[1], direction[2])
	var unit := target.normalized()
	var reference := Vector3.UP if absf(unit.y) < 0.9 else Vector3.RIGHT
	var tangent := reference.cross(unit).normalized()
	var forward := unit.cross(tangent).normalized()
	var denominator := up.dot(unit)
	if denominator <= 0:
		return point
	var column := int(floor((up.dot(tangent) * RADIUS / denominator / _detail_radius + 1.0) * 0.5 * _detail_segments))
	var row := int(floor((up.dot(forward) * RADIUS / denominator / _detail_radius + 1.0) * 0.5 * _detail_segments))
	for sample_row in range(maxi(0, row - 1), mini(_detail_segments, row + 2)):
		for sample_column in range(maxi(0, column - 1), mini(_detail_segments, column + 2)):
			var first := sample_row * (_detail_segments + 1) + sample_column
			for triangle in [[first, first + _detail_segments + 1, first + 1], [first + 1, first + _detail_segments + 1, first + _detail_segments + 2]]:
				var hit: Variant = Geometry3D.ray_intersects_triangle(point + up * 0.002, -up, _detail_vertices[triangle[0]], _detail_vertices[triangle[1]], _detail_vertices[triangle[2]])
				if hit is Vector3 and hit.distance_to(point) < 0.002:
					return hit
	return point

func _request_objects(unit: Vector3) -> void:
	if server_url.is_empty():
		return
	_objects_request = HTTPRequest.new()
	_objects_request.timeout = 8.0
	_objects_request.max_redirects = 0
	_objects_request.body_size_limit = 2 * 1024 * 1024
	_objects_request.request_completed.connect(_on_objects_received.bind(_region_generation))
	add_child(_objects_request)
	var point := unit * RADIUS * 1000.0
	var headers := PackedStringArray()
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)
	if _objects_request.request(server_url + "/world/objects?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z], headers) != OK:
		_cancel_objects()
		objects_failed.emit("Surface objects unavailable")

func _on_objects_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _region_generation:
		return
	if is_instance_valid(_objects_request):
		_objects_request.queue_free()
	_objects_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not apply_objects(JSON.parse_string(body.get_string_from_utf8())):
		objects_failed.emit("Surface objects unavailable")

func apply_objects(data: Variant) -> bool:
	if environment.is_empty() or not data is Dictionary or data.get("version") != 1 or data.get("heightmap_sha256") != environment.heightmap_sha256 or data.get("seed") != environment.seed:
		return false
	if not data.get("objects") is Array or data.objects.size() > MAX_OBJECTS:
		return false
	var identities := {}
	var accepted: Array = []
	for entry: Variant in data.objects:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or identities.has(entry.id) or not entry.get("model") is String or not _models.has(entry.model):
			return false
		identities[entry.id] = true
		if not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
		var point := Vector3(entry.position[0] / 1000.0, entry.position[1] / 1000.0, entry.position[2] / 1000.0)
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1 or (target != Vector3.ZERO and point.normalized().distance_to(target.normalized()) * RADIUS > _detail_radius * 1.2):
			return false
		for key in ["scale_m", "yaw", "collision_radius_m", "biome"]:
			var value: Variant = entry.get(key)
			if not (value is float or value is int) or not is_finite(float(value)):
				return false
		if entry.scale_m <= 0 or entry.scale_m > 20 or entry.yaw < 0 or entry.yaw > TAU or entry.collision_radius_m < 0 or entry.collision_radius_m > 20 or entry.biome < 0 or entry.biome > 7 or entry.biome != floor(entry.biome):
			return false
		# Farm animals graze wherever their settlement is. An empty biomes list means the
		# model is overlay-only (e.g. Early Dynastic wildlife): the server may place it
		# in any biome, and the catalog does not spawn it from global biome weights.
		# Skip a mismatched biome instead of rejecting the whole region: dry datadisk
		# patches over coarse river/sea cells can still carry beach overlay flora.
		var allowed: Array = _models[entry.model].biomes
		if not ":farm:" in entry.id and not allowed.is_empty() and not BIOMES[int(entry.biome)] in allowed:
			continue
		if entry.has("wander") and _parse_route(entry.wander).is_empty():
			return false
		accepted.append(entry)
	_clock_offset_ms = _server_offset(data.get("server_time_ms"))
	_clear_objects()
	for entry: Dictionary in accepted:
		_place_object(entry)
	if not apply_memorials(data.get("memorials", [])):
		return false
	apply_npcs(data.get("npcs", []))
	apply_props(data.get("props", []))
	apply_areas(data.get("areas", []))
	apply_loot(data.get("loot", []))
	if not apply_terrains(data.get("terrains", [])):
		return false
	objects_loaded = true
	return true

func _request_memorials() -> void:
	if server_url.is_empty() or target == Vector3.ZERO or not objects_loaded or is_instance_valid(_memorial_request):
		return
	_memorial_request = HTTPRequest.new()
	_memorial_request.timeout = 4.0
	_memorial_request.max_redirects = 0
	_memorial_request.body_size_limit = 65536
	_memorial_request.request_completed.connect(_on_memorials_received.bind(_region_generation))
	add_child(_memorial_request)
	var point := target.normalized() * RADIUS * 1000.0
	if _memorial_request.request(server_url + "/world/memorials?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z]) != OK:
		_memorial_request.queue_free()
		_memorial_request = null

func _on_memorials_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _region_generation:
		return
	if is_instance_valid(_memorial_request):
		_memorial_request.queue_free()
	_memorial_request = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		apply_memorials(JSON.parse_string(body.get_string_from_utf8()))

## Requests the portals near the region; also called when a pact changes.
func refresh_portals() -> void:
	if server_url.is_empty() or target == Vector3.ZERO or not objects_loaded or is_instance_valid(_portal_request):
		return
	_portal_request = HTTPRequest.new()
	_portal_request.timeout = 4.0
	_portal_request.max_redirects = 0
	_portal_request.body_size_limit = 65536
	_portal_request.request_completed.connect(_on_portals_received.bind(_region_generation))
	add_child(_portal_request)
	var point := target.normalized() * RADIUS * 1000.0
	if _portal_request.request(server_url + "/world/portals?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z]) != OK:
		_portal_request.queue_free()
		_portal_request = null

func _on_portals_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _region_generation:
		return
	if is_instance_valid(_portal_request):
		_portal_request.queue_free()
	_portal_request = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		apply_portals(JSON.parse_string(body.get_string_from_utf8()))

## Draws the portals the server reports: under construction, open and closed ruins.
func apply_portals(data: Variant) -> bool:
	if not data is Array or data.size() > 64:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("name") is String or not entry.get("peer") is String or not entry.get("state") in PORTAL_STATES or not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			return false
	if data == _portal_entries:
		return true
	for child in portals.get_children():
		portals.remove_child(child)
		child.queue_free()
	_portal_entries = data.duplicate(true)
	var scene: PackedScene = load(PORTAL_MODEL)
	for entry: Dictionary in data:
		var placement := Node3D.new()
		placement.name = "Portal_" + String(entry.name).validate_node_name()
		placement.position = _render_position(entry.position)
		var up := Vector3(entry.position[0], entry.position[1], entry.position[2]).normalized()
		placement.quaternion = Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, float(String(entry.name).hash() % 628) / 100.0)
		placement.scale = Vector3.ONE * PORTAL_SCALE_M / 1000.0
		var model: Node3D = scene.instantiate()
		_tint_portal(model, entry.state)
		placement.add_child(model)
		portals.add_child(placement)
	return true

## Open portals glow, portals under construction are plain metal and ruins are dark.
func _tint_portal(model: Node, state: String) -> void:
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface)
			if not source is StandardMaterial3D:
				continue
			var material := source.duplicate() as StandardMaterial3D
			match state:
				"open":
					material.emission_enabled = true
					material.emission = Color(0.2, 0.8, 1.0)
					material.emission_energy_multiplier = 1.4
				"closed":
					material.albedo_color = Color(0.35, 0.35, 0.38)
			instance.set_surface_override_material(surface, material)

func apply_memorials(data: Variant) -> bool:
	if not data is Array or data.size() > 128:
		return false
	var identities := {}
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry.id.is_valid_int() or int(entry.id) <= 0 or identities.has(entry.id) or not entry.get("player_name") is String or not MEMORIALS.MODELS.has(entry.get("kind")):
			return false
		identities[entry.id] = true
		if not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1 or (target != Vector3.ZERO and point.normalized().distance_to(target.normalized()) * RADIUS > _detail_radius * 1.02):
			return false
	if data == _memorial_entries:
		return true
	for child in memorials.get_children():
		memorials.remove_child(child)
		child.queue_free()
	_memorial_entries = data.duplicate(true)
	for entry: Dictionary in data:
		var placement := Node3D.new()
		placement.name = "Grave" + entry.id
		placement.position = _render_position(entry.position)
		var up := Vector3(entry.position[0], entry.position[1], entry.position[2]).normalized()
		placement.quaternion = Quaternion(Vector3.UP, up)
		placement.scale = Vector3.ONE / 1000.0
		placement.add_child(MEMORIALS.create_memorial(entry.kind))
		memorials.add_child(placement)
	return true

## Characters of the story. A malformed entry is skipped; it never spoils the region.
func apply_npcs(data: Variant) -> bool:
	_clear_npcs()
	if not data is Array or data.size() > MAX_NPCS:
		return false
	var identities := {}
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or identities.has(entry.id) or not entry.get("name_key") is String:
			continue
		if not entry.get("character") is String or not CHARACTERS.is_valid(entry.character) or not entry.get("position") is Array or entry.position.size() != 3:
			continue
		var finite := true
		for value: Variant in entry.position:
			finite = finite and (value is float or value is int) and is_finite(float(value)) and absf(value) <= 7000000.0
		for key in ["yaw", "scale_m"]:
			finite = finite and (entry.get(key) is float or entry.get(key) is int) and is_finite(float(entry[key]))
		if not finite or entry.scale_m <= 0 or entry.scale_m > 6 or entry.yaw < 0 or entry.yaw > TAU:
			continue
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			continue
		identities[entry.id] = true
		var model := CHARACTERS.create_model(entry.character)
		if model == null:
			continue
		var placement := Node3D.new()
		placement.name = ("Npc" + entry.id).validate_node_name()
		placement.position = _render_position(entry.position)
		placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
		placement.scale = Vector3.ONE * (float(entry.scale_m) / 1.8) / 1000.0
		placement.add_child(model)
		_attach_face(model)
		var label := Label3D.new()
		label.name = "Name"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 12
		# Just above the head, whatever the character pack's proportions.
		var head := CHARACTERS.head_height(model)
		label.position = Vector3(0, head * 1.08, 0)
		label.no_depth_test = false
		label.text = _npc_name(entry.name_key)
		placement.add_child(label)
		_attach_health_bar(placement, entry, head)
		npcs.add_child(placement)
		_npc_entries.append(entry.duplicate(true))
		if entry.has("wander"):
			var route := _parse_route(entry.wander)
			if not route.is_empty():
				_npc_walkers.append({
					"id": entry.id,
					"index": _npc_entries.size() - 1,
					"route": route,
					"walking": false,
					"player": _npc_player(model),
					"gesture_until": 0,
					"gesture_clip": "",
				})
		if entry.get("model") != null and fetch_media.is_valid() and preload("res://scripts/story_client.gd").valid_media_url(entry.model) and entry.model.ends_with(".glb"):
			fetch_media.call(entry.model)
	npcs_changed.emit()
	return true

## A character model arrived: it replaces the pack character of the NPCs that name it.
## Only the NPCs of the current region are looked at, so a late answer cannot change anything else.
func media_ready(url: String, resource: Resource) -> void:
	if not resource is PackedScene or not url.ends_with(".glb"):
		return
	if _structure_waiting.has(url):
		_structure_ready(url, resource)
		return
	for index in _npc_entries.size():
		if _npc_entries[index].get("model") != url:
			continue
		var placement := npcs.get_child(index)
		var model := (resource as PackedScene).instantiate() as Node3D
		if model == null:
			continue
		for child in placement.get_children():
			if child is Node3D and not child is Label3D and child.name != "HealthBar":
				placement.remove_child(child)
				child.queue_free()
		# A datadisk's model is authored in metres; the pack characters are larger in client units.
		model.scale *= CHARACTERS.GLTF_UNITS_PER_METRE
		placement.add_child(model)
		_attach_face(model)
		# A rigged datadisk model breathes and looks around; one without clips stays as it is.
		var clips := _animate(model, "Idle", String(_npc_entries[index].id))
		for walker in _npc_walkers:
			if walker.index == index:
				walker.player = clips
				walker.walking = false
		var label := placement.get_node_or_null("Name") as Label3D
		var head := CHARACTERS.head_height(model) * model.scale.y
		if label != null:
			label.position = Vector3(0, head * 1.08, 0)
		_attach_health_bar(placement, _npc_entries[index], head)

## Health bar above the name: green for a friend (escort), red for a foe; hidden when absent.
func _attach_health_bar(placement: Node3D, entry: Dictionary, head: float) -> void:
	var old := placement.get_node_or_null("HealthBar")
	if old != null:
		placement.remove_child(old)
		old.queue_free()
	var health: Variant = entry.get("health")
	if not health is Dictionary:
		return
	var current: Variant = health.get("current")
	var maximum: Variant = health.get("max")
	var relation := str(health.get("relation", ""))
	if not (current is float or current is int) or not (maximum is float or maximum is int):
		return
	var max_hp := float(maximum)
	if max_hp <= 0.0:
		return
	var ratio := clampf(float(current) / max_hp, 0.0, 1.0)
	var root := Node3D.new()
	root.name = "HealthBar"
	root.position = Vector3(0, head * 1.08 + 0.14, 0)
	var bg := MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(0.45, 0.045, 0.012)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.08, 0.08, 0.1, 0.85)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bg_mat
	root.add_child(bg)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.42 * maxf(ratio, 0.02), 0.032, 0.014)
	fill.mesh = fill_mesh
	# Left-align the fill inside the background while billboarded.
	fill.position = Vector3(-0.21 * (1.0 - ratio), 0, 0.001)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if relation == "friend":
		fill_mat.albedo_color = Color(0.28, 0.88, 0.35)
	else:
		fill_mat.albedo_color = Color(0.92, 0.22, 0.2)
	fill.material_override = fill_mat
	root.add_child(fill)
	placement.add_child(root)

## Updates one character's health bar from a server or event payload without rebuilding the region.
func set_npc_health(npc_id: String, current: int, maximum: int, relation: String) -> void:
	var index := -1
	for i in _npc_entries.size():
		var entry_id := str(_npc_entries[i].get("id", ""))
		if entry_id == npc_id:
			index = i
			break
		if ":" in entry_id and entry_id.get_slice(":", 1) == npc_id:
			index = i
			break
		if ":" in npc_id and npc_id.get_slice(":", 1) == entry_id:
			index = i
			break
	if index < 0 or index >= npcs.get_child_count():
		return
	var entry: Dictionary = _npc_entries[index]
	if current >= maximum and relation != "foe":
		entry.erase("health")
	else:
		entry["health"] = {"current": current, "max": maximum, "relation": relation}
	_npc_entries[index] = entry
	var placement := npcs.get_child(index) as Node3D
	var label := placement.get_node_or_null("Name") as Label3D
	var head := 1.6
	if label != null:
		head = label.position.y / 1.08
	_attach_health_bar(placement, entry, head)

## Applies health fields from a fresh `/world/objects` npc list onto the current characters.
func sync_npc_health(data: Variant) -> void:
	if not data is Array:
		return
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String:
			continue
		var health: Variant = entry.get("health")
		if health == null:
			# Apology or healed escort: hide the bar once the server stops announcing it.
			set_npc_health(entry.id, 100, 100, "friend")
			continue
		if not health is Dictionary:
			continue
		var current: Variant = health.get("current")
		var maximum: Variant = health.get("max")
		var relation := str(health.get("relation", "foe"))
		if (current is float or current is int) and (maximum is float or maximum is int):
			set_npc_health(entry.id, int(current), int(maximum), relation)

## Landscape patches the server announces for the region (ADR 0013): their grids are the
## disk's own 16-bit PNGs, fetched apart from `fetch_media` (which would hand over Godot's
## half-float image and lose the decimetre step), and kept while the region keeps naming them.
func apply_terrains(data: Variant) -> bool:
	_stop_detail_work()
	if not data is Array or data.size() > 8:
		return false
	var patches := []
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("place") is String or entry.place.is_empty() \
				or not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 7000000.0:
				return false
		if not entry.get("height_m") is float or not is_finite(entry.height_m):
			return false
		if not entry.get("extent_m") is Array or entry.extent_m.size() != 2 or not entry.get("offset_m") is Array or entry.offset_m.size() != 2:
			return false
		for key in ["extent_m", "offset_m"]:
			for value: Variant in entry[key]:
				if not (value is float or value is int) or not is_finite(float(value)):
					return false
		if entry.extent_m[0] < 100.0 or entry.extent_m[0] > 10000.0 or entry.extent_m[1] < 100.0 or entry.extent_m[1] > 10000.0:
			return false
		if absf(float(entry.offset_m[0])) > 5000.0 or absf(float(entry.offset_m[1])) > 5000.0:
			return false
		if not entry.get("feather_m") is float or not is_finite(entry.feather_m) or entry.feather_m < 10.0 or entry.feather_m > 500.0:
			return false
		if not entry.get("visible_m") is float or not is_finite(entry.visible_m) or entry.visible_m < 100.0 or entry.visible_m > 5000.0:
			return false
		if not entry.get("heightmap") is String or not preload("res://scripts/story_client.gd").valid_media_url(entry.heightmap) or not entry.heightmap.ends_with(".png"):
			return false
		if entry.get("water") != null and (not entry.water is String or not preload("res://scripts/story_client.gd").valid_media_url(entry.water) or not entry.water.ends_with(".png")):
			return false
		if entry.get("clear") != null and (not entry.clear is String or not preload("res://scripts/story_client.gd").valid_media_url(entry.clear) or not entry.clear.ends_with(".png")):
			return false
		var anchor := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		patches.append({
			"place": entry.place,
			"anchor": [anchor.x, anchor.y, anchor.z],
			"anchor_height_m": float(entry.height_m),
			"extent": [float(entry.extent_m[0]), float(entry.extent_m[1])],
			"offset": [float(entry.offset_m[0]), float(entry.offset_m[1])],
			"feather": float(entry.feather_m),
			# The axes turn a unit direction: the anchor is a position, not yet one.
			"axes": _terrain_axes([anchor.normalized().x, anchor.normalized().y, anchor.normalized().z]),
			"heightmap_url": entry.heightmap,
			"water_url": entry.get("water", ""),
			"clear_url": entry.get("clear", ""),
			"grid": null,
			"water_grid": null,
			"clear_image": null,
			"width": 0,
			"height": 0
		})
	for patch: Dictionary in patches:
		var old: Dictionary = {}
		for previous: Dictionary in _terrain_patches:
			if previous.place == patch.place:
				old = previous
		if not old.is_empty() and old.heightmap_url == patch.heightmap_url and old.water_url == patch.water_url and old.get("clear_url", "") == patch.clear_url:
			patch.grid = old.grid
			patch.water_grid = old.water_grid
			patch.clear_image = old.get("clear_image")
			patch.width = old.width
			patch.height = old.height
	_terrain_patches = patches
	var rebuild := false
	for patch: Dictionary in patches:
		if patch.grid == null:
			_terrain_fetch(patch.heightmap_url)
		else:
			rebuild = true
		if patch.water_url != "" and patch.water_grid == null:
			_terrain_fetch(patch.water_url)
		if patch.clear_url != "" and patch.clear_image == null:
			_terrain_fetch(patch.clear_url)
	if rebuild:
		_build_detail()
	return true

## Downloads one terrain grid; the answer is decoded into the patch that asked for it.
func _terrain_fetch(url: String) -> void:
	if server_url.is_empty() or _terrain_requests.has(url) or url.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.body_size_limit = 4 << 20
	_terrain_requests[url] = request
	add_child(request)
	request.request_completed.connect(_terrain_received.bind(url))
	if request.request(server_url + url) != OK:
		request.queue_free()
		_terrain_requests.erase(url)

func _terrain_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, url: String) -> void:
	_stop_detail_work()
	if _terrain_requests.get(url) is HTTPRequest:
		(_terrain_requests[url] as HTTPRequest).queue_free()
		_terrain_requests.erase(url)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var clear_only := false
	for patch: Dictionary in _terrain_patches:
		if url == String(patch.get("clear_url", "")):
			var image := Image.new()
			if image.load_png_from_buffer(body) != OK:
				return
			patch.clear_image = image
			clear_only = true
	if clear_only:
		if target != Vector3.ZERO:
			var unit := target.normalized()
			var reference := Vector3.UP if absf(unit.y) < 0.9 else Vector3.RIGHT
			var tangent := reference.cross(unit).normalized()
			_bake_water_map(unit, tangent, unit.cross(tangent).normalized())
		return
	var grid := _terrain_decode_png16(body)
	if grid.is_empty():
		return
	for patch: Dictionary in _terrain_patches:
		var water: bool = url == String(patch.water_url)
		if not water and url != String(patch.heightmap_url):
			continue
		if patch.width > 0 and (patch.width != grid[0] or patch.height != grid[1]):
			continue
		patch.width = grid[0]
		patch.height = grid[1]
		if water:
			patch.water_grid = grid[2]
		else:
			patch.grid = grid[2]
	_build_detail()

## A minimal 16-bit greyscale PNG decoder (no interlace): Godot's own loader keeps only a half
## float per pixel and would flatten the decimetre step the patch is built of. One row is the
## PNG filter byte followed by big-endian 16-bit samples; values come back shifted by -32768.
func _terrain_decode_png16(body: PackedByteArray) -> Array:
	if body.size() < 64 or body.slice(0, 8) != PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return []
	var offset := 8
	var width := 0
	var height := 0
	var depth := 0
	var color := 0
	var interlace := 0
	var compressed := PackedByteArray()
	while offset + 8 <= body.size():
		var length := int(body[offset]) << 24 | int(body[offset + 1]) << 16 | int(body[offset + 2]) << 8 | int(body[offset + 3])
		var kind := body.slice(offset + 4, offset + 8).get_string_from_ascii()
		offset += 8
		if kind == "IHDR":
			var header := body.slice(offset, offset + length)
			width = int(header[0]) << 24 | int(header[1]) << 16 | int(header[2]) << 8 | int(header[3])
			height = int(header[4]) << 24 | int(header[5]) << 16 | int(header[6]) << 8 | int(header[7])
			depth = header[8]
			color = header[9]
			interlace = header[12]
		elif kind == "IDAT":
			compressed.append_array(body.slice(offset, offset + length))
		offset += length + 4
	if depth != 16 or color != 0 or interlace != 0 or width < 16 or height < 16 or width * height > 4 << 20:
		return []
	var stride := width * 2
	# Compression mode 1 is DEFLATE (zlib), matching the PNG IDAT stream.
	var raw := compressed.decompress((stride + 1) * height, 1)
	if raw.size() != (stride + 1) * height:
		return []
	var rows := PackedByteArray()
	rows.resize(stride * height)
	for row in height:
		var filter := raw[row * (stride + 1)]
		var source := row * (stride + 1) + 1
		var target := row * stride
		for column in stride:
			var value := int(raw[source + column])
			# PNG unfiltering works on reconstructed bytes: two back is the same channel (bpp = 2).
			var left := int(rows[target + column - 2]) if column >= 2 else 0
			var above := int(rows[target - stride + column]) if row > 0 else 0
			var above_left := int(rows[target - stride + column - 2]) if row > 0 and column >= 2 else 0
			match filter:
				0:
					pass
				1:
					value = (value + left) & 0xFF
				2:
					value = (value + above) & 0xFF
				3:
					value = (value + ((left + above) >> 1)) & 0xFF
				4:
					var distance := left + above - above_left
					var left_miss := absi(distance - left)
					var above_miss := absi(distance - above)
					var corner_miss := absi(distance - above_left)
					var near := left
					if above_miss < left_miss or corner_miss < left_miss:
						near = above if above_miss <= corner_miss else above_left
					value = (value + near) & 0xFF
				_:
					return []
			rows[target + column] = value
	var grid := PackedFloat32Array()
	grid.resize(width * height)
	for pixel in width * height:
		grid[pixel] = float((int(rows[pixel * 2]) << 8 | int(rows[pixel * 2 + 1])) - 32768)
	return [width, height, grid]

## The client's local +X and +Z axes of a patch anchor, mirroring the server's `client_axes`
## (a Rodrigues turn of the world axes about the axis from +Y to the anchor).
func _terrain_axes(up: Array) -> Array:
	var cos_v := clampf(float(up[1]), -1.0, 1.0)
	var axis := [float(up[2]), 0.0, -float(up[0])]
	var norm := sqrt(axis[0] * axis[0] + axis[2] * axis[2])
	if norm < 1.0e-12:
		return [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0]] if cos_v > 0.0 else [[1.0, 0.0, 0.0], [0.0, 0.0, -1.0]]
	var k := [axis[0] / norm, 0.0, axis[2] / norm]
	var sin_v := sqrt(1.0 - cos_v * cos_v)
	var rotate := func(vector: Array) -> Array:
		var cross := [k[1] * vector[2] - k[2] * vector[1], k[2] * vector[0] - k[0] * vector[2], k[0] * vector[1] - k[1] * vector[0]]
		var dot: float = k[0] * float(vector[0]) + k[1] * float(vector[1]) + k[2] * float(vector[2])
		var turned := []
		for axis_index in 3:
			turned.append(vector[axis_index] * cos_v + cross[axis_index] * sin_v + k[axis_index] * dot * (1.0 - cos_v))
		return turned
	return [rotate.call([1.0, 0.0, 0.0]), rotate.call([0.0, 0.0, 1.0])]

## Local metres of a direction from a patch's centre and its blend weight (1.0 in the feathered
## core, easing to 0.0 at the edge), or an empty array outside the patch.
func _terrain_local(patch: Dictionary, direction: Array) -> Array:
	var axes: Array = patch.axes
	var x := 6371000.0 * (float(direction[0]) * float(axes[0][0]) + float(direction[1]) * float(axes[0][1]) + float(direction[2]) * float(axes[0][2])) - float(patch.offset[0])
	var z := 6371000.0 * (float(direction[0]) * float(axes[1][0]) + float(direction[1]) * float(axes[1][1]) + float(direction[2]) * float(axes[1][2])) - float(patch.offset[1])
	var half_x := float(patch.extent[0]) * 0.5
	var half_z := float(patch.extent[1]) * 0.5
	if absf(x) > half_x or absf(z) > half_z:
		return []
	var ease := func(distance: float, edge: float) -> float:
		var weight := clampf((edge - distance) / float(patch.feather), 0.0, 1.0)
		return weight * weight * (3.0 - 2.0 * weight)
	return [x, z, ease.call(absf(x), half_x) * ease.call(absf(z), half_z)]

## How many metres the landscape patches shift the ground in a direction (0.0 without a patch),
## blending the patch over the base terrain across the feather margin.
func _terrain_offset_m(direction: Array, metres: float) -> float:
	for patch: Dictionary in _terrain_patches:
		if patch.grid == null:
			continue
		var local: Array = _terrain_local(patch, direction)
		if local.is_empty() or local[2] == 0.0:
			continue
		var grid: PackedFloat32Array = patch.grid
		var width := int(patch.width)
		var height := int(patch.height)
		var horizontal := clampf((float(local[0]) + float(patch.extent[0]) * 0.5) / float(patch.extent[0]) * width - 0.5, 0.0, width - 1)
		var vertical := clampf((float(local[1]) + float(patch.extent[1]) * 0.5) / float(patch.extent[1]) * height - 0.5, 0.0, height - 1)
		var column := int(horizontal)
		var row := int(vertical)
		# Bilinear corners must stay inside the grid: at the south/east edge, row+1 / column+1
		# would otherwise index past the last sample (PackedFloat32Array out of bounds).
		var corner := func(at_column: int, at_row: int) -> float:
			return float(grid[mini(at_row, height - 1) * width + mini(at_column, width - 1)])
		var west: float = corner.call(column, row)
		var east: float = corner.call(column + 1, row)
		var north: float = corner.call(column, row + 1)
		var south: float = corner.call(column + 1, row + 1)
		var upper: float = west + (east - west) * (horizontal - column)
		var lower: float = north + (south - north) * (horizontal - column)
		var sample: float = upper + (lower - upper) * (vertical - row)
		var patched: float = float(patch.anchor_height_m) + sample * 0.1
		return (patched - metres) * float(local[2])
	return 0.0

## The water surface of a patch in a direction, in metres, or `NAN` where no patch says water.
func _terrain_water_m(direction: Array) -> float:
	for patch: Dictionary in _terrain_patches:
		if patch.water_grid == null:
			continue
		var local: Array = _terrain_local(patch, direction)
		if local.is_empty():
			continue
		var width := int(patch.width)
		var height := int(patch.height)
		var column := int(clampf((float(local[0]) + float(patch.extent[0]) * 0.5) / float(patch.extent[0]) * width, 0.0, width - 1))
		var row := int(clampf((float(local[1]) + float(patch.extent[1]) * 0.5) / float(patch.extent[1]) * height, 0.0, height - 1))
		var level: float = (patch.water_grid as PackedFloat32Array)[row * width + column]
		if level > -32768.0:
			return float(patch.anchor_height_m) + level * 0.1
	return NAN

## A model with blend shapes for the eyes and the mouth blinks and talks.
func _attach_face(model: Node3D) -> void:
	var face := FACE.new()
	face.name = "Face"
	model.add_child(face)
	if not face.setup(model):
		model.remove_child(face)
		face.free()

## The character of a conversation starts or stops talking (it has a face to move, or nothing happens).
func set_npc_talking(npc_id: String, talking: bool) -> void:
	for index in _npc_entries.size():
		if _npc_entries[index].id != npc_id:
			continue
		var face := npcs.get_child(index).find_child("Face", true, false)
		if face != null:
			face.talking = talking

## The path of a generated place's model, or an empty string when it is not bundled.
static func prop_path(model: Variant) -> String:
	if not model is String or model.length() > 60:
		return ""
	var parts: PackedStringArray = model.split(".")
	if parts.size() != 2 or not PROP_KITS.has(parts[0]) or not parts[1].is_valid_filename() or parts[1].contains("/") or parts[1].contains("."):
		return ""
	var path := "res://assets/kenney/%s/%s.glb" % [PROP_KITS[parts[0]], parts[1]]
	if parts[0] == "zeroad":
		# 0 A.D. props (CC BY-SA 3.0): bridges, flora, fauna and structures from tools/zeroad-*.py.
		for folder in ["bridges", "flora", "fauna", "structures"]:
			var candidate := "res://assets/zeroad/%s/%s.glb" % [folder, parts[1]]
			if ResourceLoader.exists(candidate):
				path = candidate
				break
	elif parts[0] == "quaternius":
		# A model has a folder of its own, or is one of the ready-made buildings.
		path = "res://assets/quaternius/%s/Models/%s.glb" % [parts[1], parts[1]]
		if not ResourceLoader.exists(path):
			path = "res://assets/quaternius/buildings/Models/%s.glb" % parts[1]
	return path if ResourceLoader.exists(path) else ""

## The media URL of a datadisk building (`disk:<disk>:<path>`), or an empty string.
static func structure_url(model: Variant) -> String:
	if not model is String or model.length() > 160 or not model.begins_with("disk:"):
		return ""
	var parts: PackedStringArray = model.split(":")
	if parts.size() != 3 or parts[1].is_empty() or not parts[2].begins_with("media/models/") or not parts[2].ends_with(".glb"):
		return ""
	var url := "/story/media/%s/%s" % [parts[1], parts[2]]
	return url if preload("res://scripts/story_client.gd").valid_media_url(url) else ""

## Buildings and props of the places nearby. A malformed or unknown entry is skipped.
## Places with background music near the player: id, centre (metres), radius and track.
var areas: Array = []

func apply_areas(data: Variant) -> bool:
	areas = []
	if not data is Array or data.size() > 16:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("position") is Array or entry.position.size() != 3:
			return false
		var radius: Variant = entry.get("radius_m")
		var music: Variant = entry.get("music")
		if not (radius is float or radius is int) or radius <= 0 or radius > 6000 or not music is Dictionary or not music.get("loop") is bool or not music.get("title_key") is String or not preload("res://scripts/story_client.gd").valid_media_url(music.get("url")):
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
	areas = data.duplicate(true)
	return true

## The area whose music is loudest at a point (metres) with its hearing level, or an empty dictionary.
func area_at(metres: Vector3) -> Dictionary:
	var best := {}
	var best_level := 0.0
	for area: Dictionary in areas:
		var centre := Vector3(area.position[0], area.position[1], area.position[2])
		var level: float = preload("res://scripts/area_music.gd").level_for(centre.distance_to(metres), float(area.radius_m))
		if level > best_level:
			best_level = level
			best = {"area": area, "level": level}
	return best

func apply_props(data: Variant) -> bool:
	_clear_props()
	if not data is Array or data.size() > MAX_PROPS:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("position") is Array or entry.position.size() != 3:
			continue
		var path := prop_path(entry.get("model"))
		var url := structure_url(entry.get("model"))
		var finite := not path.is_empty() or not url.is_empty()
		for value: Variant in entry.get("position", []):
			finite = finite and (value is float or value is int) and is_finite(float(value)) and absf(value) <= 7000000.0
		for key in ["yaw", "scale_m"]:
			finite = finite and (entry.get(key) is float or entry.get(key) is int) and is_finite(float(entry[key]))
		if not finite or entry.scale_m <= 0.05 or entry.scale_m > 20:
			continue
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			continue
		var placement := Node3D.new()
		placement.position = _render_position(entry.position)
		placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
		placement.scale = Vector3.ONE * float(entry.scale_m) / 1000.0
		if not url.is_empty():
			props.add_child(placement)
			_prop_entries.append(entry.duplicate(true))
			_place_structure(placement, url)
			continue
		if not _prop_scenes.has(path):
			_prop_scenes[path] = load(path)
		var model: Node = (_prop_scenes[path] as PackedScene).instantiate()
		if not model is Node3D:
			model.free()
			placement.free()
			continue
		_light_materials(model)
		placement.add_child(model)
		props.add_child(placement)
		_prop_entries.append(entry.duplicate(true))
		if LAMP_MODELS.has(entry.model):
			_add_lamp(entry)
	props_changed.emit()
	return true

## Roads and buildings of the generated places for the minimap: the position in metres (from
## the planet's centre), the yaw in radians, and the side lengths of the footprint in metres.
## Props the map does not show (trees, graves, crates, ships) are left out.
func map_props() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _prop_entries:
		var kind := _map_prop_kind(entry.get("model"))
		if kind.is_empty():
			continue
		var size := _prop_footprint_m(entry)
		if size == Vector2.ZERO:
			continue
		result.append({
			"kind": kind,
			"position": Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2])),
			"yaw": float(entry.yaw),
			"size": size,
		})
	return result

## "road", "building" or "": what the minimap draws of a prop's model.
static func _map_prop_kind(model: Variant) -> String:
	if not model is String:
		return ""
	if model in ROAD_MODELS:
		return "road"
	# A datadisk structure is always a building: its model name (`disk:.../<name>.glb`)
	# says nothing about walls, roofs or houses, so the keyword list would miss it.
	if (model as String).begins_with("disk:"):
		return "building"
	for keyword in BUILDING_KEYWORDS:
		if keyword in model:
			return "building"
	return ""

## The size of a prop's horizontal footprint in metres, or zero when the model is unknown yet.
func _prop_footprint_m(entry: Dictionary) -> Vector2:
	var units := Vector2.ZERO
	var model: Variant = entry.get("model")
	if model is String and model.begins_with("disk:"):
		units = _structure_footprints.get(structure_url(model), Vector2.ZERO)
	else:
		var path := prop_path(model)
		if not path.is_empty():
			units = _kit_footprint(path)
	if units == Vector2.ZERO:
		return Vector2.ZERO
	return units * float(entry.scale_m)

## The x and z extents of a bundled kit model in model units, by scene path, measured from the
## meshes and cached: the towns are built from a few hundred pieces of a handful of models.
func _kit_footprint(path: String) -> Vector2:
	if _prop_footprints.has(path):
		return _prop_footprints[path]
	var units := Vector2.ZERO
	var scene: Variant = _prop_scenes.get(path)
	if scene == null and ResourceLoader.exists(path, "PackedScene"):
		scene = load(path)
	if scene is PackedScene:
		units = _scene_footprint(scene)
	_prop_footprints[path] = units
	return units

## The x and z extents of all meshes of a scene, in the scene's own units.
static func _scene_footprint(scene: PackedScene) -> Vector2:
	var root := scene.instantiate()
	var aabb := _combined_aabb(root, Transform3D.IDENTITY)
	root.free()
	if aabb == AABB():
		return Vector2.ZERO
	return Vector2(aabb.size.x, aabb.size.z)

static func _combined_aabb(node: Node, parent: Transform3D) -> AABB:
	var result := AABB()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = parent * (node as MeshInstance3D).mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_aabb := _combined_aabb(child, parent * (child as Node3D).transform)
			if child_aabb == AABB():
				continue
			result = child_aabb if result == AABB() else result.merge(child_aabb)
	return result

## Metres the minimap region texture covers from the centre: grows with landscape patches so a
## city like Uruk and its river fit when the big map is zoomed out.
func _map_extent_m() -> float:
	var extent := WATER_MAP_EXTENT_M
	for patch: Dictionary in _terrain_patches:
		extent = maxf(extent, maxf(float(patch.extent[0]), float(patch.extent[1])) * 0.55)
	return minf(extent, WATER_MAP_EXTENT_MAX_M)

## Whether a landscape patch marks this direction as built or tilled ground (minimap city).
func _terrain_cleared(direction: Array) -> bool:
	for patch: Dictionary in _terrain_patches:
		var image: Variant = patch.get("clear_image")
		if not image is Image:
			continue
		var local: Array = _terrain_local(patch, direction)
		if local.is_empty():
			continue
		var clear: Image = image
		var column := int(clampf((float(local[0]) + float(patch.extent[0]) * 0.5) / float(patch.extent[0]) * clear.get_width(), 0.0, clear.get_width() - 1))
		var row := int(clampf((float(local[1]) + float(patch.extent[1]) * 0.5) / float(patch.extent[1]) * clear.get_height(), 0.0, clear.get_height() - 1))
		if clear.get_pixel(column, row).r > 0.5:
			return true
	return false

## Whether the minimap (and the player's eyes) should treat this direction as open water.
## The water surface (km) of the local patch mesh at a vertex, or NAN on dry ground. The server walks the
## same rules (`WalkingTerrain::surface`): a river of a landscape patch is water, and a coarse river cell
## on a flat plain is dry unless water stands at least half a metre above the ground.
func _detail_water_km(direction: Array, point: Vector3, height: float) -> float:
	var patch_water := _terrain_water_m(direction)
	if is_finite(patch_water):
		return patch_water / 1000.0
	var index := environment_index(point)
	var water_m: float = float(environment.water_m[index])
	if water_m <= -8001.0:
		return NAN
	var biome := int(environment.biomes[index])
	if biome != 0 and biome != 1:
		if water_m <= float(environment.elevation_m[index]) or water_m - height * 1000.0 < 0.5:
			return NAN
	return water_m / 1000.0

## Matches `planet_surface.gdshader` water_pass: ocean and lake fill, plus landscape-patch
## rivers. Coarse "river" cells from drainage on a flat plain (Early Dynastic floodplain)
## must not paint the whole 150 km cell blue when the heightmap underfoot is dry land.
func _minimap_water_at(direction: Array) -> bool:
	var height := elevation64(direction)
	var patch_water := _terrain_water_m(direction)
	if is_finite(patch_water):
		return patch_water / 1000.0 + 0.001 > height
	if environment.is_empty():
		return height <= 0.001
	var point := Vector3(float(direction[0]), float(direction[1]), float(direction[2]))
	var index := environment_index(point)
	var water_m: float = float(environment.water_m[index])
	if water_m <= -8001.0:
		return false
	var biome := int(environment.biomes[index])
	# Planet water pass only draws ocean and lake; flow rivers are line meshes, not a flood.
	if biome != 0 and biome != 1:
		var elevation_m: float = float(environment.elevation_m[index])
		# Standing ponding above the coarse ground (a carved channel) still counts.
		if water_m <= elevation_m or water_m - height * 1000.0 < 0.5:
			return false
	return water_m / 1000.0 + 0.001 > height

## The baked region picture (see `water_map`): settlement clear-mask under water where the water
## plane stands above the ground, so the minimap shows the city silhouette and its rivers.
func _bake_water_map(unit: Vector3, tangent: Vector3, forward: Vector3) -> void:
	_apply_water_map(_bake_water_image(unit, tangent, forward, _map_extent_m()), unit, tangent, forward, _map_extent_m())

## Worker-safe: only reads terrain data, and returns the picture.
func _bake_water_image(unit: Vector3, tangent: Vector3, forward: Vector3, extent_m: float) -> Image:
	var pixels := WATER_MAP_PIXELS
	var step := extent_m * 2.0 / float(pixels)
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for row in pixels:
		for column in pixels:
			var horizontal := (float(column) + 0.5 - pixels * 0.5) * step
			# Image row 0 is the top of the map: the `forward` direction of the bake frame.
			var vertical := (pixels * 0.5 - (float(row) + 0.5)) * step
			var direction: Vector3 = (unit * RADIUS + tangent * horizontal / 1000.0 + forward * vertical / 1000.0).normalized()
			var dir := [direction.x, direction.y, direction.z]
			if _terrain_cleared(dir):
				image.set_pixel(column, row, SETTLEMENT_MAP_COLOR)
			if _minimap_water_at(dir):
				image.set_pixel(column, row, WATER_MAP_COLOR)
	return image

func _apply_water_map(image: Image, unit: Vector3, tangent: Vector3, forward: Vector3, extent_m: float) -> void:
	var step := extent_m * 2.0 / float(WATER_MAP_PIXELS)
	water_map = {
		"texture": ImageTexture.create_from_image(image),
		"centre": unit * (RADIUS + elevation64([unit.x, unit.y, unit.z])) * 1000.0,
		"tangent": tangent,
		"forward": forward,
		"metres_per_pixel": step,
	}
	water_changed.emit()

## A datadisk building is drawn when its model is here; until then the placement stays empty.
func _place_structure(placement: Node3D, url: String) -> void:
	if _structure_models.has(url):
		_fill_structure(placement, _structure_models[url])
		return
	var first := not _structure_waiting.has(url)
	if first:
		_structure_waiting[url] = []
	# Placements of an earlier region may be gone by now.
	_structure_waiting[url] = _structure_waiting[url].filter(func(node: Variant) -> bool: return is_instance_valid(node))
	_structure_waiting[url].append(placement)
	if first and fetch_media.is_valid():
		fetch_media.call(url)

func _fill_structure(placement: Node3D, scene: PackedScene) -> void:
	var model := scene.instantiate() as Node3D
	if model != null:
		placement.add_child(model)

## A building model arrived: it fills the placements that waited for it.
func _structure_ready(url: String, scene: PackedScene) -> void:
	_structure_models[url] = scene
	_structure_footprints[url] = _scene_footprint(scene)
	for placement: Variant in _structure_waiting.get(url, []):
		if is_instance_valid(placement):
			_fill_structure(placement, scene)
	_structure_waiting.erase(url)
	props_changed.emit()

## Some kit models (Retro Fantasy barrels, crates, shrubs and trees) are authored unshaded, so they would
## keep their daylight colour at night. Their materials are replaced by lit copies, one per original.
func _light_materials(model: Node) -> void:
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface)
			if not source is BaseMaterial3D or source.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			if not _lit_materials.has(source):
				var lit := source.duplicate() as BaseMaterial3D
				lit.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				_lit_materials[source] = lit
			instance.set_surface_override_material(surface, _lit_materials[source])

## A lamp post gets a light at its head; it only burns while it is night.
func _add_lamp(entry: Dictionary) -> void:
	var head: Array = LAMP_MODELS[entry.model]
	var scale_m := float(entry.scale_m)
	var point := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var up := point.normalized()
	var turn := Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, entry.yaw)
	var offset := turn * Vector3(head[0], head[1], head[2]) * scale_m
	var position := [point.x + offset.x, point.y + offset.y, point.z + offset.z]
	var light := OmniLight3D.new()
	light.omni_range = LAMP_RANGE_M / 1000.0
	light.omni_attenuation = 2.0
	light.light_color = Color(1.0, 0.6, 0.26)
	light.set_meta("phase", float(_lamp_positions.size()) * 1.7)
	light.shadow_enabled = false
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07 * scale_m / 1000.0
	sphere.height = sphere.radius * 2.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.66, 0.3)
	sphere.material = glow
	bulb.mesh = sphere
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.add_child(bulb)
	light.position = _render_position(position)
	lamps.add_child(light)
	_lamp_positions.append(position)
	_apply_night(light)

## How dark it is (0 = day, 1 = night); the lamps fade in with the dusk.
func set_night(amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	if is_equal_approx(clamped, _night):
		return
	_night = clamped
	for light in lamps.get_children():
		_apply_night(light)

## The flame of a gas lamp wavers a little; each lamp has its own phase.
func _flicker_lamps(delta: float) -> void:
	_lamp_time += delta
	if _night <= 0.02:
		return
	for light: OmniLight3D in lamps.get_children():
		var phase: float = light.get_meta("phase", 0.0)
		var wave := sin(_lamp_time * 7.0 + phase) * 0.6 + sin(_lamp_time * 13.0 + phase * 2.0) * 0.4
		light.light_energy = LAMP_ENERGY * _night * (1.0 + LAMP_FLICKER * wave)

func _apply_night(light: Node) -> void:
	(light as OmniLight3D).light_energy = LAMP_ENERGY * _night
	(light as OmniLight3D).visible = _night > 0.02

## Things that characters put into the world: campfires, benches, tents and crops. The list is what
## the server says; an entry with an unknown model or a strange value is skipped, never drawn.
## Datadisk models (`disk:…`) wait for media like town structures.
func apply_placed(data: Variant) -> bool:
	_clear_placed()
	if not data is Array or data.size() > 500:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not (entry.get("id") is float or entry.get("id") is int) or not entry.get("kind") is String or not entry.get("position") is Array or entry.position.size() != 3:
			continue
		var path := prop_path(entry.get("model"))
		var url := structure_url(entry.get("model"))
		var finite := not path.is_empty() or not url.is_empty()
		for value: Variant in entry.position:
			finite = finite and (value is float or value is int) and is_finite(float(value)) and absf(value) <= 7000000.0
		for key in ["yaw", "scale"]:
			finite = finite and (entry.get(key) is float or entry.get(key) is int) and is_finite(float(entry[key]))
		if not finite or entry.scale <= 0.05 or entry.scale > 10 or entry.yaw < 0 or entry.yaw > 6.3:
			continue
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			continue
		var placement := Node3D.new()
		placement.name = "Placed%d" % int(entry.id)
		placement.position = _render_position(entry.position)
		placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
		# Crops are small food models; they are drawn larger so that a field can be seen.
		var factor := 2.5 if String(entry.model).begins_with("food.") else 1.0
		placement.scale = Vector3.ONE * float(entry.scale) * factor / 1000.0
		if not url.is_empty():
			placed.add_child(placement)
			_placed_entries.append(entry.duplicate(true))
			_place_structure(placement, url)
			continue
		if not _prop_scenes.has(path):
			_prop_scenes[path] = load(path)
		var model: Node = (_prop_scenes[path] as PackedScene).instantiate()
		if not model is Node3D:
			model.free()
			placement.free()
			continue
		_light_materials(model)
		placement.add_child(model)
		placed.add_child(placement)
		_placed_entries.append(entry.duplicate(true))
	return true

func _clear_placed() -> void:
	_placed_entries.clear()
	for child in placed.get_children():
		placed.remove_child(child)
		child.queue_free()

## Loose packs lying on the ground. Drawn as floating item icons.
func apply_loot(data: Variant) -> void:
	_clear_loot()
	if not data is Array or data.size() > 200:
		return
	var icons := preload("res://scripts/item_icons.gd")
	for entry: Variant in data:
		if not entry is Dictionary or not (entry.get("id") is float or entry.get("id") is int):
			continue
		if not entry.get("item_id") is String or not entry.get("name") is String:
			continue
		var pos_ok := true
		for key in ["position_x", "position_y", "position_z"]:
			if not (entry.get(key) is float or entry.get(key) is int) or not is_finite(float(entry[key])):
				pos_ok = false
				break
		if not pos_ok:
			continue
		var metres := [float(entry.position_x), float(entry.position_y), float(entry.position_z)]
		var point := Vector3(metres[0], metres[1], metres[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			continue
		var marker := Node3D.new()
		marker.name = "Loot%d" % int(entry.id)
		marker.position = _render_position(metres) + point.normalized() * 0.0004
		var sprite := Sprite3D.new()
		sprite.texture = icons.texture(entry.item_id)
		sprite.pixel_size = 0.004
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.double_sided = true
		sprite.position = Vector3(0, 0.35, 0)
		marker.add_child(sprite)
		loot.add_child(marker)
		_loot_entries.append(entry.duplicate(true))

func _clear_loot() -> void:
	_loot_entries.clear()
	if not is_instance_valid(loot):
		return
	for child in loot.get_children():
		loot.remove_child(child)
		child.queue_free()

## The nearest dropped pile within reach of a position in metres.
func nearest_loot(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for entry: Dictionary in _loot_entries:
		var at := Vector3(float(entry.position_x), float(entry.position_y), float(entry.position_z))
		var distance := player_metres.distance_to(at)
		if distance <= reach_m and distance < best_distance:
			best = entry
			best_distance = distance
	return best

## The nearest thing that characters put into the world within reach of a position in metres.
func nearest_placed(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for entry: Dictionary in _placed_entries:
		var distance := player_metres.distance_to(Vector3(entry.position[0], entry.position[1], entry.position[2]))
		if distance <= reach_m and distance < best_distance:
			best = entry
			best_distance = distance
	return best

func _clear_props() -> void:
	_prop_entries.clear()
	_lamp_positions.clear()
	for lamp in lamps.get_children():
		lamps.remove_child(lamp)
		lamp.queue_free()
	for child in props.get_children():
		props.remove_child(child)
		child.queue_free()

func _npc_name(key: String) -> String:
	return str(npc_text.call(key)) if npc_text.is_valid() else key

## Names are translated when the story strings arrive or the language changes.
func refresh_npc_names() -> void:
	for index in _npc_entries.size():
		var label := npcs.get_child(index).get_node_or_null("Name") as Label3D
		if label != null:
			label.text = _npc_name(_npc_entries[index].name_key)

func _clear_npcs() -> void:
	_npc_entries.clear()
	_npc_walkers.clear()
	npcs_changed.emit()
	for child in npcs.get_children():
		npcs.remove_child(child)
		child.queue_free()

## Briefly sends an NPC to a point (metres from the planet's centre) at a run, then lets wander resume.
## Used when wild Enkidu tears a snare; `seconds` is how long they stay at the point.
func rush_npc(npc_id: String, metres: Array, seconds: float = 3.5) -> void:
	if metres.size() != 3 or seconds <= 0.0 or seconds > 20.0:
		return
	var index := -1
	for i in _npc_entries.size():
		var id := str(_npc_entries[i].get("id", ""))
		if id == npc_id or id.ends_with(":" + npc_id):
			index = i
			break
	if index < 0 or index >= npcs.get_child_count():
		return
	var held_id := str(_npc_entries[index].id)
	hold_npc(held_id, true)
	var node := npcs.get_child(index) as Node3D
	var home := node.position
	var target := _render_position(metres)
	var tween := create_tween()
	tween.tween_property(node, "position", target, 0.9).set_trans(Tween.TRANS_SINE)
	var player := _npc_player(node)
	if player != null:
		_play_npc(player, 4.0)
	tween.tween_interval(seconds)
	tween.tween_property(node, "position", home, 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		hold_npc(held_id, false)
	)

## The nearest character within reach of a server position in metres.
func nearest_npc(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for entry: Dictionary in _npc_entries:
		var distance := player_metres.distance_to(Vector3(entry.position[0], entry.position[1], entry.position[2]))
		if distance <= reach_m and distance < best_distance:
			best = entry
			best_distance = distance
	return best

func set_render_origin(coordinates_metres: Array) -> void:
	_origin_metres = coordinates_metres.duplicate()
	for index in placements.size():
		objects.get_child(index).position = _render_position(placements[index].coordinates)
	for index in _memorial_entries.size():
		memorials.get_child(index).position = _render_position(_memorial_entries[index].position)
	for index in _portal_entries.size():
		portals.get_child(index).position = _render_position(_portal_entries[index].position)
	for index in _npc_entries.size():
		npcs.get_child(index).position = _render_position(_npc_entries[index].position)
	for index in _prop_entries.size():
		props.get_child(index).position = _render_position(_prop_entries[index].position)
	for index in _placed_entries.size():
		placed.get_child(index).position = _render_position(_placed_entries[index].position)
	for index in _lamp_positions.size():
		lamps.get_child(index).position = _render_position(_lamp_positions[index])
	_build_detail()
	# Until the rebuilt disk arrives the old one is slid into the new origin's frame instead of jumping.
	if _detail_pending and _detail_anchor.size() == 3:
		var now: Array = _origin_metres if _origin_metres.size() == 3 else [0.0, 0.0, 0.0]
		grass.position = Vector3((float(_detail_anchor[0]) - float(now[0])) / 1000.0, (float(_detail_anchor[1]) - float(now[1])) / 1000.0, (float(_detail_anchor[2]) - float(now[2])) / 1000.0)
		detail.position = Vector3((float(_detail_anchor[0]) - float(now[0])) / 1000.0, (float(_detail_anchor[1]) - float(now[1])) / 1000.0, (float(_detail_anchor[2]) - float(now[2])) / 1000.0)

## Where a point (metres from the planet's centre) is in the scene, relative to the render origin.
func render_position(metres: Array) -> Vector3:
	return _render_position(metres)

func _render_position(metres: Array) -> Vector3:
	var anchor: Array = _origin_metres if _origin_metres.size() == 3 else [0.0, 0.0, 0.0]
	return _position_from(anchor, metres)

func _position_from(anchor: Array, metres: Array) -> Vector3:
	return Vector3((float(metres[0]) - anchor[0]) / 1000.0, (float(metres[1]) - anchor[1]) / 1000.0, (float(metres[2]) - anchor[2]) / 1000.0)

## Plays the looping animation `name` (with or without the armature prefix) of an animated model.
## Every object starts at its own moment so a herd or a shoal does not move in step.
## Returns the animation player, or null when the model has none.
func _animate(model: Node, animation_name: String, identity: String) -> AnimationPlayer:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null
	var player: AnimationPlayer = players[0]
	_play_clip(player, animation_name, identity)
	return player

func _play_clip(player: AnimationPlayer, animation_name: String, identity: String) -> void:
	for candidate in player.get_animation_list():
		# Exact, glTF "Armature|Idle", or Blender-style "Idle_Armature".
		if (
			candidate == animation_name
			or candidate.ends_with("|" + animation_name)
			or candidate.begins_with(animation_name + "_")
		):
			var animation := player.get_animation(candidate)
			animation.loop_mode = Animation.LOOP_LINEAR
			player.play(candidate)
			var hash := identity.hash()
			player.seek(float(hash % 1000) / 1000.0 * animation.length, true)
			player.speed_scale = 0.9 + float(hash % 21) / 100.0
			return

## The server's clock minus ours, from a reply's `server_time_ms` (zero when it has none).
func _server_offset(server_time: Variant) -> float:
	if server_time is float or server_time is int:
		return float(server_time) - Time.get_unix_time_from_system() * 1000.0
	return 0.0

## Waypoints [unix milliseconds, x, y, z] of a walking animal; empty when they are not valid.
func _parse_route(data: Variant) -> Array:
	if not data is Array or data.size() < 2 or data.size() > MAX_WAYPOINTS:
		return []
	var route := []
	var previous := -INF
	for waypoint: Variant in data:
		if not waypoint is Array or waypoint.size() != 4:
			return []
		for index in 4:
			var value: Variant = waypoint[index]
			if not (value is float or value is int) or not is_finite(float(value)) or (index > 0 and absf(value) > 7000000.0):
				return []
		if float(waypoint[0]) < previous:
			return []
		previous = float(waypoint[0])
		route.append([float(waypoint[0]), float(waypoint[1]), float(waypoint[2]), float(waypoint[3])])
	return route

## Where a route puts an animal at `time_ms` (metres) and its velocity (metres per second).
func _route_sample(route: Array, time_ms: float) -> Array:
	var first: Array = route[0]
	if time_ms <= first[0]:
		return [Vector3(first[1], first[2], first[3]), Vector3.ZERO]
	for index in range(1, route.size()):
		var next: Array = route[index]
		if time_ms <= next[0]:
			var start: Array = route[index - 1]
			var span: float = next[0] - start[0]
			var from := Vector3(start[1], start[2], start[3])
			var to := Vector3(next[1], next[2], next[3])
			if span <= 0.0:
				return [to, Vector3.ZERO]
			return [from.lerp(to, (time_ms - start[0]) / span), (to - from) / (span / 1000.0)]
	var last: Array = route[route.size() - 1]
	return [Vector3(last[1], last[2], last[3]), Vector3.ZERO]

## Walks the land animals along their routes: they turn towards where they go and play the
## walking clip while they move and the idle one while they stand.
func _wander(delta: float) -> void:
	if _walkers.is_empty():
		return
	var now := Time.get_unix_time_from_system() * 1000.0 + _clock_offset_ms
	for walker in _walkers:
		var node: Node3D = walker.node
		if not is_instance_valid(node):
			continue
		var sample := _route_sample(walker.route, now)
		var metres: Vector3 = sample[0]
		var velocity: Vector3 = sample[1]
		node.position = _render_position([metres.x, metres.y, metres.z])
		var placement: Dictionary = walker.placement
		placement.coordinates = [metres.x, metres.y, metres.z]
		placement.position = metres / 1000.0
		var walking := velocity.length() > 0.05
		if walking:
			var up := metres.normalized()
			var forward := (velocity - up * velocity.dot(up)).normalized()
			# Models face +Z, and a basis that looks at a point has -Z pointing there.
			var facing := Basis.looking_at(-forward, up).get_rotation_quaternion()
			node.quaternion = node.quaternion.slerp(facing, minf(1.0, delta * 5.0))
		if walking != walker.walking:
			walker.walking = walking
			if walker.player != null:
				_play_clip(walker.player, "Walk" if walking else "Idle", walker.id)
				if walking:
					walker.player.speed_scale = 1.0

## The animation player of a character's model: the pack characters name it, a datadisk's model has its own.
func _npc_player(model: Node) -> AnimationPlayer:
	var named := model.get_node_or_null("CharacterAnimation") as AnimationPlayer
	if named != null:
		return named
	var players := model.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null

## Plays Idle, Walk or Run for a character from ground speed (m/s). Walk is authored near 1 m/s;
## Run near 2.2 m/s. Falls back to Walk when Run is missing (elderly models).
func _play_npc(player: AnimationPlayer, speed_m_s: float) -> void:
	if player == null:
		return
	var wanted := "idle"
	if speed_m_s > 1.55:
		wanted = "run"
	elif speed_m_s > 0.05:
		wanted = "walk"
	var clip := _npc_clip(player, wanted)
	if clip.is_empty() and wanted == "run":
		wanted = "walk"
		clip = _npc_clip(player, wanted)
	if clip.is_empty():
		return
	var reference := 2.2 if wanted == "run" else 1.0
	var scale := 1.0 if wanted == "idle" else clampf(speed_m_s / reference, 0.35, 1.85)
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.speed_scale = scale
	if player.current_animation != clip:
		player.play(clip, 0.2)

func _npc_clip(player: AnimationPlayer, wanted: String) -> String:
	for candidate in player.get_animation_list():
		var lower := String(candidate).to_lower()
		if lower == wanted or lower.ends_with("|" + wanted):
			return String(candidate)
	return ""

## Walks the characters that walk along their routes: they turn towards where they go and play the walking
## clip while they move and the idle one while they stand. Their entry follows them, so that talking to them,
## the minimap and the next render origin all find them where they are.
func _walk_npcs(delta: float) -> void:
	if _npc_walkers.is_empty():
		return
	var now := Time.get_unix_time_from_system() * 1000.0 + _clock_offset_ms
	var ticks := Time.get_ticks_msec()
	for walker in _npc_walkers:
		var index: int = walker.index
		if index >= npcs.get_child_count() or index >= _npc_entries.size():
			continue
		if _held_npcs.has(walker.id):
			walker.gesture_until = 0
			walker.gesture_clip = ""
			continue	# it talks to the player: it stands (`_face_held`)
		var node := npcs.get_child(index) as Node3D
		var sample := _route_sample(walker.route, now)
		var metres: Vector3 = sample[0]
		var velocity: Vector3 = sample[1]
		node.position = _render_position([metres.x, metres.y, metres.z])
		_npc_entries[index].position = [metres.x, metres.y, metres.z]
		var speed := velocity.length()
		var walking := speed > 0.05
		if walking:
			walker.gesture_until = 0
			walker.gesture_clip = ""
			var up := metres.normalized()
			var forward := (velocity - up * velocity.dot(up)).normalized()
			# Models face +Z, and a basis that looks at a point has -Z pointing there.
			var facing := Basis.looking_at(-forward, up).get_rotation_quaternion()
			node.quaternion = node.quaternion.slerp(facing, minf(1.0, delta * 5.0))
		var gesturing := int(walker.gesture_until) > ticks
		if gesturing and not walking:
			continue
		if walker.gesture_until != 0 and not gesturing and not walking:
			walker.gesture_until = 0
			walker.gesture_clip = ""
			_play_npc(walker.player, 0.0)
		if walking != walker.walking or walking:
			walker.walking = walking
			_play_npc(walker.player, speed if walking else 0.0)
			if not walking:
				_maybe_npc_gesture(walker, _npc_entries[index])

## The player starts or ends a conversation with a character. While it lasts the character stands still and turns to the player (the server
## stops the clock of its walk too, so it is where the client sees it); afterwards a walking character goes on to where it was going (the
## routes are asked for again, they go on from where it stood) and one that only stood turns back.
func hold_npc(npc_id: String, held: bool) -> void:
	if held:
		if _held_npcs.has(npc_id):
			_held_npcs[npc_id].released_at = 0
			return
		var home := Quaternion.IDENTITY
		for index in _npc_entries.size():
			if _npc_entries[index].id == npc_id and index < npcs.get_child_count():
				home = (npcs.get_child(index) as Node3D).quaternion
		_held_npcs[npc_id] = {"released_at": 0, "home": home}
	elif _held_npcs.has(npc_id) and _held_npcs[npc_id].released_at == 0:
		_held_npcs[npc_id].released_at = Time.get_ticks_msec()
		_request_animals()

## Turns the characters in conversation to the player (and the released ones that only stood back to where they looked).
func _face_held(delta: float) -> void:
	if _held_npcs.is_empty():
		return
	for npc_id: String in _held_npcs.keys():
		var hold: Dictionary = _held_npcs[npc_id]
		var index := -1
		for candidate in _npc_entries.size():
			if _npc_entries[candidate].id == npc_id:
				index = candidate
		if index < 0 or index >= npcs.get_child_count():
			_held_npcs.erase(npc_id)
			continue
		var node := npcs.get_child(index) as Node3D
		var entry: Dictionary = _npc_entries[index]
		var walker: Variant = _npc_walker(npc_id)
		if walker != null and walker.walking:
			walker.walking = false
			_play_npc(walker.player, 0.0)
		var released: int = hold.released_at
		if released == 0:
			var metres := Vector3(entry.position[0], entry.position[1], entry.position[2])
			if target != Vector3.ZERO and metres != Vector3.ZERO:
				var up := metres.normalized()
				var toward := target * metres.length() - metres
				var forward := toward - up * toward.dot(up)
				if forward.length() > 0.01:
					# Models face +Z, and a basis that looks at a point has -Z pointing there.
					var facing := Basis.looking_at(-forward.normalized(), up).get_rotation_quaternion()
					node.quaternion = node.quaternion.slerp(facing, minf(1.0, delta * 6.0))
		elif walker == null:
			# A character that only stood turns back and is let go.
			node.quaternion = node.quaternion.slerp(hold.home, minf(1.0, delta * 6.0))
			if node.quaternion.angle_to(hold.home) < 0.03:
				_held_npcs.erase(npc_id)
		elif Time.get_ticks_msec() - released > HOLD_RELEASE_MS:
			_held_npcs.erase(npc_id)	# the server did not answer: it goes on by the route it has

func _npc_walker(npc_id: String) -> Variant:
	for walker in _npc_walkers:
		if walker.id == npc_id:
			return walker
	return null

## Plays a one-shot clip on an NPC model (duel flourish or Easter egg). Returns false when missing.
func play_npc_clip(npc_id: String, clip: String) -> bool:
	var player: AnimationPlayer = null
	var walker: Variant = _npc_walker(npc_id)
	if walker != null:
		player = walker.player
	else:
		for index in _npc_entries.size():
			if _npc_entries[index].id == npc_id and index < npcs.get_child_count():
				player = _npc_player(npcs.get_child(index))
				break
	if player == null or clip.is_empty():
		return false
	var name := _npc_clip(player, clip.to_lower())
	if name.is_empty():
		# Egg clips keep their authored capitalisation (`Twerk`).
		for candidate in player.get_animation_list():
			if String(candidate) == clip or String(candidate).ends_with("|" + clip):
				name = String(candidate)
				break
	if name.is_empty():
		return false
	player.get_animation(name).loop_mode = Animation.LOOP_NONE
	player.speed_scale = 1.0
	player.play(name, 0.12)
	if walker != null:
		walker.gesture_clip = name
		walker.gesture_until = Time.get_ticks_msec() + int(maxf(player.current_animation_length, 0.3) * 1000.0)
	return true

## Rare ambient or unlocked egg while the character stands still.
func _maybe_npc_gesture(walker: Dictionary, entry: Dictionary) -> void:
	if walker.player == null or int(walker.gesture_until) > Time.get_ticks_msec():
		return
	var slot := int(Time.get_unix_time_from_system() / 17.0)
	var roll: int = absi(("%s:%s" % [entry.id, slot]).hash()) % 100
	var eggs: Array = entry.get("unlocked_eggs", []) if entry.get("unlocked_eggs") is Array else []
	var pick := ""
	if roll < 4 and not eggs.is_empty():
		pick = str(eggs[abs(("%s:egg:%s" % [entry.id, slot]).hash()) % eggs.size()])
	elif roll < 12:
		var common: Array[String] = []
		for name in COMMON_GESTURES:
			if not _npc_clip(walker.player, name.to_lower()).is_empty() or _npc_has_clip(walker.player, name):
				common.append(name)
		if not common.is_empty():
			pick = common[abs(("%s:soft:%s" % [entry.id, slot]).hash()) % common.size()]
	if not pick.is_empty():
		play_npc_clip(entry.id, pick)

func _npc_has_clip(player: AnimationPlayer, clip: String) -> bool:
	for candidate in player.get_animation_list():
		if String(candidate) == clip or String(candidate).ends_with("|" + clip):
			return true
	return false

## Asks the server for the routes of the animals again, without rebuilding the region.
func _request_animals() -> void:
	if server_url.is_empty() or target == Vector3.ZERO or not objects_loaded or (_walkers.is_empty() and _npc_walkers.is_empty()) or is_instance_valid(_animals_request):
		return
	_animals_request = HTTPRequest.new()
	_animals_request.timeout = 8.0
	_animals_request.max_redirects = 0
	_animals_request.body_size_limit = 2 * 1024 * 1024
	_animals_request.request_completed.connect(_on_animals_received.bind(_region_generation))
	add_child(_animals_request)
	var point := target.normalized() * RADIUS * 1000.0
	var headers := PackedStringArray()
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)
	if _animals_request.request(server_url + "/world/objects?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z], headers) != OK:
		_animals_request.queue_free()
		_animals_request = null

func _on_animals_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if is_instance_valid(_animals_request):
		_animals_request.queue_free()
	_animals_request = null
	if generation != _region_generation or result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or data.get("version") != 1 or data.get("heightmap_sha256") != environment.get("heightmap_sha256") or data.get("seed") != environment.get("seed") or not data.get("objects") is Array:
		return
	_clock_offset_ms = _server_offset(data.get("server_time_ms"))
	var routes := {}
	for entry: Variant in data.objects:
		if entry is Dictionary and entry.get("id") is String and entry.has("wander"):
			var route := _parse_route(entry.wander)
			if not route.is_empty():
				routes[entry.id] = route
	for walker in _walkers:
		if routes.has(walker.id):
			walker.route = routes[walker.id]
	if data.get("npcs") is Array:
		var walks := {}
		for entry: Variant in data.npcs:
			if entry is Dictionary and entry.get("id") is String and entry.has("wander"):
				var route := _parse_route(entry.wander)
				if not route.is_empty():
					walks[entry.id] = route
		for walker in _npc_walkers:
			if walks.has(walker.id):
				walker.route = walks[walker.id]
				if _held_npcs.has(walker.id) and _held_npcs[walker.id].released_at != 0:
					_held_npcs.erase(walker.id)	# the new route goes on from where it stood
		sync_npc_health(data.npcs)

## The nearest walking animal within reach of a server position in metres.
func nearest_animal(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for walker in _walkers:
		var coordinates: Array = walker.placement.coordinates
		var distance := player_metres.distance_to(Vector3(coordinates[0], coordinates[1], coordinates[2]))
		if distance <= reach_m and distance < best_distance:
			best = walker.placement
			best_distance = distance
	return best

## Moves fish around their anchor and turns them along their path.
func _swim() -> void:
	if _swimmers.is_empty():
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	for swimmer in _swimmers:
		var node: Node3D = swimmer.node
		if not is_instance_valid(node):
			continue
		var radius: float = swimmer.radius
		var angle: float = swimmer.phase + seconds * swimmer.speed / radius
		node.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
		node.rotation.y = atan2(-sin(angle), cos(angle))

## What an object can be harvested for, or an empty dictionary for scenery.
func _harvest_info(data: Variant) -> Dictionary:
	if data is Dictionary and data.get("kind") in ["tree", "rock", "logs"] and data.get("tool") is String and (data.get("hits") is int or data.get("hits") is float):
		return {"kind": data.kind, "tool": data.tool, "hits": int(data.hits)}
	return {}

## The nearest harvestable object within reach of a server position in metres.
func nearest_harvestable(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for placement: Dictionary in placements:
		if placement.harvest.is_empty():
			continue
		var coordinates: Array = placement.coordinates
		var distance := player_metres.distance_to(Vector3(coordinates[0], coordinates[1], coordinates[2]))
		if distance <= reach_m + float(placement.collision_radius_m) and distance < best_distance:
			best = placement
			best_distance = distance
	return best

## Requests the objects again, for example after a tree was felled.
func refresh_objects() -> void:
	if not server_url.is_empty() and target != Vector3.ZERO and not is_instance_valid(_objects_request):
		_request_objects(target.normalized())

func _place_object(entry: Dictionary) -> void:
	var selected: Dictionary = _models[entry.model]
	if not _scenes.has(selected.id):
		_scenes[selected.id] = load(selected.scene)
	var model: Node = _scenes[selected.id].instantiate()
	if not model is Node3D:
		model.free()
		return
	if selected.has("metallic"):
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		for mesh_instance: MeshInstance3D in meshes:
			for surface in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.get_active_material(surface)
				if source is StandardMaterial3D:
					var material := source.duplicate() as StandardMaterial3D
					material.metallic = selected.metallic
					mesh_instance.set_surface_override_material(surface, material)
	var swimmer: Node3D = null
	var player: AnimationPlayer = null
	if selected.has("animation"):
		player = _animate(model, selected.animation, entry.id)
		if selected.has("swim_radius_m"):
			swimmer = Node3D.new()
			swimmer.name = "Swimmer"
	var placement := Node3D.new()
	placement.name = entry.id.validate_node_name()
	placement.position = _render_position(entry.position)
	var point := Vector3(entry.position[0] / 1000.0, entry.position[1] / 1000.0, entry.position[2] / 1000.0)
	placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
	placement.scale = Vector3.ONE * entry.scale_m / 1000.0
	# Vertical placement offset in metres (negative sinks into the ground); 0 A.D. trees
	# have roots at Y=0 but their trunks start higher, so they appear to float without this.
	var ground_offset: float = entry.get("ground_offset_m", 0.0)
	if ground_offset != 0.0:
		model.position.y = ground_offset / float(entry.scale_m)
	if swimmer != null:
		swimmer.add_child(model)
		placement.add_child(swimmer)
		var hash: int = String(entry.id).hash()
		# Fish swim at 0.3 to 0.9 metres per second on a circle; the radius is in model units.
		var speed := 0.3 + float(hash % 7) * 0.1
		_swimmers.append({"node": swimmer, "radius": float(selected.swim_radius_m) / float(entry.scale_m), "speed": speed / float(entry.scale_m), "phase": float(hash % 628) / 100.0})
	else:
		placement.add_child(model)
	objects.add_child(placement)
	var record := {"id":entry.id,"model":selected.id,"position":point,"coordinates":entry.position.duplicate(),"scale":placement.scale,"rotation":placement.quaternion,"biome":BIOMES[int(entry.biome)],"collision_radius_m":entry.collision_radius_m,"harvest":_harvest_info(entry.get("harvest"))}
	placements.append(record)
	if entry.has("wander"):
		_walkers.append({"id": entry.id, "node": placement, "placement": record, "player": player, "route": _parse_route(entry.wander), "walking": false})