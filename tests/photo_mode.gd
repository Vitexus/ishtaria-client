extends SceneTree
## Photo mode: the camera takes over the game's own view, the bar stays usable, the sun is moved
## for the picture only, and everything borrowed is given back on the way out.
##
## A native run (`godot4 --path . --script res://tests/photo_mode.gd`) also checks that the mode
## leaves the cursor free; headless has no pointer to capture, so that one check is skipped there.

class StubControls extends Node:
	const RADIUS := 6371.0
	var avatar: Node3D
	var direction := Vector3.UP
	var yaw := 0.0
	var pitch := 0.0
	var _anchor_metres: Array = [0.0, 0.0, 0.0]

class StubSky extends Node:
	var preview_offset_seconds := 0.0

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

## The walking actions the camera flies by; the real ones are put in the map by `character_controls`.
func _register_actions() -> void:
	for action in ["walk_forward", "walk_backward", "walk_left", "walk_right", "run", "jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _run() -> void:
	_register_actions()
	var ui_root := Node.new()
	root.add_child(ui_root)
	var other := CanvasLayer.new()
	ui_root.add_child(other)

	var avatar := Node3D.new()
	root.add_child(avatar)
	var camera := Camera3D.new()
	root.add_child(camera)
	# The scene is in kilometres: the game camera stands two metres up and five metres behind.
	camera.position = Vector3(0.0, 0.002, 0.005)
	camera.look_at(avatar.position, Vector3.UP)
	camera.fov = 75.0
	var placed := camera.position
	var aimed := -camera.basis.z

	var controls := StubControls.new()
	controls.avatar = avatar
	var sky := StubSky.new()
	root.add_child(controls)
	root.add_child(sky)

	var photo := preload("res://scripts/photo_mode.gd").new()
	photo.camera = camera
	photo.controls = controls
	photo.sky = sky
	ui_root.add_child(photo)

	photo.open(ui_root)
	await process_frame
	await process_frame
	_check(photo.active, "the mode opens")
	_check(not other.visible, "the rest of the interface steps aside")
	# The bar carries sliders and a switch, so the pointer has to stay the player's. Headless has no
	# pointer to capture and always reads back VISIBLE, so only a native run can tell.
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the cursor stays free for the bar")
	_check(camera.position.distance_to(placed) < 0.000001, "the camera keeps the game's place: %s against %s" % [camera.position, placed])
	_check((-camera.basis.z).dot(aimed) > 0.9999, "the camera keeps the game's direction: %s against %s" % [-camera.basis.z, aimed])

	photo._time_slider.value = 3600.0
	_check(sky.preview_offset_seconds == 3600.0, "the time slider carries the sun for the picture: %f" % sky.preview_offset_seconds)
	photo._fov_slider.value = 30.0
	_check(camera.fov == 30.0, "the field of view follows its slider: %f" % camera.fov)

	photo._show_avatar.button_pressed = false
	_check(not avatar.visible, "the character can be left out of the picture")

	# `notice` is called without `await`, so it must not be a coroutine: a coroutine is refused and
	# the player is never told where the picture went.
	var hint: String = photo._hint.text
	photo.notice("Picture saved to /tmp/x.png")
	_check(photo._hint.text == "Picture saved to /tmp/x.png", "the bar says where the picture went: %s" % photo._hint.text)

	photo.close()
	await process_frame
	_check(not photo.active, "the mode closes")
	_check(other.visible, "the interface comes back")
	_check(avatar.visible, "the character comes back")
	_check(sky.preview_offset_seconds == 0.0, "the world's own sun is put back: %f" % sky.preview_offset_seconds)
	_check(camera.fov == 75.0, "the field of view is put back: %f" % camera.fov)
	photo.open(ui_root)
	await process_frame
	_check(photo._hint.text == hint, "a reopened bar shows the hint again, not the last message")
	photo.close()

	if _failures > 0:
		push_error("%d photo mode checks failed" % _failures)
	else:
		print("Photo mode checks passed")
	quit(1 if _failures > 0 else 0)
