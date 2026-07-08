extends Creature

@export var static_agr : float

func _process(delta: float) -> void:
	if Global.day_night.current_phase == Global.day_night.Phase.NIGHT:
		behavior = 0.75
		_resolve_behavior_type()

		# Если стал агрессивным и видит игрока — немедленно атаковать
		if behavior_type == BehaviorType.Aggressive and is_instance_valid(target):
			if current_state not in [State.CHASE, State.ATTACK]:
				_enter_state(State.CHASE)
	elif Global.day_night.current_phase == Global.day_night.Phase.DAY:
		behavior = static_agr
		_resolve_behavior_type()

		# Если стал агрессивным и видит игрока — немедленно атаковать
		if behavior_type == BehaviorType.Aggressive and is_instance_valid(target):
			if current_state not in [State.CHASE,State.WANDER, State.ATTACK]:
				_enter_state(State.WANDER)
