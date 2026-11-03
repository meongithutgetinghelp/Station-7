extends SceneTree
const Store = preload("res://scripts/checkpoint_store.gd")
const Guide = preload("res://scripts/shift_guidance.gd")
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func clean(path: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".auto", ".auto.bak", ".auto.tmp", ".auto.bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
func damage(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("unfinished checkpoint")
	file.close()
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	gm.save_path = "user://playability-checkpoints.json"
	clean(gm.save_path)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var service = station.get_node("PassengerService")
	var train = station.get_node("TrainService")
	var desk = station.get_node("BoothDesk")
	var player = station.get_node("Player")
	for path in ["PassengerService", "TrainService", "NightEvents", "PassengerDialogueEvents"]: station.get_node(path).set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	player.set_physics_process(false)
	for i in range(12): await physics_frame
	gm._tick_autosave(5)
	check(FileAccess.file_exists(gm.save_path + ".auto") and not FileAccess.file_exists(gm.save_path), "Beginning a playable night creates a separate automatic checkpoint")
	gm.time_minutes = 131
	check(gm.save_game(), "Manual save remains available beside autosave")
	var manual := FileAccess.get_file_as_string(gm.save_path)
	OS.delay_msec(3)
	gm.time_minutes = 132
	gm._tick_autosave(120)
	check(FileAccess.get_file_as_string(gm.save_path) == manual, "Autosaving never overwrites the manual save")
	check(gm.read_checkpoint().core.time == 132 and gm.read_checkpoint().get("automatic_checkpoint", false), "Continue selects the newest successful checkpoint")
	OS.delay_msec(3)
	gm.time_minutes = 133
	gm._tick_autosave(120)
	damage(gm.save_path + ".auto")
	check(gm.read_checkpoint().core.time == 132 and gm.read_checkpoint().get("recovered_backup", false), "Damaged autosave recovers its own previous checkpoint")
	OS.delay_msec(3)
	gm.time_minutes = 134
	gm.save_game()
	check(gm.read_checkpoint().core.time == 134 and not gm.read_checkpoint().get("automatic_checkpoint", false), "A newer manual save takes precedence over autosaves")
	gm._secured_time = 5.9
	gm._completion_elapsed = 0.2
	check(gm.load_game() and gm._secured_time == 0 and gm._completion_elapsed == 0, "Loading resets partial shift-completion timers")
	var automatic := FileAccess.get_file_as_string(gm.save_path + ".auto")
	desk.stamping = true
	gm._tick_autosave(120)
	check(FileAccess.get_file_as_string(gm.save_path + ".auto") == automatic, "Autosave waits for an unresolved stamp")
	desk.stamping = false
	desk.held = MeshInstance3D.new()
	desk.add_child(desk.held)
	gm._tick_autosave(1)
	check(FileAccess.get_file_as_string(gm.save_path + ".auto") == automatic, "Autosave waits while a paper is held")
	desk.held.free()
	desk.held = null
	gm._tick_autosave(1)
	check(not Store.read_valid(gm.save_path + ".auto").is_empty(), "Deferred autosave commits once the desk is safe")
	gm.restore_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	check(Guide.booth_lesson(self).contains("chair"), "First booth instruction names the chair and interaction key")
	player.position = Vector3(-9.3,0.35,3.2)
	service.open_desk()
	station.get_node("NightHUD")._process(0.6)
	check(service.ui.is_open and not service.ui.visible and station.get_node("NightHUD")._canvas.visible, "Physical booth mode keeps its teaching and status HUD visible")
	service.ui.close_desk()
	player.set_meta("seated_workstation", true)
	desk.computer_active = true
	check(Guide.booth_lesson(self).contains("Tab / Esc"), "Computer lesson explains returning to the physical desk")
	desk.computer_active = false
	player.set_meta("seated_workstation", false)
	var hud = station.get_node("NightHUD")
	hud._process(0.6)
	hud._process(12)
	check(hud._guide_card.visible, "Night 1 teaching remains visible after twelve seconds")
	service.reviewed = 8
	service.correct = 4
	check(gm.irreversible_shift_failure().is_empty(), "Incomplete tutorial continues despite mistakes")
	var recoverable := FileAccess.get_file_as_string(gm.save_path + ".auto")
	gm._tick_autosave(120)
	check(FileAccess.get_file_as_string(gm.save_path + ".auto") == recoverable, "Autosave preserves a recoverable checkpoint when remaining decisions cannot rescue accuracy")
	service.reviewed = 9
	service.correct = 5
	check(gm.irreversible_shift_failure().contains("too few"), "Finished checks explain mathematically unrecoverable accuracy")
	service.correct = 6
	check(gm.irreversible_shift_failure().is_empty(), "Exactly meeting the accuracy boundary is not an early failure")
	service.decisions.assign([{"approved":true,"anomaly":true}])
	check(gm.irreversible_shift_failure().contains("camera-invisible"), "An admitted early-night intruder gives an actionable retry reason")
	service.decisions.assign([{"approved":false,"anomaly":false}])
	check(gm.irreversible_shift_failure().contains("nobody can board"), "Denying everyone explains the otherwise endless boarding wait")
	service.correct = 5
	gm._process(0.3)
	check(gm.state == gm.NightState.SHIFT_OVER and station.get_node("ShiftReport").is_open and gm.time_minutes < gm.END_MINUTE, "Unwinnable completed checks offer retry without waiting until dawn")
	station.get_node("ShiftReport").close_panel()
	paused = false
	gm.state = gm.NightState.WORKING
	service.reviewed = 0
	service.decisions.clear()
	var actor = service.actors[0]
	actor.phase = "BOARD_TRAIN"
	actor._train = train
	actor._points.assign([Vector3(0,0.35,18.6)])
	actor.seat_anchor = service._seats[0]
	train.phase = "BOARDING"
	train.elapsed = 1
	train.queue_point(actor)
	train.phase = "DEPARTING"
	actor._physics_process(0.016)
	check(actor.phase == "TO_SEAT", "A missed train returns a walking passenger to their seat without waiting to reach the obsolete target")
	var queued := false
	for queue in train._queues.values(): queued = queued or actor in queue
	check(not queued, "Missed boarding releases the old doorway queue reservation")
	actor.phase = "BOARD_TRAIN"
	actor.seat_anchor = null
	actor.position = Vector3(-5, 0.35, 16)
	actor._physics_process(0.016)
	check(actor.phase == "PLATFORM_WAIT" and is_instance_valid(actor), "A legacy passenger without a seat waits visibly instead of crashing or disappearing")
	train.phase = "BOARDING"
	train.elapsed = 1
	train._process(0.016)
	check(actor.phase == "BOARD_TRAIN", "Waiting passengers can join the next train")
	actor.phase = "CROSS_GATE"
	actor._boarding_pending = true
	actor._train = null # A resumed gate crossing has not yet resolved its runtime reference.
	actor._arrived()
	check(actor.phase == "BOARD_TRAIN" and actor._train == train, "A resumed gate crossing resolves its train before beginning boarding")
	actor.phase = "CROSS_GATE"
	actor._path_pending = false
	actor.gate = station.get_node("GateLane_0")
	actor._points.assign([Vector3(actor.gate.global_position.x,0.35,11.8)])
	var legacy_crossing: Dictionary = service.save_state()
	legacy_crossing.movement_revision = 3
	service.load_state(legacy_crossing)
	actor = service.actors[0]
	actor.set_physics_process(false)
	check(actor.phase == "CROSS_GATE" and not actor._path_pending and actor._points.size() == 1, "Legacy gate crossings preserve their supported corridor instead of repathing backwards")
	actor.train_offset = train.interior.seats[0]
	actor.phase = "ENTER_TRAIN"
	check(train.board(actor), "Passenger can complete one boarding transaction")
	var count: int = train.boarded_count
	check(not train.board(actor) and train.boarded_count == count, "Repeated boarding cannot duplicate passenger counts")
	actor.position = Vector3(-5,0.35,16)
	actor._start_activity()
	check(actor._visit_kind == "platform" and actor._visit_target.z >= 10, "Cleared platform passengers do not wander back against incoming gate traffic")
	var blocked = load("res://scripts/passenger_actor.gd").new()
	blocked.profile = service.Cases.for_night(1,0,3)[0].duplicate(true)
	blocked.profile.uid = "blocked-detour-fixture"
	blocked.position = Vector3(-14.5,0.35,-3)
	station.add_child(blocked)
	var door = station.get_node("SmokingDoor_InteractiveDoor")
	door.set_open(false)
	door.locked = true
	var requested := {"queue":false}
	blocked.ready_to_queue.connect(func(_visitor: Node) -> void: requested.queue = true)
	blocked.pre_ticket_plan.assign(["smoking"])
	blocked._advance_visit()
	for i in range(2400):
		await physics_frame
		if requested.queue: break
	check(requested.queue and is_instance_valid(blocked) and blocked.visible and blocked.position.distance_to(Vector3(-14.5,0.35,-3)) < 3, "An actually blocked optional visit yields to ticket checking without teleporting or despawning the passenger")
	door.locked = false
	blocked.queue_free()
	actor.phase = "DANGER"
	actor.danger_timer = 0.01
	gm.state = gm.NightState.DEAD
	var loss: int = gm.lost_passengers
	var elapsed: float = train.elapsed
	actor._physics_process(1)
	train._process(1)
	gm.passenger_lost()
	check(gm.lost_passengers == loss and actor.danger_timer == 0.01 and train.elapsed == elapsed, "Death freezes passengers, loss counters and trains even when the co-op world is not paused")
	service.current_actor = actor
	service.counter_ready = true
	check(service.decide(true).is_empty(), "A delayed verdict cannot commit after death")
	gm.player_died.emit()
	var report = station.get_node("ShiftReport")
	check(report._actions.get_child_count() == 3 and report._actions.is_ancestor_of(root.gui_get_focus_owner()), "Death report exposes focused retry, checkpoint and menu controls outside the scrolling text")
	station.get_node("StationJobs").open_journal()
	check(report.is_open and not station.get_node("StationJobs").journal.is_open, "Journal shortcuts cannot replace terminal retry controls")
	station.get_node("PauseMenu").set_paused(true)
	station.get_node("PauseMenu").set_paused(false)
	check(paused and report.is_open, "Closing settings returns to the paused death report")
	paused = false
	clean(gm.save_path)
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(10): await process_frame
	OS.delay_msec(100)
	print("PLAYABILITY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
