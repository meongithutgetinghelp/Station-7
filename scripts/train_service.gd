extends Node3D

var phase: String = "WAITING"
var elapsed: float = 0
var next_arrival: float = 137.0
var boarded_count: int = 0
var vehicle: Node3D
var interior: Node3D
var _doors: Array[Dictionary] = []
var _motor: AudioStreamPlayer3D
var _queues: Dictionary = {}
var _tween: Tween


func _ready() -> void:
	add_to_group("train_service")
	add_to_group("save_participant")
	_build_train()
	GameManager.player_died.connect(_halt)
	GameManager.shift_finished.connect(_halt)
	GameManager.night_started.connect(_reset)
	_reset(GameManager.night)


func _halt() -> void:
	_motor.stop()
	if _tween and _tween.is_valid(): _tween.pause()


func _build_train() -> void:
	vehicle = Node3D.new()
	vehicle.name = "NightTrain"
	vehicle.position.z = 21
	add_child(vehicle)
	var model := preload("res://assets/trains/subway/subway_train.glb").instantiate()
	model.name = "SubwayModel"
	# Body floor meets the platform; prepared running gear meets the existing rails.
	model.position.y = -0.20
	vehicle.add_child(model)
	interior = preload("res://scripts/train_interior.gd").new()
	vehicle.add_child(interior)
	for leaf in model.find_children("SlidingDoor_*", "MeshInstance3D", true, false):
		_doors.append({"node": leaf, "closed": leaf.position.x, "closed_z": leaf.position.z, "outward": signf(leaf.position.z), "direction": -1.0 if str(leaf.name).ends_with("_L") else 1.0})
	# Warm carriage lighting keeps real boarding passengers readable through the doorways.
	for x in [-18.75, -6.25, 6.25, 18.75]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 2.45, 0.4)
		light.light_color = Color(1.0, 0.91, 0.74)
		light.light_energy = 0.8
		light.omni_range = 7.0
		light.shadow_enabled = false
		light.light_cull_mask = 3
		vehicle.add_child(light)
	_motor = AudioStreamPlayer3D.new()
	_motor.bus = "Ambience"
	_motor.stream = preload("res://scripts/station_audio.gd").hum(3.0, 47.0)
	_motor.volume_db = -16
	_motor.unit_size = 12
	_motor.max_distance = 90
	vehicle.add_child(_motor)


func _reset(_night: int) -> void:
	phase = "WAITING"
	elapsed = 0
	next_arrival = 137
	boarded_count = 0
	_queues.clear()
	vehicle.position.x = -65
	vehicle.visible = false
	_motor.stop()
	_set_doors(false, true)


func _process(delta: float) -> void:
	if Coop.simulation_blocked() or not GameManager.signed_in: return
	if GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]:
		return
	elapsed += delta
	match phase:
		"WAITING":
			if GameManager.time_minutes >= next_arrival:
				phase = "ARRIVING"
				elapsed = 0
				vehicle.visible = true
				_motor.play()
				next_arrival += 18
				GameManager.notice_posted.emit("PA: Line 7 train approaching Platform 7. Stand behind the yellow line.")
		"ARRIVING":
			vehicle.position.x = lerpf(-65, 0, smoothstep(0, 12, elapsed))
			if elapsed >= 12:
				phase = "BOARDING"
				elapsed = 0
				vehicle.position.x = 0
				_set_doors(true)
				GameManager.notice_posted.emit("PA: Doors open. North Terminal service now boarding.")
		"BOARDING":
			for actor in get_tree().get_nodes_in_group("passenger_actor"):
				if elapsed < 30 and actor.phase in ["SEATED", "ACTIVITY", "IDLE_ACTIVITY", "RETURN_SEAT", "PLATFORM_WAIT"]:
					actor.board_train(self)
			var events := get_tree().get_first_node_in_group("night_events")
			if elapsed > 35 and not crossing_passengers() and not (events and events.holds_departure()):
				phase = "CLOSING"
				elapsed = 0
				_set_doors(false)
				GameManager.notice_posted.emit("PA: Mind the doors. Train departing.")
		"CLOSING":
			if elapsed > 1:
				phase = "DEPARTING"
				elapsed = 0
		"DEPARTING":
			vehicle.position.x = lerpf(0, 65, smoothstep(0, 10, elapsed))
			if elapsed > 10:
				phase = "WAITING"
				elapsed = 0
				vehicle.visible = false
				for actor in get_tree().get_nodes_in_group("passenger_actor"):
					if actor.phase == "BOARDED": actor.queue_free()
				_motor.stop()


func _set_doors(open: bool, immediate: bool = false) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	if not immediate:
		_tween = create_tween().set_parallel(true)
	for entry in _doors:
		var target: float = entry.closed + (float(entry.direction) * 0.78 if open else 0.0)
		var outside: float = entry.closed_z + entry.outward * 0.14
		if immediate:
			entry.node.position.x = target
			entry.node.position.z = outside if open else entry.closed_z
		elif open:
			_tween.tween_property(entry.node, "position:z", outside, 0.22)
			_tween.tween_property(entry.node, "position:x", target, 0.55).set_delay(0.22)
		else:
			_tween.tween_property(entry.node, "position:x", target, 0.55)
			_tween.tween_property(entry.node, "position:z", entry.closed_z, 0.22).set_delay(0.55)


func boarding_point(from: Vector3) -> Vector3:
	# Align the platform approach with the supplied four-car model's actual doors.
	var x := -22.75
	for door_x in [-22.75, -18.75, -14.75, -10.25, -6.25, -2.25, 2.25, 6.25, 10.25, 14.75, 18.75, 22.75]:
		if absf(from.x - door_x) < absf(from.x - x): x = door_x
	return Vector3(x, 0.35, 17.2)


func board(actor: Node) -> bool:
	if phase != "BOARDING" or actor.phase == "BOARDED":
		return false
	_release_queue(actor)
	boarded_count += 1
	if is_instance_valid(actor.seat_anchor):
		actor.seat_anchor.set_meta("reserved", false)
		actor.seat_anchor.set_meta("occupied", false)
	actor.seat_anchor = null
	GameManager.objectives["board_passengers"] = {"text": "Passengers boarded: %d." % boarded_count, "done": true}
	GameManager.objectives_changed.emit()
	actor.phase = "BOARDED"
	actor.rotation.y = PI if actor.train_offset.z > 0 else 0
	actor.global_position = vehicle.to_global(actor.train_offset)
	actor.visual.set_seated(true, interior.SEAT_HEIGHT - 0.35)
	actor.velocity = Vector3.ZERO
	actor.collision_layer = 0
	actor.collision_mask = 0
	return true


func save_state() -> Dictionary:
	return {"phase": phase, "elapsed": elapsed, "next": next_arrival, "boarded": boarded_count, "x": vehicle.position.x}


func load_state(data: Dictionary) -> void:
	phase = data.get("phase", "WAITING")
	elapsed = float(data.get("elapsed", 0))
	next_arrival = float(data.get("next", 137))
	boarded_count = int(data.get("boarded", 0))
	vehicle.position.x = float(data.get("x", -65))
	vehicle.visible = phase != "WAITING"
	_set_doors(phase == "BOARDING", true)
	if vehicle.visible:
		_motor.play()
	else:
		_motor.stop()


func crossing_passengers() -> bool:
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if actor.phase == "ENTER_TRAIN": return true
	return false


func can_enter(actor: Node3D) -> bool:
	if phase != "BOARDING" or elapsed < 0.8 or elapsed > 34 or not interior_point(actor).is_finite(): return false
	var queue: Array = _queue_for(actor)
	if queue.is_empty() or queue[0] != actor: return false
	for other in get_tree().get_nodes_in_group("passenger_actor"):
		if other == actor or absf(other.global_position.x - actor.global_position.x) > 0.65: continue
		if other.phase == "ENTER_TRAIN": return false
	return true


func interior_point(actor: Node3D) -> Vector3:
	var door_x: float = boarding_point(actor.global_position).x
	var occupied: Array[Vector3] = []
	for other in get_tree().get_nodes_in_group("passenger_actor"):
		if other != actor and other.phase in ["ENTER_TRAIN", "BOARDED"]: occupied.append(other.train_offset)
	var best := Vector3.INF
	var best_score := INF
	for point in interior.seats:
		var free := true
		for taken in occupied:
			if point.distance_to(taken) < 0.65: free = false
		var score: float = absf(point.x - door_x) + (0.15 if point.z > 0 else 0.0)
		if free and score < best_score:
			best = point
			best_score = score
	return vehicle.to_global(best) if best.is_finite() else Vector3.INF


func seat_approach(offset: Vector3) -> Vector3:
	return vehicle.to_global(offset - Vector3(0,0,signf(offset.z)*0.42))


func _queue_for(actor: Node3D) -> Array:
	var key: float = boarding_point(actor.global_position).x
	if not _queues.has(key): _queues[key] = []
	var queue: Array = _queues[key]
	for i in range(queue.size() - 1, -1, -1):
		if not is_instance_valid(queue[i]) or queue[i].phase not in ["BOARD_TRAIN", "ENTER_TRAIN"]: queue.remove_at(i)
	if actor not in queue: queue.append(actor)
	return queue


func queue_point(actor: Node3D) -> Vector3:
	var queue: Array = _queue_for(actor)
	var index: int = queue.find(actor)
	var x: float = boarding_point(actor.global_position).x
	if index == 0: return Vector3(x, 0.35, 18.6)
	var column := -0.8 if index % 2 == 1 else 0.8
	return Vector3(x + column, 0.35, 18.6 - ceilf(float(index) / 2) * 0.85)


func _release_queue(actor: Node) -> void:
	for queue in _queues.values(): queue.erase(actor)
