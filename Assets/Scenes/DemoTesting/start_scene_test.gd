extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
		DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	
func _on_dialogue_ended(_resource: DialogueResource) -> void:
	Global.scene_manager.change_scene("Forest",Vector2.ZERO)
