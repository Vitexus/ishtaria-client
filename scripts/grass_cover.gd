extends RefCounted
## Decorative ground cover around the player: tufts of grass in MultiMesh chunks. Purely visual and
## client-side (never collides, never harvested, not part of `/world/objects`), so it is generated from
## the world seed and planet-fixed coordinates: the same place always grows the same grass, whatever
## the region disk is centred on.

## The player stays within 100 m of the region centre (main.gd re-targets beyond that) and sees VIEW_M further.
const HALF_M := 200.0
const CELL_M := 1.8
const CHUNK_M := 32.0
const VIEW_M := 90.0
const SLOPE_SAMPLE_M := 1.5
const MAX_SLOPE := 0.5
const BLADES := 14

var surface: Node3D
## Lets a visual test grow grass in any biome (the default flat plain of a fresh world is sand).
var every_biome := false
var _mesh: ArrayMesh
var _material: ShaderMaterial

func _init(host: Node3D) -> void:
	surface = host

## One tuft: a ring of tapered blades leaning outward, modelled in metres.
func tuft_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var random := RandomNumberGenerator.new()
	random.seed = 20261021
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for blade in BLADES:
		var yaw := TAU * (float(blade) + random.randf() * 0.6) / BLADES
		var outward := Vector3(cos(yaw), 0.0, sin(yaw))
		var across := Vector3(-outward.z, 0.0, outward.x)
		var root := outward * random.randf_range(0.04, 0.22)
		var height := random.randf_range(0.45, 0.95)
		var half_width := random.randf_range(0.035, 0.06)
		var lean := outward * random.randf_range(0.05, 0.28) + across * random.randf_range(-0.06, 0.06)
		vertices.append_array(PackedVector3Array([root - across * half_width, root + across * half_width, root + lean + Vector3(0.0, height, 0.0)]))
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh

func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://scripts/grass.gdshader")
	return _material

func _mix(cell_a: int, cell_b: int, salt: int) -> int:
	var value := (cell_a * 73856093) ^ (cell_b * 19349663) ^ (salt * 83492791)
	value &= 0xFFFFFFFF
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return value ^ (value >> 16)

## How thickly grass grows here, 0 to 1: grassland fully, forest floor partly, never on beaches, water or snow.
## Dry land of a landscape patch (a water-hole bank on a coarse river cell) grows grass even when the
## planet biome is floodplain — matching the server's wildlife placement rule.
func _density(point: Vector3) -> float:
	if every_biome:
		return 1.0
	match int(surface.environment.biomes[surface.environment_index(point)]):
		4:
			return 1.0
		5:
			return 0.55
	var direction := [point.x, point.y, point.z]
	if surface._terrain_offset_m(direction, surface.elevation64_base(direction) * 1000.0) != 0.0 \
			and not is_finite(surface._terrain_water_m(direction)):
		return 0.9
	return 0.0

## Worker-safe (reads terrain data only). Returns {chunk key: PackedFloat32Array of MultiMesh buffer rows},
## 16 floats per tuft: a 3x4 transform and an RGBA tint, positioned relative to `anchor` (metres).
func compute(unit: Vector3, anchor: Array) -> Dictionary:
	var radius_m: float = surface.RADIUS * 1000.0
	var axis := 0
	for index in 3:
		if absf(unit[index]) > absf(unit[axis]):
			axis = index
	var plane_a := (axis + 1) % 3
	var plane_b := (axis + 2) % 3
	var side := 1.0 if unit[axis] >= 0.0 else -1.0
	var centre_a := float(unit[plane_a]) * radius_m
	var centre_b := float(unit[plane_b]) * radius_m
	var salt := int(str(surface.environment.seed).hash()) ^ (axis * 7919)
	var gathered := {}
	for cell_a in range(int(floor((centre_a - HALF_M) / CELL_M)), int(floor((centre_a + HALF_M) / CELL_M)) + 1):
		for cell_b in range(int(floor((centre_b - HALF_M) / CELL_M)), int(floor((centre_b + HALF_M) / CELL_M)) + 1):
			var bits := _mix(cell_a, cell_b, salt)
			var plane_x := (float(cell_a) + float(bits & 255) / 256.0) * CELL_M
			var plane_y := (float(cell_b) + float((bits >> 8) & 255) / 256.0) * CELL_M
			var from_centre := Vector2(plane_x - centre_a, plane_y - centre_b)
			if from_centre.length_squared() > HALF_M * HALF_M:
				continue
			var direction := _direction(axis, side, plane_a, plane_b, plane_x, plane_y, radius_m)
			if direction.is_empty():
				continue
			var point := Vector3(direction[0], direction[1], direction[2])
			var density := _density(point)
			if density <= 0.0 or float((bits >> 16) & 255) / 256.0 >= density:
				continue
			var height: float = surface.elevation64(direction)
			var water: float = surface._detail_water_km(direction, point, height)
			if is_finite(water) and water >= height - 0.0001:
				continue
			var east: Array = _direction(axis, side, plane_a, plane_b, plane_x + SLOPE_SAMPLE_M, plane_y, radius_m)
			var north: Array = _direction(axis, side, plane_a, plane_b, plane_x, plane_y + SLOPE_SAMPLE_M, radius_m)
			if east.is_empty() or north.is_empty():
				continue
			var rise_east: float = (float(surface.elevation64(east)) - height) * 1000.0 / SLOPE_SAMPLE_M
			var rise_north: float = (float(surface.elevation64(north)) - height) * 1000.0 / SLOPE_SAMPLE_M
			if Vector2(rise_east, rise_north).length() > MAX_SLOPE:
				continue
			var variation := float((bits >> 24) & 255) / 255.0
			var scale := (0.55 + 0.9 * variation) * 0.001
			var up := point
			var tangent := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
			var basis := Basis(up, float(bits & 1023) / 1023.0 * TAU) * Basis(tangent, up, tangent.cross(up))
			basis = basis.scaled_local(Vector3(scale, scale, scale))
			var position: Vector3 = surface._position_from(anchor, [direction[0] * (radius_m + height * 1000.0), direction[1] * (radius_m + height * 1000.0), direction[2] * (radius_m + height * 1000.0)])
			var shade := 0.75 + 0.5 * float((bits >> 4) & 255) / 255.0
			var key := Vector2i(int(floor(plane_x / CHUNK_M)), int(floor(plane_y / CHUNK_M)))
			if not gathered.has(key):
				gathered[key] = []
			(gathered[key] as Array).append_array([
				basis.x.x, basis.y.x, basis.z.x, position.x,
				basis.x.y, basis.y.y, basis.z.y, position.y,
				basis.x.z, basis.y.z, basis.z.z, position.z,
				shade, shade, shade * (0.9 + 0.2 * variation), 1.0,
			])
	var chunks := {}
	for key: Vector2i in gathered:
		chunks[key] = PackedFloat32Array(gathered[key])
	return chunks

## The planet-fixed unit direction of a point of the plane lattice, or empty when it is off the sphere.
func _direction(axis: int, side: float, plane_a: int, plane_b: int, plane_x: float, plane_y: float, radius_m: float) -> Array:
	var rest := radius_m * radius_m - plane_x * plane_x - plane_y * plane_y
	if rest <= 0.0:
		return []
	var direction := [0.0, 0.0, 0.0]
	direction[plane_a] = plane_x / radius_m
	direction[plane_b] = plane_y / radius_m
	direction[axis] = side * sqrt(rest) / radius_m
	return direction

## Main thread: one MultiMeshInstance3D per chunk under `parent`, faded out beyond VIEW_M.
func apply(parent: Node3D, chunks: Dictionary) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	for key: Vector2i in chunks:
		var buffer: PackedFloat32Array = chunks[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = tuft_mesh()
		multimesh.instance_count = buffer.size() / 16
		multimesh.buffer = buffer
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = VIEW_M / 1000.0
		instance.visibility_range_end_margin = 10.0 / 1000.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(instance)
