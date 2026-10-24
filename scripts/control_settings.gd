extends Window
## The settings: display, sound and controls (key bindings, mouse), saved with the other local
## preferences. A window over the whole game with its own framed card (scripts/ui).

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal closed

var controls: Node3D
## The dialogue panel whose music and voice levels the sliders set.
var dialogue: Node
## The quest clay-tablet prologue; shares the dialogue voice volume.
var tablet: Node
## Whether closing the dialog gives the mouse back to the game; off when the ESC menu opened it.
var recapture := true
## The sky whose volumetric light shafts the check box switches.
var sky: Node
var _fullscreen: CheckBox
var _light_shafts: CheckBox
var _buttons: Array[Button] = []
var _waiting := -1
var _feedback: Label
var _sensitivity: HSlider
var _invert: CheckBox
var _music_volume: HSlider
var _voice_volume: HSlider
var _card: Control
var _title_label: Label
var _close_icon: Button
var _tabs: TabContainer
var _tab_keys: Array[String] = []

func _ready() -> void:
	title = tr("Settings")
	# The window covers the game: a dimmed scene with a framed card in the middle and the
	# settings in three tabs. It draws its own frame and title, so the system border is off.
	borderless = true
	transparent_bg = true
	transient = true
	exclusive = true
	close_requested.connect(_close)
	var root := PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(root)
	root.add_child(UiKit.backdrop(0.8))
	var center := CenterContainer.new()
	root.add_child(center)
	var column := UiKit.framed_panel(center, 10)
	_card = column.get_parent()
	var header := HBoxContainer.new()
	column.add_child(header)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(40, 0)
	header.add_child(spacer)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeaderLabel"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(_title_label)
	_close_icon = UiKit.icon_button(preload("res://assets/kenney/game-icons/cross.png"), "back")
	_close_icon.pressed.connect(_close)
	header.add_child(_close_icon)
	column.add_child(UiKit.divider())
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	column.add_child(_tabs)

	var display := _page("Display")
	_fullscreen = CheckBox.new()
	_fullscreen.name = "Fullscreen"
	_fullscreen.text = tr("Fullscreen")
	_fullscreen.toggled.connect(func(enabled: bool) -> void:
		apply_fullscreen(enabled)
		_feedback.text = "" if save_fullscreen(enabled) else tr("Could not save controls")
	)
	display.add_child(_fullscreen)
	_light_shafts = CheckBox.new()
	_light_shafts.name = "LightShafts"
	_light_shafts.text = tr("Light shafts")
	_light_shafts.toggled.connect(func(enabled: bool) -> void:
		if is_instance_valid(sky):
			sky.set_light_shafts(enabled)
		_feedback.text = "" if save_light_shafts(enabled) else tr("Could not save controls")
	)
	display.add_child(_light_shafts)

	var sound := _page("Sound")
	_music_volume = _volume_slider(sound, "Music volume", "music_volume")
	_voice_volume = _volume_slider(sound, "Dialogue voice volume", "voice_volume")

	var input := _page("Controls")
	_setting_label(input, "Mouse sensitivity")
	_sensitivity = HSlider.new()
	_sensitivity.min_value = 0.0005
	_sensitivity.max_value = 0.01
	_sensitivity.step = 0.0001
	_sensitivity.value = controls.sensitivity
	_sensitivity.value_changed.connect(func(value: float) -> void:
		controls.sensitivity = value
		_save()
	)
	input.add_child(_sensitivity)
	_invert = CheckBox.new()
	_invert.text = "Invert mouse Y"
	_invert.button_pressed = controls.invert_y
	_invert.toggled.connect(func(enabled: bool) -> void:
		controls.invert_y = enabled
		_save()
	)
	input.add_child(_invert)
	input.add_child(UiKit.divider())
	for index in controls.ACTIONS.size():
		var row := HBoxContainer.new()
		input.add_child(row)
		var label := Label.new()
		label.text = controls.LABELS[index]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		# A key cap: the bound key in gold on a clay plate.
		var button := UiKit.button("")
		button.custom_minimum_size = Vector2(130, 36)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.add_theme_font_override("font", ThemeDB.fallback_font)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_begin_binding.bind(index))
		row.add_child(button)
		_buttons.append(button)

	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_color", UiTheme.CARNELIAN.lightened(0.25))
	column.add_child(_feedback)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var reset := UiKit.button("Restore defaults", &"GhostButton")
	reset.pressed.connect(func() -> void:
		controls.reset_keys()
		controls.sensitivity = 0.002
		controls.invert_y = false
		_sensitivity.set_value_no_signal(controls.sensitivity)
		_invert.set_pressed_no_signal(false)
		_music_volume.value = 1.0
		_voice_volume.value = 1.0
		_waiting = -1
		_save()
		_refresh()
	)
	row.add_child(reset)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var close := UiKit.button("Close", &"PrimaryButton", "back")
	close.custom_minimum_size.x = 160
	close.pressed.connect(_close)
	row.add_child(close)
	_update_titles()
	_refresh()
	get_tree().root.size_changed.connect(func() -> void:
		if visible:
			size = get_tree().root.size
			_fit()
	)
	hide()

## One tab: a scrolled column of settings, named by its untranslated key.
func _page(key: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = key
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_tab_keys.append(key)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	scroll.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(page)
	return page

func _setting_label(page: VBoxContainer, key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.theme_type_variation = &"GoldLabel"
	page.add_child(label)
	return label

func _update_titles() -> void:
	title = tr("Settings")
	if is_instance_valid(_title_label):
		_title_label.text = title
		_close_icon.tooltip_text = tr("Close")
		for index in _tab_keys.size():
			_tabs.set_tab_title(index, tr(_tab_keys[index]))

## The card takes 720x640 at most and shrinks with the window, leaving a margin around it.
func _fit() -> void:
	var screen := Vector2(size)
	_card.custom_minimum_size = Vector2(minf(720.0, screen.x - 24.0), minf(640.0, screen.y - 24.0))

## Connects the dialogue panel (created later than this window) and shows its current levels.
func bind_dialogue(panel: Node) -> void:
	dialogue = panel
	_music_volume.set_value_no_signal(panel.music_volume)
	_voice_volume.set_value_no_signal(panel.voice_volume)

## Connects the quest tablet so the narrator uses the same voice volume as dialogue.
func bind_tablet(panel: Node) -> void:
	tablet = panel
	if panel != null and panel.has_method("set_voice_volume"):
		panel.set_voice_volume(_voice_volume.value)

## A 0-200 % slider for a playback level; the value is saved as [audio] <key> and applied at once.
func _volume_slider(column: VBoxContainer, label_key: String, key: String) -> HSlider:
	_setting_label(column, label_key)
	var slider := HSlider.new()
	slider.name = key.to_pascal_case()
	slider.min_value = 0.0
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = 1.0
	slider.value_changed.connect(func(level: float) -> void:
		if dialogue != null:
			if key == "music_volume":
				dialogue.set_music_volume(level)
			else:
				dialogue.set_voice_volume(level)
		if key == "voice_volume" and tablet != null and tablet.has_method("set_voice_volume"):
			tablet.set_voice_volume(level)
		var config := ConfigFile.new()
		config.load(controls.settings_path)
		config.set_value("audio", key, level)
		_feedback.text = "" if config.save(controls.settings_path) == OK else tr("Could not save controls")
	)
	column.add_child(slider)
	return slider

func open() -> void:
	controls.release_mouse()
	_waiting = -1
	_feedback.text = ""
	_fullscreen.set_pressed_no_signal(is_fullscreen())
	_light_shafts.set_pressed_no_signal(is_instance_valid(sky) and sky.light_shafts)
	_refresh()
	popup(Rect2i(Vector2i.ZERO, get_tree().root.size))
	_fit()
	UiKit.open_animated(_card)

static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

static func apply_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

## The display preference is the client's own and shares the file of the other preferences.
func save_fullscreen(enabled: bool) -> bool:
	var config := ConfigFile.new()
	config.load(controls.settings_path)
	config.set_value("display", "fullscreen", enabled)
	return config.save(controls.settings_path) == OK

func save_light_shafts(enabled: bool) -> bool:
	var config := ConfigFile.new()
	config.load(controls.settings_path)
	config.set_value("display", "light_shafts", enabled)
	return config.save(controls.settings_path) == OK

func _begin_binding(index: int) -> void:
	_waiting = index
	_refresh()

func _refresh() -> void:
	for index in _buttons.size():
		_buttons[index].text = tr("Press a key") if index == _waiting else OS.get_keycode_string(controls.key_for(index))

func _save() -> void:
	_feedback.text = "" if controls.save_preferences() else tr("Could not save controls")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _waiting >= 0:
			if event.physical_keycode != KEY_ESCAPE and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
				_feedback.text = "" if controls.rebind(_waiting, event.physical_keycode) else tr("Could not save controls")
			_waiting = -1
			_refresh()
			set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_close()
			set_input_as_handled()

func _close() -> void:
	_waiting = -1
	hide()
	if recapture:
		controls.capture_mouse()
	closed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_titles()
		if is_instance_valid(_fullscreen):
			_fullscreen.text = tr("Fullscreen")
		_refresh()
