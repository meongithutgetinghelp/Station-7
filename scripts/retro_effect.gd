extends CanvasLayer
var _effect: ColorRect

func _ready() -> void:
	layer = 1
	add_to_group("retro_effect")
	_effect = ColorRect.new()
	_effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/retro_screen.gdshader")
	_effect.material = material
	add_child(_effect)
	_effect.hide()

func set_enabled(enabled: bool) -> void:
	_effect.visible = enabled
	var environment := get_parent().get_node("WorldEnvironment") as WorldEnvironment
	environment.environment.fog_enabled = enabled
	environment.environment.fog_density = 0.006 if enabled else 0
	environment.environment.fog_light_color = Color(0.2, 0.28, 0.26)
