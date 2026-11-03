class_name Interactable
extends Node

## Attach to a collider or its controller. All player interactions use this contract.
var enabled: bool = true
var hold_seconds: float = 0.0
var prompt: String = "[E] Interact"
var prompt_provider: Callable
var action: Callable


func get_prompt() -> String:
	return str(prompt_provider.call()) if prompt_provider.is_valid() else prompt


func interact() -> void:
	if enabled and action.is_valid():
		var session := get_node_or_null("/root/Coop")
		if session and session.active and not session.local_interaction(self):
			session.request_interaction(self)
		else:
			action.call()


static func attach(target: Node, callback: Callable, text: Callable, duration: float = 0.0) -> Interactable:
	# Resolve our script directly even before the editor registers class_name.
	var interaction := target.get_node_or_null("Interaction") as Interactable
	if interaction == null:
		interaction = load("res://scripts/interactable.gd").new()
		interaction.name = "Interaction"
		target.add_child(interaction)
	interaction.name = "Interaction"
	interaction.action = callback
	interaction.prompt_provider = text
	interaction.hold_seconds = duration
	return interaction


static func resolve(collider: Node) -> Interactable:
	var node := collider
	while node != null:
		var interaction := node.get_node_or_null("Interaction") as Interactable
		if interaction:
			return interaction
		node = node.get_parent()
	return null
