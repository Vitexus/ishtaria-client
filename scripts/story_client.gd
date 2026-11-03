extends Node
## The story of the connected world: dialogues with characters, the translations the
## server hands out for every language, and the portraits and music of a conversation.
## The server decides everything; this node sends the player's choice and shows the answer.
## The language is the client's own: the server only ever sees translation keys.

const QUEST_COMPASS := preload("res://scripts/quest_compass.gd")

signal dialogue_changed(reply: Dictionary)
signal failed(message: String)
signal strings_changed
## The player's quests, each {quest, title_key, stage, text_key, final}; sent when they change.
signal quests_changed(quests: Array)
## Places the quests point to (active guides always; unstarted need the aetherglass); sent when they change.
signal markers_changed(markers: Array)
## A portrait (Texture2D) or a track (AudioStream) finished loading.
signal media_ready(url: String, resource: Resource)
## What a character tells about itself (a knowledge card).
signal about_ready(npc_id: String, card: Dictionary)
## A dialogue request the player asked for (a choice, "tell me about yourself") is in flight, or was answered.
signal busy_changed(busy: bool)
## What the player read at a structure of a place (a knowledge card).
signal reading_ready(place_id: String, card: Dictionary)

const MAX_STRINGS_BYTES := 4194304
const MAX_IMAGE_BYTES := 2097152
const MAX_AUDIO_BYTES := 10485760
const MAX_CACHED_MEDIA := 32
const MAX_MODEL_BYTES := 4194304
const QUEST_POLL_SECONDS := 6.0

var server_url := ""
var _token := ""
var _generation := 0
var _strings: Dictionary = {}
var _media: Dictionary = {}
var _pending_media: Dictionary = {}
var _busy := false
var _actions := 0
var _quests: Array = []
var _quests_loaded := false
var _markers: Array = []
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = QUEST_POLL_SECONDS
	_timer.timeout.connect(load_quests)
	add_child(_timer)

func is_running() -> bool:
	return not _token.is_empty()

func start_session(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token
	_quests = []
	_quests_loaded = false
	load_strings()
	load_quests()
	_timer.start()

func stop() -> void:
	_generation += 1
	_token = ""
	_busy = false
	_set_actions(0)
	if not _markers.is_empty():
		_markers = []
		markers_changed.emit(_markers)
	_quests = []
	_quests_loaded = false
	if is_instance_valid(_timer):
		_timer.stop()
	_strings = {}
	_pending_media.clear()
	_media.clear()
	for child in get_children():
		if child != _timer:
			child.queue_free()

## Text for a translation key in the player's language (English when missing, the key
## itself when unknown). `args` are substituted for `%s` after translation.
func text(key: String, args: Array = []) -> String:
	var language := TranslationServer.get_locale().substr(0, 2)
	var table: Variant = _strings.get(language, _strings.get("en", {}))
	var found: String = key
	if table is Dictionary and table.get(key) is String:
		found = table[key]
	elif _strings.get("en") is Dictionary and _strings.en.get(key) is String:
		found = _strings.en[key]
	# The name is data and goes in last, after any `%s` of the text has been filled.
	return substitute_player(found % args if not args.is_empty() else found, player_name)

## The name the player chose when creating the character; `{player}` in a story text becomes it.
var player_name := ""

static func substitute_player(text: String, name: String) -> String:
	if not text.contains("{player}"):
		return text
	return text.replace("{player}", name if not name.is_empty() else "…")

static func valid_strings(data: Variant) -> bool:
	if not data is Dictionary or not data.get("languages") is Dictionary or data.languages.size() > 8:
		return false
	for language: Variant in data.languages:
		if not language is String or language.length() != 2 or not data.languages[language] is Dictionary:
			return false
		for key: Variant in data.languages[language]:
			if not key is String or key.length() > 160 or not data.languages[language][key] is String or data.languages[language][key].length() > 2000:
				return false
	return true

static func valid_media_url(url: Variant) -> bool:
	if not url is String or not url.begins_with("/story/media/") or url.length() > 220 or url.contains("..") or url.contains("//") or url.contains("?") or url.contains("#") or url.contains("%") or url.contains("\\"):
		return false
	return url.ends_with(".png") or url.ends_with(".jpg") or url.ends_with(".ogg") or url.ends_with(".glb")

## A dialogue answer the server sent, or false when anything is missing or malformed.
static func valid_reply(data: Variant) -> bool:
	if not data is Dictionary or not data.get("npc_id") is String or not data.get("name_key") is String or not data.get("open") is bool:
		return false
	if not (data.get("seq") is float or data.get("seq") is int):
		return false
	if data.get("portrait") != null and not valid_media_url(data.portrait):
		return false
	if data.get("about") != null and not data.about is bool:
		return false
	if data.get("can_trade") != null and not data.can_trade is bool:
		return false
	if data.get("music") != null:
		if not data.music is Dictionary or not valid_media_url(data.music.get("url")) or not data.music.get("title_key") is String or not data.music.get("loop") is bool:
			return false
	if not data.open:
		return true
	var node: Variant = data.get("node")
	# Authored dialogues stay at most 8 choices; the server may inject a 9th apology.
	if not node is Dictionary or not node.get("node") is String or not node.get("text_key") is String or not node.get("choices") is Array or node.choices.size() > 9:
		return false
	if node.get("voice") != null and (not node.voice is String or not valid_media_url(node.voice)):
		return false
	for choice: Variant in node.choices:
		if not choice is Dictionary or not (choice.get("index") is float or choice.get("index") is int) or not choice.get("text_key") is String:
			return false
	return true

## A knowledge card the server sent: text keys, one picture and the titles of the Wikipedia articles by language.
static func valid_about(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key: String in ["title_key", "text_key", "credit_key"]:
		if not data.get(key) is String or data[key].is_empty() or data[key].length() > 160:
			return false
	if not valid_media_url(data.get("image")):
		return false
	var titles: Variant = data.get("wikipedia")
	if not titles is Dictionary or not titles.get("en") is String or titles.size() > 32:
		return false
	for language: Variant in titles:
		if not language is String or language.length() != 2 or not (language >= "aa" and language <= "zz") or not valid_wiki_title(titles[language]):
			return false
	return true

## An article title that goes into a Wikipedia address as it is: no spaces, no characters with a meaning in a URL.
static func valid_wiki_title(title: Variant) -> bool:
	if not title is String or title.is_empty() or title.length() > 100 or title.begins_with("_"):
		return false
	for character in title:
		if character in " \t\n\r#?<>[]{}|\\/%\"&=+" or character.unicode_at(0) < 32:
			return false
	return true

## The address of the article of a card in the language of the interface, or in English when the card has none.
static func wikipedia_url(card: Dictionary, language: String) -> String:
	var titles: Dictionary = card.wikipedia
	var chosen := language if titles.has(language) else "en"
	return "https://%s.wikipedia.org/wiki/%s" % [chosen, String(titles[chosen]).uri_encode()]

## Asks what a character tells about itself; the answer arrives as `about_ready`.
func fetch_about(npc_id: String) -> void:
	_act("/story/npcs/%s/about" % npc_id.uri_encode(), HTTPClient.METHOD_GET, "", func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			failed.emit("Conversation unavailable")
			return
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not valid_about(data):
			failed.emit("Conversation unavailable")
			return
		about_ready.emit(npc_id, data)
	)

## Reads what a structure of a place carries, standing at it; the server may grant an achievement for it
## (announced as an event). The answer arrives as `reading_ready`.
func read_place(place_id: String) -> void:
	_send("/story/places/%s/read" % place_id.uri_encode(), HTTPClient.METHOD_POST, "", func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			failed.emit("Too far away to read" if code == 403 else "Nothing to read here")
			return
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not valid_about(data):
			failed.emit("Nothing to read here")
			return
		reading_ready.emit(place_id, data)
	)

func load_strings() -> void:
	_send("/story/strings", HTTPClient.METHOD_GET, "", _on_strings, MAX_STRINGS_BYTES)

## Asks for the quest log; the server also moves on quests that wait for the player to reach a place.
## `lang` only selects the narrator voice for a new quest's tablet intro; it is never stored.
func load_quests() -> void:
	_send("/story/quests?lang=" + _language(), HTTPClient.METHOD_GET, "", _on_quests)

static func valid_quests(data: Variant) -> bool:
	if not data is Array or data.size() > 64:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("quest") is String or not entry.get("title_key") is String or not entry.get("stage") is String or not entry.get("text_key") is String or not entry.get("final") is bool:
			return false
		var excerpt: Variant = entry.get("excerpt")
		if excerpt != null:
			if not excerpt is Dictionary or not excerpt.get("paraphrase_key") is String:
				return false
			if excerpt.get("akkadian_key") != null and not excerpt.akkadian_key is String:
				return false
			if excerpt.get("voice") != null and not valid_media_url(excerpt.voice):
				return false
	return true

## Asks where the quests point to; asked after every quest poll, so a new item shows up within seconds.
func load_markers() -> void:
	_send("/story/markers", HTTPClient.METHOD_GET, "", _on_markers)

func _on_markers(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if QUEST_COMPASS.valid_markers(data) and data != _markers:
		_markers = data
		markers_changed.emit(_markers)

func _on_quests(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	load_markers()
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if valid_quests(data) and (data != _quests or not _quests_loaded):
		_quests = data
		_quests_loaded = true
		quests_changed.emit(_quests)

## The language of the interface, sent with a dialogue request only so the server can pick the
## spoken line; it is never stored there.
static func _language() -> String:
	return TranslationServer.get_locale().substr(0, 2)

func start(npc_id: String) -> void:
	if _busy:
		return
	_busy = true
	_act("/story/dialogue/start", HTTPClient.METHOD_POST, JSON.stringify({"npc_id": npc_id, "lang": _language()}), _on_reply)

func choose(npc_id: String, seq: int, choice: int) -> void:
	if _busy:
		return
	_busy = true
	_act("/story/dialogue/choose", HTTPClient.METHOD_POST, JSON.stringify({"npc_id": npc_id, "seq": seq, "choice": choice, "lang": _language()}), _on_reply)

## Ends the open conversation (the player pressed escape or walked away).
func leave() -> void:
	if not _token.is_empty():
		_send("/story/dialogue", HTTPClient.METHOD_DELETE, "", func(_result: int, _code: int, _body: PackedByteArray) -> void: pass)

## Message key for a refused dialogue request; fixed keys, never the server text.
static func error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"character is out of reach":
			return "Too far away to talk"
		"not enough to pay", "not enough gold":
			return "Not enough gold"
		"npc not hostile":
			return "Conversation unavailable"
		"inventory is full", "stack is full":
			return "Inventory is full"
	return "Conversation unavailable"

func _on_reply(result: int, code: int, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit(error_key(code, body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else "Conversation unavailable")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not valid_reply(data):
		failed.emit("Conversation unavailable")
		return
	dialogue_changed.emit(data)

func _on_strings(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not valid_strings(data):
		return
	_strings = data.languages
	strings_changed.emit()

## Fetches a portrait or a track once; later calls answer from memory. A missing or
## broken file is simply never announced, so a conversation never waits for its media.
func fetch_media(url: String) -> void:
	if not valid_media_url(url):
		return
	if _media.has(url):
		media_ready.emit(url, _media[url])
		return
	if _pending_media.has(url) or _token.is_empty():
		return
	_pending_media[url] = true
	var limit := MAX_MODEL_BYTES if url.ends_with(".glb") else (MAX_AUDIO_BYTES if url.ends_with(".ogg") else MAX_IMAGE_BYTES)
	var generation := _generation
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.body_size_limit = limit
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation:
			return
		_pending_media.erase(url)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		if url.ends_with(".glb"):
			# Parsing a model takes up to a few hundred milliseconds (a quarter of Uruk is a megabyte): never on the frame.
			_decode_queue.append([url, body, generation])
			_decode_next()
			return
		_media_decoded(url, decode_media(url, body), generation)
	)
	if request.request(server_url + url) != OK:
		request.queue_free()
		_pending_media.erase(url)

## Models waiting for a worker thread, and how many are being parsed: two at most, so the game keeps its cores.
var _decode_queue: Array = []
var _decoding := 0
const MAX_DECODING := 2

func _decode_next() -> void:
	while _decoding < MAX_DECODING and not _decode_queue.is_empty():
		var job: Array = _decode_queue.pop_front()
		if job[2] != _generation:
			continue
		_decoding += 1
		var url: String = job[0]
		var body: PackedByteArray = job[1]
		var generation: int = job[2]
		WorkerThreadPool.add_task(func() -> void:
			var resource := decode_media(url, body)
			_decoded_on_main.call_deferred(url, resource, generation))

func _decoded_on_main(url: String, resource: Resource, generation: int) -> void:
	_decoding = maxi(_decoding - 1, 0)
	_media_decoded(url, resource, generation)
	_decode_next()

func _media_decoded(url: String, resource: Resource, generation: int) -> void:
	if generation != _generation or resource == null:
		return
	if _media.size() >= MAX_CACHED_MEDIA:
		_media.erase(_media.keys()[0])
	_media[url] = resource
	media_ready.emit(url, resource)

static func decode_media(url: String, body: PackedByteArray) -> Resource:
	if url.ends_with(".glb"):
		return decode_model(body)
	if url.ends_with(".ogg"):
		var stream := AudioStreamOggVorbis.load_from_buffer(body)
		return stream
	var image := Image.new()
	var error := image.load_png_from_buffer(body) if url.ends_with(".png") else image.load_jpg_from_buffer(body)
	if error != OK or image.get_width() > 2048 or image.get_height() > 2048:
		return null
	return ImageTexture.create_from_image(image)

## A character model (a self-contained glTF binary) as a scene to instantiate, or null when
## it is broken. Nothing outside the buffer is ever read.
static func decode_model(body: PackedByteArray) -> PackedScene:
	if body.size() < 20 or body.slice(0, 4).get_string_from_ascii() != "glTF":
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(body, "", state) != OK:
		return null
	var root := document.generate_scene(state)
	if root == null:
		return null
	var scene := PackedScene.new()
	var packed := scene.pack(root) == OK
	root.free()
	return scene if packed else null

## A request the player asked for: `busy_changed` reports it until its answer has been handled.
func _act(path: String, method: HTTPClient.Method, body: String, handler: Callable) -> void:
	_set_actions(_actions + 1)
	var generation := _generation
	var done := func(result: int, code: int, reply: PackedByteArray) -> void:
		handler.call(result, code, reply)
		if generation == _generation:
			_set_actions(_actions - 1)
	if not _send(path, method, body, done):
		_set_actions(_actions - 1)

func _set_actions(count: int) -> void:
	var was := _actions > 0
	_actions = maxi(count, 0)
	if was != (_actions > 0):
		busy_changed.emit(_actions > 0)

## Whether a request the player asked for is still awaited.
func is_busy() -> bool:
	return _actions > 0

func _send(path: String, method: HTTPClient.Method, body: String, handler: Callable, limit := 262144) -> bool:
	if _token.is_empty():
		_busy = false
		return false
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.max_redirects = 0
	request.body_size_limit = limit
	add_child(request)
	var generation := _generation
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, reply: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation:
			return
		handler.call(result, code, reply)
	)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _token])
	if request.request(server_url + path, headers, method, body) != OK:
		request.queue_free()
		_busy = false
		return false
	return true
