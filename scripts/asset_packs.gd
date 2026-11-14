extends Node
## Downloads the asset packs of the browser build in the background. The page starts from the small `index.pck` (code, interface,
## characters, the Kenney and Quaternius art); the 0 A.D. art (`zeroad.pck`, nine tenths of the data) arrives after the first screen,
## while the player is still typing the server address or signing in. The packs are listed in `asset-packs.json` next to the page
## (name, file, size, SHA-256; made by `tools/web-packs.sh`), kept in the browser's storage as `user://packs/<name>-<hash>.pck`,
## so that the next visit downloads nothing, and mounted with `ProjectSettings.load_resource_pack`. The desktop builds carry
## everything in their one package: there `is_ready()` is true at once and nothing is fetched.

signal progress(fraction: float)
## All packs are mounted (`ok`), or a download failed for good after the retries.
signal finished(ok: bool)

const MANIFEST_NAME := "asset-packs.json"
const PACKS_DIR := "user://packs"
## A resource of the 0 A.D. pack: when it can be loaded, the pack is mounted (or was never separate).
const SENTINEL := "res://assets/zeroad/flora/palm_date_a.glb"
const KNOWN_PACKS := ["zeroad"]
const MAX_PACK_BYTES := 1073741824
const MAX_ATTEMPTS := 3
const RETRY_SECONDS := 3.0

var base_url := ""
var _ready_state := false
var _failed := false
var _fraction := 0.0
var _jobs: Array[Dictionary] = []
var _total_bytes := 0
var _done_bytes := 0
var _request: HTTPRequest
var _attempt := 0

## True when the art the world needs can be loaded.
func is_ready() -> bool:
	return _ready_state

func has_failed() -> bool:
	return _failed

## Share of the download that is done, 0 to 1.
func fraction() -> float:
	return _fraction

## Where the packs of the page lie: the directory of the page itself.
static func page_base_url() -> String:
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		var value: Variant = JavaScriptBridge.eval("new URL('.', document.baseURI).href")
		if value is String:
			return value
	return ""

## The packs of a manifest that are valid: known name, plain file name, plausible size, a SHA-256. Anything else is dropped.
static func parse_manifest(text: String) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("packs") is Dictionary:
		return jobs
	for name: Variant in parsed.packs:
		var entry: Variant = parsed.packs[name]
		if not name is String or not name in KNOWN_PACKS or not entry is Dictionary:
			continue
		var file: Variant = entry.get("file")
		var size: Variant = entry.get("bytes")
		var hash: Variant = entry.get("sha256")
		if not file is String or not file.is_valid_filename() or not file.ends_with(".pck"):
			continue
		if not (size is float or size is int) or size <= 0 or size > MAX_PACK_BYTES or float(int(size)) != float(size):
			continue
		if not hash is String or hash.length() != 64 or not hash.is_valid_hex_number(false):
			continue
		jobs.append({"name": name, "file": file, "bytes": int(size), "sha256": hash.to_lower(), "path": "%s/%s-%s.pck" % [PACKS_DIR, name, hash.substr(0, 12).to_lower()]})
	return jobs

func start() -> void:
	if _ready_state or not _jobs.is_empty() or is_instance_valid(_request):
		return
	if ResourceLoader.exists(SENTINEL):
		_finish(true)
		return
	if not OS.has_feature("web") and base_url.is_empty():
		# A desktop build without the art is a broken build; there is nothing to download from.
		_finish(false)
		return
	if base_url.is_empty():
		base_url = page_base_url()
	_attempt = 0
	_fetch_manifest()

func _fetch_manifest() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	add_child(_request)
	_request.request_completed.connect(_on_manifest)
	if _request.request(base_url + MANIFEST_NAME) != OK:
		_retry_or_fail()

func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_retry_or_fail()
		return
	_jobs = parse_manifest(body.get_string_from_utf8())
	if _jobs.is_empty():
		_finish(false)
		return
	DirAccess.make_dir_recursive_absolute(PACKS_DIR)
	_total_bytes = 0
	for job in _jobs:
		_total_bytes += job.bytes
	_attempt = 0
	_next_job()

func _next_job() -> void:
	_done_bytes = 0
	for job in _jobs:
		if job.get("mounted", false):
			_done_bytes += job.bytes
			continue
		if FileAccess.file_exists(job.path) and _file_size(job.path) == job.bytes:
			if _mount(job):
				_done_bytes += job.bytes
				continue
			DirAccess.remove_absolute(job.path)
		_download(job)
		return
	_fraction = 1.0
	progress.emit(1.0)
	_finish(ResourceLoader.exists(SENTINEL))

func _download(job: Dictionary) -> void:
	_request = HTTPRequest.new()
	_request.download_file = job.path + ".part"
	_request.timeout = 0.0
	add_child(_request)
	_request.request_completed.connect(_on_downloaded.bind(job))
	if _request.request(base_url + job.file) != OK:
		_request.queue_free()
		_retry_or_fail()

func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, job: Dictionary) -> void:
	_request.queue_free()
	var part: String = job.path + ".part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or _file_size(part) != job.bytes or FileAccess.get_sha256(part) != job.sha256:
		DirAccess.remove_absolute(part)
		_retry_or_fail()
		return
	if DirAccess.rename_absolute(part, job.path) != OK or not _mount(job):
		DirAccess.remove_absolute(part)
		DirAccess.remove_absolute(job.path)
		_retry_or_fail()
		return
	_forget_old_versions(job)
	_attempt = 0
	_next_job()

func _mount(job: Dictionary) -> bool:
	if not ProjectSettings.load_resource_pack(job.path, true):
		return false
	job.mounted = true
	return true

## A pack of an older build (another hash) is no use any more; it would only fill the browser's storage.
func _forget_old_versions(job: Dictionary) -> void:
	var directory := DirAccess.open(PACKS_DIR)
	if directory == null:
		return
	for entry in directory.get_files():
		if entry.begins_with(job.name + "-") and PACKS_DIR + "/" + entry != job.path:
			directory.remove(entry)

func _retry_or_fail() -> void:
	_attempt += 1
	if _attempt >= MAX_ATTEMPTS:
		_finish(false)
		return
	await get_tree().create_timer(RETRY_SECONDS).timeout
	if _jobs.is_empty():
		_fetch_manifest()
	else:
		_next_job()

func _finish(ok: bool) -> void:
	_ready_state = ok
	_failed = not ok
	finished.emit(ok)

## Gives the retry button a clean start after a failure.
func retry() -> void:
	if _ready_state or is_instance_valid(_request):
		return
	_failed = false
	_attempt = 0
	_jobs.clear()
	start()

func _process(_delta: float) -> void:
	if _ready_state or not is_instance_valid(_request) or _request.download_file.is_empty() or _total_bytes <= 0:
		return
	var value := clampf(float(_done_bytes + _request.get_downloaded_bytes()) / float(_total_bytes), 0.0, 1.0)
	if value != _fraction:
		_fraction = value
		progress.emit(value)

static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length
