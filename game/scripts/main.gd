extends Node2D

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"
const LOGIN_TIMEOUT_SECONDS := 600.0
const LOGIN_POLL_SECONDS := 2.0
const GAME_SCENE := preload("res://scenes/game.tscn")

@onready var status_value: Label = $StatusPanel/StatusValue
@onready var continue_button: Button = $ContinueButton
@onready var login_button: Button = $DiscordLoginButton
@onready var account_summary: Label = $AccountSummary

var login_session_id := ""
var login_elapsed := 0.0
var login_poll_timer := 0.0
var logged_in := false
var session_token := ""
var account: Dictionary = {}
var home_panel: Panel
var home_message: Label
var home_overlay: Panel

func _ready() -> void:
    continue_button.pressed.connect(_on_continue_pressed)
    login_button.pressed.connect(_on_discord_login_pressed)
    status_value.text = "Checking server..."
    _check_server()

func _process(delta: float) -> void:
    if login_session_id.is_empty() or logged_in:return
    login_elapsed += delta
    login_poll_timer += delta
    if login_elapsed >= LOGIN_TIMEOUT_SECONDS:
        status_value.text="Login timed out. Please try again."
        login_session_id=""
        login_elapsed=0.0
        login_poll_timer=0.0
        login_button.disabled=false
        return
    if login_poll_timer >= LOGIN_POLL_SECONDS:
        login_poll_timer=0.0
        _poll_login_status()

func _check_server() -> void:
    var request:=HTTPRequest.new();add_child(request);request.request_completed.connect(_health_done.bind(request));request.request(SERVER_URL+"/health")
func _health_done(result:int,code:int,_headers:PackedStringArray,_body:PackedByteArray,request:HTTPRequest)->void:
    request.queue_free();status_value.text="Server online" if result==HTTPRequest.RESULT_SUCCESS and code==200 else "Server unavailable"

func _on_discord_login_pressed() -> void:
    if logged_in or not login_session_id.is_empty():return
    login_session_id=_make_session_id();login_elapsed=0.0;login_poll_timer=0.0;login_button.disabled=true;status_value.text="Opening Discord..."
    var error:=OS.shell_open(SERVER_URL+"/auth/discord/start?session="+login_session_id)
    if error!=OK:
        status_value.text="Could not open Discord.";login_session_id="";login_button.disabled=false
    else:status_value.text="Complete login in Discord, then return to ConquerX."

func _poll_login_status()->void:
    if login_session_id.is_empty():return
    var request:=HTTPRequest.new();add_child(request);request.request_completed.connect(_login_done.bind(request));request.request(SERVER_URL+"/auth/discord/status?session="+login_session_id)
func _login_done(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray,request:HTTPRequest)->void:
    request.queue_free()
    if login_session_id.is_empty() or logged_in or result!=HTTPRequest.RESULT_SUCCESS or code!=200:return
    var parsed=JSON.parse_string(body.get_string_from_utf8());if typeof(parsed)!=TYPE_DICTIONARY:return
    if parsed.get("status","pending")!="completed":return
    session_token=str(parsed.get("session_token",""));account=parsed.get("account",{})
    if session_token.is_empty() or account.is_empty():return
    logged_in=true;login_session_id="";login_button.disabled=true;_show_home()

func _show_home()->void:
    $Title.text="ConquerX"
    $Subtitle.text="WELCOME BACK • %s" % str(account.get("username","Player"))
    $StatusPanel.visible=false;$DiscordLoginButton.visible=false;$ContinueButton.visible=false;$AccountSummary.visible=false;$Version.text="ConquerX • Multiplayer Season 1"
    home_panel=Panel.new();home_panel.position=Vector2(90,205);home_panel.size=Vector2(1100,430);add_child(home_panel)
    var stats:=Label.new();stats.position=Vector2(35,25);stats.text="LEVEL %s     GOLD %s     GEMS %s     WINS %s     KILLS %s"%[str(account.get("level",1)),str(account.get("gold",0)),str(account.get("gems",0)),str(account.get("wins",0)),str(account.get("kills",0))];stats.add_theme_font_size_override("font_size",22);home_panel.add_child(stats)
    _home_button("PLAY ONLINE",Vector2(40,95),Vector2(500,90),Callable(self,"_play_online"))
    _home_button("SHOP",Vector2(560,95),Vector2(240,90),Callable(self,"_home_shop"))
    _home_button("PROFILE",Vector2(820,95),Vector2(240,90),Callable(self,"_home_profile"))
    _home_button("SKINS",Vector2(40,205),Vector2(330,80),Callable(self,"_home_skins"))
    _home_button("SETTINGS",Vector2(385,205),Vector2(330,80),Callable(self,"_home_settings"))
    _home_button("LEADERBOARD",Vector2(730,205),Vector2(330,80),Callable(self,"_home_leaderboard"))
    var note:=Label.new();note.position=Vector2(40,325);note.size=Vector2(1000,60);note.text="🌐 Real multiplayer matchmaking • 20-player rooms • 3-minute matches\n🏆 Win matches to earn Gold, Gems, XP and unlock more skins.";note.add_theme_font_size_override("font_size",18);home_panel.add_child(note)

func _home_button(text:String,pos:Vector2,size:Vector2,callback:Callable)->void:
    var b:=Button.new();b.text=text;b.position=pos;b.size=size;b.add_theme_font_size_override("font_size",22);b.pressed.connect(callback);home_panel.add_child(b)
func _play_online()->void:
    var gameplay=GAME_SCENE.instantiate();gameplay.set_meta("session_token",session_token);gameplay.set_meta("account",account);get_tree().root.add_child(gameplay);queue_free()
func _home_profile()->void:_show_overlay("PROFILE",["%s"%str(account.get("username","Player")),"Level %s • XP %s"%[str(account.get("level",1)),str(account.get("xp",0))],"Gold %s • Gems %s"%[str(account.get("gold",0)),str(account.get("gems",0))],"Wins %s • Kills %s"%[str(account.get("wins",0)),str(account.get("kills",0))]])
func _home_skins()->void:
    _http_get("/shop",func(data):
        var lines:Array=["Owned skins: %s / 50"%str(account.get("unlocked_skins",[1]).size())]
        for s in data.get("skins",[]):lines.append("Skin %02d • %s"%[int(s.get("id",0)),str(s.get("rarity","Common"))])
        _show_overlay("50 SKINS",lines))
func _home_shop()->void:_show_overlay("SHOP",["Gold %s"%str(account.get("gold",0)),"Gems %s"%str(account.get("gems",0)),"Use the in-game Store to buy currency and unlock skins."])
func _home_leaderboard()->void:
    _http_get("/leaderboard?sort=gold&limit=20",func(data):
        var lines:Array=[]
        for row in data.get("leaderboard",[]):lines.append("#%s  %s  • Gold %s • Wins %s"%[str(row.get("rank",0)),str(row.get("username","Player")),str(row.get("gold",0)),str(row.get("wins",0))])
        _show_overlay("LEADERBOARD",lines))
func _home_settings()->void:_show_overlay("SETTINGS",["Sound and music controls are available in-game.","Graphics and animation effects are optimized for 1280×720 landscape."])
func _show_overlay(title:String,lines:Array)->void:
    if home_overlay!=null:home_overlay.queue_free()
    home_overlay=Panel.new();home_overlay.position=Vector2(270,120);home_overlay.size=Vector2(740,500);add_child(home_overlay)
    var t:=Label.new();t.position=Vector2(30,25);t.text=title;t.add_theme_font_size_override("font_size",28);home_overlay.add_child(t)
    var body:=Label.new();body.position=Vector2(30,80);body.size=Vector2(680,330);body.text="\n".join(lines);body.add_theme_font_size_override("font_size",19);home_overlay.add_child(body)
    var close:=Button.new();close.text="CLOSE";close.position=Vector2(30,420);close.size=Vector2(680,55);close.pressed.connect(func():home_overlay.queue_free();home_overlay=null);home_overlay.add_child(close)
func _http_get(path:String,callback:Callable)->void:
    var request:=HTTPRequest.new();add_child(request);request.request_completed.connect(func(result,code,_h,body):request.queue_free();if result==HTTPRequest.RESULT_SUCCESS and code==200:var d=JSON.parse_string(body.get_string_from_utf8());if typeof(d)==TYPE_DICTIONARY:callback.call(d));request.request(SERVER_URL+path,PackedStringArray(["Authorization: Bearer %s"%session_token]))
func _on_continue_pressed()->void:_play_online()
func _make_session_id()->String:
    var rng:=RandomNumberGenerator.new();rng.randomize();return "%08x-%04x-%04x-%04x-%08x%04x"%[rng.randi(),rng.randi()&0xffff,rng.randi()&0xffff,rng.randi()&0xffff,rng.randi(),rng.randi()&0xffff]
