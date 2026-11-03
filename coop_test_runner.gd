extends SceneTree

## Four independent instances exercise real ENet, not mocked RPC callbacks.
var failures: int = 0
var role: String = ""
var slot: int = 0
var directory: String
var port: int
var session: Node
var gm: Node
var _last_stage: String = ""


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		elif argument.begins_with("--slot="): slot = int(argument.trim_prefix("--slot="))
		elif argument.begins_with("--test-dir="): directory = argument.trim_prefix("--test-dir=")
		elif argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func mark(name_text: String, data: Variant = true) -> void:
	var temporary := directory.path_join(name_text + ".json.tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(temporary, directory.path_join(name_text + ".json"))


func exists(name_text: String) -> bool:
	return FileAccess.file_exists(directory.path_join(name_text + ".json"))


func wait_for(condition: Callable, description: String, seconds: float = 20) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	var ok: bool = condition.call()
	check(ok, description)
	return ok


func run() -> void:
	session = root.get_node("Coop")
	gm = root.get_node("GameManager")
	gm.save_path = directory.path_join("test-save.json")
	if role == "host": await run_host()
	elif role == "outsider": await run_outsider()
	else: await run_client()
	mark(role + str(slot) + "-result", {"failures": failures})
	print("COOP ", role, slot, ": ", failures, " failures")
	quit(0 if failures == 0 else 1)


func fixture(stage: String, points: Array) -> void:
	var ids: Array = []
	for index in range(1, 4):
		ids.append(int(JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("client-id%d.json" % index)))))
	for i in range(ids.size()):
		var avatar = session.player_for(ids[i])
		avatar.position = points[i]
		avatar.target_position = points[i]
		session._correct_position.rpc_id(ids[i], session.generation, points[i])
	mark("stage", {"name": stage, "uid": current_scene.get_node("PassengerService").current_profile().get("uid", "")})


func all_acked(stage: String) -> bool:
	return exists("1-" + stage) and exists("2-" + stage) and exists("3-" + stage)


func run_host() -> void:
	check(session.host(port) == OK, "Host opens ENet lobby")
	mark("listening")
	if not await wait_for(func() -> bool: return session.roster.size() == 4 and session.can_start(), "Four staff join and ready"): return
	check(session.start_shift(), "Host starts shared shift")
	if not await wait_for(func() -> bool: return session.world_live, "All four scene acknowledgements release simulation", 40): return
	var station = current_scene
	var player = session.local_player()
	player.set_physics_process(false)
	check(session._avatars.size() == 3, "Host has three remote crew avatars")
	var population = station.get_node("PassengerService")
	check(not gm.powered and not gm.signed_in and population.actors.is_empty(), "Host starts in a dark, closed and empty station")
	await wait_for(func() -> bool: return all_acked("intro"), "Every client receives closed station state")
	mark("allow-outsider")
	await wait_for(func() -> bool: return exists("outsider0-result"), "Fifth player rejected during active shift")
	var opening_origin: Vector3 = player.position
	player.position = Vector3(23.0, 0.36, 6.5)
	station._use_breaker()
	check(gm.powered and population.actors.is_empty() and not station.get_node("StationJobs").wire_panel.is_open, "Host switches on station power without a repair puzzle or passenger arrivals")
	player.position = opening_origin
	fixture("sign-one", [Vector3(-12, 0.35, 5), Vector3(0, 0.35, -14), Vector3(1, 0.35, -14)])
	await wait_for(func() -> bool: return gm.staff_sign_in_count() == 1 and all_acked("sign-one"), "One client's signature replicates to every peer")
	check(not gm.signed_in and population.actors.is_empty(), "One player signing twice cannot open the station")
	check(gm.save_game(), "Partial crew signatures can be saved")
	gm.signed_staff.clear()
	check(gm.load_game() and gm.staff_sign_in_count() == 1 and not gm.signed_in, "Partial signatures resume within the same host session and shift")
	var saved_token: String = session.session_token
	session.session_token = "different-session-for-test"
	check(gm.load_game() and gm.signed_staff.is_empty() and not gm.signed_in, "Another host session cannot inherit saved peer signatures")
	session.session_token = saved_token
	gm.load_game()
	fixture("sign-rest", [Vector3(-12, 0.35, 5), Vector3(-12.4, 0.35, 5), Vector3(-13, 0.35, 5)])
	await wait_for(func() -> bool: return gm.staff_sign_in_count() == 3 and all_acked("sign-rest"), "All three remote staff sign individually")
	check(not gm.signed_in and population.actors.is_empty() and not gm.signed_staff.has(1), "The station waits for the host even after every remote staff member signs")
	player.position = Vector3(-12, 0.35, 5)
	station.get_node("TB_LogbookInteraction/Interaction").interact()
	fixture("open", [Vector3(-12, 0.35, 5), Vector3(-12.4, 0.35, 5), Vector3(-13, 0.35, 5)])
	await wait_for(func() -> bool: return gm.signed_in and all_acked("open"), "The host's final signature opens the station for all peers")
	check(gm.staff_sign_in_count() == 4, "All four lobby members including the host are recorded")
	player.position = opening_origin
	check(gm.balance == 22, "Routine startup pays no repair reward and duplicate sign-in pays once")
	check(population.actors.size() == 3, "Remote sign-in starts the host's tutorial crowd wave")
	population.round_number = 1
	population._spawn_wave()
	population.round_number = 2
	population._spawn_wave()
	check(population.actors.size() == 9, "Host simulates the nine-person tutorial after opening")
	var appearance_manifest: Dictionary = {}
	for actor in population.actors: appearance_manifest[actor.profile.uid] = actor.visual.appearance.seed
	mark("appearance-manifest", appearance_manifest)
	var jobs = station.get_node("StationJobs")
	jobs._take("mop")
	jobs._spawn_mess(0)
	jobs._update_cleanliness()
	fixture("clean", [Vector3(0, 0.35, -14), Vector3(2, 0.35, -7), Vector3(1, 0.35, -14)])
	await wait_for(func() -> bool: return "0" in jobs.cleared and all_acked("clean"), "Remote held cleaning changes authoritative world")
	check(jobs.cleanliness == 100 and gm.balance == 24, "Cleanliness and reward agree on host")
	var services = station.get_node("StationServices")
	# Isolate the purchase race from legitimate passenger kiosk purchases.
	for actor in station.get_node("PassengerService").actors: actor.set_physics_process(false)
	services.stock.drink = 1
	gm.balance = 20
	fixture("purchase", [Vector3(-13, 0.35, -12), Vector3(-14, 0.35, -12), Vector3(-15, 0.35, -12)])
	await wait_for(func() -> bool: return all_acked("purchase"), "Concurrent purchases complete")
	await create_timer(0.5).timeout
	check(services.stock.drink == 0 and gm.balance == 17 and gm.inventory.get("drink", 0) == 1, "Last item sold once across three simultaneous buyers")
	var director = station.get_node("PassengerService")
	for actor in director.actors: actor.set_physics_process(false)
	director._queue.assign(director.actors)
	director.current_actor = director.actors[0]
	director.counter_ready = true
	fixture("ticket", [Vector3(-9, 0.35, 3), Vector3(-10, 0.35, 3), Vector3(-11, 0.35, 3)])
	await wait_for(func() -> bool: return all_acked("ticket"), "Three clerks submit same ticket")
	await create_timer(0.5).timeout
	check(director.reviewed == 1, "Stale ticket submissions cannot decide next passenger")
	var conversations = station.get_node("PassengerDialogueEvents")
	conversations.set_process(false)
	var talker = director.actors[1]
	talker.phase = "SEATED"
	talker._pre_ticket_seated = false
	talker.profile.anomaly = false
	talker.position = Vector3(2, 0.35, 14)
	check(conversations.begin_event(talker, "lost_property"), "Host schedules a shared passenger conversation")
	fixture("dialogue", [Vector3(2,0.35,12), Vector3(3,0.35,12), Vector3(1,0.35,12)])
	await wait_for(func() -> bool: return all_acked("dialogue"), "Concurrent dialogue choices converge on every client")
	check(conversations.active.is_empty() and conversations.count == 1, "Simultaneous dialogue resolutions finish the shared event only once")
	check(not conversations.reader.is_open, "Remote conversations never open the host's dialogue UI")
	fixture("invalid", [Vector3(0, 0.35, -14), Vector3(1, 0.35, -14), Vector3(2, 0.35, -14)])
	await wait_for(func() -> bool: return all_acked("invalid"), "Invalid interaction requests sent")
	check(not gm.powered == false, "Remote invalid calls do not change power")
	check(not jobs._messes.is_empty(), "Malformed node path cannot destroy station")
	check(gm.save_game(), "Host can save co-op world")
	gm.time_minutes = 138
	fixture("train", [Vector3(0, 0.35, -14), Vector3(1, 0.35, -14), Vector3(2, 0.35, -14)])
	await wait_for(func() -> bool: return all_acked("train"), "Train, economy and crew state agree across peers")
	var incident = station.get_node("NightEvents")
	incident.begin_incident()
	var incident_balance: int = gm.balance
	fixture("incident-distance", [Vector3(0,0.35,-5), Vector3(1,0.35,-5), Vector3(2,0.35,-5)])
	await wait_for(func() -> bool: return all_acked("incident-distance"), "Clients receive incident snapshot and attempt distant actions")
	check(not incident.completed, "Host rejects incident interaction outside physical reach")
	fixture("incident-resolve", [Vector3(-2,0.35,-14.4), Vector3(1,0.35,-5), Vector3(2,0.35,-5)])
	await wait_for(func() -> bool: return incident.completed and all_acked("incident-resolve"), "Nearby remote crew resolves the shared incident")
	check(gm.balance == incident_balance + 4, "Duplicate incident requests award exactly one reward")
	# Optional atmosphere shares host state but cannot mutate passenger verdicts.
	gm.night = 3
	var pacing = station.get_node("HorrorPacing")
	pacing.set_process(false)
	pacing._reset(3)
	pacing.sighting_chance = 1
	pacing.try_sighting()
	fixture("pacing-distance", [Vector3(0,0.35,-5), Vector3(1,0.35,-5), Vector3(2,0.35,-5)])
	await wait_for(func() -> bool: return all_acked("pacing-distance"), "Clients receive optional atmosphere and send distant evidence attempts")
	check(pacing._viewers.is_empty() and not gm.campaign.get("mystery", []).has("archive"), "Host rejects out-of-range pacing observations and archive evidence")
	fixture("pacing-watch", [Vector3(23,0.35,2), Vector3(23,0.35,3), Vector3(23,0.35,4)])
	await wait_for(func() -> bool: return all_acked("pacing-watch") and pacing._viewers.size() == 3, "Three remote camera observers reach the host")
	check(pacing.sighting == "SEEN", "Remote observation advances only host atmosphere state")
	for id in pacing._viewers: pacing._viewers[id] = Time.get_ticks_msec()
	pacing.advance(1)
	check(pacing.sighting == "SEEN", "Simultaneous viewers retain the shared sighting")
	fixture("pacing-away", [Vector3(23,0.35,2), Vector3(23,0.35,3), Vector3(23,0.35,4)])
	await wait_for(func() -> bool: return all_acked("pacing-away") and pacing._viewers.is_empty(), "All remote viewers lower their monitors")
	pacing.advance(2)
	fixture("pacing-retired", [Vector3(23,0.35,2), Vector3(23,0.35,3), Vector3(23,0.35,4)])
	await wait_for(func() -> bool: return all_acked("pacing-retired"), "Retired sighting and evidence converge across peers")
	check(director.reviewed == 1, "Optional anomaly does not approve or deny a passenger")
	fixture("pacing-archive", [Vector3(23,0.35,3.8), Vector3(23,0.35,3), Vector3(23,0.35,2)])
	await wait_for(func() -> bool: return all_acked("pacing-archive") and gm.campaign.get("mystery", []).has("archive"), "Remote archive discoveries become shared campaign evidence")
	check(not pacing._reader.is_open, "Remote archive readers never open the host's interface")
	gm.night = 4
	pacing._reset(4)
	pacing.begin_turn()
	fixture("pacing-turn", [Vector3(23,0.35,2), Vector3(23,0.35,3), Vector3(23,0.35,4)])
	await wait_for(func() -> bool: return all_acked("pacing-turn"), "Night 4 aftermath replicates without opening remote cutscenes")
	pacing.advance(21)
	gm.entity_identified = true
	var entity = station.get_node("PassengerEntity")
	entity.position = Vector3(0, 0.35, 0)
	entity.rotation.y = 0
	entity.phase = "STALK"
	entity.visible = true
	entity._target = Vector3(0, 0.35, 2)
	entity._path.clear()
	entity._path_timer = 10000
	entity.set_physics_process(false)
	fixture("attack", [Vector3(0, 0.35, 0.7), Vector3(0, 0.35, -14), Vector3(1, 0.35, -14)])
	var target_id: int = int(JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("client-id1.json"))))
	var attack_target = session.player_for(target_id)
	entity.phase = "HUNT"
	entity._begin_attack(attack_target)
	await wait_for(func() -> bool: return all_acked("attack"), "Animated wind-up replicates to all three clients")
	fixture("evade", [Vector3(0, 0.35, 3), Vector3(0, 0.35, -14), Vector3(1, 0.35, -14)])
	await create_timer(0.9).timeout
	entity._advance_attack(1, attack_target)
	await wait_for(func() -> bool: return all_acked("evade"), "Clients see host cancel attack after target escapes")
	check(gm.state != gm.NightState.DEAD, "Escaped teammate is not killed by a delayed hit")
	entity.phase = "STALK"
	entity._target = Vector3(0, 0.35, 2)
	entity._path.clear()
	entity._path_timer = 10000
	entity.set_physics_process(true)
	fixture("beam", [Vector3(-1, 0.35, -14), Vector3(0, 0.35, -7.5), Vector3(1, 0.35, -14)])
	await wait_for(func() -> bool: return entity.banished and all_acked("beam"), "Client flashlight can banish host-controlled entity")
	var rescued_actor = director.actors[1]
	# Model an admitted, seated passenger rather than retaining pre-ticket waypoints.
	rescued_actor.gate = station.get_node("GateLane_0")
	rescued_actor._path_pending = false
	rescued_actor._points.clear()
	rescued_actor.seat_anchor = director._reserve_seat()
	rescued_actor._sit()
	rescued_actor.put_in_danger()
	mark("rescue-uid", rescued_actor.profile.uid)
	fixture("rescue", [rescued_actor.position + Vector3(0, 0, 1), Vector3(0, 0.35, -14), Vector3(1, 0.35, -14)])
	await wait_for(func() -> bool: return rescued_actor.phase == "FOLLOW" and all_acked("rescue"), "Remote staff can rescue a threatened passenger")
	var rescuer: int = int(JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("client-id1.json"))))
	check(rescued_actor.follow_peer == rescuer, "Passenger follows requesting staff rather than always the host")
	rescued_actor.walk_speed = 5
	rescued_actor.set_physics_process(true)
	fixture("escort", [Vector3(-10, 0.35, 4), Vector3(0, 0.35, -14), Vector3(1, 0.35, -14)])
	var escorted: bool = await wait_for(func() -> bool: return rescued_actor.phase == "SAFE" and all_acked("escort"), "Remote teammate escorts passenger into booth", 30)
	if not escorted: print("ESCORT STALL ", rescued_actor.position, " ", rescued_actor._points.slice(0, 3), " ", rescued_actor.velocity)
	check(gm.rescued_passengers == 1, "Shared rescue counted once")
	var epoch: int = session.generation
	session.restart_shift()
	await wait_for(func() -> bool: return session.generation == epoch + 1 and session.world_live, "Host restart reloads every peer behind readiness barrier", 40)
	mark("stage", {"name": "restart"})
	await wait_for(func() -> bool: return all_acked("restart"), "Clients reject stale generation after restart")
	station = current_scene
	player = session.local_player()
	player.set_physics_process(false)
	check(gm.signed_staff.is_empty(), "Host reset clears signatures from the previous shift")
	player.position = Vector3(23, 0.35, 6.5)
	station._use_breaker()
	await create_timer(0.2).timeout
	player.position = Vector3(-12, 0.35, 5)
	station.get_node("TB_LogbookInteraction/Interaction").interact()
	fixture("sign-before-leave", [Vector3(-12, 0.35, 5), Vector3(-12.4, 0.35, 5), Vector3(1, 0.35, -14)])
	await wait_for(func() -> bool: return gm.staff_sign_in_count() == 3 and all_acked("sign-before-leave"), "Three remaining staff sign before an unsigned player departs")
	check(not gm.signed_in, "Unsigned fourth staff member still prevents opening")
	check(gm.save_game(), "Partial signatures save while waiting for the final staff member")
	mark("stage", {"name": "disconnect"})
	await wait_for(func() -> bool: return session.roster.size() == 3, "Disconnect removes crew member")
	check(session._avatars.size() == 2, "Disconnected avatar removed")
	check(gm.signed_in and gm.staff_sign_in_count() == 3, "Unsigned departure permits the fully signed remaining crew to open")
	check(gm.load_game() and gm.signed_in and gm.staff_sign_in_count() == 3, "A closed checkpoint reevaluates its signatures against the remaining crew")
	mark("stage", {"name": "host-leave"})
	await create_timer(0.5).timeout
	session.leave("Test complete")
	await wait_for(func() -> bool: return exists("client1-result") and exists("client2-result") and exists("client3-result"), "Clients cleanly return when host exits")


func run_client() -> void:
	check(session.join("127.0.0.1", port) == OK, "Client begins ENet connection")
	if not await wait_for(func() -> bool: return not session.roster.is_empty(), "Client receives lobby roster"): return
	mark("client-id%d" % slot, root.multiplayer.get_unique_id())
	session.set_ready(true)
	if not await wait_for(func() -> bool: return session.world_live, "Client loads station and receives start", 45): return
	session.local_player().set_physics_process(false)
	var station = current_scene
	check(session._avatars.size() == 3 and get_nodes_in_group("player").size() == 1, "Exactly one local controller plus three teammates")
	check(not gm.powered and not gm.signed_in and station.get_node("PassengerService").actors.is_empty(), "Client joins a dark, closed station without passengers")
	gm.sign_in()
	check(gm.signed_staff.is_empty() and not gm.signed_in, "A client cannot locally grant itself a signature or open the station")
	mark(str(slot) + "-intro")
	var deadline := Time.get_ticks_msec() + 100000
	while Time.get_ticks_msec() < deadline:
		if not session.active:
			check(true, "Host disconnect ends session")
			return
		if not exists("stage"):
			await create_timer(0.05).timeout
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("stage.json")))
		if not data is Dictionary or data.name == _last_stage:
			await create_timer(0.05).timeout
			continue
		_last_stage = data.name
		await create_timer(0.6).timeout
		if not session.active:
			check(true, "Host departure is handled")
			return
		station = current_scene
		var jobs = station.get_node("StationJobs")
		match _last_stage:
			"sign-one":
				if slot == 1:
					station.get_node("TB_LogbookInteraction/Interaction").interact()
					await create_timer(0.25).timeout
					station.get_node("TB_LogbookInteraction/Interaction").interact()
				await wait_for(func() -> bool: return gm.staff_sign_in_count() == 1, "First signature count replicates")
				check(not gm.signed_in and station.get_node("PassengerService").actors.is_empty(), "Clients stay closed and empty after only one player signs")
				check(gm.local_staff_signed() == (slot == 1), "Each client sees its own signature state")
			"sign-rest":
				if slot != 1: station.get_node("TB_LogbookInteraction/Interaction").interact()
				await wait_for(func() -> bool: return gm.staff_sign_in_count() == 3, "Three remote signatures replicate")
				check(not gm.signed_in and not gm.signed_staff.has(1), "Clients still wait for the host's signature")
			"open":
				await wait_for(func() -> bool: return gm.signed_in and gm.staff_sign_in_count() == 4, "Shared opening arrives only with all four signatures")
				await wait_for(func() -> bool: return station.get_node("NightHUD")._opening_title.visible, "Opening announcement reaches every client")
				check(station.get_node("NightHUD")._opening_title.text == "The Station Is Now Open", "Clients display the exact opening text")
			"clean":
				await wait_for(func() -> bool: return jobs._messes.has("0"), "Client sees spawned dirt")
				if slot == 2:
					var target = jobs._messes["0"].get_node("Interaction")
					session.begin_hold(target)
					await create_timer(1.3).timeout
					target.interact()
				await wait_for(func() -> bool: return "0" in jobs.cleared, "Shared cleaning arrives")
			"purchase":
				session.request_action("purchase", "drink")
				await create_timer(1).timeout
				check(gm.balance == 17 and station.get_node("StationServices").stock.drink == 0, "Purchase race converges on client")
			"ticket":
				var director = station.get_node("PassengerService")
				check(not str(data.get("uid", "")).is_empty(), "Fixture supplies same ticket to every clerk")
				session.request_action("ticket", {"uid": data.uid, "approve": false})
				await create_timer(1).timeout
				check(director.reviewed == 1, "Exactly one ticket verdict replicated")
			"dialogue":
				var conversations = station.get_node("PassengerDialogueEvents")
				await wait_for(func() -> bool: return not conversations.active.is_empty(), "Client receives the passenger conversation snapshot")
				if not conversations.active.is_empty():
					var talker = conversations.actor_for(str(conversations.active.uid))
					await wait_for(func() -> bool: return is_instance_valid(talker) and talker.phase == "SEATED", "Client receives the talkable passenger's seated state")
					talker.get_node("Interaction").interact()
					check(conversations.reader.is_open and session.local_player().in_booth_inspection, "Remote player opens only their local dialogue UI")
					mark(str(slot) + "-dialogue-open")
					await wait_for(func() -> bool: return exists("1-dialogue-open") and exists("2-dialogue-open") and exists("3-dialogue-open"), "All clients open dialogue before the response race")
					for i in range(3): conversations.reader._choose(0)
				await wait_for(func() -> bool: return conversations.active.is_empty(), "Host dialogue resolution replicates to this client")
				check(not conversations.reader.is_open, "Client closes dialogue after choosing its response")
			"invalid":
				session._interact.rpc_id(1, session.generation, "../../GameManager")
				session._interact.rpc_id(1, session.generation, "TB_LogbookInteraction/Interaction")
				session.request_action("restore")
				check(not gm.save_game(), "Client cannot write campaign save")
				var pause_menu = station.get_node("PauseMenu")
				pause_menu.set_paused(true)
				check(not paused and session.local_player().get_meta("local_menu"), "Personal pause never freezes shared world")
				pause_menu.set_paused(false)
			"pacing-distance":
				var pacing = station.get_node("HorrorPacing")
				pacing.set_process(false)
				await wait_for(func() -> bool: return gm.night == 3 and pacing.sighting == "AVAILABLE", "Optional sighting snapshot arrives on client")
				session.request_action("pacing_view", true)
				session.request_action("pacing_archive")
				check(pacing._viewers.is_empty(), "Client cannot advance authoritative observation locally")
			"pacing-watch":
				session.request_action("pacing_view", true)
				await wait_for(func() -> bool: return station.get_node("HorrorPacing").sighting == "SEEN", "Host-observed figure state returns to remote viewer")
			"pacing-away":
				session.request_action("pacing_view", false)
			"pacing-retired":
				await wait_for(func() -> bool: return station.get_node("HorrorPacing").sighting == "RETIRED" and gm.campaign.get("mystery", []).has("camera"), "Client receives disappearance and persistent optional evidence")
			"pacing-archive":
				var pacing = station.get_node("HorrorPacing")
				if slot == 1:
					pacing._archive.get_node("Interaction").interact()
					check(pacing._reader.is_open and session.local_player().in_booth_inspection, "Archive interaction opens the requesting client's local reader")
				await wait_for(func() -> bool: return gm.campaign.get("mystery", []).has("archive"), "Archive discovery is replicated to every crew member")
				pacing._reader.close_panel()
			"pacing-turn":
				await wait_for(func() -> bool: return station.get_node("HorrorPacing").turn == "AFTERMATH", "Client receives Night 4 aftermath state")
				check(not session.local_player().in_booth_inspection, "Night 4 atmosphere leaves remote controls available")
				check(station.get_node("StationPA")._stage in ["INTERRUPTED", "SILENCE"], "Live Night 4 transition presents interrupted PA locally once")
			"incident-distance":
				var incident = station.get_node("NightEvents")
				check(incident.started and not incident.completed, "Authored incident state replicates to each client")
				incident.resolve("exit")
				check(not incident.completed, "Client cannot locally complete authoritative incident state")
				station.get_node("NightEvents/ExitSeal/Interaction").interact()
				await create_timer(0.5).timeout
			"incident-resolve":
				if slot == 1:
					station.get_node("NightEvents/ExitSeal/Interaction").interact()
					await create_timer(0.25).timeout
					station.get_node("NightEvents/ExitSeal/Interaction").interact()
				await wait_for(func() -> bool: return station.get_node("NightEvents").completed, "Remote incident completion converges on every client")
				check(gm.objectives.night_incident.done, "Clients receive completed incident objective")
			"train":
				await wait_for(func() -> bool: return station.get_node("TrainService").phase == "ARRIVING", "Client receives host train movement")
				check(session._avatars.size() == 3, "All teammates remain visible")
				var expected = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("appearance-manifest.json")))
				var identities_match := true
				for actor in station.get_node("PassengerService").actors:
					identities_match = identities_match and int(expected.get(actor.profile.uid, -1)) == int(actor.visual.appearance.seed)
				check(identities_match, "All passenger appearances agree with the host")
				check(station.get_node("PassengerService").actors.size() == 9, "All nine tutorial passengers replicate without duplicate simulation")
			"attack":
				var threat = station.get_node("PassengerEntity")
				await wait_for(func() -> bool: return threat.phase == "ATTACK" and threat.visual.current_clip == "Attack", "Host wind-up drives client animation")
				check(threat.visual.skeleton.get_bone_count() == 19, "Remote monster has full imported skeleton")
			"evade":
				var threat = station.get_node("PassengerEntity")
				await wait_for(func() -> bool: return threat.phase == "STALK", "Host range check cancels remote wind-up")
				check(gm.state != gm.NightState.DEAD, "Client receives no false death after escape")
			"beam":
				if slot == 2:
					session.local_player().rotation.y = PI
					session.local_player().head.rotation.x = 0
					session.local_player().set_flashlight(true, false)
				await wait_for(func() -> bool: return station.get_node("PassengerEntity").banished, "Banishment replicates to every crew member")
			"rescue":
				var uid: String = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("rescue-uid.json")))
				if slot == 1: station.get_node("Passenger_" + uid + "/Interaction").interact()
				await wait_for(func() -> bool: return station.get_node("Passenger_" + uid).phase == "FOLLOW", "Rescue request replicates")
			"escort":
				var uid: String = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("rescue-uid.json")))
				await wait_for(func() -> bool: return station.get_node("Passenger_" + uid).phase == "SAFE", "Teammate escort reaches shared safety", 30)
			"restart":
				await wait_for(func() -> bool: return session.world_live and session.generation == 2, "Client reloads correct world generation", 40)
				session.local_player().set_physics_process(false)
				check(not gm.signed_in and gm.signed_staff.is_empty() and gm.time_minutes < 131, "Restart clears all crew signatures and resets the shift")
			"sign-before-leave":
				if slot != 3: station.get_node("TB_LogbookInteraction/Interaction").interact()
				await wait_for(func() -> bool: return gm.staff_sign_in_count() == 3, "New shift records fresh signatures")
				check(not gm.signed_in, "New shift waits for its final staff member")
			"disconnect":
				if slot == 3:
					session.leave("Client disconnect test")
					return
			"host-leave":
				await wait_for(func() -> bool: return not session.active, "Host departure is handled", 10)
				return
		mark(str(slot) + "-" + _last_stage)
	check(false, "Client test deadline")


func run_outsider() -> void:
	session.join("127.0.0.1", port)
	await wait_for(func() -> bool: return not session.active, "Full/running lobby rejects fifth player", 20)
