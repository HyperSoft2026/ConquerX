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
var dead := false
var profile_open := false
var leaderboard_open := false
var skins_open := false

@onready var status_label: Label = $HUD/TopBar/Status
@onready var player_label: Label = $HUD/TopBar/Player
@onready var territory_label: Label = $HUD/TopBar/Territory
@onready var kills_label: Label = $HUD/TopBar/Kills
@onready var death_panel: Panel = $HUD/DeathPanel
@onready var death_label: Label = $HUD/DeathPanel/DeathLabel
@onready var profile_panel: Panel = $HUD/ProfilePanel
@onready var profile_text: Label = $HUD/ProfilePanel/ProfileText
@onready var leaderboard_panel: Panel = $HUD/LeaderboardPanel
@onready var leaderboard_text: Label = $HUD/LeaderboardPanel/LeaderboardText
@onready var skins_panel: Panel = $HUD/SkinsPanel
@onready var skins_grid: GridContainer = $HUD/SkinsPanel/Scroll/SkinsGrid

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
    death_panel.visible = false
    profile_panel.visible = false
    leaderboard_panel.visible = false
    skins_panel.visible = false
    _build_skin_grid()
    queue_redraw()
    if session_token.is_empty():
        status_label.text = "Session missing"
        return
    _connect_game()

func _connect_game() -> void:
    var error := socket.connect_to_url(WS_URL + session_token.uri_encode())
    if error != OK:
        status_label.text = "Connection failed"
        return
    socket_started = true

func _process(_delta: float) -> void:
    if socket_started:
        socket.poll()
        var state := socket.get_ready_state()
        if state == WebSocketPeer.STATE_OPEN:
            if not connected:
                connected = true
                status_label.text = "LIVE • Server connected"
            input_timer += _delta
            if input_timer >= INPUT_SEND_INTERVAL:
                input_timer = 0.0
                _send_input()
            while socket.get_available_packet_count() > 0:
                _handle_server_message(socket.get_packet().get_string_from_utf8())
        elif state == WebSocketPeer.STATE_CLOSED and connected:
            connected = false
            socket_started = false
            status_label.text = "Disconnected • retrying..."
            await get_tree().create_timer(2.0).timeout
            if is_inside_tree():
                socket = WebSocketPeer.new()
                _connect_game()
    queue_redraw()

func _send_input() -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN or dead:
        return
    socket.send_text(JSON.stringify({"type":"input", "x":input_vector.x, "y":input_vector.y}))

func _handle_server_message(text: String) -> void:
    var data = JSON.parse_string(text)
    if typeof(data) != TYPE_DICTIONARY: return
    var message_type := str(data.get("type", ""))
    if message_type == "state":
        var world = data.get("world", {})
        world_size = Vector2(float(world.get("width", 4000)), float(world.get("height", 2400)))
        cell_size = float(world.get("cell_size", 50))
        grid_width = int(world.get("grid_width", 80))
        grid_height = int(world.get("grid_height", 48))
        self_id = int(data.get("self_id", self_id))
        territory = data.get("territory", [])
        _apply_players(data.get("players", []), true)
    elif message_type == "state_tick":
        territory = data.get("territory", territory)
        _apply_players(data.get("players", []), false)
    elif message_type == "player_joined":
        var joined = data.get("player", {})
        if typeof(joined) == TYPE_DICTIONARY: players[int(joined.get("id", 0))] = joined
    elif message_type == "player_left":
        players.erase(int(data.get("id", 0)))
    elif message_type == "death":
        dead = true
        input_vector = Vector2.ZERO
        death_label.text = "ELIMINATED\nDefeated by %s\nRespawning..." % str(data.get("killer", "another player"))
        death_panel.visible = true
    elif message_type == "respawned":
        dead = false
        death_panel.visible = false
    elif message_type == "kill" and int(data.get("killer_id", -1)) == self_id:
        status_label.text = "⚔ KILL! %s eliminated" % str(data.get("victim", "Player"))
    elif message_type == "error":
        status_label.text = str(data.get("message", "Server error"))
    _update_self_ui()

func _apply_players(server_players: Array, move_camera: bool) -> void:
    var next_players: Dictionary = {}
    for item in server_players:
        if typeof(item) == TYPE_DICTIONARY:
            var id := int(item.get("id", 0))
            if id > 0: next_players[id] = item
    players = next_players
    if players.has(self_id):
        var me: Dictionary = players[self_id]
        dead = bool(me.get("dead", false))
        if move_camera or not dead:
            camera.position = Vector2(float(me.get("x", world_size.x * 0.5)), float(me.get("y", world_size.y * 0.5)))

func _update_self_ui() -> void:
    if not players.has(self_id): return
    var me: Dictionary = players[self_id]
    territory_label.text = "Territory  %s" % str(me.get("territory", 0))
    kills_label.text = "⚔ %s" % str(me.get("kills", 0))
    if not bool(me.get("dead", false)): death_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and event.position.x < get_viewport_rect().size.x * 0.55 and joystick_touch_id == -1 and not _ui_open():
            joystick_touch_id = event.index; joystick_active = true; joystick_center = event.position; joystick_knob = event.position; _update_joystick(event.position)
        elif not event.pressed and event.index == joystick_touch_id: _release_joystick()
    elif event is InputEventScreenDrag and event.index == joystick_touch_id: _update_joystick(event.position)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and event.position.x < get_viewport_rect().size.x * 0.55 and not _ui_open():
            joystick_touch_id = -2; joystick_active = true; joystick_center = event.position; joystick_knob = event.position; _update_joystick(event.position)
        elif not event.pressed and joystick_touch_id == -2: _release_joystick()
    elif event is InputEventMouseMotion and joystick_touch_id == -2 and joystick_active: _update_joystick(event.position)
    elif event is InputEventKey and event.pressed:
        var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
        if keyboard.length() > 0.01: input_vector = keyboard.normalized()

func _update_joystick(position: Vector2) -> void:
    var offset := position - joystick_center
    if offset.length() > joystick_radius: offset = offset.normalized() * joystick_radius
    joystick_knob = joystick_center + offset
    input_vector = offset / joystick_radius

func _release_joystick() -> void:
    joystick_touch_id = -1; joystick_active = false; joystick_knob = joystick_center; input_vector = Vector2.ZERO

func _ui_open() -> bool:
    return profile_open or leaderboard_open or skins_open or dead

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, world_size), Color("101827"), true)
    for y in range(grid_height):
        for x in range(grid_width):
            var index := y * grid_width + x
            if index >= territory.size(): continue
            var owner := int(territory[index])
            if owner <= 0: continue
            draw_rect(Rect2(Vector2(x*cell_size,y*cell_size),Vector2(cell_size+1,cell_size+1)), _player_color(owner,0.52), true)
    for x in range(grid_width + 1):
        var px := x * cell_size; draw_line(Vector2(px,0),Vector2(px,world_size.y),Color(0.14,0.18,0.25,0.42),1.0)
    for y in range(grid_height + 1):
        var py := y * cell_size; draw_line(Vector2(0,py),Vector2(world_size.x,py),Color(0.14,0.18,0.25,0.42),1.0)
    for id in players.keys():
        var player: Dictionary = players[id]
        if bool(player.get("dead", false)): continue
        var pos := Vector2(float(player.get("x",0)),float(player.get("y",0)))
        var is_me := int(id) == self_id
        draw_circle(pos,24.0 if is_me else 18.0,_player_color(int(id),1.0))
        draw_circle(pos,8.0,Color(0.95,0.98,1,1))
        draw_string(ThemeDB.fallback_font,pos+Vector2(-55,-32),str(player.get("username","Player")),HORIZONTAL_ALIGNMENT_CENTER,110,16,Color(0.9,0.94,1,1))
    if joystick_active and not _ui_open():
        draw_circle(joystick_center,joystick_radius,Color(0.05,0.08,0.14,0.82))
        draw_circle(joystick_center,joystick_radius,Color(0.35,0.65,1,0.35),false,4.0)
        draw_circle(joystick_knob,34.0,Color(0.35,0.65,1,0.9))

func _player_color(id: int, alpha: float) -> Color:
    var skin_id := 1
    if players.has(id): skin_id = int(players[id].get("skin",1))
    var hue := fmod(float(max(0,skin_id-1))*0.02,1.0)
    return Color.from_hsv(hue,0.72,0.95,alpha)

func _build_skin_grid() -> void:
    for child in skins_grid.get_children(): child.queue_free()
    for i in range(1,51):
        var button:=Button.new(); button.custom_minimum_size=Vector2(150,58); button.text="SKIN %02d"%i; button.pressed.connect(_select_skin.bind(i)); skins_grid.add_child(button)

func _select_skin(skin_id:int) -> void:
    var unlocked=account.get("unlocked_skins",[1])
    if typeof(unlocked)!=TYPE_ARRAY or not skin_id in unlocked:
        status_label.text="Skin %02d is locked"%skin_id; return
    var request:=HTTPRequest.new();add_child(request);request.request_completed.connect(_on_skin_changed.bind(request))
    request.request(SERVER_URL+"/profile/skin",PackedStringArray(["Content-Type: application/json","Authorization: Bearer %s"%session_token]),HTTPClient.METHOD_POST,JSON.stringify({"skin_id":skin_id}))

func _on_skin_changed(result:int,response_code:int,_headers:PackedStringArray,body:PackedByteArray,request:HTTPRequest)->void:
    request.queue_free()
    if result==HTTPRequest.RESULT_SUCCESS and response_code==200:
        var data=JSON.parse_string(body.get_string_from_utf8());account["selected_skin"]=int(data.get("selected_skin",1));status_label.text="Skin equipped";skins_panel.visible=false;skins_open=false

func _on_profile_pressed()->void:
    profile_open=!profile_open;leaderboard_open=false;skins_open=false;profile_panel.visible=profile_open;leaderboard_panel.visible=false;skins_panel.visible=false
    if profile_open:_load_profile()

func _load_profile()->void:
    var request:=HTTPRequest.new();add_child(request);request.request_completed.connect(_on_profile_loaded.bind(request));request.request(SERVER_URL+"/profile",PackedStringArray(["Authorization: Bearer %s"%session_token]))

func _on_profile_loaded(result:int,response_code:int,_headers:PackedStringArray,body:PackedByteArray,request:HTTPRequest)->void:
    request.queue_free()
    if result!=HTTPRequest.RESULT_SUCCESS or response_code!=200:return
    var data=JSON.parse_string(body.get_string_from_utf8());if typeof(data)!=TYPE_DICTIONARY:return
    account=data.get("profile",account)
    profile_text.text="PROFILE\n\n%s\n\nLevel: %s\nGold: %s    Gems: %s\nKills: %s    Wins: %s\nEquipped Skin: %02d\n\nYour progress is saved on the ConquerX server."%[str(account.get("username","Player")),str(account.get("level",1)),str(account.get("gold",0)),str(account.get("gems",0)),str(account.get("kills",0)),str(account.get("wins",0)),int(account.get("selected_skin",1))]

func _on_leaderboard_pressed()->void:
    leaderboard_open=!leaderboard_open;profile_open=false;skins_open=false;leaderboard_panel.visible=leaderboard_open;profile_panel.visible=false;skins_panel.visible=false
    if leaderboard_open:_load_leaderboard()

func _load_leaderboard()->void:
    var request:=HTTPRequest.new();add_child(request);request.request_completed.connect(_on_leaderboard_loaded.bind(request));request.request(SERVER_URL+"/leaderboard?sort=gold&limit=500")

func _on_leaderboard_loaded(result:int,response_code:int,_headers:PackedStringArray,body:PackedByteArray,request:HTTPRequest)->void:
    request.queue_free()
    if result!=HTTPRequest.RESULT_SUCCESS or response_code!=200:return
    var data=JSON.parse_string(body.get_string_from_utf8());if typeof(data)!=TYPE_DICTIONARY:return
    var rows=data.get("leaderboard",[]);var text="TOP 500 • GOLD\n\n"
    for i in range(min(rows.size(),500)):
        var row:Dictionary=rows[i];text+="%3d. %-22s Gold %-8s ⚔ %-5s\n"%[int(row.get("rank",i+1)),str(row.get("username","Player")).left(22),str(row.get("gold",0)),str(row.get("kills",0))]
    leaderboard_text.text=text

func _on_skins_pressed()->void:
    skins_open=!skins_open;profile_open=false;leaderboard_open=false;skins_panel.visible=skins_open;profile_panel.visible=false;leaderboard_panel.visible=false

func _on_close_panels_pressed()->void:
    profile_open=false;leaderboard_open=false;skins_open=false;profile_panel.visible=false;leaderboard_panel.visible=false;skins_panel.visible=false
