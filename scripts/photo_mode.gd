extends CanvasLayer
## Photo mode. The interface steps aside, the camera comes off the character's shoulder and flies on
## a short leash, and the sun can be carried for the shot.
##
## The sun is moved locally only (`planet_sky.gd` `preview_offset_seconds`). The world's solar clock
## belongs to the server and the Day and Night scrolls turn it for everybody at once; a photograph
## must not do that, so the offset is dropped when the mode closes.
##
## The leash is what keeps this a camera and not a spyglass: in a world where other people walk
## about, a view that could wander off would scout what the character cannot see.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

## How far the camera may drift from the character, in metres: far enough to step back and climb for
## a composition, not far enough to look over the next hill.
const LEASH_M := 50.0
## Kept above the ground so a shot from low down does not end up inside the planet.
const CLEARANCE_M := 0.4
const MOVE_M_S := 6.0
const FAST_M_S := 20.0
const LOOK_SPEED := 0.0028
const FOV_MIN := 20.0
const FOV_MAX := 110.0
## The sun can be carried half a day either way, which reaches every hour from here.
const TIME_RANGE_S := 43200.0

signal closed

var camera: Camera3D
var controls: Node
var environment: Node3D
var sky: Node

var active := false

var _offset := Vector3.ZERO
var _yaw := 0.0
var _pitch := -0.15
var _fov_before := 75.0
var _hidden: Array[CanvasLayer] = []
var _bar: PanelContainer
var _time_slider: HSlider
var _fov_slider: HSlider
var _show_avatar: CheckBox
var _hint: Label
var _time_label: Label
var _notice_until_ms := 0

func _ready() -> void:
	layer = 6
	_build()
	hide()
	set_process(false)
	set_process_unhandled_input(false)

func _build() -> void:
	_bar = PanelContainer.new()
	_bar.name = "PhotoBar"
	_bar.theme_type_variation = &"FramePanel"
	add_child(_bar)
	get_viewport().size_changed.connect(_fit_bar)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_bar.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)

	var time_box := VBoxContainer.new()
	row.add_child(time_box)
	_time_label = Label.new()
	_time_label.theme_type_variation = &"MutedLabel"
	_time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	time_box.add_child(_time_label)
	_time_slider = HSlider.new()
	_time_slider.custom_minimum_size = Vector2(240, 0)
	_time_slider.min_value = -TIME_RANGE_S
	_time_slider.max_value = TIME_RANGE_S
	_time_slider.step = 60.0
	_time_slider.value_changed.connect(_on_time_changed)
	time_box.add_child(_time_slider)

	var fov_box := VBoxContainer.new()
	row.add_child(fov_box)
	var fov_label := Label.new()
	fov_label.theme_type_variation = &"MutedLabel"
	fov_label.text = tr("Field of view")
	fov_box.add_child(fov_label)
	_fov_slider = HSlider.new()
	_fov_slider.custom_minimum_size = Vector2(200, 0)
	_fov_slider.min_value = FOV_MIN
	_fov_slider.max_value = FOV_MAX
	_fov_slider.step = 1.0
	_fov_slider.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(camera):
			camera.fov = value)
	fov_box.add_child(_fov_slider)

	_show_avatar = CheckBox.new()
	_show_avatar.text = tr("Show character")
	_show_avatar.button_pressed = true
	_show_avatar.toggled.connect(_on_avatar_toggled)
	row.add_child(_show_avatar)

	_hint = Label.new()
	_hint.theme_type_variation = &"MutedLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)
	_refresh_hint()

## Anchors alone leave the panel at its default offsets, which puts it off the bottom of the
## screen; the offsets have to be set with them, and again whenever the window changes size.
func _fit_bar() -> void:
	if is_instance_valid(_bar):
		_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)

func _refresh_hint() -> void:
	_hint.text = tr("Walking keys move the camera, the right mouse button looks around, jump and Control rise and sink, run flies faster. The screenshot key takes the picture, Escape leaves.")

## Opens the mode: the interface goes away and the camera takes up the character's own view, so the
## first frame of photo mode looks exactly like the last frame of the game.
func open(ui_root: Node) -> void:
	if active or not is_instance_valid(camera) or controls == null:
		return
	active = true
	_hidden.clear()
	for child in ui_root.get_children():
		if child is CanvasLayer and child != self and (child as CanvasLayer).visible:
			_hidden.append(child)
			(child as CanvasLayer).visible = false
	_take_over_view()
	_fov_before = camera.fov
	_fov_slider.set_value_no_signal(camera.fov)
	_time_slider.set_value_no_signal(0.0)
	_show_avatar.set_pressed_no_signal(true)
	_on_avatar_toggled(true)
	_on_time_changed(0.0)
	_refresh_hint()
	show()
	_fit_bar.call_deferred()
	set_process(true)
	set_process_unhandled_input(true)
	# The cursor stays free, because the bar's sliders and the character switch have to be
	# reachable the whole time the mode is open; looking around is the right button held down.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Leaves the mode and puts back everything it borrowed: the sun, the field of view, the character
## and every window that was open when it started.
func close() -> void:
	if not active:
		return
	active = false
	set_process(false)
	set_process_unhandled_input(false)
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if sky != null:
		sky.preview_offset_seconds = 0.0
	if is_instance_valid(camera):
		camera.fov = _fov_before
	_on_avatar_toggled(true)
	for layer: CanvasLayer in _hidden:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden.clear()
	closed.emit()

func _on_time_changed(value: float) -> void:
	if sky != null:
		sky.preview_offset_seconds = value
	var shift := int(round(value / 60.0))
	var sign_text := "+" if shift >= 0 else "-"
	_time_label.text = "%s  %s%d:%02d" % [tr("Time of day"), sign_text, absi(shift) / 60, absi(shift) % 60]

func _on_avatar_toggled(shown: bool) -> void:
	if controls != null and is_instance_valid(controls.avatar):
		controls.avatar.visible = shown or not active

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * LOOK_SPEED
		_pitch = clampf(_pitch - event.relative.y * LOOK_SPEED, -1.5, 1.5)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(camera) or controls == null:
		return
	var up := _player_up()
	var forward := _basis_forward(up)
	var right := forward.cross(up).normalized()
	# The same actions the character walks by, so a rebound key moves the camera too
	# (`character_controls.intent` reads them the same way). Up is the jump key; down is Control,
	# which is not a bindable action.
	var step := (FAST_M_S if Input.is_action_pressed("run") else MOVE_M_S) * delta / 1000.0
	var axes := Input.get_vector("walk_left", "walk_right", "walk_forward", "walk_backward")
	var wish := right * axes.x - forward * axes.y
	if Input.is_action_pressed("jump"):
		wish += up
	if Input.is_key_pressed(KEY_CTRL):
		wish -= up
	if wish.length_squared() > 0.0:
		_offset += wish.normalized() * step
	var leash := LEASH_M / 1000.0
	if _offset.length() > leash:
		_offset = _offset.normalized() * leash
	_place(up, forward)

## Takes the game camera's place, so the first frame of photo mode is the last frame of the game.
## The character's own yaw and pitch cannot simply be copied: `character_controls` turns the camera
## around the character by a surface tangent, this flies it by a basis of its own, and the two do
## not agree. Reading the direction back out of the camera is what makes them agree.
func _take_over_view() -> void:
	_offset = Vector3.ZERO
	if not is_instance_valid(controls.avatar):
		return
	_offset = camera.position - controls.avatar.position
	var leash := LEASH_M / 1000.0
	if _offset.length() > leash:
		_offset = _offset.normalized() * leash
	var up := _player_up()
	var reference := up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP).normalized()
	var north := up.cross(reference).normalized()
	var aim := -camera.basis.z
	_pitch = clampf(asin(clampf(aim.dot(up), -1.0, 1.0)), -1.5, 1.5)
	var flat := (aim - up * aim.dot(up))
	if flat.length_squared() > 0.0:
		flat = flat.normalized()
		_yaw = atan2(flat.dot(reference), flat.dot(north))

## The character's own up, so flying stays sensible on a sphere.
func _player_up() -> Vector3:
	if is_instance_valid(controls.avatar) and controls.direction != Vector3.ZERO:
		return controls.direction.normalized()
	return Vector3.UP

func _basis_forward(up: Vector3) -> Vector3:
	var reference := up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP).normalized()
	var north := up.cross(reference).normalized()
	var flat := (north * cos(_yaw) + reference * sin(_yaw)).normalized()
	return (flat * cos(_pitch) + up * sin(_pitch)).normalized()

func _place(up: Vector3, forward: Vector3) -> void:
	if not is_instance_valid(controls.avatar):
		return
	camera.position = controls.avatar.position + _offset
	_lift_above_ground(up)
	camera.look_at(camera.position + forward, up)

## The same clearance `character_controls.update_camera` keeps: the scene is in kilometres and the
## ground is read in metres from the planet's centre.
func _lift_above_ground(up: Vector3) -> void:
	if environment == null or not environment.has_method("elevation64"):
		return
	var anchor: Variant = controls.get("_anchor_metres")
	var base: Array = anchor if anchor is Array and anchor.size() == 3 else [0.0, 0.0, 0.0]
	var absolute: Array[float] = []
	for axis in 3:
		absolute.append(float(base[axis]) + float(camera.position[axis]) * 1000.0)
	var radius := Vector3(absolute[0], absolute[1], absolute[2]).length() / 1000.0
	var point := Vector3(absolute[0], absolute[1], absolute[2]).normalized()
	var ground: float = maxf(0.0, environment.elevation64(absolute))
	var floor_km: float = controls.RADIUS + ground + CLEARANCE_M / 1000.0
	if radius < floor_km:
		camera.position += point * (floor_km - radius)

## Saves what the camera sees, without the bar. Returns the path, or an empty string.
func shoot() -> String:
	var was := _bar.visible
	_bar.visible = false
	var path := await _capture()
	_bar.visible = was
	return path

## Says something on the hint line for a moment: where the picture went, or that it could not be
## saved. The game's own messages share a layer with the interaction prompt, which has no place in
## a photograph, so that whole layer stays hidden and the bar carries the word instead.
func notice(text: String, seconds := 4.0) -> void:
	if not active:
		return
	_hint.text = text
	# No `await` here: the caller does not await this, and Godot refuses to start a coroutine that
	# nobody awaits. A later notice pushes the deadline out, so only the last one puts the hint back.
	_notice_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	get_tree().create_timer(seconds).timeout.connect(_clear_notice)

func _clear_notice() -> void:
	if active and Time.get_ticks_msec() >= _notice_until_ms:
		_refresh_hint()

## A picture with no interface and no mode: everything is hidden for the one frame it takes.
func shoot_plain(ui_root: Node) -> String:
	var hidden: Array[CanvasLayer] = []
	for child in ui_root.get_children():
		if child is CanvasLayer and (child as CanvasLayer).visible:
			hidden.append(child)
			(child as CanvasLayer).visible = false
	var path := await _capture()
	for layer: CanvasLayer in hidden:
		if is_instance_valid(layer):
			layer.visible = true
	return path

func _capture() -> String:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return ""
	var folder := _folder()
	if DirAccess.make_dir_recursive_absolute(folder) != OK and not DirAccess.dir_exists_absolute(folder):
		return ""
	var path := folder.path_join("ishtaria-%s.png" % Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-"))
	return path if image.save_png(path) == OK else ""

## The system pictures folder, so a photograph can be found again. Godot's `user://` is where
## nobody looks.
func _folder() -> String:
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pictures.is_empty():
		pictures = OS.get_user_data_dir()
	return pictures.path_join("Ishtaria")
