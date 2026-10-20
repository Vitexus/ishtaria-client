extends CanvasLayer
## Recipes only: inventory stays in the survival panel.

signal craft_requested(recipe_id: String)
signal recipes_requested

const ITEM_ICONS := preload("res://scripts/item_icons.gd")

var panel: PanelContainer
var recipe_list: VBoxContainer
var feedback: Label
var _profile: Dictionary = {}
var _busy := false
var _feedback_key := ""
var _buttons: Array[Button] = []
var _recipes: Array = []

func _ready() -> void:
	layer = 4
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	recipe_list = VBoxContainer.new()
	recipe_list.name = "Recipes"
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_constant_override("separation", 8)
	scroll.add_child(recipe_list)
	feedback = Label.new()
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
	get_viewport().size_changed.connect(_resize)
	_resize()
	_update_texts()
	hide()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(760, screen.x - 24), minf(680, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions

func open() -> void:
	show()
	_update_texts()
	_render()
	if _recipes.is_empty():
		recipes_requested.emit()

func set_profile(profile: Dictionary) -> void:
	_profile = profile.duplicate(true)
	if profile.is_empty():
		hide()
	_render()

func set_busy(value: bool) -> void:
	_busy = value
	for button in _buttons:
		if is_instance_valid(button):
			button.disabled = value or not _alive()

func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message)

## Accepts the recipe list of the server; malformed entries are ignored.
func set_recipes(recipes: Array) -> void:
	_recipes = []
	for recipe: Variant in recipes:
		if recipe is Dictionary and recipe.get("id") is String and _valid_stacks(recipe.get("inputs")) and _valid_stacks(recipe.get("outputs")):
			_recipes.append(recipe)
	_render()

static func _valid_stacks(stacks: Variant) -> bool:
	if not stacks is Array or stacks.is_empty() or stacks.size() > 8:
		return false
	for stack: Variant in stacks:
		if not stack is Dictionary or not stack.get("item_id") is String or not stack.get("name") is String or not stack.get("quantity") is String or not stack.quantity.is_valid_int():
			return false
	return true

func _owned() -> Dictionary:
	var owned := {}
	for item: Variant in _profile.get("inventory", {}).get("items", []):
		if item is Dictionary and item.get("item_id") is String and item.get("quantity") is String and item.quantity.is_valid_int():
			owned[item.item_id] = int(item.quantity)
	return owned

func _stacks_text(stacks: Array) -> String:
	var parts: Array[String] = []
	for stack: Dictionary in stacks:
		parts.append("%s x %s" % [tr(stack.name), stack.quantity])
	return ", ".join(parts)

func can_craft(recipe: Dictionary) -> bool:
	var owned := _owned()
	for stack: Dictionary in recipe.inputs:
		if owned.get(stack.item_id, 0) < int(stack.quantity):
			return false
	var tool: Variant = recipe.get("tool")
	return not tool is String or owned.get(tool, 0) > 0

func _alive() -> bool:
	return _profile.get("life", {}).get("alive", false) == true

func _clear() -> void:
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()

func _label(list: Node, text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(label)
	return label

func _update_texts() -> void:
	panel.find_child("Title", true, false).text = tr("Crafting")
	panel.find_child("Close", true, false).text = tr("Close")

func _render() -> void:
	if not is_instance_valid(recipe_list):
		return
	_buttons.clear()
	_clear()
	_update_texts()
	if _recipes.is_empty():
		_label(recipe_list, tr("No recipes yet"))
		_resize.call_deferred()
		return
	for recipe: Dictionary in _recipes:
		var row := HBoxContainer.new()
		row.name = "Recipe_" + recipe.id
		recipe_list.add_child(row)
		var icon := ITEM_ICONS.texture(recipe.outputs[0].item_id)
		if icon != null:
			var picture := TextureRect.new()
			picture.texture = icon
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size = Vector2(48, 48)
			row.add_child(picture)
		var text := _stacks_text(recipe.outputs) + "\n" + tr("Needs") + ": " + _stacks_text(recipe.inputs)
		if recipe.get("tool") is String:
			text += " + " + tr("tool") + ": " + tr(String(recipe.tool).capitalize())
		if recipe.get("station") is String:
			text += "\n" + tr("At") + ": " + tr(String(recipe.station).capitalize())
		_label(row, text)
		var button := Button.new()
		button.name = "Craft"
		button.text = tr("Craft")
		button.custom_minimum_size = Vector2(72, 44)
		button.disabled = _busy or not _alive() or not can_craft(recipe)
		button.pressed.connect(func() -> void:
			set_feedback("")
			craft_requested.emit(recipe.id)
		)
		row.add_child(button)
		_buttons.append(button)
	_resize.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(panel):
		_render()
		feedback.text = tr(_feedback_key)
