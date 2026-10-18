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
var dead := false
var profile_open := false
var leaderboard_open := false
var skins_open := false
var shop_open := false
var settings_open := false
var match_end_open := false
var match_id := ""
var match_status := "waiting"
var match_remaining_ms := 0
var status_message := "Connecting..."
var sound_enabled := true
var music_enabled := true
var effects_enabled := true
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback
var music_phase := 0.0
var sfx_playback: AudioStreamGeneratorPlayback

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
    $HUD/TopBar/ProfileButton.pressed.connect(_on_profile_pressed)
    $HUD/TopBar/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
    $HUD/TopBar/SkinsButton.pressed.connect(_on_skins_pressed)
    session_token = str(get_meta("session_token", ""))
    account = get_meta("account", {})
    _load_local_settings()
    _add_extra_buttons()
    _setup_audio()
    camera_setup()
    status_label.text = "Finding a match..."
    player_label.text = str(account.get("username", "Player"))
    death_panel.visible = false
    profile_panel.visible = false
    leaderboard_panel.visible = false
    skins_panel.visible = false
    if session_token.is_empty(): status_label.text = "Session missing"; return
    _connect_game()

func camera_setup() -> void:
    var camera: Camera2D = $Camera2D
    camera.position = world_size * 0.5
    camera.limit_left = 0; camera.limit_top = 0; camera.limit_right = int(world_size.x); camera.limit_bottom = int(world_size.y)

func _add_extra_buttons() -> void:
    var shop := Button.new(); shop.name = "ShopButton"; shop.text = "Shop"; shop.position = Vector2(1010, 8); shop.size = Vector2(70, 48); shop.pressed.connect(_on_shop_pressed); $HUD/TopBar.add_child(shop)
    var settings := Button.new(); settings.name = "SettingsButton"; settings.text = "⚙"; settings.position = Vector2(1185, 8); settings.size = Vector2(52, 48); settings.pressed.connect(_on_settings_pressed); $HUD/TopBar.add_child(settings)
    $HUD/TopBar/ProfileButton.position = Vector2(790, 8); $HUD/TopBar/ProfileButton.size = Vector2(85,48)
    $HUD/TopBar/LeaderboardButton.position = Vector2(880,8); $HUD/TopBar/LeaderboardButton.size = Vector2(90,48)
    $HUD/TopBar/SkinsButton.position = Vector2(975,8); $HUD/TopBar/SkinsButton.size = Vector2(85,48)

func _setup_audio() -> void:
    music_player = AudioStreamPlayer.new(); music_player.name = "Music"; add_child(music_player)
    var music := AudioStreamGenerator.new(); music.mix_rate = 22050; music.buffer_length = 0.5; music_player.stream = music
    sfx_player = AudioStreamPlayer.new(); sfx_player.name = "SFX"; add_child(sfx_player)
    var sfx := AudioStreamGenerator.new(); sfx.mix_rate = 22050; sfx.buffer_length = 0.2; sfx_player.stream = sfx
    if music_enabled: music_player.play(); music_playback = music_player.get_stream_playback()
    sfx_player.play(); sfx_playback = sfx_player.get_stream_playback()

func _process(delta: float) -> void:
    if music_enabled and music_player.playing and music_playback:
        var frames := music_playback.get_frames_available()
        for i in frames:
            var sample := sin(music_phase) * 0.025
            music_phase += TAU * 110.0 / 22050.0
            music_playback.push_frame(Vector2(sample, sample))
    if socket_started:
        socket.poll()
        var state := socket.get_ready_state()
        if state == WebSocketPeer.STATE_OPEN:
            if not connected: connected = true; status_label.text = "Matchmaking • connected"
            input_timer += delta
            if input_timer >= INPUT_SEND_INTERVAL: input_timer = 0.0; _send_input()
            while socket.get_available_packet_count() > 0: _handle_server_message(socket.get_packet().get_string_from_utf8())
        elif state == WebSocketPeer.STATE_CLOSED and connected:
            connected = false; socket_started = false; status_label.text = "Disconnected • reconnecting..."
            await get_tree().create_timer(2.0).timeout
            if is_inside_tree(): socket = WebSocketPeer.new(); _connect_game()
    queue_redraw()

func _connect_game() -> void:
    var error := socket.connect_to_url(WS_URL + session_token.uri_encode())
    if error != OK: status_label.text = "Connection failed"; return
    socket_started = true

func _send_input() -> void:
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN or dead or match_status != "playing": return
    socket.send_text(JSON.stringify({"type":"input", "x":input_vector.x, "y":input_vector.y}))

func _handle_server_message(text: String) -> void:
    var data = JSON.parse_string(text)
    if typeof(data) != TYPE_DICTIONARY: return
    var t := str(data.get("type", ""))
    if t == "matchmaking":
        match_status = "waiting"; match_id = str(data.get("match_id", "")); status_label.text = "Finding players • %s/%s" % [str(data.get("players",1)),str(data.get("max_players",20))]; _toast("MATCHMAKING", false)
    elif t == "match_found":
        match_status = "playing"; match_id = str(data.get("match_id",match_id)); status_label.text = "MATCH FOUND • Fight!"; _sound(520,0.10)
    elif t == "state":
        match_status = str(data.get("match_status",match_status)); match_id = str(data.get("match_id",match_id)); _apply_state(data)
    elif t == "state_tick":
        match_remaining_ms = int(data.get("match_remaining_ms",match_remaining_ms)); territory = data.get("territory",territory); _apply_players(data.get("players",[]),false)
    elif t == "player_joined":
        var joined = data.get("player", {}); if typeof(joined)==TYPE_DICTIONARY: players[int(joined.get("id",0))]=joined
    elif t == "player_left": players.erase(int(data.get("id",0)))
    elif t == "death":
        dead=true; input_vector=Vector2.ZERO; death_label.text="ELIMINATED\nDefeated by %s\nRespawning..."%str(data.get("killer","another player")); death_panel.visible=true; _sound(150,0.22)
    elif t == "respawned": dead=false; death_panel.visible=false; _sound(420,0.08)
    elif t == "kill" and int(data.get("killer_id",-1))==self_id:
        status_label.text="⚔ KILL • %s"%str(data.get("victim","Player")); _sound(720,0.12)
    elif t == "match_end":
        match_status="finished"; match_end_open=true; _show_match_end(data); _refresh_account(); _sound(880,0.25)
    elif t == "error": status_label.text=str(data.get("message","Server error"))
    _update_self_ui()

func _apply_state(data: Dictionary) -> void:
    var world=data.get("world",{}); world_size=Vector2(float(world.get("width",4000)),float(world.get("height",2400))); cell_size=float(world.get("cell_size",50)); grid_width=int(world.get("grid_width",80)); grid_height=int(world.get("grid_height",48)); self_id=int(data.get("self_id",self_id)); territory=data.get("territory",[]); match_remaining_ms=int(data.get("match_remaining_ms",0)); _apply_players(data.get("players",[]),true)

func _apply_players(server_players: Array, move_camera: bool) -> void:
    var next:Dictionary={}
    for item in server_players:
        if typeof(item)==TYPE_DICTIONARY:
            var id:=int(item.get("id",0)); if id>0: next[id]=item
    players=next
    if players.has(self_id):
        var me:Dictionary=players[self_id]; dead=bool(me.get("dead",false)); if move_camera and not dead: $Camera2D.position=Vector2(float(me.get("x",world_size.x*0.5)),float(me.get("y",world_size.y*0.5)))

func _update_self_ui() -> void:
    if players.has(self_id):
        var me:Dictionary=players[self_id]; territory_label.text="Territory  %s"%str(me.get("territory",0)); kills_label.text="⚔ %s"%str(me.get("kills",0))
    if match_status=="playing": status_label.text="LIVE • %02d:%02d"%[int(match_remaining_ms/60000),int((match_remaining_ms%60000)/1000)]

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and event.position.x<get_viewport_rect().size.x*0.55 and joystick_touch_id==-1 and not _ui_open(): joystick_touch_id=event.index;joystick_active=true;joystick_center=event.position;joystick_knob=event.position;_update_joystick(event.position)
        elif not event.pressed and event.index==joystick_touch_id:_release_joystick()
    elif event is InputEventScreenDrag and event.index==joystick_touch_id:_update_joystick(event.position)
    elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        if event.pressed and event.position.x<get_viewport_rect().size.x*0.55 and not _ui_open(): joystick_touch_id=-2;joystick_active=true;joystick_center=event.position;joystick_knob=event.position;_update_joystick(event.position)
        elif not event.pressed and joystick_touch_id==-2:_release_joystick()
    elif event is InputEventMouseMotion and joystick_touch_id==-2 and joystick_active:_update_joystick(event.position)

func _update_joystick(position:Vector2)->void:
    var offset:=position-joystick_center;if offset.length()>joystick_radius:offset=offset.normalized()*joystick_radius;joystick_knob=joystick_center+offset;input_vector=offset/joystick_radius
func _release_joystick()->void: joystick_touch_id=-1;joystick_active=false;joystick_knob=joystick_center;input_vector=Vector2.ZERO
func _ui_open()->bool:return profile_open or leaderboard_open or skins_open or shop_open or settings_open or match_end_open or dead

func _draw()->void:
    draw_rect(Rect2(Vector2.ZERO,world_size),Color("101827"),true)
    for y in range(grid_height):
        for x in range(grid_width):
            var index:=y*grid_width+x
            if index>=territory.size():continue
            var owner:=int(territory[index]);if owner<=0:continue
            draw_rect(Rect2(Vector2(x*cell_size,y*cell_size),Vector2(cell_size+1,cell_size+1)),_player_color(owner,0.48),true)
    for x in range(grid_width+1):draw_line(Vector2(x*cell_size,0),Vector2(x*cell_size,world_size.y),Color(0.14,0.18,0.25,0.42),1)
    for y in range(grid_height+1):draw_line(Vector2(0,y*cell_size),Vector2(world_size.x,y*cell_size),Color(0.14,0.18,0.25,0.42),1)
    for id in players.keys():
        var p:Dictionary=players[id];if bool(p.get("dead",false)):continue
        var pos:=Vector2(float(p.get("x",0)),float(p.get("y",0)));var me:=int(id)==self_id;var pulse=sin(Time.get_ticks_msec()*0.006)*2.0 if me else 0.0
        draw_circle(pos,24+pulse if me else 18,_player_color(int(id),1));draw_circle(pos,8,Color(0.95,0.98,1,1));draw_string(ThemeDB.fallback_font,pos+Vector2(-55,-32),str(p.get("username","Player")),HORIZONTAL_ALIGNMENT_CENTER,110,16,Color(0.9,0.94,1,1))
    if joystick_active and not _ui_open():draw_circle(joystick_center,joystick_radius,Color(0.05,0.08,0.14,0.82));draw_circle(joystick_center,joystick_radius,Color(0.35,0.65,1,0.35),false,4);draw_circle(joystick_knob,34,Color(0.35,0.65,1,0.9))

func _player_color(id:int,alpha:float)->Color:
    var skin_id:=1;if players.has(id):skin_id=int(players[id].get("skin",1));return Color.from_hsv(fmod(float(max(0,skin_id-1))*0.02,0.72,0.95,alpha)

func _on_profile_pressed()->void:
    _close_panels();profile_open=true;profile_panel.visible=true;_load_profile()
func _on_leaderboard_pressed()->void:
    _close_panels();leaderboard_open=true;leaderboard_panel.visible=true;_load_leaderboard()
func _on_skins_pressed()->void:
    _close_panels();skins_open=true;skins_panel.visible=true;_load_shop()
func _on_shop_pressed()->void:
    _close_panels();shop_open=true;_show_shop_panel()
func _on_settings_pressed()->void:
    _close_panels();settings_open=true;_show_settings()
func _close_panels()->void:
    profile_open=false;leaderboard_open=false;skins_open=false;shop_open=false;settings_open=false;match_end_open=false;profile_panel.visible=false;leaderboard_panel.visible=false;skins_panel.visible=false

func _load_profile()->void:
    _http_get("/profile",Callable(self,"_profile_loaded"))
func _profile_loaded(data:Dictionary)->void:
    account=data.get("profile",account);profile_text.text="PROFILE\n\n%s\n\nLevel %s   XP %s\nGold %s   Gems %s\nKills %s   Wins %s\nSkin %02d"%[str(account.get("username","Player")),str(account.get("level",1)),str(account.get("xp",0)),str(account.get("gold",0)),str(account.get("gems",0)),str(account.get("kills",0)),str(account.get("wins",0)),int(account.get("selected_skin",1))]
func _load_leaderboard()->void:_http_get("/leaderboard?sort=gold&limit=500",Callable(self,"_leaderboard_loaded"))
func _leaderboard_loaded(data:Dictionary)->void:
    var text="TOP 500 • GOLD\n\n";for row in data.get("leaderboard",[]):text+="%3d. %-20s  G:%-6s  W:%-3s  L:%-3s\n"%[int(row.get("rank",0)),str(row.get("username","Player")).left(20),str(row.get("gold",0)),str(row.get("wins",0)),str(row.get("level",1))];leaderboard_text.text=text

func _build_button(parent:Control,title:String,pos:Vector2,size:Vector2,callback:Callable)->Button:
    var b:=Button.new();b.text=title;b.position=pos;b.size=size;b.pressed.connect(callback);parent.add_child(b);return b
func _show_shop_panel()->void:
    var panel:=_get_dynamic_panel("SHOP",Vector2(180,95),Vector2(920,570));var scroll:=ScrollContainer.new();scroll.position=Vector2(25,65);scroll.size=Vector2(870,450);panel.add_child(scroll);var grid:=GridContainer.new();grid.columns=4;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(grid)
    _http_get("/shop",func(data):
        for child in grid.get_children():child.queue_free()
        for item in data.get("skins",[]):
            var id:=int(item.get("id",0));var unlocked=id in _unlocked();var b:=Button.new();b.custom_minimum_size=Vector2(205,75);b.text=("✓ " if unlocked else "🔒 ")+"SKIN %02d\nG %s • 💎 %s"%[id,str(item.get("gold_cost",0)),str(item.get("gems_cost",0))];b.pressed.connect(_buy_skin.bind(id));grid.add_child(b)
        for item in data.get("items",[]):
            var b:=Button.new();b.custom_minimum_size=Vector2(205,75);b.text=str(item.get("name","Item"));b.pressed.connect(_buy_currency.bind(str(item.get("id",""))));grid.add_child(b))
func _buy_skin(id:int)->void:_http_post("/shop/buy",{"type":"skin","id":id},func(data):account["unlocked_skins"]=data.get("unlocked_skins",account.get("unlocked_skins",[1]));_toast("Skin unlocked!",true);_show_shop_panel())
func _buy_currency(id:String)->void:_http_post("/shop/buy",{"type":"currency","id":id},func(_data):_toast("Purchase complete",true);_refresh_account();_show_shop_panel())
func _unlocked()->Array:return account.get("unlocked_skins",[1]) if typeof(account.get("unlocked_skins",[1]))==TYPE_ARRAY else [1]

func _show_settings()->void:
    var panel:=_get_dynamic_panel("SETTINGS",Vector2(370,145),Vector2(540,430));_build_button(panel,"Sound: ON" if sound_enabled else "Sound: OFF",Vector2(55,80),Vector2(430,60),func():sound_enabled=!sound_enabled;_show_settings());_build_button(panel,"Music: ON" if music_enabled else "Music: OFF",Vector2(55,155),Vector2(430,60),func():music_enabled=!music_enabled;if music_enabled:music_player.play();music_playback=music_player.get_stream_playback() if not music_enabled:music_player.stop();_show_settings());_build_button(panel,"Effects: ON" if effects_enabled else "Effects: OFF",Vector2(55,230),Vector2(430,60),func():effects_enabled=!effects_enabled;_show_settings());_build_button(panel,"Back to Match",Vector2(55,315),Vector2(430,60),func():_close_panels())
func _get_dynamic_panel(title:String,pos:Vector2,size:Vector2)->Panel:
    var old:=get_node_or_null("DynamicPanel");if old:old.queue_free();var panel:=Panel.new();panel.name="DynamicPanel";panel.position=pos;panel.size=size;$HUD.add_child(panel);var label:=Label.new();label.text=title;label.position=Vector2(25,18);label.add_theme_font_size_override("font_size",26);panel.add_child(label);return panel

func _show_match_end(data:Dictionary)->void:
    var panel:=_get_dynamic_panel("MATCH COMPLETE",Vector2(300,120),Vector2(680,500));var l:=Label.new();l.position=Vector2(35,75);l.size=Vector2(610,220);l.text="Place: %s\n+%s Gold   +%s Gems   +%s XP\n\nTOP PLAYERS\n"%[str(data.get("place",0)),str(data.get("gold_reward",0)),str(data.get("gems_reward",0)),str(data.get("xp_reward",0))];for r in data.get("results",[]):l.text+="#%s  %s  • territory %s • kills %s\n"%[str(r.get("place",0)),str(r.get("username","Player")),str(r.get("territory",0)),str(r.get("kills",0))];panel.add_child(l);_build_button(panel,"PLAY AGAIN",Vector2(35,400),Vector2(290,60),func():_close_panels();socket=WebSocketPeer.new();_connect_game());_build_button(panel,"CLOSE",Vector2(350,400),Vector2(290,60),func():_close_panels())

func _refresh_account()->void:_http_get("/profile",func(data):account=data.get("profile",account))
func _http_get(path:String,callback:Callable)->void:
    var req:=HTTPRequest.new();add_child(req);req.request_completed.connect(func(result,code,_h,body):req.queue_free();if result==HTTPRequest.RESULT_SUCCESS and code==200:var d=JSON.parse_string(body.get_string_from_utf8());if typeof(d)==TYPE_DICTIONARY:callback.call(d));req.request(SERVER_URL+path,PackedStringArray(["Authorization: Bearer %s"%session_token]))
func _http_post(path:String,payload:Dictionary,callback:Callable)->void:
    var req:=HTTPRequest.new();add_child(req);req.request_completed.connect(func(result,code,_h,body):req.queue_free();var d=JSON.parse_string(body.get_string_from_utf8());if result==HTTPRequest.RESULT_SUCCESS and code>=200 and code<300 and typeof(d)==TYPE_DICTIONARY:callback.call(d);else _toast("Request failed",false));req.request(SERVER_URL+path,PackedStringArray(["Content-Type: application/json","Authorization: Bearer %s"%session_token]),HTTPClient.METHOD_POST,JSON.stringify(payload))
func _toast(text:String,success:bool)->void:status_label.text=text;if success:_sound(660,0.08)
func _sound(freq:float,duration:float)->void:
    if not sound_enabled or not effects_enabled:return
    if not sfx_player.playing:sfx_player.play();sfx_playback=sfx_player.get_stream_playback()
    var frames=min(sfx_playback.get_frames_available(),int(22050*duration));for i in frames:var v=sin(TAU*freq*float(i)/22050.0)*0.10;sfx_playback.push_frame(Vector2(v,v))
func _load_local_settings()->void:
    sound_enabled=bool(ProjectSettings.get_setting("conquerx/sound_enabled",true));music_enabled=bool(ProjectSettings.get_setting("conquerx/music_enabled",true));effects_enabled=bool(ProjectSettings.get_setting("conquerx/effects_enabled",true))
