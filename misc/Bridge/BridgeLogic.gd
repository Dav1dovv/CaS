extends Node2D

@onready var interaction: interaction_area = $interaction_area
@export var need_count : int = 80
@export var is_builded : bool = false
const WOOD = preload("uid://10qblpi41tcd")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if is_builded:
		$Broken.queue_free()
		$interaction_area.queue_free()
		$Builded.visible = true
	
	else:
		interaction.interact = Callable(self, "build")
		interaction.show_message = "Build X" + str(need_count)
	

func build() -> void:
	if Global.inventory.has_total_item(WOOD,need_count):
		Global.scene_manager.fade()
		$Broken.queue_free()
		$interaction_area.queue_free()
		$Builded.visible = true
	
	
	

func _on_interaction_area_area_entered(area: Area2D) -> void:
		if Global.inventory.has_total_item(WOOD,need_count):
			Cursor.modulate = Color.WHITE
		else : Cursor.modulate = Color.RED


func _on_interaction_area_area_exited(area: Area2D) -> void:
	Cursor.modulate = Color.WHITE
