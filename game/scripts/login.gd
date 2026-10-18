extends Control

@onready var discord_button: Button = $DiscordButton
@onready var guest_button: Button = $GuestButton
@onready var status_label: Label = $Status

func _ready() -> void:
    discord_button.pressed.connect(_on_discord_pressed)
    guest_button.pressed.connect(_on_guest_pressed)

func _on_discord_pressed() -> void:
    status_label.text = "Discord login will be connected to the ConquerX account service."

func _on_guest_pressed() -> void:
    status_label.text = "Guest session started."
    await get_tree().create_timer(0.25).timeout
    get_tree().change_scene_to_file("res://game/scenes/main_menu.tscn")
