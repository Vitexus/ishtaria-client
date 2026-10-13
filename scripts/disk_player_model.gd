extends Node
## The model a story datadisk draws for its players (`player_model` of a disk in GET /world
## `datadisks`), fetched from the server before anybody signs in: story media is public, like the
## covers. Until it arrives the pack look of the character is drawn; a broken or oversized file is
## never used. The character catalog keeps the result.

const CATALOG := preload("res://scripts/character_catalog.gd")
const STORY := preload("res://scripts/story_client.gd")

## The model of a character arrived, or was withdrawn.
signal changed

var _request: HTTPRequest
var _wanted := ""

## The character, model URL and height in metres (0 when the disk does not say) the first disk of a world
## names, from `datadisks`; empty strings when no disk gives players a model of its own.
static func announced(datadisks: Variant) -> Array:
	if not datadisks is Array:
		return ["", "", 0.0]
	for disk: Variant in datadisks:
		if not disk is Dictionary or not disk.get("player_character") is String:
			continue
		# The first disk that names the character decides, with or without a model.
		var url: Variant = disk.get("player_model")
		var body: Variant = disk.get("player_body")
		var height := 0.0
		if body is Dictionary and (body.get("height_m") is float or body.get("height_m") is int) and body.height_m >= 0.5 and body.height_m <= 8.0:
			height = float(body.height_m)
		if url is String and STORY.valid_media_url(url) and url.ends_with(".glb"):
			return [disk.player_character, url, height]
		return [disk.player_character, "", height]
	return ["", "", 0.0]

## Asks for the model of the world's players; `server_url` is the base address.
func use(server_url: String, character: String, url: String, height_m := 0.0) -> void:
	if url.is_empty() or character.is_empty() or not CATALOG.is_valid(character):
		_wanted = ""
		_cancel()
		if not CATALOG.disk_character.is_empty():
			CATALOG.set_disk_model("", null)
			changed.emit()
		return
	var key := server_url + url
	if key == _wanted:
		return
	_wanted = key
	_cancel()
	CATALOG.set_disk_model("", null)
	_request = HTTPRequest.new()
	_request.timeout = 20.0
	_request.max_redirects = 0
	_request.body_size_limit = STORY.MAX_MODEL_BYTES
	add_child(_request)
	_request.request_completed.connect(_on_completed.bind(key, character, height_m))
	if _request.request(key) != OK:
		_cancel()

func _cancel() -> void:
	if is_instance_valid(_request):
		_request.queue_free()
	_request = null

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, key: String, character: String, height_m: float) -> void:
	_cancel()
	if key != _wanted:
		return
	var scene: PackedScene = STORY.decode_model(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if scene == null:
		# The next refresh of the world asks again.
		_wanted = ""
		return
	CATALOG.set_disk_model(character, scene, height_m)
	changed.emit()
