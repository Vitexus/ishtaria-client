extends Node

signal profile_changed(profile: Dictionary)
## An item was dropped or picked up from the ground; refresh nearby piles.
signal ground_changed
signal failed(message: String)
signal busy_changed(busy: bool)
signal obituary_received(obituary: Dictionary)
signal grave_changed(grave: Dictionary)
signal position_changed(position: Dictionary, moving: bool, sitting: bool)
## The server says whether the character is in deep water (swimming, which tires; drowning only at low stamina).
signal swimming_changed(swimming: bool)
## The vehicle (a place id) the character is aboard, empty when none; sent with every move acknowledgement.
signal vehicle_changed(id: String)
## The server moved the character itself: boarding (onto the boat) or getting off (onto the shore); absolute metres.
signal vehicle_moved(position: Array)
signal stats_changed(stats: Dictionary)
signal harvested(reply: Dictionary)
signal npc_struck(reply: Dictionary)
signal milked(reply: Dictionary)
signal crafted
signal blocked(reply: Dictionary)
signal recipes_received(recipes: Array)
## The share link of a finished portal, to copy.
signal link_received(link: String)
signal portals_received(portals: Array)
signal portal_received(portal: Dictionary)
signal portal_closed

const CATALOG := preload("res://scripts/character_catalog.gd")
## After this many lost moves in a row the player is told once; walking keeps retrying.
const MOVE_FAILURE_NOTICE := 5
var server_url := ""
var busy := false
var _token := ""
var _generation := 0
var _request: HTTPRequest
var _timer: Timer
var _move_request: HTTPRequest
var _move_sequence := 0
var _movement_available := true
## Consecutive move requests lost to timeouts, rate limits or server errors.
var _move_failures := 0

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 10.0
	_timer.timeout.connect(refresh)
	add_child(_timer)

func token() -> String:
	return _token

func configure(url: String) -> void:
	_generation += 1
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null
	if is_instance_valid(_move_request):
		_move_request.cancel_request()
		_move_request.queue_free()
	_move_request = null
	_move_sequence = 0
	_movement_available = true
	_move_failures = 0
	_token = ""
	server_url = url
	_timer.stop()
	_set_busy(false)
	profile_changed.emit({})

static func safe_transport(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	var pattern := RegEx.new()
	pattern.compile("^http://(?:127\\.0\\.0\\.1|localhost|\\[::1\\])(?::[0-9]+)?(?:/|$)")
	return pattern.search(url) != null

func submit(nickname: String, password: String, character: String, create: bool) -> void:
	if busy:
		return
	var pattern := RegEx.new()
	pattern.compile("^[a-zA-Z0-9_-]{3,32}$")
	if pattern.search(nickname) == null:
		failed.emit("Invalid nickname")
		return
	# Every account needs a password: an empty one used to skip this check on both sides, and
	# because usernames are public anyone could sign in as such a character and destroy it
	# for good. Mirrors `validate` of the server's players.rs.
	if password.to_utf8_buffer().size() < 8 or password.to_utf8_buffer().size() > 128:
		failed.emit("Invalid password")
		return
	if not CATALOG.is_valid(character):
		failed.emit("Invalid character")
		return
	if not safe_transport(server_url):
		failed.emit("HTTPS is required for remote accounts")
		return
	var payload := {"username": nickname, "password": password}
	if create:
		payload.character = character
	_send("/players" if create else "/players/login", HTTPClient.METHOD_POST, JSON.stringify(payload))

func refresh() -> void:
	if not busy and not _token.is_empty():
		_send("/players/me", HTTPClient.METHOD_GET)

var _vehicle := ""

func _set_vehicle(id: String) -> void:
	if id != _vehicle:
		_vehicle = id
		vehicle_changed.emit(id)

func sign_out() -> void:
	if busy or _token.is_empty():
		return
	_send("/players/session", HTTPClient.METHOD_DELETE)

func eat(item_id: String) -> void:
	if busy or _token.is_empty() or item_id.is_empty() or item_id.length() > 64:
		return
	_send("/players/me/eat", HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id}))

## `action`: "fill" at fresh water or a fountain, or "drink" from the waterskin anywhere.
func waterskin(action: String) -> void:
	if not busy and not _token.is_empty() and action in ["fill", "drink"]:
		_send("/players/me/waterskin/" + action, HTTPClient.METHOD_POST)

## Boards the vehicle of a datadisk (a boat) within reach, by its place id.
func board_vehicle(id: String) -> void:
	if not busy and not _token.is_empty() and not id.is_empty() and id.length() <= 200:
		_send("/players/me/vehicle/board", HTTPClient.METHOD_POST, JSON.stringify({"id": id}))

## Gets off the vehicle at the nearest shore.
func leave_vehicle() -> void:
	if not busy and not _token.is_empty():
		_send("/players/me/vehicle/leave", HTTPClient.METHOD_POST)

static func vehicle_error(code: int, text: String) -> String:
	match text.strip_edges():
		"vehicle is not within reach":
			return "The boat is out of reach"
		"vehicle is taken", "already aboard":
			return "The boat is taken"
		"vehicle is aground":
			return "The boat is aground"
		"no shore within reach":
			return "No shore within reach"
		"player is dead":
			return "Player is dead"
	return "Too many actions" if code == 429 else "Item action unavailable"

func drink() -> void:
	if not busy and not _token.is_empty():
		_send("/players/me/drink", HTTPClient.METHOD_POST)

func grave(id: String) -> void:
	if not busy and not _token.is_empty() and id.is_valid_int():
		_send("/graves/" + id, HTTPClient.METHOD_GET)

func loot(id: String, item_id: String) -> void:
	if not busy and not _token.is_empty() and id.is_valid_int():
		_send("/graves/" + id + "/loot", HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id, "quantity": "1"}))

## Drops one piece of an unequipped inventory item at the character's feet.
func drop_item(item_id: String) -> void:
	if not busy and not _token.is_empty() and not item_id.is_empty() and item_id.length() <= 64:
		_send("/players/me/drop", HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id, "quantity": 1}))

## Picks up a pile lying on the ground nearby.
func pickup_ground(id: int) -> void:
	if not busy and not _token.is_empty() and id > 0:
		_send("/ground/%s/pickup" % id, HTTPClient.METHOD_POST)

func harvest(object_id: String) -> void:
	if not busy and not _token.is_empty() and not object_id.is_empty() and object_id.length() <= 100:
		_send("/players/me/harvest", HTTPClient.METHOD_POST, JSON.stringify({"object_id": object_id}))

## Sit on a generated rock (empty hands / no pickaxe). Stand with the same E, or by walking.
func sit(object_id: String) -> void:
	if not busy and not _token.is_empty() and not object_id.is_empty() and object_id.length() <= 100:
		_send("/players/me/sit", HTTPClient.METHOD_POST, JSON.stringify({"object_id": object_id}))

func stand() -> void:
	if not busy and not _token.is_empty():
		_send("/players/me/stand", HTTPClient.METHOD_POST)

## Swings the weapon in hand at an animal; the server decides whether it is hit and butchered.
func butcher(object_id: String) -> void:
	if not busy and not _token.is_empty() and not object_id.is_empty() and object_id.length() <= 100:
		_send("/players/me/butcher", HTTPClient.METHOD_POST, JSON.stringify({"object_id": object_id}))

## Strikes a story NPC; the server marks lasting hostility and may have the NPC strike back.
func strike_npc(npc_id: String) -> void:
	if not busy and not _token.is_empty() and not npc_id.is_empty() and npc_id.length() <= 80:
		_send("/story/npc/strike", HTTPClient.METHOD_POST, JSON.stringify({"npc_id": npc_id}))

## Drinks milk from a cow.
func milk(object_id: String) -> void:
	if not busy and not _token.is_empty() and not object_id.is_empty() and object_id.length() <= 100:
		_send("/players/me/milk", HTTPClient.METHOD_POST, JSON.stringify({"object_id": object_id}))

## Shows (or with null hides) the flag next to the player's name. A display choice only; the
## server never uses it for translation.
func set_flag(flag: Variant) -> void:
	var pattern := RegEx.new()
	pattern.compile("^[A-Z]{2}$")
	if busy or _token.is_empty() or not (flag == null or (flag is String and pattern.search(flag) != null)):
		return
	_send("/players/me/flag", HTTPClient.METHOD_PUT, JSON.stringify({"flag": flag}))

func craft(recipe_id: String, count := 1) -> void:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{1,60}$")
	if not busy and not _token.is_empty() and pattern.search(recipe_id) != null and count >= 1 and count <= 100:
		_send("/players/me/craft", HTTPClient.METHOD_POST, JSON.stringify({"recipe": recipe_id, "count": str(count)}))

func equip(item_id: String) -> void:
	if not busy and not _token.is_empty() and item_id.length() <= 40:
		_send("/players/me/equip", HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id}))

func unequip(slot := "hand") -> void:
	if not busy and not _token.is_empty() and slot in ["hand", "offhand", "body", "hands"]:
		_send("/players/me/equip" + ("" if slot == "hand" else "?slot=" + slot), HTTPClient.METHOD_DELETE)

## Raises the shield in the other hand; the server renews the block for a couple of seconds.
func block() -> void:
	if not busy and not _token.is_empty():
		_send("/players/me/block", HTTPClient.METHOD_POST, "{}")

func fetch_recipes() -> void:
	if not busy:
		_send("/recipes", HTTPClient.METHOD_GET)

## Starts a portal where the player stands.
func build_portal(portal_name: String) -> void:
	if not busy and not _token.is_empty() and valid_portal_name(portal_name):
		_send("/portals/build", HTTPClient.METHOD_POST, JSON.stringify({"portal_name": portal_name}))

func fetch_portals() -> void:
	if not busy and not _token.is_empty():
		_send("/portals/mine", HTTPClient.METHOD_GET)

func fetch_portal(id: String) -> void:
	if not busy and not _token.is_empty() and valid_uuid(id):
		_send("/portals/mine/" + id, HTTPClient.METHOD_GET)

func deliver(id: String, item_id: String, quantity: int) -> void:
	if not busy and not _token.is_empty() and valid_uuid(id) and quantity > 0 and item_id.length() <= 40:
		_send("/portals/mine/" + id + "/contribute", HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id, "quantity": str(quantity)}))

## Asks for the share link of a finished portal.
func fetch_link(id: String) -> void:
	if not busy and not _token.is_empty() and valid_uuid(id):
		_send("/portals/mine/" + id + "/link", HTTPClient.METHOD_GET)

## Pastes the share link of another world's portal at one of the player's finished portals.
func connect_portal(id: String, link: String) -> void:
	if not busy and not _token.is_empty() and valid_uuid(id) and valid_link(link):
		_send("/portals/mine/" + id + "/connect", HTTPClient.METHOD_POST, JSON.stringify({"link": link.strip_edges()}))

## Breaks the link of a portal; it is a finished portal again.
func disconnect_portal(id: String) -> void:
	if not busy and not _token.is_empty() and valid_uuid(id):
		_send("/portals/mine/" + id + "/link", HTTPClient.METHOD_DELETE)

func close_portal(id: String) -> void:
	if not busy and not _token.is_empty() and valid_uuid(id):
		_send("/portals/mine/" + id, HTTPClient.METHOD_DELETE)

static func valid_link(link: String) -> bool:
	var text := link.strip_edges()
	return text.begins_with("ishtaria-portal:v1.") and text.length() <= 2048 and not text.contains(" ")

static func valid_portal_name(name: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9-]{1,64}$")
	return pattern.search(name) != null

static func valid_uuid(id: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return pattern.search(id) != null

## Message key for a refused portal action; fixed keys, never the server text.
static func portal_error(code: int, text: String) -> String:
	match text.strip_edges():
		"federation is closed", "this world does not link portals":
			return "This world does not link portals"
		"federation not configured", "federation unavailable":
			return "Federation is not configured"
		"too many portals":
			return "Too many portals"
		"portal name already in use":
			return "Portal name already in use"
		"invalid portal name":
			return "Invalid portal name"
		"this is not a portal share link", "invalid signed message":
			return "That is not a portal share link"
		"peer unreachable", "invalid peer address", "invalid peer info", "invalid peer reply":
			return "The other world is unreachable"
		"peer key changed", "peer identity mismatch", "peer address does not match its world name", "invalid signature", "peer banned", "peer refused the link", "unprocessable":
			return "The other world could not be verified"
		"the portal does not stand there":
			return "The portal does not stand there"
		"the other portal is not finished":
			return "The other portal is not finished"
		"the other portal is already linked":
			return "The other portal is already linked"
		"the other portal is closed":
			return "The other portal is closed"
		"the peer portal is not ready to be linked", "peer rejected the link":
			return "The other portal is not ready"
		"only a finished, unlinked portal can be shared", "only a finished, unlinked portal can be connected", "the portal was linked meanwhile":
			return "Only a finished, unlinked portal can be linked"
		"the portal is not linked":
			return "The portal is not linked"
		"a portal cannot be built here":
			return "A portal cannot be built here"
		"another portal is too close":
			return "Another portal is too close"
		"the land is leased by another player":
			return "The land is leased by another player"
		"the construction site is out of reach":
			return "The construction site is out of reach"
		"more than the portal still needs":
			return "More than the portal still needs"
		"not enough items":
			return "Not enough items"
		"the portal does not need this item":
			return "The portal does not need this item"
		"the portal is not under construction", "there is no construction site":
			return "The portal is not under construction"
		"the portal is already closed":
			return "The portal is already closed"
		"player position unavailable":
			return "Player position unavailable"
	return "Too many actions" if code == 429 else "Portal action unavailable"

static func valid_portal(data: Variant) -> bool:
	if not data is Dictionary or not data.get("id") is String or not valid_uuid(data.id):
		return false
	for key in ["state", "portal_name"]:
		if not data.get(key) is String:
			return false
	for key in ["peer_host", "peer_portal_name"]:
		if data.get(key) != null and not data.get(key) is String:
			return false
	if not data.state in ["building", "built", "pending", "open", "closed"]:
		return false
	if data.has("requirements"):
		if not data.requirements is Array or data.requirements.size() > 16:
			return false
		for requirement: Variant in data.requirements:
			if not requirement is Dictionary or not requirement.get("id") is String or not requirement.get("items") is Array or not requirement.get("required") is String or not requirement.required.is_valid_int() or not requirement.get("contributed") is String or not requirement.contributed.is_valid_int():
				return false
			for item: Variant in requirement.items:
				if not item is String:
					return false
	return true

## Message key for a refused harvest or craft; empty when nothing should be shown.
static func drink_error(code: int, text: String) -> String:
	match text.strip_edges():
		"sea water is not drinkable":
			return "Sea water is salty"
		"no fresh water within reach":
			return "Nothing to harvest or drink nearby"
		"no waterskin":
			return "You have no waterskin"
		"waterskin is empty":
			return "The waterskin is empty"
		"not thirsty":
			return "You are not thirsty"
		"player is dead":
			return "Player is dead"
	return "Too many actions" if code == 429 else "Item action unavailable"

static func action_error(code: int, text: String) -> String:
	match text.strip_edges():
		"inventory is full", "stack is full":
			return "Inventory is full"
		"too exhausted":
			return "Too exhausted"
		"required tool missing":
			return "Equip a suitable tool"
		"this item cannot be equipped":
			return "This item cannot be equipped"
		"no shield in hand":
			return "No shield in hand"
		"already harvested", "object not found", "object cannot be harvested", "already butchered", "animal not found", "animal cannot be butchered", "animal gives no milk", "object cannot be sat on", "object is gone":
			return "Nothing to harvest there"
		"object is out of reach", "animal is out of reach", "npc out of reach":
			return "Object is out of reach"
		"cannot strike companion":
			return "You will not strike your companion"
		"cannot strike a friend":
			return "You will not strike a friend"
		"npc not found":
			return "Nothing to hit"
		"story unavailable":
			return "Action unavailable"
		"player position unavailable":
			return "Action unavailable"
		"cannot sit while airborne":
			return "Cannot sit while jumping"
		"weapon missing":
			return "Equip a weapon"
		"cow was milked recently":
			return "The cow has no milk now"
		"missing ingredients":
			return "Missing ingredients"
		"station missing":
			return "Stand next to the station this needs"
		"cannot drop an equipped item":
			return "Unequip it first"
		"not enough to drop", "item not found":
			return "Nothing to drop"
		"nothing to pick up":
			return "Nothing to pick up"
		"drop worn gear one piece at a time":
			return "Drop one piece at a time"
		"too fast":
			return ""
	return "Too many actions" if code == 429 else "Item action unavailable"

static func valid_harvest(data: Variant) -> bool:
	if not data is Dictionary or not data.get("object_id") is String or not data.get("state") in ["hit", "depleted"]:
		return false
	for key in ["hits", "hits_required"]:
		if not (data.get(key) is float or data.get(key) is int) or data[key] < 0 or data[key] > 1000:
			return false
	if data.has("xp") and (not (data.xp is float or data.xp is int) or data.xp < 0 or data.xp > 100000):
		return false
	if not valid_wear(data.get("wear")) or not valid_counter(data.get("counter")):
		return false
	if not data.get("items") is Array or data.items.size() > 16 or not data.get("player") is Dictionary:
		return false
	for item: Variant in data.items:
		if not item is Dictionary or not item.get("item_id") is String or not item.get("name") is String or not item.get("quantity") is String or not item.quantity.is_valid_int():
			return false
	if data.has("ground"):
		if not data.ground is Array or data.ground.size() > 16:
			return false
		for item: Variant in data.ground:
			if not item is Dictionary or not item.get("item_id") is String or not item.get("name") is String or not item.get("quantity") is String or not item.quantity.is_valid_int():
				return false
	return true

static func valid_milk(data: Variant) -> bool:
	return data is Dictionary and data.get("object_id") is String and (data.get("water") is float or data.get("water") is int) and data.water >= 0 and data.water <= 100 and data.get("player") is Dictionary

## How an animal bit back: absent, or the damage it meant, the damage that got through and the armour's share.
static func valid_npc_strike(data: Variant) -> bool:
	if not data is Dictionary or not data.get("npc_id") is String:
		return false
	if not (data.get("health") is float or data.get("health") is int):
		return false
	if not (data.get("max_health") is float or data.get("max_health") is int):
		return false
	if not data.get("hostile") is bool or not data.get("defeated") is bool:
		return false
	var counter: Variant = data.get("counter")
	if counter == null:
		return true
	if not counter is Dictionary:
		return false
	if not (counter.get("damage") is float or counter.get("damage") is int):
		return false
	return counter.get("died") is bool

static func valid_counter(counter: Variant) -> bool:
	if counter == null:
		return true
	if not counter is Dictionary or not counter.get("blocked") is bool or not counter.get("died") is bool:
		return false
	for key in ["attempted", "damage", "defense"]:
		if not (counter.get(key) is float or counter.get(key) is int) or counter[key] < 0 or counter[key] > 100:
			return false
	return counter.get("wear") is Array and counter.wear.size() <= 4

static func valid_wear(wear: Variant) -> bool:
	return wear == null or (wear is Dictionary and wear.get("broken") is bool and (wear.get("durability") is float or wear.get("durability") is int) and wear.durability >= 0 and (wear.get("max_durability") is float or wear.get("max_durability") is int) and wear.max_durability > 0)

static func valid_block(data: Variant) -> bool:
	return data is Dictionary and (data.get("blocking_seconds") is float or data.get("blocking_seconds") is int) and data.blocking_seconds >= 0 and data.blocking_seconds <= 30 and valid_wear(data.get("wear")) and data.get("player") is Dictionary

func _set_busy(value: bool) -> void:
	busy = value
	busy_changed.emit(value)

func move(direction: Vector3, jump: bool = false, run: bool = false) -> bool:
	if busy or _token.is_empty() or is_instance_valid(_move_request) or not _movement_available:
		return false
	if _move_sequence == 9223372036854775807:
		return false
	_move_sequence += 1
	var request := HTTPRequest.new()
	request.timeout = 2.0
	request.max_redirects = 0
	request.body_size_limit = 2048
	request.request_completed.connect(_move_received.bind(_generation, request))
	add_child(request)
	_move_request = request
	var body := JSON.stringify({"direction": [direction.x, direction.y, direction.z], "sequence": str(_move_sequence), "jump": jump, "run": run})
	if request.request(server_url + "/players/me/move", PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _token]), HTTPClient.METHOD_POST, body) != OK:
		_move_request = null
		request.queue_free()
		return false
	return true

func _move_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, request: HTTPRequest) -> void:
	if generation != _generation:
		return
	_move_request = null
	request.queue_free()
	if code == 401 or code == 410:
		configure(server_url)
		var notice: Variant = JSON.parse_string(body.get_string_from_utf8())
		if code == 410 and notice is Dictionary and valid_obituary(notice.get("obituary")):
			obituary_received.emit(notice.obituary)
			return
		failed.emit("Player is dead" if code == 410 else "Invalid credentials or expired session")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# A missing endpoint really means walking is off. A timeout, 429 or brief proxy glitch must not
		# lock the character in place (while drowning that is fatal): the next intent retries.
		if code in [400, 404, 405, 422, 501]:
			_movement_available = false
			failed.emit("Movement unavailable")
			return
		_move_failures += 1
		if _move_failures == MOVE_FAILURE_NOTICE:
			failed.emit("Movement interrupted")
		return
	_move_failures = 0
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("position") is Dictionary or not data.get("moving") is bool:
		_movement_available = false
		failed.emit("Invalid player profile")
		return
	var sequence: Variant = data.position.get("sequence")
	if not sequence is String or not sequence.is_valid_int() or int(sequence) < _move_sequence:
		_movement_available = false
		failed.emit("Invalid player profile")
		return
	_move_sequence = int(sequence)
	if data.get("stats") is Dictionary:
		stats_changed.emit(data.stats)
	var seated: bool = data.get("sitting") == true
	swimming_changed.emit(data.get("swimming") == true)
	_set_vehicle(data.get("vehicle") if data.get("vehicle") is String else "")
	position_changed.emit(data.position, data.moving, seated)

static func valid_obituary(data: Variant) -> bool:
	if not data is Dictionary or not data.get("name") is String:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[a-zA-Z0-9_-]{3,32}$")
	if pattern.search(data.name) == null:
		return false
	if not data.get("born_at") is String:
		return false
	pattern.compile("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\\.[0-9]{6}Z$")
	if pattern.search(data.born_at) == null:
		return false
	var birth: String = data.born_at.substr(0, 19)
	var date := Time.get_datetime_dict_from_datetime_string(birth, false)
	var year: int = date.year
	var month_days := [31, 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if date.day > month_days[date.month - 1]:
		return false
	pattern.compile("^(0|[1-9][0-9]{0,18})$")
	for field in ["lived_days", "lifetime_gold", "friends_count"]:
		var value: Variant = data.get(field)
		if not value is String or pattern.search(value) == null:
			return false
		if value.length() == 19 and value > "9223372036854775807":
			return false
	return true

func _send(path: String, method: HTTPClient.Method, body := "") -> void:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.max_redirects = 0
	request.body_size_limit = 262144
	request.request_completed.connect(_received.bind(_generation, request, path))
	add_child(request)
	_request = request
	_set_busy(true)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	if request.request(server_url + path, headers, method, body) != OK:
		_request = null
		request.queue_free()
		_set_busy(false)
		failed.emit("Player service unavailable")

func _received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, request: HTTPRequest, path: String) -> void:
	if generation != _generation:
		return
	_request = null
	if is_instance_valid(request):
		request.queue_free()
	_set_busy(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Player service unavailable")
		return
	if path == "/players/session" and code == 204:
		configure(server_url)
		return
	if code == 401:
		configure(server_url)
		failed.emit("Invalid credentials or expired session")
		return
	if code == 410:
		configure(server_url)
		var notice: Variant = JSON.parse_string(body.get_string_from_utf8())
		if notice is Dictionary and valid_obituary(notice.get("obituary")):
			obituary_received.emit(notice.obituary)
			return
		failed.emit("Player is dead")
		return
	if code < 200 or code >= 300:
		if path in ["/players/me/harvest", "/players/me/butcher", "/players/me/milk", "/players/me/craft", "/players/me/block", "/players/me/sit", "/players/me/stand", "/players/me/drop", "/story/npc/strike"] or path.begins_with("/players/me/equip") or path.begins_with("/ground/"):
			var message := action_error(code, body.get_string_from_utf8())
			if not message.is_empty():
				failed.emit(message)
			if code != 429:
				refresh()
			return
		if path.begins_with("/portals/"):
			var portal_message := portal_error(code, body.get_string_from_utf8())
			failed.emit(portal_message)
			return
		if path.begins_with("/players/me/vehicle/"):
			failed.emit(vehicle_error(code, body.get_string_from_utf8()))
			return
		if path == "/players/me/drink" or path.begins_with("/players/me/waterskin/"):
			failed.emit(drink_error(code, body.get_string_from_utf8()))
			return
		if path == "/players/me/eat" or path.begins_with("/graves/"):
			failed.emit("Player is dead" if code == 409 and path == "/players/me/eat" else ("Grave is out of reach" if code == 403 else "Item action unavailable"))
			refresh()
			return
		failed.emit("Nickname is already taken" if code == 409 else ("Authentication busy" if code == 429 else "Player service unavailable"))
		return
	if path.begins_with("/portals/") and code == 204:
		portal_closed.emit()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if path.begins_with("/players/me/vehicle/") and data is Dictionary and data.get("position") is Array and data.position.size() == 3:
		for value: Variant in data.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				failed.emit("Invalid player profile")
				return
		_set_vehicle(data.get("vehicle") if data.get("vehicle") is String else "")
		vehicle_moved.emit(data.position)
		return
	if path.begins_with("/graves/") and not path.ends_with("/loot") and data is Dictionary:
		if valid_obituary(data.get("obituary")):
			grave_changed.emit(data)
		else:
			failed.emit("Invalid player profile")
		return
	if path.begins_with("/portals/mine/") and path.ends_with("/link") and data is Dictionary and data.has("link"):
		if data.get("link") is String and valid_link(data.link):
			link_received.emit(data.link)
		else:
			failed.emit("Invalid player profile")
		return
	if path == "/portals/mine" and data is Array:
		if data.size() > 64:
			failed.emit("Invalid player profile")
			return
		var accepted: Array = []
		for portal: Variant in data:
			if valid_portal(portal):
				accepted.append(portal)
		portals_received.emit(accepted)
		return
	if path.begins_with("/portals/mine/") or path == "/portals/build":
		if valid_portal(data):
			portal_received.emit(data)
		else:
			failed.emit("Invalid player profile")
		return
	if path == "/recipes":
		if data is Array and data.size() <= 64:
			recipes_received.emit(data)
		else:
			failed.emit("Invalid player profile")
		return
	if not data is Dictionary:
		failed.emit("Invalid player profile")
		return
	if path == "/story/npc/strike":
		if not valid_npc_strike(data):
			failed.emit("Invalid player profile")
			return
		npc_struck.emit(data)
		refresh()
		return
	var harvest_reply: Dictionary = {}
	var milk_reply: Dictionary = {}
	if path == "/players/me/milk":
		if not valid_milk(data):
			failed.emit("Invalid player profile")
			return
		milk_reply = data
		data = data.player
	if path == "/players/me/harvest" or path == "/players/me/butcher":
		if not valid_harvest(data):
			failed.emit("Invalid player profile")
			return
		harvest_reply = data
		data = data.player
	if path == "/players/me/sit" or path == "/players/me/stand":
		if not data.get("sitting") is bool or not data.get("player") is Dictionary:
			failed.emit("Invalid player profile")
			return
		data = data.player
	var block_reply: Dictionary = {}
	if path == "/players/me/block":
		if not valid_block(data):
			failed.emit("Invalid player profile")
			return
		block_reply = data
		data = data.player
	var profile: Variant = data
	if path in ["/players", "/players/login"]:
		var token: Variant = data.get("token")
		var pattern := RegEx.new()
		pattern.compile("^[0-9a-f]{64}$")
		if not token is String or pattern.search(token) == null:
			failed.emit("Invalid player profile")
			return
		_token = token
		profile = data.get("player")
	if not profile is Dictionary or not profile.get("character") is String or not CATALOG.is_valid(profile.character):
		configure(server_url)
		failed.emit("Invalid player profile")
		return
	profile_changed.emit(profile)
	if not block_reply.is_empty():
		blocked.emit(block_reply)
	if not harvest_reply.is_empty():
		harvested.emit(harvest_reply)
		if harvest_reply.get("ground") is Array and not harvest_reply.ground.is_empty():
			ground_changed.emit()
	elif not milk_reply.is_empty():
		milked.emit(milk_reply)
	elif path == "/players/me/craft":
		crafted.emit()
	if path == "/players/me/drop" or (path.begins_with("/ground/") and path.ends_with("/pickup")):
		ground_changed.emit()
	var position: Variant = profile.get("position")
	if position is Dictionary and position.get("sequence") is String and position.sequence.is_valid_int():
		_move_sequence = maxi(_move_sequence, int(position.sequence))
	_movement_available = true
	if path.begins_with("/graves/") and path.ends_with("/loot"):
		grave(path.split("/")[2])
	if not _token.is_empty():
		_timer.start()

func _exit_tree() -> void:
	if is_instance_valid(_move_request):
		_move_request.cancel_request()
	if is_instance_valid(_request):
		_request.cancel_request()