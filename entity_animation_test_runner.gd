extends SceneTree

var failures: int = 0
var checks: int = 0
var deaths: int = 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func run() -> void:
	var gm := root.get_node("GameManager")
	var session := root.get_node("Coop")
	gm.set_process(false)
	gm.start_night(4)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	for i in range(25): await physics_frame
	var entity = station.get_node("PassengerEntity")
	entity.set_physics_process(false)
	entity.set_process(false)
	var visual = entity.visual
	var skeleton: Skeleton3D = visual.skeleton
	var animator: AnimationPlayer = visual.animation_player
	check(skeleton.get_bone_count() == 19, "Imported creature has its 19 deform bones")
	check(visual._clips.size() == 5, "All five authored clips import")
	var meshes: Array = visual.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 3, "Visual consists only of cleaned body and two eyes")
	var cctv_excluded := true
	var skinned := true
	for mesh in meshes:
		cctv_excluded = cctv_excluded and mesh.layers == 2
		skinned = skinned and mesh.skin != null and not mesh.skeleton.is_empty()
	check(cctv_excluded, "Body and white eyes all stay off CCTV layer one")
	check(skinned, "Body and both eyes bind to the skeleton")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var unchanged_origin: Vector3 = entity.position
	for clip in ["Idle", "Walk", "Chase", "Attack", "Retreat"]:
		var name: StringName = visual._clips[clip]
		var animation: Animation = animator.get_animation(name)
		check(animation.length > 0.5, clip + " has a real timed animation")
		check(animation.loop_mode == (Animation.LOOP_NONE if clip == "Attack" else Animation.LOOP_LINEAR), clip + " has correct looping")
		animator.play(name, 0)
		animator.seek(0, true)
		animator.advance(0)
		var before: Array[Quaternion] = []
		for i in range(skeleton.get_bone_count()): before.append(skeleton.get_bone_pose_rotation(i))
		animator.seek(animation.length * 0.25, true)
		animator.advance(0)
		var changed: bool = false
		for i in range(skeleton.get_bone_count()):
			if before[i].angle_to(skeleton.get_bone_pose_rotation(i)) > 0.005: changed = true
		check(changed, clip + " actually changes imported bone poses")
	check(entity.position == unchanged_origin, "In-place animation never moves the gameplay body")
	gm.player_died.connect(func() -> void: deaths += 1)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	player.set_flashlight(false, false)
	player.position = Vector3(0, 0.35, 0.7)
	player.set_meta("hiding", false)
	entity.position = Vector3(0, 0.35, 0)
	entity.phase = "HUNT"
	entity.banished = false
	entity.visible = true
	entity._begin_attack(player)
	check(entity.phase == "ATTACK" and gm.state != gm.NightState.DEAD, "Contact starts a visible wind-up before damage")
	entity._advance_attack(0.3, player)
	check(gm.state != gm.NightState.DEAD, "Wind-up gives the player time to escape")
	player.position.z = 3
	entity._advance_attack(0.5, player)
	check(gm.state != gm.NightState.DEAD and entity.phase == "STALK", "Leaving range before impact cancels the hit")
	player.position.z = 0.7
	entity.phase = "HUNT"
	entity._begin_attack(player)
	player.set_meta("hiding", true)
	entity._advance_attack(1, player)
	check(gm.state != gm.NightState.DEAD, "Hiding before impact prevents damage")
	player.set_meta("hiding", false)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.1)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(0, 1.5, 0.35)
	station.add_child(wall)
	for i in range(2): await physics_frame
	entity.phase = "HUNT"
	entity._begin_attack(player)
	entity._advance_attack(1, player)
	check(gm.state != gm.NightState.DEAD, "Solid cover acquired during wind-up blocks the hit")
	wall.queue_free()
	for i in range(2): await physics_frame
	entity.phase = "HUNT"
	entity._begin_attack(player)
	var saved: Dictionary = entity.save_state()
	entity._cancel_attack()
	entity.load_state(saved)
	check(entity.phase == "ATTACK" and entity.attack_remaining > 0, "Checkpoint restores pending attack rather than instant damage")
	entity._advance_attack(1, player)
	check(gm.state == gm.NightState.DEAD and deaths == 1, "Host resolves a valid impact once after wind-up")
	entity._advance_attack(1, player)
	check(deaths == 1, "Completed attack cannot apply damage twice")
	paused = false
	station.get_node("ShiftReport").close_panel()
	for number in [1, 3]:
		gm.start_night(number)
		entity.set_physics_process(false)
		entity.phase = "HUNT"
		entity._begin_attack(player)
		check(entity.phase != "ATTACK", "Night %d cannot begin an attack" % number)
		entity.load_state(saved)
		check(entity.phase == "OBSERVE" and not entity.visible, "Night %d sanitizes saved hostile form" % number)
	gm.start_night(4)
	entity.set_physics_process(false)
	# Exercise client-only safeguards without a second world or a mocked RPC sender.
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", 1, 3)
	root.multiplayer.multiplayer_peer = client
	session.active = true
	var state := {"revision": 10, "p": entity.position, "y": 0.0, "phase": "ATTACK", "banished": false, "visible": true, "attack_remaining": 0.4, "attack_serial": 7}
	entity.apply_network_state(state)
	entity._process(0.05)
	check(entity.phase == "ATTACK" and visual.current_clip == "Attack", "Client selects attack clip from authoritative state")
	var previous: Dictionary = state.duplicate()
	previous.revision = 9
	previous.phase = "STALK"
	entity.apply_network_state(previous)
	check(entity.phase == "ATTACK" and entity.attack_serial == 7, "Out-of-order state cannot cancel or restart an attack")
	var remaining: float = entity.attack_remaining
	entity.apply_network_state(state)
	check(entity.attack_remaining == remaining, "Duplicate revision cannot rewind the wind-up")
	entity._advance_attack(10, player)
	check(gm.state != gm.NightState.DEAD, "Client never resolves lethal damage")
	session.leave()
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(8): await process_frame
	print("ENTITY ANIMATION CHECKS: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
