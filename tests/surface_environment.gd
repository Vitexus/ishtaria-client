extends SceneTree

const SURFACE := preload("res://scripts/surface_environment.gd")
const SHADER := preload("res://scripts/planet_surface.gdshader")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

## The worker-thread disk: identical to the synchronous one, slid (not jumped) while it is computed,
## and a build that was asked for and superseded never reaches the scene.
func _test_async_detail(surface: Node3D) -> void:
	surface.show_region(Vector3.FORWARD)
	var expected: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	surface.async_detail = true
	surface.show_region(Vector3.FORWARD)
	_check(surface._detail_pending, "An asynchronous build is pending until the worker has finished")
	surface.show_region(Vector3.FORWARD)
	for _frame in 600:
		if not surface._detail_pending:
			break
		await process_frame
	_check(not surface._detail_pending and surface.detail.get_child_count() == 2, "The asynchronous build arrives as one land and one water mesh")
	var arrived: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(arrived == expected, "The asynchronous disk has exactly the vertices of the synchronous one")
	var moved: Array = surface._origin_metres.duplicate()
	moved = [6371001.0, 0.0, 0.0] if moved.size() != 3 else moved
	surface.set_render_origin(moved)
	surface.set_render_origin([])
	_check(surface._detail_pending, "Moving the origin twice leaves only the last build pending")
	for _frame in 600:
		if not surface._detail_pending:
			break
		await process_frame
	_check(not surface._detail_pending and surface.detail.position == Vector3.ZERO and surface.detail.get_child_count() == 2, "A superseded build is dropped and the disk is back at its own origin")
	surface.async_detail = false
	surface.show_region(Vector3.FORWARD)

## A pond of a landscape patch is water for the client as it is for the server: the surface is announced where the
## water stands above the ground, and nowhere else.
func _test_pond(surface: Node3D) -> void:
	var point := [0.0, 0.0, -1.0]
	var size := 200
	var grid := PackedFloat32Array()
	var water := PackedFloat32Array()
	grid.resize(size * size)
	grid.fill(-20.0)
	water.resize(size * size)
	water.fill(-4.0)
	var height_m: float = surface.elevation64_base(point) * 1000.0
	var saved: Array = surface._terrain_patches
	surface._terrain_patches = [{"place": "pond", "anchor": [0.0, 0.0, -6371.0], "anchor_height_m": height_m, "extent": [400.0, 400.0], "offset": [0.0, 0.0], "feather": 60.0, "axes": surface._terrain_axes(point), "heightmap_url": "", "water_url": "", "clear_url": "", "grid": grid, "water_grid": water, "clear_image": null, "width": size, "height": size}]
	var metres := [0.0, 0.0, -6371000.0 - height_m]
	var level: float = surface.water_surface_km(metres)
	_check(is_finite(level) and absf(level * 1000.0 - (height_m - 0.4)) < 0.01, "The surface of a pond is announced 40 cm under the anchor height")
	surface._terrain_patches = []
	_check(not is_finite(surface.water_surface_km(metres)) or absf(surface.water_surface_km(metres) * 1000.0 - (height_m - 0.4)) > 0.01, "Without the patch there is no pond")
	surface._terrain_patches = [{"place": "pond", "anchor": [0.0, 0.0, -6371.0], "anchor_height_m": height_m, "extent": [400.0, 400.0], "offset": [0.0, 0.0], "feather": 60.0, "axes": surface._terrain_axes(point), "heightmap_url": "", "water_url": "", "clear_url": "", "grid": grid, "water_grid": water, "clear_image": null, "width": size, "height": size}]
	grid.fill(0.0)
	surface._terrain_patches[0].grid = grid
	_check(not is_finite(surface.water_surface_km(metres)), "Water below the ground is not a surface")
	surface._terrain_patches = saved

## Grass is decorative and deterministic: the same place grows the same tufts, only grassy ground grows any.
func _test_grass(surface: Node3D) -> void:
	surface.show_region(Vector3.FORWARD)
	var first := _grass_signature(surface)
	surface.show_region(Vector3.FORWARD)
	_check(first[0] > 0, "Forest ground grows grass tufts")
	_check(first == _grass_signature(surface), "The same region grows exactly the same grass")
	var forest_count: int = first[0]
	surface.environment.biomes.fill(3)
	surface.show_region(Vector3.FORWARD)
	_check(_grass_signature(surface)[0] == 0, "Beaches grow no grass")
	surface.environment.biomes.fill(4)
	surface.show_region(Vector3.FORWARD)
	_check(_grass_signature(surface)[0] > forest_count, "Grassland is thicker than forest floor")
	surface.environment.biomes.fill(5)
	surface.show_region(Vector3.FORWARD)

## [tufts, checksum of every transform] of the grass under the region.
func _grass_signature(surface: Node3D) -> Array:
	var count := 0
	var sum := 0.0
	for chunk in surface.grass.get_children():
		var buffer: PackedFloat32Array = chunk.multimesh.buffer
		count += buffer.size() / 16
		for value in buffer:
			sum += value
	return [count, snappedf(sum, 0.0001)]

func _fixture(size: int) -> Dictionary:
	var count := size * size * 6
	var data := {"version":1,"heightmap_sha256":"fixture","seed":"18446744073709551615","face_size":size,"elevation_m":[],"water_m":[],"biomes":[],"downstream":[],"flow":[]}
	for index in count:
		data.elevation_m.append(1000)
		data.water_m.append(-8001)
		data.biomes.append(5)
		data.downstream.append(-1)
		data.flow.append(1)
	return data

func _object_fixture(surface: Node3D, biome: int = 5) -> Dictionary:
	var data := {"version":1,"heightmap_sha256":surface.environment.heightmap_sha256,"seed":surface.environment.seed,"objects":[]}
	var available: Array = surface.catalog.filter(func(entry: Dictionary) -> bool: return surface.BIOMES[biome] in entry.biomes)
	if available.is_empty():
		return data
	for index in 160:
		var direction: Vector3 = (Vector3.FORWARD * surface.RADIUS + Vector3((index % 16 - 8) * 0.012, (int(index / 16) - 5) * 0.012, 0)).normalized()
		var point: Vector3 = direction * (surface.RADIUS + surface.elevation(direction))
		var selected: Dictionary = available[index % available.size()]
		data.objects.append({"id":"%s:fixture:%d" % [data.seed,index],"model":selected.id,"position":[point.x*1000.0,point.y*1000.0,point.z*1000.0],"scale_m":selected.scale_m,"yaw":0.4,"collision_radius_m":0.5,"biome":biome})
	return data

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var surface := SURFACE.new()
	surface.land_material = ShaderMaterial.new()
	surface.land_material.shader = SHADER
	surface.water_material = ShaderMaterial.new()
	surface.water_material.shader = SHADER
	surface.water_material.set_shader_parameter("water_pass", true)
	world.add_child(surface)
	_check(surface.catalog.size() == 337, "All Nature variants, packs, ED waterfowl and the 0 A.D. flora and fauna have validated entries")
	_check(surface.catalog.filter(func(entry: Dictionary) -> bool: return entry.id.begins_with("nature.")).size() == 162, "161 Nature Kit variants plus the reed clump")
	for entry in surface.catalog:
		var scene := load(entry.scene) as PackedScene
		_check(scene != null, entry.id + " loads as a PackedScene")
		var model := scene.instantiate()
		_check(model is Node3D and not model.find_children("*", "MeshInstance3D", true, false).is_empty(), entry.id + " contains real 3D meshes")
		model.free()
	for face in 6:
		for position in [Vector2(-0.7, -0.4), Vector2(0.8, 0.6), Vector2.ZERO]:
			var mapped := surface.coordinates(surface.cube_point(face, position.x, position.y))
			_check(int(mapped.x) == face and absf(mapped.y - (position.x + 1) * 0.5) < 0.00001 and absf(mapped.z - (1 - position.y) * 0.5) < 0.00001, "Cube-sphere inverse preserves face, coordinates and north-up rows")
	var image := Image.create(96, 16, false, Image.FORMAT_L8)
	image.fill(Color(0.5625, 0.5625, 0.5625))
	surface.heightmap = image
	var texture := ImageTexture.create_from_image(image)
	for material in [surface.land_material, surface.water_material]:
		material.set_shader_parameter("heightmap", texture)
		material.set_shader_parameter("has_heightmap", true)
	var data := _fixture(16)
	_check(not surface.apply_environment(data, "another-map", data.seed), "Foreign heightmap checksum is rejected")
	_check(not surface.apply_environment(data, "fixture", "42"), "Foreign seed is rejected without integer precision loss")
	var invalid := data.duplicate(true)
	invalid.biomes[0] = 99
	_check(not surface.apply_environment(invalid, "fixture", data.seed), "Unknown biomes are rejected")
	invalid = data.duplicate(true)
	invalid.downstream[0] = data.biomes.size()
	_check(not surface.apply_environment(invalid, "fixture", data.seed), "Out-of-bounds drainage is rejected")
	_check(surface.apply_environment(data, "fixture", data.seed), "Valid server environment is accepted")
	surface.show_region(Vector3.FORWARD)
	_check(surface.placements.is_empty() and not surface.objects_loaded, "Missing backend objects are not replaced by invented local obstacles")
	var objects := _object_fixture(surface)
	_check(surface.apply_objects(objects), "Authoritative object region is accepted")
	_check(surface.placements.size() == 160 and surface.objects_loaded, "Forest streams the server's bounded populated region")
	var original := surface.placements.duplicate(true)
	surface.show_region(Vector3.FORWARD)
	_check(original == surface.placements, "Region refresh retains visible obstacles until their replacement arrives")
	_check(surface.apply_objects(objects) and original == surface.placements, "Repeated server data preserves model, identity, position, scale and rotation")
	var invalid_objects := objects.duplicate(true)
	invalid_objects.seed = "wrong"
	_check(not surface.apply_objects(invalid_objects) and surface.placements == original, "Foreign object identity cannot replace the current scene")
	invalid_objects = objects.duplicate(true)
	invalid_objects.objects[0].model = "unknown"
	_check(not surface.apply_objects(invalid_objects), "Unknown object models are rejected")
	invalid_objects = objects.duplicate(true)
	invalid_objects.objects[0].position[0] = INF
	_check(not surface.apply_objects(invalid_objects), "Non-finite object coordinates are rejected")
	invalid_objects = objects.duplicate(true)
	invalid_objects.objects[1].id = invalid_objects.objects[0].id
	_check(not surface.apply_objects(invalid_objects), "Duplicate obstacle identities are rejected")
	var precise: Array = objects.objects[0].position.duplicate()
	precise[0] -= 0.4
	surface.set_render_origin(precise)
	_check(absf(surface.objects.get_child(0).position.x - 0.0004) < 0.0000001, "Obstacle positioning preserves forty centimetres at planet-scale coordinates")
	var vertices: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	# A disk inscribed in the old square: full vertex grid, fewer triangles (about π/4 of the square).
	_check(vertices.size() == 129 * 129 and indices.size() < 128 * 128 * 6 and indices.size() > int(128 * 128 * 6 * 0.7), "Fine detail is a shared-vertex disk, not a floating square tile")
	_check(is_equal_approx(surface._detail_radius, surface.DETAIL_RADIUS), "Without a landscape patch the detail disk stays at the default radius")
	# A city patch (Uruk is 6 km) widens the disk so the walled precinct is not cut by a 700 m circle.
	surface._terrain_patches = [{"extent": [6000.0, 6000.0], "offset": [0.0, 0.0], "feather": 120.0, "axes": [[1, 0, 0], [0, 0, 1]], "grid": null, "water_grid": null, "width": 0, "height": 0, "anchor_height_m": 0.0, "place": "uruk", "heightmap_url": "", "water_url": "", "clear_url": ""}]
	surface.show_region(Vector3.FORWARD)
	var city_vertices: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(surface._detail_radius > surface.DETAIL_RADIUS + 0.5 and surface._detail_radius <= surface.DETAIL_RADIUS_MAX, "A landscape patch widens the detail disk toward the settlement")
	_check(city_vertices.size() == (surface._detail_segments + 1) * (surface._detail_segments + 1), "A widened disk keeps a shared-vertex grid scaled to its radius")
	surface._terrain_patches = []
	surface.show_region(Vector3.FORWARD)
	_check(surface.detail.top_level and surface.detail.get_child(0).material_override.get_shader_parameter("is_detail"), "Detail uses local coordinates without a second planet-scale transform")
	_check(vertices[0].length() < 2.0, "Detail vertices are local, not planet-scale")
	var shifted := precise.duplicate()
	shifted[0] += 0.01
	surface.set_render_origin(shifted)
	var rebased: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(absf((vertices[0].x - rebased[0].x) - 0.00001) < 0.0000001, "Terrain rebase preserves one centimetre without moving its absolute surface")
	surface.set_render_origin([])
	await _test_async_detail(surface)
	_test_grass(surface)
	_test_pond(surface)
	for placement in surface.placements:
		_check(placement.position.is_finite() and absf(placement.position.length() - (surface.RADIUS + surface.elevation(placement.position) + 0.0005)) < 0.002, "Objects stand on actual terrain")
	for sample in [
		[[1.0, 0.0, 0.0], "42", -7.595497428807521],
		[[1.0, 1.0, 0.0], "42", 4.106134823054352],
		[[1.0, 2.0, 3.0], "18446744073709551615", -1.7645037024417682],
		[[6371000.0, 0.01, 0.0], "42", -7.594750622916318],
	]:
		_check(absf(surface.relief64(sample[0], 1000.0, sample[1]) - sample[2]) < 0.000001, "Relief matches Rust's metre-scale reference, including seams and u64 seed")
	data.version = 2
	_check(surface.apply_environment(data, "fixture", data.seed), "Version two explicitly enables shared relief")
	_check(surface.apply_environment(JSON.parse_string(JSON.stringify(data)), "fixture", data.seed), "Version two is accepted after real JSON numeric decoding")
	var minimum := INF
	var maximum := -INF
	for metre in 1000:
		var point: Array = [6371000.0, float(metre), 0.0]
		var height: float = surface.elevation64(point)
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		point[1] += 0.01
		_check(absf(height - surface.elevation64(point)) < 0.000003, "Terrain height remains continuous during centimeter movement")
	_check(maximum - minimum > 0.01, "Walkable landscape has more than ten metres of local relief")
	data.seed = "43"
	_check(surface.apply_environment(data, "fixture", "43"), "Another seed is accepted with its matching identity")
	surface.show_region(Vector3.FORWARD)
	_check(surface.apply_objects(_object_fixture(surface)), "Object descriptors follow the new server identity")
	_check(original != surface.placements, "Seed changes object placement")
	if DisplayServer.get_name() != "headless":
		await _capture(world, surface, data)
	var lake := data.duplicate(true)
	lake.biomes.fill(1)
	lake.water_m.fill(2000)
	_check(surface.apply_environment(lake, "fixture", "43"), "Lake levels are accepted")
	surface.show_region(Vector3.FORWARD)
	_check(surface.placements.is_empty(), "No objects spawn underwater")
	_check(not surface.water_map.is_empty() and surface.water_map.has("texture"), "A flooded region bakes a water picture for the minimap")
	# Flow rivers on dry floodplain must not paint the whole coarse cell blue (Gilgamesh hunter).
	var river := data.duplicate(true)
	river.biomes.fill(2)
	river.elevation_m.fill(30)
	river.water_m.fill(30)
	_check(surface.apply_environment(river, "fixture", "43"), "A flow river cell is accepted")
	surface.heightmap = Image.create(16, 16, false, Image.FORMAT_RF)
	# Pixel 128 ≈ +31 m land (same encoding as the planet heightmap).
	surface.heightmap.fill(Color(128.0 / 255.0, 0, 0, 1))
	surface.show_region(Vector3(1, 0, 0))
	_check(not surface._minimap_water_at([1.0, 0.0, 0.0]), "A dry floodplain in a coarse river cell is not water on the minimap")
	# Landscape patches: bilinear sample at the south/east edge must not index past the grid
	# (regression: row+1 / column+1 without clamping → PackedFloat32Array out of bounds).
	var patch_axes: Array = surface._terrain_axes([1.0, 0.0, 0.0])
	var patch_grid := PackedFloat32Array()
	patch_grid.resize(4 * 4)
	for index in patch_grid.size():
		patch_grid[index] = float(index)
	var edge_patch := {
		"place": "edge",
		"grid": patch_grid,
		"water_grid": null,
		"width": 4,
		"height": 4,
		"extent": [40.0, 40.0],
		"offset": [0.0, 0.0],
		"feather": 2.0,
		"anchor_height_m": 1000.0,
		"anchor": [6371000.0, 0.0, 0.0],
		"axes": patch_axes,
	}
	surface._terrain_patches = [edge_patch]
	var rim_ok := true
	var rim_hit := false
	for local_x in [0.0, 19.5, -19.5]:
		for local_z in [0.0, 19.5, -19.5]:
			var direction: Array = [
				1.0 + float(patch_axes[0][0]) * local_x / 6371000.0 + float(patch_axes[1][0]) * local_z / 6371000.0,
				0.0 + float(patch_axes[0][1]) * local_x / 6371000.0 + float(patch_axes[1][1]) * local_z / 6371000.0,
				0.0 + float(patch_axes[0][2]) * local_x / 6371000.0 + float(patch_axes[1][2]) * local_z / 6371000.0,
			]
			var length := sqrt(direction[0] * direction[0] + direction[1] * direction[1] + direction[2] * direction[2])
			direction = [direction[0] / length, direction[1] / length, direction[2] / length]
			if surface._terrain_local(edge_patch, direction).is_empty():
				continue
			rim_hit = true
			var sample: float = surface._terrain_offset_m(direction, 1000.0)
			if not is_finite(sample):
				rim_ok = false
	_check(rim_hit and rim_ok, "Terrain patch height sample at the grid rim stays in bounds")
	surface._terrain_patches = []
	_check(surface._map_prop_kind("town.road") == "road", "Road modules are roads on the map")
	_check(surface._map_prop_kind("town.wall") == "building" and surface._map_prop_kind("quaternius.castle") == "building", "Walls and ready-made buildings are buildings on the map")
	_check(surface._map_prop_kind("disk:gilgamesh:media/models/architecture/uruk_quarter_01.glb") == "building", "Datadisk structures are buildings on the map whatever their model is named")
	_check(surface._map_prop_kind("town.tree").is_empty() and surface._map_prop_kind("retro.barrels").is_empty(), "Trees and crates stay off the map")
	var footprint: Vector2 = surface._kit_footprint(surface.prop_path("town.road"))
	_check(absf(footprint.x - 1.0) < 0.01 and absf(footprint.y - 1.0) < 0.01, "The road tile's footprint is one model unit square")
	for bridge in ["bridge_edge_wooden", "bridge_edge_hele", "broken_rope_bridge_long"]:
		_check(not surface.prop_path("zeroad." + bridge).is_empty(), "The 0 A.D. bridge %s resolves to a bundled model" % bridge)
	_check(surface.prop_path("zeroad.bridge_small").is_empty() and surface.prop_path("zeroad.../x").is_empty(), "Unknown or malformed 0 A.D. models resolve to nothing")
	var prop_region := {"version":1,"heightmap_sha256":surface.environment.heightmap_sha256,"seed":surface.environment.seed,"objects":[],"props":[
		{"id":"p1","model":"town.road","position":[0.0,6371000.0,0.0],"yaw":0.0,"scale_m":2.5},
		{"id":"p2","model":"town.wall","position":[1000.0,6371000.0,0.0],"yaw":0.0,"scale_m":2.5},
	]}
	_check(surface.apply_objects(prop_region), "A region with roads and buildings is accepted")
	var mapped: Array[Dictionary] = surface.map_props()
	_check(mapped.size() == 2 and mapped[0].kind == "road" and mapped[1].kind == "building", "Roads and buildings are mapped for the minimap")
	_check(mapped[0].position == Vector3(0.0, 6371000.0, 0.0), "Prop positions are metres from the planet's centre")
	_check(absf(mapped[0].size.x - 2.5) < 0.01, "The road tile's footprint is scaled to metres")
	var test_url := OS.get_environment("ISHTARIA_ENVIRONMENT_TEST_URL")
	if not test_url.is_empty():
		await _test_http(surface, test_url)
	surface.clear_world()
	_check(surface.environment.is_empty() and surface.heightmap == null and surface.objects.get_child_count() == 0, "Disconnect clears the entire former world")
	world.queue_free()
	await process_frame
	print("Surface environment: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_http(surface: Node3D, url: String) -> void:
	var loader := HTTPRequest.new()
	loader.timeout = 8.0
	loader.max_redirects = 0
	loader.body_size_limit = 16 * 1024 * 1024
	root.add_child(loader)
	var responses := {}
	for endpoint in ["/world", "/world/heightmap.png", "/world/environment"]:
		_check(loader.request(url + endpoint) == OK, "Environment HTTP request starts")
		var result: Array = await loader.request_completed
		_check(result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200, "Environment HTTP response succeeds: " + endpoint)
		if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
			loader.queue_free()
			return
		responses[endpoint] = result[3]
	loader.queue_free()
	var metadata: Dictionary = JSON.parse_string(responses["/world"].get_string_from_utf8())
	var data: Dictionary = JSON.parse_string(responses["/world/environment"].get_string_from_utf8())
	var image := Image.new()
	_check(image.load_png_from_buffer(responses["/world/heightmap.png"]) == OK, "HTTP terrain image decodes")
	_check(image.get_height() == metadata.face_size and image.get_width() == metadata.face_size * 6, "HTTP terrain dimensions match identity")
	surface.clear_world()
	surface.heightmap = image
	var texture := ImageTexture.create_from_image(image)
	for material in [surface.land_material, surface.water_material]:
		material.set_shader_parameter("heightmap", texture)
	_check(surface.apply_environment(data, metadata.sha256, metadata.seed), "Real persisted HTTP environment is accepted by the renderer")
	for biome in 8:
		_check(data.biomes.has(float(biome)), "Generated world contains " + surface.BIOMES[biome])
	var forest: int = data.biomes.find(5.0)
	if forest >= 0:
		surface.server_url = url
		surface.show_region(surface._cell_direction(forest))
		for frame in 240:
			if surface.objects_loaded:
				break
			await process_frame
		_check(not surface.placements.is_empty(), "HTTP-generated forest contains actual Kenney objects")
		var maximum_error := 0.0
		for placement in surface.placements:
			var point: Array = placement.coordinates
			var radius := sqrt(float(point[0]) * point[0] + float(point[1]) * point[1] + float(point[2]) * point[2])
			maximum_error = maxf(maximum_error, absf(radius - surface.RADIUS * 1000.0 - surface.elevation64(point) * 1000.0))
		_check(maximum_error < 0.001, "All live server object heights match client scalar terrain within one millimetre")
	_check(surface.get_node_or_null("Rivers") != null, "HTTP drainage generates a river mesh")

func _capture(world: Node3D, surface: Node3D, data: Dictionary) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(35, 140, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 0.5
	world.add_child(sun)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(0.55, 0.72, 0.82)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color.WHITE
	sky.environment.ambient_light_energy = 0.65
	world.add_child(sky)
	var camera := Camera3D.new()
	camera.near = 0.001
	camera.far = 20.0
	world.add_child(camera)
	camera.make_current()
	for biome in [5, 7, 6, 1]:
		data.biomes.fill(biome)
		data.water_m.fill(2000 if biome == 1 else -8001)
		_check(surface.apply_environment(data, "fixture", "43"), "Visual fixture applies")
		surface.show_region(Vector3.FORWARD)
		_check(surface.apply_objects(_object_fixture(surface, biome)), "Visual fixture uses authoritative-format object descriptors")
		var height: float = 2.0 if biome == 1 else surface.elevation(Vector3.FORWARD)
		var anchor: Array = [0.0, 0.0, -(surface.RADIUS + height) * 1000.0]
		surface.set_render_origin(anchor)
		var center := Vector3.ZERO
		camera.position = center + Vector3(0.07, 0.0, -0.055)
		camera.look_at(center, Vector3.FORWARD)
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
			root.get_window().size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			screenshot.save_png("/tmp/ishtaria-environment-%s-%dx%d.png" % [surface.BIOMES[biome], dimensions.x, dimensions.y])
			var colors := {}
			for row in range(0, screenshot.get_height(), 8):
				for column in range(0, screenshot.get_width(), 8):
					colors[screenshot.get_pixel(column, row).to_html()] = true
			_check(colors.size() > 20, "Native %s renders nonblank assets/water at %s" % [surface.BIOMES[biome], dimensions])