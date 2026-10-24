extends StyleBox
## A panel of fired clay with a gold frame: two white nine-patches of the Fantasy UI Borders
## kit, tinted and drawn on top of each other in one style box. The thin pixel art is scaled up
## by whole pixels (nearest neighbour) so its lines stay sharp at 1600x900 as at 640x480.

var fill: Texture2D
var fill_color := Color.WHITE
var frame: Texture2D
var frame_color := Color.WHITE
## The nine-patch margin in pixels of the original texture.
var patch := 16
## How many screen pixels one texture pixel takes.
var pixel_scale := 2

static var _scaled := {}

func _init(fill_texture: Texture2D = null, fill_tint := Color.WHITE, frame_texture: Texture2D = null, frame_tint := Color.WHITE, margin := 16, scale := 2) -> void:
	fill = fill_texture
	fill_color = fill_tint
	frame = frame_texture
	frame_color = frame_tint
	patch = margin
	pixel_scale = scale

func _draw(canvas: RID, rect: Rect2) -> void:
	_nine_patch(canvas, rect, fill, fill_color)
	_nine_patch(canvas, rect, frame, frame_color)

func _nine_patch(canvas: RID, rect: Rect2, texture: Texture2D, color: Color) -> void:
	if texture == null or color.a <= 0.0:
		return
	var scaled := _scaled_texture(texture, pixel_scale)
	var corner := Vector2.ONE * float(patch * pixel_scale)
	# A panel smaller than two corners would fold the frame over itself.
	corner = corner.min(rect.size / 2.0)
	RenderingServer.canvas_item_add_nine_patch(
		canvas, rect, Rect2(Vector2.ZERO, scaled.get_size()), scaled.get_rid(), corner, corner,
		RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, color
	)

## A texture of the kit enlarged by whole pixels, for a NinePatchRect drawn like this box.
static func scaled(texture: Texture2D, scale: int) -> Texture2D:
	return _scaled_texture(texture, scale)

static func _scaled_texture(texture: Texture2D, scale: int) -> Texture2D:
	if scale <= 1:
		return texture
	var key := "%s@%d" % [texture.resource_path, scale]
	if not _scaled.has(key):
		var image := texture.get_image()
		if image == null:
			return texture
		if image.is_compressed():
			image.decompress()
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
		_scaled[key] = ImageTexture.create_from_image(image)
	return _scaled[key]
