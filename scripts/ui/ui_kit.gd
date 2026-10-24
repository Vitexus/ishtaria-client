extends RefCounted
## Shared pieces of every menu and window, so they look and move alike: the framed clay panel,
## a gold section header with its divider, the darkened backdrop behind a menu, the open and
## close animation and the interface sounds of buttons. Colours and fonts come from ui_theme.gd.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const VIGNETTE := preload("res://scripts/ui/vignette.gdshader")
const SPINNER := preload("res://assets/branding/spinner.png")

const OPEN_SECONDS := 0.18
const CLOSE_SECONDS := 0.12
const HOVER_SECONDS := 0.1

## The interface sounds of main.gd (interface_audio.gd); null in tests, then buttons are silent.
static var audio: Node

## A framed clay panel; returns the column inside it to which the content is added.
static func framed_panel(parent: Node, separation := 10) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"FramePanel"
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	panel.add_child(column)
	return column

## A title in the gold display font with a fading divider under it. The label is returned so
## its text can be changed when the language changes.
static func section_header(parent: Node, text := "", variation := &"HeaderLabel") -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	parent.add_child(divider())
	return label

## A gold line that fades out to both sides from a knot in the middle: the fading divider of
## the border kit (its knot is at the right end) and its mirror image, end to end.
static func divider() -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.custom_minimum_size.y = 18
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for mirrored in [false, true]:
		var half := NinePatchRect.new()
		half.texture = _divider_half(mirrored)
		half.patch_margin_left = 0 if not mirrored else 24
		half.patch_margin_right = 24 if not mirrored else 0
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		half.custom_minimum_size = Vector2(40, 18)
		half.modulate = UiTheme.GOLD
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(half)
	return line

static var _divider_halves := {}

static func _divider_half(mirrored: bool) -> Texture2D:
	if not _divider_halves.has(mirrored):
		var texture: Texture2D = load(UiTheme.DIVIDER_TEXTURE)
		if not mirrored:
			_divider_halves[mirrored] = texture
		else:
			var image := texture.get_image()
			if image.is_compressed():
				image.decompress()
			image.flip_x()
			_divider_halves[mirrored] = ImageTexture.create_from_image(image)
	return _divider_halves[mirrored]

## The dark veil behind a menu: the scene stays visible at the centre and fades to near black
## at the edges. Full rect; it stops the mouse from reaching the world beneath.
static func backdrop(strength := 0.82) -> ColorRect:
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE
	material.set_shader_parameter("tint", Color(UiTheme.CLAY_DARK, 1.0))
	material.set_shader_parameter("strength", strength)
	veil.material = material
	return veil

## Fades a control in and lets it grow from 96 % to full size around its centre.
static func open_animated(control: Control) -> void:
	control.show()
	control.modulate.a = 0.0
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2.ONE * 0.96
	var tween := control.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, OPEN_SECONDS)
	tween.tween_property(control, "scale", Vector2.ONE, OPEN_SECONDS)

## Fades a control out and hides it; `done` runs after it is hidden.
static func close_animated(control: Control, done := Callable()) -> void:
	var tween := control.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "modulate:a", 0.0, CLOSE_SECONDS)
	tween.tween_callback(func() -> void:
		control.hide()
		control.modulate.a = 1.0
		if done.is_valid():
			done.call()
	)

## Gives a button the interface click, and a short brightening while the pointer is over it.
static func hook_sounds(button: BaseButton, sound := "click") -> void:
	button.pressed.connect(func() -> void:
		if is_instance_valid(audio):
			audio.play(sound)
	)
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		var tween := button.create_tween()
		tween.tween_property(button, "self_modulate", Color(1.12, 1.08, 1.0), HOVER_SECONDS)
	)
	button.mouse_exited.connect(func() -> void:
		var tween := button.create_tween()
		tween.tween_property(button, "self_modulate", Color.WHITE, HOVER_SECONDS)
	)

## Marks a button whose request is on its way to the server: its text gives way to a turning
## gold spinner, it keeps its size and its look (not the dimmed disabled one) and cannot be
## pressed again. `false` restores the text. The caller keeps it disabled while it waits.
static func set_pending(button: Button, pending: bool) -> void:
	var spinner := button.get_node_or_null("PendingSpinner") as TextureRect
	if pending == (spinner != null):
		return
	if pending:
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, button.get_combined_minimum_size().x)
		button.set_meta("pending_text", button.text)
		button.text = ""
		button.disabled = true
		button.add_theme_stylebox_override("disabled", button.get_theme_stylebox("pressed"))
		spinner = TextureRect.new()
		spinner.name = "PendingSpinner"
		spinner.texture = SPINNER
		spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spinner.modulate = UiTheme.GOLD_BRIGHT
		spinner.set_anchors_preset(Control.PRESET_CENTER)
		spinner.offset_left = -11.0
		spinner.offset_top = -11.0
		spinner.offset_right = 11.0
		spinner.offset_bottom = 11.0
		spinner.pivot_offset = Vector2(11, 11)
		button.add_child(spinner)
		spinner.create_tween().set_loops().tween_property(spinner, "rotation", TAU, 0.8).from(0.0)
	else:
		button.remove_child(spinner)
		spinner.queue_free()
		button.text = button.get_meta("pending_text", button.text)
		button.remove_meta("pending_text")
		button.remove_theme_stylebox_override("disabled")

## Lights a card up in gold for a moment, to show that what it stands for has just happened.
static func flash(control: Control) -> void:
	control.modulate = Color(1.5, 1.3, 0.75)
	control.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(control, "modulate", Color.WHITE, 0.7)

## A row of a list on a dark clay card (inventory, shop, recipes, friends); returns the row the
## contents go into; name the row, so the icon stays its first child. A highlighted card (an item in hand) has a brighter edge.
static func card(list: Node, highlighted := false) -> HBoxContainer:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UiTheme.flat_style(Color(UiTheme.CLAY_DARK, 0.7), Color(UiTheme.GOLD if highlighted else UiTheme.GOLD_DIM, 0.9 if highlighted else 0.45), 1, 3, 8.0))
	list.add_child(holder)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	holder.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	return row

## Buttons of a card row keep their height and sit in its middle.
static func center_buttons(row: HBoxContainer) -> void:
	for child in row.get_children():
		if child is Button:
			child.size_flags_vertical = Control.SIZE_SHRINK_CENTER

## A square button showing only an icon (Kenney Game Icons) tinted like the text of buttons;
## the caller sets its translated tooltip.
static func icon_button(texture: Texture2D, sound := "click", side := 40) -> Button:
	var result := button("", &"GhostButton", sound)
	result.icon = texture
	result.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_constant_override("icon_max_width", int(side * 0.55))
	result.custom_minimum_size = Vector2(side, side)
	return result

## A themed button; `variation` is &"PrimaryButton", &"GhostButton" or empty.
static func button(text: String, variation := &"", sound := "click") -> Button:
	var result := Button.new()
	result.text = text
	result.theme_type_variation = variation
	result.focus_mode = Control.FOCUS_ALL
	hook_sounds(result, sound)
	return result
