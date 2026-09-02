class_name JuiceConfig
extends Resource

## Presentation-only timing and magnitude values. The simulation never loads
## this resource, so visual tuning cannot change battle outcomes.

@export var deploy_drag_time_scale: float = 0.3
@export var deploy_crouch_frames: int = 6
@export var deploy_dust_frames: int = 10
@export var deploy_ground_particles: int = 8
@export var deploy_ground_speed_px: float = 4.5
@export var deploy_ground_color: Color = Color("d9a35f")
@export var deploy_elevated_frames: int = 18
@export var deploy_elevated_shards: int = 8
@export var deploy_elevated_shard_speed_px: float = 6.0
@export var deploy_elevated_shard_color: Color = Color("b9f7ff")
@export var deploy_elevated_ring_color: Color = Color("65eaff")
@export var deploy_elevated_beam_color: Color = Color(0.45, 0.95, 1.0, 0.5)

@export var skill_flash_frames: int = 24
@export var skill_burst_frames: int = 8
@export var damage_flash_frames: int = 6
@export var damage_flash_white: Color = Color("ffffff")
@export var damage_flash_red: Color = Color("ff3b30")
@export var heal_burst_frames: int = 16
@export var heal_burst_particles: int = 8
@export var heal_burst_size_px: float = 8.0
@export var heal_burst_speed_px: float = 4.0
@export var heal_burst_color: Color = Color("88ffcc")

@export var kill_spark_frames: int = 4
@export var kill_spark_cap: int = 12

@export var leak_vignette_frames: int = 12
@export var leak_shake_amplitude_px: float = 6.0
@export var leak_shake_frames: int = 8
@export var leak_hit_stop_frames: int = 0

@export var wave_banner_frames: int = 45
@export var high_threat_warning_frames: int = 96
@export var high_threat_spawn_pulse_frames: int = 54
@export var high_threat_particle_frames: int = 42
@export var high_threat_particles_per_spawn: int = 4
@export var high_threat_particle_speed_px: float = 3.5
@export var star_burst_stagger_frames: int = 10

@export var trap_sprung_frames: int = 8
@export var tar_shimmer_period_frames: int = 16

@export var tracer_frames: int = 4

# Shake/hit-stop whitelist; boss_hit stays unwired until a boss-attack model.
@export var shake_events: PackedStringArray = ["leak", "boss_hit"]
