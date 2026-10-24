extends SceneTree
## Smoke-checks the clay-tablet prologue: blank reverse split and flip helpers.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	var panel: CanvasLayer = preload("res://scripts/tablet_panel.gd").new()
	root.add_child(panel)
	await process_frame
	await process_frame
	_check(panel.has_method("present"), "tablet panel exposes present()")
	_check(panel.has_method("present_epilog"), "tablet panel exposes present_epilog()")
	_check(panel.get_node_or_null("Narrator") != null or panel.find_child("Narrator", true, false) != null, "narrator player exists")
	# Long carved string must split across two faces.
	var long := ""
	for _i in 80:
		long += String.chr(0x12000) + String.chr(0x121A0) + " "
	panel._begin("Test", long, "subtitle line for the hunter", "")
	await process_frame
	_check(panel.visible, "tablet is shown")
	_check(not str(panel._side_a).is_empty(), "front side has text")
	_check(str(panel._side_a).length() < long.length(), "overflow continues on the reverse")
	_check(str(panel._side_b).length() > 0, "reverse side receives the overflow")
	panel.hide_tablet()
	await process_frame
	_check(not panel.visible, "tablet hides")
	panel.queue_free()
	if _failures:
		quit(1)
	else:
		print("tablet_panel: ok")
		quit(0)
