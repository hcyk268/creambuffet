extends Resource
class_name PlayerSodaProfile

@export var movement: PlayerMovementConfig

@export_group("Network")
@export var remote_reconciliation_gain := 14.0
@export var remote_snap_distance := 48.0

@export_group("Oxygen")
@export var max_oxygen := 10.0
@export var oxygen_recovery_rate := 3.0
@export var default_oxygen_drain_rate := 1.0

@export_group("Bubble")
@export var bubble_breath_interval := 0.7
@export var bubble_swim_interval := 0.16
@export var bubble_swim_velocity_threshold := 45.0
@export var bubble_trail_lifetime := 0.75

@export_group("Water Jet")
@export var water_jet_response := 14.0
@export var water_jet_cross_drag := 2.5
@export var water_jet_max_velocity := 760.0
@export var water_jet_upward_lift_ratio := 0.16
@export var water_jet_upward_max_lift_speed := 78.0
@export var water_jet_upward_lift_stop_speed := 45.0
@export var water_jet_upward_side_ratio := 0.72
@export var water_jet_upward_side_min_speed := 180.0
@export var water_jet_upward_side_max_speed := 280.0


func ensure_defaults() -> PlayerSodaProfile:
	if movement == null:
		movement = PlayerMovementConfig.new()
	return self
