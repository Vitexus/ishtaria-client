extends SceneTree

const STORY := preload("res://scripts/story_client.gd")
const DISK := "res://../ishtaria-datadisk-endland/"

var _failures := 0
var _chosen: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _reply(open := true) -> Dictionary:
	var reply := {"npc_id": "endland:kragg", "name_key": "endland:npc.kragg", "seq": 3, "open": open,
		"portrait": "/story/media/endland/media/portraits/kragg.jpg",
		"music": {"url": "/story/media/endland/media/music/tavern_old_tower_inn.ogg", "title_key": "endland:music.tavern", "loop": true},
		"player": {}}
	if open:
		reply["node"] = {"node": "greet", "text_key": "endland:kragg.greet", "choices": [{"index": 0, "text_key": "endland:kragg.ask_gossip"}, {"index": 2, "text_key": "endland:kragg.leave"}]}
	else:
		reply["node"] = null
	return reply

func _run() -> void:
	# What the server sends is checked before it is shown.
	_check(STORY.valid_reply(_reply()), "a good reply is accepted")
	_check(STORY.valid_reply(_reply(false)), "a closed conversation is accepted")
	var bad := _reply()
	bad.node.choices = [{"index": "x", "text_key": "a"}]
	_check(not STORY.valid_reply(bad), "a choice needs a numeric index")
	bad = _reply()
	bad.portrait = "/story/media/endland/../datadisk.yaml"
	_check(not STORY.valid_reply(bad), "a traversal portrait is refused")
	# Background music of places: validated, heard within the radius and fading towards its edge.
	var area_env := preload("res://scripts/surface_environment.gd").new()
	root.add_child(area_env)
	var area := {"id": "endland:old_graveyard", "position": [6371000.0, 0.0, 0.0], "radius_m": 70.0, "music": {"url": "/story/media/endland/media/music/graveyard_midnightcem.ogg", "title_key": "endland:music.graveyard", "loop": true}}
	_check(area_env.apply_areas([area]), "an area with music is accepted")
	_check(not area_env.apply_areas([{"id": "x", "position": [0, 0, 0], "radius_m": 70.0, "music": {"url": "/etc/passwd", "title_key": "k", "loop": true}}]) and area_env.areas.is_empty(), "an area with a bad track is refused")
	area_env.apply_areas([area])
	_check(area_env.area_at(Vector3(6371000.0, 10.0, 0.0)).level == 1.0, "full level near the place")
	_check(area_env.area_at(Vector3(6371000.0, 60.0, 0.0)).level < 0.5, "the music fades near the edge")
	_check(area_env.area_at(Vector3(6371000.0, 200.0, 0.0)).is_empty(), "silence far from the place")
	area_env.queue_free()
	_check(STORY.substitute_player("Hi, {player}!", "Vitexys") == "Hi, Vitexys!", "the player's name replaces {player}")
	_check(STORY.substitute_player("Hi, {player}!", "50%") == "Hi, 50%!" and STORY.substitute_player("none", "x") == "none", "a name with % is kept and texts without it are untouched")
	var spoken := _reply()
	spoken.node.voice = "/story/media/endland/media/voice/cs/kragg.greet.ogg"
	_check(STORY.valid_reply(spoken), "a spoken line is accepted")
	spoken.node.voice = "/story/media/endland/../x.ogg"
	_check(not STORY.valid_reply(spoken), "a traversal voice is refused")
	spoken.node.voice = 5
	_check(not STORY.valid_reply(spoken), "a voice must be a url")
	for url in ["/other/x.png", "/story/media/a/b.exe", "/story/media/a//b.png", "/story/media/a/b.png?x=1", "/story/media/a/%2e%2e/b.png", 5]:
		_check(not STORY.valid_media_url(url), "refused media url %s" % str(url))
	_check(STORY.valid_media_url("/story/media/endland/media/portraits/kragg.jpg"), "a portrait url is valid")
	_check(STORY.error_key(403, "character is out of reach") == "Too far away to talk", "fixed error keys")
	_check(STORY.error_key(500, "SELECT secret FROM users") == "Conversation unavailable", "server text never reaches the player")

	# Translations: every language is delivered, the player's own is used, English is the fallback.
	var story: Node = STORY.new()
	root.add_child(story)
	var strings := {"languages": {"en": {"k.hello": "Hello %s", "k.only_en": "English only"}, "cs": {"k.hello": "Ahoj %s"}}}
	_check(STORY.valid_strings(strings), "strings are valid")
	story._strings = strings.languages
	TranslationServer.set_locale("cs")
	_check(story.text("k.hello", ["světe"]) == "Ahoj světe", "Czech text with an argument")
	_check(story.text("k.only_en") == "English only", "English is the fallback")
	_check(story.text("k.unknown") == "k.unknown", "an unknown key is shown as is")
	TranslationServer.set_locale("en")
	_check(story.text("k.hello", ["world"]) == "Hello world", "English text")
	_check(not STORY.valid_strings({"languages": {"english": {}}}), "language codes have two letters")

	# NPCs near the player are rendered, nameable and found by distance.
	var environment := preload("res://scripts/surface_environment.gd").new()
	root.add_child(environment)
	environment.npc_text = func(key: String) -> String: return story.text(key)
	var good := {"id": "endland:kragg", "name_key": "k.only_en", "character": "survivors/survivorMaleB", "position": [6371000.0, 10.0, 0.0], "yaw": 1.0, "scale_m": 1.8}
	var broken := {"id": "endland:x", "name_key": "k.hello", "character": "nope/none", "position": [6371000.0, 0.0, 0.0], "yaw": 1.0, "scale_m": 1.8}
	var far := {"id": "endland:far", "name_key": "k.hello", "character": "retro/humanMaleA", "position": [6371000.0, 500.0, 0.0], "yaw": 0.0, "scale_m": 1.8}
	environment.apply_npcs([good, broken, far, "junk"])
	_check(environment.npcs.get_child_count() == 2, "valid characters are placed, malformed ones skipped")
	_check(environment.nearest_npc(Vector3(6371000.0, 8.0, 0.0), 4.5).get("id", "") == "endland:kragg", "the character in reach is found")
	_check(environment.nearest_npc(Vector3(6371000.0, 100.0, 0.0), 4.5).is_empty(), "nobody is in reach")
	var label := environment.npcs.get_child(0).get_node("Name") as Label3D
	_check(label.text == "English only", "the name is shown in the player's language")
	environment.set_render_origin([6371000.0, 0.0, 0.0])
	_check(environment.npcs.get_child(0).position.distance_to(Vector3(0, 0.01, 0)) < 0.0001, "characters follow the render origin")
	environment._clear_objects()
	_check(environment.npcs.get_child_count() == 0, "clearing the region removes the characters")

	# A character of a datadisk that walks follows the route the server sent, plays its walking clip while it moves and
	# its idle clip while it stands, and is found where it is.
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	var walker := {"id": "x:walker", "name_key": "k.hello", "character": "retro/humanMaleA", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 1.8,
		"wander": [[now_ms - 10000.0, 6371000.0, 0.0, 0.0], [now_ms + 10000.0, 6371000.0, 20.0, 0.0], [now_ms + 60000.0, 6371000.0, 20.0, 0.0]]}
	environment.apply_npcs([walker])
	_check(environment._npc_walkers.size() == 1, "a character with a route walks")
	environment._walk_npcs(0.1)
	var walked: Array = environment._npc_entries[0].position
	_check(walked[1] > 8.0 and walked[1] < 12.0, "it is half way along its first walk: %s" % str(walked))
	_check(environment._npc_walkers[0].walking and environment._npc_walkers[0].player.current_animation == "walk", "it walks")
	_check(environment.nearest_npc(Vector3(6371000.0, 10.0, 0.0), 4.5).get("id", "") == "x:walker", "it is found where it is, not where it was put")
	var stood := walker.duplicate(true)
	stood.wander = [[now_ms - 60000.0, 6371000.0, 20.0, 0.0], [now_ms + 60000.0, 6371000.0, 20.0, 0.0]]
	environment.apply_npcs([stood])
	environment._walk_npcs(0.1)
	_check(not environment._npc_walkers[0].walking, "a character that stands does not walk")
	# A conversation holds a walking character still and turns it to the player; afterwards the new route sets it going again.
	var talker := walker.duplicate(true)
	talker.id = "x:talker"
	environment.apply_npcs([talker])
	environment._walk_npcs(0.1)
	var stopped: Array = environment._npc_entries[0].position.duplicate()
	environment.target = Vector3(1.0, 0.0, 1.0e-5).normalized()
	environment.hold_npc("x:talker", true)
	for frame in 30:
		environment._walk_npcs(0.1)
		environment._face_held(0.1)
	_check(environment._npc_entries[0].position == stopped, "a character in conversation stands where it was")
	# the player stands towards +Z of the character (the target is a direction on the planet): it looks that way
	var look: Vector3 = (environment.npcs.get_child(0) as Node3D).global_transform.basis.z.normalized()
	_check(look.dot(Vector3(0, 0, 1)) > 0.9, "it turns to the player: %s" % str(look))
	environment.hold_npc("x:talker", false)
	_check(environment._held_npcs.has("x:talker"), "a released character waits for its new route")
	environment._held_npcs["x:talker"].released_at = Time.get_ticks_msec() - environment.HOLD_RELEASE_MS - 10
	environment._face_held(0.1)
	_check(not environment._held_npcs.has("x:talker"), "and goes on by the old route when no new one comes")
	var back := walker.duplicate(true)
	back.wander = [[now_ms, 6371000.0, 0.0, 0.0], [now_ms - 1000.0, 6371000.0, 20.0, 0.0]]
	environment.apply_npcs([back])
	_check(environment._npc_walkers.is_empty(), "a route in which time runs back is refused")
	environment._clear_objects()
	_check(environment._npc_walkers.is_empty(), "clearing the region stops them")

	# Props of generated places: known kit models are built, anything odd is skipped.
	var prop := {"id": "world:town_00#1", "model": "town.wall", "position": [6371000.0, 5.0, 0.0], "yaw": 0.5, "scale_m": 2.5}
	var bad_props := [
		{"id": "a", "model": "town.nothing-like-this", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 2.5},
		{"id": "b", "model": "../../project", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 2.5},
		{"id": "c", "model": "town.wall", "position": [6371000.0, 0.0], "yaw": 0.0, "scale_m": 2.5},
		{"id": "d", "model": "town.wall", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 900.0},
		{"id": "e", "model": "pirate.ship-small", "position": [1.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 1.0},
		"junk"]
	_check(environment.apply_props([prop, {"id": "w2", "model": "pirate.ship-small", "position": [6371000.0, 9.0, 3.0], "yaw": 0.0, "scale_m": 1.0}] + bad_props), "a prop list is accepted")
	_check(environment.props.get_child_count() == 2, "only the two good props are built: %d" % environment.props.get_child_count())
	_check(environment.prop_path("graveyard.crypt-large") != "" and environment.prop_path("castle.wall-doorway") != "" and environment.prop_path("quaternius.willow") != "", "bundled models resolve")
	for model in ["town.", ".wall", "town.a.b", "kit.wall", "town./x", 5, null]:
		_check(environment.prop_path(model) == "", "refused model %s" % str(model))
	environment._clear_objects()
	_check(environment.props.get_child_count() == 0, "clearing the region removes the props")

	# A building of a datadisk is drawn when its model arrives, and fetched once.
	var requested: Array = []
	environment.fetch_media = func(url: String) -> void: requested.append(url)
	var ziggurat := {"id": "g:ziggurat", "model": "disk:gilgamesh:media/models/architecture/ziggurat_anu.glb", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 1.0, "visible_m": 1500.0}
	var bad_structures: Array = []
	for model in ["disk:gilgamesh:../../x.glb", "disk:gilgamesh:media/other/a.glb", "disk::media/models/a.glb", "disk:a:b:media/models/a.glb", "disk:gilgamesh:media/models/a.png", "disk:gilgamesh:media//models/a.glb"]:
		bad_structures.append({"id": "bad", "model": model, "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 1.0})
	_check(environment.apply_props([ziggurat] + bad_structures), "a list with a datadisk building is accepted")
	_check(environment.props.get_child_count() == 1, "only the valid building is placed: %d" % environment.props.get_child_count())
	var url := "/story/media/gilgamesh/media/models/architecture/ziggurat_anu.glb"
	_check(requested == [url], "its model is requested once: %s" % str(requested))
	_check(environment.props.get_child(0).get_child_count() == 0, "nothing is drawn before the model arrives")
	environment.apply_props([ziggurat])
	_check(requested.size() == 1, "a second region does not fetch the model again")
	var scene := PackedScene.new()
	var sample := Node3D.new()
	scene.pack(sample)
	sample.free()
	environment.media_ready(url, scene)
	environment.fill_structures(true)   # buildings are filled a few milliseconds a frame in the game
	_check(environment.props.get_child(0).get_child_count() == 1, "the model fills the waiting placement")
	environment.apply_props([ziggurat])
	environment.fill_structures(true)
	_check(environment.props.get_child(0).get_child_count() == 1 and requested.size() == 1, "a known model is drawn at once")
	_check(environment.structure_url("disk:gilgamesh:media/models/a.glb") == "/story/media/gilgamesh/media/models/a.glb" and environment.structure_url("town.wall") == "", "structure_url separates datadisk models from kit models")
	environment.fetch_media = Callable()
	environment._clear_objects()

	# Lamp posts burn at night only.
	var post := {"id": "g:lamp", "model": "graveyard.lightpost-single", "position": [6371000.0, 5.0, 0.0], "yaw": 0.0, "scale_m": 2.0}
	_check(environment.apply_props([post, prop]), "lamp posts are accepted")
	_check(environment.lamps.get_child_count() == 1, "a lamp post gets one light")
	var lamp := environment.lamps.get_child(0) as OmniLight3D
	environment.set_night(0.0)
	_check(not lamp.visible and lamp.light_energy == 0.0, "the lamp is out by day")
	environment.set_night(1.0)
	_check(lamp.visible and lamp.light_energy > 1.0e-6 and lamp.light_energy < 1.0e-5, "the lamp burns at night")
	_check(lamp.position.distance_to(environment.props.get_child(0).position) < 0.005, "the light hangs at the lamp post")
	environment.set_render_origin([6371000.0, 100.0, 0.0])
	_check(lamp.position.distance_to(environment.props.get_child(0).position) < 0.005, "the light follows the render origin")
	environment.apply_props([])
	_check(environment.lamps.get_child_count() == 0, "clearing the props removes the lamps")

	# The panel shows what was said, offers the choices and reports the choice with the sequence.
	var panel: CanvasLayer = preload("res://scripts/dialogue_panel.gd").new()
	panel.story = story
	root.add_child(panel)
	panel.choice_made.connect(func(npc: String, seq: int, choice: int) -> void: _chosen.append([npc, seq, choice]))
	story._strings = {"en": {"endland:kragg.greet": "Welcome!", "endland:npc.kragg": "Kragg", "endland:kragg.ask_gossip": "News?", "endland:kragg.leave": "Bye"}}
	panel.show_reply(_reply())
	await process_frame
	_check(panel.visible and panel.speech.text == "Welcome!" and panel.name_label.text == "Kragg", "the panel shows the speaker and the speech")
	_check(panel.choices_box.get_child_count() == 2, "both choices are offered")
	(panel.choices_box.get_child(1) as Button).pressed.emit()
	_check(_chosen == [["endland:kragg", 3, 2]], "the choice carries the server's own index and sequence: %s" % str(_chosen))
	panel.show_reply(_reply(false))
	_check(not panel.visible, "a closed conversation hides the panel")

	# Portraits and music of the Endland datadisk decode (skipped when the disk is not checked out).
	var portrait_path := ProjectSettings.globalize_path("res://").path_join("../ishtaria-datadisk-endland/media/portraits/kragg.jpg").simplify_path()
	if FileAccess.file_exists(portrait_path):
		var texture := STORY.decode_media("/story/media/endland/media/portraits/kragg.jpg", FileAccess.get_file_as_bytes(portrait_path))
		_check(texture is Texture2D and texture.get_width() > 0, "the portrait decodes")
		panel.show_reply(_reply())
		panel.media_ready("/story/media/endland/media/portraits/kragg.jpg", texture)
		_check(panel.portrait.texture == texture, "the portrait is shown beside the speech")
		var track_path := portrait_path.get_base_dir().get_base_dir().path_join("music/tavern_old_tower_inn.ogg")
		var track := STORY.decode_media("/story/media/endland/media/music/tavern_old_tower_inn.ogg", FileAccess.get_file_as_bytes(track_path))
		_check(track is AudioStreamOggVorbis and track.get_length() > 1.0, "the track decodes")
		panel.media_ready("/story/media/endland/media/music/tavern_old_tower_inn.ogg", track)
		_check(panel._music.stream == track and (track as AudioStreamOggVorbis).loop, "the track plays and loops during the conversation")
		_check(panel._music.gain == 0.0 and panel._music.target == 1.0, "the track fades in from silence")
		var playing_channel: Node = panel._music
		panel.close()
		_check(playing_channel.stream == track and playing_channel.target == 0.0 and playing_channel.free_when_done, "closing the conversation lets the track fade out instead of cutting it")
		_check(not panel.has_own_music(), "the area music may come back while the track fades")
		panel.set_music_enabled(false)
		_check(panel._music.stream == null, "music can be switched off")
	_check(STORY.decode_media("/story/media/a/b.jpg", PackedByteArray([1, 2, 3])) == null, "garbage is not an image")

	# The quest log lists quests with their stage and marks finished ones.
	var quests := [{"quest": "endland:graveyard_job", "title_key": "k.only_en", "stage": "have_key", "text_key": "k.hello", "final": false}, {"quest": "x:y", "title_key": "k.only_en", "stage": "done", "text_key": "k.only_en", "final": true}]
	_check(STORY.valid_quests(quests), "a quest list is valid")
	_check(not STORY.valid_quests([{"quest": 1}]) and not STORY.valid_quests("x"), "malformed quest lists are refused")
	var log: CanvasLayer = preload("res://scripts/quest_panel.gd").new()
	log.story = story
	root.add_child(log)
	log.set_quests([])
	_check(log.list.get_child_count() == 1, "an empty log says there are no quests")
	log.set_quests(quests)
	log.open()
	_check(log.visible and log.list.get_child_count() == 4, "two quests give a heading and a step each")
	_check((log.list.get_child(2) as Label).text.ends_with("(" + log.tr("Finished") + ")"), "a finished quest is marked")

	# The compass lists the places the server names and puts them to the side they lie on.
	var compass_script := preload("res://scripts/quest_compass.gd")
	var marker := {"id": "endland:udrury", "quest": "endland:graveyard_job", "name_key": "k.hello", "kind": "city", "position": [0.0, 0.0, -100.0], "next": true}
	_check(compass_script.valid_markers([marker]) and compass_script.valid_markers([]), "a marker list is valid")
	_check(not compass_script.valid_markers([{"id": "x"}]) and not compass_script.valid_markers([marker.merged({"position": [1, 2]}, true)]) and not compass_script.valid_markers("x"), "malformed marker lists are refused")
	var up := Vector3.UP
	var ahead := Vector3(0, 0, -1)
	var right_of := compass_script.bearing(Vector3.ZERO, Vector3(50, 0, 0), up, ahead)
	_check(absf(compass_script.bearing(Vector3.ZERO, Vector3(0, 0, -50), up, ahead)) < 0.001, "a place ahead has no bearing")
	_check(absf(absf(right_of) - PI / 2.0) < 0.001, "a place at the side is a quarter turn away")
	_check(right_of * compass_script.bearing(Vector3.ZERO, Vector3(-50, 0, 0), up, ahead) < 0.0, "the two sides have opposite signs")
	var compass: CanvasLayer = compass_script.new()
	compass.story = story
	root.add_child(compass)
	compass.set_markers([])
	_check(not compass._strip.visible, "without markers the strip is hidden")
	compass.set_markers([marker])
	_check(compass._strip.visible and compass._items.size() == 1, "a marker shows the strip")
	# Two places almost in the same direction: only the one nearer the heading keeps its text, on top;
	# a place far to the side keeps its own.
	var beside := marker.merged({"id": "endland:beside", "position": [6.0, 0.0, -100.0], "next": false}, true)
	var side := marker.merged({"id": "endland:side", "position": [100.0, 0.0, -10.0], "next": false}, true)
	compass.set_markers([beside, marker, side])
	await process_frame
	# The headless window is small; lay the strip out at its usual width.
	compass._area.size = Vector2(540.0, 46.0)
	compass.update_view(Vector3.ZERO, up, ahead)
	var texts: Array = compass._items.map(func(item: Control) -> bool: return item.get_node("Text").visible)
	_check(texts == [false, true, true], "overlapping compass labels keep the one nearest the heading: %s" % [texts])
	_check(compass._area.get_child(compass._area.get_child_count() - 1) == compass._items[1], "the label nearest the heading is drawn on top")
	# A place known from an earlier quest gives way to a goal even when it lies nearer the heading.
	var known_place := marker.merged({"id": "endland:known", "position": [0.0, 0.0, -100.0], "known": true}, true)
	var goal := marker.merged({"id": "endland:goal", "position": [6.0, 0.0, -100.0], "next": false}, true)
	_check(compass_script.valid_markers([known_place, goal]) and not compass_script.valid_markers([marker.merged({"known": "yes"}, true)]), "known is an optional flag")
	compass.set_markers([known_place, goal])
	compass.update_view(Vector3.ZERO, up, ahead)
	texts = compass._items.map(func(item: Control) -> bool: return item.get_node("Text").visible)
	_check(texts == [false, true], "a goal keeps its label before a known place: %s" % [texts])

	# "Tell me about yourself": a knowledge card is checked before it is shown, the article follows the language.
	var card := {"title_key": "world:knowledge.shepherd.title", "text_key": "world:knowledge.shepherd.text", "credit_key": "world:knowledge.shepherd.credit",
		"image": "/story/media/world/media/knowledge/shepherd.jpg", "wikipedia": {"en": "Shepherd", "cs": "Pastýř"}}
	_check(STORY.valid_about(card), "a good knowledge card is accepted")
	for flaw: Dictionary in [{"image": "/etc/passwd"}, {"text_key": 5}, {"wikipedia": {"cs": "Pastýř"}}, {"wikipedia": {"en": "Two words"}}, {"wikipedia": {"en": "a?b=c"}}, {"wikipedia": {"english": "Shepherd", "en": "Shepherd"}}, {"wikipedia": {"en": "Shepherd", "cs": "../x"}}]:
		var changed := card.duplicate(true)
		changed.merge(flaw, true)
		_check(not STORY.valid_about(changed), "a broken card is refused: %s" % str(flaw))
	_check(STORY.wikipedia_url(card, "cs") == "https://cs.wikipedia.org/wiki/Past%C3%BD%C5%99", "the Czech article for the Czech client: %s" % STORY.wikipedia_url(card, "cs"))
	_check(STORY.wikipedia_url(card, "de") == "https://en.wikipedia.org/wiki/Shepherd", "English when the card has no article in the language")
	var talk := _reply()
	talk["about"] = true
	_check(STORY.valid_reply(talk), "a reply that offers a card is accepted")
	talk["about"] = "yes"
	_check(not STORY.valid_reply(talk), "the offer is a boolean")
	var dialogue := preload("res://scripts/dialogue_panel.gd").new()
	root.add_child(dialogue)
	var asked: Array = []
	dialogue.about_requested.connect(func(npc_id: String) -> void: asked.append(npc_id))
	var plain := _reply()
	dialogue.show_reply(plain)
	_check(not dialogue.choices_box.has_node("About"), "a character without a card offers none")
	var offered := _reply()
	offered["about"] = true
	dialogue.show_reply(offered)
	_check(dialogue.choices_box.has_node("About"), "a character with a card offers to tell about itself")
	dialogue.choices_box.get_node("About").pressed.emit()
	dialogue.choices_box.get_node("About").pressed.emit()
	_check(asked == ["endland:kragg"], "the card is asked for once while the answer is on its way")
	dialogue.show_about("endland:somebody", card)
	_check(not dialogue._card_mode, "a card of another character is not shown")
	dialogue.show_about("endland:kragg", card)
	_check(dialogue._card_mode and dialogue.choices_box.find_child("Back", true, false) != null and dialogue.choices_box.find_child("Wikipedia", true, false) != null, "the card has its way back and its link")
	_check(dialogue.choices_box.find_child("Credit", true, false) != null, "the card names the author of the picture")
	dialogue.choices_box.find_child("Back", true, false).pressed.emit()
	_check(not dialogue._card_mode and dialogue.choices_box.has_node("About"), "back from the card the conversation is as it was")
	dialogue.show_about("endland:kragg", card)
	dialogue.close()
	_check(not dialogue._card_mode and not dialogue.visible, "closing the conversation leaves the card")
	dialogue.queue_free()

	if _failures > 0:
		push_error("%d story client checks failed" % _failures)
	else:
		print("Story client checks passed")
	quit(1 if _failures > 0 else 0)
