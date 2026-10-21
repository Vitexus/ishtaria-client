extends Node3D

## Every gameplay key the player can rebind. Settings lists these; Escape alone stays reserved.
const ACTIONS := [
	"walk_forward", "walk_backward", "walk_left", "walk_right", "jump", "run",
	"inventory", "crafting", "quest_log", "chat", "friends", "pickup", "portals", "interact", "minimap",
	"spell_1", "spell_2", "spell_3", "spell_4", "spell_5", "spell_6", "spell_7", "spell_8", "spell_9",
]
const DEFAULT_KEYS := [
	KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE, KEY_SHIFT,
	KEY_I, KEY_C, KEY_J, KEY_ENTER, KEY_F, KEY_G, KEY_P, KEY_E, KEY_M,
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
]
const LABELS := [
	"Forward", "Backward", "Left", "Right", "Jump", "Run",
	"Inventory", "Crafting", "Quest log", "Chat", "Friends", "Pick up", "Portals", "Interact", "Minimap",
	"Spell 1", "Spell 2", "Spell 3", "Spell 4", "Spell 5", "Spell 6", "Spell 7", "Spell 8", "Spell 9",
]
const JUMP := 4
const RUN := 5
const INVENTORY := 6
const CRAFTING := 7
const QUEST_LOG := 8
const CHAT := 9
const FRIENDS := 10
const PICKUP := 11
const PORTALS := 12
const INTERACT := 13
const MINIMAP := 14
const SPELL_1 := 15
## Only Escape cannot be assigned; every other functional key is listed in Settings.
const RESERVED_KEYS := [KEY_ESCAPE]
const RADIUS := 6371.0
## A swimmer floats with the feet this far (km) under the water surface, chest-deep; the paddling clip is slowed.
const SWIM_DRAFT_KM := 0.0012
const SWIM_SPEED_SCALE := 0.55
## With the swimming clip the body lies on the water, hips 0.9 m above the feet: the back should just break the surface.
const SWIM_CLIP_DRAFT_KM := 0.0009
## The camera looks over the shoulder of its character at the closest zoom and from the middle from this distance (metres, before the
## size of the character is applied) on.
const OVER_SHOULDER_NEAR_M := 2.5
const OVER_SHOULDER_FAR_M := 11.0

var camera: Camera3D
var settings_path := "user://client.cfg"
var sensitivity := 0.002
var invert_y := false
var distance_m := 5.0
var yaw := 0.0
var pitch := -0.25
var active := false
var moving := false
var direction := Vector3.ZERO
var sequence := -1
var avatar: Node3D
var origin := Vector3.ZERO
var _anchor_metres: Array = []
var _forward := Vector3.FORWARD
var _character := ""
var _animation: AnimationPlayer
var _motion_until := 0
var _last_position_ms := 0
var _walk_speed := 1.0
var _position_target := Vector3.ZERO
var _ground_surface: Node
var airborne := false
var on_object := false
var sitting := false
var swimming := false
var jump_pending := false
var jump_direction := Vector3.ZERO
var jump_running := false
var _dying := false
var _glow_until := 0
var _swinging := false
var _combat_until := 0
var _strike_index := 0
var _glow_total := 1.0
var _glow_surfaces: Array[Dictionary] = []

func _ready() -> void:
	load_preferences()

func load_preferences() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	var used := []
	for index in ACTIONS.size():
		var has_saved := config.has_section_key("controls", ACTIONS[index])
		var key: Variant = config.get_value("controls", ACTIONS[index], DEFAULT_KEYS[index])
		if not key is int or key <= 0 or key in RESERVED_KEYS:
			key = DEFAULT_KEYS[index]
		if key in used:
			if has_saved:
				# Duplicate saved bindings are corrupt; fall back to defaults.
				reset_keys()
				return
			# New action after an upgrade: keep older remaps, assign another free key.
			key = _first_free_key(used)
			if key <= 0:
				reset_keys()
				return
		_set_key(index, key)
		used.append(key)
	var saved: Variant = config.get_value("controls", "sensitivity", 0.002)
	if (saved is float or saved is int) and is_finite(float(saved)):
		sensitivity = clampf(saved, 0.0005, 0.01)
	var inverted: Variant = config.get_value("controls", "invert_y", false)
	invert_y = inverted if inverted is bool else false

func _first_free_key(used: Array) -> int:
	for candidate in DEFAULT_KEYS:
		if candidate not in used and candidate not in RESERVED_KEYS:
			return candidate
	for code in range(KEY_A, KEY_Z + 1):
		if code not in used and code not in RESERVED_KEYS:
			return code
	return -1

func _set_key(index: int, key: int) -> void:
	if not InputMap.has_action(ACTIONS[index]):
		InputMap.add_action(ACTIONS[index])
	InputMap.action_erase_events(ACTIONS[index])
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(ACTIONS[index], event)

func key_for(index: int) -> int:
	return InputMap.action_get_events(ACTIONS[index])[0].physical_keycode

func rebind(index: int, key: int) -> bool:
	if index < 0 or index >= ACTIONS.size() or key <= 0 or key in RESERVED_KEYS:
		return false
	var previous := key_for(index)
	for other in ACTIONS.size():
		if other != index and key_for(other) == key:
			_set_key(other, previous)
	_set_key(index, key)
	return save_preferences()

func reset_keys() -> void:
	for index in ACTIONS.size():
		_set_key(index, DEFAULT_KEYS[index])

func save_preferences() -> bool:
	var config := ConfigFile.new()
	config.load(settings_path)
	for index in ACTIONS.size():
		config.set_value("controls", ACTIONS[index], key_for(index))
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	return config.save(settings_path) == OK

## Whether a key event matches a remappable action (physical key; keypad Enter aliases Chat when bound to Enter).
func matches_action(event: InputEvent, index: int) -> bool:
	if not event is InputEventKey or index < 0 or index >= ACTIONS.size():
		return false
	var key: int = key_for(index)
	if event.physical_keycode == key:
		return true
	if index == CHAT and key == KEY_ENTER and event.keycode == KEY_KP_ENTER:
		return true
	return false

## Spell hotbar slot 0..8 for a key press, or -1 when it is not a spell binding.
func spell_slot(event: InputEvent) -> int:
	for slot in 9:
		if matches_action(event, SPELL_1 + slot):
			return slot
	return -1

func start(character: String, point: Vector3, coordinates: Dictionary = {}) -> void:
	stop()
	if point.length_squared() < 1.0:
		return
	direction = point.normalized()
	var reference := Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	_forward = reference.cross(direction).normalized()
	if _character != character or not is_instance_valid(avatar):
		if is_instance_valid(avatar):
			avatar.free()
		avatar = preload("res://scripts/character_catalog.gd").create_model(character)
		if avatar == null:
			return
		_character = character
		avatar.scale = Vector3.ONE * 0.001
		add_child(avatar)
		_animation = avatar.get_node_or_null("CharacterAnimation")
	avatar.position = point
	_position_target = point
	_anchor_metres = [coordinates.get("x", point.x * 1000.0), coordinates.get("y", point.y * 1000.0), coordinates.get("z", point.z * 1000.0)]
	airborne = coordinates.get("airborne", false) == true
	on_object = coordinates.get("on_object", false) == true
	avatar.basis = Basis.looking_at(-_forward, direction).scaled(Vector3.ONE * 0.001)
	avatar.show()
	yaw = 0.0
	pitch = -0.25
	sequence = -1
	_last_position_ms = Time.get_ticks_msec()

## The model of a datadisk arrived or was withdrawn: the avatar is made again, where it stands.
func reload_avatar() -> void:
	if not is_instance_valid(avatar) or _character.is_empty():
		return
	var fresh: Node3D = preload("res://scripts/character_catalog.gd").create_model(_character)
	if fresh == null:
		return
	fresh.transform = avatar.transform
	fresh.visible = avatar.visible
	avatar.queue_free()
	avatar = fresh
	add_child(avatar)
	_animation = avatar.get_node_or_null("CharacterAnimation")

## Story handed the player another body: keep position and control, change the look.
func swap_character(character: String) -> void:
	if not preload("res://scripts/character_catalog.gd").is_valid(character):
		return
	if character == _character:
		reload_avatar()
		return
	_character = character
	reload_avatar()
	if not is_instance_valid(avatar):
		# First body after a failed look: place a new model at the last known point.
		avatar = preload("res://scripts/character_catalog.gd").create_model(character)
		if avatar == null:
			return
		avatar.scale = Vector3.ONE * 0.001
		avatar.position = _position_target
		avatar.basis = Basis.looking_at(-_forward, direction).scaled(Vector3.ONE * 0.001)
		add_child(avatar)
		_animation = avatar.get_node_or_null("CharacterAnimation")


func stop() -> void:
	active = false
	moving = false
	_ground_surface = null
	airborne = false
	on_object = false
	sitting = false
	_dying = false
	direction = Vector3.ZERO
	if is_instance_valid(avatar):
		avatar.hide()
	release_mouse()

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	moving = false
	jump_pending = false
	jump_running = false
	Input.action_release("run")
	_play_animation(false)
	for action in ACTIONS:
		Input.action_release(action)

func capture_mouse() -> void:
	if active and get_window().has_focus():
		get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func look(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * sensitivity * (-1.0 if invert_y else 1.0), -1.35, 1.25)

func zoom(steps: float) -> void:
	distance_m = clampf(distance_m * pow(1.15, steps), 2.0, 30.0)

func heading() -> Vector3:
	var tangent := (_forward - direction * _forward.dot(direction)).normalized()
	return tangent.rotated(direction, yaw)

func intent() -> Vector3:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return Vector3.ZERO
	var axes := Input.get_vector(ACTIONS[2], ACTIONS[3], ACTIONS[0], ACTIONS[1])
	return (heading() * -axes.y + heading().cross(direction) * axes.x).limit_length(1.0)

## Whether a key event is the (rebindable) jump key.
func is_jump_event(event: InputEvent) -> bool:
	return matches_action(event, JUMP)

func queue_jump() -> void:
	if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not airborne and not jump_pending:
		jump_direction = intent()
		jump_running = running()
		jump_pending = true

func running() -> bool:
	return active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("run")

func apply_position(data: Variant, is_moving: bool) -> bool:
	if not data is Dictionary or not data.get("sequence") is String or not data.sequence.is_valid_int():
		return false
	for axis in ["x", "y", "z"]:
		var value: Variant = data.get(axis)
		if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
			return false
	var received := int(data.sequence)
	if received < 0 or received <= sequence:
		return false
	for state in ["airborne", "on_object"]:
		if data.has(state) and not data[state] is bool:
			return false
	var point := Vector3(data.x / 1000.0, data.y / 1000.0, data.z / 1000.0)
	if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
		return false
	sequence = received
	airborne = data.get("airborne", false)
	on_object = data.get("on_object", false)
	direction = point.normalized()
	var previous := _position_target
	_position_target = Vector3((float(data.x) - _anchor_metres[0]) / 1000.0, (float(data.y) - _anchor_metres[1]) / 1000.0, (float(data.z) - _anchor_metres[2]) / 1000.0) if origin != Vector3.ZERO else point
	var now := Time.get_ticks_msec()
	var travelled := _position_target.distance_to(previous) * 1000.0
	moving = is_moving and travelled > 0.0001
	if moving:
		_walk_speed = clampf(travelled / maxf((now - _last_position_ms) / 1000.0, 0.04) / 4.0, 0.2, 1.5)
		_motion_until = now + 350
	_last_position_ms = now
	_play_animation(moving and active and intent().length_squared() > 0.0001)
	return true

## A swing of the tool or weapon. Disk models with combat clips play `box` / `kick` / `sweep`
## (see `play_combat`); Kenney packs keep a short squash-and-stretch lunge.
func swing(kind := "") -> void:
	if not is_instance_valid(avatar) or _swinging:
		return
	var clip := kind
	if clip.is_empty():
		clip = _next_strike_clip()
	if play_combat(clip):
		return
	_swinging = true
	var rest := avatar.scale
	var tween := create_tween()
	tween.tween_property(avatar, "scale", rest * Vector3(1.1, 0.9, 1.1), 0.08)
	tween.tween_property(avatar, "scale", rest * Vector3(0.95, 1.06, 0.95), 0.1)
	tween.tween_property(avatar, "scale", rest, 0.1)
	tween.tween_callback(func() -> void:
		_swinging = false
		if is_instance_valid(avatar):
			avatar.scale = rest
	)

## True when the disk model has at least one strike clip (bare-handed wildlife blows).
func has_combat_clips() -> bool:
	for name in ["box", "kick", "sweep"]:
		if _has_clip(name):
			return true
	return false

## Plays a one-shot combat clip (`box`, `kick`, `sweep`, `hit`, …). Returns false when missing.
func play_combat(clip: String) -> bool:
	if clip.is_empty() or not _has_clip(clip) or _dying:
		return false
	_swinging = true
	_animation.speed_scale = 1.0
	_animation.play(clip, 0.08)
	var length := _animation.current_animation_length
	_combat_until = Time.get_ticks_msec() + int(maxf(length, 0.2) * 1000.0)
	get_tree().create_timer(maxf(length, 0.2)).timeout.connect(func() -> void:
		_swinging = false
		_combat_until = 0
		if not _dying:
			_play_animation(false)
	, CONNECT_ONE_SHOT)
	return true

func _next_strike_clip() -> String:
	var order: Array[String] = ["box", "kick", "sweep"]
	if running():
		order = ["kick", "box", "sweep"]
	var available: Array[String] = []
	for name in order:
		if _has_clip(name):
			available.append(name)
	if available.is_empty():
		return ""
	var chosen: String = available[_strike_index % available.size()]
	_strike_index += 1
	return chosen

## Makes the character shine for a while, for example after reaching a new level.
func glow(seconds: float = 10.0) -> void:
	if not is_instance_valid(avatar):
		return
	_end_glow()
	_glow_total = maxf(seconds, 0.1)
	_glow_until = Time.get_ticks_msec() + int(_glow_total * 1000.0)
	for mesh: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				material.emission_enabled = true
				material.emission = Color(1.0, 0.82, 0.35)
				material.emission_energy_multiplier = 0.0
				mesh.set_surface_override_material(surface, material)
				_glow_surfaces.append({"mesh": mesh, "surface": surface, "material": material})

func is_glowing() -> bool:
	return _glow_until > Time.get_ticks_msec()

## Pulses the glow and fades it out over the last second.
func _update_glow() -> void:
	if _glow_surfaces.is_empty():
		return
	var left := (_glow_until - Time.get_ticks_msec()) / 1000.0
	if left <= 0.0 or not is_instance_valid(avatar):
		_end_glow()
		return
	var fade := minf(1.0, left)
	var energy := (1.6 + 0.9 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)) * fade
	for entry: Dictionary in _glow_surfaces:
		entry.material.emission_energy_multiplier = energy

func _end_glow() -> void:
	for entry: Dictionary in _glow_surfaces:
		if is_instance_valid(entry.mesh):
			entry.mesh.set_surface_override_material(entry.surface, null)
	_glow_surfaces.clear()
	_glow_until = 0

func _process(delta: float) -> void:
	_update_glow()
	if active and is_instance_valid(avatar):
		avatar.position = avatar.position.lerp(_position_target, 1.0 - exp(-18.0 * delta))
		_ground_avatar(_ground_surface)
	_play_animation(active and moving and Time.get_ticks_msec() < _motion_until and intent().length_squared() > 0.0001)

func _ground_avatar(surface: Node) -> void:
	if airborne or on_object or not is_instance_valid(surface) or not is_instance_valid(avatar) or origin == Vector3.ZERO:
		return
	var absolute: Array = []
	for axis in 3:
		absolute.append(float(_anchor_metres[axis]) + float(avatar.position[axis]) * 1000.0)
	var level: float = surface.water_surface_km(absolute) if swimming and surface.has_method("water_surface_km") else NAN
	if is_finite(level):
		# The server keeps a swimmer on the bed; what is shown floats chest-deep at the surface.
		var radius_m := sqrt(float(absolute[0]) * absolute[0] + float(absolute[1]) * absolute[1] + float(absolute[2]) * absolute[2])
		var up := Vector3(absolute[0] / radius_m, absolute[1] / radius_m, absolute[2] / radius_m)
		# A giant of a datadisk floats as much deeper as it is taller than a man.
		var draft := (SWIM_CLIP_DRAFT_KM if _has_clip("swim") else SWIM_DRAFT_KM) * preload("res://scripts/character_catalog.gd").body_scale(_character)
		avatar.position += up * (RADIUS + level - draft - radius_m / 1000.0)
	elif surface.has_method("ground_position64"):
		avatar.position = surface.ground_position64(absolute)
	else:
		var radius := sqrt(float(absolute[0]) * absolute[0] + float(absolute[1]) * absolute[1] + float(absolute[2]) * absolute[2])
		var up := Vector3(absolute[0] / radius, absolute[1] / radius, absolute[2] / radius)
		var height: float = surface.elevation64(absolute) if surface.has_method("elevation64") else surface.elevation(up)
		avatar.position += up * (RADIUS + height - radius / 1000.0)

## Plays a death clip once. Prefer a variant matching `cause` (`fall`, `creature`, …).
func play_death(cause := "") -> void:
	_dying = true
	_swinging = false
	if not is_instance_valid(_animation):
		return
	var clip := _death_clip(cause)
	if clip.is_empty():
		return
	_animation.speed_scale = 1.0
	_animation.play(clip, 0.1)

func _death_clip(cause: String) -> String:
	var preferred: Array[String] = []
	match cause:
		"fall":
			preferred = ["die", "die2", "dieleft"]
		"creature":
			preferred = ["dieleft", "die2", "die", "hit"]
		"exhaustion", "dehydration":
			preferred = ["die2", "die", "dieleft"]
		_:
			preferred = ["die", "die2", "dieleft"]
	for name in preferred:
		if _has_clip(name):
			return name
	var deaths: Array[String] = []
	for candidate in _animation.get_animation_list():
		if String(candidate).begins_with("die"):
			deaths.append(String(candidate))
	if deaths.is_empty():
		return ""
	var key := "%s:%s" % [_character, cause]
	return deaths[abs(key.hash()) % deaths.size()]

## The server says the character is in water: it swims at the surface (the `swim` clip, or the slowed walk of a model without
## one) instead of standing on the bed.
func set_swimming(value: bool) -> void:
	if value == swimming:
		return
	swimming = value
	_play_animation(moving)

func set_sitting(value: bool) -> void:
	sitting = value
	_play_animation(false)

func _has_clip(name: String) -> bool:
	return is_instance_valid(_animation) and _animation.has_animation(name)

func _play_animation(walking: bool) -> void:
	if not is_instance_valid(_animation) or _dying:
		return
	if _swinging or Time.get_ticks_msec() < _combat_until:
		return
	if sitting and _has_clip("sit"):
		_animation.speed_scale = 1.0
		if _animation.current_animation != "sit":
			_animation.play("sit", 0.15)
		return
	if airborne:
		if _has_clip("jump"):
			_animation.speed_scale = 1.0
			if _animation.current_animation != "jump":
				_animation.play("jump", 0.1)
		else:
			# Without a jump clip the legs stop until landing.
			_animation.speed_scale = 0.0
		return
	if swimming and _has_clip("swim"):
		# The swimming clip is a prone stroke, played whether the swimmer moves or treads water.
		_animation.speed_scale = 1.0 if walking else 0.6
		if _animation.current_animation != "swim":
			_animation.play("swim", 0.2)
		return
	var action := "idle"
	if walking:
		if running() and _has_clip("run"):
			action = "run"
		else:
			action = "walk"
	_animation.speed_scale = (_walk_speed if walking else 1.0) * (SWIM_SPEED_SCALE if swimming else 1.0)
	if _animation.current_animation != action:
		_animation.play(action, 0.15)

## Puts the camera behind the character. `force` does it before the controls are active too (the landing flies the camera to this
## pose before the player gets the controls).
func update_camera(surface: Node, hud: Control = null, force := false) -> void:
	if not (active or force) or not is_instance_valid(avatar):
		return
	_ground_surface = surface
	_ground_avatar(surface)
	var visible_fraction := 1.0
	if is_instance_valid(hud) and hud.is_visible_in_tree():
		visible_fraction = clampf(hud.global_position.y / get_viewport().get_visible_rect().size.y, 0.25, 1.0)
	var forward := heading()
	# A giant of a datadisk is followed from higher up and further away.
	var giant := preload("res://scripts/character_catalog.gd").body_scale(_character)
	# Close behind a character its own back fills the middle of the picture and nothing ahead can be seen (a giant of a datadisk is
	# worse): the camera then looks over the shoulder, at a point above the head and to the right of it, and this goes back to the
	# centre as the camera moves away (no offset from OVER_SHOULDER_FAR_M on).
	var close := clampf(1.0 - (distance_m - OVER_SHOULDER_NEAR_M) / (OVER_SHOULDER_FAR_M - OVER_SHOULDER_NEAR_M), 0.0, 1.0)
	close = close * close * (3.0 - 2.0 * close)
	var right := forward.cross(direction).normalized()
	var target := avatar.position + direction * (0.0015 + 0.0005 * close) * giant + right * (0.0007 * close * giant)
	var view := forward * cos(pitch) + direction * sin(pitch)
	camera.position = target - view * (distance_m * giant / (1000.0 * visible_fraction))
	var coordinates: Array = _anchor_metres if origin != Vector3.ZERO else [0.0, 0.0, 0.0]
	var absolute: Array[float] = []
	for axis in 3:
		absolute.append(float(coordinates[axis]) + float(camera.position[axis]) * 1000.0)
	var radius := sqrt(absolute[0] * absolute[0] + absolute[1] * absolute[1] + absolute[2] * absolute[2]) / 1000.0
	var point := Vector3(absolute[0], absolute[1], absolute[2]).normalized()
	var height: float = maxf(0.0, surface.elevation64(absolute) if surface.has_method("elevation64") else surface.elevation(point.normalized()))
	if radius < RADIUS + height + 0.0005:
		camera.position += point * (RADIUS + height + 0.0005 - radius)
	camera.near = 0.0002
	camera.far = 5.0
	camera.look_at(target, direction)
	camera.rotate_object_local(Vector3.RIGHT, -atan((1.0 - visible_fraction) * tan(deg_to_rad(camera.fov) * 0.5)))
	if moving:
		var desired := intent()
		if desired.length_squared() > 0.01:
			avatar.basis = Basis.looking_at(-desired.normalized(), direction).scaled(Vector3.ONE * 0.001)

func _exit_tree() -> void:
	release_mouse()