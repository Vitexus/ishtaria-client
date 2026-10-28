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
	_check(not panel._faces[0].is_empty(), "front side has text")
	_check(panel._faces.size() >= 2 and not panel._faces[1].is_empty(), "overflow continues on the reverse")
	# No face holds more ruled rows than fit on it; a text too long for one tablet goes on to the next.
	for signs: int in [80, 400]:
		var text := ""
		for i in signs:
			text += String.chr(0x12000 + (i * 37) % 0x300) + (" " if i % 3 == 2 else "")
		panel._begin("Test", text, "", "")
		var fits: int = panel.rows_per_face(panel.LABEL_PIXEL_SIZE)
		var rows: Array = Array(panel._faces).map(func(face: String) -> int: return face.count("\n") + 1)
		_check(rows.all(func(count: int) -> bool: return count <= fits), "%d signs: every face fits: %s of %d" % [signs, rows, fits])
		_check(panel._carve_text == "".join(panel._faces), "carving runs over what the faces show")
		if signs == 400:
			_check(panel._faces.size() > 2, "a long text continues on a second tablet")
			# Carving into the third face slides a new tablet in; skipping shows the last face written.
			panel._apply_carve(panel._face_starts[1] + 1)
			panel._turning = false
			panel._face = 1
			panel._apply_carve(panel._face_starts[2] + 1)
			_check(panel._turning, "the full reverse sends the tablet away")
			panel._on_backdrop()
			_check(panel._face == panel._faces.size() - 1 and panel._dismiss.visible, "skipping ends on the last face")
			_check(panel._tablet_root.position.x == 0.0, "the last tablet stands in view")
	panel.hide_tablet()
	await process_frame
	_check(not panel.visible, "tablet hides")
	panel.queue_free()
	if _failures:
		quit(1)
	else:
		print("tablet_panel: ok")
		quit(0)
