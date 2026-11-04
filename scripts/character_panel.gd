extends CanvasLayer
## The window of the character (key `K`, the person button of the HUD): its statistics (level, experience, score, days
## lived, gold and the five reserves) and a summary of its achievements with a button to the full list. The data are the
## validated profile that main.gd already gives the HUD and the reply of achievements_client.gd; nothing here changes the game.

signal closed
signal achievements_requested

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const LifeOrdinal := preload("res://scripts/life_ordinal.gd")
const ItemIcons := preload("res://scripts/item_icons.gd")
const PERSON := preload("res://assets/kenney/game-icons/singleplayer.png")
const TROPHY := preload("res://assets/kenney/game-icons/trophy.png")
const RESERVES := [["health", "Health"], ["stamina", "Stamina"], ["food", "Food"], ["water", "Water"], ["mana", "Mana"]]
## How many of the newest earned achievements the summary shows.
const LATEST := 6

var name_label: Label
var level_label: Label
var experience_label: Label
var experience_bar: ProgressBar
var score_value: Label
var age_value: Label
var gold_value: Label
var reserve_values := {}
var achievements_label: Label
var achievements_bar: ProgressBar
var latest_list: VBoxContainer
var all_button: Button
## Translates an entry of the achievements catalog (achievements_client.gd `text`).
var texts: Callable

## The framed card (for tests of the look: it must fit the window).
var panel: Control
var _card: Control
var _title: Label
var _close: Button
var _labels := {}
var _profile := {}
var _data := {"achievements": [], "earned": []}

func _ready() -> void:
	layer = 30
	add_child(UiKit.backdrop(0.85))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := UiKit.framed_panel(center, 10)
	_card = column.get_parent()
	panel = _card
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var person := TextureRect.new()
	person.texture = PERSON
	person.modulate = UiTheme.GOLD
	person.custom_minimum_size = Vector2(32, 32)
	person.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	person.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(person)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(_title)
	_close = UiKit.icon_button(preload("res://assets/kenney/game-icons/cross.png"), "back")
	_close.pressed.connect(close)
	header.add_child(_close)

	# Everything below the header scrolls on a small window; the button to the full list stays at the bottom.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 12)
	body.add_child(who)
	name_label = Label.new()
	name_label.name = "Name"
	name_label.theme_type_variation = &"GoldLabel"
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(name_label)
	level_label = Label.new()
	level_label.name = "Level"
	level_label.add_theme_font_size_override("font_size", 20)
	level_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(level_label)

	experience_label = Label.new()
	experience_label.name = "Experience"
	experience_label.theme_type_variation = &"MutedLabel"
	experience_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.add_child(experience_label)
	experience_bar = ProgressBar.new()
	experience_bar.name = "ExperienceBar"
	experience_bar.show_percentage = false
	experience_bar.custom_minimum_size.y = 12
	_style_bar(experience_bar)
	body.add_child(experience_bar)

	var stats := GridContainer.new()
	stats.name = "Statistics"
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 24)
	stats.add_theme_constant_override("v_separation", 6)
	body.add_child(stats)
	score_value = _stat_row(stats, "Score", "Score")
	age_value = _stat_row(stats, "Age", "Age")
	gold_value = _stat_row(stats, "Gold", "Gold")
	for reserve: Array in RESERVES:
		reserve_values[reserve[0]] = _stat_row(stats, "Reserve_" + str(reserve[0]), str(reserve[1]))

	body.add_child(UiKit.divider())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	body.add_child(head)
	var trophy := TextureRect.new()
	trophy.texture = TROPHY
	trophy.modulate = UiTheme.GOLD
	trophy.custom_minimum_size = Vector2(24, 24)
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(trophy)
	var achievements_title := Label.new()
	achievements_title.name = "AchievementsTitle"
	achievements_title.theme_type_variation = &"HeaderLabel"
	achievements_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	achievements_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_child(achievements_title)
	_labels["achievements_title"] = achievements_title
	achievements_label = Label.new()
	achievements_label.name = "AchievementsProgress"
	achievements_label.theme_type_variation = &"GoldLabel"
	achievements_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_child(achievements_label)
	achievements_bar = ProgressBar.new()
	achievements_bar.name = "AchievementsBar"
	achievements_bar.show_percentage = false
	achievements_bar.custom_minimum_size.y = 10
	_style_bar(achievements_bar)
	body.add_child(achievements_bar)
	latest_list = VBoxContainer.new()
	latest_list.name = "Latest"
	latest_list.add_theme_constant_override("separation", 4)
	body.add_child(latest_list)
	all_button = UiKit.button("", &"PrimaryButton")
	all_button.name = "AllAchievements"
	all_button.pressed.connect(func() -> void: achievements_requested.emit())
	column.add_child(all_button)

	get_viewport().size_changed.connect(_fit)
	_fit()
	_update_texts()
	hide()

## The bars of the HUD: a dark clay trough and a glazed gold fill.
func _style_bar(bar: ProgressBar) -> void:
	var background := UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.95), Color(UiTheme.GOLD_DIM, 0.7), 1, 3, 0.0)
	background.content_margin_top = 0.0
	background.content_margin_bottom = 0.0
	var fill := UiTheme.flat_style(UiTheme.GOLD, UiTheme.GOLD.lightened(0.45), 0, 3, 0.0)
	fill.border_width_top = 2
	fill.content_margin_top = 0.0
	fill.content_margin_bottom = 0.0
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)

## A row of the statistics: the muted name on the left, the value on the right.
func _stat_row(grid: GridContainer, node_name: String, label_key: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	grid.add_child(label)
	_labels[node_name] = [label, label_key]
	var value := Label.new()
	value.name = node_name
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)
	return value

func open() -> void:
	show()
	_fit()
	_render()
	UiKit.open_animated(_card)
	_close.grab_focus()

func close() -> void:
	hide()
	closed.emit()

## The validated profile of the HUD (`GET /players/me`).
func set_profile(profile: Dictionary) -> void:
	_profile = profile
	if visible:
		_render()

## The validated reply of achievements_client.gd.
func show_data(data: Dictionary) -> void:
	_data = data
	if visible:
		_render()

func _fit() -> void:
	if not is_instance_valid(_card):
		return
	var screen := get_viewport().get_visible_rect().size
	_card.custom_minimum_size = Vector2(minf(720.0, screen.x - 24.0), minf(600.0, screen.y - 24.0))

func _earned_at(id: String) -> int:
	for earned: Dictionary in _data.earned:
		if earned.id == id:
			return int(earned.unlocked_at)
	return 0

func _render() -> void:
	if not is_instance_valid(name_label):
		return
	var stats: Dictionary = _profile.get("stats", {})
	var signed_in := not _profile.is_empty() and not stats.is_empty()
	name_label.text = LifeOrdinal.with_name(str(_profile.get("username", "")), _profile.get("ordinal")) if signed_in else tr("Not signed in")
	level_label.text = tr("Level %s") % int(stats.get("level", 1)) if signed_in else ""
	var next_level: Variant = stats.get("next_level_experience")
	var floor_xp: Variant = stats.get("level_experience")
	var experience := int(stats.get("experience", 0))
	if signed_in and (next_level is float or next_level is int) and next_level > experience:
		experience_label.text = tr("Experience %s / %s") % [experience, int(next_level)]
	else:
		experience_label.text = tr("Experience %s") % experience if signed_in else ""
	if signed_in and (next_level is float or next_level is int) and (floor_xp is float or floor_xp is int) and next_level > floor_xp:
		experience_bar.max_value = float(next_level) - float(floor_xp)
		experience_bar.value = clampf(float(experience) - float(floor_xp), 0.0, experience_bar.max_value)
	else:
		experience_bar.max_value = 1.0
		experience_bar.value = 0.0
	score_value.text = str(stats["score"]) if stats.has("score") else "-"
	score_value.tooltip_text = tr("Score: 100 per level and 10 per day lived")
	age_value.text = tr("%s days") % _profile.get("life", {}).get("age_days", "-") if signed_in else "-"
	gold_value.text = str(stats.get("gold", "-"))
	for reserve: Array in RESERVES:
		var key: String = reserve[0]
		reserve_values[key].text = "%d / 100" % int(stats[key]) if stats.has(key) else "-"
	_render_achievements()

func _render_achievements() -> void:
	for child in latest_list.get_children():
		latest_list.remove_child(child)
		child.queue_free()
	var total: int = _data.achievements.size()
	var earned: int = _data.earned.size()
	achievements_label.text = "%d / %d" % [earned, total]
	achievements_bar.max_value = maxi(total, 1)
	achievements_bar.value = earned
	var done: Array = _data.achievements.filter(func(entry: Dictionary) -> bool: return _earned_at(entry.id) > 0)
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _earned_at(a.id) > _earned_at(b.id))
	if total == 0:
		_note(tr("Connect to a server first"))
	elif done.is_empty():
		_note(tr("No achievement earned yet"))
	for entry: Dictionary in done.slice(0, LATEST):
		var row := HBoxContainer.new()
		row.name = "Latest_" + entry.id.replace(":", "_")
		row.add_theme_constant_override("separation", 10)
		latest_list.add_child(row)
		var icon := TextureRect.new()
		icon.texture = ItemIcons.texture(entry.icon)
		if icon.texture == null:
			icon.texture = TROPHY
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var title := Label.new()
		title.theme_type_variation = &"GoldLabel"
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.text = texts.call(entry, "title") if texts.is_valid() else tr(str(entry.get("title", "")))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)
		var date := Label.new()
		date.theme_type_variation = &"MutedLabel"
		date.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var day := Time.get_datetime_dict_from_unix_time(_earned_at(entry.id))
		date.text = "%d. %d. %d" % [day.day, day.month, day.year]
		row.add_child(date)

func _note(text: String) -> void:
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.text = text
	latest_list.add_child(note)

func _update_texts() -> void:
	if not is_instance_valid(_title):
		return
	_title.text = tr("Character")
	_close.tooltip_text = tr("Close")
	for key: String in _labels:
		var entry: Variant = _labels[key]
		if entry is Array:
			entry[0].text = tr(str(entry[1]))
	_labels["achievements_title"].text = tr("Achievements")
	all_button.text = tr("All achievements")
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
