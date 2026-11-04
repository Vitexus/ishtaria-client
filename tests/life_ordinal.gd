extends SceneTree
## Checks the number of a life on a memorial: Roman by default, cuneiform when the datadisk asks, none for a first life.

const LifeOrdinal := preload("res://scripts/life_ordinal.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	_check(LifeOrdinal.roman(2) == "II" and LifeOrdinal.roman(4) == "IV" and LifeOrdinal.roman(1994) == "MCMXCIV", "Roman numerals")
	_check(LifeOrdinal.roman(4000) == "4000" and LifeOrdinal.roman(0) == "0", "what Roman cannot write stays decimal")
	var one := String.chr(0x12079)
	var ten := String.chr(0x1230B)
	_check(LifeOrdinal.sumerian(1) == one and LifeOrdinal.sumerian(2) == one + one, "cuneiform ones")
	_check(LifeOrdinal.sumerian(13) == ten + one + one + one, "cuneiform tens then ones")
	_check(LifeOrdinal.sumerian(59) == ten.repeat(5) + one.repeat(9), "fifty-nine")
	_check(LifeOrdinal.sumerian(61) == one + " " + one, "sixty-one is two places")
	_check(LifeOrdinal.sumerian(60) == one + " ", "sixty is a place and an empty place")
	# No number for a first life or garbage; the default system is Roman.
	_check(LifeOrdinal.with_name("Heir", null) == "Heir" and LifeOrdinal.with_name("Heir", 1) == "Heir", "a first life has no number")
	_check(LifeOrdinal.with_name("Heir", "II") == "Heir" and LifeOrdinal.with_name("Heir", 2.5) == "Heir", "a malformed number is ignored")
	_check(LifeOrdinal.with_name("Heir", 3) == "Heir III", "engine default is Roman")
	_check(LifeOrdinal.with_name("Heir", 2, "sumerian") == "Heir " + one + one, "datadisk system")
	# The announcement of a datadisk.
	var disk := {"ordinal_numerals": "sumerian", "ordinal_font": "/story/media/gilgamesh/media/fonts/noto-sans-cuneiform-numerals.ttf"}
	_check(LifeOrdinal.announced([{"id": "x"}, disk]) == ["sumerian", disk.ordinal_font], "the first disk that names a system wins")
	_check(LifeOrdinal.announced([]) == ["roman", ""] and LifeOrdinal.announced(null) == ["roman", ""], "Roman without a disk")
	_check(LifeOrdinal.announced([{"ordinal_numerals": "klingon"}]) == ["roman", ""], "an unknown system is ignored")
	_check(LifeOrdinal.announced([{"ordinal_numerals": "sumerian", "ordinal_font": "/evil/../x.ttf"}])[1] == "", "a bad font URL is refused")
	_check(not LifeOrdinal.valid_font_url("/story/media/a/media/fonts/x.exe") and LifeOrdinal.valid_font_url("/story/media/a/media/fonts/x.otf"), "font extensions")
	# The memorial panel writes it.
	LifeOrdinal.numerals = "sumerian"
	var panel := preload("res://scripts/survival_panel.gd").new()
	root.add_child(panel)
	panel.show_obituary({"name": "Heir", "born_at": "2000-01-02T03:04:05.000006Z", "lived_days": "1", "lifetime_gold": "1", "friends_count": "0", "ordinal": 2})
	var label := panel.find_child("MemorialName", true, false) as Label
	_check(label != null and label.text == "Heir " + one + one, "the memorial name carries the cuneiform number")
	panel.show_obituary({"name": "Heir", "born_at": "2000-01-02T03:04:05.000006Z", "lived_days": "1", "lifetime_gold": "1", "friends_count": "0"})
	label = panel.find_child("MemorialName", true, false) as Label
	_check(label != null and label.text == "Heir", "a first life carries the plain name")
	if _failures:
		quit(1)
	else:
		print("life ordinal: ok")
		quit(0)
