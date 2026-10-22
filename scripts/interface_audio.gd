extends Node

const SOUNDS := {
	"click": preload("res://assets/kenney/interface-sounds/Audio/click_001.ogg"),
	"confirmation": preload("res://assets/kenney/interface-sounds/Audio/confirmation_001.ogg"),
	"error": preload("res://assets/kenney/interface-sounds/Audio/error_001.ogg"),
	"back": preload("res://assets/kenney/interface-sounds/Audio/back_001.ogg"),
}

const MIX_RATE := 22050

var enabled := true
var players: Dictionary = {}

func _ready() -> void:
	for sound in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.stream = SOUNDS[sound]
		player.volume_db = -14.0
		player.max_polyphony = 2
		add_child(player)
		players[sound] = player
	_add_synth("fanfare", make_fanfare(), -9.0)
	_add_synth("spell", make_spell(), -11.0)
	_add_synth("warning", make_warning(), -12.0)
	_add_synth("break", make_break(), -10.0)

func _add_synth(name: String, stream: AudioStreamWAV, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_polyphony = 2
	add_child(player)
	players[name] = player

## A short original fanfare for a new level, synthesised from sine waves: a rising
## arpeggio of C major that ends in a held chord. No recording is needed.
static func make_fanfare() -> AudioStreamWAV:
	return _tone_stream(
		[[523.25, 0.0, 0.14], [659.25, 0.14, 0.14], [783.99, 0.28, 0.14], [1046.5, 0.42, 0.9], [783.99, 0.42, 0.9], [659.25, 0.42, 0.9]],
		1.4,
		0.22
	)

## Bright chime when a spell is cast or a scroll is read successfully.
static func make_spell() -> AudioStreamWAV:
	return _tone_stream(
		[[783.99, 0.0, 0.08], [987.77, 0.06, 0.1], [1174.66, 0.14, 0.12], [1567.98, 0.22, 0.28], [1174.66, 0.22, 0.28]],
		0.55,
		0.2
	)

## Short low deny cue when an item or spell cannot be used (level, mana, target, reach).
static func make_warning() -> AudioStreamWAV:
	return _tone_stream(
		[[311.13, 0.0, 0.12], [233.08, 0.1, 0.18], [196.0, 0.1, 0.18]],
		0.32,
		0.28
	)

## Sharp crack when a tool, weapon, shield or armour piece wears out and is destroyed.
static func make_break() -> AudioStreamWAV:
	return _tone_stream(
		[[220.0, 0.0, 0.05], [140.0, 0.03, 0.12], [90.0, 0.08, 0.18], [60.0, 0.12, 0.2]],
		0.35,
		0.35
	)

## `notes` are [frequency_hz, start_s, duration_s]; gain scales every partial.
static func _tone_stream(notes: Array, seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for note: Array in notes:
		var start := int(note[1] * MIX_RATE)
		var length := int(note[2] * MIX_RATE)
		for i in length:
			if start + i >= count:
				break
			var t := float(i) / MIX_RATE
			var attack := minf(1.0, t / 0.01)
			var release := minf(1.0, float(length - i) / (MIX_RATE * 0.1))
			var tone := sin(TAU * note[0] * t) + 0.45 * sin(TAU * 2.0 * note[0] * t) + 0.2 * sin(TAU * 3.0 * note[0] * t)
			samples[start + i] += tone * attack * release * gain
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

func play(sound: String) -> void:
	if enabled and players.has(sound):
		players[sound].play()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for player in players.values():
			player.stop()

func _exit_tree() -> void:
	for player in players.values():
		player.stop()
