extends CharacterBody3D

signal reached_counter(actor: Node)
signal journey_finished(actor: Node, seated: bool)
signal ready_to_queue(actor: Node)

var profile: Dictionary
var ticket: Ticket
var phase: String = "QUEUE"
var walk_speed: float = 2.0
var gate: Gate
var seat_anchor: Marker3D
var _points: Array[Vector3] = []
var _wait: float = 0.0
var _authorized: bool = false
var _counter_announced: bool = false
var visual: Node3D
var _visual_previous := Vector3.ZERO
var _train: Node
var danger_timer: float = 0
var _follow_timer: float = 0
var follow_peer: int = 1
var _follow_destination := Vector3.INF
var _danger_label: Label3D
var _queue_destination := Vector3.ZERO
var _path_pending: bool = false
var _idle_time: float = 20
var _visit_kind: String = ""
var _boarding_pending: bool = false
var pre_ticket_plan: Array[String] = []
var activity_history: Array[String] = []
var _pre_ticket_seated: bool = false
var train_offset := Vector3.ZERO
var document_handover_left := 0.0
var _entry_delay: float = 0
var _visit_target := Vector3.ZERO
var _visit_elapsed := 0.0
var _visit_probe_elapsed := 0.0
var _visit_stalled := 0.0
var _visit_probe_position := Vector3.ZERO
var _navigation_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	add_to_group("passenger_actor")
	collision_layer = preload("res://scripts/collision_layers.gd").ACTORS | preload("res://scripts/collision_layers.gd").PASSENGERS
	collision_mask = preload("res://scripts/collision_layers.gd").SOLID | preload("res://scripts/collision_layers.gd").PASSENGERS
	floor_snap_length = 0.2
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.31
	shape.height = 1.75
	_navigation_query.shape = shape
	_navigation_query.collision_mask = preload("res://scripts/collision_layers.gd").SOLID
	collision.shape = shape
	collision.position.y = 0.875
	add_child(collision)
	_build_person()
	_danger_label = Label3D.new()
	_danger_label.text = "! NEEDS HELP"
	_danger_label.position.y = 2.1
	_danger_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_danger_label.modulate = Color(1, 0.35, 0.2)
	_danger_label.font_size = 40
	_danger_label.pixel_size = 0.005
	_danger_label.visible = false
	add_child(_danger_label)
	preload("res://scripts/interactable.gd").attach(self, _interact, _interaction_prompt)


func _build_person() -> void:
	visual = preload("res://scripts/passenger_visual.gd").new()
	visual.name = "PassengerVisual"
	visual.profile = profile
	add_child(visual)
	_visual_previous = global_position


func _process(delta: float) -> void:
	var conversations := get_tree().get_first_node_in_group("passenger_dialogue_events")
	var talking: bool = conversations != null and conversations.has_conversation(self)
	_danger_label.visible = (talking and not (conversations.reader.is_open and conversations.reader.target_uid == str(profile.get("uid", "")))) or phase in ["DANGER", "FOLLOW"]
	if talking: _danger_label.text = "[E] TALK"
	elif phase == "DANGER": _danger_label.text = "! NEEDS HELP"
	elif phase == "FOLLOW": _danger_label.text = "FOLLOWING — LEAD TO SAFETY"
	if not visual: return
	var distance: float = Vector2(global_position.x - _visual_previous.x, global_position.z - _visual_previous.z).length()
	_visual_previous = global_position
	visual.update_motion(delta, 0.0 if phase == "BOARDED" else minf(4.0, distance / maxf(delta, 0.001)))


func queue_at(point: Vector3, first: bool) -> void:
	phase = "COUNTER" if first else "QUEUE"
	_counter_announced = false
	_queue_destination = point
	_path_pending = true


func begin_visit() -> void:
	phase = "PRE_ENTRY"
	var choices: Array[String] = ["shop", "wait", "bathroom", "wander", "smoking"]
	choices.shuffle()
	pre_ticket_plan.assign(choices.slice(0, randi_range(2, 3)))
	activity_history = ["arrival"]
	_queue_destination = Vector3(0, 0.35, -14)
	_path_pending = true


func _advance_visit() -> void:
	if _pre_ticket_seated:
		_stand_up()
		seat_anchor.set_meta("reserved", false)
		seat_anchor = null
		_pre_ticket_seated = false
	if pre_ticket_plan.is_empty():
		phase = "WANTS_TICKET"
		ready_to_queue.emit(self)
		return
	_visit_kind = pre_ticket_plan.pop_front()
	activity_history.append(_visit_kind)
	phase = "PRE_VISIT"
	_visit_elapsed = 0
	_visit_probe_elapsed = 0
	_visit_stalled = 0
	_visit_probe_position = global_position
	_visit_target = _choose_activity_target(_visit_kind)
	if _visit_kind == "wait":
		for marker in get_tree().get_nodes_in_group("passenger_seats"):
			if str(marker.get_parent().name).begins_with("WaitingBench_") and not marker.get_meta("reserved", false):
				seat_anchor = marker
				marker.set_meta("reserved", true)
				_visit_target = marker.global_position + marker.global_basis.z * 0.75
				break
	_navigate_to(_visit_target)


func wait_for_queue_space() -> void:
	pre_ticket_plan.assign(["wait"])
	_advance_visit()


func approve(lane: Gate, anchor: Marker3D) -> void:
	_path_pending = false
	gate = lane
	seat_anchor = anchor
	if seat_anchor.global_position.z < 10:
		phase = "TO_SEAT"
		_navigate_to(seat_anchor.global_position + seat_anchor.global_basis.z * 0.75)
		_points.push_front(Vector3(-4.85, 0.35, 4.0))
		return
	phase = "TO_GATE"
	_points.assign([Vector3(-4.85, 0.35, 4.0), Vector3(-4.85, 0.35, 8.2), Vector3(gate.global_position.x, 0.35, 8.2), Vector3(gate.global_position.x, 0.35, 9.1)])


func reject() -> void:
	_path_pending = false
	phase = "LEAVING"
	_navigate_to(Vector3(0, 4.67, -36))
	_points.push_front(Vector3(-4.85, 0.35, 4.0))


func _physics_process(delta: float) -> void:
	if Coop.simulation_blocked(): return
	if GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]: return
	if phase == "PRE_VISIT":
		_visit_elapsed += delta
		_visit_probe_elapsed += delta
		if _visit_probe_elapsed >= 4:
			_visit_stalled = _visit_stalled + _visit_probe_elapsed if global_position.distance_to(_visit_probe_position) < 0.25 else 0.0
			_visit_probe_elapsed = 0
			_visit_probe_position = global_position
		if _visit_stalled >= 16 or _visit_elapsed >= 90:
			# Optional shopping/smoking/restroom detours must never hold up inspection.
			# Abandon the detour visibly; no teleport, despawn or forced ticket verdict.
			if is_instance_valid(seat_anchor): seat_anchor.set_meta("reserved", false)
			seat_anchor = null
			_pre_ticket_seated = false
			pre_ticket_plan.clear()
			_points.clear()
			_path_pending = false
			activity_history.append("detour_unavailable")
			phase = "WANTS_TICKET"
			ready_to_queue.emit(self)
			return
	if phase in ["BOARDED", "ENTER_TRAIN"]:
		if not is_instance_valid(_train): _train = get_tree().get_first_node_in_group("train_service")
		if not _train: return
		if phase == "BOARDED":
			global_position = _train.vehicle.to_global(train_offset)
			velocity = Vector3.ZERO
			return
		# Only an admitted passenger follows this supported, level doorway corridor.
		# Keep station-parent identity intact for save files and network snapshots.
		if _points.is_empty():
			_train.board(self)
			return
		var inside: Vector3 = _points[0]
		var direction := inside - global_position
		global_position = global_position.move_toward(inside, walk_speed * delta)
		if direction.length_squared() > 0.001: rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1, delta * 10))
		if global_position.distance_to(inside) < 0.03: _points.pop_front()
		return
	if phase == "BOARD_TRAIN":
		if not is_instance_valid(_train): _train = get_tree().get_first_node_in_group("train_service")
		if not _train or _train.phase != "BOARDING" or _train.elapsed > 34:
			_abandon_boarding()
			return
		if _train and _train.phase == "BOARDING":
			var waiting: Vector3 = _train.queue_point(self)
			if waiting.distance_to(_queue_destination) > 0.05:
				_queue_destination = waiting
				_navigate_to(waiting)
	if document_handover_left > 0:
		document_handover_left = maxf(0, document_handover_left - delta)
		velocity = Vector3.ZERO
		return
	if phase == "PRE_ENTRY" and _entry_delay > 0:
		_entry_delay -= delta
		return
	if _path_pending:
		var navigation := get_tree().get_first_node_in_group("station_navigation")
		if not navigation or not navigation.ready_for_paths: return
		if phase in ["COUNTER", "QUEUE"]:
			_navigate_to(Vector3(-4.95, _queue_destination.y, _queue_destination.z))
			_points.append(_queue_destination)
		else:
			_navigate_to(_queue_destination)
		if _points.is_empty(): return
		_path_pending = false
	if phase == "DANGER":
		if GameManager.night <= 3:
			phase = "SEATED"
			_danger_label.hide()
			return
		danger_timer -= delta
		if danger_timer <= 0:
			GameManager.passenger_lost()
			if is_instance_valid(seat_anchor): seat_anchor.set_meta("reserved", false)
			queue_free()
		return
	if phase == "SEATED":
		_idle_time -= delta
		if _idle_time <= 0 and not profile.get("anomaly", false): _start_activity()
		return
	if phase == "IDLE_ACTIVITY":
		_wait -= delta
		if _wait <= 0:
			phase = "RETURN_SEAT"
			_navigate_to(seat_anchor.global_position + seat_anchor.global_basis.z * 0.75)
		return
	if phase in ["SAFE", "PLATFORM_WAIT"]: return
	if phase == "PRE_IDLE":
		_wait -= delta
		if _wait <= 0: _advance_visit()
		return
	if phase == "FOLLOW":
		# Escorted passengers can exit without reusing their entry ticket.
		if gate and gate.powered and absf(global_position.x - gate.global_position.x) < 0.7 and absf(global_position.z - gate.global_position.z) < 1.7:
			gate.open_lane()
		_follow_timer -= delta
		var player := Coop.player_for(follow_peer) if Coop.active else get_tree().get_first_node_in_group("player") as Node3D
		if not player and Coop.active:
			follow_peer = 1
			player = Coop.player_for(1)
		if player and _follow_timer <= 0:
			_follow_timer = 0.6
			if global_position.distance_to(player.global_position) > 1.4 and (_points.is_empty() or _follow_destination.distance_to(player.global_position) > 0.75):
				_follow_destination = player.global_position
				_navigate_to(_follow_destination)
			if (global_position.x > 16.5 and global_position.z > 0.5 and global_position.z < 4.5) or (global_position.x < -7.5 and global_position.z > 1.5 and global_position.z < 6.5):
				phase = "SAFE"
				if is_instance_valid(seat_anchor): seat_anchor.set_meta("reserved", false)
				_danger_label.visible = false
				GameManager.rescued_passengers += 1
				GameManager.complete_objective("save_passenger")
				GameManager.notice_posted.emit("Passenger brought to safety.")
				return
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	velocity.x = 0
	velocity.z = 0
	if phase in ["TO_GATE", "GATE_WAIT", "CROSS_GATE"] and not get_node("/root/GameManager").powered:
		move_and_slide()
		return
	if phase == "GATE_WAIT":
		if not _authorized:
			_authorized = gate.scan_ticket(ticket)
			_wait = 0.4
		elif gate.state != Gate.State.OPEN:
			gate.open_lane()
			_wait = 0.4
		else:
			_wait -= delta
			if _wait <= 0:
				phase = "CROSS_GATE"
				_points.assign([Vector3(gate.global_position.x, 0.35, 11.8)])
	elif not _points.is_empty():
		var target := _points[0]
		var offset := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		var reached := offset.length() < 0.1
		if not reached and _points.size() > 1 and offset.length() < 0.4:
			reached = _can_skip_waypoint(_points[1])
		if reached:
			_points.pop_front()
		else:
			var direction := offset.normalized()
			var speed: float = minf(walk_speed, offset.length() / maxf(delta, 0.001))
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 10.0))
	else:
		_arrived()
		if phase in ["SEATED", "DANGER", "PRE_IDLE"]: return
	_avoid_people(delta)
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.1:
		var motion := Vector3(velocity.x, 0, velocity.z) * delta
		var obstruction := KinematicCollision3D.new()
		if test_move(global_transform, motion, obstruction) and not (obstruction.get_collider() is CharacterBody3D):
			var raised := global_transform
			raised.origin.y += 0.23
			if not test_move(global_transform, Vector3.UP * 0.23) and not test_move(raised, motion):
				global_position.y += 0.23
	move_and_slide()
	for i in range(get_slide_collision_count()):
		var collider = get_slide_collision(i).get_collider()
		if collider and collider.has_meta("door_controller"):
			var door = collider.get_meta("door_controller")
			if not door.locked and not door.jammed: door.set_open(true)
	if gate and ticket and ticket.is_valid and absf(global_position.x - gate.global_position.x) < 0.7 and absf(global_position.z - gate.global_position.z) < 1.5:
		if phase not in ["TO_GATE", "GATE_WAIT"]: gate.open_lane()


func _can_skip_waypoint(next: Vector3) -> bool:
	# Loose intermediate tolerances let crowds pass a shared waypoint. Sweep
	# the real capsule against walls first so that tolerance cannot cut a column.
	_navigation_query.transform = Transform3D(global_basis, global_position + Vector3.UP * 0.875)
	_navigation_query.motion = Vector3(next.x - global_position.x, 0, next.z - global_position.z)
	var fractions := get_world_3d().direct_space_state.cast_motion(_navigation_query)
	return fractions.size() == 2 and fractions[0] >= 0.99


func _arrived() -> void:
	match phase:
		"PRE_ENTRY":
			_advance_visit()
		"PRE_VISIT":
			if _visit_kind == "wait" and is_instance_valid(seat_anchor):
				_sit()
				_pre_ticket_seated = true
			phase = "PRE_IDLE"
			_wait = randf_range(5, 14)
			if _visit_kind == "shop":
				var services := get_tree().get_first_node_in_group("station_services")
				if services: services.passenger_purchase(profile.uid, "food" if absi(hash(str(profile.uid))) % 2 == 0 else "drink")
		"COUNTER":
			rotation.y = -PI * 0.5 # face the clerk through the west-side window
			if not _counter_announced:
				_counter_announced = true
				reached_counter.emit(self)
		"TO_GATE":
			phase = "GATE_WAIT"
		"CROSS_GATE":
			if _boarding_pending:
				_boarding_pending = false
				board_train(_train)
				return
			phase = "TO_SEAT"
			var front := seat_anchor.global_position + seat_anchor.global_basis.z * 0.75
			_navigate_to(Vector3(front.x, 0.35, front.z))
		"TO_SEAT":
			_sit()
		"RETURN_SEAT":
			_sit()
		"ACTIVITY":
			phase = "IDLE_ACTIVITY"
			_wait = randf_range(5, 12)
			if _visit_kind == "shop":
				var services := get_tree().get_first_node_in_group("station_services")
				if services: services.passenger_purchase(profile.uid, "food" if absi(hash(str(profile.uid))) % 2 == 0 else "drink")
		"LEAVING":
			journey_finished.emit(self, false)
			queue_free()
		"BOARD_TRAIN":
			if not is_instance_valid(_train): _train = get_tree().get_first_node_in_group("train_service")
			if _train and _train.can_enter(self):
				train_offset = _train.vehicle.to_local(_train.interior_point(self))
				_points.assign([Vector3(global_position.x, 0.35, 20.15), Vector3(global_position.x, 0.35, 21.0), Vector3(_train.vehicle.to_global(train_offset).x, 0.35, 21.0), _train.seat_approach(train_offset)])
				phase = "ENTER_TRAIN"
				collision_layer = 0
				collision_mask = 0
			elif not _train or _train.phase != "BOARDING" or _train.elapsed > 34:
				_abandon_boarding()


func _abandon_boarding() -> void:
	if is_instance_valid(_train): _train._release_queue(self)
	_boarding_pending = false
	collision_layer = preload("res://scripts/collision_layers.gd").ACTORS | preload("res://scripts/collision_layers.gd").PASSENGERS
	collision_mask = preload("res://scripts/collision_layers.gd").SOLID | preload("res://scripts/collision_layers.gd").PASSENGERS
	# Once through the fare barrier, wait on the platform rather than walking
	# against the next boarding passenger through the same narrow gate.
	if global_position.z >= 10 and is_instance_valid(seat_anchor) and seat_anchor.global_position.z < 10:
		seat_anchor.set_meta("reserved", false)
		seat_anchor.set_meta("occupied", false)
		seat_anchor = null
		var nearest := INF
		for marker in get_tree().get_nodes_in_group("passenger_seats"):
			if not str(marker.get_parent().name).begins_with("PlatformBench_") or marker.get_meta("reserved", false): continue
			var distance: float = global_position.distance_squared_to(marker.global_position)
			if distance < nearest:
				nearest = distance
				seat_anchor = marker
		if is_instance_valid(seat_anchor): seat_anchor.set_meta("reserved", true)
	if is_instance_valid(seat_anchor):
		phase = "TO_SEAT"
		var front := seat_anchor.global_position + seat_anchor.global_basis.z * 0.75
		_navigate_to(Vector3(front.x, 0.35, front.z))
	else:
		# Imported/legacy saves can lack a station seat. Wait visibly for the next train.
		phase = "PLATFORM_WAIT"
		_points.clear()
		_path_pending = false
	velocity = Vector3.ZERO


func _sit() -> void:
	_idle_time = randf_range(18, 35)
	phase = "SEATED"
	global_position = Vector3(seat_anchor.global_position.x, 0.35, seat_anchor.global_position.z)
	rotation.y = seat_anchor.global_rotation.y
	velocity = Vector3.ZERO
	visual.set_seated(true, seat_anchor.global_position.y - global_position.y)
	seat_anchor.set_meta("occupied", true)
	journey_finished.emit(self, true)


func board_train(train: Node) -> void:
	# Checkpoints can resume a gate crossing before its deferred train approach.
	_train = train if is_instance_valid(train) else get_tree().get_first_node_in_group("train_service")
	if not _train or _train.phase != "BOARDING" or _train.elapsed > 34:
		_abandon_boarding()
		return
	if phase == "SEATED": _stand_up()
	if global_position.z < 10 and not _authorized:
		_boarding_pending = true
		phase = "TO_GATE"
		_navigate_to(Vector3(gate.global_position.x, 0.35, 9.1))
		return
	phase = "BOARD_TRAIN"
	var destination: Vector3 = _train.queue_point(self)
	_queue_destination = destination
	_navigate_to(destination)
	if _points.is_empty():
		_points.assign([Vector3(destination.x, 0.35, 16.8), destination])


func _navigate_to(point: Vector3) -> void:
	_points.clear()
	var from := global_position
	var destinations: Array[Vector3] = []
	if from.z < -22 and absf(from.x) < 3:
		destinations.append(Vector3(0, 0.35, -21))
		destinations.append(Vector3(0, 0.35, -15))
	if from.x < -16 and from.z < 0:
		if from.z < -4.6: destinations.append(Vector3(-18, 0.35, -4.6))
		destinations.append(Vector3(-18, 0.35, -3))
		destinations.append(Vector3(-15, 0.35, -3))
	if from.z < -16 and from.x > 3:
		destinations.append(Vector3(9, 0.35, -18))
		destinations.append(Vector3(9, 0.35, -15))
	if gate and (from.z < 10) != (point.z < 10):
		destinations.append(Vector3(gate.global_position.x, 0.35, 8.4 if from.z < 10 else 11.6))
		destinations.append(Vector3(gate.global_position.x, 0.35, 11.6 if from.z < 10 else 8.4))
	if point.x < -16 and point.z < 0:
		destinations.append(Vector3(-15, 0.35, -3))
		destinations.append(Vector3(-18, 0.35, -3))
		destinations.append(Vector3(-18, 0.35, -4.6))
	if point.z < -16 and point.x > 3:
		destinations.append(Vector3(9, 0.35, -15))
		destinations.append(Vector3(9, 0.35, -18))
	if point.z < -22 and absf(point.x) < 3:
		destinations.append(Vector3(0, 0.35, -15))
		destinations.append(Vector3(0, 0.35, -21))
	# Keep escorts centered through the booth door instead of grazing its outward leaf.
	var from_booth: bool = from.x < -7.5 and from.x > -16 and from.z > 1 and from.z < 7
	var to_booth: bool = point.x < -7.5 and point.x > -16 and point.z > 1 and point.z < 7
	if to_booth and not from_booth:
		destinations.append(Vector3(-10, 0.35, -0.6))
		destinations.append(Vector3(-10, 0.35, 2.4))
	elif from_booth and not to_booth:
		destinations.append(Vector3(-10, 0.35, 2.4))
		destinations.append(Vector3(-10, 0.35, -0.6))
	destinations.append(point)
	for target in destinations:
		var segment := NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, target, true)
		_points.append_array(segment)
		from = target


func _start_activity() -> void:
	var choices := ["smoking", "bathroom", "wander", "shop"]
	if profile.get("vip", false): choices.append("lounge")
	_visit_kind = "platform" if global_position.z >= 10 else choices.pick_random()
	_visit_target = _choose_activity_target(_visit_kind)
	_stand_up()
	phase = "ACTIVITY"
	_navigate_to(_visit_target)


func _choose_activity_target(kind: String) -> Vector3:
	var options: Array[Vector3] = []
	var bathroom_z: float = -1.5 if profile.get("gender", "") == "M" else -8.5
	for row in range(4):
		for column in range(3):
			match kind:
				"platform": options.append(Vector3(-22 + row * 14 + column * 2, 0.35, 16.8))
				"shop": options.append(Vector3(-14.4 + column * 0.65, 0.35, -12.4 + row * 0.65))
				"bathroom": options.append(Vector3(27.3 + row * 0.8, 0.35, bathroom_z + (column - 1) * 0.6))
				"smoking": options.append(Vector3(-18.4 + column * 0.8, 0.35, -6.5 - row * 0.8))
				"wander": options.append(Vector3(-2 + column * 2, 0.35, -7 - row))
				"wait": options.append(Vector3(2 + column * 0.7, 0.35, -1 - row * 0.7))
				"lounge": options.append(Vector3(4 + row * 2, 0.35, -17.5 - column * 0.4))
	options.shuffle()
	for point in options:
		var occupied := false
		for other in get_tree().get_nodes_in_group("passenger_actor"):
			if other == self: continue
			if other.phase in ["PRE_VISIT", "PRE_IDLE", "ACTIVITY", "IDLE_ACTIVITY"] and other._visit_target.distance_to(point) < 0.55:
				occupied = true
				break
		if not occupied: return point
	return options[0]


func _stand_up() -> void:
	visual.set_seated(false)
	if not is_instance_valid(seat_anchor): return
	var front: Vector3 = seat_anchor.global_position + seat_anchor.global_basis.z * 0.8
	global_position = Vector3(front.x, 0.37, front.z)
	_visual_previous = global_position
	seat_anchor.set_meta("occupied", false)


func put_in_danger() -> void:
	if GameManager.night <= 3: return
	if phase != "SEATED": return
	phase = "DANGER"
	danger_timer = maxf(10, 22 - GameManager.night)
	_danger_label.visible = true
	GameManager.objectives["save_passenger"] = {"text": "Rescue the passenger marked ! and lead them to Security or the booth.", "done": false}
	GameManager.objectives_changed.emit()
	GameManager.notice_posted.emit("A passenger is in danger! Reach them before their panic timer expires.")


func _rescue() -> void:
	if phase != "DANGER": return
	follow_peer = Coop.interaction_peer
	_follow_destination = Vector3.INF
	_stand_up()
	phase = "FOLLOW"
	_danger_label.text = "FOLLOWING — LEAD TO SAFETY"


func _interaction_prompt() -> String:
	var conversations := get_tree().get_first_node_in_group("passenger_dialogue_events")
	if conversations and conversations.has_conversation(self): return "[E] Talk to " + str(profile.get("name", "passenger"))
	return "[E] Guide passenger to Security or the booth" if phase == "DANGER" else ""


func _interact() -> void:
	var conversations := get_tree().get_first_node_in_group("passenger_dialogue_events")
	if conversations and conversations.has_conversation(self):
		conversations.open_conversation(self)
	else:
		_rescue()


func _avoid_people(delta: float) -> void:
	var desired := Vector3(velocity.x, 0, velocity.z)
	if desired.length_squared() < 0.001: return
	var direction := desired.normalized()
	var adjustment := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("passenger_actor"):
		if other == self or other.phase in ["BOARDED", "ENTER_TRAIN"]: continue
		var offset: Vector3 = global_position - other.global_position
		if absf(offset.y) > 0.8: continue
		offset.y = 0
		var distance := offset.length()
		if distance > 1.15: continue
		if distance < 0.001: offset = Vector3.RIGHT if get_instance_id() > other.get_instance_id() else Vector3.LEFT
		var away := offset.normalized()
		adjustment += away * maxf(0, 0.8 - distance) * 4.0
		var ahead := -offset.dot(direction)
		var lateral := absf(offset.cross(direction).y)
		if ahead > 0 and lateral < 0.52:
			# Follow at a walking gap; opposing walkers consistently pass on their right.
			var opposing: bool = Vector3(other.velocity.x, 0, other.velocity.z).dot(direction) < -0.1
			if opposing or Vector2(other.velocity.x, other.velocity.z).length() < 0.05:
				var side := direction.cross(Vector3.UP)
				# Preserve an existing passing side instead of steering two near walkers across each other.
				if offset.dot(side) < -0.05: side = -side
				adjustment += side * (1.15 - distance) * 2.5
			else:
				desired *= clampf((distance - 0.55) / 0.55, 0, 1)
	var result := (desired + adjustment).limit_length(walk_speed)
	velocity.x = result.x
	velocity.z = result.z
