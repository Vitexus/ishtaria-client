extends SceneTree

const CLIENT := preload("res://scripts/achievements_client.gd")
const PANEL := preload("res://scripts/achievements_panel.gd")
const TOAST := preload("res://scripts/achievement_toast.gd")
const SOCIAL := preload("res://scripts/social.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _entry(id: String, category := "gathering", hidden := false, icon := "axe") -> Dictionary:
	return {"id": id, "category": category, "icon": icon, "title": "" if hidden else "Woodcutter", "description": "" if hidden else "Swing an axe or a pickaxe at a tree or a rock.", "hidden": hidden}

func _reply() -> Dictionary:
	return {
		"achievements": [_entry("first_harvest"), _entry("first_catch", "gathering", false, "fish_koi"), _entry("level_5", "progress", false, "star_coin"), _entry("level_30", "progress", true, "crown")],
		"earned": [{"id": "first_harvest", "unlocked_at": 1792678589}],
	}

func _run() -> void:
	# The answer of the server is checked before anything is shown.
	_check(CLIENT.valid_reply(_reply()), "a catalog with an earned achievement is accepted")
	_check(CLIENT.valid_reply({"achievements": [], "earned": []}), "an empty catalog is accepted")
	var unknown := _reply()
	unknown.earned = [{"id": "nothing", "unlocked_at": 1}]
	_check(not CLIENT.valid_reply(unknown), "an earned id missing from the catalog is refused")
	var twice := _reply()
	twice.achievements.append(_entry("first_harvest"))
	_check(not CLIENT.valid_reply(twice), "a duplicate id is refused")
	var textless := _reply()
	textless.achievements[0].title = ""
	_check(not CLIENT.valid_reply(textless), "only hidden achievements may lack their texts")
	var bad_category := _reply()
	bad_category.achievements[0].category = "cheating"
	_check(not CLIENT.valid_reply(bad_category), "an unknown category is refused")
	var bad_time := _reply()
	bad_time.earned[0].unlocked_at = -5
	_check(not CLIENT.valid_reply(bad_time), "a negative time is refused")
	for broken: Variant in [null, "x", {"achievements": "x", "earned": []}, {"achievements": [{"id": "Bad Id"}], "earned": []}]:
		_check(not CLIENT.valid_reply(broken), "malformed reply %s" % [broken])
	_check(CLIENT.valid_id("level_10") and not CLIENT.valid_id("Level") and not CLIENT.valid_id("") and not CLIENT.valid_id(5), "ids follow the server's rule")

	# The event of a new achievement carries only its id.
	_check(SOCIAL.valid_event({"id": 9, "kind": "achievement", "subject": "first_harvest"}), "an achievement event is accepted")
	_check(not SOCIAL.valid_event({"id": 9, "kind": "achievement", "subject": "<b>x</b>"}), "an event with a strange id is dropped")

	# Announcing waits for the list; without a session nothing is asked or announced.
	var client := CLIENT.new()
	root.add_child(client)
	var announced: Array = []
	client.unlocked.connect(func(achievement: Dictionary) -> void: announced.append(achievement.id))
	client.announce("first_harvest")
	_check(announced.is_empty() and not client.is_running(), "nothing is announced without a session")
	client.data = _reply()
	var earned := client.entry("first_harvest")
	_check(earned.unlocked_at == 1792678589 and earned.title == "Woodcutter", "an earned entry has its time")
	_check(client.entry("first_catch").unlocked_at == 0 and client.entry("missing").is_empty(), "other entries are not earned")

	# The panel: a card each, secrets masked, the count and the category filter.
	TranslationServer.set_locale("en")
	var panel := PANEL.new()
	root.add_child(panel)
	await process_frame
	panel.show_data(_reply())
	panel.open()
	await process_frame
	_check(panel.visible and panel.grid.get_child_count() == 4, "every achievement has a card")
	_check(panel.progress_label.text == "1 / 4" and panel.progress_bar.value == 1, "the count of earned ones is shown")
	var first := panel.grid.get_child(0)
	_check(first.name == "Achievement_first_harvest" and first.find_child("Earned", true, false) != null, "earned ones come first with their date")
	var secret := panel.grid.find_child("Achievement_level_30", true, false)
	_check(secret != null and secret.find_child("Title", true, false).text == "???", "a hidden achievement keeps its secret")
	panel._tabs.current_tab = 1
	await process_frame
	_check(panel.grid.get_child_count() == 2, "the progress tab shows the level achievements")
	panel._tabs.current_tab = 0
	panel.show_data({"achievements": [], "earned": []})
	_check(panel.grid.get_child_count() == 0 and panel.empty_label.visible, "without data the panel says so")
	panel.close()
	_check(not panel.visible, "the panel closes")

	# The toast queues several achievements and shows one at a time.
	var toast := TOAST.new()
	root.add_child(toast)
	await process_frame
	toast.show_achievement(client.entry("first_harvest"))
	toast.show_achievement(client.entry("first_catch"))
	_check(toast.is_showing() and toast.panel.visible and toast._queue.size() == 1, "the second banner waits for the first")

	if DisplayServer.get_name() != "headless":
		await _screenshots(panel, toast)

	if _failures > 0:
		push_error("%d achievement checks failed" % _failures)
	else:
		print("Achievement checks passed")
	quit(1 if _failures > 0 else 0)

## A native run saves the panel and the banner in Czech as /tmp/ishtaria-achievements-cs-<size>.png.
func _screenshots(panel: CanvasLayer, toast: CanvasLayer) -> void:
	ThemeDB.get_default_theme().merge_with(UiTheme.get_theme())
	TranslationServer.set_locale("cs")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/achievements.json"))
	panel.show_data(catalog)
	toast._queue.clear()
	while toast.is_showing():
		await process_frame
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480)]:
		root.size = dimensions
		panel.open()
		toast.show_achievement(catalog.achievements[0])
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bounds.encloses(panel._card.get_global_rect()), "the panel fits %s" % dimensions)
		root.get_texture().get_image().save_png("/tmp/ishtaria-achievements-cs-%sx%s.png" % [dimensions.x, dimensions.y])
		panel.close()
	TranslationServer.set_locale("en")
