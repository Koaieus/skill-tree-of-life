class_name NetworkSession
extends Node
## Stub — replaced by the real session in the next commit.


func is_authority() -> bool:
	return false


func is_host() -> bool:
	return true


func is_client() -> bool:
	return true


func join_or_host() -> bool:
	await get_tree().process_frame
	return false
