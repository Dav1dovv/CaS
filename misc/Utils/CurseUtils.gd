class_name CurseUtils
extends RefCounted

## Общая логика для Harvestable и CurseObject — раньше была продублирована
## в обоих местах. Возвращает множитель заражения в зависимости от
## брони/амулетов игрока.
## 1.0 = без защиты, 0.0 = полный иммунитет.
## TODO: подключить к системе брони когда она будет реализована.
static func get_armor_curse_multiplier(player: Node) -> float:
	if player == null:
		return 1.0
	if player.has_method("get_curse_resistance"):
		return 1.0 - clamp(player.get_curse_resistance(), 0.0, 1.0)
	return 1.0
