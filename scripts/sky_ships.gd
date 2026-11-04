extends Node3D
## The gods' sky ships (an Easter egg of the Gilgamesh disk): winged discs and fire-arrows that cross the sky between the
## cities about once an hour, high up and in silence (`GET /story/sky_flights`, a schedule the server derives from the
## clock), and one that crosses close in front of the player, in view and with its roar, when a character tells of them
## (a `sky_flyover` event). Scenery only: nothing here is sent back.
##
## Scene units are kilometres and the render origin moves, so every ship keeps its path in metres from the planet's
## centre and is placed with the environment's `render_position` each frame. The sound is a looping synthesised hum or
## roar on an AudioStreamPlayer3D (panning and distance); the Doppler shift is worked out here, in metres per second,
## because Godot's own would take the speed of sound in kilometres.

signal flight_started(ship_id: String, flyover: bool)

const SPEED_OF_SOUND_M_S := 343.0
const MEDIA_PREFIX := "/story/media/"
## A flight told by a character: the ship crosses the player's view from side to side, level, this far ahead of the
## character and this high above them (about 48 degrees up), so that houses in the street do not hide it and it is seen whole
## and seen to be huge.
const FLYOVER_AHEAD_M := 150.0
const FLYOVER_ALTITUDE_M := 170.0
const FLYOVER_SPEED_M_S := 180.0
const FLYOVER_HALF_LENGTH_M := 1800.0
const POLL_SECONDS := 600.0
const MAX_ACTIVE := 4
const MIX_RATE := 22050
const LOOP_SECONDS := 3.0

var _environment: Node
var _story: Node
var _ships: Dictionary = {}
var _scenes: Dictionary = {}
var _waiting: Dictionary = {}
var _active: Array = []
var _scheduled_seen: Dictionary = {}
var _streams: Dictionary = {}
var _poll := 0.0
var enabled := true
## False while the interface sounds are off: the ship is seen and not heard.
var sound_enabled := true

func setup(environment: Node, story: Node) -> void:
	_environment = environment
	_story = story
	story.sky_flights_ready.connect(_on_flights)
	story.media_ready.connect(media_ready)

## Asks the server for the schedule now and then again every ten minutes.
func refresh() -> void:
	_poll = POLL_SECONDS
	if is_instance_valid(_story):
		_story.fetch_sky_flights()

func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0 and is_instance_valid(_story):
		refresh()
	var now := Time.get_unix_time_from_system()
	for flight: Dictionary in _active.duplicate():
		_advance(flight, now, delta)

# --- data from the server -------------------------------------------------------------------------------------

func _on_flights(data: Dictionary) -> void:
	_ships.clear()
	for ship: Dictionary in data.ships:
		_ships[ship.id] = ship
	var waiting := _waiting.duplicate()
	_waiting.clear()
	for ship_id: String in waiting:
		flyover(ship_id, waiting[ship_id][0], waiting[ship_id][1])
	for flight: Dictionary in data.flights:
		if _scheduled_seen.has(flight.id) or not _ships.has(flight.ship):
			continue
		_scheduled_seen[flight.id] = true
		_launch({
			"ship": flight.ship,
			"mode": "arc",
			"from": flight.from,
			"to": flight.to,
			"altitude_m": float(flight.altitude_m),
			"start": float(flight.start_ms) / 1000.0,
			"duration": float(flight.duration_ms) / 1000.0,
		})

## A character told of the ship `ship_id`: it crosses close in front of the player at `player_metres`, where they look.
func flyover(ship_id: String, player_metres: Vector3, seed: int = 0) -> void:
	if not enabled or player_metres == Vector3.ZERO:
		return
	if not _ships.has(ship_id):
		# The schedule has not arrived yet; the flight starts when it has.
		_waiting[ship_id] = [player_metres, seed]
		refresh()
		return
	var looking: Array = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		# The scene's axes are the planet's, only moved, so the camera's direction is a direction in metres too.
		var forward := -camera.global_basis.z
		looking = [forward.x, forward.y, forward.z]
	var path := flyover_path([player_metres.x, player_metres.y, player_metres.z], looking, seed)
	_launch({
		"ship": ship_id,
		"mode": "line",
		"from": path.from,
		"to": path.to,
		"altitude_m": 0.0,
		"start": Time.get_unix_time_from_system(),
		"duration": 2.0 * FLYOVER_HALF_LENGTH_M / FLYOVER_SPEED_M_S,
		"flyover": true,
	})

func media_ready(url: String, resource: Resource) -> void:
	if not resource is PackedScene or not url.ends_with(".glb"):
		return
	# The story client names a medium by its whole path, `/story/media/<disk>/<file>`; the ships name theirs from the disk on.
	var model := url.trim_prefix(MEDIA_PREFIX)
	_scenes[model] = resource
	for flight: Dictionary in _active:
		if flight.node == null and str(_ships.get(flight.ship, {}).get("model")) == model:
			_attach(flight)

# --- flights --------------------------------------------------------------------------------------------------

func _launch(flight: Dictionary) -> void:
	if _active.size() >= MAX_ACTIVE or not _ships.has(flight.ship):
		return
	flight.node = null
	flight.player = null
	flight.done = false
	var now := Time.get_unix_time_from_system()
	if flight.start + flight.duration <= now:
		return
	_active.append(flight)
	var url := str(_ships[flight.ship].model)
	if _scenes.has(url):
		_attach(flight)
	elif is_instance_valid(_story):
		_story.fetch_media("/story/media/" + url)
	flight_started.emit(flight.ship, flight.get("flyover", false))

func _attach(flight: Dictionary) -> void:
	var ship: Dictionary = _ships[flight.ship]
	var model := (_scenes[str(ship.model)] as PackedScene).instantiate() as Node3D
	if model == null:
		_finish(flight)
		return
	var root := Node3D.new()
	root.top_level = true
	root.visible = false
	# The models are authored in metres, the scene is in kilometres.
	model.scale = Vector3.ONE * float(ship.scale) / 1000.0
	root.add_child(model)
	flight.player = null
	if not sound_enabled or not flight.get("flyover", false):
		# Only a ship that a character told of is heard; the ones of the schedule cross the high sky in silence.
		add_child(root)
		flight.node = root
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream_for(str(flight.ship))
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 0.25
	player.max_distance = 12.0
	player.max_db = 2.0
	player.volume_db = 4.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	root.add_child(player)
	add_child(root)
	flight.node = root
	flight.player = player

func _advance(flight: Dictionary, now: float, delta: float) -> void:
	var t := (now - float(flight.start)) / float(flight.duration)
	if t >= 1.0 or _environment == null:
		_finish(flight)
		return
	var node: Node3D = flight.node
	if node == null or t < 0.0:
		return
	var metres := position_at(flight, t)
	var velocity := velocity_of(flight)
	node.visible = true
	node.position = _environment.render_position(metres)
	var up := Vector3(metres[0], metres[1], metres[2]).normalized()
	if velocity.length() > 0.1 and absf(velocity.normalized().dot(up)) < 0.999:
		# The models' front is +Z, and Godot looks along -Z.
		node.basis = Basis.looking_at(-velocity.normalized(), up)
	var player: AudioStreamPlayer3D = flight.player
	if player == null:
		return
	if not player.playing:
		player.play()
	var listener := get_viewport().get_camera_3d()
	if listener != null:
		var to_listener := (listener.global_position - node.global_position) * 1000.0
		if to_listener.length() > 1.0:
			# Closing speed: how fast the distance to the listener shrinks. The pitch follows it a little
			# slowly, so that the drop as the ship passes overhead is a swoop and not a click.
			var target := doppler_pitch(velocity.dot(to_listener.normalized()))
			player.pitch_scale = lerpf(player.pitch_scale, target, minf(1.0, delta * 8.0))

func _finish(flight: Dictionary) -> void:
	_active.erase(flight)
	if flight.node != null:
		flight.node.queue_free()
		flight.node = null

## The position of a flight (metres from the planet's centre) at `t` of its way, 0 to 1.
static func position_at(flight: Dictionary, t: float) -> Array:
	# Scalars, not Vector3: a Vector3 is single precision and would round a point 6000 km from the centre to half a metre.
	var from: Array = flight.from
	var to: Array = flight.to
	var point := [0.0, 0.0, 0.0]
	for axis in 3:
		point[axis] = lerpf(float(from[axis]), float(to[axis]), t)
	if flight.mode == "arc":
		# Over the planet's curve: on the great circle between the cities, lifted to the flight's altitude.
		var radius := (_length(from) + _length(to)) * 0.5 + float(flight.altitude_m)
		var scale := radius / _length(point)
		for axis in 3:
			point[axis] *= scale
	return point

static func _length(point: Array) -> float:
	return sqrt(float(point[0]) * float(point[0]) + float(point[1]) * float(point[1]) + float(point[2]) * float(point[2]))

## How fast a flight goes, metres per second: constant along its path.
static func velocity_of(flight: Dictionary) -> Vector3:
	var from: Array = flight.from
	var to: Array = flight.to
	return (Vector3(to[0], to[1], to[2]) - Vector3(from[0], from[1], from[2])) / float(flight.duration)

## The straight path of a flight in front of a character at `player` (metres from the planet's centre) who looks along
## `looking` (a direction; empty when unknown): level, FLYOVER_ALTITUDE_M above them, across their view at
## FLYOVER_AHEAD_M, from the left or the right as `seed` chooses. With no known view the ship crosses in a direction
## that `seed` chooses.
static func flyover_path(player: Array, looking: Array, seed: int) -> Dictionary:
	var up := Vector3(player[0], player[1], player[2]).normalized()
	var reference := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var east := up.cross(reference).normalized()
	var north := east.cross(up).normalized()
	var ahead := east * cos(float(absi(seed) % 360) * PI / 180.0) + north * sin(float(absi(seed) % 360) * PI / 180.0)
	if looking.size() == 3:
		var view := Vector3(looking[0], looking[1], looking[2])
		var level := view - up * view.dot(up)
		# Looking straight up or down shows no side to cross: keep the seeded direction.
		if level.length() > 0.2:
			ahead = level.normalized()
	var heading := ahead.cross(up).normalized()
	if absi(seed) % 2 == 1:
		heading = -heading
	var centre := Vector3(player[0], player[1], player[2]) + up * FLYOVER_ALTITUDE_M + ahead * FLYOVER_AHEAD_M
	var start := centre - heading * FLYOVER_HALF_LENGTH_M
	var end := centre + heading * FLYOVER_HALF_LENGTH_M
	return {"from": [start.x, start.y, start.z], "to": [end.x, end.y, end.z]}

## The pitch of a sound whose source closes on the listener at `closing_m_s` (negative while it recedes). The speed is held
## below that of sound: a ship that outruns it is heard as the loudest, highest note and then as the lowest.
static func doppler_pitch(closing_m_s: float) -> float:
	var speed := clampf(closing_m_s, -0.9 * SPEED_OF_SOUND_M_S, 0.9 * SPEED_OF_SOUND_M_S)
	return SPEED_OF_SOUND_M_S / (SPEED_OF_SOUND_M_S - speed)

# --- sound ----------------------------------------------------------------------------------------------------

func stream_for(ship_id: String) -> AudioStreamWAV:
	if not _streams.has(ship_id):
		_streams[ship_id] = make_roar() if ship_id == "gir" else make_hum()
	return _streams[ship_id]

## The winged disc: a low double tone that beats once a second, a thin high shimmer and a breath of wind. Every
## frequency makes whole cycles in the loop, so that it repeats without a click.
static func make_hum() -> AudioStreamWAV:
	var count := int(MIX_RATE * LOOP_SECONDS)
	var wind := _noise(count, 11, 0.03)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index in count:
		var t := float(index) / MIX_RATE
		var tone := 0.32 * sin(TAU * 120.0 * t) + 0.32 * sin(TAU * 121.0 * t) + 0.14 * sin(TAU * 240.0 * t)
		var shimmer := 0.07 * sin(TAU * 880.0 * t) * (0.6 + 0.4 * sin(TAU * 6.0 * t))
		samples[index] = tone + shimmer + 0.5 * wind[index]
	return _wav(samples)

## The fire-arrow: a deep rumble of filtered noise over a low tone with its harmonics and a crackle.
static func make_roar() -> AudioStreamWAV:
	var count := int(MIX_RATE * LOOP_SECONDS)
	var rumble := _noise(count, 23, 0.02)
	var hiss := _noise(count, 37, 0.25)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index in count:
		var t := float(index) / MIX_RATE
		var tone := 0.22 * sin(TAU * 55.0 * t) + 0.12 * sin(TAU * 110.0 * t) + 0.08 * sin(TAU * 165.0 * t) + 0.06 * sin(TAU * 220.0 * t)
		samples[index] = tone + 1.4 * rumble[index] + 0.25 * hiss[index] * (0.5 + 0.5 * sin(TAU * 4.0 * t))
	return _wav(samples)

## Low-passed noise (`alpha` the share of each new sample), cross-faded at the loop's seam.
static func _noise(count: int, seed: int, alpha: float) -> PackedFloat32Array:
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var fade := int(MIX_RATE * 0.25)
	var raw := PackedFloat32Array()
	raw.resize(count + fade)
	var level := 0.0
	for index in count + fade:
		level += alpha * (random.randf_range(-1.0, 1.0) - level)
		raw[index] = level
	var peak := 0.0001
	for value in raw:
		peak = maxf(peak, absf(value))
	var out := PackedFloat32Array()
	out.resize(count)
	for index in count:
		var value := raw[index]
		if index < fade:
			var mix := float(index) / fade
			value = value * mix + raw[count + index] * (1.0 - mix)
		out[index] = value / peak
	return out

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for value in samples:
		peak = maxf(peak, absf(value))
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		bytes.encode_s16(index * 2, int(clampf(samples[index] / peak * 0.8, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	return stream
