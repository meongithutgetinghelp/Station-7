extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.save_path = "user://station7-horror-pacing-test.json"
	gm.new_campaign()
	gm.start_night(3)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var pacing = station.get_node("HorrorPacing")
	pacing.set_process(false)
	var service = station.get_node("PassengerService")
	service.set_process(false)
	var entity = station.get_node("PassengerEntity")
	entity.set_physics_process(false)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	for i in range(20): await physics_frame
	check(pacing.is_in_group("save_participant"), "Pacing participates in ordinary checkpoints")
	pacing.sighting_chance = 1
	pacing.try_sighting()
	check(not pacing.opportunity_used and not pacing._figure.visible, "Anomaly cannot start before opening")
	check(pacing.remember("note/2"), "Discovering a letter before startup still records it")
	pacing.read_archive()
	check(pacing._reader.is_open, "Archive can be read by flashlight before the station opens")
	pacing._reader.close_panel()
	gm.turn_on_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	var objectives: Dictionary = gm.objectives.duplicate(true)
	var original_actor_count: int = get_nodes_in_group("passenger_actor").size()
	pacing.try_sighting()
	check(pacing.sighting == "AVAILABLE" and pacing._figure.visible, "Eligible sighting uses prepared visible figure")
	check(get_nodes_in_group("passenger_actor").size() == original_actor_count and pacing._figure.find_children("*", "CollisionShape3D").is_empty(), "Atmosphere creates no ticket actor, collision or passenger-count mutation")
	check(gm.objectives == objectives, "Optional sighting adds no required duty")
	check((player.camera.cull_mask & pacing.CAMERA_LAYER) == 0, "Main first-person camera excludes camera-only figure")
	for i in range(6):
		var mask: int = load("res://scripts/security_camera.gd").feed_mask(i)
		check(bool(mask & pacing.CAMERA_LAYER) == (i == 2), "Only CAM 03 includes the special render layer: %d" % i)
	for mesh in pacing._meshes:
		check(mesh.layers == pacing.CAMERA_LAYER and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Figure cannot leak ordinary world shadows or layers")
	var camera = station.get_node("StationJobs")._camera_screens[2].camera
	check(pacing.sees_figure(camera), "Default CAM 03 framing shows the figure without a special pan")
	camera.look_at(pacing.FIGURE_POINT + Vector3.UP)
	check(pacing.report_sighting(2, camera).contains("RECORDED") and pacing.report_sighting(2, camera).contains("ALREADY"), "Camera report records the optional figure once without a ticket verdict")
	check(pacing.report_sighting(1, camera).is_empty(), "Other feeds cannot report the camera-only phenomenon")
	check(pacing.sees_figure(camera), "CAM 03 has a physically unobstructed view of the figure")
	camera.look_at(camera.global_position + Vector3(0, 0.5, 1))
	check(not pacing.sees_figure(camera), "Panning away is not counted as observation")
	pacing.observe(1, true)
	pacing.observe(22, true)
	pacing.observe(1, false)
	pacing.advance(2)
	check(pacing.sighting == "SEEN", "One remaining viewer keeps the figure present for co-op callouts")
	pacing.observe(22, false)
	pacing.advance(1)
	check(pacing.sighting == "SEEN", "Looking away has a grace interval")
	pacing.advance(0.6)
	check(pacing.sighting == "RETIRED" and not pacing._figure.visible, "Figure vanishes after every viewer looks away")
	check(gm.campaign.get("mystery", []).has("camera") and gm.objectives == objectives, "Sighting records optional evidence without changing progression")
	pacing.try_sighting()
	check(pacing.sighting == "RETIRED", "Consumed opportunity never rerolls into another sighting")
	pacing._reset(3)
	pacing.sighting_chance = 0
	pacing.try_sighting()
	for i in range(10): pacing.try_sighting()
	check(pacing.opportunity_used and pacing.sighting == "RETIRED", "Random miss stays a miss instead of becoming guaranteed")
	pacing._reset(3)
	pacing.sighting_chance = 1
	pacing.try_sighting()
	pacing.advance(91)
	check(pacing.sighting == "RETIRED", "Unnoticed optional event expires without blocking the shift")
	pacing._reset(3)
	pacing.try_sighting()
	pacing.observe(1, true)
	pacing._viewers[1] = Time.get_ticks_msec() - 3000
	pacing.advance(2)
	check(pacing.sighting == "RETIRED", "Missing viewer heartbeat cannot hold atmosphere forever")
	check(root.get_node("Coop").local_interaction(pacing._archive.get_node("Interaction")), "Archive reading stays local to each crew member")
	player.position = Vector3(23,0.35,3.8)
	player.camera.look_at(pacing._archive.global_position)
	await physics_frame
	check(player._get_interaction_target() == pacing._archive.get_node("Interaction"), "Old ledger is reachable with the actual player ray")
	pacing.read_archive()
	check(pacing._reader.is_open and gm.campaign.mystery.has("archive"), "Physical archive reader records persistent evidence")
	pacing._reader.close_panel()
	check(not pacing.remember("archive") and not pacing.remember("made-up") and not pacing.remember("note/999") and not pacing.remember("note/garbage"), "Evidence entries are idempotent and allowlisted")
	var before_size: int = gm.campaign.mystery.size()
	pacing.remember("note/0")
	check(gm.campaign.mystery.size() == before_size + 1 and pacing.journal_entries().size() == gm.campaign.mystery.size(), "Found letters appear in the campaign evidence journal")
	check(gm.save_game(), "Checkpoint with optional discoveries writes")
	gm.campaign.erase("mystery")
	check(gm.load_game() and gm.campaign.mystery.has("archive"), "Checkpoint restores optional campaign discoveries")
	gm.start_night(4)
	gm.turn_on_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	check(pacing.holds_first_hunt() and not pacing._figure.visible, "Night 4 waits for turning point before its first automatic hunt")
	gm.time_minutes = 144
	entity.phase = "DORMANT"
	entity._physics_process(0.1)
	check(entity.phase == "DORMANT", "Actual entity wake respects Night 4 preparation interval")
	var train = station.get_node("TrainService")
	train.set_process(false)
	train.phase = "DEPARTING"
	pacing.advance(0.25)
	train.phase = "WAITING"
	pacing.advance(0.25)
	check(pacing.turn == "AFTERMATH" and pacing._figure.visible and pacing.turn_left > 19, "Actual departure transition starts a quiet non-attacking aftermath")
	check(gm.campaign.mystery.has("departure") and pacing._dispatch.visible, "Departure discrepancy has a lasting visible dispatch record")
	check(not player.in_booth_inspection and not get_tree_paused(), "Turning point leaves player control and simulation available")
	var pa = station.get_node("StationPA")
	check(pa._stage == "INTERRUPTED" and pa._timer.time_left <= 0.28, "Departure clips a quiet chime rather than adding a loud sting")
	pa._advance_announcement()
	check(pa._stage == "SILENCE" and pa._timer.time_left > 4.9, "Interrupted PA is followed by silence")
	var old_left: float = pacing.turn_left
	pacing.begin_turn()
	check(pacing.turn_left == old_left, "Duplicate departure cannot restart presentation")
	var malformed := {"version":1, "available":NAN, "turn":"AFTERMATH", "turn_left":{}, "rng":"not-a-number"}
	pacing.load_state(malformed)
	check(pacing.available_left == 0 and pacing.turn_left == 0, "Malformed optional timers cannot create an endless hunt hold")
	pacing.advance(0.1)
	check(pacing.turn == "COMPLETE", "Invalid presentation time recovers to a playable state")
	pacing.turn = "AFTERMATH"
	pacing.turn_left = old_left
	var state: Dictionary = pacing.save_state().duplicate(true)
	pa._stage = "TEST_RESTORE"
	pacing.load_state(state)
	check(pacing.turn == "AFTERMATH" and pacing.turn_left == old_left and pa._stage == "TEST_RESTORE", "Mid-event restore resumes state without replaying PA")
	gm.cause_power_failure()
	var dark_left: float = pacing.turn_left
	pacing.advance(60)
	check(not pacing._figure.visible and pacing.turn_left == dark_left, "Outage hides figure and defers aftermath without new light flashes")
	gm.restore_power()
	pacing.advance(21)
	check(pacing.turn == "COMPLETE" and not pacing.holds_first_hunt() and not pacing._figure.visible, "Aftermath completes and releases existing hostile behaviour")
	entity._physics_process(0.1)
	check(entity.phase != "DORMANT", "Existing entity can wake after the turning point")
	entity.set_physics_process(false)
	pacing._reset(4)
	gm.time_minutes = 156
	pacing.advance(0.25)
	check(pacing.turn == "AFTERMATH", "Older checkpoint or missed departure has a bounded recovery trigger")
	pacing.turn = "COMPLETE"
	# Simulate client presentation snapshots separately from host gameplay authority.
	pacing._network_initialized = false
	pa._stage = "NO_REPLAY"
	pacing.apply_network_state({"turn":"AFTERMATH", "turn_left":10})
	check(pa._stage == "NO_REPLAY", "Initial network snapshot never replays historical audio")
	pacing.apply_network_state({"turn":"WAITING"})
	pacing.apply_network_state({"turn":"AFTERMATH", "turn_left":20})
	check(pa._stage == "INTERRUPTED", "New live network transition presents its local audio")
	pa._stage = "DUPLICATE_GUARD"
	pacing.apply_network_state({"turn":"AFTERMATH", "turn_left":19})
	check(pa._stage == "DUPLICATE_GUARD", "Repeated network snapshots never restart the audio")
	gm.start_night(7)
	check(gm.campaign.mystery.has("archive") and not pacing.holds_first_hunt(), "Discoveries survive nights without delaying later threats")
	var ending: String = pacing.ending_text(true)
	check(ending.contains("A. Morrow") and ending.contains("I SAVED YOU A SEAT") and not ending.contains("02:17"), "Evidence-rich ending connects notes and ledger without a false departure time")
	gm.campaign.erase("mystery")
	check(pacing.ending_text(true).contains("unclaimed reservation") and not pacing.ending_text(true).contains("You remember"), "Main ending remains coherent without optional discoveries")
	check(not pacing.ending_text(false).contains("releases"), "Failed shift does not claim the mystery was resolved")
	gm.state = gm.NightState.DEAD
	pacing.sighting = "AVAILABLE"
	pacing.opportunity_used = false
	pacing.try_sighting()
	pacing.observe(1, true)
	check(not pacing.opportunity_used and pacing.sighting == "AVAILABLE" and not pacing.remember("archive"), "Terminal state rejects new sightings, observations and evidence")
	for suffix in ["", ".bak", ".tmp", ".auto", ".auto.bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path + suffix))
	station.queue_free()
	for i in range(4): await process_frame
	print("Horror pacing failures: ", failures)
	quit(1 if failures else 0)
func get_tree_paused() -> bool: return paused
