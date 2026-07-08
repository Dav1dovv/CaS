extends Panel

enum planet {Oktavia, Melaris}

@onready var location: Label = $VBoxContainer/VBoxContainer/Location
@onready var note: AutoSizeLabel = $VBoxContainer/VBoxContainer/Note

func _ready() -> void:
	location.text = "Planet: " + Global.current_location
	Global.day_night.day_changed.connect(update_info)
	

func update_info():
	location.text = "Planet: " + Global.current_location
