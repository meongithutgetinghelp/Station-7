extends "res://field_panel.gd"
## A physical letter, shown without the journal's rectangular document panel.

const ARTWORK = preload("res://assets/entity/letter/entity-letter.png")


func read_texture(texture: Texture2D) -> void:
	_root.get_node("LetterArtwork").texture = texture
	open_panel()


func _ready() -> void:
	layer = 25
	add_to_group("world_modal")
	StationStyle.backdrop(self)
	_root = Control.new()
	_root.theme = StationStyle.theme()
	_root.size = Vector2(900, 720)
	add_child(_root)
	var artwork := TextureRect.new()
	artwork.name = "LetterArtwork"
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.texture = ARTWORK
	artwork.position = Vector2(180, 12)
	artwork.size = Vector2(540, 636)
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(artwork)
	close_button = Button.new()
	close_button.text = "Put down letter / Tab"
	close_button.position = Vector2(275, 660)
	close_button.size = Vector2(350, 44)
	close_button.pressed.connect(close_panel)
	_root.add_child(close_button)
	StationStyle.animate_button(close_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false
