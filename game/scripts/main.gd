extends Node2D

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"
const LOGIN_POLL_SECONDS := 2.0
const LOGIN_TIMEOUT_SECONDS := 600.0
const GAME_SCENE := preload("res://scenes/game.tscn")

@onready var status_value: Label = $StatusPanel/StatusValue
@onready var continue_button: Button = $ContinueButton
@onready var login_button: Button = $DiscordLoginButton

var login_session_id := ""
var login_elapsed := 0.0
var login_poll_timer := 0.0
var logged_in := false
var session_token := ""
var account: Dictionary = {}

func _ready() -> void:
    continue_button.pressed.connect(_on_continue_pressed)
    login_button.pressed.connect(_on_discord_login_pressed)
    status_value.text = "Checking server..."
    _check_server()

func _process(delta: float) -> void:
    if login_session_id.is_empty() or logged_in:
        return
    login_elapsed += delta
    login_poll_timer += delta
    if login_elapsed >= LOGIN_TIMEOUT_SECONDS:
        status_value.text = "Login timed out. Please try again."
        login_session_id = ""
        login_poll_timer = 0.0
        login_elapsed = 0.0
        login_button.disabled = false
        return
    if login_poll_timer >= LOGIN_POLL_SECONDS:
        login_poll_timer = 0.0
        _poll_login_status()

func _check_server() -> void:
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_health_completed.bind(request))
    var error := request.request(SERVER_URL.rstrip("/") + "/health")
    if error != OK:
        request.queue_free()
        status_value.text = "Connection error"

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
    request.queue_free()
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        status_value.text = "Server online"
    else:
        status_value.text = "Server unavailable"

func _on_discord_login_pressed() -> void:
    if logged_in or not login_session_id.is_empty():
        return
    login_session_id = _make_session_id()
    login_elapsed = 0.0
    login_poll_timer = 0.0
    login_button.disabled = true
    status_value.text = "Opening Discord..."
    var login_url := SERVER_URL.rstrip("/") + "/auth/discord/start?session=" + login_session_id
    var error := OS.shell_open(login_url)
    if error != OK:
        status_value.text = "Could not open Discord."
        login_session_id = ""
        login_button.disabled = false
        return
    status_value.text = "Complete login in Discord, then return to ConquerX."

func _poll_login_status() -> void:
    if login_session_id.is_empty():
        return
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_login_status_completed.bind(request))
    var url := SERVER_URL.rstrip("/") + "/auth/discord/status?session=" + login_session_id
    var error := request.request(url)
    if error != OK:
        request.queue_free()

func _on_login_status_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
    request.queue_free()
    if login_session_id.is_empty() or logged_in:
        return
    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        return
    var parsed = JSON.parse_string(body.get_string_from_utf8())
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    if parsed.get("status", "pending") != "completed":
        return
    var received_token: String = parsed.get("session_token", "")
    var received_account: Dictionary = parsed.get("account", {})
    if received_token.is_empty() or received_account.is_empty():
        status_value.text = "Login response was incomplete. Please try again."
        login_session_id = ""
        login_button.disabled = false
        return
    session_token = received_token
    account = received_account
    logged_in = true
    login_session_id = ""
    login_elapsed = 0.0
    login_poll_timer = 0.0
    login_button.disabled = true
    continue_button.disabled = false
    status_value.text = "Welcome, %s!" % str(account.get("username", "Player"))
    _show_account_summary()

func _show_account_summary() -> void:
    var summary := "Gold: %s   Gems: %s   Kills: %s   Wins: %s   Level: %s" % [
        str(account.get("gold", 0)),
        str(account.get("gems", 0)),
        str(account.get("kills", 0)),
        str(account.get("wins", 0)),
        str(account.get("level", 1))
    ]
    $AccountSummary.text = summary

func _on_continue_pressed() -> void:
    if not logged_in:
        status_value.text = "Please sign in with Discord first."
        return
    var gameplay = GAME_SCENE.instantiate()
    gameplay.set_meta("session_token", session_token)
    gameplay.set_meta("account", account)
    get_tree().root.add_child(gameplay)
    hide()

func _make_session_id() -> String:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var p1 := "%08x" % rng.randi()
    var p2 := "%04x" % (rng.randi() & 0xffff)
    var p3 := "%04x" % (rng.randi() & 0xffff)
    var p4 := "%04x" % (rng.randi() & 0xffff)
    var p5 := "%08x%04x" % [rng.randi(), rng.randi() & 0xffff]
    return "%s-%s-%s-%s-%s" % [p1, p2, p3, p4, p5]
