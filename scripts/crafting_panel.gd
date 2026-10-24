extends CanvasLayer
## Recipes only: inventory stays in the survival panel.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal craft_requested(recipe_id: String)
signal recipes_requested

const ITEM_ICONS := preload("res://scripts/item_icons.gd")
## The spinner stays at least this long, so an answer from a near server is still seen.
const MIN_PENDING_MS := 400
## Past the request timeout of the session (8 s), a spinner without an answer stops anyway.
const MAX_PENDING_MS := 10000

var panel: PanelContainer
var recipe_list: VBoxContainer
var feedback: Label
var _profile: Dictionary = {}
var _busy := false
var _feedback_key := ""
var _buttons: Array[Button] = []
var _recipes: Array = []
## The recipe whose request is on its way (its button spins), and when it was sent.
var _pending_recipe := ""
var _pending_since := 0
var _last_recipe := ""
## The recipe to light up once its spinner has stopped (the server said it was crafted).
var _flash_recipe := ""

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
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var close := Button.new()
	close.theme_type_variation = &"GhostButton"
	UiKit.hook_sounds(close, "back")
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
	feedback.name = "Feedback"
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	var was_open := visible
	show()
	if not was_open:
		UiKit.open_animated(panel)
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
		if is_instance_valid(button) and not button.has_node("PendingSpinner"):
			button.disabled = value or not _alive()
	if not value and not _pending_recipe.is_empty():
		var left := MIN_PENDING_MS - (Time.get_ticks_msec() - _pending_since)
		if left > 0:
			await get_tree().create_timer(left / 1000.0).timeout
		_finish_pending()

## "Crafted" is gold and lights up the recipe; a refusal is red.
func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message)
	var success := message == "Crafted"
	feedback.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT if success else UiTheme.CARNELIAN.lightened(0.25))
	if success:
		_flash_recipe = _pending_recipe
		if _pending_recipe.is_empty():
			_flash_recipe = _last_recipe
			_flash_done()

## The answer is in: the spinner gives way to the text again, and a crafted recipe lights up.
func _finish_pending() -> void:
	var recipe_id := _pending_recipe
	_pending_recipe = ""
	var button := _craft_button(recipe_id)
	if button != null:
		UiKit.set_pending(button, false)
		button.disabled = _busy or not _alive() or not _can_craft_id(recipe_id)
	_flash_done()

func _flash_done() -> void:
	if _flash_recipe.is_empty():
		return
	var row := recipe_list.find_child("Recipe_" + _flash_recipe, true, false) as Control
	_flash_recipe = ""
	if row != null:
		UiKit.flash(row.get_parent().get_parent())

func _craft_button(recipe_id: String) -> Button:
	if recipe_id.is_empty() or not is_instance_valid(recipe_list):
		return null
	var row := recipe_list.find_child("Recipe_" + recipe_id, true, false)
	return row.find_child("Craft", true, false) as Button if row != null else null

func _can_craft_id(recipe_id: String) -> bool:
	for recipe: Dictionary in _recipes:
		if recipe.id == recipe_id:
			return can_craft(recipe)
	return false

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
		var row := UiKit.card(recipe_list)
		row.name = "Recipe_" + recipe.id
		var icon: Texture2D = ITEM_ICONS.texture(recipe.outputs[0].item_id)
		if icon == null:
			# Missing bake: clay tile so the recipe row still has a picture.
			var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
			image.fill(Color(0.72, 0.55, 0.32, 0.95))
			icon = ImageTexture.create_from_image(image)
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
			_pending_recipe = recipe.id
			_last_recipe = recipe.id
			_pending_since = Time.get_ticks_msec()
			UiKit.set_pending(button, true)
			var sent := _pending_since
			get_tree().create_timer(MAX_PENDING_MS / 1000.0).timeout.connect(func() -> void:
				if _pending_recipe == recipe.id and _pending_since == sent:
					_finish_pending()
			)
			craft_requested.emit(recipe.id)
		)
		row.add_child(button)
		_buttons.append(button)
		# A list drawn again while the answer is awaited keeps the spinner on its button.
		if recipe.id == _pending_recipe:
			UiKit.set_pending(button, true)
		UiKit.center_buttons(row)
	_resize.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(panel):
		_render()
		feedback.text = tr(_feedback_key)
