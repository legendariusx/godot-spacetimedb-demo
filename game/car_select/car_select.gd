extends Control

var town: Node3D = null

@onready var name_input: LineEdit = $Name/NameInput

func _ready():
	# Automatically focus the first item for gamepad accessibility.
	$HBoxContainer/MiniVan.grab_focus.call_deferred()
	if not GameState.current_user:
		await GameState.current_user_upated
	name_input.text = GameState.current_user.name

func _process(_delta: float):
	if Input.is_action_just_pressed(&"back"):
		_on_back_pressed()

func _load_scene(car_scene: PackedScene):
	if name_input.text != "":
		SpacetimeDB.call_reducer("SetName", [name_input.text])
	
	var car: Node3D = car_scene.instantiate()
	car.name = "car"
	town = preload("res://town/town_scene.tscn").instantiate()
	town.get_node(^"InstancePos").add_child(car)
	town.get_node(^"Spedometer").car_body = car.get_child(0)
	town.get_node(^"Back").pressed.connect(_on_back_pressed)

	get_parent().add_child(town)
	hide()


func _on_back_pressed():
	if is_instance_valid(town):
		# Currently in the town, go back to main menu.
		town.queue_free()
		name_input.text = GameState.current_user.name
		show()
		# Automatically focus the first item for gamepad accessibility.
		$HBoxContainer/MiniVan.grab_focus.call_deferred()
	else:
		# In main menu, exit the game.
		get_tree().quit()

func _on_mini_van_pressed():
	_load_scene(preload("res://vehicles/car_base.tscn"))


func _on_trailer_truck_pressed():
	_load_scene(preload("res://vehicles/trailer_truck.tscn"))


func _on_tow_truck_pressed():
	_load_scene(preload("res://vehicles/tow_truck.tscn"))

func _on_name_input_text_changed(text: String) -> void:
	if name_input.text.ends_with("\n"):
		name_input.text = name_input.text.replace("\n", "")
