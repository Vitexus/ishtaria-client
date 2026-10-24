extends RefCounted
## The look of the whole interface in one place: the palette of an Early Dynastic city (fired
## clay, sand, lapis lazuli, gold and carnelian), the Kenney fonts with Czech carons
## (tools/kenney-font-czech.py) and a Godot Theme built from them. main.gd merges it into the
## default theme, so every window and panel uses it; a panel only names a variation
## (`theme_type_variation`) instead of overriding colours and style boxes itself.
##
## Variations: TitleLabel, HeaderLabel, MutedLabel, GoldLabel, PrimaryButton, GhostButton,
## FramePanel, InsetPanel, HeaderPanel, ChoiceButton.

const FramedStyleBox := preload("res://scripts/ui/framed_style_box.gd")

const CLAY_DARK := Color("1e130d")
const CLAY := Color("3a2418")
const CLAY_LIGHT := Color("5a3a26")
const SAND := Color("ecdcb4")
const SAND_MUTED := Color("b8a27c")
const LAPIS_DARK := Color("142a63")
const LAPIS := Color("1f3f8f")
const LAPIS_LIGHT := Color("3a68d8")
const GOLD := Color("e0b04a")
const GOLD_BRIGHT := Color("ffd77a")
const GOLD_DIM := Color("8f6d2e")
const CARNELIAN := Color("c0502f")
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)

const TITLE_FONT := "res://assets/kenney/fonts/KenneyFutureCS.ttf"
const LABEL_FONT := "res://assets/kenney/fonts/KenneyFutureNarrowCS.ttf"
const BORDERS := "res://assets/kenney/fantasy-ui-borders/PNG/Default/"
const FRAME_TEXTURE := BORDERS + "Border/panel-border-026.png"
const FILL_TEXTURE := BORDERS + "Panel/panel-011.png"
const DIVIDER_TEXTURE := BORDERS + "Divider Fade/divider-fade-003.png"

static var _theme: Theme
static var _fonts := {}

## The shared theme; built once.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme

## The Kenney title face (capitals, wide) or the narrow label face. Missing glyphs (player
## names in other scripts, typographic signs) fall back to Godot's default font.
static func font(narrow := false) -> Font:
	var path := LABEL_FONT if narrow else TITLE_FONT
	if not _fonts.has(path):
		var file: Font = load(path)
		var variation := FontVariation.new()
		variation.base_font = file
		variation.spacing_glyph = 0 if narrow else 1
		variation.fallbacks = [ThemeDB.fallback_font]
		_fonts[path] = variation
	return _fonts[path]

## A clay panel in the gold frame of the border kit.
static func framed_style(fill := Color(CLAY, 0.94), frame := GOLD, content := 28.0) -> StyleBox:
	var style := FramedStyleBox.new(load(FILL_TEXTURE), fill, load(FRAME_TEXTURE), frame, 16, 2)
	_margins(style, content)
	return style

static func flat_style(fill: Color, border: Color, width := 2, radius := 3, content := 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	_margins(style, content)
	style.content_margin_top = content * 0.6
	style.content_margin_bottom = content * 0.6
	return style

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	var label_font := font(true)
	var title_font := font(false)

	# Text.
	theme.set_color("font_color", "Label", SAND)
	theme.set_color("font_shadow_color", "Label", SHADOW)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("default_color", "RichTextLabel", SAND)
	theme.set_color("font_shadow_color", "RichTextLabel", SHADOW)
	_variation(theme, "TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", title_font)
	theme.set_font_size("font_size", "TitleLabel", 34)
	theme.set_color("font_color", "TitleLabel", GOLD_BRIGHT)
	theme.set_color("font_outline_color", "TitleLabel", CLAY_DARK)
	theme.set_constant("outline_size", "TitleLabel", 6)
	theme.set_constant("shadow_offset_y", "TitleLabel", 3)
	_variation(theme, "HeaderLabel", "Label")
	theme.set_font("font", "HeaderLabel", title_font)
	theme.set_font_size("font_size", "HeaderLabel", 18)
	theme.set_color("font_color", "HeaderLabel", GOLD)
	_variation(theme, "GoldLabel", "Label")
	theme.set_font("font", "GoldLabel", label_font)
	theme.set_color("font_color", "GoldLabel", GOLD_BRIGHT)
	_variation(theme, "MutedLabel", "Label")
	theme.set_font_size("font_size", "MutedLabel", 14)
	theme.set_color("font_color", "MutedLabel", SAND_MUTED)

	# Panels.
	theme.set_stylebox("panel", "PanelContainer", flat_style(Color(CLAY_DARK, 0.86), Color(GOLD_DIM, 0.7), 1, 3, 10.0))
	theme.set_stylebox("panel", "Panel", flat_style(Color(CLAY_DARK, 0.86), Color(GOLD_DIM, 0.7), 1, 3, 10.0))
	_variation(theme, "FramePanel", "PanelContainer")
	theme.set_stylebox("panel", "FramePanel", framed_style())
	_variation(theme, "InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel", flat_style(Color(CLAY_DARK, 0.72), Color(GOLD_DIM, 0.45), 1, 2, 10.0))
	_variation(theme, "HeaderPanel", "PanelContainer")
	var header := flat_style(Color(LAPIS_DARK, 0.92), GOLD, 0, 0, 14.0)
	header.border_width_bottom = 2
	theme.set_stylebox("panel", "HeaderPanel", header)
	theme.set_stylebox("panel", "PopupPanel", flat_style(Color(CLAY_DARK, 0.97), GOLD_DIM, 1, 2, 6.0))
	theme.set_stylebox("panel", "TooltipPanel", flat_style(Color(CLAY_DARK, 0.96), GOLD, 1, 2, 8.0))
	theme.set_color("font_color", "TooltipLabel", SAND)
	theme.set_font_size("font_size", "TooltipLabel", 14)

	# Windows (settings and other native dialogs).
	theme.set_stylebox("embedded_border", "Window", framed_style(Color(CLAY, 0.97), GOLD, 12.0))
	theme.set_stylebox("embedded_unfocused_border", "Window", framed_style(Color(CLAY, 0.97), GOLD_DIM, 12.0))
	theme.set_font("title_font", "Window", title_font)
	theme.set_font_size("title_font_size", "Window", 16)
	theme.set_color("title_color", "Window", GOLD)
	theme.set_constant("title_height", "Window", 40)
	theme.set_stylebox("panel", "AcceptDialog", flat_style(Color(CLAY, 0.0), Color(0, 0, 0, 0), 0, 0, 16.0))

	# Buttons: clay with a thin gold edge; lapis when hovered, as glazed brick.
	_buttons(theme, "Button", Color(CLAY_LIGHT, 0.92), LAPIS, LAPIS_DARK)
	theme.set_font("font", "Button", label_font)
	theme.set_font_size("font_size", "Button", 17)
	_variation(theme, "PrimaryButton", "Button")
	_buttons(theme, "PrimaryButton", Color(LAPIS, 0.95), LAPIS_LIGHT, LAPIS_DARK)
	theme.set_font_size("font_size", "PrimaryButton", 20)
	_variation(theme, "GhostButton", "Button")
	_buttons(theme, "GhostButton", Color(0, 0, 0, 0), Color(LAPIS, 0.7), Color(LAPIS_DARK, 0.8))
	theme.set_stylebox("normal", "GhostButton", flat_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 14.0))
	# An answer in a conversation: readable body text, a gold strip at its left edge, lapis when
	# hovered.
	_variation(theme, "ChoiceButton", "Button")
	_buttons(theme, "ChoiceButton", Color(CLAY_DARK, 0.55), LAPIS, LAPIS_DARK)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var choice := (theme.get_stylebox(state, "ChoiceButton") as StyleBoxFlat).duplicate() as StyleBoxFlat
		choice.border_width_left = 3
		choice.border_width_top = 0 if state != "focus" else choice.border_width_top
		choice.border_width_right = 0 if state != "focus" else choice.border_width_right
		choice.border_width_bottom = 0 if state != "focus" else choice.border_width_bottom
		choice.shadow_size = 0
		choice.content_margin_left = 14.0
		theme.set_stylebox(state, "ChoiceButton", choice)
	theme.set_font("font", "ChoiceButton", ThemeDB.fallback_font)
	theme.set_font_size("font_size", "ChoiceButton", 16)
	theme.set_constant("outline_size", "ChoiceButton", 0)
	for kind in ["OptionButton", "MenuButton", "CheckBox", "CheckButton", "LinkButton"]:
		if kind in ["OptionButton", "MenuButton"]:
			theme.set_font("font", kind, label_font)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			theme.set_color(state, kind, GOLD_BRIGHT if state != "font_color" else SAND)
	_buttons(theme, "OptionButton", Color(CLAY_DARK, 0.9), LAPIS, LAPIS_DARK)
	theme.set_icon("arrow", "OptionButton", _arrow_icon())
	for kind in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		_margins(empty, 4.0)
		for state in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
			theme.set_stylebox(state, kind, empty)
		theme.set_stylebox("focus", kind, flat_style(Color(0, 0, 0, 0), Color(GOLD, 0.6), 1, 3, 4.0))
	for icon in ["checked", "radio_checked"]:
		theme.set_icon(icon, "CheckBox", _check_icon(true))
	for icon in ["unchecked", "radio_unchecked"]:
		theme.set_icon(icon, "CheckBox", _check_icon(false))
	theme.set_icon("checked", "CheckButton", _toggle_icon(true))
	theme.set_icon("unchecked", "CheckButton", _toggle_icon(false))
	theme.set_constant("h_separation", "CheckBox", 10)

	# Text input.
	var field := flat_style(Color(CLAY_DARK, 0.92), Color(GOLD_DIM, 0.8), 1, 2, 10.0)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("read_only", "LineEdit", flat_style(Color(CLAY_DARK, 0.6), Color(GOLD_DIM, 0.4), 1, 2, 10.0))
	theme.set_stylebox("focus", "LineEdit", flat_style(Color(0, 0, 0, 0), GOLD, 2, 2, 10.0))
	theme.set_color("font_color", "LineEdit", SAND)
	theme.set_color("font_placeholder_color", "LineEdit", Color(SAND_MUTED, 0.6))
	theme.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	theme.set_color("selection_color", "LineEdit", Color(LAPIS_LIGHT, 0.6))
	theme.set_stylebox("normal", "TextEdit", field)
	theme.set_stylebox("focus", "TextEdit", flat_style(Color(0, 0, 0, 0), GOLD, 2, 2, 10.0))
	theme.set_color("font_color", "TextEdit", SAND)

	# Lists and menus.
	theme.set_stylebox("panel", "ItemList", flat_style(Color(CLAY_DARK, 0.85), Color(GOLD_DIM, 0.6), 1, 2, 6.0))
	theme.set_stylebox("selected", "ItemList", flat_style(Color(LAPIS, 0.85), GOLD, 1, 2, 4.0))
	theme.set_stylebox("selected_focus", "ItemList", flat_style(Color(LAPIS, 0.95), GOLD_BRIGHT, 1, 2, 4.0))
	theme.set_stylebox("hovered", "ItemList", flat_style(Color(LAPIS_DARK, 0.6), Color(0, 0, 0, 0), 0, 2, 4.0))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", SAND)
	theme.set_color("font_selected_color", "ItemList", GOLD_BRIGHT)
	theme.set_color("font_hovered_color", "ItemList", GOLD_BRIGHT)
	theme.set_constant("v_separation", "ItemList", 6)
	theme.set_stylebox("hover", "PopupMenu", flat_style(Color(LAPIS, 0.9), Color(0, 0, 0, 0), 0, 2, 4.0))
	theme.set_color("font_color", "PopupMenu", SAND)
	theme.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)
	theme.set_font("font", "PopupMenu", label_font)
	theme.set_constant("v_separation", "PopupMenu", 8)

	# Tabs: lapis plaques along a gold line.
	theme.set_stylebox("panel", "TabContainer", flat_style(Color(CLAY_DARK, 0.55), Color(GOLD_DIM, 0.6), 1, 0, 16.0))
	var tab := flat_style(Color(CLAY_DARK, 0.7), Color(GOLD_DIM, 0.5), 1, 0, 18.0)
	tab.border_width_bottom = 0
	var tab_selected := flat_style(Color(LAPIS, 0.95), GOLD, 1, 0, 18.0)
	tab_selected.border_width_bottom = 0
	tab_selected.border_width_top = 3
	var tab_hover := flat_style(Color(LAPIS_DARK, 0.85), GOLD_DIM, 1, 0, 18.0)
	tab_hover.border_width_bottom = 0
	for kind in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_unselected", kind, tab)
		theme.set_stylebox("tab_selected", kind, tab_selected)
		theme.set_stylebox("tab_hovered", kind, tab_hover)
		theme.set_stylebox("tab_focus", kind, StyleBoxEmpty.new())
		theme.set_font("font", kind, label_font)
		theme.set_font_size("font_size", kind, 16)
		theme.set_color("font_unselected_color", kind, SAND_MUTED)
		theme.set_color("font_hovered_color", kind, SAND)
		theme.set_color("font_selected_color", kind, GOLD_BRIGHT)

	# Sliders, bars and scrolling.
	var groove := flat_style(Color(CLAY_DARK, 0.95), Color(GOLD_DIM, 0.7), 1, 3, 0.0)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", groove)
	var filled := flat_style(LAPIS_LIGHT, Color(0, 0, 0, 0), 0, 3, 0.0)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", _grabber_icon(GOLD))
	theme.set_icon("grabber_highlight", "HSlider", _grabber_icon(GOLD_BRIGHT))
	theme.set_stylebox("background", "ProgressBar", flat_style(Color(CLAY_DARK, 0.9), Color(GOLD_DIM, 0.7), 1, 2, 0.0))
	theme.set_stylebox("fill", "ProgressBar", flat_style(LAPIS_LIGHT, Color(0, 0, 0, 0), 0, 2, 0.0))
	theme.set_color("font_color", "ProgressBar", SAND)
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, flat_style(Color(CLAY_DARK, 0.5), Color(0, 0, 0, 0), 0, 4, 3.0))
		theme.set_stylebox("grabber", bar, flat_style(Color(GOLD_DIM, 0.85), Color(0, 0, 0, 0), 0, 4, 3.0))
		theme.set_stylebox("grabber_highlight", bar, flat_style(GOLD, Color(0, 0, 0, 0), 0, 4, 3.0))
		theme.set_stylebox("grabber_pressed", bar, flat_style(GOLD_BRIGHT, Color(0, 0, 0, 0), 0, 4, 3.0))
	theme.set_stylebox("separator", "HSeparator", _divider_style())
	theme.set_constant("separation", "HSeparator", 18)
	return theme

## A thin fading gold line with a knot in the middle, for section breaks.
static func _divider_style() -> StyleBox:
	var style := StyleBoxTexture.new()
	style.texture = load(DIVIDER_TEXTURE)
	style.texture_margin_left = 40
	style.texture_margin_right = 40
	style.modulate_color = GOLD
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

static func _buttons(theme: Theme, kind: String, fill: Color, hover: Color, pressed: Color) -> void:
	var normal := flat_style(fill, Color(GOLD_DIM, 0.9), 1, 3, 18.0)
	normal.shadow_color = Color(0, 0, 0, 0.35)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 2)
	theme.set_stylebox("normal", kind, normal)
	var hovered := flat_style(hover, GOLD, 2, 3, 18.0)
	hovered.shadow_color = Color(GOLD, 0.25)
	hovered.shadow_size = 8
	theme.set_stylebox("hover", kind, hovered)
	theme.set_stylebox("hover_pressed", kind, hovered)
	theme.set_stylebox("pressed", kind, flat_style(pressed, GOLD_BRIGHT, 2, 3, 18.0))
	theme.set_stylebox("disabled", kind, flat_style(Color(CLAY_DARK, 0.5), Color(GOLD_DIM, 0.35), 1, 3, 18.0))
	theme.set_stylebox("focus", kind, flat_style(Color(0, 0, 0, 0), Color(GOLD_BRIGHT, 0.85), 2, 4, 18.0))
	theme.set_color("font_color", kind, SAND)
	theme.set_color("font_hover_color", kind, GOLD_BRIGHT)
	theme.set_color("font_pressed_color", kind, GOLD_BRIGHT)
	theme.set_color("font_hover_pressed_color", kind, GOLD_BRIGHT)
	theme.set_color("font_focus_color", kind, GOLD_BRIGHT)
	theme.set_color("font_disabled_color", kind, Color(SAND_MUTED, 0.5))
	theme.set_color("icon_normal_color", kind, GOLD)
	theme.set_color("icon_hover_color", kind, GOLD_BRIGHT)
	theme.set_color("icon_pressed_color", kind, GOLD_BRIGHT)
	theme.set_color("icon_focus_color", kind, GOLD_BRIGHT)
	theme.set_color("icon_hover_pressed_color", kind, GOLD_BRIGHT)
	theme.set_color("icon_disabled_color", kind, Color(GOLD_DIM, 0.5))
	theme.set_color("font_outline_color", kind, CLAY_DARK)
	theme.set_constant("outline_size", kind, 3)
	theme.set_constant("h_separation", kind, 10)

static func _variation(theme: Theme, name: String, base: String) -> void:
	theme.add_type(name)
	theme.set_type_variation(name, base)

static func _margins(style: StyleBox, value: float) -> void:
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, value)

# Small icons drawn in code: a gold-edged clay square with a lapis gem, a toggle and a grabber.

static func _check_icon(checked: bool) -> Texture2D:
	var image := Image.create_empty(22, 22, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, 22, 22), GOLD_DIM)
	image.fill_rect(Rect2i(2, 2, 18, 18), CLAY_DARK)
	if checked:
		image.fill_rect(Rect2i(5, 5, 12, 12), GOLD)
		image.fill_rect(Rect2i(7, 7, 8, 8), LAPIS_LIGHT)
	return ImageTexture.create_from_image(image)

static func _toggle_icon(on: bool) -> Texture2D:
	var image := Image.create_empty(44, 22, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, 44, 22), GOLD_DIM)
	image.fill_rect(Rect2i(2, 2, 40, 18), LAPIS if on else CLAY_DARK)
	image.fill_rect(Rect2i(24 if on else 4, 4, 16, 14), GOLD_BRIGHT if on else SAND_MUTED)
	return ImageTexture.create_from_image(image)

static func _grabber_icon(color: Color) -> Texture2D:
	var image := Image.create_empty(14, 22, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, 14, 22), CLAY_DARK)
	image.fill_rect(Rect2i(2, 2, 10, 18), color)
	image.fill_rect(Rect2i(6, 6, 2, 10), CLAY_DARK)
	return ImageTexture.create_from_image(image)

static func _arrow_icon() -> Texture2D:
	var image := Image.create_empty(14, 9, false, Image.FORMAT_RGBA8)
	for row in 7:
		image.fill_rect(Rect2i(row, row + 1, 14 - row * 2, 1), GOLD)
	return ImageTexture.create_from_image(image)
