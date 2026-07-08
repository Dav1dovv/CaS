extends CanvasLayer

# Сигналы
signal command_entered(command: String, args: Array)
signal chat_message_sent(message: String)  # Обычное сообщение в чат

# Ноды
@onready var console_container: VBoxContainer = $VBoxContainer
@onready var console_output: RichTextLabel = $VBoxContainer/OutPut
@onready var console_input: LineEdit = $VBoxContainer/LineEdit
@onready var hint_label: AutoSizeRichTextLabel = $AutoSizeRichTextLabel
@onready var hint_timer: Timer = $HintTimer                        # создай Timer в той же сцене!

# Переменные
var is_console_visible: bool = false
var command_history: Array[String] = []      # Только команды с "/"
var history_index: int = -1
#var max_output_lines: int = 500
var commands: Dictionary = {}

func _ready() -> void:
	console_container.visible = false
	console_input.text_submitted.connect(_on_text_submitted)
	
	# Встроенные команды
	register_command("help", _cmd_help, "Показать список команд")
	register_command("clear", _cmd_clear, "Очистить консоль")
	register_command("reload", _cmd_reload_scene, "Перезагрузить текущую сцену")
	register_command("clearGameData", _cmd_clear_data,"Удаляет все сохранение за все время")
	# Можно добавить свои: register_command("give", _cmd_give, "give <item> <amount>")
	
	add_to_console("[color=aaaaaa]Добро пожаловать в игру! Используйте /help для списка команд, или нажмите ` чотбы закрыть консоль.[/color]")

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_call_debugMenu"):  # Обычно это клавиша ~
		toggle_console()

func toggle_console() -> void:
	if Global.is_opened_menu && !is_console_visible:
		return  # Запрещаем открывать, если уже открыто другое меню
	
	is_console_visible = !is_console_visible
	Global.is_opened_menu = is_console_visible
	
	console_container.visible = is_console_visible
	if is_console_visible:
		layer = 128  # Поверх всего
		console_input.grab_focus()
		console_input.clear()
	else:
		layer = 1
		console_input.release_focus()

# Основная функция обработки ввода
func _on_text_submitted(text: String) -> void:
	var input = text.strip_edges()
	if input.is_empty():
		return
	
	console_input.clear()
	
	# Сохраняем в историю ТОЛЬКО команды (начинающиеся с /)
	if input.begins_with("/"):
		if command_history.is_empty() or command_history.back() != input:
			command_history.append(input)
		history_index = command_history.size()
	
	# === ОБЫЧНОЕ СООБЩЕНИЕ (БЕЗ /) ===
	if !input.begins_with("/"):
		# Показываем как чат-сообщение от игрока
		add_chat_message(Global.player_name, input, Color(0.4, 0.8, 1.0))  # Синий цвет
		emit_signal("chat_message_sent", input)
		return
	
	# === КОМАНДА (С /) ===
	var without_slash = input.substr(1)  # Убираем первый символ "/"
	add_command_echo(input)  # Показываем команду зелёным
	
	if without_slash.is_empty():
		add_to_console("[color=yellow]Напишите /help для списка команд[/color]")
		return
	
	# Разбиваем команду
	var parts = without_slash.split(" ", false)
	var cmd = parts[0].to_lower()
	var args = parts.slice(1)
	
	# Выполняем команду
	if commands.has(cmd):
		var result = commands[cmd]["callable"].call(args)
		if result is String and !result.is_empty():
			add_to_console(result)
	else:
		add_to_console("[color=red]Неизвестная команда: [b]" + cmd + "[/b]. Используйте /help[/color]")
	
	emit_signal("command_entered", cmd, args)

# --------------------- ВЫВОД СООБЩЕНИЙ ---------------------

func add_to_console(text: String) -> void:
	console_output.append_text("[color=#cccccc]" + text + "[/color]\n")
	#_limit_lines()

func add_chat_message(sender: String, message: String, color: Color = Color.WHITE) -> void:
	var color_hex = color.to_html(false)
	console_output.append_text("[color=%s][b]%s:[/b] %s[/color]\n" % [color_hex, sender, message])
	#_limit_lines()
	# Автопрокрутка вниз
	console_output.scroll_to_line(console_output.get_line_count() - 1)

func add_command_echo(command: String) -> void:
	console_output.append_text("[color=#88ff88]> %s[/color]\n" % command)
	#_limit_lines()

#func _limit_lines() -> void:
	#var lines = console_output.get_line_count()
	#if lines > max_output_lines:
		#console_output.remove_line(0)
		#_limit_lines()  # Рекурсивно, пока не уложимся


func show_hint(text: String, duration: float = 3.0, color: Color = Color(1, 1, 1)) -> void:
	if not hint_label:
		push_warning("HintLabel не найден! Подсказки не будут работать.")
		return
	
	hint_label.text = "[center][color=%s]%s[/color][/center]" % [color.to_html(false), text]
	hint_label.visible = true
	
	# Плавное появление
	var tween = create_tween()
	tween.tween_property(hint_label, "modulate:a", 1.0, 0.3).from(0.0)
	
	# Перезапускаем таймер
	hint_timer.stop()
	hint_timer.wait_time = duration
	hint_timer.start()

func _on_hint_timer_timeout() -> void:
	if not hint_label:
		return
	
	var tween = create_tween()
	tween.tween_property(hint_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(hint_label.hide)

# --------------------- РЕГИСТРАЦИЯ КОМАНД ---------------------

func register_command(command_name: String, callable: Callable, description: String = "") -> void:
	commands[command_name.to_lower()] = {
		"callable": callable,
		"description": description
	}

# --------------------- ВСТРОЕННЫЕ КОМАНДЫ ---------------------

func _cmd_help(_args: Array) -> String:
	var help_text = "[color=aqua]Доступные команды:[/color]\n"
	for cmd in commands.keys():
		var desc = commands[cmd]["description"] if commands[cmd]["description"] else "Нет описания"
		help_text += "[color=yellow]/%s[/color] — %s\n" % [cmd, desc]
	return help_text

func _cmd_clear(_args: Array) -> String:
	console_output.clear()
	add_to_console("[color=gray]Консоль очищена[/color]")
	return ""

func _cmd_clear_data(_args: Array) -> String:
	var help_text = "[color=red]Game Data Cleared:[/color]"
	get_parent().delete_game_data()
	return help_text

func _cmd_reload_scene(_args: Array) -> String:
	get_tree().reload_current_scene()
	return "[color=orange]Сцена перезагружена[/color]"

# --------------------- НАВИГАЦИЯ ПО ИСТОРИИ ---------------------

func _unhandled_input(event: InputEvent) -> void:
	if !is_console_visible or !(event is InputEventKey) or !event.pressed:
		return
	
	if event.keycode == KEY_UP:
		if history_index > 0:
			history_index -= 1
			console_input.text = command_history[history_index]
			console_input.caret_column = console_input.text.length()
		#event.eat()
	elif event.keycode == KEY_DOWN:
		if history_index < command_history.size() - 1:
			history_index += 1
			console_input.text = command_history[history_index]
			console_input.caret_column = console_input.text.length()
		elif history_index == command_history.size() - 1:
			history_index += 1
			console_input.text = ""
		#event.eat()
