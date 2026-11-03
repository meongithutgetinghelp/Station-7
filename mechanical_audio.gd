extends RefCounted

## Quiet, deterministic mechanical transients. Signed 16-bit PCM avoids the
## offset and harsh quantization of the old unsigned-style 8-bit buffers.
const SAMPLE_RATE: int = 48000


static func flashlight_switch(enabled: bool) -> AudioStreamWAV:
	var pitch: float = 1.0 if enabled else 0.84
	return _render(0.085, [
		[0.0, 0.035, 620.0 * pitch, 0.18, 110.0],
		[0.012, 0.045, 340.0 * pitch, 0.12, 85.0],
	])


static func footstep() -> AudioStreamWAV:
	return _render(0.16, [[0.0, 0.13, 92.0, 0.22, 35.0], [0.012, 0.09, 185.0, 0.08, 48.0], [0.018, 0.05, 390.0, 0.035, 80.0]])


static func door_action(opening: bool, steel: bool) -> AudioStreamWAV:
	var body_frequency: float = 170.0 if steel else 115.0
	if opening:
		return _render(0.22, [
			[0.0, 0.055, 680.0, 0.12, 75.0],
			[0.018, 0.15, body_frequency, 0.22, 26.0],
			[0.025, 0.1, body_frequency * 2.1, 0.07, 40.0],
		])
	return _render(0.3, [
		[0.0, 0.23, body_frequency * 0.72, 0.3, 21.0],
		[0.008, 0.14, body_frequency * 1.7, 0.09, 32.0],
		[0.045, 0.06, 560.0, 0.1, 70.0],
	])


static func _render(duration: float, pulses: Array) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var mean: float = 0.0
	for i in range(count):
		var time: float = float(i) / SAMPLE_RATE
		var value: float = 0.0
		for pulse: Array in pulses:
			var age: float = time - float(pulse[0])
			var length: float = pulse[1]
			if age < 0.0 or age >= length:
				continue
			var attack: float = smoothstep(0.0, 0.003, age)
			var release: float = smoothstep(0.0, 0.015, length - age)
			value += sin(TAU * float(pulse[2]) * age) * float(pulse[3]) * exp(-age * float(pulse[4])) * attack * release
		samples[i] = value
		mean += value / count
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var time: float = float(i) / SAMPLE_RATE
		var fade: float = smoothstep(0.0, 0.003, time) * smoothstep(0.0, 0.015, float(count - 1 - i) / SAMPLE_RATE)
		var sample: float = clampf((samples[i] - mean) * fade, -0.9, 0.9)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav
