extends Node2D

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"
const WS_URL := "wss://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io/ws?token="
const INPUT_SEND_INTERVAL := 0.05
const WORLD_SIZE := Vector2(4000.0, 2400.0)
const CELL_SIZE := 50.0

var socket := WebSocketPeer.new()
var socket_started := false
var session_token := ""
var account: Dictionary = {}
var self_id := 0
var world_size := WORLD_SIZE
var cell_size := CELL_SIZE
var grid_width := 80
var grid_height := 48
var territory: Array = []
var players: Dictionary = {}
var input_vector := Vector2.ZERO
var input_timer := 0.0
var joystick_active := false
var joystick_touch_id := -1
var joystick_center := Vector2(145.0, 570.0)
var joystick_radius := 86.0
var joystick_knob := Vector2.ZERO
var connected := false
var camera: Camera2D

@onready var status_label: Label = $HUD/TopBar/Status
@onready var player_label: Label = $HUD/TopBar/Player
@onready var territory_label: Label = $HUD/TopBar/Territory
@onready var joystick_hint: Label = $HUD/JoystickHint

func _ready() -> void:
    session_token = str(get_meta("session_token", ""))
    account = get_meta("account", {})
    camera = $Camera2D
    camera.position = world_size * 0.5
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = int(world_size.x)
    camera.limit_bottom = int(world_size.y)
    status_label.text = "Connecting to ConquerX..."
    player_label.text = str(account.get("username", "Player"))
    joystick_hint.text = "Touch & drag to move"
    queue_redraw()
    if session_token.is_empty():
        status_label.text = "Session missing"
        return
    _connect_game()

func _connect_game() -> void:
    var error := socket.connect_to_url(WS_URL + Uri.encode_component(session_token, ""))
    if error != OK:
        status_label.text = "Connection failed"
        return
    socket_started = true

func _process(delta: float) -> void:
    if socket_started:
        socket.poll()
        var state := socket.get_ready_state()
        if state == WebSocketPeer.STATE_OPEN:
            if not connected:
                connected = true
                status_label.text = "LIVE • Server connected"
            input_timer += delta
            if input_timer >= INPUT_SEND_INTERVAL:
                input_timer = 0.0
                _send_input()
            while socket.get_available_packet_count() > 0:
                var packet := socket.get_packet()
                _handle_server_message(packet.get_string_from_utf8())
        elif state == WebSocketPeer.STATE_CLOSING:
            status_label.text = "Closing connection..."
        elif state == WebSocketPeer.STATE_CLOSED:
            if connected:
                connected = false
                status_label.text = "Disconnected • retrying..."
                socket_started = false
                await get_tree().create_timer(2.0).timeout
                if is_inside_tree():
                    socket = WebSocketPeer.new()
                    _connect_game()
    queue_redraw()

func _send_input() -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    var payload := {"type": "input", "x": input_vector.x, "y": input_vector.y}
    socket.send_text(JSON.stringify(payload))

func _handle_server_message(text: String) -> void:
    var data = JSON.parse_string(text)
    if typeof(data) != TYPE_DICTIONARY:
        return
    var message_type := str(data.get("type", ""))
    if message_type == "state":
        var world = data.get("world", {})
        world_size = Vector2(float(world.get("width", 4000)), float(world.get("height", 2400)))
        cell_size = float(world.get("cell_size", 50))
        grid_width = int(world.get("grid_width", 80))
        grid_height = int(world.get("grid_height", 48))
        self_id = int(data.get("self_id", self_id))
        territory = data.get("territory", [])
        _apply_players(data.get("players", []))
    elif message_type == "player_joined":
        var joined = data.get("player", {})
        if typeof(joined) == TYPE_DICTIONARY:
            players[int(joined.get("id", 0))] = joined
    elif message_type == "player_left":
        players.erase(int(data.get("id", 0)))
    elif message_type == "error":
        status_label.text = str(data.get("message", "Server error"))
    _update_self_ui()

func _apply_players(server_players: Array) -> void:
    var next_players: Dictionary = {}
    for item in server_players:
        if typeof(item) == TYPE_DICTIONARY:
            var id := int(item.get("id", 0))
            if id > 0:
                next_players[id] = item
    players = next_players
    if players.has(self_id):
        var me: Dictionary = players[self_id]
        camera.position = Vector2(float(me.get("x", world_size.x * 0.5)), float(me.get("y", world_size.y * 0.5)))

func _update_self_ui() -> void:
    if not players.has(self_id):
        return
    var me: Dictionary = players[self_id]
    territory_label.text = "Territory  %s" % str(me.get("territory", 0))

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and event.position.x < get_viewport_rect().size.x * 0.55 and joystick_touch_id == -1:
            joystick_touch_id = event.index
            joystick_active = true
            joystick_center = event.position
            joystick_knob = event.position
            _update_joystick(event.position)
        elif not event.pressed and event.index == joystick_touch_id:
            _release_joystick()
    elif event is InputEventScreenDrag and event.index == joystick_touch_id:
        _update_joystick(event.position)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and event.position.x < get_viewport_rect().size.x * 0.55:
            joystick_touch_id = -2
            joystick_active = true
            joystick_center = event.position
            joystick_knob = event.position
            _update_joystick(event.position)
        elif not event.pressed and joystick_touch_id == -2:
            _release_joystick()
    elif event is InputEventMouseMotion and joystick_touch_id == -2 and joystick_active:
        _update_joystick(event.position)
    elif event is InputEventKey and event.pressed:
        var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
        if keyboard.length() > 0.01:
            input_vector = keyboard.normalized()

func _update_joystick(position: Vector2) -> void:
    var offset := position - joystick_center
    if offset.length() > joystick_radius:
        offset = offset.normalized() * joystick_radius
    joystick_knob = joystick_center + offset
    input_vector = offset / joystick_radius

func _release_joystick() -> void:
    joystick_touch_id = -1
    joystick_active = false
    joystick_knob = joystick_center
    input_vector = Vector2.ZERO

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, world_size), Color("101827"), true)
    for y in range(grid_height):
        for x in range(grid_width):
            var index := y * grid_width + x
            if index >= territory.size():
                continue
            var owner := int(territory[index])
            if owner <= 0:
                continue
            var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size + 1.0, cell_size + 1.0))
            draw_rect(rect, _player_color(owner, 0.52), true)
    for x in range(0, grid_width + 1):
        var px := x * cell_size
        draw_line(Vector2(px, 0), Vector2(px, world_size.y), Color(0.14, 0.18, 0.25, 0.42), 1.0)
    for y in range(0, grid_height + 1):
        var py := y * cell_size
        draw_line(Vector2(0, py), Vector2(world_size.x, py), Color(0.14, 0.18, 0.25, 0.42), 1.0)
    for id in players.keys():
        var player: Dictionary = players[id]
        var pos := Vector2(float(player.get("x", 0)), float(player.get("y", 0)))
        var is_me := int(id) == self_id
        draw_circle(pos, 22.0 if is_me else 18.0, _player_color(int(id), 1.0))
        draw_circle(pos, 8.0, Color(0.95, 0.98, 1.0, 1.0))
        draw_string(ThemeDB.fallback_font, pos + Vector2(-45, -32), str(player.get("username", "Player")), HORIZONTAL_ALIGNMENT_CENTER, 90, 16, Color(0.9, 0.94, 1.0, 1.0))
    if joystick_active:
        draw_circle(joystick_center, joystick_radius, Color(0.05, 0.08, 0.14, 0.82))
        draw_circle(joystick_center, joystick_radius, Color(0.35, 0.65, 1.0, 0.35), false, 4.0)
        draw_circle(joystick_knob, 34.0, Color(0.35, 0.65, 1.0, 0.9))

func _player_color(id: int, alpha: float) -> Color:
    if id == self_id:
        return Color(0.18, 0.58, 1.0, alpha)
    var hue := fmod(float(id * 0.173), 1.0)
    return Color.from_hsv(hue, 0.62, 0.92, alpha)
