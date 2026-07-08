# inventory.gd
# Оригинальный + слот золота (GoldSlot)
#
# ИЗМЕНЕНИЯ В ЭТОЙ ВЕРСИИ:
#  • get_total_item_count() больше не сканирует все слоты линейно на каждый вызов.
#    Вместо этого ведётся кэш _count_cache (ItemData -> int), который лениво
#    пересчитывается при первом обращении после inventory_changed/hotbar_changed.
#    Это особенно заметно в CraftStation, где count запрашивается на каждый
#    ингредиент при каждом refresh.
#  • items_storage (список всех ItemData из res://scr/Resources/Items/) теперь
#    кэшируется на уровне класса (static), а не пересканируется с диска в _init()
#    каждый раз, когда создаётся новый Inventory (например, при пересборке UI).
extends Control
class_name Inventory

signal inventory_changed

@onready var grid_container: GridContainer = $HBoxContainer/Inventory/VBoxContainer/HBoxContainer/GridContainer
@onready var hotbar: Hotbar = $HotBar

#Menus
@onready var inventory: Panel = $HBoxContainer/Inventory
@onready var smith: Control = $HBoxContainer/Smith
@onready var barmen: Control = $HBoxContainer/Barmen
@onready var trade_window: TradeWindow = $HBoxContainer/TradeWindow


# ── Слот золота ──────────────────────────────────────────────────
# Добавь ноду: HBoxContainer/Inventory/VBoxContainer/GoldSlot
@onready var gold_slot: GoldSlot

var items: Array[InventorySlotData] = []
var items_storage: Array[ItemData]

# Кэш списка предметов на уровне класса — грузится с диска один раз за сессию,
# а не при каждом создании ноды Inventory.
static var _items_storage_cache: Array[ItemData] = []
static var _items_storage_loaded: bool = false

# Кэш "сколько всего предмета в инвентаре+хотбаре" — ключ: resource_path (или
# item_name, если путь пуст), значение: суммарное количество.
var _count_cache: Dictionary = {}
var _count_cache_dirty: bool = true

func _init() -> void:
	_load_all_items()

func _ready() -> void:
	_initialize_slots()
	_initialize_gold_slot()
	Global.inventory = self
	Global.developer_console.register_command("all_items_list", _cmd_list, "List all items")
	Global.developer_console.register_command("add_item", _cmd_add_item, "Usage: add_item [itm_indx] [count]")
	gold_slot = get_tree().get_first_node_in_group("CoinSlot")

	inventory_changed.connect(_mark_count_cache_dirty)
	if hotbar:
		hotbar.hotbar_changed.connect(_mark_count_cache_dirty)

# ─────────────────────────────────────────────────────────────────
#  ИНИЦИАЛИЗАЦИЯ
# ─────────────────────────────────────────────────────────────────
func _load_all_items() -> void:
	if _items_storage_loaded:
		items_storage = _items_storage_cache
		return

	_items_storage_cache = []
	var dir = DirAccess.open("res://scr/Resources/Items/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var itm: Resource = load("res://scr/Resources/Items/" + file_name)
				if itm is ItemData:
					_items_storage_cache.append(itm)
			file_name = dir.get_next()

	_items_storage_loaded = true
	items_storage = _items_storage_cache

func _initialize_slots() -> void:
	items.clear()
	for child in grid_container.get_children():
		if child is InventorySlot:
			var data = InventorySlotData.new()
			data.slot_node = child
			items.append(data)
			child.inventory = self

func _initialize_gold_slot() -> void:
	if gold_slot:
		gold_slot.inventory = self

# ─────────────────────────────────────────────────────────────────
#  ДОБАВЛЕНИЕ ПРЕДМЕТОВ
# ─────────────────────────────────────────────────────────────────
func add_item(item_data: ItemData, amount: int = 1) -> bool:
	if not item_data or amount <= 0:
		return false

	var remaining := amount

	# Стакаем в существующие слоты
	for data in items:
		if remaining <= 0:
			break
		if data.item and _is_same_item(data.item, item_data) and item_data.stackable:
			var space: int = item_data.max_count - data.amount
			if space > 0:
				var add: int = mini(remaining, space)
				data.amount += add
				data.slot_node.item    = data.item
				data.slot_node.ammount = data.amount
				data.slot_node.update_ui()
				remaining -= add

	# Раскладываем по пустым слотам
	for data in items:
		if remaining <= 0:
			break
		if data.item == null:
			# Дублируем только стакаемые предметы; нестакаемые — напрямую
			data.item   = item_data.duplicate() if item_data.stackable else item_data
			var add: int = mini(remaining, item_data.max_count)
			data.amount  = add
			data.slot_node.item    = data.item
			data.slot_node.ammount = data.amount
			data.slot_node.update_ui()
			remaining -= add

	if remaining < amount:
		emit_signal("inventory_changed")
		return true

	push_warning("Inventory full! Could not add: %s" % item_data.item_name)
	return false

# ─────────────────────────────────────────────────────────────────
#  УТИЛИТЫ
# ─────────────────────────────────────────────────────────────────
func _is_same_item(a: ItemData, b: ItemData) -> bool:
	if a == null or b == null: return false
	if a.resource_path != "" and a.resource_path == b.resource_path: return true
	if a.item_name == b.item_name and a.get_class() == b.get_class(): return true
	return false

## Ключ для кэша количества — стараемся использовать resource_path (стабилен
## для всех дубликатов одного и того же ресурса), иначе падаем на item_name.
func _count_key(item: ItemData) -> String:
	if item.resource_path != "":
		return item.resource_path
	return item.item_name

func _mark_count_cache_dirty() -> void:
	_count_cache_dirty = true

## Пересчитывает _count_cache целиком за один проход по items+hotbar.slots.
## Вызывается лениво — только когда данные реально устарели, а не на каждый
## get_total_item_count().
func _rebuild_count_cache() -> void:
	_count_cache.clear()
	if hotbar and hotbar.slots:
		for slot_data in hotbar.slots:
			if slot_data.item:
				var key := _count_key(slot_data.item)
				_count_cache[key] = _count_cache.get(key, 0) + slot_data.amount
	for slot_data in items:
		if slot_data.item:
			var key := _count_key(slot_data.item)
			_count_cache[key] = _count_cache.get(key, 0) + slot_data.amount
	_count_cache_dirty = false

## Раньше — полный линейный проход по items+hotbar на КАЖДЫЙ вызов.
## Теперь — O(1) обращение к предпосчитанному кэшу (пересчёт только когда
## инвентарь реально менялся).
func get_total_item_count(search_item: ItemData) -> int:
	if not search_item: return 0
	if _count_cache_dirty:
		_rebuild_count_cache()
	return _count_cache.get(_count_key(search_item), 0)

func has_total_item(search_item: ItemData, required_amount: int) -> bool:
	return get_total_item_count(search_item) >= required_amount

func remove_from_total(search_item: ItemData, amount: int) -> bool:
	if amount <= 0 or not search_item: return true
	var remaining: int = amount
	var changed: bool = false

	if hotbar and hotbar.slots:
		for slot_data in hotbar.slots:
			if remaining <= 0: break
			if _is_same_item(slot_data.item, search_item):
				var remove_amt: int = mini(remaining, slot_data.amount)
				slot_data.amount -= remove_amt
				remaining -= remove_amt
				changed = true
				if slot_data.amount <= 0:
					slot_data.item = null
					slot_data.slot_node.item = null
				slot_data.slot_node.ammount = slot_data.amount
				slot_data.slot_node.update_ui()

	for slot_data in items:
		if remaining <= 0: break
		if _is_same_item(slot_data.item, search_item):
			var remove_amt: int = mini(remaining, slot_data.amount)
			slot_data.amount -= remove_amt
			remaining -= remove_amt
			changed = true
			if slot_data.amount <= 0:
				slot_data.item = null
				slot_data.slot_node.item = null
			slot_data.slot_node.ammount = slot_data.amount
			slot_data.slot_node.update_ui()

	if changed:
		emit_signal("inventory_changed")
		if hotbar:
			hotbar.emit_signal("hotbar_changed")
			hotbar._recalculate_accessories()

	return remaining <= 0

func get_slot_data_by_node(slot_node: InventorySlot) -> InventorySlotData:
	for data in items:
		if data.slot_node == slot_node:
			return data
	return null

func can_add_item(item_data: ItemData, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	var remaining: int = amount
	var all_slots: Array[InventorySlotData] = items.duplicate()
	if hotbar and hotbar.slots:
		all_slots.append_array(hotbar.slots)
	# Считаем пространство в существующих стаках
	for slot_data in all_slots:
		if slot_data.item and _is_same_item(slot_data.item, item_data) and item_data.stackable:
			var space: int = item_data.max_count - slot_data.amount
			if space > 0:
				remaining -= mini(remaining, space)
				if remaining <= 0:
					return true
	# Считаем пустые слоты
	for slot_data in all_slots:
		if slot_data.item == null:
			remaining -= item_data.max_count
			if remaining <= 0:
				return true
	return false

func get_save_path() -> String:
	return "user://Saves/%s/inventory.save" % Global.player_name

# ─────────────────────────────────────────────────────────────────
#  ОТКРЫТИЕ / ЗАКРЫТИЕ
# ─────────────────────────────────────────────────────────────────
var is_opened: bool = false

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("CallInventory"):
		toggle_inv()

func toggle_inv():
	call_inventory()

func call_inventory():
	if Global.is_opened_menu && !is_opened:
		return
	is_opened = !is_opened
	Global.is_opened_menu = is_opened
	$HBoxContainer.visible = is_opened
	$Panel.visible = is_opened
	inventory.visible = true
	smith.visible = false
	trade_window.visible = false
	Cursor.detection_mode(is_opened)

func uncall_craft():
	is_opened = false
	Global.is_opened_menu = false
	$Panel.visible = is_opened
	$HBoxContainer.visible = false
	inventory.visible = false
	smith.visible = false
	trade_window.visible = false
	Cursor.detection_mode(false)



func call_craft():
	if Global.is_opened_menu && !is_opened:
		return
	is_opened = !is_opened
	Global.is_opened_menu = is_opened
	$HBoxContainer.visible = is_opened
	$Panel.visible = is_opened
	smith.visible = true
	inventory.visible = false
	Cursor.detection_mode(is_opened)
	if is_opened:
		smith._refresh()
		smith._update_preview()

func uncall_trade():
	is_opened = false
	Global.is_opened_menu = false
	$Panel.visible = is_opened
	$HBoxContainer.visible = false
	inventory.visible = false
	trade_window.visible = false
	Cursor.detection_mode(false)



func call_trade(Trader : TraderData):
	if Global.is_opened_menu && !is_opened:
		return
	is_opened = !is_opened
	Global.is_opened_menu = is_opened
	$HBoxContainer.visible = is_opened
	$Panel.visible = is_opened
	inventory.visible = false
	trade_window.visible = true
	Cursor.detection_mode(is_opened)
	if is_opened:
		trade_window.open(Trader)



# ─────────────────────────────────────────────────────────────────
#  DEBUG КОМАНДЫ
# ─────────────────────────────────────────────────────────────────
func _get_items_list() -> String:
	var list = "all items list:\n"
	for i in range(items_storage.size()):
		var config = items_storage[i]
		var itm = "EMPTY" if not config else config.item_name
		list += "%d: %s\n" % [i, itm]
	return list

func _cmd_list(_args: Array) -> String:
	return _get_items_list()

func _cmd_add_item(args: Array) -> String:
	if args.size() != 2:
		return "Usage: add_item [itm_index] [count]"
	var index = int(args[0])
	var count = int(args[1])
	if index < 0 or index >= items_storage.size():
		return "Error: invalid item index (use /all_items_list to see indices)"
	if count <= 0:
		return "Error: count must be > 0"
	var item_data = items_storage[index]
	Global.pickup_item(item_data, count)
	return "Added %d × %s" % [count, item_data.item_name]
