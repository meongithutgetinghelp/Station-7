extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(3)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var events = station.get_node("PassengerDialogueEvents")
	events.set_process(false)
	station.get_node("NightEvents").set_process(false)
	station.get_node("TrainService").set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	var service = station.get_node("PassengerService")
	service.set_process(false)
	var player = station.get_node("Player")
	player.set_physics_process(false)
	gm.turn_on_power()
	gm.sign_in()
	var actor = load("res://scripts/passenger_actor.gd").new()
	actor.profile = load("res://scripts/passenger_cases.gd").for_night(3, 0)[0].duplicate(true)
	actor.profile.uid = "dialogue-fixture"
	actor.profile.anomaly = false
	station.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector3(2, 0.35, 14)
	player.position = Vector3(2, 0.35, 12)
	actor.phase = "SEATED"
	actor._pre_ticket_seated = true
	check(not events.begin_event(actor, "lost_property"), "Uninspected seated passengers cannot receive a conversation")
	actor._pre_ticket_seated = false
	actor.profile.anomaly = true
	check(not events.begin_event(actor, "lost_property"), "Impostors are excluded from friendly dialogue events")
	actor.profile.anomaly = false
	check(events.begin_event(actor, "lost_property"), "Lost property begins for an admitted passenger")
	check(not events.begin_event(actor, "needs_help"), "Only one optional event runs at once")
	check(root.get_node("Coop").local_interaction(actor.get_node("Interaction")), "Conversation opening stays local in co-op")
	actor.get_node("Interaction").interact()
	check(events.reader.is_open and player.in_booth_inspection, "Talk opens subtitle dialogue and locks local movement")
	check(events.reader.subtitle.get_parsed_text().contains(actor.profile.name + ": ") and events.reader.subtitle.get_parsed_text().contains("bag"), "Subtitles display speaker name and lost-property dialogue")
	events.reader._choose(1)
	check(not events.reader.is_open and not player.in_booth_inspection and not events.active.is_empty(), "Deferring restores movement and preserves the event")
	var state: Dictionary = events.save_state()
	events.active.clear()
	events.load_state(state)
	check(events.has_conversation(actor), "Save restoration preserves the same passenger and event token")
	var token: int = events.active.token
	check(not events.finish_dialogue(actor.profile.uid, token + 1, 1), "Stale event tokens cannot resolve another conversation")
	player.position = Vector3(-14, 0.35, 4)
	check(not events.finish_dialogue(actor.profile.uid, token, 1), "Remote or out-of-reach resolutions are rejected")
	player.position = Vector3(2, 0.35, 12)
	events.open_conversation(actor)
	for i in range(3): events.reader._choose(0)
	check(events.active.is_empty() and actor.phase == "SEATED" and not events.reader.is_open, "Lost property resolves through its complete conversation")
	check(not events.finish_dialogue(actor.profile.uid, token, 1), "Duplicate resolution has no effect")
	check(events.begin_event(actor, "needs_help"), "Needs help is available from Night 3")
	events.open_conversation(actor)
	for i in range(3): events.reader._choose(0)
	check(actor.phase == "FOLLOW" and actor.follow_peer == 1 and events.active.stage == "escort", "Accepting help starts the existing escort flow for the correct player")
	actor._points.clear()
	actor._path_pending = false
	actor._follow_timer = 0
	actor.position = Vector3(-10, 0.35, 4)
	player.position = Vector3(-10, 0.35, 4)
	actor._physics_process(0.016)
	events._process(0.1)
	check(actor.phase == "SAFE" and events.active.is_empty() and gm.objectives.save_passenger.done, "Reaching the booth completes the escort and releases the event slot")
	actor.phase = "SEATED"
	gm.night = 1
	check(not events.begin_event(actor, "needs_help"), "Early nights do not schedule frightened escort passengers")
	events.count = 0
	events.next_reviewed = 3
	events.cooldown = 0
	service.reviewed = 2
	events._process(1)
	check(events.active.is_empty(), "Scheduler waits for enough completed inspections")
	service.reviewed = 3
	station.get_node("NightEvents").started = true
	station.get_node("NightEvents").completed = false
	events._process(1)
	check(events.active.is_empty(), "Authored incidents take priority over random conversations")
	station.get_node("NightEvents").completed = true
	# Force a missed roll only in this fixture: no event and no frame-by-frame retry.
	events.event_chance = 0.0
	events._process(1)
	check(events.active.is_empty() and events.count == 0 and events.cooldown >= 90 and events.next_reviewed > service.reviewed, "A missed random opportunity produces no event and schedules no immediate retry")
	var missed_state: Dictionary = events.save_state()
	events.load_state(missed_state)
	events._process(1)
	check(events.active.is_empty() and events.next_reviewed == missed_state.next_reviewed, "Save/load preserves a missed opportunity instead of rerolling it")
	events.event_chance = 1.0
	events._process(1)
	check(events.active.is_empty(), "Even a successful future roll cannot bypass the cooldown and next inspection threshold")
	events.cooldown = 0
	service.reviewed = events.next_reviewed
	events._process(1)
	check(events.active.get("kind", "") == "lost_property", "Scheduler starts an eligible conversation when station work allows it")
	events.active.clear()
	events.cooldown = 0
	events._process(1)
	check(events.active.is_empty(), "Night 1 is capped at one random conversation")
	gm.night = 3
	var authored = station.get_node("NightEvents")
	authored.started = false
	authored.completed = false
	service.reviewed = authored.THRESHOLDS[2]
	check(events.begin_event(actor, "lost_property"), "Optional conversation can be pending when an authored incident becomes due")
	authored.advance(0.25)
	check(authored.started and events.active.is_empty(), "An ignored optional conversation never blocks required incident progression")
	station.queue_free()
	for i in range(8): await process_frame
	print("PASSENGER DIALOGUE CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
