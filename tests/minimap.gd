extends SceneTree

const MINIMAP := preload("res://scripts/minimap.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var minimap := MINIMAP.new()
	root.add_child(minimap)
	minimap.set_process(false)
	minimap.set_player_position(Vector3(1000, 0, 1000))
	# Standing on the +Y pole facing -Z: right is +X, forward (up on the map) is -Z.
	minimap.set_player_orientation(Vector3.UP, Vector3.FORWARD)
	var entities: Array[Dictionary] = [
		{"id": "near", "name": "Gilgamesh", "kind": "npc", "position": Vector3(1050, 0, 1000), "is_quest": false},
		{"id": "north", "name": "Uruk", "kind": "city", "position": Vector3(1000, 0, 900), "is_quest": false},
		{"id": "far", "name": "Humbaba", "kind": "npc", "position": Vector3(5000, 0, 1000), "is_quest": false},
		{"id": "goal", "name": "Goal", "kind": "quest", "position": Vector3(1000, 0, 400), "is_quest": true},
	]
	minimap.set_entities(entities)
	minimap._update_minimap()
	var markers: Dictionary = minimap._entity_markers
	_check(markers.size() == 4, "Every entity gets a marker")
	var centre: Vector2 = minimap._get_size() / 2.0
	_check(markers.near.marker.visible and markers.near.marker.position.x > centre.x, "East of the player is right of the centre")
	_check(markers.north.marker.position.y < centre.y, "North of the player is above the centre")
	_check(not markers.far.marker.visible, "Beyond the view radius is hidden")
	var goal: Array = minimap._goal_overlay._goals
	_check(goal.size() == 1 and goal[0].id == "goal", "Only quest entities are goals, even beyond the view radius")
	_check(not markers.goal.marker.visible and goal[0].offset.y < 0.0, "A distant goal is hidden but still points forward")
	minimap.set_player_orientation(Vector3.UP, Vector3.RIGHT)
	minimap._update_minimap()
	_check(markers.near.marker.position.y < centre.y, "The entity ahead is above the centre when facing east")
	minimap.set_player_orientation(Vector3.UP, Vector3.FORWARD)
	minimap._update_minimap()
	var before: float = markers.near.marker.position.x
	minimap.zoom_in()
	minimap._update_minimap()
	_check(markers.near.marker.position.x > before, "Zooming in moves markers away from the centre")
	minimap.set_entities([])
	_check(minimap._entity_markers.is_empty(), "Removed entities lose their markers")
	# Roads and buildings, with the player standing on the north pole so the yaw axes are the
	# world axes: a road tile east of the player and one far beyond the view radius.
	minimap.set_player_position(Vector3(0, 1000, 0))
	minimap.set_player_orientation(Vector3.UP, Vector3.FORWARD)
	var props: Array[Dictionary] = [
		{"kind": "road", "position": Vector3(10, 1000, 0), "yaw": 0.0, "size": Vector2(2.5, 2.5)},
		{"kind": "building", "position": Vector3(5000, 1000, 0), "yaw": 0.0, "size": Vector2(4.0, 6.0)},
	]
	minimap.set_props(props)
	minimap._update_minimap()
	_check(minimap._prop_overlay._drawn == 1, "A prop inside the view radius is drawn, a far one is not")
	var quad: PackedVector2Array = minimap._prop_overlay._quads[0].points
	var metres: float = minimap._pixels_per_metre()
	_check(quad[0].distance_to(centre + Vector2(8.75, -1.25) * metres) < 0.01, "The road rectangle spans its footprint east of the player")
	_check(quad[2].distance_to(centre + Vector2(11.25, 1.25) * metres) < 0.01, "The road rectangle's far corner is projected like a marker")
	# The baked water picture: centred, unturned and scaled when its frame matches the player's.
	var water := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	water.fill(Color(0.2, 0.4, 0.6, 0.9))
	var texture := ImageTexture.create_from_image(water)
	minimap.set_water_map({"texture": texture, "centre": Vector3(0, 1000, 0), "tangent": Vector3.RIGHT, "forward": Vector3.FORWARD, "metres_per_pixel": 10.0})
	minimap._update_minimap()
	_check(minimap._water_sprite.visible, "The water picture is shown when the region has one")
	_check(minimap._water_sprite.position == centre, "A water bake at the player is centred on the map")
	_check(is_equal_approx(minimap._water_sprite.rotation, 0.0), "A water bake in the player's frame is not turned")
	_check(is_equal_approx(minimap._water_sprite.scale.x, metres * 10.0), "The water bake is scaled to metres")
	minimap.set_water_map({"texture": texture, "centre": Vector3(0, 1000, 0), "tangent": Vector3.BACK, "forward": Vector3.RIGHT, "metres_per_pixel": 10.0})
	minimap._update_minimap()
	_check(is_equal_approx(minimap._water_sprite.rotation, PI * 0.5), "The bake's tangent axis decides the turn")
	minimap.set_water_map({})
	_check(not minimap._water_sprite.visible, "Without a water picture none is drawn")
	print("minimap checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
