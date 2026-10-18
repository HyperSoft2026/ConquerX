extends Node

var seen: Dictionary = {}
var pulse_time := 0.0

func _process(delta:float) -> void:
    pulse_time += delta
    _style_tree(get_parent())

func _style_tree(root:Node) -> void:
    for node in root.get_children():
        if node is Button:
            _style_button(node)
        elif node is Panel:
            _style_panel(node)
        elif node is Label:
            node.add_theme_color_override("font_shadow_color", Color(0,0,0,0.35))
            node.add_theme_constant_override("shadow_offset_x", 1)
            node.add_theme_constant_override("shadow_offset_y", 2)
        _style_tree(node)

func _style_panel(panel:Panel) -> void:
    var box := StyleBoxFlat.new()
    box.bg_color = Color("111b2d")
    box.border_color = Color("29415f")
    box.set_border_width_all(1)
    box.corner_radius_top_left=16; box.corner_radius_top_right=16; box.corner_radius_bottom_left=16; box.corner_radius_bottom_right=16
    box.shadow_color = Color(0,0,0,0.28)
    box.shadow_size = 10
    panel.add_theme_stylebox_override("panel", box)

func _style_button(button:Button) -> void:
    if not seen.has(button.get_instance_id()):
        seen[button.get_instance_id()] = true
        button.mouse_entered.connect(_hover_in.bind(button))
        button.mouse_exited.connect(_hover_out.bind(button))
    var normal := StyleBoxFlat.new()
    normal.bg_color=Color("17253a"); normal.border_color=Color("315274"); normal.set_border_width_all(1)
    normal.corner_radius_top_left=12; normal.corner_radius_top_right=12; normal.corner_radius_bottom_left=12; normal.corner_radius_bottom_right=12
    var hover := StyleBoxFlat.new()
    hover.bg_color=Color("203a5b"); hover.border_color=Color("55d6ff"); hover.set_border_width_all(2)
    hover.corner_radius_top_left=12; hover.corner_radius_top_right=12; hover.corner_radius_bottom_left=12; hover.corner_radius_bottom_right=12
    var pressed := StyleBoxFlat.new()
    pressed.bg_color=Color("0f1b2d"); pressed.border_color=Color("a98bff"); pressed.set_border_width_all(2)
    pressed.corner_radius_top_left=12; pressed.corner_radius_top_right=12; pressed.corner_radius_bottom_left=12; pressed.corner_radius_bottom_right=12
    button.add_theme_stylebox_override("normal",normal)
    button.add_theme_stylebox_override("hover",hover)
    button.add_theme_stylebox_override("pressed",pressed)
    button.add_theme_font_size_override("font_size",18)

func _hover_in(button:Button) -> void:
    var tween := create_tween()
    tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(button,"scale",Vector2(1.025,1.025),0.10)

func _hover_out(button:Button) -> void:
    var tween := create_tween()
    tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(button,"scale",Vector2.ONE,0.10)
