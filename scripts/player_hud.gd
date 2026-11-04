extends CanvasLayer

signal sound_toggled(enabled: bool)
signal inventory_requested
signal connection_requested

const ICONS := "res://assets/kenney/game-icons/"
const LifeOrdinal := preload("res://scripts/life_ordinal.gd")
const ITEM_ICONS := preload("res://scripts/item_icons.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const FramedStyleBox := preload("res://scripts/ui/framed_style_box.gd")
## Label key and bar colour of each reserve.
const METERS := {"health": ["Health", Color("d8463a")], "stamina": ["Stamina", Color("6cae3c")], "food": ["Food", Color("e0a032")], "water": ["Water", Color("3a86d8")], "mana": ["Mana", Color("9a5ae0")]}
## A reserve at or below this blinks.
const LOW_RESERVE := 20.0
## Left hand = offhand (shield), right hand = dominant hand (tool / weapon).
const HAND_SLOTS := {"offhand": "left", "hand": "right"}

var sound_enabled := true
var sky: Node
var clock_label: Label
var _clock_elapsed := 1.0
var _blink_elapsed := 0.0
var panel: PanelContainer
var grid: GridContainer
var meters: Dictionary = {}
var player_name: Label
var level_label: Label
var age_label: Label
var experience_label: Label
var gold_label: Label
var score_label: Label
var xp_bar: ProgressBar
var inventory_button: Button
var connection_button: Button
var sound_checkbox: Button
var _frame: NinePatchRect
var _panel_style: StyleBox
var _header: HBoxContainer
var _labels: Dictionary = {}
var _values: Dictionary = {}
var _player: Dictionary = {}
## `{slot: {panel, icon, label, broken}}` for the bottom-corner equipment display.
var _hands: Dictionary = {}

func _ready() -> void:
	layer = 2
	panel = PanelContainer.new()
	panel.name = "PlayerHUD"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -8.0
	panel.offset_top = -96.0
	panel.theme = Theme.new()
	panel.theme.default_font_size = 13
	# Clay fill of the kit; the gold frame is a separate rectangle on top (`_frame`) so it can
	# be drawn over the content's edge without taking the pointer.
	var style := FramedStyleBox.new(load(UiTheme.FILL_TEXTURE), Color(UiTheme.CLAY, 0.93), null, Color.WHITE, 16, 2)
	style.content_margin_top = 14.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	_panel_style = style
	_frame = NinePatchRect.new()
	_frame.modulate = UiTheme.GOLD
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	panel.resized.connect(_sync_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	# Header: level badge, name, gold, commands.
	var header := HBoxContainer.new()
	_header = header
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	level_label = Label.new()
	level_label.name = "Level"
	level_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_override("font", UiTheme.font(true))
	level_label.add_theme_font_size_override("font_size", 13)
	level_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	var badge := UiTheme.flat_style(UiTheme.LAPIS, UiTheme.GOLD, 1, 10, 10.0)
	badge.content_margin_top = 2.0
	badge.content_margin_bottom = 2.0
	level_label.add_theme_stylebox_override("normal", badge)
	header.add_child(level_label)
	player_name = Label.new()
	player_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_name.add_theme_font_override("font", UiTheme.font(false))
	player_name.add_theme_font_size_override("font_size", 16)
	player_name.add_theme_color_override("font_color", UiTheme.GOLD)
	player_name.add_theme_color_override("font_outline_color", UiTheme.CLAY_DARK)
	player_name.add_theme_constant_override("outline_size", 4)
	header.add_child(player_name)
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override("separation", 4)
	header.add_child(purse)
	var coin := TextureRect.new()
	coin.texture = ITEM_ICONS.texture("gold")
	coin.custom_minimum_size = Vector2(24, 24)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	purse.add_child(coin)
	gold_label = Label.new()
	gold_label.name = "Gold"
	gold_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	gold_label.add_theme_font_size_override("font_size", 15)
	gold_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	purse.add_child(gold_label)
	inventory_button = UiKit.icon_button(load(ICONS + "basket.png"), "click", 28)
	inventory_button.name = "Inventory"
	inventory_button.pressed.connect(func() -> void: inventory_requested.emit())
	header.add_child(inventory_button)
	connection_button = UiKit.icon_button(load(ICONS + "gear.png"), "click", 28)
	connection_button.name = "ConnectionSettings"
	connection_button.pressed.connect(func() -> void: connection_requested.emit())
	header.add_child(connection_button)
	sound_checkbox = UiKit.icon_button(load(ICONS + "audioOn.png"), "click", 28)
	sound_checkbox.name = "InterfaceSounds"
	sound_checkbox.toggle_mode = true
	sound_checkbox.button_pressed = sound_enabled
	sound_checkbox.toggled.connect(_on_sound_toggled)
	header.add_child(sound_checkbox)
	for button: Button in [inventory_button, connection_button, sound_checkbox]:
		# The ghost style shows no plate until hovered; here a quiet clay plate stays visible.
		button.add_theme_stylebox_override("normal", UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.7), Color(UiTheme.GOLD_DIM, 0.8), 1, 3, 4.0))
		button.add_theme_stylebox_override("pressed", UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.7), Color(UiTheme.GOLD_DIM, 0.8), 1, 3, 4.0))

	# The five reserves.
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for key in METERS:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		grid.add_child(cell)
		var heading := HBoxContainer.new()
		cell.add_child(heading)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_override("font", UiTheme.font(true))
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", UiTheme.SAND_MUTED)
		heading.add_child(label)
		_labels[key] = label
		var value := Label.new()
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.custom_minimum_size.x = 28.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 12)
		value.add_theme_color_override("font_color", UiTheme.SAND)
		heading.add_child(value)
		_values[key] = value
		var meter := ProgressBar.new()
		meter.name = "Meter_" + key
		meter.custom_minimum_size = Vector2(60.0, 10.0)
		meter.show_percentage = false
		meter.add_theme_stylebox_override("background", _bar_background())
		meter.add_theme_stylebox_override("fill", _bar_fill(METERS[key][1]))
		cell.add_child(meter)
		meters[key] = meter

	# Experience across the whole width, then the small figures and the solar clock.
	xp_bar = ProgressBar.new()
	xp_bar.name = "ExperienceBar"
	xp_bar.custom_minimum_size = Vector2(100.0, 5.0)
	xp_bar.show_percentage = false
	xp_bar.add_theme_stylebox_override("background", _bar_background())
	xp_bar.add_theme_stylebox_override("fill", _bar_fill(UiTheme.GOLD))
	column.add_child(xp_bar)
	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 16)
	footer.add_theme_constant_override("v_separation", 2)
	column.add_child(footer)
	experience_label = Label.new()
	experience_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	footer.add_child(experience_label)
	score_label = Label.new()
	score_label.name = "Score"
	score_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	footer.add_child(score_label)
	age_label = Label.new()
	age_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	footer.add_child(age_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	clock_label = Label.new()
	clock_label.name = "SolarClock"
	clock_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	footer.add_child(clock_label)
	for label in [experience_label, score_label, age_label, clock_label]:
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", UiTheme.SAND_MUTED)
	score_label.add_theme_color_override("font_color", UiTheme.GOLD)
	clock_label.add_theme_color_override("font_color", UiTheme.SAND)
	for slot: String in HAND_SLOTS:
		_hands[slot] = _make_hand_slot(slot)
	get_viewport().size_changed.connect(_resize)
	_resize()
	clear_player()

## The dark groove of a bar.
func _bar_background() -> StyleBoxFlat:
	var style := UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.95), Color(UiTheme.GOLD_DIM, 0.7), 1, 3, 0.0)
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style

## The coloured part of a bar, with a lighter top edge so it reads as glazed.
func _bar_fill(color: Color) -> StyleBoxFlat:
	var style := UiTheme.flat_style(color, color.lightened(0.45), 0, 3, 0.0)
	style.border_width_top = 2
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style

## A framed icon in a screen corner for the item held in that hand.
func _make_hand_slot(slot: String) -> Dictionary:
	var holder := PanelContainer.new()
	holder.name = "Hand_" + slot
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.88), UiTheme.GOLD, 2, 4, 6.0)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	holder.add_theme_stylebox_override("panel", style)
	add_child(holder)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(column)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44, 44)
	icon.modulate = Color(1, 1, 1, 0.35)
	column.add_child(icon)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UiTheme.SAND)
	label.text = "—"
	column.add_child(label)
	return {"panel": holder, "icon": icon, "label": label, "broken": false}

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var width := screen.x
	var margin := maxf(8.0, (width - 920.0) / 2.0)
	panel.offset_left = margin
	panel.offset_right = -margin
	grid.columns = 5 if width >= 640.0 else 3
	# The frame of the menus at twice its pixels; a narrow screen has no room for its corner
	# knots and gets it at its own size.
	var scale := 2 if width >= 640.0 else 1
	_frame.texture = FramedStyleBox.scaled(load(UiTheme.FRAME_TEXTURE), scale)
	for side in ["left", "right", "top", "bottom"]:
		_frame.set("patch_margin_" + side, 16 * scale)
	_panel_style.content_margin_left = 34.0 if scale == 2 else 18.0
	_panel_style.content_margin_right = _panel_style.content_margin_left
	_header.add_theme_constant_override("separation", 10 if width >= 640.0 else 5)
	panel.offset_top = -maxf(96.0, panel.get_combined_minimum_size().y)
	_sync_frame.call_deferred()
	# The whole gold amount when it fits; on a narrow screen it is cut and the tooltip keeps it.
	var font := gold_label.get_theme_font("font")
	var text_width := font.get_string_size(gold_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, gold_label.get_theme_font_size("font_size")).x
	gold_label.custom_minimum_size.x = minf(ceilf(text_width) + 2.0, 240.0 if width >= 640.0 else 70.0)

## The frame and the hand slots follow the panel once its size is known.
func _sync_frame() -> void:
	_frame.position = panel.position
	_frame.size = panel.size
	_frame.visible = panel.visible
	var screen := get_viewport().get_visible_rect().size
	var slot_size := Vector2(68, 80) if screen.x >= 640.0 else Vector2(56, 70)
	var gap := 10.0
	for slot: String in _hands:
		var holder: PanelContainer = _hands[slot].panel
		holder.custom_minimum_size = slot_size
		holder.size = slot_size
		var y := minf(panel.position.y - slot_size.y - 6.0, screen.y - slot_size.y - gap)
		if HAND_SLOTS[slot] == "left":
			holder.position = Vector2(gap, y)
		else:
			holder.position = Vector2(screen.x - slot_size.x - gap, y)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(grid):
		_update_labels()

func _process(delta: float) -> void:
	_frame.visible = panel.visible
	_clock_elapsed += delta
	if _clock_elapsed >= 1.0:
		_clock_elapsed = 0.0
		_update_clock()
	_blink_elapsed += delta
	var pulse := 0.45 + 0.55 * absf(sin(_blink_elapsed * TAU * 1.6))
	for key in meters:
		var low: bool = not _player.is_empty() and _player.stats.has(key) and meters[key].value <= LOW_RESERVE
		meters[key].self_modulate = Color(1.0 + 0.6 * pulse, 1.0, 1.0) if low else Color.WHITE
		_values[key].add_theme_color_override("font_color", UiTheme.CARNELIAN.lerp(UiTheme.SAND, 1.0 - pulse) if low else UiTheme.SAND)
	for slot: String in _hands:
		var entry: Dictionary = _hands[slot]
		if entry.broken and entry.icon.texture != null:
			entry.icon.modulate.a = pulse
			entry.panel.modulate = Color(1.0, 0.55 + 0.35 * pulse, 0.45, 1.0)
		else:
			entry.panel.modulate = Color.WHITE

func _update_clock() -> void:
	var state: Dictionary = sky.clock_state() if is_instance_valid(sky) else {}
	clock_label.tooltip_text = tr("Local solar time; sunrise and sunset use the astronomical horizon")
	if state.is_empty():
		clock_label.text = tr("Time unavailable")
		return
	var local_minutes := int(state.local_seconds / 60.0)
	var time := "%02d:%02d" % [local_minutes / 60, local_minutes % 60]
	var event: String
	if state.remaining_seconds < 0.0:
		event = tr("Sunset beyond 24 h" if state.day else "Sunrise beyond 24 h")
	else:
		var minutes := int(ceil(state.remaining_seconds / 60.0))
		var remaining := "%02d:%02d" % [minutes / 60, minutes % 60]
		event = tr("Sunset in %s" if state.day else "Sunrise in %s") % remaining
	clock_label.text = tr("Solar time %s") % time + "  ·  " + event

func _on_sound_toggled(value: bool) -> void:
	sound_enabled = value
	sound_checkbox.icon = load(ICONS + ("audioOn.png" if value else "audioOff.png"))
	sound_toggled.emit(value)

func clear_player() -> void:
	_player = {}
	for key in meters:
		meters[key].value = 0.0
		meters[key].modulate.a = 0.45
		_values[key].text = "-"
	_update_hands()
	_update_labels()

## Draws the labels again, for example when the font of the datadisk's numerals has arrived.
func refresh_labels() -> void:
	_update_labels()

func set_player(profile: Dictionary) -> bool:
	if not profile.get("username") is String or not profile.get("stats") is Dictionary:
		return false
	var stats: Dictionary = profile.stats
	var gold: Variant = stats.get("gold")
	if not gold is String:
		return false
	var gold_pattern := RegEx.new()
	gold_pattern.compile("^(0|[1-9][0-9]{0,18})$")
	if gold_pattern.search(gold) == null or (gold.length() == 19 and gold > "9223372036854775807"):
		return false
	var life: Variant = profile.get("life", {})
	if not life is Dictionary:
		return false
	if life.has("age_days"):
		var age: Variant = life.age_days
		if not age is String or gold_pattern.search(age) == null or (age.length() == 19 and age > "9223372036854775807"):
			return false
	for key in METERS:
		# A server without magic sends no mana; the meter then stays empty.
		if key == "mana" and not stats.has("mana"):
			continue
		var value: Variant = stats.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value > 100:
			return false
	for key in ["level", "experience"]:
		var value: Variant = stats.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value != floor(value) or value < (1 if key == "level" else 0):
			return false
	var score: Variant = stats.get("score")
	if score != null and (not score is String or gold_pattern.search(score) == null):
		return false
	for key in ["level_experience", "next_level_experience"]:
		if stats.has(key):
			var value: Variant = stats[key]
			if not (value is float or value is int) or not is_finite(float(value)) or value != floor(value) or value < 0:
				return false
	_player = profile.duplicate(true)
	for key in meters:
		var shown: float = float(stats.get(key, 0))
		meters[key].value = shown
		meters[key].modulate.a = 1.0 if stats.has(key) else 0.45
		_values[key].text = str(int(shown)) if stats.has(key) else "-"
	_update_labels()
	return true

func _update_labels() -> void:
	_update_clock()
	connection_button.tooltip_text = tr("Connection settings")
	inventory_button.tooltip_text = tr("Inventory")
	sound_checkbox.icon = load(ICONS + ("audioOn.png" if sound_enabled else "audioOff.png"))
	sound_checkbox.tooltip_text = tr("Interface sounds")
	for key in _labels:
		_labels[key].text = tr(METERS[key][0])
		meters[key].tooltip_text = tr(METERS[key][0])
	player_name.text = LifeOrdinal.with_name(str(_player.username), _player.get("ordinal")) if not _player.is_empty() else tr("Not signed in")
	player_name.tooltip_text = player_name.text
	# The number of a later life may be cuneiform, which the theme font lacks: the datadisk's numerals font fills in.
	player_name.add_theme_font_override("font", LifeOrdinal.with_fallback(UiTheme.font(false)))
	level_label.text = tr("Level %s") % (int(_player.stats.level) if not _player.is_empty() else "-")
	level_label.tooltip_text = level_label.text
	age_label.text = tr("Age: %s days") % _player.get("life", {}).get("age_days", "-")
	age_label.tooltip_text = age_label.text
	var next_level: Variant = _player.get("stats", {}).get("next_level_experience")
	if not _player.is_empty() and (next_level is float or next_level is int) and next_level > _player.stats.experience:
		experience_label.text = tr("Experience %s / %s") % [int(_player.stats.experience), int(next_level)]
	else:
		experience_label.text = tr("Experience %s") % (int(_player.stats.experience) if not _player.is_empty() else "-")
	experience_label.tooltip_text = experience_label.text
	var stats: Dictionary = _player.get("stats", {})
	score_label.text = tr("Score %s") % (int(stats["score"]) if stats.has("score") else "-")
	score_label.tooltip_text = tr("Score: 100 per level and 10 per day lived")
	xp_bar.tooltip_text = experience_label.text
	var floor_xp: Variant = stats.get("level_experience")
	if (next_level is float or next_level is int) and (floor_xp is float or floor_xp is int) and next_level > floor_xp:
		xp_bar.max_value = float(next_level) - float(floor_xp)
		xp_bar.value = clampf(float(stats.get("experience", 0)) - float(floor_xp), 0.0, xp_bar.max_value)
	else:
		xp_bar.max_value = 1.0
		xp_bar.value = 0.0
	gold_label.text = tr("Gold %s") % (_player.stats.gold if not _player.is_empty() else "-")
	gold_label.tooltip_text = gold_label.text
	_update_hands()
	_resize.call_deferred()

## Fills the corner slots from `equipment.hand` / `equipment.offhand` and inventory durability.
func _update_hands() -> void:
	var equipment: Dictionary = _player.get("equipment", {}) if not _player.is_empty() else {}
	var inventory: Array = _player.get("inventory", {}).get("items", []) if not _player.is_empty() else []
	for slot: String in HAND_SLOTS:
		var entry: Dictionary = _hands[slot]
		var item_id: Variant = equipment.get(slot)
		var held: Dictionary = {}
		if item_id is String and not item_id.is_empty():
			for item: Variant in inventory:
				if item is Dictionary and item.get("item_id") == item_id:
					held = item
					break
		var icon: TextureRect = entry.icon
		var label: Label = entry.label
		entry.panel.self_modulate = Color(1, 1, 1, 0.55 if held.is_empty() else 1.0)
		if held.is_empty():
			icon.texture = null
			icon.modulate = Color(1, 1, 1, 0.35)
			label.text = "—"
			label.tooltip_text = tr("Left hand" if slot == "offhand" else "Right hand")
			entry.panel.tooltip_text = label.tooltip_text
			entry.broken = false
			continue
		var id: String = held.item_id
		icon.texture = ITEM_ICONS.texture(id)
		icon.modulate = Color.WHITE
		var name_text := tr(held.get("name", id))
		var durability: Variant = held.get("durability")
		var max_durability: Variant = held.get("max_durability")
		# Blink while the piece is nearly spent; at 0 HP the server destroys it.
		var worn := false
		if (durability is float or durability is int) and (max_durability is float or max_durability is int) and max_durability > 0:
			worn = float(durability) / float(max_durability) <= 0.2
			label.text = "%s/%s" % [int(durability), int(max_durability)]
			label.tooltip_text = "%s\n%s" % [name_text, tr("Durability %s / %s") % [int(durability), int(max_durability)]]
			if worn:
				label.tooltip_text += "\n" + tr("Worn — repair at a blacksmith")
		else:
			label.text = name_text
			label.tooltip_text = name_text
		entry.panel.tooltip_text = label.tooltip_text
		entry.broken = worn
		if not worn:
			icon.modulate.a = 1.0