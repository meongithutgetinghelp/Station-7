# Station PA voice

The four assigned WAV clips use the American female neural voice af_heart (Voice A) from Kokoro-82M at 0.96 speed, with Misaki English pronunciation and clean full-band speech. The previous narrow speaker filter has been removed; only a low-frequency rumble filter, level normalization and short silence padding are applied. The game adds its existing chime and positional speaker playback.

Clean female WAV renders and the earlier Daniel/Emma recordings are retained under generated/ (excluded from Godot imports). tools/generate_pa_voice.py reproduces the clips with an isolated runtime and model cache under builds/voice-tools; the game only loads the four final WAVs. No neural model or extra runtime is needed during gameplay.

Model: https://huggingface.co/hexgrad/Kokoro-82M (Apache-2.0). Authoring runtime: https://github.com/thewh1teagle/kokoro-onnx (MIT).

- welcome.wav: Attention, staff. Station Seven is now open.
- approach.wav: Your attention, please. The next train is arriving at platform seven. Please stay behind the yellow line.
- boarding.wav: The train to North Terminal is now boarding at platform seven. Please mind the gap.
- departure.wav: Please stand clear of the doors. The train is now departing.

Welcome plays after power is on and all staff have signed the logbook. The other slots follow train approach, boarding and departure. Replace these recordings or drag another AudioStream into res://scenes/pa_recordings.tres to change the voice. Volume Db there controls PA level; the existing SFX slider also applies.

false_call.wav is the authored Night 3 unverified cancellation call. It plays once through the normal PA queue; the official platform indicator provides the correction.

## Project layout

| Folder | Contents |
| --- | --- |
| [scenes/](scenes/) and [rooms/](rooms/) | Main scenes, shared resources, and room layouts |
| [scripts/](scripts/) | Gameplay, networking, and station systems |
| [assets/](assets/), [audio/](audio/), and [ui/](ui/) | Models, sound, and interface assets |
| [tests/](tests/) and [tools/](tools/) | Automated checks and development tools |
| [docs/](docs/) | Co-op setup, campaign design, and playtest notes |
