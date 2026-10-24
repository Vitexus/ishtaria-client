extends SceneTree
## Checks that Latin Akkadian becomes Unicode cuneiform wedges for the tablet prologue.

const Cuneiform := preload("res://scripts/cuneiform.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


func _run() -> void:
	var carved := Cuneiform.from_akkadian("Aruru Enkidu Uruk ša")
	_check(not carved.is_empty(), "cuneiform output is not empty")
	_check(carved.unicode_at(0) >= 0x12000, "first sign is in the cuneiform block")
	var latin_left := false
	for i in carved.length():
		var code := carved.unicode_at(i)
		if code != 0x20 and code != 0x0A and code < 0x12000:
			latin_left = true
			break
	_check(not latin_left, "Latin letters are not left on the tablet")
	_check(Cuneiform.from_akkadian("").is_empty(), "empty Latin stays empty")
	var excerpt := {
		"paraphrase_key": "quest.hunter.excerpt",
		"akkadian_key": "quest.hunter.excerpt.akkadian",
		"voice": "/story/media/gilgamesh/media/voice/cs/quest.hunter.excerpt.ogg",
	}
	_check(preload("res://scripts/story_client.gd").valid_quests([{
		"quest": "gilgamesh:the_hunter_and_the_wild_man",
		"title_key": "gilgamesh:quest.hunter.title",
		"stage": "lay_snares",
		"text_key": "gilgamesh:quest.hunter.lay_snares",
		"final": false,
		"excerpt": excerpt,
	}]), "quest excerpt with narrator voice is accepted")
	excerpt = excerpt.duplicate()
	excerpt.voice = "/evil/../path.ogg"
	_check(not preload("res://scripts/story_client.gd").valid_quests([{
		"quest": "gilgamesh:the_hunter_and_the_wild_man",
		"title_key": "gilgamesh:quest.hunter.title",
		"stage": "lay_snares",
		"text_key": "gilgamesh:quest.hunter.lay_snares",
		"final": false,
		"excerpt": excerpt,
	}]), "a bad voice URL is refused")
	if _failures:
		quit(1)
	else:
		print("cuneiform: ok")
		quit(0)
