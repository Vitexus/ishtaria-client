extends CanvasLayer
## The friends: add by name, answer requests, and see where each friend is.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal add_requested(name: String)
signal accept_requested(id: int)
signal decline_requested(id: int)
signal remove_requested(name: String)
signal refresh_requested

var panel: PanelContainer
var name_input: LineEdit
var feedback: Label
var list: VBoxContainer
var _friends: Array = []
var _incoming: Array = []
var _outgoing: Array = []
var _feedback_key := ""

func _ready() -> void:
	layer = 4
	add_child(UiKit.backdrop(0.78))
	panel = PanelContainer.new()
	add_child(panel)
	panel.theme_type_variation = &"FramePanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"HeaderLabel"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var close := Button.new()
	close.theme_type_variation = &"GhostButton"
	UiKit.hook_sounds(close, "back")
	close.name = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	var row := HBoxContainer.new()
	column.add_child(row)
	name_input = LineEdit.new()
	name_input.name = "FriendName"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.custom_minimum_size.y = 36
	name_input.max_length = 32
	name_input.text_submitted.connect(func(_text: String) -> void: _add())
	row.add_child(name_input)
	var add := Button.new()
	add.name = "AddFriend"
	add.pressed.connect(_add)
	row.add_child(add)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	feedback = Label.new()
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	column.add_child(feedback)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()
	_update_texts()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(620, screen.x - 24), minf(620, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions

func open() -> void:
	var was_open := visible
	show()
	if not was_open:
		UiKit.open_animated(panel)
	_update_texts()
	refresh_requested.emit()
	name_input.grab_focus()

func _add() -> void:
	var name := name_input.text.strip_edges()
	if name.is_empty():
		return
	set_feedback("")
	add_requested.emit(name)
	name_input.clear()

func set_feedback(key: String) -> void:
	_feedback_key = key
	feedback.text = tr(key) if not key.is_empty() else ""

func set_friends(friends: Array) -> void:
	_friends = friends.duplicate(true)
	_render()

func set_requests(incoming: Array, outgoing: Array) -> void:
	_incoming = incoming.duplicate(true)
	_outgoing = outgoing.duplicate(true)
	_render()

func _label(parent: Node, text: String, color := UiTheme.SAND) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _heading(text: String) -> void:
	var label := _label(list, text, UiTheme.GOLD)
	label.theme_type_variation = &"HeaderLabel"
	label.add_theme_font_size_override("font_size", 15)

func _button(parent: Node, name: String, text: String, action: Callable) -> void:
	var button := Button.new()
	# Taking something back is quiet; accepting stands out.
	button.theme_type_variation = &"GhostButton" if name in ["Remove", "Decline", "Cancel"] else &""
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.name = name
	button.text = text
	button.custom_minimum_size = Vector2(88, 34)
	button.pressed.connect(func() -> void:
		set_feedback("")
		action.call()
	)
	parent.add_child(button)

func _render() -> void:
	if not is_instance_valid(list):
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if not _incoming.is_empty():
		_heading(tr("Friend requests"))
		for request: Dictionary in _incoming:
			var row := UiKit.card(list)
			row.name = "Request_%d" % int(request.id)
			_label(row, request.name)
			_button(row, "Accept", tr("Accept"), func() -> void: accept_requested.emit(int(request.id)))
			_button(row, "Decline", tr("Decline"), func() -> void: decline_requested.emit(int(request.id)))
	if not _outgoing.is_empty():
		_heading(tr("Sent requests"))
		for request: Dictionary in _outgoing:
			var row := UiKit.card(list)
			row.name = "Sent_%d" % int(request.id)
			_label(row, request.name, UiTheme.SAND_MUTED)
			_button(row, "Cancel", tr("Cancel"), func() -> void: decline_requested.emit(int(request.id)))
	_heading(tr("Friends"))
	if _friends.is_empty():
		_label(list, tr("No friends yet"), UiTheme.SAND_MUTED)
	for friend: Dictionary in _friends:
		var row := UiKit.card(list)
		row.name = "Friend_" + friend.name
		var flag_texture := _flag_texture(friend.get("flag"))
		if flag_texture != null:
			var flag := TextureRect.new()
			flag.name = "Flag"
			flag.texture = flag_texture
			flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			flag.custom_minimum_size = Vector2(26, 26)
			flag.tooltip_text = String(friend.flag)
			row.add_child(flag)
		var dot := _label(row, "●" if friend.online else "○", Color(0.45, 0.95, 0.5) if friend.online else UiTheme.SAND_MUTED)
		dot.size_flags_horizontal = Control.SIZE_FILL
		dot.custom_minimum_size.x = 22
		dot.tooltip_text = tr("Online") if friend.online else tr("Offline")
		var text := "%s  ·  %s %d" % [friend.name, tr("Level"), int(friend.level)]
		if friend.online:
			text += "  ·  " + tr("World") + ": " + friend.world
		_label(row, text, UiTheme.SAND if friend.online else UiTheme.SAND_MUTED)
		_button(row, "Remove", tr("Remove"), func() -> void: remove_requested.emit(friend.name))

## The bundled picture of a flag a friend chose to show (two capital letters), if we have it.
static func _flag_texture(code: Variant) -> Texture2D:
	if not code is String or code.length() != 2 or code != code.to_upper() or not code.is_valid_identifier():
		return null
	var path := "res://assets/kenney/flag-pack/%s.png" % code
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _update_texts() -> void:
	if not is_instance_valid(name_input):
		return
	find_child("Title", true, false).text = tr("Friends")
	find_child("Close", true, false).text = tr("Close")
	find_child("AddFriend", true, false).text = tr("Add friend")
	name_input.placeholder_text = tr("Name of a player")
	if not _feedback_key.is_empty():
		feedback.text = tr(_feedback_key)
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
