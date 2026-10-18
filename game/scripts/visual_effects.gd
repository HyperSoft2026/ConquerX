extends Node2D

var parent_game: Node
var particles: Array[Dictionary] = []
var last_kills := 0
var last_dead := false
var victory_time := -1.0
var death_time := -1.0
var kill_time := -1.0
var match_end_seen := false

func _ready() -> void:
    parent_game = get_parent()
    z_index = 20
    set_process(true)

func _process(delta: float) -> void:
    if parent_game == null:
        return
    var account_value = parent_game.get("account")
    var kills := int(account_value.get("kills", 0)) if typeof(account_value) == TYPE_DICTIONARY else 0
    var players: Dictionary = parent_game.get("players")
    var self_id := int(parent_game.get("self_id"))
    if players.has(self_id):
        kills = int(players[self_id].get("kills", kills))
    var dead := bool(parent_game.get("dead"))
    var match_status := str(parent_game.get("match_status"))
    if kills > last_kills:
        kill_time = 0.0
        _burst(_player_pos(), 18)
    if dead and not last_dead:
        death_time = 0.0
        _burst(_player_pos(), 28)
    if match_status == "finished" and not match_end_seen:
        victory_time = 0.0
        match_end_seen = true
        _burst(_player_pos(), 44)
    last_kills = kills
    last_dead = dead
    if kill_time >= 0: kill_time += delta
    if death_time >= 0: death_time += delta
    if victory_time >= 0: victory_time += delta
    for p in particles:
        p.life = float(p.life) - delta
        p.pos = p.pos + p.vel * delta
        p.vel = p.vel * 0.94
    particles = particles.filter(func(p): return float(p.life) > 0.0)
    queue_redraw()

func _player_pos() -> Vector2:
    var players: Dictionary = parent_game.get("players")
    var id := int(parent_game.get("self_id"))
    if players.has(id):
        var p: Dictionary = players[id]
        return Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
    return Vector2(2000,1200)

func _burst(pos:Vector2, amount:int) -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    for i in range(amount):
        var a := TAU * float(i) / float(amount) + rng.randf_range(-0.12,0.12)
        particles.append({"pos":pos,"vel":Vector2(cos(a),sin(a))*rng.randf_range(80,260),"life":rng.randf_range(0.35,0.9),"size":rng.randf_range(3,9)})

func _draw() -> void:
    if parent_game == null: return
    var players: Dictionary = parent_game.get("players")
    var cell_size: float = float(parent_game.get("cell_size"))
    var grid_w: int = int(parent_game.get("grid_width"))
    var grid_h: int = int(parent_game.get("grid_height"))
    var territory: Array = parent_game.get("territory")
    var self_id := int(parent_game.get("self_id"))

    for y in range(grid_h):
        for x in range(grid_w):
            var idx := y * grid_w + x
            if idx >= territory.size() or int(territory[idx]) <= 0: continue
            var owner := int(territory[idx])
            var base := Vector2(x*cell_size, y*cell_size)
            var edge := 1.0 + sin(Time.get_ticks_msec()*0.003 + float(idx))*0.6
            draw_rect(Rect2(base+Vector2(2,2),Vector2(cell_size-4,cell_size-4)),_skin_accent(owner,0.10),false,edge)

    for id in players.keys():
        var p: Dictionary = players[id]
        if bool(p.get("dead",false)): continue
        var pos := Vector2(float(p.get("x",0)),float(p.get("y",0)))
        var skin_id := int(p.get("skin",1))
        _draw_skin(pos, skin_id, 1.0 if int(id)==self_id else 0.84, int(id)==self_id)

    for p in particles:
        var life := float(p.life)
        draw_circle(p.pos, float(p.size)*life, Color(1.0,0.86,0.34,life))

    if kill_time >= 0 and kill_time < 0.65:
        _draw_ring(_player_pos(), 35.0 + kill_time*150.0, 1.0-kill_time/0.65)
        _draw_crosshair(_player_pos(), 1.0-kill_time/0.65)
    if death_time >= 0 and death_time < 0.9:
        _draw_ring(_player_pos(), 30.0 + death_time*180.0, 1.0-death_time/0.9)
        draw_circle(_player_pos(), 38.0, Color(0.08,0.03,0.08,0.30*(1.0-death_time/0.9)))
    if victory_time >= 0 and victory_time < 2.2:
        var alpha := 1.0-victory_time/2.2
        _draw_victory_burst(_player_pos(), alpha)

func _draw_ring(pos:Vector2,radius:float,alpha:float) -> void:
    draw_arc(pos,radius,0,TAU,48,Color(1,0.78,0.25,alpha),5.0)
    draw_arc(pos,radius-8,0,TAU,48,Color(0.45,0.85,1,alpha*0.7),2.0)

func _draw_crosshair(pos:Vector2,alpha:float) -> void:
    for i in range(4):
        var a := i*TAU/4.0
        var d := Vector2(cos(a),sin(a))
        draw_line(pos+d*18,pos+d*46,Color(1,0.32,0.30,alpha),5.0,true)

func _draw_victory_burst(pos:Vector2,alpha:float) -> void:
    for i in range(12):
        var a := i*TAU/12.0 + victory_time*0.8
        var r := 55.0 + victory_time*75.0
        var d := Vector2(cos(a),sin(a))
        draw_line(pos+d*18,pos+d*r,Color(1,0.86,0.35,alpha),4.0,true)
        draw_circle(pos+d*r,5.0,Color(0.45,0.9,1.0,alpha))

func _skin_accent(id:int,alpha:float)->Color:
    var accents=[Color("55d6ff"),Color("a98bff"),Color("ff6b8a"),Color("62e58a"),Color("ffc857"),Color("ff8f5a")]
    return Color(accents[(max(id,1)-1)%accents.size()],alpha)

func _draw_skin(pos:Vector2,id:int,scale:float,mine:bool) -> void:
    var s := 28.0*scale
    var accent := _skin_accent(id,1.0)
    var white := Color("eef7ff")
    draw_circle(pos,s+5.0,Color(0.02,0.05,0.10,0.72))
    match ((id-1)%50)+1:
        1: _shield(pos,s,accent,white)
        2: _diamond(pos,s,accent,white)
        3: _star(pos,s,accent,5)
        4: _hex(pos,s,accent)
        5: _bolt(pos,s,accent,white)
        6: _crystal(pos,s,accent)
        7: _crown(pos,s,accent,white)
        8: _wing(pos,s,accent,1)
        9: _wing(pos,s,accent,-1)
        10: _orb(pos,s,accent,white)
        11: _star(pos,s,accent,6)
        12: _diamond(pos,s,white,accent)
        13: _hex(pos,s,white)
        14: _bolt(pos,s,white,accent)
        15: _crystal(pos,s,white)
        16: _crown(pos,s,white,accent)
        17: _wing(pos,s,white,1)
        18: _wing(pos,s,white,-1)
        19: _orb(pos,s,white,accent)
        20: _star(pos,s,accent,7)
        21: _diamond(pos,s,accent,Color("ff4f72"))
        22: _hex(pos,s,accent)
        23: _bolt(pos,s,accent,Color("ffd166"))
        24: _crystal(pos,s,accent)
        25: _crown(pos,s,accent,Color("7df9ff"))
        26: _wing(pos,s,accent,1)
        27: _wing(pos,s,accent,-1)
        28: _orb(pos,s,accent,Color("ffffff"))
        29: _star(pos,s,Color("ff6b6b"),5)
        30: _diamond(pos,s,Color("63e6be"),white)
        31: _hex(pos,s,Color("74c0fc"))
        32: _bolt(pos,s,Color("ffd43b"),white)
        33: _crystal(pos,s,Color("da77f2"))
        34: _crown(pos,s,Color("ff922b"),white)
        35: _wing(pos,s,Color("20c997"),1)
        36: _wing(pos,s,Color("f783ac"),-1)
        37: _orb(pos,s,Color("4dabf7"),white)
        38: _star(pos,s,Color("ff8787"),8)
        39: _diamond(pos,s,Color("51cf66"),white)
        40: _hex(pos,s,Color("845ef7"))
        41: _bolt(pos,s,Color("fab005"),white)
        42: _crystal(pos,s,Color("15aabf"))
        43: _crown(pos,s,Color("e64980"),white)
        44: _wing(pos,s,Color("12b886"),1)
        45: _wing(pos,s,Color("7950f2"),-1)
        46: _orb(pos,s,Color("ff6b6b"),Color("ffe066"))
        47: _star(pos,s,Color("339af0"),6)
        48: _diamond(pos,s,Color("ae3ec9"),Color("f8f0fc"))
        49: _hex(pos,s,Color("f08c00"))
        50: _crown(pos,s,Color("00b4d8"),Color("caf0f8"))
    if mine:
        var pulse := 1.0 + sin(Time.get_ticks_msec()*0.006)*0.08
        draw_arc(pos,s*1.28*pulse,0,TAU,48,Color(0.5,0.9,1,0.55),2.5)

func _shield(p:Vector2,s:float,c:Color,inner:Color):
    draw_colored_polygon(PackedVector2Array([p+Vector2(-s,-s*0.45),p+Vector2(s,-s*0.45),p+Vector2(s*0.65,s*0.7),p,p+Vector2(-s*0.65,s*0.7)]),c)
    draw_line(p+Vector2(-s*0.5,-s*0.25),p+Vector2(s*0.5,-s*0.25),inner,3)
    draw_line(p+Vector2(0,-s*0.25),p+Vector2(0,s*0.45),inner,3)
func _diamond(p:Vector2,s:float,c:Color,inner:Color):
    draw_colored_polygon(PackedVector2Array([p+Vector2(0,-s),p+Vector2(s*0.72,0),p+Vector2(0,s),p+Vector2(-s*0.72,0)]),c)
    draw_line(p+Vector2(0,-s*0.55),p+Vector2(s*0.4,0),inner,3)
    draw_line(p+Vector2(s*0.4,0),p+Vector2(0,s*0.55),inner,3)
func _star(p:Vector2,s:float,c:Color,points:int):
    var a:=PackedVector2Array()
    for i in range(points*2):
        var r:=s if i%2==0 else s*0.42
        var ang:float=-PI/2.0+float(i)*PI/points
        a.append(p+Vector2(cos(ang),sin(ang))*r)
    draw_colored_polygon(a,c)
func _hex(p:Vector2,s:float,c:Color):
    var a:=PackedVector2Array()
    for i in range(6):
        var ang:=float(i)*TAU/6.0
        a.append(p+Vector2(cos(ang),sin(ang))*s)
    draw_colored_polygon(a,c)
    draw_arc(p,s*0.55,0,TAU,24,Color("f7fbff"),3)
func _bolt(p:Vector2,s:float,c:Color,inner:Color):
    draw_colored_polygon(PackedVector2Array([p+Vector2(-s*0.15,-s),p+Vector2(s*0.55,-s*0.1),p+Vector2(s*0.1,-s*0.1),p+Vector2(s*0.28,s),p+Vector2(-s*0.55,s*0.05),p+Vector2(-s*0.05,s*0.05)]),c)
    draw_line(p+Vector2(-s*0.05,-s*0.55),p+Vector2(s*0.2,s*0.35),inner,3)
func _crystal(p:Vector2,s:float,c:Color):
    draw_colored_polygon(PackedVector2Array([p+Vector2(0,-s),p+Vector2(s*0.62,-s*0.25),p+Vector2(s*0.38,s),p+Vector2(-s*0.38,s),p+Vector2(-s*0.62,-s*0.25)]),c)
    draw_line(p+Vector2(0,-s),p+Vector2(0,s),Color(1,1,1,0.72),3)
func _crown(p:Vector2,s:float,c:Color,inner:Color):
    draw_colored_polygon(PackedVector2Array([p+Vector2(-s,-s*0.25),p+Vector2(-s*0.55,s*0.55),p+Vector2(0,s*0.18),p+Vector2(s*0.55,s*0.55),p+Vector2(s,-s*0.25),p+Vector2(s*0.65,-s*0.05),p+Vector2(-s*0.65,-s*0.05)]),c)
    draw_line(p+Vector2(-s*0.55,s*0.2),p+Vector2(s*0.55,s*0.2),inner,4)
func _wing(p:Vector2,s:float,c:Color,side:int):
    var d:=float(side)
    draw_colored_polygon(PackedVector2Array([p+Vector2(0,-s*0.35),p+Vector2(d*s,-s*0.85),p+Vector2(d*s*0.7,s*0.05),p+Vector2(d*s*0.15,s*0.72),p+Vector2(0,s*0.35)]),c)
    draw_line(p+Vector2(d*s*0.15,-s*0.1),p+Vector2(d*s*0.72,s*0.15),Color(1,1,1,0.65),3)
func _orb(p:Vector2,s:float,c:Color,inner:Color):
    draw_circle(p,s,c)
    draw_arc(p,s*0.72,-PI*0.8,PI*0.2,20,inner,4)
    draw_circle(p+Vector2(-s*0.28,-s*0.28),s*0.15,Color(1,1,1,0.8))
