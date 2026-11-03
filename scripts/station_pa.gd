extends Node3D

@export var recordings: Resource = preload("res://scenes/pa_recordings.tres")
var _speakers: Array[AudioStreamPlayer3D] = []
var _queue: Array[String] = []
var _playing: bool = false
var _chime: AudioStreamWAV
var _timer: Timer
var _current_announcement: String = ""
var _stage: String = ""

func _ready() -> void:
	add_to_group("station_pa")
	_chime = _make_chime()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_advance_announcement)
	add_child(_timer)
	for point in [Vector3(0, 4, -8), Vector3(0, 4, 5), Vector3(-18, 4, 15), Vector3(18, 4, 15)]:
		var speaker := AudioStreamPlayer3D.new()
		speaker.bus = "SFX"
		speaker.position = point
		speaker.max_distance = 30
		speaker.unit_size = 8
		add_child(speaker)
		_speakers.append(speaker)
	GameManager.notice_posted.connect(_notice)

func _make_chime() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 48000
	var data := PackedByteArray()
	data.resize(48000 * 2)
	for i in range(48000):
		var t := float(i) / 48000
		var local := fmod(t, 0.5)
		var frequency := 660.0 if t < 0.5 else 880.0
		var envelope := minf(1, local / 0.015) * exp(-local * 6)
		data.encode_s16(i * 2, int(sin(TAU * frequency * t) * envelope * 6500))
	stream.data = data
	return stream

func _notice(text: String) -> void:
	if text.begins_with("UNSCHEDULED VOICE:"):
		announce("false_call")
		return
	if not text.begins_with("PA:"): return
	announce("approach" if "approaching" in text else ("boarding" if "boarding" in text else "departure"))

func announce(id: String) -> void:
	_queue.append(id)
	if not _playing: _play_next()

func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		return
	_playing = true
	_current_announcement = _queue.pop_front()
	_stage = "CHIME"
	for speaker in _speakers:
		speaker.stream = _chime
		speaker.volume_db = recordings.volume_db
		speaker.play()
	_timer.start(1.1)

func _advance_announcement() -> void:
	if _stage == "INTERRUPTED":
		for speaker in _speakers: speaker.stop()
		_stage = "SILENCE"
		_timer.start(5.0)
		return
	if _stage == "CHIME":
		var clip: AudioStream = recordings.clip(_current_announcement)
		if clip:
			_stage = "VOICE"
			for speaker in _speakers:
				speaker.stream = clip
				speaker.play()
			_timer.start(maxf(1, clip.get_length()) + 0.25)
			return
	_play_next()

func _exit_tree() -> void:
	if is_instance_valid(_timer): _timer.stop()
	for speaker in _speakers:
		if is_instance_valid(speaker):
			speaker.stop()
			speaker.stream = null


func interrupt_for_unlisted_departure() -> void:
	# One clipped chime, then silence. No flashing, sting or unbounded audio queue.
	_queue.clear()
	_timer.stop()
	for speaker in _speakers: speaker.stop()
	_playing = true
	_stage = "INTERRUPTED"
	_current_announcement = ""
	for speaker in _speakers:
		speaker.stream = _chime
		speaker.volume_db = recordings.volume_db - 6
		speaker.play()
	_timer.start(0.28)
