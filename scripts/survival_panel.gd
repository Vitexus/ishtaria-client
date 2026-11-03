extends CanvasLayer

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

## The spinner stays at least this long, so an answer from a near server is still seen.
const MIN_PENDING_MS := 400
## Past the request timeout of the session (8 s), a spinner without an answer stops anyway.
const MAX_PENDING_MS := 10000

signal eat_requested(item_id: String)
signal waterskin_requested(action: String)
signal new_character_requested
signal loot_requested(id: String, item_id: String)
signal equip_requested(item_id: String)
## Use a tool: take it in hand if needed and work with it on whatever is in reach.
signal use_requested(item_id: String)
## Put a thing from the inventory into the world, or plant a seed.
signal place_requested(item_id: String)
signal plant_requested(item_id: String)
## Read a scroll of the inventory, or cast a known spell.
signal learn_requested(item_id: String)
signal cast_requested(spell_id: String)
signal unequip_requested
signal unequip_offhand_requested
## Take off armour: `body` or `hands`.
signal unequip_slot_requested(slot: String)
## Drop an unequipped inventory stack onto the ground at the character's feet.
signal drop_requested(item_id: String)

const ITEM_ICONS := preload("res://scripts/item_icons.gd")
const GRAVES := "res://assets/kenney/graveyard-kit/"
const MODELS := {"headstone": ["gravestone-round"], "monument": ["pillar-obelisk"], "mausoleum": ["crypt-large", "crypt-large-roof", "crypt-large-door"]}
var panel: PanelContainer
var content: VBoxContainer
var summary: Label
var inventory_list: VBoxContainer
var grave_list: VBoxContainer
var feedback: Label
var preview: SubViewport
var preview_container: SubViewportContainer
var _model: Node3D
var _profile: Dictionary = {}
var _obituary: Dictionary = {}
var _grave: Dictionary = {}
var _busy := false
var _feedback_key := ""
var _buttons: Array[Button] = []
## The button whose request is on its way (it spins), and when it was sent.
var _pending_key := ""
var _pending_since := 0
## Whether the panel is narrower than 520 px, so the rows put their buttons under the item.
var _narrow := false

func _ready() -> void:
	layer = 4
	add_child(UiKit.backdrop(0.78))
	panel = PanelContainer.new()
	add_child(panel)
	panel.theme_type_variation = &"FramePanel"
	var column := VBoxContainer.new()
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	summary = Label.new()
	summary.theme_type_variation = &"HeaderLabel"
	summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(summary)
	var close := Button.new()
	close.theme_type_variation = &"GhostButton"
	UiKit.hook_sounds(close, "back")
	close.text = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	column.add_child(UiKit.divider())
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	inventory_list = _list()
	grave_list = _list()
	feedback = Label.new()
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(760, screen.x - 24), minf(680, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions
	if _narrow != (dimensions.x < 520.0):
		_narrow = dimensions.x < 520.0
		_render.call_deferred()

func open() -> void:
	_grave = {}
	_obituary = {}
	var was_open := visible
	show()
	if not was_open:
		UiKit.open_animated(panel)
	_render()

## The spells the character knows: `{mana, mana_max, spells: [{id, name, mana, effect, ready_in_ms ...}]}`.
var _spells: Dictionary = {}

func set_spells(known: Dictionary) -> void:
	_spells = known.duplicate(true)
	if is_instance_valid(inventory_list):
		_render()

func _spells_list() -> void:
	var spells: Array = _spells.get("spells", [])
	if spells.is_empty():
		return
	var heading := _label(inventory_list, tr("Spells") + "  ·  " + tr("Mana") + " %s / %s" % [_spells.get("mana", 0), _spells.get("mana_max", 100)])
	heading.theme_type_variation = &"HeaderLabel"
	heading.add_theme_font_size_override("font_size", 17)
	var number := 0
	for spell: Dictionary in spells:
		number += 1
		var row := _card(inventory_list)
		# The column holds the row and, on a narrow panel, the line of buttons under it.
		row.get_parent().name = "Spell_" + spell.id
		_label(row, "%s  ·  %s %s  ·  %s" % [tr(spell.name), spell.mana, tr("mana"), tr("key %s") % number if number <= 9 else ""])
		var button := Button.new()
		button.name = "Cast"
		button.text = tr("Cast")
		button.custom_minimum_size = Vector2(72, 40)
		button.disabled = _busy or not _alive() or int(_spells.get("mana", 0)) < int(spell.mana)
		row.add_child(button)
		_action(button, "Cast:" + String(spell.id), func() -> void: cast_requested.emit(spell.id))
		_center_buttons(row)

func set_profile(profile: Dictionary) -> void:
	var unchanged := not profile.is_empty() and _shown_part(profile) == _shown_part(_profile)
	_profile = profile.duplicate(true)
	if profile.is_empty():
		_obituary = {}
		_grave = {}
		hide()
	# Stats arrive with every step and survival tick. Rebuilding the list then would replace the buttons under the
	# mouse, and a click pressed on one button and released on its replacement is lost: redraw only on a real change.
	if unchanged:
		return
	_render()

## The part of a profile the panel shows (stats change with every step; of them only the gold is listed).
func _shown_part(profile: Dictionary) -> Array:
	return [profile.get("inventory"), profile.get("equipment"), profile.get("life", {}).get("alive"), profile.get("stats", {}).get("gold")]

func set_busy(value: bool) -> void:
	_busy = value
	_disable_actions()
	# The answer is in: keep the hourglass a moment so a near server still shows it, then restore.
	if not value and not _pending_key.is_empty():
		var left := MIN_PENDING_MS - (Time.get_ticks_msec() - _pending_since)
		if left > 0:
			await get_tree().create_timer(left / 1000.0).timeout
		_finish_pending()

## Local refusal before a request left (wrong state, already busy elsewhere): drop the hourglass.
func cancel_pending() -> void:
	_finish_pending()
	_busy = false
	_disable_actions()

## Registers an action button: hourglass and disable at once; stay that way until `set_busy(false)`
## (server answered) or `cancel_pending()` (the click never became a request).
func _action(button: Button, key: String, act: Callable) -> void:
	_buttons.append(button)
	button.set_meta("pending_key", key)
	button.pressed.connect(func() -> void:
		set_feedback("")
		# One in-flight action at a time: busy flag, hourglass, or a pending key still clearing.
		if _busy or not _pending_key.is_empty() or button.has_node("PendingSpinner"):
			return
		_pending_key = key
		_pending_since = Time.get_ticks_msec()
		# Optimistic busy so a second click cannot start another request before the client marks busy.
		_busy = true
		UiKit.set_pending(button, true)
		_disable_actions()
		act.call()
		var sent := _pending_since
		get_tree().create_timer(MAX_PENDING_MS / 1000.0).timeout.connect(func() -> void:
			if _pending_key == key and _pending_since == sent:
				_finish_pending()
				_busy = false
				_disable_actions()
		)
	)
	# A list drawn again while the answer is awaited keeps the spinner on its button.
	if key == _pending_key:
		UiKit.set_pending(button, true)

func _disable_actions() -> void:
	for button in _buttons:
		if not is_instance_valid(button):
			continue
		# Pending key locks every action until the hourglass is cleared (also during MIN_PENDING).
		button.disabled = _busy or not _pending_key.is_empty() or not _alive() or button.has_node("PendingSpinner")

func _finish_pending() -> void:
	var key := _pending_key
	_pending_key = ""
	for button in _buttons:
		if is_instance_valid(button) and button.get_meta("pending_key", "") == key:
			UiKit.set_pending(button, false)
			button.disabled = _busy or not _alive()

func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message)

func show_obituary(data: Dictionary) -> void:
	_obituary = data.duplicate(true)
	_grave = {}
	set_feedback("")
	show()
	_render()

func set_grave(data: Dictionary) -> void:
	_obituary = {}
	_grave = data.duplicate(true)
	show()
	_render()

## Whether the memorial's stored belongings include the item.
func _grave_holds(item_id: String) -> bool:
	for item: Variant in _grave.get("items", []):
		if item is Dictionary and item.get("item_id") == item_id:
			return true
	return false

func _alive() -> bool:
	return _profile.get("life", {}).get("alive", false) == true

func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _label(list: Node, text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(label)
	return label

## A row of the list on a dark clay card; returns the row the contents go into.
func _card(list: VBoxContainer, highlighted := false) -> HBoxContainer:
	return UiKit.card(list, highlighted)

func _item(list: VBoxContainer, item: Dictionary, grave_id := "") -> void:
	var id: String = item.get("item_id", "")
	var in_hand_now: bool = id in _profile.get("equipment", {}).values()
	var row := _card(list, grave_id.is_empty() and in_hand_now)
	var picture := ITEM_ICONS.texture(id)
	if picture == null:
		# Missing bake: clay tile so the row still has a picture.
		var image := Image.create(44, 44, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.72, 0.55, 0.32, 0.95))
		picture = ImageTexture.create_from_image(image)
	# The icon sits in a sunken slot, like a bag's pocket.
	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", UiTheme.flat_style(Color(0, 0, 0, 0.35), Color(UiTheme.GOLD_DIM, 0.6), 1, 3, 3.0))
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slot)
	var icon := TextureRect.new()
	icon.texture = picture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44, 44)
	slot.add_child(icon)
	var name_text := tr(item.get("name", id)) + " x " + str(item.get("quantity", "0"))
	var calories: int = int(item.get("calories", 0))
	if calories > 0:
		name_text += "\n" + tr("%s kcal") % calories
		var water: int = int(item.get("water", 0))
		if water > 0:
			name_text += ", " + tr("water +%s") % water
	var skin: bool = grave_id.is_empty() and item.get("capacity_ml") != null and item.get("fill_ml") != null
	if skin:
		name_text += "\n" + tr("Water %s / %s l") % ["%.1f" % (float(item.fill_ml) / 1000.0), "%.1f" % (float(item.capacity_ml) / 1000.0)]
	var equippable: bool = grave_id.is_empty() and item.get("category") in ["tool", "weapon", "shield", "armor"]
	var shield: bool = item.get("category") == "shield"
	var worn_slot := _worn_slot(id) if equippable and item.get("category") == "armor" else ""
	var in_hand: bool = equippable and (not worn_slot.is_empty() if item.get("category") == "armor" else _profile.get("equipment", {}).get("offhand" if shield else "hand") == id)
	if item.get("durability") is float or item.get("durability") is int:
		name_text += "\n" + tr("Durability %s / %s") % [int(item.durability), int(item.get("max_durability", item.durability))]
	if in_hand:
		name_text += "\n" + tr("Worn" if item.get("category") == "armor" else "In hand")
	var description := _label(row, name_text)
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if grave_id.is_empty() and item.get("category") == "tool":
		var use := Button.new()
		use.name = "Use"
		use.text = tr("Use")
		use.custom_minimum_size = Vector2(72, 40)
		use.disabled = _busy or not _alive()
		row.add_child(use)
		_action(use, "Use:" + id, func() -> void: use_requested.emit(id))
	if grave_id.is_empty() and id.begins_with("scroll_"):
		var read := Button.new()
		read.name = "Learn"
		read.text = tr("Read")
		read.custom_minimum_size = Vector2(72, 40)
		read.disabled = _busy or not _alive()
		row.add_child(read)
		_action(read, "Learn:" + id, func() -> void: learn_requested.emit(id))
	if skin:
		for action: String in ["Drink", "Fill"]:
			var button := Button.new()
			button.name = "Skin" + action
			button.text = tr(action)
			button.custom_minimum_size = Vector2(72, 40)
			button.disabled = _busy or not _alive() or (action == "Drink" and int(item.fill_ml) <= 0) or (action == "Fill" and int(item.fill_ml) >= int(item.capacity_ml))
			row.add_child(button)
			_action(button, "Skin:" + action, func() -> void: waterskin_requested.emit(action.to_lower()))
	var placeable: bool = grave_id.is_empty() and item.get("category") == "placeable"
	var seed: bool = grave_id.is_empty() and id.begins_with("seed_")
	if placeable or seed:
		var put := Button.new()
		put.name = "Plant" if seed else "Place"
		put.text = tr("Plant" if seed else "Place")
		put.custom_minimum_size = Vector2(72, 40)
		put.disabled = _busy or not _alive()
		row.add_child(put)
		_action(put, "Place:" + id, func() -> void:
			if seed:
				plant_requested.emit(id)
			else:
				place_requested.emit(id)
		)
	if equippable:
		var hold := Button.new()
		hold.name = "Unequip" if in_hand else "Equip"
		hold.text = tr("Unequip" if in_hand else "Equip")
		hold.custom_minimum_size = Vector2(88, 40)
		hold.disabled = _busy or not _alive()
		row.add_child(hold)
		_action(hold, "Equip:" + id, func() -> void:
			if in_hand:
				if not worn_slot.is_empty():
					unequip_slot_requested.emit(worn_slot)
				elif shield:
					unequip_offhand_requested.emit()
				else:
					unequip_requested.emit()
			else:
				equip_requested.emit(id)
		)
	# Equipped pieces stay in the pack until released; only loose inventory can be thrown away.
	if grave_id.is_empty() and not in_hand and id != "gold":
		var drop := Button.new()
		# Quiet, so it is not taken for the main action of the row.
		drop.theme_type_variation = &"GhostButton"
		drop.name = "Drop"
		drop.text = tr("Drop")
		drop.custom_minimum_size = Vector2(72, 40)
		drop.disabled = _busy or not _alive()
		drop.tooltip_text = tr("Drop on the ground")
		row.add_child(drop)
		_action(drop, "Drop:" + id, func() -> void: drop_requested.emit(id))
	if not grave_id.is_empty() or calories > 0:
		var button := Button.new()
		button.name = "Take" if not grave_id.is_empty() else "Eat"
		button.text = tr("Take" if not grave_id.is_empty() else "Eat")
		button.custom_minimum_size = Vector2(72, 40)
		button.disabled = _busy or not _alive()
		row.add_child(button)
		var eat_key := "Eat:" + id + grave_id
		_action(button, eat_key, func() -> void:
			if grave_id.is_empty():
				eat_requested.emit(id)
			else:
				loot_requested.emit(grave_id, id)
		)
	_center_buttons(row)

## Buttons keep their height and sit in the middle of a taller card; on a narrow panel they go on
## a line of their own under the item, so its description keeps the width.
func _center_buttons(row: HBoxContainer) -> void:
	var actions := row
	if _narrow:
		actions = HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_END
		actions.add_theme_constant_override("separation", 8)
		row.get_parent().add_child(actions)
	UiKit.center_buttons(row)
	if actions != row:
		for child in row.get_children():
			if child is Button:
				child.reparent(actions)

## The armour slot (`body` or `hands`) in which the item is worn, or an empty string.
func _worn_slot(item_id: String) -> String:
	var equipment: Dictionary = _profile.get("equipment", {})
	for slot in ["body", "hands"]:
		if equipment.get(slot) == item_id:
			return slot
	return ""

func _render() -> void:
	if not is_instance_valid(inventory_list):
		return
	_buttons.clear()
	_clear(inventory_list)
	_clear(grave_list)
	preview = null
	var memorial := not _grave.is_empty() or not _obituary.is_empty()
	inventory_list.get_parent().visible = not memorial
	grave_list.get_parent().visible = memorial
	var inventory: Dictionary = _profile.get("inventory", {})
	summary.text = tr("Inventory %s / %s") % [inventory.get("used", "-"), inventory.get("capacity", "-")]
	var held: Variant = _profile.get("equipment", {}).get("hand")
	if held is String:
		for item: Variant in inventory.get("items", []):
			if item is Dictionary and item.get("item_id") == held:
				summary.text += "  ·  " + tr("In hand") + ": " + tr(item.get("name", held))
	var defense: Variant = _profile.get("equipment", {}).get("defense", 0)
	if (defense is float or defense is int) and defense > 0:
		summary.text += "  ·  " + tr("Defense %s%%") % int(defense)
	if not _profile.is_empty() and not _alive():
		summary.text += "\n" + tr("Deceased")
	if _profile.get("stats", {}).get("gold", "0") != "0":
		_item(inventory_list, {"item_id": "gold", "name": "Gold", "quantity": _profile.stats.gold})
	for item in inventory.get("items", []):
		if item is Dictionary:
			_item(inventory_list, item)
	if not memorial and _alive():
		_spells_list()
	if memorial:
		summary.text = tr("In Memoriam")
		var notice: Dictionary = _grave.get("obituary", _obituary)
		var name_label := _label(grave_list, notice.get("name", ""))
		name_label.name = "MemorialName"
		name_label.theme_type_variation = &"TitleLabel"
		name_label.add_theme_font_size_override("font_size", 30)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview(_grave.get("kind", "headstone"))
		for entry in [["Born: %s", "born_at"], ["Lived days: %s", "lived_days"], ["Lifetime wealth: %s gold", "lifetime_gold"], ["Friends: %s", "friends_count"]]:
			var value := str(notice.get(entry[1], "-"))
			if entry[1] == "born_at" and value != "-":
				value = value.replace("T", " ").trim_suffix("Z") + " UTC"
			var statistic := _label(grave_list, tr(entry[0]) % value)
			statistic.name = entry[1]
			statistic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# A traveller who died of thirst without a waterskin has it carved on the stone. The text is a key; the
		# server stores the cause only, never a language.
		if str(_grave.get("cause", notice.get("death_cause", ""))) == "dehydration" and not _grave_holds("waterskin"):
			var epitaph := _label(grave_list, "„" + tr("He did not buy a waterskin") + "“")
			epitaph.name = "Epitaph"
			epitaph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not _obituary.is_empty():
		var create := Button.new()
		create.name = "NewCharacter"
		create.text = "New character"
		create.theme_type_variation = &"PrimaryButton"
		create.custom_minimum_size.y = 48
		create.pressed.connect(func() -> void: hide(); new_character_requested.emit())
		grave_list.add_child(create)
	elif not _grave.is_empty():
		if _grave.get("gold", "0") != "0":
			_item(grave_list, {"item_id": "gold", "name": "Gold", "quantity": _grave.gold}, _grave.id)
		for item in _grave.get("items", []):
			if item is Dictionary:
				_item(grave_list, item, _grave.id)
	_resize.call_deferred()

static func _bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var relative: Transform3D = mesh.transform
		var ancestor: Node = mesh.get_parent()
		while ancestor != model:
			if ancestor is Node3D:
				relative = ancestor.transform * relative
			ancestor = ancestor.get_parent()
		var box: AABB = relative * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

static func create_memorial(kind: String) -> Node3D:
	var model := Node3D.new()
	if not MODELS.has(kind):
		return model
	for filename in MODELS[kind]:
		var scene: PackedScene = load(GRAVES + filename + ".glb")
		var part: Node3D = scene.instantiate()
		model.add_child(part)
		if filename == "crypt-large-roof":
			part.position.y = _bounds(model.get_child(0)).end.y - _bounds(part).position.y
		elif filename == "crypt-large-door":
			part.position.z = _bounds(model.get_child(0)).end.z
	return model

func _preview(kind: String) -> void:
	if not MODELS.has(kind):
		return
	preview_container = SubViewportContainer.new()
	preview_container.custom_minimum_size.y = 180
	preview_container.stretch = true
	grave_list.add_child(preview_container)
	preview = SubViewport.new()
	preview.size = Vector2i(360, 180)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(preview)
	_model = create_memorial(kind)
	preview.add_child(_model)
	var bounds := _bounds(_model)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length(), 0.5)
	var camera := Camera3D.new()
	preview.add_child(camera)
	camera.position = center + Vector3(1, 0.7, 1.4).normalized() * radius
	camera.look_at(center)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	preview.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.22, 0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	preview.add_child(environment)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(panel):
		_render()
		feedback.text = tr(_feedback_key)