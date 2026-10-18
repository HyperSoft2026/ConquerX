extends Control

var world_size := Vector2(4000.0, 2400.0)
var grid_width := 80
var grid_height := 48
var cell_size := 50.0
var territory: Array = []
var players: Dictionary = {}
var self_id := 0

func update_snapshot(world:Vector2, width:int, height:int, cell:float, cells:Array, roster:Dictionary, local_id:int) -> void:
    world_size = world
    grid_width = maxi(1, width)
    grid_height = maxi(1, height)
    cell_size = cell
    territory = cells
    players = roster
    self_id = local_id
    queue_redraw()

func _draw() -> void:
    var bounds := Rect2(Vector2.ZERO, size)
    draw_rect(bounds, Color(0.025, 0.055, 0.12, 0.88), true)
    draw_rect(bounds, Color("#3edbff"), false, 2.0)
    if grid_width <= 0 or grid_height <= 0:
        return
    var tile := Vector2(size.x / float(grid_width), size.y / float(grid_height))
    for y in range(grid_height):
        for x in range(grid_width):
            var index := y * grid_width + x
            if index >= territory.size():
                continue
            var owner := int(territory[index])
            if owner > 0:
                draw_rect(Rect2(Vector2(x, y) * tile, tile + Vector2(0.5, 0.5)), _player_color(owner), true)
    for key in players.keys():
        var p:Dictionary = players[key]
        if bool(p.get("dead", false)):
            continue
        var point := Vector2(float(p.get("x", 0.0)) / world_size.x * size.x, float(p.get("y", 0.0)) / world_size.y * size.y)
        var radius := 4.0 if int(key) == self_id else 2.5
        draw_circle(point, radius + 1.5, Color(0.02, 0.05, 0.12, 0.85))
        draw_circle(point, radius, Color("#ffffff") if int(key) == self_id else _player_color(int(key)))

func _player_color(id:int) -> Color:
    var palette:Array = [Color("#ff5252"), Color("#43a5ff"), Color("#5fe08a"), Color("#ffd447"), Color("#bd7bff"), Color("#ff8a3d")]
    return palette[posmod(maxi(1, id) - 1, palette.size())]
