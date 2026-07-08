extends Creature
class_name Slime

var agr_phase : int = 0


func _on_Damaged(new_health: float) -> void:
	if agr_phase > 3:
		agr_phase += 1
		 
		# Каждый удар делает слайма агрессивнее (шаг 0.2, не 0.7 — иначе с первого же удара максимум)
		behavior += 0.3
		Entity_stats.move_speed += 1.5
		$Skin/AnimationPlayer.speed_scale += 0.2
		$HitBox.equip.Damage += 1
		_resolve_behavior_type()

	# Если стал агрессивным и видит игрока — немедленно атаковать
	if behavior_type == BehaviorType.Aggressive and is_instance_valid(target):
		if current_state not in [State.CHASE, State.ATTACK]:
			_enter_state(State.CHASE)
	elif behavior_type == BehaviorType.Aggressive:
		# Цели нет — ищем немедленно, не ждать следующего тика
		for player in get_tree().get_nodes_in_group("Player"):
			if player is Node2D and _can_sense(player):
				_acquire_target(player)
				break
