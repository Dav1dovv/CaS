extends Sprite2D

@onready var gui: CanvasLayer = %GUI
@onready var interaction: interaction_area = $interaction_area

func _ready() -> void:
	interaction.interact = Callable(self, "open_sell_ui")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func open_sell_ui() -> void:
	gui.show_sell_ui()
