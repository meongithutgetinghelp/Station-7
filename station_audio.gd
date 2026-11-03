extends Node
## Local environmental sound; no gameplay or shared-state effects.
var _powered_loops: Array[AudioStreamPlayer3D] = []
var _event: AudioStreamPlayer3D
var _wait := 105.0
var _rng := RandomNumberGenerator.new()
var _power_gain := -60.0

# Retained for procedural audio callers.
static func hum(duration: float, frequency: float) -> AudioStreamWAV:
	var count: int = int(duration * 48000)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / 48000.0
		data.encode_s16(i * 2, int((sin(TAU * frequency * t) * 0.15 + sin(TAU * frequency * 2 * t) * 0.025) * 32767))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 48000
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = count
	sound.data = data
	return sound

func _source(n: String, file: String, point: Vector3, gain: float, reach: float, looping: bool) -> AudioStreamPlayer3D:
	var source := AudioStreamPlayer3D.new()
	source.name = n
	source.bus = "Ambience"
	var sound: AudioStreamWAV = load("res://audio/ambience/" + file + ".wav").duplicate()
	if looping:
		sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound.loop_begin = 0
		sound.loop_end = sound.data.size() / 2
	source.stream = sound
	source.position = point
	source.volume_db = gain
	source.unit_size = 3
	source.max_distance = reach
	add_child(source)
	if looping: source.play()
	return source

func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(90, 150)
	_source("TunnelAir", "tunnel-air", Vector3(0, 1.5, 21), -14, 42, true)
	for point in [Vector3(0, 4.5, -8), Vector3(20, 3, 7), Vector3(0, 4.5, 14)]:
		_powered_loops.append(_source("FluorescentHum", "fluorescent", point, -60, 14, true))
	_event = _source("DistantStationSound", "distant-rail", Vector3.ZERO, -14, 45, false)
	_power_gain = -17 if GameManager.powered else -60

func _process(delta: float) -> void:
	_power_gain = move_toward(_power_gain, -17.0 if GameManager.powered else -60.0, delta * 22)
	for source in _powered_loops: source.volume_db = _power_gain
	# No tension events during setup, menus, failure or the end-of-shift report.
	if not GameManager.signed_in or GameManager.state != GameManager.NightState.WORKING: return
	_wait -= delta
	if _wait <= 0:
		play_distant_event()
		_wait = _rng.randf_range(100, 190)

func play_distant_event() -> void:
	if _event.playing: return
	var rail := _rng.randf() < 0.55
	_event.stream = load("res://audio/ambience/" + ("distant-rail.wav" if rail else "pipe-settle.wav"))
	_event.position = Vector3(_rng.randf_range(-18, 18), 1.5, 22) if rail else Vector3(23, 3, _rng.randf_range(-12, 8))
	_event.pitch_scale = _rng.randf_range(0.92, 1.06)
	_event.volume_db = -13 if rail else -17
	_event.play()

func _exit_tree() -> void:
	for source in get_children():
		if source is AudioStreamPlayer3D:
			source.stop()
			source.stream = null
