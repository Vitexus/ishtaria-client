extends SceneTree
## Connects to a Gilgamesh world, teleports to Uruk via SQL on the local DB, and saves
## low oblique screenshots of its houses and ground (`make run` style check of buildings/uruk.yaml and `ground: alluvial`). Needs a display, ISHTARIA_TEST_SERVER, and DATABASE_URL
## (or ISHTARIA_AERIAL_DB) so the player can be moved to the city anchor.

const PLANET_RADIUS_M := 6371000.0
const AERIAL_HEIGHT_M := 2200.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var url := OS.get_environment("ISHTARIA_TEST_SERVER")
	if url.is_empty():
		push_error("ISHTARIA_TEST_SERVER is required")
		quit(1)
		return
	var out := OS.get_environment("ISHTARIA_SHOT_DIR")
	if out.is_empty():
		out = "/tmp"
	var db := OS.get_environment("ISHTARIA_AERIAL_DB")
	if db.is_empty():
		db = OS.get_environment("DATABASE_URL")
	if db.is_empty():
		db = "postgresql:///ishtaria_gilgamesh_dev?host=/var/run/postgresql"
	OS.set_environment("ISHTARIA_SERVER_URL", url)
	var name := "aerial-%d" % (Time.get_ticks_usec() % 100000)
	var password := "aerial-shot"
	# Register first so SQL can move the row, then the client logs in at Uruk.
	var character := "survivors/survivorMaleB"
	if not await _register(url, name, password, character):
		quit(1)
		return
	var uruk := _uruk_metres(db)
	if uruk.is_empty():
		push_error("could not resolve gilgamesh:uruk from story_anchors")
		quit(1)
		return
	# ISHTARIA_SHOT_OFFSET="x,z": stand that many metres from the anchor of Uruk (plan frame: x east, z south),
	# e.g. beside a building listed in the datadisk's buildings/uruk.yaml.
	var shift := OS.get_environment("ISHTARIA_SHOT_OFFSET").split(",")
	if shift.size() == 2:
		# The plan's frame is the client's local one: +X and +Z carried to the site by the shortest arc from +Y.
		var up := Vector3(uruk[0], uruk[1], uruk[2]).normalized()
		var turn := Quaternion(Vector3.UP, up)
		var moved := Vector3(uruk[0], uruk[1], uruk[2]) + (turn * Vector3.RIGHT) * float(shift[0]) + (turn * Vector3.BACK) * float(shift[1])
		moved = moved.normalized() * Vector3(uruk[0], uruk[1], uruk[2]).length()
		uruk = [moved.x, moved.y, moved.z]
	if not _teleport(db, name, uruk):
		quit(1)
		return
	print("teleported %s to Uruk at %s" % [name, str(uruk)])
	var client := (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	client._settings_path = "user://uruk-aerial-%d.cfg" % OS.get_process_id()
	root.add_child(client)
	root.size = Vector2i(1920, 1080)
	await create_timer(1.5).timeout
	client._session.submit(name, password, character, false)
	var waited := 0.0
	while not client._controls.active and waited < 90.0:
		# Skip the cinematic landing once the city geometry is here.
		if client._surface_direction != Vector3.ZERO and client._environment.objects_loaded:
			client._approach_elapsed = client.APPROACH_SECONDS
		if client._settle_elapsed >= 0.0:
			client._settle_elapsed = maxf(client._settle_elapsed, client.SETTLE_SECONDS)
		await create_timer(0.25).timeout
		waited += 0.25
	print("surface active after %.1f s: %s" % [waited, str(client._controls.active)])
	if not client._controls.active:
		push_error("controls never became active")
		quit(1)
		return
	var min_filled := 20 if OS.get_environment("ISHTARIA_MIN_FILLED").is_empty() else int(OS.get_environment("ISHTARIA_MIN_FILLED"))
	# Prop Node3Ds appear at once; the disk GLBs arrive later through fetch_media.
	waited = 0.0
	while waited < 120.0:
		var waiting: int = client._environment._structure_waiting.size()
		var pending: int = client._story._pending_media.size()
		var filled := _filled_structures(client)
		var patches_ready := _terrain_patches_ready(client)
		print("structures filled=%d/%d waiting_urls=%d pending_media=%d terrain=%s (%.1fs)" % [
			filled, client._environment.props.get_child_count(), waiting, pending, str(patches_ready), waited,
		])
		if waiting == 0 and pending == 0 and filled >= min_filled and patches_ready and client._environment.detail.get_child_count() > 0:
			break
		await create_timer(1.0).timeout
		waited += 1.0
	print("objects loaded: props=%d filled=%d models=%d npcs=%d" % [
		client._environment.props.get_child_count(),
		_filled_structures(client),
		client._environment._structure_models.size(),
		client._environment.npcs.get_child_count(),
	])
	if _filled_structures(client) < min_filled:
		push_error("too few city models arrived; aerial shot would be empty")
		quit(1)
		return
	# Freeze the client so approach / third-person follow cannot steal the camera.
	client.set_process(false)
	client._controls.set_process(false)
	for child in client._environment.detail.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			var material: ShaderMaterial = child.material_override
			print("detail material: is_detail=%s use_textures=%s biome_layers=%s" % [material.get_shader_parameter("is_detail"), material.get_shader_parameter("use_textures"), material.get_shader_parameter("biome_layers")])
	client._hud.hide()
	client._tablet.hide()
	client._minimap.hide()
	client._quest_indicator.hide()
	client._quest_compass.hide()
	if client._disk_cover != null:
		client._disk_cover.dismiss()
		client._disk_cover.hide()
	client._controls.release_mouse()
	if is_instance_valid(client._controls.avatar):
		client._controls.avatar.hide()
	# ISHTARIA_HIDE="props,objects,detail,npcs": hide those layers, to find which one draws something odd.
	for layer: String in OS.get_environment("ISHTARIA_HIDE").split(","):
		var node: Variant = client._environment.get(layer)
		if node is Node3D:
			node.hide()
	var needle := OS.get_environment("ISHTARIA_HIDE_MODEL")
	if not needle.is_empty():
		var hidden := 0
		for index in client._environment._prop_entries.size():
			var entry: Dictionary = client._environment._prop_entries[index]
			if String(entry.get("model", "")).contains(needle):
				client._environment.props.get_child(index).hide()
				hidden += 1
		print("hid %d props matching %s" % [hidden, needle])
	_force_local_noon(client)
	await create_timer(0.5).timeout
	if OS.get_environment("ISHTARIA_HITCH") == "1":
		# The region is asked for again as it is while walking: the longest frame while the answer is built is the hitch.
		for round_number in 3:
			client._environment.refresh_objects()
			var worst := 0.0
			var last := Time.get_ticks_usec()
			for _frame in 240:
				await process_frame
				var now := Time.get_ticks_usec()
				worst = maxf(worst, float(now - last) / 1000.0)
				last = now
			print("refresh %d: longest frame %.0f ms, %d props, %d fills waiting" % [round_number, worst, client._environment.props.get_child_count(), client._environment._fill_queue.size()])
	# Low and oblique: the houses of the city, their plots and the ground of the alluvial set.
	var shots: Array = [["house", 22.0, 0.45], ["house2", 80.0, 0.5], ["close", 22.0, 0.8], ["ground", 5.0, 2.2], ["street", 70.0, 0.9], ["quarter", 420.0, 0.7]]
	# ISHTARIA_SHOTS="name:height_m:tilt,...": other views, e.g. "horizon:3:8" looks far across the ground from 3 m.
	if not OS.get_environment("ISHTARIA_SHOTS").is_empty():
		shots = []
		for text: String in OS.get_environment("ISHTARIA_SHOTS").split(","):
			var fields := text.split(":")
			shots.append([fields[0], float(fields[1]), float(fields[2])])
	for shot: Array in shots:
		_aim_oblique(client, shot[1], shot[2])
		for _frame in 14:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/ishtaria-uruk-%s.png" % [out, shot[0]]
		root.get_texture().get_image().save_png(path)
		print("saved %s" % path)
	quit(0)

func _filled_structures(client: Node) -> int:
	var filled := 0
	for child in client._environment.props.get_children():
		if child.get_child_count() > 0:
			filled += 1
	return filled

func _terrain_patches_ready(client: Node) -> bool:
	if client._environment._terrain_patches.is_empty():
		return false
	for patch: Dictionary in client._environment._terrain_patches:
		if patch.get("grid") == null:
			return false
	return true

func _register(url: String, username: String, password: String, character: String) -> bool:
	var http := HTTPRequest.new()
	root.add_child(http)
	var body := JSON.stringify({"username": username, "password": password, "character": character})
	var err := http.request(url + "/players", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("register request failed: %s" % err)
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	if code != 200 and code != 201:
		push_error("register HTTP %d: %s" % [code, (result[3] as PackedByteArray).get_string_from_utf8()])
		return false
	return true

func _uruk_metres(db: String) -> Array:
	var output: Array = []
	var status := OS.execute("psql", [db, "-tA", "-c",
		"SELECT direction_x, direction_y, direction_z, height_m FROM story_anchors WHERE anchor_id = '" + OS.get_environment("ISHTARIA_SHOT_PLACE") + "' LIMIT 1"],
		output, true)
	if status != 0 or output.is_empty():
		return []
	var parts: PackedStringArray = String(output[0]).strip_edges().split("|")
	if parts.size() != 4:
		return []
	var dx := float(parts[0])
	var dy := float(parts[1])
	var dz := float(parts[2])
	var height := float(parts[3])
	var radius := PLANET_RADIUS_M + height
	return [dx * radius, dy * radius, dz * radius]

func _teleport(db: String, username: String, metres: Array) -> bool:
	var sql := "UPDATE players SET position_x = %s, position_y = %s, position_z = %s, movement_sequence = COALESCE(movement_sequence, 0) + 1, movement_airborne = false, last_moved_at = clock_timestamp() WHERE username = '%s'" % [
		str(metres[0]), str(metres[1]), str(metres[2]), username.replace("'", "''"),
	]
	var output: Array = []
	var status := OS.execute("psql", [db, "-c", sql], output, true)
	if status != 0:
		push_error("teleport failed: %s" % "\n".join(output))
		return false
	return true

func _ground_target(client: Node) -> Vector3:
	if is_instance_valid(client._controls.avatar):
		return client._controls.avatar.position
	return client._controls._position_target

func _tangent_north(up: Vector3) -> Vector3:
	var north := Vector3.UP
	if absf(up.dot(north)) > 0.95:
		north = Vector3.FORWARD
	var east := up.cross(north).normalized()
	return east.cross(up).normalized()

## Puts the shared solar clock at true local noon above the player (highest sun).
func _force_local_noon(client: Node) -> void:
	var sky: Node = client._sky
	var observer: Vector3 = client._controls.direction.normalized()
	sky.set_observer(observer)
	# Search the current UTC day so seasonal declination matches today's sun height.
	var day_start := floorf(Time.get_unix_time_from_system() / 86400.0) * 86400.0
	var best := day_start
	var best_dot := -2.0
	for step in 1440:
		var seconds := day_start + step * 60.0
		var elevation := observer.dot(sky.solar_direction(seconds))
		if elevation > best_dot:
			best_dot = elevation
			best = seconds
	for step in range(-60, 61):
		var seconds := best + float(step)
		var elevation := observer.dot(sky.solar_direction(seconds))
		if elevation > best_dot:
			best_dot = elevation
			best = seconds
	var direction: Vector3 = sky.solar_direction(best)
	var solar := {
		"version": 1,
		"unix_seconds": best,
		"direction": [direction.x, direction.y, direction.z],
		"sidereal_day_seconds": 86164.0905,
		"angular_radius_degrees": 0.26779660030765046,
	}
	sky.apply_solar(solar)
	client._environment.set_night(0.0)
	var clock: Dictionary = sky.clock_state()
	print("local noon: elev=%.1f° local_seconds=%.0f day=%s" % [
		rad_to_deg(asin(clampf(best_dot, -1.0, 1.0))),
		float(clock.get("local_seconds", -1.0)),
		str(clock.get("day", false)),
	])

func _aim_aerial(client: Node, height_m: float) -> void:
	var up: Vector3 = client._controls.direction.normalized()
	var target := _ground_target(client)
	client._camera.far = maxf(8.0, height_m / 1000.0 + 5.0)
	client._camera.near = 0.0005
	client._camera.fov = 55.0
	client._camera.position = target + up * (height_m / 1000.0)
	client._camera.look_at(target, _tangent_north(up))
	client._sky.set_altitude(height_m, true)
	client._sky.set_observer(up)
	_force_local_noon(client)

func _aim_oblique(client: Node, height_m: float, tilt: float) -> void:
	var up: Vector3 = client._controls.direction.normalized()
	var target := _ground_target(client)
	var north := _tangent_north(up)
	client._camera.far = maxf(8.0, height_m / 1000.0 + 5.0)
	client._camera.near = 0.0005
	client._camera.fov = 50.0
	client._camera.position = target + up * (height_m / 1000.0) - north * (height_m / 1000.0 * tilt)
	client._camera.look_at(target, up)
	client._sky.set_altitude(height_m, true)
	client._sky.set_observer(up)
	_force_local_noon(client)
