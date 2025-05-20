extends Node

func connect_if_not_connected(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		#print('connecting %s -> %s' % [sig, callable])
		sig.connect(callable)
