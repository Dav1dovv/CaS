extends Harvestable

@export var Boss : PackedScene

# Переопределяем логику уничтожения из Harvestable
func _on_tree_exiting() -> void:
	_spawn_boss_delayed(0.1)  # задержка 2 секунды

func _spawn_boss_delayed(delay: float) -> void:
	print("Started spawn boss")
	if Boss == null:
		print("Boss not found")
		return

	var timer = Timer.new()
	get_parent().add_child(timer)  # добавляем к родителю, не к себе
	timer.wait_time = delay
	timer.one_shot = true
	timer.start()

	var boss_instance = Boss.instantiate()
	var spawn_pos = Vector2(
		global_position.x + randf_range(-10, 10),
		global_position.y + randf_range(-10, 10)
	)
	boss_instance.global_position = spawn_pos

	get_parent().get_parent().add_child(boss_instance)
	print("Boss spawned at : " + str(spawn_pos))
	timer.queue_free()
