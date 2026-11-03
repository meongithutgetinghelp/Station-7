extends Node3D

## Animation affects only the model. CharacterBody3D owns all gameplay movement.
const MODEL = preload("res://assets/entity/the_passenger_rigged.glb")
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var current_clip: String = ""
var _clips: Dictionary = {}


func _ready() -> void:
	var model := MODEL.instantiate()
	model.name = "RiggedModel"
	add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		node.layers = 2 # The entire creature, eyes included, stays absent from CCTV.
	for node in model.find_children("*", "Skeleton3D", true, false): skeleton = node
	for node in model.find_children("*", "AnimationPlayer", true, false): animation_player = node
	assert(animation_player != null and skeleton != null, "Entity requires its rig and clips")
	for name in animation_player.get_animation_list():
		for clip in ["Idle", "Walk", "Chase", "Attack", "Retreat"]:
			if str(name).get_file() == clip:
				_clips[clip] = name
				animation_player.get_animation(name).loop_mode = Animation.LOOP_NONE if clip == "Attack" else Animation.LOOP_LINEAR
	assert(_clips.size() == 5, "Entity must import all five animation clips")
	play_clip("Idle")


func play_clip(clip: String, speed: float = 1.0, elapsed: float = -1.0) -> void:
	if not animation_player or not _clips.has(clip): return
	animation_player.speed_scale = clampf(speed, 0.5, 1.5)
	if clip == current_clip: return
	current_clip = clip
	animation_player.play(_clips[clip], 0.12 if clip == "Attack" else 0.18)
	if elapsed >= 0: animation_player.seek(elapsed, true)


func reset_visual() -> void:
	current_clip = ""
	if animation_player: animation_player.stop()


func clip_length(clip: String) -> float:
	return animation_player.get_animation(_clips[clip]).length if animation_player and _clips.has(clip) else 0.0
