class_name ArmedStack
extends Node

signal changed

func set_root(_mode: ArmedMode) -> void: pass
func push(_mode: ArmedMode) -> bool: return false
func pop_top() -> bool: return true
func pop(_mode: ArmedMode) -> bool: return false
func switch_to(_mode: ArmedMode, _anchor: ArmedMode = null) -> bool: return false
func clear_to_root() -> void: pass
func top() -> ArmedMode: return null
func branch() -> Array[ArmedMode]: return []
