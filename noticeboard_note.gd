@tool
extends Resource

## Editable note content, refreshed on the board when changed.
@export_multiline var text: String = "Write your note here":
	set(value):
		text = value
		emit_changed()

@export var paper_color: Color = Color(1.0, 0.9, 0.52):
	set(value):
		paper_color = value
		emit_changed()
