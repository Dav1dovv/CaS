extends VisibleOnScreenEnabler2D
class_name optimizer

@export var hide_objects : Array[Node]

func _init() -> void:
	connect("screen_entered",on_screen)
	connect("screen_exited",non_screen)
	non_screen()
	pass

func on_screen():
	for i in hide_objects.size():
		if !hide_objects[i] == null:
			hide_objects[i].visible = true

func non_screen():
	for i in hide_objects.size():
		if !hide_objects[i]== null:
			hide_objects[i].visible = false
