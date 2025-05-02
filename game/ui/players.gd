extends Control

@onready var players_container: VBoxContainer = $ScrollContainer/Players

func _ready() -> void:
	_on_reset()
	if not GameState.identity:
		await GameState.identity_updated
	UserState.update.connect(_on_user_updated)
	update_users()

func _exit_tree() -> void:
	_on_reset()
	
func add_title():
	var new_message = Label.new()
	new_message.text = "Connected Players"
	new_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_container.add_child(new_message)

func update_users():
	_on_reset()
	add_title()
	var current_user: User = UserState.find_by_pk(GameState.identity)
	var filtered_users = UserState.data.filter(func(user: User): return user.identity != GameState.identity and user.online)
	for user in [current_user] + filtered_users:
		
		var new_message = Label.new()
		new_message.text = user.name
		new_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if user.identity == GameState.identity:
			new_message.text += " (you)"
		players_container.add_child(new_message)

func _on_user_updated(update: User):
	update_users()

func _on_reset() -> void:
	for child in players_container.get_children():
		child.queue_free()
