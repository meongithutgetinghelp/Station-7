extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	root.get_node("GameManager").set_process(false)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var arrival = station.get_node("SpawnFade")
	check(arrival.layer > station.get_node("NightHUD").layer and arrival._shade.modulate.a == 1.0, "Spawn begins fully black above the game and HUD")
	check(arrival.process_mode == Node.PROCESS_MODE_ALWAYS and not paused, "Wake-up fade remains local and never pauses shared simulation")
	for frame in range(150): await physics_frame
	check(not station.has_node("SpawnFade"), "Spawn fade reveals the station and removes its full-screen layer")
	var settings = station.get_node("PauseMenu")
	var previous_motion: bool = settings._reduced_motion.button_pressed
	settings._reduced_motion.button_pressed = true
	var reduced_fade = load("res://spawn_fade.gd").new()
	station.add_child(reduced_fade)
	paused = true
	for frame in range(40): await process_frame
	paused = false
	check(not is_instance_valid(reduced_fade), "Reduced-motion spawn reveal finishes even while gameplay is paused")
	settings._reduced_motion.button_pressed = previous_motion
	for floor_name in ["Floor_Hall", "Floor_Platform", "Rooms/Security/Floor"]:
		check(station.get_node(floor_name).get_child(0).material_override is ShaderMaterial, floor_name + " uses the tiled textured floor finish")
	check(station.get_node("TactileEntrance_RaisedRibs").multimesh.instance_count > 100, "Entrance guidance uses visibly raised ribs")
	check(station.get_node("PlatformTactileWarning_RaisedStuds").multimesh.instance_count > 1000, "Platform edge uses batched raised warning studs")
	check(is_equal_approx(station.get_node("TactileGateRoute_Bed").position.x, -0.65), "Tactile route follows a gate opening rather than a turnstile pedestal")
	for step in range(24):
		check(station.has_node("StairRiser_" + str(step)) and station.has_node("StairEdge_" + str(step)), "Step %d has a visible riser and contrasting nosing" % step)
	var rails = station.find_children("StairHandrail_*", "MeshInstance3D", false, false)
	check(rails.size() == 2 and rails[0].position.x * rails[1].position.x < 0, "Entrance stairs have handrails on both sides")
	var door = station.get_node("SecurityDoor_InteractiveDoor")
	check(door.security_style and door._anim_body.has_node("SecurityWindow") and door._anim_body.has_node("SecuritySign_Back"), "CCTV door uses steel panels, reinforced glazing and security signage")
	door.interact()
	for frame in range(30): await physics_frame
	check(door.is_open and absf(door._anim_body.rotation.y) > 1, "Security door and its attached hardware still swing normally")
	var player = station.get_node("Player")
	player.position = Vector3(0, 0.37, -20.8)
	player.rotation.y = 0
	player.head.rotation.x = 0
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for frame in range(360): await physics_frame
	Input.action_release("move_forward")
	check(player.position.y > 4.5 and player.position.z < -29.5, "Player can walk up the detailed stairway onto the upper landing")
	player.rotation.y = PI
	Input.action_press("move_forward")
	for frame in range(360): await physics_frame
	Input.action_release("move_forward")
	check(player.position.y < 0.6 and player.position.z > -22, "Player can walk back down the stairway without catching on decorative nosings")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for frame in range(8): await physics_frame
	print("STATION FINISHES CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
