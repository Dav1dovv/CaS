extends Creature
class_name Nox

var player_in_fear_zone : bool = false

func _on_fearzone_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		$Timer.start()
		player_in_fear_zone = true
		can_flee = true
		if is_instance_valid(target):
			_enter_state(State.FLEE)
		else:
			# Игрок вне зоны видимости — просто бредём прочь от home
			_enter_state(State.WANDER)

func _on_fearzone_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_fear_zone = false
		$Timer.stop()
	


func _on_timer_timeout() -> void:
	if player_in_fear_zone:
		can_flee = true
		if is_instance_valid(target):
			_enter_state(State.FLEE)
		else:
			# Игрок вне зоны видимости — просто бредём прочь от home
			_enter_state(State.WANDER)
			if player_in_fear_zone : $Timer.start()
