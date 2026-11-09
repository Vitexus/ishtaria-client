extends CanvasLayer
## Quest prologue on the 3D Sumerian clay tablet: cuneiform is carved sign by sign on the
## front face; when that side is full the tablet flips and carving continues on the blank reverse;
## when the reverse is full too, the written tablet slides away and a blank one takes its place.
## The narrator speaks the paraphrase; readable subtitles run along the bottom.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const Cuneiform := preload("res://scripts/cuneiform.gd")

signal closed

const TABLET_SCENE := "res://assets/models/sumerian_clay_tablet/sumerian_clay_tablet.glb"
const BLANK_ALBEDO := "res://assets/models/sumerian_clay_tablet/textures/T_AncientClayBlank_BaseColor.png"
const BLANK_NORMAL := "res://assets/models/sumerian_clay_tablet/textures/T_AncientClayBlank_Normal.png"

const VOICE_DB := 0.0
const MAX_VOLUME := 2.0
const MIN_DURATION_SEC := 4.0
const FALLBACK_CHAR_SEC := 0.045
const FLIP_SEC := 0.85
## A written tablet slides this far aside (metres, out of view) and a blank one slides in, each in SLIDE_SEC.
const SLIDE_M := 0.17
const SLIDE_SEC := 0.7
## Usable writing area on one face (metres), inset from the rounded rim.
const FACE_W_M := 0.082
const FACE_H_M := 0.055
const FACE_Z_M := 0.0082
## Small script, as a scribe packs it close to the rim: about 70 % of the former glyph size, drawn from a
## larger raster so the wedges stay sharp.
const LABEL_PIXEL_SIZE := 0.00007
const CUNEIFORM_FONT_SIZE := 64
## Pixels added between rows (negative: the cuneiform font's line height leaves far more room than a scribe).
const LINE_SPACING := -36.0
## Fresh, still wet clay (the reference is a photo of cuneiform pressed into fresh clay): darker and
## greyer than fired terracotta, with a damp sheen.
const WET_CLAY_TINT := Color(0.50, 0.55, 0.64)
const WET_CLAY_ROUGHNESS := 0.45
## The layers of an impressed sign: name, colour, offset (metres) on the front face. The key light comes
## from the upper left, so the wall of a wedge under it falls into shadow and the far, lower right wall
## catches the light. The reverse is turned about the vertical axis, so its offsets mirror in x.
## The stylus is a narrow three-sided pyramid: a wedge is a deep head sloping up to a thin tail, with one face
## toward the light and two away. So: a faint rim catch-light on the lit edge, a soft wide shadow and a hard
## narrow one on the far side, and the dark wet floor of the impression on top.
const IMPRESSION_LAYERS := [
	["SoftShadow", Color(0.07, 0.05, 0.04, 0.32), Vector3(-0.00024, 0.00024, 0.00001)],
	["LitWall", Color(0.90, 0.80, 0.64, 0.60), Vector3(0.00015, -0.00015, 0.00002)],
	["ShadowWall", Color(0.09, 0.06, 0.04, 0.88), Vector3(-0.00011, 0.00011, 0.00004)],
	["Floor", Color(0.27, 0.19, 0.13, 0.96), Vector3(0.0, 0.0, 0.00006)],
]
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
var _front_label: Node3D
var _back_label: Node3D
var _subtitles: Label
var _subtitle_bar: PanelContainer
var _dismiss: Button
var _voice: AudioStreamPlayer
var _voice_url := ""
var _carve_text := ""
## The text of each face in order: front and reverse of the first tablet, then of the next ones.
var _faces := PackedStringArray()
## Where each face starts in `_carve_text`.
var _face_starts: Array[int] = []
## The face being carved (or last carved).
var _face := 0
var _subtitle_text := ""
var _carve_index := 0
var _subtitle_index := 0
var _elapsed := 0.0
var _duration := MIN_DURATION_SEC
var _carving := false
var _turning := false
var _turn_tween: Tween
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
	if model is Node3D:
		_blank_clay_materials(model)
		# The model is exported Y-up with its writing face up; stand that face toward the camera (+Z).
		(model as Node3D).rotation_degrees = Vector3(90, 0, 0)
		tilt.add_child(model)
	else:
		push_warning("Clay tablet GLB missing; prologue uses a stand-in box.")
		var stand_in := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.065, 0.016)
		stand_in.mesh = box
		stand_in.material_override = _blank_material()
		tilt.add_child(stand_in)

	_front_label = _make_face_label("FrontScript", false)
	_front_label.position = Vector3(0.0, 0.0, FACE_Z_M)
	tilt.add_child(_front_label)

	_back_label = _make_face_label("BackScript", true)
	_back_label.position = Vector3(0.0, 0.0, -FACE_Z_M)
	_back_label.rotation_degrees = Vector3(0, 180, 0)
	tilt.add_child(_back_label)

	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.position = Vector3(0.0, 0.012, 0.16)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


## One face of script, drawn as wedges pressed into fresh wet clay rather than ink on it: the wall of each
## wedge toward the light falls into shadow, the far wall catches the light, the floor is the clay's own
## darker, wetter colour (the stylus squeezes water to the surface).
func _make_face_label(node_name: String, reverse: bool) -> Node3D:
	var face := Node3D.new()
	face.name = node_name
	for index in IMPRESSION_LAYERS.size():
		var layer: Array = IMPRESSION_LAYERS[index]
		var label := Label3D.new()
		# The layers lie in one plane: draw them in a fixed order (walls first, the floor over them),
		# not by distance, which flickers between frames.
		label.render_priority = index
		label.name = layer[0]
		label.font = _cuneiform_font
		label.font_size = CUNEIFORM_FONT_SIZE
		label.pixel_size = LABEL_PIXEL_SIZE
		label.modulate = layer[1]
		label.position = layer[2]
		if reverse:
			label.position.x = -label.position.x
		label.shaded = true
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		# Rows are broken by _split_sides, so what is measured is what is drawn.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.outline_size = 0
		label.line_spacing = LINE_SPACING
		# A Label3D hangs its text from its origin: put that at the top left of the writing area.
		label.position += Vector3(-FACE_W_M * 0.5, FACE_H_M * 0.5, 0.0)
		label.text = ""
		face.add_child(label)
	return face


## Shows `text` on every layer of a face.
func _set_face_text(face: Node3D, text: String) -> void:
	for label: Label3D in face.get_children():
		label.text = text



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
	mat.albedo_color = Color(0.50, 0.40, 0.30)
	var albedo := _load_texture(BLANK_ALBEDO)
	if albedo != null:
		mat.albedo_texture = albedo
		mat.albedo_color = WET_CLAY_TINT
	# Wet clay is smooth and damp: no roughness map (that is the dry, crumbly look), a soft sheen instead.
	# No clearcoat: on the writing face's coarse normal map it blows into bright squares.
	mat.roughness = WET_CLAY_ROUGHNESS
	var normal := _load_texture(BLANK_NORMAL)
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 0.35
	mat.metallic = 0.0
	mat.metallic_specular = 0.25
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
	_split_sides(carved)  # also re-lays `_carve_text` in rows
	_subtitle_text = subtitle
	_carve_index = 0
	_subtitle_index = 0
	_elapsed = 0.0
	_face = 0
	if _tablet_root != null:
		_tablet_root.rotation = Vector3.ZERO
		_tablet_root.position = Vector3.ZERO
	_set_face_text(_front_label, "")
	_set_face_text(_back_label, "")
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


## Lays `carved` out in ruled rows (the breaks are put in here, the labels do not wrap) and fills the
## faces in order: the front of a tablet, its reverse, then the front of the next tablet.
func _split_sides(carved: String) -> void:
	_faces = PackedStringArray([carved])
	if carved.is_empty() or _cuneiform_font == null:
		_lay_faces()
		return
	var rows := _rows(carved, FACE_W_M / LABEL_PIXEL_SIZE)
	var per_face := rows_per_face(LABEL_PIXEL_SIZE)
	_faces = PackedStringArray()
	for first in range(0, rows.size(), per_face):
		_faces.append("\n".join(rows.slice(first, first + per_face)))
	if _faces.is_empty():
		_faces.append("")
	_lay_faces()


## Carving runs over exactly what the faces show (the row breaks included), face after face.
func _lay_faces() -> void:
	_carve_text = "".join(_faces)
	_face_starts.clear()
	var start := 0
	for face: String in _faces:
		_face_starts.append(start)
		start += face.length()


## How many ruled rows fit one face at `pixel` metres per font pixel.
func rows_per_face(pixel: float) -> int:
	var row := _cuneiform_font.get_height(CUNEIFORM_FONT_SIZE) + LINE_SPACING
	var glyph := _cuneiform_font.get_height(CUNEIFORM_FONT_SIZE)
	return maxi(1, 1 + int(floor((FACE_H_M / pixel - glyph) / row)))


## Breaks `text` into rows no wider than `width` font pixels: at spaces, or between signs inside a word
## too long for one row.
func _rows(text: String, width: float) -> PackedStringArray:
	var rows: PackedStringArray = []
	for paragraph: String in text.split("\n"):
		var row := ""
		for word: String in paragraph.split(" ", false):
			var joined := word if row.is_empty() else row + " " + word
			if _width(joined) <= width:
				row = joined
				continue
			if not row.is_empty():
				rows.append(row)
				row = ""
			for sign: String in word:
				if not row.is_empty() and _width(row + sign) > width:
					rows.append(row)
					row = ""
				row += sign
		if not row.is_empty():
			rows.append(row)
	return rows


func _width(text: String) -> float:
	return _cuneiform_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CUNEIFORM_FONT_SIZE).x


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
	if not _carving or _turning:
		return
	_elapsed += delta
	var progress := clampf(_elapsed / _duration, 0.0, 1.0)
	_carve_index = mini(_carve_text.length(), int(ceil(progress * float(_carve_text.length()))))
	_subtitle_index = mini(_subtitle_text.length(), int(ceil(progress * float(_subtitle_text.length()))))
	_apply_carve(_carve_index)
	_subtitles.text = _subtitle_text.substr(0, _subtitle_index)
	if _turning:
		return
	if progress >= 1.0 and _face == _faces.size() - 1 and (not _voice.playing or _voice.stream == null):
		_finish_carving()


## The face a carving position falls on: the last one that starts before it.
func _face_of(index: int) -> int:
	var face := 0
	for i in _face_starts.size():
		if _face_starts[i] < index:
			face = i
	return face


## The label group showing face `face`: even faces are fronts, odd ones reverses.
func _face_node(face: int) -> Node3D:
	return _front_label if face % 2 == 0 else _back_label


func _apply_carve(index: int) -> void:
	if _face_of(index) > _face:
		# This face is full: finish it, then turn the tablet over or bring a new one.
		_set_face_text(_face_node(_face), _faces[_face])
		_turn_to(_face + 1)
		return
	_set_face_text(_face_node(_face), _faces[_face].substr(0, maxi(0, index - _face_starts[_face])))


## Turns to face `face`: a reverse is reached by flipping the tablet; past a reverse the written tablet
## slides away to the side and a blank one slides in from the other.
func _turn_to(face: int) -> void:
	if _turning or _tablet_root == null:
		return
	_turning = true
	if _turn_tween != null:
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if face % 2 == 1:
		_turn_tween.tween_property(_tablet_root, "rotation:y", PI, FLIP_SEC)
	else:
		_turn_tween.tween_property(_tablet_root, "position:x", -SLIDE_M, SLIDE_SEC)
		_turn_tween.tween_callback(func() -> void:
			_tablet_root.rotation.y = 0.0
			_tablet_root.position.x = SLIDE_M
			_set_face_text(_front_label, "")
			_set_face_text(_back_label, "")
		)
		_turn_tween.tween_property(_tablet_root, "position:x", 0.0, SLIDE_SEC)
	_turn_tween.finished.connect(func() -> void:
		_turning = false
		_face = face
		# Catch up carving that waited during the turn.
		if _carving:
			_apply_carve(_carve_index)
	, CONNECT_ONE_SHOT)


## Ends the carving at once: the last tablet, written to the end, faces the player.
func _finish_carving() -> void:
	_carving = false
	set_process(false)
	_kill_turn()
	_subtitles.text = _subtitle_text
	_face = _faces.size() - 1
	var front := _face - _face % 2
	_set_face_text(_front_label, _faces[front])
	_set_face_text(_back_label, _faces[front + 1] if front + 1 < _faces.size() else "")
	if _tablet_root != null:
		_tablet_root.position.x = 0.0
		_tablet_root.rotation.y = PI if _face % 2 == 1 else 0.0
	_dismiss.visible = true


func _kill_turn() -> void:
	if _turn_tween != null:
		_turn_tween.kill()
		_turn_tween = null
	_turning = false


func _on_backdrop() -> void:
	if _carving or _turning:
		_elapsed = _duration
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
	_kill_turn()
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
