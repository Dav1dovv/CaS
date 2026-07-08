extends Sprite2D

@onready var interaction: interaction_area = $interaction_area
enum actor_types {Swordsman, Sciensist}
@export var actor : actor_types = actor_types.Swordsman 
var inventory

func _ready() -> void:
	inventory = get_tree().get_first_node_in_group("Inventory")
	interaction.interact = Callable(self, "open_shop")

func open_shop():
	match actor:
		actor_types.Swordsman:
			inventory.call_craft()
		actor_types.Sciensist:
			inventory.call_sciensist()
