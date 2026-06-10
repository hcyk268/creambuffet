extends RefCounted

const ROOM_STATUS_LOBBY := "lobby"
const ROOM_STATUS_PLAYING := "playing"
const ROOM_STATUS_COMPLETE := "complete"

const ROOM_VISIBILITY_PUBLIC := "public"
const ROOM_VISIBILITY_PRIVATE := "private"

const ACTION_COLLECT := "collect"
const ACTION_OPEN := "open"
const ACTION_COLLECT_TORCH := "collect_torch"
const ACTION_COLLECT_BUFF := "collect_buff"
const ACTION_PLAYER_DEATH := "player_death"
const ACTION_BUTTON_STATE := "button_state"
const ACTION_PUSH_BOX_STATE := "push_box_state"
const ACTION_GOAL_ENTER := "goal_enter"
const ACTION_GOAL_EXIT := "goal_exit"
const ACTION_OXYGEN_DEPLETED := "oxygen_depleted"

const EVENT_KEY_COLLECTED := "key_collected"
const EVENT_DOOR_OPENED := "door_opened"
const EVENT_DOOR_KEY_DEPOSITED := "door_key_deposited"
const EVENT_PLAYER_DIED := "player_died"
const EVENT_PLAYER_RESPAWNED := "player_respawned"
const EVENT_GOAL_ENTERED := "goal_entered"
const EVENT_GOAL_EXITED := "goal_exited"
const EVENT_BUTTON_STATE := "button_state"
const EVENT_PUSH_BOX_STATE := "push_box_state"
const EVENT_OXYGEN_COLLECTED := "oxygen_collected"
const EVENT_TEAM_RESPAWN_BUDGET_CHANGED := "team_respawn_budget_changed"
const EVENT_LEVEL_FAILED := "level_failed"
const EVENT_OBJECT_STATE_CHANGED := "object_state_changed"
const EVENT_TORCH_COLLECTED := "torch_collected"
const EVENT_BUFF_COLLECTED := "buff_collected"

const OBJECT_KIND_KEY := "key"
const OBJECT_KIND_DOOR := "door"
const OBJECT_KIND_EXIT_DOOR := "exit_door"
const OBJECT_KIND_GOAL := "goal"
const OBJECT_KIND_BUTTON := "button"
const OBJECT_KIND_PRESSURE_PLATE := "pressure_plate"
const OBJECT_KIND_PUSH_BOX := "push_box"
const OBJECT_KIND_MOVING_PLATFORM := "moving_platform"
const OBJECT_KIND_OXYGEN_TANK := "oxygen_tank"
const OBJECT_KIND_OXYGEN_STATION := "oxygen_station"
const OBJECT_KIND_TEAM_RESPAWN_BUDGET := "team_respawn_budget"
const OBJECT_KIND_WATER_JET_NOZZLE := "water_jet_nozzle"
const OBJECT_KIND_WATER_JET := "water_jet"
const OBJECT_KIND_EXTENDABLE_BARRIER := "extendable_barrier"
const OBJECT_KIND_WATER_BARRIER := "water_barrier"
const OBJECT_KIND_BARRIER := "barrier"
const OBJECT_KIND_HAZARD := "hazard"
const OBJECT_KIND_CHAINSAW := "chainsaw"
const OBJECT_KIND_FALL_RESET := "fall_reset"
const OBJECT_KIND_TORCH := "torch"
const OBJECT_KIND_BUFF := "buff"

const RULESET_KEY_DOOR_V1 := "key_door_v1"
const RULESET_GOAL_ALL_V1 := "goal_all_v1"
const RULESET_HAZARD_RESPAWN_V1 := "hazard_respawn_v1"
const RULESET_PUSH_BOX_V1 := "push_box_v1"
const RULESET_BUTTON_PLATFORM_V1 := "button_platform_v1"
const RULESET_MOVING_PLATFORM_V1 := "moving_platform_v1"
const RULESET_OXYGEN_V1 := "oxygen_v1"
const RULESET_TORCH_BUFF := "torch_buff_v1"

const DOOR_KINDS := [
	OBJECT_KIND_DOOR,
	OBJECT_KIND_EXIT_DOOR,
]
const BUTTON_KINDS := [
	OBJECT_KIND_BUTTON,
	OBJECT_KIND_PRESSURE_PLATE,
]
const OXYGEN_SOURCE_KINDS := [
	OBJECT_KIND_OXYGEN_TANK,
	OBJECT_KIND_OXYGEN_STATION,
]
const WATER_JET_KINDS := [
	OBJECT_KIND_WATER_JET_NOZZLE,
	OBJECT_KIND_WATER_JET,
]
const BARRIER_KINDS := [
	OBJECT_KIND_EXTENDABLE_BARRIER,
	OBJECT_KIND_WATER_BARRIER,
	OBJECT_KIND_BARRIER,
]
const HAZARD_KINDS := [
	OBJECT_KIND_HAZARD,
	OBJECT_KIND_FALL_RESET,
	OBJECT_KIND_CHAINSAW
]
const LIGHT_KINDS := [
	OBJECT_KIND_TORCH,
	OBJECT_KIND_BUFF
]

static func is_door_kind(kind: String) -> bool:
	return DOOR_KINDS.has(kind)


static func is_button_kind(kind: String) -> bool:
	return BUTTON_KINDS.has(kind)


static func is_oxygen_source_kind(kind: String) -> bool:
	return OXYGEN_SOURCE_KINDS.has(kind)


static func is_water_jet_kind(kind: String) -> bool:
	return WATER_JET_KINDS.has(kind)


static func is_barrier_kind(kind: String) -> bool:
	return BARRIER_KINDS.has(kind)


static func is_hazard_kind(kind: String) -> bool:
	return HAZARD_KINDS.has(kind)

static func is_light_kind(kind: String) -> bool:
	return LIGHT_KINDS.has(kind)
