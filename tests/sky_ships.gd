extends SceneTree
## The gods' sky ships: the Doppler shift, the path of a flight over the player, what the client accepts from
## the server and the synthesised sounds. Headless: `make test-sky-ships`.

const SKY := preload("res://scripts/sky_ships.gd")
const STORY := preload("res://scripts/story_client.gd")
const SOCIAL := preload("res://scripts/social.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	# Doppler: higher while the ship closes, lower while it recedes, the pitch of the source when it is level.
	_check(is_equal_approx(SKY.doppler_pitch(0.0), 1.0), "no shift without relative speed")
	_check(SKY.doppler_pitch(220.0) > 2.5 and SKY.doppler_pitch(220.0) < 3.0, "closing at 220 m/s is about 2.8x: %f" % SKY.doppler_pitch(220.0))
	_check(SKY.doppler_pitch(-220.0) > 0.55 and SKY.doppler_pitch(-220.0) < 0.65, "receding at 220 m/s is about 0.61x")
	_check(is_finite(SKY.doppler_pitch(5000.0)) and SKY.doppler_pitch(5000.0) <= 10.0 and SKY.doppler_pitch(-5000.0) > 0.5, "a supersonic ship stays inside a sane range")

	# A flight told by a character: across the player's view, FLYOVER_AHEAD_M in front and FLYOVER_ALTITUDE_M above,
	# level, and it passes in front of the player (in view) at its middle whichever way they look.
	var player := [4000000.0, 4900000.0, 100000.0]
	var ground := Vector3(player[0], player[1], player[2])
	var up := ground.normalized()
	var looking := (Vector3(0.3, -0.2, 1.0) - up * Vector3(0.3, -0.2, 1.0).dot(up)).normalized()
	for seed in [123, 124]:
		var path: Dictionary = SKY.flyover_path(player, [looking.x, looking.y, looking.z], seed)
		var flight := {"mode": "line", "from": path.from, "to": path.to, "altitude_m": 0.0, "duration": 2.0 * SKY.FLYOVER_HALF_LENGTH_M / SKY.FLYOVER_SPEED_M_S}
		var at_middle: Array = SKY.position_at(flight, 0.5)
		var offset := Vector3(at_middle[0] - player[0], at_middle[1] - player[1], at_middle[2] - player[2])
		_check(absf(offset.dot(up) - SKY.FLYOVER_ALTITUDE_M) < 1.0, "%f m above the player" % offset.dot(up))
		var level := offset - up * offset.dot(up)
		_check(absf(level.length() - SKY.FLYOVER_AHEAD_M) < 1.0, "%f m ahead" % level.length())
		_check(level.normalized().dot(looking) > 0.999, "in the direction they look")
		var velocity: Vector3 = SKY.velocity_of(flight)
		_check(absf(velocity.length() - SKY.FLYOVER_SPEED_M_S) < 0.5, "at the speed of a flyover")
		_check(absf(velocity.normalized().dot(up)) < 0.01, "level with the ground")
		_check(absf(velocity.normalized().dot(looking)) < 0.01, "across their view, not toward them")
	var left: Dictionary = SKY.flyover_path(player, [looking.x, looking.y, looking.z], 2)
	var right: Dictionary = SKY.flyover_path(player, [looking.x, looking.y, looking.z], 3)
	_check(left.from != right.from, "it comes from the left or from the right")
	# Looking straight up shows no side: the seeded direction is kept and the path is still level and near.
	var skyward: Dictionary = SKY.flyover_path(player, [up.x, up.y, up.z], 5)
	_check(skyward.from.size() == 3 and skyward.from != skyward.to, "looking up still gives a path")
	var unknown: Dictionary = SKY.flyover_path(player, [], 5)
	_check(unknown.from == skyward.from, "no view is the seeded direction as well")

	# A flight between cities follows the planet's curve at its altitude.
	var arc := {"mode": "arc", "from": [6371000.0, 0.0, 0.0], "to": [0.0, 6371000.0, 0.0], "altitude_m": 2500.0, "duration": 90.0}
	var half: Array = SKY.position_at(arc, 0.5)
	var radius := sqrt(half[0] * half[0] + half[1] * half[1] + half[2] * half[2])
	_check(absf(radius - 6373500.0) < 0.01, "the arc holds its altitude: %f" % radius)

	# Sound: the ships of the schedule cross the high sky in silence, only a ship told of by a character roars.
	var packed := PackedScene.new()
	var template := Node3D.new()
	packed.pack(template)
	template.free()
	var sky: Node3D = SKY.new()
	sky._ships = {"disc": {"id": "disc", "model": "d/media/models/sky_disc.glb", "scale": 4.0}}
	sky._scenes = {"d/media/models/sky_disc.glb": packed}
	var now := Time.get_unix_time_from_system()
	var scheduled := {"ship": "disc", "mode": "arc", "from": [6371000.0, 0.0, 0.0], "to": [0.0, 6371000.0, 0.0], "altitude_m": 8000.0, "start": now, "duration": 90.0}
	var told := {"ship": "disc", "mode": "line", "from": [6371000.0, 0.0, 0.0], "to": [6371000.0, 100.0, 0.0], "altitude_m": 0.0, "start": now, "duration": 20.0, "flyover": true}
	sky._launch(scheduled)
	sky._launch(told)
	_check(scheduled.node != null and told.node != null, "both ships are drawn")
	_check(scheduled.player == null and scheduled.node.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "a scheduled ship is silent")
	_check(told.player != null and told.player.stream != null, "a ship told of is heard")
	sky.sound_enabled = false
	var muted := {"ship": "disc", "mode": "line", "from": [6371000.0, 0.0, 0.0], "to": [6371000.0, 100.0, 0.0], "altitude_m": 0.0, "start": now, "duration": 20.0, "flyover": true}
	sky._launch(muted)
	_check(muted.node != null and muted.player == null, "with the interface sounds off it is seen and not heard")
	sky.free()

	# What the client accepts from the server.
	var good := {
		"ships": [{"id": "disc", "model": "gilgamesh/media/models/sky_disc.glb", "scale": 4.0}],
		"flights": [{"id": "5", "ship": "disc", "model": "gilgamesh/media/models/sky_disc.glb", "scale": 4.0, "start_ms": 1.7e12, "duration_ms": 90000, "from": [1.0, 2.0, 3.0], "to": [4.0, 5.0, 6.0], "altitude_m": 2500.0}],
	}
	_check(STORY.valid_sky(good), "a well-formed schedule")
	_check(STORY.valid_sky({"ships": [], "flights": []}), "an empty schedule (a world without sky ships)")
	var bad: Dictionary = good.duplicate(true)
	bad.flights[0].ship = "zeppelin"
	_check(not STORY.valid_sky(bad), "a flight of an unknown ship")
	bad = good.duplicate(true)
	bad.ships[0].model = "gilgamesh/../etc/passwd.glb"
	_check(not STORY.valid_sky(bad), "a model outside the media")
	bad = good.duplicate(true)
	bad.flights[0].from = [1.0, 2.0]
	_check(not STORY.valid_sky(bad), "a point with two coordinates")
	_check(SOCIAL.valid_event({"id": 9, "kind": "sky_flyover", "subject": "disc"}), "the flyover event")
	_check(not SOCIAL.valid_event({"id": 9, "kind": "sky_flyover", "subject": "Disc One"}), "a flyover event naming no ship id")

	# The sounds: whole loops, audible, different for the two ships, and the seam does not click.
	for stream: AudioStreamWAV in [SKY.make_hum(), SKY.make_roar()]:
		_check(stream.data.size() == int(SKY.MIX_RATE * SKY.LOOP_SECONDS) * 2, "one loop of 16-bit samples")
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "it loops")
		var first := stream.data.decode_s16(0)
		var last := stream.data.decode_s16(stream.data.size() - 2)
		_check(absf(float(first - last)) < 12000.0, "the seam is soft: %d to %d" % [last, first])
		var peak := 0
		for index in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(index)))
		_check(peak > 15000 and peak < 30000, "audible and not clipping: %d" % peak)
	_check(SKY.make_hum().data != SKY.make_roar().data, "two different sounds")

	print("sky ships: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
