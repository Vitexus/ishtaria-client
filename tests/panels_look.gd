extends SceneTree
## Opens every game window with sample data in the game's theme and checks that it fits the
## screen at 1600x900 and 640x480. A native run (not headless) also saves each one in Czech as
## /tmp/ishtaria-panel-<name>-cs-<size>.png, to be looked at: these checks prove no looks.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const STORY := preload("res://scripts/story_client.gd")
const ID1 := "11111111-1111-4111-8111-111111111111"
const ID2 := "22222222-2222-4222-8222-222222222222"

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _stack(id: String, name: String, quantity: String) -> Dictionary:
	return {"item_id": id, "name": name, "quantity": quantity}

func _profile() -> Dictionary:
	return {"life": {"alive": true}, "stats": {"gold": "240"}, "inventory": {"used": 4, "capacity": 100, "items": [
		_stack("oak_log", "Oak log", "3"), _stack("axe", "Axe", "1"), _stack("hide", "Hide", "6"), _stack("stone_block", "Stone block", "7")]}}

func _story() -> Node:
	var story: Node = STORY.new()
	story._strings = {"cs": {"endland:kragg.greet": "Vítej v hostinci, poutníku. Co tě sem přivádí za tak pozdní hodiny?", "endland:npc.kragg": "Kragg", "endland:kragg.ask_gossip": "Co je nového ve městě?", "endland:kragg.leave": "Na shledanou.", "q.title": "Hrobníkova práce", "q.have_key": "Máš klíč od hřbitova. Odnes ho Kraggovi do hostince.", "endland:elder.greet": "Posaď se, dítě, mé nohy jsou starší než hradby Uruku. \"Když bohové byli lidmi,\" tak začíná ten starý příběh, a já ho znám tak, jak mi ho vyprávěl můj otec. Ptej se, dokud mi slouží paměť, protože po mně už nebude koho se zeptat.", "endland:elder.a": "Jak byli stvořeni lidé?", "endland:elder.b": "Proč umíráme a proč jsou některé ženy bezdětné?", "endland:elder.c": "Vyprávěj mi o potopě.", "endland:elder.d": "Kde bych našel jeden z těch příběhů psaný na hlíně?", "endland:elder.e": "Pokoj tobě, starý otče."}}
	story._strings["en"] = story._strings.cs
	return story

func _run() -> void:
	ThemeDB.get_default_theme().merge_with(UiTheme.get_theme())
	TranslationServer.set_locale("cs")
	var native := DisplayServer.get_name() != "headless"
	var story := _story()
	root.add_child(story)

	var crafting: CanvasLayer = preload("res://scripts/crafting_panel.gd").new()
	root.add_child(crafting)
	crafting.set_recipes([
		{"id": "chop_oak_log", "inputs": [_stack("oak_log", "Oak log", "1")], "outputs": [_stack("oak_wood", "Oak wood", "20")], "tool": "axe"},
		{"id": "oak_plank", "inputs": [_stack("oak_wood", "Oak wood", "4")], "outputs": [_stack("oak_plank", "Oak plank", "1")]},
	])
	crafting.set_profile(_profile())

	var trade: CanvasLayer = preload("res://scripts/trade_panel.gd").new()
	root.add_child(trade)
	trade.set_profile(_profile())

	var friends: CanvasLayer = preload("res://scripts/friends_panel.gd").new()
	root.add_child(friends)

	var quests: CanvasLayer = preload("res://scripts/quest_panel.gd").new()
	quests.story = story
	root.add_child(quests)

	var portals: CanvasLayer = preload("res://scripts/portal_panel.gd").new()
	root.add_child(portals)
	portals.set_profile(_profile())

	var character: CanvasLayer = preload("res://scripts/character_panel.gd").new()
	root.add_child(character)
	character.set_profile({"username": "Enkidu", "ordinal": 1, "life": {"age_days": "12"}, "stats": {"level": 4, "experience": 230, "level_experience": 200,
		"next_level_experience": 300, "score": "520", "gold": "1250", "health": 80, "stamina": 55, "food": 100, "water": 62, "mana": 30}})
	var catalog: Array = []
	for index in 14:
		catalog.append({"id": "step_%d" % index, "category": "progress", "icon": "star_coin", "title": "Úspěch %d" % (index + 1), "description": "Popis", "hidden": false})
	character.show_data({"achievements": catalog, "earned": [{"id": "step_0", "unlocked_at": 1792678589}, {"id": "step_1", "unlocked_at": 1792778589}, {"id": "step_2", "unlocked_at": 1792878589}]})

	var dialogue: CanvasLayer = preload("res://scripts/dialogue_panel.gd").new()
	dialogue.story = story
	root.add_child(dialogue)
	await process_frame

	var shows := {
		"crafting": func() -> Control:
			crafting.open()
			return crafting.panel,
		"crafting_pending": func() -> Control:
			# Pressed and waiting for the server: the button spins.
			crafting.open()
			crafting.find_child("Craft", true, false).pressed.emit()
			return crafting.panel,
		"shop": func() -> Control:
			trade.show_goods({"npc_id": "x", "sells": [{"item_id": "oak_plank", "name": "Oak plank", "price": "4"}, {"item_id": "axe", "name": "Axe", "price": "30"}], "buys": [{"item_id": "hide", "name": "Hide", "price": "5"}], "daily_limit": "400", "sold_today": "20"}, "Kupec Ur-Nanše")
			return trade.panel,
		"exchange": func() -> Control:
			trade.show_exchange({"with": "boris", "mine": [_stack("hide", "Hide", "5")], "theirs": [_stack("oak_plank", "Oak plank", "10")], "i_accepted": false, "they_accepted": true})
			return trade.panel,
		"friends": func() -> Control:
			friends.set_friends([{"name": "boris", "online": true, "world": "w.example", "level": 3, "flag": "CZ"}, {"name": "cyril", "online": false, "world": "w.example", "level": 1}])
			friends.set_requests([{"id": 7, "name": "dana"}], [{"id": 8, "name": "eva"}])
			friends.open()
			return friends.panel,
		"quests": func() -> Control:
			quests.set_quests([{"quest": "endland:graveyard_job", "title_key": "q.title", "stage": "have_key", "text_key": "q.have_key", "final": false}])
			quests.open()
			return quests.panel,
		"portals": func() -> Control:
			portals.set_portals([{"id": ID1, "state": "built", "portal_name": "brana-jih", "peer_host": null, "peer_portal_name": null}, {"id": ID2, "state": "open", "portal_name": "brana-sever", "peer_host": "svet-a.example.org", "peer_portal_name": "brana-vychod"}])
			portals.open()
			return portals.panel,
		"character": func() -> Control:
			character.open()
			return character.panel,
		"dialogue": func() -> Control:
			dialogue.show_reply({"npc_id": "endland:kragg", "name_key": "endland:npc.kragg", "seq": 3, "open": true, "player": {},
				"node": {"node": "greet", "text_key": "endland:kragg.greet", "choices": [{"index": 0, "text_key": "endland:kragg.ask_gossip"}, {"index": 2, "text_key": "endland:kragg.leave"}]}})
			return dialogue.panel,
		# A long line with five answers: the panel must still show what was said. It used to be a
		# fixed 300 px with the speech squeezed to 48, so the line was cut off behind a scrollbar.
		"dialogue_long": func() -> Control:
			dialogue.show_reply({"npc_id": "endland:elder", "name_key": "endland:npc.kragg", "seq": 4, "open": true, "player": {},
				"node": {"node": "greet", "text_key": "endland:elder.greet", "choices": [
					{"index": 0, "text_key": "endland:elder.a"}, {"index": 1, "text_key": "endland:elder.b"},
					{"index": 2, "text_key": "endland:elder.c"}, {"index": 3, "text_key": "endland:elder.d"},
					{"index": 4, "text_key": "endland:elder.e"}]}})
			return dialogue.panel,
	}
	var layers := {"crafting": crafting, "crafting_pending": crafting, "shop": trade, "exchange": trade, "friends": friends, "quests": quests, "portals": portals, "character": character, "dialogue": dialogue, "dialogue_long": dialogue}
	for name: String in shows:
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480)]:
			root.size = dimensions
			await process_frame
			var shown: Control = shows[name].call()
			await create_timer(0.35).timeout
			if native:
				# Headless runs have no renderer and never post a frame.
				await RenderingServer.frame_post_draw
			_check(layers[name].visible, "%s opens" % name)
			_check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1.0).encloses(shown.get_global_rect()), "%s fits %s: %s" % [name, dimensions, shown.get_global_rect()])
			if native:
				root.get_texture().get_image().save_png("/tmp/ishtaria-panel-%s-cs-%sx%s.png" % [name, dimensions.x, dimensions.y])
		layers[name].hide()

	TranslationServer.set_locale("en")
	if _failures > 0:
		push_error("%d panel look checks failed" % _failures)
	else:
		print("Panel look checks passed")
	quit(1 if _failures > 0 else 0)
