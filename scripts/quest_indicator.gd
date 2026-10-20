extends CanvasLayer
## The active quest in the top left corner of the screen: its name and a reminder of the key that opens the
## quest log. The active quest is the most recently changed one that is not finished; with none the corner is empty.

const MARGIN := 12.0

var story: Node
## The key bindings: the reminder shows the key the player has chosen for the quest log.
var controls: Node
var panel: PanelContainer
var heading: Label
var title: Label
var hint: Label
var _quests: Array = []
var _key := ""

func _ready() -> void:
	layer = 3
	panel = PanelContainer.new()
	panel.name = "Indicator"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(MARGIN, MARGIN)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	style.border_color = Color(0.75, 0.6, 0.3)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_border_width(side, 2)
		style.set_content_margin(side, 8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	heading = _label(12, Color(0.7, 0.7, 0.72))
	column.add_child(heading)
	title = _label(16, Color(1.0, 0.85, 0.5))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(220, 0)
	column.add_child(title)
	hint = _label(12, Color(0.8, 0.8, 0.82))
	column.add_child(hint)
	if story != null and story.has_signal("strings_changed"):
		story.strings_changed.connect(_refresh)
	_refresh()

func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

## The quests the server sent (most recently changed first).
func set_quests(quests: Array) -> void:
	_quests = quests.duplicate(true)
	_refresh()

## The quest the indicator shows, or an empty dictionary.
func active_quest() -> Dictionary:
	for quest: Variant in _quests:
		if quest is Dictionary and not quest.get("final", false):
			return quest
	return {}

func _process(_delta: float) -> void:
	if visible and _key != _key_text():
		_refresh()

func _key_text() -> String:
	if controls == null:
		return ""
	return OS.get_keycode_string(controls.key_for(controls.QUEST_LOG))

func _refresh() -> void:
	if panel == null:
		return
	var quest := active_quest()
	visible = not quest.is_empty()
	if quest.is_empty():
		return
	_key = _key_text()
	heading.text = tr("Active quest")
	title.text = story.text(quest.title_key) if story != null else str(quest.title_key)
	hint.text = "[%s] %s" % [_key, tr("Quest log")]
