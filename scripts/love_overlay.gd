## Draws flying heart-grenades, love-zone discs and the red/green meter above Enkidu.
extends Node3D

## Anachronistic love-grenade (original prop; not the Cults PU listing).
const HEART_GRENADE := preload("res://assets/props/heart_grenade/heart_grenade.glb")
## Scene units are kilometres; ~0.55 m prop reads clearly in the throw.
const GRENADE_SCALE := 0.00055

var _love: Node = null
var _environment: Node = null
var _zones_root: Node3D
var _meter: MeshInstance3D
var _meter_green: MeshInstance3D
var _meter_red: MeshInstance3D
var _flying: Array = []

func setup(love: Node, environment: Node) -> void:
	_love = love
	_environment = environment
	_zones_root = Node3D.new()
	_zones_root.name = "LoveZones"
	_zones_root.top_level = true
	add_child(_zones_root)
	_meter = _bar(Color(0.15, 0.15, 0.15, 0.85))
	_meter_green = _bar(Color(0.25, 0.85, 0.35, 0.95))
	_meter_red = _bar(Color(0.9, 0.2, 0.25, 0.95))
	for node in [_meter, _meter_green, _meter_red]:
		node.top_level = true
		node.visible = false
		add_child(node)
	if love.has_signal("throw_landed"):
		love.throw_landed.connect(_spawn_heart_flight)
	if love.has_signal("status_changed"):
		love.status_changed.connect(func(_a, _h, _w) -> void: _rebuild_zones())

func _bar(color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 0.12, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node

func _process(_delta: float) -> void:
	if _love == null or not _love.is_active():
		_meter.visible = false
		_meter_green.visible = false
		_meter_red.visible = false
		return
	_update_meter()
	_rebuild_zones()

func _update_meter() -> void:
	var metres: Variant = _love.enkidu_metres()
	if metres == null or _environment == null or not _environment.has_method("_render_position"):
		# Fall back: find NPC named enkidu.
		var entry := _find_enkidu_entry()
		if entry.is_empty():
			_meter.visible = false
			_meter_green.visible = false
			_meter_red.visible = false
			return
		metres = Vector3(entry.position[0], entry.position[1], entry.position[2])
	var pos: Vector3 = _environment._render_position(metres)
	pos.y += 0.0022
	var hits: int = _love.hits()
	var need: int = maxi(1, _love.hits_to_win())
	var green_w := 1.2 * float(hits) / float(need)
	var red_w := 1.2 - green_w
	_meter.visible = true
	_meter.global_position = pos
	_meter_green.visible = green_w > 0.01
	_meter_red.visible = red_w > 0.01
	_meter_green.scale = Vector3(maxf(green_w / 1.2, 0.01), 1, 1)
	_meter_red.scale = Vector3(maxf(red_w / 1.2, 0.01), 1, 1)
	_meter_green.global_position = pos + Vector3(-0.6 + green_w * 0.5, 0, 0) * 0.001
	# Place bars in local camera-facing plane: keep them at pos with x offset in metres-ish.
	# Simpler: stack along local X in render space.
	_meter.global_position = pos
	_meter_green.global_position = Vector3(pos.x - (0.6 - green_w * 0.5) * 0.001, pos.y, pos.z)
	_meter_red.global_position = Vector3(pos.x + (0.6 - red_w * 0.5) * 0.001, pos.y, pos.z)

func _find_enkidu_entry() -> Dictionary:
	if _environment == null or not "_npc_entries" in _environment:
		return {}
	for entry: Variant in _environment._npc_entries:
		if entry is Dictionary:
			var id := str(entry.get("id", ""))
			if id.ends_with(":enkidu") and not id.contains("civilized"):
				return entry
	return {}

func _rebuild_zones() -> void:
	if not is_instance_valid(_zones_root):
		return
	for child in _zones_root.get_children():
		child.queue_free()
	if _love == null or not _love.is_active() or _environment == null:
		return
	var radius_m: float = _love.zone_radius_m()
	for zone: Variant in _love.zones():
		if not zone is Dictionary:
			continue
		var disc := _make_disc(radius_m)
		disc.position = _environment._render_position(zone.position)
		disc.position.y += 0.00015
		_zones_root.add_child(disc)

func _make_disc(radius_m: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_m * 0.001
	mesh.bottom_radius = radius_m * 0.001
	mesh.height = 0.00005
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.55, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node

func _spawn_heart_flight(land: Vector3, _ttl: float) -> void:
	if _environment == null:
		return
	var start: Vector3 = _environment._render_position(_player_aim_start())
	var end: Vector3 = _environment._render_position(land)
	var root := Node3D.new()
	root.top_level = true
	root.position = start
	root.scale = Vector3.ONE * GRENADE_SCALE
	var model: Node3D = HEART_GRENADE.instantiate() as Node3D
	if model == null:
		root.queue_free()
		return
	root.add_child(model)
	add_child(root)
	# Arc slightly upward so the grenade reads as a toss, not a laser.
	var mid := start.lerp(end, 0.5)
	mid.y += start.distance_to(end) * 0.18 + 0.0004
	var spin := Vector3(TAU * 1.4, TAU * 0.7, TAU * 0.35)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "position", mid, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "rotation", spin * 0.5, 0.22)
	tween.chain().set_parallel(true)
	tween.tween_property(root, "position", end, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(root, "rotation", spin, 0.28)
	tween.chain().tween_callback(root.queue_free)

func _player_aim_start() -> Vector3:
	# Prefer camera-near player; overlay parent may set meta.
	if has_meta("player_metres"):
		return get_meta("player_metres")
	return Vector3.ZERO

func set_player_metres(metres: Vector3) -> void:
	set_meta("player_metres", metres)
