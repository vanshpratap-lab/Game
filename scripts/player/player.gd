extends CharacterBody3D

@export var move_speed: float = 5.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.01

@export_group("References")
@export var camera_rig: Node3D
@export var camera: Camera3D

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    velocity = Vector3.ZERO
    if camera == null:
        camera = get_node_or_null("CameraRig/Camera3D") as Camera3D
    if camera_rig == null:
        camera_rig = get_node_or_null("CameraRig") as Node3D

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if event is InputEventMouseMotion:
        rotation.y -= event.relative.x * mouse_sensitivity
        camera_rig.rotation.x = clamp(
            camera_rig.rotation.x - event.relative.y * mouse_sensitivity,
            deg_to_rad(-89.0),
            deg_to_rad(89.0)
        )

func _physics_process(delta: float) -> void:
    var input_vector := Input.get_vector(
        "move_left",
        "move_right",
        "move_forward",
        "move_backward"
    )
    var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
    velocity.x = direction.x * move_speed
    velocity.z = direction.z * move_speed

    if not is_on_floor():
        velocity.y += get_gravity().y * delta
    else:
        velocity.y = 0.0
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity
    move_and_slide()
