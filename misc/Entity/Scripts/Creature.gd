extends Entity
class_name Creature

# ═══════════════════════════════════════════════════════════════
#  ENUMS
# ═══════════════════════════════════════════════════════════════

signal attack_finished

enum BehaviorType { Passive, Neutral, Aggressive, Special }

enum State {
	IDLE,     # стоит, ждёт
	WANDER,   # бродит случайно
	PATROL,   # идёт по точкам
	CHASE,    # преследует цель
	FLEE,     # убегает от цели
	ATTACK,   # атакует
	STUNNED,  # оглушён
	DEAD,
}

# ═══════════════════════════════════════════════════════════════
#  EXPORTS
# ═══════════════════════════════════════════════════════════════

@export_category("Behavior")
## -1 = Пассивный  0 = Нейтральный  1 = Агрессивный
@export_range(-1.0, 1.0, 0.01) var behavior: float = 0.0
@export var can_flee: bool = false
## На каком % HP начинает убегать
@export_range(0.0, 1.0) var flee_threshold: float = 0.25

@export_category("Fear")
## Включить систему страха
@export var use_fear: bool = false
## Скорость накопления страха при получении урона (за 1 ед. урона)
@export var fear_per_damage: float = 0.05
## Страх нарастает, если цель ближе этого расстояния (пикселей)
@export var fear_proximity_radius: float = 60.0
## Скорость накопления страха от близости цели (ед./сек)
@export var fear_proximity_rate: float = 0.08
## Скорость затухания страха в секунду (когда угрозы нет)
@export var fear_decay_rate: float = 0.05
## Порог страха — выше этого существо переходит в FLEE
@export_range(0.0, 1.0) var fear_flee_threshold: float = 0.6
## При страхе ниже этого порога существо успокаивается и перестаёт убегать
@export_range(0.0, 1.0) var fear_calm_threshold: float = 0.25

@export_category("Detection")
## Радиус слуха — замечает в любом направлении (стены не блокируют)
@export var hear_radius: float = 60.0
## Радиус зрения (длина конуса)
@export var sight_radius: float = 180.0
## Половина угла конуса зрения в градусах (60 → конус 120°)
@export var fov_half_angle: float = 60.0
## Проверять ли стены (raycast к игроку)
@export var use_los_check: bool = true
## Маска слоёв стен для LOS-raycast
@export var wall_collision_mask: int = 1

@export_category("Movement")
var move_speed: float = 60.0
@export var wander_interval_min: float = 2.0
@export var wander_interval_max: float = 5.0
@export var wander_radius: float = 100.0
## Точки патруля (Node2D / Marker2D)
@export var patrol_points: Array[NodePath] = []

@export_category("Obstacle Avoidance")
## Дальность лучей для обхода стен
@export var ray_length: float = 40.0
## Сила отталкивания от стены
@export var avoidance_strength: float = 1.8

@export_category("Attack")
@export var attack_damage: float = 10.0
@export var attack_radius: float = 28.0
@export var attack_cooldown: float = 1.2

@export_category("Poise / Stagger")
## Сколько "стаггера" существо выдерживает до оглушения
@export var max_poise: float = 100.0
## Скорость восстановления poise в секунду (когда не бьют)
@export var poise_decay_rate: float = 15.0
## Задержка перед началом восстановления poise после последнего удара
@export var poise_decay_delay: float = 1.0
## Длительность стаггера при заполнении poise
@export var stagger_duration: float = 1.0
## Множитель урона по существу во время стаггера (окно "добивания")
@export var vulnerable_damage_multiplier: float = 1.5

@export_category("Animators")
@export var body_anim: AnimationPlayer
@export var hand_anim: AnimationPlayer

# ═══════════════════════════════════════════════════════════════
#  NODES
# ═══════════════════════════════════════════════════════════════

@onready var drop: Drop_items        = $Drop
@onready var health_bar: ProgressBar = $HealthBar

# RayCast2D создаются в коде — добавлять в сцену не нужно
var _rays: Array[RayCast2D] = []

# Углы лучей avoidance (локальные, градусы)
const RAY_ANGLES := [-60.0, -30.0, 0.0, 30.0, 60.0]

# ═══════════════════════════════════════════════════════════════
#  RUNTIME STATE
# ═══════════════════════════════════════════════════════════════

var behavior_type: BehaviorType
var current_state: State = State.IDLE
var target: Node2D = null
var home_position: Vector2
var _facing_dir: Vector2 = Vector2.RIGHT  # куда смотрит существо

var _wander_timer: float  = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _attack_timer: float  = 0.0
var _stun_timer: float    = 0.0
var _detect_timer: float  = 0.0  # throttle проверки игрока

## Текущий уровень страха [0.0 – 1.0]
var fear_level: float = 0.0

## Текущий накопленный poise (стаггер)
var current_poise: float = 0.0
var _poise_decay_timer: float = 0.0

const DETECT_INTERVAL := 0.12   # проверка каждые ~120 мс

var _patrol_nodes: Array[Node2D] = []
var _patrol_index: int = 0

# ── ОПТИМИЗАЦИЯ: throttle вне экрана ─────────────────────────────
# Существо вне видимости не бегает по рейкастам/детекту/move_and_slide —
# это основная стоимость AI при большом кол-ве существ в открытом мире.
@onready var _screen_notifier: VisibleOnScreenEnabler2D = get_node_or_null("optimizer")
var _is_active: bool = true

# Кешируем квадраты радиусов — сравнение дистанций без sqrt (distance_to)
var _sight_radius_sq: float
var _hear_radius_sq: float
var _chase_giveup_sq: float
var _flee_giveup_sq: float
var _attack_radius_sq: float

# ═══════════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	super._ready()
	home_position = global_position
	move_speed = Entity_stats.move_speed * 10
	health_bar.visible = false
	health_bar.max_value = Entity_stats.max_health
	health_bar.value     = Entity_stats.max_health
	_resolve_behavior_type()
	_resolve_patrol_nodes()
	_build_rays()
	_cache_squared_radii()
	_setup_screen_throttle()
	_enter_state(_default_start_state())

## Квадраты радиусов считаем один раз — сравнение дистанций без sqrt
func _cache_squared_radii() -> void:
	_sight_radius_sq  = sight_radius * sight_radius
	_hear_radius_sq   = hear_radius * hear_radius
	_chase_giveup_sq  = (sight_radius * 1.6) * (sight_radius * 1.6)
	_flee_giveup_sq   = (sight_radius * 2.0) * (sight_radius * 2.0)
	_attack_radius_sq = attack_radius * attack_radius

## Подключаемся к уже существующему VisibleOnScreenEnabler2D ("optimizer" в сцене)
func _setup_screen_throttle() -> void:
	if _screen_notifier == null:
		return
	_screen_notifier.screen_entered.connect(func(): _is_active = true)
	_screen_notifier.screen_exited.connect(func(): _is_active = false)
	_is_active = _screen_notifier.is_on_screen()

func _resolve_behavior_type() -> void:
	if behavior < -0.33:
		behavior_type = BehaviorType.Passive
	elif behavior < 0.33:
		behavior_type = BehaviorType.Neutral
	else:
		behavior_type = BehaviorType.Aggressive

func _resolve_patrol_nodes() -> void:
	for path in patrol_points:
		var n = get_node_or_null(path)
		if n is Node2D:
			_patrol_nodes.append(n)

## Создаём 5 лучей один раз — они живут всё время жизни существа
func _build_rays() -> void:
	for angle_deg in RAY_ANGLES:
		var ray := RayCast2D.new()
		ray.collision_mask  = wall_collision_mask
		ray.exclude_parent  = true
		ray.enabled         = true
		# target_position обновляем динамически в _move_toward
		ray.target_position = Vector2.RIGHT * ray_length
		add_child(ray)
		_rays.append(ray)

func _default_start_state() -> State:
	if not _patrol_nodes.is_empty():
		return State.PATROL
	return State.WANDER

# ═══════════════════════════════════════════════════════════════
#  MAIN LOOP
# ═══════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if not _is_active:
		_tick_offscreen(delta)
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_stun_timer   = maxf(0.0, _stun_timer   - delta)
	_wander_timer = maxf(0.0, _wander_timer - delta)
	_detect_timer = maxf(0.0, _detect_timer - delta)

	# Проверка игрока — не каждый кадр, раз в DETECT_INTERVAL
	if _detect_timer <= 0.0:
		_detect_timer = DETECT_INTERVAL
		_check_for_target()

	if use_fear:
		_tick_fear(delta)

	_tick_poise(delta)

	_tick_state(delta)

## Существо вне экрана: не гоняем детект/рейкасты/move_and_slide,
## но не даём таймерам "зависнуть", чтобы не было рывков при возврате в кадр.
func _tick_offscreen(delta: float) -> void:
	_stun_timer = maxf(0.0, _stun_timer - delta)
	if use_fear:
		fear_level = maxf(0.0, fear_level - fear_decay_rate * delta)
	_tick_poise(delta)
	if current_state == State.STUNNED and _stun_timer <= 0.0:
		_enter_state(_default_start_state())

# ═══════════════════════════════════════════════════════════════
#  STATE MACHINE
# ═══════════════════════════════════════════════════════════════

func _enter_state(new_state: State) -> void:
	current_state = new_state
	match new_state:
		State.IDLE:
			velocity = Vector2.ZERO
			_play_anim("Idle")
			_wander_timer = randf_range(wander_interval_min, wander_interval_max)
		State.WANDER:
			_pick_wander_target()
			_play_anim("Walk")
		State.PATROL:
			_play_anim("Walk")
		State.CHASE:
			_play_anim("Walk")
		State.FLEE:
			_play_anim("Walk")
		State.ATTACK:
			velocity = Vector2.ZERO
			_play_anim("Attack")
		State.STUNNED:
			velocity = Vector2.ZERO
			_play_anim("Stunned")
		State.DEAD:
			velocity = Vector2.ZERO
			_play_anim("Death")


func _tick_state(delta: float) -> void:
	match current_state:
		State.IDLE:    _tick_idle(delta)
		State.WANDER:  _tick_wander(delta)
		State.PATROL:  _tick_patrol(delta)
		State.CHASE:   _tick_chase(delta)
		State.FLEE:    _tick_flee(delta)
		State.ATTACK:  _tick_attack(delta)
		State.STUNNED: _tick_stunned(delta)

# ── IDLE ──────────────────────────────────────────────────────
func _tick_idle(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	if _wander_timer <= 0.0:
		_enter_state(State.WANDER if _patrol_nodes.is_empty() else State.PATROL)

# ── WANDER ────────────────────────────────────────────────────
func _tick_wander(delta: float) -> void:
	var arrived := _move_toward(_wander_target, delta)
	if arrived:
		_enter_state(State.IDLE)

# ── PATROL ────────────────────────────────────────────────────
func _tick_patrol(delta: float) -> void:
	if _patrol_nodes.is_empty():
		_enter_state(State.WANDER)
		return
	var pt := _patrol_nodes[_patrol_index].global_position
	if _move_toward(pt, delta):
		_patrol_index = (_patrol_index + 1) % _patrol_nodes.size()
		_enter_state(State.IDLE)

# ── CHASE ─────────────────────────────────────────────────────
func _tick_chase(delta: float) -> void:
	if not is_instance_valid(target):
		_lose_target(); return
	var dist_sq := global_position.distance_squared_to(target.global_position)
	if dist_sq > _chase_giveup_sq:
		_lose_target(); return
	if dist_sq <= _attack_radius_sq:
		_enter_state(State.ATTACK); return
	_move_toward(target.global_position, delta)

# ── FLEE ──────────────────────────────────────────────────────
func _tick_flee(delta: float) -> void:
	if not is_instance_valid(target):
		_lose_target(); return
	var away := global_position + (global_position - target.global_position).normalized() * sight_radius
	_move_toward(away, delta)
	if global_position.distance_squared_to(target.global_position) > _flee_giveup_sq:
		_lose_target()

# ── ATTACK ────────────────────────────────────────────────────
func _tick_attack(_delta: float) -> void:
	if not is_instance_valid(target):
		_lose_target(); return
	if global_position.distance_squared_to(target.global_position) > _attack_radius_sq:
		_enter_state(State.CHASE); return
	if _attack_timer <= 0.0:
		_do_attack()
		_attack_timer = attack_cooldown

# ── STUNNED ───────────────────────────────────────────────────
func _tick_stunned(_delta: float) -> void:
	if _stun_timer <= 0.0:
		_enter_state(_default_start_state())

# ═══════════════════════════════════════════════════════════════
#  ДВИЖЕНИЕ + ОБХОД СТЕН
# ═══════════════════════════════════════════════════════════════

## Двигает существо к точке. Возвращает true если прибыли.
## Лучи собирают вектор отталкивания от стен и добавляют его к направлению.
func _move_toward(target_pos: Vector2, _delta: float) -> bool:
	var to_target := target_pos - global_position
	var dist      := to_target.length()
	if dist < 4.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return true

	var dir := to_target / dist

	# Обновляем лучи по текущему направлению движения
	var avoidance := Vector2.ZERO
	for i in _rays.size():
		var ray_dir := dir.rotated(deg_to_rad(RAY_ANGLES[i]))
		_rays[i].target_position = ray_dir * ray_length
		_rays[i].force_raycast_update()

		if _rays[i].is_colliding():
			var hit_point  := _rays[i].get_collision_point()
			var hit_normal := _rays[i].get_collision_normal()
			var hit_dist   := global_position.distance_to(hit_point)
			# Чем ближе препятствие — тем сильнее отталкивание
			var weight := 1.0 - clampf(hit_dist / ray_length, 0.0, 1.0)
			avoidance += hit_normal * weight

	var final_dir := (dir + avoidance * avoidance_strength).normalized()
	_facing_dir   = final_dir

	# Разворот спрайта по горизонтали
	if final_dir.x != 0.0:
		$Skin.scale.x = -1.0 if final_dir.x < 0.0 else 1.0

	velocity = final_dir * move_speed
	move_and_slide()
	return false

# ═══════════════════════════════════════════════════════════════
#  ОБНАРУЖЕНИЕ ИГРОКА (чистая математика, без Area2D)
# ═══════════════════════════════════════════════════════════════

func _check_for_target() -> void:
	if behavior_type == BehaviorType.Passive:
		return

	# Уже есть цель — проверяем не потеряли ли
	if is_instance_valid(target):
		if not _can_sense(target):
			_lose_target()
		return

	# Ищем нового кандидата в группе "Player"
	for player in get_tree().get_nodes_in_group("Player"):
		if player is Node2D and _can_sense(player):
			_acquire_target(player)
			return

## Слышим (круг) ИЛИ видим (конус + опционально LOS)
func _can_sense(body: Node2D) -> bool:
	var to_body := body.global_position - global_position
	var dist_sq := to_body.length_squared()

	# 1. Слух — простой круг, стены не блокируют
	if dist_sq <= _hear_radius_sq:
		return true

	# 2. За пределами зрения — не видим
	if dist_sq > _sight_radius_sq:
		return false

	# 3. Проверка угла конуса
	var angle_to_body := rad_to_deg(_facing_dir.angle_to(to_body.normalized()))
	if absf(angle_to_body) > fov_half_angle:
		return false

	# 4. Line-of-sight — нет ли стены между нами
	if use_los_check:
		return _has_line_of_sight(body.global_position)

	return true

## Один raycast напрямую к цели через PhysicsDirectSpaceState2D
func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space  := get_world_2d().direct_space_state
	var query  := PhysicsRayQueryParameters2D.create(
		global_position, target_pos, wall_collision_mask
	)
	query.exclude = [self]
	return space.intersect_ray(query).is_empty()

# ═══════════════════════════════════════════════════════════════
#  TARGET MANAGEMENT
# ═══════════════════════════════════════════════════════════════

func _acquire_target(new_target: Node2D) -> void:
	target = new_target
	if can_flee and _is_low_health():
		_enter_state(State.FLEE)
	elif behavior_type == BehaviorType.Aggressive:
		_enter_state(State.CHASE)
	# Neutral — ждёт удара, реагирует в on_hit()

func _lose_target() -> void:
	target = null
	_enter_state(State.WANDER if _patrol_nodes.is_empty() else State.PATROL)

# ═══════════════════════════════════════════════════════════════
#  ATTACK
# ═══════════════════════════════════════════════════════════════

## Переопредели в подклассе для уникальной атаки
func _do_attack() -> void:
	if not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.take_damage(attack_damage, self)
		emit_signal("attack_finished")

# ═══════════════════════════════════════════════════════════════
#  HIT / STATUS EFFECTS
# ═══════════════════════════════════════════════════════════════

## Вызови после take_damage чтобы существо среагировало на удар
## is_critical  — был ли удар критическим (крит наносит +50% poise-урона)
## poise_damage — сколько стаггера наносит удар (берётся из оружия игрока)
func on_hit(_knockback: Vector2 = Vector2.ZERO, is_critical: bool = false, poise_damage: float = 0.0) -> void:
	add_fear_from_damage(attack_damage)  # ← страх от удара

	if poise_damage > 0.0 and current_state != State.DEAD:
		add_poise_damage(poise_damage * (1.5 if is_critical else 1.0))

	if behavior_type == BehaviorType.Neutral and \
	   current_state not in [State.CHASE, State.ATTACK]:
		if is_instance_valid(target):
			_enter_state(State.CHASE)
	if can_flee and _is_low_health():
		_enter_state(State.FLEE)

func apply_stun(duration: float) -> void:
	_stun_timer = duration
	_enter_state(State.STUNNED)

# ═══════════════════════════════════════════════════════════════
#  FEAR SYSTEM
# ═══════════════════════════════════════════════════════════════

## Вызывается каждый кадр когда use_fear = true
func _tick_fear(delta: float) -> void:
	if is_instance_valid(target):
		# Страх нарастает от близости угрозы
		var dist := global_position.distance_to(target.global_position)
		if dist <= fear_proximity_radius:
			var proximity_factor := 1.0 - (dist / fear_proximity_radius)
			fear_level = minf(1.0, fear_level + fear_proximity_rate * proximity_factor * delta)
	else:
		# Нет угрозы — страх постепенно уходит
		fear_level = maxf(0.0, fear_level - fear_decay_rate * delta)

	_apply_fear_state()

## Проверяет пороги и при необходимости меняет состояние
func _apply_fear_state() -> void:
	if current_state == State.DEAD or current_state == State.STUNNED:
		return
	if fear_level >= fear_flee_threshold:
		if current_state != State.FLEE:
			_enter_state(State.FLEE)
	elif current_state == State.FLEE and fear_level <= fear_calm_threshold:
		# Успокоился — возвращаемся к обычному поведению
		if is_instance_valid(target) and behavior_type == BehaviorType.Aggressive:
			_enter_state(State.CHASE)
		else:
			_lose_target()

## Добавляет страх при получении урона. Вызови из take_damage / on_hit.
func add_fear_from_damage(damage: float) -> void:
	if not use_fear:
		return
	fear_level = minf(1.0, fear_level + damage * fear_per_damage)

# ═══════════════════════════════════════════════════════════════
#  POISE / STAGGER SYSTEM
# ═══════════════════════════════════════════════════════════════

## Во время стаггера существо открыто — по нему проходит усиленный урон
func get_incoming_damage_multiplier() -> float:
	return vulnerable_damage_multiplier if current_state == State.STUNNED else 1.0

## Затухание poise, если существо не получало ударов последние poise_decay_delay сек
func _tick_poise(delta: float) -> void:
	if current_state == State.DEAD:
		return
	if _poise_decay_timer > 0.0:
		_poise_decay_timer -= delta
		return
	if current_poise > 0.0:
		current_poise = maxf(0.0, current_poise - poise_decay_rate * delta)

## Вызывается из on_hit при каждом ударе. При заполнении — стаггер.
func add_poise_damage(amount: float) -> void:
	if current_state == State.DEAD or max_poise <= 0.0:
		return
	current_poise += amount
	_poise_decay_timer = poise_decay_delay
	if current_poise >= max_poise:
		current_poise = 0.0
		_trigger_stagger()

func _trigger_stagger() -> void:
	apply_stun(stagger_duration)

# ═══════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════

func _pick_wander_target() -> void:
	var angle := randf_range(0.0, TAU)
	var dist  := randf_range(20.0, wander_radius)
	_wander_target = home_position + Vector2(cos(angle), sin(angle)) * dist

func _is_low_health() -> bool:
	return Entity_stats.current_health / Entity_stats.max_health <= flee_threshold

func _play_anim(anim_name: String) -> void:
	if body_anim and body_anim.has_animation(anim_name):
		body_anim.play(anim_name)
	elif hand_anim and hand_anim.has_animation(anim_name):
		hand_anim.play(anim_name)

# ═══════════════════════════════════════════════════════════════
#  ENTITY SIGNAL CALLBACKS
# ═══════════════════════════════════════════════════════════════

func _on_health_changed(new_health: float) -> void:
	health_bar.visible = true
	if new_health > 0:
		health_bar.value = new_health
	elif new_health <= 0:
		health_bar.visible = false
	

func _on_died() -> void:
	_enter_state(State.DEAD)
	if $HitBox:
		$HitBox.queue_free()
	if drop:
		drop._drop_items()
	if is_in_group("Creature"):
		remove_from_group("Creature")
		
	await get_tree().create_timer(1.5).timeout
	queue_free()
