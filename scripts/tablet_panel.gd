extends CanvasLayer
## Clay tablet prologue when a story quest first opens: title, paraphrase, optional Akkadian.

signal closed

var story: Node
var _title: Label
var _paraphrase: Label
var _akkadian: Label
var _panel: PanelContainer

func _ready() -> void:
	layer = 5
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hide_tablet()
	)
	add_child(backdrop)
	_panel = PanelContainer.new()
	add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.72, 0.58, 0.38)
	style.border_color = Color(0.42, 0.30, 0.16)
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(28)
	_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.22, 0.14, 0.08))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(0.42, 0.30, 0.16, 0.7)
	column.add_child(rule)
	_paraphrase = Label.new()
	_paraphrase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paraphrase.add_theme_font_size_override("font_size", 16)
	_paraphrase.add_theme_color_override("font_color", Color(0.18, 0.12, 0.07))
	_paraphrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_paraphrase)
	_akkadian = Label.new()
	_akkadian.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_akkadian.add_theme_font_size_override("font_size", 14)
	_akkadian.add_theme_color_override("font_color", Color(0.35, 0.22, 0.12))
	_akkadian.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_akkadian)
	var dismiss := Button.new()
	dismiss.text = tr("Continue")
	dismiss.pressed.connect(hide_tablet)
	column.add_child(dismiss)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(520, screen.x - 40), minf(360, screen.y - 40))
	_panel.position = (screen - dimensions) / 2
	_panel.size = dimensions

## Shows the tablet for a quest entry that carries an `excerpt` (paraphrase / Akkadian keys).
func present(quest: Dictionary) -> void:
	var excerpt: Variant = quest.get("excerpt")
	if not excerpt is Dictionary or not excerpt.get("paraphrase_key") is String:
		return
	_show_text(
		_text(str(quest.get("title_key", ""))),
		_text(str(excerpt.paraphrase_key)),
		excerpt.get("akkadian_key")
	)

## Closing tablet for a finished quest (epilog body is already localized story text).
func present_epilog(title_key: String, body_key: String) -> void:
	_show_text(_text(title_key), _text(body_key), null)

func _show_text(title: String, paraphrase: String, akkadian: Variant) -> void:
	_title.text = title
	_paraphrase.text = paraphrase
	if akkadian is String and not akkadian.is_empty():
		_akkadian.text = _text(akkadian)
		_akkadian.visible = true
	else:
		_akkadian.visible = false
	show()
	_resize()

func hide_tablet() -> void:
	hide()
	closed.emit()

func _text(key: String) -> String:
	if key.is_empty():
		return ""
	return story.text(key) if story != null else key
