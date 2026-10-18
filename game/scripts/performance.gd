extends Node

## Adaptive rendering profile for Android devices.
## The game remains deterministic; this only changes presentation cost.

enum Tier { LOW, MEDIUM, HIGH }

var tier: Tier = Tier.MEDIUM
var effects_enabled := true
var particles_enabled := true
var shadows_enabled := false
var target_fps := 60

func _ready() -> void:
    _detect_device()
    apply_profile()

func _detect_device() -> void:
    var ram_mb := int(OS.get_static_memory_usage() / 1048576.0)
    var renderer := RenderingServer.get_video_adapter_name().to_lower()
    var low_hint := renderer.contains("mali-4") or renderer.contains("mali-t") or renderer.contains("adreno 3")
    if ram_mb > 0 and ram_mb < 900 or low_hint:
        tier = Tier.LOW
    elif ram_mb >= 1800:
        tier = Tier.HIGH
    else:
        tier = Tier.MEDIUM

func apply_profile() -> void:
    match tier:
        Tier.LOW:
            target_fps = 30
            particles_enabled = false
            effects_enabled = false
            shadows_enabled = false
            Engine.max_fps = 30
        Tier.MEDIUM:
            target_fps = 60
            particles_enabled = true
            effects_enabled = true
            shadows_enabled = false
            Engine.max_fps = 60
        Tier.HIGH:
            target_fps = 60
            particles_enabled = true
            effects_enabled = true
            shadows_enabled = true
            Engine.max_fps = 60

func quality_name() -> String:
    match tier:
        Tier.LOW: return "Low"
        Tier.HIGH: return "High"
        _: return "Balanced"

func set_quality(value: String) -> void:
    match value.to_lower():
        "low": tier = Tier.LOW
        "high": tier = Tier.HIGH
        _: tier = Tier.MEDIUM
    apply_profile()
