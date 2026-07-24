extends RapierArea2D
class_name Harvestable

signal collected
signal hit
## Испускается при каждом ударе — множитель можно использовать для UI/попапов чисел
signal combo_hit(multiplier: float, combo_count: int)

var is_corrupted : bool = false
var gm

@onready var Dropper_component : Dropper = $droper
@onready var animation: AnimationPlayer = $AnimationPlayer

@export_range(2,999,1) var durability : float = 6
@export_range(0,10) var harvest_tool_lvl : int = 1
@export var VFX_component : VFX
@export var can_corrupt : bool = true
@export var corrupted_texture : Texture2D

# ─── CurseObject ────────────────────────────────────────────────────────────
## Сцена CurseObject — создаётся когда объект добывают киркой ниже нужного тира
@export var curse_object_scene : PackedScene
## Сколько заражения получает игрок за КАЖДЫЙ удар по заражённому объекту
## Финальное значение умножается на armor_curse_multiplier из брони/амулетов
@export_range(0.0, 20.0, 0.5) var infection_per_hit : float = 2.0
# ────────────────────────────────────────────────────────────────────────────

var player
var tween: Tween
var _last_tool_lvl: int = 999  # запоминаем последний использованный tier

# Ссылка на ShaderMaterial спрайта
var _shader_material: ShaderMaterial

@export_group("Transparency Settings")
@export_range(0.0, 200.0, 10.0) var max_distance : float = 20
@export_range(0.0, 1.0, 0.01) var fade_alpha : float = 0.50
@export_range(0.1, 1.0, 0.05) var fade_duration : float = 0.2

# ОПТИМИЗАЦИЯ: квадрат дистанции — сравнение без sqrt
var _max_distance_sq : float = 0.0
# Текущее "выцветшее" состояние — tween запускаем только при его смене,
# а не каждый physics-кадр
var _is_faded : bool = false


# ─── Combo / Timing Harvest ──────────────────────────────────────────────────
@export_group("Combo Harvest")
## Максимальный интервал между ударами, чтобы комбо не сбросилось (сек)
@export_range(0.2, 3.0, 0.05) var combo_window : float = 0.9
## На сколько растёт множитель за каждый удар в тайминге
@export_range(0.0, 1.0, 0.01) var combo_bonus_per_hit : float = 0.15
## Потолок множителя комбо
@export_range(1.0, 5.0, 0.1) var combo_max_multiplier : float = 2.0

var _combo_count : int = 0
var _combo_multiplier : float = 1.0
var _last_hit_time : float = -999.0

# ─── Rich Vein — редкая "богатая жила" ───────────────────────────────────────
@export_group("Rich Vein")
## Шанс, что этот ресурс окажется "богатой жилой" (только если не заражён)
@export_range(0.0, 1.0, 0.01) var rich_vein_chance : float = 0.08
## Множитель к финальному дропу с богатой жилы
@export_range(1.0, 5.0, 0.1) var rich_vein_multiplier : float = 2.5
@export var rich_vein_tint : Color = Color(1.0, 0.85, 0.2, 1.0)

var is_rich_vein : bool = false

func _init() -> void:
	set_collision_layer_value(2,true)
	set_collision_layer_value(5,true)
	set_collision_mask_value(1,false)
	set_collision_mask_value(4,true)
	set_collision_mask_value(9,true)

func _ready() -> void:
	add_to_group("Harvestable")
	if not is_inside_tree():
		await tree_entered
	
	Dropper_component = $droper
	player = get_tree().get_first_node_in_group("Player")
	gm = get_tree().get_first_node_in_group("World")

	var sprite = $Sprite2D
	if sprite and sprite.material is ShaderMaterial:
		_shader_material = sprite.material
		_shader_material.set_shader_parameter("wind_offset", global_position.x)

	_max_distance_sq = max_distance * max_distance
	
	#region CORRUPTION
	# Заражение теперь берётся только из WorldGenerator (родителя) — у него
	# corruption_level настраивается вручную в редакторе на конкретной зоне (0..3).
	if can_corrupt:
		var world_generator = get_parent()
		var chance: float = 0.0
		if world_generator and "corruption_level" in world_generator:
			chance = float(world_generator.corruption_level) / 3.0

		is_corrupted = chance > 0.0 and randf() < chance
		
		if is_corrupted:
			if corrupted_texture:
				$Sprite2D.texture = corrupted_texture
			#else:
				#modulate = Color(0.733, 0.325, 0.745, 1.0)
			$PointLight2D.visible = true
			$"Corruption Effect".emitting = true
			durability += 20
		else:
			# ── Богатая жила — редкий шанс на не заражённом ресурсе ─────────────
			is_rich_vein = randf() < rich_vein_chance
			if is_rich_vein:
				#modulate = rich_vein_tint
				$PointLight2D.visible = true
				$PointLight2D.color   = rich_vein_tint
				$"Corruption Effect".queue_free()
			else:
				$PointLight2D.queue_free()
				$"Corruption Effect".queue_free()
		# ─────────────────────────────────────────────────────────────────────
	#endregion

func _physics_process(_delta: float) -> void:
	update_transparency()


func Harvest(hit_strenght : float, tool_lvl : int, is_weapon : bool) -> void:
	if is_weapon:
		return

	# Запоминаем тир для spawn CurseObject при разрушении
	_last_tool_lvl = tool_lvl

	# ── Комбо-тайминг: бей ритмично — множитель растёт ───────────────────────
	#_update_combo()
	# ─────────────────────────────────────────────────────────────────────────

	# ── Визуальный фидбэк ────────────────────────────────────────────────────
	if VFX_component != null:
		VFX_component._hit_vfx($Sprite2D)
		await VFX_component.vfx_finished
	# ─────────────────────────────────────────────────────────────────────────

	# ── Заражение игрока при каждом ударе по corrupted объекту ───────────────
	if is_corrupted and player and player.has_method("curse"):
		var mult: float = _get_armor_curse_multiplier()
		player.curse(infection_per_hit * mult)
	# ─────────────────────────────────────────────────────────────────────────

	# ── Уменьшение прочности (с бонусом от комбо-тайминга) ───────────────────
	durability -= hit_strenght * _combo_multiplier
	# ─────────────────────────────────────────────────────────────────────────

	if durability <= 0:
		_on_destroyed(tool_lvl)


### Тайминг-комбо: удары в узкое окно после предыдущего растят множитель,
### пауза длиннее combo_window сбрасывает серию.
#func _update_combo() -> void:
	#var now := Time.get_ticks_msec() / 1000.0
	#if now - _last_hit_time <= combo_window:
		#_combo_count += 1
	#else:
		#_combo_count = 0
	#_last_hit_time = now
	#_combo_multiplier = minf(combo_max_multiplier, 1.0 + _combo_count * combo_bonus_per_hit)
	#emit_signal("combo_hit", _combo_multiplier, _combo_count)


func _on_destroyed(tool_lvl: int) -> void:
	## Дроп ресурсов — с бонусом за комбо-тайминг и/или богатую жилу
	#if Dropper_component != null:
		#Dropper_component.max_drop += scale.x
#
		#var bonus_mult := _combo_multiplier
		#if is_rich_vein:
			#bonus_mult *= rich_vein_multiplier
#
		#if bonus_mult > 1.0:
			#if Dropper_component.has_method("set_drop_multiplier"):
				#Dropper_component.set_drop_multiplier(bonus_mult)
			#else:
				#Dropper_component.max_drop = int(round(Dropper_component.max_drop * bonus_mult))
#
		#if is_rich_vein:
			#DebugLog.log("Богатая жила! Бонус к дропу: x%.2f" % bonus_mult)
#
		#Dropper_component._drop_items()
		
		
	if is_corrupted: 
		Dropper_component.drop_resources[0].max_throws += 5
		Dropper_component.drop_resources[0].min_throws += 5
	$CollisionShape2D.disabled = true
	Dropper_component._drop_items()
	if animation.has_animation("destroy"):
		animation.play("destroy")
		await animation.animation_finished
	else : 
		$Sprite2D .visible = false
		$StaticBody2D.queue_free()
	if $Destroy:
		$Destroy.play()
		await $Destroy.finished

	# Регистрация сбора в мире
	if gm and gm.has_method("register_harvested"):
		var loc_key := get_tree().current_scene.scene_file_path
		gm.register_harvested(loc_key, global_position)

	# ── Спавн CurseObject если тир кирки ниже требуемого ────────────────────
	#if tool_lvl < harvest_tool_lvl and curse_object_scene != null:
	if is_corrupted:
		_spawn_curse_object(harvest_tool_lvl - tool_lvl)
		Global.corruption -= 1
	# ─────────────────────────────────────────────────────────────────────────

	emit_signal("collected")
	queue_free()


func _spawn_curse_object(tier_diff: int) -> void:
	## Сила проклятия растёт с разницей тиров:
	##   tier_diff 1 → infection_damage 8
	##   tier_diff 2 → infection_damage 16
	##   tier_diff 3 → infection_damage 24
	var curse = curse_object_scene.instantiate()
	curse.global_position = global_position
	curse.infection_damage = tier_diff * 8.0

	# Отдаём в сцену (не в себя — мы сами queue_free)
	get_tree().current_scene.add_child(curse)


## Возвращает множитель заражения в зависимости от брони/амулетов игрока.
## Логика вынесена в CurseUtils — раньше дублировалась с CurseObject.gd.
func _get_armor_curse_multiplier() -> float:
	return CurseUtils.get_armor_curse_multiplier(player)


#region Background transparency
## ОПТИМИЗАЦИЯ: distance_squared_to вместо distance_to (без sqrt) +
## tween запускаем только при смене состояния near/far, а не каждый кадр —
## иначе на каждый Harvestable в мире это create_tween()+kill() 60 раз/сек.
func update_transparency() -> void:
	if _shader_material == null:
		return

	var should_fade := false
	if player != null:
		var dist_sq := global_position.distance_squared_to(player.global_position)
		var player_behind = player.global_position.y < global_position.y
		should_fade = player_behind and dist_sq < _max_distance_sq

	if should_fade == _is_faded:
		return  # состояние не изменилось — tween не нужен

	_is_faded = should_fade
	_tween_fade(fade_alpha if should_fade else 1.0)

func _tween_fade(target_alpha: float) -> void:
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var current_alpha: float = _shader_material.get_shader_parameter("fade_alpha")
	tween.tween_method(
		func(v: float): _shader_material.set_shader_parameter("fade_alpha", v),
		current_alpha,
		target_alpha,
		fade_duration
	)
#endregion
