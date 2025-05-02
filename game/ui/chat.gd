extends Control

@onready var input: LineEdit = $Container/SendMessage/Input
@onready var scroll_container = $Container/ScrollContainer
@onready var messages_container = $Container/ScrollContainer/Messages

@onready var message_state: MessageState = preload("res://state/message_state.gd").new()

func _ready() -> void:
	_on_reset()
	message_state.update.connect(_on_state_update)
	UserState.update.connect(_on_state_update)
	update_messages()

func _exit_tree() -> void:
	_on_reset()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and input.has_focus():
		_on_button_pressed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		input.grab_focus()
	elif event.is_action_pressed("ui_cancel"):
		input.release_focus()

func _on_button_pressed() -> void:
	if input.text == "": return
	if input.text.begins_with("/name"):
		SpacetimeDB.call_reducer("SetName", [input.text.substr(6)])
	else:
		SpacetimeDB.call_reducer("SendMessage", [input.text])
	input.text = ""
	
	await get_tree().create_timer(.1).timeout
	scroll_container.set_deferred("scroll_vertical", scroll_container.get_v_scroll_bar().max_value)

func update_messages():
	_on_reset()
	message_state.data.sort_custom(func(a,b): return a.id < b.id)
	for message in message_state.data:
		var user = UserState.find_by_pk(message.sender)
		if not user: return
		
		var new_message = Label.new()
		var timestamp := Time.get_datetime_dict_from_unix_time(message.sent / 1_000_000.0 + Time.get_time_zone_from_system().bias * 60)
		new_message.text = "[%s] %s: %s" % ["%02d:%02d:%02d" % [timestamp.hour, timestamp.minute, timestamp.second], user.name if user else "unknown", message.text]
		messages_container.add_child(new_message)

func _on_state_update(_row: Resource):
	update_messages()

func _on_reset() -> void:
	for child in messages_container.get_children():
		child.queue_free()

func _on_input_text_changed(text: String) -> void:
	if input.text.ends_with("\n"):
		input.text = input.text.replace("\n", "")
