extends VehicleBody3D
class_name Vehicle

const STEER_SPEED = 1.5
const STEER_LIMIT = 0.4
const BRAKE_STRENGTH = 2.0

@export var engine_force_value := 40.0

var previous_speed := linear_velocity.length()
var _steer_target := 0.0

@onready var desired_engine_pitch: float = $EngineSound.pitch_scale
@onready var camera_base: Node3D = $CameraBase
@onready var label: Node3D = $Name
@onready var label_front: Label3D = $Name/LabelFront
@onready var label_back: Label3D = $Name/LabelBack
@onready var audio_listener: AudioListener3D = $AudioListener3D

var owner_identity: PackedByteArray
var owner_name: String = ""
var is_owner := true
var car_type := "MINIVAN"

var is_accelerating := false
var is_reversing := false
var is_steering := false

func set_owner_data(new_owner_identity: PackedByteArray, u_is_owner: bool, u_owner_name: String):
	owner_identity = new_owner_identity
	is_owner = u_is_owner
	owner_name = u_owner_name

func set_owner_name(new_name: String):
	owner_name = new_name
	label_front.text = new_name
	label_back.text = new_name

func _ready():
	if not is_owner:
		camera_base.queue_free()
		audio_listener.queue_free()
		label_front.text = owner_name
		label_back.text = owner_name
	else:
		label.queue_free()

func _exit_tree() -> void:
	if is_owner: SpacetimeDB.call_reducer("UpdatePlayerData", [global_position, global_rotation, car_type, false])

func _physics_process(delta: float):
	if is_owner and not is_queued_for_deletion(): SpacetimeDB.call_reducer("UpdatePlayerData", [global_position, global_rotation, car_type, true])
	
	var fwd_mps := (linear_velocity * transform.basis).x

	if is_owner and is_steering:
		_steer_target = Input.get_axis(&"turn_right", &"turn_left")
		_steer_target *= STEER_LIMIT

	# Engine sound simulation (not realistic, as this car script has no notion of gear or engine RPM).
	desired_engine_pitch = 0.05 + linear_velocity.length() / (engine_force_value * 0.5)
	# Change pitch smoothly to avoid abrupt change on collision.
	$EngineSound.pitch_scale = lerpf($EngineSound.pitch_scale, desired_engine_pitch, 0.2)

	if is_owner and abs(linear_velocity.length() - previous_speed) > 1.0:
		# Sudden velocity change, likely due to a collision. Play an impact sound to give audible feedback,
		# and vibrate for haptic feedback.
		$ImpactSound.play()
		Input.vibrate_handheld(100)
		for joypad in Input.get_connected_joypads():
			Input.start_joy_vibration(joypad, 0.0, 0.5, 0.1)

	# Automatically accelerate when using touch controls (reversing overrides acceleration).
	if is_owner and (DisplayServer.is_touchscreen_available() or is_accelerating):
		# Increase engine force at low speeds to make the initial acceleration faster.
		var speed := linear_velocity.length()
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = clampf(engine_force_value * 5.0 / speed, 0.0, 100.0)
		else:
			engine_force = engine_force_value

		if not DisplayServer.is_touchscreen_available():
			# Apply analog throttle factor for more subtle acceleration if not fully holding down the trigger.
			engine_force *= Input.get_action_strength(&"accelerate")
	else:
		engine_force = 0.0

	if is_owner and is_reversing:
		# Increase engine force at low speeds to make the initial reversing faster.
		var speed := linear_velocity.length()
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = -clampf(engine_force_value * BRAKE_STRENGTH * 5.0 / speed, 0.0, 100.0)
		else:
			engine_force = -engine_force_value * BRAKE_STRENGTH

		# Apply analog brake factor for more subtle braking if not fully holding down the trigger.
		engine_force *= Input.get_action_strength(&"reverse")

	steering = move_toward(steering, _steer_target, STEER_SPEED * delta)

	previous_speed = linear_velocity.length()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"accelerate"):
		is_accelerating = true
	elif event.is_action_released(&"accelerate"):
		is_accelerating = false
		
	if event.is_action_pressed(&"reverse"):
		is_reversing = true
	elif event.is_action_released(&"reverse"):
		is_reversing = false
	
	if event.is_action_pressed("turn_left") or event.is_action_pressed("turn_right"):
		is_steering = true
	elif event.is_action_released("turn_left") and not Input.is_action_pressed("turn_right"):
		is_steering = false
		_steer_target = 0
	elif event.is_action_released("turn_right") and not Input.is_action_pressed("turn_left"):
		is_steering = false
		_steer_target = 0
