extends SceneTree
## The window of the character: statistics of the profile and a summary of the achievements, without a server.

const PANEL := preload("res://scripts/character_panel.gd")
const CONTROLS := preload("res://scripts/character_controls.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _profile() -> Dictionary:
	return {
		"username": "Enkidu", "ordinal": 1,
		"stats": {"level": 4, "experience": 230, "level_experience": 200, "next_level_experience": 300, "score": "430", "gold": "1250",
			"health": 80, "stamina": 55, "food": 100, "water": 62, "mana": 30},
		"life": {"age_days": "3"},
	}

func _entry(id: String, hidden := false) -> Dictionary:
	return {"id": id, "category": "progress", "icon": "star_coin", "title": "" if hidden else "Title " + id, "description": "" if hidden else "Text", "hidden": hidden}

func _run() -> void:
	var panel: CanvasLayer = PANEL.new()
	root.add_child(panel)
	await process_frame
	_check(not panel.visible, "the window starts closed")
	# Before sign-in nothing is made up.
	panel.open()
	_check(panel.name_label.text == "Not signed in" and panel.level_label.text == "", "an unknown player is not invented")
	_check(panel.gold_value.text == "-" and panel.score_value.text == "-" and panel.age_value.text == "-", "no statistics without a profile")
	panel.close()
	panel.set_profile(_profile())
	panel.show_data({
		"achievements": [_entry("a"), _entry("b"), _entry("c"), _entry("d", true)],
		"earned": [{"id": "a", "unlocked_at": 1792678589}, {"id": "b", "unlocked_at": 1792778589}],
	})
	panel.open()
	_check(panel.name_label.text == "Enkidu", "the name is shown (the first life has no number)")
	_check(panel.level_label.text == "Level 4", "the level is shown: %s" % panel.level_label.text)
	_check(panel.experience_label.text == "Experience 230 / 300", "experience with the next level: %s" % panel.experience_label.text)
	_check(is_equal_approx(panel.experience_bar.max_value, 100.0) and is_equal_approx(panel.experience_bar.value, 30.0), "the bar fills the part of the level")
	_check(panel.score_value.text == "430" and panel.gold_value.text == "1250", "score and exact gold are shown as the server wrote them")
	_check(panel.age_value.text == "3 days", "days lived: %s" % panel.age_value.text)
	_check(panel.reserve_values.health.text == "80 / 100" and panel.reserve_values.mana.text == "30 / 100", "the reserves are shown")
	_check(panel.achievements_label.text == "2 / 4" and is_equal_approx(panel.achievements_bar.value, 2.0), "earned of all achievements: %s" % panel.achievements_label.text)
	_check(panel.latest_list.get_child_count() == 2, "the earned ones are listed: %d" % panel.latest_list.get_child_count())
	_check(panel.latest_list.get_child(0).name == "Latest_b", "the newest earned comes first")
	# A server without magic sends no mana: shown as a dash, not as zero.
	var no_mana := _profile()
	no_mana.stats.erase("mana")
	panel.set_profile(no_mana)
	_check(panel.reserve_values.mana.text == "-", "a missing reserve is a dash")
	# Nothing earned yet.
	panel.show_data({"achievements": [_entry("a")], "earned": []})
	_check(panel.achievements_label.text == "0 / 1" and panel.latest_list.get_child_count() == 1, "an empty summary says so")
	# The button opens the full list; the window closes by its own button.
	var requested := [false]
	panel.achievements_requested.connect(func() -> void: requested[0] = true)
	panel.all_button.pressed.emit()
	_check(requested[0], "the button asks for the full list of achievements")
	var closed := [false]
	panel.closed.connect(func() -> void: closed[0] = true)
	panel.close()
	_check(closed[0] and not panel.visible, "the window closes")
	# The key is a rebindable action with its own default.
	_check(CONTROLS.ACTIONS[CONTROLS.CHARACTER] == "character" and CONTROLS.DEFAULT_KEYS[CONTROLS.CHARACTER] == KEY_K and CONTROLS.LABELS[CONTROLS.CHARACTER] == "Character", "the character action is K")
	_check(CONTROLS.ACTIONS.size() == CONTROLS.DEFAULT_KEYS.size() and CONTROLS.ACTIONS.size() == CONTROLS.LABELS.size(), "actions, keys and labels are of one length")
	if _failures > 0:
		quit(1)
		return
	print("character panel: checks passed")
	quit(0)
