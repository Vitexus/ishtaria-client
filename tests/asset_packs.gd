extends SceneTree
## The asset packs of the browser build: what a manifest may name, and that a desktop build is ready at once.
## Headless: `make test-asset-packs`.

const PACKS := preload("res://scripts/asset_packs.gd")
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", label)

func _manifest(entry: Dictionary, name := "zeroad") -> String:
	return JSON.stringify({"version": 1, "packs": {name: entry}})

func _run() -> void:
	var hash := "ab".repeat(32)
	var good := {"file": "zeroad.pck", "bytes": 1000, "sha256": hash}
	var jobs: Array[Dictionary] = PACKS.parse_manifest(_manifest(good))
	_check(jobs.size() == 1 and jobs[0].path == "user://packs/zeroad-abababababab.pck", "a valid pack is accepted and cached under a name with its hash")
	_check(PACKS.parse_manifest("not json").is_empty(), "garbage gives no packs")
	_check(PACKS.parse_manifest(JSON.stringify({"version": 2, "packs": {}})).is_empty(), "another version is refused")
	_check(PACKS.parse_manifest(_manifest(good, "evil")).is_empty(), "an unknown pack name is dropped")
	for bad: Dictionary in [
			{"file": "../zeroad.pck", "bytes": 1000, "sha256": hash}, {"file": "a/b.pck", "bytes": 1000, "sha256": hash},
			{"file": "zeroad.exe", "bytes": 1000, "sha256": hash}, {"file": "zeroad.pck", "bytes": 0, "sha256": hash},
			{"file": "zeroad.pck", "bytes": 2000000000, "sha256": hash}, {"file": "zeroad.pck", "bytes": 10.5, "sha256": hash},
			{"file": "zeroad.pck", "bytes": 1000, "sha256": "abc"}, {"file": "zeroad.pck", "bytes": 1000, "sha256": "zz".repeat(32)}]:
		_check(PACKS.parse_manifest(_manifest(bad)).is_empty(), "a bad entry is dropped: %s" % JSON.stringify(bad))
	var packs: Node = PACKS.new()
	root.add_child(packs)
	packs.start()
	_check(packs.is_ready() and not packs.has_failed(), "a build that carries the art is ready at once and fetches nothing")
	print("asset packs: ", "FAILED (%d)" % _failures if _failures > 0 else "ok")
	quit(1 if _failures > 0 else 0)
