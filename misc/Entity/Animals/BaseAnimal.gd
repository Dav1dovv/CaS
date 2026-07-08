extends Creature
class_name SimpleAnimal

			
func _on_Damaged(new_health: float) -> void:
	can_flee = true
	if is_instance_valid(target):
		_enter_state(State.FLEE)
	else:
		# Игрок вне зоны видимости — просто бредём прочь от home
		_enter_state(State.WANDER)
