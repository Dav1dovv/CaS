extends Sprite2D

@onready var interaction: interaction_area = $Interaction

func _ready() -> void:
	interaction.interact = Callable(self, "_call_UI")


func _call_UI():
	if !Global.is_opened_menu:
		Global.inventory.call_workbench()
		Global.is_opened_menu = true
