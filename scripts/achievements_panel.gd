extends CanvasLayer
## The achievements of the character: a card for each one of the catalog, earned ones in gold
## with the day they were earned, the others dimmed, secret ones as "???" until earned. Tabs
## filter by category; the bar shows how many are earned. Opened from the ESC menu; the data
## comes from achievements_client.gd and nothing here changes it.

signal closed

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ItemIcons := preload("res://scripts/item_icons.gd")
const CATEGORIES := ["", "progress", "gathering", "magic", "social", "story"]
const CATEGORY_KEYS := ["All", "Progress", "Gathering", "Magic", "Social", "Story"]
const TROPHY := preload("res://assets/kenney/game-icons/trophy.png")
const LOCKED := preload("res://assets/kenney/game-icons/locked.png")

var grid: GridContainer
var progress_label: Label
var progress_bar: ProgressBar
var empty_label: Label
var _card: Control
var _title: Label
var _tabs: TabBar
var _close: Button
var _data := {"achievements": [], "earned": []}

func _ready() -> void:
	layer = 30
	add_child(UiKit.backdrop(0.85))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := UiKit.framed_panel(center, 10)
	_card = column.get_parent()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var trophy := TextureRect.new()
	trophy.texture = TROPHY
	trophy.modulate = UiTheme.GOLD
	trophy.custom_minimum_size = Vector2(32, 32)
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(trophy)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(_title)
	progress_label = Label.new()
	progress_label.name = "Progress"
	progress_label.theme_type_variation = &"GoldLabel"
	progress_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	progress_label.add_theme_font_size_override("font_size", 20)
	header.add_child(progress_label)
	_close = UiKit.icon_button(preload("res://assets/kenney/game-icons/cross.png"), "back")
	_close.pressed.connect(close)
	header.add_child(_close)
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = 10
	column.add_child(progress_bar)
	_tabs = TabBar.new()
	_tabs.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	# On a narrow window the tabs scroll instead of widening the card.
	_tabs.clip_tabs = true
	for key in CATEGORY_KEYS:
		_tabs.add_tab(key)
	_tabs.tab_changed.connect(func(_tab: int) -> void: _render())
	column.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "Achievements"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	empty_label = Label.new()
	empty_label.theme_type_variation = &"MutedLabel"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(empty_label)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_update_texts()
	hide()

func open() -> void:
	show()
	_fit()
	_render()
	UiKit.open_animated(_card)
	_close.grab_focus()

func close() -> void:
	hide()
	closed.emit()

## Translates an entry's text (achievements_client.gd `text`); English keys when unset.
var texts: Callable

## Shows a validated reply of achievements_client.gd.
func show_data(data: Dictionary) -> void:
	_data = data
	if visible:
		_render()

func earned_count() -> int:
	return _data.earned.size()

## The card fills most of a small window and stops at 960x680; cards go three, two or one in a row.
func _fit() -> void:
	if not is_instance_valid(_card):
		return
	var screen := get_viewport().get_visible_rect().size
	_card.custom_minimum_size = Vector2(minf(960.0, screen.x - 24.0), minf(680.0, screen.y - 24.0))
	var width := _card.custom_minimum_size.x
	grid.columns = 3 if width >= 900.0 else (2 if width >= 560.0 else 1)

func _earned_at(id: String) -> int:
	for earned: Dictionary in _data.earned:
		if earned.id == id:
			return int(earned.unlocked_at)
	return 0

func _render() -> void:
	if not is_instance_valid(grid):
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var total: int = _data.achievements.size()
	progress_label.text = "%d / %d" % [earned_count(), total]
	progress_bar.max_value = maxi(total, 1)
	progress_bar.value = earned_count()
	var category: String = CATEGORIES[clampi(_tabs.current_tab, 0, CATEGORIES.size() - 1)]
	var shown := 0
	# Earned first, newest first; then the rest in catalog order.
	var entries: Array = _data.achievements.filter(func(entry: Dictionary) -> bool: return category.is_empty() or entry.category == category)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _earned_at(a.id) > _earned_at(b.id)
	)
	for entry: Dictionary in entries:
		_add_card(entry, _earned_at(entry.id))
		shown += 1
	empty_label.text = tr("Connect to a server first") if total == 0 else ""
	empty_label.visible = shown == 0

func _add_card(entry: Dictionary, unlocked_at: int) -> void:
	var earned := unlocked_at > 0
	var secret: bool = entry.hidden and not earned
	var card := PanelContainer.new()
	# A node name cannot hold the `:` of a datadisk achievement.
	card.name = "Achievement_" + entry.id.replace(":", "_")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.85 if earned else 0.55), UiTheme.GOLD if earned else Color(UiTheme.GOLD_DIM, 0.45), 2 if earned else 1, 3, 12.0)
	if earned:
		style.shadow_color = Color(UiTheme.GOLD, 0.18)
		style.shadow_size = 6
	card.add_theme_stylebox_override("panel", style)
	grid.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = LOCKED if secret else ItemIcons.texture(entry.icon)
	if icon.texture == null:
		icon.texture = TROPHY
	icon.modulate = Color.WHITE if earned else Color(0.62, 0.56, 0.5, 0.85)
	if secret:
		icon.modulate = UiTheme.GOLD_DIM
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var title := Label.new()
	title.name = "Title"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = &"GoldLabel" if earned else &""
	title.text = "???" if secret else _text(entry, "title")
	if not earned:
		title.add_theme_color_override("font_color", UiTheme.SAND_MUTED)
	title.add_theme_font_size_override("font_size", 18)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var description := Label.new()
	description.theme_type_variation = &"MutedLabel"
	description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = tr("A secret achievement") if secret else _text(entry, "description")
	text.add_child(description)
	if earned:
		var date := Label.new()
		date.name = "Earned"
		date.theme_type_variation = &"MutedLabel"
		date.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		date.add_theme_font_size_override("font_size", 12)
		date.add_theme_color_override("font_color", UiTheme.GOLD_DIM.lightened(0.3))
		var day := Time.get_datetime_dict_from_unix_time(unlocked_at)
		date.text = tr("Earned %s") % ("%d. %d. %d" % [day.day, day.month, day.year])
		text.add_child(date)

func _update_texts() -> void:
	if not is_instance_valid(_title):
		return
	_title.text = tr("Achievements")
	_close.tooltip_text = tr("Close")
	for index in CATEGORY_KEYS.size():
		_tabs.set_tab_title(index, tr(CATEGORY_KEYS[index]))
	_render()

func _text(entry: Dictionary, key: String) -> String:
	return texts.call(entry, key) if texts.is_valid() else tr(str(entry.get(key, "")))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
