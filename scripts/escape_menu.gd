extends CanvasLayer
## The menu of the ESC key: the name of the game, a column of commands (continue, settings,
## friends, achievements, main menu, quitting) and the hall of fame of the server (its ten most
## successful characters), side by side on a wide screen and one under the other on a narrow one.

signal settings_requested
signal quit_requested
signal friends_requested
signal achievements_requested
## Leave the world and open the connection screen (pick another server).
signal main_menu_requested

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const GOLD := UiTheme.GOLD
const MAX_ENTRIES := 10
const HEADSTONE := "res://assets/icons/ui/headstone.png"
## The first three places of the hall: gold, silver and bronze.
const PODIUM := [Color("ffd77a"), Color("d8d8e0"), Color("d79a5a")]

var server_url := ""
var title_label: Label
var resume_button: Button
var settings_button: Button
var quit_button: Button
var friends_button: Button
var achievements_button: Button
var main_menu_button: Button
var hall_title: Label
var hall_status: Label
var hall_spinner: TextureRect
var hall_grid: GridContainer
var _scroll: ScrollContainer
var _content: BoxContainer
var _commands: VBoxContainer
var _hall_panel: Control
var _request: HTTPRequest
var _entries: Array = []
var _status_key := ""

func _ready() -> void:
	layer = 30
	add_child(UiKit.backdrop(0.85))
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_content = BoxContainer.new()
	_content.add_theme_constant_override("separation", 28)
	center.add_child(_content)
	_build_commands()
	_build_hall()
	get_viewport().size_changed.connect(_fit)
	_fit()
	_update_texts()
	hide()

## The title over a column of large commands, like the main menu of a console game.
func _build_commands() -> void:
	_commands = VBoxContainer.new()
	_commands.add_theme_constant_override("separation", 10)
	_commands.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(_commands)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"TitleLabel"
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = "Ishtaria"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commands.add_child(title_label)
	var line := UiKit.divider()
	line.name = "OrnamentTop"
	_commands.add_child(line)
	resume_button = _button("ResumeButton", &"PrimaryButton", "back")
	resume_button.pressed.connect(close)
	settings_button = _button("SettingsButton")
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	friends_button = _button("FriendsButton")
	friends_button.pressed.connect(func() -> void: friends_requested.emit())
	achievements_button = _button("AchievementsButton")
	achievements_button.icon = preload("res://assets/kenney/game-icons/trophy.png")
	achievements_button.add_theme_constant_override("icon_max_width", 24)
	achievements_button.pressed.connect(func() -> void: achievements_requested.emit())
	main_menu_button = _button("MainMenuButton", &"", "back")
	main_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())
	quit_button = _button("QuitButton", &"", "back")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())

func _button(name: String, variation := &"", sound := "click") -> Button:
	var button := UiKit.button("", variation, sound)
	button.name = name
	button.custom_minimum_size = Vector2(280, 52)
	button.add_theme_font_size_override("font_size", 20)
	_commands.add_child(button)
	return button

func _build_hall() -> void:
	var inner := UiKit.framed_panel(_content, 8)
	_hall_panel = inner.get_parent()
	_hall_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hall_title = UiKit.section_header(inner)
	hall_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hall_title.add_theme_font_size_override("font_size", 22)
	hall_status = Label.new()
	hall_status.theme_type_variation = &"MutedLabel"
	hall_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hall_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hall_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hall_spinner = TextureRect.new()
	hall_spinner.name = "Spinner"
	hall_spinner.texture = load("res://assets/branding/spinner.png") as Texture2D
	hall_spinner.custom_minimum_size = Vector2(48, 48)
	hall_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hall_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hall_spinner.pivot_offset = Vector2(24, 24)
	hall_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hall_spinner.visible = false
	inner.add_child(hall_spinner)
	inner.add_child(hall_status)
	hall_grid = GridContainer.new()
	hall_grid.name = "Hall"
	hall_grid.columns = 6
	hall_grid.add_theme_constant_override("h_separation", 22)
	hall_grid.add_theme_constant_override("v_separation", 8)
	inner.add_child(hall_grid)

## Commands beside the hall when there is room, above it otherwise.
func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var wide := screen.x >= 1100.0
	_content.vertical = not wide
	_hall_panel.custom_minimum_size.x = clampf(screen.x - 32.0, 280.0, 700.0)
	_commands.custom_minimum_size.x = clampf(screen.x - 32.0, 260.0, 340.0)
	_commands.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var size := int(clampf(screen.x / 16.0, 34.0, 64.0))
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", size)

func is_open() -> bool:
	return visible

func open(url: String) -> void:
	server_url = url
	show()
	_update_texts()
	_fetch()
	for control: Control in [_commands, _hall_panel]:
		UiKit.open_animated(control)
	resume_button.grab_focus()

func close() -> void:
	_cancel()
	hide()

func _cancel() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null

func _fetch() -> void:
	_cancel()
	_entries = []
	if server_url.is_empty():
		_set_status("Connect to a server first")
		_render()
		return
	_set_status("Loading")
	_render()
	_request = HTTPRequest.new()
	_request.timeout = 4.0
	_request.max_redirects = 0
	_request.body_size_limit = 65536
	add_child(_request)
	var request := _request
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if request != _request:
			return
		_request = null
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_set_status("Hall of fame unavailable")
			return
		show_hall(JSON.parse_string(body.get_string_from_utf8()))
	)
	if request.request(server_url + "/hall-of-fame") != OK:
		_request = null
		request.queue_free()
		_set_status("Hall of fame unavailable")

## Shows the entries sent by the server; malformed answers are not shown.
func show_hall(data: Variant) -> bool:
	var valid := valid_hall(data)
	_entries = data if valid else []
	_set_status("" if valid and not _entries.is_empty() else ("No characters yet" if valid else "Hall of fame unavailable"))
	_render()
	return valid

static func valid_hall(data: Variant) -> bool:
	if not data is Array or data.size() > MAX_ENTRIES:
		return false
	var pattern := RegEx.new()
	pattern.compile("^(0|[1-9][0-9]{0,18})$")
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("name") is String or entry.name.is_empty() or entry.name.length() > 64 or not entry.get("alive") is bool:
			return false
		if not (entry.get("level") is float or entry.get("level") is int) or entry.level < 1 or entry.level > 100000 or entry.level != floor(entry.level):
			return false
		for key in ["wealth", "lived_days", "score"]:
			if not entry.get(key) is String or pattern.search(entry[key]) == null:
				return false
	return true

## Groups the digits of a decimal string in threes: "1234567" becomes "1 234 567".
static func group_digits(number: String) -> String:
	var out := ""
	for index in number.length():
		if index > 0 and (number.length() - index) % 3 == 0:
			out += " "
		out += number[index]
	return out

func _process(delta: float) -> void:
	if is_instance_valid(hall_spinner) and hall_spinner.visible:
		hall_spinner.rotation += TAU * delta

func _set_status(key: String) -> void:
	_status_key = key
	if is_instance_valid(hall_status):
		hall_status.text = tr(key) if not key.is_empty() else ""
		hall_status.visible = not key.is_empty()
	if is_instance_valid(hall_spinner):
		hall_spinner.visible = key == "Loading"

func _cell(text: String, color := UiTheme.SAND, align := HORIZONTAL_ALIGNMENT_LEFT, expand := true) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	hall_grid.add_child(label)
	return label

## The name of a character; a small headstone marks one who has died.
func _name_cell(name: String, color: Color, dead: bool) -> void:
	var row := HBoxContainer.new()
	row.name = "Name_" + name
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hall_grid.add_child(row)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = name
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	if dead:
		var icon := TextureRect.new()
		icon.name = "Headstone"
		icon.texture = load(HEADSTONE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(22, 22)
		icon.tooltip_text = tr("Deceased")
		row.add_child(icon)

func _render() -> void:
	if not is_instance_valid(hall_grid):
		return
	for child in hall_grid.get_children():
		hall_grid.remove_child(child)
		child.queue_free()
	if _entries.is_empty():
		return
	var head := UiTheme.GOLD_DIM.lightened(0.25)
	_cell("#", head, HORIZONTAL_ALIGNMENT_LEFT, false)
	_cell(tr("Name"), head)
	_cell(tr("Level"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(tr("Score"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(tr("Life"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(tr("Wealth"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	var rank := 0
	for entry: Dictionary in _entries:
		rank += 1
		var color := UiTheme.SAND if entry.alive else UiTheme.SAND_MUTED
		var place := _cell(str(rank), PODIUM[rank - 1] if rank <= PODIUM.size() else UiTheme.SAND_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		place.add_theme_font_size_override("font_size", 19)
		_name_cell(entry.name, color, not entry.alive)
		_cell(str(int(entry.level)), color, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(group_digits(entry.score), UiTheme.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(tr("%s d") % group_digits(entry.lived_days), color, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(group_digits(entry.wealth), GOLD if entry.wealth != "0" else UiTheme.SAND_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)

func _update_texts() -> void:
	if not is_instance_valid(settings_button):
		return
	resume_button.text = tr("Continue")
	settings_button.text = tr("Settings")
	friends_button.text = tr("Friends")
	achievements_button.text = tr("Achievements")
	main_menu_button.text = tr("Go to main menu")
	quit_button.text = tr("Quit game")
	hall_title.text = tr("Hall of fame")
	_set_status(_status_key)
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
