extends CharacterBody3D

const ATTACK_WINDUP: float = 0.65
const EYE_HEIGHT: float = 2.14
var visual: Node3D
var attack_remaining: float = 0
var attack_serial: int = 0
var _attack_peer: int = 1
var _attack_resolved: bool = false
var _attack_cooldown: float = 0
var _played_attack_serial: int = -1
var _network_revision: int = 0
var _last_network_revision: int = -1
var _last_visual_position := Vector3.ZERO

var phase: String = "DORMANT"
var banished: bool = false
var _target := Vector3.ZERO
var _path := PackedVector3Array()
var _path_timer: float = 0
var _retreat_time: float = 0
var _beam_time: float = 0
var _fault_time: float = 0
var _fault_index: int = 0
var _danger_time: float = 0
var _patrol_index: int = 0
var _lost_sight: float = 0
var _patrol := [Vector3(-3, 0.35, -10), Vector3(3, 0.35, -2), Vector3(14, 0.35, 4), Vector3(0, 0.35, 16), Vector3(-20, 0.35, 16)]


func _ready() -> void:
	add_to_group("entity_hearing")
	add_to_group("save_participant")
	add_to_group("station_entity")
	collision_layer = preload("res://scripts/collision_layers.gd").ACTORS
	collision_mask = preload("res://scripts/collision_layers.gd").SOLID
	floor_snap_length = 0.25
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 2.2
	shape.shape = capsule
	shape.position.y = 1.1
	add_child(shape)
	visual = preload("res://scripts/entity_visual.gd").new()
	visual.name = "EntityVisual"
	add_child(visual)
	GameManager.night_started.connect(_reset)
	_reset(GameManager.night)


func _reset(_night: int) -> void:
	phase = "DORMANT"
	banished = false
	visible = false
	position = Vector3(-20, 0.4, 16)
	velocity = Vector3.ZERO
	_path.clear()
	_fault_time = 0
	_fault_index = 0
	_danger_time = 0
	_beam_time = 0
	attack_remaining = 0
	_attack_cooldown = 0
	_attack_resolved = false
	attack_serial = 0
	_played_attack_serial = -1
	_last_network_revision = -1
	_last_visual_position = global_position
	if visual: visual.reset_visual()
	set_physics_process(true)


func wake() -> void:
	if phase != "DORMANT": return
	if GameManager.night <= 3:
		phase = "OBSERVE"
		visible = false
		GameManager.objectives["banish_entity"] = {"text": "Keep disguised intruders off the train: investigate suspicious passengers.", "done": false}
		GameManager.objectives_changed.emit()
		if GameManager.night >= 3: _sabotage()
		return
	phase = "STALK"
	visible = true
	_target = _patrol[0]
	GameManager.objectives["identify_entity"] = {"text": "Collect the three night reports and identify the intruder at Security.", "done": GameManager.entity_identified}
	GameManager.objectives["banish_entity"] = {"text": "Identify The Passenger, then hold your flashlight on it.", "done": false}
	GameManager.objectives_changed.emit()
	GameManager.notice_posted.emit("An unfamiliar passenger is moving through the station. Check the cameras.")
	_sabotage()


func hear_noise(point: Vector3, radius: float) -> void:
	if GameManager.night <= 3: return
	if phase in ["DORMANT", "BANISHED", "RETREAT", "ATTACK"]: return
	if global_position.distance_to(point) <= radius and global_position.distance_to(point) > 0.7:
		_target = point
		phase = "HUNT" if radius >= 9 else "STALK"
		_path_timer = 0


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = preload("res://scripts/collision_layers.gd").SOLID
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	if Coop.simulation_blocked(): return
	if GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD]: return
	if GameManager.night <= 3:
		_observe(delta)
		return
	var navigation := get_tree().get_first_node_in_group("station_navigation")
	if not navigation or not navigation.ready_for_paths: return
	if phase == "DORMANT":
		var pacing := get_tree().get_first_node_in_group("horror_pacing")
		if pacing and pacing.holds_first_hunt(): return
		if GameManager.signed_in and GameManager.time_minutes >= 150.0 - (GameManager.night - 1) * 2:
			wake()
		return
	if banished: return
	_attack_cooldown = maxf(0, _attack_cooldown - delta)
	var player := get_tree().get_first_node_in_group("player")
	if Coop.active and phase == "ATTACK":
		player = Coop.player_for(_attack_peer)
	elif Coop.active:
		var nearest: float = INF
		for member in Coop.crew():
			var distance_to_member: float = global_position.distance_to(member.global_position)
			if not member.get_meta("hiding", false) and distance_to_member < nearest:
				nearest = distance_to_member
				player = member
	if not player:
		if phase == "ATTACK": _cancel_attack()
		return
	_fault_time += delta
	_danger_time += delta
	if _fault_time > maxf(18, 50 - GameManager.night * 3):
		_fault_time = 0
		_sabotage()
	var distance: float = global_position.distance_to(player.global_position)
	var hidden: bool = player.get_meta("hiding", false)
	var eye: Vector3 = global_position + Vector3(0, EYE_HEIGHT, 0)
	var player_eye: Vector3 = player.camera.global_position
	var sight: bool = not hidden and distance < 15 and _line_clear(eye, player_eye)
	if sight and phase not in ["RETREAT", "ATTACK"]:
		var direction: Vector3 = (player.global_position - global_position).normalized()
		if global_basis.z.dot(direction) > 0.25 or phase == "HUNT":
			phase = "HUNT"
			_target = player.global_position
	if hidden and phase == "HUNT":
		phase = "STALK"
		_target = _patrol[_patrol_index]
	if phase == "HUNT":
		_lost_sight = 0 if sight else _lost_sight + delta
		if _lost_sight > 8:
			phase = "STALK"
			_target = _patrol[_patrol_index]
	var light_player = player
	if Coop.active:
		for member in Coop.crew():
			var member_eye: Vector3 = member.camera.global_position
			if member.is_flashlight_on and global_position.distance_to(member.global_position) < 8 and (-member.camera.global_basis.z).dot((eye - member_eye).normalized()) > 0.9 and _line_clear(member_eye, eye):
				light_player = member
				break
	var light_eye: Vector3 = light_player.camera.global_position
	if light_player.is_flashlight_on and global_position.distance_to(light_player.global_position) < 8 and _line_clear(light_eye, eye):
		var aimed: bool = (-light_player.camera.global_basis.z).dot((eye - light_eye).normalized()) > 0.9
		if aimed:
			_beam_time += delta
			if GameManager.entity_identified and _beam_time >= 2.5:
				banished = true
				phase = "BANISHED"
				visible = false
				GameManager.complete_objective("banish_entity")
				GameManager.notice_posted.emit("The Passenger withdraws. Keep the remaining passengers safe until dawn.")
				return
			elif not GameManager.entity_identified and _beam_time > 0.6:
				phase = "RETREAT"
				attack_remaining = 0
				_retreat_time = 5
				_target = global_position + (global_position - player.global_position).normalized() * 8
		else: _beam_time = 0
	else: _beam_time = 0
	if phase == "RETREAT":
		_retreat_time -= delta
		if _retreat_time <= 0: phase = "STALK"
	if phase == "STALK" and global_position.distance_to(_target) < 1:
		_patrol_index = (_patrol_index + 1) % _patrol.size()
		_target = _patrol[_patrol_index]
	if phase == "ATTACK":
		_advance_attack(delta, player)
		return
	if distance < 0.95 and sight and not hidden and phase == "HUNT" and _attack_cooldown <= 0:
		_begin_attack(player)
		return
	if _danger_time > 18 and phase == "HUNT":
		_danger_time = 0
		for actor in get_tree().get_nodes_in_group("passenger_actor"):
			if actor.phase == "SEATED" and global_position.distance_to(actor.global_position) < 8:
				actor.put_in_danger()
				break
	_path_timer -= delta
	if _path_timer <= 0:
		_path_timer = 0.5
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, _target, true)
	while not _path.is_empty() and global_position.distance_to(_path[0]) < 0.35: _path.remove_at(0)
	velocity.x = 0
	velocity.z = 0
	if not _path.is_empty():
		var direction := (_path[0] - global_position)
		direction.y = 0
		direction = direction.normalized()
		var speed: float = (2.6 + GameManager.night * 0.2) if phase == "HUNT" else 1.3
		var jobs := get_tree().get_first_node_in_group("station_jobs")
		if jobs and jobs.cleanliness < 50: speed += 0.5
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1, delta * 8))
	if not is_on_floor(): velocity.y -= 9.8 * delta
	move_and_slide()
	for i in range(get_slide_collision_count()):
		var collider = get_slide_collision(i).get_collider()
		if collider and collider.has_meta("door_controller"):
			var door = collider.get_meta("door_controller")
			if not door.locked and not door.jammed: door.set_open(true)
		elif collider and collider.get_parent() is Gate:
			collider.get_parent().open_lane()


func _sabotage() -> void:
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	if jobs:
		var faults: Array = ["flicker", "light", "power"] if GameManager.night <= 3 else ["door", "gate", "light", "power"]
		jobs.trigger_fault(faults[_fault_index % faults.size()])
		_fault_index += 1


func _observe(delta: float) -> void:
	# Early nights have no separate monster, attacks or abduction timers.
	visible = false
	velocity = Vector3.ZERO
	var service := get_tree().get_first_node_in_group("passenger_director")
	if not service or not GameManager.signed_in: return
	if service.reviewed >= service.total_cases():
		var admitted_intruder := false
		for verdict in service.decisions:
			if verdict.get("anomaly", false) and verdict.approved: admitted_intruder = true
		banished = not admitted_intruder
		if banished: GameManager.complete_objective("banish_entity")
	if banished: return
	if phase == "DORMANT" and GameManager.time_minutes >= 150.0 - (GameManager.night - 1) * 2: wake()
	if phase == "OBSERVE":
		_fault_time += delta
		if _fault_time > (180 if GameManager.night <= 2 else 70):
			_fault_time = 0
			if GameManager.night >= 2: _sabotage()


func save_state() -> Dictionary:
	return {"phase": phase, "banished": banished, "position": [position.x, position.y, position.z], "target": [_target.x, _target.y, _target.z], "fault_time": _fault_time, "fault_index": _fault_index, "attack_remaining": attack_remaining, "attack_serial": attack_serial, "attack_peer": _attack_peer, "attack_cooldown": _attack_cooldown}


func load_state(data: Dictionary) -> void:
	phase = data.get("phase", "DORMANT")
	if GameManager.night <= 3 and phase not in ["DORMANT", "BANISHED"]: phase = "OBSERVE"
	banished = bool(data.get("banished", false))
	var point: Array = data.get("position", [-20, 0.4, 16])
	position = Vector3(float(point[0]), float(point[1]), float(point[2]))
	point = data.get("target", [-3, 0.35, -10])
	_target = Vector3(float(point[0]), float(point[1]), float(point[2]))
	_fault_time = float(data.get("fault_time", 0))
	_fault_index = int(data.get("fault_index", 0))
	attack_remaining = clampf(float(data.get("attack_remaining", 0)), 0, ATTACK_WINDUP)
	attack_serial = int(data.get("attack_serial", 0))
	_attack_peer = int(data.get("attack_peer", 1))
	_attack_cooldown = maxf(0, float(data.get("attack_cooldown", 0)))
	_attack_resolved = false
	if phase == "ATTACK" and attack_remaining <= 0: phase = "STALK"
	_played_attack_serial = -1
	_last_visual_position = global_position
	if visual: visual.reset_visual()
	visible = GameManager.night >= 4 and phase != "DORMANT" and not banished


func _process(delta: float) -> void:
	if not visual: return
	var speed: float = Vector2(global_position.x - _last_visual_position.x, global_position.z - _last_visual_position.z).length() / maxf(delta, 0.001)
	_last_visual_position = global_position
	if not visible or phase in ["DORMANT", "OBSERVE", "BANISHED"]:
		if visual.current_clip != "": visual.reset_visual()
		return
	if Coop.is_client() and phase == "ATTACK": attack_remaining = maxf(0, attack_remaining - delta)
	if phase == "ATTACK":
		if _played_attack_serial != attack_serial:
			visual.reset_visual()
			_played_attack_serial = attack_serial
		visual.play_clip("Attack", 1.0, maxf(0, ATTACK_WINDUP - attack_remaining))
	elif phase == "RETREAT": visual.play_clip("Retreat")
	elif speed > 0.08:
		visual.play_clip("Chase" if phase == "HUNT" else "Walk", clampf(speed / (3.4 if phase == "HUNT" else 1.3), 0.65, 1.35))
	else: visual.play_clip("Idle")


func _begin_attack(player: Node3D) -> void:
	if Coop.is_client() or GameManager.night <= 3 or banished or phase != "HUNT": return
	phase = "ATTACK"
	attack_remaining = ATTACK_WINDUP
	attack_serial += 1
	_attack_resolved = false
	_attack_peer = 1
	if Coop.active:
		for id in Coop.roster:
			if Coop.player_for(id) == player: _attack_peer = id
	velocity = Vector3.ZERO


func _cancel_attack() -> void:
	attack_remaining = 0
	_attack_resolved = true
	_attack_cooldown = 1.0
	phase = "STALK"


func _advance_attack(delta: float, player: Node3D) -> void:
	if Coop.is_client() or phase != "ATTACK" or _attack_resolved: return
	velocity = Vector3.ZERO
	if GameManager.night <= 3 or banished or not is_instance_valid(player):
		_cancel_attack()
		return
	attack_remaining = maxf(0, attack_remaining - delta)
	if attack_remaining > 0: return
	_attack_resolved = true
	_attack_cooldown = 1.2
	var in_range: bool = global_position.distance_to(player.global_position) <= 1.2
	var clear: bool = _line_clear(global_position + Vector3(0, EYE_HEIGHT, 0), player.camera.global_position)
	if in_range and clear and not player.get_meta("hiding", false): GameManager.kill_player()
	else: phase = "STALK"


func network_state() -> Dictionary:
	_network_revision += 1
	return {"revision": _network_revision, "p": position, "y": rotation.y, "phase": phase, "banished": banished, "visible": visible, "attack_remaining": attack_remaining, "attack_serial": attack_serial}


func apply_network_state(data: Dictionary) -> void:
	if not Coop.is_client() or int(data.get("revision", -1)) <= _last_network_revision: return
	_last_network_revision = int(data.revision)
	phase = str(data.phase)
	banished = bool(data.banished)
	visible = bool(data.visible)
	attack_remaining = clampf(float(data.get("attack_remaining", 0)), 0, ATTACK_WINDUP)
	attack_serial = int(data.get("attack_serial", 0))
	set_meta("net_position", data.p)
	set_meta("net_yaw", data.y)
