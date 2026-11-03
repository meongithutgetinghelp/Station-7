extends "res://field_panel.gd"

var _transitioning := false
var _actions: GridContainer


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 70
	add_to_group("shift_report")
	close_button.hide()
	_actions = GridContainer.new()
	_actions.name = "ReportActions"
	_actions.columns = 2
	_actions.add_theme_constant_override("h_separation", 10)
	_actions.add_theme_constant_override("v_separation", 8)
	close_button.get_parent().add_child(_actions)
	GameManager.shift_finished.connect(_show_report)
	GameManager.player_died.connect(_show_death)


func _input(_event: InputEvent) -> void:
	pass # End-of-shift and death screens require an explicit action.


func _action(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 45
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	if Coop.is_client() and callback != _main_menu:
		button.disabled = true
		button.tooltip_text = "The host controls campaign progression."
	_actions.add_child(button)


func _clear_actions() -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()


func _focus_action() -> void:
	for button in _actions.get_children():
		if not button.disabled:
			button.grab_focus()
			return


func _show_death() -> void:
	_transitioning = false
	clear_body()
	_clear_actions()
	heading.text = "TAKEN BY THE PASSENGER"
	paragraph("The station falls silent. Your shift is unfinished. Use cover, keep your battery charged, and identify the intruder before confronting it.")
	_action("Retry this night", _retry)
	_action("Load latest checkpoint", _load_saved)
	_action("Main menu", _main_menu)
	open_panel()
	_focus_action()
	get_tree().paused = not Coop.active


func _show_report() -> void:
	_transitioning = false
	var service := get_tree().get_first_node_in_group("passenger_director")
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	var entity := get_tree().get_first_node_in_group("station_entity")
	var train := get_tree().get_first_node_in_group("train_service")
	var blockers := GameManager.shift_blockers()
	var passed := blockers.is_empty()
	clear_body()
	_clear_actions()
	heading.text = "06:00 / NIGHT %d COMPLETE" % GameManager.night if passed else "SHIFT ENDED / STATION NOT SECURED"
	paragraph("Ticket decisions: %d correct / %d checked\nPassengers boarded: %d\nPassengers rescued: %d\nPassengers lost: %d\nCleanliness: %d%%\nEntity: %s" % [service.correct if service else 0, service.reviewed if service else 0, train.boarded_count if train else 0, GameManager.rescued_passengers, GameManager.lost_passengers, int(jobs.cleanliness) if jobs else 0, ("screened out" if GameManager.night <= 3 else "banished") if entity and entity.banished else "uncontained"])
	if not passed: paragraph("Unfinished duties:\n• " + "\n• ".join(blockers))
	var failure := GameManager.irreversible_shift_failure()
	if not failure.is_empty(): paragraph(failure)
	if GameManager.night >= 7:
		var total_lost: int = int(GameManager.campaign.lost) + GameManager.lost_passengers
		var ending := "SAFE DAWN" if passed and total_lost == 0 else ("THE LAST TRAIN" if entity and entity.banished else "EMPTY PLATFORM")
		heading.text = ending
		paragraph({"SAFE DAWN": "The final service leaves with everyone accounted for. Platform 7 is yours again.", "THE LAST TRAIN": "You drove it away, but the night's mistakes travel with you.", "EMPTY PLATFORM": "The station opens at dawn. No one is waiting on the platform."}[ending])
		var pacing := get_tree().get_first_node_in_group("horror_pacing")
		if pacing: paragraph(pacing.ending_text(passed))
		_action("Main menu / credits", _main_menu)
	elif passed:
		paragraph("Station secured. The remaining hours pass quietly. A harder shift waits tomorrow.")
		_action("Begin night %d" % (GameManager.night + 1), _next_night)
	_action("Retry this night", _retry)
	_action("Load latest checkpoint", _load_saved)
	if GameManager.night < 7: _action("Main menu", _main_menu)
	open_panel()
	_focus_action()
	get_tree().paused = not Coop.active


func _retry() -> void:
	if _transitioning: return
	_transitioning = true
	if Coop.active:
		if not Coop.is_client(): Coop.restart_shift()
		return
	close_panel()
	get_tree().paused = false
	GameManager.start_night(GameManager.night)
	get_tree().reload_current_scene()


func _next_night() -> void:
	if _transitioning: return
	_transitioning = true
	if Coop.active:
		if not Coop.is_client(): Coop.restart_shift(true)
		return
	close_panel()
	get_tree().paused = false
	GameManager.record_night()
	GameManager.start_night(GameManager.night + 1)
	get_tree().reload_current_scene()


func _load_saved() -> void:
	if Coop.active:
		if not Coop.is_client(): Coop.restart_shift(false, true)
		return
	if GameManager.load_game():
		get_tree().paused = GameManager.state in [GameManager.NightState.DEAD, GameManager.NightState.SHIFT_OVER]


func _main_menu() -> void:
	if _transitioning: return
	_transitioning = true
	if Coop.active:
		Coop.leave("Session ended.")
		return
	close_panel()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")
