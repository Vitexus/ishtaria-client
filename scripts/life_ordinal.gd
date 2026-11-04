extends Node
## The number of a life on a memorial: a login may be used again after a permanent death, and the next character
## carries the count after its name, as a ruler does (`Heir II`). The first life has no number, and the server sends
## `ordinal` only from the second life on. The engine counts with Roman numerals; a story datadisk may ask for
## another system (`ordinal_numerals` of its manifest in GET /world `datadisks`) and ships the font for it
## (`ordinal_font`), fetched from the server like the other story media. The numbers are no language: the server
## stores the count only, and the client chooses how to write it.

## The numerals font arrived (or went away): names already drawn without its signs must be drawn again.
signal font_changed

## The cuneiform number signs: DISH (one) and U (ten); a sexagesimal place holds up to fifty-nine of them.
const SUMERIAN_ONE := 0x12079
const SUMERIAN_TEN := 0x1230B
const ROMAN := [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
const MAX_FONT_BYTES := 1048576
const STYLES := ["roman", "sumerian"]

## The system of the world's datadisk and its font; `roman` without a font is the engine default.
static var numerals := "roman"
static var font: Font = null

## The numeral system and font URL the first datadisk that names one asks for; roman and no font otherwise.
static func announced(datadisks: Variant) -> Array:
	if datadisks is Array:
		for disk: Variant in datadisks:
			if not disk is Dictionary or not disk.get("ordinal_numerals") in STYLES:
				continue
			var url: Variant = disk.get("ordinal_font")
			return [disk.ordinal_numerals, url if valid_font_url(url) else ""]
	return ["roman", ""]

static func valid_font_url(url: Variant) -> bool:
	if not url is String or not url.begins_with("/story/media/") or url.length() > 220 or url.contains("..") or url.contains("//") or url.contains("?") or url.contains("#") or url.contains("%") or url.contains("\\"):
		return false
	return url.ends_with(".ttf") or url.ends_with(".otf")

## `value` (1 and up) written in the system; anything else, or a number a system cannot write, stays decimal.
static func format(value: int, style := "") -> String:
	if value < 1:
		return str(value)
	match style if not style.is_empty() else numerals:
		"sumerian":
			return sumerian(value)
		_:
			return roman(value)

static func roman(value: int) -> String:
	if value < 1 or value > 3999:
		return str(value)
	var text := ""
	var rest := value
	for pair: Array in ROMAN:
		while rest >= pair[0]:
			text += pair[1]
			rest -= pair[0]
	return text

## Base 60 as the scribes wrote it: places from the highest, each a row of tens (U) and ones (DISH), a gap for an
## empty place.
static func sumerian(value: int) -> String:
	if value < 1:
		return str(value)
	var places: Array[int] = []
	var rest := value
	while rest > 0:
		places.push_front(rest % 60)
		rest /= 60
	var rows: PackedStringArray = []
	for place in places:
		var row := ""
		for _i in place / 10:
			row += String.chr(SUMERIAN_TEN)
		for _i in place % 10:
			row += String.chr(SUMERIAN_ONE)
		rows.append(row)
	return " ".join(rows)

## The name as written on a memorial: with its number from the second life on.
static func with_name(player_name: String, ordinal: Variant, style := "") -> String:
	if (ordinal is int or ordinal is float) and ordinal >= 2 and ordinal == floorf(ordinal) and ordinal <= 1000000:
		return "%s %s" % [player_name, format(int(ordinal), style)]
	return player_name

## A font that draws the theme font's glyphs first and the numerals font for what it lacks (cuneiform signs).
static func with_fallback(base: Font) -> Font:
	if font == null or base == null:
		return base
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [font]
	return variation

var _request: HTTPRequest
var _wanted := ""

## Takes over what the world's datadisks announce and fetches the font; `server_url` is the base address.
func use(server_url: String, datadisks: Variant) -> void:
	var given := announced(datadisks)
	numerals = given[0]
	var url: String = given[1]
	if url.is_empty():
		_wanted = ""
		_cancel()
		var had := font != null
		font = null
		if had:
			font_changed.emit()
		return
	var key := server_url + url
	if key == _wanted:
		return
	_wanted = key
	_cancel()
	font = null
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	_request.max_redirects = 0
	_request.body_size_limit = MAX_FONT_BYTES
	add_child(_request)
	_request.request_completed.connect(_on_completed.bind(key))
	if _request.request(key) != OK:
		_cancel()
		_wanted = ""

func _cancel() -> void:
	if is_instance_valid(_request):
		_request.queue_free()
	_request = null

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, key: String) -> void:
	_cancel()
	if key != _wanted:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		# The next refresh of the world asks again; the system fonts may still draw the signs.
		_wanted = ""
		return
	var loaded := FontFile.new()
	loaded.data = body
	font = loaded
	font_changed.emit()
