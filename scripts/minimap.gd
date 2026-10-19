extends CanvasLayer
## Minimap showing a top-down view of the area around the player.
## Displays the player position, direction, NPCs, places, and objects with icons and names.

const RPG := "res://assets/kenney/ui-rpg/PNG/"

# Minimap sizes: small mode (always visible corner) and big mode (full screen)
const MINIMAP_SIZE_SMALL := 128

# Margin from edge for small mode
const MARGIN := 16

# Scale indicator
const SCALE_INDICATOR_SIZE := 14
const SCALE_INDICATOR_COLOR := Color(0.8, 0.8, 0.8)
## Half zoom still shows ~400 m; big-map mode allows a much wider view so a city disk fits.
const MIN_ZOOM := 0.5
const MIN_ZOOM_BIG := 0.08
const MAX_ZOOM := 2.0
const ZOOM_STEP := 0.25

# Colors with good contrast
const PLAYER_COLOR := Color(1.0, 1.0, 1.0)
const NORTH_COLOR := Color(1.0, 0.35, 0.3)
const BACKGROUND_COLOR := Color(0.08, 0.1, 0.12, 0.85)
const ROAD_COLOR := Color(0.62, 0.55, 0.42, 0.95)
const BUILDING_COLOR := Color(0.55, 0.62, 0.60, 0.95)
const WATER_COLOR := Color(0.18, 0.45, 0.65, 0.92)
const LEGEND_SWATCH := 12
const NPC_COLOR := Color(1.0, 0.65, 0.0)
const PLACE_COLOR := Color(0.2, 0.8, 1.0)
const OBJECT_COLOR := Color(0.4, 1.0, 0.4)
const QUEST_COLOR := Color(1.0, 0.4, 0.8)
const LABEL_COLOR := Color(1.0, 1.0, 1.0)
const GOAL_COLOR := Color(1.0, 0.85, 0.3)
const GOAL_CLOSER_COLOR := Color(0.45, 1.0, 0.5)
const GOAL_FARTHER_COLOR := Color(1.0, 0.5, 0.35)
## The distance to a goal is compared with the one this many seconds ago to tell closer from farther.
const TREND_SECONDS := 1.5
## Change in metres that counts as moving towards or away from a goal.
const TREND_MIN_M := 1.0

# View radius in meters
const VIEW_RADIUS_M := 200.0

# Icon and label sizes
const ICON_SIZE := 14
const LABEL_SIZE := 10

var environment: Node3D
var player_position: Vector3 = Vector3.ZERO
var player_direction: Vector3 = Vector3.FORWARD
var player_heading: Vector3 = Vector3.RIGHT
var _zoom_level: float = 1.0
var _big_mode: bool = false

# Entity data: Array of {id: String, name: String, kind: String, position: Vector3, is_quest: bool}
var _entities: Array[Dictionary] = []

# Roads and buildings of the generated places: {kind: String, position: Vector3 (metres),
# yaw: float, size: Vector2 (metres)}.
var _props: Array[Dictionary] = []

# The environment's baked water picture: {texture, centre, tangent, forward, metres_per_pixel}.
var _water_map: Dictionary = {}

var _minimap_panel: Control
var _minimap_container: SubViewportContainer
var _minimap_viewport: SubViewport
var _render_node: Node2D
var _background: Sprite2D
var _water_sprite: Sprite2D
var _prop_overlay: PropOverlay
var _legend: Control
var _player_marker: Sprite2D
var _north_marker: Sprite2D
var _border: ColorRect
var _scale_bar: ColorRect
var _scale_label: Label
var _goal_overlay: GoalOverlay

# Entity markers: Dictionary of entity_id -> {marker: Sprite2D, label: Sprite2D, position: Vector3, kind: String, name: String}
var _entity_markers: Dictionary = {}

# Texture caches to avoid recreating textures every frame
var _icon_texture_cache: Dictionary = {}
var _letter_texture_cache: Dictionary = {}

func _get_size() -> Vector2:
	if _big_mode:
		return get_viewport().get_visible_rect().size
	return Vector2(MINIMAP_SIZE_SMALL, MINIMAP_SIZE_SMALL)


## Screen pixels for one metre: the view radius fits the shorter side of the map.
func _pixels_per_metre() -> float:
	var size := _get_size()
	return minf(size.x, size.y) / 2.0 / VIEW_RADIUS_M * _zoom_level


func _apply_size() -> void:
	var size := _get_size()
	if _big_mode:
		_minimap_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		_minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_minimap_panel.offset_right = -MARGIN
		_minimap_panel.offset_left = -MARGIN - size.x
		_minimap_panel.offset_top = MARGIN
		_minimap_panel.offset_bottom = MARGIN + size.y
	_minimap_container.position = Vector2.ZERO
	_minimap_container.size = size
	_background.texture = _create_solid_color_texture(BACKGROUND_COLOR, int(size.x), int(size.y))
	_background.position = size / 2.0
	_player_marker.position = size / 2.0
	_north_marker.position = Vector2(size.x / 2.0, minf(size.y * 0.1, 24.0))
	_border.position = Vector2(-2, -2)
	_border.size = size + Vector2(4, 4)
	_legend.visible = _big_mode
	_legend.position = Vector2(12.0, 12.0)
	_update_scale_bar()


func _update_scale_bar() -> void:
	var size := _get_size()
	var length := 50.0 * _pixels_per_metre()
	_scale_bar.size = Vector2(length, 3)
	_scale_bar.position = Vector2(8, size.y - 10)
	_scale_label.text = "50 m"
	_scale_label.position = Vector2(8, size.y - 28)


func _ready() -> void:
	layer = 3
	
	# Create minimap panel
	_minimap_panel = Control.new()
	_minimap_panel.name = "MinimapPanel"
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	add_child(_minimap_panel)
	
	# Create SubViewportContainer for displaying the viewport texture
	_minimap_container = SubViewportContainer.new()
	_minimap_container.name = "MinimapContainer"
	_minimap_container.stretch = true
	_minimap_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimap_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_minimap_panel.add_child(_minimap_container)
	
	# Create SubViewport for rendering with fixed size
	_minimap_viewport = SubViewport.new()
	_minimap_viewport.name = "MinimapViewport"
	_minimap_viewport.transparent_bg = true
	_minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_minimap_container.add_child(_minimap_viewport)
	
	# Create 2D scene for minimap
	_render_node = Node2D.new()
	_render_node.name = "MinimapScene"
	_minimap_viewport.add_child(_render_node)
	
	# Background
	_background = Sprite2D.new()
	_background.name = "Background"
	_background.texture = _create_solid_color_texture(BACKGROUND_COLOR, MINIMAP_SIZE_SMALL, MINIMAP_SIZE_SMALL)
	_background.position = Vector2(MINIMAP_SIZE_SMALL / 2, MINIMAP_SIZE_SMALL / 2)
	_background.z_index = -10
	_render_node.add_child(_background)

	# The baked water picture (streams, lakes and the sea) of the region, placed and turned
	# every frame to the player's view.
	_water_sprite = Sprite2D.new()
	_water_sprite.name = "Water"
	_water_sprite.z_index = -8
	_water_sprite.visible = false
	_render_node.add_child(_water_sprite)

	# Roads and buildings of the generated places.
	_prop_overlay = PropOverlay.new()
	_prop_overlay.name = "Props"
	_prop_overlay.z_index = -5
	_render_node.add_child(_prop_overlay)

	_goal_overlay = GoalOverlay.new()
	_goal_overlay.name = "Goals"
	_goal_overlay.z_index = 8
	_render_node.add_child(_goal_overlay)

	# Player marker (arrow with better visibility)
	_player_marker = Sprite2D.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.texture = _create_player_arrow()
	_player_marker.position = Vector2(MINIMAP_SIZE_SMALL / 2, MINIMAP_SIZE_SMALL / 2)
	_player_marker.z_index = 10
	_render_node.add_child(_player_marker)
	
	# North direction marker (N)
	_north_marker = Sprite2D.new()
	_north_marker.name = "NorthMarker"
	_north_marker.texture = _create_letter_texture("N", NORTH_COLOR)
	_north_marker.position = Vector2(MINIMAP_SIZE_SMALL / 2, MINIMAP_SIZE_SMALL * 0.1)
	_north_marker.z_index = 5
	_render_node.add_child(_north_marker)
	
	# Add scale bar (visual scale indicator)
	_scale_bar = ColorRect.new()
	_scale_bar.name = "ScaleBar"
	_scale_bar.color = SCALE_INDICATOR_COLOR
	_scale_bar.z_index = 5
	_minimap_panel.add_child(_scale_bar)
	
	# Add scale label
	_scale_label = Label.new()
	_scale_label.name = "ScaleLabel"
	_scale_label.text = "100m"
	_scale_label.self_modulate = SCALE_INDICATOR_COLOR
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scale_label.position = Vector2(0, 2)
	_minimap_panel.add_child(_scale_label)
	
	# Add border
	_border = ColorRect.new()
	_border.name = "Border"
	_border.color = Color(0.2, 0.2, 0.2, 0.8)
	_border.position = Vector2(-2, -2)
	_border.show_behind_parent = true
	_minimap_panel.add_child(_border)

	# Legend of the big map: what the water, road and building colours mean.
	_legend = HBoxContainer.new()
	_legend.name = "Legend"
	_legend.add_theme_constant_override("separation", 8)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in [["water", "Water"], ["road", "Road"], ["building", "Building"]]:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(LEGEND_SWATCH, LEGEND_SWATCH)
		swatch.color = WATER_COLOR if entry[0] == "water" else (ROAD_COLOR if entry[0] == "road" else BUILDING_COLOR)
		_legend.add_child(swatch)
		var label := Label.new()
		label.text = entry[1]
		label.add_theme_font_size_override("font_size", 11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_legend.add_child(label)
	_minimap_panel.add_child(_legend)

	# Initially visible in small mode
	_minimap_panel.show()
	_minimap_container.show()
	
	# Apply initial size
	_apply_size()


func _process(delta: float) -> void:
	_update_minimap()


func set_environment(env: Node3D) -> void:
	environment = env

## Roads and buildings to draw, from the environment's generated places.
func set_props(props: Array[Dictionary]) -> void:
	_props = props

## The environment's baked water picture of the region (see `surface_environment.water_map`).
func set_water_map(map: Dictionary) -> void:
	_water_map = map
	_water_sprite.texture = map.get("texture") if not map.is_empty() else null
	_water_sprite.visible = not map.is_empty()


func set_player_position(pos: Vector3) -> void:
	player_position = pos


func set_player_orientation(direction: Vector3, heading: Vector3) -> void:
	player_direction = direction
	player_heading = heading


func set_entities(entities: Array[Dictionary]) -> void:
	# Only rebuild markers if entities actually changed
	var entities_changed := false
	if _entities.size() != entities.size():
		entities_changed = true
	else:
		for i in range(_entities.size()):
			if not _entities[i] == entities[i]:
				entities_changed = true
				break
	
	if entities_changed:
		_entities = entities.duplicate()
		_update_entity_markers()


func is_big_mode() -> bool:
	return _big_mode

func toggle_visibility() -> void:
	_big_mode = not _big_mode
	# Reset zoom when switching modes
	_zoom_level = 1.0
	_update_zoom()
	_apply_size()


func zoom_in() -> void:
	_zoom_level = min(_zoom_level + ZOOM_STEP, MAX_ZOOM)
	_update_zoom()


func zoom_out() -> void:
	var floor_zoom := MIN_ZOOM_BIG if _big_mode else MIN_ZOOM
	_zoom_level = max(_zoom_level - ZOOM_STEP, floor_zoom)
	_update_zoom()


func _update_zoom() -> void:
	_update_scale_bar()


func _update_entity_markers() -> void:
	# Clear existing entity markers that are no longer present
	var current_ids: Array = []
	for entity: Dictionary in _entities:
		current_ids.append(entity.get("id", ""))
	
	for entity_id: String in _entity_markers.keys():
		if not current_ids.has(entity_id):
			var entry: Dictionary = _entity_markers[entity_id]
			if entry.has("marker") and entry["marker"] != null:
				entry["marker"].queue_free()
			if entry.has("label") and entry["label"] != null:
				entry["label"].queue_free()
			_entity_markers.erase(entity_id)
	
	# Create or update markers for each entity
	for entity: Dictionary in _entities:
		var entity_id: String = entity.get("id", "")
		var name: String = entity.get("name", "")
		var kind: String = entity.get("kind", "object")
		var position: Vector3 = entity.get("position", Vector3.ZERO)
		var is_quest: bool = entity.get("is_quest", false)
		
		# If marker already exists, just update its data
		if _entity_markers.has(entity_id):
			var entry: Dictionary = _entity_markers[entity_id]
			entry["position"] = position
			entry["is_quest"] = is_quest
			# Update icon if kind changed
			if entry.get("kind") != kind:
				entry["kind"] = kind
				entry["name"] = name
				entry["marker"].texture = _get_entity_icon_texture(kind)
				entry["label"].texture = _get_letter_texture(name.substr(0, 1).to_upper())
			continue
		
		# Create new marker
		var marker: Sprite2D = Sprite2D.new()
		marker.name = "EntityIcon_" + entity_id
		marker.texture = _get_entity_icon_texture(kind)
		marker.z_index = 1
		_render_node.add_child(marker)
		
		# Create name label as a Sprite2D with pre-rendered text
		var label: Sprite2D = Sprite2D.new()
		label.name = "EntityLabel_" + entity_id
		var label_char: String = name.substr(0, 1).to_upper() if not name.is_empty() else "?"
		label.texture = _get_letter_texture(label_char)
		label.z_index = 2
		label.visible = _zoom_level >= 0.75
		_render_node.add_child(label)
		
		_entity_markers[entity_id] = {
			"marker": marker,
			"label": label,
			"position": position,
			"is_quest": is_quest,
			"kind": kind,
			"name": name
		}


## Tangent plane at the player: `up` is away from the planet's centre, `forward` the way the
## player faces, `right` to their right. The map shows forward at the top, like the quest compass.
func _tangent_basis() -> Dictionary:
	var up: Vector3 = player_direction.normalized() if player_direction.length() > 0.1 else Vector3.UP
	var forward: Vector3 = player_heading - up * up.dot(player_heading)
	if forward.length() < 0.001:
		forward = up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.9 else up.cross(Vector3.FORWARD)
	forward = forward.normalized()
	return {"up": up, "forward": forward, "right": forward.cross(up)}


## Metres on the map (x right, y down) of an offset from the player.
static func _to_map(offset: Vector3, basis: Dictionary) -> Vector2:
	return Vector2(offset.dot(basis.right), -offset.dot(basis.forward))


func _update_minimap() -> void:
	var size := _get_size()
	var centre := size / 2.0
	var scale_px := _pixels_per_metre()
	var basis := _tangent_basis()
	# The player always points up: the map turns with the player.
	_player_marker.rotation = 0.0
	# The N sits on the rim in the direction of geographic north.
	var up: Vector3 = basis.up
	var north: Vector3 = Vector3.UP - up * up.dot(Vector3.UP)
	if north.length() > 0.001:
		var dir := _to_map(north.normalized(), basis)
		_north_marker.position = centre + dir * (minf(size.x, size.y) / 2.0 - 10.0)
		_north_marker.visible = true
	else:
		_north_marker.visible = false

	var goals: Array[Dictionary] = []
	_update_water(size, centre, scale_px, basis)
	_prop_overlay.update_props(_props, size, scale_px, player_position, basis)
	if player_position.length() > 0:
		for entity_id: String in _entity_markers:
			var entry: Dictionary = _entity_markers[entity_id]
			var marker: Sprite2D = entry["marker"]
			var label: Sprite2D = entry["label"]
			var relative_pos: Vector3 = entry["position"] - player_position
			var distance := relative_pos.length()
			if entry.get("is_quest", false):
				goals.append({"id": entity_id, "offset": _to_map(relative_pos, basis), "distance": distance})
			# Only show entities within the view radius
			if distance > VIEW_RADIUS_M:
				marker.visible = false
				label.visible = false
				continue
			marker.visible = true
			label.visible = _zoom_level >= 0.75
			var point := centre + _to_map(relative_pos, basis) * scale_px
			marker.position = point
			label.position = point + Vector2(0, 10)
	_goal_overlay.update_goals(goals, size, scale_px, _now())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Places and turns the baked water picture so it lines up with the entity markers: the bake
## frame's tangent axis decides the rotation, its centre the position, and one baked metre
## is `scale_px` screen pixels.
func _update_water(size: Vector2, centre: Vector2, scale_px: float, basis: Dictionary) -> void:
	if _water_map.is_empty() or not is_instance_valid(_water_sprite.texture):
		return
	var world_centre: Vector3 = _water_map.centre
	_water_sprite.position = centre + _to_map(world_centre - player_position, basis) * scale_px
	_water_sprite.rotation = _to_map(_water_map.tangent, basis).angle()
	_water_sprite.scale = Vector2.ONE * scale_px * float(_water_map.metres_per_pixel)


# Texture getter functions with caching

func _get_entity_icon_texture(kind: String) -> Texture2D:
	var cache_key: String = "icon_" + kind.to_lower()
	if _icon_texture_cache.has(cache_key):
		return _icon_texture_cache[cache_key]
	
	var texture: Texture2D = _create_entity_icon(kind, _get_kind_color(kind))
	_icon_texture_cache[cache_key] = texture
	return texture


func _get_letter_texture(letter: String) -> Texture2D:
	if letter.length() == 0:
		letter = "?"
	letter = letter.to_upper()
	
	var cache_key: String = "letter_" + letter
	if _letter_texture_cache.has(cache_key):
		return _letter_texture_cache[cache_key]
	
	var texture: Texture2D = _create_letter_texture(letter, LABEL_COLOR)
	_letter_texture_cache[cache_key] = texture
	return texture


func _get_kind_color(kind: String) -> Color:
	match kind.to_lower():
		"npc", "character":
			return NPC_COLOR
		"place", "landmark", "building":
			return PLACE_COLOR
		"quest":
			return QUEST_COLOR
		_:
			return OBJECT_COLOR


# Texture creation functions

func _create_player_arrow() -> Texture2D:
	var width: int = 16
	var height: int = 32
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	var center: int = width / 2
	
	# Arrow head - filled triangle at top (pointing up in 2D = north in world)
	for y in range(0, 10):
		var half_width: int = 7 - y * 0.6
		if half_width < 1:
			half_width = 1
		for x in range(center - half_width, center + half_width + 1):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, PLAYER_COLOR)
	
	# Arrow shaft
	for y in range(10, 24):
		for x in range(center - 2, center + 3):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, PLAYER_COLOR)
	
	# Arrow base
	for y in range(24, height):
		for x in range(center - 1, center + 2):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, PLAYER_COLOR)
	
	return ImageTexture.create_from_image(image)


func _create_solid_color_texture(color: Color, width: int, height: int) -> Texture2D:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _create_letter_texture(letter: String, color: Color) -> Texture2D:
	var size: int = LABEL_SIZE
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	if letter.length() == 0:
		letter = "?"
	
	# Use simple but recognizable letter shapes
	# Each letter is drawn with filled pixels in a 10x10 grid
	var first_char: String = letter.to_upper().substr(0, 1)
	
	# Simple letter patterns - each is a series of pixel coordinates
	var pixels: Array[Vector2] = []
	
	match first_char:
		"A":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(8,2),
				Vector2(1,3), Vector2(8,3),
				Vector2(1,4), Vector2(8,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), 
				Vector2(6,5), Vector2(7,5), Vector2(8,5),
				Vector2(1,6), Vector2(8,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(8,8)
			]
		"B":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(1,7), Vector2(7,7),
				Vector2(1,8), Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"C":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), Vector2(1,6), Vector2(1,7),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8), Vector2(7,8)
			]
		"D":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(1,7), Vector2(7,7),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"E":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(2,6), Vector2(3,6), Vector2(4,6), Vector2(5,6), Vector2(6,6),
				Vector2(1,7), Vector2(1,8), Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"F":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(2,6), Vector2(3,6), Vector2(4,6), Vector2(5,6), Vector2(6,6),
				Vector2(1,7), Vector2(1,8)
			]
		"G":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), Vector2(1,6), Vector2(1,7),
				Vector2(1,8), Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8),
				Vector2(7,5), Vector2(8,5)
			]
		"H":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), 
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(7,1), Vector2(7,2), Vector2(7,3), Vector2(7,4), Vector2(7,5),
				Vector2(7,6), Vector2(7,7), Vector2(7,8),
				Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5)
			]
		"I":
			pixels = [
				Vector2(4,1), Vector2(5,1),
				Vector2(4,2), Vector2(5,2),
				Vector2(4,3), Vector2(5,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(4,5), Vector2(5,5),
				Vector2(4,6), Vector2(5,6),
				Vector2(4,7), Vector2(5,7),
				Vector2(4,8), Vector2(5,8)
			]
		"J":
			pixels = [
				Vector2(5,1), Vector2(5,2), Vector2(5,3), Vector2(5,4), Vector2(5,5), 
				Vector2(5,6), Vector2(5,7),
				Vector2(4,8), Vector2(5,8), Vector2(6,8),
				Vector2(4,9), Vector2(5,9)
			]
		"K":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), 
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5),
				Vector2(6,6), Vector2(7,7), Vector2(8,8)
			]
		"L":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), 
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8),
				Vector2(7,8), Vector2(8,8)
			]
		"M":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1),
				Vector2(1,2), Vector2(8,2),
				Vector2(1,3), Vector2(8,3),
				Vector2(1,4), Vector2(2,4), Vector2(3,4), Vector2(4,4),
				Vector2(5,4), Vector2(6,4), Vector2(7,4), Vector2(8,4)
			]
		"N":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1),
				Vector2(1,2), Vector2(8,2),
				Vector2(1,3), Vector2(5,3), Vector2(8,3),
				Vector2(1,4), Vector2(6,4), Vector2(8,4),
				Vector2(1,5), Vector2(7,5), Vector2(8,5),
				Vector2(1,6), Vector2(8,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(8,8)
			]
		"O":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(2,7), Vector2(3,7), Vector2(4,7), Vector2(5,7), Vector2(6,7)
			]
		"P":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5)
			]
		"Q":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(2,7), Vector2(3,7), Vector2(4,7), Vector2(5,7), Vector2(6,7),
				Vector2(7,8), Vector2(8,8)
			]
		"R":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(9,8)
			]
		"S":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4),
				Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(7,6), Vector2(8,7), Vector2(8,8),
				Vector2(7,8), Vector2(6,8), Vector2(5,8), Vector2(4,8), Vector2(3,8)
			]
		"T":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1), Vector2(9,1),
				Vector2(5,2), Vector2(5,3), Vector2(5,4), Vector2(5,5),
				Vector2(5,6), Vector2(5,7), Vector2(5,8), Vector2(5,9)
			]
		"U":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(1,7),
				Vector2(8,1), Vector2(8,2), Vector2(8,3), Vector2(8,4), Vector2(8,5),
				Vector2(8,6), Vector2(8,7),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"V":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(7,1), Vector2(8,1),
				Vector2(2,2), Vector2(7,2),
				Vector2(3,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(4,5), Vector2(5,5),
				Vector2(4,6), Vector2(5,6),
				Vector2(4,7), Vector2(5,7),
				Vector2(4,8), Vector2(5,8)
			]
		"W":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(8,1), Vector2(8,2), Vector2(8,3), Vector2(8,4), Vector2(8,5),
				Vector2(8,6), Vector2(8,7), Vector2(8,8),
				Vector2(1,9), Vector2(2,9), Vector2(3,9), Vector2(4,9), Vector2(5,9),
				Vector2(6,9), Vector2(7,9), Vector2(8,9)
			]
		"X":
			pixels = [
				Vector2(1,1), Vector2(8,1),
				Vector2(2,2), Vector2(7,2),
				Vector2(3,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(3,5), Vector2(6,5),
				Vector2(2,6), Vector2(7,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(8,8)
			]
		"Y":
			pixels = [
				Vector2(1,1), Vector2(8,1),
				Vector2(2,2), Vector2(7,2),
				Vector2(3,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(5,5), Vector2(5,6), Vector2(5,7), Vector2(5,8)
			]
		"Z":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1), Vector2(9,1),
				Vector2(7,2), Vector2(6,3), Vector2(5,4), Vector2(4,5),
				Vector2(3,6), Vector2(2,7), Vector2(1,8), Vector2(2,8), 
				Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8), 
				Vector2(7,8), Vector2(8,8)
			]
		"0":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(2,7), Vector2(3,7), Vector2(4,7), Vector2(5,7), Vector2(6,7)
			]
		"1":
			pixels = [
				Vector2(5,1), Vector2(4,2), Vector2(5,2), Vector2(6,2),
				Vector2(3,3), Vector2(4,3), Vector2(5,3), Vector2(6,3), Vector2(7,3),
				Vector2(4,4), Vector2(5,4), Vector2(6,4),
				Vector2(5,5), Vector2(5,6), Vector2(5,7), Vector2(5,8)
			]
		_:
			# Default for unknown characters - simple cross
			pixels = [
				Vector2(4,3), Vector2(5,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4), Vector2(6,4),
				Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(5,2), Vector2(5,6)
			]
	
	# Draw the pixels
	for pixel: Vector2 in pixels:
		var x: int = int(pixel.x) - 1  # Convert to 0-indexed
		var y: int = int(pixel.y) - 1  # Convert to 0-indexed
		if x >= 0 and x < size and y >= 0 and y < size:
			image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)


func _create_entity_icon(kind: String, color: Color) -> Texture2D:
	var size: int = ICON_SIZE
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Add dark outline for better visibility
	var outline_color: Color = Color(0.15, 0.15, 0.15, 0.8)
	
	match kind.to_lower():
		"npc", "character":
			# Diamond shape for NPCs with outline
			for y in range(size):
				for x in range(size):
					var dist: float = sqrt(pow(x - size/2, 2) + pow(y - size/2, 2))
					if dist <= size/2 - 0.5:
						image.set_pixel(x, y, color)
					elif dist <= size/2 + 0.5:
						image.set_pixel(x, y, outline_color)
			
		"place", "building", "landmark":
			# Square for places with outline
			for y in range(1, size - 1):
				for x in range(1, size - 1):
					image.set_pixel(x, y, color)
			# Outline
			for x in range(size):
				image.set_pixel(x, 0, outline_color)
				image.set_pixel(x, size - 1, outline_color)
			for y in range(1, size - 1):
				image.set_pixel(0, y, outline_color)
				image.set_pixel(size - 1, y, outline_color)
			
		"quest":
			# Star for quest markers with outline
			for y in range(size):
				for x in range(size):
					var dx: float = x - size/2
					var dy: float = y - size/2
					if abs(dx) + abs(dy) <= size/2 - 0.5:
						image.set_pixel(x, y, color)
					elif abs(dx) + abs(dy) <= size/2 + 0.5:
						image.set_pixel(x, y, outline_color)
			
		_:  # Default circle for objects with outline
			for y in range(size):
				for x in range(size):
					var dist: float = sqrt(pow(x - size/2, 2) + pow(y - size/2, 2))
					if dist <= size/2 - 1:
						image.set_pixel(x, y, color)
					elif dist <= size/2 - 0.5:
						image.set_pixel(x, y, outline_color)
	
	return ImageTexture.create_from_image(image)


## Draws the goals of the quests above the map: a line from the player, a pulsing ring, the
## distance, and an arrow on the rim for goals outside the view. Green means the player is getting
## closer, red farther, yellow neither.
class GoalOverlay extends Node2D:
	var _goals: Array[Dictionary] = []
	var _size := Vector2(128, 128)
	var _scale_px := 1.0
	var _time := 0.0
	## goal id -> {distance: float, since: float, trend: int}
	var _history: Dictionary = {}

	func update_goals(goals: Array[Dictionary], size: Vector2, scale_px: float, now: float) -> void:
		_goals = goals
		_size = size
		_scale_px = scale_px
		_time = now
		var seen := {}
		for goal in goals:
			var id: String = goal.id
			seen[id] = true
			var entry: Dictionary = _history.get(id, {"distance": goal.distance, "since": now, "trend": 0})
			if now - entry.since >= TREND_SECONDS:
				var change: float = goal.distance - entry.distance
				entry.trend = 0 if absf(change) < TREND_MIN_M else (-1 if change < 0.0 else 1)
				entry.distance = goal.distance
				entry.since = now
			_history[id] = entry
		for id: String in _history.keys():
			if not seen.has(id):
				_history.erase(id)
		queue_redraw()

	func _color_of(id: String) -> Color:
		match int(_history.get(id, {}).get("trend", 0)):
			-1:
				return GOAL_CLOSER_COLOR
			1:
				return GOAL_FARTHER_COLOR
		return GOAL_COLOR

	func _draw() -> void:
		var centre := _size / 2.0
		var rim := minf(_size.x, _size.y) / 2.0 - 8.0
		var font := ThemeDB.fallback_font
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		for goal in _goals:
			var color := _color_of(goal.id)
			var offset: Vector2 = goal.offset * _scale_px
			var inside := offset.length() <= rim
			var point := offset if inside else offset.normalized() * rim
			point += centre
			draw_dashed_line(centre, point, Color(color, 0.55), 1.5, 5.0)
			if inside:
				draw_arc(point, 9.0 + 3.0 * pulse, 0.0, TAU, 24, color, 2.0)
			else:
				var direction := offset.normalized()
				var side := Vector2(-direction.y, direction.x)
				var tip := point + direction * 6.0
				draw_colored_polygon(PackedVector2Array([tip, point - direction * 5.0 + side * 6.0, point - direction * 5.0 - side * 6.0]), color)
			var text := "%d m" % roundi(goal.distance)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var at := point + Vector2(-width / 2.0, 22.0 if point.y < _size.y - 24.0 else -14.0)
			at.x = clampf(at.x, 2.0, _size.x - width - 2.0)
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


## Draws the roads and buildings of the generated places: each prop a rectangle of its real
## footprint, turned by its yaw around the planet's radius at its place, projected on the
## player's tangent plane exactly like the entity markers. The geometry is recomputed when
## the view changes; the draw only puts the collected rectangles on screen.
class PropOverlay extends Node2D:
	var _quads: Array[Dictionary] = []
	## How many props the last view update kept (for tests).
	var _drawn := 0

	func update_props(props: Array[Dictionary], size: Vector2, scale_px: float, position: Vector3, basis: Dictionary) -> void:
		_quads.clear()
		_drawn = 0
		var centre := size / 2.0
		var right: Vector3 = basis.right
		var forward: Vector3 = basis.forward
		for prop: Dictionary in props:
			if not (prop.get("position") is Vector3 and prop.get("size") is Vector2):
				continue
			var prop_position: Vector3 = prop.position
			var relative := prop_position - position
			var prop_size: Vector2 = prop.size
			if relative.length() > VIEW_RADIUS_M + prop_size.length() * 0.5:
				continue
			var up := prop_position.normalized()
			var rotation := Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, float(prop.get("yaw", 0.0)))
			var half := prop_size * 0.5
			var points := PackedVector2Array()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var world := relative + rotation * Vector3(corner.x * half.x, 0.0, corner.y * half.y)
				points.append(centre + Vector2(world.dot(right), -world.dot(forward)) * scale_px)
			_quads.append({"points": points, "color": ROAD_COLOR if prop.get("kind", "") == "road" else BUILDING_COLOR})
			_drawn += 1
		queue_redraw()

	func _draw() -> void:
		for quad: Dictionary in _quads:
			draw_colored_polygon(quad.points, quad.color)
