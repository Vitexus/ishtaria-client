extends SceneTree
## The loading bar: where its marker sits, what a disk may announce and what the client decodes.
## Headless: `make test-loading-bar`.

const BAR := preload("res://scripts/loading_bar.gd")
const OVERLAY := preload("res://scripts/loading_overlay.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", label)

func _run() -> void:
	_check(is_equal_approx(BAR.boundary_x(20.0, 220.0, 0.0), 20.0), "empty bar: boundary at the left end")
	_check(is_equal_approx(BAR.boundary_x(20.0, 220.0, 50.0), 120.0), "half: boundary in the middle")
	_check(is_equal_approx(BAR.boundary_x(20.0, 220.0, 100.0), 220.0), "full: boundary at the right end")
	_check(is_equal_approx(BAR.boundary_x(20.0, 220.0, 400.0), 220.0), "over 100 is clamped")
	_check(BAR.marker_size(null) == Vector2.ZERO, "no marker: no size")
	var image := Image.create(256, 121, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var size: Vector2 = BAR.marker_size(texture)
	_check(is_equal_approx(size.y, BAR.MARKER_HEIGHT) and is_equal_approx(size.x / size.y, 256.0 / 121.0), "the marker keeps its aspect ratio")

	# The marker's flight: it starts on the bar and ends wholly beyond the bottom right corner, bigger all the way.
	var base := Vector2(85.0, 40.0)
	var corner := Vector2(1280.0, 720.0)
	var start: Rect2 = BAR.flight_rect(Vector2(600.0, 500.0), base, corner, 30.0, 0.0)
	_check(start.size.is_equal_approx(base) and start.get_center().is_equal_approx(Vector2(600.0, 500.0)), "flight starts on the bar")
	var middle: Rect2 = BAR.flight_rect(Vector2(600.0, 500.0), base, corner, 30.0, 0.7)
	_check(middle.size.x > base.x and middle.get_center().x > 600.0 and middle.get_center().y > 500.0, "it grows and moves toward the corner")
	var end: Rect2 = BAR.flight_rect(Vector2(600.0, 500.0), base, corner, 30.0, 1.0)
	_check(end.position.is_equal_approx(corner) and not Rect2(Vector2.ZERO, corner).intersects(end), "it ends wholly beyond the bottom right")
	var earlier := 0.0
	var grows := true
	for step in range(1, 11):
		var width: float = BAR.flight_rect(Vector2(600.0, 500.0), base, corner, 30.0, step / 10.0).size.x
		grows = grows and width >= earlier
		earlier = width
	_check(grows, "it never shrinks")

	var bar := BAR.new()
	bar.value = 250.0
	_check(is_equal_approx(bar.value, 100.0), "value is clamped to 100")
	bar.value = NAN
	_check(is_equal_approx(bar.value, 0.0), "a non-finite value is zero")
	BAR.shared_marker = null
	root.add_child(bar)
	bar.size = Vector2(400.0, 48.0)
	bar.value = 40.0
	await process_frame
	BAR.shared_marker = texture
	bar.queue_redraw()
	await process_frame
	_check(true, "draws with and without a marker")
	BAR.shared_marker = null

	_check(OVERLAY.marker_path([{"loading_marker": "/story/media/g/media/loading/f.png"}]) == "/story/media/g/media/loading/f.png", "a disk's marker is accepted")
	_check(OVERLAY.marker_path([{"id": "x"}, {"loading_marker": "/story/media/g/a.png"}]) == "/story/media/g/a.png", "the first disk with one wins")
	for bad: Variant in ["/etc/passwd.png", "/story/media/../x.png", "/story/media/a.jpg", "/story/media/a.png?x=1", "/story/media//a.png", 5, null]:
		_check(OVERLAY.marker_path([{"loading_marker": bad}]) == "", "rejected: %s" % str(bad))
	_check(OVERLAY.marker_path("nope") == "" and OVERLAY.marker_path([]) == "", "no disks, no marker")
	_check(OVERLAY.decode(PackedByteArray([1, 2, 3])) == null, "garbage is not a picture")
	_check(OVERLAY.decode(image.save_png_to_buffer()) != null, "a png decodes")
	print("loading bar: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
