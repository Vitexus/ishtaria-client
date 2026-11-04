extends SceneTree
## The address a new install connects to: the server written into release_server.txt when a release is built, else the
## local development server. Run from a source checkout (res:// must be writable).

const MAIN := preload("res://scripts/main.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _write(text: String) -> void:
	var file := FileAccess.open(MAIN.RELEASE_SERVER_FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _run() -> void:
	# a release_server.txt left by a build is put back afterwards
	var kept := ""
	var had_file := FileAccess.file_exists(MAIN.RELEASE_SERVER_FILE)
	if had_file:
		kept = FileAccess.get_file_as_string(MAIN.RELEASE_SERVER_FILE)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAIN.RELEASE_SERVER_FILE))
	_check(MAIN.default_server_url() == MAIN.DEFAULT_SERVER_URL, "a source checkout (no release_server.txt) uses the local development server")
	_write("https://world.example/api\n")
	_check(MAIN.default_server_url() == "https://world.example/api", "the server of the release is the default, trailing newline dropped")
	_write("  https://world.example:7400/  ")
	_check(MAIN.default_server_url() == "https://world.example:7400", "spaces and a trailing slash are dropped")
	_write("world.example")
	_check(MAIN.default_server_url() == "http://world.example", "an address without a scheme is read as the other sources read it")
	_write("javascript:alert(1)")
	_check(MAIN.default_server_url() == MAIN.DEFAULT_SERVER_URL, "a malformed address falls back to the local development server")
	_write("")
	_check(MAIN.default_server_url() == MAIN.DEFAULT_SERVER_URL, "an empty file falls back to the local development server")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MAIN.RELEASE_SERVER_FILE))
	if had_file:
		_write(kept)
	if _failures > 0:
		quit(1)
		return
	print("default server checks passed")
	quit(0)
