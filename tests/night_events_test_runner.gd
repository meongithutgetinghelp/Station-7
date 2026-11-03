extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error(message)
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.save_path = "user://night-events-test.json"
	gm.new_campaign()
	for number in range(1,8):
		gm.start_night(number)
		var station = load("res://scenes/station_builder.tscn").instantiate()
		root.add_child(station)
		current_scene = station
		var events = station.get_node("NightEvents")
		events.set_process(false)
		var service = station.get_node("PassengerService")
		service.set_process(false)
		var entity = station.get_node("PassengerEntity")
		entity.set_physics_process(false)
		var player = station.get_node("Player")
		player.set_physics_process(false)
		for i in range(20): await physics_frame
		if number == 1:
			var approaches := {"ExitSeal":Vector3(-1.95,0.36,-14.3), "CameraJunction":Vector3(23.2,0.36,4.7), "RollCall":Vector3(-11.6,0.36,4.9), "ClearanceBooth":Vector3(-14.1,0.36,4.9), "ClearanceSecurity":Vector3(23.2,0.36,0.3)}
			for target in approaches:
				player.position = approaches[target]
				player.camera.look_at(events.get_node(target).global_position)
				await physics_frame
				check(player._get_interaction_target() == events.get_node(target+"/Interaction"), "%s can be reached with the real player interaction ray" % target)
		for target in ["KeepService", "CancelService", "ClearancePlatform"]:
			var control = events.get_node(target)
			var relevant: bool = number == (7 if target == "ClearancePlatform" else 3)
			check(control.visible == relevant and control.collision_layer == (8 if relevant else 0), "Night %d only exposes its relevant dispatch controls: %s" % [number, target])
		check(events.get_node("ServiceBoard").position == Vector3(-9.0, 1.9, 7.20), "Dispatch is mounted outside the ticket booth, clear of passenger seating")
		check(station.get_node("StationNavigation").ready_for_paths, "Night %d station navigation remains connected" % number)
		events.advance(100)
		check(not events.started and service.actors.is_empty(), "Night %d incident waits for station opening" % number)
		gm.turn_on_power()
		gm.sign_in()
		for actor in service.actors: actor.set_physics_process(false)
		service.reviewed = events.THRESHOLDS[number-1]-1
		events.advance(0.25)
		check(not events.started, "Night %d incident respects its inspection trigger" % number)
		service.reviewed += 1
		events.advance(0.25)
		check(events.started and not events.completed and not gm.objectives.night_incident.done, "Night %d starts a distinct required incident" % number)
		if number in [3, 7]:
			var targets: Array = ["KeepService", "CancelService"] if number == 3 else ["ClearancePlatform"]
			for target in targets:
				var control = events.get_node(target)
				player.position = Vector3(control.position.x, 0.36, 8.5)
				player.camera.look_at(control.global_position)
				await physics_frame
				check(player._get_interaction_target() == control.get_node("Interaction") and control.get_node("Interaction").enabled, "Relocated dispatch control is reachable and active: " + target)
			check(events._label.text.contains("SCHEDULED" if number == 3 else "passengers have boarded"), "Dispatch explains the current night's task")
		check(gm.shift_blockers().has(str(gm.objectives.night_incident.text)), "Night %d active incident appears in canonical completion checklist" % number)
		var state_before: Dictionary = events.save_state().duplicate(true)
		check(gm.save_game(), "Night %d incident checkpoint saves" % number)
		events.stage = "BROKEN_FIXTURE"
		check(gm.load_game() and events.save_state() == state_before, "Night %d reload restores incident stage without replay" % number)
		for actor in service.actors: actor.set_physics_process(false)
		match number:
			1:
				events.resolve("camera")
				check(not events.completed, "Safety check requires its own entrance seal")
				events.resolve("exit")
			2:
				var console = station.get_node("StationServices").cctv
				console.open_panel()
				console.select_feed(3)
				console._process(0.1)
				station.get_node("StationJobs")._update_camera_feeds(1)
				check(console._status.text.contains("SIGNAL LOST") and console._image.modulate == Color.BLACK, "Failed camera line is visibly offline")
				check(not station.get_node("StationJobs")._camera_screens[4].get("signal_lost",false), "Line fault preserves the other cameras")
				events.resolve("camera")
				console._process(0.1)
				check(console._status.text.contains("LIVE"), "Physical junction repair restores the feed")
				console.close_panel()
			3:
				events.resolve("cancel")
				check(not events.completed and gm.powered, "False PA choice offers correction without an unfair penalty")
				events.resolve("keep")
			4:
				check(gm.powered and events.warning_left > 15, "Overload gives preparation time before cutting power")
				events.advance(20)
				check(not gm.powered and gm.needs_power_repair(), "Warned overload enters the existing real repair flow")
				gm.restore_power()
				events.advance(0.25)
			5:
				var actor = load("res://scripts/passenger_actor.gd").new()
				actor.profile = load("res://scripts/passenger_cases.gd").for_night(5,0)[0].duplicate(true)
				actor.profile.uid = "roll-call-fixture"
				actor.profile.anomaly = false
				actor.position = Vector3(0,0.35,14)
				station.add_child(actor)
				actor.set_physics_process(false)
				actor.phase = "SEATED"
				actor._pre_ticket_seated = false
				actor._path_pending = false
				events.resolve("roster")
				check(actor.phase == "DANGER" and actor.danger_timer == 90 and events.target_uid == actor.profile.uid, "Roll call selects an admitted passenger and gives a fair rescue interval")
				actor._rescue()
				actor._points.clear()
				actor._path_pending = false
				actor.position = Vector3(20,0.35,2.5)
				actor._physics_process(0.016)
				events.advance(0.25)
				check(actor.phase == "SAFE", "Actual escort safety logic resolves the roll-call incident")
			6:
				station.get_node("StationJobs").repair_light()
				events.advance(0.25)
				check(events.stage == "GATE" and station.get_node("GateLane_1").jammed, "Lighting repair reveals the second reader fault")
				station.get_node("GateLane_1").scanner.interact()
				events.advance(0.25)
			7:
				var train = station.get_node("TrainService")
				train.phase = "BOARDING"
				train.elapsed = 36
				train._process(0.1)
				check(train.phase == "BOARDING" and events.holds_departure(), "Final train holds its doors for crew clearance")
				events.resolve("booth")
				events.resolve("security")
				events.resolve("platform")
				check(events.checkpoints.is_empty(), "Premature clearances fail until their real prerequisites are met")
				service.reviewed = service.total_cases()
				gm.entity_identified = true
				train.boarded_count = 1
				for point in ["booth","security","platform"]: events.resolve(point)
				train._process(0.1)
				check(train.phase == "CLOSING" and not events.holds_departure(), "All three clearances release the final train")
		check(events.completed and gm.objectives.night_incident.done, "Night %d incident can be completed" % number)
		var balance: int = gm.balance
		var completed_state: Dictionary = events.save_state().duplicate(true)
		check(gm.save_game() and gm.load_game() and events.save_state() == completed_state and gm.balance == balance, "Night %d completed checkpoint neither repeats the incident nor its reward" % number)
		events.resolve("exit")
		events.advance(100)
		check(gm.balance == balance and events.completed, "Night %d ignores duplicate resolutions" % number)
		# Deterministic successful campaign-state fixture; locomotion/tickets are covered by separate suites.
		service.reviewed = service.total_cases()
		service.correct = service.reviewed
		gm.inspect_platform()
		station.get_node("TrainService").boarded_count = 1
		station.get_node("StationJobs").cleanliness = 100
		entity.banished = true
		for key in ["fix_door","fix_gate","fix_light"]:
			if gm.objectives.has(key): gm.objectives[key].done = true
		check(gm.shift_blockers().is_empty(), "Night %d has a reachable successful campaign state after its incident" % number)
		if number == 1:
			var hud = station.get_node("NightHUD")
			hud._process(0.6)
			hud._process(11)
			check(hud._guide_card.visible and hud._tasks.text.contains("Night log"), "Tutorial guidance remains visible while the journal shortcut stays available")
			station.get_node("StationJobs").open_journal()
			hud._process(0.6)
			check(not hud._canvas.visible and station.get_node("StationJobs").journal.is_open, "Detailed journal replaces the HUD without overlapping it")
			station.get_node("StationJobs").journal.close_panel()
			hud._process(0.6)
			check(hud._canvas.visible, "Closing a work panel restores the compact HUD")
			var detail = station.get_node("StationDetail")
			check(detail.find_children("*", "PhysicsBody3D", true, false).is_empty() and detail.get_node("WallWear") is MultiMeshInstance3D, "Environmental wear is batched and adds no navigation obstacles")
		gm._process(6.1)
		check(gm.state == gm.NightState.SHIFT_OVER, "Night %d reaches its real end-of-shift transition" % number)
		gm.record_night()
		check(gm.campaign.nights_completed == number, "Campaign carries progress from night %d" % number)
		call_group("world_modal","close_panel")
		paused = false
		station.queue_free()
		for i in range(12): await physics_frame
		OS.delay_msec(70)
	DirAccess.remove_absolute(gm.save_path)
	print("NIGHT EVENTS CHECKS: ",failures," failures")
	quit(0 if failures == 0 else 1)
