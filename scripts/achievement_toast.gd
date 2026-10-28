extends CanvasLayer
## The banner of a newly earned achievement: it slides down at the top of the screen with the
## icon, "Achievement unlocked" and the title, plays the level fanfare and leaves after five
## seconds. Several in a row wait in a queue and come one after another.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const ItemIcons := preload("res://scripts/item_icons.gd")
const SHOW_SECONDS := 5.0
const SLIDE_SECONDS := 0.35
const MAX_QUEUE := 8

## The interface sounds (interface_audio.gd); may be null.
var audio: Node
var panel: PanelContainer
var _icon: TextureRect
var _heading: Label
var _title: Label
var _queue: Array[Dictionary] = []
var _busy := false

func _ready() -> void:
	# Above every panel and menu (the ESC menu is 30); it never takes the pointer.
	layer = 40
	panel = PanelContainer.new()
	panel.name = "AchievementToast"
	panel.theme_type_variation = &"FramePanel"
	panel.add_theme_stylebox_override("panel", UiTheme.framed_style(Color(UiTheme.CLAY, 0.96), UiTheme.GOLD_BRIGHT, 28.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(56, 56)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_heading = Label.new()
	_heading.theme_type_variation = &"HeaderLabel"
	_heading.add_theme_font_size_override("font_size", 14)
	_heading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.add_child(_heading)
	_title = Label.new()
	_title.theme_type_variation = &"GoldLabel"
	_title.add_theme_font_size_override("font_size", 22)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.add_child(_title)
	panel.hide()

## Translates an entry's text (achievements_client.gd `text`); English keys when unset.
var texts: Callable

## Queues the banner of a validated achievement entry.
func show_achievement(achievement: Dictionary) -> void:
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append(achievement)
	if not _busy:
		_next()

func is_showing() -> bool:
	return _busy

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		panel.hide()
		return
	_busy = true
	var achievement: Dictionary = _queue.pop_front()
	_icon.texture = ItemIcons.texture(str(achievement.get("icon", "")))
	if _icon.texture == null:
		_icon.texture = preload("res://assets/kenney/game-icons/trophy.png")
	_heading.text = tr("Achievement unlocked")
	_title.text = texts.call(achievement, "title") if texts.is_valid() else tr(str(achievement.get("title", "")))
	panel.reset_size()
	var screen := get_viewport().get_visible_rect().size
	var width := panel.get_combined_minimum_size().x
	var shown_y := 18.0
	panel.position = Vector2((screen.x - width) / 2.0, -panel.get_combined_minimum_size().y - 8.0)
	panel.modulate.a = 0.0
	panel.show()
	if is_instance_valid(audio):
		audio.play("fanfare")
	var tween := panel.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:y", shown_y, SLIDE_SECONDS)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, SLIDE_SECONDS)
	tween.tween_interval(SHOW_SECONDS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, SLIDE_SECONDS)
	tween.parallel().tween_property(panel, "position:y", shown_y - 24.0, SLIDE_SECONDS)
	tween.tween_callback(_next)
