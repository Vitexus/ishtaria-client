extends SceneTree
## "Tell me about yourself": the knowledge card of a character in the dialogue panel. Headless runs check the
## behaviour; a native run (`godot4 --path . --script res://tests/about_card.gd`) also checks that the card fits
## the window in Czech and writes screenshots to /tmp to look at.

const PICTURE := "res://../ishtaria-server/assets/knowledge/shepherd.jpg"
const TEXTS := {
	"world:npc.shepherd": "Pastevec",
	"world:shepherd.greet": "Dávejte pozor na stádo, pocestný. Rozutečou se, když jimi proběhnete.",
	"world:shepherd.ask_flock": "Kam hnáte ovce a kozy?",
	"world:shepherd.leave": "Šťastnou cestu.",
	"world:knowledge.shepherd.title": "Pastevec",
	"world:knowledge.shepherd.text": "Stáda ovcí a koz chová lidé zhruba deset tisíc let. Pastevec hnal zvířata přes den na čerstvou pastvu, na noc je vedl domů a bránil je před vlky a zloději. Vlna, mléko, maso a kůže udělaly ze stáda jednu z prvních podob bohatství.",
	"world:knowledge.shepherd.credit": "Vincent van Gogh, Pastýř se stádem ovcí (1884). Volné dílo, přes Wikimedia Commons.",
}

class StubStory extends Node:
	var texts: Dictionary
	func text(key: String, _args: Array = []) -> String:
		return texts.get(key, key)
	func fetch_media(_url: String) -> void:
		pass

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _run() -> void:
	TranslationServer.set_locale("cs")
	var story := StubStory.new()
	story.texts = TEXTS
	root.add_child(story)
	var dialogue := preload("res://scripts/dialogue_panel.gd").new()
	dialogue.story = story
	root.add_child(dialogue)
	var reply := {"npc_id": "world:shepherd_00", "name_key": "world:npc.shepherd", "seq": 1, "open": true, "about": true,
		"node": {"node": "greet", "text_key": "world:shepherd.greet", "choices": [{"index": 0, "text_key": "world:shepherd.ask_flock"}, {"index": 1, "text_key": "world:shepherd.leave"}]}}
	dialogue.show_reply(reply)
	var about: Button = dialogue.choices_box.get_node("About")
	_check(about.text == "Pověz mi něco o sobě", "the option is in Czech: %s" % about.text)
	var card := {"title_key": "world:knowledge.shepherd.title", "text_key": "world:knowledge.shepherd.text", "credit_key": "world:knowledge.shepherd.credit",
		"image": "/story/media/world/media/knowledge/shepherd.jpg", "wikipedia": {"en": "Shepherd", "cs": "Pastýř"}}
	dialogue.show_about("world:shepherd_00", card)
	var picture := Image.load_from_file(ProjectSettings.globalize_path(PICTURE))
	_check(picture != null, "the picture of the card is installed with the server")
	if picture != null:
		dialogue.media_ready(card.image, ImageTexture.create_from_image(picture))
		_check(dialogue.portrait.texture != null, "the picture of the card replaces the portrait")
	var link: Button = dialogue.choices_box.find_child("Wikipedia", true, false)
	_check(link != null and link.text == "Číst více na Wikipedii", "the link is in Czech")
	_check(dialogue._card_url == "https://cs.wikipedia.org/wiki/Past%C3%BD%C5%99", "the article of the Czech client: %s" % dialogue._card_url)
	if DisplayServer.get_name() != "headless":
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480)]:
			root.size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(dialogue.panel.get_global_rect()), "the card fits the window %s" % dimensions)
			_check(bounds.encloses(dialogue.choices_box.get_global_rect()), "the credit and the buttons are inside the window %s" % dimensions)
			_check(bounds.encloses(link.get_global_rect()), "the link button is inside the window %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-about-cs-%sx%s.png" % [dimensions.x, dimensions.y])
	dialogue.choices_box.find_child("Back", true, false).pressed.emit()
	_check(dialogue.choices_box.has_node("About") and dialogue.speech.text == TEXTS["world:shepherd.greet"], "back to the conversation")
	if _failures > 0:
		push_error("%d about card checks failed" % _failures)
	else:
		print("About card checks passed")
	quit(1 if _failures > 0 else 0)
