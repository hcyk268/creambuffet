extends RefCounted

const PROTOCOL_VERSION := 1
const MAX_PACKET_BYTES := 16384

const FIELD_VERSION := "v"
const FIELD_TYPE := "type"
const FIELD_REQUEST_ID := "request_id"
const FIELD_PAYLOAD := "payload"

const REQUEST_PREFIX_ACTION := "act"

const MESSAGE_HELLO := "hello"
const MESSAGE_WELCOME := "welcome"
const MESSAGE_PING := "ping"
const MESSAGE_PONG := "pong"
const MESSAGE_LIST_ROOMS := "list_rooms"
const MESSAGE_ROOM_LIST := "room_list"
const MESSAGE_CREATE_ROOM := "create_room"
const MESSAGE_JOIN_ROOM := "join_room"
const MESSAGE_LEAVE_ROOM := "leave_room"
const MESSAGE_START_MATCH := "start_match"
const MESSAGE_SET_ROOM_MAP := "set_room_map"
const MESSAGE_ROOM_CREATED := "room_created"
const MESSAGE_ROOM_JOINED := "room_joined"
const MESSAGE_ROOM_UPDATED := "room_updated"
const MESSAGE_ROOM_MAP_UPDATED := "room_map_updated"
const MESSAGE_ROOM_LEFT := "room_left"
const MESSAGE_MATCH_STARTED := "match_started"
const MESSAGE_PLAYER_STATE := "player_state"
const MESSAGE_PUSHABLE_CONTROL := "pushable_control"
const MESSAGE_LEVEL_CHANGED := "level_changed"
const MESSAGE_LEVEL_COMPLETE := "level_complete"
const MESSAGE_LEVEL_TRANSITION := "level_transition"
const MESSAGE_WORLD_EVENT := "world_event"
const MESSAGE_WORLD_EVENT_REQUEST := "world_event_request"
const MESSAGE_WORLD_ACTION_REQUEST := "world_action_request"
const MESSAGE_ERROR := "error"
