extends Node2D
## Original ConquerX menu backdrop. All shapes are drawn procedurally; no third-party artwork.

func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 720), Color("#10b9f2"))
    draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.15, 0.48, 0.10))
    # Soft light blooms
    draw_circle(Vector2(980, 130), 250, Color(0.25, 0.86, 1.0, 0.18))
    draw_circle(Vector2(310, 580), 310, Color(0.10, 0.94, 0.88, 0.15))
    # Floating island silhouettes
    draw_colored_polygon(PackedVector2Array([Vector2(0, 420), Vector2(145, 375), Vector2(250, 410), Vector2(350, 390), Vector2(470, 440), Vector2(410, 505), Vector2(180, 520), Vector2(0, 490)]), Color("#22d5ee"))
    draw_colored_polygon(PackedVector2Array([Vector2(790, 720), Vector2(860, 590), Vector2(1020, 555), Vector2(1140, 600), Vector2(1280, 565), Vector2(1280, 720)]), Color("#0ca9db"))
    draw_colored_polygon(PackedVector2Array([Vector2(0, 650), Vector2(155, 610), Vector2(270, 650), Vector2(420, 620), Vector2(520, 720), Vector2(0, 720)]), Color("#19c7e8"))
    # Distant playful bubbles
    for bubble in [Vector2(690, 110), Vector2(760, 170), Vector2(1140, 340), Vector2(650, 570), Vector2(120, 180), Vector2(1070, 475)]:
        draw_circle(bubble, 13, Color(1, 1, 1, 0.13))
        draw_arc(bubble, 13, 3.8, 5.2, 20, Color(1, 1, 1, 0.22), 2.0)
    # Decorative territory tiles
    for i in range(6):
        var x := 720.0 + i * 58.0
        var y := 470.0 + sin(float(i) * 0.8) * 18.0
        var points := PackedVector2Array([Vector2(x, y-16), Vector2(x+24, y-26), Vector2(x+48, y-12), Vector2(x+46, y+14), Vector2(x+22, y+25), Vector2(x, y+10)])
        draw_colored_polygon(points, Color(0.98, 1.0, 1.0, 0.12))
        draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3]]), Color(1, 1, 1, 0.18), 2.0)
