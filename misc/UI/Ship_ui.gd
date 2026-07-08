extends CanvasLayer

@onready var planetmanager: Panel = $PlanetChooserUI
@onready var sell_ui: Panel = $Sell_UI

func show_planet_manager() -> void:
	visible = true
	planetmanager.visible = true

func show_sell_ui() -> void:
	visible = true
	sell_ui.visible = true

func _on_button_pressed() -> void:
	for i in get_child_count():
		get_child(i).visible = false
		visible = false
