extends Node

const SOUNDS := {
	"click": preload("res://assets/kenney/interface-sounds/Audio/click_001.ogg"),
	"confirmation": preload("res://assets/kenney/interface-sounds/Audio/confirmation_001.ogg"),
	"error": preload("res://assets/kenney/interface-sounds/Audio/error_001.ogg"),
	"back": preload("res://assets/kenney/interface-sounds/Audio/back_001.ogg"),
}

## Sounds of the world: several recordings per kind, one is picked at random so that steps do not repeat.
const WORLD_SOUNDS := {
	"step": [
		preload("res://assets/kenney/impact-sounds/Audio/footstep_grass_000.ogg"),
		preload("res://assets/kenney/impact-sounds/Audio/footstep_grass_001.ogg"),
		preload("res://assets/kenney/impact-sounds/Audio/footstep_grass_002.ogg"),
		preload("res://assets/kenney/impact-sounds/Audio/footstep_grass_003.ogg"),
		preload("res://assets/kenney/impact-sounds/Audio/footstep_grass_004.ogg"),
	],
	"mine": [
		preload("res://assets/kenney/impact-sounds/Audio/impactMining_000.ogg"),
		preload("res://assets/kenney/impact-sounds/Audio/impactMining_001.ogg"),
		preload("res://assets/kenney/impact-sounds/Audio/impactMining_002.ogg"),
	],
	"chop": [preload("res://assets/kenney/rpg-audio/Audio/chop.ogg")],
	"splash": [
		preload("res://assets/cc0-sounds/splash_01.ogg"),
		preload("res://assets/cc0-sounds/splash_02.ogg"),
		preload("res://assets/cc0-sounds/splash_03.ogg"),
	],
	"coins": [preload("res://assets/kenney/rpg-audio/Audio/handleCoins.ogg")],
}
const WORLD_VOLUME_DB := {"step": -17.0, "mine": -9.0, "chop": -8.0, "coins": -10.0, "splash": -8.0}

const SWIM_LOOP := preload("res://assets/cc0-sounds/loop_water_02.ogg")

const WIND_STEADY := preload("res://assets/cc0-sounds/wind_steady.ogg")
const WIND_GUSTS := preload("res://assets/cc0-sounds/wind_gusts.ogg")
const WIND_STEADY_DB := -24.0
const WIND_GUST_DB := -22.0

const WATER_FLOW := preload("res://assets/cc0-sounds/water_flowing.ogg")
const WATER_FLOW_DB := -12.0

const MIX_RATE := 22050
var _flow_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _gust_player: AudioStreamPlayer
var _wind_clock := 0.0
var _gust_wait := 20.0
var _swim_player: AudioStreamPlayer

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
	for kind in WORLD_SOUNDS:
		var world_player := AudioStreamPlayer.new()
		world_player.volume_db = WORLD_VOLUME_DB[kind]
		world_player.max_polyphony = 2
		add_child(world_player)
		players[kind] = world_player
	_wind_player = AudioStreamPlayer.new()
	var steady: AudioStreamOggVorbis = WIND_STEADY.duplicate()
	steady.loop = true
	_wind_player.stream = steady
	_wind_player.volume_db = -80.0
	add_child(_wind_player)
	_gust_player = AudioStreamPlayer.new()
	_gust_player.stream = WIND_GUSTS
	_gust_player.volume_db = WIND_GUST_DB
	add_child(_gust_player)
	_flow_player = AudioStreamPlayer.new()
	var flow: AudioStreamOggVorbis = WATER_FLOW.duplicate()
	flow.loop = true
	_flow_player.stream = flow
	_flow_player.volume_db = -80.0
	add_child(_flow_player)
	_swim_player = AudioStreamPlayer.new()
	var loop: AudioStreamOggVorbis = SWIM_LOOP.duplicate()
	loop.loop = true
	_swim_player.stream = loop
	_swim_player.volume_db = -16.0
	add_child(_swim_player)
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
		if WORLD_SOUNDS.has(sound):
			var choices: Array = WORLD_SOUNDS[sound]
			players[sound].stream = choices[randi() % choices.size()]
			players[sound].pitch_scale = randf_range(0.92, 1.08)
		players[sound].play()

## Outdoor wind on the surface: a steady breath whose strength drifts slowly, and a stronger gust every half minute or so.
## Called every frame; `outdoors` is true while the player stands on the surface. Silent when interface sounds are off.
func update_wind(delta: float, outdoors: bool) -> void:
	if not (enabled and outdoors):
		if _wind_player.playing:
			_wind_player.stop()
		return
	if not _wind_player.playing:
		_wind_player.play()
	_wind_clock += delta
	_wind_player.volume_db = WIND_STEADY_DB + 4.0 * sin(_wind_clock * 0.11) + 2.0 * sin(_wind_clock * 0.37)
	_gust_wait -= delta
	if _gust_wait <= 0.0 and not _gust_player.playing:
		_gust_player.play()
		_gust_wait = randf_range(25.0, 70.0)

## Running water near the player: `nearness` is 1.0 at the water's edge and 0.0 when none is close.
## The loop fades with it and stops at 0; interface sounds off silence it.
func set_water_nearness(nearness: float) -> void:
	if not enabled or nearness <= 0.01:
		if _flow_player.playing:
			_flow_player.stop()
		return
	if not _flow_player.playing:
		_flow_player.play()
	_flow_player.volume_db = lerpf(-45.0, WATER_FLOW_DB, clampf(nearness, 0.0, 1.0))

## The water bed while a character swims (deep water); it stops with the swim and with the sound switch.
func set_swimming(swimming: bool) -> void:
	if swimming and enabled:
		_swim_player.play()
	else:
		_swim_player.stop()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_swim_player.stop()
		_wind_player.stop()
		_gust_player.stop()
		_flow_player.stop()
		for player in players.values():
			player.stop()

func _exit_tree() -> void:
	for player in players.values():
		player.stop()
