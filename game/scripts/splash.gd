extends Control

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"

@onready var status_label: Label = $Status
@onready var progress: ProgressBar = $Progress

func _ready() -> void:
    get_viewport().size_changed.connect(_layout_splash)
    _layout_splash()
    status_label.text = I18n.text_for("server_online")
    _start_splash()

func _start_splash() -> void:
    var tween := create_tween()
    tween.tween_property(progress, "value", 70.0, 1.4)
    tween.tween_callback(_check_server)

func _check_server() -> void:
    status_label.text = I18n.text_for("server_unavailable")
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_health_completed.bind(request))
    var error := request.request(SERVER_URL.rstrip("/") + "/health")
    if error != OK:
        _finish_with_offline(request)

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
    request.queue_free()
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        status_label.text = I18n.text_for("server_online")
        progress.value = 100.0
    else:
        status_label.text = I18n.text_for("server_unavailable")
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

func _layout_splash() -> void:
    var viewport_size := get_viewport_rect().size
    var center := viewport_size * 0.5
    $Glow.visible = false
    $Logo.position = center + Vector2(-120, -205)
    $Logo.size = Vector2(240, 240)
    $Title.position = center + Vector2(-250, 48)
    $Title.size = Vector2(500, 58)
    $Status.position = center + Vector2(-360, 112)
    $Status.size = Vector2(720, 36)
    $Progress.position = center + Vector2(-220, 166)
    $Progress.size = Vector2(440, 14)
