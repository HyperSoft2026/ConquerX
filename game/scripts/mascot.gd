extends Node2D
## Original friendly ConquerX mascot, drawn with native Godot vector primitives.

var bob_time := 0.0

func _process(delta: float) -> void:
    bob_time += delta
    queue_redraw()

func _draw() -> void:
    var bob := sin(bob_time * 1.7) * 7.0
    # Shadow
    var shadow_points := PackedVector2Array()
    for i in range(24):
        var angle := TAU * float(i) / 24.0
        shadow_points.append(Vector2(cos(angle) * 94.0, 108.0 + sin(angle) * 18.0))
    draw_colored_polygon(shadow_points, Color(0.02, 0.16, 0.38, 0.24))
    # Back fins / ears
    draw_colored_polygon(PackedVector2Array([Vector2(-48, -50+bob), Vector2(-80, -88+bob), Vector2(-73, -25+bob), Vector2(-45, -15+bob)]), Color("#ff9d22"))
    draw_colored_polygon(PackedVector2Array([Vector2(48, -50+bob), Vector2(80, -88+bob), Vector2(73, -25+bob), Vector2(45, -15+bob)]), Color("#ff9d22"))
    # Main rounded body
    draw_colored_polygon(PackedVector2Array([Vector2(-70, -43+bob), Vector2(-54, -72+bob), Vector2(-20, -82+bob), Vector2(26, -78+bob), Vector2(58, -57+bob), Vector2(72, -15+bob), Vector2(66, 43+bob), Vector2(40, 67+bob), Vector2(-42, 67+bob), Vector2(-67, 43+bob), Vector2(-75, 0+bob)]), Color("#ffb91f"))
    draw_polyline(PackedVector2Array([Vector2(-70, -43+bob), Vector2(-54, -72+bob), Vector2(-20, -82+bob), Vector2(26, -78+bob), Vector2(58, -57+bob), Vector2(72, -15+bob), Vector2(66, 43+bob), Vector2(40, 67+bob), Vector2(-42, 67+bob), Vector2(-67, 43+bob), Vector2(-75, 0+bob), Vector2(-70, -43+bob)]), Color("#e77b10"), 4.0, true)
    # Gloss highlight
    draw_circle(Vector2(-40, -48+bob), 13, Color(1, 0.94, 0.63, 0.92))
    draw_circle(Vector2(-24, -55+bob), 6, Color(1, 1, 1, 0.95))
    # Eyes with bright blue irises
    draw_circle(Vector2(-20, 6+bob), 23, Color("#fffdf4"))
    draw_circle(Vector2(29, 5+bob), 23, Color("#fffdf4"))
    draw_circle(Vector2(-16, 10+bob), 13, Color("#15317b"))
    draw_circle(Vector2(33, 9+bob), 13, Color("#15317b"))
    draw_circle(Vector2(-13, 14+bob), 8, Color("#16a9ff"))
    draw_circle(Vector2(36, 13+bob), 8, Color("#16a9ff"))
    draw_circle(Vector2(-20, 2+bob), 5, Color.WHITE)
    draw_circle(Vector2(29, 1+bob), 5, Color.WHITE)
    # Tiny crown to reinforce the conqueror theme
    draw_colored_polygon(PackedVector2Array([Vector2(-35, -73+bob), Vector2(-42, -99+bob), Vector2(-20, -87+bob), Vector2(0, -108+bob), Vector2(18, -87+bob), Vector2(39, -99+bob), Vector2(33, -70+bob)]), Color("#ffdf48"))
    draw_polyline(PackedVector2Array([Vector2(-35, -73+bob), Vector2(-42, -99+bob), Vector2(-20, -87+bob), Vector2(0, -108+bob), Vector2(18, -87+bob), Vector2(39, -99+bob), Vector2(33, -70+bob)]), Color("#d88915"), 3.0, true)
    for gem in [Vector2(-31, -86), Vector2(0, -96), Vector2(29, -86)]:
        draw_circle(gem + Vector2(0, bob), 5, Color("#21e3f4"))
