extends CanvasLayer
## What the client shows while it stands still waiting for the world (terrain, environment, scenery, the avatar):
## a caption and the loading bar. It also fetches the `loading_marker` picture a story datadisk announces in
## GET /world `datadisks` and hands it to every bar through `LoadingBar.shared_marker`. The picture is public
## media, so no sign-in is needed. The caption is translated; the picture belongs to the disk.

const LoadingBar := preload("res://scripts/loading_bar.gd")
const MAX_IMAGE_BYTES := 1048576
const FLIGHT_SECONDS := 1.5

var _generation := 0
var _bar: Control
var _caption: Label
var _request: HTTPRequest
var _finishing := false
var _tween: Tween

func _ready() -> void:
	# Above the datadisk cover (layer 15), which is shown over the world while it loads.
	layer = 16
	visible = false
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 18)
	# Readable over any cover art.
	_caption.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_caption.add_theme_constant_override("outline_size", 6)
	add_child(_caption)
	# Near the bottom edge but above the HUD frame (about 140 px high), and over the cover's caption line.
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 0.0
	_caption.offset_right = 0.0
	_caption.offset_top = -224.0
	_caption.offset_bottom = -196.0
	_bar = LoadingBar.new()
	_bar.name = "Bar"
	add_child(_bar)
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 120.0
	_bar.offset_right = -120.0
	_bar.offset_top = -192.0
	_bar.offset_bottom = -144.0
	_update_caption()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_caption()

func _update_caption() -> void:
	if is_instance_valid(_caption):
		_caption.text = tr("Loading the world")

## A new wait begins: the bar may be shown again, even if the last one was finished.
func begin() -> void:
	hide_progress()
	_finishing = false

## Shows the bar at `fraction` (0 to 1); it is ignored while the bar is playing its ending.
func show_progress(fraction: float) -> void:
	if _finishing:
		return
	_bar.value = 100.0 * clampf(fraction, 0.0, 1.0)
	visible = true

## Hides the bar at once, without the ending (the connection was dropped, or there is nothing to wait for).
func hide_progress() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	visible = false
	if is_instance_valid(_bar):
		_bar.flight = 0.0
		_bar.track_alpha = 1.0
		_caption.modulate.a = 1.0

## The wait is over: the bar is full, then the disk's marker flies off toward the bottom right corner, growing as if
## it came at the viewer, until it has left the screen; without a marker the bar only fades. Once per wait.
func finish() -> void:
	if _finishing or not visible:
		return
	_finishing = true
	_bar.value = 100.0
	_tween = create_tween()
	_tween.tween_interval(0.25)
	if LoadingBar.shared_marker != null:
		_tween.set_parallel(true)
		_tween.tween_property(_bar, "flight", 1.0, FLIGHT_SECONDS).set_delay(0.25)
		_tween.tween_property(_bar, "track_alpha", 0.0, FLIGHT_SECONDS * 0.4).set_delay(0.25)
		_tween.tween_property(_caption, "modulate:a", 0.0, FLIGHT_SECONDS * 0.4).set_delay(0.25)
		_tween.chain().tween_callback(_end_finish)
	else:
		_tween.tween_property(_bar, "track_alpha", 0.0, 0.4)
		_tween.parallel().tween_property(_caption, "modulate:a", 0.0, 0.4)
		_tween.tween_callback(_end_finish)

func _end_finish() -> void:
	hide_progress()

func is_finishing() -> bool:
	return _finishing

## The marker URL path an announced disk gives, or "" (the first disk that has a well-formed one wins).
static func marker_path(disks: Variant) -> String:
	if not disks is Array:
		return ""
	for disk: Variant in disks:
		if not disk is Dictionary:
			continue
		var url: Variant = disk.get("loading_marker")
		if url is String and url.begins_with("/story/media/") and url.length() <= 220 and url.ends_with(".png") \
				and not (url.contains("..") or url.contains("//") or url.contains("?") or url.contains("#") or url.contains("%") or url.contains("\\")):
			return url
	return ""

## A server was connected: forgets the old picture and fetches the one its disks announce, if any.
func use(server_url: String, disks: Variant) -> void:
	forget()
	var path := marker_path(disks)
	if path.is_empty():
		return
	var generation := _generation
	_request = HTTPRequest.new()
	_request.timeout = 10.0
	_request.max_redirects = 0
	_request.body_size_limit = MAX_IMAGE_BYTES
	add_child(_request)
	var request := _request
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation or result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		LoadingBar.shared_marker = decode(body)
		_bar.queue_redraw()
	)
	if request.request(server_url + path) != OK:
		request.queue_free()

## Drops the picture and any fetch in flight (the connection was dropped).
func forget() -> void:
	_generation += 1
	if is_instance_valid(_request):
		_request.queue_free()
	_request = null
	LoadingBar.shared_marker = null

static func decode(body: PackedByteArray) -> Texture2D:
	var image := Image.new()
	if image.load_png_from_buffer(body) != OK or image.get_width() < 1 or image.get_height() < 1 \
			or image.get_width() > 1024 or image.get_height() > 1024:
		return null
	return ImageTexture.create_from_image(image)
