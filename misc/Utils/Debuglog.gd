class_name DebugLog
extends RefCounted

## Обёртка над print() — печатает только в debug-сборке (редактор / debug export).
## В релизном экспорте print() ничего не стоит по CPU, но полезно не засорять
## консоль игрока боевым спамом (удары, урон и т.д.).
static func log(message: String) -> void:
	if OS.is_debug_build():
		print(message)
