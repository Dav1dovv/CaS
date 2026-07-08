extends Area2D
class_name Whirlpool

# ═════════════════════════════════════════════════════════════════════════════
#  ВОДОВОРОТ — затягивает, вращает и выбрасывает корабль
# ═════════════════════════════════════════════════════════════════════════════
#
# Как использовать:
# 1. Создай Area2D узел и прикрепи этот скрипт
# 2. Добавь дочерний CollisionShape2D (лучше круглый)
# 3. Опционально: добавь AnimatedSprite2D или Sprite2D для визуализации воды
# 4. Настрой параметры в инспекторе
#
# Механика:
# - Корабль затягивается к центру водоворота
# - Вращается вокруг центра с увеличением скорости
# - При достижении центра — выбрасывается в случайном направлении
#
# ═════════════════════════════════════════════════════════════════════════════

## Сила затягивания к центру (пикселей/сек²)
@export var pull_strength: float = 200.0

## Скорость вращения корабля вокруг центра (градусов/сек)
@export var rotation_speed: float = 180.0

## Радиус "ядра" водоворота — при достижении корабль выбрасывается
@export var core_radius: float = 30.0

## Сила выброса (пикселей/сек)
@export var eject_force: float = 600.0

## Урон при нахождении в водовороте (HP/сек)
@export var damage_per_second: float = 5.0

## Опциональный спрайт водоворота для визуализации
@export var visual_sprite: NodePath

# Корабли в водовороте и их данные
var ships_data: Dictionary = {}  # { ship: { angle: float, time: float } }


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Анимация спрайта (если есть)
	if not visual_sprite.is_empty():
		var sprite = get_node_or_null(visual_sprite)
		if sprite and sprite is AnimatedSprite2D:
			sprite.play()


func _physics_process(delta: float) -> void:
	for ship in ships_data.keys():
		if not is_instance_valid(ship):
			ships_data.erase(ship)
			continue
		
		_process_ship_in_whirlpool(ship, delta)


# ─── Вход корабля в водоворот ───────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.has_method("_move_toward_mouse"):
		# Инициализируем данные корабля
		var angle_to_center := (body.global_position - global_position).angle()
		ships_data[body] = {
			"angle": angle_to_center,
			"time_in_whirlpool": 0.0
		}
		print("Whirlpool: Корабль попал в водоворот!")


func _on_body_exited(body: Node2D) -> void:
	if body in ships_data:
		ships_data.erase(body)
		print("Whirlpool: Корабль покинул водоворот")


# ─── Обработка корабля внутри водоворота ────────────────────────────────────

func _process_ship_in_whirlpool(ship: Node, delta: float) -> void:
	var data: Dictionary = ships_data[ship]
	var to_center: Vector2 = global_position - ship.global_position
	var distance: float = to_center.length()
	
	# 1. ЗАТЯГИВАНИЕ К ЦЕНТРУ
	var pull_force := to_center.normalized() * pull_strength * delta
	if "_velocity" in ship:
		ship._velocity += pull_force
	
	# 2. ВРАЩЕНИЕ ВОКРУГ ЦЕНТРА
	data["angle"] += deg_to_rad(rotation_speed) * delta
	
	# Тангенциальная сила (перпендикулярно к центру)
	var tangent := Vector2(-to_center.y, to_center.x).normalized()
	var spin_force := tangent * (rotation_speed * 2.0) * delta
	if "_velocity" in ship:
		ship._velocity += spin_force
	
	# 3. ВРАЩЕНИЕ СПРАЙТА КОРАБЛЯ (для эффекта кружения)
	if "sprite" in ship and ship.sprite:
		ship.sprite.rotation += deg_to_rad(rotation_speed * 1.5) * delta
	
	# 4. УРОН ОТ ВОДОВОРОТА
	data["time_in_whirlpool"] += delta
	if ship.has_method("take_damage"):
		ship.take_damage(damage_per_second * delta)
	
	# 5. ПРОВЕРКА ДОСТИЖЕНИЯ ЦЕНТРА → ВЫБРОС
	if distance <= core_radius:
		_eject_ship(ship)


# ─── Выброс корабля из водоворота ───────────────────────────────────────────

func _eject_ship(ship: Node) -> void:
	# Случайное направление выброса
	var eject_angle := randf() * TAU
	var eject_vector := Vector2.RIGHT.rotated(eject_angle) * eject_force
	
	if "_velocity" in ship:
		ship._velocity = eject_vector
	
	print("Whirlpool: Корабль выброшен с силой %s!" % eject_force)
	
	# Удаляем из списка
	ships_data.erase(ship)
	
	# Можно добавить эффект всплеска
	_spawn_splash_effect()


# ─── Визуальный эффект выброса (опционально) ────────────────────────────────

func _spawn_splash_effect() -> void:
	# Здесь можно создать частицы, звук и т.д.
	pass


# ─── Визуализация в редакторе ───────────────────────────────────────────────

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Рисуем зону водоворота
	draw_circle(Vector2.ZERO, core_radius, Color(1, 0.3, 0.3, 0.3))  # Красное ядро
	
	# Стрелки вращения
	for i in range(8):
		var angle := (TAU / 8.0) * i
		var radius := core_radius + 20
		var start := Vector2.RIGHT.rotated(angle) * radius
		var end := Vector2.RIGHT.rotated(angle + 0.3) * (radius + 10)
		draw_line(start, end, Color(0.2, 0.5, 1.0), 2.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	var has_collision := false
	for child in get_children():
		if child is CollisionShape2D:
			has_collision = true
			break
	
	if not has_collision:
		warnings.append("Добавь CollisionShape2D (лучше круглый)")
	
	return warnings
