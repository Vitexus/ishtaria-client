extends CanvasLayer
## A conversation with a character: the portrait, what they say and what the player can
## answer. It only shows what the server sent; choosing sends the choice back.

signal choice_made(npc_id: String, seq: int, choice: int)
signal closed
## The player asks the character to tell about itself.
signal about_requested(npc_id: String)
## The character speaking starts or stops: while its voice plays, or its words are on screen for a
## time proportional to their length when there is no voice.
signal speaking_changed(npc_id: String, speaking: bool)

const MUSIC_DB := -10.0
const VOICE_DB := 0.0
const MAX_VOLUME := 2.0
const ICONS := "res://assets/kenney/game-icons/"
## The panel is taller while it shows a knowledge card.
const CARD_HEIGHT := 380.0

var panel: PanelContainer
var portrait: TextureRect
var name_label: Label
var speech: Label
var choices_box: VBoxContainer
var music_enabled := true
## Spoken lines follow the same sound setting as the music.
var voice_enabled := true
## Playback levels chosen in the settings (1.0 = the default level, up to MAX_VOLUME).
var music_volume := 1.0
var voice_volume := 1.0
var story: Node
## The area music; a dialogue whose track is already playing there does not start it a second time.
var area_music: Node
var _npc_id := ""
var _seq := 0
var _music: Node
var _music_url := ""
var _voice: AudioStreamPlayer
var _voice_url := ""
var _portrait_url := ""
var _loop := true
var _reply: Dictionary = {}
var _speaking := false
var _speak_until_ms := 0
## While a knowledge card is shown instead of the conversation: its picture and article, and the dialog that asks
## before the browser opens.
var _card_mode := false
var _card_image_url := ""
var _card_url := ""
var _about_pending := false
var _confirm: ConfirmationDialog

func _ready() -> void:
	layer = 4
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.94)
	style.border_color = Color(0.75, 0.6, 0.3)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_border_width(side, 2)
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(160, 200)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)
	name_label = Label.new()
	name_label.name = "Speaker"
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	column.add_child(name_label)
	speech = Label.new()
	speech.name = "Speech"
	speech.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A long text scrolls instead of making the panel taller than the window.
	var speech_scroll := ScrollContainer.new()
	speech_scroll.name = "SpeechScroll"
	speech_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	speech_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	speech_scroll.custom_minimum_size = Vector2(0.0, 48.0)
	speech_scroll.add_child(speech)
	column.add_child(speech_scroll)
	choices_box = VBoxContainer.new()
	choices_box.name = "Choices"
	choices_box.add_theme_constant_override("separation", 4)
	column.add_child(choices_box)
	_music = _new_music_channel()
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.volume_db = _db(VOICE_DB, voice_volume)
	add_child(_voice)
	_confirm = ConfirmationDialog.new()
	_confirm.name = "ConfirmLink"
	_confirm.confirmed.connect(_open_link)
	add_child(_confirm)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var width := minf(760.0, screen.x - 24.0)
	var height := minf(CARD_HEIGHT if _card_mode else 300.0, screen.y - 24.0)
	panel.size = Vector2(width, height)
	# Above the HUD bar when the screen is tall enough for both.
	var margin := 176.0 if screen.y >= 760.0 else 16.0
	panel.position = Vector2((screen.x - width) / 2.0, screen.y - height - margin)
	var picture_width := width * 0.4 if _card_mode else width * 0.25
	portrait.custom_minimum_size = Vector2(minf(300.0 if _card_mode else 160.0, picture_width), minf(200.0, height - 24.0))

func is_open() -> bool:
	return visible

## Shows the server's answer. A closed conversation (`open` false) hides the panel.
func show_reply(reply: Dictionary) -> void:
	if not reply.open:
		close()
		return
	var first: bool = not visible or reply.npc_id != _npc_id
	_reply = reply
	_npc_id = reply.npc_id
	_seq = int(reply.seq)
	_card_mode = false
	_about_pending = false
	_resize()
	_fill_node(reply)
	show()
	if first:
		_start_media(reply)
	_start_voice(reply.node)
	_speak_until_ms = Time.get_ticks_msec() + int(clampf(speech.text.length() * 55.0, 1200.0, 9000.0))
	if choices_box.get_child_count() > 0:
		(choices_box.get_child(0) as Button).grab_focus()

## The character's name, words and answers (also when the conversation returns from a knowledge card).
func _fill_node(reply: Dictionary) -> void:
	name_label.text = _text(reply.name_key)
	speech.text = _text(reply.node.text_key)
	for child in choices_box.get_children():
		choices_box.remove_child(child)
		child.queue_free()
	for choice: Dictionary in reply.node.choices:
		var button := Button.new()
		button.text = _text(choice.text_key)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_choose.bind(int(choice.index)))
		choices_box.add_child(button)
	if reply.get("about") == true:
		var about := Button.new()
		about.name = "About"
		about.text = tr("Tell me about yourself")
		about.alignment = HORIZONTAL_ALIGNMENT_LEFT
		about.pressed.connect(_ask_about)
		choices_box.add_child(about)
	if reply.node.choices.is_empty():
		var leave := Button.new()
		leave.text = tr("Leave")
		leave.name = "Leave"
		leave.pressed.connect(close)
		choices_box.add_child(leave)

## The card could not be fetched: the button works again.
func about_failed() -> void:
	_about_pending = false

func _ask_about() -> void:
	if _about_pending or _npc_id.is_empty():
		return
	_about_pending = true
	about_requested.emit(_npc_id)

## The knowledge card of the character: its picture, a short text and the way to the article. Shown instead of the
## conversation; only while the conversation it was asked in is still the open one.
func show_about(npc_id: String, card: Dictionary) -> void:
	_about_pending = false
	if not visible or npc_id != _npc_id or _card_mode:
		return
	_card_mode = true
	_resize()
	name_label.text = _text(card.title_key)
	speech.text = _text(card.text_key)
	_card_image_url = card.image
	_card_url = preload("res://scripts/story_client.gd").wikipedia_url(card, TranslationServer.get_locale().substr(0, 2))
	portrait.texture = null
	if story != null:
		story.fetch_media(_card_image_url)
	for child in choices_box.get_children():
		choices_box.remove_child(child)
		child.queue_free()
	var credit := Label.new()
	credit.name = "Credit"
	credit.text = _text(card.credit_key)
	credit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.add_theme_font_size_override("font_size", 12)
	credit.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	choices_box.add_child(credit)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 4)
	choices_box.add_child(buttons)
	var back := Button.new()
	back.name = "Back"
	back.text = tr("Back to the conversation")
	back.icon = load(ICONS + "arrowLeft.png") as Texture2D
	back.add_theme_constant_override("icon_max_width", 20)
	back.pressed.connect(_leave_card)
	buttons.add_child(back)
	var link := Button.new()
	link.name = "Wikipedia"
	link.text = tr("Read more on Wikipedia")
	link.icon = load(ICONS + "exitRight.png") as Texture2D
	link.add_theme_constant_override("icon_max_width", 20)
	link.tooltip_text = tr("Opens the article in your web browser")
	link.pressed.connect(_confirm_link)
	buttons.add_child(link)
	back.grab_focus()

## Back from the card to what the character said last.
func _leave_card() -> void:
	if not _card_mode:
		return
	_card_mode = false
	_card_image_url = ""
	_card_url = ""
	_resize()
	_fill_node(_reply)
	var url: String = _reply.get("portrait", "") if _reply.get("portrait") != null else ""
	if not url.is_empty() and story != null:
		story.fetch_media(url)
	else:
		portrait.texture = load("res://assets/branding/portrait_unknown.jpg") as Texture2D
	if choices_box.get_child_count() > 0:
		(choices_box.get_child(0) as Button).grab_focus()

func _confirm_link() -> void:
	if _card_url.is_empty():
		return
	_confirm.ok_button_text = tr("Open in browser")
	_confirm.cancel_button_text = tr("Cancel")
	_confirm.dialog_text = tr("Open this page in your web browser?") + "\n" + _card_url
	_confirm.popup_centered(Vector2i(520, 140))

func _open_link() -> void:
	if _card_mode and _card_url.begins_with("https://"):
		OS.shell_open(_card_url)

func _choose(index: int) -> void:
	_voice.stop()
	choice_made.emit(_npc_id, _seq, index)

func _text(key: String) -> String:
	return story.text(key) if story != null else key

func _start_media(reply: Dictionary) -> void:
	portrait.texture = null
	_portrait_url = reply.get("portrait", "") if reply.get("portrait") != null else ""
	if not _portrait_url.is_empty() and story != null:
		story.fetch_media(_portrait_url)
	else:
		portrait.texture = load("res://assets/branding/portrait_unknown.jpg") as Texture2D
	_loop = true
	if reply.get("music") != null and story != null and music_enabled and not (area_music != null and area_music.current_url == reply.music.url and area_music.gain > 0.3):
		_music_url = reply.music.url
		_loop = reply.music.loop
		story.fetch_media(_music_url)

## Plays the spoken line of the node, if the server sent one for the interface language.
func _start_voice(node: Dictionary) -> void:
	_voice.stop()
	_voice.stream = null
	_voice_url = ""
	if node.get("voice") != null and story != null and voice_enabled:
		_voice_url = node.voice
		story.fetch_media(_voice_url)

## A portrait or track arrived; it is used only if the conversation still wants it.
func media_ready(url: String, resource: Resource) -> void:
	if not visible:
		return
	if _card_mode and url == _card_image_url and resource is Texture2D:
		portrait.texture = resource
	elif not _card_mode and url == _portrait_url and resource is Texture2D:
		portrait.texture = resource
	elif url == _voice_url and resource is AudioStream and voice_enabled:
		_voice.stream = resource
		_voice.play()
	elif url == _music_url and resource is AudioStream and music_enabled:
		if resource is AudioStreamOggVorbis:
			resource.loop = _loop
		# A track still fading out from an earlier conversation keeps going; this one starts beside it.
		if _music.stream != null:
			_retire_music()
		_music.start(resource, _loop, 1.0, url)

func _new_music_channel() -> Node:
	var channel := preload("res://scripts/music_channel.gd").new()
	channel.name = "Music"
	channel.base_db = MUSIC_DB
	channel.volume = music_volume
	add_child(channel)
	return channel

## The track of the conversation is not cut off: it fades out to the end and then goes away.
func _retire_music() -> void:
	if _music.stream != null:
		_music.free_when_done = true
		_music.fade_out()
		_music = _new_music_channel()

## Whether the dialogue plays a track of its own that the area music has to give way to.
func has_own_music() -> bool:
	return _music != null and _music.stream != null and _music.target > 0.0

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	if not value:
		_music.stop_now()

static func _db(base: float, volume: float) -> float:
	return -80.0 if volume <= 0.001 else base + linear_to_db(clampf(volume, 0.0, MAX_VOLUME))

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, MAX_VOLUME)
	if _music != null:
		_music.volume = music_volume

func set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, MAX_VOLUME)
	if _voice != null:
		_voice.volume_db = _db(VOICE_DB, voice_volume)

func set_voice_enabled(value: bool) -> void:
	voice_enabled = value
	if not value:
		_voice.stop()

func _process(_delta: float) -> void:
	_set_speaking(visible and not _npc_id.is_empty() and (_voice.playing or Time.get_ticks_msec() < _speak_until_ms))

func _set_speaking(value: bool) -> void:
	if value != _speaking:
		_speaking = value
		speaking_changed.emit(_npc_id, value)

func close() -> void:
	if not visible and _npc_id.is_empty():
		return
	_speak_until_ms = 0
	_set_speaking(false)
	_retire_music()
	_music_url = ""
	_voice.stop()
	_voice.stream = null
	_voice_url = ""
	_portrait_url = ""
	_card_mode = false
	_card_image_url = ""
	_card_url = ""
	_about_pending = false
	_confirm.hide()
	_npc_id = ""
	_resize()
	hide()
	closed.emit()
