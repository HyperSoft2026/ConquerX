extends Control

const SERVER_URL := ""

@onready var status_label: Label = $Status
@onready var progress: ProgressBar = $Progress

func _ready() -> void:
    _start_splash()

func _start_splash() -> void:
    var tween := create_tween()
    tween.tween_property(progress, "value", 70.0, 1.4)
    tween.tween_callback(_check_server)

func _check_server() -> void:
    if SERVER_URL.is_empty():
        status_label.text = "ConquerX is ready"
        progress.value = 100.0
        await get_tree().create_timer(0.7).timeout
        _open_login()
        return

    status_label.text = "Connecting to ConquerX servers..."
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_health_completed.bind(request))
    var error := request.request(SERVER_URL.rstrip("/") + "/health")
    if error != OK:
        _finish_with_offline(request)

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
    request.queue_free()
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        status_label.text = "Server connected"
        progress.value = 100.0
    else:
        status_label.text = "Server unavailable — continuing offline"
        progress.value = 100.0
    await get_tree().create_timer(0.7).timeout
    _open_login()

func _finish_with_offline(request: HTTPRequest) -> void:
    request.queue_free()
    status_label.text = "Server unavailable — continuing offline"
    progress.value = 100.0
    await get_tree().create_timer(0.7).timeout
    _open_login()

func _open_login() -> void:
    get_tree().change_scene_to_file("res://game/scenes/main.tscn")
