extends Control
## The progress bar of everything the client waits for. The finished part and the remaining part differ in colour
## (the engine's own look). A story datadisk may announce a `loading_marker` picture, which is then drawn on the
## bar at the current value, centred on the boundary between the two parts (the Gilgamesh disk uses the Faravahar,
## whose figure faces right, the way the bar fills). `value` runs from 0 to 100 like a ProgressBar's.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const BAR_HEIGHT := 14.0
const MARKER_HEIGHT := 40.0

## The picture of the connected server's disk, shared by every bar; null means the plain colour difference.
static var shared_marker: Texture2D

var value := 0.0:
	set(new_value):
		var clamped := clampf(new_value if is_finite(new_value) else 0.0, 0.0, 100.0)
		if clamped != value:
			value = clamped
			queue_redraw()
var done_color := UiTheme.GOLD
var remaining_color := UiTheme.CLAY_LIGHT
## 0 to 1: the marker's flight out of the picture at the end of loading (see `flight_rect`); 0 is the marker on the bar.
var flight := 0.0:
	set(new_flight):
		flight = clampf(new_flight, 0.0, 1.0)
		queue_redraw()
## Opacity of the track (finished and remaining part); the end of loading fades it while the marker flies.
var track_alpha := 1.0:
	set(new_alpha):
		track_alpha = clampf(new_alpha, 0.0, 1.0)
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160.0, MARKER_HEIGHT)

## Where the boundary between the two parts lies, from `track_left` to `track_right`.
static func boundary_x(track_left: float, track_right: float, percent: float) -> float:
	return lerpf(track_left, track_right, clampf(percent, 0.0, 100.0) / 100.0)

## Where the marker is `t` (0 to 1) into its flight: it leaves `start_centre` for the screen corner `corner` and grows
## from `base_size` to `end_scale` times that, as if it came toward the viewer; it ends with its top left corner on
## `corner`, so that it is wholly beyond the bottom right edge. Eased in: slow at first, then fast.
static func flight_rect(start_centre: Vector2, base_size: Vector2, corner: Vector2, end_scale: float, t: float) -> Rect2:
	var eased := clampf(t, 0.0, 1.0)
	eased *= eased
	var size := base_size * lerpf(1.0, end_scale, eased)
	var centre := start_centre.lerp(corner, eased) + size * 0.5 * eased
	return Rect2(centre - size * 0.5, size)

## Size of the marker as drawn: `MARKER_HEIGHT` tall with its own aspect ratio.
static func marker_size(texture: Texture2D) -> Vector2:
	if texture == null or texture.get_height() < 1:
		return Vector2.ZERO
	return Vector2(MARKER_HEIGHT * float(texture.get_width()) / float(texture.get_height()), MARKER_HEIGHT)

func _draw() -> void:
	var marker := shared_marker
	var marker_extent := marker_size(marker)
	# The picture is centred on the boundary, so the track leaves half of it free at each end.
	var margin := marker_extent.x * 0.5
	var left := margin
	var right := maxf(size.x - margin, left + 1.0)
	var top := size.y - BAR_HEIGHT
	var at := boundary_x(left, right, value)
	if track_alpha > 0.0:
		draw_rect(Rect2(left, top, right - left, BAR_HEIGHT), Color(remaining_color, remaining_color.a * track_alpha))
		draw_rect(Rect2(left, top, at - left, BAR_HEIGHT), Color(done_color, done_color.a * track_alpha))
		draw_rect(Rect2(left, top, right - left, BAR_HEIGHT), Color(UiTheme.CLAY_DARK, track_alpha), false, 2.0)
	if marker != null:
		# It sits on the bar, its lower edge on the bar's middle, so that the wings reach over both parts.
		var rect := Rect2(at - margin, top + BAR_HEIGHT * 0.5 - marker_extent.y, marker_extent.x, marker_extent.y)
		if flight > 0.0:
			var viewport := get_viewport_rect().size
			var corner := viewport - get_global_transform().origin
			rect = flight_rect(rect.get_center(), marker_extent, corner, 2.2 * maxf(viewport.x, viewport.y) / maxf(marker_extent.x, 1.0), flight)
		draw_texture_rect(marker, rect, false)
