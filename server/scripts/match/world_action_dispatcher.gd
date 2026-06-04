extends RefCounted
class_name WorldActionDispatcher

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const MatchStateContext = preload("res://scripts/match/match_state_context.gd")


static func dispatch(match_state, peer_id: int, action: String, target_id: String, payload: Dictionary) -> Dictionary:
	if not match_state.has_player(peer_id):
		return match_state.error("unknown_peer", "Peer is not part of this match.")

	var validation := GameCatalog.validate_world_action(match_state.current_level_id, target_id, action, payload)
	if not bool(validation.get("ok", false)):
		return validation

	var handler_id := String(validation.get("server_handler", ""))
	var handler: Callable = match_state.get_mechanic_handler(handler_id)
	if handler_id.is_empty() or not handler.is_valid():
		return match_state.error("missing_world_action_handler", "No server handler registered for action: %s" % action)

	var context := MatchStateContext.new(match_state)
	var result = handler.call(context, peer_id, target_id, payload)
	if typeof(result) != TYPE_DICTIONARY:
		return match_state.error("bad_world_action_handler", "World action handler did not return a dictionary: %s" % handler_id)

	return result
