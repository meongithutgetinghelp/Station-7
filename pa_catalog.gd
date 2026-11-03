extends Resource
## Drop your recorded AudioStreams into these slots in pa_recordings.tres.
@export var approach: AudioStream
@export var boarding: AudioStream
@export var departure: AudioStream
@export var welcome: AudioStream
@export var false_call: AudioStream
@export_range(-30, 0) var volume_db: float = -12

func clip(id: String) -> AudioStream:
	return get(id) as AudioStream if id in ["approach", "boarding", "departure", "welcome", "false_call"] else null
