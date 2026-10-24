extends Node
## Achievements: the catalog with what this character has earned (`GET /players/me/achievements`).
## The server alone grants them, inside the action that earns one, and tells the owner through an
## `achievement` event; the client asks again and then announces the new one. Titles and
## descriptions are English keys translated here; hidden ones arrive without them until earned.

signal loaded(data: Dictionary)
## A newly earned achievement (a validated catalog entry with `unlocked_at`), to be announced.
signal unlocked(achievement: Dictionary)

const CATEGORIES := ["progress", "gathering", "magic", "social", "story"]
const MAX_ACHIEVEMENTS := 200

var server_url := ""
var data := {"achievements": [], "earned": []}
var _token := ""
var _generation := 0
var _pending: Array[String] = []

func start(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token
	refresh()

func stop() -> void:
	_generation += 1
	_token = ""
	_pending.clear()
	data = {"achievements": [], "earned": []}
	loaded.emit(data)

func is_running() -> bool:
	return not _token.is_empty()

## The server said `id` was just earned: load the list again, then announce it.
func announce(id: String) -> void:
	if not valid_id(id) or id in _pending:
		return
	_pending.append(id)
	refresh()

static func valid_id(id: Variant) -> bool:
	if not id is String:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{1,48}$")
	return pattern.search(id) != null

static func valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary or not valid_id(entry.get("id")) or not valid_id(entry.get("icon")):
		return false
	if not entry.get("category") in CATEGORIES or not entry.get("hidden") is bool:
		return false
	for key in ["title", "description"]:
		if not entry.get(key) is String or entry[key].length() > 200:
			return false
	# Only a hidden achievement may come without its texts.
	return entry.hidden or (not entry.title.is_empty() and not entry.description.is_empty())

static func valid_reply(reply: Variant) -> bool:
	if not reply is Dictionary or not reply.get("achievements") is Array or not reply.get("earned") is Array:
		return false
	if reply.achievements.size() > MAX_ACHIEVEMENTS or reply.earned.size() > MAX_ACHIEVEMENTS:
		return false
	var ids := {}
	for entry: Variant in reply.achievements:
		if not valid_entry(entry) or ids.has(entry.id):
			return false
		ids[entry.id] = true
	for earned: Variant in reply.earned:
		if not earned is Dictionary or not ids.has(earned.get("id")):
			return false
		var when: Variant = earned.get("unlocked_at")
		if not (when is float or when is int) or when < 0 or when > 1e11 or when != floor(when):
			return false
	return true

## The catalog entry of `id` with `unlocked_at` (0 when not earned), or an empty dictionary.
func entry(id: String) -> Dictionary:
	for candidate: Dictionary in data.achievements:
		if candidate.id == id:
			var result := candidate.duplicate()
			result["unlocked_at"] = 0
			for earned: Dictionary in data.earned:
				if earned.id == id:
					result["unlocked_at"] = int(earned.unlocked_at)
			return result
	return {}

func refresh() -> void:
	if _token.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 6.0
	request.max_redirects = 0
	request.body_size_limit = 131072
	add_child(request)
	var generation := _generation
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, reply: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation or result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var parsed: Variant = JSON.parse_string(reply.get_string_from_utf8())
		if not valid_reply(parsed):
			return
		data = parsed
		loaded.emit(data)
		var announced := _pending.duplicate()
		_pending.clear()
		for id in announced:
			var earned := entry(id)
			if not earned.is_empty() and earned.unlocked_at > 0:
				unlocked.emit(earned)
	)
	var headers := PackedStringArray(["Authorization: Bearer " + _token])
	if request.request(server_url + "/players/me/achievements", headers) != OK:
		request.queue_free()
