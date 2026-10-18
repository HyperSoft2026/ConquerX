extends Control

@onready var play_button: Button = $PlayButton
@onready var leaderboard_button: Button = $LeaderboardButton
@onready var shop_button: Button = $ShopButton
@onready var status_label: Label = $Status

func _ready() -> void:
    play_button.pressed.connect(_on_play_pressed)
    leaderboard_button.pressed.connect(_on_leaderboard_pressed)
    shop_button.pressed.connect(_on_shop_pressed)

func _on_play_pressed() -> void:
    status_label.text = "Gameplay will be connected next."

func _on_leaderboard_pressed() -> void:
    status_label.text = "Top 500 leaderboard is coming next."

func _on_shop_pressed() -> void:
    status_label.text = "Shop is coming soon."
