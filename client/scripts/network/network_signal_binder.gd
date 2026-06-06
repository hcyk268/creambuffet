extends RefCounted
class_name NetworkSignalBinder

## Utility to bind/unbind network signals with less boilerplate.
## Usage:
##   var _binder := NetworkSignalBinder.new()
##   func _ready():
##       _binder.bind(network_client.connection_state_changed, _on_connection_state_changed)
##       _binder.bind(network_client.error_received, _on_network_error)
##   func _exit_tree():
##       _binder.unbind_all()

var _bindings: Array[Dictionary] = []


func bind(source_signal: Signal, method: Callable) -> void:
	if not source_signal.is_connected(method):
		source_signal.connect(method)
	_bindings.append({"signal": source_signal, "method": method})


func unbind_all() -> void:
	for binding in _bindings:
		var sig: Signal = binding["signal"]
		var method: Callable = binding["method"]
		if sig.is_connected(method):
			sig.disconnect(method)
	_bindings.clear()
