extends SceneTree
## A datadisk's own model walks at the pace of its walking clip: the hunter of the Gilgamesh disk
## walks about 1.3 m/s in his clip, drawn 2.09 times his metres like every disk model, so about
## 2.8 m/s on the ground; at the server's 4 m/s the clip plays about 1.4 times as fast and the
## feet keep their place instead of sliding along under short steps.
## Skipped when the Gilgamesh datadisk is neither beside the client nor installed.

const CATALOG := preload("res://scripts/character_catalog.gd")
const STORY := preload("res://scripts/story_client.gd")
const CONTROLS := preload("res://scripts/character_controls.gd")
const MODELS := ["../ishtaria-datadisk-gilgamesh/media/models/hunter.glb", "/usr/share/ishtaria/datadisks/gilgamesh/media/models/hunter.glb"]

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _run() -> void:
	var path := ""
	for candidate: String in MODELS:
		var absolute: String = ProjectSettings.globalize_path("res://").path_join(candidate) if candidate.begins_with("..") else candidate
		if FileAccess.file_exists(absolute):
			path = absolute
			break
	if path.is_empty():
		print("Walk pace checks skipped (no Gilgamesh hunter model)")
		quit(0)
		return
	var scene := STORY.decode_model(FileAccess.get_file_as_bytes(path))
	_check(scene != null, "the hunter model loads")
	var character := "survivors/survivorMaleB"
	CATALOG.set_disk_model(character, scene)
	var controls: Node3D = CONTROLS.new()
	root.add_child(controls)
	controls.start(character, Vector3(0, 6371.0, 0))
	await process_frame
	_check(controls._animation != null and controls._animation.has_animation("walk"), "the hunter has a walking clip")
	_check(controls._walk_pace > 2.0 and controls._walk_pace < 3.6, "the hunter's clip is measured, not taken for a pack run: %.2f m/s" % controls._walk_pace)
	# Four metres a second (the server's walking speed) plays the clip faster than at its own pace.
	var scale: float = clampf(4.0 / controls._walk_pace, 0.2, controls.MAX_WALK_SCALE)
	print("hunter walk pace %.2f m/s, played x%.2f at 4 m/s (%s)" % [controls._walk_pace, scale, path])
	_check(scale > 1.15 and scale < 2.0, "at the server's walking speed the legs keep up: x%.2f" % scale)
	# Move acks always report sitting=false; that must not restart Walk mid-cycle.
	controls.active = true
	controls.moving = true
	controls._motion_until = Time.get_ticks_msec() + 1000
	Input.action_press("walk_forward")
	controls._play_animation(true)
	_check(controls._animation.current_animation == "walk", "walk starts for the sitting-restart check")
	controls._animation.advance(0.35)
	var mid_pos: float = float(controls._animation.current_animation_position)
	controls.set_sitting(false)
	controls.set_sitting(false)
	_check(controls._animation.current_animation == "walk", "repeated sitting=false keeps Walk")
	_check(
		float(controls._animation.current_animation_position) >= mid_pos - 0.001,
		"sitting=false does not rewind the Walk cycle (was %.3f, now %.3f)" % [mid_pos, float(controls._animation.current_animation_position)]
	)
	Input.action_release("walk_forward")
	# A pack character walks with a real walk clip (Kenney's retargeted from the Quaternius
	# Universal Animation Library), so its pace is measured too, not taken for a 4 m/s run.
	CATALOG.set_disk_model("", null)
	controls.swap_character("protagonists/criminalMaleA")
	_check(controls._walk_pace > 0.8 and controls._walk_pace < 2.0, "a Kenney character's walk is measured: %.2f m/s" % controls._walk_pace)
	controls.swap_character("quaternius/adventurer")
	_check(controls._walk_pace > 1.5 and controls._walk_pace < controls.WALK_CLIP_PACE, "a Quaternius character's own Walk is measured: %.2f m/s" % controls._walk_pace)
	if _failures > 0:
		push_error("%d walk pace checks failed" % _failures)
	else:
		print("Walk pace checks passed")
	quit(1 if _failures > 0 else 0)
