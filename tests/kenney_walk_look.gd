extends SceneTree

## One-off visual check: poses a pack character through its walk clip and saves frames.
## Run natively: godot4 --path . --script res://tests/kenney_walk_look.gd -- <character> <out dir>

const CATALOG := preload("res://scripts/character_catalog.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var character := args[0] if args.size() > 0 else "protagonists/criminalMaleA"
	var out_dir := args[1] if args.size() > 1 else "/tmp"
	var model := CATALOG.create_model(character)
	root.add_child(model)
	await process_frame
	var player := model.get_node_or_null("CharacterAnimation") as AnimationPlayer
	if player == null or not player.has_animation("walk"):
		push_error("no walk clip")
		quit(1)
		return
	# The client works in kilometres: frame the camera on the model's own size.
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	var height := maxf(box.size.y, 0.000001)
	var centre := box.get_center()
	var camera := Camera3D.new()
	camera.near = height * 0.01
	camera.far = height * 100.0
	root.add_child(camera)
	camera.look_at_from_position(centre + Vector3(height * 1.4, height * 0.1, height * 0.9), centre)
	camera.current = true
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation = Vector3(-0.8, 0.6, 0)
	light.light_energy = 1.4
	player.play("walk")
	var length := player.get_animation("walk").length
	for i in 12:
		player.seek(length * float(i) / 12.0, true)
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("%s/walk_%02d.png" % [out_dir, i])
	print("saved frames for %s, clip length %.3f s, height %.6f" % [character, length, height])
	quit(0)
