extends RefCounted
## Maps Latin Akkadian transliteration to Unicode Sumero-Akkadian cuneiform (U+12000+)
## for the clay-tablet prologue. Syllables are matched longest-first; leftover letters
## become single-sign stand-ins so every Latin character still carves a wedge.
##
## Signs are built with String.chr: GDScript `\uXXXX` only accepts four hex digits, which
## cannot reach the cuneiform block in the supplementary plane.

## Common CV / CVC readings used in the Gilgamesh excerpt lines (Noto Sans Cuneiform).
## Values are Unicode code points (not strings) so they stay above U+FFFF safely.
const SYLLABLES := {
	"lugal": [0x12217],
	"enkidu": [0x12097, 0x121A0, 0x12072, 0x1207A],
	"gilgamesh": [0x12100, 0x12000, 0x122B9, 0x12000, 0x1226D],
	"gilgameš": [0x12100, 0x12000, 0x122B9, 0x12000, 0x1226D],
	"aruru": [0x1202D, 0x12292, 0x12292],
	"ninurta": [0x12261, 0x1230B, 0x1202D],
	"sumukan": [0x122E7, 0x1222A, 0x121A0],
	"sumuqan": [0x122E7, 0x1222A, 0x121A0],
	"nissaba": [0x12261, 0x122E7, 0x12049],
	"nisaba": [0x12261, 0x122E7, 0x12049],
	"uruk": [0x1230B, 0x121A0],
	"šam": [0x122E7],
	"ša": [0x122AD],
	"še": [0x122BA],
	"ši": [0x122BB],
	"šu": [0x122D7],
	"ṣa": [0x122FB],
	"ṣe": [0x122FC],
	"ṣi": [0x122FD],
	"ṣu": [0x12305],
	"ḫa": [0x1212D],
	"ḫe": [0x1212D],
	"ḫi": [0x12134],
	"ḫu": [0x12135],
	"ha": [0x1212D],
	"he": [0x1212D],
	"hi": [0x12134],
	"hu": [0x12135],
	"ba": [0x12040],
	"be": [0x12049],
	"bi": [0x12049],
	"bu": [0x1204D],
	"da": [0x12055],
	"de": [0x12072],
	"di": [0x12072],
	"du": [0x1207A],
	"ga": [0x120B5],
	"ge": [0x12000],
	"gi": [0x12100],
	"gu": [0x12116],
	"ka": [0x121A0],
	"ke": [0x121A0],
	"ki": [0x121A0],
	"ku": [0x121AA],
	"la": [0x121B7],
	"le": [0x121F7],
	"li": [0x121F7],
	"lu": [0x121FB],
	"ma": [0x12220],
	"me": [0x12228],
	"mi": [0x1222A],
	"mu": [0x1222C],
	"na": [0x1223E],
	"ne": [0x12248],
	"ni": [0x1224C],
	"nu": [0x12261],
	"pa": [0x1227A],
	"pe": [0x1227A],
	"pi": [0x1227A],
	"pu": [0x1227B],
	"qa": [0x12248],
	"qe": [0x12248],
	"qi": [0x12248],
	"qu": [0x12261],
	"ra": [0x1228F],
	"re": [0x12292],
	"ri": [0x12292],
	"ru": [0x12292],
	"sa": [0x12293],
	"se": [0x122E2],
	"si": [0x122DB],
	"su": [0x122E2],
	"ta": [0x122FE],
	"te": [0x122FC],
	"ti": [0x122FE],
	"tu": [0x12305],
	"ṭa": [0x122FB],
	"ṭe": [0x122FC],
	"ṭi": [0x122FE],
	"ṭu": [0x12305],
	"wa": [0x12000],
	"we": [0x12000],
	"wi": [0x12000],
	"wu": [0x12000],
	"ya": [0x12000],
	"ye": [0x12000],
	"yi": [0x12000],
	"yu": [0x12000],
	"za": [0x1235A],
	"ze": [0x1235A],
	"zi": [0x12363],
	"zu": [0x1236A],
	"ab": [0x1200A],
	"ad": [0x1201C],
	"ag": [0x1201D],
	"ak": [0x1201D],
	"al": [0x12020],
	"am": [0x1202D],
	"an": [0x1202D],
	"ap": [0x1202D],
	"aq": [0x1202D],
	"ar": [0x1202D],
	"as": [0x1202D],
	"at": [0x1202D],
	"aṣ": [0x1202D],
	"aš": [0x1202D],
	"aṭ": [0x1202D],
	"eb": [0x1208A],
	"ed": [0x1208A],
	"eg": [0x1208A],
	"ek": [0x1208A],
	"el": [0x1208A],
	"em": [0x1208A],
	"en": [0x12097],
	"ep": [0x1208A],
	"eq": [0x1208A],
	"er": [0x1208A],
	"es": [0x1208A],
	"et": [0x1208A],
	"ib": [0x1213F],
	"id": [0x1213F],
	"ig": [0x1213F],
	"ik": [0x1213F],
	"il": [0x1213F],
	"im": [0x1214E],
	"in": [0x12154],
	"ip": [0x1213F],
	"iq": [0x1213F],
	"ir": [0x1213F],
	"is": [0x1213F],
	"it": [0x1213F],
	"ub": [0x1230B],
	"ud": [0x12313],
	"ug": [0x1230B],
	"uk": [0x1230B],
	"ul": [0x1230B],
	"um": [0x1231C],
	"un": [0x12326],
	"up": [0x1230B],
	"uq": [0x1230B],
	"ur": [0x12328],
	"us": [0x1230B],
	"ut": [0x1230B],
	"a": [0x12000],
	"e": [0x1208A],
	"i": [0x1213F],
	"u": [0x1230B],
	"á": [0x12000],
	"é": [0x1208A],
	"í": [0x1213F],
	"ú": [0x1230B],
}

static var _sorted: Array[String] = []


## Turns a Latin Akkadian line into a string of cuneiform signs (spaces and newlines kept).
static func from_akkadian(latin: String) -> String:
	if latin.is_empty():
		return ""
	_ensure_sorted()
	var out := ""
	var i := 0
	var lower := latin.to_lower()
	while i < lower.length():
		var ch := lower[i]
		if ch == " " or ch == "\n" or ch == "\t":
			out += " " if ch != "\n" else "\n"
			i += 1
			continue
		if ch == "-" or ch == "—" or ch == "." or ch == "," or ch == ";" or ch == ":" or ch == "!" or ch == "?" or ch == "'" or ch == "ʾ" or ch == "ʿ":
			i += 1
			continue
		var matched := false
		for syllable: String in _sorted:
			var length := syllable.length()
			if i + length <= lower.length() and lower.substr(i, length) == syllable:
				out += _signs(SYLLABLES[syllable])
				i += length
				matched = true
				break
		if not matched:
			out += String.chr(0x12000 + (ch.unicode_at(0) % 200))
			i += 1
	return out.strip_edges()


static func _signs(codes: Array) -> String:
	var out := ""
	for code: Variant in codes:
		out += String.chr(int(code))
	return out


static func _ensure_sorted() -> void:
	if not _sorted.is_empty():
		return
	for key: String in SYLLABLES.keys():
		_sorted.append(key)
	_sorted.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
