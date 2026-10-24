extends CanvasLayer
## Quest prologue on the 3D Sumerian clay tablet: cuneiform is carved sign by sign on the
## front face; when that side is full the tablet flips and carving continues on the blank reverse.
## The narrator speaks the paraphrase; readable subtitles run along the bottom.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const Cuneiform := preload("res://scripts/cuneiform.gd")

signal closed

const TABLET_SCENE := "res://assets/models/sumerian_clay_tablet/sumerian_clay_tablet.glb"
const BLANK_ALBEDO := "res://assets/models/sumerian_clay_tablet/textures/T_AncientClayBlank_BaseColor.png"
const BLANK_ROUGH := "res://assets/models/sumerian_clay_tablet/textures/T_AncientClayBlank_Roughness.png"
const BLANK_NORMAL := "res://assets/models/sumerian_clay_tablet/textures/T_AncientClayBlank_Normal.png"

const VOICE_DB := 0.0
const MAX_VOLUME := 2.0
const MIN_DURATION_SEC := 4.0
const FALLBACK_CHAR_SEC := 0.045
const FLIP_SEC := 0.85
## Usable writing area on one face (metres), inset from the rounded rim.
const FACE_W_M := 0.074
const FACE_H_M := 0.052
const FACE_Z_M := 0.0082
const LABEL_PIXEL_SIZE := 0.00095
const CUNEIFORM_FONT_SIZE := 22
const CUNEIFORM_PATHS := [
	"/usr/share/fonts/truetype/noto/NotoSansCuneiform-Regular.ttf",
	"/usr/share/fonts/opentype/noto/NotoSansCuneiform-Regular.otf",
]

var story: Node
var voice_enabled := true
var voice_volume := 1.0

var _title: Label
var _preview: SubViewportContainer
var _viewport: SubViewport
var _tablet_root: Node3D
var _front_label: Label3D
var _back_label: Label3D
var _subtitles: Label
var _subtitle_bar: PanelContainer
var _dismiss: Button
var _voice: AudioStreamPlayer
var _voice_url := ""
var _carve_text := ""
var _side_a := ""
var _side_b := ""
var _subtitle_text := ""
var _carve_index := 0
var _subtitle_index := 0
var _elapsed := 0.0
var _duration := MIN_DURATION_SEC
var _carving := false
var _flipping := false
var _flipped := false
var _flip_tween: Tween
var _cuneiform_font: Font


func _ready() -> void:
	layer = 5
	_cuneiform_font = _load_cuneiform_font()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.03, 0.02, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_on_backdrop()
	)
	add_child(backdrop)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)

	_preview = SubViewportContainer.new()
	_preview.stretch = true
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.size = Vector2i(640, 480)
	_preview.add_child(_viewport)
	_build_stage()

	_dismiss = Button.new()
	_dismiss.text = tr("Continue")
	_dismiss.theme_type_variation = &"PrimaryButton"
	_dismiss.pressed.connect(hide_tablet)
	add_child(_dismiss)

	_subtitle_bar = PanelContainer.new()
	_subtitle_bar.add_theme_stylebox_override(
		"panel",
		UiTheme.flat_style(Color(0.05, 0.04, 0.03, 0.82), Color(0.0, 0.0, 0.0, 0.0), 0, 0, 12.0)
	)
	add_child(_subtitle_bar)
	_subtitles = Label.new()
	_subtitles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitles.add_theme_font_size_override("font_size", 18)
	_subtitles.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	_subtitles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_bar.add_child(_subtitles)

	_voice = AudioStreamPlayer.new()
	_voice.name = "Narrator"
	_voice.volume_db = _db(VOICE_DB, voice_volume)
	add_child(_voice)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()
	set_process(false)


func _build_stage() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.88, 0.80)
	environment.ambient_light_energy = 0.55
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -28, 0)
	key.light_energy = 1.55
	key.light_color = Color(1.0, 0.96, 0.88)
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	_viewport.add_child(fill)

	_tablet_root = Node3D.new()
	_tablet_root.name = "TabletRoot"
	_viewport.add_child(_tablet_root)
	# Tip the tablet toward the camera; Y flip for the reverse side rotates this whole group.
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.rotation_degrees = Vector3(-18, 0, 0)
	_tablet_root.add_child(tilt)

	var model := _instantiate_tablet()
	if model != null:
		_blank_clay_materials(model)
		tilt.add_child(model)
	else:
		push_warning("Clay tablet GLB missing; prologue uses a stand-in box.")
		var stand_in := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.065, 0.016)
		stand_in.mesh = box
		stand_in.material_override = _blank_material()
		tilt.add_child(stand_in)

	_front_label = _make_face_label("FrontScript")
	_front_label.position = Vector3(0.0, 0.0, FACE_Z_M)
	tilt.add_child(_front_label)

	_back_label = _make_face_label("BackScript")
	_back_label.position = Vector3(0.0, 0.0, -FACE_Z_M)
	_back_label.rotation_degrees = Vector3(0, 180, 0)
	tilt.add_child(_back_label)

	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.position = Vector3(0.0, 0.012, 0.16)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


func _make_face_label(node_name: String) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.font = _cuneiform_font
	label.font_size = CUNEIFORM_FONT_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = Color(0.16, 0.10, 0.06)
	label.outline_modulate = Color(0.12, 0.08, 0.05, 0.35)
	label.outline_size = 2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = FACE_W_M / LABEL_PIXEL_SIZE
	label.text = ""
	return label


func _instantiate_tablet() -> Node:
	# Prefer a direct GLB parse so a half-finished .import does not error-spam.
	var abs_path := ProjectSettings.globalize_path(TABLET_SCENE)
	if FileAccess.file_exists(abs_path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(abs_path, state) == OK:
			var scene: Node = doc.generate_scene(state)
			if scene != null:
				return scene
	var packed: Variant = ResourceLoader.load(TABLET_SCENE)
	return (packed as PackedScene).instantiate() if packed is PackedScene else null


func _load_texture(res_path: String) -> Texture2D:
	# Prefer a direct PNG load so a missing .ctex (fresh checkout) does not spam errors.
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var image := Image.load_from_file(abs_path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	var loaded: Variant = ResourceLoader.load(res_path)
	return loaded as Texture2D if loaded is Texture2D else null


func _blank_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.66, 0.48, 0.28)
	var albedo := _load_texture(BLANK_ALBEDO)
	if albedo != null:
		mat.albedo_texture = albedo
	var rough := _load_texture(BLANK_ROUGH)
	if rough != null:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var normal := _load_texture(BLANK_NORMAL)
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 0.85
	mat.roughness = 0.9
	mat.metallic = 0.0
	return mat


func _blank_clay_materials(node: Node) -> void:
	var blank := _blank_material()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = blank
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = blank


func _load_cuneiform_font() -> Font:
	for path: String in CUNEIFORM_PATHS:
		if FileAccess.file_exists(path):
			var file := FontFile.new()
			if file.load_dynamic_font(path) == OK:
				return file
	return ThemeDB.fallback_font


func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var title_h := 48.0
	_title.position = Vector2(24, 16)
	_title.size = Vector2(screen.x - 48, title_h)
	var bar_height := mini(120.0, screen.y * 0.20)
	var dismiss_h := 44.0
	var preview_top := 16.0 + title_h + 8.0
	var preview_bottom := screen.y - bar_height - dismiss_h - 36.0
	var preview_h := maxf(180.0, preview_bottom - preview_top)
	var preview_w := mini(screen.x - 48.0, preview_h * 1.35)
	_preview.position = Vector2((screen.x - preview_w) * 0.5, preview_top)
	_preview.size = Vector2(preview_w, preview_h)
	# SubViewportContainer.stretch owns the viewport size; do not set it here.
	_dismiss.position = Vector2((screen.x - mini(280.0, screen.x - 48.0)) * 0.5, preview_top + preview_h + 10.0)
	_dismiss.size = Vector2(mini(280.0, screen.x - 48.0), dismiss_h)
	_subtitle_bar.position = Vector2(24, screen.y - bar_height - 12)
	_subtitle_bar.size = Vector2(screen.x - 48, bar_height)


## Shows the tablet for a quest entry that carries an `excerpt` (paraphrase / Akkadian keys).
func present(quest: Dictionary) -> void:
	var excerpt: Variant = quest.get("excerpt")
	if not excerpt is Dictionary or not excerpt.get("paraphrase_key") is String:
		return
	var paraphrase := _text(str(excerpt.paraphrase_key))
	var akkadian := ""
	if excerpt.get("akkadian_key") is String and not str(excerpt.akkadian_key).is_empty():
		akkadian = _text(str(excerpt.akkadian_key))
	var carved := Cuneiform.from_akkadian(akkadian) if not akkadian.is_empty() else paraphrase
	var voice_url := ""
	if excerpt.get("voice") is String:
		voice_url = str(excerpt.voice)
	_begin(_text(str(quest.get("title_key", ""))), carved, paraphrase, voice_url)


## Closing tablet for a finished quest (epilog body is already localized story text).
func present_epilog(title_key: String, body_key: String) -> void:
	var body := _text(body_key)
	_begin(_text(title_key), Cuneiform.from_akkadian(body) if _looks_latin_akkadian(body) else body, body, "")


func _looks_latin_akkadian(text: String) -> bool:
	return text.contains("š") or text.contains("ḫ") or text.contains("ṣ") or text.contains("ṭ")


func _begin(title: String, carved: String, subtitle: String, voice_url: String) -> void:
	_stop_carving()
	_title.text = title
	_carve_text = carved
	_split_sides(carved)
	_subtitle_text = subtitle
	_carve_index = 0
	_subtitle_index = 0
	_elapsed = 0.0
	_flipped = false
	_flipping = false
	if _tablet_root != null:
		_tablet_root.rotation = Vector3.ZERO
	_front_label.text = ""
	_back_label.text = ""
	_subtitles.text = ""
	_dismiss.visible = false
	_voice_url = ""
	_voice.stop()
	_voice.stream = null
	_duration = maxf(MIN_DURATION_SEC, maxf(carved.length(), subtitle.length()) * FALLBACK_CHAR_SEC)
	_carving = true
	show()
	_resize()
	set_process(true)
	if not voice_url.is_empty() and story != null and voice_enabled:
		_voice_url = voice_url
		story.fetch_media(_voice_url)


## Packs as much of `carved` as fits on the front face; the rest waits for the reverse.
func _split_sides(carved: String) -> void:
	_side_a = carved
	_side_b = ""
	if carved.is_empty() or _cuneiform_font == null:
		return
	var max_w := FACE_W_M / LABEL_PIXEL_SIZE
	var max_h := FACE_H_M / LABEL_PIXEL_SIZE
	var lo := 0
	var hi := carved.length()
	var fit := 0
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var chunk := carved.substr(0, mid)
		var size := _cuneiform_font.get_multiline_string_size(
			chunk, HORIZONTAL_ALIGNMENT_LEFT, max_w, CUNEIFORM_FONT_SIZE, -1, TextServer.BREAK_WORD_BOUND
		)
		if size.y <= max_h + 1.0:
			fit = mid
			lo = mid + 1
		else:
			hi = mid - 1
	# Prefer a break at whitespace / newline when splitting mid-tablet.
	if fit > 0 and fit < carved.length():
		var soft := carved.rfind(" ", fit)
		var soft_nl := carved.rfind("\n", fit)
		var break_at := maxi(soft, soft_nl)
		if break_at >= int(float(fit) * 0.55):
			fit = break_at + 1
	# If metrics refuse even one sign (missing font glyphs), fall back to a half split.
	if fit <= 0 and carved.length() > 1:
		fit = carved.length() >> 1
	_side_a = carved.substr(0, fit)
	_side_b = carved.substr(fit)


func media_ready(url: String, resource: Resource) -> void:
	if not visible or url != _voice_url or not resource is AudioStream or not voice_enabled:
		return
	_voice.stream = resource
	var length := (resource as AudioStream).get_length()
	if length > 0.5:
		var progress := clampf(_elapsed / _duration, 0.0, 1.0)
		_duration = maxf(MIN_DURATION_SEC, length)
		_elapsed = progress * _duration
	_voice.play()


func _process(delta: float) -> void:
	if not _carving or _flipping:
		return
	_elapsed += delta
	var progress := clampf(_elapsed / _duration, 0.0, 1.0)
	_carve_index = mini(_carve_text.length(), int(ceil(progress * float(_carve_text.length()))))
	_subtitle_index = mini(_subtitle_text.length(), int(ceil(progress * float(_subtitle_text.length()))))
	_apply_carve(_carve_index)
	_subtitles.text = _subtitle_text.substr(0, _subtitle_index)
	if progress >= 1.0 and (not _voice.playing or _voice.stream == null):
		_finish_carving()


func _apply_carve(index: int) -> void:
	var a_len := _side_a.length()
	if index <= a_len:
		_front_label.text = _side_a.substr(0, index)
		_back_label.text = ""
		return
	if not _flipped and not _side_b.is_empty():
		_front_label.text = _side_a
		_start_flip()
		return
	_front_label.text = _side_a
	_back_label.text = _side_b.substr(0, mini(_side_b.length(), index - a_len))


func _start_flip() -> void:
	if _flipping or _flipped or _tablet_root == null:
		return
	_flipping = true
	if _flip_tween != null:
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_flip_tween.tween_property(_tablet_root, "rotation:y", PI, FLIP_SEC)
	_flip_tween.finished.connect(_on_flip_done, CONNECT_ONE_SHOT)


func _on_flip_done() -> void:
	_flipping = false
	_flipped = true
	_back_label.text = ""
	# Catch up carving that waited during the flip.
	if _carving:
		_apply_carve(_carve_index)


func _finish_carving() -> void:
	_carving = false
	set_process(false)
	_subtitles.text = _subtitle_text
	if not _side_b.is_empty() and not _flipped:
		_front_label.text = _side_a
		_start_flip()
		if _flip_tween != null:
			_flip_tween.finished.connect(func() -> void:
				_back_label.text = _side_b
				_dismiss.visible = true
			, CONNECT_ONE_SHOT)
			return
	_front_label.text = _side_a
	_back_label.text = _side_b
	_dismiss.visible = true


func _on_backdrop() -> void:
	if _carving or _flipping:
		_elapsed = _duration
		if _flipping and _flip_tween != null:
			_flip_tween.kill()
			if _tablet_root != null:
				_tablet_root.rotation.y = PI
			_flipping = false
			_flipped = true
		_finish_carving()
		if _voice.playing:
			_voice.stop()
	else:
		hide_tablet()


func hide_tablet() -> void:
	_stop_carving()
	hide()
	closed.emit()


func _stop_carving() -> void:
	_carving = false
	_flipping = false
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null
	set_process(false)
	_voice.stop()
	_voice.stream = null
	_voice_url = ""


func set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, MAX_VOLUME)
	if _voice != null:
		_voice.volume_db = _db(VOICE_DB, voice_volume)


func set_voice_enabled(value: bool) -> void:
	voice_enabled = value
	if not value and _voice != null:
		_voice.stop()


func _text(key: String) -> String:
	if key.is_empty():
		return ""
	return story.text(key) if story != null else key


static func _db(base: float, volume: float) -> float:
	return -80.0 if volume <= 0.001 else base + linear_to_db(clampf(volume, 0.0, MAX_VOLUME))
