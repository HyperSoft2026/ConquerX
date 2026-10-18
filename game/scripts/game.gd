extends Node2D

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"
const WS_URL := "wss://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io/ws?token="
const WORLD_SIZE := Vector2(4000.0, 2400.0)
const CELL_SIZE := 50.0
const INPUT_INTERVAL := 0.05

var socket := WebSocketPeer.new()
var socket_started := false
var connected := false
var session_token := ""
var account: Dictionary = {}
var players: Dictionary = {}
var territory: Array = []
var self_id := 0
var world_size := WORLD_SIZE
var cell_size := CELL_SIZE
var grid_width := 80
var grid_height := 48
var input_vector := Vector2.ZERO
var input_timer := 0.0
var joystick_active := false
var joystick_touch_id := -1
var joystick_center := Vector2(145,570)
var joystick_radius := 86.0
var joystick_knob := Vector2.ZERO
var dead := false
var match_status := "waiting"
var match_remaining_ms := 0
var profile_open := false
var leaderboard_open := false
var skins_open := false
var shop_open := false
var settings_open := false
var dynamic_panel: Panel
var sound_enabled := true
var music_enabled := true
var effects_enabled := true
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback
var sfx_playback: AudioStreamGeneratorPlayback
var music_phase := 0.0
var camera_target := WORLD_SIZE * 0.5
var reconnect_timer := 0.0
var reconnect_delay := 1.0

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

func _ready() -> void:
    $HUD/TopBar/ProfileButton.visible = false
    $HUD/TopBar/LeaderboardButton.visible = false
    $HUD/TopBar/SkinsButton.visible = false
    $HUD/JoystickHint.visible = false
    $HUD/VirtualJoystick.vector_changed.connect(_on_joystick_vector_changed)
    _add_panel_close_buttons()
    session_token = str(get_meta("session_token", ""))
    account = get_meta("account", {})
    _setup_audio()
    _add_header_buttons()
    camera_target = world_size * 0.5
    $Camera2D.position_smoothing_enabled = false
    $Camera2D.position = camera_target
    $Camera2D.limit_left = 0
    $Camera2D.limit_top = 0
    $Camera2D.limit_right = int(world_size.x)
    $Camera2D.limit_bottom = int(world_size.y)
    player_label.text = str(account.get("username", "Player"))
    death_panel.visible = false
    profile_panel.visible = false
    leaderboard_panel.visible = false
    skins_panel.visible = false
    status_label.text = "Finding a match..."
    if session_token.is_empty():
        status_label.text = "Session missing"
        return
    _connect_game()

func _add_panel_close_buttons() -> void:
    _add_panel_close_button(profile_panel, 510, 12)
    _add_panel_close_button(leaderboard_panel, 720, 10)
    _add_panel_close_button(skins_panel, 870, 10)

func _add_panel_close_button(panel:Control, x:float, y:float) -> void:
    var close := Button.new()
    close.text = "✕"
    close.position = Vector2(x, y)
    close.size = Vector2(48, 44)
    close.focus_mode = Control.FOCUS_NONE
    close.pressed.connect(Callable(self, "_close_existing"))
    panel.add_child(close)

func _add_header_buttons() -> void:
    $HUD/TopBar/Player.position = Vector2(18, 8)
    $HUD/TopBar/Player.size = Vector2(205, 48)
    $HUD/TopBar/Status.position = Vector2(225, 8)
    $HUD/TopBar/Status.size = Vector2(340, 48)
    $HUD/TopBar/Territory.position = Vector2(575, 8)
    $HUD/TopBar/Territory.size = Vector2(175, 48)
    $HUD/TopBar/Kills.position = Vector2(755, 8)
    $HUD/TopBar/Kills.size = Vector2(95, 48)
    var pause := Button.new()
    pause.text = "Ⅱ"
    pause.tooltip_text = "Menu"
    pause.position = Vector2(1080, 6)
    pause.size = Vector2(60, 50)
    pause.focus_mode = Control.FOCUS_NONE
    pause.pressed.connect(_show_pause_menu)
    $HUD/TopBar.add_child(pause)
    var board := Button.new()
    board.text = "🏆"
    board.tooltip_text = "Leaderboard"
    board.position = Vector2(1148, 6)
    board.size = Vector2(70, 50)
    board.focus_mode = Control.FOCUS_NONE
    board.pressed.connect(_on_leaderboard_pressed)
    $HUD/TopBar.add_child(board)

func _setup_audio() -> void:
    music_player = AudioStreamPlayer.new()
    add_child(music_player)
    var music_stream := AudioStreamGenerator.new()
    music_stream.mix_rate = 22050
    music_stream.buffer_length = 0.5
    music_player.stream = music_stream
    sfx_player = AudioStreamPlayer.new()
    add_child(sfx_player)
    var sfx_stream := AudioStreamGenerator.new()
    sfx_stream.mix_rate = 22050
    sfx_stream.buffer_length = 0.2
    sfx_player.stream = sfx_stream
    if music_enabled:
        music_player.play()
        music_playback = music_player.get_stream_playback()

func _process(delta: float) -> void:
    if music_enabled and music_player.playing and music_playback != null:
        var frames := music_playback.get_frames_available()
        for i in range(frames):
            var v := sin(music_phase) * 0.018
            music_phase += TAU * 110.0 / 22050.0
            music_playback.push_frame(Vector2(v, v))

    # Smoothly track the local player on every frame, clamped to world bounds.
    var camera := $Camera2D
    var view_size := get_viewport_rect().size / camera.zoom
    var half := view_size * 0.5
    var min_x := min(half.x, world_size.x * 0.5)
    var max_x := max(min_x, world_size.x - half.x)
    var min_y := min(half.y, world_size.y * 0.5)
    var max_y := max(min_y, world_size.y - half.y)
    camera_target.x = clamp(camera_target.x, min_x, max_x)
    camera_target.y = clamp(camera_target.y, min_y, max_y)
    camera.position = camera.position.lerp(camera_target, 1.0 - exp(-delta * 8.5))

    if socket_started:
        socket.poll()
        if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
            if not connected:
                connected = true
                reconnect_delay = 1.0
                status_label.text = I18n.text_for("match_connected")
            input_timer += delta
            if input_timer >= INPUT_INTERVAL:
                input_timer = 0.0
                _send_input()
            while socket.get_available_packet_count() > 0:
                _handle_message(socket.get_packet().get_string_from_utf8())
        elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
            socket_started = false
            connected = false
            reconnect_timer = reconnect_delay
            reconnect_delay = min(reconnect_delay * 2.0, 16.0)
            status_label.text = I18n.text_for("reconnecting")
    elif not session_token.is_empty():
        reconnect_timer -= delta
        if reconnect_timer <= 0.0:
            socket = WebSocketPeer.new()
            _connect_game()
    queue_redraw()

func _connect_game() -> void:
    var result := socket.connect_to_url(WS_URL + session_token.uri_encode())
    if result != OK:
        status_label.text = "Connection failed"
        return
    socket_started = true

func _send_input() -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN or dead or match_status != "playing":
        return
    socket.send_text(JSON.stringify({"type":"input","x":input_vector.x,"y":input_vector.y}))

func _handle_message(text: String) -> void:
    var data = JSON.parse_string(text)
    if typeof(data) != TYPE_DICTIONARY:
        return
    var t := str(data.get("type", ""))
    if t == "matchmaking":
        match_status = "waiting"
        status_label.text = "Finding players • %s/%s" % [str(data.get("players",1)),str(data.get("max_players",20))]
    elif t == "match_found":
        match_status = "playing"
        status_label.text = "MATCH FOUND • FIGHT!"
        _sound(600.0,0.10)
    elif t == "state":
        _apply_state(data)
    elif t == "state_tick":
        match_remaining_ms = int(data.get("match_remaining_ms",match_remaining_ms))
        territory = data.get("territory",territory)
        _apply_players(data.get("players",[]),false)
    elif t == "player_left":
        players.erase(int(data.get("id",0)))
    elif t == "death":
        dead = true
        input_vector = Vector2.ZERO
        death_label.text = "ELIMINATED\nDefeated by %s\nRespawning..." % str(data.get("killer","another player"))
        death_panel.visible = true
        _sound(150.0,0.18)
    elif t == "respawned":
        dead = false
        death_panel.visible = false
        _sound(420.0,0.08)
    elif t == "kill" and int(data.get("killer_id",-1)) == self_id:
        status_label.text = "⚔ KILL • %s" % str(data.get("victim","Player"))
        _sound(720.0,0.10)
    elif t == "match_end":
        match_status = "finished"
        _show_match_end(data)
        _refresh_account()
        _sound(880.0,0.25)
    elif t == "error":
        status_label.text = str(data.get("message","Server error"))
    _update_ui()

func _apply_state(data: Dictionary) -> void:
    var world: Dictionary = data.get("world",{})
    world_size = Vector2(float(world.get("width",4000)),float(world.get("height",2400)))
    cell_size = float(world.get("cell_size",50))
    grid_width = int(world.get("grid_width",80))
    grid_height = int(world.get("grid_height",48))
    self_id = int(data.get("self_id",self_id))
    match_status = str(data.get("match_status",match_status))
    match_remaining_ms = int(data.get("match_remaining_ms",match_remaining_ms))
    territory = data.get("territory",[])
    _apply_players(data.get("players",[]),true)

func _apply_players(items:Array, _move_camera:bool) -> void:
    var next:Dictionary = {}
    for item in items:
        if typeof(item) == TYPE_DICTIONARY:
            var id := int(item.get("id", 0))
            if id > 0:
                next[id] = item
    players = next
    if players.has(self_id):
        var me:Dictionary = players[self_id]
        dead = bool(me.get("dead", false))
        if not dead:
            camera_target = Vector2(float(me.get("x", world_size.x * 0.5)), float(me.get("y", world_size.y * 0.5)))

func _update_ui() -> void:
    if players.has(self_id):
        var me:Dictionary = players[self_id]
        territory_label.text = "Territory %s" % str(me.get("territory",0))
        kills_label.text = "⚔ %s" % str(me.get("kills",0))
    if match_status == "playing":
        var seconds: int = maxi(0, int(match_remaining_ms / 1000))
        status_label.text = "LIVE • %02d:%02d" % [int(seconds/60),seconds%60]

func _unhandled_key_input(event:InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
            if _ui_open():
                _close_existing()
            else:
                _show_pause_menu()
            get_viewport().set_input_as_handled()

func _on_joystick_vector_changed(value:Vector2) -> void:
    input_vector = Vector2.ZERO if _ui_open() else value

func _ui_open() -> bool:
    return profile_open or leaderboard_open or skins_open or shop_open or settings_open or dynamic_panel != null or dead

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,world_size),Color("101827"),true)
    for y in range(grid_height):
        for x in range(grid_width):
            var index := y*grid_width+x
            if index >= territory.size(): continue
            var owner := int(territory[index])
            if owner > 0:
                draw_rect(Rect2(Vector2(x*cell_size,y*cell_size),Vector2(cell_size+1,cell_size+1)),_player_color(owner,0.48),true)
    for x in range(grid_width+1):
        draw_line(Vector2(x*cell_size,0),Vector2(x*cell_size,world_size.y),Color(0.14,0.18,0.25,0.42),1.0)
    for y in range(grid_height+1):
        draw_line(Vector2(0,y*cell_size),Vector2(world_size.x,y*cell_size),Color(0.14,0.18,0.25,0.42),1.0)
    for id in players.keys():
        var p:Dictionary = players[id]
        if bool(p.get("dead",false)): continue
        var pos := Vector2(float(p.get("x",0)),float(p.get("y",0)))
        var mine := int(id) == self_id
        var pulse := sin(Time.get_ticks_msec()*0.006)*2.0 if mine else 0.0
        draw_circle(pos, 29.0 if mine else 22.0, _player_color(int(id), 0.18))
        draw_circle(pos, (23.0+pulse) if mine else 18.0, _player_color(int(id),1.0))
        draw_circle(pos + Vector2(-6,-2), 5.0, Color(0.95,0.98,1,1))
        draw_circle(pos + Vector2(6,-2), 5.0, Color(0.95,0.98,1,1))
        draw_circle(pos + Vector2(-6,-2), 2.5, Color(0.05,0.12,0.3,1))
        draw_circle(pos + Vector2(6,-2), 2.5, Color(0.05,0.12,0.3,1))
        draw_string(ThemeDB.fallback_font,pos+Vector2(-70,-35),str(p.get("username","Player")),HORIZONTAL_ALIGNMENT_CENTER,140,16,Color(0.9,0.94,1,1))


func _player_color(id:int,alpha:float)->Color:
    var palette:Array = [Color("#ff5252"), Color("#43a5ff"), Color("#5fe08a"), Color("#ffd447"), Color("#bd7bff"), Color("#ff8a3d")]
    var index := posmod(max(1, id) - 1, palette.size())
    var color:Color = palette[index]
    color.a = alpha
    return color

func _close_existing() -> void:
    profile_open=false;leaderboard_open=false;skins_open=false;shop_open=false;settings_open=false
    input_vector = Vector2.ZERO
    profile_panel.visible=false;leaderboard_panel.visible=false;skins_panel.visible=false
    if dynamic_panel != null:
        dynamic_panel.queue_free()
        dynamic_panel=null

func _show_pause_menu() -> void:
    _close_existing()
    var panel := _new_panel("MENU", Vector2(340, 110), Vector2(600, 500))
    var w := 250.0
    _button(panel, I18n.text_for("profile"), Vector2(28, 82), Vector2(w, 62), Callable(self, "_on_profile_pressed"))
    _button(panel, I18n.text_for("shop"), Vector2(320, 82), Vector2(w, 62), Callable(self, "_on_shop_pressed"))
    _button(panel, I18n.text_for("skins"), Vector2(28, 160), Vector2(w, 62), Callable(self, "_on_skins_pressed"))
    _button(panel, I18n.text_for("leaderboard"), Vector2(320, 160), Vector2(w, 62), Callable(self, "_on_leaderboard_pressed"))
    _button(panel, I18n.text_for("settings"), Vector2(28, 238), Vector2(w, 62), Callable(self, "_on_settings_pressed"))
    _button(panel, I18n.text_for("close"), Vector2(320, 238), Vector2(w, 62), Callable(self, "_close_existing"))

func _on_profile_pressed() -> void:
    _close_existing();profile_open=true;profile_panel.visible=true;_load_profile()
func _on_leaderboard_pressed() -> void:
    _close_existing();leaderboard_open=true;leaderboard_panel.visible=true;_load_leaderboard()
func _on_skins_pressed() -> void:
    _close_existing();skins_open=true;_show_skins()
func _on_shop_pressed() -> void:
    _close_existing();shop_open=true;_show_shop()
func _on_settings_pressed() -> void:
    _close_existing();settings_open=true;_show_settings()

func _load_profile() -> void:
    _http_get("/profile",Callable(self,"_profile_loaded"))
func _profile_loaded(data:Dictionary) -> void:
    account=data.get("profile",account)
    profile_text.text="PROFILE\n\n%s\n\nLevel %s   XP %s\nGold %s   Gems %s\nKills %s   Wins %s\nEquipped Skin %02d" % [str(account.get("username","Player")),str(account.get("level",1)),str(account.get("xp",0)),str(account.get("gold",0)),str(account.get("gems",0)),str(account.get("kills",0)),str(account.get("wins",0)),int(account.get("selected_skin",1))]
func _load_leaderboard() -> void:
    _http_get("/leaderboard?sort=gold&limit=500",Callable(self,"_leaderboard_loaded"))
func _leaderboard_loaded(data:Dictionary) -> void:
    var text := "TOP 500 • GOLD\n\n"
    for row in data.get("leaderboard",[]):
        text += "%3d. %-20s G:%-6s W:%-3s L:%-3s\n" % [int(row.get("rank",0)),str(row.get("username","Player")).left(20),str(row.get("gold",0)),str(row.get("wins",0)),str(row.get("level",1))]
    leaderboard_text.text=text

func _show_skins() -> void:
    skins_panel.visible=true
    var title:Label=skins_panel.get_node("Title")
    title.text="50 SKINS • OWNED %s" % str(_unlocked().size())
    var scroll:ScrollContainer=skins_panel.get_node("Scroll")
    var grid:GridContainer=scroll.get_node("SkinsGrid")
    for c in grid.get_children(): c.queue_free()
    for i in range(1,51):
        var b:=Button.new()
        b.custom_minimum_size=Vector2(150,58)
        var owned:=i in _unlocked()
        b.text=("✓ " if owned else "🔒 ")+"SKIN %02d"%i
        if owned: b.pressed.connect(_equip_skin.bind(i))
        grid.add_child(b)
func _equip_skin(id:int) -> void:
    _http_post("/profile/skin",{"skin_id":id},func(_d):account["selected_skin"]=id;_sound(650,0.08);_show_skins())
func _unlocked()->Array:
    var value=account.get("unlocked_skins",[1])
    return value if typeof(value)==TYPE_ARRAY else [1]

func _new_panel(title:String,pos:Vector2,size:Vector2)->Panel:
    if dynamic_panel != null: dynamic_panel.queue_free()
    dynamic_panel=Panel.new();dynamic_panel.position=pos;dynamic_panel.size=size;$HUD.add_child(dynamic_panel)
    var label:=Label.new();label.text=title;label.position=Vector2(24,18);label.size=Vector2(size.x-130,42);label.add_theme_font_size_override("font_size",26);dynamic_panel.add_child(label)
    var close:=Button.new();close.text="✕";close.position=Vector2(size.x-74,14);close.size=Vector2(52,46);close.focus_mode=Control.FOCUS_NONE;close.pressed.connect(Callable(self,"_close_existing"));dynamic_panel.add_child(close)
    return dynamic_panel
func _button(parent:Control,text:String,pos:Vector2,size:Vector2,callback:Callable)->Button:
    var b:=Button.new();b.text=text;b.position=pos;b.size=size;b.pressed.connect(callback);parent.add_child(b);return b

func _show_shop() -> void:
    var panel:=_new_panel("STORE • GOLD & GEMS",Vector2(150,90),Vector2(980,590))
    var info:=Label.new();info.position=Vector2(25,55);info.text="Gold: %s     Gems: %s"%[str(account.get("gold",0)),str(account.get("gems",0))];panel.add_child(info)
    var scroll:=ScrollContainer.new();scroll.position=Vector2(20,95);scroll.size=Vector2(940,460);panel.add_child(scroll)
    var grid:=GridContainer.new();grid.columns=4;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(grid)
    _http_get("/shop",func(data):
        for item in data.get("items",[]):
            var b:=Button.new();b.custom_minimum_size=Vector2(215,80);b.text="%s\nGold %s • Gems %s"%[str(item.get("name","Item")),str(item.get("gold_cost",0)),str(item.get("gems_cost",0))];b.pressed.connect(_buy_item.bind(str(item.get("id",""))));grid.add_child(b)
        for skin in data.get("skins",[]):
            var id:=int(skin.get("id",0));var owned:=id in _unlocked();var b:=Button.new();b.custom_minimum_size=Vector2(215,80);b.text=("✓ " if owned else "BUY ")+"Skin %02d\nG %s • 💎 %s"%[id,str(skin.get("gold_cost",0)),str(skin.get("gems_cost",0))];if not owned:b.pressed.connect(_buy_skin.bind(id));grid.add_child(b))
func _buy_item(id:String)->void:
    _http_post("/shop/buy",{"type":"currency","id":id},func(_d):_refresh_account();_sound(700,0.1);_show_shop())
func _buy_skin(id:int)->void:
    _http_post("/shop/buy",{"type":"skin","id":id},func(data):account["unlocked_skins"]=data.get("unlocked_skins",_unlocked());_sound(760,0.1);_show_shop())

func _show_settings() -> void:
    var panel:=_new_panel("SETTINGS",Vector2(350,120),Vector2(580,480))
    _button(panel,"Sound: %s" % ("ON" if sound_enabled else "OFF"),Vector2(60,85),Vector2(460,62),Callable(self,"_toggle_sound"))
    _button(panel,"Music: %s" % ("ON" if music_enabled else "OFF"),Vector2(60,160),Vector2(460,62),Callable(self,"_toggle_music"))
    _button(panel,"Effects: %s" % ("ON" if effects_enabled else "OFF"),Vector2(60,235),Vector2(460,62),Callable(self,"_toggle_effects"))
    _button(panel,I18n.text_for("language") + ": " + ("English" if I18n.is_arabic() else "العربية"),Vector2(60,310),Vector2(460,54),Callable(self,"_toggle_language"))
    _button(panel,I18n.text_for("back_match"),Vector2(60,380),Vector2(460,54),Callable(self,"_close_existing"))
func _toggle_sound()->void:sound_enabled=!sound_enabled;_show_settings()
func _toggle_music()->void:
    music_enabled=!music_enabled
    if music_enabled:
        music_player.play();music_playback=music_player.get_stream_playback()
    else: music_player.stop()
    _show_settings()
func _toggle_effects()->void:effects_enabled=!effects_enabled;_show_settings()
func _toggle_language()->void:
    I18n.set_language("en" if I18n.is_arabic() else "ar")
    I18n.apply_tree($HUD)
    _show_settings()

func _show_match_end(data:Dictionary) -> void:
    _close_existing()
    var panel:=_new_panel("MATCH COMPLETE",Vector2(300,105),Vector2(680,510))
    var text:=Label.new();text.position=Vector2(35,70);text.size=Vector2(610,290);text.text="Place #%s\n+%s Gold   +%s Gems   +%s XP\n\nTOP PLAYERS\n"%[str(data.get("place",0)),str(data.get("gold_reward",0)),str(data.get("gems_reward",0)),str(data.get("xp_reward",0))]
    for row in data.get("results",[]):text.text+="#%s  %s  • %s territory • %s kills\n"%[str(row.get("place",0)),str(row.get("username","Player")),str(row.get("territory",0)),str(row.get("kills",0))]
    panel.add_child(text)
    _button(panel,"PLAY AGAIN",Vector2(35,420),Vector2(290,58),Callable(self,"_play_again"))
    _button(panel,"CLOSE",Vector2(355,420),Vector2(290,58),Callable(self,"_close_existing"))
func _play_again()->void:
    _close_existing();socket=WebSocketPeer.new();socket_started=false;connected=false;_connect_game()

func _refresh_account()->void:_http_get("/profile",func(data):account=data.get("profile",account))
func _http_get(path:String,callback:Callable)->void:
    var req:=HTTPRequest.new();add_child(req)
    req.request_completed.connect(func(result,code,_headers,body):
        req.queue_free()
        if result==HTTPRequest.RESULT_SUCCESS and code==200:
            var data=JSON.parse_string(body.get_string_from_utf8())
            if typeof(data)==TYPE_DICTIONARY:callback.call(data)
    )
    req.request(SERVER_URL+path,PackedStringArray(["Authorization: Bearer %s"%session_token]))
func _http_post(path:String,payload:Dictionary,callback:Callable)->void:
    var req:=HTTPRequest.new();add_child(req)
    req.request_completed.connect(func(result,code,_headers,body):
        req.queue_free()
        if result==HTTPRequest.RESULT_SUCCESS and code>=200 and code<300:
            var data=JSON.parse_string(body.get_string_from_utf8())
            if typeof(data)==TYPE_DICTIONARY:callback.call(data)
        else: status_label.text="Request failed"
    )
    req.request(SERVER_URL+path,PackedStringArray(["Content-Type: application/json","Authorization: Bearer %s"%session_token]),HTTPClient.METHOD_POST,JSON.stringify(payload))
func _sound(freq:float,duration:float)->void:
    if not sound_enabled or not effects_enabled:return
    if not sfx_player.playing:sfx_player.play();sfx_playback=sfx_player.get_stream_playback()
    if sfx_playback==null:return
    var frames: int = mini(sfx_playback.get_frames_available(), int(22050 * duration))
    for i in range(frames):
        var v:=sin(TAU*freq*float(i)/22050.0)*0.08
        sfx_playback.push_frame(Vector2(v,v))
