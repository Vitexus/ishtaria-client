extends SceneTree
## The active quest in the top left corner. A native run (`godot4 --path . --script res://tests/quest_indicator.gd`)
## also checks the corner at 1600x900 and 640x480 in Czech and writes screenshots to /tmp.

class StubStory extends Node:
	signal strings_changed
	func text(key: String, _args: Array = []) -> String:
		return {"q.title": "Cesta do Uruku", "q2.title": "Starý úkol"}.get(key, key)

class StubControls extends Node:
	const QUEST_LOG := 8
	var key := KEY_J
	func key_for(_index: int) -> int:
		return key

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _run() -> void:
	TranslationServer.set_locale("cs")
	var story := StubStory.new()
	var controls := StubControls.new()
	root.add_child(story)
	root.add_child(controls)
	var indicator := preload("res://scripts/quest_indicator.gd").new()
	indicator.story = story
	indicator.controls = controls
	root.add_child(indicator)
	_check(not indicator.visible, "without quests the corner is empty")
	indicator.set_quests([{"quest": "old", "title_key": "q2.title", "stage": "done", "text_key": "x", "final": true}])
	_check(not indicator.visible, "a finished quest is not shown")
	indicator.set_quests([
		{"quest": "old", "title_key": "q2.title", "stage": "done", "text_key": "x", "final": true},
		{"quest": "q", "title_key": "q.title", "stage": "s1", "text_key": "y", "final": false},
	])
	_check(indicator.visible and indicator.title.text == "Cesta do Uruku", "the unfinished quest is shown by name: %s" % indicator.title.text)
	_check(indicator.heading.text == "Aktivní úkol", "the heading is in Czech: %s" % indicator.heading.text)
	_check(indicator.hint.text == "[J] Deník úkolů", "the reminder names the key and the log: %s" % indicator.hint.text)
	controls.key = KEY_K
	await process_frame
	await process_frame
	_check(indicator.hint.text == "[K] Deník úkolů", "a rebound key is shown: %s" % indicator.hint.text)
	if DisplayServer.get_name() != "headless":
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480)]:
			root.size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(indicator.panel.get_global_rect()), "the indicator fits the window %s" % dimensions)
			_check(indicator.panel.get_global_rect().position.x < 20.0 and indicator.panel.get_global_rect().position.y < 20.0, "the indicator is in the top left corner at %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-quest-indicator-%sx%s.png" % [dimensions.x, dimensions.y])
	indicator.set_quests([])
	_check(not indicator.visible, "with the quests gone the corner is empty again")
	if _failures > 0:
		push_error("%d quest indicator checks failed" % _failures)
	else:
		print("Quest indicator checks passed")
	quit(1 if _failures > 0 else 0)
