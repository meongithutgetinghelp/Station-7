extends CanvasLayer

const StationStyle = preload("res://ui/station_skin.gd")

const SETTINGS_PATH: String = "user://settings.cfg"
var settings_path: String = SETTINGS_PATH
var _overlay: Control
var _resume: Button
var _volume: HSlider
var _sensitivity: HSlider
var _player: Node
var _dirty: bool = false
var is_main_menu: bool = false
var _reduced_motion: CheckButton
var _reduced_flashes: CheckButton
var _text_scale: HSlider
var _bus_sliders: Dictionary = {}
var _retro: CheckButton
var _toggle_crouch: CheckButton
var _toggle_sprint: CheckButton
var _render_scale: HSlider
var _show_fps: CheckButton
var _fps_counter: Label
var _fps_elapsed: float = 0.0


var _pages: TabContainer
var _tabs: Array[Button] = []
var _sheet: PanelContainer
var _return_focus: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	add_to_group("pause_menu")
	_player = get_tree().get_first_node_in_group("player")
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.theme = StationStyle.theme()
	add_child(_overlay)
	_fps_counter = Label.new()
	_fps_counter.name = "FPSCounter"
	_fps_counter.theme = StationStyle.theme()
	_fps_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_counter.offset_left = -180
	_fps_counter.offset_right = -16
	_fps_counter.offset_top = 8
	_fps_counter.offset_bottom = 34
	_fps_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_counter.add_theme_font_size_override("font_size", 18)
	_fps_counter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_fps_counter.add_theme_constant_override("outline_size", 3)
	_fps_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_counter.hide()
	add_child(_fps_counter)
	var artwork := TextureRect.new()
	artwork.texture = preload("res://ui/illustrations/station-charcoal-v1.png")
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(artwork)
	_sheet = PanelContainer.new()
	_sheet.size = Vector2(920, 650)
	var style := StationStyle.surface(Color.TRANSPARENT, Color.TRANSPARENT)
	style.shadow_size = 0
	style.set_content_margin_all(38)
	_sheet.add_theme_stylebox_override("panel", style)
	_overlay.add_child(_sheet)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	_sheet.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "Settings" if is_main_menu else "Shift paused"
	title.add_theme_font_size_override("font_size", 38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_resume = Button.new()
	_resume.add_theme_font_size_override("font_size", 24)
	_resume.text = "Back  /  Esc" if is_main_menu else "Resume  /  Esc"
	_resume.pressed.connect(func() -> void: set_paused(false))
	header.add_child(_resume)
	StationStyle.animate_button(_resume)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 24)
	content.add_child(nav)
	_pages = TabContainer.new()
	_pages.tabs_visible = false
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_pages)
	var group := ButtonGroup.new()
	for title_text in ["Controls", "Display", "Sound", "Shift"]:
		var tab := Button.new()
		tab.text = title_text
		tab.add_theme_font_size_override("font_size", 24)
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := _tabs.size()
		tab.pressed.connect(func() -> void:
			_pages.current_tab = index
			StationStyle.reveal(_pages))
		nav.add_child(tab)
		_tabs.append(tab)
		StationStyle.animate_button(tab)
	var controls := _page("Controls")
	var display := _page("Display")
	var audio := _page("Sound")
	var shift := _page("Shift")
	_tabs[0].button_pressed = true
	var hint := Label.new()
	hint.text = "WASD  Move      E  Interact      F  Flashlight\nShift  Sprint      Ctrl  Crouch      P  Phone      J  Journal"
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_color_override("font_color", StationStyle.MUTED)
	hint.add_theme_constant_override("line_spacing", 12)
	controls.add_child(hint)
	_sensitivity = _slider_row(controls, "Mouse sensitivity", 0.5, 6.0, 0.1, float(_player.mouse_sensitivity) * 1000.0 if _player else 2.5)
	_toggle_crouch = _toggle_row(controls, "Toggle crouch")
	_toggle_sprint = _toggle_row(controls, "Toggle sprint")
	_render_scale = _slider_row(display, "3D render scale", 50, 100, 5, 75)
	_render_scale.tooltip_text = "Lower values improve FPS. Text and interface stay at full resolution."
	_show_fps = _toggle_row(display, "Show FPS counter")
	_reduced_motion = _toggle_row(display, "Reduce camera and menu motion")
	_reduced_flashes = _toggle_row(display, "Reduce flashing lights")
	_retro = _toggle_row(display, "Retro pixels, dither and fog")
	_text_scale = _slider_row(display, "HUD text size", 1.0, 1.35, 0.05, 1.0)
	_volume = _slider_row(audio, "Master volume", 0, 100, 1, 100)
	for bus in ["SFX", "Ambience", "Music"]:
		_bus_sliders[bus] = _slider_row(audio, bus + " volume", 0, 100, 1, 100)
	_load_settings()
	_apply_settings()
	_volume.value_changed.connect(_settings_changed)
	_sensitivity.value_changed.connect(_settings_changed)
	_text_scale.value_changed.connect(_settings_changed)
	_render_scale.value_changed.connect(_settings_changed)
	for slider: HSlider in _bus_sliders.values(): slider.value_changed.connect(_settings_changed)
	for toggle in [_retro, _toggle_crouch, _toggle_sprint, _reduced_flashes, _reduced_motion, _show_fps]:
		toggle.toggled.connect(func(_enabled: bool) -> void: _settings_changed(0))
	if is_main_menu:
		_tabs[3].hide()
	else:
		var restart := _action(shift, "Restart shift", _restart_shift)
		var save := _action(shift, "Save shift", func() -> void: GameManager.save_game())
		var load_button := _action(shift, "Load latest checkpoint", func() -> void: GameManager.load_game())
		if Coop.active:
			restart.disabled = Coop.is_client()
			save.disabled = Coop.is_client()
			load_button.hide()
			_action(shift, "Leave co-op session", func() -> void: Coop.leave("You left the session."))
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameManager.notice_posted.connect(message.set_text)
	content.add_child(message)
	_overlay.hide()
	get_viewport().size_changed.connect(_layout_sheet)
	_layout_sheet()


func _layout_sheet() -> void:
	var screen := get_viewport().get_visible_rect().size
	var factor := minf(1.15, minf(screen.x / 1020.0, screen.y / 750.0))
	_sheet.scale = Vector2.ONE * factor
	_sheet.position = Vector2(screen.x * 0.075, (screen.y - _sheet.size.y * factor) * 0.5)


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pages.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


func _slider_row(parent: Node, title: String, low: float, high: float, increment: float, initial: float) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 58
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 270
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = increment
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = title
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", StationStyle.AMBER)
	row.add_child(value)
	var refresh := func(number: float) -> void:
		value.text = ("%d%%" % roundi(number)) if high == 100 else (("%d%%" % roundi(number * 100)) if high < 2 else "%.1f" % number)
	slider.value_changed.connect(refresh)
	refresh.call(initial)
	return slider


func _toggle_row(parent: Node, title: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.custom_minimum_size.y = 54
	parent.add_child(toggle)
	return toggle


func _action(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 52
	button.pressed.connect(action)
	parent.add_child(button)
	StationStyle.animate_button(button)
	return button


func _process(delta: float) -> void:
	if not _fps_counter.visible: return
	_fps_elapsed += delta
	if _fps_elapsed >= 0.25:
		_fps_elapsed = 0.0
		_update_fps_counter()


func _update_fps_counter() -> void:
	_fps_counter.text = "%d FPS" % Engine.get_frames_per_second()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		var desk := get_tree().get_first_node_in_group("booth_desk")
		if desk and desk.computer_active:
			desk.exit_computer()
			get_viewport().set_input_as_handled()
			return
		var report := get_tree().get_first_node_in_group("shift_report")
		if report and report.is_open: return
		set_paused(not _overlay.visible if is_main_menu or Coop.active else not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	var terminal: bool = not is_main_menu and GameManager.state in [GameManager.NightState.DEAD, GameManager.NightState.SHIFT_OVER]
	get_tree().paused = (paused or is_main_menu or terminal) and not Coop.active
	if Coop.active and is_instance_valid(_player): _player.set_meta("local_menu", paused)
	if paused and not _overlay.visible:
		_return_focus = get_viewport().gui_get_focus_owner()
	_overlay.visible = paused
	if not paused and is_instance_valid(_return_focus): _return_focus.grab_focus()
	var inspecting: bool = is_instance_valid(_player) and _player.in_booth_inspection
	var physical_desk: bool = is_instance_valid(_player) and _player._physical_desk_active()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused or (inspecting and not physical_desk) or is_main_menu else Input.MOUSE_MODE_CAPTURED
	if paused:
		StationStyle.reveal(_overlay)
		_resume.grab_focus()
	elif _dirty:
		var config := ConfigFile.new()
		config.set_value("audio", "master_volume", _volume.value)
		config.set_value("controls", "sensitivity", _sensitivity.value)
		config.set_value("controls", "toggle_crouch", _toggle_crouch.button_pressed)
		config.set_value("controls", "toggle_sprint", _toggle_sprint.button_pressed)
		config.set_value("display", "render_scale", _render_scale.value)
		config.set_value("display", "show_fps", _show_fps.button_pressed)
		config.set_value("display", "retro", _retro.button_pressed)
		config.set_value("display", "reduced_flashes", _reduced_flashes.button_pressed)
		config.set_value("display", "reduced_motion", _reduced_motion.button_pressed)
		config.set_value("display", "hud_text_scale", _text_scale.value)
		for bus in _bus_sliders: config.set_value("audio", bus, _bus_sliders[bus].value)
		if config.save(settings_path) == OK:
			_dirty = false


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		_volume.value = clampf(float(config.get_value("audio", "master_volume", 100.0)), 0.0, 100.0)
		_sensitivity.value = clampf(float(config.get_value("controls", "sensitivity", _sensitivity.value)), 0.5, 6.0)
		_toggle_crouch.button_pressed = bool(config.get_value("controls", "toggle_crouch", false))
		_toggle_sprint.button_pressed = bool(config.get_value("controls", "toggle_sprint", false))
		_render_scale.value = clampf(float(config.get_value("display", "render_scale", 75.0)), 50.0, 100.0)
		_show_fps.button_pressed = bool(config.get_value("display", "show_fps", false))
		_retro.button_pressed = bool(config.get_value("display", "retro", false))
		_reduced_motion.button_pressed = bool(config.get_value("display", "reduced_motion", false))
		_reduced_flashes.button_pressed = bool(config.get_value("display", "reduced_flashes", false))
		_text_scale.value = clampf(float(config.get_value("display", "hud_text_scale", 1.0)), 1.0, 1.35)
		for bus in _bus_sliders: _bus_sliders[bus].value = clampf(float(config.get_value("audio", bus, 100.0)), 0, 100)


func _settings_changed(_value: float) -> void:
	_dirty = true
	_apply_settings()



func _apply_settings() -> void:
	get_viewport().scaling_3d_scale = _render_scale.value / 100.0
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	_fps_counter.visible = _show_fps.button_pressed
	_update_fps_counter()
	AudioServer.set_bus_mute(0, _volume.value <= 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume.value / 100.0, 0.001)))
	if is_instance_valid(_player):
		_player.mouse_sensitivity = _sensitivity.value / 1000.0
		_player.toggle_crouch = _toggle_crouch.button_pressed
		_player.toggle_sprint = _toggle_sprint.button_pressed
		_player.enable_head_bob = not _reduced_motion.button_pressed
	get_tree().call_group("retro_effect", "set_enabled", _retro.button_pressed)
	get_tree().call_group("night_hud", "set_text_scale", _text_scale.value)
	for bus in _bus_sliders:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_mute(index, _bus_sliders[bus].value <= 0)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(_bus_sliders[bus].value / 100.0, 0.001)))


func _restart_shift() -> void:
	if Coop.active:
		if not Coop.is_client(): Coop.restart_shift()
		return
	set_paused(false)
	GameManager.start_night(GameManager.night)
	get_tree().reload_current_scene()


func reduced_flashes() -> bool:
	return _reduced_flashes != null and _reduced_flashes.button_pressed
