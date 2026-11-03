extends CanvasLayer

var _shade: ColorRect
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_shade = ColorRect.new()
	_shade.color = Color.BLACK
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	call_deferred("_begin_fade")


func _begin_fade() -> void:
	# Keep the first frame black until local setup and the crew's loading barrier finish.
	for frame in range(2): await get_tree().process_frame
	while Coop.active and not Coop.world_live:
		await get_tree().process_frame
	var reduced := preload("res://ui/station_skin.gd").reduced_motion(self)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if not reduced: _tween.tween_interval(0.25)
	_tween.tween_property(_shade, "modulate:a", 0.0, 0.35 if reduced else 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(queue_free)
