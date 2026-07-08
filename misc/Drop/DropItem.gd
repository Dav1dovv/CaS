extends Node
class_name Drop_items

@export var drop_item : Array[ItemData]
@export var unique_items : Array[weight_item] 
@export var max_drop : int
@export var random_values : bool = false
const DROP = preload("uid://drqvpabe55ide")
const DROPED_HEART = preload("uid://ciane2i2vcc0q")



func _drop_items() -> void:
	var root = get_tree().get_first_node_in_group("World")
	if root == null:
		return
	var drop_count = randi_range(4, max_drop)
	
	for i in drop_count:
		var new_drop = DROP.instantiate()
		var selected_item: ItemData = null
		
		# Проверяем уникальные предметы по приоритету
		if !unique_items.is_empty():
			for unique in unique_items:
				if randf() <= unique.weight:
					selected_item = unique.item
					print("Dropped unique: ", unique.item.item_name)
					break  # Выпал уникальный — больше не проверяем
		
		# Если ничего уникального не выпало — берём обычный
		if selected_item == null && !drop_item.is_empty():
			selected_item = drop_item[randi() % drop_item.size()]
			if random_values and selected_item.is_class("equip_data"):
				selected_item.Damage += 10 / randi_range(0,6)
				
		# Если и обычных нет — ничего не дропаем (на всякий случай)
		if selected_item != null:
			new_drop.update_drop(selected_item)
			new_drop.global_position = get_parent().global_position + Vector2(
				randf_range(-10.0, 10.0),
				randf_range(-10.0, 10.0)
			)
			root.call_deferred("add_child", new_drop)

func drop_bonus_heart():
	var root = get_tree().get_first_node_in_group("World")
	var new_drop = DROPED_HEART.instantiate()
	new_drop.global_position = get_parent().global_position + Vector2(
		randf_range(-10.0, 10.0),
		randf_range(-10.0, 10.0)
	)
	root.call_deferred("add_child", new_drop)
