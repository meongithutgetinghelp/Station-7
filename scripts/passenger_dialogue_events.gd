extends Node
## Optional, host-scheduled conversations. No effect on the required clue count.
@export_range(0.0, 1.0) var event_chance := 0.30
var chance_rng := RandomNumberGenerator.new()
var active: Dictionary = {}
var count := 0
var serial := 0
var next_reviewed := 3
var cooldown := 0.0
var last_kind := ""
var reader: CanvasLayer
var _station: Node

func _ready() -> void:
	add_to_group("passenger_dialogue_events")
	add_to_group("save_participant")
	_station = get_parent()
	chance_rng.randomize()
	reader = preload("res://scripts/passenger_dialogue.gd").new()
	reader.director = self
	add_child(reader)
	GameManager.night_started.connect(_reset)
	GameManager.shift_finished.connect(reader.close_panel)
	GameManager.player_died.connect(reader.close_panel)
	_reset(GameManager.night)

func _reset(_night: int) -> void:
	active.clear()
	count = 0
	serial += 1
	next_reviewed = randi_range(3, 5)
	cooldown = 45.0
	reader.close_panel()

func actor_for(uid: String) -> Node:
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if str(actor.profile.get("uid", "")) == uid: return actor
	return null

func has_conversation(actor: Node) -> bool:
	return not active.is_empty() and active.get("uid", "") == str(actor.profile.get("uid", "")) and active.get("stage", "") == "waiting" and actor.phase == "SEATED"

func open_conversation(actor: Node) -> void:
	if has_conversation(actor):
		reader.talk(str(actor.profile.uid), int(active.token), str(active.kind), str(actor.profile.get("name", "Passenger")))

func _process(delta: float) -> void:
	if reader.is_open:
		var target := actor_for(reader.target_uid)
		if not is_instance_valid(target) or not has_conversation(target): reader.close_panel()
	if Coop.is_client() or Coop.simulation_blocked() or GameManager.loading: return
	if not GameManager.signed_in or GameManager.state != GameManager.NightState.WORKING: return
	if not active.is_empty():
		var actor := actor_for(str(active.uid))
		if not is_instance_valid(actor) or actor.phase not in ["SEATED", "FOLLOW"]:
			active.clear()
			cooldown = randf_range(90, 150)
		elif actor.phase == "SEATED":
			actor._idle_time = 5.0
		return
	cooldown = maxf(0, cooldown - delta)
	if cooldown > 0 or count >= (1 if GameManager.night <= 2 else 2): return
	if _station.get_node("PassengerService").reviewed < next_reviewed: return
	var incident := _station.get_node("NightEvents")
	if incident.started and not incident.completed: return
	for panel in get_tree().get_nodes_in_group("world_modal"):
		if panel.is_open: return
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if actor.phase in ["DANGER", "FOLLOW"]: return
	var candidates: Array = []
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if actor.phase == "SEATED" and not actor._pre_ticket_seated and not actor.profile.get("anomaly", false):
			candidates.append(actor)
	if candidates.is_empty(): return
	# This is an opportunity, not a scheduled encounter. A miss is consumed;
	# never reroll every frame until an event is effectively guaranteed.
	next_reviewed = _station.get_node("PassengerService").reviewed + randi_range(3, 5)
	cooldown = randf_range(90, 150)
	if chance_rng.randf() >= event_chance: return
	var kind := "lost_property"
	if GameManager.night >= 3:
		kind = ["lost_property", "needs_help"].pick_random()
	begin_event(candidates.pick_random(), kind)

func begin_event(actor: Node, kind: String) -> bool:
	if Coop.is_client() or not active.is_empty() or not is_instance_valid(actor): return false
	if kind not in ["lost_property", "needs_help"] or (kind == "needs_help" and GameManager.night < 3): return false
	if actor.phase != "SEATED" or actor._pre_ticket_seated or actor.profile.get("anomaly", false): return false
	serial += 1
	count += 1
	last_kind = kind
	active = {"uid": str(actor.profile.uid), "kind": kind, "token": serial, "stage": "waiting"}
	actor._idle_time = 5.0
	GameManager.notice_posted.emit(str(actor.profile.get("name", "A passenger")) + " is asking to speak with a member of staff.")
	return true

func finish_dialogue(uid: String, token: int, peer: int) -> bool:
	if Coop.is_client() or GameManager.loading or not GameManager.signed_in or GameManager.state != GameManager.NightState.WORKING: return false
	var actor := actor_for(uid)
	if not is_instance_valid(actor) or not has_conversation(actor) or int(active.token) != token: return false
	var player := Coop.player_for(peer) if Coop.active else get_tree().get_first_node_in_group("player")
	if not player or player.global_position.distance_to(actor.global_position) > 4.5: return false
	if active.kind == "needs_help":
		# Reuse the existing escort/safe-room flow without a timed danger penalty.
		actor.phase = "DANGER"
		actor._rescue()
		actor.follow_peer = peer
		actor._danger_label.visible = true
		GameManager.objectives["save_passenger"] = {"text": "Walk the passenger to Security or the ticket booth.", "done": false}
		GameManager.objectives_changed.emit()
		active.stage = "escort"
	else:
		actor._idle_time = randf_range(18, 35)
		active.clear()
		cooldown = randf_range(90, 150)
	next_reviewed = _station.get_node("PassengerService").reviewed + randi_range(3, 5)
	return true


func yield_to_incident() -> bool:
	if active.is_empty(): return true
	# An accepted escort remains a safety task; an unanswered optional offer must
	# never become a prerequisite for the required incident or the shift ending.
	if active.get("stage", "") == "escort": return false
	var actor := actor_for(str(active.get("uid", "")))
	if is_instance_valid(actor) and actor.phase == "SEATED": actor._idle_time = randf_range(18, 35)
	reader.close_panel()
	active.clear()
	cooldown = randf_range(90, 150)
	return true

func save_state() -> Dictionary:
	return {"active": active.duplicate(true), "count": count, "serial": serial, "next_reviewed": next_reviewed, "cooldown": cooldown, "last_kind": last_kind, "chance_rng_state": str(chance_rng.state)}

func load_state(data: Dictionary) -> void:
	active = data.get("active", {}).duplicate(true)
	count = int(data.get("count", 0))
	serial = int(data.get("serial", 0))
	next_reviewed = int(data.get("next_reviewed", 3))
	cooldown = float(data.get("cooldown", 45))
	last_kind = str(data.get("last_kind", ""))
	if data.has("chance_rng_state"): chance_rng.state = int(data.chance_rng_state)
	if reader.is_open and (active.get("uid", "") != reader.target_uid or int(active.get("token", -1)) != reader.event_token): reader.close_panel()
