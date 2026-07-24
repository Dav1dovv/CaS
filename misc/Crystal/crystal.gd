extends Node2D

@export_enum("Forest","Desert","Other") var biom_crystal : String = "Forest"

func _process(delta: float) -> void:
	var corruption_strength = clamp(Global.corruption / 100.0, 0.0, 1.0)
	$Crystal.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.0, 0.0, 1.0, 1.0), corruption_strength)
