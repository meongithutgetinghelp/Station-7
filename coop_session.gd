extends Node

## Host owns world simulation. A crew shares funds, tools and campaign progress.
signal lobby_changed
signal status_changed(message: String)
signal world_started

const MAX_PLAYERS := 4
const DEFAULT_PORT := 27017
const PROTOCOL := 6
const Avatar = preload("res://coop_avatar.gd")
var active: bool = false
var running: bool = false
var world_live: bool = false
var roster: Dictionary = {}
var status: String = ""
var generation: int = 0
var session_token: String = ""
var interaction_peer: int = 1
var _ready_peers: Dictionary = {}
var _avatars: Dictionary = {}
var _station: Node3D
var _loading_time: float = 0
var _connect_time: float = 0
var _pose_time: float = 0
var _state_time: float = 0
var _motion_time: float = 0
var _manifest_ids: Array = []
var _last_state: Dictionary = {}
var _last_action: Dictionary = {}
var _hold_started: Dictionary = {}
var _last_pose: Dictionary = {}
var _wires: Dictionary = {}
var _last_motion_seq: int = 0
var _motion_seq: int = 0
var _world_seed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func() -> void: leave("Could not connect. Check address, port and firewall."))
	multiplayer.server_disconnected.connect(func() -> void: leave("The host left the session."))



func _forward_notice(message: String) -> void:
	if active and running and world_live and multiplayer.is_server(): _notice.rpc(generation, message)


@rpc("authority", "call_remote", "reliable")
func _notice(epoch: int, message: String) -> void:
	if epoch == generation and world_live: GameManager.notice_posted.emit(message)


func is_client() -> bool:
	return active and not multiplayer.is_server()


func simulation_blocked() -> bool:
	return active and (is_client() or not world_live)


func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	if port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1, 3)
	if error != OK:
		_set_status("Could not host on UDP port %d: %s" % [port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	session_token = str(Time.get_unix_time_from_system()) + ":" + str(randi())
	GameManager.notice_posted.connect(_forward_notice)
	roster = {1: {"ready": true}}
	_set_status("Hosting on UDP port %d. Invite up to three teammates." % port)
	lobby_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	if address.strip_edges().is_empty() or port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port, 3)
	if error != OK:
		_set_status("Could not join: " + error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	_connect_time = 0
	_set_status("Connecting…")
	return OK


func leave(message: String = "") -> void:
	var was_running := running
	if GameManager.notice_posted.is_connected(_forward_notice): GameManager.notice_posted.disconnect(_forward_notice)
	active = false
	session_token = ""
	running = false
	world_live = false
	_station = null
	roster.clear()
	_ready_peers.clear()
	_avatars.clear()
	_last_pose.clear()
	_last_action.clear()
	_hold_started.clear()
	_wires.clear()
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if not message.is_empty(): _set_status(message)
	lobby_changed.emit()
	if was_running:
		get_tree().paused = false
		get_tree().call_deferred("change_scene_to_file", "res://main_menu.tscn")


func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)


func _connected() -> void:
	_hello.rpc_id(1, PROTOCOL)


func _peer_connected(id: int) -> void:
	if active and multiplayer.is_server() and (running or roster.size() >= MAX_PLAYERS):
		multiplayer.multiplayer_peer.disconnect_peer(id)


@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int) -> void:
	if not active or not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL or running or roster.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	roster[id] = {"ready": false}
	_sync_roster.rpc(roster)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_roster(value: Dictionary) -> void:
	if not active: return
	roster = value
	_set_status("Lobby: %d / 4 staff" % roster.size())
	if is_instance_valid(_station): _refresh_avatars()
	lobby_changed.emit()


func set_ready(value: bool) -> void:
	if not active or running: return
	if is_client(): _set_ready.rpc_id(1, value)
	else:
		roster[1].ready = value
		_sync_roster.rpc(roster)
		lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _set_ready(value: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not active or not multiplayer.is_server() or running or not roster.has(id): return
	roster[id].ready = value
	_sync_roster.rpc(roster)
	lobby_changed.emit()


func can_start() -> bool:
	if not active or is_client() or running or roster.is_empty(): return false
	for entry in roster.values():
		if not entry.ready: return false
	return true


func start_shift(saved: bool = false) -> bool:
	if not can_start(): return false
	if saved:
		var data := GameManager.read_checkpoint()
		if data.is_empty():
			GameManager.notice_posted.emit("No readable checkpoint found. Start a new campaign.")
			return false
		GameManager.night = clampi(int(data.core.get("night", 1)), 1, 7)
	else: GameManager.new_campaign()
	_begin_shift(GameManager.night, saved)
	return true


func restart_shift(next_night: bool = false, saved: bool = false) -> void:
	if not active or is_client(): return
	var number: int = GameManager.night + (1 if next_night else 0)
	if saved:
		var data := GameManager.read_checkpoint()
		if data.is_empty():
			GameManager.notice_posted.emit("No readable checkpoint found. Retry this night.")
			return
		number = clampi(int(data.core.get("night", 1)), 1, 7)
	if next_night: GameManager.record_night()
	GameManager.start_night(number)
	_begin_shift(GameManager.night, saved)


func _begin_shift(number: int, saved: bool) -> void:
	generation += 1
	_world_seed = randi()
	_enter_shift.rpc(generation, number, _world_seed)
	_enter_shift(generation, number, _world_seed)
	GameManager.pending_load = saved


@rpc("authority", "call_remote", "reliable")
func _enter_shift(epoch: int, number: int, station_seed: int) -> void:
	generation = epoch
	running = true
	world_live = false
	_loading_time = 0
	_ready_peers.clear()
	_avatars.clear()
	_manifest_ids.clear()
	_last_state.clear()
	_last_pose.clear()
	_last_action.clear()
	_hold_started.clear()
	_wires.clear()
	_last_motion_seq = 0
	_station = null
	seed(station_seed)
	GameManager.start_night(number)
	GameManager.pending_load = false
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://station_builder.tscn")


func attach_world(station: Node3D) -> void:
	if not active or not running: return
	_station = station
	var player := local_player()
	player.add_to_group("crew")
	player.set_meta("peer_id", multiplayer.get_unique_id())
	var ids := roster.keys()
	ids.sort()
	player.position = Vector3(-1.5 + ids.find(multiplayer.get_unique_id()), 0.5, -14)
	_refresh_avatars()
	# Allow the host's deferred checkpoint load to finish before declaring readiness.
	await get_tree().process_frame
	if not is_instance_valid(_station): return
	if is_client(): _scene_ready.rpc_id(1, generation)
	else:
		_ready_peers[1] = true
		_check_ready()


@rpc("any_peer", "call_remote", "reliable")
func _scene_ready(epoch: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not active or not multiplayer.is_server() or epoch != generation or not roster.has(id): return
	_ready_peers[id] = true
	_check_ready()


func _check_ready() -> void:
	if not is_instance_valid(_station): return
	for id in roster:
		if not _ready_peers.has(id): return
	if not world_live:
		_release_world.rpc(generation)
		_release_world(generation)
		_broadcast_structure()
		_broadcast_state()


@rpc("authority", "call_remote", "reliable")
func _release_world(epoch: int) -> void:
	if epoch != generation: return
	world_live = true
	_set_status("Co-op shift started — %d staff" % roster.size())
	world_started.emit()


func local_player() -> Node3D:
	return get_tree().get_first_node_in_group("player")


func player_for(id: int) -> Node3D:
	return local_player() if id == multiplayer.get_unique_id() else _avatars.get(id)


func interacting_player() -> Node3D:
	return player_for(interaction_peer) if active else local_player()


func crew() -> Array:
	var people: Array = []
	if local_player(): people.append(local_player())
	for avatar in _avatars.values():
		if is_instance_valid(avatar): people.append(avatar)
	return people


func _refresh_avatars() -> void:
	if not is_instance_valid(_station): return
	for id in _avatars.keys():
		if not roster.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)
	var ids := roster.keys()
	ids.sort()
	for id in roster:
		if id == multiplayer.get_unique_id() or _avatars.has(id): continue
		var avatar := Avatar.new()
		avatar.name = "Crew_%d" % id
		avatar.peer_id = id
		avatar.position = Vector3(-1.5 + ids.find(id), 0.5, -14)
		avatar.target_position = avatar.position
		_station.add_child(avatar)
		avatar.stepped.connect(_crew_step)
		_avatars[id] = avatar


func _crew_step(point: Vector3, radius: float) -> void:
	if active and world_live and multiplayer.is_server():
		get_tree().call_group("entity_hearing", "hear_noise", point, radius)


func _peer_disconnected(id: int) -> void:
	if not active: return
	roster.erase(id)
	_ready_peers.erase(id)
	_last_pose.erase(id)
	_hold_started.erase(id)
	_wires.erase(id)
	if is_instance_valid(_station): _refresh_avatars()
	if multiplayer.is_server():
		_sync_roster.rpc(roster)
		if running: _check_ready()
		if world_live:
			GameManager.refresh_staff_sign_in()
			_broadcast_state()
	lobby_changed.emit()


func _process(delta: float) -> void:
	if not active: return
	if not running:
		_connect_time += delta
		if is_client() and roster.is_empty() and _connect_time > 15: leave("Connection timed out or lobby is full/already playing.")
		return
	if not is_instance_valid(_station): return
	if not world_live:
		_loading_time += delta
		if _loading_time > 45: leave("A teammate could not load the station. Rehost and try again.")
		return
	_pose_time += delta
	if _pose_time >= 0.05:
		_pose_time = 0
		if is_client(): _submit_pose.rpc_id(1, generation, _pose(local_player()))
		else: _broadcast_crew()
	if is_client():
		_interpolate(delta)
		return
	_motion_time += delta
	_state_time += delta
	if _motion_time >= 0.1:
		_motion_time = 0
		_broadcast_structure()
		_broadcast_motion()
	if _state_time >= 0.25:
		_state_time = 0
		_broadcast_state()


func _pose(player: Node3D) -> Dictionary:
	return {"p": player.position, "y": player.rotation.y, "pitch": player.camera.rotation.x, "c": player.is_crouching, "s": player.is_sprinting, "f": player.is_flashlight_on}


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(epoch: int, pose: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not active or not multiplayer.is_server() or not world_live or epoch != generation or not roster.has(id): return
	var avatar: Node3D = _avatars.get(id)
	var point = pose.get("p")
	if not avatar or not point is Vector3 or not point.is_finite(): return
	if point.x < -28 or point.x > 43 or point.z < -40 or point.z > 19 or point.y < -1 or point.y > 12: return
	var yaw := float(pose.get("y", 0))
	var pitch := float(pose.get("pitch", 0))
	if not is_finite(yaw) or not is_finite(pitch): return
	# Locally predicted movement; limit displacement and query solid walls on the host.
	var now := Time.get_ticks_msec()
	var age: float = minf(0.5, float(now - int(_last_pose.get(id, now - 100))) / 1000.0)
	_last_pose[id] = now
	if avatar.position.distance_to(point) > 1.0 + 10 * age:
		_correct_position.rpc_id(id, generation, avatar.position)
		return
	var query := PhysicsRayQueryParameters3D.create(avatar.position + Vector3.UP * 0.8, point + Vector3.UP * 0.8, 1 | 4)
	if not _station.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_correct_position.rpc_id(id, generation, avatar.position)
		return
	pose["pitch"] = clampf(pitch, -1.5, 1.5)
	avatar.apply_pose(pose, true)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _correct_position(epoch: int, point: Vector3) -> void:
	if epoch == generation and local_player(): local_player().position = point


func _broadcast_crew() -> void:
	var poses := {1: _pose(local_player())}
	for id in _avatars: poses[id] = _pose(_avatars[id])
	_crew_poses.rpc(generation, poses)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _crew_poses(epoch: int, poses: Dictionary) -> void:
	if epoch != generation or not is_instance_valid(_station): return
	for id in poses:
		if _avatars.has(id): _avatars[id].apply_pose(poses[id])


func _broadcast_structure() -> void:
	var director := _station.get_node("PassengerService")
	var ids: Array = []
	var people: Array = []
	for actor in director.actors:
		if is_instance_valid(actor):
			ids.append(actor.profile.uid)
			people.append(actor.profile)
	if ids != _manifest_ids:
		_manifest_ids = ids
		_structure.rpc(generation, people)


@rpc("authority", "call_remote", "reliable")
func _structure(epoch: int, people: Array) -> void:
	if epoch != generation or not is_instance_valid(_station): return
	var director := _station.get_node("PassengerService")
	var keep: Array = []
	for profile: Dictionary in people:
		var uid: String = profile.uid
		keep.append(uid)
		var actor := _station.get_node_or_null("Passenger_" + uid)
		if actor: continue
		actor = preload("res://passenger_actor.gd").new()
		actor.name = "Passenger_" + uid
		actor.profile = profile
		actor.ticket = preload("res://ticket.gd").make(profile.ticket_number, profile.ticket_name, profile.destination, false)
		_station.add_child(actor)
		director.actors.append(actor)
	for actor in director.actors.duplicate():
		if actor.profile.uid not in keep:
			director.actors.erase(actor)
			_station.remove_child(actor)
			actor.queue_free()


func _broadcast_motion() -> void:
	var people: Array = []
	for actor in _station.get_node("PassengerService").actors:
		if is_instance_valid(actor):
			people.append({"id": actor.profile.uid, "p": actor.position, "y": actor.rotation.y, "phase": actor.phase, "visible": actor.visible, "seated": actor.phase in ["SEATED", "DANGER", "BOARDED"] or actor._pre_ticket_seated, "seat": str(_station.get_path_to(actor.seat_anchor)) if is_instance_valid(actor.seat_anchor) else ""})
	var entity := _station.get_node("PassengerEntity")
	var train := _station.get_node("TrainService")
	var entity_state: Dictionary = entity.network_state()
	# Keep unreliable packets below ENet's MTU, even with all 24 passengers.
	for offset in range(0, maxi(1, people.size()), 3):
		_motion_seq += 1
		_motion.rpc(generation, _motion_seq, people.slice(offset, offset + 3), entity_state, train.save_state())


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _motion(epoch: int, sequence: int, people: Array, entity_data: Dictionary, train_data: Dictionary) -> void:
	if epoch != generation or sequence <= _last_motion_seq or not is_instance_valid(_station): return
	_last_motion_seq = sequence
	for person: Dictionary in people:
		var actor := _station.get_node_or_null("Passenger_" + str(person.id))
		if not actor: continue
		var seated: bool = bool(person.seated)
		if str(person.phase) == "BOARDED":
			actor.visual.set_seated(true, 0.49)
		elif seated != bool(actor.get_meta("net_seated", false)):
			if not seated and is_instance_valid(actor.seat_anchor): actor._stand_up()
			actor.seat_anchor = _station.get_node_or_null(str(person.seat)) if not str(person.seat).is_empty() else null
			if seated and is_instance_valid(actor.seat_anchor): actor._sit()
		actor.set_meta("net_seated", seated)
		actor.phase = person.phase
		actor.visible = person.visible
		actor._danger_label.visible = person.phase in ["DANGER", "FOLLOW"]
		actor.set_meta("net_position", person.p)
		actor.set_meta("net_yaw", person.y)
	var entity := _station.get_node("PassengerEntity")
	entity.apply_network_state(entity_data)
	var train := _station.get_node("TrainService")
	if train.phase != train_data.phase: train.load_state(train_data)
	train.set_meta("net_x", train_data.x)
	train.boarded_count = train_data.boarded


func _interpolate(delta: float) -> void:
	var factor := minf(1, delta * 14)
	for actor in get_tree().get_nodes_in_group("passenger_actor") + get_tree().get_nodes_in_group("station_entity"):
		if actor.has_meta("net_position"):
			actor.position = actor.position.lerp(actor.get_meta("net_position"), factor)
			actor.rotation.y = lerp_angle(actor.rotation.y, float(actor.get_meta("net_yaw")), factor)
	var train := _station.get_node("TrainService")
	if train.has_meta("net_x"): train.vehicle.position.x = lerpf(train.vehicle.position.x, float(train.get_meta("net_x")), factor)


func _broadcast_state() -> void:
	var director := _station.get_node("PassengerService")
	var jobs: Dictionary = _station.get_node("StationJobs").save_state()
	jobs.erase("timer")
	jobs.erase("next_mess_delay")
	var objects: Dictionary = {}
	for node in get_tree().get_nodes_in_group("save_participant"):
		if node is Gate or node is InteractiveDoor: objects[str(_station.get_path_to(node))] = node.save_state()
	var services := _station.get_node("StationServices")
	var state := {"night": GameManager.night, "time": GameManager.time_minutes, "state": GameManager.state, "powered": GameManager.powered, "signed": GameManager.signed_in, "signed_staff": GameManager.signed_staff.duplicate(), "objectives": GameManager.objectives.duplicate(true), "inventory": GameManager.inventory.duplicate(), "balance": GameManager.balance, "identified": GameManager.entity_identified, "rescued": GameManager.rescued_passengers, "lost": GameManager.lost_passengers, "campaign": GameManager.campaign.duplicate(), "jobs": jobs, "objects": objects, "reviewed": director.reviewed, "correct": director.correct, "round": director.round_number, "per_round": director.passengers_per_round, "ready": director.counter_ready, "current": director.current_actor.profile.uid if is_instance_valid(director.current_actor) else "", "stock": services.stock.duplicate(), "till": services.till_balance, "entity_banished": _station.get_node("PassengerEntity").banished, "entity_state": _station.get_node("PassengerEntity").network_state(), "boarded": _station.get_node("TrainService").boarded_count}
	state["last_verdict"] = director.decisions.back().duplicate(true) if not director.decisions.is_empty() else {}
	state["events"] = _station.get_node("NightEvents").save_state()
	state["pacing"] = _station.get_node("HorrorPacing").save_state()
	state["dialogues"] = _station.get_node("PassengerDialogueEvents").save_state()
	_state.rpc(generation, state)


@rpc("authority", "call_remote", "reliable")
func _state(epoch: int, data: Dictionary) -> void:
	if epoch != generation or not is_instance_valid(_station): return
	var previous_state := GameManager.state
	var power_changed := GameManager.powered != bool(data.powered)
	var objectives_changed: bool = GameManager.objectives != data.objectives
	GameManager.night = data.night
	GameManager.time_minutes = data.time
	GameManager.state = data.state
	GameManager.powered = data.powered
	GameManager.signed_in = data.signed
	GameManager.signed_staff.assign(data.get("signed_staff", []))
	GameManager.objectives = data.objectives
	GameManager.inventory = data.inventory
	GameManager.balance = data.balance
	GameManager.entity_identified = data.identified
	GameManager.rescued_passengers = data.rescued
	GameManager.lost_passengers = data.lost
	GameManager.campaign = data.campaign
	GameManager.loading = true
	if _last_state.get("jobs") != data.jobs:
		_station.get_node("StationJobs").load_state(data.jobs)
		_station._apply_station_power()
	if data.has("events") and _last_state.get("events") != data.events:
		_station.get_node("NightEvents").load_state(data.events)
	if data.has("dialogues") and _last_state.get("dialogues") != data.dialogues:
		_station.get_node("PassengerDialogueEvents").load_state(data.dialogues)
	if data.has("pacing") and _last_state.get("pacing") != data.pacing:
		_station.get_node("HorrorPacing").apply_network_state(data.pacing)
	for path in data.objects:
		var node := _station.get_node_or_null(path)
		if node: node.load_state(data.objects[path])
	var director := _station.get_node("PassengerService")
	director.started = bool(data.signed)
	director.reviewed = data.reviewed
	director.correct = data.correct
	director.round_number = data.round
	director.passengers_per_round = data.per_round
	var current_id: String = data.current
	var old_id: String = director.current_actor.profile.uid if is_instance_valid(director.current_actor) else ""
	director.current_actor = _station.get_node_or_null("Passenger_" + current_id) if not current_id.is_empty() else null
	director.counter_ready = data.ready and is_instance_valid(director.current_actor)
	if director.counter_ready and old_id != current_id: director.passenger_ready.emit(director.current_profile())
	var services := _station.get_node("StationServices")
	var stock_changed: bool = services.stock != data.stock
	services.stock = data.stock
	services.till_balance = data.till
	_station.get_node("PassengerEntity").apply_network_state(data.entity_state)
	_station.get_node("TrainService").boarded_count = data.boarded
	GameManager.loading = false
	if services.shop.is_open and stock_changed: services.open_shop()
	if services.phone.is_open and (_last_state.get("balance") != data.balance or _last_state.get("inventory") != data.inventory): services.open_phone()
	if data.has("last_verdict") and _last_state.get("last_verdict") != data.last_verdict:
		_station.get_node("BoothDesk")._decision_recorded(data.last_verdict)
	_last_state = data
	GameManager.clock_changed.emit()
	if power_changed: GameManager.power_changed.emit(GameManager.powered)
	if objectives_changed: GameManager.objectives_changed.emit()
	if previous_state != GameManager.state:
		if GameManager.state == GameManager.NightState.DEAD: GameManager.player_died.emit()
		elif GameManager.state == GameManager.NightState.SHIFT_OVER: GameManager.shift_finished.emit()


## UI-only interactions stay on the caller. World mutations are requests to the host.
func local_interaction(target: Node) -> bool:
	if target.get_parent().is_in_group("handwritten_note"): return true
	if target.get_parent().is_in_group("booth_desk_local"): return true
	var conversations := get_tree().get_first_node_in_group("passenger_dialogue_events")
	if conversations and target.get_parent().is_in_group("passenger_actor") and conversations.has_conversation(target.get_parent()): return true
	var name_text := str(target.get_parent().name)
	return name_text in ["TB_InspectionConsole", "TB_Keyboard", "TB_Chair_Seat", "ShopCounter", "ChargingCounter", "SecurityTerminal", "ElecPanel_1", "EntityLetter", "ArchivedDepartureLedger"] or target.get_parent().is_in_group("cctv_console_targets")


func request_interaction(target: Node) -> void:
	if not world_live or not is_instance_valid(_station): return
	var path := str(_station.get_path_to(target))
	if is_client(): _interact.rpc_id(1, generation, path)
	else: _perform_interaction(1, path)


func begin_hold(target: Node) -> void:
	if active and is_client() and world_live:
		_begin_hold.rpc_id(1, generation, str(_station.get_path_to(target)))


@rpc("any_peer", "call_remote", "reliable")
func _begin_hold(epoch: int, path: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not active or not multiplayer.is_server() or epoch != generation or not roster.has(id): return
	var target := _safe_target(path)
	if target and _in_reach(id, target): _hold_started[id] = {"path": path, "at": Time.get_ticks_msec()}


@rpc("any_peer", "call_remote", "reliable")
func _interact(epoch: int, path: String) -> void:
	if not active or not multiplayer.is_server() or epoch != generation: return
	_perform_interaction(multiplayer.get_remote_sender_id(), path)


func _safe_target(path: String) -> Node:
	if not is_instance_valid(_station) or path.begins_with("/") or ".." in path or path.length() > 200: return null
	var target := _station.get_node_or_null(path)
	return target if target and target.get_script() == preload("res://interactable.gd") else null


func _in_reach(id: int, target: Node) -> bool:
	var player := player_for(id)
	var body := target.get_parent() as Node3D
	if not player or not body: return false
	var distance: float = player.camera.global_position.distance_to(body.global_position)
	return distance <= 4.5


func _perform_interaction(id: int, path: String) -> void:
	if not world_live or not roster.has(id): return
	if GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]: return
	var target := _safe_target(path)
	if not target or not _in_reach(id, target) or local_interaction(target) or not target.enabled: return
	var now := Time.get_ticks_msec()
	if now - int(_last_action.get(id, -1000)) < 150: return
	if id != 1 and target.hold_seconds > 0:
		var held: Dictionary = _hold_started.get(id, {})
		if held.get("path") != path or now - int(held.get("at", now)) < target.hold_seconds * 1000 - 100: return
	_last_action[id] = now
	_hold_started.erase(id)
	interaction_peer = id
	target.action.call()
	interaction_peer = 1
	_broadcast_state()
	if str(target.get_parent().name).begins_with("Clue_") and id != 1: _action_result_to(id, "journal", true)


func request_action(kind: String, argument: Variant = null) -> void:
	if not active or not world_live: return
	if is_client(): _action.rpc_id(1, generation, kind, argument)
	else: _perform_action(1, kind, argument)


@rpc("any_peer", "call_remote", "reliable")
func _action(epoch: int, kind: String, argument: Variant) -> void:
	if active and multiplayer.is_server() and epoch == generation:
		_perform_action(multiplayer.get_remote_sender_id(), kind, argument)


func _at_monitor(player: Node3D) -> bool:
	var targets: Array = get_tree().get_nodes_in_group("cctv_console_targets")
	targets.append(_station.get_node("Rooms/Security/SecurityTerminal"))
	for target in targets:
		if player.global_position.distance_to(target.global_position) < 6: return true
	return false


func _perform_action(id: int, kind: String, argument: Variant) -> void:
	if not roster.has(id) or not world_live: return
	if GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]: return
	var player := player_for(id)
	if not player: return
	if kind == "pacing_view":
		if argument is bool and _at_monitor(player): _station.get_node("HorrorPacing").observe(id, argument)
		return # Cosmetic heartbeats cannot throttle purchases/verdicts or force state broadcasts.
	var now := Time.get_ticks_msec()
	if now - int(_last_action.get(id, -1000)) < 150 and kind not in ["wire", "restore"]: return
	_last_action[id] = now
	var services := _station.get_node("StationServices")
	match kind:
		"pacing_archive":
			var pacing := _station.get_node("HorrorPacing")
			if GameManager.night < 3 or player.global_position.distance_to(pacing._archive.global_position) > 4.5: return
			pacing.remember("archive")
		"pacing_note":
			if not argument is int: return
			for note in get_tree().get_nodes_in_group("handwritten_note"):
				if int(note.get_meta("note_id", -1)) == argument and player.global_position.distance_to(note.global_position) <= 4.5:
					_station.get_node("HorrorPacing").remember("note/%d" % argument)
					break
		"passenger_dialogue":
			if not argument is Dictionary: return
			_station.get_node("PassengerDialogueEvents").finish_dialogue(str(argument.get("uid", "")), int(argument.get("token", -1)), id)
		"ticket":
			if not argument is Dictionary or player.position.x > -7.125 or player.position.x < -16 or player.position.z < 1 or player.position.z > 7: return
			var director := _station.get_node("PassengerService")
			if director.current_profile().get("uid", "") != argument.get("uid", ""): return
			var result: Dictionary = director.decide(bool(argument.get("approve", false)))
			_action_result_to(id, "ticket", result)
		"identify":
			if not _at_monitor(player): return
			interaction_peer = id
			_station.get_node("StationJobs")._identify()
			interaction_peer = 1
		"cctv":
			if not _at_monitor(player) or not argument is Dictionary: return
			var monitor = services.cctv
			var feed: int = int(argument.get("feed", -1))
			var angles = argument.get("rotation")
			if feed < 0 or feed >= monitor.feeds.size() or not angles is Vector3 or not angles.is_finite(): return
			var old_feed: int = monitor.selected
			var camera: Camera3D = monitor.feeds[feed].camera
			var old_angles: Vector3 = camera.rotation
			monitor.selected = feed
			camera.rotation = Vector3(clampf(angles.x, -1.5, 1.5), angles.y, 0)
			monitor.mark_suspicious()
			_action_result_to(id, "cctv", monitor._feedback.text)
			camera.rotation = old_angles
			monitor.selected = old_feed
		"purchase":
			if player.position.distance_to(_station.get_node("ShopCounter").position) > 5: return
			_action_result_to(id, "purchase", services.purchase(str(argument)))
			if id == 1 and services.shop.is_open: services.open_shop()
		"consume":
			var item := str(argument)
			if item not in ["food", "drink"] or not GameManager.has_item(item): return
			GameManager.inventory[item] -= 1
			_action_result_to(id, "consume", 60 if item == "food" else 30)
		"battery":
			if not GameManager.has_item("battery"): return
			GameManager.inventory.battery -= 1
			_action_result_to(id, "battery", true)
		"wire":
			if not argument is int or argument < 0 or argument > 2 or player.position.distance_to(_station.get_node("ElecPanel_1").position) > 5: return
			if not _wires.has(id): _wires[id] = []
			if argument not in _wires[id]: _wires[id].append(argument)
		"power_on":
			if player.position.distance_to(_station.get_node("ElecPanel_1").position) > 5: return
			GameManager.turn_on_power()
		"restore":
			if player.position.distance_to(_station.get_node("ElecPanel_1").position) > 5 or _wires.get(id, []).size() != 3: return
			_wires.erase(id)
			GameManager.restore_power()
		_:
			return
	_broadcast_state()


func _action_result_to(id: int, kind: String, result: Variant) -> void:
	if id == 1: _action_result(generation, kind, result)
	else: _action_result.rpc_id(id, generation, kind, result)


@rpc("authority", "call_remote", "reliable")
func _action_result(epoch: int, kind: String, result: Variant) -> void:
	if epoch != generation or not is_instance_valid(_station): return
	match kind:
		"cctv": _station.get_node("StationServices").cctv._feedback.text = str(result)
		"journal": _station.get_node("StationJobs").open_journal()
		"ticket": _station.get_node("PassengerService").ui.show_network_decision(result)
		"consume": local_player().current_stamina = minf(local_player().max_stamina, local_player().current_stamina + int(result))
		"battery": local_player().flashlight_charge = 100
		"purchase": GameManager.notice_posted.emit("Purchase complete." if result else "Insufficient funds or item out of stock.")
