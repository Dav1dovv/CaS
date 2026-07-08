extends Creature
class_name Trader

@onready var interaction: interaction_area = $interaction_area

@export var dialog_timeline: Array[String]
@export var TradeData : TraderData

## Расстояние, на котором НПС останавливается и смотрит на игрока
@export var awareness_radius: float = 80.0
## Расстояние, на котором НПС поворачивается лицом к игроку
@export var face_player_radius: float = 40.0

var inventory
@export var player: Player

var _npc_stopped: bool = false

func _ready() -> void:
	super._ready()
	if !player:
		player = get_tree().get_first_node_in_group("Player")
	inventory = get_tree().get_first_node_in_group("Inventory")
	interaction.interact = Callable(self, "Interact")

func Interact() -> void:
	Global.Trade(TradeData)
	#if !dialog_timeline.is_empty():
		#Dialogic.start(dialog_timeline.pick_random())
	#else:
		#push_warning("NPC '%s': dialog_timeline не задан!" % name)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if current_state == State.DEAD:
		return

	var dist := global_position.distance_to(player.global_position)

	if dist <= face_player_radius:
		# Смотрим на игрока — останавливаемся и поворачиваемся
		if not _npc_stopped:
			_npc_stopped = true
			_enter_state(State.IDLE)
		var dir_to_player := (player.global_position - global_position).normalized()
		_facing_dir = dir_to_player
		if dir_to_player.x != 0.0:
			$Skin.scale.x = -1.0 if dir_to_player.x < 0.0 else 1.0

	elif dist <= awareness_radius:
		# В зоне осведомлённости — останавливаемся, но не поворачиваемся
		if not _npc_stopped:
			_npc_stopped = true
			_enter_state(State.IDLE)

	else:
		# Игрок ушёл — возобновляем обычное поведение
		if _npc_stopped:
			_npc_stopped = false
			_enter_state(_default_start_state())
