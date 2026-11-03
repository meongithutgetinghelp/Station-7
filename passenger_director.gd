extends Node

const Cases = preload("res://passenger_cases.gd")
const Actor = preload("res://passenger_actor.gd")
const InspectionUI = preload("res://ticket_inspection_ui.gd")

signal passenger_ready(profile: Dictionary)
signal decision_recorded(result: Dictionary)

var started: bool = false
var counter_ready: bool = false
var _queue_release: Node
var _queue_revision := 0
var current_actor: Node
var reviewed: int = 0
var correct: int = 0
var decisions: Array[Dictionary] = []
var ui: CanvasLayer
var _queue: Array[Node] = []
var actors: Array[Node] = []
var _station: Node3D
var _seats: Array[Marker3D] = []
var round_limit: int = 3
@export_range(3, 12) var passengers_per_round: int = 8
@export var pre_ticket_routines_enabled: bool = true
var round_number: int = 0
var _wave_timer: float = 0


func _ready() -> void:
	passengers_per_round = 3 if GameManager.night == 1 else 8
	add_to_group("passenger_director")
	add_to_group("save_participant")
	_station = get_parent()
	ui = InspectionUI.new()
	ui.name = "TicketInspectionUI"
	ui.director = self
	add_child(ui)
	var console: Node = _station.get_node("TB_InspectionConsole")
	preload("res://interactable.gd").attach(console, open_desk, console_prompt)
	GameManager.objectives_changed.connect(_sync_shift)
	GameManager.shift_finished.connect(_end_shift)
	GameManager.night_started.connect(_night_reset)
	call_deferred("_sync_shift")


func _sync_shift() -> void:
	if Coop.is_client(): return
	if GameManager.loading or not GameManager.signed_in:
		return
	if GameManager.state not in [GameManager.NightState.WORKING, GameManager.NightState.BLACKOUT]:
		return
	if not started and not GameManager.pending_load:
		_start_queue()


func _night_reset(_number: int) -> void:
	_reset()
	passengers_per_round = 3 if _number == 1 else 8
	call_deferred("_sync_shift")


func _start_queue() -> void:
	if started or not GameManager.signed_in: return
	started = true
	for marker: Node in get_tree().get_nodes_in_group("passenger_seats"):
		if str(marker.get_parent().name).begins_with("PlatformBench_") or str(marker.get_parent().name).begins_with("WaitingBench_"):
			_seats.append(marker)
	_spawn_wave()
	_update_objective()


func _spawn_wave() -> void:
	if not GameManager.signed_in: return
	var index: int = 0
	for profile in Cases.for_night(GameManager.night, round_number, passengers_per_round):
		var actor := Actor.new()
		actor.name = "Passenger_" + profile.uid
		actor.profile = profile
		# Gate validity represents the clerk's approval, not hidden document truth.
		actor.ticket = Ticket.make(profile.ticket_number, profile.ticket_name, profile.destination, false)
		actor.position = Vector3(-0.7 + (index % 3) * 0.7, 4.69, -34.4 - floorf(float(index) / 3) * 0.85)
		actor._entry_delay = index * 0.9
		actor.walk_speed = randf_range(1.7, 2.2)
		index += 1
		actor.reached_counter.connect(_on_counter_ready)
		actor.ready_to_queue.connect(_request_ticket)
		_station.add_child(actor)
		actors.append(actor)
		if pre_ticket_routines_enabled: actor.begin_visit()
		else: _queue.append(actor)
	_reposition_queue()
	_wave_timer = 0


func total_cases() -> int:
	return round_limit * passengers_per_round


func _process(delta: float) -> void:
	if Coop.simulation_blocked() or not GameManager.signed_in: return
	if started and round_number + 1 < round_limit and GameManager.state not in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]:
		_wave_timer += delta
		if _wave_timer >= maxf(24, 40 - GameManager.night * 2):
			round_number += 1
			_spawn_wave()
			GameManager.notice_posted.emit("More passengers are entering the station.")


func _request_ticket(actor: Node) -> void:
	if actor in _queue: return
	if _queue.size() >= 6:
		actor.wait_for_queue_space()
		return
	_queue.append(actor)
	_reposition_queue()


func _reposition_queue() -> void:
	if is_instance_valid(_queue_release):
		for i in range(_queue.size()): _queue[i].queue_at(Vector3(-5.85, 0.35, 4.0 - (i + 1) * 1.3), false)
		return
	var keep_front: bool = counter_ready and not _queue.is_empty() and current_actor == _queue[0]
	if keep_front:
		for i in range(1, _queue.size()):
			_queue[i].queue_at(Vector3(-5.85, 0.35, 4.0 - i * 1.3), false)
		return
	counter_ready = false
	current_actor = null
	for i in range(_queue.size()):
		_queue[i].queue_at(Vector3(-5.85, 0.35, 4.0 - i * 1.3), i == 0)


func _on_counter_ready(actor: Node) -> void:
	if _queue.is_empty() or _queue[0] != actor:
		return
	current_actor = actor
	counter_ready = true
	passenger_ready.emit(actor.profile)
	if ui.is_open:
		ui.passenger_arrived(actor.profile)


func console_prompt() -> String:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.x > -7.125:
		return "Use the staff side of the ticket booth"
	if not GameManager.signed_in:
		return "Sign in at the rear logbook first"
	if reviewed >= total_cases():
		return "[E] View ticket inspection report"
	return "[E] Inspect passenger documents" if counter_ready else "[E] Open desk — passenger approaching"


func open_desk() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not GameManager.signed_in or GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]:
		return
	if player and (player.global_position.x > -7.125 or player.global_position.z < 1.0 or player.global_position.z > 7.0):
		return
	ui.open_desk()


func current_profile() -> Dictionary:
	return current_actor.profile if counter_ready and is_instance_valid(current_actor) else {}


func decide(approve: bool) -> Dictionary:
	if not counter_ready or not is_instance_valid(current_actor) or GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]:
		return {}
	if approve and not GameManager.powered:
		return {}
	var actor: Node = current_actor
	var problems := Cases.errors(actor.profile)
	var valid: bool = problems.is_empty()
	var result := {"uid": actor.profile.uid, "approved": approve, "correct": approve == valid, "errors": problems, "anomaly": actor.profile.get("anomaly", false)}
	if approve:
		var seat := _reserve_seat()
		if seat == null:
			return {}
		actor.ticket.is_valid = true
		actor.approve(_station.get_node("GateLane_0"), seat)
		if actor.profile.get("anomaly", false):
			var entity := get_tree().get_first_node_in_group("station_entity")
			if entity: entity.wake()
	else:
		actor.reject()
	var desk := get_tree().get_first_node_in_group("booth_desk")
	actor.document_handover_left = 1.25 if desk and desk.stamping else 0.85
	reviewed += 1
	if result.correct:
		correct += 1
		GameManager.reward_once("ticket/" + str(actor.profile.uid), 3)
	decisions.append(result)
	_queue.pop_front()
	counter_ready = false
	current_actor = null
	_advance_after_clear(actor)
	_update_objective()
	decision_recorded.emit(result)
	return result


func _reserve_seat() -> Marker3D:
	var platform_first := reviewed % 2 == 0
	for pass_index in range(2):
		for marker in _seats:
			var platform := marker.global_position.z > 10
			if platform != (platform_first if pass_index == 0 else not platform_first): continue
			if not marker.get_meta("reserved", false):
				marker.set_meta("reserved", true)
				return marker
	return null


func _update_objective() -> void:
	GameManager.objectives["check_tickets"] = {"text": "Inspect passengers at the booth (%d/%d)." % [reviewed, total_cases()], "done": reviewed >= total_cases()}
	GameManager.objectives_changed.emit()


func _reset() -> void:
	_queue_revision += 1
	_queue_release = null
	ui.close_desk()
	for actor in actors:
		if is_instance_valid(actor):
			actor.set_physics_process(false)
			_station.remove_child(actor)
			actor.queue_free()
	for marker in _seats:
		if is_instance_valid(marker):
			marker.set_meta("reserved", false)
			marker.set_meta("occupied", false)
	actors.clear()
	_queue.clear()
	_seats.clear()
	decisions.clear()
	current_actor = null
	counter_ready = false
	started = false
	reviewed = 0
	correct = 0
	round_number = 0
	_wave_timer = 0


func _end_shift() -> void:
	ui.close_desk()
	for actor in actors:
		if is_instance_valid(actor):
			actor.set_physics_process(false)


func save_state() -> Dictionary:
	var people: Array = []
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var points: Array = []
		for point in actor._points:
			points.append([point.x, point.y, point.z])
		people.append({"uid": actor.profile.uid, "phase": actor.phase, "position": [actor.position.x, actor.position.y, actor.position.z], "yaw": actor.rotation.y, "points": points, "wait": actor._wait, "authorized": actor._authorized, "ticket_valid": actor.ticket.is_valid, "ticket_used": actor.ticket.used, "seat": str(_station.get_path_to(actor.seat_anchor)) if is_instance_valid(actor.seat_anchor) else "", "danger_timer": actor.danger_timer, "train_offset": [actor.train_offset.x, actor.train_offset.y, actor.train_offset.z], "handover": actor.document_handover_left, "follow_peer": actor.follow_peer, "idle": actor._idle_time, "visit": actor._visit_kind, "boarding_pending": actor._boarding_pending, "path_pending": actor._path_pending, "queue_destination": [actor._queue_destination.x, actor._queue_destination.y, actor._queue_destination.z], "pre_plan": actor.pre_ticket_plan, "history": actor.activity_history, "pre_seated": actor._pre_ticket_seated, "entry_delay": actor._entry_delay, "visit_target": [actor._visit_target.x, actor._visit_target.y, actor._visit_target.z], "visit_elapsed": actor._visit_elapsed})
	var queue_ids: Array = []
	for actor in _queue:
		queue_ids.append(actor.profile.uid)
	return {"queue_release": _queue_release.profile.uid if is_instance_valid(_queue_release) else "", "movement_revision": 4, "started": started, "reviewed": reviewed, "correct": correct, "decisions": decisions, "people": people, "queue": queue_ids, "current": current_actor.profile.uid if is_instance_valid(current_actor) else "", "ready": counter_ready, "rounds": round_limit, "round": round_number, "wave_timer": _wave_timer, "people_per_round": passengers_per_round, "routines": pre_ticket_routines_enabled}


func load_state(data: Dictionary) -> void:
	_reset()
	# Old saves may contain visitors spawned before the logbook was signed.
	if not GameManager.signed_in: return
	started = bool(data.get("started", false))
	reviewed = int(data.get("reviewed", 0))
	correct = int(data.get("correct", 0))
	round_limit = int(data.get("rounds", 3))
	passengers_per_round = clampi(int(data.get("people_per_round", 3)), 3, 12)
	pre_ticket_routines_enabled = bool(data.get("routines", true))
	if not started and not data.has("people_per_round"): passengers_per_round = 3 if GameManager.night == 1 else 8
	round_number = int(data.get("round", 0))
	_wave_timer = float(data.get("wave_timer", 0))
	decisions.assign(data.get("decisions", []))
	if not started:
		return
	for marker in get_tree().get_nodes_in_group("passenger_seats"):
		if str(marker.get_parent().name).begins_with("PlatformBench_") or str(marker.get_parent().name).begins_with("WaitingBench_"):
			_seats.append(marker)
	var people_by_id: Dictionary = {}
	for person: Dictionary in data.get("people", []):
		var profile: Dictionary = {}
		for wave in range(round_limit):
			for candidate in Cases.for_night(GameManager.night, wave, passengers_per_round):
				if candidate.uid == person.uid:
					profile = candidate
		if profile.is_empty():
			continue
		var actor := Actor.new()
		actor.name = "Passenger_" + profile.uid
		actor.profile = profile
		actor.ticket = Ticket.make(profile.ticket_number, profile.ticket_name, profile.destination, bool(person.get("ticket_valid", false)))
		actor.ticket.used = bool(person.get("ticket_used", false))
		var pos: Array = person.position
		actor.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		actor.rotation.y = float(person.yaw)
		actor.reached_counter.connect(_on_counter_ready)
		actor.ready_to_queue.connect(_request_ticket)
		_station.add_child(actor)
		actor.phase = str(person.phase)
		if actor.phase == "BOARDED": actor.visual.set_seated(true, 0.49)
		actor.gate = _station.get_node("GateLane_0")
		actor._authorized = bool(person.get("authorized", false))
		var train_offset: Array = person.get("train_offset", [0, 0.35, -0.2])
		actor.train_offset = Vector3(float(train_offset[0]), float(train_offset[1]), float(train_offset[2]))
		if actor.phase in ["BOARDED", "ENTER_TRAIN"]:
			actor.collision_layer = 0
			actor.collision_mask = 0
		actor.follow_peer = int(person.get("follow_peer", 1))
		actor.document_handover_left = float(person.get("handover", 0))
		actor._wait = float(person.get("wait", 0.0))
		actor._idle_time = float(person.get("idle", 20))
		actor._visit_kind = str(person.get("visit", ""))
		actor._boarding_pending = bool(person.get("boarding_pending", false))
		actor.pre_ticket_plan.assign(person.get("pre_plan", []))
		actor.activity_history.assign(person.get("history", []))
		actor._pre_ticket_seated = bool(person.get("pre_seated", false))
		actor._entry_delay = float(person.get("entry_delay", 0))
		var visit_target: Array = person.get("visit_target", [0, 0, 0])
		actor._visit_target = Vector3(float(visit_target[0]), float(visit_target[1]), float(visit_target[2]))
		actor._visit_elapsed = clampf(float(person.get("visit_elapsed", 0)), 0, 90)
		actor._path_pending = bool(person.get("path_pending", false))
		var queue_destination: Array = person.get("queue_destination", [0, 0.35, 4])
		actor._queue_destination = Vector3(float(queue_destination[0]), float(queue_destination[1]), float(queue_destination[2]))
		for point in person.get("points", []):
			actor._points.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		# Old navigation waypoints may cross the wall where a doorway used to be.
		if int(data.get("movement_revision", 0)) < 4 and not actor._points.is_empty() and actor.phase not in ["CROSS_GATE", "ENTER_TRAIN", "BOARDED"]:
			actor._queue_destination = actor._points.back()
			actor._path_pending = true
		var seat_path: String = person.get("seat", "")
		if not seat_path.is_empty():
			actor.seat_anchor = _station.get_node_or_null(seat_path)
			if actor.seat_anchor:
				actor.seat_anchor.set_meta("reserved", true)
				if actor.phase == "PRE_IDLE" and actor._pre_ticket_seated:
					actor._sit()
					actor.phase = "PRE_IDLE"
				elif actor.phase == "SEATED":
					actor._sit()
				elif actor.phase == "DANGER":
					actor.phase = "SEATED"
					actor._sit()
					actor.put_in_danger()
					actor.danger_timer = float(person.get("danger_timer", 20))
		actors.append(actor)
		people_by_id[profile.uid] = actor
	for uid in data.get("queue", []):
		if people_by_id.has(uid):
			_queue.append(people_by_id[uid])
	current_actor = people_by_id.get(data.get("current", ""))
	counter_ready = bool(data.get("ready", false)) and is_instance_valid(current_actor)
	if counter_ready:
		current_actor._counter_announced = true
	var departing: Node = people_by_id.get(str(data.get("queue_release", "")))
	if departing: _advance_after_clear.call_deferred(departing)


func _advance_after_clear(actor: Node) -> void:
	_queue_release = actor
	var revision := _queue_revision
	while is_instance_valid(actor) and Vector2(actor.position.x + 5.85, actor.position.z - 4.0).length() < 1.6:
		await get_tree().physics_frame
		if revision != _queue_revision: return
	_queue_release = null
	_reposition_queue()
