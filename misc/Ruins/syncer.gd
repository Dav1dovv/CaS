extends Node2D

@onready var interaction : interaction_area = $interaction_area

func _ready() -> void:
	interaction.interact = Callable(self, "save_point")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func save_point():
	var game = get_tree().get_first_node_in_group("World")
	var player = get_tree().get_first_node_in_group("Player")
	game.set_spawn_point(player.position)
