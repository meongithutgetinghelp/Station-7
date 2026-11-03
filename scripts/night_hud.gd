extends CanvasLayer

const StationStyle = preload("res://ui/station_skin.gd")

var _clock: Label
var _status: Label
var _tasks: Label
var _notice: Label
var _notice_time: float = 0
var _guide: Label
var _guide_elapsed: float = 0
var _condition: Label
var _guide_time := 0.0
var _last_guide := ""


var _canvas: Control
var _guide_card: PanelContainer
var _notice_card: PanelContainer
var _opening_title: Label
var _opening_tween: Tween

func _ready() -> void:
	layer = 5
	add_to_group("night_hud")
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_canvas.theme = StationStyle.theme()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	var status := _card(Vector2(40, 32), 450)
	_clock = _label(status, 24)
	_status = _label(status, 17)
	_tasks = _label(status, 16)
	_tasks.modulate = StationStyle.MUTED
	var condition := _card(Vector2(1340, 32), 500)
	_condition = _label(condition, 17)
	_condition.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var controls := _label(_canvas, 16)
	controls.position = Vector2(1300, 1000)
	controls.size.x = 540
	controls.text = "E  Interact   F  Flashlight   Esc  Pause\nP  Phone   1–5  Equipment   J  Night log"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.modulate = StationStyle.MUTED
	var guide := _card(Vector2(40, 865), 630)
	_guide_card = guide.get_parent()
	_guide = _label(guide, 20)
	var notice := _card(Vector2(660, 155), 600)
	_notice_card = notice.get_parent()
	_notice = _label(notice, 20)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate = StationStyle.AMBER
	_opening_title = _label(_canvas, 42)
	_opening_title.position = Vector2(360, 350)
	_opening_title.size = Vector2(1200, 100)
	_opening_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_opening_title.hide()
	GameManager.notice_posted.connect(func(text: String) -> void:
		if text == "The Station Is Now Open":
			_notice.text = ""
			_notice_time = 0
			_notice_card.hide()
			_show_station_open()
			return
		_notice.text = text
		_notice_time = 8
		StationStyle.reveal(_notice_card))
	GameManager.clock_changed.connect(_refresh)
	GameManager.power_changed.connect(_power_changed)
	GameManager.objectives_changed.connect(_refresh)
	GameManager.shift_finished.connect(_refresh)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()


func _show_station_open() -> void:
	if _opening_tween and _opening_tween.is_valid(): _opening_tween.kill()
	_opening_title.text = "The Station Is Now Open"
	_opening_title.show()
	var reduced := StationStyle.reduced_motion(self)
	_opening_title.modulate.a = 1.0 if reduced else 0.0
	_opening_tween = create_tween()
	if not reduced: _opening_tween.tween_property(_opening_title, "modulate:a", 1.0, 0.4)
	_opening_tween.tween_interval(4.0)
	if not reduced: _opening_tween.tween_property(_opening_title, "modulate:a", 0.0, 0.6)
	_opening_tween.tween_callback(_opening_title.hide)


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var factor := minf(screen.x / 1920.0, screen.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (screen - Vector2(1920, 1080) * factor) * 0.5


func _card(at: Vector2, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.custom_minimum_size.x = width
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width - 16
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	return column


func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _power_changed(_powered: bool) -> void:
	_refresh()


func _process(delta: float) -> void:
	_guide_elapsed -= delta
	if _guide_elapsed <= 0:
		_guide_elapsed = 0.5
		var next: String = "" if GameManager.state in [GameManager.NightState.SHIFT_OVER, GameManager.NightState.DEAD] else preload("res://scripts/shift_guidance.gd").compact_step(GameManager, get_tree())
		if next != _last_guide:
			_last_guide = next
			_guide.text = next
			_guide_time = 10.0
		var modal_open := get_tree().paused
		for panel in get_tree().get_nodes_in_group("world_modal"):
			# Physical desk mode keeps its UI controller open but draws no overlay.
			if panel.is_open and panel.visible: modal_open = true
		_canvas.visible = not modal_open
	var player := get_tree().get_first_node_in_group("player")
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	if player and jobs:
		_condition.text = "BAT %d%%   CLEAN %d%%   LOST %d/%d" % [int(player.flashlight_charge), int(jobs.cleanliness), GameManager.lost_passengers, 1 if GameManager.night <= 4 else 0]
	_guide_time = maxf(0.0, _guide_time - delta)
	var urgent: bool = GameManager.night == 1 or not GameManager.powered or _guide.text.begins_with("RESCUE")
	_guide_card.visible = not _guide.text.is_empty() and (_guide_time > 0 or urgent)
	_guide_card.modulate.a = 1.0 if urgent or StationStyle.reduced_motion(self) else minf(1.0, _guide_time)
	_notice_card.visible = _notice_time > 0 and not _notice.text.is_empty()
	if _notice_time > 0:
		_notice_time -= delta
		if _notice_time <= 0:
			_notice.text = ""


func _refresh() -> void:
	_clock.text = "NIGHT %d  /  %s" % [GameManager.night, GameManager.clock_text()]
	_status.text = "POWER ONLINE" if GameManager.powered else ("POWER FAILURE · [F] flashlight" if GameManager.needs_power_repair() else "LIGHTS OFF · Start up at Electrical")
	_status.modulate = Color(0.65, 0.9, 0.75) if GameManager.powered else Color(1.0, 0.65, 0.3)
	if GameManager.state == GameManager.NightState.SHIFT_OVER:
		_status.text = "SHIFT ENDED"
	var remaining := 0
	for objective: Dictionary in GameManager.objectives.values():
		if not objective.done: remaining += 1
	_tasks.text = "[J] Night log  ·  %d open duties" % remaining



func set_text_scale(value: float) -> void:
	for label in [_clock, _status, _tasks, _notice, _condition, _guide]:
		if label: label.add_theme_font_size_override("font_size", roundi((24 if label == _clock else (20 if label in [_guide, _notice] else 17)) * value))
