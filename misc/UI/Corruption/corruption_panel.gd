extends Panel

@onready var F_progress_bar: ProgressBar = $VBoxContainer/Forest_info/ProgressBar
@onready var D_progress_bar: ProgressBar = $VBoxContainer/Desert_Info/ProgressBar
@onready var T_progress_bar: ProgressBar = $VBoxContainer/Thundra_Info/ProgressBar

@onready var F_label: Label = $VBoxContainer/Forest_info/Label
@onready var D_label: Label = $VBoxContainer/Desert_Info/Label2
@onready var T_label: Label = $VBoxContainer/Thundra_Info/Label

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	F_progress_bar.value = Global.corruption
