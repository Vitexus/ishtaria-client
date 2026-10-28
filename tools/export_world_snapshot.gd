extends SceneTree

## Exports everything a running server shows around a place, as one JSON snapshot for offline
## scene building (the Gilgamesh cinematic): the world, the terrain heightmap strip, the
## landscape patches of the applied datadisk, and the objects, props, NPCs and areas of the
## region. Everything is written in the client's local frame at the landscape patch's anchor —
## scene x is the client's x, scene y is -the client's z, scene z is metres above the planet's
## radius — and each entry's yaw is the turn about +Z that puts a model's glTF +Z where the
## game client's placement quaternion (Quaternion(UP, normal) * Quaternion(UP, yaw)) puts it.
## Model ids resolve to files: `disk:<disk>:<path>` and `/story/media/<disk>/<path>` to the
## datadisk directory, catalog ids to the bundled assets. The patch PNGs are saved next to the
## JSON; an optional city plan JSON adds its gates, streets, canals and fields as an overlay.
##
##   godot4 --headless --path . --script res://tools/export_world_snapshot.gd -- \
##       [server] [lat_deg] [lon_deg] [extent_m] [datadisk_dir] [out_json] [grid_step_m] [plan_json]
##
## Defaults: http://127.0.0.1:7400  31.3228  45.6389  1800  /usr/share/ishtaria/datadisks
##           /tmp/world_snapshot.json  25  (no plan overlay)

const RADIUS_M := 6371000.0
# One /world/objects answer covers about +-267 m of scenery and keeps only the nearest 384
# objects; the smallest prop visibility is 250 m. A 200 m query grid puts every point within
# 142 m of a query, so no entry can fall between two answers or out of a truncated list.
const QUERY_SPACING_M := 200.0

var _server := ""
var _datadisk_dir := ""
var _out_path := ""
var _out_dir := ""
var _env: Node = null
var _axis_x := Vector3.ZERO
var _axis_z := Vector3.ZERO

func _initialize() -> void:
	_export.call_deferred()

func _export() -> void:
	var args := OS.get_cmdline_user_args()
	var server := args[0] if args.size() > 0 else "http://127.0.0.1:7400"
	var lat := float(args[1]) if args.size() > 1 else 31.3228
	var lon := float(args[2]) if args.size() > 2 else 45.6389
	var extent := float(args[3]) if args.size() > 3 else 1800.0
	var datadisk_dir := args[4] if args.size() > 4 else "/usr/share/ishtaria/datadisks"
	var out_path := args[5] if args.size() > 5 else "/tmp/world_snapshot.json"
	var grid_step := float(args[6]) if args.size() > 6 else 25.0
	var plan_path := args[7] if args.size() > 7 else ""
	_server = server.rstrip("/")
	_datadisk_dir = datadisk_dir.rstrip("/")
	_out_path = out_path
	_out_dir = out_path.get_base_dir()
	print("export_world_snapshot: %s around (%.4f, %.4f), +-%.0f m -> %s" % [_server, lat, lon, extent, out_path])

	# The client's own environment node: its strip parser, patch sampler and model catalog are
	# the exact code the game runs, so the snapshot cannot drift from what players see.
	var SE := preload("res://scripts/surface_environment.gd")
	_env = SE.new()
	root.add_child(_env)
	_env.server_url = _server

	var world: Dictionary = await _get_json(_server + "/world")
	var face_size := int(world.face_size)
	print("world: %s, ruleset %s, seed %s, face_size %d, server %s" % [world.server_name, world.ruleset, world.seed, face_size, world.server_version])

	var strip: Dictionary = await _get(_server + "/world/heightmap", 60.0)
	if strip.code != 200:
		push_error("heightmap strip: HTTP %d" % strip.code)
		quit(1)
		return
	_env.heightmap = _env.parse_strip(strip.body, face_size)
	if _env.heightmap.is_empty():
		push_error("heightmap strip did not parse")
		quit(1)
		return
	_env.heightmap_size = face_size
	print("heightmap strip: %d samples" % _env.heightmap.size())

	# The region at the requested point finds the landscape patch that defines the local frame.
	var centre := _planet(lat, lon)
	var first: Dictionary = await _get_json(_objects_url(centre))
	var terrains: Array = first.get("terrains", [])
	if terrains.is_empty():
		push_error("no landscape patch near (%.4f, %.4f)" % [lat, lon])
		quit(1)
		return
	var anchor := Vector3.ZERO
	var patch_place := ""
	var best := -1.0
	for entry: Variant in terrains:
		var p := Vector3(entry.position[0], entry.position[1], entry.position[2])
		var d := p.distance_to(centre)
		if best < 0.0 or d < best:
			best = d
			anchor = p
			patch_place = entry.place
	var unit := anchor.normalized()
	var axes: Array = _env._terrain_axes([unit.x, unit.y, unit.z])
	_axis_x = Vector3(axes[0][0], axes[0][1], axes[0][2])
	_axis_z = Vector3(axes[1][0], axes[1][1], axes[1][2])
	print("frame: patch %s, anchor %.0f m from the requested point" % [patch_place, best])

	# The whole region on a query grid (one answer covers about +-267 m of scenery).
	var merged := {"objects": {}, "npcs": {}, "props": {}, "areas": {}, "memorials": {}, "loot": {}}
	var n := int(extent / QUERY_SPACING_M)
	var queries := 0
	for gz in range(-n, n + 1):
		for gx in range(-n, n + 1):
			var point := anchor + _axis_x * (float(gx) * QUERY_SPACING_M) + _axis_z * (float(gz) * QUERY_SPACING_M)
			var region: Dictionary = await _get_json(_objects_url(point))
			queries += 1
			for key in ["objects", "npcs", "props", "areas", "memorials", "loot"]:
				for entry: Variant in region.get(key, []):
					merged[key][entry.id] = entry
	print("region: %d queries, %d objects, %d npcs, %d props, %d areas, %d memorials, %d loot" % [queries, merged.objects.size(), merged.npcs.size(), merged.props.size(), merged.areas.size(), merged.memorials.size(), merged.loot.size()])

	# The patches themselves, through the client's own loader, and saved as PNGs for the scene.
	var terrain_list: Array = []
	for entry: Variant in terrains:
		terrain_list.append(entry)
	if not _env.apply_terrains(terrain_list):
		push_error("the server's terrain patches were refused")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 90000
	while true:
		var pending := false
		for patch: Dictionary in _env._terrain_patches:
			if patch.get("grid") == null:
				pending = true
			elif String(patch.get("water_url", "")) != "" and patch.get("water_grid") == null:
				pending = true
			elif String(patch.get("clear_url", "")) != "" and patch.get("clear_image") == null:
				pending = true
		if not pending and _env._terrain_requests.is_empty():
			break
		if Time.get_ticks_msec() > deadline:
			push_error("patch download timed out")
			quit(1)
			return
		await process_frame
	var patch_files := {}
	for patch: Dictionary in _env._terrain_patches:
		var stem := String(patch.place).replace(":", "_")
		var files := {}
		for kind in ["heightmap_url", "water_url", "clear_url"]:
			var url := String(patch.get(kind, ""))
			if url == "":
				continue
			var name := "%s_%s.png" % [stem, kind.trim_suffix("_url")]
			var body: Dictionary = await _get(_server + url, 30.0)
			if body.code != 200:
				push_error("patch %s: HTTP %d" % [url, body.code])
				quit(1)
				return
			var f := FileAccess.open(_out_dir + "/" + name, FileAccess.WRITE)
			f.store_buffer(body.body)
			f.close()
			files[kind.trim_suffix("_url")] = name
		patch_files[patch.place] = files
	print("patches: %d saved (%s)" % [_env._terrain_patches.size(), str(patch_files)])

	# The ground: heights on a grid, in the same local frame, from the client's own sampler.
	var gnx := int(extent / grid_step) * 2 + 1
	var heights := []
	heights.resize(gnx * gnx)
	for iz in range(gnx):
		var z := -extent + float(iz) * grid_step
		for ix in range(gnx):
			var x := -extent + float(ix) * grid_step
			var point := anchor + _axis_x * x + _axis_z * z
			var u := point.normalized()
			heights[iz * gnx + ix] = snapped(_env.elevation64([u.x, u.y, u.z]) * 1000.0, 0.001)
	var anchor_height := _env.elevation64([unit.x, unit.y, unit.z]) * 1000.0
	print("ground: %d x %d samples at %.0f m, anchor height %.2f m" % [gnx, gnx, grid_step, anchor_height])

	var snapshot := {
		"tool": "res://tools/export_world_snapshot.gd",
		"server": _server,
		"fetched_unix": int(Time.get_unix_time_from_system()),
		"world": world,
		"frame": {
			"anchor_ecef": [anchor.x, anchor.y, anchor.z],
			"axis_x": [_axis_x.x, _axis_x.y, _axis_x.z],
			"axis_z": [_axis_z.x, _axis_z.y, _axis_z.z],
			"up": [unit.x, unit.y, unit.z],
			"radius_m": RADIUS_M,
			"anchor_height_m": anchor_height,
			"note": "scene x = client-local x, scene y = -client-local z, scene z = metres above the radius; yaw turns about +Z",
		},
		"patches": [],
		"ground": {"step_m": grid_step, "extent_m": extent, "nx": gnx, "nz": gnx, "heights": heights},
		"props": [],
		"npcs": [],
		"objects": [],
		"areas": [],
		"memorials": [],
		"loot": [],
		"counts": {"queries": queries},
	}
	for patch: Dictionary in _env._terrain_patches:
		var raw: Dictionary = {}
		for entry: Variant in terrains:
			if entry.place == patch.place:
				raw = entry
				break
		snapshot.patches.append({
			"place": patch.place,
			"files": patch_files.get(patch.place, {}),
			"width": patch.width,
			"height": patch.height,
			"extent_m": raw.get("extent_m", []),
			"offset_m": raw.get("offset_m", []),
			"feather_m": raw.get("feather_m", 0.0),
			"anchor_height_m": raw.get("height_m", 0.0),
		})

	var prop_patch: Dictionary = {}
	for patch: Dictionary in _env._terrain_patches:
		if patch.place == patch_place:
			prop_patch = patch
	for entry: Variant in merged.props.values():
		snapshot.props.append(_prop_entry(entry, prop_patch))
	for entry: Variant in merged.npcs.values():
		snapshot.npcs.append(_npc_entry(entry, prop_patch))
	for entry: Variant in merged.objects.values():
		snapshot.objects.append(_object_entry(entry, prop_patch, SE))
	for entry: Variant in merged.areas.values():
		snapshot.areas.append(_area_entry(entry, prop_patch))
	for entry: Variant in merged.memorials.values():
		snapshot.memorials.append(_memorial_entry(entry, prop_patch))
	for entry: Variant in merged.loot.values():
		snapshot.loot.append(_loot_entry(entry, prop_patch))
	snapshot.counts.props = snapshot.props.size()
	snapshot.counts.npcs = snapshot.npcs.size()
	snapshot.counts.objects = snapshot.objects.size()
	snapshot.counts.areas = snapshot.areas.size()
	snapshot.counts.memorials = snapshot.memorials.size()
	snapshot.counts.loot = snapshot.loot.size()

	if plan_path != "":
		snapshot.plan = _plan_overlay(plan_path)

	var output := FileAccess.open(_out_path, FileAccess.WRITE)
	if output == null:
		push_error("cannot write " + _out_path)
		quit(1)
		return
	output.store_string(JSON.stringify(snapshot) + "\n")
	output.close()
	print("snapshot: %s (%d bytes), %d props, %d npcs, %d objects, %d areas, %d memorials, %d loot" % [_out_path, FileAccess.get_file_as_bytes(_out_path).size(), snapshot.props.size(), snapshot.npcs.size(), snapshot.objects.size(), snapshot.areas.size(), snapshot.memorials.size(), snapshot.loot.size()])

	# A few landmarks, to check the frame against the city plan by eye.
	for prop: Dictionary in snapshot.props:
		if prop.id in ["gilgamesh:ishtar_temple", "gilgamesh:lamassu_ishtar_ziggurat", "gilgamesh:uruk", "gilgamesh:eanna_temple"]:
			print("  %-38s scene (%8.1f, %8.1f) yaw %7.1f deg  ground %.2f m" % [prop.id, prop.x, prop.y, rad_to_deg(prop.yaw), prop.ground_m])
	if snapshot.has("plan"):
		for gate: Dictionary in snapshot.plan.gates:
			print("  gate %-10s scene (%8.1f, %8.1f)" % [gate.name, gate.pos[0], gate.pos[1]])
	quit(0)

func _planet(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(RADIUS_M * cos(lat) * cos(lon), RADIUS_M * sin(lat), -RADIUS_M * cos(lat) * sin(lon))

func _objects_url(point: Vector3) -> String:
	return "%s/world/objects?x=%.9f&y=%.9f&z=%.9f" % [_server, point.x, point.y, point.z]

## One HTTP GET, awaited frame by frame. Returns {"code": int, "body": PackedByteArray}.
func _get(url: String, timeout := 20.0) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = timeout
	request.max_redirects = 0
	request.body_size_limit = 32 << 20
	root.add_child(request)
	var answer: Array = []
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		answer.append(code)
		answer.append(body))
	request.request(url)
	var started := Time.get_ticks_msec()
	while answer.is_empty():
		if Time.get_ticks_msec() - started > int(timeout * 1000.0):
			request.cancel_request()
			request.queue_free()
			return {"code": -1, "body": PackedByteArray()}
		await process_frame
	request.queue_free()
	return {"code": answer[0], "body": answer[1]}

func _get_json(url: String) -> Dictionary:
	var answer := await _get(url)
	if answer.code != 200:
		push_error("GET %s: HTTP %d" % [url, answer.code])
		quit(1)
		return {}
	var parsed: Variant = JSON.parse_string(answer.body.get_string_from_utf8())
	if not parsed is Dictionary:
		push_error("GET %s: not a JSON object" % url)
		quit(1)
		return {}
	return parsed

## Scene x/y (metres from the anchor, y = -client-local z) and the ground height above the
## radius at an ECEF position, through the client's own patch sampler.
func _scene_of(position: Vector3, patch: Dictionary) -> Array:
	var unit := position.normalized()
	var local: Array = _env._terrain_local(patch, [unit.x, unit.y, unit.z])
	var x: float
	var z: float
	if local.is_empty():
		# The patch dictionary keeps its anchor in kilometres; the entries arrive in metres.
		var d := position - Vector3(patch.anchor[0] * 1000.0, patch.anchor[1] * 1000.0, patch.anchor[2] * 1000.0)
		x = d.dot(_axis_x)
		z = d.dot(_axis_z)
	else:
		x = local[0]
		z = local[1]
	var ground := _env.elevation64([unit.x, unit.y, unit.z]) * 1000.0
	return [x, -z, ground]

## The Blender yaw (about +Z) that puts a model's glTF +Z where the client's placement puts it.
func _scene_yaw(position: Vector3, yaw: float) -> float:
	var unit := position.normalized()
	var q := Quaternion(Vector3.UP, unit) * Quaternion(Vector3.UP, yaw)
	var nose := q * Vector3(0, 0, 1)
	return atan2(nose.dot(_axis_x), nose.dot(_axis_z))

func _disk_file(model: String) -> String:
	if model.begins_with("disk:"):
		var parts := model.split(":")
		if parts.size() != 3 or parts[1].is_empty() or parts[2].is_empty():
			return ""
		return _datadisk_dir + "/" + parts[1] + "/" + parts[2]
	if model.begins_with("/story/media/"):
		var rest := model.trim_prefix("/story/media/")
		var slash := rest.find("/")
		if slash <= 0:
			return ""
		return _datadisk_dir + "/" + rest.substr(0, slash) + "/" + rest.substr(slash + 1)
	return ""

func _prop_entry(entry: Dictionary, patch: Dictionary) -> Dictionary:
	var position := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var scene: Array = _scene_of(position, patch)
	var model := String(entry.get("model", ""))
	var file := _disk_file(model)
	if file != "" and not FileAccess.file_exists(file):
		push_warning("prop %s: model file missing: %s" % [entry.id, file])
		return {
		"id": entry.id,
		"model": model,
		"file": file,
		"x": snapped(scene[0], 0.001),
		"y": snapped(scene[1], 0.001),
		"yaw": snapped(_scene_yaw(position, float(entry.get("yaw", 0.0))), 0.0001),
		"scale_m": entry.get("scale_m", 1.0),
		"visible_m": entry.get("visible_m", 0.0),
		"ground_m": snapped(scene[2], 0.001),
		"ecef": [position.x, position.y, position.z],
	}

func _npc_entry(entry: Dictionary, patch: Dictionary) -> Dictionary:
	var position := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var scene: Array = _scene_of(position, patch)
	var model := String(entry.get("model", ""))
	var out := {
		"id": entry.id,
		"name_key": entry.get("name_key", ""),
		"character": entry.get("character", ""),
		"model": model,
		"file": _disk_file(model),
		"x": snapped(scene[0], 0.001),
		"y": snapped(scene[1], 0.001),
		"yaw": snapped(_scene_yaw(position, float(entry.get("yaw", 0.0))), 0.0001),
		"scale_m": entry.get("scale_m", 1.0),
		"ground_m": snapped(scene[2], 0.001),
		"ecef": [position.x, position.y, position.z],
	}
	if entry.has("wander"):
		out.wander = entry.wander
	return out

func _object_entry(entry: Dictionary, patch: Dictionary, SE: GDScript) -> Dictionary:
	var position := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var scene: Array = _scene_of(position, patch)
	var model := String(entry.get("model", ""))
	var scene_path := String(SE.prop_path(model))
	var file := ""
	if scene_path != "":
		file = ProjectSettings.globalize_path(scene_path)
	var info: Dictionary = _env._models.get(model, {})
	var out := {
		"id": entry.id,
		"model": model,
		"scene": scene_path,
		"file": file,
		"face_z": info.get("face_z", 1),
		"x": snapped(scene[0], 0.001),
		"y": snapped(scene[1], 0.001),
		"yaw": snapped(_scene_yaw(position, float(entry.get("yaw", 0.0))), 0.0001),
		"scale_m": entry.get("scale_m", 1.0),
		"ground_offset_m": entry.get("ground_offset_m", 0.0),
		"biome": entry.get("biome", 0),
		"ground_m": snapped(scene[2], 0.001),
		"ecef": [position.x, position.y, position.z],
	}
	if info.has("animation"):
		out.animation = info.animation
	if info.has("swim_radius_m"):
		out.swim_radius_m = info.swim_radius_m
	if entry.has("harvest"):
		out.harvest = entry.harvest
	return out

func _area_entry(entry: Dictionary, patch: Dictionary) -> Dictionary:
	var position := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var scene: Array = _scene_of(position, patch)
	return {
		"id": entry.id,
		"x": snapped(scene[0], 0.001),
		"y": snapped(scene[1], 0.001),
		"radius_m": entry.get("radius_m", 0.0),
		"music": entry.get("music", {}),
		"ground_m": snapped(scene[2], 0.001),
	}

## A player memorial: a Kenney graveyard model of its kind, four metres tall in the game.
func _memorial_entry(entry: Dictionary, patch: Dictionary) -> Dictionary:
	var position := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var scene: Array = _scene_of(position, patch)
	return {
		"id": entry.id,
		"player_name": entry.get("player_name", ""),
		"kind": entry.get("kind", "headstone"),
		"x": snapped(scene[0], 0.001),
		"y": snapped(scene[1], 0.001),
		"ground_m": snapped(scene[2], 0.001),
		"ecef": [position.x, position.y, position.z],
	}

## A pile of items dropped on the ground; the game shows it as a floating icon, the scene can
## put the item itself down.
func _loot_entry(entry: Dictionary, patch: Dictionary) -> Dictionary:
	var position := Vector3(entry.position_x, entry.position_y, entry.position_z)
	var scene: Array = _scene_of(position, patch)
	var out := {
		"id": entry.id,
		"item_id": entry.get("item_id", ""),
		"name": entry.get("name", ""),
		"quantity": entry.get("quantity", ""),
		"x": snapped(scene[0], 0.001),
		"y": snapped(scene[1], 0.001),
		"ground_m": snapped(scene[2], 0.001),
		"ecef": [position.x, position.y, position.z],
	}
	if entry.get("durability") != null:
		out.durability = entry.durability
	if entry.get("max_durability") != null:
		out.max_durability = entry.max_durability
	return out

## The city plan of the datadisk (tools/data/uruk_city.json), converted to scene metres.
func _plan_overlay(plan_path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if not parsed is Dictionary:
		push_error("plan %s did not parse" % plan_path)
		quit(1)
		return {}
	var plan: Dictionary = parsed
	var point = func(p: Variant) -> Array:
		return [snapped(float(p[0]), 0.001), snapped(-float(p[1]), 0.001)]
	var gates := []
	for gate: Variant in plan.get("gates", []):
		gates.append({
			"name": gate.get("name", ""),
			"pos": point.call(gate.pos),
			"out": point.call(gate.out),
			"tangent": point.call(gate.tangent),
			"height": gate.get("height", 0.0),
		})
	var streets := []
	for street: Variant in plan.get("streets", []):
		var pts := []
		for p: Variant in street.pts:
			pts.append(point.call(p))
		streets.append({"kind": street.get("kind", ""), "width": street.get("width", 0.0), "name": street.get("name", ""), "pts": pts})
	var canals := []
	for canal: Variant in plan.get("canals", []):
		var pts := []
		for p: Variant in canal.pts:
			pts.append(point.call(p))
		canals.append({"width": canal.get("width", 0.0), "pts": pts})
	var fields := []
	for field: Variant in plan.get("fields", []):
		fields.append({
			"c": point.call(field.c),
			"t": [snapped(float(field.t[0]), 0.001), snapped(-float(field.t[1]), 0.001)],
			"w": field.get("w", 0.0),
			"d": field.get("d", 0.0),
			"kind": field.get("kind", ""),
		})
	return {
		"source": plan_path,
		"gates": gates,
		"streets": streets,
		"canals": canals,
		"fields": fields,
		"fixed": plan.get("fixed", {}),
		"ishtar_ziggurat": plan.get("ishtar_ziggurat", {}),
	}
