extends RefCounted
## Shared station equipment palette. Decoration stays behind readable text.

const BODY_FONT = preload("res://ui/fonts/SpecialElite.ttf")

const INK := Color("101719")
const PAPER := Color("dfdfcf")
const AMBER := Color("c5a16b")
const MUTED := Color("899494")

static func surface(background: Color = Color(0.055, 0.075, 0.079, 0.79), edge: Color = Color(0.65, 0.70, 0.65, 0.16)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	style.set_content_margin_all(22)
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY_FONT
	result.default_font_size = 20
	result.set_color("font_color", "Label", PAPER)
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_hover_color", "Button", Color("fff1d6"))
	result.set_color("font_focus_color", "Button", Color("fff1d6"))
	result.set_color("font_disabled_color", "Button", Color("667071"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := surface(Color(0.4, 0.45, 0.43, 0.035), Color.TRANSPARENT)
		style.shadow_size = 0
		style.set_content_margin_all(12)
		style.content_margin_left = 18
		style.content_margin_right = 18
		if state == "hover" or state == "focus":
			style.bg_color = Color(0.7, 0.72, 0.63, 0.10)
		if state == "pressed": style.bg_color = Color(0.7, 0.6, 0.4, 0.18)
		if state == "disabled": style.bg_color = Color.TRANSPARENT
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.set_border_width_all(0)
			style.border_width_bottom = 2
			style.border_color = AMBER
		result.set_stylebox(state, "Button", style)
	result.set_stylebox("normal", "LineEdit", surface(Color(0.03, 0.04, 0.045, 0.55)))
	result.set_stylebox("focus", "LineEdit", surface(Color(0.05, 0.07, 0.075, 0.65), AMBER))
	result.set_color("font_color", "LineEdit", PAPER)
	result.set_color("caret_color", "LineEdit", AMBER)
	result.set_color("font_color", "CheckButton", PAPER)
	result.set_color("font_hover_color", "CheckButton", AMBER)
	result.set_constant("separation", "CheckButton", 14)
	for state in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		var toggle := StyleBoxFlat.new()
		toggle.bg_color = Color.TRANSPARENT
		toggle.content_margin_top = 12
		toggle.content_margin_bottom = 12
		result.set_stylebox(state, "CheckButton", toggle)
	var empty := StyleBoxEmpty.new()
	result.set_stylebox("panel", "TabContainer", empty)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("354345")
	track.set_content_margin_all(2)
	result.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = AMBER
	result.set_stylebox("grabber_area", "HSlider", fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return result

static func backdrop(parent: Node) -> ColorRect:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = preload("res://ui/modal_backdrop.gdshader")
	shade.material = material
	parent.add_child(shade)
	return shade

static func reduced_motion(node: Node) -> bool:
	var menus := node.get_tree().get_nodes_in_group("pause_menu")
	for menu in menus:
		if menu._reduced_motion != null: return menu._reduced_motion.button_pressed
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	return bool(config.get_value("display", "reduced_motion", false))

static func reveal(control: Control) -> void:
	if control.has_meta("reveal_tween"):
		var previous: Tween = control.get_meta("reveal_tween")
		if previous.is_valid(): previous.kill()
	control.modulate.a = 1.0
	if reduced_motion(control): return
	control.modulate.a = 0.0
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	control.set_meta("reveal_tween", tween)

static func animate_button(button: BaseButton) -> void:
	var wash := Panel.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.show_behind_parent = true
	var wash_style := surface(Color(0.7, 0.66, 0.5, 0.10), Color.TRANSPARENT)
	wash_style.shadow_size = 0
	wash.add_theme_stylebox_override("panel", wash_style)
	wash.modulate.a = 0.0
	button.add_child(wash)
	var refresh := func() -> void:
		if button.has_meta("hover_tween"):
			var previous: Tween = button.get_meta("hover_tween")
			if previous.is_valid(): previous.kill()
		var active := button.is_hovered() or button.has_focus()
		var tint := Color(1.08, 1.05, 0.97) if active else Color.WHITE
		if reduced_motion(button):
			wash.modulate.a = 1.0 if active else 0.0
			button.modulate = tint
			return
		var tween := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_parallel(true)
		tween.tween_property(button, "modulate", tint, 0.14)
		tween.tween_property(wash, "modulate:a", 1.0 if active else 0.0, 0.18)
		button.set_meta("hover_tween", tween)
	button.mouse_entered.connect(refresh)
	button.mouse_exited.connect(refresh)
	button.focus_entered.connect(refresh)
	button.focus_exited.connect(refresh)
