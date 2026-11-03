extends Node

signal clock_changed
signal power_changed(powered: bool)
signal objectives_changed
signal shift_finished
signal notice_posted(text: String)
signal night_started(number: int)
signal player_died
signal checkpoint_loading

enum NightState { WORKING, BLACKOUT, SHIFT_OVER, DEAD }

const START_MINUTE: float = 130.0 # 02:10 AM
const END_MINUTE: float = 360.0
const AUTOSAVE_INTERVAL := 120.0

## One game minute per ten real seconds, beginning when the station opens.
@export var minutes_per_second: float = 0.1
var night: int = 1
var time_minutes: float = START_MINUTE
var state: NightState = NightState.BLACKOUT
var powered: bool = false
var signed_in: bool = false
var signed_staff: Array[int] = []
var objectives: Dictionary = {}
var inventory: Dictionary = {"employee_id": 1, "mop": 0, "battery": 1}
var loading: bool = false
var entity_identified: bool = false
var rescued_passengers: int = 0
var lost_passengers: int = 0
var pending_load: bool = false
var _secured_time: float = 0
var _completion_elapsed: float = 0
var campaign: Dictionary = {"correct": 0, "reviewed": 0, "lost": 0, "rescued": 0, "boarded": 0, "nights_completed": 0}
var balance: int = 20
var reward_ledger: Dictionary = {}
var save_path: String = "user://station7_save.json"
var _autosave_elapsed := AUTOSAVE_INTERVAL - 5.0


func _ready() -> void:
	for bus in ["SFX", "Ambience", "Music"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	start_night()


func start_night(number: int = 1) -> void:
	night = clampi(number, 1, 7)
	time_minutes = START_MINUTE
	state = NightState.BLACKOUT
	powered = false
	signed_in = false
	signed_staff.clear()
	entity_identified = false
	rescued_passengers = 0
	lost_passengers = 0
	_secured_time = 0
	_completion_elapsed = 0
	_autosave_elapsed = AUTOSAVE_INTERVAL - 5.0
	inventory = {"employee_id": 1, "mop": 0, "battery": 1, "phone": 1, "flashlight": 1}
	objectives = {
		"start_power": {"text": "Start up the station: switch on the main power in the Electrical Room.", "done": false},
		"sign_in": {"text": "Every staff member must sign the logbook on the booth's rear workbench.", "done": false},
	}
	clock_changed.emit()
	power_changed.emit(powered)
	objectives_changed.emit()
	night_started.emit(night)


func _process(delta: float) -> void:
	if Coop.simulation_blocked(): return
	advance_clock(delta)
	if state not in [NightState.WORKING, NightState.BLACKOUT]: return
	_tick_autosave(delta)
	_completion_elapsed += delta
	if _completion_elapsed < 0.25: return
	var elapsed := _completion_elapsed
	_completion_elapsed = 0
	if not irreversible_shift_failure().is_empty():
		state = NightState.SHIFT_OVER
		shift_finished.emit()
		return
	if shift_blockers().is_empty():
		_secured_time += elapsed
		if _secured_time >= 6:
			time_minutes = END_MINUTE
			state = NightState.SHIFT_OVER
			clock_changed.emit()
			shift_finished.emit()
	else: _secured_time = 0


## Only end an unwinnable shift after its final check, allowing the player to
## finish the lesson rather than interrupting them for a single mistake.
func irreversible_shift_failure() -> String:
	var service := get_tree().get_first_node_in_group("passenger_director")
	if not service or not service.started or service.reviewed < service.total_cases(): return ""
	var target := ceili(service.total_cases() * 0.66)
	if service.correct < target:
		return "All tickets have been checked, but too few decisions were correct to pass. Retry this night or load an earlier checkpoint."
	if service.decisions.is_empty(): return "" # Legacy saves may not contain a verdict history.
	var admitted := false
	for verdict in service.decisions:
		if verdict.get("approved", false):
			admitted = true
			if night <= 3 and verdict.get("anomaly", false):
				return "A camera-invisible passenger was approved. This shift cannot be secured. Retry, and compare the person with the camera before stamping."
	var train := get_tree().get_first_node_in_group("train_service")
	if not admitted and train and train.boarded_count == 0:
		return "Every passenger was denied, so nobody can board. Retry, and approve passengers whose documents and camera image match."
	return ""


func _tick_autosave(delta: float) -> void:
	if loading or pending_load or get_tree().paused or Coop.is_client(): return
	_autosave_elapsed += maxf(delta, 0)
	if _autosave_elapsed < AUTOSAVE_INTERVAL: return
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	var desk := get_tree().get_first_node_in_group("booth_desk")
	if not jobs or not desk: return # Never save the menu or a partially built scene.
	if desk.stamping or desk.sliding or desk._returning or is_instance_valid(desk.held): return
	if not irreversible_shift_failure().is_empty(): return
	var service := get_tree().get_first_node_in_group("passenger_director")
	if service and service.started:
		var remaining: int = maxi(0, service.total_cases() - service.reviewed)
		if service.correct + remaining < ceili(service.total_cases() * 0.66): return
		if night <= 3:
			for verdict in service.decisions:
				if verdict.get("approved", false) and verdict.get("anomaly", false): return
	if preload("res://checkpoint_store.gd").write(save_path + ".auto", _checkpoint_payload()):
		_autosave_elapsed = 0
	else:
		_autosave_elapsed = AUTOSAVE_INTERVAL - 30.0
		notice_posted.emit("Automatic checkpoint could not be saved. Your previous checkpoint is unchanged.")


## One authoritative checklist serves automatic completion and the shift report.
func shift_blockers() -> PackedStringArray:
	var reasons := PackedStringArray()
	var service := get_tree().get_first_node_in_group("passenger_director")
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	var entity := get_tree().get_first_node_in_group("station_entity")
	var train := get_tree().get_first_node_in_group("train_service")
	if not signed_in: reasons.append("Shift logbook unsigned — sign in at the booth's rear workbench.")
	if not objectives.get("check_platform", {}).get("done", false): reasons.append("Platform patrol unfinished — scan your staff ID at a gate and visit the platform.")
	if not powered:
		reasons.append("Power offline — reconnect the three wires and use the Electrical Room's main switch." if needs_power_repair() else "Station power off — switch on the Electrical Room’s main power before signing in.")
	for key in ["fix_door", "fix_gate", "fix_light", "night_incident"]:
		if objectives.has(key) and not objectives[key].done: reasons.append(str(objectives[key].text))
	if not service or not jobs or not entity or not train:
		reasons.append("Station systems are unavailable. Reload the shift.")
		return reasons
	var total: int = service.total_cases()
	if service.reviewed < total: reasons.append("%d ticket checks remaining — return to the inspection booth." % (total - service.reviewed))
	var target := ceili(total * 0.66)
	if service.correct < target: reasons.append("Ticket accuracy below requirement: %d / %d correct decisions needed. Compare every document field and the window camera." % [service.correct, target])
	if train.boarded_count <= 0: reasons.append("No passengers boarded — admit a genuine passenger and wait for the train's boarding call.")
	if jobs.cleanliness < 70: reasons.append("Cleanliness %d%% / 70%% required — collect the janitor room's mop and clean marked messes." % int(jobs.cleanliness))
	if not entity.banished: reasons.append("Intruder still uncontained — deny camera-invisible passengers." if night <= 3 else "Intruder still uncontained — collect three reports, identify it at Security, then use a direct flashlight beam.")
	if lost_passengers > (1 if night <= 4 else 0): reasons.append("Passenger loss limit exceeded — retry and escort endangered passengers to safety sooner.")
	return reasons


func advance_clock(real_seconds: float) -> void:
	if Coop.simulation_blocked(): return
	if not signed_in or get_tree().paused or state in [NightState.SHIFT_OVER, NightState.DEAD] or real_seconds <= 0.0:
		return
	var previous_minute := int(time_minutes)
	time_minutes = minf(time_minutes + real_seconds * maxf(minutes_per_second, 0.0), END_MINUTE)
	if time_minutes >= END_MINUTE:
		state = NightState.SHIFT_OVER
		shift_finished.emit()
	if int(time_minutes) != previous_minute:
		clock_changed.emit()


func cause_power_failure() -> void:
	## A real fault needs wire repair; ordinary startup only needs the main switch.
	if not powered or state == NightState.SHIFT_OVER:
		return
	powered = false
	state = NightState.BLACKOUT
	objectives["restore_power"] = {"text": "Restore power at the Electrical Room breaker (hold E).", "done": false}
	power_changed.emit(false)
	objectives_changed.emit()


func required_staff() -> Array:
	return Coop.roster.keys() if Coop.active else [1]


func staff_sign_in_count() -> int:
	var count := 0
	for id in required_staff():
		if signed_staff.has(int(id)): count += 1
	return count


func local_staff_signed() -> bool:
	return signed_staff.has(multiplayer.get_unique_id() if Coop.active else 1)


func sign_in() -> void:
	if Coop.is_client() or signed_in or state in [NightState.SHIFT_OVER, NightState.DEAD]: return
	if Coop.active and (not Coop.running or not Coop.world_live): return
	if not powered:
		notice_posted.emit("Turn on the station lights in the Electrical Room before signing the logbook.")
		return
	var staff_id: int = Coop.interaction_peer if Coop.active else 1
	if not required_staff().has(staff_id): return
	if signed_staff.has(staff_id): return
	signed_staff.append(staff_id)
	refresh_staff_sign_in()
	if not signed_in:
		notice_posted.emit("Logbook signed: %d/%d staff. Waiting for everyone to sign." % [staff_sign_in_count(), required_staff().size()])


func refresh_staff_sign_in() -> void:
	if Coop.is_client(): return
	var required := required_staff()
	for id in signed_staff.duplicate():
		if not required.has(id): signed_staff.erase(id)
	if signed_in or not objectives.has("sign_in"): return
	objectives.sign_in.text = "Sign the rear logbook: %d/%d staff signed. Everyone must sign before opening." % [staff_sign_in_count(), required.size()]
	objectives_changed.emit()
	if loading or not powered or required.is_empty() or state in [NightState.SHIFT_OVER, NightState.DEAD]: return
	if staff_sign_in_count() != required.size(): return
	signed_in = true
	objectives["check_platform"] = {"text": "Scan your staff ID at a gate and check the platform.", "done": false}
	complete_objective("sign_in")
	get_tree().call_group("station_pa", "announce", "welcome")
	notice_posted.emit("The Station Is Now Open")


func inspect_platform() -> void:
	if signed_in and state != NightState.SHIFT_OVER:
		complete_objective("check_platform")


func needs_power_repair() -> bool:
	return not powered and objectives.has("restore_power") and not objectives["restore_power"].done


func turn_on_power() -> bool:
	if powered or needs_power_repair() or state in [NightState.SHIFT_OVER, NightState.DEAD]: return false
	restore_power()
	notice_posted.emit("Station power on. Every staff member must sign the logbook to open the station.")
	return powered


func restore_power() -> void:
	if state in [NightState.SHIFT_OVER, NightState.DEAD]:
		return
	if not powered:
		powered = true
		state = NightState.WORKING
		complete_objective("start_power")
		complete_objective("restore_power")
		power_changed.emit(true)
		refresh_staff_sign_in()


func complete_objective(id: String) -> void:
	if objectives.has(id) and not objectives[id]["done"]:
		objectives[id]["done"] = true
		var rewards := {"sign_in": 2, "check_platform": 3, "check_tickets": 10, "fix_light": 6, "fix_door": 6, "fix_gate": 6, "restore_power": 10, "identify_entity": 8, "banish_entity": 20, "save_passenger": 12}
		if rewards.has(id): reward_once("duty/" + id, rewards[id])
		objectives_changed.emit()


func kill_player() -> void:
	if state in [NightState.SHIFT_OVER, NightState.DEAD]: return
	state = NightState.DEAD
	get_tree().call_group("world_modal", "close_panel")
	player_died.emit()


func passenger_lost() -> void:
	if state in [NightState.SHIFT_OVER, NightState.DEAD]: return
	lost_passengers += 1
	notice_posted.emit("A passenger has been lost. Rescue people marked in danger before time runs out.")
	if lost_passengers > (1 if night <= 4 else 0):
		state = NightState.SHIFT_OVER
		shift_finished.emit()


func maintenance_complete() -> bool:
	for key in ["restore_power", "fix_door", "fix_gate", "fix_light"]:
		if objectives.has(key) and not objectives[key]["done"]: return false
	return true


func new_campaign() -> void:
	balance = 20
	reward_ledger.clear()
	campaign = {"correct": 0, "reviewed": 0, "lost": 0, "rescued": 0, "boarded": 0, "nights_completed": 0}
	start_night(1)


func record_night() -> void:
	if int(campaign.get("nights_completed", 0)) >= night: return
	var service := get_tree().get_first_node_in_group("passenger_director")
	var train := get_tree().get_first_node_in_group("train_service")
	campaign.correct += service.correct if service else 0
	campaign.reviewed += service.reviewed if service else 0
	campaign.lost += lost_passengers
	campaign.rescued += rescued_passengers
	campaign.boarded += train.boarded_count if train else 0
	campaign.nights_completed = night


func has_item(item: String) -> bool:
	return int(inventory.get(item, 0)) > 0


func reward_once(id: String, amount: int) -> bool:
	var key := "%d/%s" % [night, id]
	if amount <= 0 or reward_ledger.has(key): return false
	reward_ledger[key] = true
	balance += amount
	notice_posted.emit("Earned %d credits." % amount)
	return true


func spend(amount: int) -> bool:
	if amount < 0 or balance < amount: return false
	balance -= amount
	return true


func give_item(item: String, amount: int = 1) -> void:
	inventory[item] = maxi(0, int(inventory.get(item, 0)) + amount)
	notice_posted.emit("Picked up " + item.replace("_", " "))


func read_checkpoint() -> Dictionary:
	var store = preload("res://checkpoint_store.gd")
	var manual: Dictionary = store.read(save_path)
	var automatic: Dictionary = store.read(save_path + ".auto")
	if automatic.is_empty(): return manual
	if manual.is_empty() or float(automatic.get("saved_at", 0)) > float(manual.get("saved_at", 0)):
		automatic["automatic_checkpoint"] = true
		return automatic
	return manual


func _checkpoint_payload() -> Dictionary:
	var payload := {"version": 1, "saved_at": Time.get_unix_time_from_system(), "core": {"night": night, "time": time_minutes, "powered": powered, "signed_in": signed_in, "state": state, "objectives": objectives, "inventory": inventory, "identified": entity_identified, "rescued": rescued_passengers, "lost": lost_passengers, "campaign": campaign}, "participants": {}}
	for node in get_tree().get_nodes_in_group("save_participant"):
		if node.has_method("save_state"):
			payload.participants[str(node.name)] = node.save_state()
	payload.core["signed_staff"] = signed_staff.duplicate()
	payload.core["signature_session"] = Coop.session_token
	payload.core["signature_generation"] = Coop.generation
	payload.core["balance"] = balance
	payload.core["rewards"] = reward_ledger
	return payload


func save_game() -> bool:
	if Coop.is_client():
		notice_posted.emit("The host saves the shared campaign.")
		return false
	if not preload("res://checkpoint_store.gd").write(save_path, _checkpoint_payload()):
		notice_posted.emit("Could not save the shift.")
		return false
	notice_posted.emit("Shift saved.")
	return true


func load_game() -> bool:
	if Coop.is_client(): return false
	var payload := read_checkpoint()
	if payload.is_empty():
		notice_posted.emit("No readable checkpoint found. Retry this night or start a new campaign.")
		return false
	var core: Dictionary = payload.core
	var saved_night: int = clampi(int(core.get("night", 1)), 1, 7)
	checkpoint_loading.emit()
	if saved_night != night:
		get_tree().call_group("world_modal", "close_panel")
		night = saved_night
		pending_load = true
		get_tree().paused = false
		get_tree().change_scene_to_file("res://station_builder.tscn")
		return true
	get_tree().call_group("world_modal", "close_panel")
	loading = true
	night = clampi(int(core.get("night", 1)), 1, 7)
	time_minutes = clampf(float(core.get("time", START_MINUTE)), START_MINUTE, END_MINUTE)
	powered = bool(core.get("powered", true))
	signed_in = bool(core.get("signed_in", false))
	signed_staff.clear()
	# Peer IDs only identify signers within the same host session.
	if signed_in:
		for id in required_staff(): signed_staff.append(int(id))
	elif not Coop.active or (core.get("signature_session", "") == Coop.session_token and int(core.get("signature_generation", -1)) == Coop.generation):
		for id in core.get("signed_staff", []):
			if required_staff().has(int(id)) and not signed_staff.has(int(id)): signed_staff.append(int(id))
	entity_identified = bool(core.get("identified", false))
	rescued_passengers = int(core.get("rescued", 0))
	lost_passengers = int(core.get("lost", 0))
	campaign = core.get("campaign", campaign)
	state = int(core.get("state", NightState.WORKING)) as NightState
	objectives = core.get("objectives", {})
	if not signed_in and objectives.has("sign_in"):
		objectives.sign_in.text = "Sign the rear logbook: %d/%d staff signed. Everyone must sign before opening." % [staff_sign_in_count(), required_staff().size()]
	inventory = core.get("inventory", {"employee_id": 1})
	inventory["phone"] = 1
	inventory["flashlight"] = 1
	balance = maxi(0, int(core.get("balance", 20)))
	reward_ledger = core.get("rewards", {})
	for node in get_tree().get_nodes_in_group("save_participant"):
		if node.has_method("load_state") and payload.get("participants", {}).has(str(node.name)):
			node.load_state(payload.participants[str(node.name)])
	loading = false
	_secured_time = 0
	_completion_elapsed = 0
	_autosave_elapsed = 0
	clock_changed.emit()
	power_changed.emit(powered)
	objectives_changed.emit()
	var restored_text := "Automatic checkpoint loaded." if payload.get("automatic_checkpoint", false) else "Saved shift loaded."
	notice_posted.emit("Recovered the previous checkpoint from backup." if payload.get("recovered_backup", false) else restored_text)
	if state == NightState.SHIFT_OVER: shift_finished.emit()
	elif state == NightState.DEAD: player_died.emit()
	# A closed checkpoint may now have a smaller, fully signed connected crew.
	if not signed_in: refresh_staff_sign_in()
	return true


func clock_text() -> String:
	var minute := int(time_minutes)
	return "%02d:%02d AM" % [minute / 60, minute % 60]
