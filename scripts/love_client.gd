## Šamḫat love minigame client: polls status, throws hearts, relays events.
extends Node

signal status_changed(active: bool, hits: int, hits_to_win: int)
signal throw_landed(position: Vector3, ttl: float)
signal won

var server_url := ""
var _token := ""
var _generation := 0
var _running := false
var _active := false
var _hits := 0
var _hits_to_win := 10
var _zone_radius_m := 1.0
var _enkidu: Variant = null
var _zones: Array = []
var _cooldown_until_ms := 0
var _poll: Timer

func start(url: String, token: String) -> void:
	stop()
	server_url = url.trim_suffix("/")
	_token = token
	_running = true
	_generation += 1
	_poll = Timer.new()
	_poll.wait_time = 1.2
	_poll.timeout.connect(refresh)
	add_child(_poll)
	_poll.start()
	refresh()

func stop() -> void:
	_generation += 1
	_running = false
	_active = false
	_hits = 0
	_enkidu = null
	_zones.clear()
	if is_instance_valid(_poll):
		_poll.stop()
		_poll.queue_free()
	_poll = null
	status_changed.emit(false, 0, _hits_to_win)

func is_running() -> bool:
	return _running

func is_active() -> bool:
	return _active

func hits() -> int:
	return _hits

func hits_to_win() -> int:
	return _hits_to_win

func enkidu_metres() -> Variant:
	return _enkidu

func zones() -> Array:
	return _zones

func zone_radius_m() -> float:
	return _zone_radius_m

func throw_at(aim: Vector3) -> void:
	if not _active or _token.is_empty() or Time.get_ticks_msec() < _cooldown_until_ms:
		return
	if not aim.is_finite() or aim.length() < 1.0:
		return
	_cooldown_until_ms = Time.get_ticks_msec() + 650
	var body := JSON.stringify({"x": aim.x, "y": aim.y, "z": aim.z})
	_send("/story/love/throw", HTTPClient.METHOD_POST, body, _on_throw)

func refresh() -> void:
	if _token.is_empty():
		return
	_send("/story/love", HTTPClient.METHOD_GET, "", _on_status)

func apply_event(event: Dictionary) -> void:
	match str(event.get("subject", "")):
		"zone":
			var parsed: Variant = JSON.parse_string(str(event.get("body", "")))
			if parsed is Dictionary and parsed.get("x") != null:
				throw_landed.emit(
					Vector3(float(parsed.x), float(parsed.y), float(parsed.z)),
					float(parsed.get("ttl", 10.0))
				)
			refresh()
		"hit":
			refresh()
		"won":
			_active = false
			won.emit()
			refresh()
		"miss":
			pass

func _on_status(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	_active = data.get("active") == true
	_hits = int(data.get("hits", 0))
	_hits_to_win = maxi(1, int(data.get("hits_to_win", 10)))
	_zone_radius_m = float(data.get("zone_radius_m", 1.0))
	var enkidu: Variant = data.get("enkidu")
	if enkidu is Array and enkidu.size() == 3:
		_enkidu = Vector3(float(enkidu[0]), float(enkidu[1]), float(enkidu[2]))
	else:
		_enkidu = null
	_zones.clear()
	var raw: Variant = data.get("zones")
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary and entry.get("position") is Array and entry.position.size() == 3:
				_zones.append({
					"id": int(entry.get("id", 0)),
					"position": Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2])),
					"ttl": float(entry.get("ttl", 0)),
				})
	status_changed.emit(_active, _hits, _hits_to_win)

func _on_throw(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("position") is Array and data.position.size() == 3:
		throw_landed.emit(
			Vector3(float(data.position[0]), float(data.position[1]), float(data.position[2])),
			10.0
		)
	refresh()

func _send(path: String, method: HTTPClient.Method, body: String, handler: Callable) -> void:
	if _token.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 6.0
	request.max_redirects = 0
	request.body_size_limit = 65536
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
